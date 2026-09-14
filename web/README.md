# Variable atlas

A site for finding raw variables across a longitudinal study's instruments,
reading what has been harmonised from them, and drafting a new variable
request — with an assistant that will do the last part with you.

Configured for one dataset at a time by `web/dataset.toml`.

```
web/
  dataset.toml    EVERYTHING dataset-specific. Start here.
  config.py       loads it                                       [stdlib]
  build_site.py   generates data/ from the deposits and registry/ [stdlib]
  build_embeddings.py  optional semantic index for the search     [stdlib + Ollama]
  server.py       serves the site and the assistant's /api        [stdlib]
  index.html
  styles.css
  atlas/          the atlas itself — one module per view
                  boot, state, dom, spine, views, metadata, derived,
                  basket (what you collected + the R you will download)
  bundle.js       packages selected variables as a runnable zip [loaded on demand]
  chat.js         the assistant's turn loop and wiring
  chat/           one module per panel — state (incl. which intent the
                  conversation is in, which the server does not remember),
                  api, transcript, steps,
                  composer, draft, settings
  assistant/      what the assistant asks and looks up   → assistant/README.md
  data/           generated, gitignored
```

No bundler and no build step: both halves are ES modules loaded straight by
the browser, and the Python is standard library. The one exception is the
assistant, which is an optional extra.

## Running it locally

`data/` is not in the repository, so build it first:

```
python3 web/build_site.py        # after any metadata or registry change
python3 web/server.py            # then open http://localhost:8000
```

One process serves the site and the API. Browsing needs **no install at all**;
the assistant needs one:

```
uv sync --extra assistant        # langgraph, langchain-ollama
```

Without it, `server.py` prints a note, `/api/health` reports
`assistant: false`, and the drawer disables itself with the install command in
its tooltip. Everything else is unaffected.

### Searching by meaning (optional)

```
python3 web/build_embeddings.py          # ~4 minutes, needs Ollama
python3 web/build_embeddings.py --check  # is the existing index current?
```

Embeds every variable label locally so the assistant's lookups can match a
concept whose wording they do not share — *"How is your health generally"* for
**self-rated health**. ~33 MB into the gitignored `data/`, so it is never
committed and CI never builds it.

Everything works without it: retrieval falls back to BM25, `server.py` says
which mode it is in on its first line, and the drawer's switch is disabled
with the reason. Rebuild it after any `build_site.py` that changes which
variables exist — the index is positional, and a stale one is **refused
rather than used**.

`build_site.py` reads the metadata CSVs under the configured `[dataset] root`
and `registry/variables.json`. It never opens a data file, so no row of study
data can reach the site.

## Tests

```
python3 -m unittest discover -s web/tests
```

Standard library, nothing to install, and no built `data/` required — they run
against a small synthetic corpus, so they work in a fresh checkout and in CI.

They cover ranking (an exact name first; a word inside a phrase *not* read as
a name), wave filtering, grouping, the suggestions offered when a name lookup
misses, semantic fusion and query expansion against stubs, and the rules that
were wrong once and are now kept where a test can reach them: the hop budget,
the checklist's completeness, an intent's declared behaviour, and the pairing
of a lookup's result to the call that asked for it.

## Pointing it at another dataset

**Nothing outside `dataset.toml` names a study.** Not the Python, not the
JavaScript, not the markup. The study's name and background, what one round of
collection is called, the order of those rounds, the metadata CSVs' column
names, the categories, the issue form's field ids, the retrieval tuning, the
assistant's capabilities and its whole interview all live in that one file.

```
cp web/dataset.toml web/other.toml     # then edit it
ATLAS_DATASET_CONFIG=web/other.toml python3 web/build_site.py
ATLAS_DATASET_CONFIG=web/other.toml python3 web/server.py
```

Change `[wave] term` from `sweep` to `visit` and the whole system follows: the
system prompt says "Visits are rounds, not years", the search tool's parameter
is named `visit`, the draft asks for `bmi_<visit>`, and its own field label
reads "Visits involved". That is checked, not asserted.

`build_site.py` copies the browser's share of the config into
`data/manifest.json`, so the front end reads one source of truth rather than
keeping its own copy. Storage keys are namespaced per dataset
(`atlas:<key>:draft`), so two atlases on one origin never collide.

## What it does

**Metadata** — search every variable by name or label. Names are terse and
inconsistent between waves, so searching the label usually beats guessing the
name. Open one to see its value labels, declared missing codes, position, and
the file and study it came from. Filter by **measurement level**, by wave from
the spine, or by file from a variable's detail pane; the three combine, and
each shows as a clearable chip.

