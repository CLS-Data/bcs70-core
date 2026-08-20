"""Adding a capability is a config change.

    python3 -m unittest discover -s web/tests

`assistant/README.md` states it plainly: add an `[[intent]]` and the router
offers it and the assistant works to its instructions, with no branch in
`router.py`, none in `prompts.py`, none in `graph.py`. Two of those were
true. `prompts.py` compared `intent.id` against "interview" to decide whether
the checklist was woven into the prompt and whether answer buttons were
allowed, and the browser compared against "explore" to decide whether to mark
a turn — so a third intent got whatever those comparisons happened to give
it, silently, whatever its config said.

These tests build a config with a third intent and check it gets what it
declares. Written against a config assembled here rather than `dataset.toml`,
because the point is intents that file does not have.
"""

from __future__ import annotations

import sys
import tomllib
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB))

from assistant import prompts  # noqa: E402
from config import Config, DEFAULT_CONFIG  # noqa: E402


def config_with(*intents: dict) -> Config:
    """The real dataset config, with its intents replaced."""
    raw = tomllib.loads(DEFAULT_CONFIG.read_text("utf-8"))
    raw["intent"] = list(intents)
    cfg = Config(raw, DEFAULT_CONFIG)
    cfg.validate()
    return cfg


INTERVIEW = {
    "id": "interview", "label": "working on the request",
    "description": "answering us", "instructions": "Work the checklist.",
    "advances": True,
}
EXPLORE = {
    "id": "explore", "label": "asking about the data",
    "description": "a question", "instructions": "Answer it.",
    "advances": False, "heuristic": "question",
}


class Defaults(unittest.TestCase):
    """An intent that says nothing extra behaves as it always did."""

    def test_advances_decides_the_other_two_when_they_are_unset(self):
        cfg = config_with(INTERVIEW, EXPLORE)
        interview, explore = cfg.intents
        self.assertTrue(interview.shows_checklist)
        self.assertTrue(interview.offers_choices)
        self.assertFalse(explore.shows_checklist)
        self.assertFalse(explore.offers_choices)

    def test_the_shipped_config_is_unchanged_by_this(self):
        """The two real intents keep exactly the behaviour they had."""
        from config import get as get_config
        real = get_config()
        by_id = {i.id: i for i in real.intents}
        self.assertTrue(by_id["interview"].shows_checklist)
        self.assertTrue(by_id["interview"].offers_choices)
        self.assertFalse(by_id["explore"].shows_checklist)
        self.assertFalse(by_id["explore"].offers_choices)


class AThirdIntent(unittest.TestCase):
    """The case that was silently broken."""

    REVIEW = {
        "id": "review", "label": "reviewing the draft",
        "description": "checking what we have so far",
        "instructions": "Read the draft back and ask about one gap.",
        # Does not credit a step, but still needs the checklist in front of it
        # and still asks a question worth offering answers to.
        "advances": False,
        "shows_checklist": True,
        "offers_choices": True,
    }

    def setUp(self):
        self.cfg = config_with(INTERVIEW, EXPLORE, self.REVIEW)

    def system(self, mode: str) -> str:
        return prompts.system(self.cfg, 0, {}, agentic=False, facts={}, mode=mode)

    def test_it_is_offered_to_the_router(self):
        self.assertIn("review", self.cfg.intent_ids)

    def test_it_gets_the_checklist_it_asked_for(self):
        text = self.system("review")
        self.assertIn("CURRENT STEP", text)
        self.assertIn("Still to come", text)

    def test_it_gets_the_answer_buttons_it_asked_for(self):
        self.assertIn("OFFERING CHOICES", self.system("review"))

    def test_it_still_does_not_credit_a_step(self):
        self.assertFalse(self.cfg.intent("review").advances)

    def test_an_intent_that_wants_neither_gets_neither(self):
        text = self.system("explore")
        self.assertNotIn("OFFERING CHOICES", text)
        self.assertNotIn("CURRENT STEP", text)

    def test_its_own_instructions_are_what_it_works_to(self):
        self.assertIn("Read the draft back", self.system("review"))

    def test_an_unknown_mode_falls_back_to_the_first_intent(self):
        self.assertEqual(self.cfg.intent("nonsense").id, "interview")
        self.assertEqual(self.cfg.intent(None).id, "interview")


class NoIdComparisons(unittest.TestCase):
    """The regression itself: no module may name an intent to decide this."""

    def test_prompts_does_not_compare_against_an_intent_id(self):
        source = (WEB / "assistant" / "prompts.py").read_text("utf-8")
        for name in ("interview", "explore"):
            self.assertNotIn(f'== "{name}"', source)
            self.assertNotIn(f'!= "{name}"', source)

    def test_the_browser_does_not_compare_against_an_intent_id(self):
        source = (WEB / "chat" / "transcript.js").read_text("utf-8")
        self.assertNotIn('=== "explore"', source)


if __name__ == "__main__":
    unittest.main()
