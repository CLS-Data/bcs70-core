# ==========================================================================
# Tests for R/lib/io.R identifier handling.
# --------------------------------------------------------------------------
# clean_bcsid() is a pure function over an already-loaded data.frame, so it
# is tested directly on fabricated rows - nothing here reads bcs70/, and no
# real identifier appears in this file.
# ==========================================================================

env <- new.env()
sys.source("../../R/lib/io.R", envir = env)

test_that("clean_bcsid keeps conforming identifiers untouched", {
  synthetic <- data.frame(
    bcsid = c("B0001", "B0002", "B0003"),
    x = c(1, 2, 3)
  )

  result <- expect_no_warning(env$clean_bcsid(synthetic, "fake_file"))

  expect_equal(result$bcsid, c("B0001", "B0002", "B0003"))
  expect_equal(result$x, c(1, 2, 3))
  expect_equal(nrow(result), 3)
})

test_that("clean_bcsid repairs case and whitespace rather than dropping", {
  # These preserve identity, so the rows must survive - silently, since
  # nothing has been lost.
  synthetic <- data.frame(
    bcsid = c(" B0001", "b0002 ", "\tb0003\t"),
    x = c(1, 2, 3)
  )

  result <- expect_no_warning(env$clean_bcsid(synthetic, "fake_file"))

  expect_equal(result$bcsid, c("B0001", "B0002", "B0003"))
  expect_equal(nrow(result), 3)
})

test_that("clean_bcsid drops unlinkable identifiers and warns with counts", {
  synthetic <- data.frame(
    bcsid = c("B0001", "", NA, "0", ".", "X9999", "B0002"),
    x = 1:7
  )

  expect_warning(
    result <- env$clean_bcsid(synthetic, "fake_file"),
    "dropped 5 of 7 row\\(s\\)"
  )

  expect_equal(result$bcsid, c("B0001", "B0002"))
  expect_equal(result$x, c(1L, 7L))
  expect_equal(rownames(result), c("1", "2")) # row names reset after the drop
})

test_that("clean_bcsid names the file it dropped rows from", {
  # The warning is the only signal that N has changed, so it has to identify
  # which deposit is responsible.
  synthetic <- data.frame(bcsid = c("B0001", "nonsense"), x = 1:2)

  expect_warning(env$clean_bcsid(synthetic, "bcs21yearsample"), "bcs21yearsample")
})

test_that("clean_bcsid reports duplicate identifiers without dropping them", {
  # Duplicates cannot be settled at load time - whether two rows conflict
  # depends on which columns the variable reads - so the loader only
  # reports them. resolve_duplicate_ids() settles them after narrowing.
  synthetic <- data.frame(
    bcsid = c("B0001", "B0001", "B0002"),
    x = 1:3
  )

  expect_message(
    result <- env$clean_bcsid(synthetic, "fake_file"),
    "1 bcsid value\\(s\\) appear on more than one row"
  )

  expect_equal(nrow(result), 3)
  expect_equal(result$bcsid, c("B0001", "B0001", "B0002"))
})

test_that("clean_bcsid returns no rows when nothing is linkable", {
  synthetic <- data.frame(bcsid = c(NA, "", "junk"), x = 1:3)

  expect_warning(result <- env$clean_bcsid(synthetic, "fake_file"))

  expect_equal(nrow(result), 0)
  expect_true(all(c("bcsid", "x") %in% names(result)))
})

test_that("clean_bcsid accepts a tightened pattern", {
  # bcsid_pattern is deliberately loose until the real files are inspected;
  # callers must be able to narrow it without editing the loader.
  synthetic <- data.frame(bcsid = c("B0001", "B12", "BX999"), x = 1:3)

  expect_warning(
    result <- env$clean_bcsid(synthetic, "fake_file", pattern = "^B[0-9]{4}$"),
    "dropped 2 of 3 row\\(s\\)"
  )

  expect_equal(result$bcsid, "B0001")
})

# --------------------------------------------------------------------------
# resolve_duplicate_ids(): applied by runner.R after each source file has
# been narrowed to bcsid + the columns one variable declared.
# --------------------------------------------------------------------------

test_that("resolve_duplicate_ids leaves already-unique data untouched", {
  synthetic <- data.frame(bcsid = c("B0001", "B0002"), d2 = c(1, 3))

  result <- expect_no_warning(env$resolve_duplicate_ids(synthetic, "fake_file"))

  expect_equal(result, synthetic)
})

test_that("resolve_duplicate_ids collapses duplicate rows that agree", {
  # Both rows say the same thing about the only column in play, so one of
  # them carries no information and the case survives intact.
  synthetic <- data.frame(
    bcsid = c("B0001", "B0001", "B0002"),
    d2 = c(3, 3, 1)
  )

  expect_message(
    result <- env$resolve_duplicate_ids(synthetic, "fake_file"),
    "collapsed 1 redundant duplicate row"
  )

  expect_equal(result$bcsid, c("B0001", "B0002"))
  expect_equal(result$d2, c(3, 1))
})

test_that("resolve_duplicate_ids drops cases whose duplicate rows disagree", {
  # Nothing in the deposit says which record is authoritative, so the case
  # is dropped rather than resolved by file order.
  synthetic <- data.frame(
    bcsid = c("B0001", "B0001", "B0002"),
    d2 = c(3, 5, 1)
  )

  expect_warning(
    result <- env$resolve_duplicate_ids(synthetic, "fake_file"),
    "dropped 1 case\\(s\\) whose duplicate rows disagree"
  )

  expect_equal(result$bcsid, "B0002")
  expect_equal(nrow(result), 1)
})

test_that("resolve_duplicate_ids treats rows agreeing only on NA as agreeing", {
  # Two rows both missing the value carry the same information; collapsing
  # them must not be mistaken for a conflict.
  synthetic <- data.frame(
    bcsid = c("B0001", "B0001"),
    d2 = c(NA_real_, NA_real_)
  )

  expect_message(result <- env$resolve_duplicate_ids(synthetic, "fake_file"))

  expect_equal(nrow(result), 1)
  expect_true(is.na(result$d2))
})

test_that("resolve_duplicate_ids handles collapse and conflict in one file", {
  synthetic <- data.frame(
    bcsid = c("B0001", "B0001", "B0002", "B0002", "B0003"),
    d2 = c(3, 3, 1, 7, 5)
  )

  expect_warning(
    result <- env$resolve_duplicate_ids(synthetic, "fake_file"),
    "dropped 1 case\\(s\\).*Collapsed 1 redundant"
  )

  expect_equal(result$bcsid, c("B0001", "B0003"))
  expect_equal(result$d2, c(3, 5))
})

test_that("resolve_duplicate_ids judges conflict only on the retained columns", {
  # The narrowing runner.R does before calling this is what makes the
  # collapse safe: a column the variable never declared cannot make two
  # rows conflict, because it is not present by the time we get here.
  narrowed <- data.frame(
    bcsid = c("B0001", "B0001"),
    d2 = c(3, 3) # unrelated columns already dropped by build_variable()
  )

  expect_message(result <- env$resolve_duplicate_ids(narrowed, "fake_file"))

  expect_equal(nrow(result), 1)
})

test_that("resolve_duplicate_ids names the file in its conflict warning", {
  synthetic <- data.frame(bcsid = c("B0001", "B0001"), d2 = c(1, 2))

  expect_warning(env$resolve_duplicate_ids(synthetic, "sn3723"), "sn3723")
})
