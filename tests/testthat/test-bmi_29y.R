# ==========================================================================
# Synthetic-data tests for derived variable: bmi_29y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_29y.R", envir = env)

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
    height2 = rep(height_flag, length.out = n),
    htmetre2 = rep(metres, length.out = n),
    htcms2 = rep(cms, length.out = n),
    htfeet2 = rep(feet, length.out = n),
    htinche2 = rep(inches, length.out = n),
    weight2 = rep(weight_flag, length.out = n),
    wtkilos2 = rep(kgs, length.out = n),
    wtstone2 = rep(stones, length.out = n),
    wtpound2 = rep(pounds, length.out = n),
    check.names = FALSE
  )
}

metric_row <- function(...) {
  fixture(height_flag = 1, metres = 1, cms = 72, weight_flag = 1, kgs = 70, ...)
}

test_that("bmi_29y returns the expected shape", {
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

test_that("flag 1 reads the metric pair as metres plus centimetres", {
  result <- env$derive(metric_row())

  expect_equal(result$bmi_29y, 70 / 1.72^2)
})

test_that("flag 2 reads the imperial columns with the exact factors", {
  expected_height <- (5 * 12 + 9) * 0.0254
  expected_weight <- (11 * 14 + 4) * 0.45359237

  result <- env$derive(fixture(
    height_flag = 2, feet = 5, inches = 9,
    weight_flag = 2, stones = 11, pounds = 4
  ))

  expect_equal(result$bmi_29y, expected_weight / expected_height^2)
})

test_that("the flag decides which system wins when both are populated", {
  metric_first <- env$derive(fixture(
    height_flag = 1, metres = 1, cms = 72,
    feet = 5, inches = 9,
    weight_flag = 1, kgs = 70,
    stones = 11, pounds = 4
  ))
  expect_equal(metric_first$bmi_29y, 70 / 1.72^2)

  imperial_first <- env$derive(fixture(
    height_flag = 2, metres = 1, cms = 72,
    feet = 5, inches = 9,
    weight_flag = 2, kgs = 70,
    stones = 11, pounds = 4
  ))
  expect_equal(
    imperial_first$bmi_29y,
    (11 * 14 + 4) * 0.45359237 / ((5 * 12 + 9) * 0.0254)^2
  )
})

test_that("the other system is still used when the flagged one is empty", {
  # Flag says metric, but only the imperial columns hold an answer. A blank
  # flag should not throw away an answer that is plainly present either.
  flagged <- env$derive(fixture(
    height_flag = 1, feet = 5, inches = 9,
    weight_flag = 1, stones = 11, pounds = 4
  ))
  expect_equal(
    flagged$bmi_29y,
    (11 * 14 + 4) * 0.45359237 / ((5 * 12 + 9) * 0.0254)^2
  )

  unflagged <- env$derive(fixture(
    height_flag = NA, feet = 5, inches = 9,
    weight_flag = NA, stones = 11, pounds = 4
  ))
  expect_equal(unflagged$bmi_29y, flagged$bmi_29y)
})

test_that("non-informative flag values still resolve a usable answer", {
  # 3 "Cannot give estimate", 8 "Dont know", 9 "Not answered".
  for (flag in c(3, 8, 9)) {
    result <- env$derive(fixture(
      height_flag = flag, metres = 1, cms = 72,
      weight_flag = flag, kgs = 70
    ))
    expect_equal(result$bmi_29y, 70 / 1.72^2)
  }
})

test_that("the positive sentinels 98 and 99 become NA", {
  # DATA_KNOWLEDGE.md's point that sentinel schemes are not always negative:
  # na_if_negative()'s defaults would catch nothing here.
  height_sentinel <- env$derive(fixture(
    height_flag = 2, feet = c(98, 99),
    inches = c(98, 99),
    weight_flag = 1, kgs = c(70, 70)
  ))
  expect_true(all(is.na(height_sentinel$bmi_29y)))

  weight_sentinel <- env$derive(fixture(
    height_flag = 1, metres = c(1, 1),
    cms = c(72, 72), weight_flag = 2,
    stones = c(98, 99), pounds = c(98, 99)
  ))
  expect_true(all(is.na(weight_sentinel$bmi_29y)))
})

test_that("a whole height deposited in the centimetres column is still read correctly", {
  result <- env$derive(fixture(
    height_flag = 1, metres = NA, cms = 172,
    weight_flag = 1, kgs = 70
  ))

  expect_equal(result$bmi_29y, 70 / 1.72^2)
})

test_that("a missing minor component is treated as zero, a missing major one is not", {
  with_minor_missing <- env$derive(fixture(
    height_flag = 2, feet = 6,
    weight_flag = 2, stones = 12
  ))
  expect_equal(
    with_minor_missing$bmi_29y,
    (12 * 14) * 0.45359237 / ((6 * 12) * 0.0254)^2
  )

  with_major_missing <- env$derive(fixture(
    height_flag = 2, inches = 9,
    weight_flag = 2, pounds = 4
  ))
  expect_true(is.na(with_major_missing$bmi_29y))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(
    height_flag = c(1, 1), metres = c(NA, 1),
    cms = c(NA, 72), weight_flag = c(1, 1),
    kgs = c(70, NA)
  ))

  expect_true(all(is.na(result$bmi_29y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    height_flag = c("1", "1"), metres = c("1", "1"),
    cms = c("72", "65"), weight_flag = c("1", "1"),
    kgs = c("70", "not a number")
  ))

  expect_equal(result$bmi_29y[1], 70 / 1.72^2)
  expect_true(is.na(result$bmi_29y[2]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(height_flag = c(NA, 9), weight_flag = c(NA, 9)))

  expect_type(result$bmi_29y, "double")
  expect_true(all(is.na(result$bmi_29y)))
})
