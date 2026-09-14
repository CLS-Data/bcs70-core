/* The basket: what you have collected, what the R you download will contain,
   and the download itself.

   This view replaced a request-drafting form. Collecting variables and asking
   for a new one to be derived looked like the same gesture and are not: one
   ends in a zip you run this afternoon, the other in an issue someone works on
   for a week. The assistant's draft panel is where a request is written now —
   it checks every name against the index as it goes, which the form never did
   — and what is left here is the half that produces something runnable.

   Two kinds of thing go in, and the difference is real rather than cosmetic.
   A harmonised variable ships as the repository's own script, verbatim — its
   output column is its `spec$id` and renaming it here would mean editing a
   tested file, so it is fixed. A raw variable has no script to ship: it is a
   deposited column, and the bundler generates a passthrough script for it from
   templates/passthrough.R. Nothing about the passthrough is bespoke — runner.R
   still does the loading, the identifier cleaning, the duplicate resolution and
   the join — so the only thing left to decide is what to call the column, which
   is exactly what the right-hand pane lets you edit.

   The list pane is what you picked up; the detail pane is what you will get.
   They are not the same list twice: the second is the output CSV's columns, in
   the shape a collision or an unusable name would actually bite. */

import { $, $$ } from "./dom.js";
import { DRAG_MIME, esc, issueUrl, state, storeKey } from "./state.js";
import { switchView } from "./views.js";

/* What to redraw when the basket changes. Set by boot.js rather than imported,
   because the two lists that feed the basket also read its contents to draw
   their ＋ controls — importing them back from here would be the one cycle
   this half of the site has stayed free of. */
let notify = () => {};
export const onChange = (fn) => { notify = fn; };

/* ── The list ────────────────────────────────────────────────────────── */

// Stable identity for an entry, so removal and duplicate detection do not
// depend on list position. A raw column is identified by where it came from,
// never by its output name — that is editable and may collide.
export const keyOf = (item) => item.kind === "derived"
  ? `derived:${item.id}`
  : `raw:${item.file}:${item.name}`;

const has = (item) => state.bundle.some((b) => keyOf(b) === keyOf(item));

/* What a raw column may be called: R will accept far more than this if you
   quote it, but the name is also a file name (the generated script is
   `<column>.R`) and is cross-checked against `spec$id` by discovery.R. The
   intersection of "valid R", "valid file name" and "survives a CSV header"
   is narrow enough to be worth enforcing rather than explaining. */
const NAME_OK = /^[A-Za-z][A-Za-z0-9_.]*$/;

export const sanitiseColumn = (s) => String(s || "")
  .replace(/[^A-Za-z0-9_.]/g, "_")
  .replace(/^[^A-Za-z]+/, "");

/* The default output name for a raw column: its own name, because that is
   what the researcher searched for and what the data dictionary calls it.
   Uniqueness is imposed on top — first by qualifying with the wave, which
   says something true about the column, and only then by counting, which
   says nothing. */
function defaultColumn(name, wave, taken) {
  const base = sanitiseColumn(name) || "var";
  if (!taken.has(base)) return base;
  const qualified = sanitiseColumn(`${base}_${wave}`);
  if (qualified && !taken.has(qualified)) return qualified;
  for (let n = 2; ; n++) {
    const candidate = `${qualified || base}_${n}`;
    if (!taken.has(candidate)) return candidate;
  }
}

/* Every output column the bundle already claims. The harmonised ids are in
   here because a raw passthrough called `bmi_10y` would collide with the
   derived variable of that name in the join, not just in the panel.

   The IDENTIFIER is in here for a worse reason. It is not in `state.bundle`
   and never can be, but it is column one of the output — and a passthrough
   named after it generates `out[[<identifier>]] <- data[["<var>"]]`, which
   overwrites the key with the raw variable's codes. `runner.R`'s check that
   derive() returned both columns passes, because both names are the same
   string, and the final merge then joins every other variable on those codes.
   Refusing the identifier as a SOURCE name (addRaw) does not cover this: the
   output name is typed by hand, separately. */
function takenColumns(except) {
  const out = new Set();
  const id = state.dataset?.identifier;
  if (id) out.add(id);
  for (const b of state.bundle) {
    if (except && keyOf(b) === except) continue;
    out.add(b.kind === "derived" ? b.id : b.column);
  }
  return out;
}

/* ── Adding and removing ─────────────────────────────────────────────── */

