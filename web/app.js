/* ==========================================================================
   BCS70 Variable Atlas — static client, no dependencies.

   Reads the JSON that web/build_site.py emits. Everything is metadata:
   variable names, labels, value labels, missing-value codes, and the R
   source of each derived variable. No study data exists in this site.
   ========================================================================== */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const MAX_ROWS = 300;      // rendered at once; the count line reports the rest
const STORE_KEY = "bcs70-atlas-draft";

// The issue form's dropdown options, verbatim. These are the strings GitHub
// matches on when prefilling, so they must not be prettified.
const CATEGORIES = [
  ["Demographic", "demographic"],
  ["Socio-economic", "socio_economic"],
  ["Health", "health"],
  ["Education", "education"],
  ["Employment", "employment"],
  ["Family & relationships", "family_relationships"],
  ["Housing", "housing"],
  ["Behavioural / lifestyle", "behavioural_lifestyle"],
  ["Cognitive / ability", "cognitive_ability"],
  ["Other", "other"],
];

const LEVEL_UNRECORDED = -1;   // dictionary records no measurement level

const state = {
  manifest: null,
  vars: [],          // [name, label, fileIdx, sweepIdx, levelIdx]
  derived: [],
  dictCache: new Map(),
  query: "",
  sweepFilter: null, // sweep index, or null
  fileFilter: null,  // file index, or null
  levelFilter: null, // measurement level index, LEVEL_UNRECORDED, or null
  levelCounts: new Map(),
  matches: [],
  selected: null,
  derivedQuery: "",
  derivedCategory: null, // category slug, or null
  derivedSelected: null,
  basket: [],
  view: "metadata",
};

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// NOMINAL -> Nominal. The dictionaries shout; the interface doesn't need to.
const levelName = (i) => i === LEVEL_UNRECORDED
  ? "Unrecorded"
  : ((state.manifest.levels || [])[i] || "?").replace(/^(.)(.*)$/,
      (_, a, b) => a + b.toLowerCase());

const categoryName = (slug) =>
  (CATEGORIES.find(([, s]) => s === slug) || [slug])[0];

function highlight(text, term) {
  const t = String(text ?? "");
  if (!term) return esc(t);
  const i = t.toLowerCase().indexOf(term.toLowerCase());
  if (i < 0) return esc(t);
  return esc(t.slice(0, i)) + "<mark>" + esc(t.slice(i, i + term.length)) +
         "</mark>" + esc(t.slice(i + term.length));
}

/* ── Boot ────────────────────────────────────────────────────────────── */

async function boot() {
  try {
    const [manifest, vars, derived] = await Promise.all([
      fetch("data/manifest.json").then((r) => r.json()),
      fetch("data/variables.json").then((r) => r.json()),
      fetch("data/derived.json").then((r) => r.json()),
    ]);
    state.manifest = manifest;
    state.vars = vars;
    state.derived = derived;
  } catch (err) {
    document.body.innerHTML =
      '<p style="font-family:var(--mono);padding:40px;max-width:60ch">' +
      "Could not load the site data. This page reads JSON over HTTP, so it " +
      "cannot run from a <code>file://</code> path. Serve the directory " +
      "instead:<br><br><code>python3 -m http.server -d web</code><br><br>" +
      "then open <code>http://localhost:8000</code>." +
      "</p>";
    return;
  }

  const c = state.manifest.counts;
  $("#foot-counts").textContent =
    `${c.variables.toLocaleString()} variables · ${c.files} files · ` +
    `${c.sweeps} sweeps · ${c.derived} derived · built ${state.manifest.built}`;
  const repoUrl = `https://github.com/${state.manifest.repo}`;
  $("#foot-repo").href = repoUrl;

  restoreDraft();
  buildCategorySelect();
  wireUp();
  renderSpine();
  runSearch();
  renderDerivedList();
  renderBasket();
}

/* ── Spine ───────────────────────────────────────────────────────────── */
/* Counts per sweep for whatever is currently on screen. Absence is drawn,
   not omitted — a sweep with no matches is the useful signal. */

