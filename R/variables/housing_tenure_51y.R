# ==========================================================================
# Derived variable: housing_tenure_51y
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
  id = "housing_tenure_51y",
  label = "Housing tenure of the cohort member's household at the 51y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs11_age51_main"), # 51y
  source_vars = c("bd11tenure", "b11ten", "b11rentom"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "Sources: bcs11_age51_main bd11tenure '(Derived) Housing Tenure' is",
    "CLS's own edited tenure variable and is preferred, since it already",
    "applies the sweep's routing and editing rules. b11ten 'Home",
    "ownership/rental tenure' is the underlying raw question and is used",
    "only where bd11tenure is missing. b11rentom 'Who home is rented from'",
    "splits renting into social vs private. This mirrors housing_tenure_46y;",
    "46y and 51y are the only sweeps in this family that deposit a",
    "ready-made derived tenure variable usable under the agreed scheme.",
    "",
    "Headline tenure (both bd11tenure and b11ten): 1 'Own outright' /",
    "'Own - outright', 2 'Own, buying with help of mortgage/loan' and",
    "3 'Part rent, part mortgage (shared equity)' -> 1, treating shared",
    "equity as owner-occupation as in the other siblings; 4 'Rent it' ->",
    "resolved from b11rentom; 5 'Live rent-free, incl. relatives/friends'",
    "and 7 'Other' / 'Other arrangement' -> 4. Neither variable documents a",
    "squatting code at this sweep (both skip 6), unlike 34y-46y; the recode",
    "still accepts 6 as 'Other' so the family stays uniform.",
    "",
    "b11rentom resolves code 4: 1 'A Local Authority' and 2 'A Housing",
    "Association' -> 2; 3 'A Private landlord', 4 'A Parent or' and",
    "5 'Someone else?' -> 3 (the trailing 'or'/'?' are artefacts of the",
    "showcard wording in the dictionary labels). As at the neighbouring",
    "sweeps, a renter whose landlord type is missing is left NA rather than",
    "defaulted to private renting.",
    "",
    "Missing: bd11tenure documents -8 'No information'; b11ten and",
    "b11rentom document -9 'Refused', -8 \"Don't know\", -3 'Not asked at",
    "case fieldwork stage', -2 'Not asked due to scripting/routing error'",
    "and -1 'Not applicable'. All become NA, as does any value outside the",
    "documented positive ranges."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # CLS's edited derived variable first, raw question only where it is missing.
  cls_derived <- data$bd11tenure
  raw_question <- data$b11ten
  rent_from <- data$b11rentom

  # Landlord type, used only for headline code 4 "Rent it".
  # The -9/-8/-3/-2/-1 sentinels fall through to NA.
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
    housing_tenure_51y = ifelse(is.na(cls_derived_class), raw_question_class, cls_derived_class)
  )
}