export function addDerived(id) {
  const entry = state.derived.find((d) => d.id === id);
  if (!entry || has({ kind: "derived", id })) return false;
  state.bundle.push({ kind: "derived", id });
  save(); render();
  return true;
}

/* The identifier is in every dictionary — it is column one of every deposited
   file — so it is searchable and draggable like anything else. It is not a
   variable, though: it is the key every variable is joined on and it is
   already the first column of the output. A passthrough of it cannot even be
   built, because `load_tab()` normalises the identifier column's name to
   the configured spelling as it loads, so a spec carrying the dictionary's
   own casing names a column that no longer exists by the time the runner
   looks for it. */
export const isIdentifier = (name) => {
  const id = String(state.dataset?.identifier || "").toLowerCase();
  return Boolean(id) && String(name).toLowerCase() === id;
};

/* A raw column, from a search result or a dragged row. Refused when its file
   has no row in the master lookup: `load_tab()` resolves a file_name through
   that lookup and nothing else, so the generated script would fail at the
   first line of the run rather than produce a column. Better to say so at the
   moment of the gesture than in an R traceback an hour later. */
export function addRaw({ name, label, file, wave }) {
  const item = { kind: "raw", name, label: label || "", file, wave };
  if (has(item)) { say(`${name} is already in the bundle.`); return false; }

  // Not a refusal. Reaching for the identifier is the correct instinct — you
  // do need something to join on — so this confirms it is already there rather
  // than telling the researcher they were wrong to look. The detail pane lists
  // it as the output's first column for the same reason: the surest way to
  // stop someone hunting for a thing is to show them they already have it.
  if (isIdentifier(name)) {
    say(`${name} is already in every download — it is the first column of the ` +
        `output, and every variable is joined on it. Nothing to add.`);
    return false;
  }

  const known = state.manifest.files.find((f) => f.name === file && f.wave === wave)
    || state.manifest.files.find((f) => f.name === file);
  if (known && known.inLookup === false) {
    say(`${file} has no row in the master lookup, so the runner cannot open it. ${name} was not added.`);
    return false;
  }

  item.column = defaultColumn(name, wave, takenColumns());
  state.bundle.push(item);
  save(); render();
  return true;
}

export function removeAt(key) {
  state.bundle = state.bundle.filter((b) => keyOf(b) !== key);
  save(); render();
}

export function inBundle(kind, a, b) {
  return has(kind === "derived" ? { kind, id: a } : { kind, file: b, name: a });
}

function rename(key, value) {
  const item = state.bundle.find((b) => keyOf(b) === key);
  if (!item || item.kind !== "raw") return;
  item.column = value;
  save(); render();
}

/* ── Persistence ─────────────────────────────────────────────────────── */

function save() {
  try {
    localStorage.setItem(storeKey("bundle"), JSON.stringify(state.bundle));
  } catch { /* private browsing, or storage full — the bundle just won't persist */ }
}

/* A saved bundle can outlive the thing it names: a variable gets renamed, a
   deposit gains a lookup row, the site is rebuilt. Anything that no longer
   resolves is dropped rather than carried forward, because a bundle cannot
   contain what is not there and a stale entry would only fail at download. */
export function restoreBundle() {
  let saved;
  try { saved = JSON.parse(localStorage.getItem(storeKey("bundle")) || "[]"); }
  catch { state.bundle = []; return; }
  if (!Array.isArray(saved)) { state.bundle = []; return; }

  const derivedIds = new Set(state.derived.map((d) => d.id));
  const rawNames = new Set();
  for (const row of state.vars) {
    const file = state.manifest.files[row[2]];
    if (file && file.inLookup !== false) rawNames.add(`${file.name} ${row[0]}`);
  }

  state.bundle = saved.filter((b) => b && (b.kind === "derived"
    ? derivedIds.has(b.id)
    // !isIdentifier: a basket saved before the identifier was refused would
    // otherwise keep producing a bundle that cannot run.
    : b.kind === "raw" && !isIdentifier(b.name) && rawNames.has(`${b.file} ${b.name}`)));

  // Restore is also the one place a column name arrives unvalidated, having
  // come back out of storage rather than through addRaw().
  const taken = new Set();
  for (const b of state.bundle) {
    if (b.kind === "derived") { taken.add(b.id); continue; }
    b.column = NAME_OK.test(b.column || "")
      ? b.column : defaultColumn(b.name, b.wave, taken);
    taken.add(b.column);
  }
}

