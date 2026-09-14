#!/usr/bin/env Rscript
# Searches every sweep's metadata (master lookup, data dictionaries, file
# information tables) for keyword matches, so a derived-variable author can
# see every candidate source across ALL sweeps before writing any logic -
# not just the sweep(s) named in the original request.
#
# Usage: Rscript scripts/search_metadata.R "keyword one" "keyword two" ...
#
# Read-only: this script only ever reads the deposits, never writes to them.

source("R/lib/dataset.R")
source("R/lib/io.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("Usage: Rscript scripts/search_metadata.R <keyword> [<keyword> ...]")
}
keywords <- args

matches_any <- function(text, keywords) {
  text <- tolower(ifelse(is.na(text), "", text))
  hit <- rep(FALSE, length(text))
  for (k in keywords) {
    hit <- hit | grepl(tolower(k), text, fixed = TRUE)
  }
  hit
}

root <- data_root()
cat(sprintf("Searching %s/ metadata for: %s\n\n", root, paste(keywords, collapse = ", ")))

# 1. the master lookup - which sweeps/files even exist ----------------------
lookup <- read.csv(file.path(root, lookup_file), stringsAsFactors = FALSE)
lookup_hits <- lookup[matches_any(lookup$description, keywords) | matches_any(lookup$file_name, keywords), ]
cat(sprintf("== %s matches ==\n", lookup_file))
if (nrow(lookup_hits) == 0) {
  cat("(none)\n\n")
} else {
  print(lookup_hits[, c("study_number", "sweep", "file_name", "description", "file_type")], row.names = FALSE)
  cat("\n")
}

# 2. data dictionaries - the actual candidate variables ----------------------
dict_files <- list.files(
  root,
  pattern = "_ukda_data_dictionary_variables\\.csv$", recursive = TRUE, full.names = TRUE
)
cat(sprintf("== data dictionary matches (%d dictionaries scanned) ==\n", length(dict_files)))
dict_hit_count <- 0
for (path in dict_files) {
  dict <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(dict)) next
  hit <- matches_any(dict$variable_label, keywords) |
    matches_any(dict$variable, keywords) |
    matches_any(dict$value_labels_json, keywords)
  if (any(hit)) {
    dict_hit_count <- dict_hit_count + sum(hit)
    sweep <- strsplit(path, "/")[[1]][2]
    file_name <- sub("_ukda_data_dictionary_variables\\.csv$", "", basename(path))
    cat(sprintf("-- sweep %s / file %s --\n", sweep, file_name))
    print(dict[hit, c("variable", "variable_label")], row.names = FALSE)
  }
}
if (dict_hit_count == 0) cat("(none)\n")
cat("\n")

# 3. file_information tables - surfaces relevant PDFs/user guides -----------
info_files <- list.files(
  root,
  pattern = "_file_information_table\\.csv$", recursive = TRUE, full.names = TRUE
)
cat(sprintf("== file_information matches (%d tables scanned) ==\n", length(info_files)))
info_hit_count <- 0
for (path in info_files) {
  info <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(info)) next
  hit <- matches_any(info$description, keywords) | matches_any(info$file_name, keywords)
  if (any(hit)) {
    info_hit_count <- info_hit_count + sum(hit)
    cat(sprintf("-- %s --\n", path))
    print(info[hit, ], row.names = FALSE)
  }
}
if (info_hit_count == 0) cat("(none)\n")
