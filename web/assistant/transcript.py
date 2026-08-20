"""The conversation as the browser sends it, planned into messages.

The server is stateless: the client holds the conversation and posts the
whole thing back each turn. Turning that into what a model expects is not a
straight mapping, and the two things it has to get right are the two things
that have gone wrong:

**Pairing a tool result to the call that asked for it.** The client stores
tool calls without ids, because nothing in the browser ever needed them.
Models pair by id, so ids are minted here and matched positionally — the
client appends each result directly after the assistant turn that asked for
it, in order, which is enough to pair them exactly. A result with no call in
front of it is dropped rather than sent: some models reject an unpaired tool
message outright, taking the whole turn with it.

**Carrying what each lookup returned.** The result's text is the model's own
record of what it already searched. When the event that reaches the browser
omitted it, every tool call in the history came back paired with an empty
string, and a model reading that either searches the same thing again or
reports a concept as absent because its record of finding it is blank.

Standard library, and separate from `agent.py`, for the reason
`Config.hops_spent` is separate from `graph.py`: `agent.py` imports LangChain,
so nothing inside it can be tested in a checkout that installed nothing —
which is every CI run. This is the part worth testing, so it lives where the
tests can reach it. `agent.to_messages` maps the plan onto message classes and
does nothing else.
"""

from __future__ import annotations

HUMAN = "human"
AI = "ai"
TOOL = "tool"


def plan(raw: list[dict]) -> list[dict]:
    """Client messages -> `{kind, ...}` records, ids minted, orphans dropped.

    Deliberately plain dicts. The caller builds the message objects; this
    decides what they are and how they pair up.
    """
    out: list[dict] = []
    pending: list[str] = []

    for i, message in enumerate(raw or []):
        role = (message or {}).get("role")
        content = message.get("content") or ""

        if role == "user":
            out.append({"kind": HUMAN, "content": content})
            # A new turn from the researcher ends any call still waiting for
            # its result: nothing after this can belong to it.
            pending = []

        elif role == "assistant":
            calls = []
            for j, call in enumerate(message.get("tool_calls") or []):
                fn = call.get("function") or call
                args = fn.get("arguments")
                calls.append({
                    "name": fn.get("name") or "",
                    # A model that answered its own schema loosely can send a
                    # string here. An empty dict is a tool call that returns
                    # nothing useful; a string is one that raises.
                    "args": args if isinstance(args, dict) else {},
                    "id": call.get("id") or f"call_{i}_{j}",
                })
            pending = [c["id"] for c in calls]
            # An assistant turn with neither prose nor calls is an artefact of
            # the client opening a reply it never filled.
            if content.strip() or calls:
                out.append({"kind": AI, "content": content, "tool_calls": calls})

        elif role == "tool" and pending:
            out.append({
                "kind": TOOL,
                "content": content,
                "name": message.get("name") or "",
                "tool_call_id": pending.pop(0),
            })

    return out
