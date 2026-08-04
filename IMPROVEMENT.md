# Improvement notes

Observations from running `variable-deriver` and `verify-variable` end to end
(issue #25, PR #26) and from setting up sandboxed git permissions for the
`variable-deriver` agent. Kept separate from `DATA_KNOWLEDGE.md` (which is a
hand-maintained ledger of deposit quirks) - this file is about the tooling
and workflow around the pipeline, not the data itself.

## Workflow

- **Run branch-mutating agent work in an isolated worktree, not the shared
  checkout.** `variable-deriver` leaves the working tree checked out on its
  new branch after opening a PR. Any unrelated work done afterward in the
  same session (e.g. editing `.claude/settings.json`) then sits on top of
  that PR branch, forcing a stash/rebase/stash-pop cycle to keep the two
  changes apart before either can be pushed. Isolating agent-driven branch
  work to its own worktree would remove this class of friction entirely.

- **`verify-variable` should name the `.verification/<sha>/*.json`
  convention explicitly.** The skill currently says to "ask for (or read
  from the issue/PR comment) the outcome" but doesn't mention that this
  repo's actual real-data-reporting mechanism is a set of JSON files
  committed directly onto the PR branch under `.verification/`. Finding
  them this session relied on knowing to look via `git log --all -- 
  .verification`, not on anything the skill itself says. Naming the
  convention in the skill file would make this step reliable regardless of
  which agent or person runs it.

- **Automate the status/notes edit.** Marking a family of siblings
  "verified" by hand means transcribing n/missing_pct/checks out of each
  result JSON into `spec$notes` - mechanical, and one mistyped number away
  from a wrong record. `scripts/verify_variables.py` (added in this PR)
  automates it: given a `.verification/<sha>/` directory already committed
  on the branch, it cross-references `registry/variables.json` for each
  variable's file path (no R parsing needed), flips `status` to
  `"verified"` for every harness "success" result, and generates the note
  block from the JSON's own summary fields. It leaves harness failures and
  unknown ids untouched, and is idempotent (an already-verified variable is
  skipped, not re-written). Still requires running `format-r`, `lint-r`,
  the test suite, and `update-registry` afterward, same as the manual
  process.

## Suggested additions to the `.verification/<sha>/*.json` schema

This file is the only channel that ever crosses from the real-data
environment into this repo - every field on it should earn its place by (a)
being provably safe to expose at any N, and (b) closing a real gap in what a
human or agent can currently tell from outside that environment. The harness
itself lives outside this repo, so these are inputs for whoever maintains it,
not something actionable here.

1. **`spec_sha256`** - a hash of the exact R spec file content that was
   checked. Right now "verified" is a point-in-time claim with no way to
   detect that the spec was edited afterward; a hash (mirrored into
   `spec$notes` or a new `spec$verified_source_hash`) would let a check fail
   the moment a verified spec's hash stops matching, without touching real
   data.

2. **Missingness broken down by cause**, not lumped into one `missing_pct` -
   e.g. `{"not_stated": 2.1, "not_known": 0.3, "not_applicable": 5.5}`. This
   is exactly the nuance `DATA_KNOWLEDGE.md` currently has to capture by
   hand from harness console output.

3. **`resolve_duplicate_ids()`/dropped-id counts, per variable** -
   `{"collapsed_agreeing": N, "dropped_disagreeing": N,
   "dropped_malformed_id": N}`. CLAUDE.md documents this resolution
   behaviour, but it's currently only visible as a runtime warning a human
   has to notice and transcribe.

4. **Populate `codes` consistently, with labels** - a `{code, label, count}`
   array per categorical level. Still codebook-level information, never a
   respondent value, but would let a script confirm `derive()`'s output
   labels actually match what the spec claims.

5. **`skip_reason` alongside `checks`** - several checks currently show
   `"skip"` with no indication of whether that's benign-by-design for this
   variable's `kind`, or an actual gap in harness coverage.

6. **Document the `levels_suppressed` k-anonymity threshold explicitly** -
   the field already exists and is presumably already enforced; stating the
   actual threshold in the schema docs would let downstream tooling rely on
   the guarantee instead of inferring it.

7. **A `previous_verification` delta block on re-verification** - prior
   commit/n/missing_pct alongside the new ones, so a regression from a later
   spec change is visible immediately instead of requiring `git log`
   archaeology.
