# ==========================================================================
# Derived variable: housing_tenure_42y
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
  id = "housing_tenure_42y",
  label = "Housing tenure of the cohort member's household at the 42y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs70_2012_flatfile"), # 42y
  source_vars = c("B9TEN", "B9PTE", "B9RENTOM"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "Sources: bcs70_2012_flatfile B9TEN 'Home onership/rental tenure' (the",
    "dictionary's label carries that typo) is the cohort member's own answer",
    "and is preferred. B9PTE 'Proxy: Whether owns or rents accommodation' is",
    "answered on the cohort member's behalf and is used only where B9TEN is",
    "missing. B9RENTOM 'Who home is rented from' splits renting into social",
    "vs private. Note this file uses upper-case variable names throughout,",
    "and is one of the two deposits whose identifier column is 'BCSID' - the",
    "runner's load_tab() lowercases the identifier only, so the source_vars",
    "above must stay upper-case.",
    "",
    "Headline tenure: 1 'Own - outright', 2 'Own - buying with help of",
    "mortgage/loan' and 3 'Pay part rent and part mortgage' -> 1, treating",
    "shared equity as owner-occupation as in the other siblings;",
    "4 'Rent it' -> resolved from B9RENTOM; 5 'Live here rent-free, excl",
    "squatting' and 7 'Other' -> 4. B9PTE additionally documents",
    "6 'Squatting' -> 4; B9TEN's own value labels skip 6 entirely, but the",
    "recode accepts it on both variables so the two are handled identically.",
    "",
    "B9RENTOM resolves code 4: 1 'Local Authority' and 2 'Housing",
    "Association/ Scottish Homes etc' -> 2; 3 'Private landlord',",
    "4 'Parent' and 5 'Other' -> 3. As at the neighbouring sweeps, a renter",
    "whose landlord type is missing is left NA rather than defaulted to",
    "private renting.",
    "",
    "Missing: B9TEN and B9PTE document -9 'Refused', -8 \"Don't know\" and",
    "-1 'Not applicable'; B9RENTOM documents -1 'Not applicable'. All become",
    "NA, as does any value outside the documented positive ranges."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  # Self-report first, proxy only where the self-report is missing.
  self_report <- data$B9TEN
  proxy <- data$B9PTE
  rent_from <- data$B9RENTOM

  # Landlord type, used only for headline code 4 "Rent it".
  # The -1 sentinel falls through to NA.
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
    housing_tenure_42y = ifelse(is.na(self_report_class), proxy_class, self_report_class)
  )
}
