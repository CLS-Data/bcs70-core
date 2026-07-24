# ==========================================================================
# Derived variable: bmi_42y
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
  id = "bmi_42y",
  label = "Body mass index (kg/m^2) at the 42y sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("bcs70_2012_derived"), # 42y
  source_vars = c("BD9BMI"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 42y",
    "already has a CLS pre-derived BMI - BD9BMI ('(Derived) Body mass",
    "index', bcs70_2012_derived) - so, per the confirmed design, this",
    "variable harmonises/renames that official value rather than",
    "recomputing it from raw height/weight, respecting CLS's own",
    "missing-value scheme (spss_user_missing_values '-1.0 thru -8.0 and",
    "-9.0'; only -8.0 'Not enough information' carries an explicit label,",
    "but the documented range covers -9 through -1). Since a real BMI can",
    "never be zero or negative, any non-positive value is treated as",
    "missing rather than hand-enumerating each individual sentinel in that",
    "range."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)

  data.frame(
    bcsid = data$bcsid,
    bmi_42y = positive_or_na(data$BD9BMI)
  )
}
