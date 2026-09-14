"""Loading `dataset.toml`.

One config, read by everything: `build_site.py`, `server.py`, and the whole
assistant. The browser never reads this file — `build_site.py` bakes the
parts it needs into `data/manifest.json`, so there is no second copy of the
categories or the wave order to fall out of step.

Standard library: `tomllib` has been in it since 3.11 and this project
targets 3.13.

Everything here is frozen. A config that a request handler could mutate is a
config that differs between two requests, and this one is read on every turn.
"""

from __future__ import annotations

import os
import subprocess
import tomllib
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

WEB = Path(__file__).resolve().parent
REPO = WEB.parent
DEFAULT_CONFIG = WEB / "dataset.toml"

# Overridable so a second dataset can live alongside the first:
#     ATLAS_DATASET_CONFIG=web/other.toml python3 web/server.py
ENV_VAR = "ATLAS_DATASET_CONFIG"

# How an intent may be entered. Named rather than spelled out at each use, so
# a typo in the config is caught by `validate()` instead of quietly making an
# intent unreachable.
ROUTER = "router"      # the router may choose it on any message
HANDOFF = "handoff"    # only ever entered by a proposal the researcher accepts
ENTRIES = (ROUTER, HANDOFF)

# Every tool. The default, so an intent that says nothing about tools keeps
# the whole toolbox rather than losing it to an empty list.
ALL_TOOLS = "*"


class ConfigError(RuntimeError):
    pass


@dataclass(frozen=True)
class Step:
    """One question in the interview."""

    id: str
    title: str
    goal: str
    probes: tuple[str, ...]
    replies: tuple[str, ...]

    def as_json(self) -> dict:
        return {
            "id": self.id, "title": self.title, "goal": self.goal,
            "probes": list(self.probes), "replies": list(self.replies),
        }


@dataclass(frozen=True)
class NoteSlot:
    key: str
    heading: str
    asks: str


@dataclass(frozen=True)
class Intent:
    """One thing the assistant can be asked to do.

    Everything an intent changes about a turn is declared here, so adding one
    stays a config change. It did not use to be: `prompts.py` compared
    `intent.id` against "interview" to decide two of these, and the browser
    compared against "explore" to decide the third, so an intent added later
    silently got the wrong behaviour whatever its config said.
    """

    id: str
    label: str
    description: str
    instructions: str
    advances: bool          # does answering this move the checklist on?
    shows_checklist: bool   # is the checklist's state woven into the prompt?
    offers_choices: bool    # may the reply end with answer buttons?
    heuristic: str          # "question" marks where the fallback rule sends one

    # How a turn ENTERS this intent and how it leaves. Without these the
    # router picks afresh on every message, which is right for answering a
    # question and wrong for an interview: a researcher asking "which sweeps
    # have this?" halfway through would be routed out of the very thing they
    # asked to start.
    sticky: bool            # once here, stay until an exit signal
    entry: str              # "router" — chosen per message | "handoff" — only
                            # ever entered by a proposal the researcher accepts
    confirm: str            # how to phrase that proposal
    exits_to: str           # which intent a sticky one returns to ("" = fallback)
    extracts: bool          # does the draft extractor run after the reply?
    tools: tuple[str, ...]  # lookups this intent may call ("*" = all of them)
    replies: tuple[str, ...]  # answers offered with its proposal

    @property
    def entered_by_handoff(self) -> bool:
        return self.entry == HANDOFF


@dataclass(frozen=True)
class Category:
    label: str
    slug: str


