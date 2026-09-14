/* The harmonised variables: the list, the category facet, and adding them to
   the R bundle.

   What goes in the bundle lives in basket.js and is independent of the filters,
   so narrowing to a category to add two more does not silently drop what was
   already collected. */

import { $, $$ } from "./dom.js";
import { categories, categoryName, dragAttr, esc, state } from "./state.js";
import { renderSpine } from "./spine.js";
import { switchView } from "./views.js";
import { runSearch } from "./metadata.js";
import * as basket from "./basket.js";
const { addButton } = basket;

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
      `<li><p class="basket-empty">No research-ready variables in the registry yet.
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
    // dropping a raw variable, so the payload says which it is. The same
    // payload is what the bundle dock reads, which is why one shape serves
    // two drop targets.
    const drag = dragAttr({
      kind: "derived", name: d.id, label: d.label,
      file: d.file, wave: d.family,
    });
    // The add control sits beside the row rather than inside it: a button
    // cannot legally contain another button. It does exactly what dragging
    // the row does, and exists so the bundle is reachable from the keyboard.
    // The open-row marker goes on the <li> so it runs down the whole line.
    return head + `<li class="pickable${cur}">
      ${addButton("derived", d.id, basket.inBundle("derived", d.id), d.id)}
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

/* ── Adding variables to the bundle ──────────────────────────────────────

   The bundle itself is basket.js; this view only feeds it. "Add all" therefore
   says how many it will add and applies to what is on screen rather than to
   the whole registry. */

/* The line under the filters, and the state of every ＋ on screen. Called by
   basket.js whenever the bundle changes, so the two stay in step without this
   view having to watch for it. */
export function renderPicked() {
  const inBundle = state.derived.filter((d) => basket.inBundle("derived", d.id));
  const n = inBundle.length;
  const missing = visibleDerived().filter((d) => !basket.inBundle("derived", d.id)).length;
  const drafts = inBundle.filter((d) => d.status !== "verified").length;

  $("#derived-picked").innerHTML = n
    ? `<strong>${n}</strong> in the bundle${drafts
        ? ` · <span class="picked-warn">${drafts} unverified</span>` : ""}`
    : "None in the bundle";

  const all = $("#pick-all");
  all.hidden = missing === 0;
  all.textContent = `Add all ${missing}`;
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
      <button class="btn ${basket.inBundle("derived", d.id) ? "" : "btn-primary"}" id="pick-this">
        ${basket.inBundle("derived", d.id) ? "Remove from the R bundle" : "Add to the R bundle"}
      </button>
      <a class="btn" href="${repoUrl}/blob/main/${esc(d.file)}" target="_blank" rel="noopener">View on GitHub</a>
    </div>`;

  // Redrawn afterwards, like the metadata view's equivalent: the bundle's own
  // change hook refreshes the two lists but not this pane, so without it the
  // button still reads "Add" after adding - and a second click silently
  // removes what you just added.
  $("#pick-this").addEventListener("click", () => {
    if (basket.inBundle("derived", d.id)) basket.removeAt(`derived:${d.id}`);
    else basket.accept({ kind: "derived", name: d.id });
    showDerived(d);
  });

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

  // The ＋ and the row are siblings, so one listener can serve both: the ＋
  // is checked first because it is the more specific target.
  $("#derived-list").addEventListener("click", (e) => {
    const add = e.target.closest("[data-add-id]");
    if (add) { basket.accept({ kind: "derived", name: add.dataset.addId }); return; }
    const btn = e.target.closest("[data-id]");
    if (btn) showDerived(state.derived.find((d) => d.id === btn.dataset.id));
  });

  $("#pick-all").addEventListener("click", () => {
    visibleDerived().forEach((d) => basket.addDerived(d.id));
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
}
