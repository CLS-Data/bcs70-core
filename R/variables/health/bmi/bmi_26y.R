# ==========================================================================
# Derived variable: bmi_26y
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
  id = "bmi_26y",
  label = "Body mass index (kg/m2) at age 26, self-reported",
  category = "health",
  github_issue = 28,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs96x"),
  source_vars = c(
    "b960433", "b960434", "b960436", "b960437",
    "b960439", "b960441", "b960443"
  ),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "SOURCE. bcs96x records height and weight in WHICHEVER SYSTEM the",
    "respondent answered in, across seven columns:",
    "  height  b960436 'Height - metres'  b960437 'Height - cms'",
    "          b960433 'Height - feet'    b960434 'Height - inches'",
    "  weight  b960443 'Weight - kgs'",
    "          b960439 'Weight - stones'  b960441 'Weight - lbs'",
    "Unlike 29y and 34y, this sweep deposits NO 'format of answer' flag",
    "saying which system a given respondent used, so the system has to be",
    "inferred from which columns hold usable values.",
    "",
    "HOW THE METRIC HEIGHT PAIR IS READ, AND WHY IT IS GUARDED. The pairing",
    "of 'Height - metres' with 'Height - cms' reads as a whole-metres",
    "component plus a centimetres remainder (1 m + 72 cm), which is",
    "explicitly how the equivalent 29y pair is labelled ('CMs height:metres.",
    "see HTCMs2 for centimetres'). The 26y dictionary does not spell that",
    "out, so it is an inference, and it is the single most likely thing to",
    "be wrong at this sweep. The derivation therefore tries the candidate",
    "readings in order and takes the first that lands inside a plausible",
    "adult envelope: metres + cms/100, then cms/100 alone (in case 'cms'",
    "turns out to hold the whole height), then metres alone, then the",
    "imperial pair. Under either coding the correct answer is the one",
    "selected; under a coding nobody anticipated the result is NA rather",
    "than a plausible-looking wrong number. WHAT TO CHECK ON REAL DATA:",
    "if this reading is wrong, missingness at 26y will be conspicuously",
    "higher than at neighbouring sweeps - that is the symptom to look for.",
    "",
    "IMPERIAL CONVERSION. (feet * 12 + inches) * 0.0254 m; (stones * 14 +",
    "pounds) * 0.45359237 kg. Both use the exact international definitions",
    "rather than rounded factors. A missing minor component (inches, or",
    "pounds) is treated as zero when the major component is present, since",
    "'5 feet' and '5 feet 0 inches' are the same answer; a missing MAJOR",
    "component yields NA rather than being treated as zero.",
    "",
    "MISSING VALUES. The seven columns do not share a sentinel scheme -",
    "exactly the situation DATA_KNOWLEDGE.md warns about. Between them they",
    "document -8 'Inappropriate Answer', -7 'Out of range', -2 'Does Not",
    "Apply', -1 'Not Answered' and an unlabelled 88, and b960437 documents",
    "no negative range at all. Rather than deny-list that inconsistent set,",
    "the derivation keeps only values inside a plausible adult envelope",
    "(height 1.20-2.20 m, weight 25-300 kg) and lets everything else fall",
    "through to NA. Note 88 as an inches or pounds value is caught by the",
    "envelope only after conversion, which is why the guard is applied to",
    "the converted metres/kilograms rather than to the raw components.",
    "",
    "SELF-REPORTED, NOT MEASURED. 26y onwards are self-reported, whereas",
    "0y, 42m, 10y and (mostly) 16y are measured. Self-reported height tends",
    "to be over-reported and weight under-reported, biasing self-reported",
    "BMI downwards, so a jump between 16y and 26y is partly a change of",
    "instrument rather than of body composition.",
    "",
    "NOT YET VERIFIED against real data - synthetic tests only."
  )
)

derive <- function(data) {
  num <- function(x) suppressWarnings(as.numeric(x))

  # Take the first candidate reading that lands inside the plausible
  # envelope; anything outside it - sentinel, unit error, or an unforeseen
  # coding - falls through to NA rather than to a wrong-looking number.
  first_plausible <- function(candidates, lo, hi) {
    out <- rep(NA_real_, length(candidates[[1]]))
    for (candidate in candidates) {
      take <- is.na(out) & !is.na(candidate) & candidate >= lo & candidate <= hi
      out[take] <- candidate[take]
    }
    out
  }

  # A missing minor component means zero when the major one is present
  # ("5 feet" == "5 feet 0 inches"); a missing major component stays NA.
  minor <- function(major, x) ifelse(!is.na(major) & is.na(x), 0, x)

  height_metres <- num(data$b960436)
  height_cms <- num(data$b960437)
  height_feet <- num(data$b960433)
  height_inches <- minor(height_feet, num(data$b960434))

  height_m <- first_plausible(
    list(
      height_metres + height_cms / 100,
      height_cms / 100,
      height_metres,
      (height_feet * 12 + height_inches) * 0.0254
    ),
    1.20, 2.20
  )

  weight_kgs <- num(data$b960443)
  weight_stones <- num(data$b960439)
  weight_pounds <- minor(weight_stones, num(data$b960441))

  weight_kg <- first_plausible(
    list(
      weight_kgs,
      (weight_stones * 14 + weight_pounds) * 0.45359237
    ),
    25, 300
  )

  data.frame(
    bcsid = data$bcsid,
    bmi_26y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
