"""Deciding what the researcher is asking for.

The assistant can be asked to do more than one thing, and each wants something
different from a turn. Working on the request drives the checklist and counts a
step settled. Asking about the data should do neither — the researcher asked a
question, and treating that as progress is how "which sweeps have self-rated
health?" got filed as an answer about variable naming.

The list of things it can be asked lives in `dataset.toml` as `[[intent]]`
entries, each with a description the router matches on and the instructions
the assistant then works to. Adding a capability is a config change: no branch
here, and none in `prompts.py`.

Two ways to decide, chosen by `[assistant] router`:

- **model** — hand the message and the intent descriptions to the helper model.
  Reads intent rather than syntax, and extends to intents a rule could never
  express. Costs one round trip before any work starts.
- **heuristic** — punctuation and opening words. Free and instant, right on the
  obvious cases, and blind to any intent it was not written for.
- **auto** — the model, falling back to the heuristic when it errors or is
  unreachable. The default, because a routing failure should degrade rather
  than end the turn.

`transition()` sits over all of that. Picking an intent afresh on every
message is right for answering a question and wrong for an interview: a
researcher who asks "which sweeps have this?" halfway through would be routed
out of the very thing they asked to start. So an intent may declare itself
`sticky`, and then the only question each turn is whether to leave it — which
is cheaper as well as steadier, because a sticky turn asks the model nothing.
Getting into one takes an accepted proposal, never a routing decision alone.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# Openers that make a message a question about the data even without a
# question mark: "list the health variables at 42y", "show me what exists".
DEFAULT_OPENERS = (
    "which", "what", "where", "when", "who", "why", "how",
    "is there", "are there", "do you", "does", "can you", "could you",
    "show", "list", "find", "search", "tell me", "explain", "compare",
    "how many", "anything", "any ",
)

# Phrases that mean "get on with it" even though they are questions.
STEER_BACK = (
    "next question", "carry on", "keep going", "move on", "what's next",
    "whats next", "what next",
)

def schema(cfg, intents=None) -> dict:
    """`intents` narrows the choice — the router is never offered one that
    can only be entered by handoff."""
    ids = [i.id for i in (intents if intents is not None else cfg.intents)]
    return {
        "type": "object",
        "properties": {"intent": {"type": "string", "enum": ids}},
        "required": ["intent"],
    }


def instruction(cfg, text: str, last_question: str, intents=None) -> str:
    options = "\n".join(f"  {i.id} — {i.description}"
                        for i in (intents if intents is not None else cfg.intents))
    asked = f'\nThe assistant had just asked: "{last_question}"\n' if last_question else ""
    return f"""Classify what the researcher wants from this message.
{asked}
Their message:
"{text}"

The options:
{options}

