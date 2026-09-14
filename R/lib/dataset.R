# The five facts about the dataset that the R pipeline needs.
#
# Everything else in R/lib/ and R/runner.R is dataset-agnostic: it reads these
# and nothing else. Point this file at another study - together with its own
# R/variables/ and its own deposits - and the pipeline runs unchanged.
#
# These are the same facts web/dataset.toml declares for the atlas, and
# web/tests/test_dataset_config.py fails if the two disagree. They are restated
# here rather than read from there because a downloaded bundle ships R/ alone,
# with no TOML parser and no Python, and must still run.

# Directory holding the deposits, relative to the working directory, unless
# data_env below names somewhere else.
data_dir_default <- "bcs70"

# Environment variable the data directory can be overridden with, so licensed
# microdata does not have to be moved to satisfy a relative path. Empty string
# for a pipeline that offers no override.
data_dir_env <- "BCS70_DATA"

# The index at the top of the deposits, mapping a file_name to a path.
lookup_file <- "master_file_info_lookup.csv"

# Its column names. Four of these are also declared in
# [metadata.lookup_columns] in web/dataset.toml, for the atlas; `path` is used
# only here, because only the pipeline opens a data file.
lookup_columns <- list(
  file_name = "file_name", # what a spec's source_files entries name
  file_type = "file_type", # "tab" selects a readable data file
  wave      = "sweep", # the directory the file sits in
  path      = "path" # the file, relative to that directory
)

# The column every file is keyed on. load_tab() normalises whichever column
# matches this case-insensitively to exactly this spelling, so everything
# downstream can assume one name.
identifier_column <- "bcsid"

# What a usable identifier looks like, after trimming and upper-casing. Rows
# that still fail this cannot be linked to a cohort member and are dropped -
# see clean_identifiers() in R/lib/io.R for why that matters.
#
# Deliberately loose: it is a convention, not a documented format, and no data
# dictionary records a type for the identifier. Tighten it only once the real
# files have been inspected. A pattern of "." accepts anything.
identifier_pattern <- "^B"
