# ==========================================================================
# Derived variable: bmi_51y
# --------------------------------------------------------------------------
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
  id = "bmi_51y",
  label = "Body mass index (kg/m^2) at the 51y sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("bcs11_age51_main"), # 51y
  source_vars = c("bd11bmi"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 51y",
    "already has a CLS pre-derived BMI - bd11bmi ('(Derived) Body mass",
    "index (based on self-reported data)', bcs11_age51_main) - so, per the",
    "confirmed design, this variable harmonises/renames that official value",
    "rather than recomputing it from raw height/weight, respecting CLS's",
    "own missing-value scheme (spss_user_missing_values '-8.0 thru None',",
    "i.e. -8.0 and below; only -8.0 'Not enough information' is labelled).",
    "Unlike every other sweep in this family, 51y has no nurse-measured",
    "companion variable - the 2021 sweep did not include an in-person",
    "measurement visit, only a self-report BMI, so there is no",
    "measured/self-report fallback pair to choose between here. Since a",
    "real BMI can never be zero or negative, any non-positive value is",
    "treated as missing rather than hand-enumerating the exact sentinel",
    "range."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)

  data.frame(
    bcsid = data$bcsid,
    bmi_51y = positive_or_na(data$bd11bmi)
  )
}
