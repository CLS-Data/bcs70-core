#!/usr/bin/env python3
"""Build the static JSON that the variable atlas reads.

Run from the repository root:

    python3 web/build_site.py

Standard library only - no dependencies to install, and no R toolchain
needed just to rebuild the site. R stays for the derivation pipeline.

READ-ONLY with respect to bcs70/: this reads metadata CSVs and writes into
web/data/. It never touches anything under bcs70/, and never opens a .tab
file, so no row of study data can reach the site. Everything it emits is
metadata - variable names, labels, value labels, missing-value codes - plus
the derived-variable specs and their R source.
"""

from __future__ import annotations

import csv
import json
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DATA = REPO / "web" / "data"
DICT = DATA / "dict"

# Sweeps in life-course order, not alphabetical. The whole site is indexed by
# age, so "42m" (42 months) belongs between 0y and 5y, not after 38y.
SWEEP_ORDER = [
    "0y", "42m", "5y", "10y", "16y", "21y", "26y",
    "29y", "34y", "38y", "42y", "46y", "51y", "xwave",
]

DICT_SUFFIX = "_ukda_data_dictionary_variables.csv"


def clean(value: str | None) -> str | None:
    """Normalise the several ways this corpus spells 'no value'."""
    if value is None:
        return None
    value = value.strip()
    return None if value in ("", "NA") else value


def write_json(path: Path, payload: object) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    path.write_text(text, encoding="utf-8")
    return len(text.encode("utf-8"))


def detect_repo() -> str:
    try:
        url = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "CLS-Data/bcs70-core"
    if "github.com" not in url:
        return "CLS-Data/bcs70-core"
    slug = url.split("github.com", 1)[1].lstrip(":/")
    return slug.removesuffix(".git")


