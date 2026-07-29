# ==========================================================================
# Derived variable: region_5y
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
  id = "region_5y",
  label = "Region of residence at age 5 (1975), Standard Region, as a string",
  category = "housing",
  github_issue = 20,
  status = "draft",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-29",
  source_files = c("bcs2derived"),
  source_vars = c("BD2REGN"),
  notes = paste(
    "Issue #20: 'region of residence at each age', harmonised to standard",
    "codes, emitted as the STRING label rather than the numeric code. This",
    "is one sibling of the region/ family - one script per sweep that",
    "actually carries a region-of-residence variable (0y, 5y, 10y, 16y, 21y,",
    "26y, 29y, 34y, 38y, 42y, 46y, 51y). 42m and xwave carry none: 42m's",
    "only file (f690) has no region variable, and xwave's response file has",
    "only `cob`, country of BIRTH, which is not residence.",
    "",
    "THIS SWEEP IS ON THE STANDARD REGION (SSR) SCHEME, NOT GOR. Read the",
    "cross-scheme warning below before pooling it with the 16y+ siblings.",
    "",
    "SOURCE. 5y bcs2derived BD2REGN '1975: Standard Region of residence',",
    "coded 1-12 with -1 'Unknown' and -2 'Armed Services' both inside the",
    "declared user-missing range (-1 thru -2).",
    "",
    "THE THREE SCHEMES IN THIS FAMILY. The deposits do not use one region",
    "coding across the life course; they use three, and they are not",
    "interchangeable:",
    "  (a) Standard Region (SSR)  - the only scheme available at 0y, 5y and",
    "      10y. 12 categories.",
    "  (b) Government Office Region (GOR) - available from 16y onwards, and",
    "      the scheme the other siblings use. 12 categories (14 at 46y).",
    "  (c) A fieldwork 'survey region' at 21y, on a third basis again.",
    "",
    "WHY SSR IS NOT CONVERTED TO GOR HERE. SSR and GOR are not nested, so no",
    "lossless crosswalk exists and none is documented in any data dictionary",
    "or user guide in this repo. The boundaries genuinely differ for the",
    "largest English categories:",
    "  - SSR 'North' spans GOR 'North East' PLUS Cumbria (which GOR puts in",
    "    'North West'), so it cannot be split into either.",
    "  - SSR 'South East' CONTAINS Greater London; GOR separates 'London'",
    "    from 'South East'. A 1970 'South East' case cannot be assigned to",
    "    one or the other.",
    "  - SSR 'East Anglia' is a subset of GOR 'East of England', which also",
    "    absorbed Bedfordshire/Hertfordshire/Essex from SSR 'South East'.",
    "Inventing a mapping would fabricate a coding scheme, which",
    "CONTRIBUTING.md and the new-variable skill both forbid. So this sibling",
    "reports the SSR category it actually has.",
    "",
    "LABELS ARE CHOSEN SO THAT AN IDENTICAL STRING MEANS AN IDENTICAL AREA.",
    "That is the actual harmonisation this family performs. Where an SSR",
    "category matches its GOR namesake ('East Midlands', 'West Midlands',",
    "'South West', 'Wales', 'Scotland', 'Northern Ireland', and",
    "'Yorkshire and the Humber' after spelling normalisation) the same string",
    "is used, and pooling across sweeps is safe. Where it does not, the",
    "string differs so the mismatch cannot pass unnoticed:",
    "  - SSR code 1 stays 'North' (never 'North East').",
    "  - SSR code 4 stays 'East Anglia' (never 'East of England').",
    "  - SSR code 5 is emitted as 'South East (incl. London)', deliberately",
    "    NOT the bare 'South East', because the bare string is used by the",
    "    16y+ GOR siblings for an area that EXCLUDES London. This is a",
    "    labelling choice, not a recode: no case is reassigned. It exists",
    "    purely so a naive cross-sweep tabulation cannot silently merge two",
    "    different geographies.",
    "  - SSR code 8 'North West' keeps the bare string, but note it excludes",
    "    Cumbria whereas the GOR 'North West' includes it. This is the one",
    "    residual imprecision in the same-string-same-area rule, kept because",
    "    Cumbria is a very small share of the region and any alternative",
    "    label would be more misleading than informative.",
    "",
    "MISSING VALUES. Following DATA_KNOWLEDGE.md, the 12 documented codes are",
    "allow-listed and everything else - including undocumented sentinels that",
    "may exist in the real file - falls through to NA. Both documented",
    "negatives become NA: -1 'Unknown', and -2 'Armed Services', which is",
    "substantive (service accommodation, frequently overseas) but is not a",
    "region and is declared user-missing by the depositor.",
    "",
    "'Overseas' (code 12) is KEPT as a category rather than set to NA: it is",
    "a documented, substantive answer about where the cohort member lived,",
    "and dropping it would silently understate emigration at birth. It has no",
    "GOR counterpart, so it appears only in the 0y/5y/10y siblings.",
    "",
    "NOT YET VERIFIED against real data - see CONTRIBUTING.md. On the first",
    "real-data run, check that the output contains no empty strings and no",
    "numeric-looking values (either would mean the code-to-label lookup",
    "missed), and that 'Northern Ireland' is present: BCS70 swept Northern",
    "Ireland at birth but not at most later sweeps, so its disappearance",
    "after 0y/5y is expected rather than a bug."
  )
)

derive <- function(data) {
  # Standard Region (SSR) codes documented for BD2REGN. Allow-listing these
  # and letting everything else fall through to NA is safer than
  # deny-listing sentinels - see DATA_KNOWLEDGE.md.
  ssr_labels <- c(
    "1" = "North",
    "2" = "Yorkshire and the Humber",
    "3" = "East Midlands",
    "4" = "East Anglia",
    # Deliberately not the bare "South East": the SSR South East contains
    # London, whereas the GOR "South East" used by the 16y+ siblings does not.
    "5" = "South East (incl. London)",
    "6" = "South West",
    "7" = "West Midlands",
    "8" = "North West",
    "9" = "Wales",
    "10" = "Scotland",
    "11" = "Northern Ireland",
    "12" = "Overseas"
  )

  # -1 "Unknown" and -2 "Armed Services" are both declared user-missing and
  # are absent from the lookup, so they resolve to NA along with anything
  # undocumented.
  code <- suppressWarnings(as.numeric(data[["BD2REGN"]]))
  region <- unname(ssr_labels[as.character(code)])

  data.frame(
    bcsid = data$bcsid,
    region_5y = as.character(region),
    stringsAsFactors = FALSE
  )
}
