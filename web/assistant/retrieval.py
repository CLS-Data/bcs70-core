"""BM25 over the variable descriptions.

Built once at start-up over the whole corpus — about 0.15 s for 32,000
variables — and answered in well under a millisecond thereafter.

Tuning (`k1`, `b`, the pool size, the stoplist, the exact-name lift) lives in
`dataset.toml`, because the right values depend on what the labels look like.
"""

from __future__ import annotations

import math
import re
from collections import defaultdict

from config import Config

TOKEN = re.compile(r"[a-z0-9]+")


def _stem(token: str) -> str:
    """One rule, applied identically at index and query time.

    Nothing more aggressive: stemming "housing" to "hous" would collapse it
    into "house" and "household", which are different concepts here.
    """
    if len(token) > 3 and token.endswith("s") and not token.endswith(("ss", "us")):
        return token[:-1]
    return token


class Bm25:
    def __init__(self, corpus, cfg: Config):
        self.corpus = corpus
        self.cfg = cfg
        self.postings: dict[str, list[tuple[int, int]]] = {}
        self.doc_len: list[int] = []
        self.by_name: dict[str, list[int]] = defaultdict(list)
        self._build()

    def tokenize(self, text: str) -> list[str]:
        out = []
        for match in TOKEN.finditer((text or "").lower()):
            token = match.group(0)
            if token in self.cfg.stopwords:
                continue
            if len(token) < 2 and not token.isdigit():
                continue
            out.append(_stem(token))
        return out

    def _build(self) -> None:
        acc: dict[str, dict[int, int]] = defaultdict(lambda: defaultdict(int))
        doc_len = []
        for doc, row in enumerate(self.corpus.vars):
            name, label = row[0], row[1]
            key = str(name).lower()
            self.by_name[key].append(doc)

            # The name is indexed whole as well as split, so `c6.8` survives
            # as a searchable term instead of only ever becoming "c6" and "8".
            tokens = self.tokenize(label)
            tokens.append(key)
            tokens.extend(self.tokenize(name))
            doc_len.append(len(tokens))
            for token in tokens:
                acc[token][doc] += 1

        self.doc_len = doc_len
        self.n = len(doc_len)
        self.avg_len = (sum(doc_len) / self.n) if self.n else 1.0
        self.postings = {t: list(m.items()) for t, m in acc.items()}

    def _idf(self, token: str) -> float:
        df = len(self.postings.get(token, ()))
        if not df:
            return 0.0
        return math.log(1 + (self.n - df + 0.5) / (df + 0.5))

    def search(self, query: str, limit: int, wave_idx: int = -1) -> list[int]:
        terms = self.tokenize(query)
        if not terms:
            return []

        k1, b = self.cfg.k1, self.cfg.b
        in_scope = (
            (lambda d: True) if wave_idx < 0
            else (lambda d: self.corpus.vars[d][3] == wave_idx)
        )

        scores: dict[int, float] = defaultdict(float)
        for term in set(terms):
            postings = self.postings.get(term)
            if not postings:
                continue
            idf = self._idf(term)
            for doc, tf in postings:
                if not in_scope(doc):
                    continue
                norm = 1 - b + b * (self.doc_len[doc] / self.avg_len)
                scores[doc] += idf * (tf * (k1 + 1)) / (tf + k1 * norm)

        # A query that *is* a variable name should return that variable
        # first. The lift has to be earned twice over, though: some variables
        # are named after ordinary English words — there is one called `day`
        # and one called `height` — so a flat bonus puts "DAY NUMBER" at the
        # top of a search for cigarettes per day. Scaling by idf makes a rare
        # code decisive and a common word nearly free, and dividing by how
        # many variables share the name stops one word lifting a crowd.
        for word in (query or "").lower().split():
            bucket = self.by_name.get(word)
            if not bucket:
                continue
            lift = (self._idf(word) * self.cfg.name_lift) / math.sqrt(len(bucket))
            for doc in bucket:
                if in_scope(doc):
                    scores[doc] += lift

        ranked = sorted(scores.items(), key=lambda kv: -kv[1])
        return [doc for doc, _ in ranked[:limit]]


def group(corpus, docs: list[int], limit: int) -> list[dict]:
    """Collapse hits that share a description.

    One question asked at six waves is one fact about the corpus, and
    spending six of the model's ten candidate slots restating it is the
    difference between a useful context block and a useless one. The wave
    list is the interesting part, and it is what the request needs to say
    anyway.
    """
    order: list[str] = []
    groups: dict[str, dict] = {}

    for doc in docs:
        name, label = corpus.vars[doc][0], corpus.vars[doc][1]
        key = (label or f" {name}").lower()
        entry = groups.get(key)
        if entry is None:
            groups[key] = entry = {
                "label": label or None, "names": [], "waves": [],
                "files": [], "rows": [], "wave_of": {},
            }
            order.append(key)
        if name not in entry["names"]:
            entry["names"].append(name)
        wave = corpus.wave_of(doc)
        # Which wave each name came from. The `waves` list is deduped
        # separately, so its order says nothing about any one name — and the
        # transcript makes every name clickable through to the atlas, which
        # needs the right one.
        entry["wave_of"].setdefault(name, wave)
        if wave not in entry["waves"]:
            entry["waves"].append(wave)
        file_name = corpus.file_of(doc).get("name")
        if file_name and file_name not in entry["files"]:
            entry["files"].append(file_name)
        entry["rows"].append(doc)

    position = {w: i for i, w in enumerate(corpus.waves)}
    out = []
    for key in order[:limit]:
        entry = groups[key]
        entry["waves"].sort(key=lambda w: position.get(w, 999))
        out.append(entry)
    return out


def search_grouped(corpus, bm25: Bm25, query: str, *, limit: int,
                   wave: str | None = None) -> dict:
    """The one entry point. Returns groups, or names an unknown wave."""
    wave_idx = -1
    if wave:
        if wave not in corpus.waves:
            return {"groups": [], "unknown_wave": wave}
        wave_idx = corpus.waves.index(wave)
    docs = bm25.search(query, bm25.cfg.pool, wave_idx)
    return {"groups": group(corpus, docs, limit), "unknown_wave": None}
