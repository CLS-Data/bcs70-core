# Tests for R/lib/utils.R, kept independent of any derived variable - shared
# helpers deserve their own coverage, and this also keeps tests/testthat/
# non-empty (testthat::test_dir() errors on a directory with no test files,
# and git doesn't track empty directories at all).

source("../../R/lib/utils.R")

test_that("na_if_negative replaces documented sentinel codes with NA", {
  expect_equal(na_if_negative(c(1, -2, 5, -9)), c(1, NA, 5, NA))
})

test_that("na_if_negative respects a custom code list", {
  expect_equal(na_if_negative(c(1, -2, 5), codes = c(-2)), c(1, NA, 5))
})

test_that("na_if_negative leaves existing NA as NA", {
  expect_equal(na_if_negative(c(NA_real_, 3)), c(NA, 3))
})
