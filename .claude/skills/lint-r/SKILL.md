---
name: lint-r
description: Lint R scripts in this repo with lintr against the project's .lintr config and report/fix issues.
---

# Lint R

Run:

    Rscript -e 'print(c(lintr::lint_dir("R"), lintr::lint_dir("tests")))'

Report every lint verbatim (file:line, message) rather than summarizing counts. Fix straightforward issues directly (unused variables, missing braces, style lintr flags that styler doesn't cover, etc.), then re-run to confirm a clean pass. If a lint looks like a false positive, ask the user before adding an exclusion to `.lintr` - don't silently widen the exclusion list. If `lintr` isn't installed, tell the user to run `install.packages("lintr")`.
