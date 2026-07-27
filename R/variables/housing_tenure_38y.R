# ==========================================================================
# Derived variable: housing_tenure_38y
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
  id = "housing_tenure_38y",
  label = "Housing tenure of the cohort member's household at the 38y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs_2008_followup"), # 38y
  source_vars = c("b8ten2", "b8rentom"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "Sources: bcs_2008_followup b8ten2 'Home Ownership / Tenure Status' plus",
    "b8rentom 'Where Property Is Rented From' to split renting into social",
    "vs private. Unlike 29y, 34y, 42y and 46y, this sweep's deposit carries",
    "no proxy-reported tenure counterpart in the data dictionary - an",
    "exhaustive search of bcs_2008_followup surfaced only b8ten2 and",
    "b8rentom - so there is no proxy fallback here.",
    "",
    "b8ten2 maps as: 1 'Own - outright', 2 'Own - buying with help of a",
    "mortgage' and 3 'Pay part rent and part mortgage' -> 1, treating shared",
    "equity as owner-occupation as in the other siblings; 4 'Rent it' ->",
    "resolved from b8rentom; 5 'Live here rent-free', 6 'Squatting' and",
    "7 'Other' -> 4.",
    "",
    "b8rentom resolves code 4: 1 'Local Authority' and 2 'Housing",
    "Association/Scottish equiv.' -> 2; 3 'Private landlord', 4 'Parent'",
    "and 5 'Other' -> 3. As at the neighbouring sweeps, a renter whose",
    "landlord type is missing is left NA rather than defaulted to private",
    "renting.",
    "",
    "Missing: both variables document -9 'Refusal', -8 \"Don't Know\",",
    "-2 'Schedule not applicable' and -1 'Item not applicable'; all become",
    "NA, as does any value outside the documented positive ranges."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # No proxy-reported counterpart exists at this sweep.
  tenure <- data$b8ten2
  rent_from <- data$b8rentom

  # Landlord type, used only for headline code 4 "Rent it".
  # The -9/-8/-2/-1 sentinels fall through to NA.
  rented_class <- ifelse(rent_from %in% c(1, 2), 2L,
    ifelse(rent_from %in% c(3, 4, 5), 3L, NA_integer_)
  )

  housing_tenure_38y <- ifelse(tenure %in% c(1, 2, 3), 1L,
    ifelse(tenure %in% 4, rented_class,
      ifelse(tenure %in% c(5, 6, 7), 4L, NA_integer_)
    )
  )

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_38y = housing_tenure_38y
  )
}
