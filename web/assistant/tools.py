"""The three tools the model can call over the corpus.

One per thing the interview actually gets stuck on: whether a concept was
measured at all, what a variable's codes mean, and whether the repository has
already harmonised it.

Each executor returns `(text, display)`. `text` is what the model reads and
is kept terse — an 8B model handed three screens of dictionary output stops
conducting an interview and starts summarising a spreadsheet. `display` is
what the transcript shows, and can afford to be richer. A LangChain tool's
return value has room for only one of those, which is why `graph.lookups`
calls these directly rather than going through a prebuilt ToolNode.
"""

from __future__ import annotations

from config import Config

from . import retrieval

SEARCH = "search_variables"
INSPECT = "inspect_variable"
HARMONISED = "list_harmonised"
NAMES = (SEARCH, INSPECT, HARMONISED)


# ── Declarations ────────────────────────────────────────────────────────

def schemas(cfg: Config) -> list[dict]:
    """OpenAI-style function schemas, worded from the dataset's own terms."""
    wave, waves = cfg.wave_term, cfg.wave_plural
    example = cfg.name_examples[0] if cfg.name_examples else "abc123"

    return [
        {
            "type": "function",
            "function": {
                "name": SEARCH,
                "description": (
                    f"Search the {cfg.name} data dictionaries for raw variables, "
                    f"by meaning or by exact name. Returns matches grouped by "
                    f"description with the {waves} each appears in. Use this "
                    f"whenever you need to know whether something was measured, "
                    f"what it was called, or at which {cfg.wave_indexed_by}s — "
                    f"never guess, and never ask the researcher something you "
                    f"can look up."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": (
                                "Plain words describing what to find (e.g. "
                                "'weight in kilograms'), or an exact variable "
                                f"name such as {example}."
                            ),
                        },
                        # Named from the dataset's own term, so the model is
                        # asked for a "sweep" or a "visit" rather than being
                        # told about one and asked for the other.
                        wave: {
                            "type": "string",
                            "description": (
                                f"Optional single {wave} to restrict to: "
                                f"{', '.join(cfg.waves)}."
                            ),
                        },
                    },
                    "required": ["query"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": INSPECT,
                "description": (
                    "Read one raw variable's full dictionary entry: label, type, "
                    "declared missing values and every value label with its code. "
                    "Use this before deciding what the missing-value codes mean "
                    "and how they should be handled — the schemes are not "
                    "consistent between variables."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string", "description": "Exact variable name."},
                        wave: {
                            "type": "string",
                            "description": f"Optional {wave}, if the name appears in several.",
                        },
                    },
                    "required": ["name"],
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": HARMONISED,
                "description": (
                    "List variables THIS REPOSITORY has already harmonised — a "
                    "small hand-built registry, not the study's own data. Use it "
                    "to check whether the concept has been done here before, or "
                    "to follow an existing family's precedent. It is NOT how you "
                    "find variables the depositor already derived: those live in "
                    "the dictionaries, usually labelled '(Derived)', and are "
                    "found with search_variables."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Optional filter on name, label or family.",
                        },
                    },
                },
            },
        },
    ]


def lc_tools(cfg: Config):
    """The same schemas as LangChain tool objects, for binding onto a model.

    Declaration only — the functions are never invoked through LangChain, for
    the two-return-values reason in the module docstring. Imported lazily so
    this module keeps working without the assistant extra installed:
    `/api/search` needs the executors below and nothing else.
    """
    from langchain_core.tools import StructuredTool

    return [
        StructuredTool.from_function(
            func=lambda **_: "",          # never called; see above
            name=spec["function"]["name"],
            description=spec["function"]["description"],
            args_schema=spec["function"]["parameters"],
        )
        for spec in schemas(cfg)
    ]


# ── Executors ───────────────────────────────────────────────────────────

def _search(corpus, bm25, cfg: Config, args: dict) -> tuple[str, dict]:
    query = str(args.get("query") or "").strip()
    wave = args.get(cfg.wave_term) or None
    if not query:
        return "No query given. Call this with what you are looking for.", {"note": "empty query"}

    found = retrieval.search_grouped(corpus, bm25, query,
                                     limit=cfg.candidates, wave=wave)

    if found["unknown_wave"]:
        return (
            f'No {cfg.wave_term} called "{found["unknown_wave"]}". '
            f'The {cfg.wave_plural} are: {", ".join(corpus.waves)}.',
            {"groups": [], "note": f'unknown {cfg.wave_term} "{found["unknown_wave"]}"'},
        )

    groups = found["groups"]
    if not groups:
        scope = f" in {wave}" if wave else ""
        return (
            f'No variable matches "{query}"{scope}. Try different wording — the '
            f"dictionaries use the language of the original questionnaires.",
            {"groups": [], "note": "no matches"},
        )

    lines = "\n".join(
        f'{", ".join(g["names"])} | {cfg.wave_plural}: {" ".join(g["waves"])} | '
        f'{g["label"] or "no label"}'
        for g in groups
    )
    head = f'{len(groups)} match{"" if len(groups) == 1 else "es"}'
    if wave:
        head += f" in {wave}"
    return f"{head}:\n{lines}", {"groups": groups, "note": "lexical"}


