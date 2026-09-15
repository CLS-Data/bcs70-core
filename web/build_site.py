#!/usr/bin/env python3
"""Build the static JSON that the variable atlas reads.

    python3 web/build_site.py

Standard library only — no dependencies to install, and no R toolchain needed
just to rebuild the site. R stays for the derivation pipeline.

Everything dataset-specific comes from `dataset.toml`: which directory the
deposits are in, how the metadata CSVs are named, the wave order, the
categories. Point that file at another study and this script needs no edit.

READ-ONLY with respect to the deposits: this reads metadata CSVs and writes
into `web/data/`. It never opens a data file, so no row of study data can
reach the site. Everything it emits is metadata — variable names, labels,
value labels, missing-value codes — plus the derived-variable specs and their
R source.
"""

from __future__ import annotations

import csv
import json
import shutil
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import REPO, Config, ConfigError, get as get_config  # noqa: E402

DATA = Path(__file__).resolve().parent / "data"
DICT = DATA / "dict"


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


def read_lookup(cfg: Config) -> list[dict]:
    path = cfg.root / cfg.lookup_csv
    if not path.exists():
        raise ConfigError(f"{path} not found — check [dataset].root and [metadata].lookup")
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def order_waves(cfg: Config, lookup: list[dict]) -> list[str]:
    """Configured order first, then anything the deposits invented."""
    col = cfg.lookup_columns
    present = {row[col["wave"]] for row in lookup}
    waves = [w for w in cfg.waves if w in present]
    unknown = sorted(present - set(cfg.waves))
    if unknown:
        print(f"warning: {cfg.wave_plural} missing from [wave].order, appended: "
              f"{', '.join(unknown)}")
        waves += unknown
    return waves


def collect_files(cfg: Config, lookup: list[dict], position: dict[str, int]) -> list[dict]:
    """One entry per deposited data file.

    Keyed by wave + name, never name alone: at least one file name is
    deposited under two different waves, and a name-only key silently
    collapses the two and misattributes every variable in the second.
    """
    col = cfg.lookup_columns
    tabs = [r for r in lookup if r[col["file_type"]] == "tab"]
    files = [
        {
            "name": r[col["file_name"]],
            "wave": r[col["wave"]],
            "study": r[col["study"]],
            "slug": f'{r[col["wave"]]}__{r[col["file_name"]]}',
            "description": clean(r.get(col["description"])),
            "inLookup": True,
        }
        for r in tabs
    ]

    # Some deposited files have a full data dictionary but no row in the
    # master lookup at all, which means the pipeline cannot resolve them.
    # They are included and flagged rather than dropped: someone searching
    # for a variable needs to find it AND be told it cannot be used yet.
    known = {(f["wave"], f["name"]) for f in files}
    for path in sorted(cfg.root.rglob(f"*{cfg.dictionary_suffix}")):
        parts = path.relative_to(cfg.root).parts
        wave, name = parts[0], path.name.removesuffix(cfg.dictionary_suffix)
        if (wave, name) in known:
            continue
        if not (cfg.root / wave / f"{name}.tab").exists():
            continue
        files.append({
            "name": name,
            "wave": wave,
            "study": parts[2] if len(parts) > 2 else None,
            "slug": f"{wave}__{name}",
            "description": None,
            "inLookup": False,
        })

    files.sort(key=lambda f: (position.get(f["wave"], 999), f["name"]))
    return files


