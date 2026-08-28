"""Moving between intents: the rules, and every way one can be unreachable.

    python3 -m unittest discover -s web/tests

The assistant used to pick an intent afresh on every message. That is right
for answering a question and wrong for an interview — a researcher asking
"which sweeps have this?" halfway through would be routed out of the very
thing they asked to start. An intent may now declare itself `sticky`, entered
only by a proposal the researcher accepts and left only on an explicit stop.

Like `test_config.py` and `test_transcript.py`, this lives outside the
LangGraph half so CI can run it in a checkout that installed nothing. The
machine in `router.transition` is pure for exactly that reason: the graph
supplies `ask_model` and stores the answer, and every rule below is decided
here.
"""

from __future__ import annotations

import sys
import tomllib
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB))

from assistant import router  # noqa: E402
from config import ALL_TOOLS, Config, ConfigError, DEFAULT_CONFIG  # noqa: E402


def config_with(*intents: dict) -> Config:
    """The real dataset config, with its intents replaced."""
    raw = tomllib.loads(DEFAULT_CONFIG.read_text("utf-8"))
    raw["intent"] = list(intents)
    cfg = Config(raw, DEFAULT_CONFIG)
    cfg.validate()
    return cfg


CHAT = {
    "id": "chat", "label": "general",
    "description": "talking about the study",
    "instructions": "Answer them.",
    "advances": False,
}
INTERVIEW = {
    "id": "variable_interviewer", "label": "variable interviewer",
    "description": "a variable request being built",
    "instructions": "Work the checklist.",
    "advances": True,
    "sticky": True,
    "entry": "handoff",
    "confirm": "Shall I take you through the request?",
    "exits_to": "chat",
    "replies": ["Yes, start the request", "No, I'm just asking"],
}


def machine() -> Config:
    return config_with(CHAT, INTERVIEW)


class Defaults(unittest.TestCase):
    """An intent that says nothing new behaves exactly as it did."""

    def test_an_intent_that_declares_nothing_new_behaves_as_it_always_did(self):
        """The defaults are what let the two original intents keep working
        through this change without restating anything."""
        plain = config_with({"id": "only", "label": "l", "description": "d",
                             "instructions": "i", "advances": True}).intent("only")
        self.assertFalse(plain.sticky)
        self.assertEqual(plain.entry, "router")
        self.assertEqual(plain.tools, (ALL_TOOLS,))
        self.assertEqual(plain.exits_to, "")
        self.assertEqual(plain.replies, ())
        # Extraction ran on every turn before it was nameable.
        self.assertEqual(plain.extracts, plain.advances)

    def test_the_shipped_config_is_a_general_agent_and_a_specialist(self):
        from config import get as get_config
        cfg = get_config()
        self.assertEqual(cfg.fallback_intent.id, "chat")
        self.assertEqual([i.id for i in cfg.router_intents], ["chat"])
        self.assertEqual([i.id for i in cfg.handoff_intents], ["variable_interviewer"])

        chat, interview = cfg.intent("chat"), cfg.intent("variable_interviewer")
        # The general agent answers and credits nothing, and the slowest node
        # in the graph does not run for it.
        self.assertFalse(chat.advances)
        self.assertFalse(chat.extracts)
        self.assertFalse(chat.sticky)
        # The specialist is entered by acceptance, stayed in, and left to chat.
        self.assertTrue(interview.sticky)
        self.assertTrue(interview.extracts)
        self.assertEqual(interview.exits_to, "chat")
        self.assertTrue(interview.confirm)
        self.assertGreaterEqual(len(interview.replies), 2)

    def test_the_offer_can_be_accepted_by_clicking_its_own_first_reply(self):
        """The buttons and the acceptance rule have to agree, or the obvious
        way to say yes does not work."""
        from config import get as get_config
        yes, *rest = get_config().intent("variable_interviewer").replies
        self.assertTrue(router.is_affirmative(yes))
        self.assertFalse(any(router.is_affirmative(r) for r in rest))

    def test_extracts_can_be_asked_for_without_advancing(self):
        """The reason it is a field and not a synonym for `advances`.

        An intent can want the draft to fill in from an aside without
        crediting a checklist step for it.
        """
        cfg = config_with({**CHAT, "extracts": True}, INTERVIEW)
        chat = cfg.intent("chat")
        self.assertTrue(chat.extracts)
        self.assertFalse(chat.advances)


