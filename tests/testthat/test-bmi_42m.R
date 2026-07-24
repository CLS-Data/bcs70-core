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
sys.source("../../R/variables/bmi_42m.R", envir = env)

test_that("bmi_42m converts height (cm) and weight (kg) into kg/m^2", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3", "A4", "A5"),
    c0087 = c(100, -4, -3, 100, 0), # cm; A2/A3 sentinels, A5 unlabelled zero
    c0088 = c(16, 16, 16, -2, 16) # kg; A4 sentinel
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(result$bmi_42m[1], 16 / (1.0^2))
  expect_true(all(is.na(result$bmi_42m[2:5])))
})
