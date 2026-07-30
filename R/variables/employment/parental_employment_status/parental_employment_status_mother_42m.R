# ==========================================================================
# Derived variable: parental_employment_status_mother_42m
# --------------------------------------------------------------------------
# Save this as R/variables/<category>/<family>/<id>.R - see
# R/variables/README.md. <category> must equal spec$category below, and
# <id> must equal spec$id; both are checked at build time.
#
# This file is self-contained and is the single source of truth for this
# variable - a future front end will display this file's raw source as
# "how this variable was made". R/runner.R discovers and runs it
# automatically; don't source or call it manually anywhere else.
#
# Rules for this file:
#   - Never read from disk (no read.csv/read.delim/file paths). All input
#     arrives via the `data` argument to derive().
#   - Never write to disk. Return the derived column; the runner writes it.
#   - Never reference bcs70/ directly - it must stay read-only.
# ==========================================================================

spec <- list(
  id = "parental_employment_status_mother_42m",
  label = "Mother's employment status at age 42 months (1972): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("f690"),
  source_vars = c("c0039"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - see",
    "parental_employment_status_father_0y.R for the full family-wide note",
    "on sweep coverage and the same-label-different-concept trap this",
    "family avoids.",
    "",
    "SOURCE. 42m f690 c0039 'Is mother employed', coded 1 'Full time', 2",
    "'Part time', 3 'No', with -3 'Not stated', -2 'Not known', -1 'Not",
    "applicable' documented as non-substantive. Unlike the father",
    "sibling's c0038, this item already distinguishes full-time from",
    "part-time work rather than a bare Yes/No - collapsed here to match",
    "the family's shared two-category vocabulary (see CODING below).",
    "",
    "CODING. c0039 == 1 or c0039 == 2 (full-time or part-time work) ->",
    "'Employed'; c0039 == 3 ('No') -> 'Not employed'; anything else (the",
    "three documented negative codes, or any undocumented value) -> NA.",
    "",
    "VERIFIED against real data on 2026-07-30 (harness run 306bc489, branch",
    "variable/parental_employment_status, schema 5). Aggregate: n = 2,290,",
    "0.99% missing, both 'Employed'/'Not employed' levels represented (no",
    "degenerate all-one-category output). All harness checks passed -",
    "columns_exact, identifier_present, identifier_unique, not_all_missing,",
    "reproducible, workspace_writes_confined - including the cross-variable",
    "integration run across all 22 variables in this build, which confirms",
    "this sibling joins cleanly on bcsid alongside the rest of the family.",
    "No row-level or respondent-level data was inspected, only this",
    "aggregate harness summary."
  )
)

derive <- function(data) {
  status <- data$c0039
  employment_status_mother <- ifelse(
    status %in% c(1, 2), "Employed",
    ifelse(status == 3, "Not employed", NA_character_)
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_mother_42m = employment_status_mother,
    stringsAsFactors = FALSE
  )
}
