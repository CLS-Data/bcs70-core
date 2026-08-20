/* The bottom of the drawer: pinned variables, the box, the reasoning toggle,
   and the connection dot in the header. */

import { $ } from "./dom.js";
import { esc } from "./markup.js";
import { chat, capitaliseWave, modelBy, modelThinks, modelUsesTools } from "./state.js";
import { renderReplies } from "./steps.js";

export function renderPinned() {
  const el = $("#chat-pinned");
  if (!el) return;
  el.innerHTML = chat.pinned.map((p, i) => `
    <span class="pinchip${p.kind === "derived" ? " is-derived" : ""}"
          title="${esc(p.label || "")}${p.kind === "derived" ? " — precedent, not a source" : ""}">
      <span class="pinchip-name">${esc(p.name)}</span>
      <span class="pinchip-wave">${esc(p.kind === "derived" ? "derived" : p.wave)}</span>
      <button data-unpin="${i}" aria-label="Unpin ${esc(p.name)}">✕</button>
    </span>`).join("");
  el.hidden = chat.pinned.length === 0;
}

export function renderComposer() {
  const waiting = chat.busy && !chat.answered;
  $("#chat-send").hidden = waiting;
  $("#chat-stop").hidden = !waiting;
  renderThinkToggle();
  // Once the picker is carrying the likely answers, the box is for the ones
  // it did not think of — so it should say that rather than repeat the
  // opening invitation for the rest of the conversation.
  $("#chat-input").placeholder = chat.messages.length
    ? "Something else…"
    : "Describe the variable you want…";
  renderReplies();
}

/* Reasoning is off by default and belongs next to Send, not three panels
   away in Setup: it is the one setting worth changing mid-conversation,
   because whether a question deserves half a minute of deliberation depends
   on the question. Absent entirely on models that cannot do it. */
export function renderThinkToggle() {
  const btn = $("#chat-think");
  if (!btn) return;
  const can = modelThinks();
  btn.hidden = !can;
  if (!can) return;
  const on = Boolean(chat.settings.think);
  btn.classList.toggle("is-on", on);
  btn.setAttribute("aria-pressed", String(on));
  btn.textContent = on ? "reasoning on" : "reasoning off";
  btn.title = on
    ? "The model reasons before answering. Slower per turn; the working is "
      + "kept, collapsed, under each reply."
    : "The model answers directly. Faster, and enough for most of these questions.";
}

export function renderStatus() {
  const dot = $("#chat-status");
  if (!dot) return;
  const model = modelBy(chat.settings.model);
  const remote = Boolean(model?.hosted);
  dot.className = `chat-status is-${chat.connection}${remote ? " is-remote" : ""}`;
  dot.title = chat.connection === "ok"
    ? (remote ? `${chat.settings.model} — hosted by Ollama, not local`
              : `${chat.settings.model} — running locally`)
    : chat.connection === "down" ? "Ollama not reachable" : "Not connected yet";
  $("#chat-remote-warn").hidden = !remote;

  // Who is driving the search is the biggest behavioural difference between
  // two models here, and it is invisible unless it is said.
  const mode = $("#chat-mode");
  const agentic = modelUsesTools();
  mode.hidden = chat.connection !== "ok" || !chat.settings.model;
  mode.textContent = agentic ? "model-led search" : "no tools";
  mode.className = `chat-mode${agentic ? " is-agentic" : ""}`;
  mode.title = agentic
    ? "This model decides when to search the dictionaries, what to look up, " +
      "and when it has enough. Every lookup is shown in the transcript."
    : "This model cannot call tools, so it cannot search the dictionaries. " +
      "Pick a tools-capable model in Setup.";
}
