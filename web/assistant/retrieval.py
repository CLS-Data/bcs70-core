"""BM25 over the variable descriptions.

Built once at start-up over the whole corpus — about 0.15 s for 32,000
variables — and answered in well under a millisecond thereafter.

Tuning (`k1`, `b`, the pool size, the stoplist, the exact-name lift) lives in
`dataset.toml`, because the right values depend on what the labels look like.
"""

from __future__ import annotations

import math
import re
from collections import defaultdict

from config import Config

from . import expansion

TOKEN = re.compile(r"[a-z0-9]+")


def _stem(token: str) -> str:
    """One rule, applied identically at index and query time.

    Nothing more aggressive: stemming "housing" to "hous" would collapse it
    into "house" and "household", which are different concepts here.
    """
    if len(token) > 3 and token.endswith("s") and not token.endswith(("ss", "us")):
        return token[:-1]
    return token


class Bm25:
    def __init__(self, corpus, cfg: Config):
        self.corpus = corpus
        self.cfg = cfg
        self.postings: dict[str, list[tuple[int, int]]] = {}
        self.doc_len: list[int] = []
        self._build()

    def tokenize(self, text: str) -> list[str]:
        out = []
        for match in TOKEN.finditer((text or "").lower()):
            token = match.group(0)
            if token in self.cfg.stopwords:
                continue
            if len(token) < 2 and not token.isdigit():
                continue
            out.append(_stem(token))
        return out

    def _build(self) -> None:
        acc: dict[str, dict[int, int]] = defaultdict(lambda: defaultdict(int))
        doc_len = []
        for doc, row in enumerate(self.corpus.vars):
            name, label = row[0], row[1]
            key = str(name).lower()

            # The name is indexed whole as well as split, so `c6.8` survives
            # as a searchable term instead of only ever becoming "c6" and "8".
            # This is also what makes a name searchable *at all*: a whole-name
            # token occurs in exactly one document, so its idf is maximal and
            # BM25 alone ranks an exact name first. See the note in search().
            tokens = self.tokenize(label)
            tokens.append(key)
            tokens.extend(self.tokenize(name))
            doc_len.append(len(tokens))
            for token in tokens:
                acc[token][doc] += 1

        self.doc_len = doc_len
        self.n = len(doc_len)
        self.avg_len = (sum(doc_len) / self.n) if self.n else 1.0
        self.postings = {t: list(m.items()) for t, m in acc.items()}

    def _idf(self, token: str) -> float:
        df = len(self.postings.get(token, ()))
        if not df:
            return 0.0
        return math.log(1 + (self.n - df + 0.5) / (df + 0.5))

    def search(self, query: str, limit: int, wave_idx: int = -1) -> list[int]:
        terms = self.tokenize(query)
        if not terms:
            return []

        k1, b = self.cfg.k1, self.cfg.b
        in_scope = (
            (lambda d: True) if wave_idx < 0
            else (lambda d: self.corpus.vars[d][3] == wave_idx)
        )

        scores: dict[int, float] = defaultdict(float)
        for term in set(terms):
            postings = self.postings.get(term)
            if not postings:
                continue
            idf = self._idf(term)
            for doc, tf in postings:
                if not in_scope(doc):
                    continue
                norm = 1 - b + b * (self.doc_len[doc] / self.avg_len)
                scores[doc] += idf * (tf * (k1 + 1)) / (tf + k1 * norm)

        # There is deliberately no bonus for an exact variable name here.
        #
        # There used to be, on the reasoning that a bare code is a poor match
        # against label text. It is not: because _build() indexes each name
        # whole, a name is a term occurring in exactly one document, so its
        # idf is the highest in the index and BM25 already ranks it first.
        # The bonus was redundant, and not harmlessly so — it was applied per
        # WORD, so any phrase containing a word that happens to be a variable
        # name lifted that variable. Searching "cigarettes per day" returned
        # `day` ("DAY NUMBER") above every cigarette variable.
        #
        # The guard against that was to scale the bonus by the word's idf, so
        # that a common word earned almost nothing. It could not work: names
        # are indexed unstemmed and labels stemmed, so the name `periods` is a
        # term in one document while the 379 labels saying "period" are a
        # different term. The guard asked "is this word rare?", was told
        # "one document", and awarded the maximum.
        #
        # Looking a variable up by name is `inspect_variable`'s job. This
        # function is about meaning.
        ranked = sorted(scores.items(), key=lambda kv: -kv[1])
        return [doc for doc, _ in ranked[:limit]]


