# ==========================================================================
# Synthetic-data tests for derived variable: bmi_46y
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/health/bmi/bmi_46y.R", envir = env)

fixture <- function(height_m, weight_kg) {
  data.frame(
    bcsid = paste0("B", seq_along(height_m)),
    BD10HGHTM = height_m,
    BD10WGHTK = weight_kg,
    check.names = FALSE
  )
}

test_that("bmi_46y returns the expected shape", {
  result <- env$derive(fixture(c(1.72, 1.65, NA), c(80, 64, NA)))

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B1", "B2", "B3"))
})

test_that("the source columns are declared and read in upper case", {
  # DATA_KNOWLEDGE.md names bcs_age46_main as one of the two files whose
  # identifier is deposited as BCSID; load_tab() lower-cases only that
  # identifier, so every other name in the file stays upper-case.
  expect_equal(env$spec$source_vars, c("BD10HGHTM", "BD10WGHTK"))
  expect_equal(env$spec$source_vars, toupper(env$spec$source_vars))
})

test_that("the self-reported pair is used, not the nurse-measured one", {
  # This sweep also deposits BD10MWGTK (nurse measured weight) and
  # BD10MBMI. Using them would make 46y the one adult sweep whose BMI shift
  # is an instrument change, so the self-reported pair is deliberate.
  expect_false(any(grepl("^BD10M", env$spec$source_vars)))
})

test_that("BMI is weight in kg over height in metres squared", {
  result <- env$derive(fixture(1.72, 80))

  expect_equal(result$bmi_46y, 80 / 1.72^2)
})

test_that("the documented sentinel becomes NA", {
  # -8 "No information", inside a declared user-missing range of
  # "-1.0 thru -8.0 and -9.0".
  sentinels <- c(-1, -8, -9)

  from_height <- env$derive(fixture(sentinels, rep(80, 3)))
  expect_true(all(is.na(from_height$bmi_46y)))

  from_weight <- env$derive(fixture(rep(1.72, 3), sentinels))
  expect_true(all(is.na(from_weight$bmi_46y)))
})

test_that("NA passes through as NA", {
  result <- env$derive(fixture(c(NA, 1.72, 1.72), c(80, NA, 80)))

  expect_true(is.na(result$bmi_46y[1]))
  expect_true(is.na(result$bmi_46y[2]))
  expect_false(is.na(result$bmi_46y[3]))
})

test_that("a height given in centimetres falls outside the envelope", {
  result <- env$derive(fixture(172, 80))

  expect_true(is.na(result$bmi_46y))
})

test_that("undocumented sentinels outside the envelope also become NA", {
  result <- env$derive(fixture(c(0, -2, -3, 999), rep(80, 4)))

  expect_true(all(is.na(result$bmi_46y)))
})

test_that("values arriving as character strings are still handled", {
  result <- env$derive(fixture(
    c("1.72", " 1.65", "not a number"),
    c("80", "64", "80")
  ))

  expect_equal(result$bmi_46y[1], 80 / 1.72^2)
  expect_equal(result$bmi_46y[2], 64 / 1.65^2)
  expect_true(is.na(result$bmi_46y[3]))
})

test_that("the output is always numeric, even when wholly missing", {
  result <- env$derive(fixture(c(NA, -8), c(NA, -8)))

  expect_type(result$bmi_46y, "double")
  expect_true(all(is.na(result$bmi_46y)))
})
