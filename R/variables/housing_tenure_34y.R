# ==========================================================================
# Derived variable: housing_tenure_34y
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
  id = "housing_tenure_34y",
  label = "Housing tenure of the cohort member's household at the 34y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs_2004_followup"), # 34y
  source_vars = c("b7ten2", "b7ten", "b7rentom"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "Sources: bcs_2004_followup b7ten2 'Home ownership / tenure status' is",
    "the cohort member's own answer and is preferred. b7ten \"(Proxy) Cohort",
    "Member's home ownership / tenure status\" carries the same coding but is",
    "answered on the cohort member's behalf, and is used only where b7ten2",
    "is missing. b7rentom 'Where property is rented from' splits renting",
    "into social vs private.",
    "",
    "Headline tenure (both b7ten2 and b7ten): 1 'Own - outright', 2 'Own -",
    "buying with help of a mortgage/loan' and 3 'Pay part rent and part",
    "mortgage (shared/equity ownership)' -> 1, treating shared equity as",
    "owner-occupation as in the other siblings; 4 'Rent it' -> resolved from",
    "b7rentom; 5 'Live here rent-free, including rent-free in relatives'/",
    "friend's', 6 'Squatting' and 7 'Other' -> 4.",
    "",
    "b7rentom resolves code 4: 1 'Local Authority' and 2 'Housing",
    "Association/Scottish Homes/SHHA' -> 2; 3 'Private landlord',",
    "4 'Parent' and 5 'Other' -> 3. As at 29y, a renter whose landlord type",
    "is missing is left NA rather than defaulted to private renting.",
    "",
    "Missing: b7ten2 and b7rentom document -9 'Refusal', -8 \"Don't Know\",",
    "-7 'Other missing' and -1 'Not applicable'; b7ten documents -9, -8 and",
    "-1. All become NA, as does any value outside the documented positive",
    "ranges."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # Self-report first, proxy only where the self-report is missing.
  self_report <- data$b7ten2
  proxy <- data$b7ten
  rent_from <- data$b7rentom

  # Landlord type, used only for headline code 4 "Rent it".
  # The -9/-8/-7/-1 sentinels fall through to NA.
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

  self_report_class <- classify(self_report)
  proxy_class <- classify(proxy)

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_34y = ifelse(is.na(self_report_class), proxy_class, self_report_class)
  )
}