def group(corpus, docs: list[int], limit: int) -> list[dict]:
    """Collapse hits that share a description.

    One question asked at six waves is one fact about the corpus, and
    spending six of the model's ten candidate slots restating it is the
    difference between a useful context block and a useless one. The wave
    list is the interesting part, and it is what the request needs to say
    anyway.
    """
    order: list[str] = []
    groups: dict[str, dict] = {}

    for doc in docs:
        name, label = corpus.vars[doc][0], corpus.vars[doc][1]
        key = (label or f" {name}").lower()
        entry = groups.get(key)
        if entry is None:
            groups[key] = entry = {
                "label": label or None, "names": [], "waves": [],
                "files": [], "rows": [], "wave_of": {},
            }
            order.append(key)
        if name not in entry["names"]:
            entry["names"].append(name)
        wave = corpus.wave_of(doc)
        # Which wave each name came from. The `waves` list is deduped
        # separately, so its order says nothing about any one name — and the
        # transcript makes every name clickable through to the atlas, which
        # needs the right one.
        entry["wave_of"].setdefault(name, wave)
        if wave not in entry["waves"]:
            entry["waves"].append(wave)
        file_name = corpus.file_of(doc).get("name")
        if file_name and file_name not in entry["files"]:
            entry["files"].append(file_name)
        entry["rows"].append(doc)

    position = {w: i for i, w in enumerate(corpus.waves)}
    out = []
    for key in order[:limit]:
        entry = groups[key]
        entry["waves"].sort(key=lambda w: position.get(w, 999))
        out.append(entry)
    return out


def fuse(runs: list[list[int]], k: float, weights: list[float] | None = None) -> list[int]:
    """Reciprocal rank fusion over several ranked lists.

    BM25 scores and cosine similarities are not on one scale and cannot be
    added, and normalising them means inventing a relationship between them
    that changes with every query. RRF only reads position: a document scores
    1/(k + rank) in each list it appears in, summed. A document found by two
    different methods beats one found emphatically by a single method, which
    is the behaviour worth having when the two methods fail in unrelated ways.

    `k` flattens the curve - at 60 the difference between rank 1 and rank 10
    is small, so a list has to agree repeatedly rather than loudly.
    """
    weights = weights or [1.0] * len(runs)
    scores: dict[int, float] = defaultdict(float)
    for run, weight in zip(runs, weights):
        if not weight:
            continue
        for rank, doc in enumerate(run):
            scores[doc] += weight / (k + rank + 1)
    return [doc for doc, _ in sorted(scores.items(), key=lambda kv: -kv[1])]


# Below this, a substring is too common to mean anything: "a" appears in
# most labels in the corpus, and a run of 30,000 rows contributes nothing to
# a fusion except noise and time.
MIN_SUBSTRING = 2


def substring(corpus, query: str, limit: int, wave_idx: int = -1) -> list[int]:
    """Rows whose name or label literally contains `query`.

    BM25 indexes whole tokens, so it cannot answer the question a researcher
    asks most often about this corpus: "I half-remember the name". Measured
    here, `b960` returns 299 rows by substring and none at all by BM25, and
    `hlth` returns 9 against none — while `cigarettes per day` is the exact
    reverse. The two are complementary, not better and worse, which is why
    this is a run to be fused rather than a mode to switch between.

    Ranked by how much of the field the query accounts for, because rank is
    all that reciprocal-rank fusion reads:

      1. the name, exactly
      2. the name, from its start   — shortest first
      3. the name, anywhere         — shortest first
      4. the label                  — in corpus order

    Sorting by length within a tier is what puts `sex` above `sexpart2` for
    "sex": in a corpus of codes, a shorter name containing the query is more
    likely to BE the thing than to merely mention it.
    """
    q = (query or "").strip().lower()
    if len(q) < MIN_SUBSTRING:
        return []

    exact: list[int] = []
    starts: list[tuple[int, int]] = []
    inside: list[tuple[int, int]] = []
    labelled: list[int] = []

    for doc, row in enumerate(corpus.vars):
        if wave_idx >= 0 and row[3] != wave_idx:
            continue
        name = str(row[0]).lower()
        if q in name:
            if name == q:
                exact.append(doc)
            elif name.startswith(q):
                starts.append((len(name), doc))
            else:
                inside.append((len(name), doc))
        elif q in str(row[1] or "").lower():
            labelled.append(doc)

    starts.sort()
    inside.sort()
    ranked = exact + [d for _, d in starts] + [d for _, d in inside] + labelled
    return ranked[:limit]


