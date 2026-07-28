# ==========================================================================
# Synthetic-data tests for derived variable: first_age_smoke
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source(
  "../../R/variables/behavioural_lifestyle/first_age_smoke/first_age_smoke.R",
  envir = env
)

# Helper: build a fixture carrying all four declared source_vars, so every
# test exercises derive() with the same column set the runner would hand it.
fixture <- function(gh5 = NA, b9 = NA, b10 = NA, b11 = NA) {
  n <- max(length(gh5), length(b9), length(b10), length(b11))
  data.frame(
    bcsid = paste0("B", seq_len(n)),
    gh5 = rep(gh5, length.out = n),
    B9AGESTR = rep(b9, length.out = n),
    B10AGESTR = rep(b10, length.out = n),
    b11agestr = rep(b11, length.out = n),
    check.names = FALSE
  )
}

test_that("first_age_smoke returns the expected shape", {
  synthetic <- fixture(gh5 = c(7, 13, -2))

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(result$bcsid, synthetic$bcsid)
})

test_that("16y gh5 bands 1-11 map to ages 5-15", {
  # gh5 is banded, not an age: 1 "5 yrs or less" ... 11 "15 yrs".
  synthetic <- fixture(gh5 = 1:11)

  result <- env$derive(synthetic)

  expect_equal(result$first_age_smoke, as.numeric(5:15))
})

test_that("16y gh5 non-age codes and sentinels become NA", {
  # 12 "Can't remember" and 13 "Never smoked" carry no age; -4 "Not asked",
  # -2 "Not stated", -1 "No questionnaire" are the documented sentinels.
  synthetic <- fixture(gh5 = c(12, 13, -4, -2, -1, 0, 14, NA))

  result <- env$derive(synthetic)

  expect_true(all(is.na(result$first_age_smoke)))
})

test_that("42y/46y/51y ages in years pass through unchanged", {
  synthetic <- fixture(b9 = c(16, 20), b10 = c(NA, NA), b11 = c(NA, NA))
  expect_equal(env$derive(synthetic)$first_age_smoke, c(16, 20))

  synthetic <- fixture(b10 = c(18, 30))
  expect_equal(env$derive(synthetic)$first_age_smoke, c(18, 30))

  synthetic <- fixture(b11 = c(15, 45))
  expect_equal(env$derive(synthetic)$first_age_smoke, c(15, 45))
})

test_that("every documented adult-sweep missing code becomes NA", {
  # 42y/46y: -9 Refused, -8 Don't know/Not known, -1 Not applicable.
  expect_true(all(is.na(env$derive(fixture(b9 = c(-9, -8, -1)))$first_age_smoke)))
  expect_true(all(is.na(env$derive(fixture(b10 = c(-9, -8, -1)))$first_age_smoke)))

  # 51y additionally documents -3 (not asked at case fieldwork stage) and
  # -2 (not asked due to scripting/routing error).
  expect_true(all(is.na(env$derive(fixture(b11 = c(-9, -8, -3, -2, -1)))$first_age_smoke)))
})

test_that("implausible ages outside the 5-60 window become NA", {
  # Guards against undocumented sentinels, which DATA_KNOWLEDGE.md warns
  # can appear even where the dictionary lists none.
  synthetic <- fixture(b9 = c(0, 4, 61, 999, -7))

  expect_true(all(is.na(env$derive(synthetic)$first_age_smoke)))
})

test_that("the earliest reported age across sweeps wins", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:4),
    # C1: 16y band 9 (13 yrs) beats the later regular-smoking reports.
    # C2: 16y missing, so the earliest adult report (18) is used.
    # C3: only 51y reports an age.
    # C4: sentinels everywhere except one usable 46y answer.
    gh5 = c(9, -2, NA, 12),
    B9AGESTR = c(17, 21, NA, -9),
    B10AGESTR = c(18, 18, NA, 25),
    b11agestr = c(NA, 19, 32, -3),
    check.names = FALSE
  )

  result <- env$derive(synthetic)

  expect_equal(result$first_age_smoke, c(13, 18, 32, 25))
})

test_that("never-smokers and wholly missing cases return NA", {
  # The request asks for NA when the cohort member never smoked. A
  # never-smoker is routed past AGESTR (-1 Not applicable) and answers gh5
  # as 13 "Never smoked", so no sweep supplies an age.
  synthetic <- data.frame(
    bcsid = c("D1", "D2"),
    gh5 = c(13, NA),
    B9AGESTR = c(-1, NA),
    B10AGESTR = c(-1, NA),
    b11agestr = c(-1, NA),
    check.names = FALSE
  )

  result <- env$derive(synthetic)

  expect_equal(nrow(result), 2L)
  expect_true(all(is.na(result$first_age_smoke)))
})

test_that("first_age_smoke is numeric even when nothing is derivable", {
  # pmin() over all-NA input must not collapse to logical NA or Inf - the
  # runner writes this column alongside real ages from other rows.
  result <- env$derive(fixture(gh5 = c(NA, NA)))

  expect_true(is.numeric(result$first_age_smoke))
  expect_false(any(is.infinite(result$first_age_smoke)))
})
