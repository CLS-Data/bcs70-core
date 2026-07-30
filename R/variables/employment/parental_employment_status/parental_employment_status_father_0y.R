# ==========================================================================
# Derived variable: parental_employment_status_father_0y
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
  id = "parental_employment_status_father_0y",
  label = "Father's employment status at cohort member's birth (1970): employed or not employed",
  category = "employment",
  github_issue = 25,
  status = "verified",
  author = "Mack Nixon (via Claude Code, variable-deriver agent)",
  created = "2026-07-30",
  source_files = c("bcs7072a"),
  source_vars = c("a0015"),
  notes = paste(
    "Issue #25: 'parental employment status', one variable for the father",
    "and one for the mother, for each available age. This is one sibling",
    "of the parental_employment_status/ family - one script per (parent",
    "role x sweep) combination that actually carries a USABLE",
    "employed/not-employed concept for that parent (see the family-wide",
    "note below, repeated in every sibling, on why some role x sweep",
    "combinations are absent).",
    "",
    "SOURCE. 0y bcs7072a a0015 'Employment Status of the Father', coded 1",
    "'Employed', 2 'Unemployed', with -3 'Not Stated', -2 'Not Known', -1",
    "'NA - Unsupported' all documented as non-substantive. This is the",
    "BIRTH-survey main file; the sweep also contains a second, redundant",
    "question in the 22-month sub-sample file bcs7072b (b0022 'IS FATHER",
    "EMPLOYED PRESENTLY?', Yes/No/On strike, plus its own missing set) -",
    "NOT used here because it is a different, later sub-sample module (22",
    "months post-birth, not birth itself), and a0015 already gives the",
    "same concept at the sweep's own reference point without introducing a",
    "second timing.",
    "",
    "WHY THIS IS A FAMILY, AND WHY IT IS NARROWER THAN 'FATHER AND MOTHER",
    "AT EVERY SWEEP'. The BCS70 deposits ask about the RESIDENT PARENTS'",
    "employment only while the cohort member is a child living with them",
    "(0y, 5y, 10y, 16y, and the 42-month sub-sweep). From 21y onward the",
    "cohort member is themselves an adult, and every 'employment status'",
    "variable from that point on describes the COHORT MEMBER (and later",
    "their partner), never their parents - confirmed by an exhaustive",
    "cross-sweep metadata search that found no father/mother employment",
    "item anywhere from 21y onward. So the family's sweep coverage stops",
    "at 16y (plus 42m), and that is a property of the survey design, not a",
    "gap in this search.",
    "",
    "WITHIN THAT CHILDHOOD WINDOW, ONLY SOME ROLE x SWEEP COMBINATIONS",
    "HAVE A USABLE VARIABLE - THIS IS THE KEY TRAP IN THIS FAMILY. Several",
    "sweeps deposit a variable literally labelled 'Employment status of",
    "father/mother', but at 10y (c4.1a/c4.2a 'CORRECTED EMPLOYMENT",
    "STATUS') and 16y (t12.1/t12.2) that label is used for a JOB-TYPE",
    "classification CONDITIONAL ON ALREADY BEING EMPLOYED (self-employed",
    "with N employees / employee at a given supervisory grade) - its",
    "category list has NO 'unemployed' or 'not working' option at all, so",
    "it cannot answer the plain question 'is this parent employed'.",
    "Treating it as if it were the same concept as a0015 above (which IS a",
    "direct employed/unemployed flag) would silently misclassify every",
    "non-working parent as missing rather than as 'not employed'. This is",
    "a same-LABEL-different-CONCEPT trap that DATA_KNOWLEDGE.md does not",
    "yet record - flagged in this PR's summary for a maintainer to add.",
    "Consequently, each sibling in this family uses only a source variable",
    "that can directly express 'not employed', never the",
    "job-type-conditional variables. The 10y and 16y siblings that DO",
    "exist in this family use a different, purpose-built source (see their",
    "own notes) rather than c4.1a/c4.2a/t12.1/t12.2.",
    "",
    "That in turn means the family is asymmetric by design, not by",
    "oversight: some (parent, sweep) pairs simply have no usable variable,",
    "and those siblings are not scaffolded at all rather than forced from",
    "an unsuitable source:",
    "  - 0y:  father (this script, a0015) AND mother (a0019) - both usable.",
    "  - 5y:  mother only (e205) - no father employed/not-employed item",
    "    exists at 5y, only father's occupational CLASS (e197/e204a,",
    "    Registrar General social class I-V) and behavioural items",
    "    (overnight work, shift work) that never say whether he is",
    "    currently employed at all.",
    "  - 10y: father AND mother, both usable, but via the c2.1-c2.16",
    "    'employment situation' checklist (see their own notes), not",
    "    c4.1a/c4.2a.",
    "  - 16y: father only (c6.16) - no mother employed/not-employed item",
    "    exists at 16y; t12.2 is the job-type-conditional variable",
    "    described above, and oe1.2 ('Source of income - mother's",
    "    employment') asks whether her earnings are a household income",
    "    source, which is a related but distinct question from whether",
    "    she is employed, so it is not used as a substitute.",
    "  - 42m: father AND mother, both usable (c0038, c0039).",
    "  - 21y onward: no parental employment item of any kind (see above).",
    "",
    "CODING. Every sibling in this family collapses its own source scale",
    "down to the SAME two-category vocabulary - 'Employed' / 'Not",
    "employed' - because that is the coarsest concept every contributing",
    "sweep can express in common; collapsing a finer source scale into",
    "these two categories loses no information no sweep actually offers",
    "uniformly, whereas inventing a finer shared scale (e.g.",
    "full-time/part-time) would fabricate distinctions that not every",
    "sibling's source can support. For this sibling specifically: a0015 ==",
    "1 -> 'Employed'; a0015 == 2 -> 'Not employed'; anything else (the",
    "three documented negative codes, or any other undocumented value, per",
    "DATA_KNOWLEDGE.md's warning that a variable's documented sentinel set",
    "is not always complete) -> NA.",
    "",
    "VERIFIED against real data on 2026-07-30 (harness run 306bc489, branch",
    "variable/parental_employment_status, schema 5). Aggregate: n = 15,825,",
    "7.97% missing, both 'Employed'/'Not employed' levels represented (no",
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
  status <- data$a0015
  employment_status_father <- ifelse(
    status == 1, "Employed",
    ifelse(status == 2, "Not employed", NA_character_)
  )

  data.frame(
    bcsid = data$bcsid,
    parental_employment_status_father_0y = employment_status_father,
    stringsAsFactors = FALSE
  )
}
