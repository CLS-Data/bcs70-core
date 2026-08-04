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
  label = "Body mass index (kg/m2) at age 16, measured where available, otherwise self-reported",
  category = "health",
  github_issue = 28,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs7016x"),
  source_vars = c("rd2.1", "rd4.1", "ha1.1", "ha1.2"),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "TWO MEASUREMENTS EXIST AT THIS SWEEP, AND THEY ARE NOT THE SAME THING.",
    "bcs7016x carries both:",
    "  - rd2.1 'Height of teen (metres)' and rd4.1 'Weight of teen in (kg)',",
    "    from the medical examination - i.e. MEASURED by an examiner;",
    "  - ha1.2 'Self reported present height (metres)' and ha1.1 'Self",
    "    reported present weight (kgs)', from the health questionnaire.",
    "Both are already in metres and kilograms, so no unit conversion is",
    "needed on either pair.",
    "",
    "WHICH IS USED. Measured first, self-reported only where the measured",
    "value is absent or implausible. Measured is the better instrument, but",
    "the 16y medical examination has markedly lower coverage than the",
    "questionnaire, and using it alone would discard a large number of",
    "otherwise usable cases. The consequence is that this column has MIXED",
    "PROVENANCE within a single sweep - some rows measured, some",
    "self-reported - which matters because self-reported height is typically",
    "over-reported and self-reported weight under-reported, biasing",
    "self-reported BMI downwards. Height and weight are resolved",
    "INDEPENDENTLY, so a row may legitimately combine a measured height with",
    "a self-reported weight. If an analysis needs a single, clean",
    "instrument, use rd2.1/rd4.1 directly rather than this column. This is",
    "the main design decision at this sweep and the thing to challenge in",
    "review.",
    "",
    "DOTTED VARIABLE NAMES. All four names contain literal dots, so they",
    "must be reached as data[[\"rd2.1\"]] and so on; data$rd2.1 does not",
    "work. This is DATA_KNOWLEDGE.md's 'Variable names containing dots'",
    "entry, and bcs7016x is the file it names.",
    "",
    "DO NOT CARRY THESE NAMES ACROSS SWEEPS. DATA_KNOWLEDGE.md records that",
    "raw names are not unique across the corpus and that colliding names are",
    "not necessarily related - c6.8 is tenure at 16y but a maternal working",
    "hours item at 10y. Each sibling in this family was confirmed against",
    "its own sweep's dictionary.",
    "",
    "MISSING VALUES. All four declare -2 'Not stated' and -1 'No",
    "questionnaire', with an SPSS user-missing range running to -1 from the",
    "smallest representable double. Per DATA_KNOWLEDGE.md the derivation",
    "does not deny-list those codes; it keeps only values inside a plausible",
    "physical envelope for a 16-year-old (height 1.20-2.10 m, weight",
    "25-200 kg) and lets everything else fall through to NA. That envelope",
    "is also what makes the measured-then-self-reported fallback safe: an",
    "implausible measured value is skipped in favour of a plausible",
    "self-reported one rather than being preferred just because it exists.",
    "",
    "BMI IN ADOLESCENCE. weight/height^2 is reported for consistency with",
    "the rest of the family, but at 16 it should be used age- and",
    "sex-standardised rather than against adult cut-offs. No cut-off",
    "classification is emitted.",
    "",
    "VERIFIED against real data on 2026-08-04 (harness 5.0.0,",
    "runner 4.5.3, commit cb4c6ddc). Every harness check passed:",
    "columns_exact, identifier_present, identifier_unique,",
    "no_nan_or_infinite, no_residual_sentinels, not_all_missing,",
    "output_written, reproducible, workspace_writes_confined.",
    "n = 7,955 non-missing, mean 21.11, sd 3.09, median 20.67."
  )
)

derive <- function(data) {
  # Keep only values inside a plausible physical envelope; everything else,
  # including every documented and undocumented sentinel, becomes NA.
  plausible <- function(x, lo, hi) {
    x <- suppressWarnings(as.numeric(x))
    ifelse(!is.na(x) & x >= lo & x <= hi, x, NA_real_)
  }

  # Take the measured value, falling back to the self-reported one only
  # where the measured one is missing or outside the envelope.
  coalesce_plausible <- function(preferred, fallback) {
    ifelse(is.na(preferred), fallback, preferred)
  }

  # Medical examination (measured). Both already metres / kilograms.
  height_measured <- plausible(data[["rd2.1"]], 1.20, 2.10)
  weight_measured <- plausible(data[["rd4.1"]], 25, 200)

  # Health questionnaire (self-reported). Same units.
  height_self <- plausible(data[["ha1.2"]], 1.20, 2.10)
  weight_self <- plausible(data[["ha1.1"]], 25, 200)

  height_m <- coalesce_plausible(height_measured, height_self)
  weight_kg <- coalesce_plausible(weight_measured, weight_self)

  data.frame(
    bcsid = data$bcsid,
    bmi_16y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
