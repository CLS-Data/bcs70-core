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

---

## Coverage gaps

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
