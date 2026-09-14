# The identifier is the key, never a source variable.
#
# Both spellings are broken rather than merely redundant, and they break
# differently - which is why this is validated rather than left to whichever
# error happens to surface first. See env$check_source_vars() in discovery.R.

env <- new.env()
sys.source("../../R/lib/dataset.R", envir = env)
sys.source("../../R/lib/discovery.R", envir = env)

spec_with <- function(vars) {
  list(id = "x", category = "other", source_files = "f", source_vars = vars)
}

test_that("a spec declaring the identifier is rejected", {
  expect_error(
    env$check_source_vars("R/variables/other/f/x.R", spec_with("bcsid")),
    "declares the identifier"
  )
})

test_that("it is rejected whatever case the dictionary spells it in", {
  # 40 of this study's 85 dictionaries spell it BCSID, and load_tab() renames
  # that column as it loads - so this spelling can never match at run time.
  expect_error(
    env$check_source_vars("R/variables/other/f/x.R", spec_with("BCSID")),
    "declares the identifier"
  )
  expect_error(
    env$check_source_vars("R/variables/other/f/x.R", spec_with(c("a0002", "BcSiD"))),
    "declares the identifier"
  )
})

test_that("the message says what to do rather than what went wrong", {
  msg <- tryCatch(
    env$check_source_vars("R/variables/other/f/x.R", spec_with("BCSID")),
    error = conditionMessage
  )
  expect_match(msg, "Remove it")
  expect_match(msg, "data\\$bcsid")
})

test_that("an ordinary spec passes", {
  expect_silent(env$check_source_vars("R/variables/other/f/x.R", spec_with(c("a0002", "sex"))))
})

test_that("a spec with no source_vars passes", {
  # Not a shape the template produces, but nothing here should be the thing
  # that turns an empty vector into an error.
  expect_silent(env$check_source_vars("R/variables/other/f/x.R", spec_with(character(0))))
})

test_that("the registry build checks it too, not just the runner", {
  # CI runs build_registry.R and testthat; it never runs the pipeline against
  # data. A spec rule wired into runner.R alone therefore goes green here and
  # fails on a human's real-data run instead - which is the failure this check
  # was added to pre-empt.
  registry <- readLines("../../scripts/build_registry.R")
  expect_true(any(grepl("check_source_vars", registry, fixed = TRUE)))
})
