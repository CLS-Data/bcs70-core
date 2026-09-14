/* Everything the views read and write, and the small helpers over it.

   Imports nothing, so it can never take part in a cycle — the same rule
   chat/state.js follows. Nothing here touches the DOM. */

export const MAX_ROWS = 300;      // rendered at once; the count line reports the rest
// Storage keys are namespaced per dataset: two atlases served from the same
// origin must not share a draft, a theme or a conversation.
export const storeKey = (name) => `atlas:${state.dataset?.key || "unknown"}:${name}`;

export const LEVEL_UNRECORDED = -1;   // dictionary records no measurement level

/* The drag payload's media type. `chat/state.js` declares the same string for
   its own half of the site — the two must match, and they are cross-referenced
   rather than imported for the reason dom.js gives: the atlas and the
   assistant do not reach into each other. */
export const DRAG_MIME = "application/x-atlas-variable";

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
  // Families folded away in the derived list, by "<category>/<family>". Not
  // persisted: it is a reading position, not a preference, and a fold you set
  // last week is a variable you cannot find today.
  collapsedFamilies: new Set(),
  // What the R bundle will contain, in the order it was collected. Both
  // kinds live in one list because they end up in one joined output: a
  // harmonised variable is {kind:"derived", id}, a raw column is
  // {kind:"raw", name, label, file, wave, column}, where `column` is the
  // output name and the only part the researcher may edit.
  bundle: [],
  pipeline: null,     // data/pipeline.json, fetched at first download
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
   the basket, and the assistant's own search hits — because four hand-built
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

/* ── Filing a request ──────────────────────────────────────────────────

   The atlas no longer hosts a request form — the assistant's draft panel is
   the place a variable request is written, and it verifies every name against
   the index as it goes, which a plain form never did. What stays here is the
   one thing both routes need and neither should own: turning a set of values
   into a URL against the repository's issue template. It lives in this module
   because it is pure, reads only the config, and touches no DOM — so the
   basket can offer a one-click request without importing the assistant, and
   the assistant can build one without importing a view. */

/* Field ids come from the config rather than being spelled here, so renaming
   one in the issue template is a one-line change in dataset.toml. */
export function issueUrl(values) {
  // Tolerated rather than assumed, for the reason categories() gives: this is
  // reached from the assistant drawer and from a view that renders on every
  // change, and a manifest without an [issue] block should cost a link, not
  // the page.
  const issue = state.dataset?.issue;
  if (!issue?.repo) return null;
  const { repo, template, titlePrefix, fields } = issue;
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
   assistant's draft panel gates on this list. */
export const requiredFields = () =>
  state.dataset?.issue?.required || ["name", "waves", "category", "description"];
