/* Collecting candidates while browsing, and the form that becomes an issue.

   Nothing is submitted from here: the draft composes a URL against the
   repository's issue template, and the researcher reviews it on GitHub. */

import { $, $$ } from "./dom.js";
import { capitalise, categories, dragAttr, esc, state, storeKey } from "./state.js";

/* ── Scratchpad ──────────────────────────────────────────────────────── */

export function addToBasket(item) {
  if (state.basket.some((b) => b.name === item.name && b.file === item.file)) return;
  state.basket.push(item);
  saveDraft();
  renderBasket();
}

export function renderBasket() {
  const tally = $("#scratch-tally");
  tally.textContent = state.basket.length;
  tally.hidden = state.basket.length === 0;

  $("#basket-empty").hidden = state.basket.length > 0;
  $("#basket").innerHTML = state.basket.map((b, i) => `
    <li><div class="row" style="cursor:grab;display:flex;align-items:flex-start;gap:8px"
        draggable="true" data-drag="${dragAttr(b)}">
      <div style="flex:1;min-width:0">
        <span class="row-top">
          <span class="row-name">${esc(b.name)}</span>
          <span class="row-wave">${esc(b.wave)}</span>
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
  const wavesField = $("#f-waves");
  const sourcesField = $("#f-sources");

  // An empty basket clears the untouched fields rather than leaving them.
  // Returning early here meant removing the last candidate left its variables
  // sitting in the form — and those fields go straight into the issue URL.
  const waves = [...new Set(state.basket.map((b) => b.wave))]
    .sort((a, b) => state.manifest.waves.indexOf(a) - state.manifest.waves.indexOf(b));
  if (!wavesField.dataset.touched) wavesField.value = waves.join(", ");

  if (!sourcesField.dataset.touched) {
    sourcesField.value = state.basket
      .map((b) => `${b.name} — ${b.label || "no label"} (${b.file}, ${b.wave})`)
      .join("\n");
  }
  saveDraft();
}

export function buildCategorySelect() {
  $("#f-category").innerHTML =
    `<option value="">Choose one…</option>` +
    categories().map((c) => `<option value="${esc(c.label)}">${esc(c.label)}</option>`).join("");
}

function draftValues() {
  return {
    name: $("#f-name").value.trim(),
    waves: $("#f-waves").value.trim(),
    category: $("#f-category").value,
    description: $("#f-description").value.trim(),
    sources: $("#f-sources").value.trim(),
    notes: $("#f-notes").value.trim(),
  };
}

/* The one place a request becomes a URL, shared with the assistant drawer.
   Field ids come from the config rather than being spelled here, so renaming
   one in the issue template is a one-line change in dataset.toml. */
export function issueUrl(values) {
  const { repo, template, titlePrefix, fields } = state.dataset.issue;
  const params = new URLSearchParams(template ? { template } : {});
  if (values.name) {
    params.set("title", `${titlePrefix}${values.name}`);
    params.set(fields.name, values.name);
  }
  const optional = [
    [fields.waves, values.waves], [fields.category, values.category],
    [fields.description, values.description], [fields.sources, values.sources],
    [fields.notes, values.notes],
  ];
  for (const [key, value] of optional) if (value) params.set(key, value);
  return `https://github.com/${repo}/issues/new?${params}`;
}

/* Which fields an issue cannot be filed without, from the config — the
   assistant's draft panel gates on the same list. */
export const requiredFields = () =>
  state.dataset?.issue?.required || ["name", "waves", "category", "description"];

/* The field's own label, so a message about what is missing uses the word on
   screen — "sweeps", not "waves" — whatever the dataset calls it. */
const fieldName = (key) =>
  key === "waves" ? state.dataset.wave.plural : key;

function missingFields(values) {
  return requiredFields().filter((k) => !String(values[k] || "").trim());
}

function refreshSubmit() {
  const v = draftValues();
  const missing = missingFields(v);
  const btn = $("#submit");
  btn.href = missing.length ? "#" : issueUrl(v);
  btn.setAttribute("aria-disabled", String(missing.length > 0));
  btn.title = missing.length
    ? `Fill in ${missing.map(fieldName).join(", ")} first`
    : "";
  saveDraft();
}

function saveDraft() {
  try {
    localStorage.setItem(storeKey("draft"), JSON.stringify({
      basket: state.basket, fields: draftValues(),
    }));
  } catch { /* private browsing, or storage full — the draft just won't persist */ }
}

export function restoreDraft() {
  let saved;
  try { saved = JSON.parse(localStorage.getItem(storeKey("draft")) || "null"); } catch { return; }
  if (!saved) return;
  state.basket = saved.basket || [];
  const f = saved.fields || {};
  const set = (sel, val) => { if (val) { $(sel).value = val; $(sel).dataset.touched = "1"; } };
  queueMicrotask(() => {
    set("#f-name", f.name); set("#f-waves", f.waves);
    if (f.category) $("#f-category").value = f.category;
    set("#f-description", f.description); set("#f-sources", f.sources); set("#f-notes", f.notes);
    refreshSubmit();
  });
}

let sayTimer;
function say(msg) {
  const el = $("#draft-status");
  el.textContent = msg;
  clearTimeout(sayTimer);
  sayTimer = setTimeout(() => { el.textContent = ""; }, 4000);
}

/* Fill the scratchpad form from outside — how the assistant hands a
   finished draft back to the plain form, so both routes to an issue end at
   the same place and the same review step. */
export function fillDraft(fields) {
  const map = {
    name: "#f-name", waves: "#f-waves", description: "#f-description",
    sources: "#f-sources", notes: "#f-notes",
  };
  for (const [key, sel] of Object.entries(map)) {
    if (!fields[key]) continue;
    $(sel).value = fields[key];
    $(sel).dataset.touched = "1";
  }
  if (fields.category) $("#f-category").value = fields.category;
  refreshSubmit();
}

export function wire() {
  ["#f-name", "#f-waves", "#f-category", "#f-description", "#f-sources", "#f-notes"]
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
      `${capitalise(state.dataset.wave.plural)} involved: ${v.waves || "—"}`,
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
    ["#f-name", "#f-waves", "#f-description", "#f-sources", "#f-notes"]
      .forEach((s) => { $(s).value = ""; delete $(s).dataset.touched; });
    $("#f-category").value = "";
    saveDraft(); renderBasket(); refreshSubmit();
    say("Draft cleared.");
  });

  refreshSubmit();
}
