# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_38y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_38y.R", envir = env)

test_that("housing_tenure_38y maps the b8ten2 categories that stand alone", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:6),
    b8ten2 = c(1, 2, 3, 5, 6, 7),
    b8rentom = NA_real_
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_38y,
    c(
      1L, # Own - outright             => owner-occupied
      1L, # Own - buying with mortgage => owner-occupied
      1L, # Pay part rent part mortgage => owner-occupied
      4L, # Live here rent-free        => other
      4L, # Squatting                  => other
      4L # Other                      => other
    )
  )
})

test_that("housing_tenure_38y resolves renting from b8rentom", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:5),
    b8ten2 = 4, # Rent it
    b8rentom = c(1, 2, 3, 4, 5)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_38y,
    c(
      2L, # Local Authority               => social rented
      2L, # Housing Association/Scottish  => social rented
      3L, # Private landlord              => private rented
      3L, # Parent                        => private rented
      3L # Other                         => private rented
    )
  )
})

test_that("housing_tenure_38y treats every documented sentinel and NA as missing", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:8),
    b8ten2 = c(-9, -8, -2, -1, NA, 99, 4, 4),
    b8rentom = c(NA, NA, NA, NA, NA, NA, -9, -1)
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_38y)))
})
