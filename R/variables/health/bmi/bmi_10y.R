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
  label = "Body mass index (kg/m2) at age 10, measured",
  category = "health",
  github_issue = 28,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("sn3723"),
  source_vars = c("meb17", "meb19.1"),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "SOURCE AND UNITS - THE TRAP AT THIS SWEEP. sn3723 meb17 is",
    "\"CHILD'S HEIGHT IN MMS\" and meb19.1 is",
    "\"CHILD'S WEIGHT IN 10THS OF A KILOGRAM\". Neither is in the units the",
    "rest of the family uses: a value of 1385 is 1.385 m, not 1385 m or",
    "13.85 cm, and a value of 312 is 31.2 kg, not 312 kg. Height is",
    "therefore divided by 1000 and weight by 10. Taking either column at",
    "face value would produce a BMI wrong by several orders of magnitude,",
    "and - because it would still be a finite positive number - it would not",
    "look obviously broken in the output.",
    "",
    "DOTTED VARIABLE NAME. meb19.1 contains a literal dot, so it must be",
    "reached as data[[\"meb19.1\"]]; data$meb19.1 does not work. This is the",
    "case DATA_KNOWLEDGE.md records under 'Variable names containing dots' -",
    "load_tab() reads with check.names = FALSE so the deposited name",
    "survives intact rather than being mangled.",
    "",
    "MISSING VALUES. Both variables declare a single documented code, -8",
    "'Out of range', with an SPSS user-missing range of '-8.0 thru None'.",
    "Per DATA_KNOWLEDGE.md the derivation does not rely on that being the",
    "whole story: it keeps only values inside a plausible physical envelope",
    "for a 10-year-old (height 1.00-1.80 m, weight 12-100 kg) and lets",
    "everything else - -8, any undocumented sentinel, and any value that",
    "survived a unit error - fall through to NA. The guard is applied AFTER",
    "converting to metres and kilograms so the envelope is stated in the",
    "same units as every other sibling.",
    "",
    "MEASURED, NOT SELF-REPORTED. These come from the 10-year medical",
    "examination, so this sibling and the 42m/0y ones are measured, whereas",
    "26y onwards are self-reported. Self-reported adult height tends to be",
    "over-reported and weight under-reported, which biases self-reported BMI",
    "downwards; a change in BMI between 16y and 26y is therefore partly a",
    "change of instrument, not only of body composition.",
    "",
    "BMI IN CHILDHOOD. weight/height^2 is reported for consistency with the",
    "rest of the family, but at age 10 it should be used age- and",
    "sex-standardised rather than against adult cut-offs. No cut-off",
    "classification is emitted.",
    "",
    "VERIFIED against real data on 2026-08-04 (harness 5.0.0,",
    "runner 4.5.3, commit cb4c6ddc). Every harness check passed:",
    "columns_exact, identifier_present, identifier_unique,",
    "no_nan_or_infinite, no_residual_sentinels, not_all_missing,",
    "output_written, reproducible, workspace_writes_confined.",
    "n = 5,590 non-missing, mean 16.88, sd 2.12, median 16.53.",
    "The millimetre / tenth-of-a-kilogram scaling of the sn3723",
    "measures is handled correctly: leaving it unconverted would put",
    "the mean orders of magnitude out."
  )
)

derive <- function(data) {
  # Keep only values inside a plausible physical envelope; everything else,
  # including every documented and undocumented sentinel, becomes NA.
  plausible <- function(x, lo, hi) {
    x <- suppressWarnings(as.numeric(x))
    ifelse(!is.na(x) & x >= lo & x <= hi, x, NA_real_)
  }

  # meb17 is millimetres; meb19.1 is tenths of a kilogram. Convert first,
  # then guard, so the envelope is in metres/kilograms like every sibling.
  height_m <- plausible(suppressWarnings(as.numeric(data[["meb17"]])) / 1000, 1.00, 1.80)
  weight_kg <- plausible(suppressWarnings(as.numeric(data[["meb19.1"]])) / 10, 12, 100)

  data.frame(
    bcsid = data$bcsid,
    bmi_10y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