/* The ＋ beside a row, and the ✓ it becomes. Shared with the metadata view
   so the same gesture looks the same wherever a variable is listed — the two
   lists are the only places a variable can be picked up, and a control that
   differed between them would read as two different features.

   `args` is what accept() needs to identify the thing: an id for a harmonised
   variable, a name and a file for a raw one. */
export function addButton(kind, id, isIn, aria, args = {}) {
  const data = Object.entries({ kind, id, ...args })
    .map(([k, v]) => `data-add-${k}="${esc(v)}"`).join(" ");
  return `<button class="add${isIn ? " is-in" : ""}" ${data}
    ${isIn ? 'aria-disabled="true"' : ""}
    title="${isIn ? "Already in the R bundle" : "Add to the R bundle"}"
    aria-label="${isIn ? `${esc(aria)} is in the R bundle` : `Add ${esc(aria)} to the R bundle`}"
    >${isIn ? "✓" : "＋"}</button>`;
}

/* ── What cannot be packaged ─────────────────────────────────────────── */

/* Returned rather than thrown: the detail pane draws the reason beside the row
   that caused it, and the download button reads the same list to decide
   whether it may run. */
export function problems() {
  const seen = new Map();
  const out = new Map();

  // The identifier occupies its column before any variable does. Seeded with a
  // key nothing else can hold, so a clash is reported against the row that
  // caused it and never against the identifier itself. See takenColumns().
  const identifier = state.dataset?.identifier;
  if (identifier) seen.set(identifier, null);

  for (const b of state.bundle) {
    const column = b.kind === "derived" ? b.id : b.column;
    if (b.kind === "raw" && !NAME_OK.test(column || "")) {
      out.set(keyOf(b), "Must start with a letter and use only letters, digits, _ or .");
      continue;
    }
    if (seen.has(column)) {
      const clashesWithIdentifier = seen.get(column) === null;
      const message = clashesWithIdentifier
        ? `${column} is the identifier — naming a column this would overwrite ` +
          `the key every variable is joined on.`
        : `Two variables would both be called ${column}.`;
      out.set(keyOf(b), message);
      if (!clashesWithIdentifier) out.set(seen.get(column), message);
      continue;
    }
    seen.set(column, keyOf(b));
  }
  return out;
}

const rawItems = () => state.bundle.filter((b) => b.kind === "raw");
const derivedItems = () => state.bundle.filter((b) => b.kind === "derived");
const specFor = (b) => state.derived.find((d) => d.id === b.id) || {};

/* ── Rendering ───────────────────────────────────────────────────────── */

export function render() {
  notify();
  renderList();
  renderDetail();
}

/* The list pane: what you have picked up, grouped by kind because the two are
   not interchangeable and the download treats them differently. */
function renderList() {
  const n = state.bundle.length;
  const raw = rawItems();
  const derived = derivedItems();

  $("#basket-tally").textContent = n;
  $("#basket-tally").hidden = n === 0;
  $("#basket-clear").hidden = n === 0;
  $("#basket-empty").hidden = n > 0;

  // Left alone while it is carrying a message, so a refusal is not wiped out
  // by the re-render that the refusal itself did not cause.
  const count = $("#basket-count");
  if (!count.classList.contains("is-saying")) {
    count.innerHTML = n
      ? `<strong>${n}</strong> variable${n === 1 ? "" : "s"}`
      : "Nothing collected yet";
  }

  const group = (title, note, items, row) => items.length
    ? `<li><p class="more" style="border-bottom:1px solid var(--rule);margin:0">
         <strong>${esc(title)}</strong> — ${esc(note)}</p></li>` + items.map(row).join("")
    : "";

  $("#basket-list").innerHTML =
    group("Research ready", "shipped as the repository's own scripts", derived, (b) => {
      const d = specFor(b);
      return `<li class="pickable">
        <button class="drop basket-x" data-remove="${esc(keyOf(b))}"
                aria-label="Remove ${esc(b.id)} from the basket">✕</button>
        <span class="row" style="cursor:default">
          <span class="row-top">
            <span class="row-name">${esc(b.id)}</span>
            <span class="row-wave">${statusPill(d.status)}</span>
          </span>
          <span class="row-label">${esc(d.label || "")}</span>
        </span></li>`;
    }) +
    group("Raw", "deposited columns, passed through unchanged", raw, (b) => `
      <li class="pickable">
        <button class="drop basket-x" data-remove="${esc(keyOf(b))}"
                aria-label="Remove ${esc(b.name)} from the basket">✕</button>
        <span class="row" style="cursor:default">
          <span class="row-top">
            <span class="row-name">${esc(b.name)}</span>
            <span class="row-wave">${esc(b.wave)}</span>
          </span>
          <span class="row-label">${esc(b.label || "no label")}</span>
          <span class="row-file">${esc(b.file)}</span>
        </span></li>`);

  $$("#basket-list [data-remove]").forEach((btn) =>
    btn.addEventListener("click", () => removeAt(btn.dataset.remove)));
}

