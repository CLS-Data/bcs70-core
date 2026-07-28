---
name: verify-variable
description: Record the outcome once a variable script has been run against the real BCS70 data outside this repo, updating its spec status and closing the loop on the originating issue.
---

# Verify variable

If the real-data run surfaced anything about the deposits themselves -
unexpected identifier behaviour, sentinel codes not documented in the
dictionary, a category that never appears - flag it for `DATA_KNOWLEDGE.md`
in your report. That ledger is how such findings survive past a single PR.
Leave the edit to the user; it is hand-maintained.

Use this after a maintainer reports back real-data test results for a variable that was previously merged with `spec$status = "draft"` or `"ready_for_real_data_test"`. This repo never contains real data, so this status change is always driven by a human reporting an external result (see `CONTRIBUTING.md#running-the-scripts-against-the-real-data` for how they produce it) - never set `status = "verified"` from synthetic-test results alone.

## Steps

1. Ask for (or read from the issue/PR comment) the outcome: pass/fail, and any discrepancies found on real data. This should already be an *aggregate* summary (e.g. "12,432 non-missing, distribution matches expected labels" or a named missing column) - if a real row-level value, respondent-level data, or a raw export shows up in what you're given, stop and flag it rather than repeating or logging it anywhere; ask the reporter to resend an aggregate-only summary instead.
2. If verified clean: update `spec$status` in `R/variables/<category>/<family>/<id>.R` to `"verified"`, and append a one-line dated note to `spec$notes` recording that it was checked against real data.
3. If issues were found: keep `status` at `"draft"`, record the specific discrepancy in `spec$notes`, and treat this as a bug-fix task on the existing script - fix the logic, add a synthetic test case that reproduces the discrepancy, then re-run the `format-r` and `lint-r` skills and the test suite.
4. Invoke the `update-registry` skill so `registry/` reflects the new status/notes.
5. Open a small PR for the status/notes update (or the fix), referencing the original issue, and close the issue once merged if the variable is now verified.