class Reachability(unittest.TestCase):
    """Every shape of intent that nothing could ever reach.

    None of these is hypothetical: an intent the router cannot choose and no
    handoff can offer loads happily and is then simply never used, and the
    symptom gives no hint where to look.
    """

    def test_the_shipped_config_still_validates(self):
        from config import get as get_config
        get_config().validate()

    def assertRefused(self, *intents: dict, saying: str):
        with self.assertRaises(ConfigError) as caught:
            config_with(*intents)
        self.assertIn(saying, str(caught.exception))

    def test_a_sticky_fallback_could_never_be_left(self):
        self.assertRefused({**CHAT, "sticky": True}, INTERVIEW,
                           saying="never leave")

    def test_a_fallback_entered_by_handoff_could_never_be_reached(self):
        self.assertRefused({**CHAT, "entry": "handoff", "confirm": "?",
                            "replies": ["Yes", "No"]},
                           INTERVIEW, saying="nothing could ever reach it")

    def test_a_handoff_intent_needs_something_to_propose_with(self):
        no_confirm = {k: v for k, v in INTERVIEW.items() if k != "confirm"}
        self.assertRefused(CHAT, no_confirm, saying="no `confirm`")

    def test_a_handoff_intent_needs_a_way_to_answer_the_offer(self):
        self.assertRefused(CHAT, {**INTERVIEW, "replies": ["Yes"]},
                           saying="least two `replies`")

    def test_an_unknown_entry_is_a_typo_not_a_new_mode(self):
        self.assertRefused(CHAT, {**INTERVIEW, "entry": "handover"},
                           saying="expected one of")

    def test_exits_to_must_name_a_real_intent(self):
        self.assertRefused(CHAT, {**INTERVIEW, "exits_to": "chatt"},
                           saying="not an intent")

    def test_an_intent_may_not_exit_to_itself(self):
        self.assertRefused(CHAT, {**INTERVIEW, "exits_to": "variable_interviewer"},
                           saying="exits to itself")

    def test_sticky_may_not_exit_into_sticky(self):
        self.assertRefused(
            CHAT,
            {**INTERVIEW, "exits_to": "verify"},
            {"id": "verify", "label": "verifying", "description": "d",
             "instructions": "i", "advances": False, "sticky": True,
             "entry": "handoff", "confirm": "?", "replies": ["Yes", "No"]},
            saying="exits into another sticky")

    def test_duplicate_ids_are_refused(self):
        self.assertRefused(CHAT, INTERVIEW, {**INTERVIEW, "sticky": False,
                                             "entry": "router"},
                           saying="duplicate id")

    def test_an_empty_tool_list_is_a_mistake_not_a_muzzle(self):
        self.assertRefused({**CHAT, "tools": []}, INTERVIEW,
                           saying="empty `tools`")


class Accessors(unittest.TestCase):
    def setUp(self):
        self.cfg = machine()

    def test_the_router_is_never_offered_a_handoff_intent(self):
        self.assertEqual([i.id for i in self.cfg.router_intents], ["chat"])
        self.assertEqual([i.id for i in self.cfg.handoff_intents], ["variable_interviewer"])

    def test_exit_honours_exits_to_and_falls_back_otherwise(self):
        self.assertEqual(self.cfg.exit_intent(self.cfg.intent("variable_interviewer")).id, "chat")
        bare = config_with(CHAT, {**INTERVIEW, "exits_to": ""})
        self.assertEqual(bare.exit_intent(bare.intent("interview")).id, "chat")

    def test_tools_default_to_all_of_them(self):
        chat = self.cfg.intent("chat")
        self.assertTrue(self.cfg.may_use(chat, "search_variables"))
        narrowed = config_with({**CHAT, "tools": ["coverage"]}, INTERVIEW)
        only = narrowed.intent("chat")
        self.assertTrue(narrowed.may_use(only, "coverage"))
        self.assertFalse(narrowed.may_use(only, "search_variables"))


