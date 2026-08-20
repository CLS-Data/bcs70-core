/* The study's time axis, across the top of every view.

   Drawing only. The click that filters to one wave is wired by the metadata
   view, because that is what it acts on — and because a spine reaching back
   into the search would make these two modules import each other. */

import { $ } from "./dom.js";
import { esc, state } from "./state.js";

/* ── Spine ───────────────────────────────────────────────────────────── */
/* Counts per wave for whatever is currently on screen. Absence is drawn,
   not omitted — a wave with no matches is the useful signal. */

function spineCounts() {
  const n = state.manifest.waves.length;
  const counts = new Array(n).fill(0);
  if (state.view === "derived" && state.derivedSelected) {
    // Coverage of the selected variable's family across waves.
    const fam = state.derivedSelected.family;
    state.derived.filter((d) => d.family === fam).forEach((d) => {
      (d.source_files || []).forEach((name) => {
        const f = state.manifest.files.find((x) => x.name === name);
        if (f) counts[state.manifest.waves.indexOf(f.wave)] += 1;
      });
    });
    return { counts, title: `Coverage · ${fam}`,
             note: `${state.dataset.wave.plural} this family draws on` };
  }
  state.matches.forEach((row) => { counts[row[3]] += 1; });
  const note = state.query || state.fileFilter !== null
    ? `${state.matches.length.toLocaleString()} matching variables`
    : "all variables";
  return { counts, title: `Matches by ${state.dataset.wave.term}`, note };
}

export function renderSpine() {
  const { counts, title, note } = spineCounts();
  const max = Math.max(1, ...counts);
  $("#spine-title").textContent = title;
  $("#spine-note").textContent = note;

  $("#spine-track").innerHTML = state.manifest.waves.map((wave, i) => {
    const n = counts[i];
    const pct = n ? Math.max(6, Math.round((n / max) * 100)) : 0;
    const on = state.waveFilter === i;
    return `<li>
      <button class="node${n ? "" : " is-empty"}" data-wave="${i}"
              aria-pressed="${on}"
              title="${esc(wave)} — ${n.toLocaleString()} ${n === 1 ? "variable" : "variables"}">
        <span class="node-bar"><span class="node-fill" style="height:${pct}%"></span></span>
        <span class="node-age">${esc(wave)}</span>
        <span class="node-n">${n ? n.toLocaleString() : "—"}</span>
      </button></li>`;
  }).join("");
}
