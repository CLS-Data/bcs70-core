/* Choosing a model, and finding out which are available. */

import { $ } from "./dom.js";
import { api } from "./api.js";
import { esc } from "./markup.js";
import { A, chat, defaultBase, modelThinks, saveSettings, wavePlural } from "./state.js";
import { renderComposer, renderStatus } from "./composer.js";
import { renderTranscript } from "./transcript.js";

/* How the dictionaries are searched.

   Every control here trades breadth against time, and which way to trade
   depends on the question rather than on a good default — looking for a
   concept nobody has named consistently is worth two seconds, and checking a
   variable you already know is not. */
function renderRetrieval(s) {
  const r = s.retrieval;
  if (!r) return `<p class="note">Retrieval settings didn't load.</p>`;
  const sem = chat.semantic || {};

  return `
    <label class="field check">
      <input id="cs-semantic" type="checkbox"${r.semantic ? " checked" : ""}
             ${sem.available ? "" : "disabled"}>
      <span>Search by meaning as well as by words</span>
      <span class="field-help">${sem.available
        ? `Finds variables whose wording shares nothing with the question —
           “How is your health generally” for <em>self-rated health</em>.
           Adds about a fifth of a second.
           <code>${esc(sem.model || "")}</code>, ${esc(String(sem.dims || ""))} dimensions.`
        : `Unavailable. ${esc(sem.reason || "No index has been built.")}`}</span>
    </label>

    <label class="field check">
      <input id="cs-expand" type="checkbox"${r.expand ? " checked" : ""}>
      <span>Also search other wordings of the same thing</span>
      <span class="field-help">Asks the helper model to rephrase the search the
        way a questionnaire would, and searches each. One extra model call per
        lookup — the slowest setting here, and the one that helps most when a
        concept has no standard name.</span>
    </label>

    <label class="field">
      <span class="field-label">Wordings to try <em>${esc(String(r.expansions))}</em></span>
      <input id="cs-expansions" type="range" min="1" max="6" step="1"
             value="${esc(String(r.expansions))}"${r.expand ? "" : " disabled"}>
    </label>

    <label class="field">
      <span class="field-label">Variables per lookup <em>${esc(String(r.candidates))}</em></span>
      <input id="cs-candidates" type="range" min="3" max="30" step="1"
             value="${esc(String(r.candidates))}">
      <span class="field-help">How many the model is shown. More is not
        automatically better: a model handed thirty variables summarises them
        instead of asking you the next question.</span>
    </label>

    <label class="field">
      <span class="field-label">Words vs meaning
        <em>${esc(balance(r))}</em></span>
      <input id="cs-balance" type="range" min="0" max="100" step="5"
             value="${esc(String(Math.round(100 * r.semanticWeight /
               ((r.lexicalWeight + r.semanticWeight) || 1))))}"
             ${sem.available && r.semantic ? "" : " disabled"}>
      <span class="field-help">Which side wins when the two disagree. Exact
        names and codes come from words; concepts come from meaning.</span>
    </label>`;
}

function balance(r) {
  const total = (r.lexicalWeight + r.semanticWeight) || 1;
  const pct = Math.round(100 * r.semanticWeight / total);
  if (pct <= 20) return "mostly words";
  if (pct >= 80) return "mostly meaning";
  if (pct === 50) return "even";
  return pct > 50 ? "leaning meaning" : "leaning words";
}