class Config:
    """Typed, read-only access to `dataset.toml`."""

    def __init__(self, raw: dict, path: Path):
        self._raw = raw
        self.path = path

    # -- loading ---------------------------------------------------------

    @classmethod
    def load(cls, path: Path | str | None = None) -> "Config":
        chosen = Path(path or os.environ.get(ENV_VAR) or DEFAULT_CONFIG)
        if not chosen.is_absolute():
            chosen = REPO / chosen
        if not chosen.exists():
            raise ConfigError(f"dataset config not found: {chosen}")
        with chosen.open("rb") as fh:
            raw = tomllib.load(fh)
        cfg = cls(raw, chosen)
        cfg.validate()
        return cfg

    def validate(self) -> None:
        """Fail at start-up rather than mid-conversation."""
        missing = [k for k in ("dataset", "wave", "metadata", "issue",
                               "assistant", "retrieval", "interview")
                   if k not in self._raw]
        if missing:
            raise ConfigError(f"{self.path}: missing section(s): {', '.join(missing)}")
        if not self.waves:
            raise ConfigError(f"{self.path}: [wave] order is empty")
        if not self.categories:
            raise ConfigError(f"{self.path}: no [[category]] entries")
        if not self.steps:
            raise ConfigError(f"{self.path}: no [[interview.step]] entries")
        if not self.intents:
            raise ConfigError(f"{self.path}: no [[intent]] entries")

        ids = [s.id for s in self.steps]
        if len(set(ids)) != len(ids):
            raise ConfigError(f"{self.path}: duplicate interview step id(s)")

        self._validate_intents()

        fields = self._raw["issue"].get("fields") or {}
        for key in ("name", "waves", "category", "description", "sources", "notes"):
            if key not in fields:
                raise ConfigError(f"{self.path}: [issue.fields] is missing '{key}'")

    def _validate_intents(self) -> None:
        """Every way an intent can be unreachable, caught at start-up.

        These are not hypothetical. An intent nothing can route to and nothing
        can hand off to is a config the assistant loads happily and then never
        uses, and the symptom — a capability that simply never appears — gives
        no hint where to look.
        """
        where = f"{self.path}: [[intent]]"

        ids = self.intent_ids
        if len(set(ids)) != len(ids):
            raise ConfigError(f"{where} duplicate id(s)")

        fallback = self.fallback_intent
        if fallback.entered_by_handoff:
            raise ConfigError(
                f'{where} "{fallback.id}" is the fallback but is entered by '
                f"handoff, so nothing could ever reach it")
        if fallback.sticky:
            raise ConfigError(
                f'{where} "{fallback.id}" is the fallback and sticky, so a '
                f"conversation would start in it and never leave")

        for i in self.intents:
            if i.entry not in ENTRIES:
                raise ConfigError(
                    f'{where} "{i.id}" has entry "{i.entry}"; expected one of '
                    f"{', '.join(ENTRIES)}")
            if i.exits_to and i.exits_to not in ids:
                raise ConfigError(
                    f'{where} "{i.id}" exits_to "{i.exits_to}", which is not an intent')
            if i.exits_to == i.id:
                raise ConfigError(f'{where} "{i.id}" exits to itself')
            if i.sticky and self.exit_intent(i).sticky:
                raise ConfigError(
                    f'{where} "{i.id}" is sticky and exits into another sticky '
                    f'intent, "{self.exit_intent(i).id}"')
            if i.entered_by_handoff and not i.confirm:
                raise ConfigError(
                    f'{where} "{i.id}" is entered by handoff but has no '
                    f"`confirm`, so there is nothing to propose with")
            if i.entered_by_handoff and len(i.replies) < 2:
                raise ConfigError(
                    f'{where} "{i.id}" is entered by handoff and needs at '
                    f"least two `replies` — an offer with no way to accept "
                    f"or decline it is not an offer")
            if not i.tools:
                raise ConfigError(
                    f'{where} "{i.id}" has an empty `tools`; omit it for all of '
                    f'them, or list the ones it may call')

    def _section(self, name: str) -> dict:
        return self._raw.get(name) or {}

    # -- the dataset -----------------------------------------------------

    @property
    def key(self) -> str:
        return self._section("dataset").get("key", "dataset")

    @property
    def name(self) -> str:
        return self._section("dataset").get("name", "Dataset")

    @property
    def full_name(self) -> str:
        return self._section("dataset").get("full_name", self.name)

    @property
    def tagline(self) -> str:
        return self._section("dataset").get("tagline", "variable atlas")

    @property
    def blurb(self) -> str:
        return " ".join(self._section("dataset").get("blurb", "").split())

    @property
    def about(self) -> str:
        """What the study is. Goes into the system prompt verbatim."""
        return " ".join(self._section("dataset").get("about", "").split())

    @cached_property
    def cautions(self) -> tuple[str, ...]:
        """Things to know before proposing a derivation."""
        return tuple(self._section("dataset").get("cautions") or ())

    @property
    def root(self) -> Path:
        return REPO / self._section("dataset").get("root", "data")

    @property
    def data_env(self) -> str:
        """Environment variable the R pipeline reads its data root from.

        Named here rather than in `build_site.py` so the instructions in a
        downloaded bundle stay a property of the dataset, like everything
        else in this file. Empty means the pipeline has no such override, and
        the bundle's README then documents only the relative layout.
        """
        return self._section("dataset").get("data_env", "")

    @property
    def identifier(self) -> str:
        return self._section("dataset").get("identifier", "id")

    @cached_property
    def examples(self) -> list[str]:
        """Starting points offered on the assistant's empty screen."""
        return list(self._section("dataset").get("examples") or ())

    # -- waves -----------------------------------------------------------

    @property
    def wave_term(self) -> str:
        return self._section("wave").get("term", "wave")

    @property
    def wave_plural(self) -> str:
        return self._section("wave").get("plural", f"{self.wave_term}s")

    @property
    def wave_indexed_by(self) -> str:
        return self._section("wave").get("indexed_by", "time")

    @cached_property
    def waves(self) -> tuple[str, ...]:
        return tuple(self._section("wave").get("order") or ())

    @property
    def cross_wave(self) -> str:
        return self._section("wave").get("cross", "")

    @property
    def cross_wave_note(self) -> str:
        return self._section("wave").get("cross_note", "")

    # -- metadata --------------------------------------------------------

    @property
    def lookup_csv(self) -> str:
        return self._section("metadata").get("lookup", "")

    @property
    def dictionary_suffix(self) -> str:
        return self._section("metadata").get("dictionary_suffix", "")

    @cached_property
    def measurement_levels(self) -> tuple[str, ...]:
        return tuple(self._section("metadata").get("measurement_levels") or ())

    @cached_property
    def columns(self) -> dict[str, str]:
        """Column names inside each data-dictionary CSV."""
        return dict(self._section("metadata").get("columns") or {})

    @cached_property
    def lookup_columns(self) -> dict[str, str]:
        """Column names inside the master lookup CSV."""
        defaults = {
            "wave": "sweep", "file_name": "file_name", "file_type": "file_type",
            "study": "study_number", "description": "description",
        }
        return {**defaults, **(self._section("metadata").get("lookup_columns") or {})}

    # -- corpus character ------------------------------------------------

    @property
    def name_examples(self) -> tuple[str, ...]:
        return tuple(self._section("corpus").get("name_examples") or ())

    @property
    def naming(self) -> str:
        return " ".join(self._section("corpus").get("naming", "").split())

    @property
    def missing_convention(self) -> str:
        return " ".join(self._section("corpus").get("missing_convention", "").split())

    # -- categories ------------------------------------------------------

    @cached_property
    def intents(self) -> tuple[Intent, ...]:
        """What the router chooses between. The first is the fallback."""
        return tuple(
            Intent(
                id=i["id"], label=i.get("label", i["id"]),
                description=" ".join(i.get("description", "").split()),
                instructions=i.get("instructions", "").strip(),
                advances=bool(i.get("advances", False)),
                # Both default to whatever `advances` says, so the two intents
                # that existed when these were added keep their behaviour
                # without restating it, and a new intent only declares what
                # differs.
                shows_checklist=bool(i.get("shows_checklist",
                                           i.get("advances", False))),
                offers_choices=bool(i.get("offers_choices",
                                          i.get("advances", False))),
                heuristic=str(i.get("heuristic", "")),
                sticky=bool(i.get("sticky", False)),
                entry=str(i.get("entry", ROUTER)),
                confirm=i.get("confirm", "").strip(),
                exits_to=str(i.get("exits_to", "")),
                # Extraction is what the checklist is built from, so an intent
                # that advances it needs the extractor by definition. One that
                # does not may still want it — a draft fills in from an aside —
                # which is why it is a separate field rather than a synonym.
                extracts=bool(i.get("extracts", i.get("advances", False))),
                tools=tuple(str(t) for t in i.get("tools", (ALL_TOOLS,))),
                replies=tuple(str(r) for r in i.get("replies", ())),
            )
            for i in self._raw.get("intent") or ()
        )

    @cached_property
    def intent_ids(self) -> list[str]:
        return [i.id for i in self.intents]

    def intent(self, intent_id: str | None) -> Intent:
        for i in self.intents:
            if i.id == intent_id:
                return i
        return self.fallback_intent

    @cached_property
    def fallback_intent(self) -> Intent:
        """Where a conversation starts, and where an unreadable mode lands."""
        return self.intents[0]

    @cached_property
    def router_intents(self) -> tuple[Intent, ...]:
        """The intents the router may choose between on any given message.

        An intent entered by handoff is deliberately absent: the researcher
        has to accept a proposal to get there, so offering it to the router as
        well would let a message put them into it unasked — which is the whole
        thing the confirmation exists to prevent.
        """
        return tuple(i for i in self.intents if not i.entered_by_handoff)

    @cached_property
    def handoff_intents(self) -> tuple[Intent, ...]:
        """The intents a conversation can be invited into."""
        return tuple(i for i in self.intents if i.entered_by_handoff)

    def exit_intent(self, intent: Intent) -> Intent:
        """Where leaving `intent` lands. The fallback unless it says otherwise."""
        return self.intent(intent.exits_to) if intent.exits_to else self.fallback_intent

    def may_use(self, intent: Intent, tool: str) -> bool:
        return ALL_TOOLS in intent.tools or tool in intent.tools

    @cached_property
    def question_intent(self) -> Intent:
        """Where the fallback rule sends anything that looks like a question."""
        for i in self.intents:
            if i.heuristic == "question":
                return i
        return self.intents[0]

    @property
    def router_strategy(self) -> str:
        """model, heuristic, or auto (model with a heuristic fallback)."""
        return str(self._assistant("router", "auto"))

    @cached_property
    def categories(self) -> tuple[Category, ...]:
        return tuple(
            Category(label=c["label"], slug=c.get("slug", c["label"].lower()))
            for c in self._raw.get("category") or ()
        )

    @property
    def category_labels(self) -> list[str]:
        return [c.label for c in self.categories]

    # -- the issue -------------------------------------------------------

    @cached_property
    def issue(self) -> dict:
        section = dict(self._section("issue"))
        section["fields"] = dict(section.get("fields") or {})
        section["repo"] = section.get("repo") or detect_repo()
        return section

    @cached_property
    def issue_required(self) -> list[str]:
        """Field keys that must be filled in before an issue can be opened.

        The assistant's draft panel gates on this. It is the only route to
        an issue now, but the list stays here rather than in the JavaScript:
        a required field is a property of the issue template, which this file
        already describes, not of the panel that happens to collect it.
        """
        wanted = self.issue.get("required")
        if not isinstance(wanted, list):
            return ["name", "waves", "category", "description"]
        return [str(k) for k in wanted if k in self.issue["fields"]]

    # -- assistant tuning ------------------------------------------------

    def _assistant(self, key: str, default):
        return self._section("assistant").get(key, default)

    @property
    def ollama(self) -> str:
        return str(self._assistant("ollama", "http://localhost:11434")).rstrip("/")

    @property
    def model(self) -> str:
        """Preferred model on a fresh profile. "" leaves it to the picker."""
        return str(self._assistant("model", "") or "")

    @property
    def temperature(self) -> float:
        return float(self._assistant("temperature", 0.4))

    @property
    def max_hops(self) -> int:
        return int(self._assistant("max_hops", 5))

    @property
    def max_turns(self) -> int:
        return int(self._assistant("max_turns", 24))

    @property
    def candidates(self) -> int:
        return int(self._assistant("candidates", 10))

    @property
    def timeout(self) -> int:
        return int(self._assistant("timeout", 600))

    @property
    def choices_open(self) -> str:
        return str(self._assistant("choices_open", "<choices>"))

    @property
    def choices_close(self) -> str:
        return str(self._assistant("choices_close", "</choices>"))

    # -- retrieval tuning ------------------------------------------------

    def _retrieval(self, key: str, default):
        return self._section("retrieval").get(key, default)

    @property
    def k1(self) -> float:
        return float(self._retrieval("k1", 1.2))

    @property
    def b(self) -> float:
        return float(self._retrieval("b", 0.75))

    @property
    def pool(self) -> int:
        return int(self._retrieval("pool", 150))

    # -- semantic search and expansion -------------------------------------
    # All optional. With no index built and expansion off, retrieval is the
    # BM25 it has always been.

    @property
    def embed_model(self) -> str:
        return self._retrieval("embed_model", "nomic-embed-text:latest")

    @property
    def embed_timeout(self) -> float:
        return float(self._retrieval("embed_timeout", 300))

    @property
    def embed_dims(self) -> int:
        """Dimensions kept per vector, or 0 for whatever the model returns.

        The scan is linear in this and nothing else: 768 dimensions cost about
        430 ms over 32,000 variables, 256 about 150 ms. Truncating only works
        on a model trained to allow it (nomic-embed-text is), which is why it
        is a setting rather than a default someone might carry to another
        model.
        """
        return int(self._retrieval("embed_dims", 0))

    @property
    def semantic(self) -> bool:
        """Whether to use the index when one is present."""
        return bool(self._retrieval("semantic", True))

    @property
    def semantic_pool(self) -> int:
        """Nearest neighbours fetched before fusion."""
        return int(self._retrieval("semantic_pool", 60))

    @property
    def fusion_k(self) -> float:
        """Reciprocal-rank-fusion constant: larger flattens the weighting."""
        return float(self._retrieval("fusion_k", 60))

    @property
    def lexical_weight(self) -> float:
        return float(self._retrieval("lexical_weight", 1.0))

    @property
    def semantic_weight(self) -> float:
        return float(self._retrieval("semantic_weight", 1.0))

    @property
    def expand(self) -> bool:
        return bool(self._retrieval("expand", True))

    @property
    def expansions(self) -> int:
        """Alternative phrasings asked of the model, beyond the original."""
        return int(self._retrieval("expansions", 3))

    @property
    def expand_timeout(self) -> float:
        return float(self._retrieval("expand_timeout", 30))

    def retrieval_defaults(self) -> dict:
        """What the drawer's controls start at.

        Sent rather than duplicated in JavaScript, for the same reason the
        interview is: two copies of a default drift, and the one you are
        reading is never the one in force.
        """
        return {
            "semantic": self.semantic,
            "expand": self.expand,
            "expansions": self.expansions,
            "candidates": self.candidates,
            "lexicalWeight": self.lexical_weight,
            "semanticWeight": self.semantic_weight,
        }

    # -- coverage ----------------------------------------------------------
    # How much of a query's idf mass a label must account for before the
    # coverage tool will say a wave measured something, and before it will
    # show the label at all. See retrieval.coverage().

    @property
    def coverage_strong(self) -> float:
        return float(self._retrieval("coverage_strong", 0.7))

    @property
    def coverage_weak(self) -> float:
        return float(self._retrieval("coverage_weak", 0.4))

    @property
    def coverage_examples(self) -> int:
        return int(self._retrieval("coverage_examples", 3))

    @cached_property
    def stopwords(self) -> frozenset[str]:
        return frozenset(self._retrieval("stopwords", ()))

    # -- the interview ---------------------------------------------------

    @cached_property
    def steps(self) -> tuple[Step, ...]:
        return tuple(
            Step(
                id=s["id"], title=s["title"], goal=s["goal"],
                probes=tuple(s.get("probes") or ()),
                replies=tuple(s.get("replies") or ()),
            )
            for s in (self._section("interview").get("step") or ())
        )

    @cached_property
    def step_ids(self) -> list[str]:
        return [s.id for s in self.steps]

    @cached_property
    def note_slots(self) -> tuple[NoteSlot, ...]:
        return tuple(
            NoteSlot(key=n["key"], heading=n["heading"], asks=n.get("asks", ""))
            for n in self._raw.get("note_slot") or ()
        )

    def first_unsettled(self, covered: dict[str, bool]) -> int:
        """Index of the step the interview should be working on.

        With everything settled there is no such step, and this returns the
        last one so that callers indexing `steps` still get something. That
        is a fallback, not an answer — ask `all_settled()` before reading it
        as "the step being worked on". Not doing so is what offered the last
        step's stock answers under a message saying the request was complete.
        """
        for i, step in enumerate(self.steps):
            if not covered.get(step.id):
                return i
        return len(self.steps) - 1

    def all_settled(self, covered: dict[str, bool]) -> bool:
        """Is every checklist step answered?"""
        return all(covered.get(step.id) for step in self.steps)

    def hops_spent(self, hops: int) -> bool:
        """Has this turn used every lookup it is allowed?

        `hops` counts COMPLETED rounds of lookups, so the budget is spent once
        it reaches `max_hops` — not one before. Here rather than in `graph.py`
        because it was off by one there and nothing could show you: `>=
        max_hops - 1` ran four of the five configured rounds, and made the
        final "that was your last lookup" warning unreachable. `graph.py`
        imports LangGraph, so a test for it could not run in a checkout
        without the extra; this one can.
        """
        return hops >= self.max_hops

    # -- for the browser -------------------------------------------------

    def for_browser(self) -> dict:
        """The slice `build_site.py` writes into the manifest.

        Only what the front end actually renders. Prompts, probes and tuning
        stay server-side, where they are used.
        """
        return {
            "key": self.key,
            "name": self.name,
            "fullName": self.full_name,
            "tagline": self.tagline,
            "blurb": self.blurb,
            "identifier": self.identifier,
            "wave": {
                "term": self.wave_term,
                "plural": self.wave_plural,
                "indexedBy": self.wave_indexed_by,
                "cross": self.cross_wave,
                "order": list(self.waves),
            },
            "categories": [{"label": c.label, "slug": c.slug} for c in self.categories],
            "issue": {
                "repo": self.issue["repo"],
                "template": self.issue.get("template", ""),
                "titlePrefix": self.issue.get("title_prefix", ""),
                "fields": self.issue["fields"],
                "required": self.issue_required,
            },
            "assistant": {"ollama": self.ollama, "model": self.model},
            "nameExamples": list(self.name_examples),
            "examples": self.examples,
        }


def detect_repo() -> str:
    """`owner/name` from the git remote, for composing issue URLs."""
    try:
        url = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=REPO, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return ""
    if "github.com" not in url:
        return ""
    return url.split("github.com", 1)[1].lstrip(":/").removesuffix(".git")


_cached: Config | None = None


def get() -> Config:
    """The process-wide config. Loaded once."""
    global _cached
    if _cached is None:
        _cached = Config.load()
    return _cached


def use(cfg: Config) -> Config:
    """Make `cfg` the process-wide config, before anything else reads one.

    Without this, `server.py --config other.toml` was only half honoured: it
    held the chosen config itself, while every default inside `ollama.py`
    still resolved through `get()` and loaded `dataset.toml`. The path that
    reached it is real — `/api/search` leaves `base_url` unset, so a semantic
    query embedded against the DEFAULT dataset's Ollama address, and a
    checkout carrying only a second config raised from inside a request.
    """
    global _cached
    _cached = cfg
    return cfg
