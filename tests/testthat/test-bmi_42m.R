# ==========================================================================
# Synthetic-data tests for derived variable: bmi_42m
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_42m.R", envir = env)

fixture <- function(height_cm, weight_kg) {
  data.frame(
    bcsid = paste0("B", seq_along(height_cm)),
    c0087 = height_cm,
    c0088 = weight_kg,
    check.names = FALSE
  )
}

test_that("bmi_42m returns the expected shape", {
  result <- env$derive(fixture(c(97, 100, NA), c(15.2, 16.0, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("height is converted from centimetres to metres", {
  # c0087 is "Height in centimetres" and c0088 "Weight in Kilos", so a
  # 97 cm, 15.2 kg child must give 15.2 / 0.97^2, not 15.2 / 97^2.
  result <- env$derive(fixture(97, 15.2))

  expect_equal(result$bmi_42m, 15.2 / 0.97^2)
  expect_false(isTRUE(all.equal(result$bmi_42m, 15.2 / 97^2)))
})

test_that("every documented sentinel becomes NA", {
  # Both columns document -4 Refused, -3 Not stated, -2 Not known, and a
  # value 0 whose label is empty in the dictionary.
  sentinels <- c(-4, -3, -2, 0)

  from_height <- env$derive(fixture(sentinels, rep(15.2, 4)))
  expect_true(all(is.na(from_height$bmi_42m)))

  from_weight <- env$derive(fixture(rep(97, 4), sentinels))
  expect_true(all(is.na(from_weight$bmi_42m)))
})

test_that("the unexplained 0 code cannot survive the unit conversion", {
  # 0 cm would become 0 m and then divide by zero, so the guard has to be
  # applied after converting, not before.
  result <- env$derive(fixture(0, 15.2))

  expect_true(is.na(result$bmi_42m))
  expect_false(is.infinite(result$bmi_42m))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 97, 97), c(15.2, NA, 15.2)))

  expect_true(is.na(result$bmi_42m[1]))
  expect_true(is.na(result$bmi_42m[2]))
  expect_false(is.na(result$bmi_42m[3]))
})

test_that("a height already given in metres falls outside the envelope", {
  # Guards against the mirror-image mistake of assuming metres here because
  # the neighbouring 0y and 16y sweeps use them.
  result <- env$derive(fixture(0.97, 15.2))

  expect_true(is.na(result$bmi_42m))
})

test_that("undocumented sentinels outside the envelope also become NA", {
  result <- env$derive(fixture(c(-1, -8, -9, 999), rep(15.2, 4)))

  expect_true(all(is.na(result$bmi_42m)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    c("97", " 100", "not a number"),
    c("15.2", "16.0", "15.2")
  ))

  expect_equal(result$bmi_42m[1], 15.2 / 0.97^2)
  expect_equal(result$bmi_42m[2], 16.0 / 1.00^2)
  expect_true(is.na(result$bmi_42m[3]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -3), c(NA, -3)))

  expect_type(result$bmi_42m, "double")
  expect_true(all(is.na(result$bmi_42m)))
})
