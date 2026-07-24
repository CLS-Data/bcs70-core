---
name: new-variable
description: Scaffold a new derived-variable R script (spec + logic + synthetic test) from a GitHub issue request, after an exhaustive metadata search, and refresh the variable registry.
---

# New variable

Use this when the user hands you a GitHub issue (number, URL, or pasted text) requesting a new derived variable.

## Steps

1. Determine the variable `id` (snake_case, becomes the output column name and the file name `R/variables/<id>.R`) - from the issue title/body, or ask the user if ambiguous.
2. Read the issue's `category` field (from the "Derived variable request" issue form) and map it to the matching `spec$category` value in `CONTRIBUTING.md#variable-categories`. If the issue predates that field or the category is unclear, ask the user rather than guessing.
3. Invoke the `metadata-search` skill using keyword variants drawn from the issue title, description, and category - do this across the whole `bcs70/` corpus, not just the sweep(s) the issue names. Do not proceed to step 4 until this search is exhausted.
4. Copy `templates/variable.R` to `R/variables/<id>.R` and fill in `spec` (id, label, category, github_issue, author, created, source_files, source_vars, notes) plus the `derive()` logic, based only on source files/variables the search surfaced and their documented value labels/missing codes. Leave `status = "draft"`.
5. Copy `templates/variable_test.R` to `tests/testthat/test-<id>.R`, filling in synthetic rows that cover: a typical valid value per source var, each documented missing/sentinel code, and a genuine `NA`.
6. Invoke the `format-r` skill, then the `lint-r` skill, against the new files.
7. Run `Rscript -e 'testthat::test_dir("tests/testthat")'` and confirm the new test passes.
8. Invoke the `update-registry` skill so `registry/` picks up the new variable, and include that diff in the same change.
9. Tell the user plainly: this script has only been checked against fabricated data - it still needs to be run against the real data outside this repo before `spec$status` can move past `"draft"`. Suggest opening a PR (using `.github/PULL_REQUEST_TEMPLATE.md`) that references the originating issue.

## Hard rules

- Never read from or write to anything under `bcs70/` from inside `R/variables/*.R` - all data access goes through `R/lib/io.R`, called only by the runner.
- Never modify any file under `bcs70/` for any reason.
- If the requested variable needs something not present in any data dictionary, say so instead of guessing at a coding scheme.
