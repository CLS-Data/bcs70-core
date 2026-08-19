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
    """One thing the assistant can be asked to do."""

    id: str
    label: str
    description: str
    instructions: str
    advances: bool      # does answering this move the checklist on?
    heuristic: str      # "question" marks where the fallback rule sends one


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

        fields = self._raw["issue"].get("fields") or {}
        for key in ("name", "waves", "category", "description", "sources", "notes"):
            if key not in fields:
                raise ConfigError(f"{self.path}: [issue.fields] is missing '{key}'")

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
                heuristic=str(i.get("heuristic", "")),
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
        return self.intents[0]

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

    @property
    def name_lift(self) -> float:
        return float(self._retrieval("name_lift", 2.5))

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
        """Index of the step the interview should be working on."""
        for i, step in enumerate(self.steps):
            if not covered.get(step.id):
                return i
        return len(self.steps) - 1

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
