/* The request being assembled, and the ways out of it: a prefilled issue, the
   clipboard, or handing the raw variables it names over to the R bundle.

   This is now the only place a variable request is written. The atlas used to
   carry a plain form beside it; that view builds downloadable R instead, and a
   request drafted here is better than one drafted there ever was, because
   every name in it is checked against the index before it is shown. */

import { $, $$ } from "./dom.js";
import { esc } from "./markup.js";
import { A, capitaliseWave, chat, saveSession } from "./state.js";

/* Every name in the draft is checked against the real index before it is
   shown. This is the backstop for the one failure mode that matters: a model
   that helpfully invents `bmi10` because it sounds like something that ought
   to exist. A flagged name is not removed — you may have typed a real name
   the site cannot resolve — but it is never presented as if the corpus
   confirmed it. */
// Built once from the ~32,000-row index rather than on every render: this
// runs on each draft event and each source-variable removal, and the corpus
// does not change while the page is open.
let knownNames = null;

export function checkNames(names) {
  if (!knownNames) {
    knownNames = new Set((A().state.vars || []).map((r) => String(r[0]).toLowerCase()));
  }
  return names.map((n) => ({
    name: n,
    known: chat.knownVars?.[n] ?? knownNames.has(String(n).toLowerCase()),
  }));
}

export function refreshGate() {
  const issue = $("#cd-issue");
  if (!issue) return;
  // From the config, via the atlas. Two copies of "what an issue needs" is one
  // copy too many, and the drifting one is always the one you are not reading.
  const missing = A().requiredFields()
    .filter((k) => !String(chat.draft[k] || "").trim());
  const ready = missing.length === 0;
  issue.href = ready ? issueUrl() : "#";
  issue.setAttribute("aria-disabled", String(!ready));
  $("#cd-status").textContent = ready
    ? "Ready. Review it on GitHub before submitting."
    : `Still needed before this can be filed: ${missing.join(", ")}.`;
}

export function renderDraft() {
  const el = $("#chat-draft");
  if (!el || !chat.interview) return;
  const d = chat.draft;

  // A background extraction can land while the researcher is mid-sentence
  // in one of these boxes. Put the caret back where it was.
  const active = document.activeElement;
  const caret = el.contains(active) && active.id
    ? { id: active.id, start: active.selectionStart, end: active.selectionEnd }
    : null;

  const checked = checkNames(d.source_vars || []);
  const unknown = checked.filter((c) => !c.known).length;

  el.innerHTML = `
    ${chat.separate.length > 1 ? `<div class="warn"><span>⚠</span><div>
      <strong>This looks like ${chat.separate.length} concepts.</strong>
      One issue is one concept — ${chat.separate.map(esc).join("; ")} each need
      their own request so they can be reviewed and verified independently.
    </div></div>` : ""}

    <label class="field">
      <span class="field-label">Proposed name</span>
      <input id="cd-name" value="${esc(d.name)}" spellcheck="false" placeholder="not settled yet">
    </label>
    <label class="field">
      <span class="field-label">${esc(capitaliseWave())}</span>
      <input id="cd-waves" value="${esc(d.waves)}" spellcheck="false" placeholder="not settled yet">
    </label>
    <label class="field">
      <span class="field-label">Category</span>
      <select id="cd-category">
        <option value="">Choose one…</option>
        ${A().categories().map(({ label }) =>
          `<option${label === d.category ? " selected" : ""}>${esc(label)}</option>`).join("")}
      </select>
    </label>
    <label class="field">
      <span class="field-label">What it should capture</span>
      <textarea id="cd-description" rows="4" placeholder="not settled yet">${esc(d.description)}</textarea>
    </label>

    <span class="field-label">Source variables
      ${unknown ? `<em>${unknown} unverified</em>` : ""}</span>
    <ul class="srcvars">${checked.length ? checked.map((c, i) => `
      <li class="${c.known ? "is-known" : "is-unknown"}">
        <code>${esc(c.name)}</code>
        <span>${c.known ? "in the dictionaries" : "not found in any dictionary"}</span>
        <button data-dropvar="${i}" aria-label="Remove ${esc(c.name)}">✕</button>
      </li>`).join("") : `<li class="srcvars-empty">None yet. Drag variables in,
        or use the search button below.</li>`}
    </ul>

    <label class="field">
      <span class="field-label">Coding and edge cases</span>
      <textarea id="cd-notes" rows="8"
        placeholder="Assembled from the conversation as each detail is settled. Edit it and it stops being overwritten.">${esc(d.notes)}</textarea>
    </label>

    <div class="draft-actions">
      <a class="btn btn-primary" id="cd-issue" href="#" target="_blank" rel="noopener">Open as GitHub issue</a>
      <button class="btn" id="cd-bundle" type="button">Add sources to R bundle</button>
      <button class="btn" id="cd-copy" type="button">Copy markdown</button>
    </div>
    <p class="draft-status" id="cd-status" role="status"></p>`;

  refreshGate();

  ["name", "waves", "category", "description", "notes"].forEach((k) => {
    const input = $(`#cd-${k}`);
    // Typing updates the state and the gate, never the whole panel: this is
    // innerHTML, so re-rendering on keystroke would drop the caret.
    const take = () => {
      d[k] = input.value;
      if (k === "notes") d.notesTouched = true;
      refreshGate();
      saveSession();
    };
    input?.addEventListener("input", take);
    input?.addEventListener("change", take);
  });
  $$("#chat-draft [data-dropvar]").forEach((b) => b.addEventListener("click", () => {
    d.source_vars.splice(Number(b.dataset.dropvar), 1);
    renderDraft(); saveSession();
  }));
  $("#cd-bundle")?.addEventListener("click", toBundle);
  $("#cd-copy")?.addEventListener("click", copyMarkdown);

  if (caret) {
    const back = $(`#${caret.id}`);
    if (back) {
      back.focus();
      try { back.setSelectionRange(caret.start, caret.end); }
      catch { /* a <select> has no selection range */ }
    }
  }
  saveSession();
}

