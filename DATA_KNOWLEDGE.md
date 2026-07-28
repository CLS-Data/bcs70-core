# Data knowledge ledger

Known quirks, traps and hard-won findings about the BCS70 deposits — the
things that aren't visible in a data dictionary and that you'd otherwise
have to rediscover by getting a variable wrong first.

This file is **maintained by hand, by the people who run this repo against
the real data.** It grows over time. It is not generated, and nothing here
should be derived automatically from `bcs70/` — the point is to capture what
the metadata *doesn't* tell you.

**If you are an agent:** read this before an exhaustive metadata search and
again before writing any `derive()` logic. An entry here overrides your
default reading of a data dictionary. If your work turns up something new
that would have been useful to know beforehand, say so in your report so a
human can add it — **do not add entries yourself.** You cannot see the real
data, so you cannot establish the facts this file records.

## How to add an entry

One entry per finding, newest first inside its section. Keep each one short
enough to be read in full, and always separate what is **confirmed** from
what is **suspected** — a wrong entry here is worse than a missing one,
because it will be trusted.

```markdown
### <short title>

**Scope:** whole corpus | sweep <n> | file `<file_name>` | variable `<var>`
**Status:** confirmed | suspected | resolved
**Found:** YYYY-MM-DD, <how it came to light>

<What the issue is, in a sentence or two.>

**Impact:** <what breaks, or what a derivation must do differently.>
**Handling:** <what the code currently does about it, if anything.>
```

---

## Identifiers

### Duplicate `bcsid` values in `sn3723` and `bcs21yearsample`

**Scope:** files `sn3723` (10y), `bcs21yearsample` (21y)
**Status:** confirmed
**Found:** 2026-07-27, real-data verification of the housing tenure family

The same `bcsid` appears on more than one row in both files. Every other
deposit checked so far has unique identifiers.

This was caught by the verification harness, not by anything in this repo:
`identifier_unique` failed for `housing_tenure_10y` (`sn3723`),
`housing_tenure_21y` (`bcs21yearsample`) and the integration run, while
every other check passed on all 11 variables. Nothing in the repo validated
identifier values at the time — `load_tab()` normalised only the identifier
*column name*.

**Impact:** `R/runner.R` joins variables with `merge(..., all = TRUE)`, so a
duplicated id multiplies rows through the join. Left unhandled, the combined
output gains rows that are indistinguishable from genuine cases.

**Handling:** `resolve_duplicate_ids()` in `R/lib/io.R`, applied by
`runner.R` *after* narrowing each file to the columns a variable declared.
Rows agreeing across every retained column collapse to one; an id whose rows
genuinely disagree is dropped with a warning, since nothing in the deposit
says which record is authoritative. Because the check runs post-narrowing,
the same duplicate pair may collapse harmlessly for one variable and
conflict for another — that is correct, not inconsistent. Verified: all 12
reports passed afterwards.

### `bcsid` values not matching the `B`-prefixed pattern

**Scope:** files `sn3723` (10y), `bcs21yearsample` (21y)
**Status:** suspected — reported by a maintainer, not independently confirmed
**Found:** 2026-07-27

Reported as instances where `bcsid` does not follow the study's usual `B*`
form. Worth distinguishing from the duplicate-id entry above: the
verification harness's `identifier_present` check *passed* on both files, so
there are no missing or blank identifiers, and `identifier_known` was
skipped, so nothing has actually tested the values against a reference list.
The exact shape of the offending values has not been recorded here yet.

**Impact:** an unlinkable id would survive `runner.R`'s outer join as a
phantom output row — one sweep's column populated, every other sweep `NA`,
which looks exactly like a genuine case observed at a single sweep.

**Handling:** `clean_bcsid()` in `R/lib/io.R` trims whitespace and upper-cases
first (both preserve identity), then drops anything still failing
`bcsid_pattern` with a counted warning. **That pattern is deliberately loose —
`^B` — and is an assumption, not a documented format.** No data dictionary
records a type or value labels for `bcsid`; the label is only ever "research
case identifier" or "BCS70 serial number". `clean_bcsid()` takes `pattern` as
an argument so it can be tightened once someone inspects the real values.
**If you inspect them, please record what they look like here.**

### Identifier column is `BCSID` in two files

**Scope:** files `bcs70_2012_flatfile` (42y), `bcs_age46_main` (46y)
**Status:** resolved
**Found:** pre-existing, documented in `CLAUDE.md`

These two deposits use upper-case `BCSID` where every other file uses
`bcsid`.

**Impact:** none remaining.
**Handling:** `load_tab()` lower-cases the identifier column name. Note it
lower-cases *only the identifier* — both files use upper-case names
throughout, so any other `source_vars` from them must stay upper-case
(`B9TEN`, `BD10TENURE`, …).

---

## Variable naming and coding traps

### The same variable name means different things in different sweeps

**Scope:** whole corpus
**Status:** confirmed
**Found:** 2026-07-27, housing tenure derivation

Raw variable names are not unique across sweeps, and colliding names are not
necessarily related. `c6.8` is the tenure question in `bcs7016x` (16y) but
"MOTHER WORKED NONSTANDARD HOURS SATURDAY" in `sn3723` (10y).

**Impact:** never carry a variable name from one sweep to another on the
assumption it measures the same thing. Always re-confirm against that
sweep's own dictionary.
**Handling:** `runner.R` disambiguates only when one spec declares the same
raw name across multiple `source_files`, renaming those columns to
`<file_name>.<var>`. It cannot protect you from declaring the wrong variable
in the first place.

