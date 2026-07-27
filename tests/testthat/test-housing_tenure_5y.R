# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_5y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_5y.R", envir = env)

test_that("housing_tenure_5y maps every documented e220 category", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:7),
    e220 = c(1, 2, 3, 4, 5, 6, 7)
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_5y,
    c(
      1L, # Owned Outright     => owner-occupied
      1L, # Being Bought       => owner-occupied
      2L, # Council Rented     => social rented
      3L, # Prv Rent Unfurn    => private rented
      3L, # Prv Rent Furnshd   => private rented
      3L, # Tied to Occup      => private rented
      4L # Other              => other
    )
  )
})

test_that("housing_tenure_5y treats every documented sentinel and NA as missing", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:6),
    e220 = c(-4, -3, -2, -1, NA, 99) # Vague/Not Stated/Not Known/NA/plain NA/undocumented
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_5y)))
})