def build_dictionaries(cfg: Config, files: list[dict], position: dict[str, int]):
    """Write one JSON per file, and the compact cross-corpus search index.

    Each variable in the index is a positional array, not an object: at tens
    of thousands of variables, repeated key names would dominate the payload.

        [name, label, fileIndex, waveIndex, levelIndex]

    `levelIndex` points into `levels`, or -1 where none is recorded.
    """
    if DICT.exists():
        shutil.rmtree(DICT)
    DICT.mkdir(parents=True)

    col = cfg.columns
    index: list[list] = []
    built: list[str] = []
    orphans: list[str] = []
    levels = list(cfg.measurement_levels)
    file_index = {(f["wave"], f["name"]): i for i, f in enumerate(files)}

    for path in sorted(cfg.root.rglob(f"*{cfg.dictionary_suffix}")):
        parts = path.relative_to(cfg.root).parts
        wave = parts[0]
        name = path.name.removesuffix(cfg.dictionary_suffix)

        idx = file_index.get((wave, name))
        if idx is None:
            orphans.append(f"{wave}/{name}")   # dictionary with no data file
            continue

        with path.open(newline="", encoding="utf-8") as fh:
            rows = list(csv.DictReader(fh))
        if not rows:
            continue

        variables = []
        for row in rows:
            raw = clean(row.get(col["value_labels"]))
            try:
                values = json.loads(raw) if raw else None
            except json.JSONDecodeError:
                values = None

            level = clean(row.get(col["measurement"]))
            # An unseen level is appended rather than folded into
            # "unrecorded", the same way an unknown wave is appended: a new
            # deposit inventing a level should show up, not disappear.
            if level and level not in levels:
                levels.append(level)

            variables.append({
                "variable": row[col["variable"]],
                "label": clean(row.get(col["label"])),
                "pos": clean(row.get(col["position"])),
                "type": clean(row.get(col["type"])),
                "measurement": level,
                "missing": clean(row.get(col["missing"])),
                "values": values,
            })
            index.append([
                row[col["variable"]],
                clean(row.get(col["label"])) or "",
                idx,
                position[wave],
                levels.index(level) if level else -1,
            ])

        # The slug carries the wave for the same collision reason — without
        # it the second dictionary overwrites the first on disk.
        slug = f"{wave}__{name}"
        write_json(DICT / f"{slug}.json",
                   {"file": name, "wave": wave, "slug": slug, "variables": variables})
        built.append(slug)

    return index, built, orphans, levels


def collect_derived() -> list[dict]:
    """The registry, plus each script's actual source.

    So the site can show how a variable was made without fetching anything
    from GitHub.
    """
    registry = REPO / "registry" / "variables.json"
    if not registry.exists():
        return []

    derived = []
    for category, entries in json.loads(
            registry.read_text("utf-8")).get("categories", {}).items():
        for entry in entries:
            script = REPO / entry["file"] if entry.get("file") else None
            entry["source"] = (
                script.read_text("utf-8") if script and script.exists() else None
            )
            entry.setdefault("family", None)
            entry.setdefault("category", category)
            derived.append(entry)

    derived.sort(key=lambda e: (e.get("category") or "", e.get("family") or "", e["id"]))
    return derived


# The pipeline a downloaded bundle needs around the variable scripts. These
# are shipped verbatim rather than regenerated into a bundle-specific runner:
# the code a researcher runs on real data is then byte-identical to the code
# CI lints and tests here, and there is no second implementation of the join,
# the identifier cleaning or the duplicate resolution to drift out of step.
PIPELINE = ("R/runner.R", "R/lib/dataset.R", "R/lib/discovery.R",
            "R/lib/io.R", "R/lib/utils.R")

# Skeletons the bundler fills in, rather than ships. A raw variable has no
# script in the repository to copy — it is a deposited column, not a
# derivation — so the bundler writes one per picked column from this. It lives
# in templates/ beside the other R skeletons rather than inside bundle.js so
# that generated R is reviewed as R, by whoever reviews the rest of it.
#
# Each entry names the placeholders that must survive editing: a rename that
# silently stopped being substituted would ship `{{id}}` into a researcher's
# bundle, and R would run it as a literal.
TEMPLATES = {
    "templates/passthrough.R": ("id", "label", "file", "var", "wave",
                               "identifier", "created"),
    # The bundle's own scaffolding: the file a researcher opens and runs, and
    # the note in the empty folder their data goes into. Both exist so that
    # "where is the data" is answered before anything tries to read it.
    "templates/run.R": ("dataset", "count", "project", "root", "lookup", "env",
                        "set_root", "files", "identifier", "wave_plural",
                        "sample_id"),
    "templates/data-README.md": ("dataset", "project", "root", "lookup",
                                 "env", "sample_wave", "setup"),
    # An RStudio project file, so opening the download sets the working
    # directory — the single most common thing to get wrong. No placeholders:
    # the name carries the identity, and the name is the bundle folder's.
    "templates/project.Rproj": (),
    # Shipped as `.Rprofile`: prints what to do, and opens the README in
    # RStudio so the instructions are on screen rather than in a file someone
    # has to think to open.
    "templates/project-Rprofile.R": ("dataset", "count"),
}


