# ==========================================================================
# Synthetic-data tests for derived variable: parental_employment_status_father_0y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source(
  "../../R/variables/employment/parental_employment_status/parental_employment_status_father_0y.R",
  envir = env
)

test_that("parental_employment_status_father_0y derives correctly on synthetic data", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3", "A4", "A5", "A6"),
    a0015 = c(1, 2, -3, -2, -1, NA)
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result[[env$spec$id]],
    c("Employed", "Not employed", NA, NA, NA, NA)
  )
})
