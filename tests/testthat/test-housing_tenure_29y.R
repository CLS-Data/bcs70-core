# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_29y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_29y.R", envir = env)

test_that("housing_tenure_29y maps the tenure2 categories that stand alone", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:6),
    tenure2 = c(1, 2, 3, 5, 6, 7),
    tenure = NA_real_,
    rentfrom = NA_real_
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_29y,
    c(
      1L, # Own - outright      => owner-occupied
      1L, # Own - with mortgage => owner-occupied
      1L, # Shared ownership    => owner-occupied
      4L, # Live rent-free      => other
      4L, # Squatting           => other
      4L # Other               => other
    )
  )
})

test_that("housing_tenure_29y resolves renting from rentfrom", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:11),
    tenure2 = 4, # Rent it
    tenure = NA_real_,
    rentfrom = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_29y,
    c(
      2L, # Local Authority                        => social rented
      2L, # Housing Association/Scottish Homes     => social rented
      3L, # Employer - rent free                   => private rented
      3L, # Employer - pays rent                   => private rented
      3L, # Other private landlord                 => private rented
      3L, # Charitable trust                       => private rented
      3L, # Student accommodation/educational trust => private rented
      3L, # Parent                                 => private rented
      3L, # Other relative                         => private rented
      3L, # Company                                => private rented
      3L # Other                                  => private rented
    )
  )
})

test_that("housing_tenure_29y falls back to the proxy report when tenure2 is missing", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:4),
    tenure2 = c(NA, 8, 9, 2), # NA / Dont know / Not answered / valid self-report
    tenure = c(1, 4, 5, 4), # proxy report, in the same row order as tenure2
    rentfrom = c(NA, 1, NA, 1)
  )

  result <- env$derive(synthetic)

  expect_equal(
    result$housing_tenure_29y,
    c(
      1L, # self-report NA          => proxy "Own - outright"
      2L, # self-report Dont know   => proxy renting + LA
      4L, # self-report Not answered => proxy rent-free
      1L # self-report present     => proxy ignored
    )
  )
})

test_that("housing_tenure_29y leaves renters with an unusable rentfrom as missing", {
  synthetic <- data.frame(
    bcsid = paste0("D", 1:3),
    tenure2 = 4,
    tenure = NA_real_,
    rentfrom = c(98, 99, NA) # Dont know / Not answered / plain NA
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_29y)))
})

test_that("housing_tenure_29y is missing when both self-report and proxy are unusable", {
  synthetic <- data.frame(
    bcsid = paste0("E", 1:3),
    tenure2 = c(NA, 8, 0),
    tenure = c(NA, 0, NA),
    rentfrom = NA_real_
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_29y)))
})
