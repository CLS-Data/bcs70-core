"""The interview as a LangGraph.

    START ─▶ interviewer ─┬─(asked for tools, hops left)─▶ lookups ─┐
                          │                                         │
                          │◀────────────────────────────────────────┘
                          ├─(asked for tools, hops spent)─▶ press ──┐
                          └─(answered)─────────────────────────────▶┴─▶ draft ─▶ END

Three things this file is careful about, all of them things the graph does
not give you for free:

**Tokens are written by hand, not streamed by the framework.** LangGraph's
`messages` stream mode would emit raw model tokens, and those include the
marker the model uses to declare its own answer buttons. That marker must
never reach the transcript, and it arrives split across chunks. So the nodes
stream the model themselves and publish through `get_stream_writer()`, which
keeps the parser between the model and the client where it belongs.

**Tools are executed here rather than by the prebuilt ToolNode.** Each lookup
produces two different things: a terse string for the model, and a richer
structure for the transcript card. ToolNode only carries the first.

**The event contract is the API's, not LangGraph's.** Everything published is
already in the shape `web/chat.js` reads, so the browser is unaware any of
this exists.
"""

from __future__ import annotations

import json
import re
from typing import Annotated, Any, TypedDict

from langchain_core.messages import (
    AIMessage,
    AnyMessage,
    HumanMessage,
    SystemMessage,
    ToolMessage,
)
from langchain_core.runnables import RunnableConfig
from langgraph.config import get_stream_writer
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages

from . import llm, prompts, router, tools as toolkit
from .choices import ChoiceParser, TagSpan

# Node names, so a typo is an error rather than an unreachable branch.
CLASSIFY = "classify"
INTERVIEWER = "interviewer"
LOOKUPS = "lookups"
PRESS = "press"
DRAFT = "draft"


def _merge_seen(left: list[dict] | None, right: list[dict] | None) -> list[dict]:
    """Accumulate the variables the tools have surfaced, without duplicates.

    A reducer rather than a plain list, so every node that runs a lookup adds
    to one working set instead of replacing it.
    """
    out = list(left or [])
    index = {(v.get("name"), v.get("wave")) for v in out}
    for v in right or []:
        key = (v.get("name"), v.get("wave"))
        if key not in index:
            index.add(key)
            out.append(v)
    return out


class TurnState(TypedDict, total=False):
    messages: Annotated[list[AnyMessage], add_messages]
    pinned: list[dict]
    covered: dict[str, bool]
    draft: dict
    options: list[str]
    asked_step: str | None
    separate: list[str]
    hops: int
    mode: str          # which intent the router chose
    seen: Annotated[list[dict], _merge_seen]   # variables the tools returned


def _advances(run: dict, state: TurnState) -> bool:
    """Does this turn's intent move the checklist on?

    Declared per intent in the config, so an intent added later decides for
    itself rather than being compared against a name hard-coded here.
    """
    return run["cfg"].intent(state.get("mode")).advances


def _run(config: RunnableConfig) -> dict:
    """Everything a node needs that is not conversation state."""
    return (config or {}).get("configurable", {})


# ── Talking ─────────────────────────────────────────────────────────────

def _context(state: TurnState, run: dict, force: bool = False) -> list[AnyMessage]:
    """System framing plus the trimmed transcript."""
    cfg = run["cfg"]
    step = cfg.first_unsettled(state.get("covered") or {})

    msgs: list[AnyMessage] = [SystemMessage(prompts.system(
        cfg, step, state.get("covered") or {}, run["agentic"],
        facts=run["corpus"].facts,
        mode=state.get("mode")))]

    pins = prompts.pinned_block(state.get("pinned") or [])
    if pins:
        msgs.append(SystemMessage(pins))

    history = list(state["messages"])[-cfg.max_turns:]
    # A slice can begin on a tool result whose call has scrolled out of the
    # window, which models reject outright. Drop leading orphans.
    while history and isinstance(history[0], ToolMessage):
        history.pop(0)
    msgs.extend(history)

    if force:
        msgs.append(SystemMessage(
            "You have no lookups left. Do not attempt another. Reply now, in "
            "plain prose, with the single question for the current step — or "
            "with what you found, if the step is answered."
        ))
    return msgs


