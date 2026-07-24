# ==========================================================================
# Synthetic-data tests for derived variable: bmi_16y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/bmi_16y.R", envir = env)

test_that("bmi_16y prefers the nurse-measured height/weight pair when present", {
  synthetic <- data.frame(
    bcsid = "A1",
    check.names = FALSE
  )
  synthetic[["rd2.1"]] <- 1.60 # measured height, metres
  synthetic[["rd4.1"]] <- 55 # measured weight, kg
  synthetic[["ha1.2"]] <- 1.70 # self-report height, metres (should be ignored)
  synthetic[["ha1.1"]] <- 90 # self-report weight, kg (should be ignored)

  result <- env$derive(synthetic)

  expect_equal(result$bmi_16y, 55 / (1.60^2))
})

test_that("bmi_16y falls back to self-report when the measured pair is missing", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3"),
    check.names = FALSE
  )
  synthetic[["rd2.1"]] <- c(NA, -2, 1.60) # A3: measured height present...
  synthetic[["rd4.1"]] <- c(NA, 55, NA) # ...but A3's measured weight missing
  synthetic[["ha1.2"]] <- c(1.70, 1.65, 1.70)
  synthetic[["ha1.1"]] <- c(65, 60, 65)

  result <- env$derive(synthetic)

  expect_equal(result$bmi_16y[1], 65 / (1.70^2)) # both measured missing -> self-report
  expect_equal(result$bmi_16y[2], 60 / (1.65^2)) # measured height is a sentinel -> self-report
  expect_equal(result$bmi_16y[3], 65 / (1.70^2)) # measured incomplete (weight NA) -> self-report
})
