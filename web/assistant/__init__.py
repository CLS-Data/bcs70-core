"""The variable-request assistant.

Everything the assistant *is* lives here: the interview it conducts, the
prompts it runs on, the tools it can call over the dictionaries, and the
LangGraph that ties them together. `web/server.py` exposes it over HTTP and
the browser draws it; neither knows how it works.

What it asks and what it is called come from `dataset.toml`, not from this
package. Nothing here knows which dataset it is looking at.

Nothing here can reach study data, for the same reason nothing else in this
site can: the corpus it searches is the metadata JSON that `build_site.py`
emits, which is variable names, labels and value labels.

Two halves, deliberately:

- **Standard library** — `corpus`, `retrieval`, `choices`, `prompts`,
  `tools`' executors, and `ollama.list_models`. These are what the atlas, the
  metadata search and the model picker need, and they must keep working in a
  checkout that installed nothing.
- **The assistant extra** — `graph`, `llm`, `agent`. These need LangGraph,
  and importing this package does not pull them in. `load()` does, and says
  plainly what to install when it cannot.

      uv sync --extra assistant
"""

from __future__ import annotations

import sys
from pathlib import Path

# `config` lives one level up, beside this package. Both entry points already
# put that directory on the path; this makes the package importable on its own
# too, which is what the tests do.
_WEB = str(Path(__file__).resolve().parent.parent)
if _WEB not in sys.path:
    sys.path.insert(0, _WEB)

from .corpus import Corpus, CorpusMissing   # noqa: E402

__all__ = ["Corpus", "CorpusMissing", "load", "MISSING"]

MISSING = (
    "The assistant needs its optional dependencies:\n"
    "    uv sync --extra assistant\n"
    "(or: uv pip install 'langgraph>=1.2,<2' 'langchain-ollama>=1.0,<2')\n"
    "The atlas, the metadata search and the registry work without them."
)


def load():
    """Return (Agent, TurnRequest), or raise ImportError naming the fix."""
    try:
        from .agent import Agent, TurnRequest
    except ImportError as err:
        raise ImportError(f"{err}\n\n{MISSING}") from err
    return Agent, TurnRequest
