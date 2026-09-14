"""Cross-file facts about the atlas's layout that nothing else would catch.

    python3 -m unittest discover -s web/tests

The front end has no build step and no framework, which is why it is readable —
but it also means a constant shared between the stylesheet and a module, or a
control that has to exist once per view, is held together by nothing but
agreement. These are the places that agreement is load-bearing.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
CSS = WEB / "styles.css"
HTML = WEB / "index.html"
BOOT = WEB / "atlas" / "boot.js"
BASKET = WEB / "atlas" / "basket.js"
DERIVED = WEB / "atlas" / "derived.js"
METADATA = WEB / "atlas" / "metadata.js"


class TheResizableListColumn(unittest.TestCase):
    """The list column is resized by dragging a grip that sets `--rail`."""

    def test_the_default_width_agrees_between_css_and_js(self):
        """`--rail` is the width the page starts at; `RAIL_DEFAULT` is what a
        double-click or Home resets to. If they drift, resetting moves the
        divider somewhere the user never chose."""
        css = re.search(r"--rail:\s*(\d+)px", CSS.read_text("utf-8"))
        js = re.search(r"RAIL_DEFAULT\s*=\s*(\d+)", BOOT.read_text("utf-8"))
        self.assertIsNotNone(css, "--rail is gone from styles.css")
        self.assertIsNotNone(js, "RAIL_DEFAULT is gone from boot.js")
        self.assertEqual(css.group(1), js.group(1),
                         "--rail and RAIL_DEFAULT have drifted apart")

    def test_every_view_has_exactly_one_grip(self):
        """The grip is positioned against its view, so a view without one
        cannot be resized and a view with two stacks them invisibly."""
        views = re.findall(
            r'<section class="view[^"]*" data-view="([a-z]+)">(.*?)</section>',
            HTML.read_text("utf-8"), re.S)
        self.assertTrue(views, "no views found in index.html")
        for name, body in views:
            self.assertEqual(body.count('class="grip"'), 1,
                             f'view "{name}" does not have exactly one grip')

    def test_the_grip_is_reachable_without_a_mouse(self):
        """A separator only a pointer can move is one half the users cannot."""
        html = HTML.read_text("utf-8")
        self.assertIn('role="separator"', html)
        self.assertIn('tabindex="0"', html)
        boot = BOOT.read_text("utf-8")
        for key in ("ArrowLeft", "ArrowRight", "Home"):
            self.assertIn(key, boot, f"the grip has no {key} handler")

    def test_the_grip_is_hidden_where_the_layout_stacks(self):
        """Below the breakpoint the panes are one column, so a vertical
        divider has nothing to divide and would sit over the content."""
        css = CSS.read_text("utf-8")
        stacked = css[css.index(".view.is-current { grid-template-columns: 1fr; }"):]
        self.assertIn(".grip { display: none; }", stacked[:400])


class TheViewTabs(unittest.TestCase):
    """What the tabs are called, and what they are keyed by.

    The labels are the researcher's vocabulary and have changed; the
    `data-view` keys are the internal ones every CSS selector, `switchView()`
    call and `window.Atlas` consumer uses, and have not. Renaming a label must
    not quietly rename a key.
    """

    def test_the_tabs_read_as_the_researcher_thinks(self):
        html = HTML.read_text("utf-8")
        for key, label in (("metadata", "Raw variables"),
                           ("derived", "Research ready")):
            self.assertRegex(
                html, rf'data-view="{key}"[^>]*>{re.escape(label)}',
                f'the "{key}" tab is no longer labelled "{label}"')

    def test_the_internal_keys_are_unchanged(self):
        html = HTML.read_text("utf-8")
        for key in ("metadata", "derived", "basket"):
            self.assertIn(f'data-view="{key}"', html,
                          f'the "{key}" view key has been renamed — every '
                          f'switchView() caller and CSS selector uses it')


class TheAddControlToggles(unittest.TestCase):
    """The ✓ has to be a way back out, not a dead end.

    It is the control that looks most like a checkbox, so a click that could
    only be undone somewhere else entirely was the wrong shape. Both lists
    route through one function, because two lists deciding separately what a
    click means is how they come to disagree.
    """

    def test_the_tick_is_not_disabled(self):
        body = BASKET.read_text("utf-8")
        add = body[body.index("export function addButton"):]
        add = add[:add.index("\n}")]
        self.assertNotIn("aria-disabled", add,
                         "the in-bundle state is aria-disabled again, so it "
                         "cannot be clicked to remove")
        self.assertIn('aria-pressed="${isIn}"', add,
                      "the control no longer reports its pressed state")

    def test_the_tick_says_it_removes(self):
        body = BASKET.read_text("utf-8")
        self.assertIn("click to remove", body)
        self.assertRegex(body, r"Remove \$\{esc\(aria\)\} from the R bundle")

    def test_both_lists_route_through_one_decision(self):
        for path in (DERIVED, METADATA):
            self.assertIn("toggleFromButton", path.read_text("utf-8"),
                          f"{path.name} decides for itself what clicking the "
                          f"add control means")

    def test_the_hover_swap_has_both_glyphs(self):
        """✓ and ✕ are different statements; the markup carries both and CSS
        chooses, so there is no second render on hover."""
        self.assertIn("add-yes", BASKET.read_text("utf-8"))
        self.assertIn("add-no", BASKET.read_text("utf-8"))
        css = CSS.read_text("utf-8")
        self.assertIn(".add .add-no { display: none; }", css)
        self.assertIn(".add.is-in:hover .add-no", css)


class FamiliesAreGrouped(unittest.TestCase):
    """A family is one concept measured at each wave.

    People want all of it or none of it far more often than one wave, so the
    header carries a control for the whole family. What that control acts on
    must be what is on screen -- the same rule "Add all N shown" already
    followed -- or a search would silently add siblings you filtered out.
    """

    def test_the_family_control_acts_on_what_is_visible(self):
        body = DERIVED.read_text("utf-8")
        fn = body[body.index("function toggleFamily"):]
        fn = fn[:fn.index("\n}")]
        self.assertIn("visibleDerived()", fn,
                      "toggleFamily reads the whole registry, so a search would "
                      "add siblings that are filtered out of view")

    def test_the_header_counts_come_from_the_same_list(self):
        body = DERIVED.read_text("utf-8")
        self.assertIn("groupByFamily(list)", body,
                      "the family headers are built from something other than "
                      "the visible list, so the count and the control disagree")

    def test_a_family_is_keyed_by_category_and_family(self):
        """Two categories could hold a family of the same name; the key has to
        separate them or folding one would fold the other."""
        body = DERIVED.read_text("utf-8")
        self.assertIn("`${d.category}/${d.family}`", body)

    def test_folds_are_not_persisted(self):
        """A fold is a reading position. One set last week is a variable you
        cannot find today."""
        state = (WEB / "atlas" / "state.js").read_text("utf-8")
        self.assertIn("collapsedFamilies", state)
        self.assertNotIn('storeKey("collapsedFamilies")', state)
        self.assertNotIn("collapsedFamilies", BOOT.read_text("utf-8"))


if __name__ == "__main__":
    unittest.main()