/* ── Handing off the draft ─────────────────────────────────────────── */

export function sourceLines() {
  const byName = new Map(chat.pinned.map((p) => [p.name, p]));
  return (chat.draft.source_vars || []).map((n) => {
    const p = byName.get(n);
    return p ? `${n} — ${p.label || "no label"} (${p.file}, ${p.wave})` : n;
  }).join("\n");
}

// Composed by the atlas, from the field ids in the config — one builder for
// both routes to an issue.
export function issueUrl() {
  const d = chat.draft;
  return A().issueUrl({
    name: d.name, waves: d.waves, category: d.category,
    description: d.description, sources: sourceLines(), notes: d.notes,
  });
}

/* The raw variables this request names, handed to the R bundle.

   A request is for a variable that does not exist yet, so there is nothing
   here to download — but its candidate sources are real deposited columns, and
   wanting to look at them before waiting on a derivation is the ordinary next
   thought. Harmonised variables among the pinned are precedents rather than
   sources and are deliberately not sent: they belong in the request's notes,
   not in a bundle the researcher did not ask for. */
export function toBundle() {
  const sources = chat.pinned.filter((p) => p.kind !== "derived");
  if (!sources.length) {
    $("#cd-status").textContent =
      "No raw variables pinned yet — this request has no sources to download.";
    return;
  }
  const added = sources
    .filter((p) => A().addToBundle({
      kind: "variable", name: p.name, label: p.label, file: p.file, wave: p.wave,
    })).length;
  A().switchView("basket");
  $("#cd-status").textContent = added
    ? `Added ${added} raw variable${added === 1 ? "" : "s"} to the bundle.`
    : "Those are already in the bundle.";
}

export async function copyMarkdown() {
  const d = chat.draft;
  const text = [
    `## ${d.name || "unnamed variable"}`, "",
    // No esc() here: this is markdown bound for the clipboard, not markup.
    // Escaping it turned an apostrophe in the wave term into `&#39;`.
    `**${capitaliseWave()}:** ${d.waves || "—"}`,
    `**Category:** ${d.category || "—"}`, "",
    "### What should this variable capture?", d.description || "—", "",
    "### Known or candidate source variables", sourceLines() || "—", "",
    "### Coding / edge-case notes", d.notes || "—",
  ].join("\n");
  try {
    await navigator.clipboard.writeText(text);
    $("#cd-status").textContent = "Copied to the clipboard.";
  } catch {
    $("#cd-status").textContent = "Couldn't reach the clipboard.";
  }
}