function spineCounts() {
  const n = state.manifest.sweeps.length;
  const counts = new Array(n).fill(0);
  if (state.view === "derived" && state.derivedSelected) {
    // Coverage of the selected variable's family across sweeps.
    const fam = state.derivedSelected.family;
    state.derived.filter((d) => d.family === fam).forEach((d) => {
      (d.source_files || []).forEach((name) => {
        const f = state.manifest.files.find((x) => x.name === name);
        if (f) counts[state.manifest.sweeps.indexOf(f.sweep)] += 1;
      });
    });
    return { counts, title: `Coverage · ${fam}`, note: "sweeps this family draws on" };
  }
  state.matches.forEach((row) => { counts[row[3]] += 1; });
  const note = state.query || state.fileFilter !== null
    ? `${state.matches.length.toLocaleString()} matching variables`
    : "all variables";
  return { counts, title: "Matches by sweep", note };
}

function renderSpine() {
  const { counts, title, note } = spineCounts();
  const max = Math.max(1, ...counts);
  $("#spine-title").textContent = title;
  $("#spine-note").textContent = note;

  $("#spine-track").innerHTML = state.manifest.sweeps.map((sweep, i) => {
    const n = counts[i];
    const pct = n ? Math.max(6, Math.round((n / max) * 100)) : 0;
    const on = state.sweepFilter === i;
    return `<li>
      <button class="node${n ? "" : " is-empty"}" data-sweep="${i}"
              aria-pressed="${on}"
              title="${esc(sweep)} — ${n.toLocaleString()} ${n === 1 ? "variable" : "variables"}">
        <span class="node-bar"><span class="node-fill" style="height:${pct}%"></span></span>
        <span class="node-age">${esc(sweep)}</span>
        <span class="node-n">${n ? n.toLocaleString() : "—"}</span>
      </button></li>`;
  }).join("");
}

/* ── Metadata search ─────────────────────────────────────────────────── */

function runSearch() {
  const q = state.query.trim().toLowerCase();
  const out = [];
  // Level counts are tallied BEFORE the level filter is applied, so each
  // facet shows what choosing it would give rather than what is on screen.
  const counts = new Map();
  for (const row of state.vars) {
    if (state.sweepFilter !== null && row[3] !== state.sweepFilter) continue;
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
   the same reason an empty sweep is drawn on the spine: knowing a search has
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
    return `<li><button class="row${cur}" data-i="${i}">
      <span class="row-top">
        <span class="row-name">${highlight(row[0], q)}</span>
        <span class="row-sweep">${esc(state.manifest.sweeps[row[3]])}</span>
      </span>
      <span class="row-label">${highlight(row[1] || "—", q)}</span>
      <span class="row-file">${esc(file ? file.name : "?")}</span>
    </button></li>`;
  }).join("");

  const more = $("#more");
  if (total > MAX_ROWS) {
    more.hidden = false;
    more.textContent = `Showing the first ${MAX_ROWS.toLocaleString()} of ${total.toLocaleString()}. Narrow the search or pick a sweep.`;
  } else {
    more.hidden = true;
  }
  $("#results").dataset.rows = JSON.stringify(shown.map((r) => state.matches.indexOf(r)));
}

