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
  server.py       serves the site and the assistant's /api        [stdlib]
  index.html
  styles.css
  app.js          search, detail, scratchpad, selecting variables
  bundle.js       packages selected variables as a runnable zip [loaded on demand]
  chat.js         the assistant's turn loop and wiring
  chat/           one module per panel — state, api, transcript, steps,
                  composer, draft, settings
  assistant/      what the assistant asks and looks up   → assistant/README.md
  data/           generated, gitignored
```

No bundler and no build step: `chat.js` is an ES module, `app.js` is a plain
script, and the Python is standard library. The one exception is the
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

`build_site.py` reads the metadata CSVs under the configured `[dataset] root`
and `registry/variables.json`. It never opens a data file, so no row of study
data can reach the site.

## Tests

```
python3 -m unittest discover -s web/tests
```

Standard library, nothing to install, and no built `data/` required — they run
against a small synthetic corpus, so they work in a fresh checkout and in CI.
They cover retrieval: that an exact name ranks first, that a word inside a
phrase is **not** treated as a name, wave filtering, grouping, and the
suggestions offered when a name lookup misses.

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
is named `visit`, the draft asks for `bmi_<visit>`, and the scratchpad's label
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

**Derived** — the harmonised variables, filterable by **category**. Each shows
the source that produces it, the files it draws on, and the raw variables it
needs, all clickable back into the metadata. Tick any of them and **download
the R code** that produces them (below).

**Scratchpad** — collect candidates while browsing, describe what you want, and
open a prefilled GitHub issue. Nothing is submitted until you review it.

**Assistant** — the same destination, reached by conversation.
See [assistant/README.md](assistant/README.md).

The level filter reads `measurement_level`, not `variable_type`: the latter is
the more obvious "type" field and does not discriminate — 31,472 of 32,454
variables are `numeric`. Both filters draw every option including empty ones,
for the reason the spine draws empty waves: knowing a search contains no scale
variables is the answer, not a reason to hide the control. Counts beside each
option are tallied *before* that filter is applied, so a count says what
choosing it would give, not what is already on screen.

## Downloading variables as R code

Tick variables in the Derived view and the bar under the filters offers them as
a zip: a README, the runner and its libraries, and one script per variable at
the path the runner expects.

```
bcs70-variables-<date>/
  README.md                  what it is, how to run it, what is unverified
  R/runner.R                 \  the pipeline, verbatim
  R/lib/{io,utils,discovery}.R  /
  R/variables/<category>/<family>/<id>.R
```

Run it with base R against your own licensed copy of the deposits — no packages,
no repository checkout:

```
BCS70_DATA=/path/to/bcs70 Rscript R/runner.R      # or all of them, from beside bcs70/
Rscript R/runner.R bmi_10y                        # or just one
```

Three things about this are deliberate:

- **The R is shipped verbatim, never regenerated.** A bundle-specific runner
  would be a second implementation of the join, the identifier cleaning and the
  duplicate resolution, and the day it drifted from the tested one, the
  researcher's numbers would quietly stop matching this repository's. The
  bundle's `R/` is this repository's `R/`, minus the variables you did not pick.
- **The zip is written in the browser.** No server is involved, so this works on
  a static deploy; `bundle.js` writes the archive format itself rather than
  taking a dependency, and compresses through `CompressionStream` where the
  browser has it. The pipeline source is fetched from `data/pipeline.json` only
  when someone actually downloads something.
- **The README names what is unverified.** A `draft` variable has passed
  synthetic tests, which cannot tell you that the codes it recodes are the codes
  your deposit uses. The selection bar counts them too, so it is visible before
  the download rather than only after.

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

**Currently unavailable, and the local route above is the supported one.**
GitHub Pages does not serve from a private account, so while the repository
is private the workflow below cannot publish. It is kept intact rather than
deleted: nothing about it has been made wrong by the account change, and it
works again the moment the repository is public. Note that the assistant is
local-only by construction — it talks to Ollama on `localhost` — so a
published copy of this site would carry the drawer but never connect.


`.github/workflows/pages.yml` runs `build_site.py` and uploads this directory
on every push to `main` touching `web/`, `registry/`, or `bcs70/`. The site is
live at <https://cls-data.github.io/bcs70-core/>.

**`data/` is generated by that workflow, not committed.** This is the single
most important thing about the setup, and it exists because the alternative
failed in practice. When `data/` was committed, publishing correct data
depended on whoever added a variable also remembering to run `build_site.py`
and commit the result. Nothing enforced it: the freshness check lived in this
workflow, which only triggered on `web/**`, so a change to `registry/` — the
exact change that invalidates the data — could never trigger the check that
would have caught it. Building at publish time removes the failure mode
instead of guarding against it, and drops ~88 files of generated JSON out of
every variable PR's diff.

Two consequences worth knowing:

- **The published site is built from the commit being published**, so it can
  never disagree with that commit's `registry/` and `bcs70/`. There is no
  "stale data" state to detect, and no rebuild step for contributors to forget.
- **`registry/**` and `bcs70/**` are in the trigger paths deliberately.** They
  are the workflow's real inputs; leaving them out is what made merges publish
  nothing.

### Source must be set to GitHub Actions

In **Settings → Pages → Source**, this must be **GitHub Actions**, not a
branch. With a branch selected, `actions/configure-pages` fails, `upload` and
`deploy` are skipped, and the run goes red without publishing — while the old
branch-served copy stays up, so the site looks fine and is silently frozen.
That is precisely what happened between the merge of PR #16 and this change.

### Two other things to know

- **This repository is public, and so is the site.** The published data
  dictionaries — variable names, labels, value labels, missing-value codes —
  are readable by anyone. No row of study data is ever included (see above),
  but the metadata's licensing is a decision to make deliberately rather than
  by default.
- **`data/` is ~21 MB**, most of it the per-file dictionaries, which are
  fetched lazily and only when a variable is opened. The initial load is the
  1.9 MB search index (about 350 KB gzipped) plus the manifest.
