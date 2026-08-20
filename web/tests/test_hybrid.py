"""Semantic search, query expansion, and the fusion of the two with BM25.

    python3 -m unittest discover -s web/tests

No Ollama and no index on disk: the embedder is a stub and the vectors are
written by the tests themselves. That is not only for CI's sake — a test that
needed a 33 MB index and a model server would be run once and then skipped
forever.

What is deliberately NOT asserted here is retrieval quality. Whether an
embedding model puts "How is your health generally" near "self-rated health"
is a property of the model, not of this code, and pinning it in a test would
break the day someone changed `embed_model` for a better one.
"""

from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB))

from assistant import expansion, retrieval, tools, vectors  # noqa: E402
from config import get as get_config  # noqa: E402
from test_retrieval import StubCorpus  # noqa: E402


class StubIndex:
    """Stands in for a loaded index: rows, in the order it wants to return."""

    def __init__(self, order, fail=None):
        self.order = list(order)
        self.fail = fail
        self.queries = []

    def search(self, text, limit, base=None):
        self.queries.append(text)
        if self.fail:
            raise self.fail
        return [(row, 1.0 - i / 100) for i, row in enumerate(self.order[:limit])]


ROWS = [
    ("a1", "Alpha one",   0, 0),
    ("b2", "Beta two",    0, 1),
    ("c3", "Gamma three", 0, 2),
    ("d4", "Delta four",  0, 3),
]


def build(order=None, fail=None):
    cfg = get_config()
    corpus = StubCorpus(ROWS, ("0y", "10y", "26y", "42y"))
    bm = retrieval.Bm25(corpus, cfg)
    index = StubIndex(order, fail) if order is not None else None
    return cfg, corpus, bm, retrieval.Retriever(corpus, bm, cfg, index), index


class Fusion(unittest.TestCase):
    def test_a_document_both_runs_agree_on_wins(self):
        # Second in each list beats first-in-one-and-absent-from-the-other,
        # which is the whole reason for fusing on rank rather than score.
        merged = retrieval.fuse([[1, 9], [2, 9]], k=1)
        self.assertEqual(merged[0], 9)

    def test_order_within_a_run_is_respected(self):
        self.assertEqual(retrieval.fuse([[5, 6, 7]], k=60), [5, 6, 7])

    def test_a_zero_weight_run_is_ignored_entirely(self):
        merged = retrieval.fuse([[1, 2], [3, 4]], k=60, weights=[1.0, 0.0])
        self.assertEqual(merged, [1, 2])

    def test_weighting_can_decide_a_tie(self):
        lexical, semantic = [1], [2]
        self.assertEqual(retrieval.fuse([lexical, semantic], 60, [1.0, 2.0])[0], 2)
        self.assertEqual(retrieval.fuse([lexical, semantic], 60, [2.0, 1.0])[0], 1)


class RetrieverModes(unittest.TestCase):
    def test_lexical_only_when_there_is_no_index(self):
        _, _, _, retriever, _ = build()
        rows, how = retriever.run("alpha", limit=5, settings=off())
        self.assertFalse(how["semantic"])
        self.assertTrue(rows)

    def test_semantic_results_are_folded_in(self):
        _, _, _, retriever, index = build(order=[3, 2])
        rows, how = retriever.run("alpha", limit=5, settings=off(semantic=True))
        self.assertTrue(how["semantic"])
        self.assertIn(3, rows, "a row only the index returned should survive fusion")
        self.assertEqual(index.queries, ["alpha"])

    def test_a_broken_index_degrades_instead_of_raising(self):
        # Ollama stopped, model deleted, machine asleep. The lexical hits are
        # already in hand and the turn must still answer.
        _, _, _, retriever, _ = build(order=[1], fail=RuntimeError("connection refused"))
        rows, how = retriever.run("alpha", limit=5, settings=off(semantic=True))
        self.assertFalse(how["semantic"])
        self.assertIn("unavailable", how["note"])
        self.assertTrue(rows)

    def test_the_wave_filter_applies_to_semantic_hits_too(self):
        # Row 3 is at 42y; restricted to 0y it must not come back just
        # because the index liked it.
        _, _, _, retriever, _ = build(order=[3, 0])
        rows, _ = retriever.run("alpha", limit=5, wave="0y", settings=off(semantic=True))
        self.assertNotIn(3, rows)

    def test_expansion_searches_every_phrasing(self):
        _, _, _, retriever, index = build(order=[1])
        settings = off(semantic=True, expand=True, expansions=2,
                       helper_model="stub")
        original = expansion.phrasings
        expansion.phrasings = lambda cfg, q, **kw: [q, "other words", "third way"]
        try:
            _, how = retriever.run("alpha", limit=5, settings=settings)
        finally:
            expansion.phrasings = original
        self.assertTrue(how["expanded"])
        self.assertEqual(how["queries"], ["alpha", "other words", "third way"])
        self.assertEqual(index.queries, ["alpha", "other words", "third way"])


