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
                  Tab labels are "Raw variables" / "Research ready" / "R bundle";
                  the data-view keys stay metadata/derived/basket.
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

**Research ready** — the harmonised variables, filterable by **category**. Each shows
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

Drag variables from either list onto the **R bundle** tab, or use the `＋`
beside any row — which becomes a `✓`, and clicking that takes it back out. In
**Research ready**, a concept measured at several waves is one item with its
variables nested under it — a header carrying a control for all of them and a
fold, and rows showing only what distinguishes each from its siblings (`10y`,
`father_0y`). A variable with no siblings is just a row. Both the count and the
control act on what is on screen, so a search narrows them.

The bundle's list pane is what you picked up; its detail pane is the output
CSV's columns, which is where a name collision becomes visible.

What comes out is an RStudio project, not a folder of scripts:

```
<key>-variables-<date>/
  <key>-variables-<date>.Rproj   open this — it sets the working directory
  .Rprofile                      prints what to do; opens README in RStudio
  run.R                          the one file to run: checks, then runs
  data/README.md                 the empty folder the deposits can go in
  README.md
  R/runner.R                     \  the pipeline, verbatim
  R/lib/{dataset,io,utils,discovery}.R  /
  R/variables/<category>/<family>/<id>.R    research ready — copied verbatim
  R/variables/other/raw_<file>/<column>.R   raw — generated from a template
```

Base R, no packages, no checkout. Open the `.Rproj`, either drop the deposits
into `data/` or set `DATA_DIR` at the top of `run.R`, and run it.

Four things about this are deliberate.

**The R is shipped verbatim, never regenerated.** A bundle-specific runner
would be a second implementation of the join, the identifier cleaning and the
duplicate resolution, and the day it drifted the researcher's numbers would
quietly stop matching this repository's.

**A raw variable is a variable script whose `derive()` is the identity.** There
is nothing to copy for a deposited column, so `bundle.js` writes one from
`templates/passthrough.R` — and writes nothing else. It declares `source_files`
and `source_vars` like any other script, so the rule above survives: no second
implementation of anything, only a second kind of leaf.

**`run.R` checks before it reads.** The working directory, the data root and
the files it needs, all before a deposit is opened, each failure saying what to
do. It reuses the runner's own discovery to do it — `R/runner.R` guards its
invocation with `sys.nframe() == 0L`, so sourcing it defines `run_all()`
without starting a run.

**One variable never denies you the others.** `run_all()` isolates failure per
variable: an invalid script, or one whose deposit lacks a column it declares,
is skipped rather than aborting the batch. Every failure is reported, the
output is written with whatever succeeded and named as partial, and the run
exits non-zero — a researcher gets their other twenty-nine columns and CI still
fails.

### Naming a raw column

A research-ready variable's output name is its `spec$id` and is fixed: renaming
it would mean editing a script tested under that name. A raw column has no such
claim, so you choose — defaulting to the variable's own name, qualified by wave
only when that would collide. Two deposits both calling something `sex` is the
normal case, and `runner.R` joins on column name, so a bundle with a duplicate
or unusable name cannot be downloaded until it is fixed. The identifier is
reserved too: a column renamed onto it would overwrite the join key.

A spec must never declare the identifier in `source_vars` either — it is the
key, not data. `R/lib/discovery.R` rejects it by name, because the two
spellings fail differently and one of them fails silently.

### Where variable requests went

This view used to be a request-drafting form. Collecting variables and asking
for one to be derived looked like the same gesture and are not: one ends in a
zip you run this afternoon, the other in an issue someone works on for a week.
Requests are written in the assistant's draft panel, which checks every name
against the index before showing it. The bundle view keeps one plain link to
the issue template, so the route survives without the `assistant` extra.

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
been made wrong — it publishes again as soon as the repository is public.

**The assistant does not work on Pages, and cannot without being rewritten.**
Everything it does goes through `/api` — `/api/health` at start-up, then
`/api/interview`, `/api/chat`, `/api/models`. Pages serves files and has no
`/api`, so the health check fails and the drawer disables itself with a message
saying to start `web/server.py`. Everything else — search, the derived list,
the R bundle, the download — is static JSON and works exactly as it does
locally.

The reason is not that Ollama is on `localhost`. It is that the browser never
talks to Ollama at all: the model call, the LangGraph interview, the tools and
the BM25 retrieval are all Python on the server, and the browser only ever
posts a message and reads events. Making the assistant work on a static deploy
would mean reimplementing that half in the browser — a second implementation of
the interview and the retrieval, in another language. It has not been done, and
the cost is the reason.

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
