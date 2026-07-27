# ==========================================================================
# Derived variable: housing_tenure_26y
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
  id = "housing_tenure_26y",
  label = "Housing tenure of the cohort member's household at the 26y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs96x"), # 26y
  source_vars = c("b960421"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "Source: bcs96x b960421 'Tenure of current address'. This is the last",
    "sweep whose single tenure item resolves social vs private renting on",
    "its own - from 29y onwards a companion 'who do you rent from' variable",
    "is needed. It maps as: 1 'Own outright' and 2 'Buying on mortgage' ->",
    "1; 3 'Rented (LA/HA)' -> 2; 4 'Rented (private)' -> 3;",
    "5 'Rented (other)' -> 3, since it is renting from a landlord that is",
    "explicitly not local-authority or housing-association, i.e. a",
    "non-social landlord; 6 'Parents (pays rent)' -> 3, consistent with the",
    "21y treatment of renting from a parent; 7 'Parents (rent-free)' and",
    "8 'Other arrangement' -> 4.",
    "",
    "Missing: b960421 documents -8 'Inappropriate Answer', -2 'Does Not",
    "Apply' and -1 'Not Answered'; all three become NA, as does any value",
    "outside 1-8."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # The -8/-2/-1 sentinels and NA all fall through to NA.
  tenure <- data$b960421

  housing_tenure_26y <- ifelse(tenure %in% c(1, 2), 1L,
    ifelse(tenure %in% 3, 2L,
      ifelse(tenure %in% c(4, 5, 6), 3L,
        ifelse(tenure %in% c(7, 8), 4L, NA_integer_)
      )
    )
  )

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_26y = housing_tenure_26y
  )
}
