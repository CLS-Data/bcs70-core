# ==========================================================================
# Derived variable: bmi_51y
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
  id = "bmi_51y",
  label = "Body mass index (kg/m2) at age 51, self-reported",
  category = "health",
  github_issue = 28,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs11_age51_main"),
  source_vars = c("bd11hghtm", "bd11wghtk"),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "SOURCE AND UNITS. bcs11_age51_main bd11hghtm '(Derived) Self-reported",
    "height in metres' and bd11wghtk '(Derived) Self-reported weight in",
    "kilograms'. Both are single columns already in SI units, collapsing the",
    "raw b11htmees/b11htcms/b11htfeet/b11htines and b11wtkis/b11wtste/",
    "b11wtpod answers, so there is no metric-vs-imperial reconciliation to",
    "do here. Names are LOWER case at this sweep, unlike the upper-case 42y",
    "and 46y equivalents.",
    "",
    "DO NOT CONFUSE bd11wghtk WITH THE SURVEY WEIGHTS. This file also",
    "carries bd11weight_main, bd11weight_psc and bd11weight_odq, which are",
    "non-response weights for the main survey, the paper self-completion and",
    "the online dietary questionnaire - nothing to do with body weight. Only",
    "bd11wghtk is kilograms.",
    "",
    "THE bd11* SERIES SOMETIMES RENUMBERS ITS PREDECESSORS, so the coding",
    "was checked against this sweep's own dictionary rather than carried",
    "over from 46y - the region family found bd11hnvq moving 'no",
    "qualification' from 0 to 96. Here there is nothing to renumber: both",
    "columns are continuous, and the only documented code is -8 'No",
    "information', matching 42y and 46y.",
    "",
    "WHY NOT THE DEPOSITED bd11bmi. This sweep deposits bd11bmi '(Derived)",
    "Body mass index (based on self-reported data)'. It is not used because",
    "only 34y, 42y, 46y and 51y deposit a ready-made BMI at all, and the six",
    "earlier siblings must be computed from height and weight regardless;",
    "computing it identically everywhere keeps one definition across all ten",
    "siblings. bd11bmi remains the best available CROSS-CHECK for this",
    "sweep - on real data bmi_51y should agree with it to rounding.",
    "",
    "MISSING VALUES. Per DATA_KNOWLEDGE.md the derivation does not",
    "deny-list -8 or any other sentinel: it keeps only values inside a",
    "plausible adult envelope (height 1.20-2.20 m, weight 25-300 kg) and",
    "lets everything else fall through to NA. Note this sweep is one of",
    "those DATA_KNOWLEDGE.md cites as carrying a wide sentinel set",
    "(-9/-8/-3/-2/-1), which the envelope handles without enumerating.",
    "",
    "SELF-REPORTED, NOT MEASURED - see bmi_26y's notes on the instrument",
    "change between 16y and 26y.",
    "",
    "VERIFIED against real data on 2026-08-04 (harness 5.0.0,",
    "runner 4.5.3, commit cb4c6ddc). Every harness check passed:",
    "columns_exact, identifier_present, identifier_unique,",
    "no_nan_or_infinite, no_residual_sentinels, not_all_missing,",
    "output_written, reproducible, workspace_writes_confined.",
    "n = 7,245 non-missing, mean 28.20, sd 5.79, median 27.28."
  )
)

derive <- function(data) {
  # Keep only values inside a plausible physical envelope; everything else,
  # including every documented and undocumented sentinel, becomes NA.
  plausible <- function(x, lo, hi) {
    x <- suppressWarnings(as.numeric(x))
    ifelse(!is.na(x) & x >= lo & x <= hi, x, NA_real_)
  }

  height_m <- plausible(data[["bd11hghtm"]], 1.20, 2.20)
  weight_kg <- plausible(data[["bd11wghtk"]], 25, 300)

  data.frame(
    bcsid = data$bcsid,
    bmi_51y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
