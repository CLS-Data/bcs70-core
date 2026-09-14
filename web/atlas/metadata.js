/* Searching the dictionaries, and reading one variable.

   The search itself is a substring scan over the index the page already
   holds: it finds a fragment of a half-remembered name, which is what this
   corpus is mostly searched by, and it answers with no server behind it. */

import { $, $$ } from "./dom.js";
import {
  LEVEL_UNRECORDED, MAX_ROWS, capitalise, esc, highlight, levelName,
  payload, rowPayload, state,
} from "./state.js";
import { renderSpine } from "./spine.js";
import { switchView } from "./views.js";
import * as basket from "./basket.js";
const { addButton } = basket;

/* ── Metadata search ─────────────────────────────────────────────────── */

export function runSearch() {
  const q = state.query.trim().toLowerCase();
  const out = [];
  // Level counts are tallied BEFORE the level filter is applied, so each
  // facet shows what choosing it would give rather than what is on screen.
  const counts = new Map();
  for (const row of state.vars) {
    if (state.waveFilter !== null && row[3] !== state.waveFilter) continue;
    if (state.fileFilter !== null && row[2] !== state.fileFilter) continue;
    if (q && !row[0].toLowerCase().includes(q) && !row[1].toLowerCase().includes(q)) continue;
    const level = row[4] ?? LEVEL_UNRECORDED;
    counts.set(level, (counts.get(level) || 0) + 1);
    if (state.levelFilter !== null && level !== state.levelFilter) continue;
    out.push(row);
  }
  state.levelCounts = counts;
  state.matches = out;
  renderResults();
  renderSpine();
  renderLevelFacets();
  renderFilters();
}

/* Measurement level — the dictionaries' one discriminating type field.
   variable_type is not offered: 31,472 of 32,454 variables are "numeric", so
   filtering on it would be a no-op. Every level is drawn even at zero, for
   the same reason an empty wave is drawn on the spine: knowing a search has
   no scale variables in it is the answer, not a reason to hide the control. */
function renderLevelFacets() {
  const levels = state.manifest.levels || [];
  const group = $("#level-facets");
  if (!levels.length) { $("#level-group").hidden = true; return; }

  const keys = [...levels.keys(), LEVEL_UNRECORDED];
  group.innerHTML = keys.map((key) => {
    const n = state.levelCounts.get(key) || 0;
    const on = state.levelFilter === key;
    return `<button class="facet${on ? " is-on" : ""}${n ? "" : " is-empty"}"
              data-level="${key}" aria-pressed="${on}" ${n || on ? "" : "disabled"}>
        ${esc(levelName(key))}<span class="facet-n">${n ? n.toLocaleString() : "—"}</span>
      </button>`;
  }).join("");
}

function renderResults() {
  const q = state.query.trim();
  const total = state.matches.length;
  $("#result-count").textContent = total
    ? `${total.toLocaleString()} ${total === 1 ? "match" : "matches"}`
    : "no matches";

  const shown = state.matches.slice(0, MAX_ROWS);
  $("#results").innerHTML = shown.map((row, i) => {
    const file = state.manifest.files[row[2]];
    const cur = state.selected === row ? " is-current" : "";
    const wave = state.manifest.waves[row[3]];
    // A raw variable can be packaged as a passthrough column, so it gets the
    // same ＋ as a harmonised one.
    //
    // The identifier gets a ✓ instead — it is in every download already, and
    // there are 85 of these rows (one per file), so someone searching for it
    // will always find one. A blank space there reads as "not offered yet" and
    // sends them looking for the control; the tick says the job is done.
    //
    // A file with no lookup row gets nothing at all: that one really is
    // unavailable, and the detail pane explains why.
    const add = basket.isIdentifier(row[0])
      ? `<span class="add is-always" title="Always included in every download"
           aria-label="${esc(row[0])} is included in every download">✓</span>`
      : file && file.inLookup !== false
        ? addButton("raw", row[0], basket.inBundle("raw", row[0], file.name), row[0],
                    { file: file.name, wave, label: row[1] || "" })
        : "";
    return `<li class="pickable${cur}">${add}<button class="row" data-i="${i}" draggable="true"
      data-drag="${esc(JSON.stringify(rowPayload(row)))}">
      <span class="row-top">
        <span class="row-name">${highlight(row[0], q)}</span>
        <span class="row-wave">${esc(wave)}</span>
      </span>
      <span class="row-label">${highlight(row[1] || "—", q)}</span>
      <span class="row-file">${esc(file ? file.name : "?")}</span>
    </button></li>`;
  }).join("");

  const more = $("#more");
  if (total > MAX_ROWS) {
    more.hidden = false;
    more.textContent = `Showing the first ${MAX_ROWS.toLocaleString()} of ${total.toLocaleString()}. Narrow the search or pick a ${state.dataset.wave.term}.`;
  } else {
    more.hidden = true;
  }
}

