/* ==========================================================================
   Variable atlas — the assistant, browser side.

   This file runs one turn and wires the drawer up. Everything it draws lives
   in ./chat/: the conversation state, the API client, and one module per
   panel. Everything it *asks* — the interview, the prompts, the tools, the
   retrieval — lives in web/assistant/ and is reached over /api.

   The server is stateless. This side holds the conversation, persists it to
   localStorage, and posts it back each turn.
   ========================================================================== */

import { $, $$ } from "./chat/dom.js";
import { api, streamTurn } from "./chat/api.js";
import { esc } from "./chat/markup.js";
import { A, DRAG_MIME, chat, creditStep, defaultBase, emptyDraft, helperThinks, key, modelThinks, modelUsesTools, restore, saveSession, saveSettings } from "./chat/state.js";
import { renderStreaming, renderTranscript } from "./chat/transcript.js";
import { applyProgress, moveChoice, renderChecklist, renderReplies, stopInterview } from "./chat/steps.js";
import { renderComposer, renderPinned, renderStatus, renderThinkToggle } from "./chat/composer.js";
import { renderDraft } from "./chat/draft.js";
import { connect, renderSettings } from "./chat/settings.js";

async function send(text) {
  // Once the reply and its choices are in you may answer straight away; the
  // draft extraction still running is left to finish in the background
  // rather than aborted. It is what advances the checklist, and cancelling
  // it every time someone answered promptly froze the interview on step one
  // — the model was told "current step: Concept" on every turn and ended up
  // restating the concept instead of moving on.
  if (chat.busy && !chat.answered) return;
  if (!chat.settings.model) { setPanel("settings"); return; }

  const turn = ++chat.turn;
  const mine = () => turn === chat.turn;

  // Credit the step the question was ABOUT, as the answer is sent, rather
  // than waiting for the draft extraction that lands after the next reply.
  // Without the optimistic credit the model is told "current step: Concept"
  // for the whole conversation and repeats itself; without using the asked
  // step it credits whichever step happens to be next, so answering one
  // question ticked another off. A message that is itself a question is not
  // an answer, so it credits nothing.
  // Only when the server named the step its question was about. A question
  // about the data names none, so asking one never counts as answering a
  // checklist question — and neither does saying yes to an offer to start,
  // which is asked before there is any interview to credit.
  creditStep(chat.askedStep);

  chat.messages.push({ role: "user", content: text });
  chat.busy = true;
  chat.answered = false;
  chat.phase = "thinking";
  // `mode` and `awaiting` are NOT cleared here. They used to be, when the
  // server decided the intent afresh every message and the browser only had
  // to display the answer. They are now what the server is told, and a
  // sticky intent forgotten on send is not sticky at all.
  chat.options = [];
  chat.askedStep = null;
  chat.agent = null;
  chat.tool = null;
  chat.abort = new AbortController();
  const signal = chat.abort.signal;
  renderTranscript();
  renderComposer();

  // Rebuilt from the event stream as it arrives, so the transcript this
  // file holds is exactly what the server saw.
  let reply = null;
  let sawDraft = false;
  const openReply = () => {
    if (reply) return reply;
    // Stamped with whoever is speaking, so the transcript still says which
     // agent answered long after the mode event has been replaced.
    reply = { role: "assistant", content: "", thinking: "", agent: chat.agent };
    chat.messages.push(reply);
    return reply;
  };

  try {
    for await (const ev of streamTurn({
      messages: chat.messages.filter((m) => m !== reply),
      pinned: chat.pinned,
      covered: chat.covered,
      draft: chat.draft,
      // The server keeps nothing between turns, so where the conversation
      // had got to comes back with it.
      mode: chat.mode,
      awaiting: chat.awaiting,
      baseUrl: chat.settings.baseUrl,
      model: chat.settings.model,
      helperModel: chat.settings.helperModel,
      temperature: Number(chat.settings.temperature) || 0,
      think: Boolean(chat.settings.think),
      agentic: modelUsesTools(),
      modelThinks: modelThinks(),
      helperThinks: helperThinks(),
      retrieval: chat.settings.retrieval || undefined,
    }, signal)) {
      // A superseded turn keeps only what ratchets: its draft was computed
      // from a real prefix of this conversation, so its checklist progress
      // is still true, while its transcript and draft body are stale.
      if (!mine()) { if (ev.type === "draft") applyProgress(ev); continue; }
      handleEvent(ev, openReply, () => { reply = null; });
      if (ev.type === "draft") sawDraft = true;
    }
  } catch (err) {
    if (!mine()) return;
    if (err?.name === "AbortError") {
      const last = chat.messages[chat.messages.length - 1];
      if (last?.role === "assistant") {
        last.content += last.content ? "\n\n_(stopped)_" : "_(stopped)_";
      }
    } else {
      // The transcript gets a sentence; the console gets the stack. An
      // unexpected client-side fault is otherwise indistinguishable from a
      // model or network failure, and reads to the user as neither.
      console.error("Assistant turn failed:", err);
      chat.messages.push({
        role: "assistant", content: "",
        error: String(err.message || err),
        // Carried into the transcript, not just the console. A fault in this
        // file reads to the user as a model or network problem, and asking
        // someone to open devtools to find out otherwise is asking too much.
        stack: String(err?.stack || ""),
      });
      chat.connection = "down";
      renderStatus();
    }
  } finally {
    if (mine()) {
      // If the draft never landed — it failed, or this turn was superseded
      // — credit the step just answered anyway. A checklist that can stall
      // is worse than one that occasionally runs a step early, because a
      // stalled one silently repeats the same question forever.
      chat.busy = false;
      chat.answered = false;
      chat.phase = "";
      chat.abort = null;
      renderTranscript();
      renderComposer();
      renderChecklist();
      renderDraft();
      saveSession();
    }
  }
}

