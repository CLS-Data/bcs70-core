/* The harmonised variables: the list, the category facet, and packaging a
   selection as runnable R.

   The selection is by id and independent of the filters, so narrowing to a
   category to tick two more does not silently drop what was already chosen. */

import { $, $$ } from "./dom.js";
import { categories, categoryName, dragAttr, esc, state, storeKey } from "./state.js";
import { renderSpine } from "./spine.js";
import { switchView } from "./views.js";
import { runSearch } from "./metadata.js";

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

  $("#category-facets").innerHTML = categories().map(({ label, slug }) => {
    const n = counts.get(slug) || 0;
    const on = state.derivedCategory === slug;
    return `<button class="facet${on ? " is-on" : ""}${n ? "" : " is-empty"}"
              data-category="${esc(slug)}" aria-pressed="${on}" ${n || on ? "" : "disabled"}>
        ${esc(label)}<span class="facet-n">${n || "—"}</span>
      </button>`;
  }).join("");

  $("#clear-category").hidden = state.derivedCategory === null;
}

/* What the derived list is currently showing: the search box and the
   category facet, combined. Used by the list itself and by "Select all",
   which applies to what is on screen rather than to the whole registry. */
function visibleDerived() {
  const q = state.derivedQuery.trim().toLowerCase();
  return state.derived.filter((d) => matchesDerivedQuery(d, q) &&
    (state.derivedCategory === null || d.category === state.derivedCategory));
}

export function renderDerivedList() {
  const list = visibleDerived();

  renderCategoryFacets();

  $("#derived-count").textContent = state.derived.length
    ? `${list.length} of ${state.derived.length}`
    : "none yet";

  if (!state.derived.length) {
    $("#derived-list").innerHTML =
      `<li><p class="basket-empty">No derived variables in the registry yet.
       Once a variable script is merged, it appears here with its source.</p></li>`;
    renderPicked();
    return;
  }

  if (!list.length) {
    $("#derived-list").innerHTML =
      `<li><p class="basket-empty">Nothing matches. ${state.derivedCategory !== null
        ? `No ${esc(categoryName(state.derivedCategory).toLowerCase())} variable matches this search.`
        : ""}</p></li>`;
    renderPicked();
    return;
  }

  let lastFamily = null;
  $("#derived-list").innerHTML = list.map((d) => {
    const head = d.family !== lastFamily
      ? `<li><p class="more" style="border-bottom:1px solid var(--rule);margin:0">
           ${esc(categoryName(d.category))} / <strong>${esc(d.family)}</strong></p></li>` : "";
    lastFamily = d.family;
    const cur = state.derivedSelected?.id === d.id ? " is-current" : "";
    // Draggable too. Dropping a harmonised variable into the assistant is
    // how you say "follow this one's precedent" - a different claim from
    // dropping a raw variable, so the payload says which it is.
    const drag = dragAttr({
      kind: "derived", name: d.id, label: d.label,
      file: d.file, wave: d.family,
    });
    // A real checkbox beside the row rather than inside it: a button cannot
    // legally contain one, and the native control brings its own keyboard
    // handling and screen-reader semantics. The open-row marker goes on the
    // <li> rather than the button, so it runs down the whole line with the
    // checkbox inside it instead of starting after it.
    return head + `<li class="pickable${cur}">
      <input type="checkbox" class="pick" data-pick="${esc(d.id)}"
             ${state.picked.has(d.id) ? "checked" : ""}
             aria-label="Include ${esc(d.id)} in the download">
      <button class="row" data-id="${esc(d.id)}"
        draggable="true" data-drag="${drag}">
        <span class="row-top">
          <span class="row-name">${esc(d.id)}</span>
          <span class="row-wave">${statusPill(d.status)}</span>
        </span>
        <span class="row-label">${esc(d.label)}</span>
      </button></li>`;
  }).join("");

  renderPicked();
}

/* ── Selecting variables to download ─────────────────────────────────────

   The selection is by id and independent of the filters, so narrowing to a
   category to tick two more variables does not silently drop what was
   already chosen. "Select all" therefore says how many it will add and
   applies only to what is on screen. */

// Ids that no longer exist are dropped on load: a saved selection can outlive
// a variable being renamed, and a bundle cannot include what is not there.
export function restorePicked() {
  try {
    const saved = JSON.parse(localStorage.getItem(storeKey("picked")) || "[]");
    const known = new Set(state.derived.map((d) => d.id));
    state.picked = new Set(saved.filter((id) => known.has(id)));
  } catch {
    state.picked = new Set();
  }
}

function savePicked() {
  localStorage.setItem(storeKey("picked"), JSON.stringify([...state.picked]));
}

function togglePick(id, on) {
  if (on) state.picked.add(id);
  else state.picked.delete(id);
  savePicked();
  renderPicked();
  if (state.derivedSelected?.id === id) showDerived(state.derivedSelected);
}

function renderPicked() {
  const n = state.picked.size;
  const visible = visibleDerived();
  const unpicked = visible.filter((d) => !state.picked.has(d.id)).length;
  const drafts = state.derived.filter((d) =>
    state.picked.has(d.id) && d.status !== "verified").length;

  $("#picked-count").innerHTML = n
    ? `<strong>${n}</strong> selected${drafts
        ? ` · <span class="picked-warn">${drafts} unverified</span>` : ""}`
    : "Nothing selected";

  const all = $("#pick-all");
  all.hidden = unpicked === 0;
  all.textContent = `Select all ${unpicked}`;
  $("#pick-none").hidden = n === 0;
  $("#pick-download").disabled = n === 0;
  $("#pick-download").textContent = n
    ? `Download ${n} variable${n === 1 ? "" : "s"}`
    : "Download R code";

  $$("#derived-list [data-pick]").forEach((box) => {
    box.checked = state.picked.has(box.dataset.pick);
  });
}

