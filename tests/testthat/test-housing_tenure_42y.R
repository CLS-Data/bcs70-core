# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_42y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_42y.R", envir = env)

# bcs70_2012_flatfile uses upper-case variable names throughout; the runner
# lowercases only the bcsid identifier column, so these fixtures must keep
# B9TEN / B9PTE / B9RENTOM exactly as deposited.

test_that("housing_tenure_42y maps the B9TEN categories that stand alone", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:6),
    B9TEN = c(1, 2, 3, 5, 6, 7),
    B9PTE = NA_real_,
    B9RENTOM = NA_real_
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_42y,
    c(
      1L, # Own - outright              => owner-occupied
      1L, # Own - buying with mortgage  => owner-occupied
      1L, # Pay part rent part mortgage => owner-occupied
      4L, # Live here rent-free         => other
      4L, # Squatting (B9PTE-only label, accepted on both) => other
      4L # Other                       => other
    )
  )
})

test_that("housing_tenure_42y resolves renting from B9RENTOM", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:5),
    B9TEN = 4, # Rent it
    B9PTE = NA_real_,
    B9RENTOM = c(1, 2, 3, 4, 5)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_42y,
    c(
      2L, # Local Authority                    => social rented
      2L, # Housing Association/Scottish Homes => social rented
      3L, # Private landlord                   => private rented
      3L, # Parent                             => private rented
      3L # Other                              => private rented
    )
  )
})

test_that("housing_tenure_42y falls back to the proxy report when B9TEN is missing", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:4),
    B9TEN = c(NA, -9, -8, 1), # NA / Refused / Don't know / valid self-report
    B9PTE = c(6, 4, 2, 4),
    B9RENTOM = c(NA, 1, NA, 1)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_42y,
    c(
      4L, # self-report NA         => proxy "Squatting"
      2L, # self-report Refused    => proxy renting + Local Authority
      1L, # self-report Don't know => proxy "Own - with mortgage"
      1L # self-report present    => proxy ignored
    )
  )
})

test_that("housing_tenure_42y treats every documented sentinel and NA as missing", {
  synthetic <- data.frame(
    bcsid = paste0("D", 1:5),
    B9TEN = c(-9, -8, -1, NA, 4),
    B9PTE = c(-9, -8, -1, NA, NA),
    B9RENTOM = c(NA, NA, NA, NA, -1)
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_42y)))
})