function handleEvent(ev, openReply, closeReply) {
  switch (ev.type) {
    case "thinking":
      openReply().thinking += ev.text;
      break;

    case "content": {
      const r = openReply();
      const first = !r.content;
      r.content += ev.text;
      // Once words are arriving there is nothing to wait for; the text
      // itself is the progress indicator.
      if (first) { chat.phase = ""; renderTranscript(); }
      renderStreaming(r);
      break;
    }

    case "tool_call":
      // The card is drawn when the result lands; until then the indicator
      // names the lookup and what was asked of it, so a slow search is
      // legible rather than a spinner.
      chat.tool = { name: ev.name, args: ev.args || {} };
      chat.phase = "searching";
      renderTranscript();
      break;

    case "tool_result": {
      const r = openReply();
      (r.tool_calls ||= []).push({
        function: { name: ev.name, arguments: ev.args },
      });
      closeReply();
      // `content` is what the MODEL read, and it is posted back next turn so
      // the conversation's own history says what each lookup returned.
      // Without it every tool call in the history was paired with an empty
      // result, and a model reading that searches the same thing again — or
      // reports a concept as absent because its record of finding it is blank.
      // `display` is the same result drawn for the reader.
      chat.messages.push({
        role: "tool", name: ev.name, args: ev.args,
        content: ev.text || "", display: ev.display,
      });
      chat.tool = null;
      chat.phase = "thinking";
      renderTranscript();
      break;
    }

    case "mode":
      chat.mode = ev.mode;
      chat.modeLabel = ev.label || "";
      // Absent means "assume it advanced", so an older server that does not
      // send this marks nothing rather than marking every turn.
      chat.modeAdvances = ev.advances !== false;
      chat.sticky = ev.sticky === true;
      chat.awaiting = ev.awaiting || "";
      chat.exitsTo = ev.exitsTo || "";
      // Held for the whole turn: `openReply` stamps it onto the message, and
      // the working row shows it before any words arrive.
      chat.agent = { id: ev.mode, label: ev.label || ev.mode };
      // The strip appears the moment an interview begins and carries the way
      // out of it, so it is redrawn here rather than only when a step lands.
      renderChecklist();
      renderTranscript();
      break;

    case "options":
      // The conversational half of the turn is over. Everything after this
      // is the draft catching up, which must not hold the answer buttons
      // or the composer hostage.
      chat.options = Array.isArray(ev.options) ? ev.options : [];
      chat.askedStep = ev.step || null;
      chat.answered = true;
      chat.phase = "drafting";
      renderComposer();
      renderTranscript();
      break;

    case "draft":
      // Shapes off the wire are checked, not assumed. `separate` arriving as
      // anything other than a list used to reach `.map` and take the whole
      // turn down with a message that pointed at the model.
      chat.phase = "";
      chat.draft = { ...emptyDraft(), ...(ev.draft || {}),
                     notesTouched: chat.draft.notesTouched };
      chat.separate = Array.isArray(ev.separate) ? ev.separate : [];
      chat.knownVars = ev.sourceVarsKnown || null;
      applyProgress(ev);
      renderDraft();
      break;

    case "draft_failed":
      console.warn("Draft extraction failed:", ev.message);
      break;

    case "error": {
      const r = openReply();
      r.error = ev.message;
      r.status = ev.status;
      renderTranscript();
      break;
    }

    default:
      break;
  }
}