def off(**kw):
    cfg = get_config()
    base = {"semantic": False, "expand": False, "helper_model": ""}
    base.update(kw)
    return retrieval.Settings.from_config(cfg, **base)


class SettingsFromClient(unittest.TestCase):
    def test_absent_keys_keep_the_configured_default(self):
        cfg = get_config()
        s = retrieval.Settings.from_json({}, cfg)
        self.assertEqual(s.candidates, cfg.candidates)
        self.assertEqual(s.semantic, cfg.semantic)

    def test_out_of_range_values_are_clamped_not_trusted(self):
        cfg = get_config()
        s = retrieval.Settings.from_json(
            {"candidates": 9999, "expansions": 99, "semanticWeight": -4}, cfg)
        self.assertEqual(s.candidates, 50)
        self.assertEqual(s.expansions, expansion.CEILING)
        self.assertEqual(s.semantic_weight, 0.0)

    def test_nonsense_is_ignored_rather_than_raising(self):
        cfg = get_config()
        s = retrieval.Settings.from_json({"candidates": "lots"}, cfg)
        self.assertEqual(s.candidates, cfg.candidates)

    def test_but_replaces_only_what_it_is_given(self):
        cfg = get_config()
        s = retrieval.Settings.from_json({"candidates": 7}, cfg).but(helper_model="m")
        self.assertEqual(s.candidates, 7)
        self.assertEqual(s.helper_model, "m")


class Expansion(unittest.TestCase):
    def test_the_original_always_comes_first(self):
        out = expansion.phrasings(get_config(), "housing tenure", count=3, model="")
        self.assertEqual(out, ["housing tenure"])

    def test_bullets_and_numbering_are_stripped(self):
        self.assertEqual(expansion._clean("  - own or rent  "), "own or rent")
        self.assertEqual(expansion._clean("2. tenure of dwelling"), "tenure of dwelling")
        self.assertEqual(expansion._clean('"renting status"'), "renting status")

    def test_a_sentence_of_explanation_is_not_a_search(self):
        self.assertEqual(
            expansion._clean("Here are some alternative phrasings you could try:"), "")

    def test_a_model_that_cannot_be_reached_costs_only_its_alternatives(self):
        cfg = get_config()
        original = expansion.ollama.complete

        def boom(*a, **kw):
            raise expansion.ollama.OllamaError("nope")

        expansion.ollama.complete = boom
        try:
            self.assertEqual(expansion.phrasings(cfg, "smoking", count=3, model="m"),
                             ["smoking"])
        finally:
            expansion.ollama.complete = original


class Coverage(unittest.TestCase):
    def test_a_semantic_hit_is_shown_despite_a_poor_lexical_share(self):
        # The point of the whole feature: a label sharing no words with the
        # query would be filtered out by the lexical floor.
        cfg, corpus, bm, retriever, _ = build(order=[3])
        found = retrieval.coverage(corpus, bm, "alpha", retriever,
                                   off(semantic=True))
        wave = next(w for w in found["waves"] if w["wave"] == "42y")
        self.assertEqual([m["name"] for m in wave["matches"]], ["d4"])

    def test_a_wave_is_judged_against_the_best_wording_searched(self):
        """A qualified query confirms nothing; its plain form confirms.

        Which is why expansion has to feed the confirmation bar and not only
        recall — otherwise asking more precisely makes the answer worse.
        """
        # "self" and "rated" must exist somewhere, or they carry no idf and
        # cannot dilute the share — which is the entire effect under test.
        rows = [
            ("h1", "General state of health", 0, 3),
            ("s1", "Self employed at this date", 0, 0),
            ("r1", "Rated the film as suitable", 0, 1),
            ("s2", "Self completion booklet returned", 0, 2),
        ]
        corpus = StubCorpus(rows, ("0y", "10y", "26y", "42y"))
        cfg = get_config()
        bm = retrieval.Bm25(corpus, cfg)
        retriever = retrieval.Retriever(corpus, bm, cfg, None)

        wordy = retrieval.coverage(corpus, bm, "self rated general health",
                                   retriever, off())
        self.assertFalse(any(w["measured"] for w in wordy["waves"]))

        original = expansion.phrasings
        expansion.phrasings = lambda cfg, q, **kw: [q, "general health"]
        try:
            expanded = retrieval.coverage(
                corpus, bm, "self rated general health", retriever,
                off(expand=True, expansions=1, helper_model="stub"))
        finally:
            expansion.phrasings = original

        self.assertTrue(any(w["measured"] for w in expanded["waves"]),
                        "the plainer wording should confirm what the wordy one cannot")

    def test_words_confirm_and_meaning_only_suggests(self):
        # Both halves in one assertion, because the distinction is the whole
        # design: a cosine is not an idf share, and letting one clear a
        # threshold calibrated for the other is how a dental-health variable
        # would get reported as confirmed self-rated health.
        cfg, corpus, bm, retriever, _ = build(order=[3])
        found = retrieval.coverage(corpus, bm, "alpha", retriever, off(semantic=True))
        lexical = next(w for w in found["waves"] if w["wave"] == "0y")   # "Alpha one"
        semantic = next(w for w in found["waves"] if w["wave"] == "42y")  # index only
        self.assertTrue(lexical["measured"])
        self.assertFalse(semantic["measured"])
        self.assertEqual([m["name"] for m in semantic["matches"]], ["d4"])

    def test_a_semantic_hit_is_never_reported_as_confirmed(self):
        # The thresholds are calibrated on idf mass and mean nothing against
        # a cosine, so meaning surfaces a candidate and never confirms one.
        cfg, corpus, bm, retriever, _ = build(order=[3])
        found = retrieval.coverage(corpus, bm, "alpha", retriever,
                                   off(semantic=True))
        wave = next(w for w in found["waves"] if w["wave"] == "42y")
        self.assertFalse(wave["measured"])


