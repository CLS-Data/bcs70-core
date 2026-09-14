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
             value="${esc(String(meaningShare(r)))}"
             ${sem.available && r.semantic ? "" : " disabled"}>
      <span class="field-help">Which side wins when the two disagree. Exact
        names and codes come from words; concepts come from meaning.</span>
    </label>`;
}

/* The slider's position: the share of the fusion given to meaning. */
function meaningShare(r) {
  return Math.round(100 * r.semanticWeight /
    ((r.lexicalWeight + r.semanticWeight) || 1));
}

function balance(r) {
  const pct = meaningShare(r);
  if (pct <= 20) return "mostly words";
  if (pct >= 80) return "mostly meaning";
  if (pct === 50) return "even";
  return pct > 50 ? "leaning meaning" : "leaning words";
}

/* Is it connected, and if not, what do you type?

   This used to be an address box with a default underneath, and a model list
   that said "Ollama is not answering at that address" when it wasn't. Both are
   true and neither tells you what to do about it — whether the trouble is that
   Ollama is not running, that it is on another port, or that it is running
   with nothing pulled. Each of those has one command, so say which. */
function connectionPanel(s, chatModels) {
  const model = A().state.dataset.assistant.model;

  if (chat.connection === "ok" && chatModels.length) {
    return `<div class="cs-state is-ok">
      <span class="cs-dot"></span>
      <span>Connected to Ollama at <code>${esc(s.baseUrl)}</code> —
        ${chatModels.length} model${chatModels.length === 1 ? "" : "s"} available.
        <button class="link-btn" id="cs-edit">change address</button></span>
    </div>
    ${addressField(s, true)}`;
  }

  // Reachable but empty: the address is right, the machine has nothing to run.
  if (chat.connection === "ok") {
    return `<div class="cs-state is-warn">
      <span class="cs-dot"></span>
      <span>Ollama is answering at <code>${esc(s.baseUrl)}</code> but has no
        models. Pull one:</span>
    </div>
    <pre class="cs-cmd">ollama pull ${esc(model)}</pre>
    <p class="note">Then press <strong>refresh</strong> below.</p>
    ${addressField(s, false)}`;
  }

  return `<div class="cs-state is-down">
    <span class="cs-dot"></span>
    <span>No Ollama at <code>${esc(s.baseUrl)}</code>. Start it:</span>
  </div>
  <pre class="cs-cmd">ollama serve</pre>
  <p class="note">If it is already running somewhere else — another port, or
    another machine on your network — put that address in below. The atlas
    server on this machine makes the call, so the address has to be one it can
    reach, not one this browser can.</p>
  ${addressField(s, false)}`;
}

/* The address box. Hidden behind a link once connected: it is the first thing
   you need and then never again, and leaving it open invites editing a setting
   that is already right. */
function addressField(s, connected) {
  return `<label class="field cs-address"${connected ? " hidden" : ""}>
    <span class="field-label">Ollama address</span>
    <input id="cs-base" value="${esc(s.baseUrl)}" spellcheck="false"
           placeholder="${esc(defaultBase())}">
    <span class="field-help">Default <code>${esc(defaultBase())}</code>.</span>
  </label>`;
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
    ${connectionPanel(s, chatModels)}

    <div class="field">
      <span class="field-label">Model
        <button class="link-btn" id="cs-refresh" type="button">refresh</button></span>
      ${chatModels.length
        ? `<select id="cs-model">
            <option value="">Choose a model…</option>
            ${chatModels.map((m) => opt(m, s.model)).join("")}
           </select>`
        : ""}
      ${chatModels.length ? `<span class="field-help">Models marked
        <strong>· model-led search</strong> can call tools, so they choose when
        to search the dictionaries and what to look up — every lookup is shown
        in the transcript. Without tools the assistant cannot search at all.
        Models marked <strong>⚠ hosted</strong> are proxied by Ollama to its
        cloud: only metadata is ever sent, but it does leave this machine.</span>`
        : ""}
    </div>

    <details class="cs-more"${s.model ? "" : " open"}>
      <summary>Tuning</summary>

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
    </details>

    <h3 class="section-title">This conversation</h3>
    <div class="draft-actions">
      <button class="btn btn-quiet" id="cs-reset" type="button">Start over</button>
    </div>
    <p class="note">Kept in this browser only. The conversation is posted to the
      atlas server on this machine, which calls Ollama; nothing else sees it.</p>`;

  $("#cs-edit")?.addEventListener("click", () => {
    const field = el.querySelector(".cs-address");
    if (field) { field.hidden = false; field.querySelector("input").focus(); }
  });
  $("#cs-base")?.addEventListener("change", (e) => {
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
