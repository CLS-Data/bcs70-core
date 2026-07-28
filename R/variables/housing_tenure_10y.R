# ==========================================================================
# Derived variable: housing_tenure_10y
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
  id = "housing_tenure_10y",
  label = "Housing tenure of the parental household at the 10y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("sn3723"), # 10y
  source_vars = c("d2"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "IMPORTANT - subject of measurement. At 10y the housing questions are",
    "put to the cohort member's parent, so this describes the PARENTAL",
    "household's tenure with the cohort member living in it as a child. It",
    "is not the cohort member's own tenure - see housing_tenure_5y for the",
    "full note on the change of subject at 21y.",
    "",
    "Source: sn3723 d2 'IS ACCOMMODATION OWNED OR RENTED?'. Its documented",
    "value labels are identical in structure to the 5y item and map the same",
    "way: 1 'Owned outright' and 2 'Being bought' -> 1; 3 'Rented, Council'",
    "-> 2; 4 'Rented, Private unfurnished', 5 'Rented, Private furnished'",
    "and 6 'Tied to occupation' -> 3; 7 'Other' -> 4.",
    "",
    "Missing: unlike the 5y item, d2 documents no SPSS user-missing range",
    "and no negative value labels at all - its value_labels_json lists only",
    "1-7. The recode therefore assigns NA to anything outside 1-7, which",
    "covers both plain NA and any undocumented sentinel that turns out to be",
    "present in the real file. This is a case worth checking explicitly when",
    "the script is first run against the real data.",
    "",
    "Note: sn3723 also contains a variable literally named 'c6.8', but at",
    "10y that is 'MOTHER WORKED NONSTANDARD HOURS SATURDAY' - it is",
    "unrelated to the 16y tenure item that shares the same name."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # Any value outside the documented 1-7 range - including NA - becomes NA.
  tenure <- data$d2

  housing_tenure_10y <- ifelse(tenure %in% c(1, 2), 1L,
    ifelse(tenure %in% 3, 2L,
      ifelse(tenure %in% c(4, 5, 6), 3L,
        ifelse(tenure %in% 7, 4L, NA_integer_)
      )
    )
  )

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_10y = housing_tenure_10y
  )
}
