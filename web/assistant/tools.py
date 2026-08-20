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

import re

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
                    f"Search the {cfg.name} data dictionaries for raw variables "
                    f"BY MEANING. Returns matches grouped by description with "
                    f"the {waves} each appears in. Use this whenever you need to "
                    f"know whether something was measured, what it was called, "
                    f"or at which {cfg.wave_indexed_by}s — never guess, and "
                    f"never ask the researcher something you can look up. If "
                    f"you already have an exact variable name, use {INSPECT} "
                    f"instead: it answers about that one variable directly."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": (
                                "Plain words describing what to find, e.g. "
                                "'weight in kilograms'. Use the language a "
                                "questionnaire would use. To look up a known "
                                f"name such as {example}, call {INSPECT}."
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
                    "Look up ONE variable by its exact name and read its full "
                    "dictionary entry: label, type, declared missing values and "
                    "every value label with its code. This is the tool to use "
                    f"whenever you already have a name — {SEARCH} is for when "
                    "you have a concept and need to find out what it was "
                    "called. Use this before deciding what the missing-value "
                    "codes mean and how they should be handled: the schemes are "
                    "not consistent between variables. Names are matched "
                    "exactly and never guessed at; if the name does not exist "
                    "you are told so, sometimes with similar names to choose "
                    "from — pick one deliberately rather than assuming."
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


# Names that differ from this one only in their digits.
#
# Deliberately NOT edit distance. In a corpus of codes the digits carry the
# meaning: b960433/b960434/b960436 are height in feet, inches and metres, all
# one edit apart, so a fuzzy match returns a plausible and wrong variable that
# nothing downstream can catch. Stripping the digits instead asks a different
# question - "is this the same question asked elsewhere?" - which is the miss
# that actually happens, a half-remembered wave prefix (b8hlthgn/b9hlthgn).
#
# The alphabetic remainder has to be substantial: a core of "b" means the
# digits ARE the name, and everything with that core is unrelated.
MIN_CORE = 3
MAX_SUGGESTIONS = 12


def _digit_core(name: str) -> str:
    return re.sub(r"\d+", "", str(name).lower())


def _near_misses(corpus, name: str) -> tuple[list[str], int]:
    """Real names that might be what was meant. Never a substitute for one."""
    core = _digit_core(name)
    if len(core) < MIN_CORE:
        return [], 0

    seen, out = set(), []
    for row in corpus.vars:
        other = str(row[0])
        key = other.lower()
        if key in seen or key == name.lower():
            continue
        if _digit_core(other) == core:
            seen.add(key)
            out.append(other)

    out.sort()
    return out[:MAX_SUGGESTIONS], len(out)


def _inspect(corpus, cfg: Config, args: dict) -> tuple[str, dict]:
    name = str(args.get("name") or "").strip()
    wave = args.get(cfg.wave_term) or None

    rows = corpus.rows_named(name)
    if not rows:
        # Offer candidates; never resolve to one. A wrong identifier that the
        # model was handed confidently is worse than no answer, because the
        # variable it names is real and its label will read plausibly.
        near, total = _near_misses(corpus, name)
        if total > MAX_SUGGESTIONS:
            hint = (
                f" {total} variables share the stem, too many to list - "
                f"search for the concept instead, or give an exact name."
            )
        elif near:
            hint = (
                f" These exist and may be what you meant: {', '.join(near)}. "
                f"Ask for one of them by name - do not assume which is right."
            )
        else:
            hint = " Search for the concept instead."
        return (
            f'No variable called "{name}" exists in any dictionary. Do not use '
            f"this name.{hint}",
            {"note": f'"{name}" not found', "suggestions": near},
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
