# Read-only helpers for loading BCS70 sweep data.
#
# IMPORTANT: bcs70/ must never be written to by anything in this repo.
# Every function here is read-only. It exists so variable scripts never
# need to know file paths - they declare a file_name in `spec$source_files`
# and the runner resolves + loads it via load_tab() below.

.bcs70_lookup_cache <- NULL

# The cohort member identifier is "B"-prefixed in every deposited file, but
# some files (sn3723 and bcs21yearsample are the known cases) carry rows
# whose identifier does not follow that pattern. Such a row cannot be linked
# to a cohort member, and left in place it is not harmless: runner.R joins
# every variable's output with merge(..., all = TRUE), so an unlinkable id
# survives as an extra output row with one sweep's column populated and all
# others NA - indistinguishable from a genuine case seen at only one sweep.
#
# NOTE: this pattern is deliberately loose ("starts with B", after trimming
# and upper-casing). It is a convention, not a documented format - no data
# dictionary records a type or value labels for bcsid - so it is set wide
# enough not to discard valid ids. Tighten it here once the real files have
# been inspected and the exact shape of the bad values is known.
bcsid_pattern <- "^B"

# Normalise identifiers, then drop rows that still cannot be linked.
# Whitespace and case are normalised first because both preserve identity;
# only what survives that and still fails the pattern is dropped, and never
# silently - the caller always gets a warning naming the file and counts.
#
# Counts only, never the offending values: warnings surface wherever this is
# run, and a malformed serial number is still case-level data.
clean_bcsid <- function(data, file_name, pattern = bcsid_pattern) {
  data$bcsid <- toupper(trimws(as.character(data$bcsid)))

  keep <- !is.na(data$bcsid) & nzchar(data$bcsid) & grepl(pattern, data$bcsid)
  dropped <- sum(!keep)
  if (dropped > 0) {
    warning(
      sprintf(
        paste(
          "%s: dropped %d of %d row(s) whose bcsid does not match %s.",
          "These cases are absent from every variable derived from this file."
        ),
        file_name, dropped, nrow(data), pattern
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
  duplicated_ids <- unique(data$bcsid[duplicated(data$bcsid)])
  if (length(duplicated_ids) > 0) {
    message(sprintf(
      "%s: %d bcsid value(s) appear on more than one row; resolved per-variable after column narrowing.",
      file_name, length(duplicated_ids)
    ))
  }

  data
}

# Resolve duplicate identifiers for one variable, applied by runner.R after
# each source file has been narrowed to bcsid + the columns that variable
# declared. Narrowing first is the whole point: two rows sharing a bcsid may
# differ only in columns this variable never reads, in which case they carry
# the same information and collapse harmlessly. The same duplicate pair can
# therefore collapse for one variable and conflict for another, which is
# correct rather than inconsistent.
#
# Rows agreeing across every retained column collapse to one. An id whose
# rows genuinely disagree cannot be resolved without knowing which record is
# authoritative - nothing in the deposit says - so the case is dropped with a
# warning rather than resolved by guesswork or by file order.
resolve_duplicate_ids <- function(data, file_name) {
  if (anyDuplicated(data$bcsid) == 0) {
    return(data)
  }

  before <- nrow(data)
  data <- unique(data)
  collapsed <- before - nrow(data)

  conflicting <- unique(data$bcsid[duplicated(data$bcsid)])
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
    data <- data[!data$bcsid %in% conflicting, , drop = FALSE]
  } else if (collapsed > 0) {
    message(sprintf(
      "%s: collapsed %d redundant duplicate row(s); no conflicts.",
      file_name, collapsed
    ))
  }

  rownames(data) <- NULL
  data
}

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
#
# Identifier *values* are then normalised and checked by clean_bcsid()
# above, which drops unlinkable rows with a warning. Variable scripts
# therefore never have to defend against a malformed bcsid themselves.
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

  clean_bcsid(data, file_name)
}
