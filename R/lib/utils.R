# Shared helpers for derived-variable scripts.
# Add to this file as real variables reveal common needs - keep it small
# and only add what's actually reused by two or more variables.

# Replace common UKDS/CLS negative sentinel codes (e.g. -1 Not applicable,
# -2 Not known, -3 Not stated, -8/-9 Refused/Missing) with NA. Always check
# the variable's own data dictionary (value_labels_json) for which negative
# codes actually apply - they are not consistent across every variable.
na_if_negative <- function(x, codes = c(-1, -2, -3, -8, -9)) {
  ifelse(x %in% codes, NA, x)
}
