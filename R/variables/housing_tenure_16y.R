# ==========================================================================
# Derived variable: housing_tenure_16y
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
  id = "housing_tenure_16y",
  label = "Housing tenure of the parental household at the 16y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs7016x"), # 16y
  source_vars = c("c6.8"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "IMPORTANT - subject of measurement. At 16y the housing questions are",
    "still put to the cohort member's parent, so this describes the PARENTAL",
    "household's tenure. It is not the cohort member's own tenure - see",
    "housing_tenure_5y for the full note on the change of subject at 21y.",
    "",
    "Source: bcs7016x c6.8 'Status of accomodation eg.bought-rented'. Note",
    "the raw variable name contains a dot, so it is read as",
    "data[['c6.8']] rather than data$c6.8; R/lib/io.R loads the .tab files",
    "with check.names = FALSE, so the name survives intact. Its documented",
    "value labels map as: 1 'Parents buy/bought' -> 1 (this sweep has no",
    "separate outright/mortgage split, so all owner-occupation collapses to",
    "one code); 3 'Rented from council' -> 2; 2 'Rented privately' -> 3;",
    "4 'Something else' -> 4.",
    "",
    "Missing: -2 'Not stated', -1 'No questionnaire' and 5 \"Don't know\" all",
    "become NA, as does any value outside 1-4.",
    "",
    "Considered and rejected: bcs7016x also has of3.3 'Is accommodation",
    "rented local auth-coun?', which could in principle back-fill social",
    "renting where c6.8 is missing. It is not used, because its value labels",
    "are 1 'Yes' and 2 'No Response' - the negative case is labelled as a",
    "non-answer rather than a 'No', so a value of 2 cannot be read as",
    "'not local-authority rented' without guessing at the coding. c6.8 is",
    "the direct tenure question and already separates council from private."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # The raw name contains a dot, so index by string rather than with $.
  # Any value outside 1-4 - including 5 "Don't know", the -2/-1 sentinels
  # and NA - becomes NA.
  tenure <- data[["c6.8"]]

  housing_tenure_16y <- ifelse(tenure %in% 1, 1L,
    ifelse(tenure %in% 3, 2L,
      ifelse(tenure %in% 2, 3L,
        ifelse(tenure %in% 4, 4L, NA_integer_)
      )
    )
  )

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_16y = housing_tenure_16y
  )
}