function renderFilters() {
  const chips = [];
  if (state.sweepFilter !== null) {
    chips.push(`<button class="chip" data-clear="sweep">sweep ${esc(state.manifest.sweeps[state.sweepFilter])} ✕</button>`);
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
  const [name, label, fileIdx, sweepIdx] = row;
  const file = state.manifest.files[fileIdx];
  const sweep = state.manifest.sweeps[sweepIdx];
  const detail = $("#detail");

  detail.innerHTML = `<p class="empty">Loading ${esc(name)}…</p>`;
  let entry = null;
  try {
    const dict = await loadDict(file.slug);
    entry = dict.variables.find((v) => v.variable === name);
  } catch { /* fall through to the minimal view below */ }

  const inBasket = state.basket.some((b) => b.name === name && b.file === file.name);

  const values = entry && entry.values ? entry.values : null;
  const valueRows = values ? values.map((v) => {
    const num = parseFloat(v.value);
    const missing = !Number.isNaN(num) && num < 0;
    return `<tr class="${missing ? "is-missing" : ""}">
      <td class="val">${esc(v.value)}</td><td>${esc(v.label)}</td></tr>`;
  }).join("") : "";

  detail.innerHTML = `
    <div class="detail-head">
      <div class="detail-eyebrow">${esc(sweep)} · ${esc(file.name)}</div>
      <h1 class="detail-name">${esc(name)}</h1>
      <p class="detail-label">${esc(label || "No label recorded in the dictionary.")}</p>
    </div>

    ${file.inLookup === false ? `<div class="warn"><span>⚠</span><div>
      <strong>Not in the master lookup.</strong> This file has a data dictionary and
      a <code>.tab</code> on disk, but no row in <code>master_file_info_lookup.csv</code>,
      so <code>load_tab()</code> cannot resolve it. A variable script cannot use it
      until that row is added.</div></div>` : ""}

    <dl class="facts">
      <div class="fact"><dt>Sweep</dt><dd>${esc(sweep)}</dd></div>
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
      <button class="btn ${inBasket ? "" : "btn-primary"}" id="add-basket" ${inBasket ? "disabled" : ""}>
        ${inBasket ? "In scratchpad" : "Add to scratchpad"}
      </button>
      <button class="btn" id="filter-file">Show all in ${esc(file.name)}</button>
    </div>`;

  $("#add-basket")?.addEventListener("click", () => {
    addToBasket({ name, label, file: file.name, sweep });
    showVariable(row);
  });
  $("#filter-file")?.addEventListener("click", () => {
    state.fileFilter = fileIdx;
    state.sweepFilter = null;
    state.levelFilter = null;
    state.query = "";
    $("#q").value = "";
    runSearch();
  });
}

/* ── Derived variables ───────────────────────────────────────────────── */

function matchesDerivedQuery(d, q) {
  return !q || d.id.toLowerCase().includes(q) ||
    (d.label || "").toLowerCase().includes(q) ||
    (d.family || "").toLowerCase().includes(q);
}

/* Categories are the fixed list from the issue template, and all ten are
   drawn even where nothing has been harmonised yet — "no health variables
   exist" is the most useful thing this control can tell you. */
function renderCategoryFacets() {
  const q = state.derivedQuery.trim().toLowerCase();
  const counts = new Map();
  state.derived.filter((d) => matchesDerivedQuery(d, q))
    .forEach((d) => counts.set(d.category, (counts.get(d.category) || 0) + 1));

  $("#category-facets").innerHTML = CATEGORIES.map(([label, slug]) => {
    const n = counts.get(slug) || 0;
    const on = state.derivedCategory === slug;
    return `<button class="facet${on ? " is-on" : ""}${n ? "" : " is-empty"}"
              data-category="${esc(slug)}" aria-pressed="${on}" ${n || on ? "" : "disabled"}>
        ${esc(label)}<span class="facet-n">${n || "—"}</span>
      </button>`;
  }).join("");

  $("#clear-category").hidden = state.derivedCategory === null;
}

function renderDerivedList() {
  const q = state.derivedQuery.trim().toLowerCase();
  const list = state.derived.filter((d) => matchesDerivedQuery(d, q) &&
    (state.derivedCategory === null || d.category === state.derivedCategory));

  renderCategoryFacets();

  $("#derived-count").textContent = state.derived.length
    ? `${list.length} of ${state.derived.length}`
    : "none yet";

  if (!state.derived.length) {
    $("#derived-list").innerHTML =
      `<li><p class="basket-empty">No derived variables in the registry yet.
       Once a variable script is merged, it appears here with its source.</p></li>`;
    return;
  }

  if (!list.length) {
    $("#derived-list").innerHTML =
      `<li><p class="basket-empty">Nothing matches. ${state.derivedCategory !== null
        ? `No ${esc(categoryName(state.derivedCategory).toLowerCase())} variable matches this search.`
        : ""}</p></li>`;
    return;
  }

  let lastFamily = null;
  $("#derived-list").innerHTML = list.map((d) => {
    const head = d.family !== lastFamily
      ? `<li><p class="more" style="border-bottom:1px solid var(--rule);margin:0">
           ${esc(categoryName(d.category))} / <strong>${esc(d.family)}</strong></p></li>` : "";
    lastFamily = d.family;
    const cur = state.derivedSelected?.id === d.id ? " is-current" : "";
    return head + `<li><button class="row${cur}" data-id="${esc(d.id)}">
      <span class="row-top">
        <span class="row-name">${esc(d.id)}</span>
        <span class="row-sweep">${statusPill(d.status)}</span>
      </span>
      <span class="row-label">${esc(d.label)}</span>
    </button></li>`;
  }).join("");
}

function statusPill(status) {
  const cls = status === "verified" ? "pill-verified"
    : status === "ready_for_real_data_test" ? "pill-ready" : "pill-draft";
  return `<span class="pill ${cls}">${esc(String(status).replace(/_/g, " "))}</span>`;
}

function showDerived(d) {
  state.derivedSelected = d;
  renderDerivedList();
  renderSpine();

  const repoUrl = `https://github.com/${state.manifest.repo}`;
  const files = (d.source_files || []).map((name) => {
    const f = state.manifest.files.find((x) => x.name === name);
    return { name, file: f };
  });

  $("#derived-detail").innerHTML = `
    <div class="detail-head">
      <div class="detail-eyebrow">${esc(categoryName(d.category))} · ${esc(d.family)} · ${statusPill(d.status)}</div>
      <h1 class="detail-name">${esc(d.id)}</h1>
      <p class="detail-label">${esc(d.label)}</p>
    </div>

    ${d.status === "draft" ? `<div class="warn"><span>⚠</span><div>
      <strong>Draft.</strong> This script has only been checked against fabricated
      test data. It has not yet been run against the real study data, so its output
      is not yet trusted.</div></div>` : ""}

    <dl class="facts">
      <div class="fact"><dt>Issue</dt><dd>${d.github_issue
        ? `<a href="${repoUrl}/issues/${esc(d.github_issue)}" target="_blank" rel="noopener">#${esc(d.github_issue)}</a>`
        : "—"}</dd></div>
      <div class="fact"><dt>Author</dt><dd style="font-size:11px">${esc(d.author || "—")}</dd></div>
      <div class="fact"><dt>Created</dt><dd>${esc(d.created || "—")}</dd></div>
      <div class="fact"><dt>Script</dt><dd style="font-size:11px">${esc(d.file || "—")}</dd></div>
    </dl>

    <h2 class="section-title">Comes from</h2>
    <ul class="linklist">${files.map(({ name, file }) => `
      <li><button data-file="${esc(name)}">
        <span class="ll-name">${esc(name)}</span>
        <span class="ll-desc">${esc(file?.description || "")}</span>
        <span class="ll-meta">${esc(file ? file.sweep : "not in lookup")}</span>
      </button></li>`).join("")}
    </ul>

    <h2 class="section-title">Raw variables used</h2>
    <ul class="linklist">${(d.source_vars || []).map((v) => `
      <li><button data-var="${esc(v)}">
        <span class="ll-name">${esc(v)}</span>
        <span class="ll-meta">find in metadata →</span>
      </button></li>`).join("")}
    </ul>

    <h2 class="section-title">How it is derived</h2>
    <pre class="code">${esc(d.source || "Source not available.")}</pre>

    <div class="detail-actions">
      <a class="btn" href="${repoUrl}/blob/main/${esc(d.file)}" target="_blank" rel="noopener">View on GitHub</a>
    </div>`;

  $$("#derived-detail [data-file]").forEach((b) =>
    b.addEventListener("click", () => {
      const idx = state.manifest.files.findIndex((f) => f.name === b.dataset.file);
      if (idx < 0) return;
      switchView("metadata");
      state.fileFilter = idx; state.sweepFilter = null; state.levelFilter = null;
      state.query = "";
      $("#q").value = ""; runSearch();
    }));

  $$("#derived-detail [data-var]").forEach((b) =>
    b.addEventListener("click", () => {
      switchView("metadata");
      state.fileFilter = null; state.sweepFilter = null; state.levelFilter = null;
      state.query = b.dataset.var; $("#q").value = b.dataset.var;
      runSearch();
    }));
}

/* ── Scratchpad ──────────────────────────────────────────────────────── */

function addToBasket(item) {
  if (state.basket.some((b) => b.name === item.name && b.file === item.file)) return;
  state.basket.push(item);
  saveDraft();
  renderBasket();
}

function renderBasket() {
  const tally = $("#scratch-tally");
  tally.textContent = state.basket.length;
  tally.hidden = state.basket.length === 0;

  $("#basket-empty").hidden = state.basket.length > 0;
  $("#basket").innerHTML = state.basket.map((b, i) => `
    <li><div class="row" style="cursor:default;display:flex;align-items:flex-start;gap:8px">
      <div style="flex:1;min-width:0">
        <span class="row-top">
          <span class="row-name">${esc(b.name)}</span>
          <span class="row-sweep">${esc(b.sweep)}</span>
        </span>
        <span class="row-label">${esc(b.label || "—")}</span>
        <span class="row-file">${esc(b.file)}</span>
      </div>
      <button class="drop" data-drop="${i}" aria-label="Remove ${esc(b.name)}">✕</button>
    </div></li>`).join("");

  $$("#basket [data-drop]").forEach((b) => b.addEventListener("click", () => {
    state.basket.splice(Number(b.dataset.drop), 1);
    saveDraft(); renderBasket(); syncDerivedFields();
  }));

  syncDerivedFields();
}

// Sweeps and source variables are derived from the basket, but only while
// the user hasn't typed over them — their edit always wins.
function syncDerivedFields() {
  const sweepsField = $("#f-sweeps");
  const sourcesField = $("#f-sources");
  if (!state.basket.length) return;

  const sweeps = [...new Set(state.basket.map((b) => b.sweep))]
    .sort((a, b) => state.manifest.sweeps.indexOf(a) - state.manifest.sweeps.indexOf(b));
  if (!sweepsField.dataset.touched) sweepsField.value = sweeps.join(", ");

  if (!sourcesField.dataset.touched) {
    sourcesField.value = state.basket
      .map((b) => `${b.name} — ${b.label || "no label"} (${b.file}, ${b.sweep})`)
      .join("\n");
  }
  saveDraft();
}

function buildCategorySelect() {
  $("#f-category").innerHTML =
    `<option value="">Choose one…</option>` +
    CATEGORIES.map(([label]) => `<option value="${esc(label)}">${esc(label)}</option>`).join("");
}

function draftValues() {
  return {
    name: $("#f-name").value.trim(),
    sweeps: $("#f-sweeps").value.trim(),
    category: $("#f-category").value,
    description: $("#f-description").value.trim(),
    sources: $("#f-sources").value.trim(),
    notes: $("#f-notes").value.trim(),
  };
}

function issueUrl() {
  const v = draftValues();
  const p = new URLSearchParams({ template: "variable_request.yml" });
  if (v.name) { p.set("title", `[variable] ${v.name}`); p.set("variable-name", v.name); }
  if (v.sweeps) p.set("sweeps", v.sweeps);
  if (v.category) p.set("category", v.category);
  if (v.description) p.set("description", v.description);
  if (v.sources) p.set("source-vars", v.sources);
  if (v.notes) p.set("logic-notes", v.notes);
  return `https://github.com/${state.manifest.repo}/issues/new?${p}`;
}