class Index(unittest.TestCase):
    """The parts of vectors.py that do not need a model."""

    def test_truncation_happens_before_normalising(self):
        out = vectors.prepare([3.0, 4.0, 100.0], dims=2)
        self.assertAlmostEqual(out[0], 0.6)
        self.assertAlmostEqual(out[1], 0.8)

    def test_a_zero_vector_does_not_divide_by_zero(self):
        self.assertEqual(vectors.prepare([0.0, 0.0]), [0.0, 0.0])

    def test_the_fingerprint_follows_names_and_their_order(self):
        a = StubCorpus(ROWS)
        b = StubCorpus(list(reversed(ROWS)))
        self.assertNotEqual(vectors.fingerprint(a), vectors.fingerprint(b))

    def test_a_corrected_label_does_not_invalidate_the_index(self):
        # Labels move; positions are what the vectors depend on.
        a = StubCorpus(ROWS)
        relabelled = [(n, lab + " (corrected)", f, w) for n, lab, f, w in ROWS]
        self.assertEqual(vectors.fingerprint(a),
                         vectors.fingerprint(StubCorpus(relabelled)))

    def test_an_index_for_a_different_corpus_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            self._write(tmp, StubCorpus(ROWS), dim=2)
            other = StubCorpus(ROWS + [("e5", "Epsilon", 0, 0)])
            self.assertIsNone(vectors.load(Path(tmp), other, get_config()))
            self.assertIn("no longer line up", other.vectors_unavailable)

    def test_an_index_of_the_wrong_size_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            corpus = StubCorpus(ROWS)
            self._write(tmp, corpus, dim=2, rows=2)   # claims 4, holds 2
            self.assertIsNone(vectors.load(Path(tmp), corpus, get_config()))
            self.assertIn("wrong size", corpus.vectors_unavailable)

    def test_a_missing_index_is_a_reason_not_an_exception(self):
        with tempfile.TemporaryDirectory() as tmp:
            corpus = StubCorpus(ROWS)
            self.assertIsNone(vectors.load(Path(tmp), corpus, get_config()))
            self.assertIn("build_embeddings", corpus.vectors_unavailable)

    def test_a_matching_index_loads(self):
        with tempfile.TemporaryDirectory() as tmp:
            corpus = StubCorpus(ROWS)
            self._write(tmp, corpus, dim=2)
            index = vectors.load(Path(tmp), corpus, get_config())
            self.assertIsNotNone(index)
            self.assertEqual((index.count, index.dim), (len(ROWS), 2))

    def _write(self, tmp, corpus, *, dim, rows=None):
        path = Path(tmp)
        count = len(corpus.vars) if rows is None else rows
        with (path / vectors.INDEX).open("wb") as fh:
            for i in range(count):
                fh.write(struct.pack(f"<{dim}f", *([1.0] + [0.0] * (dim - 1))))
        (path / vectors.META).write_text(json.dumps({
            "model": "stub", "dim": dim, "count": len(corpus.vars),
            "fingerprint": vectors.fingerprint(corpus), "built": "2026-08-20",
        }), "utf-8")


class ToolReporting(unittest.TestCase):
    def test_the_search_result_says_how_it_searched(self):
        cfg, corpus, bm, retriever, _ = build(order=[1])
        text, display = tools.run(corpus, bm, cfg, tools.SEARCH,
                                  {"query": "alpha"}, retriever, off(semantic=True))
        self.assertIn("by meaning as well as by words", text)
        self.assertTrue(display["semantic"])

    def test_lexical_only_says_nothing_extra(self):
        cfg, corpus, bm, retriever, _ = build()
        text, display = tools.run(corpus, bm, cfg, tools.SEARCH,
                                  {"query": "alpha"}, retriever, off())
        self.assertNotIn("by meaning", text)
        self.assertEqual(display["note"], "lexical")


if __name__ == "__main__":
    unittest.main()
