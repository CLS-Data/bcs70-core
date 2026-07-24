# Contributing

This repo produces one modular R script per derived variable. Because the
real BCS70 microdata is licensed and never touches this repo or any LLM,
work here is split across two environments:

- **This repo (dev environment):** dummy `.tab` files (header row only) +
  full metadata (data dictionaries, user guides). Variable logic is written
  and unit-tested here against fabricated data only.
- **The real environment (elsewhere):** identical folder structure, but with
  real data in the `.tab` files. Nobody runs an LLM there; a human pulls the
  merged script and runs `R/runner.R` against it, then reports the result
  back here.

## Workflow

1. **Request.** Open an issue using the "Derived variable request" template:
   variable name, sweep(s), category (see [Variable categories](#variable-categories)),
   what it should capture, and any known source variables/coding notes.
2. **Search.** Before writing any logic, exhaustively search all sweeps for
   candidate source variables/files - not just the sweep(s) named in the
   issue. The `metadata-search` skill runs this via `scripts/search_metadata.R`.
3. **Develop.** On a branch, scaffold and fill in `R/variables/<id>.R` (spec +
   `derive()` logic) and `tests/testthat/test-<id>.R` (synthetic-data tests),
   following `templates/variable.R` / `templates/variable_test.R`. The
   `new-variable` Claude Code skill automates steps 2-3 from the issue, and
   regenerates the registry (step 4) as its last step.
4. **Update the registry.** Run `Rscript scripts/build_registry.R` (or the
   `update-registry` skill) so `registry/variables.json`/`.csv` reflect the
   new variable, grouped by category.
5. **Open a PR** referencing the issue, using `.github/PULL_REQUEST_TEMPLATE.md`.
   CI (`.github/workflows/r-ci.yml`) runs on every PR touching `R/`, `tests/`,
   `templates/`, or `registry/`:
   - `guard-bcs70` fails the build if the diff touches anything under `bcs70/`.
   - `format-lint-test` checks `styler` formatting, runs `lintr`, and runs
     `testthat` against the synthetic fixtures in the PR - never real data.
   - `registry-up-to-date` regenerates the registry and fails if the PR's
     committed `registry/` differs from that output.
6. **Merge** once CI is green and the PR is reviewed. `spec$status` stays
   `"draft"` (or `"ready_for_real_data_test"`) at this point - merging only
   means the logic is believed correct and consistently styled, not verified.
7. **Real-data verification (external).** A maintainer pulls the script and
   runs it against the real data outside this repo, then reports the result
   back on the issue/PR.
8. **Record the outcome.** Use the `verify-variable` skill to update
   `spec$status` to `"verified"` (or, if real data revealed a problem, keep
   it at `"draft"` and fix it as a normal bug-fix PR with a new synthetic
   regression test), and regenerate the registry again.

Pull requests are the unit of review here rather than a staging directory -
a branch already gives isolated in-progress work, a diff already gives a
review surface, and merging to `main` already gives promotion, so a separate
staging area would just duplicate what git provides.

## Using a Claude Code agent to contribute

The skills that drive the workflow above live in `.claude/skills/` and are
committed to this repo, so anyone who clones it gets them automatically -
there's nothing extra to install to use them, beyond Claude Code itself and
the R packages listed under [Commands](#commands).

1. **Clone this repo** and run `claude` (or open it in the Claude Code
   VS Code/JetBrains extension, or the desktop/web app) from its root. Do
   this in a normal checkout of *this* repo only - see the hard rule below
   on never pointing an agent at a checkout that contains real data.
2. **Point it at an issue.** e.g.:
   > Use the new-variable skill for issue #12
   or just describe the request and link the issue - Claude Code matches
   skills by their description, but naming one explicitly (`metadata-search`,
   `new-variable`, `format-r`, `lint-r`, `update-registry`, `verify-variable`)
   is a good habit and removes any ambiguity about which one should run.
3. **Let it work through the pipeline**: metadata search across all sweeps →
   scaffold `spec` + `derive()` + synthetic test → format → lint → test →
   registry rebuild. Read its search results and derivation logic yourself
   before it goes further - a bad `source_files`/`source_vars` choice or
   wrong recoding is far cheaper to catch here than after a PR is open.
4. **Have it open the PR** (or open one yourself from its branch) referencing
   the issue, using `.github/PULL_REQUEST_TEMPLATE.md`. It should leave the
   "Real-data verification" section unchecked - that step isn't the agent's
   to complete.
5. Once you've run the merged script against the real data elsewhere, come
   back and tell your agent the result - it will use the `verify-variable`
   skill to update `spec$status` and the registry accordingly.

**Hard rules to hold any agent to, no matter who's driving it:**

- **Never point a Claude Code session at anything other than this repo's
  dummy `bcs70/` data.** The whole point of the dummy-data-plus-metadata
  design is that an agent never needs real-data access to write correct
  derivation logic. If a task seems to need it, that's a signal to stop and
  do that part yourself outside the agent session - not a reason to hand the
  agent access to a real-data checkout.
- **Never let an agent mark `spec$status` as `"verified"` on its own.** That
  requires a human to have actually run the script against real data outside
  this repo first (step 5 above) - it's not something synthetic tests or the
  agent's own confidence can substitute for.
- **Treat a `guard-bcs70` or `registry-up-to-date` CI failure as a bug to
  fix, not a check to route around.** Don't ask an agent to force-push past
  it, edit the CI workflow to skip it, or hand-edit `registry/` to match.
- **One variable, one branch.** If more than one collaborator has an agent
  working at the same time, keep each on its own branch named for the issue
  (e.g. `variable/highest-qualification-age30`) so concurrent sessions can't
  collide on the same files.

## `bcs70/` is read-only

Nothing in this repo may create, modify, move, or delete any file under
`bcs70/`, for any reason - not the runner, not a variable script, not a
test, not a one-off fix. It stands in for a real data mount that this
code must also run against unchanged. CI enforces this on every PR; treat
a failure of the `guard-bcs70` job as a bug in the PR, not something to
work around.

## Why one file per variable

Each `R/variables/<id>.R` is fully self-contained: a `spec` list (id, label,
category, originating issue, source files/vars, status, notes) plus a
`derive()` function that takes a data frame of only its declared source
variables and returns `bcsid` + the new column. This is deliberate: a future
front end can show "how this variable was made" by displaying that one
file's raw source, and both `R/runner.R` and `scripts/build_registry.R` can
discover every variable purely by listing `R/variables/*.R` - the spec is
the only source of truth; nothing about a variable is maintained twice.

## Variable categories

Every `spec$category` must be one of the fixed values below (enforced by
`scripts/build_registry.R`) - this is also the "Category" dropdown on the
issue template, so a new-variable request's category maps directly onto the
spec:

| Issue dropdown label     | `spec$category` value   |
|---------------------------|--------------------------|
| Demographic                | `demographic`            |
| Socio-economic              | `socio_economic`         |
| Health                      | `health`                 |
| Education                   | `education`              |
| Employment                  | `employment`             |
| Family & relationships       | `family_relationships`   |
| Housing                     | `housing`                |
| Behavioural / lifestyle       | `behavioural_lifestyle`  |
| Cognitive / ability           | `cognitive_ability`      |
| Other                       | `other`                  |

## The variable registry

`registry/variables.json` and `registry/variables.csv` are generated,
never hand-edited. They're grouped by category and give a front end (or
anyone browsing the repo) a single place to list every variable, its status,
its originating issue, and the exact file with its source code - without
parsing every `R/variables/*.R` file itself. Regenerate them with:

    Rscript scripts/build_registry.R

CI's `registry-up-to-date` job re-runs this and fails the PR if the result
differs from what's committed, so `registry/` can never silently drift from
the specs it's derived from.

## Commands

```r
# Format all R code
Rscript -e 'styler::cache_deactivate(); styler::style_dir("R"); styler::style_dir("tests")'

# Lint all R code
Rscript -e 'print(c(lintr::lint_dir("R"), lintr::lint_dir("tests")))'

# Run the synthetic-data test suite
Rscript -e 'testthat::test_dir("tests/testthat")'

# Run every derived-variable script end to end (reads bcs70/, writes output/)
Rscript R/runner.R

# Search all sweeps' metadata for candidate source variables/files
Rscript scripts/search_metadata.R "keyword one" "keyword two"

# Regenerate the variable registry from R/variables/*.R
Rscript scripts/build_registry.R
```

Required R packages: `styler`, `lintr`, `testthat`, `jsonlite`. `output/` is
gitignored - whatever `R/runner.R` writes there (including when run against
the dummy data in this repo) must never be committed. `registry/` is the
opposite: it's generated but must be committed, since it's the front end's
read path into this repo.

`styler::cache_deactivate()` is called before every format check because its
on-disk cache can fail with a permission error in sandboxed/restricted
environments (seen in a locked-down Claude Code session) - it's purely a
performance optimization, so turning it off costs nothing but a bit of speed.
