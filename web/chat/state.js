/* The conversation, and everything derived from it.
   No rendering here: this module is what the panels read, and what the turn
   loop writes. It imports nothing of its own so it can never take part in a
   cycle. */

export const DRAG_MIME = "application/x-atlas-variable";

export const A = () => window.Atlas;

export const chat = {
  open: false,
  settings: {
    baseUrl: "",       // filled from the config at boot
    model: "",
    helperModel: "",
    temperature: 0.4,
    think: false,
    // Retrieval. Left null until /api/health reports the configured
    // defaults, so there is no second copy of them to drift from
    // dataset.toml — the same reason the interview is fetched rather than
    // written out here.
    retrieval: null,
  },
  models: [],
  connection: "unknown",   // unknown | ok | down
  semantic: null,          // {available, model, dims, reason} from /api/health
  interview: null,         // {steps, categories} from /api/interview

  messages: [],
  pinned: [],
  covered: {},
  step: 0,
  draft: emptyDraft(),
  options: [],
  askedStep: null,
  separate: [],
  knownVars: null,         // name -> bool, as validated by the server

  // Which agent the current turn belongs to, and which lookup it is
  // waiting on. Both are shown while they are true and then attached to
  // the message, so scrolling back still says who answered and on what.
  agent: null,        // {id, label} for the turn being streamed
  tool: null,         // {name, args} of the lookup in flight

  busy: false,        // a request is in flight
  answered: false,    // …but the reply and its choices have already landed
  phase: "",          // what to show in the working indicator
  // How the server read the last message, and — since it keeps nothing
  // between turns — what has to be handed back for the next one. The browser
  // never needs to know which intents exist: it used to test
  // `mode === "explore"`, a config id spelled out in the markup.
  mode: "",
  modeLabel: "",
  modeAdvances: true,
  // Sticky: this intent is stayed in until an explicit stop, so the strip
  // shows a way out. `awaiting` is an offer to start something, outstanding
  // until answered — whether "yes" means anything depends on what was asked,
  // so the question has to survive the round trip. `exitsTo` is where the
  // stop control lands, named by the server rather than guessed here.
  sticky: false,
  awaiting: "",
  exitsTo: "",
  turn: 0,            // which turn owns the transcript right now
  abort: null,
  panel: "chat",
};

export function emptyDraft() {
  return {
    name: "", waves: "", category: "", description: "",
    source_vars: [], notes: "", notesTouched: false, slots: {},
  };
}

/* ── Model capabilities ────────────────────────────────────────────── */

// Namespaced per dataset by Atlas.storeKey, so two atlases on one origin
// keep separate conversations.
export const key = (name) => A().storeKey(name);

export const modelBy = (name) => chat.models.find((m) => m.name === name) || null;

export const modelUsesTools = () => Boolean(modelBy(chat.settings.model)?.tools);

export const modelThinks = () => Boolean(modelBy(chat.settings.model)?.thinking);

export const helperName = () => chat.settings.helperModel || chat.settings.model;

export const helperThinks = () => Boolean(modelBy(helperName())?.thinking);

export const stepById = (id) => (chat.interview?.steps || []).find((s) => s.id === id) || null;

export const defaultBase = () => A().state.dataset.assistant.ollama;

export const waveTerm = () => A().state.dataset.wave.term;

export const wavePlural = () => A().state.dataset.wave.plural;

export const capitaliseWave = () => wavePlural().replace(/^./, (c) => c.toUpperCase());

/* ── API ───────────────────────────────────────────────────────────── */

// The checklist belongs to the interview. Before one it is noise; after one
// it is the progress that was made, which is worth keeping on screen even
// once the conversation has gone back to general questions.
export function showsChecklist() {
  return chat.sticky || Object.values(chat.covered || {}).some(Boolean);
}

export function firstUnsettled() {
  const steps = chat.interview?.steps || [];
  const next = steps.findIndex((s) => !chat.covered[s.id]);
  return next === -1 ? Math.max(0, steps.length - 1) : next;
}

// Marks one step settled and moves to the next still open. Falls back to
// the current step when the server did not say which one was asked about.
export function creditStep(id) {
  if (!id) return;
  const step = (chat.interview?.steps || []).find((s) => s.id === id);
  if (!step || chat.covered[step.id]) return;
  chat.covered[step.id] = true;
  chat.step = firstUnsettled();
}

export function saveSettings() {
  try { localStorage.setItem(key("chat"), JSON.stringify(chat.settings)); }
  catch { /* private browsing — settings just won't persist */ }
}

export function saveSession() {
  try {
    localStorage.setItem(key("chat-session"), JSON.stringify({
      messages: chat.messages.slice(-40), pinned: chat.pinned,
      draft: chat.draft, covered: chat.covered, step: chat.step,
      separate: chat.separate, options: chat.options, askedStep: chat.askedStep,
      // Without these a reload drops you out of the interview mid-question,
      // and a reload between an offer and its answer turns "yes" into a
      // sentence about nothing.
      mode: chat.mode, sticky: chat.sticky, awaiting: chat.awaiting,
      exitsTo: chat.exitsTo,
    }));
  } catch { /* over quota — the transcript is not worth failing over */ }
}

export function restore() {
  try {
    Object.assign(chat.settings, JSON.parse(localStorage.getItem(key("chat")) || "{}"));
  } catch { /* keep the defaults */ }
  try {
    const s = JSON.parse(localStorage.getItem(key("chat-session")) || "null");
    if (s) {
      chat.messages = s.messages || [];
      chat.pinned = s.pinned || [];
      chat.draft = { ...emptyDraft(), ...(s.draft || {}) };
      chat.covered = s.covered || {};
      chat.step = s.step || 0;
      chat.separate = s.separate || [];
      chat.options = s.options || [];
      chat.askedStep = s.askedStep || null;
      chat.mode = s.mode || "";
      chat.sticky = Boolean(s.sticky);
      chat.awaiting = s.awaiting || "";
      chat.exitsTo = s.exitsTo || "";
    }
  } catch { /* start fresh */ }
}
