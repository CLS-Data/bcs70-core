# ==========================================================================
# Synthetic-data tests for derived variable: parental_employment_status_mother_10y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source(
  "../../R/variables/employment/parental_employment_status/parental_employment_status_mother_10y.R",
  envir = env
)

test_that("parental_employment_status_mother_10y derives correctly on synthetic data", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8"),
    `c2.9` = c(1, NA, NA, NA, NA, 1, NA, NA),
    `c2.10` = c(NA, 1, NA, NA, NA, NA, NA, NA),
    `c2.11` = c(NA, NA, 1, NA, NA, NA, NA, NA),
    `c2.12` = c(NA, NA, NA, 1, NA, NA, NA, NA),
    `c2.13` = c(NA, NA, NA, NA, 1, NA, NA, NA),
    `c2.15` = c(NA, NA, NA, NA, NA, NA, 1, NA),
    `c2.16` = c(NA, NA, NA, NA, NA, 1, NA, NA),
    check.names = FALSE
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result[[env$spec$id]],
    c(
      "Employed", "Employed", "Not employed", "Not employed", "Not employed",
      NA, NA, NA
    )
  )
})