def _inspect(corpus, cfg: Config, args: dict) -> tuple[str, dict]:
    name = str(args.get("name") or "").strip()
    wave = args.get(cfg.wave_term) or None

    rows = corpus.rows_named(name)
    if not rows:
        return (
            f'No variable called "{name}" exists in any dictionary. Do not use '
            f"this name. Search for the concept instead.",
            {"note": f'"{name}" not found'},
        )

    doc = rows[0]
    if wave:
        doc = next((d for d in rows if corpus.wave_of(d) == wave), rows[0])

    entry = corpus.entry(doc) or {}
    values = entry.get("values") or []
    codes = (
        "\n".join(f'  {v.get("value")} = {v.get("label")}' for v in values)
        if values
        else "  none recorded (which does not guarantee the real file has none)"
    )

    seen: list[str] = []
    for d in rows:
        w = corpus.wave_of(d)
        if w not in seen:
            seen.append(w)
    also = f'\nAlso appears in: {", ".join(seen)}' if len(seen) > 1 else ""

    real_name, label = corpus.vars[doc][0], corpus.vars[doc][1]
    file = corpus.file_of(doc)
    text = (
        f'{real_name} [{corpus.wave_of(doc)}, {file.get("name")}]\n'
        f'label: {label or "none"}\n'
        f'type: {entry.get("type") or "unrecorded"} | '
        f'measurement: {entry.get("measurement") or "unrecorded"}\n'
        f'declared missing: {entry.get("missing") or "none declared"}\n'
        f"value labels:\n{codes}{also}"
    )
    display = {
        "variable": {
            "name": real_name, "label": label,
            "wave": corpus.wave_of(doc), "file": file.get("name"),
            "missing": entry.get("missing"), "values": values,
        },
        "note": f'{len(values)} value label{"" if len(values) == 1 else "s"}',
    }
    return text, display


def _harmonised(corpus, args: dict) -> tuple[str, dict]:
    query = str(args.get("query") or "").strip()
    needle = query.lower()
    matches = [
        d for d in corpus.derived
        if not needle
        or needle in d.get("id", "").lower()
        or needle in (d.get("label") or "").lower()
        or needle in (d.get("family") or "").lower()
    ]

    if not matches:
        # Said carefully. The registry being empty of something says nothing
        # about the study, and reporting "no precedent" flatly was read as
        # "this variable does not exist" for a concept measured at six waves.
        scope = (f'No variable harmonised in this repository matches "{query}".'
                 if needle else "This repository has harmonised nothing yet.")
        return (
            f"{scope} That is only about this registry — it does not mean the "
            f"study lacks the concept. Use search_variables to find out what "
            f"the dictionaries hold, including any the depositor derived.",
            {"derived": [], "note": "nothing harmonised here"},
        )

    shown = matches[:20]
    lines = []
    for d in shown:
        sources = d.get("source_vars") or []
        tail = f' | from: {", ".join(sources[:6])}' if sources else ""
        lines.append(
            f'{d["id"]} [{d.get("category")}/{d.get("family")}, {d.get("status")}] '
            f'{d.get("label")}{tail}'
        )
    head = f"{len(matches)} already harmonised"
    if needle:
        head += f' matching "{query}"'

    slim = [
        {k: d.get(k) for k in ("id", "label", "family", "category", "status")}
        for d in shown
    ]
    return f"{head}:\n" + "\n".join(lines), {"derived": slim,
                                            "note": f"{len(matches)} in the registry"}


def run(corpus, bm25, cfg: Config, name: str, args: dict) -> tuple[str, dict]:
    if name == SEARCH:
        return _search(corpus, bm25, cfg, args)
    if name == INSPECT:
        return _inspect(corpus, cfg, args)
    if name == HARMONISED:
        return _harmonised(corpus, args)
    return (
        f'No tool called "{name}". Available: {", ".join(NAMES)}.',
        {"note": f'unknown tool "{name}"'},
    )
