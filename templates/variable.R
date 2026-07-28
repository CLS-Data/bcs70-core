# ==========================================================================
# Derived variable: <id>
# --------------------------------------------------------------------------
# Save this as R/variables/<category>/<family>/<id>.R - see
# R/variables/README.md. <category> must equal spec$category below, and
# <id> must equal spec$id; both are checked at build time.
#
# This file is self-contained and is the single source of truth for this
# variable - a future front end will display this file's raw source as
# "how this variable was made". R/runner.R discovers and runs it
# automatically; don't source or call it manually anywhere else.
#
# Rules for this file:
#   - Never read from disk (no read.csv/read.delim/file paths). All input
#     arrives via the `data` argument to derive().
#   - Never write to disk. Return the derived column; the runner writes it.
#   - Never reference bcs70/ directly - it must stay read-only.
# ==========================================================================

spec <- list(
  id = "TEMPLATE", # unique snake_case id -> becomes the output column name
  label = "Short human-readable label for this variable",
  category = "other", # one of the fixed categories in CONTRIBUTING.md#variable-categories
  github_issue = NA, # issue number this was requested in, e.g. 12
  status = "draft", # draft -> ready_for_real_data_test -> verified
  author = NA,
  created = NA, # YYYY-MM-DD
  source_files = c("example_file"), # file_name(s) from master_file_info_lookup.csv
  source_vars = c("a0001"), # raw variable name(s) needed, across those files
  notes = "Explain any non-obvious coding decisions, and cite the data dictionary/user guide sections used."
)

derive <- function(data) {
  # `data` is a data.frame with columns: bcsid, <spec$source_vars...>, named
  # bare (e.g. data$a0001) UNLESS the same raw name is declared across more
  # than one source_files entry (e.g. several sweeps each have their own
  # column literally called "sex") - then only those colliding columns are
  # disambiguated as data[["<file_name>.<var>"]]; see CLAUDE.md for details.
  # Return a data.frame with columns: bcsid, <spec$id>
  stop("Not implemented - replace with real derivation logic")
}
