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

One process serves the site and the API. **`server.py` is required, not
optional** — the search runs there, so a plain static file server gives you a
site whose search box cannot answer. Browsing still needs **no install at
all**; the assistant needs one:

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

This embeds every variable label with a local model so the search can match a
concept whose wording it does not share — *"How is your health generally"* for
**self-rated health**. It writes ~33 MB into the gitignored `data/`, so it is
never committed and CI never builds it.

Everything works without it: retrieval falls back to BM25 alone, `server.py`
says which mode it is in on its first line, and the drawer's switch is
disabled with the reason. Rebuild it after any `build_site.py` that changes
which variables exist — the index is positional, and a stale one is **refused
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

The box runs the **same retrieval the assistant's own lookups use** — one
engine, over `/api/search`. Three matchers, fused by rank:

| | finds | misses |
|---|---|---|
| literal | `b960`, `hlth` — a fragment of a half-remembered name | *cigarettes per day*, whose words are not in that order in any label |
| words (BM25) | *cigarettes per day*, *self-rated health* | `b960` — it indexes whole tokens, so half a code is not a term |
| meaning | *self-rated health* → "How is your health generally" | nothing, but it costs an embedding call |

Literal and words run on every keystroke, together in about four
milliseconds. **Meaning runs when you press Enter**, because it needs Ollama
and a fifth of a second; the line under the count says when it was used.
Filters are applied to the result in the browser, so changing one is instant
and costs no request.

That the three are complementary is measured, not assumed: `b960` returns 299
variables literally and none by words; *cigarettes per day* is the exact
reverse. Neither matcher is the better one, so the answer is not to choose.

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
- **The zip is written in the browser.** `bundle.js` writes the archive format
  itself rather than taking a dependency, and compresses through
  `CompressionStream` where the browser has it. The pipeline source is fetched
  from `data/pipeline.json` only when someone actually downloads something, so
  it stays out of the initial load.
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

## This is a local tool, not a published site

There is no static deployment, and the GitHub Pages workflow that used to
publish one has been removed. The site needs `web/server.py` behind it,
because the search runs there.

That is a deliberate trade rather than a regression. The atlas's search was
once a substring scan in the browser, which is what made a static host
viable — and it could not find *cigarettes per day*, because no label
contains that phrase. Moving to the shared engine means the search box
answers the same questions the assistant's lookups do; the cost is a Python
process, which anyone running this already needs for `build_site.py`. The
assistant was local-only by construction anyway, since it talks to Ollama on
`localhost`, so a published copy would always have carried a drawer that
never connected.

Two consequences worth knowing:

- **`data/` is built locally and is not committed.** After adding a variable
  or changing the metadata, run `python3 web/build_site.py` — nothing does it
  for you now. Rebuild the semantic index too if you use one; it is refused
  rather than used when it no longer lines up.
- **`data/` is ~21 MB**, most of it the per-file dictionaries, which are
  fetched lazily and only when a variable is opened. The initial load is the
  2.0 MB search index (about 350 KB gzipped) plus the manifest.