def _speak(state: TurnState, run: dict, *, with_tools: bool, force: bool):

    """Stream one assistant message, stripping the choices marker as it goes.

    Returns (message, options, tool_calls).
    """
    cfg = run["cfg"]
    write = get_stream_writer()

    model = llm.interviewer(run)
    if with_tools:
        model = model.bind_tools(toolkit.lc_tools(cfg))

    parser = ChoiceParser(cfg)
    # Belt and braces. Well-behaved models put their working in Ollama's own
    # field; some emit <think> tags inline in the answer instead, and one
    # emits only the closing half. None of it is prose and none of it may
    # reach the transcript as prose.
    reasoning_tags = TagSpan("<think>", "</think>", orphan_close=True)

    parts: list[str] = []
    thinking: list[str] = []
    final: AIMessage | None = None

    for chunk in model.stream(_context(state, run, force)):
        reasoning = (chunk.additional_kwargs or {}).get("reasoning_content")
        if reasoning:
            thinking.append(reasoning)

        if isinstance(chunk.content, str) and chunk.content:
            safe = parser.feed(reasoning_tags.feed(chunk.content))
            if safe:
                parts.append(safe)
                write({"type": "content", "text": safe})

        final = chunk if final is None else final + chunk

    # Buffered, not streamed: it is shown collapsed, so sending it a token at
    # a time is hundreds of frames of traffic for something nobody is reading
    # yet — and it made the visible answer feel slow.
    leftover, inline = reasoning_tags.finish()
    if inline.strip():
        thinking.append(inline)
    if leftover:
        parser.feed(leftover)
    if thinking:
        write({"type": "thinking", "text": "".join(thinking).strip()})

    tail, options = parser.finish()
    if tail:
        parts.append(tail)
        write({"type": "content", "text": tail})

    text = "".join(parts)
    calls = list(getattr(final, "tool_calls", None) or [])

    # Rebuilt with the marker removed, so the transcript sent back next turn
    # never contains it either.
    return AIMessage(content=text, tool_calls=calls), options, calls


# Small models copy the format example out of the system prompt verbatim. The
# example is written to be obviously about something else, but a guard is
# cheaper than trusting that — a parroted answer is worse than none.
PLACEHOLDER = re.compile(
    r"^(first|second|third)\s+answer$|^(option|answer|choice)\s*[a-c1-3]?$|^[a-c]$",
    re.I)


def _clean_options(options: list[str]) -> list[str]:
    return [o for o in options if not PLACEHOLDER.match(o.strip())]


def _publish_options(run: dict, question: str, options: list[str],
                     driving: str | None = None) -> tuple[list[str], str | None]:
    """Emit the answer buttons, and name the step the question was about.

    `driving` is the step the interviewer was told to work on. It matters
    beyond choosing fallback answers: the client credits the step the question
    was ABOUT when the researcher replies, and crediting whichever step
    happened to be next instead meant an answer to one question ticked
    another off.
    """
    write = get_stream_writer()
    step: str | None = driving
    options = _clean_options(options)

    # No question mark, no question. Sometimes the model summarises or states
    # a recommendation instead of asking, and putting that through the rescue
    # call costs a round trip to be told nothing — or worse, a small model
    # obliges by inventing an "answer" to a statement.
    if not options and "?" in (question or ""):
        options, rescued = _rescue_options(run, question)
        step = rescued or step

    write({"type": "options", "options": options, "step": step})
    return options, step


def _rescue_options(run: dict, question: str) -> tuple[list[str], str | None]:
    cfg = run["cfg"]
    try:
        model = llm.structured(run, prompts.options_schema(cfg))
        out = model.invoke([HumanMessage(prompts.options_instruction(cfg, question))])
    except Exception:                                  # noqa: BLE001 - best effort
        return [], None
    if not isinstance(out, dict) or not isinstance(out.get("options"), list):
        return [], None

    options = _clean_options([str(o).strip() for o in out["options"]
                              if str(o).strip() and len(str(o)) < 60])[:5]
    step = out.get("step") if out.get("step") in cfg.step_ids else None
    return options, step


# ── Nodes ───────────────────────────────────────────────────────────────