class Retriever:
    """BM25 and substring, optionally with semantic search and expansion.

    Everything above this is unchanged when the optional halves are off: one
    BM25 pass, one substring pass, same ranking, same results. That is
    deliberate — the lexical path is what runs when there is no index, no
    Ollama, or no time.
    """

    def __init__(self, corpus, bm25: Bm25, cfg, vectors=None):
        self.corpus = corpus
        self.bm25 = bm25
        self.cfg = cfg
        self.vectors = vectors

    def _wave_index(self, wave: str | None) -> int:
        return self.corpus.waves.index(wave) if wave else -1

    def run(self, query: str, *, limit: int, wave: str | None = None,
            settings=None, pool: int | None = None) -> tuple[list[int], dict]:
        """Ranked rows, plus what was actually done to get them.

        The second return value is not diagnostics for its own sake: the
        transcript tells the researcher every lookup the assistant made, and
        "searched for three other phrasings as well" is part of that.

        `pool` is how deep each individual run goes before fusion, and it is
        separate from `limit` because the two answer to different needs. A
        model wants the best ten of a considered 150. The atlas counts its
        matches per wave and per measurement level, so a pool of 150 would
        not truncate its list — it would silently make "1,240 matches across
        9 sweeps" a statement about the top 150 instead.
        """
        s = settings or Settings.from_config(self.cfg)
        pool = pool or self.cfg.pool
        wave_idx = self._wave_index(wave)
        report = {"queries": [query], "semantic": False, "expanded": False,
                  "substring": 0, "note": None, "semantic_rows": set()}
        found_by_meaning: set[int] = set()

        queries = [query]
        if s.expand and s.expansions and s.helper_model:
            queries = expansion.phrasings(
                self.cfg, query, count=s.expansions,
                model=s.helper_model, base=s.base_url,
            )
            report["queries"] = queries
            report["expanded"] = len(queries) > 1

        runs, weights = [], []
        for phrasing in queries:
            runs.append(self.bm25.search(phrasing, pool, wave_idx))
            weights.append(s.lexical_weight)

        # Only the query as typed is matched literally. An expansion is the
        # model's paraphrase, and a paraphrase has no claim to be a fragment
        # of a name — matching "general health" as a substring would find
        # labels that happen to contain it while adding nothing to the case
        # that a half-typed code is what was meant.
        if s.substring:
            found = substring(self.corpus, query, pool, wave_idx)
            if found:
                runs.append(found)
                weights.append(s.substring_weight)
                report["substring"] = len(found)

        if s.semantic and self.vectors is not None:
            try:
                for phrasing in queries:
                    hits = self.vectors.search(phrasing, self.cfg.semantic_pool,
                                               s.base_url)
                    rows = [row for row, _ in hits
                            if wave_idx < 0 or self.corpus.vars[row][3] == wave_idx]
                    runs.append(rows)
                    weights.append(s.semantic_weight)
                    found_by_meaning.update(rows)
                report["semantic"] = True
                report["semantic_rows"] = found_by_meaning
            except Exception as err:                      # noqa: BLE001
                # A missing model or a stopped Ollama must degrade the search,
                # not end the turn. The lexical runs are already in hand.
                report["note"] = f"semantic search unavailable ({err})"

        if len(runs) == 1:
            return runs[0][:limit], report
        return fuse(runs, self.cfg.fusion_k, weights)[:limit], report


