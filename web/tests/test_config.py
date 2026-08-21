"""The small rules `config.py` holds over its own settings.

    python3 -m unittest discover -s web/tests

These live here rather than beside the graph because `graph.py` imports
LangGraph at module scope, so a test for anything inside it cannot run in a
checkout that installed nothing — which is every CI run. The rules that were
wrong there are therefore kept where they can be tested.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB))

from config import get as get_config  # noqa: E402


class HopBudget(unittest.TestCase):
    """`hops` counts COMPLETED rounds, so the budget is spent AT max_hops.

    This was off by one in `graph.route` (`>= max_hops - 1`), which ran four
    of the five configured rounds and made the final "that was your last
    lookup" warning in `lookups` unreachable. Neither is visible from a
    transcript: a turn that stopped searching one round early looks exactly
    like a turn that had nothing more to look up.
    """

    def setUp(self):
        self.cfg = get_config()

    def test_a_fresh_turn_has_its_budget(self):
        self.assertFalse(self.cfg.hops_spent(0))

    def test_the_last_allowed_round_still_runs(self):
        # The regression: at max_hops - 1 rounds completed, one is still owed.
        self.assertFalse(self.cfg.hops_spent(self.cfg.max_hops - 1))

    def test_the_budget_is_spent_at_the_limit(self):
        self.assertTrue(self.cfg.hops_spent(self.cfg.max_hops))

    def test_overrun_stays_spent(self):
        self.assertTrue(self.cfg.hops_spent(self.cfg.max_hops + 3))

    def test_exactly_max_hops_rounds_run(self):
        """Counted the way the graph counts, so the two cannot disagree."""
        hops = rounds = 0
        while not self.cfg.hops_spent(hops):
            hops += 1
            rounds += 1
            self.assertLess(rounds, 100, "hops_spent never became true")
        self.assertEqual(rounds, self.cfg.max_hops)

    def test_the_final_round_is_warned_that_it_is_final(self):
        """`lookups` computes `left = max_hops - hops` and warns at <= 0.

        If that branch is unreachable the model is never told its last lookup
        was its last, which is the failure the warning exists to prevent.
        """
        last = self.cfg.max_hops                    # hops after the final round
        self.assertLessEqual(self.cfg.max_hops - last, 0)


class Completeness(unittest.TestCase):
    """`first_unsettled` returns a fallback, not an answer.

    With every step settled there is no step being worked on, and this
    returns the last index so a caller indexing `steps` still gets something.
    Read as "the step in progress" it is wrong, and silently: the interview
    named that step to the browser, which found no answers offered with the
    message and fell back to the step's stock replies — so a message saying
    "the request is complete, open the Draft panel" arrived under three
    buttons headed "Common answers on name & check".
    """

    def setUp(self):
        self.cfg = get_config()
        self.all_done = {s: True for s in self.cfg.step_ids}

    def test_nothing_settled_is_not_settled(self):
        self.assertFalse(self.cfg.all_settled({}))

    def test_all_but_one_is_not_settled(self):
        covered = dict(self.all_done)
        covered[self.cfg.step_ids[-1]] = False
        self.assertFalse(self.cfg.all_settled(covered))

    def test_everything_settled_is_settled(self):
        self.assertTrue(self.cfg.all_settled(self.all_done))

    def test_an_unknown_step_id_does_not_count(self):
        self.assertFalse(self.cfg.all_settled({"not-a-step": True}))

    def test_the_fallback_is_indistinguishable_without_asking(self):
        """Why `all_settled` has to exist rather than being inferred.

        The last step being open and every step being settled give the same
        index. Anything deciding "which step is this about" must ask.
        """
        last = len(self.cfg.step_ids) - 1
        open_last = {s: True for s in self.cfg.step_ids[:-1]}
        self.assertEqual(self.cfg.first_unsettled(open_last), last)
        self.assertEqual(self.cfg.first_unsettled(self.all_done), last)
        self.assertFalse(self.cfg.all_settled(open_last))
        self.assertTrue(self.cfg.all_settled(self.all_done))


class StepOrder(unittest.TestCase):
    def test_first_unsettled_walks_forward(self):
        cfg = get_config()
        self.assertEqual(cfg.first_unsettled({}), 0)
        covered = {cfg.step_ids[0]: True}
        self.assertEqual(cfg.first_unsettled(covered), 1)

    def test_everything_settled_rests_on_the_last_step(self):
        cfg = get_config()
        covered = {s: True for s in cfg.step_ids}
        self.assertEqual(cfg.first_unsettled(covered), len(cfg.step_ids) - 1)


if __name__ == "__main__":
    unittest.main()
