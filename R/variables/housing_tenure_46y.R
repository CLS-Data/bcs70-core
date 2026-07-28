# ==========================================================================
# Derived variable: housing_tenure_46y
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
  id = "housing_tenure_46y",
  label = "Housing tenure of the cohort member's household at the 46y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs_age46_main"), # 46y
  source_vars = c("BD10TENURE", "B10TEN", "B10RENTOM"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "Sources: bcs_age46_main BD10TENURE '(Derived) Housing Tenure' is CLS's",
    "own edited tenure variable and is preferred, since it already applies",
    "the sweep's routing and editing rules. B10TEN 'Home ownership/rental",
    "tenure' is the underlying raw question, on the same 1-7 coding, and is",
    "used only where BD10TENURE is missing. B10RENTOM 'Who home is rented",
    "from' splits renting into social vs private. Note this file uses",
    "upper-case variable names throughout, and is one of the two deposits",
    "whose identifier column is 'BCSID' - the runner's load_tab() lowercases",
    "the identifier only, so the source_vars above must stay upper-case.",
    "",
    "This differs from the earlier sweeps, where the fallback is a",
    "proxy-reported answer rather than a raw question: 46y and 51y are the",
    "only sweeps in this family that deposit a ready-made derived tenure",
    "variable usable under the agreed scheme, so they prefer it.",
    "",
    "Headline tenure (both BD10TENURE and B10TEN): 1 'Own outright',",
    "2 'Own, buying with help of mortgage/loan' and 3 'Part rent, part",
    "mortgage (shared equity)' -> 1, treating shared equity as",
    "owner-occupation as in the other siblings; 4 'Rent it' -> resolved from",
    "B10RENTOM; 5 'Live rent-free, incl. relatives/friends', 6 'Squatting'",
    "and 7 'Other' / 'Other arrangement' -> 4.",
    "",
    "B10RENTOM resolves code 4: 1 'A Local Authority' and 2 'A Housing",
    "Association' -> 2; 3 'A Private landlord', 4 'A Parent' and",
    "5 'Someone else' -> 3. As at the neighbouring sweeps, a renter whose",
    "landlord type is missing is left NA rather than defaulted to private",
    "renting.",
    "",
    "Missing: BD10TENURE documents -8 'No information'; B10TEN and",
    "B10RENTOM document -9 'Refused', -8 'Not known' and -1 'Not",
    "applicable'. All become NA, as does any value outside the documented",
    "positive ranges."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # CLS's edited derived variable first, raw question only where it is missing.
  cls_derived <- data$BD10TENURE
  raw_question <- data$B10TEN
  rent_from <- data$B10RENTOM

  # Landlord type, used only for headline code 4 "Rent it".
  # The -9/-8/-1 sentinels fall through to NA.
  rented_class <- ifelse(rent_from %in% c(1, 2), 2L,
    ifelse(rent_from %in% c(3, 4, 5), 3L, NA_integer_)
  )

  classify <- function(tenure) {
    ifelse(tenure %in% c(1, 2, 3), 1L,
      ifelse(tenure %in% 4, rented_class,
        ifelse(tenure %in% c(5, 6, 7), 4L, NA_integer_)
      )
    )
  }

  cls_derived_class <- classify(cls_derived)
  raw_question_class <- classify(raw_question)

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_46y = ifelse(is.na(cls_derived_class), raw_question_class, cls_derived_class)
  )
}
