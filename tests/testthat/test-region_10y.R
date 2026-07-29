# ==========================================================================
# Synthetic-data tests for derived variable: region_10y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing/region/region_10y.R", envir = env)

# The Standard Region vocabulary, in code order 1-12. Shared by the 0y, 5y
# and 10y siblings; distinct from the GOR vocabulary the 16y+ siblings use.
canonical_ssr <- c(
  "North", "Yorkshire and the Humber", "East Midlands", "East Anglia",
  "South East (incl. London)", "South West", "West Midlands", "North West",
  "Wales", "Scotland", "Northern Ireland", "Overseas"
)

fixture <- function(codes) {
  data.frame(
    bcsid = paste0("B", seq_along(codes)),
    bd3regn = codes,
    check.names = FALSE
  )
}

test_that("region_10y returns the expected shape", {
  result <- env$derive(fixture(c(1, 5, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("every documented Standard Region code maps to its label", {
  result <- env$derive(fixture(1:12))

  expect_equal(result$region_10y, canonical_ssr)
})

test_that("SSR categories that differ from their GOR namesake are labelled distinctly", {
  # THE test that protects this family's central rule: an identical string
  # must mean an identical area. These three SSR categories do NOT equal the
  # similarly-named GOR category the 16y+ siblings emit, so they must never
  # be emitted under the GOR spelling.
  result <- env$derive(fixture(c(1, 4, 5)))

  # SSR "North" spans GOR "North East" plus Cumbria.
  expect_equal(result$region_10y[1], "North")
  expect_false(result$region_10y[1] == "North East")

  # SSR "East Anglia" is a subset of GOR "East of England".
  expect_equal(result$region_10y[2], "East Anglia")
  expect_false(result$region_10y[2] == "East of England")

  # SSR "South East" CONTAINS London; the GOR "South East" excludes it. The
  # bare string is reserved for the GOR meaning.
  expect_equal(result$region_10y[3], "South East (incl. London)")
  expect_false(result$region_10y[3] == "South East")
})

test_that("SSR categories that do match their GOR namesake share the exact string", {
  # The other side of the same rule: where the geography genuinely matches,
  # the strings must be identical so cross-sweep grouping works with no
  # further cleaning.
  result <- env$derive(fixture(c(2, 3, 6, 7, 9, 10, 11)))

  expect_equal(
    result$region_10y,
    c(
      "Yorkshire and the Humber", "East Midlands", "South West",
      "West Midlands", "Wales", "Scotland", "Northern Ireland"
    )
  )
})

test_that("both documented missing codes become NA", {
  # -1 "Unknown" and -2 "Armed Services" are both inside the declared
  # user-missing range. "Armed Services" is substantive - service
  # accommodation, often overseas - but it is not a region.
  result <- env$derive(fixture(c(-1, -2, 3)))

  expect_equal(result$region_10y, c(NA, NA, "East Midlands"))
})

test_that("'Overseas' is kept as a category rather than treated as missing", {
  # Code 12 is a documented, substantive answer about where the cohort member
  # lived. Dropping it would silently understate emigration.
  result <- env$derive(fixture(12))

  expect_equal(result$region_10y, "Overseas")
})

test_that("undocumented and out-of-range codes become NA", {
  result <- env$derive(fixture(c(0, 13, 14, 99, -3, -8, -9)))

  expect_true(all(is.na(result$region_10y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 8)))

  expect_equal(result$region_10y, c(NA, "North West"))
})

test_that("the output is always a character vector, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -1)))

  expect_type(result$region_10y, "character")
  expect_true(all(is.na(result$region_10y)))
})

test_that("codes arriving as character strings are still recognised", {
  result <- env$derive(fixture(c("1", "12", " 9", "not a code")))

  expect_equal(result$region_10y, c("North", "Overseas", "Wales", NA))
})

test_that("no output value ever falls outside the canonical vocabulary", {
  result <- env$derive(fixture(c(-9:0, 1:20)))
  derived <- result$region_10y

  expect_true(all(is.na(derived) | derived %in% canonical_ssr))
})
