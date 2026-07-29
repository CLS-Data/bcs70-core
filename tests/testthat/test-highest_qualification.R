# ==========================================================================
# Synthetic-data tests for derived variable: highest_qualification
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Cover: each typical valid value, every documented
# missing/sentinel code (from the variable's data dictionary), and a plain
# NA passthrough. Real-data verification happens outside this repo; see
# the verify-variable skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source(
  "../../R/variables/education/highest_qualification/highest_qualification.R",
  envir = env
)

# Helper: build a fixture carrying all nine declared source_vars, so every
# test exercises derive() with the same column set the runner would hand it.
fixture <- function(hqual16 = NA, hqual21 = NA, hqual26 = NA, hinvq00 = NA,
                    bd7 = NA, bd8 = NA, bd9 = NA, bd10 = NA, bd11 = NA) {
  cols <- list(hqual16, hqual21, hqual26, hinvq00, bd7, bd8, bd9, bd10, bd11)
  n <- max(vapply(cols, length, integer(1)))
  data.frame(
    bcsid = paste0("B", seq_len(n)),
    hqual16 = rep(hqual16, length.out = n),
    hqual21 = rep(hqual21, length.out = n),
    hqual26 = rep(hqual26, length.out = n),
    HINVQ00 = rep(hinvq00, length.out = n),
    BD7HNVQ = rep(bd7, length.out = n),
    BD8HNVQ = rep(bd8, length.out = n),
    BD9HNVQ = rep(bd9, length.out = n),
    BD10HNVQ = rep(bd10, length.out = n),
    bd11hnvq = rep(bd11, length.out = n),
    check.names = FALSE
  )
}

test_that("highest_qualification returns the expected shape", {
  synthetic <- fixture(hqual21 = c(3, -1, NA))

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(result$bcsid, synthetic$bcsid)
})

test_that("every sweep's NVQ levels 0-5 pass through unchanged", {
  levels <- 0:5

  expect_equal(env$derive(fixture(hqual16 = levels))$highest_qualification, as.numeric(levels))
  expect_equal(env$derive(fixture(hqual21 = levels))$highest_qualification, as.numeric(levels))
  expect_equal(env$derive(fixture(hqual26 = levels))$highest_qualification, as.numeric(levels))
  expect_equal(env$derive(fixture(hinvq00 = levels))$highest_qualification, as.numeric(levels))
  expect_equal(env$derive(fixture(bd7 = levels))$highest_qualification, as.numeric(levels))
  expect_equal(env$derive(fixture(bd8 = levels))$highest_qualification, as.numeric(levels))
  expect_equal(env$derive(fixture(bd9 = levels))$highest_qualification, as.numeric(levels))
  expect_equal(env$derive(fixture(bd10 = levels))$highest_qualification, as.numeric(levels))

  # 51y shares codes 1-5, and its 0 is "NVQ Entry Level" rather than "none",
  # which still maps onto 0 - see the spec notes.
  expect_equal(env$derive(fixture(bd11 = levels))$highest_qualification, as.numeric(levels))
})

test_that("51y code 96 'No qualification' is folded back onto 0", {
  # THE regression test for this variable. bd11hnvq moved the
  # no-qualifications category from 0 to 96 while every earlier sweep kept it
  # at 0. Left alone, 96 would win every maximum and make the least-qualified
  # cohort members the highest-scoring ones in the output.
  synthetic <- fixture(
    bd7 = c(NA, 3, 5, NA),
    bd11 = c(96, 96, 96, 0)
  )

  result <- env$derive(synthetic)

  expect_equal(result$highest_qualification, c(0, 3, 5, 0))
  expect_false(any(result$highest_qualification == 96, na.rm = TRUE))
})

test_that("no output value can ever fall outside the harmonised 0-5 scale", {
  # Guards the scale itself rather than any one recode: every documented
  # out-of-scale code from any sweep, fed in at once.
  synthetic <- fixture(
    hqual16 = c(-1, -2, 96, 95),
    hqual21 = c(-2, -1, 95, 96),
    hqual26 = c(-1, -3, 6, 8),
    hinvq00 = c(-9, -9, 7, 6),
    bd7 = c(-1, -8, -9, 13),
    bd8 = c(-8, -9, -1, 8),
    bd9 = c(-9, -1, -8, 6),
    bd10 = c(-8, -1, -9, 7),
    bd11 = c(96, 95, 96, 95)
  )

  result <- env$derive(synthetic)
  derived <- result$highest_qualification

  expect_true(all(is.na(derived) | (derived >= 0 & derived <= 5)))
})

