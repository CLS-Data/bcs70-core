# {{dataset}} — {{count}}
#
#   1. Open {{project}}.Rproj, so the working directory is this folder.
#      (Not using RStudio? setwd() here instead.)
#   2. Put your deposits in data/, or set DATA_DIR below.
#   3. Run this file: "Source" in RStudio, or `Rscript run.R`.
#
# Result: output/derived_variables.csv — one row per case, one column per
# variable, joined on {{identifier}}.
#
# README.md has the detail, including what to do when something is missing.
# This file checks the working directory, the data and the files it needs
# before it starts, and says what to fix rather than failing part-way.


# --- Settings -------------------------------------------------------------

# Where your deposits are. "" uses the data/ folder here. `~` is fine;
# on Windows use forward slashes, "C:/data/{{root}}".
DATA_DIR <- ""

# Which to build. Empty means all; name them to build a few: c("{{sample_id}}")
VARIABLES <- character(0)


# ==========================================================================
# Nothing below here needs editing.
# ==========================================================================

# The deposited files these variables read, checked up front rather than
# discovered one failure at a time.
NEEDED <- {{files}}

# Named here so the checks below can look for it before anything reads it.
LOOKUP <- "{{lookup}}"


# --- A readable failure ---------------------------------------------------

# Addressed to a researcher who just opened this, not to whoever wrote it.
fail <- function(...) {
  stop("\n\n", paste0(..., collapse = ""), "\n", call. = FALSE)
}

say <- function(...) cat(paste0(..., collapse = ""), "\n", sep = "")


# --- Check 1: are we in the right folder? ---------------------------------

if (!file.exists(file.path("R", "runner.R"))) {
  fail(
    "I can't see this project's own R/ folder, which means the working\n",
    "directory is not the project folder.\n\n",
    "  Working directory is: ", getwd(), "\n\n",
    "Fix it by opening {{project}}.Rproj in RStudio, or by running:\n\n",
    "  setwd(\"/path/to/{{project}}\")\n"
  )
}


# --- Check 2: where is the data? ------------------------------------------

# In order: an explicit setting beats the environment, which beats a guess.
# Each has to actually contain the lookup - an empty data/ folder is the
# normal state of a fresh download, not an answer.
has_lookup <- function(path) nzchar(path) && file.exists(file.path(path, LOOKUP))

env_dir <- if (nzchar("{{env}}")) Sys.getenv("{{env}}", unset = "") else ""

candidates <- list(
  list(path = path.expand(DATA_DIR), how = "DATA_DIR in this file"),
  list(
    path = path.expand(env_dir),
    # Named only where there is one to name; "the  environment variable" is
    # what this read as for a pipeline with no data-root override.
    how = if (nzchar("{{env}}")) {
      "the {{env}} environment variable"
    } else {
      "an environment variable (this pipeline has none)"
    }
  ),
  list(path = "data", how = "the data/ folder in this project"),
  list(path = "{{root}}", how = "a {{root}}/ folder in this project")
)

found <- NULL
for (candidate in candidates) {
  if (has_lookup(candidate$path)) {
    found <- candidate
    break
  }
}

# A common near-miss: unzipped into data/ but wrapped in their own folder.
# Not worth a stop() - say what was assumed and carry on.
if (is.null(found) && dir.exists("data")) {
  nested <- list.dirs("data", recursive = FALSE)
  nested <- nested[vapply(nested, has_lookup, logical(1))]
  if (length(nested) == 1) {
    found <- list(path = nested, how = paste0("the ", nested, " folder"))
    say("Note: found the data one level down, in ", nested, "/.")
  } else if (length(nested) > 1) {
    fail(
      "There is more than one set of deposits under data/:\n\n",
      paste0("  ", nested, collapse = "\n"), "\n\n",
      "Set DATA_DIR at the top of this file to the one you want."
    )
  }
}

if (is.null(found)) {
  tried <- vapply(candidates, function(candidate) {
    if (!nzchar(candidate$path)) {
      paste0("  - ", candidate$how, ": not set")
    } else {
      paste0("  - ", candidate$how, ": ",
             if (dir.exists(candidate$path)) {
               paste0(normalizePath(candidate$path), " exists, but has no ", LOOKUP)
             } else {
               paste0(candidate$path, " does not exist")
             })
    }
  }, character(1))

  fail(
    "I could not find your copy of the deposits for {{dataset}}.\n\n",
    "I looked for a folder containing ", LOOKUP, ", in this order:\n\n",
    paste(tried, collapse = "\n"), "\n\n",
    "Do ONE of these:\n\n",
    "  (a) Copy your deposit folders into:  ", file.path(getwd(), "data"), "\n",
    "      so that ", file.path(getwd(), "data", LOOKUP), " exists.\n\n",
    "  (b) Open run.R and set DATA_DIR to wherever they already are:\n\n",
    "        DATA_DIR <- \"~/{{root}}\"\n\n",
    "This project never writes to your data. It only reads it."
  )
}

data_dir <- normalizePath(found$path, mustWork = TRUE)
say("Data:      ", data_dir, "  (from ", found$how, ")")


# --- Check 3: which variables can actually be built? ----------------------