function renderFilters() {
  const chips = [];
  if (state.waveFilter !== null) {
    chips.push(`<button class="chip" data-clear="wave">${
      esc(state.dataset.wave.term)} ${esc(state.manifest.waves[state.waveFilter])} ✕</button>`);
  }
  if (state.fileFilter !== null) {
    chips.push(`<button class="chip" data-clear="file">file ${esc(state.manifest.files[state.fileFilter].name)} ✕</button>`);
  }
  if (state.levelFilter !== null) {
    chips.push(`<button class="chip" data-clear="level">level ${esc(levelName(state.levelFilter).toLowerCase())} ✕</button>`);
  }
  $("#active-filters").innerHTML = chips.join("");
  $("#clear-filters").hidden = chips.length === 0;
}

async function loadDict(slug) {
  if (state.dictCache.has(slug)) return state.dictCache.get(slug);
  const data = await fetch(`data/dict/${slug}.json`).then((r) => r.json());
  state.dictCache.set(slug, data);
  return data;
}

async function showVariable(row) {
  state.selected = row;
  renderResults();
  const [name, label, fileIdx, waveIdx] = row;
  const file = state.manifest.files[fileIdx];
  const wave = state.manifest.waves[waveIdx];
  const detail = $("#detail");

  detail.innerHTML = `<p class="empty">Loading ${esc(name)}…</p>`;
  let entry = null;
  try {
    const dict = await loadDict(file.slug);
    entry = dict.variables.find((v) => v.variable === name);
  } catch { /* fall through to the minimal view below */ }

  const inBundle = basket.inBundle("raw", name, file.name);
  const isId = basket.isIdentifier(name);

  const values = entry && entry.values ? entry.values : null;
  const valueRows = values ? values.map((v) => {
    const num = parseFloat(v.value);
    const missing = !Number.isNaN(num) && num < 0;
    return `<tr class="${missing ? "is-missing" : ""}">
      <td class="val">${esc(v.value)}</td><td>${esc(v.label)}</td></tr>`;
  }).join("") : "";

  detail.innerHTML = `
    <div class="detail-head">
      <div class="detail-eyebrow">${esc(wave)} · ${esc(file.name)}</div>
      <h1 class="detail-name">${esc(name)}</h1>
      <p class="detail-label">${esc(label || "No label recorded in the dictionary.")}</p>
    </div>

    ${isId ? `<div class="note-box"><span>✓</span><div>
      <strong>Already in every download.</strong> This is the identifier: it is
      the first column of the output and every variable is joined on it, so it
      is supplied automatically. You do not need to add it — and it cannot be
      added on its own, because it is the key rather than a variable.</div></div>` : ""}

    ${file.inLookup === false ? `<div class="warn"><span>⚠</span><div>
      <strong>Not in the master lookup.</strong> This file has a data dictionary and
      a <code>.tab</code> on disk, but no row in <code>master_file_info_lookup.csv</code>,
      so <code>load_tab()</code> cannot resolve it. A variable script cannot use it
      until that row is added.</div></div>` : ""}

    <dl class="facts">
      <div class="fact"><dt>${esc(capitalise(state.dataset.wave.term))}</dt><dd>${esc(wave)}</dd></div>
      <div class="fact"><dt>File</dt><dd>${esc(file.name)}</dd></div>
      <div class="fact"><dt>Study</dt><dd>${esc(file.study || "—")}</dd></div>
      <div class="fact"><dt>Position</dt><dd>${esc(entry?.pos || "—")}</dd></div>
      <div class="fact"><dt>Type</dt><dd>${esc(entry?.type || "—")}</dd></div>
      <div class="fact"><dt>Measurement</dt><dd>${esc(entry?.measurement || "—")}</dd></div>
    </dl>

    ${entry?.missing ? `<h2 class="section-title">Declared missing values</h2>
      <p class="note"><code>${esc(entry.missing)}</code></p>` : ""}

    ${valueRows ? `<h2 class="section-title">Value labels</h2>
      <table class="codes">
        <thead><tr><th>Code</th><th>Meaning</th></tr></thead>
        <tbody>${valueRows}</tbody>
      </table>
      <p class="note" style="margin-top:10px;font-size:12px;color:var(--ink-3)">
        Negative codes are highlighted: across this corpus they are missing-value
        sentinels, and the schemes are not consistent between variables.</p>`
      : `<h2 class="section-title">Value labels</h2>
         <p class="note">None recorded. That does not guarantee the real file has no
         sentinel codes — some variables carry them undocumented.</p>`}

    ${file.description ? `<h2 class="section-title">About this file</h2>
      <p class="note">${esc(file.description)}</p>` : ""}

    <div class="detail-actions">
      ${file.inLookup === false || isId ? "" : `<button class="btn ${inBundle ? "" : "btn-primary"}" id="add-bundle">
        ${inBundle ? "Remove from the R bundle" : "Add to the R bundle"}
      </button>`}
      <button class="btn" id="filter-file">Show all in ${esc(file.name)}</button>
      <button class="btn" id="pin-chat">Pin to assistant</button>
    </div>`;

  $("#add-bundle")?.addEventListener("click", () => {
    if (basket.inBundle("raw", name, file.name)) basket.removeAt(`raw:${file.name}:${name}`);
    else basket.accept({ kind: "variable", name, label, file: file.name, wave });
    showVariable(row);
  });

  $("#pin-chat")?.addEventListener("click", () => {
    window.AtlasChat?.pin(payload({ name, label, file: file.name, wave }));
    window.AtlasChat?.open();
  });

  $("#filter-file")?.addEventListener("click", () => {
    state.fileFilter = fileIdx;
    state.waveFilter = null;
    state.levelFilter = null;
    state.query = "";
    $("#q").value = "";
    runSearch();
  });
}

