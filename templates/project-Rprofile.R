# Shipped as `.Rprofile` at the top of an atlas bundle. It prints what to do,
# and in RStudio opens README.md. Everything that runs is in run.R.
#
# R sources this for every session started here, `Rscript run.R` included, so
# everything below is guarded on interactive().

# A project .Rprofile SHADOWS the user's own rather than adding to it, which
# would silently drop their CRAN mirror and prompt for as long as this folder
# is open. Load theirs first, and do not let it stop this one.
local({
  personal <- path.expand("~/.Rprofile")
  same <- identical(normalizePath(personal, mustWork = FALSE),
                    normalizePath(".Rprofile", mustWork = FALSE))
  if (file.exists(personal) && !same) try(source(personal), silent = TRUE)
})

if (interactive()) {
  cat("\n{{dataset}} - {{count}}\n\n")
  cat("  1. Tell run.R where your data is (or put it in data/)\n")
  cat("  2. Run run.R\n\n")
  cat("  README.md explains both, and what to do when something is missing.\n\n")

  # RStudio cannot be asked for anything at profile time, so this waits for it.
  # Any other front end never fires the hook, and the banner above is all that
  # happens. rstudioapi ships with RStudio but can be absent; nothing here is
  # worth a warning if it is.
  setHook("rstudio.sessionInit", function(new_session) {
    if (new_session && file.exists("README.md") &&
          requireNamespace("rstudioapi", quietly = TRUE)) {
      try(rstudioapi::navigateToFile("README.md"), silent = TRUE)
    }
  }, action = "append")
}