# Sourced, not run: R/runner.R guards its own invocation, so this gets its
# functions without starting a run. The checks below then use the SAME
# discovery and spec loading the run will, rather than a second copy.
{{set_root}}

suppressWarnings(source(file.path("R", "runner.R")))

lookup <- utils::read.csv(file.path(data_dir, LOOKUP), stringsAsFactors = FALSE)

required <- unlist(lookup_columns, use.names = FALSE)
if (!all(required %in% names(lookup))) {
  fail(
    LOOKUP, " does not have the columns this expects.\n\n",
    "  Found:  ", paste(names(lookup), collapse = ", "), "\n",
    "  Needs:  ", paste(required, collapse = ", "), "\n\n",
    "Is this the right file? It should be the master lookup that ships with\n",
    "the deposits, at the top level of the data folder."
  )
}

# Resolved exactly the way load_tab() will resolve it, so a file that passes
# here cannot fail to open there for a path reason.
locate <- function(file_name) {
  row <- lookup[lookup[[lookup_columns$file_name]] == file_name &
                  lookup[[lookup_columns$file_type]] == "tab", ]
  if (nrow(row) == 0) return(NA_character_)
  file.path(data_dir, row[[lookup_columns$wave]][1], row[[lookup_columns$path]][1])
}

paths <- vapply(NEEDED, locate, character(1))
have <- !is.na(paths) & file.exists(paths)
names(have) <- NEEDED

if (!any(have)) {
  fail(
    "None of the ", length(NEEDED), " deposited file(s) these variables need\n",
    "are in ", data_dir, ":\n\n",
    paste0("  - ", NEEDED, collapse = "\n"), "\n\n",
    "That usually means the path is the right KIND of folder but the wrong\n",
    "copy - a partial download, or a different study. Check that the\n",
    "{{wave_plural}} you expect are actually in there."
  )
}

# What each variable declares it reads, through the runner's own loader.
specs <- lapply(find_variable_files("R/variables"), load_variable)
ids <- vapply(specs, function(v) v$spec$id, character(1))

# Why a variable cannot be built, from where the researcher sits: something
# it needs is not in their copy of the data.
# File presence only, from the lookup - no deposit is opened. Anything deeper
# is the runner's to find: it isolates failures per variable already, and a
# second copy of "can this be built" would be one more thing to disagree.
blocked_by <- lapply(specs, function(v) {
  wanted <- unique(v$spec$source_files)
  missing_files <- wanted[!wanted %in% NEEDED | !have[wanted]]
  if (length(missing_files) > 0) paste(missing_files, collapse = ", ") else character(0)
})
names(blocked_by) <- ids

wanted_ids <- if (length(VARIABLES)) VARIABLES else ids

unknown <- setdiff(wanted_ids, ids)
if (length(unknown) > 0) {
  fail(
    "VARIABLES names ", length(unknown), " variable(s) that are not in this\n",
    "bundle:\n\n",
    paste0("  - ", unknown, collapse = "\n"), "\n\n",
    "This bundle contains:\n\n",
    paste0("  - ", ids, collapse = "\n"), "\n\n",
    "Leave VARIABLES empty to build all of them."
  )
}

runnable <- wanted_ids[vapply(wanted_ids, function(id) length(blocked_by[[id]]) == 0, logical(1))]
blocked <- setdiff(wanted_ids, runnable)

say("Files:     ", sum(have), " of ", length(NEEDED), " deposited file(s) found")

if (length(blocked) > 0) {
  say("")
  say("SKIPPING ", length(blocked), " variable(s) - the deposited files they")
  say("read are not in your copy of the data:")
  say("")
  for (id in blocked) {
    say("  ", id, "  needs ", blocked_by[[id]])
  }
  say("")
  say("They are left out rather than stopping the run, so you still get the")
  say("rest. Add those files to your data folder and run again to include them.")
}

if (length(runnable) == 0) {
  fail(
    "Every variable in this bundle needs a deposited file that is not in\n",
    data_dir, ":\n\n",
    paste0("  - ", vapply(wanted_ids, function(id) {
      paste0(id, " needs ", blocked_by[[id]])
    }, character(1)), collapse = "\n"), "\n\n",
    "Check that DATA_DIR points at a complete copy of the deposits."
  )
}


# --- Run ------------------------------------------------------------------

say("")
say("Variables: ", paste(runnable, collapse = ", "))
say("")

result <- run_all(only_ids = runnable)

# The runner reports each failure above; this just adds them up.
lost <- length(blocked) + length(attr(result, "failures"))

say("")
say("Done. ", nrow(result), " rows x ", ncol(result) - 1, " variable(s).")
say("Written to: ", normalizePath(file.path("output", "derived_variables.csv")))
if (lost > 0) {
  say("")
  say("NOTE: this output is PARTIAL - ", lost, " variable(s) are not in it.")
}

say("")
say("Warnings above about dropped or conflicting identifiers are expected and")
say("are explained in README.md - they are the pipeline refusing to guess.")

# A partial run is a failed run to anything scripting this. Interactive
# sessions are spared - quitting the console over two skipped variables
# would be its own kind of rude.
if (lost > 0 && !interactive()) {
  quit(status = 1L)
}
