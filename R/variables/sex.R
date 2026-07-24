# ==========================================================================
# Derived variable: sex
# --------------------------------------------------------------------------
# This file is self-contained and is the single source of truth for this
# variable - a future front end will display this file's raw source as
# "how this variable was made". R/runner.R discovers and runs it
# automatically; don't source or call it manually anywhere else.
#
# Rules for this file:
#   - Never read from disk (no read.csv/read.delim/file paths). All input
#     arrives via the `data` argument to derive().
#   - Never write to disk. Return the derived column; the runner writes it.
#   - Never reference bcs70/ directly - it must stay read-only.
# ==========================================================================

spec <- list(
  id = "sex",
  label = "Sex of cohort member, most recent non-missing self-report across sweeps",
  category = "demographic",
  github_issue = 2,
  status = "draft",
  author = "Mack Nixon (via Claude Code, new-variable skill)",
  created = "2026-07-24",
  source_files = c(
    "bcs7072a", # 0y
    "f699c", # 5y
    "sn3723", # 10y
    "bcs7016x", # 16y
    "bcs21yearsample", # 21y
    "bcs96x", # 26y
    "bcs2000", # 29y
    "bcs_2004_followup", # 34y
    "bcs_2008_followup", # 38y
    "bcs70_2012_flatfile", # 42y
    "bcs_age46_main", # 46y
    "bcs11_age51_main", # 51y
    "bcs70_response_1970-2021" # xwave - fallback only, see notes
  ),
  source_vars = c(
    "a0255", "f003", "sex10", "sex86", "sex", "b960337",
    "bd7sex", "bd8sex", "B9CMSEX", "B10CMSEX", "b11sex"
  ),
  notes = paste(
    "Issue #2: 'Capture the sex of a participant. Take the most recent non",
    "null value.' One cohort-member-own-sex variable was picked per sweep",
    "(excluding partner/child/other-household-member sex variables, which",
    "exist in most sweep files alongside it) via the metadata-search skill:",
    "0y=a0255 (bcs7072a), 5y=f003 (f699c), 10y=sex10 (sn3723),",
    "16y=sex86 (bcs7016x), 21y=sex (bcs21yearsample), 26y=b960337 (bcs96x,",
    "self-report - bcs96x also has a 'sex' var but it's 'Sex from Address",
    "File', an admin source, not a self-report, so it was not used),",
    "29y=sex (bcs2000, 'CM gender [derived]'), 34y=bd7sex (bcs_2004_followup,",
    "already reconciled against the address database), 38y=bd8sex",
    "(bcs_2008_followup, labelled '(Derived) ... (final)'),",
    "42y=B9CMSEX (bcs70_2012_flatfile), 46y=B10CMSEX (bcs_age46_main, study",
    "8547 - not 8611, which is the age-46 accelerometry sub-study),",
    "51y=b11sex (bcs11_age51_main). The xwave response file's own 'sex'",
    "('Birth sex of cohort member', bcs70_response_1970-2021) is used only",
    "as a last-resort fallback, for anyone missing at every sweep-specific",
    "occasion - it wasn't given priority over sweep values because the",
    "request asks for the most RECENT self-report, and this file isn't tied",
    "to a single occasion.",
    "5y note for reviewer: bcs70_1975_developmental_history/VAR5503 and",
    "f699a/d003 are two other 5y candidates not used here (arbitrary choice",
    "among near-duplicates) - worth a second opinion.",
    "Every source variable is coded 1=Male, 2=Female with sweep-specific",
    "negative and/or positive sentinel codes for missing/not-known/refused",
    "(these differ per sweep - see each dictionary's value_labels_json);",
    "derive() whitelists only 1/2 as valid and treats every other code as",
    "missing, so no sentinel scheme needs to be enumerated here."
  )
)

derive <- function(data) {
  to_sex <- function(x) ifelse(x %in% c(1, 2), x, NA_real_)
  coalesce_first <- function(...) Reduce(function(acc, x) ifelse(is.na(acc), x, acc), list(...))

  most_recent <- coalesce_first(
    to_sex(data$b11sex), # 51y
    to_sex(data$B10CMSEX), # 46y
    to_sex(data$B9CMSEX), # 42y
    to_sex(data$bd8sex), # 38y
    to_sex(data$bd7sex), # 34y
    to_sex(data[["bcs2000.sex"]]), # 29y
    to_sex(data$b960337), # 26y
    to_sex(data[["bcs21yearsample.sex"]]), # 21y
    to_sex(data$sex86), # 16y
    to_sex(data$sex10), # 10y
    to_sex(data$f003), # 5y
    to_sex(data$a0255), # 0y
    to_sex(data[["bcs70_response_1970-2021.sex"]]) # xwave fallback
  )

  # Deliberately not ifelse(): when its `test` is NA, ifelse()'s result
  # inherits `test`'s (logical) storage mode rather than the yes/no branch
  # type, so an all-missing row would silently produce a logical NA instead
  # of NA_character_. A named-vector lookup avoids that entirely.
  sex_labels <- c(`1` = "male", `2` = "female")
  data.frame(
    bcsid = data$bcsid,
    sex = unname(sex_labels[as.character(most_recent)])
  )
}
