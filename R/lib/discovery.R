# Locating and validating derived-variable scripts.
#
# Every variable script lives at exactly one depth:
#
#   R/variables/<category>/<family>/<id>.R
#
#   <category>  one of variable_categories below, and must equal the
#               script's own spec$category - the two are cross-checked so
#               a file cannot drift away from the category it declares
#   <family>    groups variables measuring the same concept, typically the
#               longitudinal siblings of one request (housing_tenure/,
#               bmi/). Always present, even for a lone variable, so every
#               script sits at the same depth and a one-off can gain
#               siblings later without moving
#   <id>        matches spec$id exactly - Rscript R/runner.R <id> filters
#               on the file name, so a mismatch silently makes a variable
#               unrunnable
#
# Shared by R/runner.R and scripts/build_registry.R so discovery and the
# layout rules are defined once rather than drifting between them.

# lintr note: this file reads the constants in R/lib/dataset.R, which every
# entry point source()s before it. lintr cannot follow a source(), so .lintr
# disables object_usage_linter for this file only - every other linter applies.

variable_categories <- c(
  "demographic", "socio_economic", "health", "education",
  "employment", "family_relationships", "housing",
  "behavioural_lifestyle", "cognitive_ability", "other"
)

# Every variable script, at any depth. Deliberately recursive rather than
# globbing the expected three levels: a misplaced script must be found and
# reported by parse_variable_path() below, never silently skipped.
find_variable_files <- function(variables_dir = "R/variables") {
  sort(list.files(variables_dir, pattern = "\\.R$", recursive = TRUE, full.names = TRUE))
}

# Split a script path into its category/family/id, failing loudly if the
# path does not have the required shape.
parse_variable_path <- function(path, variables_dir = "R/variables") {
  rel <- sub(paste0("^", variables_dir, "/"), "", path)
  parts <- strsplit(rel, "/", fixed = TRUE)[[1]]

  if (length(parts) != 3) {
    stop(sprintf(
      "%s: expected %s/<category>/<family>/<id>.R (3 levels), found %d. See CLAUDE.md#repository-layout.",
      path, variables_dir, length(parts)
    ))
  }

  if (!(parts[1] %in% variable_categories)) {
    stop(sprintf(
      "%s: '%s' is not a known category. Must be one of: %s. See CONTRIBUTING.md#variable-categories.",
      path, parts[1], paste(variable_categories, collapse = ", ")
    ))
  }

  list(
    category = parts[1],
    family = parts[2],
    id = tools::file_path_sans_ext(parts[3])
  )
}

# Cross-check a loaded spec against where its file actually sits. Both
# mismatches are silent failures otherwise: a wrong category misgroups the
# variable in registry/, and a wrong id makes `Rscript R/runner.R <id>`
# unable to select it.
check_variable_placement <- function(path, spec, variables_dir = "R/variables") {
  location <- parse_variable_path(path, variables_dir)

  # Render a spec field for an error message: plain for the ordinary
  # single-string case, deparsed only when it is something unexpected
  # (NULL, a vector) and the reader needs to see its actual shape.
  as_label <- function(x) {
    if (is.character(x) && length(x) == 1) x else paste(deparse(x), collapse = "")
  }

  if (!identical(spec$id, location$id)) {
    stop(sprintf(
      "%s: spec$id is '%s' but the file name says '%s' - they must match exactly.",
      path, as_label(spec$id), location$id
    ))
  }

  if (!identical(spec$category, location$category)) {
    stop(sprintf(
      "%s: spec$category is '%s' but the file sits under '%s/'. Move the file or fix the spec.",
      path, as_label(spec$category), location$category
    ))
  }

  location
}

# Reject a spec that declares the identifier as one of its source variables.
#
# The identifier is already supplied to every derive() and is already the
# output's key, so declaring it is meaningless - and both spellings are broken
# rather than merely redundant. The deposit's own casing no longer matches once
# load_tab() has normalised it, so the runner stops with "not found"; the
# normalised spelling DOES match, and narrowing then yields two identifier
# columns, which R silently renames and carries into the output.
#
# The second is the dangerous one, so this is checked by name rather than left
# to whichever error surfaces.
check_source_vars <- function(path, spec) {
  declared <- as.character(spec$source_vars)
  offending <- unique(declared[tolower(declared) == tolower(identifier_column)])

  if (length(offending) > 0) {
    stop(sprintf(
      paste(
        "%s: spec$source_vars declares the identifier (%s).",
        "\n  The identifier is not a variable - it is the key every variable is",
        "\n  joined on, and derive() already receives it as data$%s. Remove it",
        "\n  from source_vars; the output column is added automatically."
      ),
      path, paste(offending, collapse = ", "), identifier_column
    ), call. = FALSE)
  }

  invisible(spec)
}