That box scans the index the page already holds, in the browser. It is
literal, so it finds a fragment of a half-remembered name — `b960`, `hlth` —
which the assistant's BM25 cannot match at all, since that indexes whole
tokens. It needs no server, which is what keeps the site static. **The
assistant's lookups are a different search** over the same corpus, ranked and
optionally semantic, via `/api/search`. Neither subsumes the other:
`cigarettes per day` is found by one and not the other, and `b960` the
reverse.

**Derived** — the harmonised variables, filterable by **category**. Each shows
the source that produces it, the files it draws on, and the raw variables it
needs, all clickable back into the metadata. Add any of them and **download
the R code** that produces them (below).

**R bundle** — what you have collected, and the R you are about to download.
Its list pane is what you picked up; its detail pane is the output CSV's
columns, which is where a name collision between two deposits becomes visible.
The tab accepts drops, so a variable can be dragged to it from either list.

**Assistant** — where a variable *request* is written, by conversation, with
every name checked against the index as it goes. Nothing is submitted until you
review it on GitHub. See [assistant/README.md](assistant/README.md).

The level filter reads `measurement_level`, not `variable_type`: the obvious
"type" field does not discriminate — 31,472 of 32,454 variables are `numeric`.
Both filters draw empty options too, for the reason the spine draws empty
waves: knowing a search has no scale variables is the answer. Counts are
tallied *before* that filter is applied, so each says what choosing it would
give, not what is already on screen.

## Downloading variables as R code

Drag variables from either list onto the **R bundle** tab — or use the `＋`
beside any row — then open that view to review what you are about to download.
Both kinds of variable go in the same bundle and come out as columns of the
same CSV. Its list pane is what you picked up; its detail pane is the output
CSV's columns, which is where a name collision becomes visible.

What comes out is an **RStudio project**, not a folder of scripts:

```
bcs70-variables-<date>/
  bcs70-variables-<date>.Rproj   open this — it sets the working directory
  run.R                          the one file to run: checks, then runs
  data/README.md                 the empty folder the deposits can go in
  README.md                      what it is, what is unverified, what to do if
  R/runner.R                     \  the pipeline, verbatim
  R/lib/{io,utils,discovery}.R   /
  R/variables/<category>/<family>/<id>.R       harmonised — copied verbatim
  R/variables/other/raw_<file>/<column>.R      raw — generated from a template
```

Base R, no packages, no repository checkout. Open the `.Rproj`, either drop the
deposits into `data/` or set `DATA_DIR` at the top of `run.R`, and run it.

Five things about this are deliberate:

- **The R is shipped verbatim, never regenerated.** A bundle-specific runner
  would be a second implementation of the join, the identifier cleaning and the
  duplicate resolution — and the day it drifted, the researcher's numbers would
  quietly stop matching this repository's.
- **A raw variable is a variable script whose `derive()` is the identity.**
  There is nothing to copy for a deposited column, so `bundle.js` writes one
  from `templates/passthrough.R` — and writes nothing else. Because it declares
  `source_files` and `source_vars` like any other script, `runner.R` resolves,
  cleans, de-duplicates and joins it with the same code it uses for a
  harmonised one. The rule above survives: no second implementation of
  anything, only a second kind of leaf. `web/tests/test_passthrough.py` holds
  that template to what `R/lib/discovery.R` will accept.
- **The zip is written in the browser**, so no server is involved. `bundle.js`
  writes the archive format itself rather than taking a dependency, and fetches
  the pipeline source only when someone actually downloads something.
- **The README names what is unverified, and what was never harmonised.** A
  `draft` variable has passed synthetic tests, which cannot tell you its codes
  are the codes your deposit uses. A raw column has not been recoded at all —
  its missing-value sentinels are still in it. The view warns about both before
  the download; the README repeats them after it.

- **`run.R` checks before it reads, and each failure says what to do.** Almost
  every way this goes wrong is one of three things, and all three are caught
  before a single file is opened: the working directory is not the project, the
  data is not where it was expected, or a deposited file is missing. The first
  two stop with the paths they tried and the two ways to fix it. The third does
  not stop at all — the variables that need the missing file are named and
  skipped, and the rest still build, because a partial answer beats a traceback
  three quarters of the way through a run.

  It gets to do that without duplicating anything: `R/runner.R` guards its own
  invocation with `sys.nframe() == 0L`, so sourcing it defines `run_all()`
  without starting a run, and `run.R` uses the runner's own
  `find_variable_files()` and `load_variable()` to read what each script
  declares. A second copy of discovery would be a second thing to be wrong —
  which is why `run.R` stops at *where is the data*. Deciding which variables
  can actually be built belongs to `run_all()`.

