# ==========================================================================
# Derived variable: region_46y
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
  id = "region_46y",
  label = "Region of residence at age 46 (2016), Government Office Region, as a string",
  category = "housing",
  github_issue = 20,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-29",
  source_files = c("bcs_age46_main"),
  source_vars = c("BD10GOR"),
  notes = paste(
    "Issue #20: 'region of residence at each age', harmonised to standard",
    "codes, emitted as the STRING label rather than the numeric code. This",
    "is one sibling of the region/ family - one script per sweep that",
    "actually carries a region-of-residence variable (0y, 5y, 10y, 16y, 21y,",
    "26y, 29y, 34y, 38y, 42y, 46y, 51y). 42m and xwave carry none: 42m's",
    "only file (f690) has no region variable, and xwave's response file has",
    "only `cob`, country of BIRTH, which is not residence.",
    "",
    "SOURCE. 46y bcs_age46_main BD10GOR '2010 Government Office Region of",
    "residence', coded 1-14. This sweep is the ONLY one in the family that",
    "documents NO missing-value codes at all - its",
    "spss_user_missing_values field is empty and its value labels start at 1,",
    "with no negative codes. DATA_KNOWLEDGE.md explicitly warns that a",
    "variable with no documented sentinels may still contain them in the real",
    "file, so the allow-list below matters more here than anywhere else in",
    "the family, not less.",
    "",
    "TWO EXTRA CATEGORIES THAT NO OTHER SWEEP HAS. BD10GOR runs to 14, not",
    "12, adding 13 '(pseudo) Channel Islands' and 14 '(pseudo) Isle of Man'.",
    "These are kept as 'Channel Islands' and 'Isle of Man' rather than folded",
    "into NA or into any UK region: they are substantive, documented answers",
    "about where the cohort member lived, and neither is part of the UK for",
    "GOR purposes. They will simply be absent from every other sibling.",
    "",
    "NOTE THE VARIABLE IS LABELLED '2010', NOT 2016. The 46y sweep was",
    "fielded in 2016-2018, but the label reads '2010 Government Office",
    "Region of residence'. GORs were abolished as administrative units in",
    "2011 and the boundaries were frozen thereafter, so the most natural",
    "reading is that this records the 2010-vintage GOR boundary set applied",
    "to the age-46 address, rather than a region of residence in 2010. That",
    "reading is not confirmed by anything in the dictionaries in this repo",
    "and should be checked against the 46y user guide before the variable is",
    "used to date a move.",
    "",
    "WHY GOR. Unlike 16y-42y, this sweep deposits NO Standard Region",
    "counterpart - BD10GOR is the only region variable in bcs_age46_main, so",
    "there is no choice to make here. GOR is used across the whole 16y+ half",
    "of the family precisely so that this sweep and 51y, which also has only",
    "a GOR-style variable, stay comparable with the sweeps that do offer",
    "both.",
    "The 0y, 5y and 10y siblings have no GOR variable available and are",
    "therefore on SSR; see their notes for why the two are not crosswalked.",
    "",
    "THE CANONICAL GOR VOCABULARY used by every 16y+ sibling is:",
    "  'North East', 'North West', 'Yorkshire and the Humber',",
    "  'East Midlands', 'West Midlands', 'East of England', 'London',",
    "  'South East', 'South West', 'Wales', 'Scotland', 'Northern Ireland'",
    "  (plus 'Channel Islands' and 'Isle of Man', which only 46y codes).",
    "The numeric codes 1-12 are identical across BD4GOR, BD5GOR, BD6GOR,",
    "BD7GOR, BD8GOR, BD9GOR, BD10GOR and bd11rgn - this was checked against",
    "each sweep's own dictionary rather than assumed, because the 51y bd11*",
    "series is known to renumber some of its predecessors' code sets",
    "(bd11hnvq moved 'no qualification' from 0 to 96). bd11rgn does NOT",
    "renumber: it keeps 1-12 exactly.",
    "",
    "LABEL NORMALISATION IS THE POINT OF THIS FAMILY. The deposited labels",
    "for one and the same category are not written the same way twice:",
    "  16y-38y  'Yorkshire and Humberside'",
    "  42y      'Yorkshire and Humberberside'   (a typo in the deposit)",
    "  46y      'Yorkshire and the Humber'",
    "  51y      'Yorkshire and The Humber'",
    "and 46y/51y prefix the non-English categories as '(pseudo) Wales',",
    "'(pseudo) Scotland', '(pseudo) Northern Ireland' - '(pseudo)' only",
    "records that a GOR is by definition an England-only unit, so the label",
    "is stripped to plain 'Wales'/'Scotland'/'Northern Ireland'. Every",
    "sibling emits the single canonical spelling above, so grouping on the",
    "string across sweeps works without any further cleaning. Reproducing",
    "the raw labels verbatim would make the same region look like four",
    "different regions.",
    "",
    "MISSING VALUES. Following DATA_KNOWLEDGE.md, the documented codes are",
    "allow-listed and everything else - including undocumented sentinels",
    "that may exist in the real file - falls through to NA. Because this",
    "sweep documents no sentinels, ANY negative value, any 0, and anything",
    "above 14 becomes NA. Note the meaning of -1 drifts across the family",
    "(16y-38y 'Unknown'; 42y 'Not applicable (not resident in UK)'; 51y 'Not",
    "applicable'; 46y documents no negative codes at all), so NA in this",
    "family is not self-describing.",
    "",
    "VERIFIED against real data on 2026-07-29 (harness run 5063c1fe, branch",
    "variable/region, schema 5). Aggregate: n = 8,580 rows in this sweep's",
    "file, 12 distinct region labels, 0.0% missing. All harness checks",
    "passed - columns_exact, identifier_present, identifier_unique,",
    "not_all_missing, no_residual_sentinels, reproducible - including the",
    "cross-variable integration run over all 14 variables, which confirms",
    "this sibling joins cleanly on bcsid alongside the other eleven. No",
    "empty strings and no numeric-looking values in the output, so the",
    "code-to-label lookup is complete."
  )
)

derive <- function(data) {
  # Government Office Region codes documented for BD10GOR. Identical numbering
  # to every other GOR sibling in this family. Allow-listing these and
  # letting everything else fall through to NA is safer than deny-listing
  # sentinels - see DATA_KNOWLEDGE.md.
  gor_labels <- c(
    "1" = "North East",
    "2" = "North West",
    "3" = "Yorkshire and the Humber",
    "4" = "East Midlands",
    "5" = "West Midlands",
    "6" = "East of England",
    "7" = "London",
    "8" = "South East",
    "9" = "South West",
    # Deposited as "(pseudo) Wales" / "(pseudo) Scotland" / "(pseudo)
    # Northern Ireland". The "(pseudo)" prefix only records that a GOR is by
    # definition an England-only unit; it is stripped so these match the
    # plain labels every other sibling uses.
    "10" = "Wales",
    "11" = "Scotland",
    "12" = "Northern Ireland",
    # 46y only - no other sweep codes these.
    "13" = "Channel Islands",
    "14" = "Isle of Man"
  )

  # This sweep documents no missing codes at all, so the allow-list is doing
  # all the work: any negative, 0, or out-of-range value resolves to NA.
  code <- suppressWarnings(as.numeric(data[["BD10GOR"]]))
  region <- unname(gor_labels[as.character(code)])

  data.frame(
    bcsid = data$bcsid,
    region_46y = as.character(region),
    stringsAsFactors = FALSE
  )
}