class Recogniser(unittest.TestCase):
    """The rules behind the model, tested on their own."""

    def test_a_question_about_the_data_is_not_a_derivation_request(self):
        for text in ("Which sweeps measured height?",
                     "What does b8hlthgn mean?",
                     "How many variables are there at 42y?",
                     "Is self-rated health in the 29y sweep?"):
            self.assertFalse(router.wants_derivation(text), text)

    def test_asking_for_something_built_is(self):
        for text in ("Can you derive BMI across the sweeps?",
                     "I want housing tenure harmonised",
                     "I'd like a variable for maternal smoking",
                     "we need a column for social class"):
            self.assertTrue(router.wants_derivation(text), text)

    def test_the_rule_is_blunt_and_the_model_is_the_primary_path(self):
        """Recorded, not endorsed.

        Wanting-language aimed at the word "variable" reads as a request even
        when it is a question. The proposal is what makes this cheap: the
        researcher says no and the turn carries on.
        """
        self.assertTrue(router.wants_derivation(
            "I need to know which variables measure height"))

    def test_stop_mid_sentence_is_not_an_exit(self):
        """The case that would drop someone out of the interview for asking
        an ordinary question — this corpus is full of stopping smoking.

        Every line here has ended an interview by accident at some point in
        writing this rule. The six-word question is the one that got past a
        word-count threshold of six; the last two got past a rule that let any
        multi-word phrase open a message.
        """
        for text in ("Did they stop smoking between 26y and 29y?",
                     "Did they stop smoking by 29y?",
                     "did they stop smoking by 29y",
                     "stop smoking questions are at 29y",
                     "Only for mothers who stopped work after the birth",
                     "The 16y sweep asks when they stopped attending",
                     "no more than 3 sweeps please",
                     "go back to the 16y sweep for that"):
            self.assertFalse(router.is_exit(text), text)

    def test_a_question_is_never_an_exit_however_it_is_worded(self):
        """They are waiting on an answer, not asking to leave."""
        self.assertFalse(router.is_exit("stop?"))
        self.assertFalse(router.is_exit("should we stop there?"))

    def test_restarting_is_not_leaving(self):
        """"start over" asks to redo the interview, not to end it — the
        checklist reopens a step when the extractor reports a revision."""
        self.assertFalse(router.is_exit("start over"))
        self.assertFalse(router.is_exit("start over from the concept step"))

    def test_an_explicit_stop_is(self):
        for text in ("stop", "Stop.", "cancel this", "never mind",
                     "forget it", "I'm done", "let's stop", "go back",
                     "stop for now", "that's enough for now",
                     "never mind, let's do something else"):
            self.assertTrue(router.is_exit(text), text)

    def test_only_a_plain_yes_accepts(self):
        for text in ("yes", "Yes please", "Yes, start the request",
                     "sure, go ahead", "ok let's do that", "yep",
                     "that's right", "go ahead", "please do",
                     "yes please, that is exactly what I want"):
            self.assertTrue(router.is_affirmative(text), text)
        for text in ("actually, which sweeps have height?", "not yet",
                     "no", "hold on", "what would that involve?"):
            self.assertFalse(router.is_affirmative(text), text)

    def test_a_question_is_never_an_acceptance(self):
        """The four that used to slip through, and why it matters.

        `right`, `correct`, `ok` and `sure` are discourse markers as often as
        they are agreement, and this is the rule BEHIND the model — it decides
        when the model is unreachable, which is when things are already going
        wrong. Each of these was read as a yes and put the researcher into an
        interview they had not agreed to.
        """
        for text in ("Right, which sweeps have height?",
                     "Right then, what does b8hlthgn mean?",
                     "Correct me if I'm wrong, but isn't BMI already there?",
                     "Sure, but first — which sweeps?",
                     "ok what about maternal smoking?",
                     "Yes — but which sweeps should I say?"):
            self.assertFalse(router.is_affirmative(text), text)

    def test_an_ambiguous_opener_must_be_the_whole_message(self):
        """No question mark, but still not agreement."""
        self.assertFalse(router.is_affirmative(
            "Right, I also need housing tenure as well as this"))
        self.assertTrue(router.is_affirmative("right"))


class AnswerButtons(unittest.TestCase):
    """Which step the buttons under a reply belong to.

    `None` from `driving` means no step is in play — a non-advancing intent,
    or a finished checklist — and the rescue that guesses buttons from the
    prose used to be able to hand a step straight back. That parked the last
    step's stock answers under a message saying the request was complete, on
    every turn after it, with no way out but a reset.
    """

    def test_a_rescued_step_refines_the_one_being_worked_on(self):
        self.assertEqual(router.step_for_options("coverage", "concept"), "concept")

    def test_it_falls_back_to_the_driving_step(self):
        self.assertEqual(router.step_for_options("coverage", None), "coverage")

    def test_it_may_never_invent_one(self):
        self.assertIsNone(router.step_for_options(None, "identity"))

    def test_nothing_in_play_stays_nothing(self):
        self.assertIsNone(router.step_for_options(None, None))


