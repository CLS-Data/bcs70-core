# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_10y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_10y.R", envir = env)

test_that("housing_tenure_10y maps every documented d2 category", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:7),
    d2 = c(1, 2, 3, 4, 5, 6, 7)
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_10y,
    c(
      1L, # Owned outright             => owner-occupied
      1L, # Being bought               => owner-occupied
      2L, # Rented, Council            => social rented
      3L, # Rented, Private unfurnished => private rented
      3L, # Rented, Private furnished  => private rented
      3L, # Tied to occupation         => private rented
      4L # Other                      => other
    )
  )
})

test_that("housing_tenure_10y treats NA and undocumented codes as missing", {
  # d2 documents no negative sentinels at all - its value_labels_json lists
  # only 1-7 - so anything outside that range must fall through to NA.
  synthetic <- data.frame(
    bcsid = paste0("B", 1:6),
    d2 = c(NA, -1, -2, -3, 0, 8)
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_10y)))
})
