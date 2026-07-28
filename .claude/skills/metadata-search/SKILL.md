---
name: metadata-search
description: Exhaustively search every sweep's data dictionaries, file descriptions, and the master lookup for variables/files relevant to a proposed derived variable, across all sweeps, before writing any derivation logic.
---

# Metadata search

Use this before scaffolding any new derived variable - the `new-variable` skill calls this first - and any time you need candidate source variables/files, not just in the sweep(s) named in a request. BCS70 derived variables frequently draw on more than one sweep (e.g. childhood social class might live in `5y`, `10y`, and `16y`), so never stop at the first sweep that seems relevant.

Before you start, check `DATA_KNOWLEDGE.md` at the repo root for entries
covering the concept, sweeps or files you're about to search. It records
things the dictionaries don't - notably which sweeps genuinely lack a
concept (so an empty result there is expected, not a search failure), and
raw variable names that collide across sweeps while measuring different
things.

## Steps

1. Pull 3-6 keyword variants from the issue/request: the exact concept name, synonyms, and related survey-instrument terms (e.g. for "childhood social class" also try "occupation", "socio-economic", "registrar general", "social class").
2. Run:

       Rscript scripts/search_metadata.R "<keyword1>" "<keyword2>" ...

3. Read the full output - it covers three independent sources, all worth checking:
   - `master_file_info_lookup.csv` description/file_name matches (which sweeps/files exist at all)
   - every `data_dictionaries/*.csv` (variable name, label, and value_labels_json - this is where actual candidate source variables show up)
   - `file_information` table descriptions (surfaces relevant PDFs/user guides worth opening for routing/derivation precedent)
4. If the first search pass looks thin, re-run with broader or more literal keyword variants before concluding nothing exists - don't settle for a single narrow query.
5. Note every sweep/file/variable that could plausibly feed the requested derived variable, even ones from sweeps not mentioned in the original request.
6. If a plausible candidate needs the PDF user guide to confirm coding (survey routing, derivation precedent, missing-value scheme not obvious from value_labels_json), open the relevant PDF under `bcs70/<sweep>/metadata/<study_number>/pdfs/`.
7. Only once this search is exhausted should `spec$source_files`/`spec$source_vars` be written - never guess at a variable name that didn't show up in the search.
8. If nothing plausible turns up anywhere, say so explicitly to the user rather than inventing a variable name or coding scheme.
