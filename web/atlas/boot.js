/* Loading the data, naming the dataset, and starting the views.

   The only module that knows all the others exist. Everything below it
   imports downwards or sideways, never back up here. */

import { $, $$ } from "./dom.js";
import { categories, issueUrl, payload, requiredFields, state, storeKey } from "./state.js";
import { renderSpine } from "./spine.js";
import { switchView } from "./views.js";
import * as metadata from "./metadata.js";
import * as derived from "./derived.js";
import * as basket from "./basket.js";

const { runSearch, openVariable } = metadata;
const { renderDerivedList, openDerived } = derived;

/* ── Boot ────────────────────────────────────────────────────────────── */

async function boot() {
  try {
    const [manifest, vars, derived] = await Promise.all([
      fetch("data/manifest.json").then((r) => r.json()),
      fetch("data/variables.json").then((r) => r.json()),
      fetch("data/derived.json").then((r) => r.json()),
    ]);
    state.manifest = manifest;
    state.dataset = manifest.dataset;
    state.vars = vars;
    state.derived = derived;
  } catch (err) {
    document.body.innerHTML =
      '<p style="font-family:var(--mono);padding:40px;max-width:60ch">' +
      "Could not load the site data. Build it and serve it:<br><br>" +
      "<code>python3 web/build_site.py</code><br>" +
      "<code>python3 web/server.py</code><br><br>" +
      "then open <code>http://localhost:8000</code>." +
      "</p>";
    return false;
  }

  applyBranding();

  const c = state.manifest.counts;
  const waves = state.dataset.wave.plural;
  $("#foot-counts").textContent =
    `${c.variables.toLocaleString()} variables · ${c.files} files · ` +
    `${c.waves} ${waves} · ${c.derived} derived · built ${state.manifest.built}`;
  $("#foot-repo").href = `https://github.com/${state.dataset.issue.repo}`;

  basket.restoreBundle();
  wire();
  renderSpine();
  runSearch();
  renderDerivedList();
  basket.render();
}

/* The dataset's own name, everywhere the markup left a placeholder. */
function applyBranding() {
  const d = state.dataset;
  document.title = `${d.name} ${d.tagline}`;
  $(".mark-name").textContent = d.name;
  $(".mark-sub").textContent = d.tagline;
  $("#spine").setAttribute("aria-label", `Coverage by ${d.wave.term}`);
  const meta = document.querySelector('meta[name="description"]');
  if (meta && d.blurb) meta.setAttribute("content", d.blurb);
}

/* Each view wires the controls it owns; this wires what belongs to the page
   itself and starts the rest. A single wireUp() reaching into all three views
   was the last thing keeping them one file. */
function wire() {
  $$(".view-tab").forEach((t) =>
    t.addEventListener("click", () => switchView(t.dataset.view)));

  metadata.wire();
  derived.wire();
  basket.wire();

  // The bundle is fed from both lists and drawn in a third view, so a change
  // has to redraw all three. basket.js calls these rather than importing the
  // views, which would close a cycle — see the notes there.
  basket.onChange(() => {
    derived.renderPicked();
    if (state.view === "metadata") runSearch();
    else renderDerivedList();
  });
  basket.onFileOpened(runSearch);

  const theme = $("#theme");
  const stored = localStorage.getItem(storeKey("theme"));
  if (stored) document.documentElement.dataset.theme = stored;
  theme.addEventListener("click", () => {
    const now = document.documentElement.dataset.theme ||
      (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    const next = now === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    localStorage.setItem(storeKey("theme"), next);
  });
}

/* Exactly what `chat/` uses, and nothing else. A surface with unused members
   stops describing the contract and starts describing the file. */
window.Atlas = {
  state, categories, issueUrl, storeKey, payload, requiredFields,
  switchView, openVariable, openDerived,
  // The assistant's one write into the atlas: handing its pinned raw
  // variables over to the bundle. It used to hand a whole drafted issue to a
  // form that no longer exists.
  addToBundle: basket.accept,
};

/* The assistant is a separate module and may load before or after this
   finishes. Whichever lands second starts the drawer. */
boot().then((ok) => {
  if (ok === false) return;
  window.Atlas.ready = true;
  window.dispatchEvent(new Event("atlas:ready"));
});