function statusPill(status) {
  const cls = status === "verified" ? "pill-verified"
    : status === "ready_for_real_data_test" ? "pill-ready" : "pill-draft";
  return `<span class="pill ${cls}">${esc(String(status || "unknown").replace(/_/g, " "))}</span>`;
}

/* The detail pane: the columns of the CSV this will produce, in the order the
   runner will write them, with the only editable thing on screen — what a raw
   column is called. This is the review step: a collision between two deposits
   that both call something `sex` is the normal case, not the exception, and it
   is invisible until the two are side by side. */
function renderDetail() {
  const el = $("#basket-detail");
  const n = state.bundle.length;

  if (!n) {
    el.innerHTML = `<div class="empty">
      <h2>Build a bundle of R code</h2>
      <p>Collect variables from the metadata and derived lists, then download
      them as R you can run against your own copy of the deposits: the runner,
      its libraries, and one script per variable, with a README.</p>
      <p>Both kinds go in the same bundle and come out as columns of the same
      CSV. A <strong>research-ready</strong> variable ships as the repository's
      own script, unchanged. A <strong>raw</strong> variable is a deposited
      column passed through as it stands — not recoded, missing-value sentinels
      and all.</p>
      <p class="empty-hint">Drag a row onto the ${esc(tabName())} tab from
      <strong>Raw variables</strong> or <strong>Research ready</strong>, or use
      the ＋ beside it.</p>
    </div>`;
    return;
  }

  const bad = problems();
  const raw = rawItems();
  const drafts = derivedItems().filter((b) => specFor(b).status !== "verified");
  const files = [...new Set([
    ...derivedItems().flatMap((b) => specFor(b).source_files || []),
    ...raw.map((b) => b.file),
  ])].sort();

  el.innerHTML = `
    <div class="detail-head">
      <div class="detail-eyebrow">${derivedItems().length} research ready · ${raw.length} raw</div>
      <h1 class="detail-name">output/derived_variables.csv</h1>
      <p class="detail-label">One row per cohort member, one column per variable
        below, joined on <code>${esc(state.dataset.identifier || "the identifier")}</code>.</p>
    </div>

    ${bad.size ? `<div class="warn"><span>⚠</span><div>
      <strong>Two columns cannot share a name.</strong> The runner joins on
      column name, so this has to be settled before the bundle can be built.
    </div></div>` : ""}

    ${drafts.length ? `<div class="warn"><span>⚠</span><div>
      <strong>${drafts.length} not verified against real data.</strong>
      Synthetic tests check that a recoding does what it says on fabricated
      rows. They cannot tell you the codes it recodes are the codes your
      deposit uses.</div></div>` : ""}

    ${raw.length ? `<div class="warn"><span>⚠</span><div>
      <strong>Raw columns are not recoded.</strong> You get the codes as
      deposited, missing-value sentinels included. Negative codes in this
      corpus are usually missing-value markers and the schemes are not
      consistent between variables — check each one's data dictionary.
    </div></div>` : ""}

    <h2 class="section-title">Columns</h2>
    <ol class="cols">${identifierCol()}${state.bundle.map((b) => b.kind === "derived"
      ? derivedCol(b, bad) : rawCol(b, bad)).join("")}</ol>

    <h2 class="section-title">Source files it needs</h2>
    <ul class="linklist">${files.map((f) => {
      const known = state.manifest.files.find((x) => x.name === f);
      return `<li><button data-file="${esc(f)}">
        <span class="ll-name">${esc(f)}</span>
        <span class="ll-desc">${esc(known?.description || "")}</span>
        <span class="ll-meta">${esc(known ? known.wave : "not in lookup")}</span>
      </button></li>`;
    }).join("")}</ul>
    <p class="note">A variable whose source file is missing from your copy stops
      the run with a message naming it.</p>

    <div class="detail-actions">
      <button class="btn btn-primary" id="basket-download">Download R code</button>
    </div>
    <p class="draft-status" id="basket-status" role="status"></p>

    ${requestUrl() ? `<h2 class="section-title">Not research ready yet?</h2>
    <p class="note">If you are about to recode one of these raw columns by hand,
      that is the moment it is worth asking for a research-ready one instead —
      then everyone gets the same variable, tested. The assistant writes the request
      with you and checks every name against the dictionaries; this link is the
      plain version, carrying what is in the basket.</p>
    <div class="detail-actions">
      <a class="btn" id="basket-issue" href="#" target="_blank" rel="noopener">Request a research-ready variable</a>
    </div>` : ""}`;

  const button = $("#basket-download");
  button.disabled = bad.size > 0;
  button.textContent = `Download ${n} variable${n === 1 ? "" : "s"}`;
  button.addEventListener("click", download);

  const issue = $("#basket-issue");
  if (issue) issue.href = requestUrl();

  wireRenames();
  $$("#basket-detail [data-file]").forEach((b) =>
    b.addEventListener("click", () => openFile(b.dataset.file)));
}

