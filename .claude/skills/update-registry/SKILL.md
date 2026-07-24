---
name: update-registry
description: Regenerate the machine-readable variable registry (registry/variables.json, registry/variables.csv) from every R/variables/*.R spec, grouped by category, after adding or changing a variable.
---

# Update registry

Run after adding a new `R/variables/<id>.R`, or after any change to an existing spec (including a `verify-variable` status update):

    Rscript scripts/build_registry.R

This scans every `R/variables/*.R`, and re-derives:

- `registry/variables.json` - grouped by `spec$category`, one array per category (always an array, even when empty, so a front end can rely on a consistent shape)
- `registry/variables.csv` - the same data flattened, one row per variable

It fails loudly (non-zero exit) if any spec is missing a valid `category` (must be one of the fixed set in `CONTRIBUTING.md#variable-categories`) or if two variables share an `id` - treat either as a bug in the variable script to fix, not something to work around.

Never hand-edit anything under `registry/` - it is fully derived from `R/variables/`. If its content looks wrong, fix the source `spec` and re-run this script. Show the user `git diff --stat registry/` (or "no changes") afterward, and include the resulting diff in the same PR as the variable change.
