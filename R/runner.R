# Orchestrates derived-variable generation across every script in
# R/variables/. This is the only entry point that should be run to
# produce output - individual variable scripts are never run directly.
#
# READ-ONLY with respect to the deposits: this script, and everything it
# calls, must never write to, move, or delete anything under them.

source("R/lib/dataset.R")
source("R/lib/discovery.R")
source("R/lib/io.R")
source("R/lib/utils.R")

# Loads one variable script into its own environment so that every script
# can reuse the same generic names (`spec`, `derive`) without colliding.
load_variable <- function(path) {
  env <- new.env()
  sys.source(path, envir = env)
  if (!is.list(env$spec) || !is.function(env$derive)) {
    stop(sprintf("%s must define both `spec` (a list) and `derive` (a function)", path))
  }
  env
}

# Loads the declared source files for one variable, narrows each to the
# identifier + the columns that variable declared (before merging, so files
# with hundreds of unrelated columns cannot collide), joins them on the
# identifier and hands the result to derive().
#
# If the same raw variable name is declared across more than one source file
# (e.g. several sweeps each have their own column literally called "sex"),
# only THOSE colliding columns are renamed to "<file_name>.<var>" so they
# stay distinguishable after the join - everything else keeps its bare name,
# so the common single-file case is unaffected.
# nolint start: object_usage_linter. load_tab() and resolve_duplicate_ids()
# come from R/lib/io.R and identifier_column from R/lib/dataset.R, both
# source()d above; lintr cannot see across a source().
build_variable <- function(variable) {
  spec <- variable$spec
  needed_files <- unique(spec$source_files)

  # Narrow to the identifier + this variable's columns BEFORE resolving
  # duplicate identifiers, so that rows differing only in columns this variable
  # never reads are recognised as carrying the same information. See
  # resolve_duplicate_ids() in R/lib/io.R.
  per_file <- lapply(needed_files, function(f) {
    raw <- load_tab(f)
    vars_here <- intersect(spec$source_vars, names(raw))
    resolve_duplicate_ids(raw[, c(identifier_column, vars_here), drop = FALSE], f)
  })
  names(per_file) <- needed_files

  found_vars <- unique(unlist(lapply(per_file, function(d) setdiff(names(d), identifier_column))))
  missing_vars <- setdiff(spec$source_vars, found_vars)
  if (length(missing_vars) > 0) {
    stop(sprintf(
      "%s declares source_vars not found in any of %s: %s",
      spec$id, paste(needed_files, collapse = ", "), paste(missing_vars, collapse = ", ")
    ))
  }

  all_var_names <- unlist(lapply(per_file, function(d) setdiff(names(d), identifier_column)))
  colliding_names <- unique(all_var_names[duplicated(all_var_names)])

  per_file <- Map(function(d, file_name) {
    cols <- setdiff(names(d), identifier_column)
    to_rename <- intersect(cols, colliding_names)
    if (length(to_rename) > 0) {
      names(d)[match(to_rename, names(d))] <- paste0(file_name, ".", to_rename)
    }
    d
  }, per_file, names(per_file))

  input <- Reduce(function(x, y) merge(x, y, by = identifier_column, all = TRUE), per_file)
  result <- variable$derive(input)

  if (!is.data.frame(result) || !all(c(identifier_column, spec$id) %in% names(result))) {
    stop(sprintf(
      "%s's derive() must return a data.frame with columns %s and %s",
      spec$id, identifier_column, spec$id
    ))
  }

  result[, c(identifier_column, spec$id), drop = FALSE]
}
# nolint end