class Settings:
    """Per-turn retrieval settings: config defaults, overridable by the client.

    The drawer exposes these so a researcher can trade breadth against speed
    without editing a file, in the same way it already exposes the model.
    """

    __slots__ = ("semantic", "expand", "expansions", "lexical_weight",
                 "semantic_weight", "substring", "substring_weight",
                 "candidates", "helper_model", "base_url")

    def __init__(self, **kw):
        for name in self.__slots__:
            setattr(self, name, kw.get(name))

    @classmethod
    def from_config(cls, cfg, **over):
        base = {
            "semantic": cfg.semantic,
            "expand": cfg.expand,
            "expansions": cfg.expansions,
            "lexical_weight": cfg.lexical_weight,
            "semantic_weight": cfg.semantic_weight,
            "substring": cfg.substring,
            "substring_weight": cfg.substring_weight,
            "candidates": cfg.candidates,
            "helper_model": "",
            "base_url": None,
        }
        base.update({k: v for k, v in over.items() if v is not None})
        return cls(**base)

    def but(self, **over):
        """A copy with some fields replaced.

        The server knows the researcher's preferences; only the agent knows
        which model and host this turn is using. Neither should have to know
        the other's fields.
        """
        current = {name: getattr(self, name) for name in self.__slots__}
        current.update({k: v for k, v in over.items() if v is not None})
        return type(self)(**current)

    @classmethod
    def from_json(cls, body: dict, cfg):
        """What the browser sends. Absent keys keep the configured default."""
        body = body or {}

        def number(key, cast, low, high, default):
            try:
                value = cast(body[key])
            except (KeyError, TypeError, ValueError):
                return default
            return max(low, min(high, value))

        return cls.from_config(
            cfg,
            semantic=body.get("semantic"),
            expand=body.get("expand"),
            substring=body.get("substring"),
            expansions=number("expansions", int, 0, expansion.CEILING, None),
            lexical_weight=number("lexicalWeight", float, 0.0, 5.0, None),
            semantic_weight=number("semanticWeight", float, 0.0, 5.0, None),
            substring_weight=number("substringWeight", float, 0.0, 5.0, None),
            candidates=number("candidates", int, 1, 50, None),
        )


def coverage(corpus, bm25: Bm25, query: str, retriever=None, settings=None) -> dict:
    """Where a concept was measured, wave by wave.

    `search_grouped` ranks every wave against every other and returns the best
    handful overall, so a concept carried through the whole study is reported
    from wherever it happens to rank — and a wave with a real but
    lower-scoring variable looks like a wave with nothing. The information is
    not missing, only truncated: for "general health" the 29y and 38y
    variables sit at rank 72 and 76 of a 150-document pool.

    So this scores once, exactly as a search does, and then buckets by wave
    instead of cutting globally. Every wave is reported, including the ones
    with nothing, because "not measured here" is the answer as often as the
    variable name is.

    Two thresholds, both from `dataset.toml`, over the share of the query's
    idf mass a match actually accounts for:

    - at or above `coverage_strong`, the wave is reported as measured;
    - at or above `coverage_weak`, candidates are listed but nothing is
      claimed - the label is shown so the reader can judge;
    - below it, nothing is shown, because a match on one common word is not
      evidence of anything.

    The weak tier is not a hedge, it is the point. `hlthgen` ("How is your
    health generally") does not match the term "general" at all, since
    "generally" does not stem to it - so a strict floor would drop the very
    wave this tool exists to surface. It ranks second within its own wave,
    and second within a wave is visible in a way that rank 72 overall is not.
    """
    terms = [t for t in set(bm25.tokenize(query)) if bm25._idf(t) > 0]
    if not terms:
        return {"terms": [], "waves": [], "unknown_terms": True, "how": {}}

    # One ranked pass over everything scored, then bucketed. Ordering inside a
    # wave stays BM25's, not the idf share: the share says how much of the
    # query a label touches, which is a filter, while the score says how well
    # it matches, which is what should be read first.
    if retriever is not None:
        ranked, how = retriever.run(query, limit=len(bm25.doc_len), settings=settings)
    else:
        ranked, how = bm25.search(query, len(bm25.doc_len)), {}

    # A label is judged against the BEST of the wordings searched, not against
    # the one the model happened to type. Every extra word raises the idf mass
    # a label has to account for, so "self rated general health" confirms
    # nothing while "general health" confirms five waves — and when expansion
    # has already produced the second, insisting on the first would throw away
    # the evidence it just gathered. Only wordings count here, never the
    # embedding: a share is a share, and this stays comparable to the
    # thresholds it is measured against.
    wordings = [query] + [q for q in (how.get("queries") or []) if q != query]
    measures = []
    for wording in wordings:
        its_terms = [t for t in set(bm25.tokenize(wording)) if bm25._idf(t) > 0]
        if not its_terms:
            continue
        its_total = sum(bm25._idf(t) for t in its_terms) or 1.0
        its_postings = {t: {d for d, _ in bm25.postings.get(t, ())} for t in its_terms}
        measures.append((its_terms, its_total, its_postings))

    def share(doc: int) -> float:
        return max(
            (sum(idf for t, idf in ((t, bm25._idf(t)) for t in ts) if doc in ps[t]) / tot
             for ts, tot, ps in measures),
            default=0.0,
        )

    # A variable found by meaning rather than by words has, almost by
    # definition, a poor lexical share - "How is your health generally" does
    # not contain "self" or "rated" - so the floor that keeps coincidences out
    # would throw away exactly what the embedding just recovered. Those rows
    # skip the floor. They never clear the confirmation bar either: the
    # thresholds above are calibrated on idf mass and mean nothing against a
    # cosine, so semantic evidence surfaces a candidate and the reader judges
    # it, which is what the middle tier is for.
    by_meaning = how.get("semantic_rows") or set()

    found: dict[str, list[tuple[float, int]]] = {}
    for doc in ranked:
        got = share(doc)
        if got < bm25.cfg.coverage_weak and doc not in by_meaning:
            continue
        found.setdefault(corpus.wave_of(doc), []).append((got, doc))

    waves = []
    for wave in corpus.waves:
        ranked = found.get(wave, [])
        strong = [c for c in ranked if c[0] >= bm25.cfg.coverage_strong]
        # Once a wave has a confirmed match, its weaker ones are noise beside
        # it - listing "GENERAL READING OR WRITING" under a wave that plainly
        # measured general health only invites the model to hedge.
        candidates = (strong or ranked)[:bm25.cfg.coverage_examples]
        measured = bool(strong)
        waves.append({
            "wave": wave,
            "measured": measured,
            "matches": [
                {
                    "name": corpus.vars[doc][0],
                    "label": corpus.vars[doc][1] or None,
                    "file": corpus.file_of(doc).get("name"),
                    "strong": got >= bm25.cfg.coverage_strong,
                }
                for got, doc in candidates
            ],
        })

    return {"terms": sorted(terms), "waves": waves, "unknown_terms": False,
            "how": how}