def main() -> int:
    lookup_path = REPO / "bcs70" / "master_file_info_lookup.csv"
    if not lookup_path.exists():
        print(f"error: {lookup_path} not found - run from the repo root", file=sys.stderr)
        return 1

    with lookup_path.open(newline="", encoding="utf-8") as fh:
        lookup = list(csv.DictReader(fh))

    all_sweeps = {row["sweep"] for row in lookup}
    sweeps = [s for s in SWEEP_ORDER if s in all_sweeps]
    unknown = sorted(all_sweeps - set(SWEEP_ORDER))
    if unknown:
        print(f"warning: sweeps missing from SWEEP_ORDER, appended: {', '.join(unknown)}")
        sweeps += unknown
    sweep_pos = {s: i for i, s in enumerate(sweeps)}

    # -- Files ------------------------------------------------------------
    # One entry per deposited .tab. Keyed by sweep + name, never name alone:
    # bcs70_age16_school_type is deposited under BOTH 16y (study 3535) and
    # 42y (study 7473). A name-only key silently collapses the two and
    # misattributes every 42y variable to the 16y file.
    tabs = [r for r in lookup if r["file_type"] == "tab"]
    tabs.sort(key=lambda r: (sweep_pos.get(r["sweep"], 999), r["file_name"]))

    files = [
        {
            "name": r["file_name"],
            "sweep": r["sweep"],
            "study": r["study_number"],
            "slug": f"{r['sweep']}__{r['file_name']}",
            "description": clean(r.get("description")),
            "inLookup": True,
        }
        for r in tabs
    ]

    # Some deposited .tab files have a full data dictionary but no row in
    # master_file_info_lookup.csv at all, which means load_tab() cannot
    # resolve them and the derivation pipeline cannot use them. They are
    # included here and flagged rather than dropped: someone searching for a
    # variable needs to find it AND be told the pipeline can't reach it yet.
    for path in sorted(REPO.joinpath("bcs70").rglob(f"*{DICT_SUFFIX}")):
        rel = path.relative_to(REPO).parts
        sweep, name = rel[1], path.name.removesuffix(DICT_SUFFIX)
        if any(f["sweep"] == sweep and f["name"] == name for f in files):
            continue
        if not (REPO / "bcs70" / sweep / f"{name}.tab").exists():
            continue
        files.append({
            "name": name,
            "sweep": sweep,
            "study": rel[3] if len(rel) > 3 else None,
            "slug": f"{sweep}__{name}",
            "description": None,
            "inLookup": False,
        })

    files.sort(key=lambda f: (sweep_pos.get(f["sweep"], 999), f["name"]))
    file_index = {(f["sweep"], f["name"]): i for i, f in enumerate(files)}

    # -- Dictionaries -----------------------------------------------------
    # One JSON per file with every variable's label, type, missing codes and
    # value labels. Fetched lazily by the site, so page weight stays small.
    if DICT.exists():
        shutil.rmtree(DICT)
    DICT.mkdir(parents=True)

    # Compact search index: each variable is a positional array, not an
    # object. At ~32k variables, repeated key names would dominate the
    # payload.  [name, label, fileIndex, sweepIndex]
    index: list[list] = []
    built_slugs: list[str] = []
    orphans: list[str] = []

    for path in sorted(REPO.joinpath("bcs70").rglob(f"*{DICT_SUFFIX}")):
        rel = path.relative_to(REPO).parts
        sweep = rel[1]
        name = path.name.removesuffix(DICT_SUFFIX)

        idx = file_index.get((sweep, name))
        if idx is None:
            orphans.append(f"{sweep}/{name}")  # dictionary with no .tab on disk
            continue

        with path.open(newline="", encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        if not rows:
            continue

        variables = []
        for r in rows:
            raw = clean(r.get("value_labels_json"))
            values = None
            if raw:
                try:
                    values = json.loads(raw)
                except json.JSONDecodeError:
                    values = None
            variables.append({
                "variable": r["variable"],
                "label": clean(r.get("variable_label")),
                "pos": clean(r.get("pos")),
                "type": clean(r.get("variable_type")),
                "measurement": clean(r.get("measurement_level")),
                "missing": clean(r.get("spss_user_missing_values")),
                "values": values,
            })
            index.append([r["variable"], clean(r.get("variable_label")) or "", idx, sweep_pos[sweep]])

        # The slug carries the sweep for the same collision reason - without
        # it the second dictionary overwrites the first on disk.
        slug = f"{sweep}__{name}"
        write_json(DICT / f"{slug}.json",
                   {"file": name, "sweep": sweep, "slug": slug, "variables": variables})
        built_slugs.append(slug)

    index_bytes = write_json(DATA / "variables.json", index)

    # -- Derived variables ------------------------------------------------
    # The registry, plus each script's actual R source, so the site can show
    # how a variable was made without fetching anything from GitHub.
    derived = []
    registry = REPO / "registry" / "variables.json"
    if registry.exists():
        reg = json.loads(registry.read_text(encoding="utf-8"))
        for category, entries in reg.get("categories", {}).items():
            for entry in entries:
                script = REPO / entry["file"] if entry.get("file") else None
                entry["source"] = (
                    script.read_text(encoding="utf-8")
                    if script and script.exists() else None
                )
                entry.setdefault("family", None)
                entry.setdefault("category", category)
                derived.append(entry)
    derived.sort(key=lambda e: (e.get("category") or "", e.get("family") or "", e["id"]))
    write_json(DATA / "derived.json", derived)

    # -- Manifest ---------------------------------------------------------
    write_json(DATA / "manifest.json", {
        "repo": detect_repo(),
        "built": date.today().isoformat(),
        "sweeps": sweeps,
        "files": files,
        "filesWithDict": built_slugs,
        "unlisted": [f["slug"] for f in files if not f["inLookup"]],
        "counts": {
            "variables": len(index),
            "files": len(files),
            "dictionaries": len(built_slugs),
            "sweeps": len(sweeps),
            "derived": len(derived),
        },
    })

    unlisted = [f["slug"] for f in files if not f["inLookup"]]
    if unlisted:
        print(f"note: {len(unlisted)} file(s) have a dictionary and a .tab on disk "
              f"but no master_file_info_lookup.csv row, so load_tab() cannot reach "
              f"them. Included and flagged: {', '.join(unlisted)}")
    if orphans:
        print(f"note: {len(orphans)} dictionary/ies have no .tab on disk, skipped.")
    print(f"Built {len(index):,} variables across {len(files)} files "
          f"({len(built_slugs)} dictionaries), {len(derived)} derived. "
          f"Index {index_bytes / 1_048_576:.1f} MB.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
