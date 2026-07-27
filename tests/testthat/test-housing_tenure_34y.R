# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_34y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_34y.R", envir = env)

test_that("housing_tenure_34y maps the b7ten2 categories that stand alone", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:6),
    b7ten2 = c(1, 2, 3, 5, 6, 7),
    b7ten = NA_real_,
    b7rentom = NA_real_
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_34y,
    c(
      1L, # Own - outright                 => owner-occupied
      1L, # Own - buying with mortgage/loan => owner-occupied
      1L, # Part rent, part mortgage       => owner-occupied
      4L, # Live here rent-free            => other
      4L, # Squatting                      => other
      4L # Other                          => other
    )
  )
})

test_that("housing_tenure_34y resolves renting from b7rentom", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:5),
    b7ten2 = 4, # Rent it
    b7ten = NA_real_,
    b7rentom = c(1, 2, 3, 4, 5)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_34y,
    c(
      2L, # Local Authority     => social rented
      2L, # Housing Association => social rented
      3L, # Private landlord    => private rented
      3L, # Parent              => private rented
      3L # Other               => private rented
    )
  )
})

test_that("housing_tenure_34y falls back to the proxy report when b7ten2 is missing", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:5),
    b7ten2 = c(NA, -9, -8, -7, 1), # NA / Refusal / Don't Know / Other missing / valid
    b7ten = c(1, 4, 5, 2, 4),
    b7rentom = c(NA, 2, NA, NA, 1)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_34y,
    c(
      1L, # self-report NA           => proxy "Own - outright"
      2L, # self-report Refusal      => proxy renting + Housing Association
      4L, # self-report Don't Know   => proxy rent-free
      1L, # self-report Other missing => proxy "Own - with mortgage"
      1L # self-report present      => proxy ignored
    )
  )
})

test_that("housing_tenure_34y treats sentinels on b7rentom and both tenure vars as missing", {
  synthetic <- data.frame(
    bcsid = paste0("D", 1:5),
    b7ten2 = c(4, 4, -1, -9, NA),
    b7ten = c(NA, NA, -1, -8, NA),
    b7rentom = c(-9, -1, NA, NA, NA)
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_34y)))
})
