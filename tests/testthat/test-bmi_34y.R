# ==========================================================================
# Synthetic-data tests for derived variable: bmi_34y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_34y.R", envir = env)

fixture <- function(height_flag = NA, metres = NA, cms = NA,
                    feet = NA, inches = NA,
                    weight_flag = NA, kgs = NA, stones = NA, pounds = NA) {
  parts <- list(
    height_flag, metres, cms, feet, inches,
    weight_flag, kgs, stones, pounds
  )
  n <- max(vapply(parts, length, integer(1)))
  data.frame(
    bcsid = paste0("B", seq_len(n)),
    bd7htun = rep(height_flag, length.out = n),
    bd7htmtr = rep(metres, length.out = n),
    bd7htcms = rep(cms, length.out = n),
    bd7htft = rep(feet, length.out = n),
    bd7htins = rep(inches, length.out = n),
    b7weigh2 = rep(weight_flag, length.out = n),
    b7wtkis2 = rep(kgs, length.out = n),
    b7wtste2 = rep(stones, length.out = n),
    b7wtpod2 = rep(pounds, length.out = n),
    check.names = FALSE
  )
}

test_that("bmi_34y returns the expected shape", {
  result <- env$derive(fixture(
    height_flag = c(1, 1, NA), metres = c(1, 1, NA),
    cms = c(72, 65, NA), weight_flag = c(1, 1, NA),
    kgs = c(70, 60, NA)
  ))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("bd7htun 1 reads the metric pair as metres plus centimetres", {
  result <- env$derive(fixture(
    height_flag = 1, metres = 1, cms = 72,
    weight_flag = 1, kgs = 70
  ))

  expect_equal(result$bmi_34y, 70 / 1.72^2)
})

test_that("bd7htun 2 reads bd7htft and bd7htins, not bd7htft twice", {
  # The deposited label for bd7htft points at itself for the inches
  # companion - "(Derived) height (feet:see bd7htft for inches)" - which is
  # a typo. The inches column is bd7htins.
  expected_height <- (5 * 12 + 9) * 0.0254
  expected_weight <- (11 * 14 + 4) * 0.45359237

  result <- env$derive(fixture(
    height_flag = 2, feet = 5, inches = 9,
    weight_flag = 2, stones = 11, pounds = 4
  ))

  expect_equal(result$bmi_34y, expected_weight / expected_height^2)
})

test_that("the flag decides which system wins when both are populated", {
  metric_first <- env$derive(fixture(
    height_flag = 1, metres = 1, cms = 72,
    feet = 5, inches = 9,
    weight_flag = 1, kgs = 70,
    stones = 11, pounds = 4
  ))
  expect_equal(metric_first$bmi_34y, 70 / 1.72^2)

  imperial_first <- env$derive(fixture(
    height_flag = 2, metres = 1, cms = 72,
    feet = 5, inches = 9,
    weight_flag = 2, kgs = 70,
    stones = 11, pounds = 4
  ))
  expect_equal(
    imperial_first$bmi_34y,
    (11 * 14 + 4) * 0.45359237 / ((5 * 12 + 9) * 0.0254)^2
  )
})

test_that("the other system is still used when the flagged one is empty", {
  result <- env$derive(fixture(
    height_flag = 1, feet = 5, inches = 9,
    weight_flag = 1, stones = 11, pounds = 4
  ))

  expect_equal(
    result$bmi_34y,
    (11 * 14 + 4) * 0.45359237 / ((5 * 12 + 9) * 0.0254)^2
  )
})

test_that("every documented sentinel becomes NA", {
  # bd7ht* document -7 "Other missing" and -1 "Not applicable"; the b7wt*
  # weight columns add -9 "Refusal" and -8 "Don't Know".
  sentinels <- c(-9, -8, -7, -1)

  height_sentinel <- env$derive(fixture(
    height_flag = 1, metres = sentinels,
    cms = sentinels, feet = sentinels,
    inches = sentinels,
    weight_flag = 1, kgs = rep(70, 4)
  ))
  expect_true(all(is.na(height_sentinel$bmi_34y)))

  weight_sentinel <- env$derive(fixture(
    height_flag = 1, metres = rep(1, 4),
    cms = rep(72, 4), weight_flag = 1,
    kgs = sentinels, stones = sentinels,
    pounds = sentinels
  ))
  expect_true(all(is.na(weight_sentinel$bmi_34y)))
})

test_that("weight flag 3 'Cannot give estimate' still resolves nothing usable", {
  result <- env$derive(fixture(
    height_flag = 1, metres = 1, cms = 72,
    weight_flag = 3, kgs = -1, stones = -1,
    pounds = -1
  ))

  expect_true(is.na(result$bmi_34y))
})

test_that("a whole height deposited in the centimetres column is still read correctly", {
  result <- env$derive(fixture(
    height_flag = 1, metres = NA, cms = 172,
    weight_flag = 1, kgs = 70
  ))

  expect_equal(result$bmi_34y, 70 / 1.72^2)
})

test_that("a missing minor component is treated as zero, a missing major one is not", {
  with_minor_missing <- env$derive(fixture(
    height_flag = 2, feet = 6,
    weight_flag = 2, stones = 12
  ))
  expect_equal(
    with_minor_missing$bmi_34y,
    (12 * 14) * 0.45359237 / ((6 * 12) * 0.0254)^2
  )

  with_major_missing <- env$derive(fixture(
    height_flag = 2, inches = 9,
    weight_flag = 2, pounds = 4
  ))
  expect_true(is.na(with_major_missing$bmi_34y))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(
    height_flag = c(1, 1), metres = c(NA, 1),
    cms = c(NA, 72), weight_flag = c(1, 1),
    kgs = c(70, NA)
  ))

  expect_true(all(is.na(result$bmi_34y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    height_flag = c("1", "1"), metres = c("1", "1"),
    cms = c("72", "65"), weight_flag = c("1", "1"),
    kgs = c("70", "not a number")
  ))

  expect_equal(result$bmi_34y[1], 70 / 1.72^2)
  expect_true(is.na(result$bmi_34y[2]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(height_flag = c(NA, -1), weight_flag = c(NA, -1)))

  expect_type(result$bmi_34y, "double")
  expect_true(all(is.na(result$bmi_34y)))
})