# `only_ids`, if non-empty, restricts the run to the variable(s) whose file
# name (without .R) matches - e.g. to verify one newly added variable against
# real data without needing every other variable's inputs to be present too.
run_all <- function(variables_dir = "R/variables", output_dir = "output", only_ids = character(0)) {
  # nolint start: object_usage_linter. these come from the libs source()d above
  variable_files <- find_variable_files(variables_dir)

  # Validate every script, not just the ones this run targets, so a misplaced
  # or malformed file is reported even when only one id was asked for. Invalid
  # scripts are collected rather than thrown: they join the build failures
  # below and are reported together, because from where the researcher sits
  # "this variable is broken" and "this variable's data is missing" have the
  # same consequence, and neither is a reason to lose the other twenty-nine.
  # Nothing is hidden by this - every failure is printed, and the exit status
  # is non-zero.
  invalid <- character(0)
  for (path in variable_files) {
    env <- new.env()
    problem <- tryCatch(
      {
        sys.source(path, envir = env)
        check_variable_placement(path, env$spec, variables_dir)
        check_source_vars(path, env$spec)
        NULL
      },
      error = function(e) conditionMessage(e)
    )

    if (!is.null(problem)) {
      invalid[[tools::file_path_sans_ext(basename(path))]] <- problem
    }
  }
  variable_files <- variable_files[
    !tools::file_path_sans_ext(basename(variable_files)) %in% names(invalid)
  ]
  # nolint end

  if (length(only_ids) > 0) {
    variable_files <- variable_files[tools::file_path_sans_ext(basename(variable_files)) %in% only_ids]
    # Anything held back as invalid is already accounted for; reporting it here
    # as "no script found" would send the reader looking for a missing file.
    missing <- setdiff(
      only_ids,
      c(tools::file_path_sans_ext(basename(variable_files)), names(invalid))
    )
    if (length(missing) > 0) {
      stop(sprintf(
        "No variable script found for: %s. Expected %s/<category>/<family>/<id>.R",
        paste(missing, collapse = ", "), variables_dir
      ))
    }
  }

  if (length(variable_files) == 0 && length(invalid) == 0) {
    stop(sprintf(
      "No variable scripts found under %s/. Expected %s/<category>/<family>/<id>.R",
      variables_dir, variables_dir
    ))
  }

  variables <- lapply(variable_files, load_variable)
  ids <- vapply(variables, function(v) v$spec$id, character(1))
  names(variables) <- ids

  cat(sprintf(
    "Discovered %d variable script(s): %s\n",
    length(variables), paste(ids, collapse = ", ")
  ))

  # Each variable is an independent derivation over its own declared files, so
  # one that cannot be built is not a reason to deny the researcher the others.
  # An lapply() here meant the first failure aborted the batch: a run of thirty
  # variables produced nothing because the thirtieth named a column its deposit
  # did not have. Failures are collected instead, reported together at the end,
  # and turned into a non-zero exit by the command-line guard below - so a
  # person gets partial output and CI still fails.
  results <- list()

  # Scripts held back as invalid above start the failure list: they were never
  # loaded, so the loop below cannot reach them, but they are as much a reason
  # this run is incomplete as anything that failed while building.
  failures <- if (length(only_ids) > 0) invalid[names(invalid) %in% only_ids] else invalid

  # Everything this run was asked for, whether or not it got as far as loading.
  attempted <- length(variables) + length(failures)

  for (id in names(variables)) {
    built <- tryCatch(build_variable(variables[[id]]), error = function(e) e)
    if (inherits(built, "error")) {
      failures[[id]] <- conditionMessage(built)
    } else {
      results[[id]] <- built
    }
  }

  if (length(failures) > 0) {
    cat(sprintf(
      "\n%d of %d variable(s) could not be built:\n\n",
      length(failures), attempted
    ))
    for (id in names(failures)) cat(sprintf("  %s\n    %s\n", id, failures[[id]]))
    cat("\n")
  }

  if (length(results) == 0) {
    stop(sprintf(
      "None of the %d variable(s) could be built. See the errors above.",
      attempted
    ), call. = FALSE)
  }

  # nolint next: object_usage_linter. identifier_column comes from dataset.R
  output <- Reduce(function(x, y) merge(x, y, by = identifier_column, all = TRUE), results)

  dir.create(output_dir, showWarnings = FALSE)
  out_path <- file.path(output_dir, "derived_variables.csv")
  write.csv(output, out_path, row.names = FALSE)

  cat(sprintf(
    "Wrote %d derived variable(s) for %d case(s) to %s\n",
    ncol(output) - 1, nrow(output), out_path
  ))

  # Named rather than returned separately so a caller that only wants the data
  # can ignore it, while run.R and the guard below can both see what was lost.
  # A partial output under the usual file name is otherwise easy to mistake for
  # a complete one.
  if (length(failures) > 0) {
    cat(sprintf(
      "PARTIAL: %d variable(s) are missing from this output. See above.\n",
      length(failures)
    ))
    attr(output, "failures") <- failures
  }

  invisible(output)
}

# Usage: Rscript R/runner.R              -> run every variable
#        Rscript R/runner.R id1 id2 ...   -> run only the named variable(s)
#
# Guarded so that source()ing this file defines run_all() without also running
# it. sys.nframe() is 0 only at the top level of an Rscript invocation, so the
# command line above behaves exactly as before; a caller that sources this -
# an interactive session, or the run.R that ships in an atlas bundle - gets the
# function and chooses its own arguments, rather than inheriting whatever
# commandArgs() happens to hold in that host.
if (sys.nframe() == 0L) {
  result <- run_all(only_ids = commandArgs(trailingOnly = TRUE))
  # A partial run is a failed run as far as anything automating this is
  # concerned, even though it wrote a file.
  if (length(attr(result, "failures")) > 0) quit(status = 1L)
}