test_that("every documented missing code becomes NA", {
  # 29y: -9 Incomplete info. 34y-46y: -1 Not applicable, -8 Don't know /
  # Not enough information, -9 Refusal. 51y: -1 Not applicable, -8
  # Insufficient information. 21y/26y document missing from -2/-1 downward.
  expect_true(all(is.na(env$derive(fixture(hinvq00 = c(-9)))$highest_qualification)))
  expect_true(all(is.na(env$derive(fixture(bd7 = c(-1, -8, -9)))$highest_qualification)))
  expect_true(all(is.na(env$derive(fixture(bd8 = c(-1, -8, -9)))$highest_qualification)))
  expect_true(all(is.na(env$derive(fixture(bd9 = c(-1, -8, -9)))$highest_qualification)))
  expect_true(all(is.na(env$derive(fixture(bd10 = c(-1, -8, -9)))$highest_qualification)))
  expect_true(all(is.na(env$derive(fixture(bd11 = c(-1, -8)))$highest_qualification)))
  expect_true(all(is.na(env$derive(fixture(hqual16 = c(-2, -3)))$highest_qualification)))
  expect_true(all(is.na(env$derive(fixture(hqual26 = c(-1, -2, -3)))$highest_qualification)))
})

test_that("'holds qualifications, level unknown' is NA rather than 0", {
  # hqual16/hqual21 code -1 as "Other quals" - a substantive answer that
  # nonetheless cannot be placed on the NVQ scale. Treating it as 0 would
  # wrongly count these cohort members as having no qualifications.
  result <- env$derive(fixture(hqual21 = c(-1, -1), hqual16 = c(-1, 2)))

  expect_equal(result$highest_qualification, c(NA_real_, 2))
})

test_that("the highest level reported across sweeps wins", {
  synthetic <- data.frame(
    bcsid = paste0("C", 1:5),
    # C1: attainment rises across the life course; the last sweep is highest.
    # C2: an earlier sweep reports higher than a later one - max is robust.
    # C3: observed at one sweep only.
    # C4: genuinely has no qualifications at any sweep.
    # C5: sentinels everywhere except one usable 38y answer.
    hqual16 = c(1, 2, NA, 0, NA),
    hqual21 = c(2, 3, NA, 0, NA),
    hqual26 = c(2, 3, NA, 0, -1),
    HINVQ00 = c(3, 5, NA, 0, -9),
    BD7HNVQ = c(3, 4, NA, 0, -1),
    BD8HNVQ = c(4, 4, NA, 0, 2),
    BD9HNVQ = c(4, 4, NA, 0, -8),
    BD10HNVQ = c(5, 4, NA, 0, -9),
    bd11hnvq = c(5, 4, 3, 96, -1),
    check.names = FALSE
  )

  result <- env$derive(synthetic)

  expect_equal(result$highest_qualification, c(5, 5, 3, 0, 2))
})

test_that("a single observed sweep is enough, and 0 is kept distinct from NA", {
  # 0 means "no qualifications" and must survive alongside missing sweeps,
  # rather than being swallowed by them.
  result <- env$derive(fixture(hqual26 = c(0, NA), bd9 = c(NA, NA)))

  expect_equal(result$highest_qualification, c(0, NA_real_))
})

test_that("wholly missing cases return numeric NA, never -Inf", {
  # pmax() over all-NA input must not collapse to logical NA or -Inf - the
  # runner writes this column alongside real levels from other rows.
  result <- env$derive(fixture(hqual21 = c(NA, NA)))

  expect_true(is.numeric(result$highest_qualification))
  expect_false(any(is.infinite(result$highest_qualification)))
  expect_true(all(is.na(result$highest_qualification)))
})

test_that("academic-only and partner qualification columns are ignored", {
  # BD7HACHQ etc. sit on a different 0-8 academic-only scale and were
  # deliberately left out of source_vars; B9PHVCDR is the partner's, not the
  # cohort member's. A stray column must not be picked up.
  synthetic <- fixture(hqual21 = c(2, NA))
  synthetic$BD7HACHQ <- c(8, 8)
  synthetic$B9PHVCDR <- c(5, 5)

  result <- env$derive(synthetic)

  expect_equal(result$highest_qualification, c(2, NA_real_))
})
