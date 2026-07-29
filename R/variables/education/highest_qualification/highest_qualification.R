# ==========================================================================
# Derived variable: highest_qualification
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
  id = "highest_qualification",
  label = "Highest qualification ever achieved, harmonised to NVQ level (0 none - 5 degree+), across all sweeps",
  category = "education",
  github_issue = 17,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-29",
  source_files = c(
    "bcs21yearsample", # 21y
    "bcs96x", # 26y
    "bcs6derived", # 29y
    "bcs7derived", # 34y
    "bcs8derived", # 38y
    "bcs70_2012_derived", # 42y
    "bcs_age46_main", # 46y
    "bcs11_age51_main" # 51y
  ),
  source_vars = c(
    "hqual16", "hqual21", "hqual26", "HINVQ00",
    "BD7HNVQ", "BD8HNVQ", "BD9HNVQ", "BD10HNVQ", "bd11hnvq"
  ),
  notes = paste(
    "Issue #17: one single cross-sweep variable (explicitly NOT a per-sweep",
    "family) giving the highest qualification achieved, with categories",
    "harmonised across sweeps.",
    "",
    "SCALE. The output is the NVQ level scale 0-5, because that is the only",
    "scale every contributing sweep already shares:",
    "  0 = no qualifications",
    "  1 = NVQ1  (CSE grades 2-5 / low GCSEs)",
    "  2 = NVQ2  (O level / good GCSEs)",
    "  3 = NVQ3  (A level)",
    "  4 = NVQ4  (higher qualification below degree, e.g. diploma)",
    "  5 = NVQ5  (degree and above)",
    "It is ORDINAL, not an interval measure - do not average it.",
    "",
    "AGGREGATION. Highest qualification ever achieved is monotone",
    "non-decreasing over the life course, so the derived value is the MAXIMUM",
    "across every sweep that observed the cohort member. The adult sweeps",
    "already deposit a cumulative 'up to <year>' variable, but attrition means",
    "different people are last observed at different sweeps, and a later",
    "cumulative report can still come out below an earlier one through",
    "reporting inconsistency. Taking the max both fills those gaps and is",
    "robust to that inconsistency. pmax(..., na.rm = TRUE) yields NA only when",
    "every sweep is missing.",
    "",
    "SOURCES (from an exhaustive cross-sweep metadata search):",
    "  21y bcs21yearsample hqual16  'Highest qualification at 16' (0-5)",
    "  21y bcs21yearsample hqual21  'Highest qualification at 21' (0-5)",
    "  26y bcs96x          hqual26  'Highest Qualification at 26' (0-5)",
    "  29y bcs6derived     HINVQ00  '2000: Highest NVQ level (academic or",
    "                                vocational)' (0-5)",
    "  34y bcs7derived     BD7HNVQ  'Highest NVQ Level from an Academic or",
    "                                Vocational Qual up to 2004' (0-5)",
    "  38y bcs8derived     BD8HNVQ  '... up to 2008' (0-5)",
    "  42y bcs70_2012_derived BD9HNVQ  '... up to 2012' (0-5)",
    "  46y bcs_age46_main  BD10HNVQ '... up to 2016' (0-5)",
    "  51y bcs11_age51_main bd11hnvq '... up to age 51' (SEE BELOW)",
    "All nine raw names are distinct, so the runner leaves them bare rather",
    "than disambiguating any of them as '<file_name>.<var>'.",
    "",
    "51y CODING TRAP - the single most important thing about this script.",
    "bd11hnvq does NOT use the same code set as its own predecessors, even",
    "though its label reads as the direct continuation of BD7/8/9/10HNVQ:",
    "  29y-46y:  0 = 'none',            1-5 = NVQ Level 1-5",
    "  51y:      0 = 'NVQ Entry Level', 1-5 = NVQ Level 1-5, 96 = 'No",
    "            qualification'",
    "So at 51y the no-qualifications category moved from 0 to 96, and 0 was",
    "reused for Entry Level. Carrying 96 through untouched would make a",
    "cohort member with NO qualifications the highest-qualified person in the",
    "dataset, since the derivation takes a maximum. bd11hnvq is therefore",
    "recoded before the max: 96 -> 0. Entry Level (51y code 0) is left at 0,",
    "which conflates it with 'none' - the 0-5 NVQ scale has no category below",
    "Level 1, and the earlier sweeps' own derived variables likewise coded a",
    "sub-Level-1 qualification as 0, so this keeps the scale internally",
    "consistent rather than inventing a category the other sweeps can't fill.",
    "",
    "MISSING VALUES. Rather than deny-listing sentinels - they differ per",
    "sweep (-9 'Incomplete info' at 29y; -1/-8/-9 at 34y-46y; -1/-8 at 51y)",
    "and DATA_KNOWLEDGE.md warns undocumented ones also occur - anything",
    "outside the allow-listed 0-5 window becomes NA. That deliberately also",
    "catches two labelled but unplaceable codes: hqual16/hqual21 -1 'Other",
    "quals' and (had it been used) hqual26d -3 'Quals but d/k level'. Both",
    "mean 'holds qualifications, level unknown', which is neither 0 nor any",
    "level, so NA is the only honest value. Note this makes NA here not",
    "self-describing: it conflates never observed, not asked, refused, and",
    "level-unknown.",
    "",
    "CONSIDERED AND REJECTED:",
    "  - 51y bd11lvl1 (and bd11alvl1/bd11vlvl1), the '8 level version': an",
    "    RQF 0-8 scale with extra codes 95 'Other qualification' / 96 'No",
    "    qualification'. Finer-grained, but no earlier sweep carries anything",
    "    on that scale, so it cannot be harmonised across sweeps - and it is",
    "    the in-sweep, not the cumulative, measure.",
    "  - The BD7ACHQ1/BD8ACHQ1/BD9ACHQ1/BD10ACHQ1/bd11achq1 'in this survey'",
    "    variants, and HIACA00/BD7HACHQ/BD10HACHQ/bd11hachq: the ACHQ family",
    "    is academic-only on a 0-8 scale and would drop vocational",
    "    qualifications entirely; the 'in this survey' variants report only",
    "    what was gained since the last interview, not the standing total.",
    "  - 26y hqual26a/b/c (academic-only and vocational-only components) and",
    "    hqual26d: hqual26 already combines academic and vocational on the",
    "    0-5 scale, matching every other sweep.",
    "  - 34y bd7hq5 / bd7hq13 in bcs_2004_followup: academic-only, on their",
    "    own 0-5 and 0-13 scales that are NOT the NVQ scale (bd7hq5's 4 is",
    "    'Degree/Dip HE', where NVQ 4 is sub-degree), so mixing them in would",
    "    silently mis-rank people.",
    "  - The raw per-qualification items (26y q5a*/q5b*/nvq_*, 29y nvqlev*,",
    "    34y b7nvql*, 38y b8vlv*, 42y B9NVQLV, 46y B10NVQLV, 51y",
    "    b11qualtyp): the deposited derived variables above already summarise",
    "    exactly these, applying CLS's own qualification-to-NVQ mapping.",
    "  - 5y f699b e189a/e189b 'Mothers/Fathers Highest Educ Qualification':",
    "    the PARENTS' qualifications, not the cohort member's.",
    "  - 42y B9PHVCDR (partner's) and B9ABQCDR (older child's): not the",
    "    cohort member.",
    "",
    "SWEEP COVERAGE. 0y, 5y, 10y and 16y contribute nothing, and that is",
    "expected rather than a gap in the search: the cohort member had no",
    "qualifications to report before age 16, and 16y's own derived file",
    "(bcs4derived) carries no qualification variable at all. Qualifications",
    "at 16 are instead captured retrospectively by 21y hqual16, which is",
    "included above. xwave holds no qualification measure either (the",
    "activity histories file is long-format and records activity type, not",
    "attainment).",
    "",
    "NOT YET VERIFIED against real data - see CONTRIBUTING.md. Two things to",
    "check on the first real-data run: (a) that no value of 96 survives into",
    "the output, which would mean the 51y recode was missed; and (b) that the",
    "distribution is plausibly skewed toward 2-5, since taking a lifetime",
    "maximum should give a markedly higher distribution than any single",
    "sweep's variable on its own."
  )
)

