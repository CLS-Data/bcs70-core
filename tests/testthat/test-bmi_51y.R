# ==========================================================================
# Synthetic-data tests for derived variable: bmi_51y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_51y.R", envir = env)

fixture <- function(height_m, weight_kg) {
  data.frame(
    bcsid = paste0("B", seq_along(height_m)),
    bd11hghtm = height_m,
    bd11wghtk = weight_kg,
    check.names = FALSE
  )
}

test_that("bmi_51y returns the expected shape", {
  result <- env$derive(fixture(c(1.72, 1.65, NA), c(82, 66, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("the body-weight column is used, not one of the survey weights", {
  # bcs11_age51_main also carries bd11weight_main, bd11weight_psc and
  # bd11weight_odq, which are non-response weights and nothing to do with
  # kilograms.
  expect_equal(env$spec$source_vars, c("bd11hghtm", "bd11wghtk"))
  expect_false(any(grepl("weight", env$spec$source_vars)))
})

test_that("BMI is weight in kg over height in metres squared", {
  result <- env$derive(fixture(1.72, 82))

  expect_equal(result$bmi_51y, 82 / 1.72^2)
})

test_that("the documented sentinel becomes NA", {
  # -8 "No information" is the only documented code, but DATA_KNOWLEDGE.md
  # records this sweep as carrying a wider set (-9/-8/-3/-2/-1).
  sentinels <- c(-9, -8, -3, -2, -1)

  from_height <- env$derive(fixture(sentinels, rep(82, 5)))
  expect_true(all(is.na(from_height$bmi_51y)))

  from_weight <- env$derive(fixture(rep(1.72, 5), sentinels))
  expect_true(all(is.na(from_weight$bmi_51y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 1.72, 1.72), c(82, NA, 82)))

  expect_true(is.na(result$bmi_51y[1]))
  expect_true(is.na(result$bmi_51y[2]))
  expect_false(is.na(result$bmi_51y[3]))
})

test_that("a height given in centimetres falls outside the envelope", {
  result <- env$derive(fixture(172, 82))

  expect_true(is.na(result$bmi_51y))
})

test_that("undocumented sentinels outside the envelope also become NA", {
  result <- env$derive(fixture(c(0, 96, 999), rep(82, 3)))

  expect_true(all(is.na(result$bmi_51y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    c("1.72", " 1.65", "not a number"),
    c("82", "66", "82")
  ))

  expect_equal(result$bmi_51y[1], 82 / 1.72^2)
  expect_equal(result$bmi_51y[2], 66 / 1.65^2)
  expect_true(is.na(result$bmi_51y[3]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -8), c(NA, -8)))

  expect_type(result$bmi_51y, "double")
  expect_true(all(is.na(result$bmi_51y)))
})