def classify(state: TurnState, config: RunnableConfig) -> dict:
    """What does the researcher want from this message?"""
    run = _run(config)
    cfg = run["cfg"]

    last = next((m for m in reversed(state["messages"])
                 if isinstance(m, HumanMessage)), None)
    earlier = sum(1 for m in state["messages"] if isinstance(m, HumanMessage)) > 1
    asked = next((str(m.content) for m in reversed(state["messages"])
                  if isinstance(m, AIMessage) and str(m.content).strip()), "")

    def ask_model(instruction: str) -> dict:
        model = llm.structured(run, router.schema(cfg))
        return model.invoke([HumanMessage(instruction)])

    mode, how = router.classify(
        cfg, str(last.content) if last else "",
        has_history=earlier, last_question=asked[-400:], ask_model=ask_model)

    intent = cfg.intent(mode)
    # `advances` travels with the mode so the browser can mark a turn that
    # ticks nothing off without knowing which intents exist. It used to test
    # `mode === "explore"`, which is a name from the config appearing in the
    # markup — and silently wrong for any intent added later.
    get_stream_writer()({"type": "mode", "mode": mode, "label": intent.label,
                         "advances": intent.advances, "decided_by": how})
    return {"mode": mode}


def interviewer(state: TurnState, config: RunnableConfig) -> dict:
    run = _run(config)
    reply, options, calls = _speak(state, run, with_tools=run["agentic"], force=False)

    if calls:
        return {"messages": [reply]}    # options wait until it has actually spoken

    if not reply.content.strip():
        return _carry_on(state, run)

    driving = _driving_step(run, state)
    options, step = _publish_options(run, reply.content, options, driving)
    return {"messages": [reply], "options": options, "asked_step": step}


def _driving_step(run: dict, state: TurnState) -> str | None:
    """Which checklist step this message is working on, if any.

    None in two cases, and they are different:

    - An exploration names no step. The researcher asked us something, and
      crediting a checklist step for that is how a question about coverage
      got filed as an answer about naming.
    - With every step settled there is no step being worked on. Naming one
      anyway is what put the last step's stock answers — "follow the existing
      family's naming" — underneath a message saying the request was already
      complete and to open the Draft panel. `first_unsettled` returns the last
      index as a fallback, which reads exactly like a real answer.
    """
    cfg = run["cfg"]
    covered = state.get("covered") or {}
    if not _advances(run, state) or cfg.all_settled(covered):
        return None
    return cfg.steps[cfg.first_unsettled(covered)].id


def press(state: TurnState, config: RunnableConfig) -> dict:
    """Hops are spent. Withhold the tools and make it ask.

    Without this the turn ends on a transcript of lookups and no question: a
    model mid-search returns nothing at all rather than change course, so
    withholding the tools is not enough on its own — it has to be told.
    """
    run = _run(config)
    reply, options, _ = _speak(state, run, with_tools=False, force=True)

    if reply.content.strip():
        driving = _driving_step(run, state)
        options, step = _publish_options(run, reply.content, options, driving)
        return {"messages": [reply], "options": options, "asked_step": step}

    return _carry_on(state, run)


def _carry_on(state: TurnState, run: dict) -> dict:
    """Move the interview on when the model has not.

    A model that spends its whole turn searching, or returns nothing at all,
    used to leave a shrug in the transcript — "I didn't get to a question" —
    which puts the researcher back in charge of a conversation they came here
    to be led through. The checklist is right here, so ask from it: either the
    next open step's own question, or, if there are none, say the request is
    ready and where to go.
    """
    cfg = run["cfg"]
    write = get_stream_writer()
    covered = state.get("covered") or {}

    if not _advances(run, state):
        text = ("I didn't find anything to add there. Ask me something else, or "
                "tell me what you would like to derive.")
        write({"type": "content", "text": text})
        write({"type": "options", "options": [], "step": None})
        return {"messages": [AIMessage(content=text)], "options": [], "asked_step": None}

    if cfg.all_settled(covered):
        text = ("That is everything on the checklist. Open **Draft** to read the "
                "request back and file it — or keep going here if you want to "
                "change any of it.")
        options: list[str] = []
        asked = None
    else:
        step = cfg.steps[cfg.first_unsettled(covered)]
        question = step.probes[0] if step.probes else step.goal
        text = f"On to **{step.title.lower()}**. {question}"
        options = list(step.replies)
        asked = step.id

    write({"type": "content", "text": text})
    write({"type": "options", "options": options, "step": asked})
    return {"messages": [AIMessage(content=text)], "options": options,
            "asked_step": asked}