/* ── Search command ────────────────────────────────────────────────── */

async function runSearch(query) {
  const msg = { role: "tool", name: "search_variables", args: { query },
                content: "", display: null };
  chat.messages.push(msg);
  renderTranscript();
  try {
    const found = await api("/api/search", { query, limit: 15 });
    msg.display = { groups: found.groups || [], note: "lexical" };
  } catch (err) {
    msg.display = { groups: [], note: `search failed: ${err.message || err}` };
  }
  renderTranscript();
  saveSession();
}

/* ── Pinning ───────────────────────────────────────────────────────── */

/* Two kinds of thing can be pinned, and conflating them would be a real
   error: a raw variable is a candidate SOURCE for the new derivation, a
   harmonised one is a PRECEDENT to follow. Only the first belongs in the
   issue's source-variable list. */
function pin(item) {
  if (!item?.name) return;
  if (chat.pinned.some((p) => p.name === item.name && p.file === item.file)) return;
  chat.pinned.push({
    kind: item.kind === "derived" ? "derived" : "variable",
    name: item.name, label: item.label || "", file: item.file || "",
    wave: item.wave || "",
  });
  if (item.kind !== "derived" && !chat.draft.source_vars.includes(item.name)) {
    chat.draft.source_vars.push(item.name);
  }
  renderPinned();
  renderDraft();
  saveSession();
}

function unpin(i) {
  chat.pinned.splice(i, 1);
  renderPinned();
  saveSession();
}

/* ── Rendering ─────────────────────────────────────────────────────── */

/* Choosing sends. Anything already typed is folded in rather than thrown
   away — an answer half-written in the box and then a click on an option
   means both, not one instead of the other. */
function useChoice(text) {
  const input = $("#chat-input");
  const typed = input.value.trim();
  input.value = "";
  input.style.height = "auto";
  send(typed ? `${typed} — ${text}` : text);
}

function resetSession() {
  chat.messages = [];
  chat.pinned = [];
  chat.draft = emptyDraft();
  chat.covered = {};
  chat.step = 0;
  chat.separate = [];
  chat.options = [];
  chat.askedStep = null;
  chat.knownVars = null;
  chat.mode = "";
  chat.sticky = false;
  chat.awaiting = "";
  chat.exitsTo = "";
  chat.agent = null;
  chat.tool = null;
  saveSession();
  renderTranscript(); renderPinned(); renderChecklist(); renderDraft();
  renderComposer();
  setPanel("chat");
}

/* ── Panel plumbing ────────────────────────────────────────────────── */

/* Why the assistant is unavailable, once `start` has found out; "" while it
   still works. Read by setOpen and by the two entry points the atlas calls. */
let disabled = "";

function setOpen(open) {
  chat.open = open;
  document.body.classList.toggle("chat-open", open);
  $("#chat-drawer").hidden = !open;
  $("#chat-toggle").setAttribute("aria-expanded", String(open));
  try { localStorage.setItem(key("chat-open"), open ? "1" : ""); } catch { /* fine */ }
  if (open && !disabled) {
    if (chat.connection === "unknown") connect();
    $("#chat-input")?.focus();
  }
}

function setPanel(name) {
  chat.panel = name;
  $$("#chat-drawer [data-panel]").forEach((el) => { el.hidden = el.dataset.panel !== name; });
  $$("#chat-drawer [data-panel-tab]").forEach((el) => {
    const on = el.dataset.panelTab === name;
    el.classList.toggle("is-current", on);
    el.setAttribute("aria-pressed", String(on));
  });
  if (name === "settings") renderSettings();
  if (name === "draft") renderDraft();
  // The line above unhides everything belonging to this panel, the strip
  // included — and whether the strip belongs on screen is not a question
  // about which panel is showing. Re-deciding it here is what stops a return
  // from Draft revealing an empty checklist.
  if (name === "chat") renderChecklist();
}

