# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_26y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_26y.R", envir = env)

test_that("housing_tenure_26y maps every documented b960421 category", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:8),
    b960421 = c(1, 2, 3, 4, 5, 6, 7, 8)
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_26y,
    c(
      1L, # Own outright        => owner-occupied
      1L, # Buying on mortgage  => owner-occupied
      2L, # Rented (LA/HA)      => social rented
      3L, # Rented (private)    => private rented
      3L, # Rented (other)      => private rented (non-social landlord)
      3L, # Parents (pays rent) => private rented
      4L, # Parents (rent-free) => other
      4L # Other arrangement   => other
    )
  )
})

test_that("housing_tenure_26y treats every documented sentinel and NA as missing", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:5),
    b960421 = c(-8, -2, -1, NA, 99) # Inappropriate/Does Not Apply/Not Answered/NA/undocumented
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_26y)))
})
