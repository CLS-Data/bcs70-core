#!/usr/bin/env python3
"""Apply real-data harness results already committed under .verification/<sha>/
on the current branch to their matching variable specs: flips spec$status to
"verified" and appends a dated note summarizing the aggregate result.

Cross-references registry/variables.json for each variable id's file path, so
this never parses R - only text-substitutes the two spec fields the
verify-variable skill would otherwise edit by hand.

Usage:
    python3 scripts/verify_variables.py <sha-dir-name> [--dry-run]
    python3 scripts/verify_variables.py --list

Only variables whose harness result has status == "success" are touched, and
only if their current spec status isn't already "verified" (idempotent re-runs
are safe). A harness "failure" is reported but never auto-edited - per the
verify-variable skill, that's a bug-fix task on the script, not a status flip.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VERIFICATION_DIR = REPO_ROOT / ".verification"
REGISTRY_PATH = REPO_ROOT / "registry" / "variables.json"

STATUS_RE = re.compile(r'(status\s*=\s*)"[^"]*"(\s*,)')
NOTE_STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def load_registry() -> dict[str, dict]:
    registry = json.loads(REGISTRY_PATH.read_text())
    by_id = {}
    for variables in registry["categories"].values():
        for var in variables:
            by_id[var["id"]] = var
    return by_id


def find_paste_block(text: str) -> tuple[int, int] | None:
    """Return (start, end) spanning the argument list of `notes = paste(...)`,
    i.e. the byte range between the open paren after `paste` and its match."""
    m = re.search(r"notes\s*=\s*paste\(", text)
    if not m:
        return None
    start = m.end()
    depth = 1
    i = start
    while i < len(text) and depth > 0:
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
        i += 1
    if depth != 0:
        return None
    return start, i - 1


def build_note_lines(variable_id: str, sha_dir: str, result: dict) -> list[str]:
    branch = result.get("branch", "?")
    schema = result.get("schema_version", "?")
    summary = result.get("summary", {}).get(variable_id, {})
    kind = summary.get("kind", "?")
    n = summary.get("n")
    missing_pct = summary.get("missing_pct")
    n_str = f"{n:,}" if isinstance(n, (int, float)) else "?"

    lines = [
        f"VERIFIED against real data on {result.get('_verified_date', '?')} "
        f"(harness run {sha_dir}, branch",
        f"{branch}, schema {schema}). Aggregate: n = {n_str}, "
        f"{missing_pct}% missing.",
    ]
    if kind == "categorical":
        levels = summary.get("levels")
        codes = summary.get("codes")
        counts = summary.get("counts")
        detail = f"{levels} level(s) represented"
        if codes:
            detail += f" (codes: {', '.join(map(str, codes))})"
        if counts and any(c == 0 for c in counts) and len(counts) > 1:
            detail += " - note at least one level had zero observations"
        lines.append(detail + ".")
    elif kind == "numeric":
        mean, sd = summary.get("mean"), summary.get("sd")
        p25, p50, p75 = (
            summary.get("p25"),
            summary.get("p50"),
            summary.get("p75"),
        )
        lines.append(f"Mean = {mean}, sd = {sd}, p25/p50/p75 = {p25}/{p50}/{p75}.")

    checks = result.get("checks", {})
    passed = [name for name, outcome in checks.items() if outcome == "pass"]
    if passed:
        lines.append("All applicable harness checks passed - " + ", ".join(passed) + ".")
    lines.append(
        "No row-level or respondent-level data was inspected, only this "
        "aggregate harness summary."
    )
    return lines


def wrap_note_lines(lines: list[str], width: int = 78) -> list[str]:
    """Re-wrap into ~width-char quoted literals; styler/format-r cleans up
    indentation afterward, so this only needs to keep lines from running long."""
    text = " ".join(lines)
    words = text.split(" ")
    wrapped, current = [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if len(candidate) > width and current:
            wrapped.append(current)
            current = word
        else:
            current = candidate
    if current:
        wrapped.append(current)
    return wrapped


def apply_note(text: str, new_lines: list[str]) -> str:
    span = find_paste_block(text)
    if span is None:
        raise ValueError("no `notes = paste(...)` block found - edit by hand")
    start, end = span
    block = text[start:end]

    literals = list(NOTE_STRING_RE.finditer(block))
    new_literal_src = ",\n".join(f'    "{line}"' for line in new_lines)

    if literals:
        last = literals[-1]
        last_content = last.group(1).strip().lower()
        if last_content.startswith("not yet verified") or last_content.startswith(
            "verified against real data"
        ):
            new_block = block[: last.start()] + new_literal_src + block[last.end() :]
            return text[:start] + new_block + text[end:]

    # No existing verification placeholder: append after the last literal.
    if literals:
        last = literals[-1]
        new_block = block[: last.end()] + ",\n" + new_literal_src + block[last.end() :]
    else:
        new_block = new_literal_src
    return text[:start] + new_block + text[end:]


def process(sha_dir: str, dry_run: bool) -> int:
    verif_path = VERIFICATION_DIR / sha_dir
    if not verif_path.is_dir():
        print(f"error: {verif_path} does not exist", file=sys.stderr)
        return 1

    registry = load_registry()
    changed, skipped, failed, missing = [], [], [], []

    for result_file in sorted(verif_path.glob("*.json")):
        if result_file.stem == "_integration":
            continue
        variable_id = result_file.stem
        result = json.loads(result_file.read_text())

        if result.get("status") != "success":
            failed.append(variable_id)
            continue

        entry = registry.get(variable_id)
        if entry is None:
            missing.append(variable_id)
            continue

        if entry["status"] == "verified":
            skipped.append(variable_id)
            continue

        spec_path = REPO_ROOT / entry["file"]
        text = spec_path.read_text()

        text, n = STATUS_RE.subn(r'\1"verified"\2', text, count=1)
        if n == 0:
            print(f"warning: no status field matched in {spec_path}", file=sys.stderr)
            continue

        import datetime

        result["_verified_date"] = datetime.date.today().isoformat()
        note_lines = wrap_note_lines(build_note_lines(variable_id, sha_dir, result))
        try:
            text = apply_note(text, note_lines)
        except ValueError as exc:
            print(f"warning: {spec_path}: {exc}", file=sys.stderr)
            continue

        if not dry_run:
            spec_path.write_text(text)
        changed.append(variable_id)

    print(f"Verified ({'dry-run, not written' if dry_run else 'written'}): {len(changed)}")
    for v in changed:
        print(f"  {v}")
    if skipped:
        print(f"Already verified, left alone: {len(skipped)}")
        for v in skipped:
            print(f"  {v}")
    if failed:
        print(f"Harness failures, NOT touched (bug-fix task instead): {len(failed)}")
        for v in failed:
            print(f"  {v}")
    if missing:
        print(f"Unknown id (not in registry/variables.json - rebuild it first): {len(missing)}")
        for v in missing:
            print(f"  {v}")

    if changed and not dry_run:
        print(
            "\nNext: run format-r, lint-r, the test suite, and update-registry, "
            "then commit."
        )
    return 0


def list_available() -> int:
    if not VERIFICATION_DIR.is_dir():
        print("no .verification/ directory in this checkout", file=sys.stderr)
        return 1
    for d in sorted(VERIFICATION_DIR.iterdir()):
        if not d.is_dir():
            continue
        n_results = len(list(d.glob("*.json")))
        print(f"{d.name}  ({n_results} result files)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sha_dir", nargs="?", help="the .verification/<sha_dir> to apply")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--list", action="store_true", help="list available sha dirs")
    args = parser.parse_args()

    if args.list or not args.sha_dir:
        return list_available()
    return process(args.sha_dir, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