- **One variable never denies you the others.** `run_all()` isolates failure
  per variable: a script that is invalid, or whose deposit lacks a column it
  declares, is skipped rather than aborting the batch. Every failure is
  reported together, the output is written with whatever succeeded, and the run
  exits non-zero — so a researcher gets their other twenty-nine columns and CI
  still fails. A partial output is always named as partial, because under the
  usual file name it is otherwise indistinguishable from a complete one.

  The invariant behind the case that prompted this lives in
  `R/lib/discovery.R`: **a spec must never declare the identifier in
  `source_vars`.** It is the key, not data — `derive()` already receives it and
  the output column is added automatically. Declaring it breaks two different
  ways (the deposit's own `BCSID` no longer matches once `load_tab()` lowercases
  it; `bcsid` *does* match and silently yields a duplicated `bcsid.1` column),
  so it is rejected by name rather than left to whichever error surfaces first.

### Naming a raw column

A harmonised variable's output name is its `spec$id` and is fixed: renaming it
would mean editing a script that was tested under that name. A raw column has
no such claim on a name, so the dock lets you choose one — defaulting to the
variable's own name, qualified with the wave only when that would collide.
Collisions are what the detail pane is really for: two deposits both calling
something `sex` is the normal case, not the exception, and `runner.R` joins on
column name. A bundle with a duplicate or unusable name cannot be downloaded
until it is fixed.

### Where variable requests went

This view used to be a request-drafting form. Collecting variables and asking
for a new one to be derived looked like one gesture and are not: one ends in a
zip you run this afternoon, the other in an issue someone works on for a week.
Requests are written in **the assistant's draft panel**, which was always the
better form — it checks every name against the 32,000-row index before showing
it, so a model that helpfully invents `bmi10` is caught. The bundle view keeps
a single plain link that opens the issue template carrying whatever is in the
basket, so the route survives when the `assistant` extra is not installed.

Raw variables from files with no row in `master_file_info_lookup.csv` are
refused at the point of the gesture: `load_tab()` resolves a `file_name`
through that lookup and nothing else, so the generated script would fail on the
first line of the run.

The environment variable is named in `dataset.toml` (`[dataset] data_env`) and
read by `R/lib/io.R`; leave it empty for a pipeline with no such override and
the README documents only the alongside layout.

## The sweep spine

The age axis across the top always reflects what is on screen: matches per wave
while searching, coverage across waves while reading a derived family. Waves
with nothing are drawn as dashed voids rather than omitted, because absence is
usually the thing you need to know. Click one to filter to it.

## Two things the site deliberately surfaces

**Files missing from the master lookup.** A deposited file can have a full data
dictionary but no row in the lookup, so the pipeline cannot resolve it and no
variable script can use it. Its variables stay searchable, with a warning on
the detail pane, rather than being hidden.

**Duplicate file names.** One file name is deposited under two different waves.
Everything here is keyed by wave *and* name, never name alone, so the two stay
distinct.

## Deploying to GitHub Pages

**Dormant: Pages will not serve from a private repository, and this one is
private.** `.github/workflows/pages.yml` is kept because nothing about it has
been made wrong — it publishes again as soon as the repository is public. Note
that the assistant talks to Ollama on `localhost`, so a published copy carries
the drawer but never connects.

The workflow runs `build_site.py` and uploads this directory on every push to
`main` touching `web/`, `registry/`, or `bcs70/`. Three things about it:

- **`data/` is built at publish time, not committed.** The published site is
  therefore built from the commit being published and cannot disagree with its
  `registry/`, there is no stale state to detect, and ~88 files of generated
  JSON stay out of every variable PR's diff.
- **`registry/**` and `bcs70/**` are trigger paths deliberately.** They are the
  workflow's real inputs; leaving them out made merges publish nothing.
- **Settings → Pages → Source must be GitHub Actions**, not a branch. With a
  branch selected the run goes red without publishing while the old copy stays
  up, so the site looks fine and is silently frozen.

Publishing exposes the data dictionaries — names, labels, value labels,
missing-value codes — to anyone. No row of study data is ever included, but
that is a licensing decision to make deliberately.

`data/` is ~21 MB, mostly the per-file dictionaries, fetched only when a
variable is opened. The initial load is the 2.0 MB search index (~350 KB
gzipped) plus the manifest.