export function renderSettings() {
  const el = $("#chat-settings");
  if (!el) return;
  const s = chat.settings;
  const chatModels = chat.models.filter((m) => !m.embedding);

  const opt = (m, sel) => `<option value="${esc(m.name)}"${
    m.name === sel ? " selected" : ""}>${esc(m.name)}${
    m.tools ? "  · model-led search" : ""}${m.hosted ? "  ⚠ hosted" : ""}</option>`;

  el.innerHTML = `
    <label class="field">
      <span class="field-label">Ollama address</span>
      <input id="cs-base" value="${esc(s.baseUrl)}" spellcheck="false">
      <span class="field-help">Default <code>${esc(defaultBase())}</code>. The atlas
        server calls it, not this page.</span>
    </label>

    <div class="field">
      <span class="field-label">Model
        <button class="link-btn" id="cs-refresh" type="button">refresh</button></span>
      ${chatModels.length
        ? `<select id="cs-model">
            <option value="">Choose a model…</option>
            ${chatModels.map((m) => opt(m, s.model)).join("")}
           </select>`
        : `<p class="note">${chat.connection === "down"
            ? "Ollama is not answering at that address."
            : "No models found. Try <code>ollama pull qwen3:8b</code>."}</p>`}
      <span class="field-help">Models marked <strong>· model-led search</strong>
        can call tools, so they choose when to search the dictionaries, what to
        look up and when they have enough — and every lookup is shown in the
        transcript. Without tools the assistant cannot search at all.</span>
      <span class="field-help">Models marked <strong>⚠ hosted</strong> are proxied
        by Ollama to its cloud. Only metadata is ever sent — variable names and
        dictionary labels — but with a hosted model that metadata leaves this
        machine. A local model sends nothing anywhere.</span>
    </div>

    <div class="field">
      <span class="field-label">Helper model</span>
      ${chatModels.length ? `<select id="cs-helper">
          <option value="">Same as the chat model</option>
          ${chatModels.map((m) => opt(m, s.helperModel)).join("")}
        </select>` : `<p class="note">No models available.</p>`}
      <span class="field-help">Fills in the draft after each reply, and rescues
        the answer buttons when a model doesn't mark its own. Small mechanical
        jobs — a smaller model here is quicker and the interview is unaffected.</span>
    </div>

    <label class="field">
      <span class="field-label">Temperature <em>${Number(s.temperature).toFixed(1)}</em></span>
      <input id="cs-temp" type="range" min="0" max="1" step="0.1" value="${esc(s.temperature)}">
      <span class="field-help">Low keeps the questions on the checklist.</span>
    </label>

    ${modelThinks() ? `<label class="field check">
      <input id="cs-think" type="checkbox"${s.think ? " checked" : ""}>
      <span>Let this model reason before answering</span>
      <span class="field-help">Off by default. “Which ${esc(wavePlural())} do you
        mean?” is not a question that gets better for half a minute of
        deliberation, and the wait is per turn.</span>
    </label>` : ""}

    <h3 class="section-title">Searching the dictionaries</h3>
    ${renderRetrieval(s)}

    <h3 class="section-title">This conversation</h3>
    <div class="draft-actions">
      <button class="btn btn-quiet" id="cs-reset" type="button">Start over</button>
    </div>
    <p class="note">Kept in this browser only. The conversation is posted to the
      atlas server on this machine, which calls Ollama; nothing else sees it.</p>`;

  $("#cs-base").addEventListener("change", (e) => {
    s.baseUrl = e.target.value.trim().replace(/\/+$/, "") || defaultBase();
    saveSettings(); connect();
  });
  $("#cs-model")?.addEventListener("change", (e) => {
    s.model = e.target.value; saveSettings(); renderStatus(); renderSettings();
    if (!chat.messages.length) renderTranscript();
  });
  $("#cs-helper")?.addEventListener("change", (e) => {
    s.helperModel = e.target.value; saveSettings();
  });
  $("#cs-temp").addEventListener("input", (e) => {
    s.temperature = Number(e.target.value); saveSettings();
    e.target.previousElementSibling.querySelector("em").textContent =
      s.temperature.toFixed(1);
  });
  $("#cs-think")?.addEventListener("change", (e) => {
    s.think = e.target.checked; saveSettings();
  });
  // Retrieval. The two checkboxes re-render because they enable and disable
  // the sliders under them; the sliders update their own label in place, so
  // that dragging one does not rebuild the panel under the cursor.
  const r = s.retrieval;
  $("#cs-semantic")?.addEventListener("change", (e) => {
    r.semantic = e.target.checked; saveSettings(); renderSettings();
  });
  $("#cs-expand")?.addEventListener("change", (e) => {
    r.expand = e.target.checked; saveSettings(); renderSettings();
  });
  const slider = (id, apply, show) => $(id)?.addEventListener("input", (e) => {
    apply(Number(e.target.value));
    saveSettings();
    e.target.previousElementSibling.querySelector("em").textContent = show(r);
  });
  slider("#cs-expansions", (v) => { r.expansions = v; }, (r) => String(r.expansions));
  slider("#cs-candidates", (v) => { r.candidates = v; }, (r) => String(r.candidates));
  slider("#cs-balance", (v) => {
    // One control, two weights: the slider is the share given to meaning.
    r.semanticWeight = v / 50;
    r.lexicalWeight = (100 - v) / 50;
  }, balance);

  $("#cs-refresh").addEventListener("click", connect);
  // Owned by the orchestrator; asked for by event so this module
  // never has to import back from chat.js.
  $("#cs-reset").addEventListener("click",
    () => window.dispatchEvent(new Event("atlas:chat-reset")));
}

export async function connect() {
  try {
    const { models, error } = await api("/api/models", { baseUrl: chat.settings.baseUrl });
    chat.models = models || [];
    chat.connection = error || !chat.models.length ? "down" : "ok";
    if (!chat.settings.model) {
      // The config names a preferred model; failing that, tool support is
      // the one thing the assistant cannot work without, so that decides
      // rather than where the model runs. Hosted models stay marked ⚠ in
      // the picker and behind the banner — which to use is a judgement
      // about the data, not one this can make.
      const wanted = A().state.dataset.assistant.model;
      const tooled = chat.models.filter((m) => !m.embedding && m.tools);
      chat.settings.model =
        (chat.models.find((m) => m.name === wanted && !m.embedding)
          || tooled[0] || chat.models.find((m) => !m.embedding))?.name || "";
    }
    saveSettings();
  } catch {
    chat.connection = "down";
    chat.models = [];
  }
  renderStatus();
  // Both the intro copy and the reasoning toggle depend on which model is
  // selected, and both are drawn before we know what that is.
  renderComposer();
  if (!chat.messages.length) renderTranscript();
  if (chat.panel === "settings") renderSettings();
}

/* ── Persistence ───────────────────────────────────────────────────── */
