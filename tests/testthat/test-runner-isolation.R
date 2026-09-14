# ==========================================================================
# One variable never denies you the others.
# --------------------------------------------------------------------------
# run_all() used to be lapply(variables, build_variable), so the first failure
# aborted the batch: a researcher who picked thirty variables and one bad one
# got nothing at all. Failures are now collected per variable and reported
# together, the output is written with whatever succeeded, and the run is
# marked partial so nothing mistakes it for complete.
#
# Runs against throwaway directories under tempdir(); no test reads
# R/variables/ or bcs70/.
# ==========================================================================

# runner.R sources its libraries by repo-relative path and guards its own
# invocation with sys.nframe(), so it is loaded from the repo root and defines
# run_all() without starting a run.
env <- new.env()
withr::with_dir("../..", sys.source("R/runner.R", envir = env))

# A minimal deposit: a lookup plus one .tab, written under tempdir().
fake_data <- function() {
  root <- file.path(tempdir(), paste0("data-", basename(tempfile())))
  dir.create(file.path(root, "0y"), recursive = TRUE)
  write.csv(
    data.frame(
      study_number = 1, sweep = "0y", file_name = "f1",
      description = "", file_type = "tab", path = "f1.tab",
      stringsAsFactors = FALSE
    ),
    file.path(root, "master_file_info_lookup.csv"),
    row.names = FALSE
  )
  write.table(
    data.frame(bcsid = c("B1", "B2"), a = 1:2, b = 3:4, stringsAsFactors = FALSE),
    file.path(root, "0y", "f1.tab"),
    sep = "\t", row.names = FALSE, quote = FALSE
  )
  root
}

# A variables tree containing exactly the scripts described.
fake_variables <- function(scripts) {
  root <- file.path(tempdir(), paste0("vars-", basename(tempfile())))
  for (id in names(scripts)) {
    dir <- file.path(root, "other", "fam")
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    writeLines(scripts[[id]], file.path(dir, paste0(id, ".R")))
  }
  root
}

good <- function(id, var = "a") {
  sprintf(
    'spec <- list(id = "%s", label = "", category = "other", source_files = "f1",
                  source_vars = "%s")
     derive <- function(data) {
       out <- data.frame(bcsid = data$bcsid)
       out[["%s"]] <- data[["%s"]]
       out
     }',
    id, var, id, var
  )
}

# Declares a column the deposit does not have - the ordinary runtime failure.
absent_column <- function(id) {
  sub('source_vars = "a"', 'source_vars = "nope"', good(id), fixed = TRUE)
}

# Declares the identifier - rejected at validation, before anything is loaded.
declares_identifier <- function(id) {
  sub('source_vars = "a"', 'source_vars = "BCSID"', good(id), fixed = TRUE)
}

run <- function(scripts, ...) {
  out_dir <- file.path(tempdir(), paste0("out-", basename(tempfile())))
  withr::with_envvar(c(BCS70_DATA = fake_data()), {
    env$run_all(fake_variables(scripts), output_dir = out_dir, ...)
  })
}

test_that("a variable that cannot be built does not take the others with it", {
  result <- suppressWarnings(run(list(
    ok1 = good("ok1"), bad = absent_column("bad"),
    ok2 = good("ok2", "b")
  )))
  expect_true(all(c("ok1", "ok2") %in% names(result)))
  expect_false("bad" %in% names(result))
  expect_equal(nrow(result), 2)
})

test_that("an invalid spec is isolated too, not just a failed build", {
  # This is the case a researcher actually hit: one generated script declared
  # the identifier, and the whole batch stopped before writing anything.
  result <- suppressWarnings(run(list(ok1 = good("ok1"), bad = declares_identifier("bad"))))
  expect_true("ok1" %in% names(result))
  expect_false("bad" %in% names(result))
})

test_that("a partial run is marked, so it cannot pass for a complete one", {
  result <- suppressWarnings(run(list(ok1 = good("ok1"), bad = absent_column("bad"))))
  failures <- attr(result, "failures")
  expect_length(failures, 1)
  expect_named(failures, "bad")
})

test_that("a complete run is not marked partial", {
  result <- suppressWarnings(run(list(ok1 = good("ok1"), ok2 = good("ok2", "b"))))
  expect_null(attr(result, "failures"))
})

test_that("the output is still written when some variables failed", {
  out_dir <- file.path(tempdir(), paste0("out-", basename(tempfile())))
  suppressWarnings(withr::with_envvar(c(BCS70_DATA = fake_data()), {
    env$run_all(
      fake_variables(list(ok1 = good("ok1"), bad = absent_column("bad"))),
      output_dir = out_dir
    )
  }))
  expect_true(file.exists(file.path(out_dir, "derived_variables.csv")))
})

test_that("nothing buildable is still an error rather than an empty file", {
  expect_error(
    suppressWarnings(run(list(bad = absent_column("bad")))),
    "None of the"
  )
})
