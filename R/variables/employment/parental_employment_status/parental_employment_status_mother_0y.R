# ==========================================================================
# Derived variable: parental_employment_status_mother_0y
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
  id = "parental_employment_status_mother_0y",
  label = "Mother's employment status at cohort member's birth (1970): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("bcs7072a"),
  source_vars = c("a0019"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - see",
    "parental_employment_status_father_0y.R for the full family-wide note",
    "on sweep coverage, the same-label-different-concept trap this family",
    "avoids, and why only some role x sweep pairs are scaffolded. Summary",
    "repeated here: the family only exists for 0y, 5y, 10y, 16y and 42m",
    "(the childhood sweeps where the deposit asks about the RESIDENT",
    "PARENTS, not the cohort member's own employment), and even within",
    "that window only role x sweep pairs with a genuine",
    "employed/not-employed source variable are included - 5y father and",
    "16y mother are absent because no such variable exists for them (see",
    "the father-0y sibling's notes for the full explanation and the",
    "alternatives considered and rejected).",
    "",
    "SOURCE. 0y bcs7072a a0019 'Employment Status of Mother', coded 1",
    "'Employed', 2 'Unemployed', with only -3 'Not Stated' documented as",
    "non-substantive (unlike a0015 for the father, this variable documents",
    "no -2/-1 codes at all - DATA_KNOWLEDGE.md warns that a variable with",
    "a shorter documented sentinel set may still contain undocumented",
    "ones in the real file, so the allow-list below matters here as much",
    "as for the father sibling). The redundant 22-month sub-sample",
    "question (bcs7072b b0023 'IS THE CHILD'S MOTHER WORKING?',",
    "Yes-FT/Yes-PT/No) is not used for the same reason given in the",
    "father sibling: it is a different, later module, not the",
    "birth-survey reference point.",
    "",
    "CODING. Following the family-wide convention, this collapses to the",
    "shared two-category vocabulary: a0019 == 1 -> 'Employed'; a0019 == 2",
    "-> 'Not employed'; anything else (the documented -3, or any",
    "undocumented value) -> NA.",
    "",
    "VERIFIED against real data on 2026-07-30 (harness run 306bc489, branch",
    "variable/parental_employment_status, schema 5). Aggregate: n = 12,255,",
    "28.74% missing, both 'Employed'/'Not employed' levels represented (no",
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
  status <- data$a0019
  employment_status_mother <- ifelse(
    status == 1, "Employed",
    ifelse(status == 2, "Not employed", NA_character_)
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_mother_0y = employment_status_mother,
    stringsAsFactors = FALSE
  )
}