/* ── Drag and drop ─────────────────────────────────────────────────── */

function wireDrop() {
  const drawer = $("#chat-drawer");
  let depth = 0;
  const accepts = (e) => [...(e.dataTransfer?.types || [])].includes(DRAG_MIME);

  // Opening on drag is the whole point of a docked panel: you should not have
  // to set the variable down, open the assistant, and go back for it. But the
  // drawer is no longer the only target — the R bundle dock is the other — so
  // an auto-open is provisional: if the drag ends anywhere but in here, the
  // drawer goes back to however the researcher had left it.
  let autoOpened = false;

  document.addEventListener("dragstart", (e) => {
    const src = e.target.closest?.("[data-drag]");
    if (!src) return;
    e.dataTransfer.setData(DRAG_MIME, src.dataset.drag);
    e.dataTransfer.setData("text/plain", JSON.parse(src.dataset.drag).name || "");
    e.dataTransfer.effectAllowed = "copy";
    if (!chat.open) { setOpen(true); autoOpened = true; }
    document.body.classList.add("is-dragging-var");
  });

  document.addEventListener("dragend", () => {
    document.body.classList.remove("is-dragging-var");
    drawer.classList.remove("is-dropping");
    depth = 0;
    if (autoOpened) { setOpen(false); autoOpened = false; }
  });

  drawer.addEventListener("dragenter", (e) => {
    if (!accepts(e)) return;
    e.preventDefault(); depth++; drawer.classList.add("is-dropping");
  });
  drawer.addEventListener("dragover", (e) => {
    if (!accepts(e)) return;
    e.preventDefault(); e.dataTransfer.dropEffect = "copy";
  });
  drawer.addEventListener("dragleave", () => {
    if (--depth <= 0) drawer.classList.remove("is-dropping");
  });
  drawer.addEventListener("drop", (e) => {
    if (!accepts(e)) return;
    e.preventDefault(); depth = 0;
    drawer.classList.remove("is-dropping");
    autoOpened = false;   // it was dropped in here after all, so it stays open
    try { pin(JSON.parse(e.dataTransfer.getData(DRAG_MIME))); }
    catch { /* something else was dropped */ }
  });
}

function wireResize() {
  const grip = $("#chat-grip");
  let startX = 0, startW = 0;
  const move = (e) => {
    const w = Math.min(720, Math.max(320, startW + (startX - e.clientX)));
    document.documentElement.style.setProperty("--chat-w", `${w}px`);
  };
  const up = () => {
    document.removeEventListener("pointermove", move);
    document.removeEventListener("pointerup", up);
    try {
      localStorage.setItem(key("chat-w"),
        getComputedStyle(document.documentElement).getPropertyValue("--chat-w"));
    } catch { /* fine */ }
  };
  grip.addEventListener("pointerdown", (e) => {
    startX = e.clientX;
    startW = $("#chat-drawer").offsetWidth;
    document.addEventListener("pointermove", move);
    document.addEventListener("pointerup", up);
    e.preventDefault();
  });
  try {
    const w = localStorage.getItem(key("chat-w"));
    if (w) document.documentElement.style.setProperty("--chat-w", w.trim());
  } catch { /* fine */ }
}

/* ── Wiring ────────────────────────────────────────────────────────── */

/* A transient line beside Send, for the one thing that happens without a
   message in the transcript: a send refused because the last turn is still
   running. */
let noteTimer;
function note(text) {
  const el = $("#chat-note");
  if (!el) return;
  el.textContent = text;
  clearTimeout(noteTimer);
  noteTimer = setTimeout(() => { el.textContent = ""; }, 4000);
}

function submit() {
  const input = $("#chat-input");
  const text = input.value.trim();
  if (!text) return;

  // A turn that has not yet spoken will refuse this. Find that out BEFORE
  // clearing the box: it used to empty it either way, so a message typed
  // while the model was still thinking vanished with nothing to say why.
  if (chat.busy && !chat.answered) {
    note("Still working on the last message — press Send again when it replies.");
    return;
  }

  input.value = "";
  input.style.height = "auto";

  const slash = text.match(/^\/(\w+)\s*([\s\S]*)$/);
  if (slash) {
    const [, cmd, rest] = slash;
    if (cmd === "search") { if (rest) runSearch(rest); return; }
    if (cmd === "clear") return resetSession();
    if (cmd === "draft") return setPanel("draft");
    if (cmd === "model") return setPanel("settings");
  }
  send(text);
}

