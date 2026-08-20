/* Which of the three views is on screen.

   Its own module rather than part of the wiring: the metadata and derived
   views each switch to the other, and if this lived with the wiring they
   would have to import the module that imports them. */

import { $$ } from "./dom.js";
import { state } from "./state.js";
import { renderSpine } from "./spine.js";

/* ── Views, wiring ───────────────────────────────────────────────────── */

export function switchView(name) {
  state.view = name;
  $$(".view-tab").forEach((t) => {
    const on = t.dataset.view === name;
    t.classList.toggle("is-current", on);
    if (on) t.setAttribute("aria-current", "page"); else t.removeAttribute("aria-current");
  });
  $$(".view").forEach((v) => v.classList.toggle("is-current", v.dataset.view === name));
  renderSpine();
}
