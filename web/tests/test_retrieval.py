"""Retrieval and lookup, over a corpus small enough to reason about.

    python3 -m unittest discover -s web/tests

Standard library only, and no built site: `web/data/` is generated and
gitignored, so a test that needed it could not run in CI. The stub below is
the whole contract `Bm25`, `group()` and the tool executors rely on.

The cases here are the ones that have actually gone wrong. Ranking bugs are
invisible - a wrong answer still reads like an answer - so they need a test
that fails rather than a reader who notices.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB))

from assistant import retrieval, tools  # noqa: E402
from config import get as get_config  # noqa: E402


class StubCorpus:
    """Just enough corpus: [name, label, fileIdx, waveIdx, levelIdx] rows."""

    def __init__(self, rows, waves=("0y", "10y", "16y", "26y", "42y")):
        self.waves = list(waves)
        self.files = [{"name": "file_a"}, {"name": "file_b"}]
        self.vars = [[n, lab, f, w, 0] for n, lab, f, w in rows]
        self._by_name: dict[str, list[int]] = {}
        for i, row in enumerate(self.vars):
            self._by_name.setdefault(str(row[0]).lower(), []).append(i)

    def wave_of(self, doc):
        return self.waves[self.vars[doc][3]]

    def file_of(self, doc):
        return self.files[self.vars[doc][2]]

    def rows_named(self, name):
        return self._by_name.get(str(name).lower(), [])

    def entry(self, doc):
        return {}


# A variable literally named "day", the trap that started this: any query
# containing the word used to drag it to the top.
ROWS = [
    ("day",       "DAY NUMBER",                             0, 2),
    ("b960633",   "No. of cigarettes smoked a day",          0, 3),
    ("b9nfcigs",  "Number of cigarettes a day usually smoked", 1, 4),
    ("b10nfcigs", "Number of cigarettes a day usually smoked", 1, 4),
    ("periods",   "CM had problems with periods",            0, 2),
    ("pm1.1",     "Age of teenager's first menstrual period", 0, 2),
    # A plural name whose label is about something else entirely: the old
    # bonus fired on the query word "drinks" and put this above the variable
    # that actually answers an alcohol question.
    ("drinks",    "DRINKING WATER SOURCE - RURAL",           0, 0),
    ("b960631",   "Other alcoholic drink drunk in last week", 0, 3),
    ("b8hlthgn",  "CM Self-Assessment Of Health",            1, 3),
    ("b9hlthgn",  "General state of health",                 1, 4),
    ("c6.8",      "Height without shoes",                    0, 1),
    ("meb17",     "Mother's employment status",              0, 0),
]


def build():
    corpus = StubCorpus(ROWS)
    return corpus, retrieval.Bm25(corpus, get_config())


def names(corpus, docs):
    return [corpus.vars[d][0] for d in docs]


class ExactNames(unittest.TestCase):
    """A name is a term in exactly one document, so BM25 ranks it first
    unaided. This is what allows the old exact-name bonus to be gone."""

    def test_a_bare_name_ranks_itself_first(self):
        corpus, bm = build()
        for name in ("b960633", "b8hlthgn", "c6.8", "meb17"):
            with self.subTest(name=name):
                self.assertEqual(names(corpus, bm.search(name, 3))[0], name)

    def test_a_name_that_is_also_a_word_still_ranks_itself_first(self):
        corpus, bm = build()
        self.assertEqual(names(corpus, bm.search("day", 3))[0], "day")


class NoNameLift(unittest.TestCase):
    """The regression. A word inside a phrase must not be read as a name."""

    def test_phrase_does_not_lift_the_variable_named_day(self):
        corpus, bm = build()
        ranked = names(corpus, bm.search("cigarettes per day", 4))
        self.assertNotEqual(ranked[0], "day")
        self.assertIn(ranked[0], {"b960633", "b9nfcigs", "b10nfcigs"})

    def test_phrase_does_not_lift_a_plural_name(self):
        # The worst case for the old idf guard: a name indexed unstemmed is a
        # term in one document, so it looked maximally rare and earned the
        # maximum bonus - while the word itself is everywhere, under the
        # stemmed spelling the guard never consulted.
        corpus, bm = build()
        ranked = names(corpus, bm.search("alcoholic drinks per week", 3))
        self.assertEqual(ranked[0], "b960631")
        self.assertNotIn("drinks", ranked[:1])

    def test_the_lift_is_gone_rather_than_narrowed(self):
        # Gating it would have left the machinery in place to be re-enabled
        # by someone reading only the config.
        _, bm = build()
        self.assertFalse(hasattr(bm, "by_name"),
                         "by_name existed only to serve the removed bonus")


class Meaning(unittest.TestCase):
    def test_concept_search_finds_the_concept(self):
        corpus, bm = build()
        top = names(corpus, bm.search("cigarettes smoked", 3))
        self.assertIn("b960633", top)

    def test_no_terms_returns_nothing(self):
        _, bm = build()
        self.assertEqual(bm.search("   ", 5), [])
        self.assertEqual(bm.search("of the and", 5), [])


class WaveFilter(unittest.TestCase):
    def test_restricts_to_one_wave(self):
        corpus, bm = build()
        found = retrieval.search_grouped(corpus, bm, "cigarettes",
                                         limit=10, wave="42y")
        got = {n for g in found["groups"] for n in g["names"]}
        self.assertTrue(got)
        self.assertNotIn("b960633", got)   # 26y

    def test_unknown_wave_is_reported_not_ignored(self):
        corpus, bm = build()
        found = retrieval.search_grouped(corpus, bm, "cigarettes",
                                         limit=10, wave="99y")
        self.assertEqual(found["unknown_wave"], "99y")
        self.assertEqual(found["groups"], [])


class Grouping(unittest.TestCase):
    def test_identical_labels_collapse_and_keep_every_name(self):
        corpus, bm = build()
        groups = retrieval.search_grouped(corpus, bm, "cigarettes usually",
                                          limit=10)["groups"]
        merged = [g for g in groups if len(g["names"]) > 1]
        self.assertTrue(merged, "the two identically-labelled variables merged")
        self.assertEqual(set(merged[0]["names"]), {"b9nfcigs", "b10nfcigs"})

    def test_waves_come_back_in_study_order(self):
        corpus = StubCorpus([
            ("a1", "same label", 0, 4),
            ("a2", "same label", 0, 1),
            ("a3", "same label", 0, 2),
        ])
        bm = retrieval.Bm25(corpus, get_config())
        groups = retrieval.search_grouped(corpus, bm, "same label", limit=5)["groups"]
        self.assertEqual(groups[0]["waves"], ["10y", "16y", "42y"])


class Coverage(unittest.TestCase):
    """Reporting a concept wave by wave.

    The labels below are shaped to land either side of the two thresholds:
    matching both query terms scores 1.0, matching one of two scores about a
    half, and matching one of three about a third. "general" and "health" are
    given the same document frequency on purpose, so that one-term matches sit
    squarely between the floors rather than on one of them.
    """

    WAVES = ("0y", "10y", "26y", "42y")
    ROWS = [
        ("h1", "General state of health",        0, 3),  # both terms
        ("h3", "General health check",           0, 3),  # both terms
        ("h2", "How is your health generally",   0, 2),  # "health" only
        ("n1", "General Election vote",          0, 1),  # "general" only
        ("x1", "Shoe size",                      0, 0),  # neither
    ]

    def coverage(self, query="general health"):
        corpus = StubCorpus(self.ROWS, self.WAVES)
        bm = retrieval.Bm25(corpus, get_config())
        return corpus, bm, retrieval.coverage(corpus, bm, query)

    def wave(self, found, name):
        return next(w for w in found["waves"] if w["wave"] == name)

    def test_every_wave_is_reported_including_empty_ones(self):
        _, _, found = self.coverage()
        self.assertEqual([w["wave"] for w in found["waves"]], list(self.WAVES))

    def test_a_full_match_marks_the_wave_measured(self):
        _, _, found = self.coverage()
        w = self.wave(found, "42y")
        self.assertTrue(w["measured"])
        self.assertEqual({m["name"] for m in w["matches"]}, {"h1", "h3"})

    def test_a_partial_match_is_shown_but_not_claimed(self):
        # The case the tool exists for: "How is your health generally" does
        # not match the term "general", so a strict floor would hide it.
        _, _, found = self.coverage()
        w = self.wave(found, "26y")
        self.assertFalse(w["measured"])
        self.assertIn("h2", {m["name"] for m in w["matches"]})

    def test_a_wave_with_nothing_says_nothing(self):
        _, _, found = self.coverage()
        w = self.wave(found, "0y")
        self.assertFalse(w["measured"])
        self.assertEqual(w["matches"], [])

    def test_weak_matches_are_dropped_once_a_wave_is_confirmed(self):
        rows = self.ROWS + [("junk", "General reading and writing", 0, 3)]
        corpus = StubCorpus(rows, self.WAVES)
        bm = retrieval.Bm25(corpus, get_config())
        found = retrieval.coverage(corpus, bm, "general health")
        w = self.wave(found, "42y")
        self.assertNotIn("junk", {m["name"] for m in w["matches"]},
                         "a confirmed wave should not also list its noise")

    def test_one_term_of_three_is_below_the_floor(self):
        rows = [
            ("c1", "Number of cigarettes smoked a day", 0, 3),
            ("c2", "Cups of tea per day",               0, 2),
            ("c3", "Cigarette advertising should stop", 0, 1),
        ]
        corpus = StubCorpus(rows, self.WAVES)
        bm = retrieval.Bm25(corpus, get_config())
        found = retrieval.coverage(corpus, bm, "cigarettes per day")
        shown = {m["name"] for w in found["waves"] for m in w["matches"]}
        self.assertIn("c1", shown)
        self.assertNotIn("c3", shown, "one term of three is not evidence")

    def test_terms_absent_from_the_index_are_reported(self):
        _, _, found = self.coverage("zzzz qqqq")
        self.assertTrue(found["unknown_terms"])
        self.assertEqual(found["waves"], [])

    def test_the_tool_summarises_before_it_lists(self):
        corpus, bm, _ = self.coverage()
        text, display = tools.run(corpus, bm, get_config(), tools.COVERAGE,
                                  {"concept": "general health"})
        head = text.splitlines()[0]
        self.assertIn("measured at: 42y", head)
        self.assertIn("10y, 26y", head)
        # The summary must not let an unconfirmed wave be read as an empty one.
        self.assertIn("Never fold these in", head)
        self.assertIn("0y: nothing found", text)
        self.assertEqual(len(display["coverage"]), len(self.WAVES))

    def test_the_tool_needs_a_concept(self):
        corpus, bm, _ = self.coverage()
        text, _ = tools.run(corpus, bm, get_config(), tools.COVERAGE, {})
        self.assertIn("No concept given", text)


class NearMisses(unittest.TestCase):
    """Suggestions on a failed lookup: structure, never edit distance."""

    def test_offers_the_same_question_at_other_waves(self):
        corpus, _ = build()
        near, total = tools._near_misses(corpus, "b7hlthgn")
        self.assertEqual(near, ["b8hlthgn", "b9hlthgn"])
        self.assertEqual(total, 2)

    def test_refuses_when_the_digits_are_the_name(self):
        # b960633's neighbours by edit distance are real, unrelated variables.
        # Its digit-stripped core is "b", so nothing is offered - the point of
        # the rule.
        corpus, _ = build()
        self.assertEqual(tools._near_misses(corpus, "b960634"), ([], 0))

    def test_never_offers_the_name_asked_for(self):
        corpus, _ = build()
        near, _ = tools._near_misses(corpus, "b8hlthgn")
        self.assertNotIn("b8hlthgn", near)

    def test_a_miss_reports_the_candidates_without_choosing(self):
        corpus, _ = build()
        text, display = tools._inspect(corpus, get_config(), {"name": "b7hlthgn"})
        self.assertIn("No variable called", text)
        self.assertIn("b8hlthgn", text)
        self.assertIn("do not assume which is right", text.lower())
        self.assertEqual(display["suggestions"], ["b8hlthgn", "b9hlthgn"])

    def test_a_miss_with_nothing_similar_says_so(self):
        corpus, _ = build()
        text, display = tools._inspect(corpus, get_config(), {"name": "zzzz999"})
        self.assertIn("Search for the concept instead", text)
        self.assertEqual(display["suggestions"], [])

    def test_a_hit_is_unaffected(self):
        corpus, _ = build()
        text, display = tools._inspect(corpus, get_config(), {"name": "b8hlthgn"})
        self.assertIn("b8hlthgn", text)
        self.assertEqual(display["variable"]["name"], "b8hlthgn")

    def test_an_enormous_stem_family_is_refused_not_dumped(self):
        rows = [(f"meb{i}.1", f"item {i}", 0, 0) for i in range(1, 40)]
        corpus = StubCorpus(rows)
        near, total = tools._near_misses(corpus, "meb99.1")
        self.assertEqual(total, 39)
        self.assertEqual(len(near), tools.MAX_SUGGESTIONS)
        text, _ = tools._inspect(corpus, get_config(), {"name": "meb99.1"})
        self.assertIn("too many to list", text)


if __name__ == "__main__":
    unittest.main()
