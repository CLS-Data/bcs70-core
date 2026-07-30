# ==========================================================================
# Derived variable: parental_employment_status_mother_5y
# --------------------------------------------------------------------------
# Save this as R/variables/<category>/<family>/<id>.R - see
# R/variables/README.md. <category> must equal spec$category below, and
# <id> must equal spec$id; both are checked at build time.
#
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
  id = "parental_employment_status_mother_5y",
  label = "Mother's employment status at age 5 (1975): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("f699b"),
  source_vars = c("e205"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - see",
    "parental_employment_status_father_0y.R for the full family-wide note",
    "on sweep coverage and the same-label-different-concept trap this",
    "family avoids.",
    "",
    "THIS SWEEP HAS NO FATHER SIBLING. An exhaustive search of both 5y",
    "home-interview files (f699a, f699b) found father items on",
    "occupational CLASS (e197/e204a, Registrar General social class I-V,",
    "which says what kind of job he holds but never whether he currently",
    "holds one at all) and on work PATTERNS (e198-e203b: away evenings,",
    "works nights/shifts, weeks off through illness or unemployment) but",
    "no direct 'is the father employed' item anywhere. e203b 'Weeks Father",
    "Off Work-Unemployment' comes closest but measures a COUNT of weeks",
    "off, not a current employed/not-employed state, and a count of 0 is",
    "ambiguous between 'never off work' (currently employed) and 'not",
    "asked/not applicable' (see its own -1 'Not Applicable' code) - so it",
    "cannot be read either way with confidence. No father sibling is",
    "scaffolded at 5y for this reason.",
    "",
    "SOURCE (mother). 5y f699b e205 'Mothers Employment', coded 1 'Ft",
    "Housewife', 2 'Regular Wk Away', 3 'Occasnl Wk Away', 4 'Regular Home",
    "Wk', 5 'Occasnl Home Wk', 6 'Has Two Jobs', 7 'Other', 8",
    "'Student-Volun Wk', with -4 'Vague', -3 'Not Stated', -2 'Not Known',",
    "-1 'Not Applicable' documented as non-substantive.",
    "",
    "CODING - THE ONE JUDGEMENT CALL IN THIS SIBLING. This is a",
    "finer-grained scale than the family's shared 'Employed'/'Not",
    "employed' vocabulary, so it is collapsed:",
    "  - 1 'Ft Housewife' -> 'Not employed' - a full-time homemaker is not",
    "    in paid work, matching how the family's binary sweeps (0y, 10y,",
    "    16y, 42m) all treat the non-working case.",
    "  - 2 'Regular Wk Away', 3 'Occasnl Wk Away', 4 'Regular Home Wk', 5",
    "    'Occasnl Home Wk', 6 'Has Two Jobs' -> 'Employed' - all describe",
    "    her actually doing paid work, whether away from or at home,",
    "    regularly or occasionally, in one job or two.",
    "  - 8 'Student-Volun Wk' -> 'Not employed' - a full-time student or",
    "    unpaid volunteer is, by definition, not in PAID employment,",
    "    which is what every other sibling's source variable actually",
    "    asks about.",
    "  - 7 'Other' -> NA - genuinely unclassifiable against the",
    "    employed/not-employed distinction; inventing a side is worse",
    "    than leaving it missing.",
    "  - Any documented negative code, or any undocumented value (per",
    "    DATA_KNOWLEDGE.md's warning that a sentinel list may be",
    "    incomplete), -> NA.",
    "",
    "VERIFIED against real data on 2026-07-30 (harness run 306bc489, branch",
    "variable/parental_employment_status, schema 5). Aggregate: n = 12,995,",
    "1.06% missing, both 'Employed'/'Not employed' levels represented (no",
    "degenerate all-one-category output). All harness checks passed -",
    "columns_exact, identifier_present, identifier_unique, not_all_missing,",
    "reproducible, workspace_writes_confined - including the cross-variable",
    "integration run across all 22 variables in this build, which confirms",
    "this sibling joins cleanly on bcsid alongside the rest of the family.",
    "No row-level or respondent-level data was inspected, only this",
    "aggregate harness summary."
  )
)

derive <- function(data) {
  status <- data$e205
  employment_status_mother <- ifelse(
    status %in% c(2, 3, 4, 5, 6), "Employed",
    ifelse(status %in% c(1, 8), "Not employed", NA_character_)
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_mother_5y = employment_status_mother,
    stringsAsFactors = FALSE
  )
}
