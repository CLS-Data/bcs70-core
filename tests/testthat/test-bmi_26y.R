# ==========================================================================
# Synthetic-data tests for derived variable: bmi_26y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_26y.R", envir = env)

fixture <- function(metres = NA, cms = NA, feet = NA, inches = NA,
                    kgs = NA, stones = NA, pounds = NA) {
  parts <- list(metres, cms, feet, inches, kgs, stones, pounds)
  n <- max(vapply(parts, length, integer(1)))
  data.frame(
    bcsid = paste0("B", seq_len(n)),
    b960436 = rep(metres, length.out = n),
    b960437 = rep(cms, length.out = n),
    b960433 = rep(feet, length.out = n),
    b960434 = rep(inches, length.out = n),
    b960443 = rep(kgs, length.out = n),
    b960439 = rep(stones, length.out = n),
    b960441 = rep(pounds, length.out = n),
    check.names = FALSE
  )
}

test_that("bmi_26y returns the expected shape", {
  result <- env$derive(fixture(
    metres = c(1, 1, NA), cms = c(72, 65, NA),
    kgs = c(70, 60, NA)
  ))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("the metric height pair combines as metres plus centimetres", {
  result <- env$derive(fixture(metres = 1, cms = 72, kgs = 70))

  expect_equal(result$bmi_26y, 70 / 1.72^2)
})

test_that("imperial height and weight convert with the exact factors", {
  # 5 ft 9 in and 11 st 4 lb.
  expected_height <- (5 * 12 + 9) * 0.0254
  expected_weight <- (11 * 14 + 4) * 0.45359237

  result <- env$derive(fixture(feet = 5, inches = 9, stones = 11, pounds = 4))

  expect_equal(result$bmi_26y, expected_weight / expected_height^2)
})

test_that("a missing minor component is treated as zero, a missing major one is not", {
  # "5 feet" and "5 feet 0 inches" are the same answer; "0 inches" alone is
  # not an answer at all.
  with_minor_missing <- env$derive(fixture(
    feet = 6, inches = NA,
    stones = 12, pounds = NA
  ))
  expect_equal(
    with_minor_missing$bmi_26y,
    (12 * 14) * 0.45359237 / ((6 * 12) * 0.0254)^2
  )

  with_major_missing <- env$derive(fixture(
    feet = NA, inches = 9,
    stones = NA, pounds = 4
  ))
  expect_true(is.na(with_major_missing$bmi_26y))
})

test_that("the metric reading is preferred over the imperial one when both are usable", {
  result <- env$derive(fixture(
    metres = 1, cms = 72, feet = 5, inches = 9,
    kgs = 70, stones = 11, pounds = 4
  ))

  expect_equal(result$bmi_26y, 70 / 1.72^2)
})

test_that("imperial is still used when the metric columns hold nothing usable", {
  result <- env$derive(fixture(
    metres = -1, cms = -1, feet = 5, inches = 9,
    kgs = -1, stones = 11, pounds = 4
  ))

  expect_equal(
    result$bmi_26y,
    (11 * 14 + 4) * 0.45359237 / ((5 * 12 + 9) * 0.0254)^2
  )
})

test_that("a whole height deposited in the centimetres column is still read correctly", {
  # The metres/centimetres pairing is inferred from the 29y labels, not
  # stated in the 26y dictionary. If "cms" turns out to hold the entire
  # height, the fallback reading must pick it up rather than return NA.
  result <- env$derive(fixture(metres = NA, cms = 172, kgs = 70))

  expect_equal(result$bmi_26y, 70 / 1.72^2)
})

test_that("every documented sentinel becomes NA", {
  # Between them the seven columns document -8 "Inappropriate Answer",
  # -7 "Out of range", -2 "Does Not Apply" and -1 "Not Answered". They do
  # NOT share a scheme: b960437 (cms) declares no negative range at all,
  # and only b960434 (inches), b960439 (stones) and b960441 (lbs) carry the
  # extra unlabelled 88.
  negatives <- c(-8, -7, -2, -1)

  height_sentinel <- env$derive(fixture(
    metres = negatives, cms = negatives,
    feet = negatives, inches = negatives,
    kgs = rep(70, 4)
  ))
  expect_true(all(is.na(height_sentinel$bmi_26y)))

  weight_sentinel <- env$derive(fixture(
    metres = rep(1, 4), cms = rep(72, 4),
    kgs = negatives, stones = negatives,
    pounds = negatives
  ))
  expect_true(all(is.na(weight_sentinel$bmi_26y)))
})

test_that("88 becomes NA in the columns that document it as a code", {
  # 88 is only implausible once converted, which is why the guard is
  # applied to the converted metres/kilograms rather than to the raw
  # components.
  in_inches <- env$derive(fixture(feet = 5, inches = 88, kgs = 70))
  expect_true(is.na(in_inches$bmi_26y))

  in_stones <- env$derive(fixture(
    metres = 1, cms = 72,
    stones = 88, pounds = 88
  ))
  expect_true(is.na(in_stones$bmi_26y))
})

test_that("88 in the kilograms column is a weight, not a sentinel", {
  # The unlabelled 88 code is documented for inches, stones and pounds -
  # NOT for b960443 kgs, where 88 kg is an entirely ordinary adult weight.
  # Deny-listing 88 across all seven columns would quietly delete real
  # cases, which is why the envelope is per-quantity rather than per-code.
  result <- env$derive(fixture(metres = 1, cms = 72, kgs = 88))

  expect_equal(result$bmi_26y, 88 / 1.72^2)
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(
    metres = c(NA, 1), cms = c(NA, 72),
    kgs = c(70, NA)
  ))

  expect_true(all(is.na(result$bmi_26y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    metres = c("1", "1"), cms = c("72", "65"),
    kgs = c("70", "not a number")
  ))

  expect_equal(result$bmi_26y[1], 70 / 1.72^2)
  expect_true(is.na(result$bmi_26y[2]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(metres = c(NA, -1), kgs = c(NA, -1)))

  expect_type(result$bmi_26y, "double")
  expect_true(all(is.na(result$bmi_26y)))
})
