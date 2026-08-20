#!/usr/bin/env python3
"""Build the semantic index the assistant searches alongside BM25.

    python3 web/build_embeddings.py            # build it
    python3 web/build_embeddings.py --check    # is the existing one current?

Reads `web/data/variables.json`, embeds each variable's label with a local
embedding model through Ollama, and writes `vectors.bin` (float32, unit
length, one row per variable) beside it with `vectors.json` describing what
was built.

Separate from `build_site.py` on purpose. That script is standard library with
no services behind it, runs in CI on every publish, and must keep working on a
machine that has never heard of Ollama. This one needs a model loaded and
takes minutes, so it is a deliberate local step and its output is optional:
without it the assistant searches lexically and says so.

**No study data is embedded or sent anywhere.** The input is the variable
labels from the published dictionaries — the same metadata the atlas already
serves publicly — and the model is local, so nothing leaves the machine.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from assistant import ollama, vectors  # noqa: E402
from assistant.corpus import Corpus, CorpusMissing  # noqa: E402
from config import get as get_config  # noqa: E402

DATA = Path(__file__).resolve().parent / "data"


def text_for(row: list) -> str:
    """What actually gets embedded.

    The label, falling back to the name. The name is not appended to the
    label: codes like `b960633` carry no meaning an embedding model can use,
    and adding them to every document only blurs the space.
    """
    return str(row[1] or row[0]).strip() or str(row[0])


def build(cfg, corpus, batch_size: int, base: str) -> int:
    texts = [text_for(row) for row in corpus.vars]
    model = cfg.embed_model
    total = len(texts)
    print(f"Embedding {total:,} labels with {model} …")

    out = DATA / vectors.INDEX
    started = time.perf_counter()
    dim = None

    with out.open("wb") as handle:
        for start in range(0, total, batch_size):
            batch = texts[start:start + batch_size]
            try:
                got = ollama.embed(batch, model, base, timeout=cfg.embed_timeout)
            except ollama.OllamaError as err:
                # Leave no half-written index behind: a truncated file would
                # load, line up for its first rows, and be wrong after that.
                handle.close()
                out.unlink(missing_ok=True)
                print(f"error: {err}", file=sys.stderr)
                if getattr(err, "status", None) == 404:
                    print(f"hint: is {model} pulled? `ollama pull {model}`",
                          file=sys.stderr)
                return 1

            for vector in got:
                vector = vectors.prepare(vector, cfg.embed_dims)
                if dim is None:
                    dim = len(vector)
                elif len(vector) != dim:
                    handle.close()
                    out.unlink(missing_ok=True)
                    print(f"error: {model} returned {len(vector)} dimensions "
                          f"after {dim}", file=sys.stderr)
                    return 1
                handle.write(struct.pack(f"<{dim}f", *vector))

            done = min(start + batch_size, total)
            elapsed = time.perf_counter() - started
            rate = done / elapsed if elapsed else 0
            left = (total - done) / rate if rate else 0
            print(f"\r  {done:,}/{total:,}  {rate:,.0f}/s  ~{left/60:.1f} min left",
                  end="", flush=True)

    print()
    (DATA / vectors.META).write_text(json.dumps({
        "model": model,
        "dim": dim,
        "count": total,
        "fingerprint": vectors.fingerprint(corpus),
        "built": time.strftime("%Y-%m-%d"),
    }, indent=2) + "\n", "utf-8")

    size = out.stat().st_size / 1e6
    print(f"Wrote {total:,} × {dim} to data/{vectors.INDEX} "
          f"({size:.0f} MB) in {(time.perf_counter()-started)/60:.1f} min.")
    return 0


def check(cfg, corpus) -> int:
    index = vectors.load(DATA, corpus, cfg)
    if index is None:
        print(getattr(corpus, "vectors_unavailable", "No index."), file=sys.stderr)
        return 1
    print(f"Current: {index.count:,} × {index.dim} from {index.model}, "
          f"built {index.meta.get('built')}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="report whether the existing index matches the corpus")
    parser.add_argument("--batch", type=int, default=256,
                        help="labels per request (default 256)")
    parser.add_argument("--ollama", default=None, help="base URL")
    args = parser.parse_args()

    cfg = get_config()
    try:
        corpus = Corpus()
    except CorpusMissing as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    if args.check:
        return check(cfg, corpus)
    return build(cfg, corpus, args.batch, args.ollama or cfg.ollama)


if __name__ == "__main__":
    raise SystemExit(main())
