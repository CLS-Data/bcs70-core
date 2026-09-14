# ==========================================================================
# Shipped as `.Rprofile` at the top of an atlas bundle.
#
# It does two things and nothing else: it prints what to do, and in RStudio it
# opens README.md so the instructions are on screen rather than in a file
# somebody has to think to open. Everything that actually runs is in run.R.
#
# R sources this automatically when a session starts in this directory - which
# includes `Rscript run.R`. Every effect below is therefore guarded on being an
# interactive session, so a scripted run behaves as if this file did not exist.
# ==========================================================================

# A project .Rprofile SHADOWS the user's own ~/.Rprofile rather than adding to
# it - R loads only the first one it finds. Somebody whose personal profile
# sets a CRAN mirror or a prompt would otherwise find those silently gone for
# as long as this project is open, which is a surprising thing for a folder of
# harmonisation scripts to do. So theirs is loaded first, and its failure is
# not allowed to stop this one.
local({
  personal <- path.expand("~/.Rprofile")
  if (file.exists(personal) && !identical(normalizePath(personal, mustWork = FALSE),
                                          normalizePath(".Rprofile", mustWork = FALSE))) {
    try(source(personal), silent = TRUE)
  }
})

if (interactive()) {
  local({
    banner <- function() {
      cat("\n")
      cat("{{dataset}} - {{count}}\n")
      cat("\n")
      cat("  1. Tell run.R where your data is (or put it in data/)\n")
      cat("  2. Run run.R\n")
      cat("\n")
      cat("  README.md explains both, and what to do when something is missing.\n")
      cat("\n")
    }

    banner()

    # RStudio is not ready to be asked for anything at profile time, so the
    # request waits for the session to finish starting. This hook is RStudio's
    # own; in any other front end it is simply never fired, and the banner
    # above is all that happens.
    setHook("rstudio.sessionInit", function(new_session) {
      if (!new_session || !file.exists("README.md")) {
        return(invisible(NULL))
      }
      # rstudioapi ships with RStudio but is an ordinary package and can be
      # absent. Nothing here is important enough to warn about if it is: the
      # README is one click away in the Files pane either way.
      if (requireNamespace("rstudioapi", quietly = TRUE)) {
        try(rstudioapi::navigateToFile("README.md"), silent = TRUE)
      }
    }, action = "append")
  })
}
