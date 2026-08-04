# ==========================================================================
# Derived variable: bmi_0y
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
  id = "bmi_0y",
  label = "Body mass index (kg/m2) at 22 months, measured (0y sweep, 22-month sub-sample)",
  category = "health",
  github_issue = 28,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs7072b"),
  source_vars = c("b0093", "b0095"),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. Three sweeps",
    "are deliberately absent: 5y has height (f699c f102 'Childs Height in",
    "Cms') and head circumference but NO weight; 21y has neither; 38y has",
    "neither (its only weight variables are the birth weights of the cohort",
    "member's CHILDREN, b8poun*/b8kilo*/b8gram*, not the cohort member).",
    "",
    "READ THE AGE LABEL, NOT THE SWEEP NAME. This sibling is named bmi_0y",
    "because the family naming rule requires the suffix to match the",
    "bcs70/<sweep>/ folder exactly, and its source file sits under 0y. It is",
    "NOT BMI at birth. bcs7072b is described in master_file_info_lookup.csv",
    "as the '22-month Sub-sample', a separate follow-up of 2,457 children",
    "deposited alongside the birth data under the same study number (2666).",
    "So this column is BMI at roughly 22 months, on a sub-sample only - N is",
    "in the low thousands, not the ~17,000 of the birth sweep, and it must",
    "not be pooled with bcs7072a birth variables as if it were whole-cohort.",
    "",
    "SOURCE AND UNITS. b0095 'CHILDS HEIGHT IN METRES AND CENTIMETRES' and",
    "b0093 'CHILDS WEIGHT IN KILOS AND GRAMMES'. Those labels are ambiguous",
    "on their own - 'metres and centimetres' could mean a decimal metre",
    "value or an integer centimetre one, a factor of 100 apart - so the",
    "coding was confirmed against the study's own user guide",
    "(bcs70/0y/metadata/2666/pdfs/2666userguide.pdf, the 22-month survey",
    "section) rather than assumed. It documents b0095 as 'Child's standing",
    "height without shoes in metres and centimetres', valid n = 2,296,",
    "range 0.44 to 1.07, median 0.83; and b0093 as weight, valid n = 2,348,",
    "range 6.40 to 20.41, median 11.86. Both are therefore already decimal",
    "metres and decimal kilograms, and need no conversion. The guide also",
    "notes weights were recorded in lb/oz or kg at the clinic and converted",
    "to metric by the coders.",
    "",
    "STANDING HEIGHT, NOT RECUMBENT LENGTH. The same examination also",
    "recorded b0096, recumbent length in metres (valid n = 1,886, range 0.41",
    "to 1.07). Standing height is used here because it has the better",
    "coverage of the two and is the measure the later sweeps continue with.",
    "The two are not interchangeable - recumbent length runs systematically",
    "longer - so they are deliberately NOT combined.",
    "",
    "MISSING VALUES. Following DATA_KNOWLEDGE.md ('Documented missing-value",
    "codes are inconsistent, and sometimes absent'), this script does not",
    "deny-list sentinels. Both variables document -6 'UNABLE TO EXAMINE',",
    "-3 'NOT STATED', -2 'NOT KNOWN', -1 'NOT APPLICABLE' and 0 'THE CHILD",
    "REFUSED', but instead of naming those codes the derivation keeps only",
    "values inside a plausible physical envelope for a 22-month-old and lets",
    "everything else - documented sentinel, undocumented sentinel, or unit",
    "error - fall through to NA. The envelope (height 0.40-1.20 m, weight",
    "3-30 kg) is set generously wider than the guide's observed ranges so it",
    "excludes sentinels and mis-scaled values without trimming genuine",
    "outliers.",
    "",
    "BMI IN INFANCY. weight/height^2 is reported here for consistency with",
    "the rest of the family, but at 22 months it is not interpretable",
    "against adult BMI cut-offs and should be used age-standardised (e.g. as",
    "a z-score against a growth reference) rather than raw. No cut-off",
    "classification is emitted.",
    "",
    "VERIFIED against real data on 2026-08-04 (harness 5.0.0,",
    "runner 4.5.3, commit cb4c6ddc). Every harness check passed:",
    "columns_exact, identifier_present, identifier_unique,",
    "no_nan_or_infinite, no_residual_sentinels, not_all_missing,",
    "output_written, reproducible, workspace_writes_confined.",
    "n = 2,225 non-missing, mean 17.32, sd 2.81, median 17.11.",
    "Mean and median sit at the infant BMI peak, i.e. consistent with",
    "the 22-month age this file actually measures and NOT with birth",
    "(a newborn's BMI is near 13). N also matches the user guide's",
    "valid n for the two source variables. Both confirm the reading",
    "of bcs7072b recorded above."
  )
)

derive <- function(data) {
  # Keep only values inside a plausible physical envelope; everything else,
  # including every documented and undocumented sentinel, becomes NA.
  plausible <- function(x, lo, hi) {
    x <- suppressWarnings(as.numeric(x))
    ifelse(!is.na(x) & x >= lo & x <= hi, x, NA_real_)
  }

  # Already decimal metres and decimal kilograms - see notes.
  height_m <- plausible(data$b0095, 0.40, 1.20)
  weight_kg <- plausible(data$b0093, 3, 30)

  data.frame(
    bcsid = data$bcsid,
    bmi_0y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
