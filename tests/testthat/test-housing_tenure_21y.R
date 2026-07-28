# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_21y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_21y.R", envir = env)

test_that("housing_tenure_21y maps the vc113 categories that stand alone", {
  # Every vc113 code except 3/4, which need vc114 to resolve. vc114 is set to
  # a social-landlord value throughout to prove it is ignored for these codes.
  synthetic <- data.frame(
    bcsid = paste0("A", 1:8),
    vc113 = c(1, 2, 5, 6, 7, 8, 9, 10),
    vc114 = 1
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_21y,
    c(
      1L, # Own outright                  => owner-occupied
      1L, # Buying on mortgage/loan       => owner-occupied
      3L, # Rented-paying rent to parents => private rented
      4L, # Squatting                     => other
      3L, # Goes with the job (rent free) => private rented
      4L, # Rent free (other)             => other
      4L, # Living with parents rent-free => other
      4L # Others                        => other
    )
  )
})

test_that("housing_tenure_21y resolves generic renting from vc114", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:10),
    vc113 = c(3, 3, 3, 3, 3, 4, 4, 4, 4, 4),
    vc114 = c(1, 2, 3, 9, 10, 4, 5, 6, 7, 8)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_21y,
    c(
      2L, # LA/New Town             => social rented
      2L, # Housing association     => social rented
      3L, # Employer                => private rented
      3L, # Other private landlord  => private rented
      3L, # Company                 => private rented
      3L, # Charitable trust        => private rented
      3L, # Educational establishment => private rented
      3L, # Student accommodation   => private rented
      3L, # Parent                  => private rented
      3L # Other relative          => private rented
    )
  )
})

test_that("housing_tenure_21y leaves renters with an unusable vc114 as missing", {
  # Renting is established, but social vs private cannot be determined, so
  # the case must be NA rather than defaulted to private renting.
  synthetic <- data.frame(
    bcsid = paste0("C", 1:4),
    vc113 = c(3, 4, 3, 4),
    vc114 = c(11, NA, 99, -1) # Don't know / NA / undocumented / undocumented
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_21y)))
})

test_that("housing_tenure_21y treats NA and undocumented vc113 as missing", {
  # Neither vc113 nor vc114 documents a negative sentinel, so anything
  # outside the documented ranges must fall through to NA.
  synthetic <- data.frame(
    bcsid = paste0("D", 1:4),
    vc113 = c(NA, 0, 11, -1),
    vc114 = 1
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_21y)))
})
