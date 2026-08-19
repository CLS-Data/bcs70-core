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
  label = "Body mass index (kg/m2) at 42 months, measured",
  category = "health",
  github_issue = 28,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("f690"),
  source_vars = c("c0087", "c0088"),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "SOURCE AND UNITS. f690 ('Birth and 42 Month Data') c0087 'Height in",
    "centimetres' and c0088 'Weight in Kilos'. Unlike the 22-month and 10y",
    "measurements, these labels state their units outright, so height is",
    "simply divided by 100 to reach metres and weight is used as deposited.",
    "Like 22 months this is a sub-sample follow-up rather than the whole",
    "cohort, so expect an N in the low thousands.",
    "",
    "MISSING VALUES. Both variables document -4 'Refused', -3 'Not stated'",
    "and -2 'Not known', plus a value 0 carrying an EMPTY label - an",
    "undocumented code the dictionary records but does not explain. Rather",
    "than deny-listing those four codes, and per DATA_KNOWLEDGE.md's warning",
    "that sentinel schemes vary per variable and that undocumented ones",
    "still occur, the derivation keeps only values inside a plausible",
    "physical envelope for a 3.5-year-old (height 0.70-1.30 m, weight",
    "5-35 kg) and lets everything else fall through to NA. That covers the",
    "unexplained 0 without having to decide what it means.",
    "",
    "BMI IN EARLY CHILDHOOD. weight/height^2 is reported for consistency",
    "with the rest of the family, but at 3.5 years it is not interpretable",
    "against adult BMI cut-offs and should be used age-standardised rather",
    "than raw. No cut-off classification is emitted.",
    "",
    "VERIFIED against real data on 2026-08-04 (harness 5.0.0,",
    "runner 4.5.3, commit cb4c6ddc). Every harness check passed:",
    "columns_exact, identifier_present, identifier_unique,",
    "no_nan_or_infinite, no_residual_sentinels, not_all_missing,",
    "output_written, reproducible, workspace_writes_confined.",
    "n = 2,150 non-missing, mean 15.91, sd 1.87, median 15.80.",
    "Lower than bmi_0y and bmi_10y, as expected between the infant",
    "peak and the adiposity rebound."
  )
)

derive <- function(data) {
  # Keep only values inside a plausible physical envelope; everything else,
  # including every documented and undocumented sentinel, becomes NA.
  plausible <- function(x, lo, hi) {
    x <- suppressWarnings(as.numeric(x))
    ifelse(!is.na(x) & x >= lo & x <= hi, x, NA_real_)
  }

  # c0087 is centimetres; guard in metres after converting, so that a
  # sentinel such as -3 or 0 can never survive the division.
  height_m <- plausible(suppressWarnings(as.numeric(data$c0087)) / 100, 0.70, 1.30)
  weight_kg <- plausible(data$c0088, 5, 35)

  data.frame(
    bcsid = data$bcsid,
    bmi_42m = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