class OfferingOneOfSeveral(unittest.TestCase):
    """Which specialist a message asks to start.

    Asking per intent cost a round trip each and made the order in
    `dataset.toml` the tie-break — the first to say yes won, which is not a
    decision that belongs in a list's order.
    """

    def setUp(self):
        self.cfg = config_with(
            CHAT, INTERVIEW,
            {**INTERVIEW, "id": "verifier", "label": "verifier",
             "description": "checking a variable against the real files"})
        self.calls = []

    def answering(self, start):
        def ask(instruction, schema):
            self.calls.append(schema["properties"]["start"]["enum"])
            return {"start": start}
        return ask

    def test_one_call_however_many_there_are(self):
        router.transition(self.cfg, "chat", "which sweeps measured height?",
                          has_history=True, ask_model=self.answering(""))
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0],
                         ["variable_interviewer", "verifier", ""])

    def test_the_model_picks_not_the_config_order(self):
        out = router.transition(self.cfg, "chat", "check bmi against the files",
                                has_history=True, ask_model=self.answering("verifier"))
        self.assertEqual(out.proposing, "verifier")

    def test_an_empty_answer_proposes_nothing(self):
        out = router.transition(self.cfg, "chat", "what does b8hlthgn mean?",
                                has_history=True, ask_model=self.answering(""))
        self.assertFalse(out.is_proposal)

    def test_an_id_that_is_not_on_offer_is_ignored(self):
        out = router.transition(self.cfg, "chat", "I want BMI harmonised",
                                has_history=True, ask_model=self.answering("chat"))
        # Falls through to the rule, which knows only "something wants
        # deriving" and can therefore only offer the first.
        self.assertEqual(out.proposing, "variable_interviewer")


class Machine(unittest.TestCase):
    """`transition()` itself, with no model behind it."""

    def setUp(self):
        self.cfg = machine()

    def go(self, mode, text, **kw):
        return router.transition(self.cfg, mode, text,
                                 has_history=kw.pop("has_history", True), **kw)

    def test_the_opening_message_goes_to_the_fallback_whatever_it_says(self):
        out = self.go(None, "derive BMI for me", has_history=False)
        self.assertEqual(out.mode, "chat")
        self.assertEqual(out.how, "first message")
        self.assertFalse(out.is_proposal)

    def test_an_ordinary_question_stays_in_chat_without_a_proposal(self):
        out = self.go("chat", "Which sweeps measured height?")
        self.assertEqual(out.mode, "chat")
        self.assertFalse(out.is_proposal)

    def test_a_derivation_request_is_proposed_not_entered(self):
        """The confirmation is the whole point: wanting it is not being in it."""
        out = self.go("chat", "I want BMI harmonised across the sweeps")
        self.assertEqual(out.mode, "chat")
        self.assertEqual(out.proposing, "variable_interviewer")
        self.assertFalse(out.entering)

    def test_accepting_enters_and_flags_the_draft_for_seeding(self):
        out = self.go("chat", "yes please", awaiting="variable_interviewer")
        self.assertEqual(out.mode, "variable_interviewer")
        self.assertEqual(out.how, "accepted")
        self.assertTrue(out.entering)

    def test_anything_but_a_yes_declines(self):
        out = self.go("chat", "actually, which sweeps have height?",
                      awaiting="variable_interviewer")
        self.assertEqual(out.mode, "chat")
        self.assertEqual(out.how, "declined")
        self.assertFalse(out.entering)

    def test_a_question_inside_the_interview_does_not_leave_it(self):
        """`explore` stops being a mode: the interviewer answers and carries on."""
        out = self.go("variable_interviewer", "Which sweeps have self-rated health?")
        self.assertEqual(out.mode, "variable_interviewer")
        self.assertEqual(out.how, "sticky")

    def test_an_explicit_stop_leaves(self):
        out = self.go("variable_interviewer", "stop for now")
        self.assertEqual(out.mode, "chat")
        self.assertEqual(out.how, "exit")

    def test_a_stale_proposal_is_dropped_rather_than_acted_on(self):
        """`awaiting` naming something no longer entered by handoff means the
        config changed mid-conversation. A yes must not act on it."""
        out = self.go("chat", "yes", awaiting="chat")
        self.assertEqual(out.mode, "chat")
        self.assertEqual(out.how, "proposal expired")
        self.assertFalse(out.entering)

    def test_an_unreadable_mode_lands_on_the_fallback(self):
        out = self.go("nonsense", "Which sweeps measured height?")
        self.assertEqual(out.mode, "chat")