function refreshSubmit() {
  const v = draftValues();
  const ready = v.name && v.sweeps && v.category && v.description;
  const btn = $("#submit");
  btn.href = ready ? issueUrl() : "#";
  btn.setAttribute("aria-disabled", String(!ready));
  btn.title = ready ? "" : "Fill in name, sweeps, category and description first";
  saveDraft();
}

function saveDraft() {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify({
      basket: state.basket, fields: draftValues(),
    }));
  } catch { /* private browsing, or storage full — the draft just won't persist */ }
}

function restoreDraft() {
  let saved;
  try { saved = JSON.parse(localStorage.getItem(STORE_KEY) || "null"); } catch { return; }
  if (!saved) return;
  state.basket = saved.basket || [];
  const f = saved.fields || {};
  const set = (sel, val) => { if (val) { $(sel).value = val; $(sel).dataset.touched = "1"; } };
  queueMicrotask(() => {
    set("#f-name", f.name); set("#f-sweeps", f.sweeps);
    if (f.category) $("#f-category").value = f.category;
    set("#f-description", f.description); set("#f-sources", f.sources); set("#f-notes", f.notes);
    refreshSubmit();
  });
}

/* ── Views, wiring ───────────────────────────────────────────────────── */

function switchView(name) {
  state.view = name;
  $$(".view-tab").forEach((t) => {
    const on = t.dataset.view === name;
    t.classList.toggle("is-current", on);
    if (on) t.setAttribute("aria-current", "page"); else t.removeAttribute("aria-current");
  });
  $$(".view").forEach((v) => v.classList.toggle("is-current", v.dataset.view === name));
  renderSpine();
}