/* The identifier, drawn first and always. It is not in `state.bundle` and
   cannot be put there — it is supplied by the runner, not selected — but
   leaving it off the list made this pane claim the output has columns it does
   not have, and sent people to the search looking for the identifier. Which
   they find: it is row one of every dictionary, indistinguishable from a real
   variable. */
function identifierCol() {
  const id = state.dataset?.identifier;
  if (!id) return "";
  return `<li class="col-row is-fixed">
    <span class="col-kind col-kind-id" title="The identifier">·</span>
    <span class="col-name">${esc(id)}</span>
    <span class="col-note">always included — the key every variable is joined on</span>
  </li>`;
}

function derivedCol(b, bad) {
  const problem = bad.get(keyOf(b));
  return `<li class="col-row${problem ? " is-bad" : ""}">
    <span class="col-kind col-kind-derived" title="Research ready — shipped as its own script">R+</span>
    <span class="col-name">${esc(b.id)}</span>
    <span class="col-note">fixed — the script was tested under this name</span>
    ${problem ? `<span class="col-problem">${esc(problem)}</span>` : ""}
  </li>`;
}

function rawCol(b, bad) {
  const key = keyOf(b);
  const problem = bad.get(key);
  return `<li class="col-row${problem ? " is-bad" : ""}">
    <span class="col-kind col-kind-raw" title="Raw — passed through unchanged">R</span>
    <input class="col-input" type="text" value="${esc(b.column)}"
           data-rename="${esc(key)}" spellcheck="false" autocomplete="off"
           aria-label="Output column name for ${esc(b.name)}"
           aria-invalid="${problem ? "true" : "false"}">
    <span class="col-note"><code>${esc(b.name)}</code> from
      <code>${esc(b.file)}</code> · ${esc(b.wave)}</span>
    ${problem ? `<span class="col-problem">${esc(problem)}</span>` : ""}
  </li>`;
}

/* Renaming re-renders, which replaces the input being typed into. So the value
   is committed on blur or Enter rather than on every keystroke, and the caret
   survives. */
function wireRenames() {
  $$("#basket-detail [data-rename]").forEach((input) => {
    const commit = () => {
      const next = sanitiseColumn(input.value.trim());
      const item = state.bundle.find((b) => keyOf(b) === input.dataset.rename);
      if (!item || next === item.column) return;
      item.column = next;
      save(); render();
    };
    input.addEventListener("blur", commit);
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); input.blur(); }
    });
  });
}

/* A request carrying what is in the basket. The raw columns are the candidate
   sources — a harmonised variable is a precedent, not a source, so it is named
   in the notes instead of the source list. */
function requestUrl() {
  const raw = rawItems();
  const derived = derivedItems();
  const waves = [...new Set(raw.map((b) => b.wave))]
    .sort((a, b) => state.manifest.waves.indexOf(a) - state.manifest.waves.indexOf(b));
  return issueUrl({
    waves: waves.join(", "),
    sources: raw.map((b) => `${b.name} — ${b.label || "no label"} (${b.file}, ${b.wave})`)
      .join("\n"),
    notes: derived.length
      ? `Follow the precedent of: ${derived.map((b) => b.id).join(", ")}.`
      : "",
  });
}

function openFile(name) {
  const idx = state.manifest.files.findIndex((f) => f.name === name);
  if (idx < 0) return;
  switchView("metadata");
  state.fileFilter = idx;
  state.waveFilter = null;
  state.levelFilter = null;
  state.query = "";
  onOpenFile();
}

/* What the metadata view has to do after the filter is set. Injected for the
   same reason `notify` is: this module must not import the views back. */
let onOpenFile = () => {};
export const onFileOpened = (fn) => { onOpenFile = fn; };

