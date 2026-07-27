# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_51y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_51y.R", envir = env)

test_that("housing_tenure_51y maps the bd11tenure categories that stand alone", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:5),
    bd11tenure = c(1, 2, 3, 5, 7),
    b11ten = NA_real_,
    b11rentom = NA_real_
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_51y,
    c(
      1L, # Own outright                      => owner-occupied
      1L, # Own, buying with mortgage/loan    => owner-occupied
      1L, # Part rent, part mortgage (shared) => owner-occupied
      4L, # Live rent-free                    => other
      4L # Other                             => other
    )
  )
})

test_that("housing_tenure_51y resolves renting from b11rentom", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:5),
    bd11tenure = 4, # Rent it
    b11ten = NA_real_,
    b11rentom = c(1, 2, 3, 4, 5)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_51y,
    c(
      2L, # A Local Authority     => social rented
      2L, # A Housing Association => social rented
      3L, # A Private landlord    => private rented
      3L, # A Parent              => private rented
      3L # Someone else          => private rented
    )
  )
})

test_that("housing_tenure_51y falls back to the raw b11ten when the derived variable is missing", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:4),
    bd11tenure = c(NA, -8, -8, 1), # NA / No information / No information / valid
    b11ten = c(2, 4, 5, 4),
    b11rentom = c(NA, 1, NA, 2)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_51y,
    c(
      1L, # derived NA             => raw "Own - with mortgage"
      2L, # derived No information => raw renting + Local Authority
      4L, # derived No information => raw rent-free
      1L # derived present        => raw ignored
    )
  )
})

test_that("housing_tenure_51y treats every documented sentinel and NA as missing", {
  # b11ten and b11rentom carry the widest sentinel set in the family:
  # -9 Refused, -8 Don't know, -3 not asked at case fieldwork stage,
  # -2 not asked due to scripting/routing error, -1 not applicable.
  synthetic <- data.frame(
    bcsid = paste0("D", 1:7),
    bd11tenure = c(-8, -8, -8, -8, -8, NA, 4),
    b11ten = c(-9, -8, -3, -2, -1, NA, NA),
    b11rentom = c(NA, NA, NA, NA, NA, NA, -3)
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_51y)))
})
