/* The request being assembled, and the two ways out of it: a prefilled issue,
   or the scratchpad. */

import { $, $$ } from "./dom.js";
import { esc } from "./markup.js";
import { A, capitaliseWave, chat, restore, saveSession } from "./state.js";

/* Every name in the draft is checked against the real index before it is
   shown. This is the backstop for the one failure mode that matters: a model
   that helpfully invents `bmi10` because it sounds like something that ought
   to exist. A flagged name is not removed — you may have typed a real name
   the site cannot resolve — but it is never presented as if the corpus
   confirmed it. */
export function checkNames(names) {
  const local = new Set((A().state.vars || []).map((r) => String(r[0]).toLowerCase()));
  return names.map((n) => ({
    name: n,
    known: chat.knownVars?.[n] ?? local.has(String(n).toLowerCase()),
  }));
}

export function refreshGate() {
  const issue = $("#cd-issue");
  if (!issue) return;
  const missing = ["name", "waves", "category", "description"]
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
  const restore = el.contains(active) && active.id
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
      <button class="btn" id="cd-scratch" type="button">Send to scratchpad</button>
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
  $("#cd-scratch")?.addEventListener("click", toScratchpad);
  $("#cd-copy")?.addEventListener("click", copyMarkdown);

  if (restore) {
    const back = $(`#${restore.id}`);
    if (back) {
      back.focus();
      try { back.setSelectionRange(restore.start, restore.end); }
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

export function toScratchpad() {
  const d = chat.draft;
  A().fillDraft({
    name: d.name, waves: d.waves, category: d.category,
    description: d.description, sources: sourceLines(), notes: d.notes,
  });
  chat.pinned.filter((p) => p.kind !== "derived").forEach((p) => A().addToBasket({
    name: p.name, label: p.label, file: p.file, wave: p.wave,
  }));
  A().switchView("scratch");
  $("#cd-status").textContent = "Copied into the scratchpad form.";
}

export async function copyMarkdown() {
  const d = chat.draft;
  const text = [
    `## ${d.name || "unnamed variable"}`, "",
    `**${esc(capitaliseWave())}:** ${d.waves || "—"}`,
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

/* ── Settings ──────────────────────────────────────────────────────── */
