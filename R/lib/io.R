# Read-only helpers for loading deposited data files.
#
# IMPORTANT: the deposits must never be written to by anything in this repo.
# Every function here is read-only. It exists so variable scripts never
# need to know file paths - they declare a file_name in `spec$source_files`
# and the runner resolves + loads it via load_tab() below.

# lintr note: this file reads the constants in R/lib/dataset.R, which every
# entry point source()s before it. lintr cannot follow a source(), so .lintr
# disables object_usage_linter for this file only - every other linter applies.

.lookup_cache <- NULL
.lookup_root <- NULL

# Where the deposits are: the configured directory, unless the environment
# points elsewhere. Licensed microdata is large, and moving it to satisfy a
# relative path is the wrong way round.
#
# Read on each call rather than at load, so changing it needs no restart.
data_root <- function() {
  root <- if (nzchar(data_dir_env)) Sys.getenv(data_dir_env, unset = "") else ""
  if (nzchar(root)) root else data_dir_default
}

# Normalise identifiers, then drop rows that still cannot be linked.
#
# Trimming and upper-casing preserve identity, so they happen first; only what
# survives them and still fails identifier_pattern is dropped. That matters
# because runner.R joins with all = TRUE, so an unlinkable id would otherwise
# survive as an output row with one sweep populated and the rest NA -
# indistinguishable from a case genuinely seen once.
#
# Counts only, never the values: a malformed serial number is still
# case-level data, and warnings surface wherever this runs.
clean_identifiers <- function(data, file_name, pattern = identifier_pattern) {
  ids <- toupper(trimws(as.character(data[[identifier_column]])))
  data[[identifier_column]] <- ids

  keep <- !is.na(ids) & nzchar(ids) & grepl(pattern, ids)
  dropped <- sum(!keep)
  if (dropped > 0) {
    warning(
      sprintf(
        paste(
          "%s: dropped %d of %d row(s) whose %s does not match %s.",
          "These cases are absent from every variable derived from this file."
        ),
        file_name, dropped, nrow(data), identifier_column, pattern
      ),
      call. = FALSE
    )
  }

  data <- data[keep, , drop = FALSE]
  rownames(data) <- NULL

  # Duplicates are a separate failure mode - they multiply rows through the
  # join rather than adding unlinkable ones - and they cannot be settled
  # here, because whether two rows conflict depends on which columns the
  # variable actually uses. They are reported at load time for visibility
  # and resolved per-variable by resolve_duplicate_ids() below.
  duplicated_ids <- unique(ids[duplicated(ids)])
  if (length(duplicated_ids) > 0) {
    message(sprintf(
      "%s: %d %s value(s) appear on more than one row; resolved per-variable after column narrowing.",
      file_name, length(duplicated_ids), identifier_column
    ))
  }

  data
}

# Resolve duplicate identifiers for one variable, applied by runner.R after
# narrowing each file to the identifier + that variable's columns.
#
# Narrowing first is the point: two rows sharing an id may differ only in
# columns this variable never reads, so they carry the same information and
# collapse. The same pair can therefore collapse for one variable and conflict
# for another, which is correct rather than inconsistent.
#
# An id whose rows genuinely disagree is dropped with a warning: nothing in the
# deposit says which record is authoritative, so the alternative is guesswork.
resolve_duplicate_ids <- function(data, file_name) {
  if (anyDuplicated(data[[identifier_column]]) == 0) {
    return(data)
  }

  before <- nrow(data)
  data <- unique(data)
  collapsed <- before - nrow(data)

  ids <- data[[identifier_column]]
  conflicting <- unique(ids[duplicated(ids)])
  if (length(conflicting) > 0) {
    warning(
      sprintf(
        paste(
          "%s: dropped %d case(s) whose duplicate rows disagree on the columns used here.",
          "Collapsed %d redundant duplicate row(s)."
        ),
        file_name, length(conflicting), collapsed
      ),
      call. = FALSE
    )
    data <- data[!ids %in% conflicting, , drop = FALSE]
  } else if (collapsed > 0) {
    message(sprintf(
      "%s: collapsed %d redundant duplicate row(s); no conflicts.",
      file_name, collapsed
    ))
  }

  rownames(data) <- NULL
  data
}

# Keyed by the root it was read from, so repointing the data directory
# mid-session re-reads rather than serving the previous study's index.
get_lookup <- function() {
  root <- data_root()
  if (is.null(.lookup_cache) || !identical(.lookup_root, root)) {
    path <- file.path(root, lookup_file)
    if (!file.exists(path)) {
      stop(sprintf(
        paste(
          "No lookup at %s. Run this from the directory that holds %s/,",
          "or set %s to where the deposits are."
        ),
        path, root, data_dir_env
      ), call. = FALSE)
    }
    .lookup_cache <<- read.csv(path, stringsAsFactors = FALSE)
    .lookup_root <<- root
  }
  .lookup_cache
}

# Resolve and read a .tab file by its file_name, as the lookup spells it.
#
# Deposits are inconsistent about the identifier column's case, so whichever
# column matches it case-insensitively is renamed to the configured spelling.
# Its values are then normalised by clean_identifiers(). Variable scripts therefore
# never have to defend against a malformed or oddly-spelled identifier.
load_tab <- function(file_name) {
  lookup <- get_lookup()
  is_wanted <- lookup[[lookup_columns$file_name]] == file_name &
    lookup[[lookup_columns$file_type]] == "tab"
  row <- lookup[is_wanted, ]
  if (nrow(row) == 0) {
    stop(sprintf(
      "No .tab file found for file_name = '%s' in %s",
      file_name, lookup_file
    ))
  }
  path <- file.path(
    data_root(),
    row[[lookup_columns$wave]][1], row[[lookup_columns$path]][1]
  )
  data <- read.delim(path, stringsAsFactors = FALSE, check.names = FALSE)

  id_col <- which(tolower(names(data)) == tolower(identifier_column))
  if (length(id_col) != 1) {
    stop(sprintf(
      "%s: expected exactly one %s-like identifier column, found %d",
      file_name, identifier_column, length(id_col)
    ))
  }
  names(data)[id_col] <- identifier_column

  clean_identifiers(data, file_name)
}