/* Open one raw variable from outside the metadata view — the assistant's
   transcript links every name it surfaces through to here, so a lookup is a
   way into the atlas rather than a dead end. Filters are cleared and the
   search set to the name, so the variable is in the list beside its detail
   rather than selected out of nowhere. */
export function openVariable(name, wave) {
  const wanted = String(name || "").toLowerCase();
  const rows = state.vars.filter((r) => String(r[0]).toLowerCase() === wanted);
  const row = (wave && rows.find((r) => state.manifest.waves[r[3]] === wave)) || rows[0];
  if (!row) return false;

  switchView("metadata");
  state.waveFilter = null;
  state.fileFilter = null;
  state.levelFilter = null;
  state.query = row[0];
  $("#q").value = row[0];
  runSearch();
  showVariable(row);
  return true;
}

/* The controls that act on this view — including the spine, whose click is
   a filter on this list rather than anything the spine itself owns. */
export function wire() {
  let timer;
  $("#q").addEventListener("input", (e) => {
    clearTimeout(timer);
    timer = setTimeout(() => { state.query = e.target.value; runSearch(); }, 120);
  });

  // The ＋ and the row are siblings; the more specific target is checked first.
  $("#results").addEventListener("click", (e) => {
    const add = e.target.closest("[data-add-id]");
    if (add) {
      basket.accept({
        kind: "variable", name: add.dataset.addId, label: add.dataset.addLabel,
        file: add.dataset.addFile, wave: add.dataset.addWave,
      });
      return;
    }
    const btn = e.target.closest("[data-i]");
    if (btn) showVariable(state.matches[Number(btn.dataset.i)]);
  });

  $("#spine-track").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-wave]");
    if (!btn) return;
    const i = Number(btn.dataset.wave);
    state.waveFilter = state.waveFilter === i ? null : i;
    if (state.view !== "metadata") switchView("metadata");
    runSearch();
  });

  $("#active-filters").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-clear]");
    if (!btn) return;
    if (btn.dataset.clear === "wave") state.waveFilter = null;
    if (btn.dataset.clear === "file") state.fileFilter = null;
    if (btn.dataset.clear === "level") state.levelFilter = null;
    runSearch();
  });

  $("#level-facets").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-level]");
    if (!btn) return;
    const key = Number(btn.dataset.level);
    state.levelFilter = state.levelFilter === key ? null : key;
    runSearch();
  });

  $("#clear-filters").addEventListener("click", () => {
    state.waveFilter = null; state.fileFilter = null; state.levelFilter = null;
    state.query = ""; $("#q").value = "";
    runSearch();
  });
}
