# ==========================================================================
# Derived variable: bmi_34y
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
  id = "bmi_34y",
  label = "Body mass index (kg/m2) at age 34, self-reported (height may be carried from age 29)",
  category = "health",
  github_issue = 28,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-08-04",
  source_files = c("bcs_2004_followup"),
  source_vars = c(
    "bd7htun", "bd7htmtr", "bd7htcms", "bd7htft", "bd7htins",
    "b7weigh2", "b7wtkis2", "b7wtste2", "b7wtpod2"
  ),
  notes = paste(
    "Issue #28: 'bmi at each age'. One sibling of the bmi/ family - one",
    "script per sweep that carries BOTH a height and a weight for the cohort",
    "member: 0y, 42m, 10y, 16y, 26y, 29y, 34y, 42y, 46y, 51y. 5y, 21y and",
    "38y carry no usable pair; see bmi_0y's notes for the detail.",
    "",
    "THE HEIGHT AT THIS SWEEP IS NOT NECESSARILY MEASURED AT THIS SWEEP.",
    "The bd7ht* series is labelled '(Derived) height ... - sweep6 or",
    "sweep7', i.e. CLS filled it from the age-29 (sweep 6) answer where the",
    "age-34 (sweep 7) answer was absent, because height was not re-asked of",
    "everyone. There is no clean contemporaneous 34y self-reported height to",
    "use instead: the unsuffixed b7height/b7htmees/b7htcms/b7htfeet/b7htines",
    "columns are labelled '(Proxy) Cohort Member's height' and come from a",
    "proxy informant, not the cohort member. The bd7ht* series is therefore",
    "the right choice - it is also what CLS's own bd7bmi uses - but it means",
    "bmi_34y and bmi_29y SHARE A HEIGHT for part of the sample, so a",
    "within-person height change between those two sweeps may be an artefact",
    "of the carry-forward rather than real. Adult height is near-stable, so",
    "this affects the interpretation of height change far more than it",
    "affects BMI. WEIGHT is not carried forward: b7weigh2/b7wtkis2/",
    "b7wtste2/b7wtpod2 are the age-34 answers, the '2' suffix marking the",
    "cohort member's own report rather than a proxy's.",
    "",
    "FORMAT FLAGS. bd7htun gives the units the height was given in",
    "(1 'Metres and centimetres', 2 'Feet and inches', with -7 'Other",
    "missing' and -1 'Not applicable'), and b7weigh2 the same for weight",
    "(1 'Kilograms', 2 'Stones and pounds', 3 'Cannot give estimate', plus",
    "-9 'Refusal', -8 'Don't Know', -7 'Other missing', -1 'Not",
    "applicable'). The flag selects which pair is read first; the other",
    "system is still tried if the indicated one yields nothing plausible,",
    "and a missing or non-informative flag falls back to metric-then-",
    "imperial. Note bd7htft's label - '(Derived) height (feet:see bd7htft",
    "for inches)' - is a typo in the deposit that points at itself; the",
    "inches companion is bd7htins.",
    "",
    "METRIC HEIGHT IS A COMPONENT PAIR: bd7htmtr whole metres plus bd7htcms",
    "centimetres, combined as metres + cms/100, with the alternative",
    "readings tried in turn if that lands outside the plausible envelope -",
    "same treatment as 26y and 29y.",
    "",
    "IMPERIAL CONVERSION. (feet * 12 + inches) * 0.0254 m; (stones * 14 +",
    "pounds) * 0.45359237 kg, using the exact international definitions. A",
    "missing minor component counts as zero when the major component is",
    "present; a missing major component yields NA.",
    "",
    "WHY NOT THE DEPOSITED bd7bmi. bcs_2004_followup already carries bd7bmi",
    "'(Derived) Body mass index (weight kgs)/(height metres sq)'. It is not",
    "used, because only 34y, 42y, 46y and 51y deposit a ready-made BMI at",
    "all - the six earlier sweeps in this family have to be computed from",
    "height and weight regardless - and mixing the two would leave the",
    "family's definition varying by sweep for no gain. Computing it the same",
    "way everywhere keeps one definition across all ten siblings. bd7bmi is",
    "still the best available CROSS-CHECK for this sweep: on real data,",
    "bmi_34y should agree with it closely, and a systematic discrepancy",
    "points at the unit handling above.",
    "",
    "MISSING VALUES. Sentinels here are -9/-8/-7/-1, which is a different",
    "set again from 26y's -8/-7/-2/-1 and 29y's positive 98/99 - the",
    "inconsistency DATA_KNOWLEDGE.md records. Rather than deny-list them,",
    "the derivation keeps only values inside a plausible adult envelope",
    "(height 1.20-2.20 m, weight 25-300 kg) after conversion and lets",
    "everything else fall through to NA.",
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

  height_metres <- num(data$bd7htmtr)
  height_cms <- num(data$bd7htcms)
  height_feet <- num(data$bd7htft)
  height_inches <- minor(height_feet, num(data$bd7htins))

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
  height_m <- by_flag(num(data$bd7htun), height_metric, height_imperial)

  weight_stones <- num(data$b7wtste2)
  weight_pounds <- minor(weight_stones, num(data$b7wtpod2))

  weight_metric <- first_plausible(list(num(data$b7wtkis2)), 25, 300)
  weight_imperial <- first_plausible(
    list((weight_stones * 14 + weight_pounds) * 0.45359237),
    25, 300
  )
  weight_kg <- by_flag(num(data$b7weigh2), weight_metric, weight_imperial)

  data.frame(
    bcsid = data$bcsid,
    bmi_34y = as.numeric(weight_kg / height_m^2),
    stringsAsFactors = FALSE
  )
}
