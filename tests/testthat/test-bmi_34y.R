# ==========================================================================
# Synthetic-data tests for derived variable: bmi_34y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/bmi_34y.R", envir = env)

test_that("bmi_34y passes through CLS's pre-derived BMI, recoding sentinels to NA", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3", "A4"),
    bd7bmi = c(24.5, -7, -9, NA) # A2/A3 documented sentinels, A4 genuine NA
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(result$bmi_34y, c(24.5, NA, NA, NA))
})