### Variable names containing dots

**Scope:** file `bcs7016x` (16y), likely others
**Status:** confirmed
**Found:** 2026-07-27

Some 16y variables are literally named `c6.8`, `of3.3`. These are valid
column names but not valid bare R symbols.

**Impact:** `data$c6.8` does not work — use `data[["c6.8"]]`.
**Handling:** `load_tab()` reads with `check.names = FALSE`, so the name
survives intact rather than being mangled to `c6.8` → `c6_8`.

### Documented missing-value codes are inconsistent, and sometimes absent

**Scope:** whole corpus
**Status:** confirmed
**Found:** 2026-07-27

Sentinel schemes vary per variable, not per sweep. Examples encountered:
`-1`/`-2`/`-3` in early sweeps; `-9`/`-8`/`-7`/`-1` at 34y; `-9`/`-8`/`-3`/
`-2`/`-1` at 51y; `-4 "Vague"` only at 5y. Some variables document **no**
negative codes at all — `d2` in `sn3723` (10y) lists only values 1–7 in
`value_labels_json`, with no user-missing range.

**Impact:** never assume a shared sentinel set. A variable with no documented
sentinels may still contain them in the real file.
**Handling:** prefer allow-listing documented valid codes and letting
everything else fall through to `NA`, rather than deny-listing known
sentinels. `na_if_negative()` in `R/lib/utils.R` exists but its default code
list is a convenience, not a corpus-wide truth.

### Some deposited "derived" variables are unusable as-is

**Scope:** file `bcs21yearsample` (21y), variable `home21`
**Status:** confirmed
**Found:** 2026-07-27

`home21` "Tenure at 21" looks like a ready-made harmonised tenure variable,
but its first category is labelled `"Owned/rented"` — owner-occupation and
renting collapsed into one code.

**Impact:** cannot be mapped onto any scheme that distinguishes owning from
renting. The raw questions (`vc113` + `vc114`) had to be used instead.
**Handling:** none — check a deposited derived variable's actual value
labels before preferring it over the raw items. By contrast `BD10TENURE`
(46y) and `bd11tenure` (51y) *are* clean and are preferred over their raw
counterparts.

### A "No" that isn't a No

**Scope:** file `bcs7016x` (16y), variable `of3.3`
**Status:** confirmed
**Found:** 2026-07-27

`of3.3` "Is accommodation rented local auth-coun?" has value labels
`1 "Yes"` and `2 "No Response"` — the negative case is labelled as a
non-answer, not as "No".

**Impact:** a value of `2` cannot be read as "not local-authority rented"
without guessing. The variable was rejected as a back-fill source for that
reason.

### Proxy-reported counterparts exist at some sweeps but not all

**Scope:** sweeps 29y, 34y, 38y, 42y, 46y
**Status:** confirmed
**Found:** 2026-07-27

Several sweeps deposit both a self-reported item and a proxy-reported one
answered on the cohort member's behalf (`tenure`/`tenure2` at 29y,
`b7ten`/`b7ten2` at 34y, `B9TEN`/`B9PTE` at 42y). **38y does not** — an
exhaustive search of `bcs_2008_followup` found only `b8ten2` and `b8rentom`.

**Impact:** don't assume a proxy fallback is available at every sweep.
**Handling:** the established convention is self-report preferred, proxy
used only where the self-report is missing.

### Value-label sets differ between a variable and its own proxy

**Scope:** files `bcs70_2012_flatfile` (42y), `bcs11_age51_main` (51y)
**Status:** confirmed
**Found:** 2026-07-27

`B9TEN`'s labels skip code `6` ("Squatting") while its proxy `B9PTE`
includes it. At 51y neither `bd11tenure` nor `b11ten` documents a code `6`,
though 34y–46y all do.

**Impact:** a recode written from one variable's labels may silently drop a
category present in its sibling.
**Handling:** where the sweeps are meant to be uniform, accept the union of
documented codes and note it — the housing tenure scripts accept `6` at
every sweep for this reason.

---

## Coverage gaps

### Not every sweep carries every concept

**Scope:** sweeps 0y, 42m
**Status:** confirmed
**Found:** 2026-07-27

Neither 0y nor 42m has a housing tenure item. Both have dwelling **type**
(`b0008` "IN WHAT DWELLING WAS THE CHILD LIVING", `c0024` "Family dwelling
type" — whole house / flat / rooms / caravan), which is a different concept
and must not be used as a stand-in.

**Impact:** a "variable at each age" request rarely means all 13 sweeps.
Establish which sweeps genuinely carry the item before proposing an id list.

### The subject of measurement changes mid-study

**Scope:** sweeps 0y–16y vs 21y onwards
**Status:** confirmed
**Found:** 2026-07-27

Up to and including 16y, household questions are answered by the cohort
member's **parent** and describe the parental household. From 21y they
describe the cohort member's own household.

**Impact:** a childhood and an adult sibling of the "same" variable are not
one continuous series. Say so in `spec$label` and `spec$notes` — the housing
tenure family does this — and don't let a request for "X at each age" hide
the change of subject.

---

## Metadata gaps

### `bcsid` has no documented format anywhere

**Scope:** whole corpus
**Status:** confirmed
**Found:** 2026-07-27

Across all 85 data dictionaries, `bcsid` carries only a label — "research
case identifier", "Research case identifier", "BCS70 serial number", or "BCS
serial number (new series)" — with `variable_type` and `value_labels_json`
empty.

**Impact:** any expectation about identifier format is convention, not
specification. See the pattern entry under Identifiers.
