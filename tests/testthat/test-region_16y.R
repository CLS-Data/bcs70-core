# ==========================================================================
# Synthetic-data tests for derived variable: region_16y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing/region/region_16y.R", envir = env)

# The canonical 12-category vocabulary every 16y+ sibling in this family
# emits, in code order 1-12.
canonical_gor <- c(
  "North East", "North West", "Yorkshire and the Humber", "East Midlands",
  "West Midlands", "East of England", "London", "South East", "South West",
  "Wales", "Scotland", "Northern Ireland"
)

fixture <- function(codes) {
  data.frame(
    bcsid = paste0("B", seq_along(codes)),
    BD4GOR = codes,
    check.names = FALSE
  )
}

test_that("region_16y returns the expected shape", {
  result <- env$derive(fixture(c(1, 7, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("every documented GOR code maps to its canonical label", {
  result <- env$derive(fixture(1:12))

  expect_equal(result$region_16y, canonical_gor)
})

test_that("the deposited label spelling is normalised, not passed through", {
  # This sweep deposits code 3 as "Yorkshire and Humberside"; the family's
  # canonical spelling is "Yorkshire and the Humber". Emitting the raw label
  # would make one region look like four across the family (42y has a typo,
  # "Humberberside"; 46y and 51y differ again on "the"/"The").
  result <- env$derive(fixture(3))

  expect_equal(result$region_16y, "Yorkshire and the Humber")
  expect_false(result$region_16y == "Yorkshire and Humberside")
})

test_that("the documented missing code becomes NA", {
  # -1 "Unknown" is the only declared user-missing value at this sweep.
  result <- env$derive(fixture(c(-1, 5)))

  expect_equal(result$region_16y, c(NA, "West Midlands"))
})

test_that("undocumented and out-of-range codes become NA", {
  # DATA_KNOWLEDGE.md warns that sentinels not named in a dictionary still
  # occur in the real files, which is why derive() allow-lists 1-12 rather
  # than deny-listing known negatives.
  result <- env$derive(fixture(c(0, 13, 14, 99, -2, -8, -9)))

  expect_true(all(is.na(result$region_16y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 2)))

  expect_equal(result$region_16y, c(NA, "North West"))
})

test_that("the output is always a character vector, even when wholly missing", {
  # The runner writes this column alongside real labels from other rows, so
  # an all-missing input must not collapse to logical NA.
  result <- env$derive(fixture(c(NA, -1)))

  expect_type(result$region_16y, "character")
  expect_true(all(is.na(result$region_16y)))
})

test_that("codes arriving as character strings are still recognised", {
  # load_tab() reads with check.names = FALSE and does not coerce types, so
  # a column may reach derive() as character.
  result <- env$derive(fixture(c("1", "12", " 7", "not a code")))

  expect_equal(
    result$region_16y,
    c("North East", "Northern Ireland", "London", NA)
  )
})

test_that("no output value ever falls outside the canonical vocabulary", {
  result <- env$derive(fixture(c(-9:0, 1:20)))
  derived <- result$region_16y

  expect_true(all(is.na(derived) | derived %in% canonical_gor))
})
