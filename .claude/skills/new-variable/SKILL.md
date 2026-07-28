---
name: new-variable
description: Scaffold a new derived-variable R script (spec + logic + synthetic test) from a GitHub issue request, after an exhaustive metadata search, and refresh the variable registry. Also handles requests that are really a family of sweep-specific siblings (e.g. "BMI at each age"), or that bundle multiple distinct concepts and need splitting into separate issues.
---

# New variable

Use this when the user hands you a GitHub issue (number, URL, or pasted text) requesting a new derived variable.

## How this gets run

Two ways, and they share this one procedure so it cannot drift:

- **Directly in the main session** (`/new-variable`, or the user pasting an
  issue). You do everything here, including Step 9's PR suggestion. Use this
  route when the work may need framework changes - the main session can make
  them; the agent cannot.
- **Via the `variable-deriver` agent**, which handles issue triage before
  calling you and branch/commit/PR afterwards. When invoked that way, stop
  after Step 8 and hand back - the agent opens the PR.

This file is the single source of truth for **how a variable is written**:
classification, naming, searching, scaffolding, validating, registering.
The agent deliberately does not restate any of it.

## Before you start: read the data knowledge ledger

Read `DATA_KNOWLEDGE.md` at the repo root before anything else. It records
known quirks in the deposits that no data dictionary mentions - duplicate
identifiers, raw variable names that mean different things in different
sweeps, deposited "derived" variables whose categories are unusable, sweeps
that don't carry a concept at all. An entry there **overrides** your default
reading of a dictionary.

Re-read the entries relevant to your sweeps and files again at Step 4 below,
before writing `derive()`. Never edit this file yourself - if your work
surfaces something that belongs in it, say so in your summary so a human
can add it.

## Step 0: classify the request

Work out which of three shapes the issue actually is - see
`CONTRIBUTING.md#family-variables-and-multi-concept-requests` for the full
policy:

- **One variable.** Continue to Step 1 below as normal.
- **A family: the same concept repeated across sweeps** (e.g. "BMI at each
  age"). This isn't one variable - it's several siblings, one per sweep that
  actually has the needed source data. Run `metadata-search` first to
  confirm which sweeps qualify, propose the resulting id list to the user
  (`<concept>_<sweep>`, e.g. `bmi_5y`, `bmi_16y`) for confirmation, then
  repeat Steps 1-7 below **once per sweep** before doing Step 8 (registry)
  and Step 9 **once**, for the whole family together.
- **Multiple distinct concepts bundled into one issue** (e.g.
  "first_age_smoking" and "number_of_cigarettes_smoked" filed together).
  Don't scaffold these together. Propose splitting into one issue per
  concept; once the user confirms, create the new issues with
  `gh issue create` (referencing the original for context), close the
  original with a comment pointing at the new issues, and stop - each new
  issue becomes its own request, worked independently afterward.
- If it's genuinely unclear which of these applies (as it was for "BMI for
  each age" - the phrase alone doesn't say whether that means one
  cross-sweep field or one-per-sweep), ask the user rather than guessing.

## Steps

1. Determine the variable `id` (snake_case, becomes the output column name and the file name at the end of `R/variables/<category>/<family>/<id>.R`) - from the issue title/body, or ask the user if ambiguous.
2. Read the issue's `category` field (from the "Derived variable request" issue form) and map it to the matching `spec$category` value in `CONTRIBUTING.md#variable-categories`. If the issue predates that field or the category is unclear, ask the user rather than guessing. This value is also the top-level directory the script goes in, and the two are cross-checked at build time.
2a. Decide the `<family>` directory name - the concept these variables measure, snake_case, without any sweep suffix (`housing_tenure`, `bmi`, `sex`). For a family request it is the shared stem of the sibling ids; for a single variable it is normally just the id itself. Reuse an existing family directory if one already covers the concept rather than creating a near-duplicate beside it.
3. Invoke the `metadata-search` skill using keyword variants drawn from the issue title, description, and category - do this across the whole `bcs70/` corpus, not just the sweep(s) the issue names. Do not proceed to step 4 until this search is exhausted.
4. Copy `templates/variable.R` to `R/variables/<category>/<family>/<id>.R` - creating the category and family directories if they don't exist yet - and fill in `spec` (id, label, category, github_issue, author, created, source_files, source_vars, notes) plus the `derive()` logic, based only on source files/variables the search surfaced and their documented value labels/missing codes. Leave `status = "draft"`. If the same raw variable name is declared across more than one `source_files` entry, remember the runner disambiguates those specific columns as `data[["<file_name>.<var>"]]` (see `CLAUDE.md`) - everything else stays bare.
5. Copy `templates/variable_test.R` to `tests/testthat/test-<id>.R`, filling in synthetic rows that cover: a typical valid value per source var, each documented missing/sentinel code, and a genuine `NA`.
6. Invoke the `format-r` skill, then the `lint-r` skill, against the new files.
7. Run `Rscript -e 'testthat::test_dir("tests/testthat")'` and confirm the new test passes.
8. Invoke the `update-registry` skill so `registry/` picks up the new variable(s), and include that diff in the same change.
9. Report plainly: this script has only been checked against fabricated data - it still needs to be run against the real data outside this repo before `spec$status` can move past `"draft"`. Also flag anything you hit that belongs in `DATA_KNOWLEDGE.md`, for a human to add.

   Then, depending on how you were invoked (see "How this gets run" above):
   - **Directly:** suggest opening a PR (using `.github/PULL_REQUEST_TEMPLATE.md`) that references the originating issue - one PR per issue, even when Step 0 produced a whole family of sibling files.
   - **Via the `variable-deriver` agent:** stop here and hand back. The agent branches, commits and opens the PR; don't do it yourself, and don't suggest it as if the user must.

## Hard rules

- Never read from or write to anything under `bcs70/` from inside a variable script - all data access goes through `R/lib/io.R`, called only by the runner.
- Never modify any file under `bcs70/` for any reason.
- If the requested variable needs something not present in any data dictionary, say so instead of guessing at a coding scheme.
