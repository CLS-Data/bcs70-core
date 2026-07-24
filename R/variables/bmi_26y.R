# ==========================================================================
# Derived variable: bmi_26y
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
  id = "bmi_26y",
  label = "Body mass index (kg/m^2) at the 26y sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("bcs96x"), # 26y
  source_vars = c("b960436", "b960443"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 26y has no",
    "pre-derived BMI, so it's computed from raw height/weight: b960436",
    "('Height - metres', bcs96x) and b960443 ('Weight - kgs', bcs96x), both",
    "already in the units needed for weight_kg / height_m^2 (bcs96x also",
    "carries b960437 'Height - cms', not used here since b960436 already",
    "gives metres directly). Documented sentinels are -7.0 'Out of range',",
    "-2.0 'Does Not Apply', -1.0 'Not Answered' (spss_user_missing_values",
    "'-7.0 thru None'); since real height/weight can never be zero or",
    "negative, any non-positive value on either input is treated as missing",
    "rather than hand-enumerating the exact sentinel list."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)

  height_m <- positive_or_na(data$b960436)
  weight_kg <- positive_or_na(data$b960443)

  data.frame(
    bcsid = data$bcsid,
    bmi_26y = weight_kg / (height_m^2)
  )
}
