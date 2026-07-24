# ==========================================================================
# Synthetic-data tests for derived variable: sex
# --------------------------------------------------------------------------
# These tests MUST use fabricated data only - there is no real data in this
# repo to test against. Column names mirror exactly what R/runner.R's
# collision-renaming hands to derive() (see CLAUDE.md): "sex" is declared
# across three source files, so those three columns arrive as
# "<file_name>.sex" while every other, uniquely-named column stays bare.
# Real-data verification happens outside this repo; see the verify-variable
# skill for recording that outcome once it comes back.
# ==========================================================================

env <- new.env()
sys.source("../../R/variables/sex.R", envir = env)

test_that("sex takes the most recent non-missing value across sweeps", {
  synthetic <- data.frame(
    bcsid = c("A1", "A2", "A3", "A4", "A5"),
    b11sex = c(1, NA, NA, NA, NA), # 51y
    B10CMSEX = c(2, NA, NA, NA, NA), # 46y
    B9CMSEX = c(2, 2, NA, NA, NA), # 42y
    bd8sex = c(2, 1, NA, NA, NA), # 38y
    bd7sex = c(2, 1, NA, NA, NA), # 34y
    b960337 = c(2, 1, -8, NA, NA), # 26y - -8 is a documented sentinel ("Inappropriate Answer")
    sex86 = c(2, 1, NA, NA, NA), # 16y
    sex10 = c(2, 1, 3, NA, NA), # 10y - 3 is a documented sentinel ("Not Known")
    f003 = c(2, 1, 2, NA, NA), # 5y
    a0255 = c(2, 1, 1, NA, NA), # 0y
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  synthetic[["bcs2000.sex"]] <- c(2, 1, NA, NA, NA) # 29y
  synthetic[["bcs21yearsample.sex"]] <- c(2, 1, NA, NA, NA) # 21y
  synthetic[["bcs70_response_1970-2021.sex"]] <- c(2, 1, 1, 1, NA) # xwave fallback

  result <- env$derive(synthetic)

  expect_true(is.data.frame(result))
  expect_true(all(c("bcsid", env$spec$id) %in% names(result)))
  expect_equal(nrow(result), nrow(synthetic))
  expect_equal(
    result$sex,
    c(
      "male", # A1: 51y (b11sex=1) wins outright, every earlier sweep says female
      "female", # A2: 51y/46y missing, falls to 42y (B9CMSEX=2)
      "female", # A3: everything through 26y/10y is missing or an invalid sentinel
      #     (-8, 3) - correctly skipped - lands on 5y (f003=2)
      "male", # A4: every sweep-specific value missing, falls back to xwave (=1)
      NA_character_ # A5: everything missing, including the xwave fallback
    )
  )
})

test_that("sex treats any code other than 1/2 as missing, not just negatives", {
  synthetic <- data.frame(
    bcsid = "B1",
    b11sex = NA,
    B10CMSEX = NA,
    B9CMSEX = NA,
    bd8sex = NA,
    bd7sex = NA,
    b960337 = 8, # documented sentinel with a blank label, not 1/2
    sex86 = NA,
    sex10 = 3, # "Not Known"
    f003 = NA,
    a0255 = NA,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  synthetic[["bcs2000.sex"]] <- NA
  synthetic[["bcs21yearsample.sex"]] <- NA
  synthetic[["bcs70_response_1970-2021.sex"]] <- 3 # "Not Known"

  result <- env$derive(synthetic)

  expect_equal(result$sex, NA_character_)
})
