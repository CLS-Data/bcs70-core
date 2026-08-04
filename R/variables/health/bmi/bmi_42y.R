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
  label = "Body mass index (kg/m2) at age 42, self-reported (height may be carried from an earlier sweep)",
  category = "health",
  github_issue = 28,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs70_2012_derived"),
  source_vars = c("BD9HGHTM", "BD9WGHTK"),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "SOURCE AND UNITS. bcs70_2012_derived BD9HGHTM '(Derived) Height in",
    "metres' and BD9WGHTK '(Derived) Weight in kilograms'. Both are already",
    "single columns in SI units, so unlike 26y/29y/34y there is no",
    "metric-vs-imperial reconciliation to do here: CLS has already collapsed",
    "the raw B9HTMEES/B9HTCMS/B9HTFEET/B9HTINES and B9WTKIS/B9WTSTE/B9WTPOD",
    "answers from bcs70_2012_flatfile into them.",
    "",
    "UPPER-CASE NAMES ARE DELIBERATE. DATA_KNOWLEDGE.md records that this",
    "sweep's files use upper case throughout and that load_tab() lower-cases",
    "ONLY the identifier column. BD9HGHTM/BD9WGHTK must therefore stay",
    "upper-case in source_vars and in derive().",
    "",
    "THE HEIGHT IS NOT NECESSARILY MEASURED AT THIS SWEEP. Appendix 1 of",
    "bcs70/42y/metadata/7473/pdfs/bcs70_2012_follow_up_derived_variables.pdf",
    "lists BD9HGHTM as derived from height variables spanning sweeps 6, 7",
    "AND 8 - height/htmetres/htcms/htfeet/htinches and height2/htmetre2/",
    "htcms2/htfeet2/htinche2 (age 29), b7height/b7htmees/b7htcms/b7htfeet/",
    "b7htines and bd7htun/bd7htmtr/bd7htcms/bd7htft/bd7htins (age 34), and",
    "b9height/b9htmees/b9htcms/b9htfeet/b9htines (age 42). In other words",
    "height is carried forward from an earlier sweep where the age-42 answer",
    "is missing, so bmi_42y may share a height with bmi_34y and bmi_29y for",
    "part of the sample. The same appendix shows BD9WGHTK is derived ONLY",
    "from the age-42 columns b9weigh/b9wtkis/b9wtste/b9wtpod, so weight is",
    "contemporaneous. Adult height is near-stable, so this affects the",
    "interpretation of height change far more than that of BMI - but it does",
    "mean this column is not a clean single-occasion measurement. Using the",
    "flatfile's contemporaneous B9HT* columns instead would trade that",
    "caveat for materially more missingness, and would no longer match the",
    "input CLS's own BD9BMI uses.",
    "",
    "WHY NOT THE DEPOSITED BD9BMI. This sweep deposits BD9BMI '(Derived)",
    "Body mass index', which the same appendix confirms is exactly",
    "bd9wghtk/bd9hghtm^2 - the identical calculation this script performs.",
    "It is not used because only 34y, 42y, 46y and 51y deposit a ready-made",
    "BMI at all, and the six earlier siblings must be computed from height",
    "and weight regardless; computing it the same way everywhere keeps one",
    "definition across all ten siblings. BD9BMI remains the best available",
    "CROSS-CHECK for this sweep - on real data bmi_42y should agree with it",
    "to rounding, and any systematic discrepancy is a bug here.",
    "",
    "MISSING VALUES. Both columns declare -8 'No information' with an SPSS",
    "user-missing range of '-1.0 thru -8.0 and -9.0'. Per DATA_KNOWLEDGE.md",
    "the derivation does not deny-list those codes: it keeps only values",
    "inside a plausible adult envelope (height 1.20-2.20 m, weight",
    "25-300 kg) and lets everything else fall through to NA.",
    "",
    "SELF-REPORTED, NOT MEASURED - see bmi_26y's notes on the instrument",
    "change between 16y and 26y.",
    "",
    "VERIFIED against real data on 2026-08-04 (harness 5.0.0,",
    "runner 4.5.3, commit cb4c6ddc). Every harness check passed:",
    "columns_exact, identifier_present, identifier_unique,",
    "no_nan_or_infinite, no_residual_sentinels, not_all_missing,",
    "output_written, reproducible, workspace_writes_confined.",
    "n = 8,835 non-missing, mean 26.83, sd 5.21, median 25.99."
  )
)

derive <- function(data) {
  # Keep only values inside a plausible physical envelope; everything else,
  # including every documented and undocumented sentinel, becomes NA.
  plausible <- function(x, lo, hi) {
    x <- suppressWarnings(as.numeric(x))
    ifelse(!is.na(x) & x >= lo & x <= hi, x, NA_real_)
  }

  # Upper-case names are correct for this file - see notes.
  height_m <- plausible(data[["BD9HGHTM"]], 1.20, 2.20)
  weight_kg <- plausible(data[["BD9WGHTK"]], 25, 300)

  data.frame(
    bcsid = data$bcsid,
    bmi_42y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
