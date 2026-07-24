# ==========================================================================
# Derived variable: bmi_10y
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
  id = "bmi_10y",
  label = "Body mass index (kg/m^2) at the 10y sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("sn3723"), # 10y
  source_vars = c("meb17", "meb19.1"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 10y has no",
    "pre-derived BMI, so it's computed here from raw height/weight: meb17",
    "('CHILD'S HEIGHT IN MMS', sn3723) and meb19.1 ('CHILD'S WEIGHT IN 10THS",
    "OF A KILOGRAM', sn3723) - both converted to metres/kilograms before",
    "applying weight_kg / height_m^2, so the output is comparable across",
    "every sweep in this family regardless of the raw units each sweep used.",
    "Both source variables document only one negative sentinel each",
    "(-8.0 = 'Out of range', spss_user_missing_values '-8.0 thru None'), but",
    "since a real height/weight can never be zero or negative, any",
    "non-positive value on either input is treated as missing rather than",
    "hand-enumerating each sweep's exact sentinel list."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)

  height_m <- positive_or_na(data$meb17) / 1000
  weight_kg <- positive_or_na(data$meb19.1) / 10

  data.frame(
    bcsid = data$bcsid,
    bmi_10y = weight_kg / (height_m^2)
  )
}
