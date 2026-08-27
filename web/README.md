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
                  boot, state, dom, spine, views, metadata, derived, scratchpad
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
needs, all clickable back into the metadata. Tick any of them and **download
the R code** that produces them (below).

**Scratchpad** — collect candidates while browsing, describe what you want, and
open a prefilled GitHub issue. Nothing is submitted until you review it.

**Assistant** — the same destination, reached by conversation.
See [assistant/README.md](assistant/README.md).

The level filter reads `measurement_level`, not `variable_type`: the obvious
"type" field does not discriminate — 31,472 of 32,454 variables are `numeric`.
Both filters draw empty options too, for the reason the spine draws empty
waves: knowing a search has no scale variables is the answer. Counts are
tallied *before* that filter is applied, so each says what choosing it would
give, not what is already on screen.

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
  duplicate resolution — and the day it drifted, the researcher's numbers would
  quietly stop matching this repository's.
- **The zip is written in the browser**, so no server is involved. `bundle.js`
  writes the archive format itself rather than taking a dependency, and fetches
  the pipeline source only when someone actually downloads something.
- **The README names what is unverified.** A `draft` variable has passed
  synthetic tests, which cannot tell you its codes are the codes your deposit
  uses. The selection bar counts them before the download, not after.

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
