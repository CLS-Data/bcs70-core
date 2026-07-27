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
  # Duplicates multiply rows through the join rather than adding unlinkable
  # ones; the loader flags them but must not choose a copy to discard.
  synthetic <- data.frame(
    bcsid = c("B0001", "B0001", "B0002"),
    x = 1:3
  )

  expect_warning(
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
