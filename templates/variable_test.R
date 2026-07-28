# ==========================================================================
# Synthetic-data tests for derived variable: <id>
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

# Tests stay flat here regardless of how deeply the script is nested; only
# this path reflects the script's category/family directories.
env <- new.env()
sys.source("../../R/variables/<category>/<family>/<id>.R", envir = env)

test_that("<id> derives correctly on synthetic data", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3"),
    a0001 = c(1, -2, NA) # replace with real source_vars / representative values
  )

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  # expect_equal(result[[env$spec$id]], c(expected, values, here))
})