class TheModelBehindIt(unittest.TestCase):
    """`ask_model` is injected, so what it is asked and when is testable."""

    def setUp(self):
        self.cfg = machine()
        self.calls: list[dict] = []

    def answering(self, **reply):
        def ask(instruction, schema):
            self.calls.append({"instruction": instruction, "schema": schema})
            return reply
        return ask

    def test_a_sticky_turn_asks_the_model_nothing(self):
        """The saving, and the reason stickiness is cheaper as well as steadier."""
        out = router.transition(self.cfg, "variable_interviewer", "Which sweeps have it?",
                                has_history=True,
                                ask_model=self.answering(start="variable_interviewer"))
        self.assertEqual(out.mode, "variable_interviewer")
        self.assertEqual(self.calls, [])

    def test_the_model_can_propose_where_the_rule_would_not(self):
        out = router.transition(
            self.cfg, "chat", "could you put together age at first birth?",
            has_history=True,
            ask_model=self.answering(start="variable_interviewer"))
        self.assertEqual(out.proposing, "variable_interviewer")
        self.assertEqual(len(self.calls), 1)

    def test_the_model_can_decline_where_the_rule_would_propose(self):
        out = router.transition(
            self.cfg, "chat", "I need to know which variables measure height",
            has_history=True, ask_model=self.answering(start=""))
        self.assertFalse(out.is_proposal)

    def test_a_mistake_in_our_own_code_is_not_a_model_failure(self):
        """The catch-all used to hide both.

        A typo in an instruction builder degraded every routing decision to
        the heuristic with nothing said anywhere — which is how a broken probe
        for this very file reported zero model calls instead of an error.
        """
        def our_bug(instruction, schema):
            raise AttributeError("typo in start_instruction")
        with self.assertRaises(AttributeError):
            router.transition(self.cfg, "chat", "please derive BMI",
                              has_history=True, ask_model=our_bug)

    def test_the_world_failing_still_degrades(self):
        def network_down(instruction, schema):
            raise ConnectionError("ollama unreachable")
        out = router.transition(self.cfg, "chat", "please derive BMI",
                                has_history=True, ask_model=network_down)
        self.assertEqual(out.proposing, "variable_interviewer")

    def test_a_model_failure_degrades_to_the_rule_rather_than_the_turn(self):
        def explode(instruction, schema):
            raise RuntimeError("ollama is not running")
        out = router.transition(self.cfg, "chat", "please derive BMI",
                                has_history=True, ask_model=explode)
        self.assertEqual(out.proposing, "variable_interviewer")

    def test_a_nonsense_answer_degrades_the_same_way(self):
        """Including a model that answers the old boolean shape."""
        for answer in ("probably", True, None):
            out = router.transition(self.cfg, "chat", "please derive BMI",
                                    has_history=True,
                                    ask_model=self.answering(start=answer))
            self.assertEqual(out.proposing, "variable_interviewer", repr(answer))

    def test_the_proposal_it_is_answering_is_quoted_back(self):
        router.transition(self.cfg, "chat", "go on", awaiting="variable_interviewer",
                          has_history=True, ask_model=self.answering(accepted=True))
        self.assertIn("Shall I take you through the request?",
                      self.calls[0]["instruction"])

    def test_routing_offers_the_model_only_what_it_may_answer(self):
        """Describing an intent in the prompt while forbidding it in the
        schema asks for an answer that cannot be given."""
        cfg = config_with(CHAT, INTERVIEW,
                          {"id": "review", "label": "reviewing",
                           "description": "checking the draft so far",
                           "instructions": "Read it back.", "advances": False})
        router.transition(cfg, "chat", "how does that look?", has_history=True,
                          ask_model=self.answering(start=False, intent="review"))
        routing = self.calls[-1]["instruction"]
        self.assertIn("review", routing)
        self.assertNotIn("interview \u2014", routing)
        self.assertEqual(self.calls[-1]["schema"]["properties"]["intent"]["enum"],
                         ["chat", "review"])


if __name__ == "__main__":
    unittest.main()
