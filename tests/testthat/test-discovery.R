# ==========================================================================
# Tests for R/lib/discovery.R - where variable scripts live and how that
# layout is enforced.
# --------------------------------------------------------------------------
# Everything here runs against throwaway directories under tempdir(); no
# test reads R/variables/ or bcs70/.
# ==========================================================================

env <- new.env()
sys.source("../../R/lib/discovery.R", envir = env)

# Build a fake R/variables tree and return its root. `paths` are given
# relative to that root, e.g. "housing/housing_tenure/housing_tenure_16y.R".
fake_variables_dir <- function(paths) {
  root <- file.path(tempfile("variables"))
  for (p in paths) {
    full <- file.path(root, p)
    dir.create(dirname(full), recursive = TRUE, showWarnings = FALSE)
    writeLines("# fixture", full)
  }
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root
}

test_that("find_variable_files discovers scripts nested under category/family", {
  root <- fake_variables_dir(c(
    "housing/housing_tenure/housing_tenure_16y.R",
    "housing/housing_tenure/housing_tenure_21y.R",
    "health/bmi/bmi_10y.R"
  ))

  found <- env$find_variable_files(root)

  expect_equal(length(found), 3)
  expect_true(all(grepl("\\.R$", found)))
  expect_equal(basename(found[1]), "bmi_10y.R") # sorted, health before housing
})

test_that("find_variable_files returns nothing for an empty tree", {
  root <- fake_variables_dir(character(0))

  expect_equal(env$find_variable_files(root), character(0))
})

test_that("parse_variable_path splits category, family and id", {
  root <- fake_variables_dir("housing/housing_tenure/housing_tenure_16y.R")
  path <- file.path(root, "housing/housing_tenure/housing_tenure_16y.R")

  location <- env$parse_variable_path(path, root)

  expect_equal(location$category, "housing")
  expect_equal(location$family, "housing_tenure")
  expect_equal(location$id, "housing_tenure_16y")
})

test_that("parse_variable_path rejects a script at the wrong depth", {
  # A file dropped straight into R/variables/, or into a category with no
  # family directory, must fail loudly rather than be silently skipped.
  root <- fake_variables_dir(c("stray.R", "housing/too_shallow.R"))

  expect_error(env$parse_variable_path(file.path(root, "stray.R"), root), "3 levels")
  expect_error(env$parse_variable_path(file.path(root, "housing/too_shallow.R"), root), "3 levels")
})

test_that("parse_variable_path rejects an unknown category directory", {
  root <- fake_variables_dir("domestic/housing_tenure/housing_tenure_16y.R")
  path <- file.path(root, "domestic/housing_tenure/housing_tenure_16y.R")

  expect_error(env$parse_variable_path(path, root), "not a known category")
})

test_that("check_variable_placement accepts a correctly placed script", {
  root <- fake_variables_dir("housing/housing_tenure/housing_tenure_16y.R")
  path <- file.path(root, "housing/housing_tenure/housing_tenure_16y.R")
  spec <- list(id = "housing_tenure_16y", category = "housing")

  location <- env$check_variable_placement(path, spec, root)

  expect_equal(location$family, "housing_tenure")
})

test_that("check_variable_placement catches a spec$category that contradicts the directory", {
  # Silent otherwise: the variable would be grouped under the declared
  # category in registry/ while living somewhere else on disk.
  root <- fake_variables_dir("housing/housing_tenure/housing_tenure_16y.R")
  path <- file.path(root, "housing/housing_tenure/housing_tenure_16y.R")
  spec <- list(id = "housing_tenure_16y", category = "socio_economic")

  expect_error(
    env$check_variable_placement(path, spec, root),
    "spec\\$category is 'socio_economic' but the file sits under 'housing/'"
  )
})

test_that("check_variable_placement catches a spec$id that contradicts the file name", {
  # Silent otherwise: Rscript R/runner.R <id> filters on the file name, so
  # the variable would simply never be selectable.
  root <- fake_variables_dir("housing/housing_tenure/housing_tenure_16y.R")
  path <- file.path(root, "housing/housing_tenure/housing_tenure_16y.R")
  spec <- list(id = "housing_tenure_21y", category = "housing")

  expect_error(env$check_variable_placement(path, spec, root), "must match exactly")
})

test_that("every category directory name is a valid spec category", {
  # The directory vocabulary and the spec vocabulary are the same list by
  # construction; this pins that they stay one list, not two.
  expect_length(env$variable_categories, 10)
  expect_true(all(c("housing", "socio_economic", "health", "other") %in% env$variable_categories))
})
