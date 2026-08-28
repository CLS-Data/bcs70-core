---
name: product-plan
description: Turn a proof-of-concept repository into a product development plan — a grounded survey of what exists, a target architecture, an evidence-backed backlog, sprints, and a review pass comparing what a sprint planned against what actually landed. Use for "plan this repo", "what would it take to productionise this", "break this into sprints", "review sprint N".
---

# Product plan

A proof of concept answers "could this work". A product plan answers "what
has to be built, in what order, and how will we know it was". This skill
turns the first into the second, and then keeps the second honest.

It is repo-agnostic. Orient from `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`
and the directory layout. Never assume a stack.

## The failure this is built against

A skill that reads a repository and emits a plan will always produce
something. The failure mode is not a crash — it is forty confident tickets
that read beautifully and are wrong in ways nobody discovers until someone
tries to build one. Two rules exist to make the output falsifiable, and
neither is negotiable.

**No ticket without evidence.** Every ticket cites the paths it is about —
the file it extends, the function it replaces, the gap it fills. Open those
files before writing the ticket. A ticket you cannot ground in code is a
guess: mark it `speculative: true` and keep it in its own section, never
mixed in with work that is grounded.

**Plan deeply, then shallowly.** Ticket-level detail for the next sprint
only. Everything beyond is a one-line epic. A six-sprint ticket breakdown of
a PoC is fiction, because sprint one changes what you know about sprint two,
and rewriting it every fortnight is the real cost.

## Four modes

Run one at a time. Each has a different failure mode and each deserves a
human reading it before the next starts. A single command that surveys,
plans, sprints and reviews produces something nobody checked.

| mode | produces | the question it answers |
|---|---|---|
| `survey` | `plan/survey.md` | is this an accurate account of the repo? |
| `plan` | `plan/architecture.md`, `plan/backlog/*.md` | are these the right problems? |
| `sprint` | `plan/sprints/NN.md` | is this the right next slice? |
| `review` | appends to `plan/sprints/NN.md` | did what we planned match what got built? |

If the user names no mode, ask which. Do not guess, and do not run several.

## Layout

```
plan/
  survey.md              what exists, what is PoC-grade, what is missing
  architecture.md        target shape, with a mermaid diagram
  backlog/
    P1-short-slug.md     one ticket per file
  sprints/
    01.md                selection, rationale, and the review afterwards
```

Committed, not ignored. The point is reviewing it together.

## Ticket format

Front-matter maps one-to-one onto `gh issue create`, so a local backlog is
one command from being real issues. Keep exactly this shape.

```markdown
---
id: P4
title: Isolate agent branch work in a worktree
status: planned          # planned | in-sprint | landed | dropped
sprint:                  # filled by `sprint`
depends_on: [P2]
evidence:
  - IMPROVEMENT.md:11
  - .claude/agents/variable-deriver.md
speculative: false
issue:                   # filled once filed on GitHub
---

## Why

The problem, in the repository's own terms. Name what goes wrong today, and
where you saw it.

## What

The change. Concrete enough that someone who has not read this conversation
could start.

## Acceptance

- [ ] Something observable, not "works correctly"
- [ ] What a reviewer checks
```

`id` is stable for the life of the plan. Never renumber — the review pass and
any filed issues reference it.

## survey

Read the repository properly first: entry points, tests, CI, docs, the
recent shape of the git log. Then write `plan/survey.md`.

- **What it does** — in the repo's own vocabulary, not yours.
- **What is solid** — parts already product-grade, with paths. Naming these
  matters as much as the gaps; a plan that proposes rebuilding working code
  is worse than no plan.
- **What is PoC-grade** — works, but would not survive being depended on.
  Say what breaks it: no tests, one hard-coded path, a single-user
  assumption, an unhandled failure.
- **What is missing** — needed for a product, absent entirely.
- **Constraints** — what any plan must respect. Usually in `CLAUDE.md` or
  `CONTRIBUTING.md`, and the fastest way to produce an unusable plan is to
  ignore them.

Every item carries paths. An item without a path is an impression, and goes
under a clearly labelled *Impressions* heading at the end, or nowhere.

## plan

`plan/architecture.md`: the target shape, a mermaid diagram, and — most
importantly — **what changes from today and what does not**. An architecture
that does not say which existing code survives it is a redesign nobody asked
for.

`plan/backlog/`: one ticket per unit of work, each referencing the survey
item it comes from.

Prefer fewer, larger, well-grounded tickets to many small speculative ones.
If a ticket cannot be written without inventing requirements, it is not
ready: leave it as an epic line in the architecture and say so.

## sprint

Select from the backlog into `plan/sprints/NN.md`, respecting `depends_on`.
Record **why these** and **why not the obvious alternatives** — that
rationale is what makes the review meaningful later.

Set `status: in-sprint` and `sprint: NN` on each selected ticket. Ask for the
sprint's length and capacity rather than assuming.

## review

The delivery-manager half, and the reason the rest exists.

1. `python3 scripts/plan.py drift NN --since <ref>` for the mechanical part:
   which cited paths were touched, which were not, and which changed paths no
   ticket claimed.
2. Read the actual diff for anything it flags. The script matches paths; only
   reading says whether the work was the work.
3. Re-survey the changed areas. The script cannot see a gap nobody wrote a
   ticket for.

Then append to the sprint file under these four headings. The last three are
the valuable ones.

- **Landed as planned** — ticket and diff agree.
- **Landed differently** — the ticket said one thing, the diff did another.
  Say which, and whether the plan or the code should change to match.
- **Not started** — and whether it still matters.
- **Landed unplanned** — work with no ticket. The most interesting category:
  either the plan missed something real, or scope crept.

Update each ticket's `status`. A dropped ticket keeps its file with
`status: dropped` and a line saying why; deleting it loses the record that a
decision was made.

## The script

`scripts/plan.py` does the mechanical half, and only that. It is genuinely
implemented — read it if in doubt.

```bash
python3 scripts/plan.py status                  # every ticket, by status
python3 scripts/plan.py drift 01 --since main   # planned paths vs landed paths
```

It parses front-matter and matches paths. It makes no judgement about whether
work was done well, and cannot tell "done differently" from "done". That is
the reading, and it is yours.

## What not to do

- **Do not regenerate.** Re-running `plan` on an existing `plan/` updates it.
  Overwriting a backlog destroys the `status` history the review depends on.
- **Do not inflate.** Thirty tickets out of a PoC almost always means the
  survey was shallow and the gaps were guessed at.
- **Do not plan around the constraints.** If `CLAUDE.md` says a directory is
  read-only or a dependency list stays empty, a ticket that violates it is
  not a bold proposal, it is a wrong ticket.
- **Do not file issues unasked.** The local backlog is the draft; filing is a
  separate, explicit step.
