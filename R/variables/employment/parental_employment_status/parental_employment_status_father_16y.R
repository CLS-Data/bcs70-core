# ==========================================================================
# Derived variable: parental_employment_status_father_16y
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
  id = "parental_employment_status_father_16y",
  label = "Father's employment status at age 16 (1986): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("bcs7016x"),
  source_vars = c("c6.16"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - see",
    "parental_employment_status_father_0y.R for the full family-wide note",
    "on sweep coverage and the same-label-different-concept trap this",
    "family avoids.",
    "",
    "THIS SWEEP HAS NO MOTHER SIBLING. bcs7016x deposits t12.2 'Employment",
    "status of mother', but that is the job-type-conditional-on-employment",
    "classification described in the family-wide note (self-employed with",
    "N employees / employee at a given supervisory grade, values 1-7,",
    "with NO 'not employed' category) - using it would misclassify every",
    "non-working mother as missing. The only other",
    "mother-employment-adjacent item at 16y is oe1.2 'Source of",
    "income-mother's employment' (Yes/No Response), which asks whether",
    "her earnings are a household income source - a related but distinct",
    "question from whether she is currently employed at all (a mother who",
    "is employed but whose earnings are not counted as a distinct 'source",
    "of income' in this household-finance question would be misrecorded",
    "as not employed) - so it is not used as a substitute. No mother",
    "sibling is scaffolded at 16y for this reason.",
    "",
    "SOURCE (father). 16y bcs7016x c6.16 'Is father employed or",
    "unemployed?', coded 1 'Employed', 2 'Unemployed', with -2 'Not",
    "stated' and -1 'No questionnaire' documented as non-substantive (the",
    "dictionary records the missing range as an open-ended floating-point",
    "lower bound, '-1.7976931348623155e+308 thru -1.0', which the",
    "allow-list approach below makes immaterial - see DATA_KNOWLEDGE.md on",
    "inconsistent missing-value documentation).",
    "",
    "CODING. Following the family-wide convention: c6.16 == 1 ->",
    "'Employed'; c6.16 == 2 -> 'Not employed'; anything else (both",
    "documented negative codes, or any undocumented value) -> NA.",
    "",
    "NOT YET VERIFIED against real data - see CONTRIBUTING.md."
  )
)

derive <- function(data) {
  status <- data[["c6.16"]]
  employment_status_father <- ifelse(
    status == 1, "Employed",
    ifelse(status == 2, "Not employed", NA_character_)
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_father_16y = employment_status_father,
    stringsAsFactors = FALSE
  )
}
