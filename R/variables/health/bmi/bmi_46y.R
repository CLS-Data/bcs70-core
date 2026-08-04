# ==========================================================================
# Derived variable: bmi_46y
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
  id = "bmi_46y",
  label = "Body mass index (kg/m2) at age 46, self-reported",
  category = "health",
  github_issue = 28,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs_age46_main"),
  source_vars = c("BD10HGHTM", "BD10WGHTK"),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "SOURCE AND UNITS. bcs_age46_main BD10HGHTM '(Derived) Self-reported",
    "height in metres' and BD10WGHTK '(Derived) Self-reported weight in",
    "kilograms'. Both are single columns already in SI units, so there is no",
    "metric-vs-imperial reconciliation to do here - CLS has collapsed the",
    "raw B10HTMEES/B10HTCMS/B10HTFEET/B10HTINES and B10WTKIS/B10WTSTE/",
    "B10WTPOD answers into them.",
    "",
    "UPPER-CASE NAMES ARE DELIBERATE. DATA_KNOWLEDGE.md names this file as",
    "one of the two whose identifier is deposited as BCSID, and records that",
    "load_tab() lower-cases ONLY the identifier: every other name in the",
    "file stays upper-case. BD10HGHTM/BD10WGHTK must therefore stay",
    "upper-case in source_vars and in derive().",
    "",
    "SELF-REPORTED, NOT NURSE-MEASURED - AND THIS SWEEP HAS BOTH. Age 46 is",
    "the only sweep in this family that deposits a nurse-measured",
    "alternative: BD10MWGTK '(Derived) Nurse measured weight in kilograms",
    "(all measured)' and B10HEIGHTCM \"Respondent's height (cm)\", alongside",
    "the deposited BMIs BD10BMI (self-reported) and BD10MBMI (nurse",
    "measurement). The self-reported pair is used here so that this sibling",
    "measures the same thing as 26y, 29y, 34y, 42y and 51y, all of which are",
    "self-report only. Choosing the nurse measurement would make 46y the one",
    "sweep in the adult series whose apparent BMI shift is an instrument",
    "change rather than a real one, since self-reported height is typically",
    "over-reported and weight under-reported. The nurse-measured variables",
    "are a natural follow-up variable in their own right - they would make a",
    "clean separate request rather than a silent substitution inside this",
    "one - and on real data BD10MBMI vs bmi_46y quantifies the",
    "self-report bias directly.",
    "",
    "WHY NOT THE DEPOSITED BD10BMI. Only 34y, 42y, 46y and 51y deposit a",
    "ready-made BMI at all; the six earlier siblings must be computed from",
    "height and weight regardless, so computing it identically everywhere",
    "keeps one definition across all ten siblings. BD10BMI remains the best",
    "available CROSS-CHECK for this sweep - on real data bmi_46y should",
    "agree with it to rounding.",
    "",
    "MISSING VALUES. Both columns declare -8 'No information' with an SPSS",
    "user-missing range of '-1.0 thru -8.0 and -9.0'. Per DATA_KNOWLEDGE.md",
    "the derivation does not deny-list those codes: it keeps only values",
    "inside a plausible adult envelope (height 1.20-2.20 m, weight",
    "25-300 kg) and lets everything else fall through to NA.",
    "",
    "VERIFIED against real data on 2026-08-04 (harness 5.0.0,",
    "runner 4.5.3, commit cb4c6ddc). Every harness check passed:",
    "columns_exact, identifier_present, identifier_unique,",
    "no_nan_or_infinite, no_residual_sentinels, not_all_missing,",
    "output_written, reproducible, workspace_writes_confined.",
    "n = 8,190 non-missing, mean 27.71, sd 5.60, median 26.82."
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
  height_m <- plausible(data[["BD10HGHTM"]], 1.20, 2.20)
  weight_kg <- plausible(data[["BD10WGHTK"]], 25, 300)

  data.frame(
    bcsid = data$bcsid,
    bmi_46y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
