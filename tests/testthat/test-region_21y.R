# ==========================================================================
# Synthetic-data tests for derived variable: region_21y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing/region/region_21y.R", envir = env)

# What region_21y can emit: the canonical GOR categories reachable from the
# 21y fieldwork scheme, plus the two categories deliberately left unmapped.
canonical_21y <- c(
  "North", "North West", "Yorkshire and the Humber", "East Midlands",
  "Anglia", "South East", "London", "South West", "Wales", "West Midlands"
)

fixture <- function(codes) {
  data.frame(
    bcsid = paste0("B", seq_along(codes)),
    region = codes,
    check.names = FALSE
  )
}

test_that("region_21y returns the expected shape", {
  result <- env$derive(fixture(c(1, 11, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("all 15 documented survey-region codes map as specified", {
  result <- env$derive(fixture(1:15))

  expect_equal(
    result$region_21y,
    c(
      "North", # 1  North (SSR-style, left unmapped)
      "North West", # 2  North West
      "North West", # 3  Mersey
      "North West", # 4  Manchester
      "Yorkshire and the Humber", # 5  West Yorkshire
      "Yorkshire and the Humber", # 6  Yorkshire & Humberside
      "Yorkshire and the Humber", # 7  South Yorkshire
      "East Midlands", # 8  East Midlands
      "Anglia", # 9  Anglia (left unmapped)
      "South East", # 10 South East
      "London", # 11 London
      "South West", # 12 South West
      "Wales", # 13 Wales
      "West Midlands", # 14 West Midlands
      "West Midlands" # 15 W Midlands Conurbation
    )
  )
})

test_that("conurbation codes are aggregated into their containing region", {
  # The only aggregation this script performs, and it is lossless: Merseyside
  # and Greater Manchester are definitionally within the North West, West and
  # South Yorkshire within Yorkshire and the Humber, and the West Midlands
  # conurbation within the West Midlands. Left unaggregated, these would each
  # look like a region no other sweep has.
  expect_equal(
    unique(env$derive(fixture(c(2, 3, 4)))$region_21y), "North West"
  )
  expect_equal(
    unique(env$derive(fixture(c(5, 6, 7)))$region_21y),
    "Yorkshire and the Humber"
  )
  expect_equal(
    unique(env$derive(fixture(c(14, 15)))$region_21y), "West Midlands"
  )
})

test_that("the two ambiguous categories are NOT folded into a GOR category", {
  # THE regression test for this sibling. Code 1 "North" spans GOR "North
  # East" plus Cumbria, and code 9 "Anglia" is not equal to GOR "East of
  # England". Mapping either would misplace real cases on an inference no
  # data dictionary in this repo supports, so both keep their own label.
  result <- env$derive(fixture(c(1, 9)))

  expect_equal(result$region_21y, c("North", "Anglia"))
  expect_false(any(result$region_21y == "North East"))
  expect_false(any(result$region_21y == "East of England"))
})

test_that("Scotland and Northern Ireland are unreachable at this sweep", {
  # The 21y survey region covers England and Wales only - there is no code
  # for Scotland or Northern Ireland. This is a property of the sample frame,
  # and it means a 16y -> 21y -> 26y migration table will show a real
  # discontinuity rather than a coding error.
  result <- env$derive(fixture(1:15))

  expect_false(any(result$region_21y %in% c("Scotland", "Northern Ireland")))
})

test_that("negative codes become NA even though none are documented", {
  # This variable declares no user-missing values at all, and
  # DATA_KNOWLEDGE.md warns that such a variable may still carry sentinels in
  # the real file. derive() allow-lists 1-15 for exactly this reason.
  result <- env$derive(fixture(c(-1, -2, -3, -8, -9)))

  expect_true(all(is.na(result$region_21y)))
})

test_that("out-of-range codes become NA", {
  result <- env$derive(fixture(c(0, 16, 17, 99)))

  expect_true(all(is.na(result$region_21y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 11)))

  expect_equal(result$region_21y, c(NA, "London"))
})

test_that("the output is always a character vector, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -1)))

  expect_type(result$region_21y, "character")
  expect_true(all(is.na(result$region_21y)))
})

test_that("codes arriving as character strings are still recognised", {
  result <- env$derive(fixture(c("3", "15", " 11", "not a code")))

  expect_equal(
    result$region_21y,
    c("North West", "West Midlands", "London", NA)
  )
})

test_that("no output value ever falls outside the documented vocabulary", {
  result <- env$derive(fixture(c(-9:0, 1:25)))
  derived <- result$region_21y

  expect_true(all(is.na(derived) | derived %in% canonical_21y))
})
