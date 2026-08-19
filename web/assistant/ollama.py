"""Listing Ollama's models, over urllib.

Deliberately not LangChain. Everything else that talks to a model goes
through `llm.py` and the assistant extra, but the model picker has to work in
a checkout that installed nothing — otherwise a missing extra shows up as an
empty dropdown rather than as the one sentence that explains it.

It also reports more than LangChain would: which models can call tools, which
think, and which are proxied to Ollama's cloud rather than running here.
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.request

from config import get as _config


class OllamaError(RuntimeError):
    """Carries the status code, because the right advice differs by code.

    A 410 in particular is not a transport failure: Ollama keeps listing
    hosted models after they are retired, so they appear in the picker and
    fail only when you talk to them.
    """

    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


def list_models(base: str | None = None, timeout: float = 10) -> list[dict]:
    base = (base or _config().ollama).rstrip("/")
    try:
        with urllib.request.urlopen(f"{base}/api/tags", timeout=timeout) as r:
            models = json.load(r).get("models", [])
    except urllib.error.HTTPError as err:
        raise OllamaError(f"Ollama /api/tags: {err.code}", err.code) from None
    except (urllib.error.URLError, TimeoutError) as err:
        raise OllamaError(f"Could not reach Ollama at {base}: {err}") from None

    out = []
    for m in models:
        caps = m.get("capabilities") or []
        name = m.get("name", "")
        out.append({
            "name": name,
            "size": m.get("size"),
            "parameters": (m.get("details") or {}).get("parameter_size"),
            "tools": "tools" in caps,
            "thinking": "thinking" in caps,
            "embedding": "embedding" in caps or "embed" in name.lower(),
            # Ollama proxies some models to its cloud. Only metadata is ever
            # sent, but with a hosted model that metadata leaves the machine,
            # which should be a deliberate choice rather than a consequence
            # of picking the top of a list.
            "hosted": bool(m.get("remote_host")) or bool(re.search(r"(^|[:-])cloud\b", name)),
        })
    return out


