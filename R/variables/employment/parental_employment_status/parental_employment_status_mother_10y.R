# ==========================================================================
# Derived variable: parental_employment_status_mother_10y
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
  id = "parental_employment_status_mother_10y",
  label = "Mother's employment status at age 10 (1980): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("sn3723"),
  source_vars = c("c2.9", "c2.10", "c2.11", "c2.12", "c2.13", "c2.15", "c2.16"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - see",
    "parental_employment_status_father_0y.R for the full family-wide note",
    "on sweep coverage and the same-label-different-concept trap this",
    "family avoids, and parental_employment_status_father_10y.R for the",
    "full reasoning behind using the c2.x checklist at this sweep rather",
    "than c4.2a/c4.2b ('MOTHER'S CORRECTED EMPLOYMENT STATUS', the",
    "job-type-conditional variable).",
    "",
    "SOURCE. This uses the mother's half of the same c2.1-c2.16",
    "'employment situation' checklist as the father sibling:",
    "  c2.9  'REGULAR PAID JOB'            (1 = Yes, else unlabelled/blank)",
    "  c2.10 'WORKS OCCASIONALLY'          (1 = Yes, else unlabelled/blank)",
    "  c2.11 'SEEKING WORK'                (1 = Yes, else unlabelled/blank)",
    "  c2.12 'LOOKS AFTER HOME'            (1 = Yes, else unlabelled/blank)",
    "  c2.13 'NOT IN PAID JOB'             (1 = Yes, else unlabelled/blank)",
    "  c2.14 'REASON NOT PAID JOB'         (follow-up detail, not used here)",
    "  c2.15 'OTHER EMPLOYMENT SITUATION'  (1 = Yes, else unlabelled/blank)",
    "  c2.16 'NO FEMALE HEAD IN HOUSE'     (1 = Yes, else unlabelled/blank)",
    "As with the father's flags, none declares a documented",
    "spss_user_missing_values range - only the value 1 ('Yes') is",
    "labelled, so anything else means 'not ticked', not a missing",
    "sentinel.",
    "",
    "CODING, IN PRECEDENCE ORDER (same structure as the father sibling):",
    "  1. c2.16 == 1 ('no female head in house') -> NA (not applicable)",
    "  2. c2.9 == 1 or c2.10 == 1 (regular or occasional paid job) ->",
    "     'Employed'",
    "  3. c2.11 == 1, c2.12 == 1 or c2.13 == 1 (seeking work / looks",
    "     after home / not in a paid job) -> 'Not employed'",
    "  4. otherwise (includes c2.15 == 1 'other employment situation',",
    "     and rows where nothing was ticked) -> NA",
    "",
    "NOT YET VERIFIED against real data - see CONTRIBUTING.md."
  )
)

derive <- function(data) {
  no_mother <- data[["c2.16"]] == 1
  employed <- data[["c2.9"]] == 1 | data[["c2.10"]] == 1
  not_employed <- data[["c2.11"]] == 1 | data[["c2.12"]] == 1 | data[["c2.13"]] == 1

  employment_status_mother <- ifelse(
    !is.na(no_mother) & no_mother, NA_character_,
    ifelse(!is.na(employed) & employed, "Employed",
      ifelse(!is.na(not_employed) & not_employed, "Not employed", NA_character_)
    )
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_mother_10y = employment_status_mother,
    stringsAsFactors = FALSE
  )
}