function pickStatus(msg) {
  $("#picked-status").textContent = msg;
}

/* Build the archive in the browser. Everything it needs — each script's
   source, and the runner around it — is already static JSON, so this works on
   a deploy with no server behind it. */
async function downloadBundle() {
  const picked = state.derived.filter((d) => state.picked.has(d.id));
  if (!picked.length) return;

  const button = $("#pick-download");
  button.disabled = true;
  pickStatus("Packaging…");

  try {
    // Both fetched only now: the zip writer and ~17 KB of pipeline source are
    // dead weight for the majority who never download anything.
    // `../` because an import specifier resolves against THIS module, while
    // the fetches below resolve against the page. The two look alike and are
    // not: bundle.js sits beside index.html, not beside this file.
    const [{ build }, pipeline] = await Promise.all([
      import("../bundle.js"),
      state.pipeline ? Promise.resolve(state.pipeline) : loadPipeline(),
    ]);
    state.pipeline = pipeline;

    const { name, blob } = await build(picked, pipeline, {
      dataset: state.dataset,
      repo: state.manifest.repo,
      built: state.manifest.built,
    });

    const url = URL.createObjectURL(blob);
    const link = Object.assign(document.createElement("a"), { href: url, download: name });
    document.body.appendChild(link);
    link.click();
    link.remove();
    // Revoked late rather than immediately: some browsers have not finished
    // reading the blob when click() returns.
    setTimeout(() => URL.revokeObjectURL(url), 30000);

    pickStatus(`${name} — ${(blob.size / 1024).toFixed(0)} KB. Its README says how to run it.`);
  } catch (err) {
    console.error(err);
    pickStatus(`Could not build the download: ${err.message}`);
  } finally {
    button.disabled = state.picked.size === 0;
  }
}

async function loadPipeline() {
  const res = await fetch("data/pipeline.json");
  if (!res.ok) {
    throw new Error("pipeline.json is missing — rebuild with python3 web/build_site.py");
  }
  const pipeline = await res.json();
  if (!pipeline?.files || !Object.keys(pipeline.files).length) {
    throw new Error("pipeline.json has no runner in it — rebuild the site");
  }
  return pipeline;
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
        <span class="ll-meta">${esc(file ? file.wave : "not in lookup")}</span>
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
      <button class="btn ${state.picked.has(d.id) ? "" : "btn-primary"}" id="pick-this">
        ${state.picked.has(d.id) ? "Remove from download" : "Add to download"}
      </button>
      <a class="btn" href="${repoUrl}/blob/main/${esc(d.file)}" target="_blank" rel="noopener">View on GitHub</a>
    </div>`;

  $("#pick-this").addEventListener("click", () =>
    togglePick(d.id, !state.picked.has(d.id)));

  $$("#derived-detail [data-file]").forEach((b) =>
    b.addEventListener("click", () => {
      const idx = state.manifest.files.findIndex((f) => f.name === b.dataset.file);
      if (idx < 0) return;
      switchView("metadata");
      state.fileFilter = idx; state.waveFilter = null; state.levelFilter = null;
      state.query = "";
      $("#q").value = ""; runSearch();
    }));

  $$("#derived-detail [data-var]").forEach((b) =>
    b.addEventListener("click", () => {
      switchView("metadata");
      state.fileFilter = null; state.waveFilter = null; state.levelFilter = null;
      state.query = b.dataset.var; $("#q").value = b.dataset.var;
      runSearch();
    }));
}

/* The same, for something already harmonised. */
export function openDerived(id) {
  const entry = state.derived.find((d) => d.id === id);
  if (!entry) return false;
  switchView("derived");
  state.derivedCategory = null;
  state.derivedQuery = "";
  $("#dq").value = "";
  renderDerivedList();
  showDerived(entry);
  return true;
}

export function wire() {
  $("#dq").addEventListener("input", (e) => {
    state.derivedQuery = e.target.value;
    renderDerivedList();
  });

  $("#derived-list").addEventListener("click", (e) => {
    const btn = e.target.closest("[data-id]");
    if (btn) showDerived(state.derived.find((d) => d.id === btn.dataset.id));
  });

  // "change", not "click": a checkbox is also toggled by the keyboard, and
  // clicking its label counts too.
  $("#derived-list").addEventListener("change", (e) => {
    const box = e.target.closest("[data-pick]");
    if (box) togglePick(box.dataset.pick, box.checked);
  });

  $("#pick-all").addEventListener("click", () => {
    visibleDerived().forEach((d) => state.picked.add(d.id));
    savePicked();
    renderPicked();
    if (state.derivedSelected) showDerived(state.derivedSelected);
  });

  $("#pick-none").addEventListener("click", () => {
    state.picked.clear();
    savePicked();
    renderPicked();
    if (state.derivedSelected) showDerived(state.derivedSelected);
  });

  $("#pick-download").addEventListener("click", downloadBundle);

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
}
