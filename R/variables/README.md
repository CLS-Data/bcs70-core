# Variable scripts

Every derived variable is one file, at exactly this depth:

```
R/variables/<category>/<family>/<id>.R
```

For example:

```
R/variables/
  housing/
    housing_tenure/
      housing_tenure_5y.R
      housing_tenure_10y.R
      housing_tenure_16y.R
  health/
    bmi/
      bmi_10y.R
      bmi_16y.R
  demographic/
    sex/
      sex.R            <- a lone variable is still nested
```

| Level | Meaning |
|---|---|
| `<category>` | One of the ten fixed values in [CONTRIBUTING.md](../../CONTRIBUTING.md#variable-categories). Must equal the script's own `spec$category`. |
| `<family>` | Groups variables measuring the same concept — usually the longitudinal siblings of a single request. Always present, even when there is only one variable. |
| `<id>` | Matches `spec$id` exactly, and becomes the output column name. |

## Why the family directory is always there

A one-off variable placed directly in its category would have to move the
moment it gains a sibling, breaking every path that referenced it. Keeping
one consistent depth means `R/variables/*/*/*.R` always describes the whole
set, and tooling never has to handle two shapes.

## What is enforced

`R/lib/discovery.R` is the single definition of this layout, shared by
`R/runner.R` and `scripts/build_registry.R`. Both fail loudly rather than
silently skipping a file, so these are build errors, not conventions:

- a script at the wrong depth (directly in `R/variables/`, or in a category
  with no family directory)
- a category directory that isn't one of the ten allowed values
- `spec$category` disagreeing with the directory the file sits in
- `spec$id` disagreeing with the file name — this one matters because
  `Rscript R/runner.R <id>` selects on the file name, so a mismatch makes
  the variable silently unrunnable

## Adding one

Use the `new-variable` skill rather than copying a file by hand — it runs
the metadata search, scaffolds the script and its test from `templates/`,
and regenerates `registry/`. See
[CONTRIBUTING.md](../../CONTRIBUTING.md) for the full issue → PR → CI →
real-data verification workflow.

Tests stay flat at `tests/testthat/test-<id>.R`, paired 1:1 with the script
regardless of how deeply it is nested.
