# ==========================================================================
# Synthetic-data tests for derived variable: region_46y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing/region/region_46y.R", envir = env)

# 46y is the only sweep in the family coding 13 and 14, so its vocabulary is
# the canonical twelve plus Channel Islands and Isle of Man.
canonical_46y <- c(
  "North East", "North West", "Yorkshire and the Humber", "East Midlands",
  "West Midlands", "East of England", "London", "South East", "South West",
  "Wales", "Scotland", "Northern Ireland", "Channel Islands", "Isle of Man"
)

fixture <- function(codes) {
  data.frame(
    bcsid = paste0("B", seq_along(codes)),
    BD10GOR = codes,
    check.names = FALSE
  )
}

test_that("region_46y returns the expected shape", {
  result <- env$derive(fixture(c(1, 7, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("every documented code maps to its canonical label", {
  result <- env$derive(fixture(1:14))

  expect_equal(result$region_46y, canonical_46y)
})

test_that("codes 1-12 agree with the rest of the family", {
  # The whole point of the family is that an identical string means an
  # identical area, so this sweep's first twelve labels must match the
  # canonical vocabulary the 16y-51y siblings emit.
  result <- env$derive(fixture(1:12))

  expect_equal(result$region_46y, canonical_46y[1:12])
})

test_that("the '(pseudo)' label prefix is stripped", {
  # Deposited as "(pseudo) Wales" / "(pseudo) Scotland" / "(pseudo) Northern
  # Ireland" - the prefix only records that a GOR is by definition an
  # England-only unit. Left in place, these would not group with the plain
  # labels every other sibling emits.
  result <- env$derive(fixture(c(10, 11, 12, 13, 14)))

  expect_equal(
    result$region_46y,
    c(
      "Wales", "Scotland", "Northern Ireland", "Channel Islands",
      "Isle of Man"
    )
  )
  expect_false(any(grepl("pseudo", result$region_46y, fixed = TRUE)))
})

test_that("the deposited spelling of code 3 is normalised", {
  result <- env$derive(fixture(3))

  expect_equal(result$region_46y, "Yorkshire and the Humber")
})

test_that("negative codes become NA even though none are documented", {
  # THE test that matters most at this sweep. BD10GOR is the only variable in
  # the family whose dictionary declares no user-missing values at all, and
  # DATA_KNOWLEDGE.md warns that such a variable may still carry sentinels in
  # the real file. derive() allow-lists 1-14, so undocumented negatives
  # cannot leak through as if they were regions.
  result <- env$derive(fixture(c(-1, -2, -8, -9)))

  expect_true(all(is.na(result$region_46y)))
})

test_that("out-of-range codes become NA", {
  result <- env$derive(fixture(c(0, 15, 16, 99)))

  expect_true(all(is.na(result$region_46y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 2)))

  expect_equal(result$region_46y, c(NA, "North West"))
})

test_that("the output is always a character vector, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -1)))

  expect_type(result$region_46y, "character")
  expect_true(all(is.na(result$region_46y)))
})

test_that("codes arriving as character strings are still recognised", {
  result <- env$derive(fixture(c("1", "14", " 7", "not a code")))

  expect_equal(
    result$region_46y,
    c("North East", "Isle of Man", "London", NA)
  )
})

test_that("no output value ever falls outside the canonical vocabulary", {
  result <- env$derive(fixture(c(-9:0, 1:20)))
  derived <- result$region_46y

  expect_true(all(is.na(derived) | derived %in% canonical_46y))
})
