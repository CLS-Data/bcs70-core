# ==========================================================================
# Synthetic-data tests for derived variable: bmi_10y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_10y.R", envir = env)

fixture <- function(height_mm, weight_tenths_kg) {
  data.frame(
    bcsid = paste0("B", seq_along(height_mm)),
    meb17 = height_mm,
    "meb19.1" = weight_tenths_kg,
    check.names = FALSE
  )
}

test_that("bmi_10y returns the expected shape", {
  result <- env$derive(fixture(c(1385, 1420, NA), c(312, 340, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("the fixture really does carry the dotted deposited name", {
  # DATA_KNOWLEDGE.md: names like meb19.1 are valid column names but not
  # valid bare R symbols, and load_tab() preserves them with
  # check.names = FALSE. If check.names mangled this to meb19_1 the test
  # would be exercising a column the real runner never supplies.
  expect_true("meb19.1" %in% names(fixture(1385, 312)))
})

test_that("height is converted from millimetres and weight from tenths of a kg", {
  # meb17 is "CHILD'S HEIGHT IN MMS" and meb19.1 is "CHILD'S WEIGHT IN
  # 10THS OF A KILOGRAM": 1385 mm and 312 tenths mean 1.385 m and 31.2 kg.
  result <- env$derive(fixture(1385, 312))

  expect_equal(result$bmi_10y, 31.2 / 1.385^2)
})

test_that("taking the raw columns at face value would be wrong", {
  # The point of the conversion: without it the answer is off by orders of
  # magnitude while still being a finite, innocuous-looking number.
  result <- env$derive(fixture(1385, 312))

  expect_false(isTRUE(all.equal(result$bmi_10y, 312 / 1385^2)))
  expect_gt(result$bmi_10y, 10)
  expect_lt(result$bmi_10y, 40)
})

test_that("the documented missing code becomes NA", {
  # -8 "Out of range" is the only code either variable declares.
  from_height <- env$derive(fixture(-8, 312))
  expect_true(is.na(from_height$bmi_10y))

  from_weight <- env$derive(fixture(1385, -8))
  expect_true(is.na(from_weight$bmi_10y))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 1385, 1385), c(312, NA, 312)))

  expect_true(is.na(result$bmi_10y[1]))
  expect_true(is.na(result$bmi_10y[2]))
  expect_false(is.na(result$bmi_10y[3]))
})

test_that("a height already given in metres falls outside the envelope", {
  # 1.385 would be a plausible height in metres but is 1.385 mm here, so it
  # must not be silently accepted.
  result <- env$derive(fixture(1.385, 312))

  expect_true(is.na(result$bmi_10y))
})

test_that("undocumented sentinels outside the envelope also become NA", {
  # DATA_KNOWLEDGE.md warns that a variable documenting only one code may
  # still carry others in the real file.
  result <- env$derive(fixture(c(0, -1, -2, -9, 99999), rep(312, 5)))

  expect_true(all(is.na(result$bmi_10y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    c("1385", " 1420", "not a number"),
    c("312", "340", "312")
  ))

  expect_equal(result$bmi_10y[1], 31.2 / 1.385^2)
  expect_equal(result$bmi_10y[2], 34.0 / 1.420^2)
  expect_true(is.na(result$bmi_10y[3]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -8), c(NA, -8)))

  expect_type(result$bmi_10y, "double")
  expect_true(all(is.na(result$bmi_10y)))
})
