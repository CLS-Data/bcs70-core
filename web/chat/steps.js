/* The checklist strip, and the answer buttons under the transcript. */

import { $, $$ } from "./dom.js";
import { esc } from "./markup.js";
import { allSettled, chat, firstUnsettled, saveSession, showsChecklist, stepById } from "./state.js";

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

  // Nothing to show until a request is actually being worked on. A checklist
  // over a conversation that is only asking questions promises an interview
  // nobody started, and counts six things unanswered that were never asked.
  const strip = $("#chat-strip");
  if (strip) strip.hidden = !showsChecklist();

  renderStop();

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

/* The way out of a sticky intent.

   A button rather than a phrase, because the phrase rule is the courtesy
   path: it cannot be certain, and in a mode you stay in, being wrong about
   an exit is expensive in both directions. This is instant and local — the
   server named where a stop lands in the `mode` event, so there is nothing
   to ask it and nothing to guess. */
export function renderStop() {
  const el = $("#chat-stop");
  if (!el) return;
  el.hidden = !chat.sticky;
}

export function stopInterview() {
  if (!chat.sticky) return;
  chat.mode = chat.exitsTo || "";
  chat.sticky = false;
  chat.awaiting = "";
  chat.options = [];
  chat.askedStep = null;
  // Said out loud in the transcript, and carried back to the model with it.
  // A mode that changes silently leaves a conversation whose next reply
  // makes no sense against anything the reader can see.
  chat.messages.push({
    role: "assistant",
    content: "Stopped working on the request. Everything settled so far is "
      + "kept — open **Draft** to read it back, or say what you would like "
      + "to derive whenever you want to pick it up again.",
  });
  saveSession();
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

  // The assistant's last message says to open the Draft. Saying it is not
  // the same as offering it: the panel tab sits at the top of the drawer,
  // away from where the conversation just ended. Prepended rather than
  // returned early, because a completing turn may still have asked a real
  // question, and its own buttons are not this action's to swallow.
  // Not until the turn is fully over. `draft` lands after the reply, it is
  // what settles the last step, and it can still REOPEN one when the
  // extractor reports a revision — so offering the Draft while "Updating the
  // draft" is still running risks showing it a beat before it is true, and
  // taking it away again.
  const done = allSettled() && !chat.busy ? `
    <button class="choice is-go" data-open-draft>
      <span class="choice-key">→</span>
      <span class="choice-text">Open the Draft to review it and file it</span>
    </button>` : "";

  const direct = chat.options?.length ? chat.options : null;
  // Stock answers belong to a question. With the checklist complete there is
  // none, whatever step the last turn happened to name — and the name stuck
  // in localStorage, so without this the offer survived a reload and there
  // was no way out of it but a reset.
  const asked = chat.askedStep && !allSettled() ? stepById(chat.askedStep) : null;
  const fallback = direct ? null : (asked?.replies || null);

  const rows = direct || fallback || [];
  // With nothing to offer there is nothing to draw. The composer below is
  // the answer, and a header over an empty list only takes up room.
  if (!rows.length && !done) { el.hidden = true; return; }

  if (!rows.length) {
    el.innerHTML = `<p class="choices-head">The request is complete</p>${done}
      <p class="choices-hint">or say something below to change any of it</p>`;
    el.hidden = false;
    return;
  }

  el.innerHTML = `${done}
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
