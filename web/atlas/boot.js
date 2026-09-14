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

/* ── Resizing the list column ─────────────────────────────────────────

   One width for all three views, because the list column means the same thing
   in each and a width set while reading raw variables should survive a switch
   to research ready. Stored per dataset, like the theme.

   Dragged with pointer events rather than mouse ones, so a trackpad, a touch
   screen and a pen all work; keyboard-resizable too, because a separator that
   only a mouse can move is a separator half the users cannot reach. */
const RAIL_MIN = 260;
const RAIL_DEFAULT = 400;      // must match --rail in styles.css
const railMax = () => Math.max(RAIL_MIN, Math.round(window.innerWidth * 0.7));

function setRail(px, remember = true) {
  const w = Math.min(railMax(), Math.max(RAIL_MIN, Math.round(px)));
  document.documentElement.style.setProperty("--rail", `${w}px`);
  $$(".grip").forEach((g) => g.setAttribute("aria-valuenow", String(w)));
  if (!remember) return;
  try { localStorage.setItem(storeKey("rail"), `${w}px`); } catch { /* fine */ }
}

function wireGrips() {
  try {
    const saved = localStorage.getItem(storeKey("rail"));
    if (saved) setRail(parseInt(saved, 10) || RAIL_DEFAULT, false);
  } catch { /* private browsing — the default width is fine */ }

  $$(".grip").forEach((grip) => {
    grip.setAttribute("aria-valuemin", String(RAIL_MIN));

    grip.addEventListener("pointerdown", (e) => {
      // Captured so the drag keeps tracking once the pointer leaves the 7px
      // grip, which it does immediately.
      grip.setPointerCapture(e.pointerId);
      document.body.classList.add("is-resizing");
      e.preventDefault();
    });

    grip.addEventListener("pointermove", (e) => {
      if (!grip.hasPointerCapture(e.pointerId)) return;
      // Measured from the view's own left edge rather than the window's, so a
      // chat drawer or any future gutter cannot skew it.
      setRail(e.clientX - grip.parentElement.getBoundingClientRect().left, false);
    });

    const end = (e) => {
      if (!grip.hasPointerCapture(e.pointerId)) return;
      grip.releasePointerCapture(e.pointerId);
      document.body.classList.remove("is-resizing");
      setRail(parseInt(
        getComputedStyle(document.documentElement).getPropertyValue("--rail"), 10));
    };
    grip.addEventListener("pointerup", end);
    grip.addEventListener("pointercancel", end);

    // Back to the default, for anyone who has dragged themselves into a corner.
    grip.addEventListener("dblclick", () => setRail(RAIL_DEFAULT));

    grip.addEventListener("keydown", (e) => {
      const step = e.shiftKey ? 64 : 16;
      const now = parseInt(
        getComputedStyle(document.documentElement).getPropertyValue("--rail"), 10);
      if (e.key === "ArrowLeft") setRail(now - step);
      else if (e.key === "ArrowRight") setRail(now + step);
      else if (e.key === "Home") setRail(RAIL_DEFAULT);
      else return;
      e.preventDefault();
    });
  });

  // A window narrow enough to make the stored width absurd gets it clamped,
  // rather than a list column wider than the window.
  window.addEventListener("resize", () => {
    const now = parseInt(
      getComputedStyle(document.documentElement).getPropertyValue("--rail"), 10);
    if (now > railMax()) setRail(railMax());
  });
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

  wireGrips();

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
