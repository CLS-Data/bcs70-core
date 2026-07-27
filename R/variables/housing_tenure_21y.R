# ==========================================================================
# Derived variable: housing_tenure_21y
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
  id = "housing_tenure_21y",
  label = "Housing tenure of the cohort member's household at the 21y sweep (4-category)",
  category = "housing",
  github_issue = 8,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-27",
  source_files = c("bcs21yearsample"), # 21y
  source_vars = c("vc113", "vc114"),
  notes = paste(
    "Issue #8: 'Housing tenure at each age', one sibling variable per sweep",
    "that carries a tenure item - see",
    "CONTRIBUTING.md#family-variables-and-multi-concept-requests. Every",
    "sibling harmonises to the same coarse 4-category scheme confirmed with",
    "the requester: 1 = Owner-occupied, 2 = Social rented, 3 = Private",
    "rented, 4 = Other (rent-free, living with parents rent-free, squatting,",
    "other arrangement), NA = missing.",
    "",
    "This is the first sweep where the tenure item describes the COHORT",
    "MEMBER's own housing situation rather than the parental household's -",
    "see housing_tenure_5y/10y/16y, which describe the parental home.",
    "",
    "Sources: bcs21yearsample vc113 'OWN OR RENT ACCOMMODATION' for the",
    "headline tenure, plus vc114 'WHO DO YOU RENT PROPERTY FROM?' to split",
    "renting into social vs private. vc113 maps as: 1 'Own outright' and",
    "2 'Buying on mortgage/loan' -> 1; 3 'Rented-furnished' and",
    "4 'Rented-unfurnished' -> resolved from vc114; 5 'Rented-paying rent to",
    "parents' -> 3, since renting from a parent is renting from a private",
    "(non-social) landlord; 7 'Goes with the job (rent free)' -> 3, matching",
    "how employer/tied accommodation is treated in every other sibling;",
    "6 'Squatting', 8 'Rent free (other)', 9 'Living with parents",
    "(rent-free)' and 10 'Others' -> 4.",
    "",
    "vc114 resolves the two generic renting codes: 1 'LA/New Town' and",
    "2 'Housing association' -> 2; 3 'Employer', 4 'Charitable trust',",
    "5 'Educational establishment', 6 'Student accommodation', 7 'Parent',",
    "8 'Other relative', 9 'Other private landlord' and 10 'Company' -> 3.",
    "11 \"Don't know\" -> NA: where the respondent rents but the landlord",
    "type is unknown, social vs private genuinely cannot be determined, so",
    "the case is left missing rather than defaulted to private renting.",
    "",
    "Missing: neither vc113 nor vc114 documents an SPSS user-missing range",
    "or any negative value label, so the recode assigns NA to anything",
    "outside their documented 1-10 / 1-11 ranges, plus plain NA.",
    "",
    "Considered and rejected: bcs21yearsample also carries home21 'Tenure at",
    "21', a ready-made derived variable. It is not used because its first",
    "category is labelled 'Owned/rented' - conflating owner-occupation with",
    "renting in a single code - which cannot be mapped onto the agreed",
    "scheme. Deriving from vc113 + vc114 keeps this sibling consistent with",
    "the rest of the family."
  )
)

derive <- function(data) {
  # 1 = owner-occupied, 2 = social rented, 3 = private rented, 4 = other.
  tenure <- data$vc113
  rent_from <- data$vc114

  # Landlord type, used only for the two generic "Rented-*" codes.
  # 11 "Don't know" is not listed on either side, so it falls through to NA.
  rented_class <- ifelse(rent_from %in% c(1, 2), 2L,
    ifelse(rent_from %in% c(3, 4, 5, 6, 7, 8, 9, 10), 3L, NA_integer_)
  )

  housing_tenure_21y <- ifelse(tenure %in% c(1, 2), 1L,
    ifelse(tenure %in% c(3, 4), rented_class,
      ifelse(tenure %in% c(5, 7), 3L,
        ifelse(tenure %in% c(6, 8, 9, 10), 4L, NA_integer_)
      )
    )
  )

  data.frame(
    bcsid = data$bcsid,
    housing_tenure_21y = housing_tenure_21y
  )
}
