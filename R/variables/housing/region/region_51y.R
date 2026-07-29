# ==========================================================================
# Derived variable: region_51y
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
  id = "region_51y",
  label = "Region of residence at age 51 (2021), Government Office Region, as a string",
  category = "housing",
  github_issue = 20,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-29",
  source_files = c("bcs11_age51_main"),
  source_vars = c("bd11rgn"),
  notes = paste(
    "Issue #20: 'region of residence at each age', harmonised to standard",
    "codes, emitted as the STRING label rather than the numeric code. This",
    "is one sibling of the region/ family - one script per sweep that",
    "actually carries a region-of-residence variable (0y, 5y, 10y, 16y, 21y,",
    "26y, 29y, 34y, 38y, 42y, 46y, 51y). 42m and xwave carry none: 42m's",
    "only file (f690) has no region variable, and xwave's response file has",
    "only `cob`, country of BIRTH, which is not residence.",
    "",
    "SOURCE. 51y bcs11_age51_main bd11rgn '(Derived) Region of interview',",
    "coded 1-12 with -1 'Not applicable' declared user-missing.",
    "",
    "THE CODE SET WAS CHECKED, NOT ASSUMED - AND IT IS FINE. The 51y bd11*",
    "derived series is known to renumber its own predecessors while keeping",
    "continuation-style labels: bd11hnvq moved 'no qualification' from 0 to",
    "96, which would silently invert a highest-qualification derivation (see",
    "R/variables/education/highest_qualification/). bd11rgn was therefore",
    "compared category by category against BD4GOR-BD10GOR rather than",
    "presumed continuous. It does NOT renumber - 1 'North East' through 12",
    "'(pseudo) Northern Ireland', identical to the rest of the family. The",
    "only differences are cosmetic: 'Yorkshire and The Humber' capitalises",
    "'The', and the non-English categories carry the '(pseudo)' prefix; both",
    "are normalised below.",
    "",
    "NOTE THE LABEL SAYS 'REGION OF INTERVIEW', NOT OF RESIDENCE. Every",
    "other sibling's variable is explicitly 'Region of residence'; this one",
    "is worded as the region the interview took place in. For a home-based",
    "interview the two coincide, which is presumably why CLS treats it as the",
    "continuation of the series, but the wording is weaker and a cohort",
    "member interviewed away from home would be misplaced. Worth confirming",
    "against the 51y user guide before using this sibling for migration work.",
    "The 34y and 38y follow-up files show the same looseness (b7gor/b8gor are",
    "'Government Office Region at Interview'), but at those sweeps the",
    "derived files offer a proper 'of residence' variable, which is what",
    "those siblings use; at 51y there is no such alternative.",
    "",
    "WHY GOR. Unlike 16y-42y, this sweep deposits NO Standard Region",
    "counterpart - bd11rgn is the only region variable in bcs11_age51_main,",
    "so there is no choice to make here.",
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
    "that may exist in the real file - falls through to NA. -1 'Not",
    "applicable' is therefore NA.",
    "Note the meaning of -1 drifts across the family (16y-38y",
    "'Unknown'; 42y 'Not applicable (not resident in UK)'; 51y 'Not",
    "applicable'; 46y documents no negative codes at all), so NA in this",
    "family is not self-describing.",
    "",
    "NOT YET VERIFIED against real data - see CONTRIBUTING.md. On the first",
    "real-data run, check that the output contains no empty strings and no",
    "numeric-looking values (either would mean the code-to-label lookup",
    "missed), and that every non-NA value is one of the twelve canonical",
    "strings above."
  )
)

derive <- function(data) {
  # Government Office Region codes documented for bd11rgn. Identical numbering
  # to every other GOR sibling in this family. Allow-listing these and
  # letting everything else fall through to NA is safer than deny-listing
  # sentinels - see DATA_KNOWLEDGE.md.
  gor_labels <- c(
    "1" = "North East",
    "2" = "North West",
    # Deposited here as "Yorkshire and The Humber"; normalised to the
    # canonical spelling so it matches the 16y-46y variants.
    "3" = "Yorkshire and the Humber",
    "4" = "East Midlands",
    "5" = "West Midlands",
    "6" = "East of England",
    "7" = "London",
    "8" = "South East",
    "9" = "South West",
    # Deposited as "(pseudo) Wales" / "(pseudo) Scotland" / "(pseudo)
    # Northern Ireland"; the prefix only records that a GOR is by definition
    # an England-only unit, so it is stripped.
    "10" = "Wales",
    "11" = "Scotland",
    "12" = "Northern Ireland"
  )

  # -1 "Not applicable" is absent from the lookup, so it resolves to NA along
  # with anything undocumented.
  code <- suppressWarnings(as.numeric(data[["bd11rgn"]]))
  region <- unname(gor_labels[as.character(code)])

  data.frame(
    bcsid = data$bcsid,
    region_51y = as.character(region),
    stringsAsFactors = FALSE
  )
}