def lookups(state: TurnState, config: RunnableConfig) -> dict:
    """Run whatever the model asked for, and show the researcher both."""
    run = _run(config)
    cfg = run["cfg"]
    write = get_stream_writer()

    hops = state.get("hops", 0) + 1
    left = cfg.max_hops - hops
    spent = left <= 0
    out: list[AnyMessage] = []
    found: list[dict] = []

    for call in getattr(state["messages"][-1], "tool_calls", None) or []:
        name = call.get("name") or ""
        args = call.get("args") or {}
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except json.JSONDecodeError:
                args = {"query": args}
        if not isinstance(args, dict):
            args = {"query": str(args)}

        write({"type": "tool_call", "name": name, "args": args})
        found_text, display = toolkit.run(run["corpus"], run["bm25"], cfg, name, args,
                                          run.get("retriever"), run.get("retrieval"))
        # Warned before the budget runs out, not only when it has. A model
        # told at the last moment has already wasted the turn.
        text = found_text
        if spent:
            text += ("\n\nThat was the last lookup available this turn. Stop "
                     "searching and put your question to the researcher now.")
        elif left <= 2:
            text += (f"\n\n({left} lookup{'' if left == 1 else 's'} left this "
                     f"turn. Ask your question unless another is essential.)")
        # `text` carries what the model reads, so the browser can post it back
        # next turn — without it, a conversation's own history says every
        # lookup returned nothing, and the model searches the same thing again.
        # The budget nudge is deliberately NOT included: it is true for this
        # turn only, and a stale one read back later is a lie about the budget.
        write({"type": "tool_result", "name": name, "args": args,
               "display": display, "text": found_text})
        out.append(ToolMessage(content=text, name=name,
                               tool_call_id=call.get("id") or name))
        found.extend(_variables_in(display))

    return {"messages": out, "hops": hops, "seen": found}


def draft(state: TurnState, config: RunnableConfig) -> dict:
    """Read the whole conversation back and fill in the request."""
    run = _run(config)
    cfg, corpus = run["cfg"], run["corpus"]
    write = get_stream_writer()

    transcript = _transcript(state)
    known = _known_names(state, corpus)
    already = [s for s in cfg.step_ids if (state.get("covered") or {}).get(s)]

    try:
        model = llm.structured(run, prompts.draft_schema(cfg))
        out = model.invoke([HumanMessage(
            prompts.draft_instruction(cfg, transcript, known, already))])
    except Exception as err:                           # noqa: BLE001 - reported, not swallowed
        write({"type": "draft_failed", "message": str(err)})
        return {}

    event = apply_draft(cfg, state, out if isinstance(out, dict) else {}, corpus,
                        advance=_advances(run, state))
    write(event)
    return {"draft": event["draft"], "covered": event["covered"],
            "separate": event["separate"]}


# Tool results dominate the draft's prompt — ten grouped hits per search, and
# every search of the conversation is in there. The names it may use are
# passed separately in `known`, so the body is summarised rather than
# repeated: on a small local model this was most of a 95-second call.
TOOL_LINES_IN_DRAFT = 4


def _transcript(state: TurnState) -> str:
    lines: list[str] = []
    for m in state["messages"]:
        if isinstance(m, ToolMessage):
            body = str(m.content).split("\n")
            head = "\n".join(body[:TOOL_LINES_IN_DRAFT])
            more = len(body) - TOOL_LINES_IN_DRAFT
            if more > 0:
                head += f"\n  (+{more} more results)"
            lines.append(f"LOOKUP ({m.name}):\n{head}")
        elif isinstance(m, HumanMessage) and str(m.content).strip():
            lines.append(f"RESEARCHER: {m.content}")
        elif isinstance(m, AIMessage) and str(m.content).strip():
            lines.append(f"ASSISTANT: {m.content}")
    return "\n\n".join(lines)


def _known_names(state: TurnState, corpus, cap: int = 60) -> list[str]:
    """Names the extractor is allowed to record as real.

    A name the tools actually returned is as real as a pinned one, and the
    extractor has to be told so — otherwise the rule against inventing names
    also stops it recording the ones properly found. Read from the working set
    the lookups keep, not from their rendered text.
    """
    known = [p["name"] for p in state.get("pinned") or []
             if p.get("kind") != "derived"]
    for variable in state.get("seen") or []:
        name = variable.get("name")
        if name and name not in known and corpus.known_name(name):
            known.append(name)
    return known[:cap]


