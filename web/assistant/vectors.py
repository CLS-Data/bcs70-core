"""Semantic search over the variable labels, in the standard library.

BM25 matches words. The dictionaries are written in questionnaire English and
researchers ask in concept English, so the words often do not meet: "How is
your health generally" does not contain the term "general", and no amount of
lexical tuning will connect it to "self-rated health". Embeddings do.

There is no numpy here and none is wanted. The vectors live in an
`array('f')`, and a dot product over a slice of one is C-backed, so a full
scan of 32,454 variables costs about 0.15 s at 256 dimensions — well inside
the budget of a tool call, and worth far more than the dependency would be.

The index is optional. It is built locally by `web/build_embeddings.py`
against a local embedding model, and CI has neither, so everything here
degrades to "not available" rather than failing: without it the assistant
searches lexically, exactly as it did before, and says so.

## Why the fingerprint matters

Vectors are stored positionally - row 8,000 of the index is row 8,000 of
`variables.json`. Rebuild the site with one more variable in the middle and
every vector after it now describes a different variable, and nothing about
the result looks wrong: the scores are plausible and the names are real. So
the index carries a fingerprint of the corpus it was built from, and a
mismatch disables it. Refusing to search is a recoverable failure; silently
searching the wrong corpus is not.
"""

from __future__ import annotations

import array
import hashlib
import json
import math
import operator
from pathlib import Path

from . import ollama

INDEX = "vectors.bin"
META = "vectors.json"


def fingerprint(corpus) -> str:
    """Identifies the exact corpus an index was built from.

    Names and their order, not the labels: a corrected label leaves every
    vector still describing the right variable, only slightly stale, while an
    inserted or removed row shifts everything after it.
    """
    digest = hashlib.sha256()
    for row in corpus.vars:
        digest.update(str(row[0]).encode("utf-8"))
        digest.update(b"\0")
    return f"{len(corpus.vars)}-{digest.hexdigest()[:16]}"


def prepare(vector: list[float], dims: int = 0) -> list[float]:
    """Truncate, then unit-normalise so cosine is a plain dot product.

    Truncation before normalisation, not after: a shortened vector is not a
    unit vector any more, and comparing it against fully-normalised ones
    would rank by how much of a vector's mass happened to sit in the leading
    dimensions. Applied identically here and at query time - the two paths
    call this same function for that reason.
    """
    if dims and 0 < dims < len(vector):
        vector = vector[:dims]
    scale = math.sqrt(sum(v * v for v in vector)) or 1.0
    return [v / scale for v in vector]


class Unavailable(RuntimeError):
    """No usable index. Carries the reason, which is shown to the user."""


class Vectors:
    """A loaded index, and the query path over it."""

    def __init__(self, data_dir: Path, corpus, cfg):
        self.cfg = cfg
        meta_path = Path(data_dir) / META
        index_path = Path(data_dir) / INDEX

        if not meta_path.exists() or not index_path.exists():
            raise Unavailable(
                "No semantic index. Build one with "
                "`python3 web/build_embeddings.py` (needs Ollama running)."
            )

        self.meta = json.loads(meta_path.read_text("utf-8"))
        self.dim = int(self.meta.get("dim") or 0)
        self.model = self.meta.get("model") or ""
        expected = fingerprint(corpus)
        if self.meta.get("fingerprint") != expected:
            raise Unavailable(
                "The semantic index was built from a different set of "
                "variables and its rows no longer line up. Rebuild it with "
                "`python3 web/build_embeddings.py`."
            )

        raw = index_path.read_bytes()
        self.data = array.array("f")
        self.data.frombytes(raw)
        if len(raw) // 4 != self.dim * len(corpus.vars):
            raise Unavailable(
                "The semantic index is the wrong size for its own metadata. "
                "Rebuild it with `python3 web/build_embeddings.py`."
            )
        self.count = len(corpus.vars)

    def embed_query(self, text: str, base: str | None = None) -> array.array:
        raw = ollama.embed([text], self.model, base,
                           timeout=self.cfg.embed_timeout)[0]
        if len(raw) < self.dim:
            raise Unavailable(
                f"{self.model} returned {len(raw)} dimensions but the index "
                f"holds {self.dim}. Rebuild it, or point at the model it was "
                f"built with."
            )
        # Truncated to the index's own width, not the current setting: an
        # index built at 256 must keep being queried at 256 however the
        # config has changed since.
        return array.array("f", prepare(raw, self.dim))

    def search(self, text: str, limit: int, base: str | None = None) -> list[tuple[int, float]]:
        """(row, similarity) for the closest variables, best first."""
        query = self.embed_query(text, base)
        dim, data = self.dim, self.data
        mul, total = operator.mul, sum

        scored = []
        for row in range(self.count):
            start = row * dim
            scored.append((total(map(mul, data[start:start + dim], query)), row))

        scored.sort(reverse=True)
        return [(row, score) for score, row in scored[:limit]]


def load(data_dir: Path, corpus, cfg) -> Vectors | None:
    """The index, or None with the reason recorded on the corpus.

    Callers treat semantic search as an enhancement, so a missing index must
    not be an exception they all have to catch.
    """
    try:
        return Vectors(data_dir, corpus, cfg)
    except Unavailable as err:
        corpus.vectors_unavailable = str(err)
        return None
    except (OSError, ValueError, json.JSONDecodeError) as err:
        corpus.vectors_unavailable = f"Semantic index could not be read: {err}"
        return None
