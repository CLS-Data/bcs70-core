"""The conversation the browser posts back, turned into messages.

    python3 -m unittest discover -s web/tests

The server is stateless, so every turn is reconstructed from what the client
sends. Two things about that have gone wrong, and both are silent: a tool
result paired to the wrong call, and a tool result that arrives empty.

Tested against `transcript.plan` rather than `agent.to_messages` because
`agent.py` imports LangChain and these have to run in a checkout that
installed nothing. `to_messages` maps this plan onto message classes and
makes no decisions of its own.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(WEB))

from assistant import transcript  # noqa: E402


def call(name, args=None):
    """A tool call as the browser stores it: no id, nested under `function`."""
    return {"function": {"name": name, "arguments": args or {}}}


class ToolResultsSurvive(unittest.TestCase):
    """The regression from Phase 1 of the review.

    The tool_result event carried only its display payload, so the browser
    stored `content: ""` and posted that back. The model's own history then
    said every lookup it had run returned nothing — which invites it to run
    the same lookup again, or to report a concept as absent because its
    record of finding it is blank. Nothing about that is visible: the
    transcript on screen showed the results perfectly well.
    """

    def test_a_lookup_keeps_what_it_found(self):
        out = transcript.plan([
            {"role": "user", "content": "is height measured at 10y?"},
            {"role": "assistant", "content": "",
             "tool_calls": [call("search_variables", {"query": "height"})]},
            {"role": "tool", "name": "search_variables",
             "content": "2 matches:\nb960421 | 10y | Height in metres"},
        ])
        result = out[-1]
        self.assertEqual(result["kind"], transcript.TOOL)
        self.assertIn("b960421", result["content"])

    def test_an_empty_result_is_still_carried(self):
        """"Nothing found" is a finding, and has to reach the model as one."""
        out = transcript.plan([
            {"role": "user", "content": "anything about tenure at 0y?"},
            {"role": "assistant", "content": "",
             "tool_calls": [call("search_variables")]},
            {"role": "tool", "name": "search_variables",
             "content": 'No variable matches "tenure" in 0y.'},
        ])
        self.assertIn("No variable matches", out[-1]["content"])


class Pairing(unittest.TestCase):
    """Ids are minted here and matched by position."""

    def test_a_result_is_paired_to_the_call_before_it(self):
        out = transcript.plan([
            {"role": "assistant", "content": "",
             "tool_calls": [call("coverage"), call("list_harmonised")]},
            {"role": "tool", "name": "coverage", "content": "first"},
            {"role": "tool", "name": "list_harmonised", "content": "second"},
        ])
        ai, first, second = out
        self.assertEqual([c["id"] for c in ai["tool_calls"]],
                         [first["tool_call_id"], second["tool_call_id"]])

    def test_every_id_in_a_conversation_is_distinct(self):
        out = transcript.plan([
            {"role": "assistant", "content": "", "tool_calls": [call("coverage")]},
            {"role": "tool", "name": "coverage", "content": "a"},
            {"role": "user", "content": "and smoking?"},
            {"role": "assistant", "content": "", "tool_calls": [call("coverage")]},
            {"role": "tool", "name": "coverage", "content": "b"},
        ])
        ids = [m["tool_call_id"] for m in out if m["kind"] == transcript.TOOL]
        self.assertEqual(len(ids), len(set(ids)))

    def test_an_id_the_client_supplies_is_kept(self):
        out = transcript.plan([
            {"role": "assistant", "content": "",
             "tool_calls": [{"id": "given", "function": {"name": "coverage"}}]},
            {"role": "tool", "name": "coverage", "content": "x"},
        ])
        self.assertEqual(out[1]["tool_call_id"], "given")

    def test_an_unpaired_result_is_dropped(self):
        # Some models reject a tool message with no matching call outright,
        # and take the whole turn down with it.
        out = transcript.plan([
            {"role": "user", "content": "hello"},
            {"role": "tool", "name": "search_variables", "content": "orphan"},
        ])
        self.assertEqual([m["kind"] for m in out], [transcript.HUMAN])

    def test_a_new_user_message_closes_any_outstanding_call(self):
        # The researcher typed while a lookup was in flight; whatever arrives
        # after that does not belong to the call before it.
        out = transcript.plan([
            {"role": "assistant", "content": "", "tool_calls": [call("coverage")]},
            {"role": "user", "content": "actually, never mind"},
            {"role": "tool", "name": "coverage", "content": "late"},
        ])
        self.assertEqual([m["kind"] for m in out],
                         [transcript.AI, transcript.HUMAN])

    def test_more_results_than_calls_drops_the_extra(self):
        out = transcript.plan([
            {"role": "assistant", "content": "", "tool_calls": [call("coverage")]},
            {"role": "tool", "name": "coverage", "content": "paired"},
            {"role": "tool", "name": "coverage", "content": "extra"},
        ])
        tools = [m for m in out if m["kind"] == transcript.TOOL]
        self.assertEqual([t["content"] for t in tools], ["paired"])


class Shapes(unittest.TestCase):
    """What the browser can send that is not quite what is expected."""

    def test_arguments_that_are_not_an_object_become_one(self):
        # A model answering its own schema loosely sends a string. An empty
        # dict is a lookup that finds nothing; a string is one that raises.
        out = transcript.plan([
            {"role": "assistant", "content": "",
             "tool_calls": [call("search_variables", "height")]},
        ])
        self.assertEqual(out[0]["tool_calls"][0]["args"], {})

    def test_an_empty_assistant_turn_is_not_sent(self):
        # The client opens a reply as soon as a turn starts and may never
        # fill it — an assistant message with no prose and no calls is that.
        out = transcript.plan([
            {"role": "user", "content": "hello"},
            {"role": "assistant", "content": "   "},
        ])
        self.assertEqual([m["kind"] for m in out], [transcript.HUMAN])

    def test_an_assistant_turn_with_only_calls_is_kept(self):
        out = transcript.plan([
            {"role": "assistant", "content": "", "tool_calls": [call("coverage")]},
        ])
        self.assertEqual(out[0]["kind"], transcript.AI)

    def test_missing_content_is_an_empty_string_not_a_crash(self):
        out = transcript.plan([{"role": "user"}])
        self.assertEqual(out[0]["content"], "")

    def test_an_empty_conversation_plans_to_nothing(self):
        self.assertEqual(transcript.plan([]), [])
        self.assertEqual(transcript.plan(None), [])


class MatchesTheRealMapping(unittest.TestCase):
    """`agent.to_messages` must still be a mapping and nothing more.

    Skipped without the assistant extra, which is the normal state in CI —
    everything above runs there, which is the point of the split.
    """

    def test_to_messages_agrees_with_the_plan(self):
        try:
            from assistant.agent import to_messages
        except ImportError:
            self.skipTest("needs the assistant extra")

        raw = [
            {"role": "user", "content": "is height measured at 10y?"},
            {"role": "assistant", "content": "",
             "tool_calls": [call("search_variables", {"query": "height"})]},
            {"role": "tool", "name": "search_variables", "content": "b960421 | 10y"},
            {"role": "assistant", "content": "Yes, at 10y."},
        ]
        planned = transcript.plan(raw)
        built = to_messages(raw)
        self.assertEqual(len(built), len(planned))
        # The tool result's text is what this whole phase is about.
        self.assertEqual(built[2].content, "b960421 | 10y")
        self.assertEqual(built[2].tool_call_id,
                         built[1].tool_calls[0]["id"])


if __name__ == "__main__":
    unittest.main()
