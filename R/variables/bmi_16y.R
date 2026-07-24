# ==========================================================================
# Derived variable: bmi_16y
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
  id = "bmi_16y",
  label = "Body mass index (kg/m^2) at the 16y sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("bcs7016x"), # 16y
  source_vars = c("rd2.1", "rd4.1", "ha1.2", "ha1.1"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 16y has no",
    "pre-derived BMI, so it's computed from raw height/weight, both already",
    "in metres/kilograms. bcs7016x has two independent height+weight pairs:",
    "rd2.1/rd4.1 ('Height of teen (metres)'/'Weight of teen in (kg)', the",
    "nurse/interviewer-measured pair) and ha1.1/ha1.2 ('Self reported",
    "present weight (kgs)'/'Self reported present height (metres)', the",
    "self-report pair). Per the confirmed design, the measured pair is",
    "preferred and the self-report pair is used only when either measured",
    "value is missing/invalid. Both pairs document the same sentinel scheme",
    "(-2.0 'Not stated', -1.0 'No questionnaire', spss_user_missing_values",
    "'... thru -1.0'); since real height/weight can never be zero or",
    "negative, any non-positive value on either input is treated as missing",
    "rather than hand-enumerating the exact sentinel list."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)
  bmi_from <- function(height_m, weight_kg) weight_kg / (height_m^2)

  measured_bmi <- bmi_from(positive_or_na(data$rd2.1), positive_or_na(data$rd4.1))
  self_report_bmi <- bmi_from(positive_or_na(data$ha1.2), positive_or_na(data$ha1.1))

  data.frame(
    bcsid = data$bcsid,
    bmi_16y = ifelse(is.na(measured_bmi), self_report_bmi, measured_bmi)
  )
}
