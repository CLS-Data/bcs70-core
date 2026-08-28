"""What a lookup may run, as opposed to what a model was shown.

    python3 -m unittest discover -s web/tests

`schemas` decides what a model is offered, which is the whole of the allowlist
as long as models only ever call what they were given. They do not always. An
intent declaring `tools = ["coverage"]` still had every other lookup execute
for it on a hallucinated name, because the executor dispatched on the name
alone and never saw the intent.
"""

from __future__ import annotations

import sys
import tomllib
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB))

from assistant import tools  # noqa: E402
from config import Config, DEFAULT_CONFIG  # noqa: E402


def narrowed_to(*allowed: str) -> Config:
    raw = tomllib.loads(DEFAULT_CONFIG.read_text("utf-8"))
    raw["intent"] = [dict(i, tools=list(allowed)) if i["id"] == "chat" else i
                     for i in raw["intent"]]
    cfg = Config(raw, DEFAULT_CONFIG)
    cfg.validate()
    return cfg


class Corpus:
    """Enough of one to reach the refusal, and no further."""

    facts: dict = {}
    counts: dict = {}
    waves: list = []
    derived: list = []

    def known_name(self, name):
        return False


class TheAllowlistIsEnforcedTwice(unittest.TestCase):
    def setUp(self):
        self.cfg = narrowed_to("coverage")
        self.chat = self.cfg.intent("chat")

    def test_a_model_is_shown_only_what_it_may_call(self):
        shown = [s["function"]["name"] for s in tools.schemas(self.cfg, self.chat)]
        self.assertEqual(shown, ["coverage"])

    def test_and_calling_anything_else_is_refused(self):
        text, display = tools.run(Corpus(), None, self.cfg, "list_harmonised",
                                  {}, intent=self.chat)
        self.assertIn("not available", text)
        self.assertIn("coverage", text)
        self.assertIn("not available", display["note"])

    def test_the_refusal_names_what_is_available(self):
        text, _ = tools.run(Corpus(), None, self.cfg, "search_variables",
                            {"query": "height"}, intent=self.chat)
        self.assertIn("Available: coverage", text)

    def test_no_intent_means_no_narrowing(self):
        """`/api/search` and the tests call the executors directly."""
        text, _ = tools.run(Corpus(), None, self.cfg, "list_harmonised", {})
        self.assertNotIn("not available", text)

    def test_the_default_allowlist_permits_everything(self):
        from config import get as get_config
        cfg = get_config()
        for intent in cfg.intents:
            for name in tools.NAMES:
                self.assertTrue(cfg.may_use(intent, name), f"{intent.id}/{name}")


if __name__ == "__main__":
    unittest.main()
