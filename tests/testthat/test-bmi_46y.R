# ==========================================================================
# Synthetic-data tests for derived variable: bmi_46y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/bmi_46y.R", envir = env)

test_that("bmi_46y prefers the nurse-measured pre-derived BMI when present", {
  synthetic <- data.frame(
    bcsid = "A1",
    BD10MBMI = 26.4,
    BD10BMI = 31.0 # self-report, should be ignored
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(result$bmi_46y, 26.4)
})

test_that("bmi_46y falls back to self-report, recoding sentinels to NA", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3"),
    BD10MBMI = c(NA, -8, -9), # A2/A3: measured value is a documented sentinel
    BD10BMI = c(29.2, 24.0, NA) # A3: self-report also missing
  )

  result <- env$derive(synthetic)

  expect_equal(result$bmi_46y, c(29.2, 24.0, NA))
})
