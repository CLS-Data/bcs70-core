# ==========================================================================
# Synthetic-data tests for derived variable: bmi_26y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/bmi_26y.R", envir = env)

test_that("bmi_26y computes weight_kg / height_m^2 from already-metric inputs", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3", "A4"),
    b960436 = c(1.75, -7, -2, NA), # metres; A2/A3 sentinels, A4 NA
    b960443 = c(80, 80, 80, 80) # kg
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(result$bmi_26y[1], 80 / (1.75^2))
  expect_true(all(is.na(result$bmi_26y[2:4])))
})
