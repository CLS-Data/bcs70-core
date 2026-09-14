# ==========================================================================
# Derived variable: region_21y
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
  id = "region_21y",
  label = "Region of residence at age 21 (1991), survey region mapped to Government Office Region, as a string",
  category = "housing",
  github_issue = 20,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-29",
  source_files = c("bcs21yearsample"),
  source_vars = c("region"),
  notes = paste(
    "Issue #20: 'region of residence at each age', harmonised to standard",
    "codes, emitted as the STRING label rather than the numeric code. This",
    "is one sibling of the region/ family - one script per sweep that",
    "actually carries a region-of-residence variable (0y, 5y, 10y, 16y, 21y,",
    "26y, 29y, 34y, 38y, 42y, 46y, 51y).",
    "",
    "THIS IS THE WEAKEST SIBLING IN THE FAMILY AND THE ONE MOST WORTH",
    "REVIEWING. Read this whole note before using it.",
    "",
    "SOURCE. 21y bcs21yearsample `region`, 'Survey region at interview',",
    "coded 1-15 with NO documented missing codes at all",
    "(spss_user_missing_values is empty).",
    "",
    "IT IS A FIELDWORK REGION, NOT A REGION OF RESIDENCE. Every other",
    "sibling draws on a variable explicitly labelled 'Region of residence'",
    "(or, at 51y, 'Region of interview'). This one is a survey/fieldwork",
    "region: its 15 categories split out conurbations for sampling purposes",
    "- 'Mersey', 'Manchester', 'West Yorkshire', 'South Yorkshire',",
    "'W Midlands Conurbation' - and it is neither the Standard Region scheme",
    "used at 0y-10y nor the Government Office Region scheme used at 16y+. It",
    "is a third scheme, and the 21y sweep deposits no alternative.",
    "",
    "WHAT THIS SCRIPT DOES ABOUT THAT. The 15 categories are aggregated UP to",
    "the family's canonical GOR vocabulary, but ONLY where the aggregation is",
    "definitional and lossless - i.e. where a category is unambiguously a",
    "sub-area of exactly one GOR:",
    "  2 North West + 3 Mersey + 4 Manchester            -> 'North West'",
    "  5 West Yorkshire + 6 Yorkshire & Humberside",
    "    + 7 South Yorkshire                             -> 'Yorkshire and",
    "                                                       the Humber'",
    "  14 West Midlands + 15 W Midlands Conurbation      -> 'West Midlands'",
    "  8 East Midlands, 10 South East, 11 London,",
    "  12 South West, 13 Wales                           -> unchanged",
    "Merseyside and Greater Manchester are by definition within the North",
    "West; West and South Yorkshire within Yorkshire and the Humber; the West",
    "Midlands conurbation within the West Midlands. Collapsing them loses",
    "sub-regional detail but cannot misplace anyone. '10 South East' maps to",
    "the bare 'South East' because London is coded separately at 11, matching",
    "the GOR split.",
    "",
    "TWO CATEGORIES ARE DELIBERATELY *NOT* MAPPED, and keep their own label",
    "so they cannot be silently pooled with a GOR category they do not equal:",
    "  - 1 'North' spans GOR 'North East' PLUS Cumbria (which GOR assigns to",
    "    'North West'). Sending it to 'North East' would misplace every",
    "    Cumbrian case; sending it to NA would delete the entire North East",
    "    at this sweep. It is emitted as 'North', the same string the 0y/5y/",
    "    10y Standard Region siblings use for the same area.",
    "  - 9 'Anglia' is emitted as 'Anglia', not 'East of England'. The two",
    "    are close but not equal - the Anglia fieldwork area reaches into",
    "    Northamptonshire, which GOR puts in the East Midlands - and no",
    "    crosswalk between them is documented anywhere in this repo.",
    "Both mappings would be my inference rather than anything the deposit",
    "states, and CONTRIBUTING.md forbids inventing a coding scheme. If a",
    "maintainer with the 21y user guide can confirm the boundaries, either",
    "could be folded into the canonical vocabulary later; until then the",
    "distinct strings make the gap visible instead of hiding it.",
    "",
    "SCOTLAND AND NORTHERN IRELAND HAVE NO CODE AT ALL in this variable - the",
    "15 categories cover England and Wales only. So `region_21y` can never",
    "take the values 'Scotland' or 'Northern Ireland', even though the 16y",
    "and 26y siblings either side of it can. That is a property of the 21y",
    "sample frame, not a bug in this script, and it will show up as a real",
    "discontinuity in any 16y -> 21y -> 26y migration table. Anyone doing",
    "such a table should exclude 21y or treat it separately.",
    "",
    "MISSING VALUES. Following DATA_KNOWLEDGE.md, the 15 documented codes are",
    "allow-listed and everything else falls through to NA. This matters more",
    "than usual here because the variable documents no sentinels whatsoever,",
    "and DATA_KNOWLEDGE.md explicitly warns that such a variable may still",
    "contain them in the real file. Note also that bcs21yearsample is one of",
    "the two files DATA_KNOWLEDGE.md flags for `bcsid` values that do not",
    "match the study's usual B-prefixed pattern; that is handled upstream by",
    "clean_identifiers() in R/lib/io.R and needs nothing here.",
    "",
    "VERIFIED against real data on 2026-07-29 (harness run 5063c1fe, branch",
    "variable/region, schema 5). Aggregate: n = 1,645 rows in this sweep's",
    "file, 10 distinct region labels, 0.0% missing. All harness checks",
    "passed - columns_exact, identifier_present, identifier_unique,",
    "not_all_missing, no_residual_sentinels, reproducible - including the",
    "cross-variable integration run over all 14 variables, which confirms",
    "this sibling joins cleanly on bcsid alongside the other eleven. No",
    "empty strings and no numeric-looking values in the output, so the",
    "code-to-label lookup is complete."
  )
)

derive <- function(data) {
  # 21y fieldwork "survey region", aggregated to the family's canonical GOR
  # vocabulary only where a category is definitionally inside exactly one
  # GOR. Codes 1 and 9 keep their own labels - see the spec notes.
  survey_region_labels <- c(
    # Standard-Region-style "North": GOR North East plus Cumbria, so it is
    # not equal to either GOR region and is left as its own category.
    "1" = "North",
    "2" = "North West",
    "3" = "North West", # Mersey
    "4" = "North West", # Manchester
    "5" = "Yorkshire and the Humber", # West Yorkshire
    "6" = "Yorkshire and the Humber",
    "7" = "Yorkshire and the Humber", # South Yorkshire
    "8" = "East Midlands",
    # Not folded into "East of England": the two are close but not equal.
    "9" = "Anglia",
    "10" = "South East",
    "11" = "London",
    "12" = "South West",
    "13" = "Wales",
    "14" = "West Midlands",
    "15" = "West Midlands" # W Midlands Conurbation
  )

  # No missing codes are documented for this variable, so the allow-list is
  # doing all the work: any negative, 0, or out-of-range value becomes NA.
  code <- suppressWarnings(as.numeric(data[["region"]]))
  region <- unname(survey_region_labels[as.character(code)])

  data.frame(
    bcsid = data$bcsid,
    region_21y = as.character(region),
    stringsAsFactors = FALSE
  )
}
