# Derived variable: <id>
#
# Save as R/variables/<category>/<family>/<id>.R - see R/variables/README.md.
# <category> must equal spec$category and <id> must equal spec$id; both are
# checked at build time.
#
# R/runner.R discovers and runs this; never source it yourself. It must not
# read or write anything on disk - input arrives as `data`, and the runner
# writes the output.

spec <- list(
  id = "TEMPLATE", # snake_case; becomes the output column name
  label = "Short human-readable label",
  category = "other", # one of the fixed categories, see CONTRIBUTING.md
  github_issue = NA, # issue number this was requested in
  status = "draft", # draft -> ready_for_real_data_test -> verified
  author = NA,
  created = NA, # YYYY-MM-DD
  source_files = c("example_file"), # file_name(s) from the master lookup
  source_vars = c("a0001"), # raw variable name(s) needed, across those files
  notes = "Non-obvious coding decisions, and the dictionary sections used."
)

derive <- function(data) {
  # `data` has the identifier plus one column per source_vars entry, named
  # bare (data$a0001) UNLESS the same raw name is declared across more than one
  # source file - then only those collisions become data[["<file_name>.<var>"]].
  #
  # Never declare the identifier in source_vars: it is the key, not data, and
  # it is already here. Return it plus a column named spec$id.
  stop("Not implemented - replace with real derivation logic")
}
