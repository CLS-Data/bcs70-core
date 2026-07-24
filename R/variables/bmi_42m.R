# ==========================================================================
# Derived variable: bmi_42m
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
  id = "bmi_42m",
  label = "Body mass index (kg/m^2) at the 42m sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("f690"), # 42m
  source_vars = c("c0087", "c0088"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 42m has no",
    "pre-derived BMI, so it's computed here from raw height/weight: c0087",
    "('Height in centimetres', f690) and c0088 ('Weight in Kilos', f690) -",
    "height converted to metres before applying weight_kg / height_m^2, so",
    "the output is comparable across every sweep in this family regardless",
    "of the raw units each sweep used. Documented sentinels are -4.0",
    "'Refused', -3.0 'Not stated', -2.0 'Not known', plus an unlabelled 0.0;",
    "since a real height/weight can never be zero or negative, any",
    "non-positive value on either input is treated as missing rather than",
    "hand-enumerating each individual sentinel."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)

  height_m <- positive_or_na(data$c0087) / 100
  weight_kg <- positive_or_na(data$c0088)

  data.frame(
    bcsid = data$bcsid,
    bmi_42m = weight_kg / (height_m^2)
  )
}
