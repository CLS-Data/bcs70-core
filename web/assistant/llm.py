"""Building the two models a turn uses.

The interviewer, and a helper. The helper does the small mechanical jobs —
filling in the draft, and rescuing answer buttons from a model that didn't
mark its own — and defaults to the interviewer when none is chosen. Neither
needs the other's settings: the interview wants a little temperature, the
structured calls want none.
"""

from __future__ import annotations

from langchain_ollama import ChatOllama


def _build(*, model: str, base_url: str, temperature: float,
           thinks: bool, reasoning: bool, timeout: int) -> ChatOllama:
    kwargs = {
        "model": model,
        "base_url": base_url,
        "temperature": temperature,
        "client_kwargs": {"timeout": timeout},
    }
    # Only sent to a model that advertises thinking; it is an error, not a
    # no-op, on the rest.
    #
    # `reasoning=False` genuinely reduces the work on models that honour it,
    # and misfires badly on ones that do not: qwen3 reasons anyway and, told
    # not to, stops putting the working in Ollama's `thinking` field and dumps
    # it into the answer instead, trailing a stray `</think>`. Sending it is
    # only safe because `graph._speak` strips inline reasoning back out — do
    # not remove one without the other.
    if thinks:
        kwargs["reasoning"] = reasoning
    return ChatOllama(**kwargs)


def interviewer(run: dict) -> ChatOllama:
    """The model that holds the conversation."""
    return _build(
        model=run["model"],
        base_url=run["base_url"],
        temperature=run["temperature"],
        thinks=run["model_thinks"],
        # Off by default: "which sweeps do you mean?" is not a question that
        # improves for half a minute of deliberation, and the wait is per turn.
        reasoning=bool(run.get("think")),
        timeout=run["timeout"],
    )


def structured(run: dict, schema: dict) -> object:
    """A helper model that must answer as one JSON object matching `schema`.

    `format` is a request, not a guarantee — models answer it loosely and drop
    required keys — so every caller still checks what came back rather than
    trusting the shape.
    """
    model = _build(
        model=run.get("helper_model") or run["model"],
        base_url=run["base_url"],
        temperature=0,
        thinks=run["helper_thinks"],
        reasoning=False,
        timeout=run["timeout"],
    )
    return model.with_structured_output(schema, method="json_schema")