function wireUp() {
  $$(".view-tab").forEach((t) => t.addEventListener("click", () => switchView(t.dataset.view)));

  let timer;
  $("#q").addEventListener("input", (e) => {
    clearTimeout(timer);
    timer = setTimeout(() => { state.query = e.target.value; runSearch(); }, 120);
  });

  $("#dq").addEventListener("input", (e) => {
    state.derivedQuery = e.target.value;
    renderDerivedList();
  });

  $("#results").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-i]");
    if (btn) showVariable(state.matches[Number(btn.dataset.i)]);
  });

  $("#derived-list").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-id]");
    if (btn) showDerived(state.derived.find((d) => d.id === btn.dataset.id));
  });

  $("#category-facets").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-category]");
    if (!btn) return;
    const slug = btn.dataset.category;
    state.derivedCategory = state.derivedCategory === slug ? null : slug;
    renderDerivedList();
  });

  $("#clear-category").addEventListener("click", () => {
    state.derivedCategory = null;
    renderDerivedList();
  });

  $("#spine-track").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-sweep]");
    if (!btn) return;
    const i = Number(btn.dataset.sweep);
    state.sweepFilter = state.sweepFilter === i ? null : i;
    if (state.view !== "metadata") switchView("metadata");
    runSearch();
  });

  $("#active-filters").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-clear]");
    if (!btn) return;
    if (btn.dataset.clear === "sweep") state.sweepFilter = null;
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
    state.sweepFilter = null; state.fileFilter = null; state.levelFilter = null;
    state.query = ""; $("#q").value = "";
    runSearch();
  });

  ["#f-name", "#f-sweeps", "#f-category", "#f-description", "#f-sources", "#f-notes"]
    .forEach((sel) => {
      const el = $(sel);
      el.addEventListener("input", () => { el.dataset.touched = "1"; refreshSubmit(); });
      el.addEventListener("change", () => { el.dataset.touched = "1"; refreshSubmit(); });
    });

  $("#draft").addEventListener("submit", (e) => e.preventDefault());

  $("#copy").addEventListener("click", async () => {
    const v = draftValues();
    const text = [
      `Proposed variable name: ${v.name || "—"}`,
      `Sweeps involved: ${v.sweeps || "—"}`,
      `Category: ${v.category || "—"}`,
      "", "What should this variable capture?", v.description || "—",
      "", "Known or candidate source variables:", v.sources || "—",
      "", "Coding / edge-case notes:", v.notes || "—",
    ].join("\n");
    try {
      await navigator.clipboard.writeText(text);
      say("Copied the draft to your clipboard.");
    } catch {
      say("Couldn't reach the clipboard — select the fields and copy manually.");
    }
  });

  $("#reset").addEventListener("click", () => {
    state.basket = [];
    ["#f-name", "#f-sweeps", "#f-description", "#f-sources", "#f-notes"]
      .forEach((s) => { $(s).value = ""; delete $(s).dataset.touched; });
    $("#f-category").value = "";
    saveDraft(); renderBasket(); refreshSubmit();
    say("Draft cleared.");
  });

  const theme = $("#theme");
  const stored = localStorage.getItem("bcs70-atlas-theme");
  if (stored) document.documentElement.dataset.theme = stored;
  theme.addEventListener("click", () => {
    const now = document.documentElement.dataset.theme ||
      (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    const next = now === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    localStorage.setItem("bcs70-atlas-theme", next);
  });

  refreshSubmit();
}

let sayTimer;
function say(msg) {
  const el = $("#draft-status");
  el.textContent = msg;
  clearTimeout(sayTimer);
  sayTimer = setTimeout(() => { el.textContent = ""; }, 4000);
}

boot();
