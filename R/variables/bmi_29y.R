# ==========================================================================
# Derived variable: bmi_29y
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
  id = "bmi_29y",
  label = "Body mass index (kg/m^2) at the 29y sweep",
  category = "health",
  github_issue = 5,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c("bcs2000"), # 29y
  source_vars = c("htmetre2", "wtkilos2", "htmetres", "wtkilos"),
  notes = paste(
    "Issue #5: 'BMI at each age', one sibling variable per sweep - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. 29y has no",
    "pre-derived BMI, so it's computed from raw height/weight, both already",
    "in metres/kilograms. bcs2000 has two independent height+weight pairs:",
    "htmetre2/wtkilos2 ('CMs height:metres'/'CMs weight:kilos', the cohort",
    "member's own self-report) and htmetres/wtkilos ('(Proxy) CM height",
    "without shoes - metres'/'(Proxy) CM current weight - kilos', answered",
    "by someone else on the CM's behalf). Per the confirmed design,",
    "self-report is preferred and the proxy pair is used only when either",
    "self-reported value is missing/invalid. None of these four variables",
    "document an SPSS user-missing range or value labels in the dictionary",
    "(value_labels_json is empty for all four), so - consistent with every",
    "other sibling in this family - any non-positive value on either input",
    "is treated as missing, since a real height/weight can never be zero or",
    "negative."
  )
)

derive <- function(data) {
  positive_or_na <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)
  bmi_from <- function(height_m, weight_kg) weight_kg / (height_m^2)

  self_report_bmi <- bmi_from(positive_or_na(data$htmetre2), positive_or_na(data$wtkilos2))
  proxy_bmi <- bmi_from(positive_or_na(data$htmetres), positive_or_na(data$wtkilos))

  data.frame(
    bcsid = data$bcsid,
    bmi_29y = ifelse(is.na(self_report_bmi), proxy_bmi, self_report_bmi)
  )
}
