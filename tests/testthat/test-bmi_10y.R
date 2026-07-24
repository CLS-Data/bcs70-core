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
sys.source("../../R/variables/bmi_10y.R", envir = env)

test_that("bmi_10y converts height (mm) and weight (1/10 kg) into kg/m^2", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3", "A4", "A5"),
    meb17 = c(1400, -8, NA, 1400, 0), # mm; A2 sentinel, A3 NA, A5 zero (invalid)
    meb19.1 = c(320, 320, 320, -8, 320) # 1/10 kg; A4 sentinel
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(result$bmi_10y[1], 32 / (1.4^2))
  expect_true(all(is.na(result$bmi_10y[2:5])))
})