Answer with the id alone, as {{"intent": "..."}}. If the message both answers
the question and asks one of its own, choose the question — it is the part
they are waiting on.
"""


def heuristic(cfg, text: str, *, has_history: bool, openers=DEFAULT_OPENERS) -> str:
    """Punctuation and opening words. No model, no network.

    It knows only two classes — a question about the data, and everything else
    — so it routes to the intent marked `heuristic = "question"` or to the
    fallback. It cannot see any intent added since it was written, which is
    the whole reason the model router exists.
    """
    default = cfg.intents[0].id
    question = cfg.question_intent.id

    body = (text or "").strip()
    if not body:
        return default

    low = body.lower()

    # "next question" is a question in form only.
    if any(phrase in low for phrase in STEER_BACK):
        return default

    # The opening message is the request itself, however it is phrased —
    # "what determines BMI?" as a first message is someone describing what
    # they want, not quizzing the corpus.
    if not has_history:
        return default

    if body.endswith("?"):
        return question

    first = re.sub(r"^[^a-z]+", "", low)
    if any(first.startswith(o) for o in openers):
        return question

    return default


def classify(cfg, text: str, *, has_history: bool, last_question: str = "",
             ask_model=None, intents=None) -> tuple[str, str]:
    """Return (intent id, how it was decided).

    `ask_model` takes the instruction and returns the parsed object, or raises.
    It is injected rather than imported so this module stays free of LangGraph
    and can be tested without one.

    `intents` narrows the choice, and must narrow what the model is TOLD as
    well as what it is allowed to answer: describing an intent in the prompt
    while forbidding it in the schema asks for an answer that cannot be given.
    """
    strategy = cfg.router_strategy
    allowed = [i.id for i in (intents if intents is not None else cfg.intents)]

    # The opening message is the request, whatever it looks like. Deciding
    # that here saves a round trip on the one turn where it is never in doubt.
    if not has_history:
        return cfg.intents[0].id, "first message"

    if strategy in ("model", "auto") and ask_model is not None:
        try:
            out = ask_model(instruction(cfg, text, last_question, intents))
            chosen = (out or {}).get("intent")
            if chosen in allowed:
                return chosen, "model"
        except Exception:                              # noqa: BLE001 - see below
            if strategy == "model":
                # Asked for the model and only the model, but a routing
                # failure must not take the turn with it.
                return heuristic(cfg, text, has_history=has_history), "heuristic (model failed)"
        if strategy == "model":
            return heuristic(cfg, text, has_history=has_history), "heuristic (model unsure)"

    return heuristic(cfg, text, has_history=has_history), "heuristic"


# ── Moving between intents ──────────────────────────────────────────────
#
# Everything below is the state machine: which intent a turn runs in, given
# the one the last turn ran in. It is deliberately standard library and
# deliberately pure — the graph supplies `ask_model` and stores the result,
# so every rule here can be tested in a checkout that installed nothing.

# Answering a proposal. Only a plain "yes" gets someone into a sticky intent:
# anything else is read as declining, which is the safe direction. A wrong
# decline costs a sentence; a wrong accept puts a researcher somewhere they
# did not ask to be.
AFFIRM = (
    "yes", "yeah", "yep", "yup", "ok", "okay", "sure", "please do", "please",
    "go ahead", "go on", "start", "let's go", "lets go", "let's do", "lets do",
    "do it", "sounds right", "that's right", "thats right", "correct", "right",
)

# Leaving a sticky intent. "stop" runs through this corpus mid-sentence —
# stopping smoking, stopping work, stopping school — so a bare match anywhere
# would drop someone out of the interview for asking an ordinary question.
STOP_PHRASES = (
    "stop", "cancel", "never mind", "nevermind", "forget it", "forget this",
    "not now", "not any more", "not anymore", "i'm done", "im done",
    "we're done", "were done", "that's enough", "thats enough", "quit",
    "abandon", "leave it", "drop it", "go back", "let's stop", "lets stop",
)

# Which of them may open a LONGER message. Listed rather than derived: being
# more than one word is not what makes a phrase unambiguous. "no more" was
# dropped from the list above for the same reason — "no more than 3 sweeps"
# is an answer — and "go back" is here only in the short form, because "go
# back to the 16y sweep" is navigation, not an exit.
#
# "start over" is deliberately absent from both: it asks to restart the
# interview, not to leave it, and the checklist already reopens a step when
# the extractor reports a revision.
STOP_OPENERS = (
    "never mind", "nevermind", "forget it", "forget this",
    "let's stop", "lets stop", "i'm done", "im done",
    "we're done", "were done", "that's enough", "thats enough",
)

# Otherwise an exit has to BE the message. Four words, not six: "did they
# stop smoking by 29y?" is exactly six, which is how this rule first let a
# perfectly ordinary question end an interview.
SHORT_MESSAGE_WORDS = 4

# Wanting something derived. Conservative on purpose: the proposal is what
# makes a wrong reading cheap, but only if wrong readings are rare enough
# that the proposal is not constantly in the way.
DERIVE_WORDS = ("derive", "derived", "derivation", "harmonis", "harmoniz")
WANT_VERBS = (
    "i want", "i need", "i'd like", "id like", "i would like", "we want",
    "we need", "can you make", "can you build", "can you create", "can you add",
    "could you make", "could you build", "please make", "please create",
    "let's add", "lets add", "how do i request", "how do i ask for",
)
WANT_NOUNS = ("variable", "measure", "column", "request", "issue")


@dataclass(frozen=True)
class Transition:
    """What this turn does about its intent.

    `mode` is the intent the turn runs in — always a real one, so a caller
    never has to guard against an empty string. The other two are the things
    a turn can additionally be: an invitation awaiting an answer, or the first
    turn inside an intent just accepted.
    """

    mode: str
    how: str                 # provenance, shown in the `mode` event
    proposing: str = ""      # an intent offered this turn, awaiting a yes
    entering: bool = False   # accepted just now, so the draft wants seeding

    @property
    def is_proposal(self) -> bool:
        return bool(self.proposing)


def _words(text: str) -> list[str]:
    return re.findall(r"[a-z']+", (text or "").lower())


def _opens_with(text: str, phrases) -> bool:
    low = re.sub(r"^[^a-z]+", "", (text or "").lower())
    return any(re.match(rf"{re.escape(p)}\b", low) for p in phrases)


def is_affirmative(text: str) -> bool:
    """Did they say yes to the proposal?"""
    return _opens_with(text, AFFIRM)


def is_exit(text: str) -> bool:
    """Do they want out of the sticky intent?

    Note what this does NOT do: infer an exit from a message that merely
    changes the subject. Asking about the data mid-interview is expected — the
    interviewer answers it and carries on — so only an explicit stop leaves.

    Three narrowings, each for a message that would otherwise have ended an
    interview by accident: a question is never an exit however it is worded,
    only an unambiguous multi-word phrase may open a longer message, and
    anything else has to be short enough to be the whole point of the message.

    A two-word "stop smoking" still reads as an exit. That is the residue of
    a rule with no model behind it — the visible stop control is the reliable
    way out, this is the courtesy — and leaving is recoverable: the draft is
    kept and the interview is one sentence away.
    """
    body = (text or "").strip()
    if _opens_with(body, STOP_OPENERS):
        return True
    # A question is a question. Whatever else it contains, they are waiting
    # on an answer, not asking to leave.
    if body.endswith("?"):
        return False
    words = _words(body)
    if not words or len(words) > SHORT_MESSAGE_WORDS:
        return False
    low = " ".join(words)
    return any(re.search(rf"\b{re.escape(p)}\b", low) for p in STOP_PHRASES)


def wants_derivation(text: str) -> bool:
    """Does this message ask for something to be derived?

    The rule behind the model, so it is blunt: a derivation word on its own,
    or wanting-language aimed at a variable. "Which sweeps measured height?"
    matches neither, which is the case worth getting right.
    """
    low = (text or "").lower()
    if any(w in low for w in DERIVE_WORDS):
        return True
    return (any(v in low for v in WANT_VERBS)
            and any(n in low for n in WANT_NOUNS))


def start_schema() -> dict:
    return {
        "type": "object",
        "properties": {"start": {"type": "boolean"}},
        "required": ["start"],
    }


def start_instruction(cfg, intent, text: str) -> str:
    return f"""A researcher is talking to an assistant about {cfg.name}.

