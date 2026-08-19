# ==========================================================================
# Synthetic-data tests for derived variable: bmi_42y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_42y.R", envir = env)

fixture <- function(height_m, weight_kg) {
  data.frame(
    bcsid = paste0("B", seq_along(height_m)),
    BD9HGHTM = height_m,
    BD9WGHTK = weight_kg,
    check.names = FALSE
  )
}

test_that("bmi_42y returns the expected shape", {
  result <- env$derive(fixture(c(1.72, 1.65, NA), c(78, 62, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("the source columns are declared and read in upper case", {
  # DATA_KNOWLEDGE.md: load_tab() lower-cases only the identifier, so every
  # other name in this 42y file stays upper-case. The runner supplies the
  # columns named in spec$source_vars, so a lower-cased spec would hand
  # derive() columns it never looks up.
  expect_equal(env$spec$source_vars, c("BD9HGHTM", "BD9WGHTK"))
  expect_equal(env$spec$source_vars, toupper(env$spec$source_vars))
})

test_that("BMI is weight in kg over height in metres squared", {
  result <- env$derive(fixture(1.72, 78))

  expect_equal(result$bmi_42y, 78 / 1.72^2)
})

test_that("the documented sentinel becomes NA", {
  # -8 "No information", inside a declared user-missing range of
  # "-1.0 thru -8.0 and -9.0".
  sentinels <- c(-1, -8, -9)

  from_height <- env$derive(fixture(sentinels, rep(78, 3)))
  expect_true(all(is.na(from_height$bmi_42y)))

  from_weight <- env$derive(fixture(rep(1.72, 3), sentinels))
  expect_true(all(is.na(from_weight$bmi_42y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 1.72, 1.72), c(78, NA, 78)))

  expect_true(is.na(result$bmi_42y[1]))
  expect_true(is.na(result$bmi_42y[2]))
  expect_false(is.na(result$bmi_42y[3]))
})

test_that("a height given in centimetres falls outside the envelope", {
  result <- env$derive(fixture(172, 78))

  expect_true(is.na(result$bmi_42y))
})

test_that("undocumented sentinels outside the envelope also become NA", {
  result <- env$derive(fixture(c(0, -2, -3, 999), rep(78, 4)))

  expect_true(all(is.na(result$bmi_42y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    c("1.72", " 1.65", "not a number"),
    c("78", "62", "78")
  ))

  expect_equal(result$bmi_42y[1], 78 / 1.72^2)
  expect_equal(result$bmi_42y[2], 62 / 1.65^2)
  expect_true(is.na(result$bmi_42y[3]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -8), c(NA, -8)))

  expect_type(result$bmi_42y, "double")
  expect_true(all(is.na(result$bmi_42y)))
})
