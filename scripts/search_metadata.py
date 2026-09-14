#!/usr/bin/env python3
"""Search every wave's metadata for keyword matches.

    python3 scripts/search_metadata.py "keyword one" "keyword two" ...

Three independent sources, all worth reading: the master lookup (which files
exist at all), every data dictionary (the actual candidate variables), and the
file_information tables (the PDFs and user guides worth opening before trusting
a coding scheme). A variable that matters is often in a wave the request never
mentioned, which is why this searches all of them rather than a named few.

Read-only. It opens metadata CSVs and nothing else -- never a data file, so no
row of study data passes through it.

Standard library, like everything else under `web/`. It reads the same CSVs
`web/build_site.py` does, through the same config, so there is one description
of where the deposits are and what their columns are called.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "web"))

from config import Config, ConfigError, get as get_config  # noqa: E402


def matches(text: str | None, keywords: list[str]) -> bool:
    low = (text or "").lower()
    return any(k in low for k in keywords)


def read_csv(path: Path) -> list[dict]:
    """A row per record, or nothing. One unreadable file must not end a search
    that has 84 others to get through."""
    try:
        with path.open(newline="", encoding="utf-8", errors="replace") as fh:
            return list(csv.DictReader(fh))
    except OSError:
        return []


def show(rows: list[dict], columns: list[str], indent: str = "  ") -> None:
    """Print the named columns, padded to line up. Anything missing from a row
    prints empty rather than raising: deposits vary, and a column this script
    did not expect is not a reason to stop."""
    widths = [max(len(c), *(len(str(r.get(c) or "")) for r in rows)) for c in columns]
    print(indent + "  ".join(c.ljust(w) for c, w in zip(columns, widths)))
    for row in rows:
        print(indent + "  ".join(str(row.get(c) or "").ljust(w)
                                 for c, w in zip(columns, widths)))


def search_lookup(cfg: Config, keywords: list[str]) -> int:
    col = cfg.lookup_columns
    rows = read_csv(cfg.root / cfg.lookup_csv)
    hits = [r for r in rows
            if matches(r.get(col["description"]), keywords)
            or matches(r.get(col["file_name"]), keywords)]

    print(f"== {cfg.lookup_csv} matches ==")
    if not hits:
        print("(none)\n")
        return 0
    show(hits, [col["study"], col["wave"], col["file_name"],
                col["description"], col["file_type"]])
    print()
    return len(hits)


def search_dictionaries(cfg: Config, keywords: list[str]) -> int:
    col = cfg.columns
    paths = sorted(cfg.root.rglob(f"*{cfg.dictionary_suffix}"))
    print(f"== data dictionary matches ({len(paths)} dictionaries scanned) ==")

    total = 0
    for path in paths:
        rows = read_csv(path)
        # value_labels_json is searched too: a concept is often named only in a
        # category label, never in the variable's own label.
        hits = [r for r in rows
                if matches(r.get(col["label"]), keywords)
                or matches(r.get(col["variable"]), keywords)
                or matches(r.get(col["value_labels"]), keywords)]
        if not hits:
            continue
        total += len(hits)
        parts = path.relative_to(cfg.root).parts
        name = path.name.removesuffix(cfg.dictionary_suffix)
        print(f"-- {cfg.wave_term} {parts[0]} / file {name} --")
        show(hits, [col["variable"], col["label"]])

    if not total:
        print("(none)")
    print()
    return total


def search_file_information(cfg: Config, keywords: list[str]) -> int:
    if not cfg.file_information_suffix:
        return 0
    paths = sorted(cfg.root.rglob(f"*{cfg.file_information_suffix}"))
    print(f"== file_information matches ({len(paths)} tables scanned) ==")

    total = 0
    for path in paths:
        rows = read_csv(path)
        hits = [r for r in rows if any(matches(v, keywords) for v in r.values())]
        if not hits:
            continue
        total += len(hits)
        print(f"-- {path.relative_to(cfg.root)} --")
        show(hits, list(hits[0].keys()))

    if not total:
        print("(none)")
    print()
    return total


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Search every wave's metadata for keyword matches.")
    parser.add_argument("keyword", nargs="+", help="one or more keywords")
    args = parser.parse_args()

    try:
        cfg = get_config()
    except ConfigError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    if not (cfg.root / cfg.lookup_csv).exists():
        print(f"error: no {cfg.lookup_csv} under {cfg.root}. Is the deposits "
              f"directory mounted?", file=sys.stderr)
        return 1

    keywords = [k.lower() for k in args.keyword]
    print(f"Searching {cfg.root.name}/ metadata for: {', '.join(args.keyword)}\n")

    found = (search_lookup(cfg, keywords)
             + search_dictionaries(cfg, keywords)
             + search_file_information(cfg, keywords))

    # Nothing found is a real answer -- some waves genuinely lack a concept,
    # and DATA_KNOWLEDGE.md records which. It is also what a too-narrow keyword
    # looks like, so say both rather than let it read as failure.
    if not found:
        print("No matches. Try broader or more literal keyword variants before "
              "concluding the concept is absent; check DATA_KNOWLEDGE.md for "
              "waves known not to carry it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
