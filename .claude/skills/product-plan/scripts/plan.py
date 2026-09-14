#!/usr/bin/env python3
"""The mechanical half of a product plan: read the tickets, and compare the
paths they claim against the paths a sprint actually touched.

    python3 plan.py status
    python3 plan.py drift 01 --since main

Deliberately narrow. It parses front-matter and matches paths; it makes no
judgement about whether work was done well, and it cannot tell "done
differently" from "done" — a ticket's files can all be touched by a change
that did something else entirely. That reading is the reviewer's job, and
pretending otherwise would make a clean run mean nothing.

Standard library only, so it runs wherever the repository does.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

PLAN = Path("plan")
STATUSES = ("planned", "in-sprint", "landed", "dropped")


# ── reading tickets ─────────────────────────────────────────────────────

def parse_front_matter(text: str) -> dict:
    """The subset of YAML a ticket actually uses.

    A real parser is not in the standard library and a ticket's front matter
    is four scalars and two lists, so this reads those and nothing else. It
    is lenient on purpose: a malformed ticket should surface as an obviously
    empty field in `status`, not as a traceback in the middle of a review.
    """
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}

    out: dict = {}
    key = None
    for raw in text[3:end].splitlines():
        line = raw.split("#", 1)[0].rstrip() if not raw.strip().startswith("#") else ""
        if not line.strip():
            continue
        if line.lstrip().startswith("- ") and key:
            out.setdefault(key, []).append(line.lstrip()[2:].strip())
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if value.startswith("[") and value.endswith("]"):
            out[key] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        elif value:
            out[key] = value
        else:
            out[key] = []          # a list follows, or the field is empty
    return out


def load_tickets(root: Path) -> list[dict]:
    backlog = root / PLAN / "backlog"
    if not backlog.is_dir():
        return []
    tickets = []
    for path in sorted(backlog.glob("*.md")):
        meta = parse_front_matter(path.read_text("utf-8"))
        meta["_path"] = path.relative_to(root)
        tickets.append(meta)
    return tickets


def ticket_paths(ticket: dict) -> list[str]:
    """The files a ticket claims, with any `:line` suffix dropped."""
    out = []
    for item in ticket.get("evidence") or []:
        out.append(str(item).split(":", 1)[0].strip())
    return [p for p in out if p]


# ── reading the repository ──────────────────────────────────────────────

def changed_paths(since: str, until: str, root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--name-only", f"{since}...{until}"],
        cwd=root, capture_output=True, text=True,
    )
    if result.returncode != 0:
        # git answers a bad ref with a screenful of usage; the first line is
        # the only part that says what went wrong.
        why = (result.stderr.strip().splitlines() or ["unknown error"])[0]
        sys.exit(f"git diff {since}...{until} failed: {why}")
    return [line for line in result.stdout.splitlines() if line]


def touched(claimed: str, changed: list[str]) -> list[str]:
    """A claimed path matches a changed one, or anything beneath it.

    Directories are the reason: a ticket that cites `web/assistant/` is
    satisfied by a change to any file in it.
    """
    prefix = claimed.rstrip("/") + "/"
    return [c for c in changed if c == claimed or c.startswith(prefix)]


# ── commands ────────────────────────────────────────────────────────────

def cmd_status(root: Path) -> int:
    tickets = load_tickets(root)
    if not tickets:
        print(f"No tickets under {PLAN / 'backlog'}. Run the plan mode first.")
        return 1

    width = max(len(str(t.get("id", "?"))) for t in tickets)
    for status in STATUSES:
        group = [t for t in tickets if t.get("status") == status]
        if not group:
            continue
        print(f"\n{status}  ({len(group)})")
        for t in group:
            sprint = t.get("sprint")
            mark = "!" if str(t.get("speculative", "")).lower() == "true" else " "
            print(f"  {mark}{str(t.get('id', '?')):<{width}}  "
                  f"{'s' + str(sprint) if sprint else '  ':<4}"
                  f"{t.get('title', '(untitled)')}")

    unknown = [t for t in tickets if t.get("status") not in STATUSES]
    if unknown:
        print(f"\nunreadable status  ({len(unknown)})")
        for t in unknown:
            print(f"   {t.get('id', '?'):<{width}}      {t['_path']}")
    print(f"\n{len(tickets)} tickets. ! = speculative.")
    return 0


def cmd_drift(root: Path, sprint: str, since: str, until: str) -> int:
    tickets = [t for t in load_tickets(root)
               if str(t.get("sprint", "")).lstrip("0") == sprint.lstrip("0")]
    if not tickets:
        print(f"No tickets carry sprint: {sprint}.")
        return 1

    changed = changed_paths(since, until, root)
    if not changed:
        print(f"No files changed between {since} and {until}.")
        return 1

    print(f"sprint {sprint}   {since}...{until}   {len(changed)} files changed\n")

    claimed_all: set[str] = set()
    for t in tickets:
        claims = ticket_paths(t)
        hits = {c: touched(c, changed) for c in claims}
        for matched in hits.values():
            claimed_all.update(matched)

        any_hit = any(hits.values())
        print(f"{t.get('id', '?')}  {t.get('title', '(untitled)')}")
        print(f"    status: {t.get('status', '?')}   "
              f"{'some cited paths changed' if any_hit else 'NO cited path changed'}")
        for claim, matched in hits.items():
            print(f"      {'✓' if matched else '·'} {claim}"
                  + (f"  ({len(matched)} file{'s' if len(matched) != 1 else ''})"
                     if len(matched) > 1 else ""))
        if not claims:
            print("      (no evidence cited — nothing to check against)")
        print()

    unclaimed = sorted(set(changed) - claimed_all)
    if unclaimed:
        print(f"changed, claimed by no ticket in this sprint  ({len(unclaimed)})")
        for path in unclaimed:
            print(f"    {path}")
        print("\nRead these. Either the plan missed something real, or scope crept.")
    else:
        print("Every changed file was claimed by a ticket in this sprint.")

    print("\nPath matching only. A ticket whose files all changed may still "
          "have been\nbuilt as something else entirely — that is the reading, "
          "and it is yours.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    # On every subcommand rather than on the parent, so `plan.py status --root
    # X` works. Argparse accepts a parent's options only BEFORE the
    # subcommand, which is not the order anyone types.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--root", default=".", help="repository root")

    sub.add_parser("status", parents=[common],
                   help="every ticket, grouped by status")

    drift = sub.add_parser("drift", parents=[common],
                           help="planned paths against landed paths")
    drift.add_argument("sprint", help="sprint number, e.g. 01")
    drift.add_argument("--since", required=True, help="ref the sprint began at")
    drift.add_argument("--until", default="HEAD", help="ref it ended at")

    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    if not (root / PLAN).is_dir():
        sys.exit(f"No {PLAN}/ directory under {root}. Run the survey mode first.")

    if args.command == "status":
        return cmd_status(root)
    return cmd_drift(root, args.sprint, args.since, args.until)


if __name__ == "__main__":
    raise SystemExit(main())
