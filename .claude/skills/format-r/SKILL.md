---
name: format-r
description: Auto-format R scripts in this repo with styler so every variable script follows one consistent style.
---

# Format R

Run:

    Rscript -e 'styler::style_dir("R"); styler::style_dir("tests")'

Then show the user a `git diff` of what changed (or report "no changes" if styler made none). Never hand-tune whitespace or formatting in `.R` files yourself when this skill applies - let styler own it, so every script stays consistent byte-for-byte. If `styler` isn't installed, tell the user to run `install.packages("styler")` rather than skipping the check.
