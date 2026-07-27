# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_46y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_46y.R", envir = env)

# bcs_age46_main uses upper-case variable names throughout; the runner
# lowercases only the bcsid identifier column, so these fixtures must keep
# BD10TENURE / B10TEN / B10RENTOM exactly as deposited.

test_that("housing_tenure_46y maps the BD10TENURE categories that stand alone", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:6),
    BD10TENURE = c(1, 2, 3, 5, 6, 7),
    B10TEN = NA_real_,
    B10RENTOM = NA_real_
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_46y,
    c(
      1L, # Own outright                      => owner-occupied
      1L, # Own, buying with mortgage/loan    => owner-occupied
      1L, # Part rent, part mortgage (shared) => owner-occupied
      4L, # Live rent-free                    => other
      4L, # Squatting                         => other
      4L # Other                             => other
    )
  )
})

test_that("housing_tenure_46y resolves renting from B10RENTOM", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:5),
    BD10TENURE = 4, # Rent it
    B10TEN = NA_real_,
    B10RENTOM = c(1, 2, 3, 4, 5)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_46y,
    c(
      2L, # A Local Authority     => social rented
      2L, # A Housing Association => social rented
      3L, # A Private landlord    => private rented
      3L, # A Parent              => private rented
      3L # Someone else          => private rented
    )
  )
})

test_that("housing_tenure_46y falls back to the raw B10TEN when the derived variable is missing", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:4),
    BD10TENURE = c(NA, -8, -8, 1), # NA / No information / No information / valid
    B10TEN = c(2, 4, 7, 4),
    B10RENTOM = c(NA, 2, NA, 1)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_46y,
    c(
      1L, # derived NA              => raw "Own - with mortgage"
      2L, # derived No information  => raw renting + Housing Association
      4L, # derived No information  => raw "Other arrangement"
      1L # derived present         => raw ignored
    )
  )
})

test_that("housing_tenure_46y treats every documented sentinel and NA as missing", {
  synthetic <- data.frame(
    bcsid = paste0("D", 1:5),
    BD10TENURE = c(-8, NA, 99, 4, 4),
    B10TEN = c(-9, -8, -1, NA, NA),
    B10RENTOM = c(NA, NA, NA, -9, -1)
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_46y)))
})