def search_rows(corpus, bm25: Bm25, query: str, *, limit: int,
                wave: str | None = None, retriever=None, settings=None) -> dict:
    """Ranked ROW INDICES, for a caller that already holds the corpus.

    The atlas draws one line per variable and tallies its own facets, so
    collapsing by label — right for a model reading ten candidates — throws
    away exactly what it needs. It also already has every row in memory from
    `variables.json`, so sending positions rather than records keeps a
    thousand-hit search to a few kilobytes.

    Those positions are only meaningful against the build they came from.
    That is safe by construction here and nowhere else: the page fetched
    `variables.json` and `manifest.json` from this same process at boot. It
    is the assumption `vectors.py` makes about its index, and it fails the
    same way — silently — so nothing else should adopt it.
    """
    if wave and wave not in corpus.waves:
        return {"rows": [], "unknown_wave": wave, "how": {}}

    # Pool as deep as the answer asked for: the caller counts what comes back.
    docs, how = _ranked(corpus, bm25, query, limit, wave, retriever, settings,
                        pool=limit)
    return {
        "rows": docs,
        "unknown_wave": None,
        "how": {k: v for k, v in how.items() if k != "semantic_rows"},
    }


def _ranked(corpus, bm25: Bm25, query: str, limit: int, wave: str | None,
            retriever, settings, pool: int | None = None) -> tuple[list[int], dict]:
    """One ranked pass, however much of the machinery is available.

    `retriever` is optional so every existing caller - and any checkout with
    no index and no Ollama - keeps the plain lexical path it had.
    """
    if retriever is not None:
        return retriever.run(query, limit=limit, wave=wave, settings=settings,
                             pool=pool)
    wave_idx = corpus.waves.index(wave) if wave else -1
    return bm25.search(query, limit, wave_idx), {}


def search_grouped(corpus, bm25: Bm25, query: str, *, limit: int,
                   wave: str | None = None, retriever=None, settings=None) -> dict:
    """The entry point for a reader of ten candidates. Groups by description.

    `retriever` is optional so every existing caller - and any checkout with
    no index and no Ollama - keeps the plain lexical path it had.
    """
    if wave and wave not in corpus.waves:
        return {"groups": [], "unknown_wave": wave, "how": {}}

    docs, how = _ranked(corpus, bm25, query, bm25.cfg.pool, wave,
                        retriever, settings)

    # `semantic_rows` is a set of row indices for coverage() to consult, and
    # this result is serialised straight to JSON by /api/search. Dropping it
    # here rather than converting it: nothing downstream of a grouped search
    # wants row numbers, and shipping them would only invite a caller to
    # depend on positions that a rebuild invalidates.
    return {
        "groups": group(corpus, docs, limit),
        "unknown_wave": None,
        "how": {k: v for k, v in how.items() if k != "semantic_rows"},
    }