def collect_pipeline() -> dict[str, str]:
    """The runner and its libraries, by repo path.

    A missing one is a build failure rather than a smaller bundle: the atlas
    would go on offering a download that cannot run.
    """
    out = {}
    for rel in PIPELINE:
        path = REPO / rel
        if not path.exists():
            raise ConfigError(
                f"{rel} is missing, so a downloaded bundle could not run. "
                f"Update PIPELINE in build_site.py if the pipeline moved."
            )
        out[rel] = path.read_text("utf-8")
    return out


def collect_templates() -> dict[str, str]:
    """The skeletons the bundler fills in, by repo path, placeholders checked."""
    out = {}
    for rel, required in TEMPLATES.items():
        path = REPO / rel
        if not path.exists():
            raise ConfigError(
                f"{rel} is missing, so the atlas could not package raw variables. "
                f"Update TEMPLATES in build_site.py if it moved."
            )
        text = path.read_text("utf-8")
        absent = [p for p in required if "{{" + p + "}}" not in text]
        if absent:
            raise ConfigError(
                f"{rel} no longer contains the placeholder(s) "
                f"{', '.join('{{' + p + '}}' for p in absent)}, which web/bundle.js "
                f"substitutes. Either restore them or update TEMPLATES and the bundler."
            )
        out[rel] = text
    return out


def main() -> int:
    try:
        cfg = get_config()
        lookup = read_lookup(cfg)
        pipeline = collect_pipeline()
        templates = collect_templates()
    except ConfigError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    waves = order_waves(cfg, lookup)
    position = {w: i for i, w in enumerate(waves)}

    files = collect_files(cfg, lookup, position)
    index, built, orphans, levels = build_dictionaries(cfg, files, position)
    derived = collect_derived()

    index_bytes = write_json(DATA / "variables.json", index)
    write_json(DATA / "derived.json", derived)
    # Fetched only when someone downloads a bundle, so it stays out of the
    # initial load.
    # `lookup` joins `root` and `env` here rather than in the browser config
    # because all three describe the same thing — the shape of the deposits a
    # download expects to find — and only the bundle ever reads them.
    write_json(DATA / "pipeline.json",
               {"root": cfg.root.name, "env": cfg.data_env,
                "lookup": cfg.lookup_csv,
                "files": pipeline, "templates": templates})
    write_json(DATA / "manifest.json", {
        # The browser's copy of dataset.toml. One source of truth: nothing in
        # the front end hard-codes a category, a wave or an issue field.
        "dataset": cfg.for_browser(),
        "repo": cfg.issue["repo"],
        "built": date.today().isoformat(),
        "waves": waves,
        "levels": levels,
        "files": files,
        "filesWithDict": built,
        "unlisted": [f["slug"] for f in files if not f["inLookup"]],
        "counts": {
            "variables": len(index),
            "files": len(files),
            "dictionaries": len(built),
            "waves": len(waves),
            "derived": len(derived),
        },
    })

    extra = levels[len(cfg.measurement_levels):]
    if extra:
        print(f"warning: measurement levels missing from [metadata], appended: "
              f"{', '.join(extra)}")

    unlisted = [f["slug"] for f in files if not f["inLookup"]]
    if unlisted:
        print(f"note: {len(unlisted)} file(s) have a dictionary and a data file on "
              f"disk but no {cfg.lookup_csv} row, so the pipeline cannot reach them. "
              f"Included and flagged: {', '.join(unlisted)}")
    if orphans:
        print(f"note: {len(orphans)} dictionary/ies have no data file on disk, skipped.")

    print(f"Built {len(index):,} variables across {len(files)} files "
          f"({len(built)} dictionaries), {len(derived)} derived. "
          f"Index {index_bytes / 1_048_576:.1f} MB.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
