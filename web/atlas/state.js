/* Everything the views read and write, and the small helpers over it.

   Imports nothing, so it can never take part in a cycle — the same rule
   chat/state.js follows. Nothing here touches the DOM. */

export const MAX_ROWS = 300;      // rendered at once; the count line reports the rest
// Storage keys are namespaced per dataset: two atlases served from the same
// origin must not share a draft, a theme or a conversation.
export const storeKey = (name) => `atlas:${state.dataset?.key || "unknown"}:${name}`;

export const LEVEL_UNRECORDED = -1;   // dictionary records no measurement level

export const state = {
  manifest: null,
  dataset: null,     // manifest.dataset — see the note at the top of this file
  vars: [],          // [name, label, fileIdx, waveIdx, levelIdx]
  derived: [],
  dictCache: new Map(),
  query: "",
  waveFilter: null,  // wave index, or null
  fileFilter: null,  // file index, or null
  levelFilter: null, // measurement level index, LEVEL_UNRECORDED, or null
  levelCounts: new Map(),
  matches: [],
  selected: null,
  derivedQuery: "",
  derivedCategory: null, // category slug, or null
  derivedSelected: null,
  picked: new Set(),  // ids ticked for download; survives a reload
  pipeline: null,     // data/pipeline.json, fetched at first download
  basket: [],
  view: "metadata",
};

export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// NOMINAL -> Nominal. The dictionaries shout; the interface doesn't need to.
export const levelName = (i) => i === LEVEL_UNRECORDED
  ? "Unrecorded"
  : ((state.manifest.levels || [])[i] || "?").replace(/^(.)(.*)$/,
      (_, a, b) => a + b.toLowerCase());

export const capitalise = (s) => String(s).replace(/^./, (c) => c.toUpperCase());

// Reached from the assistant drawer as well as from here, so it tolerates a
// manifest that predates the dataset block rather than throwing "cannot read
// properties of undefined" from inside a conversation.
export const categories = () => state.dataset?.categories || [];
export const categoryName = (slug) =>
  (categories().find((c) => c.slug === slug) || { label: slug }).label;

/* What a dragged thing carries. The assistant drawer reads this off
   dataTransfer, so anything draggable anywhere in the site describes itself
   the same way and there is one shape to keep in step.

   Two kinds, and the difference is a real claim rather than a label: a raw
   variable is a candidate SOURCE for a derivation, a harmonised one is a
   PRECEDENT to follow. Only the first belongs in an issue's source list.

   Everything goes through here — the result rows, the derived list, the
   scratchpad, and the assistant's own search hits — because four hand-built
   copies of one shape is four places for it to drift. */
export function payload({ kind = "variable", name, label, file, wave }) {
  return {
    kind,
    name: name || "",
    label: label || "",
    file: file || "",
    wave: wave || "",
  };
}

/* The same, for a row of the variables index. */
export function rowPayload(row) {
  const file = state.manifest.files[row[2]];
  return payload({
    name: row[0],
    label: row[1],
    file: file ? file.name : "",
    wave: state.manifest.waves[row[3]],
  });
}

/* Serialised into a data-drag attribute, ready to be escaped into markup. */
export const dragAttr = (item) => esc(JSON.stringify(payload(item)));

export function highlight(text, term) {
  const t = String(text ?? "");
  if (!term) return esc(t);
  const i = t.toLowerCase().indexOf(term.toLowerCase());
  if (i < 0) return esc(t);
  return esc(t.slice(0, i)) + "<mark>" + esc(t.slice(i, i + term.length)) +
         "</mark>" + esc(t.slice(i + term.length));
}