def apply_draft(cfg, state: TurnState, out: dict, corpus, *,
                advance: bool = True) -> dict:
    """Merge the extractor's answer into the draft the client holds.

    `advance` is false while exploring. The draft's own fields still fill in —
    someone saying "I only care about the adult sweeps" mid-question has told
    us something worth keeping — but no step is ticked off, because they were
    not answering a question. A revision still applies either way.
    """
    draft_now = dict(state.get("draft") or {})
    slots = dict(draft_now.get("slots") or {})

    def keep(current: str, incoming) -> str:
        incoming = incoming if isinstance(incoming, str) else ""
        return incoming.strip() or current

    for key in ("name", "category", "description"):
        draft_now[key] = keep(draft_now.get(key, ""), out.get(key))
    draft_now["waves"] = keep(draft_now.get("waves", ""), out.get("waves"))

    for slot in cfg.note_slots:
        slots[slot.key] = keep(slots.get(slot.key, ""), out.get(slot.key))
    draft_now["slots"] = slots

    if not draft_now.get("notesTouched"):
        draft_now["notes"] = "\n\n".join(
            f"{slot.heading}: {slots[slot.key]}"
            for slot in cfg.note_slots if slots.get(slot.key)
        )

    seen = list(draft_now.get("source_vars") or [])
    for name in out.get("source_vars") or []:
        name = str(name).strip()
        if name and name not in seen:
            seen.append(name)
    for pin in state.get("pinned") or []:
        if pin.get("kind") != "derived" and pin["name"] not in seen:
            seen.append(pin["name"])
    draft_now["source_vars"] = seen

    covered = _ratchet(cfg, state, out, advance=advance)
    separate = out.get("separate_concepts")
    return {
        "type": "draft",
        "draft": draft_now,
        "covered": covered,
        "step": cfg.first_unsettled(covered),
        "separate": separate if isinstance(separate, list) else [],
        "sourceVarsKnown": {v: corpus.known_name(v) for v in draft_now["source_vars"]},
    }


def _ratchet(cfg, state: TurnState, out: dict, *, advance: bool = True) -> dict[str, bool]:
    """Coverage moves forward on its own, and back only when asked.

    The ratchet exists so a model that forgets on turn six what it confirmed
    on turn two cannot un-tick the checklist. A researcher changing their mind
    is the opposite case and the one thing that may reopen a step — without
    this, a correction to something already settled was silently filed as an
    answer to whatever question happened to be on screen.
    """
    covered = dict(state.get("covered") or {})
    settled = out.get("settled") if advance else None

    if isinstance(settled, list):
        for step_id in settled:
            if step_id in cfg.step_ids:
                covered[step_id] = True
    elif advance:
        # The extractor said nothing readable about progress. Rather than
        # freezing the interview, credit the step just answered.
        current = cfg.steps[cfg.first_unsettled(state.get("covered") or {})]
        covered[current.id] = True

    revised = out.get("revised")
    if isinstance(revised, list):
        for step_id in revised:
            if step_id in cfg.step_ids:
                covered[step_id] = False
    return covered


# ── Wiring ──────────────────────────────────────────────────────────────

def _variables_in(display: dict) -> list[dict]:
    """The variables a lookup surfaced, as records rather than as prose.

    These used to be recovered by re-parsing the rendered tool output — split
    on pipes, strip punctuation, hope. That threw away everything but the
    name, and broke whenever the wording changed.
    """
    found: list[dict] = []
    for group in (display or {}).get("groups") or []:
        for name in group.get("names") or []:
            found.append({
                "name": name,
                "wave": (group.get("waves") or [None])[0],
                "label": group.get("label"),
                "file": (group.get("files") or [None])[0],
            })
    one = (display or {}).get("variable")
    if one:
        found.append({k: one.get(k) for k in ("name", "wave", "label", "file")})
    return found


def route(state: TurnState, config: RunnableConfig) -> str:
    if not getattr(state["messages"][-1], "tool_calls", None):
        return DRAFT
    return PRESS if _run(config)["cfg"].hops_spent(state.get("hops", 0)) else LOOKUPS


def build():
    graph = StateGraph(TurnState)
    graph.add_node(CLASSIFY, classify)
    graph.add_node(INTERVIEWER, interviewer)
    graph.add_node(LOOKUPS, lookups)
    graph.add_node(PRESS, press)
    graph.add_node(DRAFT, draft)

    graph.add_edge(START, CLASSIFY)
    graph.add_edge(CLASSIFY, INTERVIEWER)
    graph.add_conditional_edges(INTERVIEWER, route,
                                {LOOKUPS: LOOKUPS, PRESS: PRESS, DRAFT: DRAFT})
    graph.add_edge(LOOKUPS, INTERVIEWER)
    graph.add_edge(PRESS, DRAFT)
    graph.add_edge(DRAFT, END)
    return graph.compile()
