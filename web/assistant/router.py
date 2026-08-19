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
"""

from __future__ import annotations

import re

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

def schema(cfg) -> dict:
    return {
        "type": "object",
        "properties": {"intent": {"type": "string", "enum": cfg.intent_ids}},
        "required": ["intent"],
    }


def instruction(cfg, text: str, last_question: str) -> str:
    options = "\n".join(f"  {i.id} — {i.description}" for i in cfg.intents)
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
             ask_model=None) -> tuple[str, str]:
    """Return (intent id, how it was decided).

    `ask_model` takes the instruction and returns the parsed object, or raises.
    It is injected rather than imported so this module stays free of LangGraph
    and can be tested without one.
    """
    strategy = cfg.router_strategy

    # The opening message is the request, whatever it looks like. Deciding
    # that here saves a round trip on the one turn where it is never in doubt.
    if not has_history:
        return cfg.intents[0].id, "first message"

    if strategy in ("model", "auto") and ask_model is not None:
        try:
            out = ask_model(instruction(cfg, text, last_question))
            chosen = (out or {}).get("intent")
            if chosen in cfg.intent_ids:
                return chosen, "model"
        except Exception:                              # noqa: BLE001 - see below
            if strategy == "model":
                # Asked for the model and only the model, but a routing
                # failure must not take the turn with it.
                return heuristic(cfg, text, has_history=has_history), "heuristic (model failed)"
        if strategy == "model":
            return heuristic(cfg, text, has_history=has_history), "heuristic (model unsure)"

    return heuristic(cfg, text, has_history=has_history), "heuristic"