derive <- function(data) {
  # Allow-list the documented NVQ levels 0-5 and let everything else fall
  # through to NA. Deny-listing sentinels would be unsafe here: the codes
  # differ per sweep and undocumented ones may also be present.
  nvq_level <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    ifelse(!is.na(x) & x >= 0 & x <= 5, x, NA_real_)
  }

  # 51y only: 'No qualification' is 96 there, not 0 (0 means Entry Level).
  # Fold it back onto the 0-5 scale BEFORE the max, or a cohort member with
  # no qualifications would outrank a graduate. Entry Level stays at 0.
  nvq_level_51y <- function(x) {
    x <- suppressWarnings(as.numeric(x))
    nvq_level(ifelse(!is.na(x) & x == 96, 0, x))
  }

  # Highest level reported at any sweep. na.rm = TRUE means a single observed
  # sweep is enough, and the result is NA only if every sweep is missing.
  highest_qualification <- pmax(
    nvq_level(data[["hqual16"]]),
    nvq_level(data[["hqual21"]]),
    nvq_level(data[["hqual26"]]),
    nvq_level(data[["HINVQ00"]]),
    nvq_level(data[["BD7HNVQ"]]),
    nvq_level(data[["BD8HNVQ"]]),
    nvq_level(data[["BD9HNVQ"]]),
    nvq_level(data[["BD10HNVQ"]]),
    nvq_level_51y(data[["bd11hnvq"]]),
    na.rm = TRUE
  )

  data.frame(
    bcsid = data$bcsid,
    highest_qualification = as.numeric(highest_qualification)
  )
}
