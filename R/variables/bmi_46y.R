# ==========================================================================
# Derived variable: bmi_46y
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
  id = "bmi_46y",
  label = "Body mass index (kg/m^2) at the 46y sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("bcs_age46_main"), # 46y
  source_vars = c("BD10MBMI", "BD10BMI"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 46y",
    "already has two CLS pre-derived BMI values - BD10MBMI ('(Derived) Body",
    "mass index (based on nurse measurement)') and BD10BMI ('(Derived) Body",
    "mass index (based on self-reported data)'), both bcs_age46_main - so,",
    "per the confirmed design, this variable harmonises/renames those",
    "official values rather than recomputing from raw height/weight,",
    "preferring the nurse-measured value and falling back to self-report",
    "only when the measured value is missing/invalid. Both variables share",
    "the same missing-value scheme (spss_user_missing_values '-1.0 thru",
    "-8.0 and -9.0'; only -8.0 'Not enough information' carries an explicit",
    "label, but the documented range covers -9 through -1). Since a real",
    "BMI can never be zero or negative, any non-positive value is treated",
    "as missing rather than hand-enumerating each individual sentinel in",
    "that range."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)

  measured <- positive_or_na(data$BD10MBMI)
  self_report <- positive_or_na(data$BD10BMI)

  data.frame(
    bcsid = data$bcsid,
    bmi_46y = ifelse(is.na(measured), self_report, measured)
  )
}