const tabName = () => state.dataset?.basketTab || "R bundle";

/* Where a message about the basket goes.

   `#basket-status` only exists once the detail pane has drawn a non-empty
   bundle, and only while this view is on screen — but the three things
   addRaw() refuses are reachable by dragging onto the TAB from the metadata
   view, where it is absent or scrolled away. So the count line, which is in
   the list pane and always rendered, is the fallback. A refusal nobody can
   see is indistinguishable from a drop that did nothing. */
let sayTimer;
function say(msg) {
  const el = $("#basket-status") || $("#basket-count");
  if (!el) return;
  const restore = el.id === "basket-count" ? el.innerHTML : "";
  el.textContent = msg;
  el.classList.add("is-saying");
  clearTimeout(sayTimer);
  sayTimer = setTimeout(() => {
    el.classList.remove("is-saying");
    if (restore) el.innerHTML = restore; else el.textContent = "";
  }, 8000);
}

/* ── Downloading ─────────────────────────────────────────────────────── */

async function download() {
  if (!state.bundle.length || problems().size) return;

  const button = $("#basket-download");
  button.disabled = true;
  say("Packaging…");

  try {
    // Both fetched only now: the zip writer and ~17 KB of pipeline source are
    // dead weight for the majority who never download anything.
    // `../` because an import specifier resolves against THIS module, while
    // the fetch below resolves against the page.
    const [{ build }, pipeline] = await Promise.all([
      import("../bundle.js"),
      state.pipeline ? Promise.resolve(state.pipeline) : loadPipeline(),
    ]);
    state.pipeline = pipeline;

    const picked = {
      derived: derivedItems().map((b) => state.derived.find((d) => d.id === b.id))
        .filter(Boolean),
      raw: rawItems(),
    };

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

    say(`${name} — ${(blob.size / 1024).toFixed(0)} KB. Its README says how to run it.`);
  } catch (err) {
    console.error(err);
    say(`Could not build the download: ${err.message}`);
  } finally {
    const again = $("#basket-download");
    if (again) again.disabled = state.bundle.length === 0 || problems().size > 0;
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
  if (rawItems().length && !pipeline.templates?.["templates/passthrough.R"]) {
    throw new Error("pipeline.json has no passthrough template — rebuild the site");
  }
  return pipeline;
}

/* ── Wiring ──────────────────────────────────────────────────────────── */

export function wire() {
  $("#basket-clear").addEventListener("click", () => {
    state.bundle = [];
    save(); render();
  });

  /* Drag and drop. The view's own pane is the target while you are in it, and
     its TAB is a target from anywhere else — which is the whole reason the tab
     accepts a drop at all: you cannot drag something onto a pane you would
     first have to navigate to, and asking someone to put the variable down,
     switch view, and go back for it is not a gesture. */
  const targets = [$("#basket-drop"), $('.view-tab[data-view="basket"]')];
  const accepts = (e) => [...(e.dataTransfer?.types || [])].includes(DRAG_MIME);

  document.addEventListener("dragstart", (e) => {
    if (e.target.closest?.("[data-drag]")) document.body.classList.add("is-dragging-var");
  });
  document.addEventListener("dragend", () => {
    document.body.classList.remove("is-dragging-var");
    targets.forEach((t) => t?.classList.remove("is-dropping"));
  });

  for (const target of targets) {
    if (!target) continue;
    let depth = 0;
    target.addEventListener("dragenter", (e) => {
      if (!accepts(e)) return;
      e.preventDefault(); depth++; target.classList.add("is-dropping");
    });
    target.addEventListener("dragover", (e) => {
      if (!accepts(e)) return;
      e.preventDefault(); e.dataTransfer.dropEffect = "copy";
    });
    target.addEventListener("dragleave", () => {
      if (--depth <= 0) target.classList.remove("is-dropping");
    });
    target.addEventListener("drop", (e) => {
      if (!accepts(e)) return;
      e.preventDefault(); depth = 0;
      target.classList.remove("is-dropping");
      let item;
      try { item = JSON.parse(e.dataTransfer.getData(DRAG_MIME)); }
      catch { return; }
      accept(item);
    });
  }
}

/* One entry point for anything arriving from outside — a drop, a ＋ on a row,
   a button in a detail pane, the assistant handing over its pinned variables —
   so the two kinds are told apart in exactly one place. The drag payload has
   carried `kind` since it was introduced. */
export function accept(item) {
  if (!item?.name) return false;
  return item.kind === "derived" ? addDerived(item.name) : addRaw(item);
}
