"""The four tools the model can call over the corpus.

One per thing the interview actually gets stuck on: whether a concept was
measured at all, where it was measured, what a variable's codes mean, and
whether the repository has already harmonised it.

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
COVERAGE = "coverage"
HARMONISED = "list_harmonised"
NAMES = (SEARCH, INSPECT, COVERAGE, HARMONISED)


# ── Declarations ────────────────────────────────────────────────────────

def schemas(cfg: Config, intent=None) -> list[dict]:
    """OpenAI-style function schemas, worded from the dataset's own terms.

    `intent` narrows them to the lookups it declares. Binding is the
    enforcement point: a tool the model is never shown is a tool it cannot
    ask for, which is steadier than refusing the call afterwards.
    """
    wave, waves = cfg.wave_term, cfg.wave_plural
    example = cfg.name_examples[0] if cfg.name_examples else "abc123"

    declared = [
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
                "name": COVERAGE,
                "description": (
                    f"Report a concept {wave} by {wave}: which {waves} measured "
                    f"it, what the variable is called in each, and which have "
                    f"nothing. Use this for any question about coverage across "
                    f"{waves} — 'which {waves} have X', 'is X available "
                    f"throughout', 'can I follow X over time' — and before "
                    f"proposing a longitudinal variable. {SEARCH} ranks all "
                    f"{waves} against each other and returns only the best few "
                    f"overall, so it cannot answer this: a {wave} whose variable "
                    f"scores lower looks like a {wave} with nothing."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "concept": {
                            "type": "string",
                            "description": (
                                "The concept in the fewest plain words that "
                                "identify it — 'general health', 'cigarettes "
                                "per day'. Not a variable name, and not a "
                                "qualified phrase: every extra word narrows "
                                "the match, so 'self-rated general health' "
                                f"finds fewer {waves} than 'general health' "
                                "does. Use the words a questionnaire would "
                                "print, and call again with a different "
                                "wording if the result looks thin."
                            ),
                        },
                    },
                    "required": ["concept"],
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
    if intent is None:
        return declared
    return [s for s in declared
            if cfg.may_use(intent, s["function"]["name"])]


def lc_tools(cfg: Config, intent=None):
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
        for spec in schemas(cfg, intent)
    ]


# ── Executors ───────────────────────────────────────────────────────────

def _search(corpus, bm25, cfg: Config, args: dict,
            retriever=None, settings=None) -> tuple[str, dict]:
    query = str(args.get("query") or "").strip()
    wave = args.get(cfg.wave_term) or None
    if not query:
        return "No query given. Call this with what you are looking for.", {"note": "empty query"}

    limit = getattr(settings, "candidates", None) or cfg.candidates
    found = retrieval.search_grouped(corpus, bm25, query, limit=limit, wave=wave,
                                     retriever=retriever, settings=settings)

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

    # How the answer was reached is part of the answer. The transcript shows
    # every lookup, and "also tried these three wordings" is what tells a
    # researcher whether a thin result means the study lacks the concept or
    # only that the search missed it.
    how = found.get("how") or {}
    also = [q for q in (how.get("queries") or [])[1:]]
    method = []
    if how.get("semantic"):
        method.append("by meaning as well as by words")
    if also:
        method.append(f'also searched: {", ".join(also)}')
    if how.get("note"):
        method.append(how["note"])
    if method:
        head += f' ({"; ".join(method)})'

    return f"{head}:\n{lines}", {
        "groups": groups,
        "queries": how.get("queries") or [query],
        "semantic": bool(how.get("semantic")),
        "note": "hybrid" if how.get("semantic") else "lexical",
    }


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


def _coverage(corpus, bm25, cfg: Config, args: dict,
              retriever=None, settings=None) -> tuple[str, dict]:
    concept = str(args.get("concept") or args.get("query") or "").strip()
    if not concept:
        return "No concept given. Call this with what to look for.", {"note": "empty query"}

    found = retrieval.coverage(corpus, bm25, concept, retriever, settings)
    if found["unknown_terms"]:
        return (
            f'Nothing in "{concept}" appears in any dictionary. Try the wording '
            f"a questionnaire would use.",
            {"waves": [], "note": "no usable terms"},
        )

    lines, measured, weak = [], [], []
    for entry in found["waves"]:
        wave = entry["wave"]
        if not entry["matches"]:
            lines.append(f"{wave}: nothing found")
            continue
        shown = ", ".join(
            f'{m["name"]} ({m["label"] or "no label"})' for m in entry["matches"]
        )
        if entry["measured"]:
            measured.append(wave)
            lines.append(f"{wave}: MEASURED — {shown}")
        else:
            weak.append(wave)
            lines.append(f"{wave}: possible, unconfirmed — {shown}")

    # The summary goes first because it is the answer; the per-wave detail is
    # the evidence for it. A model given only the detail tends to restate it.
    head = (
        f'"{concept}" is measured at: {", ".join(measured) or "no " + cfg.wave_plural}.'
    )
    if weak:
        # Naming the unconfirmed waves and stopping there reads as "nothing
        # here", and a model asked to summarise will fold them in with the
        # waves that genuinely have nothing - which is how a real variable
        # like "How is your health generally" gets reported as absent. The
        # instruction has to be explicit that these are a third answer.
        head += (
            f' {len(weak)} more {cfg.wave_plural} have candidates that need '
            f'judging, listed below as "possible": {", ".join(weak)}. Read each '
            f"label. Some will be the concept under different wording and some "
            f"will be a coincidence of vocabulary; decide which, and report "
            f'them separately. Never fold these in with "nothing found" - that '
            f"is a different finding, and reporting it as absent is wrong."
        )
    if not measured:
        # Every extra word raises the total idf mass a label has to account
        # for, so a precise-sounding concept scores worse than a plain one:
        # "self rated general health" confirms nothing, while "general health"
        # confirms five waves. The model cannot see that from the result, so
        # the result has to say it.
        head += (
            f" Nothing reached confirmation for this wording. If the concept "
            f"carries qualifiers, try again with the plainest two or three "
            f"words a questionnaire would print — extra words narrow this and "
            f"can hide {cfg.wave_plural} that do have the variable."
        )

    # This result is wide, and a wide result invites a verifying lookup per
    # candidate - which is how a turn spends its whole hop budget confirming
    # what it was already told and ends with nothing said. Every label needed
    # to answer is already here.
    head += (
        f" Every candidate's label is below: that is enough to answer which "
        f"{cfg.wave_plural} have this. Look a variable up individually only if "
        f"its codes or missing values matter to the answer."
    )

    return f"{head}\n" + "\n".join(lines), {
        "coverage": found["waves"],
        "note": f'{len(measured)} {cfg.wave_plural} measured, {len(weak)} unconfirmed',
    }


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


def run(corpus, bm25, cfg: Config, name: str, args: dict,
        retriever=None, settings=None) -> tuple[str, dict]:
    if name == SEARCH:
        return _search(corpus, bm25, cfg, args, retriever, settings)
    if name == INSPECT:
        return _inspect(corpus, cfg, args)
    if name == COVERAGE:
        return _coverage(corpus, bm25, cfg, args, retriever, settings)
    if name == HARMONISED:
        return _harmonised(corpus, args)
    return (
        f'No tool called "{name}". Available: {", ".join(NAMES)}.',
        {"note": f'unknown tool "{name}"'},
    )
