---
name: format-r
description: Auto-format R scripts in this repo with styler so every variable script follows one consistent style.
---

# Format R

Run:

    Rscript -e 'styler::cache_deactivate(); styler::style_dir("R"); styler::style_dir("tests")'

Then show the user a `git diff` of what changed (or report "no changes" if styler made none). Never hand-tune whitespace or formatting in `.R` files yourself when this skill applies - let styler own it, so every script stays consistent byte-for-byte. If `styler` isn't installed, tell the user to run `install.packages("styler")` rather than skipping the check.

`cache_deactivate()` is called first because styler's on-disk cache can throw a permission error in sandboxed/restricted environments - it's only a performance optimization, so disabling it is always safe.
