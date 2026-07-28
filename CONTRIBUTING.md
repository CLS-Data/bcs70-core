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
3. **Develop.** On a branch, scaffold and fill in `R/variables/<category>/<family>/<id>.R` (spec +
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

## Family variables and multi-concept requests

"One variable, one script" doesn't mean every issue maps to exactly one
`R/variables/<category>/<family>/<id>.R`. Two patterns come up that need different handling -
distinguishing them is Step 0 of the `new-variable` skill:

**Same concept, repeated across sweeps** - e.g. "BMI at each age," "highest
qualification at every sweep." This is a *family* of sibling variables, not
one variable. Scaffold one script + one test per sweep that actually has the
needed source data (confirm which via `metadata-search` - don't assume every
sweep qualifies), named `<concept>_<sweep>` with `<sweep>` matching the
`bcs70/<sweep>/` folder exactly (e.g. `bmi_5y`, `bmi_16y`, `bmi_34y`). Every
sibling's `spec$github_issue` points at the same originating issue, and all
the siblings from one issue land in a single PR together - reviewing several
near-identical, sweep-specific scripts side by side is easier than splitting
one request across N separate PRs.

**Genuinely distinct concepts bundled into one ask** - e.g.
"first_age_smoking" and "number_of_cigarettes_smoked" filed together. These
don't share a derivation, a value type, or a verification path, so they get
split into one issue per concept instead of one bundled PR: propose the
split back to whoever filed it, and once confirmed, open a new issue per
concept (referencing the original for context) and close the original with
a comment pointing at the replacements. Each new issue is then worked as its
own, independent request.

When it's genuinely unclear which pattern applies - as it was for "BMI for
each age," where the phrase alone doesn't say whether that means one
cross-sweep field or one-per-sweep - ask rather than guessing. That's
expected behaviour from both the `new-variable` skill and the
`variable-deriver` subagent, not something to route around.

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

### The `variable-deriver` subagent

Steps 1-4 above can also be delegated wholesale to a dedicated subagent,
`.claude/agents/variable-deriver.md`, rather than driving them yourself in
your main session. Ask for it directly, e.g.:

> Use the variable-deriver agent

It fetches every open "Derived variable request" issue (`gh issue list
--label variable-request`), asks which one to work on, then runs the same
metadata-search → scaffold → format/lint/test → registry pipeline as the
`new-variable` skill (it invokes that skill directly rather than
duplicating it) and opens the PR itself.

The difference from just running the skill yourself is scope: this
subagent's own instructions restrict it to creating or changing only
`R/variables/<category>/<family>/<id>.R`, `tests/testthat/test-<id>.R`, and `registry/`. If a
request would require any other file to change, it's instructed to stop and
report back rather than make that change itself; framework-level work stays
something you do directly, not something a variable-deriving agent does on
your behalf. Because it needs to ask which issue to work on, run it in the
foreground (so you can answer that question) rather than backgrounding it.

That boundary is not hypothetical. It has been hit twice: `sex` surfaced two
bugs in `R/runner.R` and `R/lib/io.R`, and the housing tenure family
surfaced duplicate `bcsid` values in two deposits, again needing changes to
`R/lib/io.R` and `R/runner.R`. Both were fixed by hand in a main session.

**Which route to pick.** The agent and the skill run the *same* procedure -
the agent calls the skill rather than reimplementing it, so there is only
one definition of how a variable gets written. Choose on scope, not on
capability:

| | Use the agent | Use the skill directly |
|---|---|---|
| Issue triage (list open requests, pick one) | done for you | you point at the issue |
| Branch, commit, PR | done for you | you drive it |
| Work might need framework changes | it will stop and hand back | you can make them |
| Context | fresh, tool-restricted | your main session |

So: reach for the agent when the request looks like ordinary variable work
and you want the guard rails. Reach for the skill when you already suspect
the job will spill past `R/variables/` - as both examples above did.

The one exception to "only those three paths": when [Step 0](#family-variables-and-multi-concept-requests)
finds an issue bundling multiple distinct concepts, the agent is allowed to
open the split-off issues with `gh issue create` and close the original -
that's GitHub-side triage, not a repository file change, so it doesn't
violate the scope restriction above.

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

## Running the scripts against the real data

This is the "real-data verification" step from the workflow above, done by a
human with authorised access to the real BCS70 microdata - never by an
agent, and never inside a checkout that also talks to GitHub with real data
present.

**Your real-data environment already has the layout this repo's `bcs70/`
mirrors** (built via [CLS-Data/make-directories-bcs70 (shuffle-plus)](https://github.com/CLS-Data/make-directories-bcs70/tree/shuffle-plus)
per the README) - same `<sweep>/`, `metadata/`, and `master_file_info_lookup.csv`
layout, just with real content in the `.tab` files instead of header-only
dummies. All the derivation code needs is that layout plus the `R/` folder
from this repo sitting alongside it.

1. **Keep code and real data in separate git contexts.** Clone this repo
   somewhere that will never contain real data - that clone is safe to
   `git pull` and push/PR from normally:

       git clone <this-repo-url> bcs70-core-code
       cd bcs70-core-code && git pull   # whenever you need the latest scripts

2. **Copy just the `R/` folder into the real-data root** (the directory
   whose `bcs70/` already holds the real `.tab` files) - do not clone or
   `git init` this repo on top of the real data:

       cp -r bcs70-core-code/R /path/to/real-data-root/R

3. **Run it from the real-data root:**

       cd /path/to/real-data-root
       Rscript R/runner.R                    # every variable in R/variables/
       Rscript R/runner.R highest_qualification_age30   # just one variable, by id

   Use the single-variable form when verifying one newly requested variable
   - it only requires that variable's declared `source_files`/`source_vars`
   to exist, not every variable's. (This depends on the file being named
   exactly `R/variables/<category>/<family>/<id>.R`, which the `new-variable` skill always does.)
   Output lands at `output/derived_variables.csv`, entirely on the real-data
   machine - it never needs to leave it.

4. **Check the result without exposing raw values.** Confirm it ran without
   error (a wrong/missing column shows up immediately as an R error from
   `build_variable()`), then look at *aggregate* diagnostics only - `summary()`
   for continuous output, `table()` for categorical/ordinal output, and the
   count of `NA`s - and compare them against what the variable's data
   dictionary (`value_labels_json`, missing-value codes) would lead you to
   expect.

5. **Report back a pass/fail and aggregate diagnostics only** - e.g. "ran
   clean, 12,432 non-missing, distribution matches expected value labels" or
   "column `a0193c` doesn't exist in the real file, only `a0193b`". Never
   paste real row-level values, respondent-level output, or a raw data
   export into the issue, a PR, or a Claude Code session - the aggregate
   summary is enough for the `verify-variable` skill to update `spec$status`.
6. **Never commit anything from the real-data root.** If real-data testing
   surfaces a bug in the script itself, make the fix in `bcs70-core-code`
   (step 1's clean clone) using the synthetic fixtures as normal, re-copy
   `R/` across to confirm the fix works on real data, and open the PR from
   the clean clone - not from the real-data root.

## `bcs70/` is read-only

Nothing in this repo may create, modify, move, or delete any file under
`bcs70/`, for any reason - not the runner, not a variable script, not a
test, not a one-off fix. It stands in for a real data mount that this
code must also run against unchanged. CI enforces this on every PR; treat
a failure of the `guard-bcs70` job as a bug in the PR, not something to
work around.

## Why one file per variable

Each variable script is fully self-contained: a `spec` list (id, label,
category, originating issue, source files/vars, status, notes) plus a
`derive()` function that takes a data frame of only its declared source
variables and returns `bcsid` + the new column. This is deliberate: a future
front end can show "how this variable was made" by displaying that one
file's raw source, and both `R/runner.R` and `scripts/build_registry.R` can
discover every variable purely by listing `R/variables/*/*/*.R` - the spec is
the only source of truth; nothing about a variable is maintained twice.

## The data knowledge ledger

[`DATA_KNOWLEDGE.md`](DATA_KNOWLEDGE.md) records what the data dictionaries
don't: duplicate identifiers in particular files, raw variable names that
mean different things in different sweeps, deposited "derived" variables
whose categories are unusable, sweeps that lack a concept entirely.

It is **maintained by hand, by people who can see the real data.** Agents
read it — the `variable-deriver` agent and the `new-variable`,
`metadata-search` and `verify-variable` skills all point at it — but never
write to it. An agent that turns up something worth recording reports it so
a human can add the entry, because establishing these facts generally
requires a real-data run that no agent in this repo can perform.

Add an entry whenever a real-data verification surfaces something that would
have changed how a variable was written. The format is at the top of the
file; the important discipline is separating **confirmed** from
**suspected** — a wrong entry is worse than a missing one, because it will
be trusted without being re-checked.

## Where variable scripts live

Every variable script sits at exactly one depth:

```
R/variables/<category>/<family>/<id>.R
```

```
R/variables/
  housing/
    housing_tenure/
      housing_tenure_5y.R
      housing_tenure_16y.R
  health/
    bmi/
      bmi_10y.R
  demographic/
    sex/
      sex.R            <- a lone variable is still nested
```

- **`<category>`** is one of the fixed values in the next section, and must
  equal the script's own `spec$category`.
- **`<family>`** groups variables measuring the same concept - usually the
  longitudinal siblings produced by one request. It is **always** present,
  even when a request yields a single variable. A one-off placed directly in
  its category would have to move the moment it gained a sibling, breaking
  every path that referenced it; one consistent depth means
  `R/variables/*/*/*.R` always describes the whole set.
- **`<id>`** equals `spec$id`, and becomes the output column name.

`R/lib/discovery.R` is the single definition of this layout, shared by
`R/runner.R` and `scripts/build_registry.R`. Both fail loudly rather than
skipping a file, so these are build errors and not merely conventions: a
script at the wrong depth, an unrecognised category directory, a
`spec$category` that disagrees with the directory, or a `spec$id` that
disagrees with the file name. That last one matters most, because
`Rscript R/runner.R <id>` selects on the file name - a mismatch would make
the variable silently unrunnable rather than visibly broken.

Tests do **not** mirror this structure. They stay flat at
`tests/testthat/test-<id>.R`, still paired 1:1 with their script; only the
`sys.source()` path inside each test reflects the nesting.

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
parsing every variable script itself. Regenerate them with:

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

# Regenerate the variable registry from R/variables/*/*/*.R
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
