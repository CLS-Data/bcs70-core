# ==========================================================================
# Synthetic-data tests for derived variable: bmi_0y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_0y.R", envir = env)

fixture <- function(height, weight) {
  data.frame(
    bcsid = paste0("B", seq_along(height)),
    b0095 = height,
    b0093 = weight,
    check.names = FALSE
  )
}

test_that("bmi_0y returns the expected shape", {
  result <- env$derive(fixture(c(0.83, 0.90, NA), c(11.86, 13.0, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("BMI is weight in kg over height in metres squared", {
  # Values at the user guide's documented medians: height 0.83 m, weight
  # 11.86 kg. The deposited columns are already decimal metres and decimal
  # kilograms, so no unit conversion should happen.
  result <- env$derive(fixture(0.83, 11.86))

  expect_equal(result$bmi_0y, 11.86 / 0.83^2)
})

test_that("the documented range endpoints are kept, not trimmed", {
  # The user guide records height 0.44-1.07 m and weight 6.40-20.41 kg as
  # genuinely observed, so the envelope must be wide enough to admit them.
  result <- env$derive(fixture(c(0.44, 1.07), c(6.40, 20.41)))

  expect_equal(result$bmi_0y, c(6.40 / 0.44^2, 20.41 / 1.07^2))
})

test_that("every documented sentinel becomes NA", {
  # Both columns document -6 UNABLE TO EXAMINE, -3 NOT STATED, -2 NOT
  # KNOWN, -1 NOT APPLICABLE and 0 THE CHILD REFUSED.
  sentinels <- c(-6, -3, -2, -1, 0)

  # Sentinel height with a valid weight.
  from_height <- env$derive(fixture(sentinels, rep(11.86, 5)))
  expect_true(all(is.na(from_height$bmi_0y)))

  # Valid height with a sentinel weight.
  from_weight <- env$derive(fixture(rep(0.83, 5), sentinels))
  expect_true(all(is.na(from_weight$bmi_0y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 0.83, 0.83), c(11.86, NA, 11.86)))

  expect_true(is.na(result$bmi_0y[1]))
  expect_true(is.na(result$bmi_0y[2]))
  expect_false(is.na(result$bmi_0y[3]))
})

test_that("values mis-scaled by a factor of 100 or 1000 become NA", {
  # This is the failure the labels invite: "metres and centimetres" read as
  # centimetres (83) or "kilos and grammes" read as grammes (11860). Both
  # must fall outside the envelope rather than produce a finite BMI.
  result <- env$derive(fixture(c(83, 0.83), c(11.86, 11860)))

  expect_true(all(is.na(result$bmi_0y)))
})

test_that("undocumented sentinels outside the envelope also become NA", {
  # DATA_KNOWLEDGE.md warns that codes absent from a dictionary still occur
  # in the real files, which is why the derivation allow-lists a plausible
  # range rather than deny-listing the five documented codes.
  result <- env$derive(fixture(c(-8, -9, 99), c(11.86, 11.86, 11.86)))

  expect_true(all(is.na(result$bmi_0y)))
})

test_that("values arriving as character strings are still handled", {
  # load_tab() reads with check.names = FALSE and does not coerce types, so
  # a column may reach derive() as character.
  result <- env$derive(fixture(
    c("0.83", " 0.90", "not a number"),
    c("11.86", "13.0", "11.86")
  ))

  expect_equal(result$bmi_0y[1], 11.86 / 0.83^2)
  expect_equal(result$bmi_0y[2], 13.0 / 0.90^2)
  expect_true(is.na(result$bmi_0y[3]))
})

test_that("the output is always numeric, even when wholly missing", {
  # The runner writes this column alongside real values from other rows, so
  # an all-missing input must not collapse to logical NA.
  result <- env$derive(fixture(c(NA, -1), c(NA, -1)))

  expect_type(result$bmi_0y, "double")
  expect_true(all(is.na(result$bmi_0y)))
})
