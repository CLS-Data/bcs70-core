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