Their message:
"{text}"

Are they asking for a variable to be derived — that is, do they want work
started that ends in {intent.description.lower() or "a variable request"}?

Answer true only if they are asking for something to be BUILT. A question
about what the study measured, what a variable means, or where a concept
appears is not a request to derive anything, however specific it is.

Answer {{"start": true}} or {{"start": false}}.
"""


def accept_schema() -> dict:
    return {
        "type": "object",
        "properties": {"accepted": {"type": "boolean"}},
        "required": ["accepted"],
    }


def accept_instruction(text: str, proposal: str) -> str:
    return f"""An assistant offered to start work, asking:

"{proposal}"

The researcher replied:
"{text}"

Did they agree to start? Answer true only for agreement. A reply that ignores
the offer, asks something else, or hedges is not agreement.

Answer {{"accepted": true}} or {{"accepted": false}}.
"""


def step_for_options(driving: str | None, rescued: str | None) -> str | None:
    """Which checklist step the answer buttons belong to.

    `driving` is the step the agent was told to work on, and `None` from it
    means no step is in play at all — the intent does not advance one, or
    every step is already settled. A rescued step may only ever REFINE that,
    never introduce one, because the two Nones are load-bearing:

    - In a non-advancing intent, naming a step credits it when the researcher
      replies, which is how a question about coverage got filed as an answer
      about naming.
    - With the checklist complete there is no question, so there is nothing
      for a step to be about. `_driving_step` returns None for exactly this,
      and the rescue used to hand a step straight back — which parked the
      last step's stock answers ("compare against the published CLS figures")
      under a message saying the request was finished, on every turn after,
      with no way out but a reset.
    """
    return (rescued or driving) if driving else None


def transition(cfg, mode: str | None, text: str, *, has_history: bool,
               awaiting: str = "", last_question: str = "",
               ask_model=None) -> Transition:
    """Which intent this turn runs in.

    `awaiting` is the intent proposed on the previous turn, if any; the graph
    carries it, because whether a "yes" means anything depends on what was
    asked. `ask_model(instruction, schema) -> dict` is injected so this module
    stays free of LangGraph.

    The order is not arbitrary. A pending proposal is answered before anything
    else, or a "yes" gets classified as a fresh message; leaving a sticky
    intent is decided before staying in it; and only a turn that is doing
    neither is free to route.
    """
    current = cfg.intent(mode) if mode else cfg.fallback_intent

    if not has_history:
        # The opening message goes to the fallback whatever it says. Deciding
        # it here saves a round trip on the one turn where it is not in doubt.
        return Transition(cfg.fallback_intent.id, "first message")

    if awaiting:
        return _answer_proposal(cfg, current, awaiting, text, ask_model)

    if current.sticky:
        if is_exit(text):
            return Transition(cfg.exit_intent(current).id, "exit")
        # The steady case, and the common one: no model call at all.
        return Transition(current.id, "sticky")

    return _route(cfg, current, text, last_question, ask_model)


def _answer_proposal(cfg, current, awaiting: str, text: str,
                     ask_model) -> Transition:
    offered = cfg.intent(awaiting)
    # A proposal for something that is no longer a handoff intent is a config
    # change mid-conversation. Drop it rather than acting on it.
    if not offered.entered_by_handoff:
        return Transition(current.id, "proposal expired")

    accepted = _ask_yes_no(
        cfg, ask_model, accept_schema(), "accepted",
        lambda: accept_instruction(text, offered.confirm),
        lambda: is_affirmative(text))

    if accepted:
        return Transition(offered.id, "accepted", entering=True)
    return Transition(cfg.exit_intent(offered).id, "declined")


def _route(cfg, current, text: str, last_question: str, ask_model) -> Transition:
    """Not in a sticky intent, and nothing pending. Route the message."""
    for offered in cfg.handoff_intents:
        starting = _ask_yes_no(
            cfg, ask_model, start_schema(), "start",
            lambda: start_instruction(cfg, offered, text),
            lambda: wants_derivation(text))
        if starting:
            return Transition(current.id, "proposed", proposing=offered.id)

    choices = cfg.router_intents
    if len(choices) < 2:
        # Nothing to decide. Asking a model to pick from a list of one is a
        # round trip that can only agree with itself.
        return Transition(choices[0].id if choices else current.id, "only intent")

    chosen, how = classify(cfg, text, has_history=True,
                           last_question=last_question, intents=choices,
                           ask_model=(
                               (lambda ins: ask_model(ins, schema(cfg, choices)))
                               if ask_model else None))
    # The heuristic behind `classify` knows only the intent marked
    # `heuristic = "question"`, which need not be one of `choices`. Its answer
    # is a suggestion; the narrowing is the rule.
    if chosen not in [i.id for i in choices]:
        chosen = choices[0].id
    return Transition(chosen, how)


def _ask_yes_no(cfg, ask_model, sch: dict, key: str, instruct, rule) -> bool:
    """The model where it is wanted, the rule where it is not — or where the
    model failed. Same contract as `classify`: a routing failure degrades the
    turn rather than ending it."""
    strategy = cfg.router_strategy
    if strategy in ("model", "auto") and ask_model is not None:
        try:
            out = ask_model(instruct(), sch)
            value = (out or {}).get(key)
            if isinstance(value, bool):
                return value
        except Exception:                              # noqa: BLE001 - see above
            pass
    return rule()
