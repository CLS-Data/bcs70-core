# Variable atlas

A static site for finding raw BCS70 variables across 55 years of instruments,
reading what has been harmonised from them, and drafting a new variable
request.

Self-contained: no build tooling, no framework, no dependencies. Three source
files plus generated JSON.

```
web/
  index.html      structure
  styles.css      tokens and layout
  app.js          search, detail, scratchpad
  build_site.py   generates data/ from bcs70/ and registry/
  data/           generated - committed so GitHub Pages can serve it
```

## Running it locally

The page fetches JSON, so it cannot run from a `file://` path — serve the
directory:

```
python3 web/build_site.py        # regenerate data/ (only when metadata changes)
python3 -m http.server -d web    # then open http://localhost:8000
```

`build_site.py` uses the standard library only. It reads the metadata CSVs
under `bcs70/` and `registry/variables.json`, and writes `web/data/`. It never
opens a `.tab` file, so no row of study data can reach the site.

Rebuild after: adding a derived variable, changing a spec, or any change to
the metadata.

## What it does

**Metadata** — search 32,000+ variables by name or label. Names are terse and
inconsistent between sweeps, so searching the label usually beats guessing the
name. Open one to see its value labels, declared missing codes, position, and
the file and study it came from.

**Derived** — the harmonised variables. Each shows the R source that produces
it, the deposited files it draws on, and the raw variables it needs. Source
files and variables are clickable and jump back into the metadata view.

**Scratchpad** — collect candidate variables while browsing, describe what you
want, and open a prefilled GitHub issue against the repository's request
template. Nothing is submitted until you review it on GitHub. The draft
persists in `localStorage`.

## The sweep spine

The age axis across the top is the one element to understand. It always
reflects what is on screen: matches per sweep while searching, coverage across
sweeps while reading a derived family. Sweeps with nothing are drawn as dashed
voids rather than omitted, because absence is usually the thing you need to
know — housing tenure exists at 11 sweeps, BMI at 9, and two sweeps carry
neither. Click a sweep to filter to it.

## Two things the site deliberately surfaces

**Files missing from the master lookup.** Seven deposited `.tab` files have a
full data dictionary but no row in `master_file_info_lookup.csv`, so
`load_tab()` cannot resolve them and no variable script can use them. Their
variables are still searchable here, with a warning on the detail pane, rather
than being hidden.

**Duplicate file names.** `bcs70_age16_school_type` is deposited under both 16y
(study 3535) and 42y (study 7473). Everything here is keyed by sweep *and*
name, never name alone, so the two stay distinct.

## Deploying to GitHub Pages

`.github/workflows/pages.yml` publishes this directory on every push to `main`
that touches it. Enable it once in **Settings → Pages → Source → GitHub
Actions**.

Two things to check before you do:

- **This repository is private.** Publishing puts the data dictionaries on a
  public URL unless you are on a plan with private Pages. That is a decision
  about the metadata's licensing, not a technical one.
- **`data/` is ~21 MB**, most of it the per-file dictionaries, which are
  fetched lazily and only when a variable is opened. The initial load is the
  1.9 MB search index (about 350 KB gzipped) plus the manifest.
