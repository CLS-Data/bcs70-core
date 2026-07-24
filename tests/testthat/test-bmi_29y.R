# ==========================================================================
# Synthetic-data tests for derived variable: bmi_29y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/bmi_29y.R", envir = env)

test_that("bmi_29y prefers self-report height/weight when present", {
  synthetic <- data.frame(
    bcsid = "A1",
    htmetre2 = 1.60, # self-report height, metres
    wtkilos2 = 55, # self-report weight, kg
    htmetres = 1.70, # proxy height, metres (should be ignored)
    wtkilos = 90 # proxy weight, kg (should be ignored)
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(result$bmi_29y, 55 / (1.60^2))
})

test_that("bmi_29y falls back to proxy report when self-report is missing", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3"),
    htmetre2 = c(NA, 0, 1.60),
    wtkilos2 = c(NA, 55, NA), # A3: self-report height present but weight missing
    htmetres = c(1.70, 1.65, 1.70),
    wtkilos = c(65, 60, 65)
  )

  result <- env$derive(synthetic)

  expect_equal(result$bmi_29y[1], 65 / (1.70^2)) # self-report fully missing -> proxy
  expect_equal(result$bmi_29y[2], 60 / (1.65^2)) # self-report height invalid (0) -> proxy
  expect_equal(result$bmi_29y[3], 65 / (1.70^2)) # self-report incomplete (weight NA) -> proxy
})
