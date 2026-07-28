# ==========================================================================
# Derived variable: housing_tenure_5y
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
  id = "housing_tenure_5y",
  label = "Housing tenure of the parental household at the 5y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("f699b"), # 5y
  source_vars = c("e220"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "IMPORTANT - subject of measurement. At 5y the housing questions are put",
    "to the cohort member's parent, so this describes the PARENTAL",
    "household's tenure with the cohort member living in it as a child. It",
    "is not the cohort member's own tenure. The same caveat applies to",
    "housing_tenure_10y and housing_tenure_16y; from housing_tenure_21y",
    "onwards the variable describes the cohort member's own household.",
    "Do not treat the childhood and adult siblings as a single continuous",
    "series without accounting for that change of subject.",
    "",
    "Source: f699b e220 'Tenure of Accommodation'. Its documented value",
    "labels map as: 1 'Owned Outright' and 2 'Being Bought' -> 1; 3 'Council",
    "Rented' -> 2; 4 'Prv Rent Unfurn', 5 'Prv Rent Furnshd' and 6 'Tied to",
    "Occup' -> 3; 7 'Other' -> 4. Tied/employer accommodation is grouped",
    "with private renting rather than 'Other' because it is renting from a",
    "non-social landlord, which is how the later sweeps' rentfrom items",
    "('Employer', 'Company') are treated in the sibling scripts.",
    "",
    "Missing: e220 documents -4 'Vague', -3 'Not Stated', -2 'Not Known' and",
    "-1 'Not Applicable'; all four become NA, as does any undocumented value",
    "outside 1-7, since the recode only ever assigns an output category to a",
    "value whose label is documented in the data dictionary."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # Any value not listed - including the -4/-3/-2/-1 sentinels and NA -
  # falls through to NA.
  tenure <- data$e220

  housing_tenure_5y <- ifelse(tenure %in% c(1, 2), 1L,
    ifelse(tenure %in% 3, 2L,
      ifelse(tenure %in% c(4, 5, 6), 3L,
        ifelse(tenure %in% 7, 4L, NA_integer_)
      )
    )
  )

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_5y = housing_tenure_5y
  )
}
