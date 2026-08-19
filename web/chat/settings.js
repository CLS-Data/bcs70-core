/* Choosing a model, and finding out which are available. */

import { $ } from "./dom.js";
import { api } from "./api.js";
import { esc } from "./markup.js";
import { A, chat, defaultBase, modelThinks, saveSettings, wavePlural } from "./state.js";
import { renderComposer, renderStatus } from "./composer.js";
import { renderTranscript } from "./transcript.js";

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
