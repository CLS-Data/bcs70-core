# ==========================================================================
# Derived variable: parental_employment_status_father_42m
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
  id = "parental_employment_status_father_42m",
  label = "Father's employment status at age 42 months (1972): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("f690"),
  source_vars = c("c0038"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - see",
    "parental_employment_status_father_0y.R for the full family-wide note",
    "on sweep coverage and the same-label-different-concept trap this",
    "family avoids.",
    "",
    "SOURCE. 42m f690 c0038 'Is father currently employed', coded 1",
    "'Yes', 2 'No', with -3 'Not stated', -2 'Not known', -1 'Not",
    "applicable' documented as non-substantive. The same file also",
    "carries c0035 'Is father self employed' (Yes/No) - NOT used here",
    "because it is a narrower, DIFFERENT question that presupposes",
    "employment (self-employed vs employee among those already working),",
    "the same kind of job-type-conditional concept the family-wide note",
    "excludes at other sweeps; c0038 is the direct employed/not-employed",
    "item.",
    "",
    "CODING. Following the family-wide convention: c0038 == 1 ->",
    "'Employed'; c0038 == 2 -> 'Not employed'; anything else (the three",
    "documented negative codes, or any undocumented value) -> NA.",
    "",
    "NOT YET VERIFIED against real data - see CONTRIBUTING.md."
  )
)

derive <- function(data) {
  status <- data$c0038
  employment_status_father <- ifelse(
    status == 1, "Employed",
    ifelse(status == 2, "Not employed", NA_character_)
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_father_42m = employment_status_father,
    stringsAsFactors = FALSE
  )
}
