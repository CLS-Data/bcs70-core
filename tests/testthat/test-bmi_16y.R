# ==========================================================================
# Synthetic-data tests for derived variable: bmi_16y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_16y.R", envir = env)

# Column order matches the spec: measured height/weight, then self-reported.
fixture <- function(height_measured, weight_measured,
                    height_self = NA, weight_self = NA) {
  n <- max(
    length(height_measured), length(weight_measured),
    length(height_self), length(weight_self)
  )
  data.frame(
    bcsid = paste0("B", seq_len(n)),
    "rd2.1" = rep(height_measured, length.out = n),
    "rd4.1" = rep(weight_measured, length.out = n),
    "ha1.2" = rep(height_self, length.out = n),
    "ha1.1" = rep(weight_self, length.out = n),
    check.names = FALSE
  )
}

test_that("bmi_16y returns the expected shape", {
  result <- env$derive(fixture(c(1.70, 1.65, NA), c(60, 55, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("the fixture really does carry the dotted deposited names", {
  # DATA_KNOWLEDGE.md names bcs7016x as the file whose variables are called
  # rd2.1, ha1.1 and so on - valid column names, invalid bare R symbols.
  supplied <- names(fixture(1.70, 60))

  expect_true(all(c("rd2.1", "rd4.1", "ha1.2", "ha1.1") %in% supplied))
})

test_that("BMI uses the measured pair when it is present", {
  # rd2.1/rd4.1 are already metres and kilograms, so no conversion.
  result <- env$derive(fixture(1.70, 60, 1.75, 55))

  expect_equal(result$bmi_16y, 60 / 1.70^2)
})

test_that("the self-reported pair is used only when measured is missing", {
  result <- env$derive(fixture(NA, NA, 1.75, 55))

  expect_equal(result$bmi_16y, 55 / 1.75^2)
})

test_that("height and weight fall back independently", {
  # A row may legitimately combine a measured height with a self-reported
  # weight; this mixed provenance is documented in the spec's notes.
  result <- env$derive(fixture(1.70, NA, 1.75, 55))

  expect_equal(result$bmi_16y, 55 / 1.70^2)
})

test_that("every documented sentinel becomes NA, in both pairs", {
  # All four variables document -2 "Not stated" and -1 "No questionnaire".
  measured_sentinel <- env$derive(fixture(c(-1, -2), c(-1, -2)))
  expect_true(all(is.na(measured_sentinel$bmi_16y)))

  both_sentinel <- env$derive(fixture(c(-1, -2), c(-1, -2), c(-1, -2), c(-1, -2)))
  expect_true(all(is.na(both_sentinel$bmi_16y)))
})

test_that("a sentinel in the measured pair falls back to self-report", {
  # The measured value exists but is -1, so preferring it just because the
  # column is populated would throw away a usable self-reported answer.
  result <- env$derive(fixture(-1, -1, 1.75, 55))

  expect_equal(result$bmi_16y, 55 / 1.75^2)
})

test_that("an implausible measured value falls back to self-report", {
  # 170 is a height in centimetres in a column documented as metres.
  result <- env$derive(fixture(170, 60, 1.75, 55))

  expect_equal(result$bmi_16y, 60 / 1.75^2)
})

test_that("NA passes through as NA when neither source has a value", {
  result <- env$derive(fixture(c(NA, 1.70), c(NA, 60)))

  expect_true(is.na(result$bmi_16y[1]))
  expect_false(is.na(result$bmi_16y[2]))
})

test_that("undocumented sentinels outside the envelope also become NA", {
  result <- env$derive(fixture(c(0, -8, -9, 999), rep(60, 4)))

  expect_true(all(is.na(result$bmi_16y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    c("1.70", "not a number"), c("60", "60"),
    c("1.75", "1.75"), c("55", "55")
  ))

  expect_equal(result$bmi_16y[1], 60 / 1.70^2)
  expect_equal(result$bmi_16y[2], 60 / 1.75^2)
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -1), c(NA, -1), c(NA, -1), c(NA, -1)))

  expect_type(result$bmi_16y, "double")
  expect_true(all(is.na(result$bmi_16y)))
})
