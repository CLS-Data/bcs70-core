# ==========================================================================
#
#   {{dataset}} — harmonised variables
#
#   Run this file. It checks everything first and tells you exactly what to
#   fix if something is not ready, rather than failing part-way through.
#
# --------------------------------------------------------------------------
#
#   STEP 1 — open the project
#
#     Double-click {{project}}.Rproj. That opens RStudio with the working
#     directory already set to this folder, which is the single most common
#     thing to get wrong. If you are not using RStudio, just make sure your
#     working directory is the folder this file is in:
#
#         setwd("/path/to/{{project}}")
#
#   STEP 2 — tell it where your data is. EITHER:
#
#     (a) PUT THE DATA HERE. Copy or move your deposit folders into the
#         `data/` folder next to this file, so that you end up with:
#
#             {{project}}/data/{{lookup}}
#             {{project}}/data/{{sample_wave}}/...
#
#         Nothing is copied, moved or written by this project — it only
#         reads. See data/README.md.
#
#     (b) POINT AT THE DATA where it already lives. Licensed microdata is
#         large and you should not have to duplicate it. Put the path in
#         DATA_DIR below:
#
#             DATA_DIR <- "~/{{root}}"
#
#         (Only where this study's pipeline supports it - if it does not,
#          option (a) is the whole story and DATA_DIR will say so.)
#
#   STEP 3 — run it
#
#     In RStudio: click "Source" (or Ctrl/Cmd + Shift + S).
#     In a terminal: Rscript run.R
#
#   The answer lands in output/derived_variables.csv — one row per cohort
#   member, one column per variable, joined on {{identifier}}.
#
# ==========================================================================


# --- Settings -------------------------------------------------------------

# Where your deposits are. Leave as "" to use the `data/` folder next to this
# file. A `~` is fine. Windows paths: use forward slashes, "C:/data/{{root}}".
DATA_DIR <- ""

# Which variables to build. Leave empty for all of them. To build just one or
# two while you check them, name them: c("{{sample_id}}")
VARIABLES <- character(0)


# ==========================================================================
# Nothing below here needs editing.
# ==========================================================================

# The deposited files these variables read. Every one has to be present, so
# they are checked up front rather than discovered one failure at a time.
NEEDED <- {{files}}

# Where load_tab() resolves file names through. Named here only so the checks
# below can look for it before anything tries to read it.
LOOKUP <- "{{lookup}}"


# --- A readable failure ---------------------------------------------------

# stop() with call. = FALSE and no "Error in ..." preamble: these messages are
# addressed to a researcher who has just opened the project, not to whoever
# wrote this file. Blank lines survive, so the message can breathe.
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

# Tried in order, and the order is deliberate: an explicit setting in this
# file beats the environment, which beats a guess. Each candidate has to
# actually contain the lookup to count - a `data/` folder that exists but is
# empty is the normal state of a fresh download, not an answer.
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

# A very common near-miss: the deposits were unzipped into data/ but arrived
# wrapped in their own folder, so the lookup is one level deeper than
# expected. That is not a mistake worth a stop() - say what was assumed and
# carry on.
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

# The runner is sourced rather than run: since the guard at the bottom of
# R/runner.R, source()ing it defines its functions without also starting a
# run. That matters here because the checks below need the SAME discovery and
# spec-loading the run will use - find_variable_files(), load_variable() and
# the placement validation - rather than a second copy of them that could
# disagree about which scripts exist or what they declare.
{{set_root}}

suppressWarnings(source(file.path("R", "runner.R")))

lookup <- utils::read.csv(file.path(data_dir, LOOKUP), stringsAsFactors = FALSE)

required <- c("file_name", "file_type", "sweep", "path")
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
  row <- lookup[lookup$file_name == file_name & lookup$file_type == "tab", ]
  if (nrow(row) == 0) return(NA_character_)
  file.path(data_dir, row$sweep[1], row$path[1])
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

# What each variable declares it reads. Read through the runner's own loader,
# so a script that would fail to load at run time fails here instead.
specs <- lapply(find_variable_files("R/variables"), load_variable)
ids <- vapply(specs, function(v) v$spec$id, character(1))

# Why a variable cannot be built: a file that is not here, or a column that is
# not in the files that are. Both are reported the same way, because from where
# the researcher sits they are the same problem - something this variable needs
# is not in their copy of the data.
# Only file presence is checked here, and only from the lookup - no deposit is
# opened. Anything deeper (a column a deposit does not have, a derive() that
# throws) is the runner's to find and to report: since it isolates failures
# per variable, a second copy of "can this one be built" living out here would
# be one more thing to disagree with it.
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

# Anything the runner could not build is reported by the runner itself, in
# detail, above. This only adds up what that means for the file just written.
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

# A partial run is a failed run to anything scripting this, even though a file
# was written. Interactive sessions are left alone - quitting RStudio's console
# because two variables were skipped would be its own kind of rude.
if (lost > 0 && !interactive()) {
  quit(status = 1L)
}
