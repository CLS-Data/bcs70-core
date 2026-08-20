/* The checklist strip, and the answer buttons under the transcript. */

import { $, $$ } from "./dom.js";
import { esc } from "./markup.js";
import { chat, firstUnsettled, saveSession, stepById } from "./state.js";

export function applyProgress(ev) {
  if (ev.covered && typeof ev.covered !== "object") return;
  // The server's map is authoritative for steps it mentions, because it is
  // the only thing that can REOPEN one — a researcher revising a settled
  // answer. Anything it does not mention keeps whatever was credited
  // optimistically on send.
  chat.covered = { ...chat.covered, ...(ev.covered || {}) };
  chat.step = firstUnsettled();
  renderChecklist();
  saveSession();
}

export function renderChecklist() {
  const el = $("#chat-steps");
  const steps = chat.interview?.steps;
  if (!el || !Array.isArray(steps)) return;
  el.innerHTML = steps.map((s, i) => {
    const done = Boolean(chat.covered[s.id]);
    const now = i === chat.step && !done;
    return `<button class="step${done ? " is-done" : ""}${now ? " is-now" : ""}"
      data-step="${i}" title="${esc(s.goal)}"
      aria-pressed="${now}">${esc(s.title)}</button>`;
  }).join("");
  const n = steps.filter((s) => chat.covered[s.id]).length;
  $("#chat-progress").textContent = `${n}/${steps.length} settled`;
  renderReplies();
}

/* Answers to the question actually asked come first — the model marks them
   inline as it writes, so they are ready the instant the prose is. Where
   there are none, fall back to the common answers for the step THE
   QUESTION was about, never the step the checklist has reached: those two
   drift apart routinely, and offering "a continuous number" in reply to
   "which waves?" is worse than offering nothing at all. */
export function renderReplies() {
  const el = $("#chat-replies");
  if (!el || !chat.interview) return;

  // Hidden only until the reply's own choices arrive. The draft extraction
  // that runs afterwards is nobody's business here.
  if (!chat.messages.length || (chat.busy && !chat.answered)) {
    el.hidden = true;
    return;
  }

  const direct = chat.options?.length ? chat.options : null;
  const asked = chat.askedStep ? stepById(chat.askedStep) : null;
  const fallback = direct ? null : (asked?.replies || null);

  const rows = direct || fallback || [];
  // With nothing to offer there is nothing to draw. The composer below is
  // the answer, and a header over an empty list only takes up room.
  if (!rows.length) { el.hidden = true; return; }

  el.innerHTML = `
    <p class="choices-head">${direct
      ? "Pick an answer, or say something else below"
      : `Common answers on ${esc(asked.title.toLowerCase())}, or say something else below`}</p>
    <ul class="choice-list">
      ${rows.map((text, i) => `
        <li><button class="choice" data-reply="${esc(text)}" data-n="${i + 1}">
          <span class="choice-key">${i < 9 ? i + 1 : "·"}</span>
          <span class="choice-text">${esc(text)}</span>
        </button></li>`).join("")}
    </ul>
    <p class="choices-hint"><kbd>↑</kbd><kbd>↓</kbd> choose · <kbd>⏎</kbd> send</p>`;
  el.hidden = false;
}

// Roving focus over real buttons, so Enter, Tab and screen readers all work
// without being reimplemented.
export function moveChoice(dir, from) {
  const items = $$("#chat-replies .choice");
  if (!items.length) return;
  const at = items.indexOf(from);
  const next = at < 0
    ? (dir > 0 ? 0 : items.length - 1)
    : (at + dir + items.length) % items.length;
  items[next].focus();
}
