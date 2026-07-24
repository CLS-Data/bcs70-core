---
name: verify-variable
description: Record the outcome once a variable script has been run against the real BCS70 data outside this repo, updating its spec status and closing the loop on the originating issue.
---

# Verify variable

Use this after a maintainer reports back real-data test results for a variable that was previously merged with `spec$status = "draft"` or `"ready_for_real_data_test"`. This repo never contains real data, so this status change is always driven by a human reporting an external result - never set `status = "verified"` from synthetic-test results alone.

## Steps

1. Ask for (or read from the issue/PR comment) the outcome: pass/fail, and any discrepancies found on real data.
2. If verified clean: update `spec$status` in `R/variables/<id>.R` to `"verified"`, and append a one-line dated note to `spec$notes` recording that it was checked against real data.
3. If issues were found: keep `status` at `"draft"`, record the specific discrepancy in `spec$notes`, and treat this as a bug-fix task on the existing script - fix the logic, add a synthetic test case that reproduces the discrepancy, then re-run the `format-r` and `lint-r` skills and the test suite.
4. Invoke the `update-registry` skill so `registry/` reflects the new status/notes.
5. Open a small PR for the status/notes update (or the fix), referencing the original issue, and close the issue once merged if the variable is now verified.
