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
  label = "Body mass index (kg/m2) at age 29-30, self-reported",
  category = "health",
  github_issue = 28,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs2000"),
  source_vars = c(
    "height2", "htmetre2", "htcms2", "htfeet2", "htinche2",
    "weight2", "wtkilos2", "wtstone2", "wtpound2"
  ),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "THE '2' SUFFIX MATTERS - THESE ARE THE COHORT MEMBER'S OWN ANSWERS.",
    "bcs2000 carries two parallel sets. The suffixed ones used here are the",
    "cohort member's own report ('CMs self-reported height without shoes');",
    "the unsuffixed twins - height, htmetres, htcms, htfeet, htinches,",
    "weight, wtkilos, wtstones, wtpounds - are labelled '(Proxy)' and come",
    "from a proxy informant. Reading the shorter name because it looks",
    "tidier would silently swap the respondent, so the suffixed set is used",
    "throughout and the proxy set is deliberately NOT used as a fallback.",
    "",
    "FORMAT FLAGS. Unlike 26y, this sweep records which system the",
    "respondent answered in: height2 (1 'Metres and Centimetres',",
    "2 'Feet and inches', 3 'Cannot give estimate', 8 'Dont know',",
    "9 'Not answered') and weight2 (1 'Kilograms', 2 'Stones and pounds',",
    "3, 8, 9 as above). The flag selects which pair is read FIRST; the other",
    "system is still tried as a fallback if the indicated one yields nothing",
    "plausible, and when the flag itself is missing or non-informative (3/8/",
    "9) the metric pair is tried first and imperial second. Honouring the",
    "documented routing while not depending on it is deliberate: the flag is",
    "the study's own statement of intent, but a blank flag should not throw",
    "away an answer that is plainly present.",
    "",
    "METRIC HEIGHT IS A COMPONENT PAIR. htmetre2 is labelled 'CMs",
    "height:metres. see HTCMs2 for centimetres' and htcms2 'CMs",
    "height:centimetres. see HTmetre2 for metres' - i.e. whole metres plus a",
    "centimetres remainder, combined as metres + cms/100. As at 26y, the",
    "alternative readings (cms/100 alone, metres alone) are tried in turn if",
    "that lands outside the plausible envelope, so a coding surprise",
    "produces NA rather than a plausible-looking wrong value.",
    "",
    "IMPERIAL CONVERSION. (feet * 12 + inches) * 0.0254 m; (stones * 14 +",
    "pounds) * 0.45359237 kg, using the exact international definitions. A",
    "missing minor component (inches, pounds) counts as zero when the major",
    "component is present; a missing major component yields NA.",
    "",
    "MISSING VALUES. The sentinel scheme here is POSITIVE, not negative -",
    "htfeet2, htinche2, wtstone2 and wtpound2 document 98 'Dont know' and",
    "99 'Not answered', while htmetre2 and htcms2 and wtkilos2 document no",
    "codes at all. This is precisely DATA_KNOWLEDGE.md's warning that",
    "sentinel schemes vary per variable and that na_if_negative()'s default",
    "code list is a convenience rather than a corpus-wide truth - it would",
    "catch nothing here. The derivation instead keeps only values inside a",
    "plausible adult envelope (height 1.20-2.20 m, weight 25-300 kg) after",
    "conversion, so 98 and 99 are excluded on the same footing as any",
    "undocumented code.",
    "",
    "WEIGHT AND PREGNANCY. weight2 is labelled 'CMs self-reported weight",
    "without clothes(before being preg)', i.e. respondents who were pregnant",
    "were asked for their pre-pregnancy weight. Their BMI here therefore",
    "does not describe their weight at interview.",
    "",
    "SELF-REPORTED, NOT MEASURED - see bmi_26y's notes on the instrument",
    "change between 16y and 26y.",
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

  # Format flag 2 means the respondent answered in imperial units.
  by_flag <- function(flag, metric, imperial) {
    prefers_imperial <- !is.na(flag) & flag == 2
    chosen <- ifelse(prefers_imperial, imperial, metric)
    other <- ifelse(prefers_imperial, metric, imperial)
    ifelse(is.na(chosen), other, chosen)
  }

  height_metres <- num(data$htmetre2)
  height_cms <- num(data$htcms2)
  height_feet <- num(data$htfeet2)
  height_inches <- minor(height_feet, num(data$htinche2))

  height_metric <- first_plausible(
    list(
      height_metres + height_cms / 100,
      height_cms / 100,
      height_metres
    ),
    1.20, 2.20
  )
  height_imperial <- first_plausible(
    list((height_feet * 12 + height_inches) * 0.0254),
    1.20, 2.20
  )
  height_m <- by_flag(num(data$height2), height_metric, height_imperial)

  weight_stones <- num(data$wtstone2)
  weight_pounds <- minor(weight_stones, num(data$wtpound2))

  weight_metric <- first_plausible(list(num(data$wtkilos2)), 25, 300)
  weight_imperial <- first_plausible(
    list((weight_stones * 14 + weight_pounds) * 0.45359237),
    25, 300
  )
  weight_kg <- by_flag(num(data$weight2), weight_metric, weight_imperial)

  data.frame(
    bcsid = data$bcsid,
    bmi_29y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