function wireUp() {
  $("#chat-toggle").addEventListener("click", () => setOpen(!chat.open));
  $("#chat-close").addEventListener("click", () => setOpen(false));
  $$("#chat-drawer [data-panel-tab]").forEach((b) =>
    b.addEventListener("click", () => setPanel(b.dataset.panelTab)));

  /* Reset asks twice. Not a modal — the button becomes the confirmation and
     reverts if you leave it alone, which costs one click when you meant it
     and nothing at all when you didn't. A transcript is cheap to lose but
     the draft built from it is not. */
  const reset = $("#chat-reset");
  let armed = null;
  const disarm = () => {
    clearTimeout(armed); armed = null;
    reset.textContent = "⟲";
    reset.classList.remove("is-armed");
    reset.title = "Start a new conversation";
  };
  reset.addEventListener("click", () => {
    if (armed) { disarm(); resetSession(); return; }
    if (!chat.messages.length && !chat.pinned.length) return;
    reset.textContent = "sure?";
    reset.classList.add("is-armed");
    reset.title = "Click again to discard this conversation and its draft";
    armed = setTimeout(disarm, 4000);
  });

  const input = $("#chat-input");
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); submit(); }
  });
  input.addEventListener("input", () => {
    input.style.height = "auto";
    input.style.height = `${Math.min(180, input.scrollHeight)}px`;
  });

  $("#chat-think").addEventListener("click", () => {
    chat.settings.think = !chat.settings.think;
    saveSettings();
    renderThinkToggle();
  });

  $("#chat-send").addEventListener("click", submit);
  $("#chat-stop").addEventListener("click", () => chat.abort?.abort());
  $("#chat-search").addEventListener("click", () => {
    const text = input.value.trim();
    if (text) { input.value = ""; runSearch(text); } else input.focus();
  });

  $("#chat-log").addEventListener("click", (e) => {
    const seed = e.target.closest("[data-seed]");
    if (seed) { input.value = seed.dataset.seed; submit(); return; }
    const p = e.target.closest("[data-pin]");
    if (p) { pin(JSON.parse(p.dataset.pin)); p.textContent = "pinned"; p.disabled = true; return; }

    // A name the assistant surfaced is a link into the atlas. The drawer
    // stays open beside it, so the transcript and the variable are readable
    // together rather than one replacing the other.
    const v = e.target.closest("[data-open]");
    if (v) {
      const { name, wave } = JSON.parse(v.dataset.open);
      if (!A().openVariable(name, wave)) {
        v.title = `${name} is not in the dictionaries`;
        v.classList.add("is-missing");
      }
      return;
    }
    const d = e.target.closest("[data-derived]");
    if (d && !A().openDerived(d.dataset.derived)) {
      d.classList.add("is-missing");
    }
  });

  // Search hits inside the transcript are themselves draggable, so a result
  // the assistant found can be pinned the same way one from the list is.
  $("#chat-log").addEventListener("dragstart", (e) => {
    const hit = e.target.closest("[data-hit]");
    if (!hit) return;
    e.dataTransfer.setData(DRAG_MIME, hit.dataset.hit);
    e.dataTransfer.effectAllowed = "copy";
  });

  $("#chat-pinned").addEventListener("click", (e) => {
    const b = e.target.closest("[data-unpin]");
    if (b) unpin(Number(b.dataset.unpin));
  });

  const choices = $("#chat-replies");
  choices.addEventListener("click", (e) => {
    if (e.target.closest("[data-open-draft]")) return setPanel("draft");
    const b = e.target.closest("[data-reply]");
    if (b) useChoice(b.dataset.reply);
  });
  choices.addEventListener("keydown", (e) => {
    const b = e.target.closest(".choice");
    if (e.key === "ArrowDown") { e.preventDefault(); moveChoice(1, b); return; }
    if (e.key === "ArrowUp") { e.preventDefault(); moveChoice(-1, b); return; }
    if (e.key === "Escape") { e.preventDefault(); input.focus(); return; }
    if (/^[1-9]$/.test(e.key)) {
      const pick = $(`#chat-replies .choice[data-n="${e.key}"]`);
      if (pick) { e.preventDefault(); useChoice(pick.dataset.reply); }
    }
  });

  // Up-arrow out of an empty composer reaches for the list — the same
  // gesture as recalling the last thing you typed, which is roughly what it
  // is doing.
  input.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowUp" || choices.hidden) return;
    if (input.selectionStart !== 0 || input.selectionEnd !== 0) return;
    e.preventDefault();
    moveChoice(-1, null);
  });

  $("#chat-stop").addEventListener("click", () => {
    stopInterview();
    renderChecklist();
    renderTranscript();
    renderComposer();
  });

  $("#chat-steps").addEventListener("click", (e) => {
    const b = e.target.closest("[data-step]");
    if (!b) return;
    // Jumping back is allowed and does not un-settle anything — it just
    // says "ask me about this one again".
    chat.step = Number(b.dataset.step);
    const step = (chat.interview?.steps || [])[chat.step];
    if (step) chat.covered[step.id] = false;
    renderChecklist();
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && chat.open && !chat.busy) {
      if (document.activeElement === $("#chat-input")) return;
      setOpen(false);
    }
    if ((e.metaKey || e.ctrlKey) && e.key === "j") {
      e.preventDefault(); setOpen(!chat.open);
    }
  });

  wireDrop();
  wireResize();
}

