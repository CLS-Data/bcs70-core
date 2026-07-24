# Read-only helpers for loading BCS70 sweep data.
#
# IMPORTANT: bcs70/ must never be written to by anything in this repo.
# Every function here is read-only. It exists so variable scripts never
# need to know file paths - they declare a file_name in `spec$source_files`
# and the runner resolves + loads it via load_tab() below.

.bcs70_lookup_cache <- NULL

get_lookup <- function() {
  if (is.null(.bcs70_lookup_cache)) {
    .bcs70_lookup_cache <<- read.csv(
      "bcs70/master_file_info_lookup.csv",
      stringsAsFactors = FALSE
    )
  }
  .bcs70_lookup_cache
}

# Resolve and read a .tab file by its file_name, as it appears in
# master_file_info_lookup.csv (e.g. "bcs7016x", "bcs_age46_main").
#
# Some deposited files (e.g. bcs70_2012_flatfile, bcs_age46_main) use
# "BCSID" rather than "bcsid" for the identifier column - normalised to
# lowercase here so every other file in this codebase (runner.R, variable
# scripts, tests) can always assume a single, consistent "bcsid" name.
load_tab <- function(file_name) {
  lookup <- get_lookup()
  row <- lookup[lookup$file_name == file_name & lookup$file_type == "tab", ]
  if (nrow(row) == 0) {
    stop(sprintf(
      "No .tab file found for file_name = '%s' in master_file_info_lookup.csv",
      file_name
    ))
  }
  path <- file.path("bcs70", row$sweep[1], row$path[1])
  data <- read.delim(path, stringsAsFactors = FALSE, check.names = FALSE)

  id_col <- which(tolower(names(data)) == "bcsid")
  if (length(id_col) != 1) {
    stop(sprintf(
      "%s: expected exactly one bcsid-like identifier column, found %d",
      file_name, length(id_col)
    ))
  }
  names(data)[id_col] <- "bcsid"

  data
}
