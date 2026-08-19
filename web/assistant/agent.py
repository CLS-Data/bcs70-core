"""Driving one turn of the graph, and translating it for the browser.

The server is stateless: the client sends the conversation it holds, the
graph runs, and the events stream straight back. That keeps `localStorage` as
the only place a draft lives, makes a server restart invisible, and means
nothing accumulates in memory per user.

Events emitted (NDJSON, one object per line):

    {"type":"thinking",   "text": …}     reasoning tokens, if the model emits them
    {"type":"content",    "text": …}     prose, streamed
    {"type":"tool_call",  "name": …, "args": {…}}
    {"type":"tool_result","name": …, "args": {…}, "display": {…}}
    {"type":"options",    "options": [...], "step": "coverage"|null}
    {"type":"draft",      "draft": {…}, "covered": {…}, "step": n, "separate": [...]}
    {"type":"error",      "message": …, "status": 410|null}
    {"type":"done"}
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from dataclasses import dataclass, field
from typing import Any

from config import Config
from langchain_core.messages import AIMessage, AnyMessage, HumanMessage, ToolMessage

from .graph import build

# A tool hop is two nodes, so the hop cap alone cannot bound the graph. This
# is the backstop against a cycle no one predicted.
RECURSION_LIMIT = 40


@dataclass
class TurnRequest:
    """Everything the client holds, handed back for one turn."""

    messages: list[dict] = field(default_factory=list)
    pinned: list[dict] = field(default_factory=list)
    covered: dict[str, bool] = field(default_factory=dict)
    draft: dict = field(default_factory=dict)
    base_url: str = ""
    model: str = ""
    helper_model: str = ""
    temperature: float = 0.4
    think: bool = False
    agentic: bool = True
    model_thinks: bool = False
    helper_thinks: bool = False

    @classmethod
    def from_json(cls, body: dict, cfg: Config) -> "TurnRequest":
        return cls(
            messages=body.get("messages") or [],
            pinned=body.get("pinned") or [],
            covered=body.get("covered") or {},
            draft=body.get("draft") or {},
            base_url=(body.get("baseUrl") or cfg.ollama).rstrip("/"),
            model=body.get("model") or "",
            helper_model=body.get("helperModel") or "",
            temperature=float(body.get("temperature", cfg.temperature)),
            think=bool(body.get("think")),
            agentic=bool(body.get("agentic", True)),
            model_thinks=bool(body.get("modelThinks")),
            helper_thinks=bool(body.get("helperThinks")),
        )


def to_messages(raw: list[dict]) -> list[AnyMessage]:
    """Client transcript -> LangChain messages.

    The client stores tool calls without ids, because it never needed them.
    LangChain pairs a call to its result by id, so ids are minted here and
    matched positionally: the client appends each tool result directly after
    the assistant turn that asked for it, in order, which is enough to pair
    them exactly. An unpaired result is dropped rather than sent — a
    ToolMessage with no matching call is rejected outright by some models.
    """
    out: list[AnyMessage] = []
    pending: list[str] = []

    for i, message in enumerate(raw):
        role = message.get("role")
        content = message.get("content") or ""

        if role == "user":
            out.append(HumanMessage(content))
            pending = []

        elif role == "assistant":
            calls = []
            for j, call in enumerate(message.get("tool_calls") or []):
                fn = call.get("function") or call
                args = fn.get("arguments")
                calls.append({
                    "name": fn.get("name") or "",
                    "args": args if isinstance(args, dict) else {},
                    "id": call.get("id") or f"call_{i}_{j}",
                })
            pending = [c["id"] for c in calls]
            if content.strip() or calls:
                out.append(AIMessage(content=content, tool_calls=calls))

        elif role == "tool" and pending:
            out.append(ToolMessage(content=content,
                                   name=message.get("name") or "",
                                   tool_call_id=pending.pop(0)))

    return out


class Agent:
    def __init__(self, corpus, bm25, cfg: Config):
        self.corpus = corpus
        self.bm25 = bm25
        self.cfg = cfg
        self.graph = build()

    def run(self, req: TurnRequest) -> Iterator[dict[str, Any]]:
        if not req.model:
            yield {"type": "error", "message": "No model selected.", "status": None}
            yield {"type": "done"}
            return

        state = {
            "messages": to_messages(req.messages),
            "pinned": req.pinned,
            "covered": req.covered,
            "draft": req.draft,
            "options": [],
            "asked_step": None,
            "separate": [],
            "hops": 0,
        }
        config = {
            "configurable": {
                "cfg": self.cfg,
                "corpus": self.corpus,
                "bm25": self.bm25,
                "base_url": req.base_url or self.cfg.ollama,
                "model": req.model,
                "helper_model": req.helper_model,
                "temperature": req.temperature,
                "timeout": self.cfg.timeout,
                "think": req.think,
                "agentic": req.agentic,
                "model_thinks": req.model_thinks,
                "helper_thinks": req.helper_thinks,
            },
            "recursion_limit": RECURSION_LIMIT,
        }

        try:
            # "custom" only: the nodes publish exactly the events the browser
            # reads, so nothing has to be translated after the fact.
            yield from self.graph.stream(state, config, stream_mode="custom")
        except Exception as err:                        # noqa: BLE001 - reported, not swallowed
            yield {"type": "error", **describe(err)}

        yield {"type": "done"}


def describe(err: Exception) -> dict:
    """Turn an exception into something the drawer can act on.

    Ollama's failures are not interchangeable and the useful next step differs
    completely between them — a retired hosted model in particular still
    appears in the picker and fails only when you talk to it, which looks like
    a bug in the page unless it is named.
    """
    text = f"{type(err).__name__}: {err}"
    status = getattr(err, "status_code", None)
    if status is None:
        match = re.search(r"\b(40[34]|410|500|502|503)\b", str(err))
        status = int(match.group(1)) if match else None
    if status is None and re.search(r"connect|refused|unreachable|timed out",
                                    str(err), re.I):
        text = f"Could not reach Ollama: {err}"
    return {"message": text, "status": status}
