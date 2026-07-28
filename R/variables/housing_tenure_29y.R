# ==========================================================================
# Derived variable: housing_tenure_29y
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
  id = "housing_tenure_29y",
  label = "Housing tenure of the cohort member's household at the 29y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs2000"), # 29y
  source_vars = c("tenure2", "tenure", "rentfrom"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "Sources: bcs2000 tenure2 'Is current accom owned or rented' is the",
    "cohort member's own answer and is preferred. tenure \"(Proxy) 'Does CM",
    "own or rent home'\" carries the same 1-7 coding but is answered by",
    "someone else on the cohort member's behalf, and is used only where",
    "tenure2 is missing - the same self-report-then-proxy precedence used by",
    "the BMI family at this sweep. rentfrom 'Who does CM rent current accom",
    "from' splits renting into social vs private.",
    "",
    "Headline tenure (both tenure2 and tenure): 1 'Own - outright',",
    "2 'Own - with mortgage' and 3 'Shared ownership' -> 1, since shared",
    "ownership is part-equity owner-occupation; 4 'Rent it' / 'Renting' ->",
    "resolved from rentfrom; 5 'Live rent-free' / 'Rent-free', 6 'Squatting'",
    "and 7 'Other' -> 4. tenure2 additionally documents 8 \"Dont know\" and",
    "9 'Not answered', both NA.",
    "",
    "rentfrom resolves code 4: 1 'Local Authority' and 2 'Housing",
    "Association/Scottish Homes/SHHA' -> 2; 3 'Employer - rent free',",
    "4 'Employer - pays rent', 5 'Other private landlord', 6 'Charitable",
    "trust', 7 'Student accommodation/educational trust', 8 'Parent',",
    "9 'Other relative', 10 'Company' and 11 'Other' -> 3. Code 11 'Other'",
    "is grouped with private renting rather than with category 4 because the",
    "respondent has already said they rent - only the landlord type is",
    "residual, and it is by construction not a social landlord. 98 \"Dont",
    "know\" and 99 'Not answered' -> NA, so a renter whose landlord type is",
    "unknown is left missing rather than defaulted to private renting.",
    "",
    "Missing: none of the three variables documents an SPSS user-missing",
    "range, so the recode assigns NA to anything outside the documented",
    "value ranges, plus plain NA."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # Self-report first, proxy only where the self-report is missing.
  self_report <- data$tenure2
  proxy <- data$tenure
  rent_from <- data$rentfrom

  # Landlord type, used only for headline code 4 "Rent it".
  # 98/99 are not listed on either side, so they fall through to NA.
  rented_class <- ifelse(rent_from %in% c(1, 2), 2L,
    ifelse(rent_from %in% c(3, 4, 5, 6, 7, 8, 9, 10, 11), 3L, NA_integer_)
  )

  classify <- function(tenure) {
    ifelse(tenure %in% c(1, 2, 3), 1L,
      ifelse(tenure %in% 4, rented_class,
        ifelse(tenure %in% c(5, 6, 7), 4L, NA_integer_)
      )
    )
  }

  self_report_class <- classify(self_report)
  proxy_class <- classify(proxy)

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_29y = ifelse(is.na(self_report_class), proxy_class, self_report_class)
  )
}
