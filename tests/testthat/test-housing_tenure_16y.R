# ==========================================================================
# Synthetic-data tests for derived variable: housing_tenure_16y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/housing_tenure_16y.R", envir = env)

# The 16y tenure item is literally named "c6.8" - a name with a dot in it.
# check.names = FALSE is used when building these fixtures so the column
# reaches derive() under exactly the name the real .tab header carries.

test_that("housing_tenure_16y maps every documented c6.8 category", {
  synthetic <- data.frame(
    bcsid = paste0("A", 1:4),
    "c6.8" = c(1, 2, 3, 4),
    check.names = FALSE
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$housing_tenure_16y,
    c(
      1L, # Parents buy/bought  => owner-occupied
      3L, # Rented privately    => private rented
      2L, # Rented from council => social rented
      4L # Something else      => other
    )
  )
})

test_that("housing_tenure_16y treats don't-know, sentinels and NA as missing", {
  synthetic <- data.frame(
    bcsid = paste0("B", 1:5),
    "c6.8" = c(5, -2, -1, NA, 99), # Don't know/Not stated/No questionnaire/NA/undocumented
    check.names = FALSE
  )

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$housing_tenure_16y)))
})

test_that("housing_tenure_16y reads the dotted column name, not a sanitised one", {
  # Guards against a fixture or loader that silently renames c6.8 to c6_8:
  # derive() indexes by the literal string, so a renamed column yields NULL
  # and every row would come back NA even for valid input.
  synthetic <- data.frame(
    bcsid = "A1",
    "c6.8" = 3,
    check.names = FALSE
  )

  expect_equal(names(synthetic)[2], "c6.8")
  expect_equal(env$derive(synthetic)$housing_tenure_16y, 2L)
})
