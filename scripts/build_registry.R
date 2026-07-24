#!/usr/bin/env Rscript
# Regenerates the machine-readable variable registry (registry/variables.json
# and registry/variables.csv) by scanning every R/variables/*.R spec.
#
# This is the single source of truth a front end (or CI) should read for the
# list of derived variables, grouped by category. Never hand-edit anything
# under registry/ - it is fully derived from R/variables/*.R; if its content
# looks wrong, fix the source spec and re-run this script.
#
# Usage: Rscript scripts/build_registry.R

allowed_categories <- c(
  "demographic", "socio_economic", "health", "education",
  "employment", "family_relationships", "housing",
  "behavioural_lifestyle", "cognitive_ability", "other"
)

load_entry <- function(path) {
  env <- new.env()
  sys.source(path, envir = env)
  spec <- env$spec
  if (!is.list(spec)) {
    stop(sprintf("%s does not define `spec`", path))
  }
  if (is.null(spec$category) || length(spec$category) != 1 || !(spec$category %in% allowed_categories)) {
    stop(sprintf(
      "%s: spec$category must be exactly one of: %s (got: %s). See CONTRIBUTING.md#variable-categories.",
      path, paste(allowed_categories, collapse = ", "), paste(deparse(spec$category), collapse = "")
    ))
  }
  list(
    id = spec$id,
    label = spec$label,
    category = spec$category,
    github_issue = spec$github_issue,
    status = spec$status,
    author = spec$author,
    created = spec$created,
    source_files = I(as.character(spec$source_files)),
    source_vars = I(as.character(spec$source_vars)),
    notes = spec$notes,
    file = path
  )
}

variable_files <- sort(list.files("R/variables", pattern = "\\.R$", full.names = TRUE))
entries <- lapply(variable_files, load_entry)

ids <- vapply(entries, function(e) e$id, character(1))
if (any(duplicated(ids))) {
  stop(sprintf("Duplicate spec$id across R/variables/: %s", paste(unique(ids[duplicated(ids)]), collapse = ", ")))
}
names(entries) <- ids

by_category <- lapply(split(entries, vapply(entries, function(e) e$category, character(1))), unname)
for (category in allowed_categories) {
  if (is.null(by_category[[category]])) {
    by_category[[category]] <- list()
  }
}
by_category <- by_category[allowed_categories]

registry <- list(categories = by_category)

dir.create("registry", showWarnings = FALSE)
jsonlite::write_json(registry, "registry/variables.json", pretty = TRUE, auto_unbox = TRUE, na = "null")

csv_rows <- lapply(entries, function(e) {
  data.frame(
    id = e$id,
    category = e$category,
    label = e$label,
    github_issue = ifelse(is.null(e$github_issue) || is.na(e$github_issue), NA, e$github_issue),
    status = e$status,
    source_files = paste(e$source_files, collapse = "; "),
    source_vars = paste(e$source_vars, collapse = "; "),
    file = e$file,
    stringsAsFactors = FALSE
  )
})
csv_out <- if (length(csv_rows) == 0) {
  data.frame(
    id = character(), category = character(), label = character(), github_issue = character(),
    status = character(), source_files = character(), source_vars = character(), file = character()
  )
} else {
  do.call(rbind, csv_rows)
}
write.csv(csv_out, "registry/variables.csv", row.names = FALSE)

cat(sprintf(
  "Wrote %d variable(s) to registry/variables.json and registry/variables.csv\n",
  length(entries)
))
