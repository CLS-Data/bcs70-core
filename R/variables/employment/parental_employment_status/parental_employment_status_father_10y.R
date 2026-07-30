# ==========================================================================
# Derived variable: parental_employment_status_father_10y
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
  id = "parental_employment_status_father_10y",
  label = "Father's employment status at age 10 (1980): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("sn3723"),
  source_vars = c("c2.1", "c2.2", "c2.3", "c2.4", "c2.5", "c2.7", "c2.8"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - see",
    "parental_employment_status_father_0y.R for the full family-wide note",
    "on sweep coverage and the same-label-different-concept trap this",
    "family avoids.",
    "",
    "WHY THIS SIBLING DOES NOT USE c4.1a/c4.1b ('FATHER'S CORRECTED",
    "EMPLOYMENT STATUS'). Despite the label, c4.1a/b is the",
    "job-type-conditional-on-employment classification described in the",
    "family-wide note (self-employed with N employees / employee at a",
    "given supervisory grade, values 1-7, with NO 'not employed' category",
    "at all) - using it here would misclassify every unemployed or",
    "non-working father as missing. Instead this sibling uses the",
    "c2.1-c2.8 'FATHER'S EMPLOYMENT' item set, a single checklist of",
    "mutually exclusive employment-situation flags (inferred from the",
    "label pattern - a 'reason not paid job' follow-up (c2.6) and a 'no",
    "male head in house' catch-all (c2.8) only make sense as siblings of",
    "one classification, not eight independent yes/no questions someone",
    "could tick several of):",
    "  c2.1  'REGULAR PAID JOB'            (1 = Yes, else unlabelled/blank)",
    "  c2.2  'WORKS OCCASIONALLY'          (1 = Yes, else unlabelled/blank)",
    "  c2.3  'SEEKING WORK'                (1 = Yes, else unlabelled/blank)",
    "  c2.4  'LOOKS AFTER HOME'            (1 = Yes, else unlabelled/blank)",
    "  c2.5  'NOT IN PAID JOB'             (1 = Yes, else unlabelled/blank)",
    "  c2.6  'REASON NOT PAID JOB'         (follow-up detail, not used here)",
    "  c2.7  'OTHER EMPLOYMENT SITUATION'  (1 = Yes, else unlabelled/blank)",
    "  c2.8  'NO MALE HEAD IN HOUSE'       (1 = Yes, else unlabelled/blank)",
    "None of these declares a documented spss_user_missing_values range -",
    "the dictionary only labels the value 1 ('Yes') for each flag, so",
    "anything else (0, blank, NA) means 'this box was not ticked', not a",
    "missing sentinel to strip.",
    "",
    "CODING, IN PRECEDENCE ORDER (checked in this order because c2.8",
    "overrides everything - if there is no father in the household at",
    "all, the concept 'is the father employed' is not applicable",
    "regardless of what else got ticked):",
    "  1. c2.8 == 1 ('no male head in house') -> NA (not applicable)",
    "  2. c2.1 == 1 or c2.2 == 1 (regular or occasional paid job) ->",
    "     'Employed'",
    "  3. c2.3 == 1, c2.4 == 1 or c2.5 == 1 (seeking work / looks after",
    "     home / not in a paid job) -> 'Not employed'",
    "  4. otherwise (includes c2.7 == 1 'other employment situation',",
    "     which is genuinely unclassifiable against employed/not-employed,",
    "     and rows where none of the checklist was ticked at all, e.g.",
    "     not asked) -> NA",
    "",
    "NOT YET VERIFIED against real data - see CONTRIBUTING.md."
  )
)

derive <- function(data) {
  no_father <- data[["c2.8"]] == 1
  employed <- data[["c2.1"]] == 1 | data[["c2.2"]] == 1
  not_employed <- data[["c2.3"]] == 1 | data[["c2.4"]] == 1 | data[["c2.5"]] == 1

  employment_status_father <- ifelse(
    !is.na(no_father) & no_father, NA_character_,
    ifelse(!is.na(employed) & employed, "Employed",
      ifelse(!is.na(not_employed) & not_employed, "Not employed", NA_character_)
    )
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_father_10y = employment_status_father,
    stringsAsFactors = FALSE
  )
}
