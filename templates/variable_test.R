# Tests for R/variables/<category>/<family>/<id>.R
#
# Save as tests/testthat/test-<id>.R - flat, however deeply the script nests.
# Synthetic rows only: no real data exists in this repository to test against.
# Cover typical values, every documented missing/sentinel code, and NA.

env <- new.env()
sys.source("../../R/variables/<category>/<family>/<id>.R", envir = env)

test_that("<id> recodes as documented", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3"),
    a0001 = c(1, -1, NA), # replace with this variable's real codes
    stringsAsFactors = FALSE
  )

  result <- env$derive(synthetic)

  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(result[[env$spec$id]], c(NA, NA, NA)) # replace with expected
})