/* ── Boot ──────────────────────────────────────────────────────────── */

async function start() {
  restore();
  if (!chat.settings.baseUrl) chat.settings.baseUrl = defaultBase();
  // Turn the drawer off cleanly in the two cases where it cannot work, and
  // say which one it is: no API at all (a static deploy such as GitHub Pages,
  // or anything served by something other than web/server.py), or an API whose
  // assistant extra was never installed.
  //
  // Off is a state of the drawer, not a dead button. A disabled toggle said
  // nothing a visitor could read and stopped none of the other ways in - Pin
  // to assistant opened the drawer through AtlasChat.open(), and since the
  // close button was never wired there was then no way back out. So the
  // drawer still opens and still closes; CSS empties it of everything but
  // the reason, and the entry points that would do nothing are hidden.
  const off = (why) => {
    disabled = why;
    document.body.classList.add("chat-off");
    const note = $("#chat-dead");
    note.textContent = why;
    note.hidden = false;
    $("#chat-toggle").title = why;
    $("#chat-toggle").addEventListener("click", () => setOpen(!chat.open));
    $("#chat-close").addEventListener("click", () => setOpen(false));
  };
  try {
    const health = await fetch("/api/health").then((r) => r.json());
    if (!health.assistant) {
      return off("The assistant's dependencies aren't installed. " +
                 "Run: uv sync --extra assistant");
    }
    // Whether there is a semantic index, and what the configured retrieval
    // defaults are. Both come from the server so the drawer never holds a
    // second copy of dataset.toml.
    chat.semantic = health.semantic || { available: false };
    if (!chat.settings.retrieval && health.retrieval) {
      chat.settings.retrieval = { ...health.retrieval };
      saveSettings();
    }

    chat.interview = await fetch("/api/interview").then((r) => r.json());
    // Checked here, once, rather than trusted. A payload without steps used
    // to surface as "cannot read properties of undefined" partway through a
    // conversation — a mystery pointing at the model, when the cause was
    // the API. Usually it means an older server process is still running.
    if (!Array.isArray(chat.interview?.steps) || !chat.interview.steps.length) {
      return off("The assistant's interview definition didn't load. Restart " +
                 "the server: python3 web/server.py");
    }
  } catch {
    return off("The assistant isn't available on this published site — it " +
               "needs its own local server. Run the atlas with " +
               "python3 web/server.py to use it.");
  }
  wireUp();
  renderTranscript();
  renderPinned();
  renderChecklist();
  renderComposer();
  renderStatus();

  let wasOpen = "";
  try { wasOpen = localStorage.getItem(key("chat-open")) || ""; } catch { /* fine */ }
  if (wasOpen) setOpen(true);
}

window.addEventListener("atlas:chat-reset", resetSession);

window.AtlasChat = { start, pin: (v) => { if (!disabled) pin(v); }, open: () => setOpen(true), DRAG_MIME };

// The atlas finishes booting on its own schedule, and this module is deferred,
// so whichever lands second starts the drawer.
if (window.Atlas?.ready) start();
else window.addEventListener("atlas:ready", start, { once: true });
