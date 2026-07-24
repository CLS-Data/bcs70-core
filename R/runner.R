# Orchestrates derived-variable generation across every script in
# R/variables/. This is the only entry point that should be run to
# produce output - individual variable scripts are never run directly.
#
# READ-ONLY with respect to bcs70/: this script (and everything it calls)
# must never write to, move, or delete anything under bcs70/.

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

# Loads the declared source files for one variable, narrows each one to just
# bcsid + the columns this variable declared (before merging, so files with
# hundreds of unrelated columns can't collide with each other), then joins
# them on bcsid and hands the result to the variable's derive() function.
#
# If the same raw variable name is declared across more than one source file
# (e.g. several sweeps each have their own column literally called "sex"),
# only THOSE colliding columns are renamed to "<file_name>.<var>" so they
# stay distinguishable after the join - everything else keeps its bare name,
# so the common single-file case is unaffected.
build_variable <- function(variable) {
  spec <- variable$spec
  needed_files <- unique(spec$source_files)

  # nolint start: object_usage_linter. load_tab comes from source("R/lib/io.R") above
  per_file <- lapply(needed_files, function(f) {
    raw <- load_tab(f)
    vars_here <- intersect(spec$source_vars, names(raw))
    raw[, c("bcsid", vars_here), drop = FALSE]
  })
  # nolint end
  names(per_file) <- needed_files

  found_vars <- unique(unlist(lapply(per_file, function(d) setdiff(names(d), "bcsid"))))
  missing_vars <- setdiff(spec$source_vars, found_vars)
  if (length(missing_vars) > 0) {
    stop(sprintf(
      "%s declares source_vars not found in any of %s: %s",
      spec$id, paste(needed_files, collapse = ", "), paste(missing_vars, collapse = ", ")
    ))
  }

  all_var_names <- unlist(lapply(per_file, function(d) setdiff(names(d), "bcsid")))
  colliding_names <- unique(all_var_names[duplicated(all_var_names)])

  per_file <- Map(function(d, file_name) {
    cols <- setdiff(names(d), "bcsid")
    to_rename <- intersect(cols, colliding_names)
    if (length(to_rename) > 0) {
      names(d)[match(to_rename, names(d))] <- paste0(file_name, ".", to_rename)
    }
    d
  }, per_file, names(per_file))

  input <- Reduce(function(x, y) merge(x, y, by = "bcsid", all = TRUE), per_file)
  result <- variable$derive(input)

  if (!is.data.frame(result) || !all(c("bcsid", spec$id) %in% names(result))) {
    stop(sprintf("%s's derive() must return a data.frame with columns bcsid and %s", spec$id, spec$id))
  }

  result[, c("bcsid", spec$id), drop = FALSE]
}

# `only_ids`, if non-empty, restricts the run to the variable(s) whose file
# name (without .R) matches - e.g. to verify one newly added variable against
# real data without needing every other variable's inputs to be present too.
run_all <- function(variables_dir = "R/variables", output_dir = "output", only_ids = character(0)) {
  variable_files <- list.files(variables_dir, pattern = "\\.R$", full.names = TRUE)
  if (length(only_ids) > 0) {
    variable_files <- variable_files[tools::file_path_sans_ext(basename(variable_files)) %in% only_ids]
    missing <- setdiff(only_ids, tools::file_path_sans_ext(basename(variable_files)))
    if (length(missing) > 0) {
      stop(sprintf("No R/variables/*.R found for: %s", paste(missing, collapse = ", ")))
    }
  }
  variables <- lapply(variable_files, load_variable)
  ids <- vapply(variables, function(v) v$spec$id, character(1))
  names(variables) <- ids

  cat(sprintf(
    "Discovered %d variable script(s): %s\n",
    length(variables), paste(ids, collapse = ", ")
  ))

  results <- lapply(variables, build_variable)
  output <- Reduce(function(x, y) merge(x, y, by = "bcsid", all = TRUE), results)

  dir.create(output_dir, showWarnings = FALSE)
  out_path <- file.path(output_dir, "derived_variables.csv")
  write.csv(output, out_path, row.names = FALSE)

  cat(sprintf(
    "Wrote %d derived variable(s) for %d case(s) to %s\n",
    ncol(output) - 1, nrow(output), out_path
  ))

  invisible(output)
}

# Usage: Rscript R/runner.R              -> run every variable
#        Rscript R/runner.R id1 id2 ...   -> run only the named variable(s)
run_all(only_ids = commandArgs(trailingOnly = TRUE))
