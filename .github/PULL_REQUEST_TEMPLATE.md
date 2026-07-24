## Variable

Closes #<issue number>

## Summary

<what this derives and how, in 1-2 sentences>

## Checklist

- [ ] Ran a cross-sweep metadata search (`scripts/search_metadata.R` / `metadata-search` skill) before settling on source files/vars
- [ ] `R/variables/<id>.R` added, `spec` fields filled in (id, label, category, github_issue, author, created, source_files, source_vars)
- [ ] `tests/testthat/test-<id>.R` added, covering typical values, every documented missing/sentinel code, and NA
- [ ] `styler::style_dir("R")` / `styler::style_dir("tests")` run, no diffs left
- [ ] `lintr::lint_dir("R")` clean
- [ ] `testthat::test_dir("tests/testthat")` passes locally
- [ ] `Rscript scripts/build_registry.R` run, `registry/` diff included in this PR
- [ ] Reads no data directly (only via `R/lib/io.R` helpers) and writes nothing to disk
- [ ] No files under `bcs70/` are touched by this diff

## Real-data verification

- [ ] Not yet tested on real data (`spec$status` should still say `"draft"` or `"ready_for_real_data_test"`)
- [ ] Tested on real data externally - see notes below, `spec$status` updated to `"verified"` accordingly

<paste verification summary here once available, or leave for a follow-up PR via the verify-variable workflow>
