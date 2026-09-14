"""The contract between `templates/passthrough.R` and `web/bundle.js`.

    python3 -m unittest discover -s web/tests

A raw variable is the one thing the atlas generates R for rather than copying
it: a deposited column has no script in the repository. The generated script
is deliberately an ordinary variable script — so `R/runner.R` does the
resolving, the identifier cleaning, the duplicate resolution and the join for
it exactly as it does for a harmonised one — and that only holds while the
template keeps satisfying the rules `R/lib/discovery.R` enforces.

None of that is reachable from the browser, where the substitution actually
happens, so it is checked here against the template and the bundler's source.
These are the failures that would ship a bundle that cannot run: a placeholder
renamed on one side only, a category the runner rejects, or a template that
quietly stopped declaring the file and variable it reads.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
REPO = WEB.parent

TEMPLATE = REPO / "templates" / "passthrough.R"
RUN = REPO / "templates" / "run.R"
RPROFILE = REPO / "templates" / "project-Rprofile.R"
BUNDLER = WEB / "bundle.js"
DISCOVERY = REPO / "R" / "lib" / "discovery.R"
RUNNER = REPO / "R" / "runner.R"

PLACEHOLDER = re.compile(r"\{\{([a-z_]+)\}\}")


def template() -> str:
    return TEMPLATE.read_text("utf-8")


class Placeholders(unittest.TestCase):
    """Every `{{name}}` in the template is one the bundler substitutes.

    A placeholder the bundler does not know is not a no-op: `{{id}}` would
    reach the researcher's disk as a literal, and R would run it as one.
    """

    def test_template_exists(self):
        self.assertTrue(TEMPLATE.exists(), f"{TEMPLATE} is missing")

    def test_every_placeholder_is_substituted(self):
        # The bundler's substitution is a single alternation; read the names
        # out of it rather than restating them, so this cannot pass by
        # agreeing with a stale copy of the list.
        match = re.search(r"\\\{\\\{\(([a-z|]+)\)\\\}\\\}", BUNDLER.read_text("utf-8"))
        self.assertIsNotNone(match, "bundle.js no longer substitutes {{...}} placeholders")
        known = set(match.group(1).split("|"))

        used = set(PLACEHOLDER.findall(template()))
        self.assertTrue(used, "the template has no placeholders left in it")
        self.assertEqual(used - known, set(),
                         "template placeholders the bundler would leave as literals")

    def test_the_fields_a_run_depends_on_are_present(self):
        """Without these the script either cannot be found or reads nothing."""
        used = set(PLACEHOLDER.findall(template()))
        for field in ("id", "file", "var"):
            self.assertIn(field, used, f"{{{{{field}}}}} is no longer in the template")


class SatisfiesTheRunner(unittest.TestCase):
    """The generated script has to pass `R/lib/discovery.R` unchanged.

    `parse_variable_path` rejects a category outside its fixed list, and
    `check_variable_placement` rejects a spec whose category or id disagrees
    with where the file sits. The bundler writes passthroughs to
    `R/variables/other/raw_<file>/<column>.R`, so all three have to line up.
    """

    def test_template_declares_a_category_the_runner_accepts(self):
        declared = re.search(r'category\s*=\s*"([a-z_]+)"', template())
        self.assertIsNotNone(declared, "the template no longer declares a category")

        known = re.search(r"variable_categories\s*<-\s*c\((.*?)\)",
                          DISCOVERY.read_text("utf-8"), re.S)
        self.assertIsNotNone(known, "discovery.R no longer lists variable_categories")
        categories = set(re.findall(r'"([a-z_]+)"', known.group(1)))
        self.assertIn(declared.group(1), categories,
                      "the passthrough category is not one discovery.R accepts")

    def test_the_bundler_writes_into_that_same_category(self):
        declared = re.search(r'category\s*=\s*"([a-z_]+)"', template()).group(1)
        used = re.search(r'PASSTHROUGH_CATEGORY\s*=\s*"([a-z_]+)"',
                         BUNDLER.read_text("utf-8"))
        self.assertIsNotNone(used, "bundle.js no longer names a passthrough category")
        self.assertEqual(used.group(1), declared,
                         "the template's spec$category and the directory bundle.js "
                         "writes it to have drifted apart")

    def test_the_output_column_is_named_by_the_same_placeholder_as_the_file(self):
        """`spec$id` must equal the file name, and the bundler names the file
        from the column. Both therefore have to be `{{id}}`."""
        body = template()
        self.assertRegex(body, r'id\s*=\s*"\{\{id\}\}"')
        self.assertRegex(body, r'out\[\["\{\{id\}\}"\]\]')

    def test_it_reads_the_column_by_name_rather_than_with_dollar(self):
        """`load_tab()` reads with `check.names = FALSE`, so a deposited column
        can have a name `data$name` cannot reach."""
        body = template()
        self.assertIn('data[["{{var}}"]]', body)
        self.assertNotRegex(body, r"data\$\{\{var\}\}")


class TheProjectEntryPoint(unittest.TestCase):
    """`templates/run.R` is what a researcher actually opens and runs.

    It gets to reuse the runner's own discovery and spec loading — rather than
    carrying a second copy that could disagree about which scripts exist — only
    because `R/runner.R` guards its own invocation. Sourcing it has to define
    `run_all` WITHOUT running it; if that guard goes, run.R starts a full run
    during its pre-flight checks and every check after it is dead code.
    """

    def test_the_runner_does_not_run_itself_when_sourced(self):
        body = RUNNER.read_text("utf-8")
        self.assertRegex(
            body, r"if\s*\(\s*sys\.nframe\(\)\s*==\s*0L?\s*\)",
            "R/runner.R no longer guards its own invocation, so templates/run.R "
            "would trigger a full run while still checking whether one can happen",
        )

    def test_run_sources_the_runner_rather_than_reimplementing_it(self):
        body = RUN.read_text("utf-8")
        self.assertIn('source(file.path("R", "runner.R"))', body)
        for fn in ("find_variable_files", "load_variable", "run_all"):
            self.assertIn(fn, body, f"run.R no longer uses the runner's {fn}()")

    def test_run_does_not_reimplement_what_the_runner_now_owns(self):
        """run.R checks the environment; the runner checks the variables.

        It used to read every deposit's header row to work out which variables
        could be built. That became a second copy of the runner's own knowledge
        the moment `run_all()` learned to isolate per-variable failures — and a
        second copy is a second thing to disagree. run.R now checks only what
        nothing else can know before a run: where the data is, and whether the
        files exist at all.
        """
        body = RUN.read_text("utf-8")
        self.assertNotIn("columns_of", body,
                         "run.R is reading file headers again — deciding which "
                         "variables can be built belongs to run_all(), which "
                         "reports per-variable failures itself")
        self.assertNotIn("read.delim", body,
                         "run.R should open no deposit; it resolves paths from "
                         "the lookup and leaves reading to R/lib/io.R")

    def test_run_reports_what_the_runner_lost(self):
        """A partial output under the usual file name is easy to mistake for a
        complete one, so the two sources of loss are added up and named."""
        body = RUN.read_text("utf-8")
        self.assertIn('attr(result, "failures")', body,
                      "run.R no longer reads the runner's failure list, so a "
                      "partial run would look complete")
        self.assertIn("quit(status = 1L)", body,
                      "a partial run must exit non-zero for anything scripting it")

    def test_run_checks_before_it_reads(self):
        """Each of these is a failure a researcher hits before any data is read,
        and each has to be caught here rather than surfacing as an R traceback
        from somewhere inside the pipeline."""
        body = RUN.read_text("utf-8")
        self.assertIn('file.exists(file.path("R", "runner.R"))', body,
                      "run.R no longer checks the working directory")
        self.assertIn("has_lookup", body,
                      "run.R no longer checks that the data root holds the lookup")
        self.assertIn("blocked", body,
                      "run.R no longer works out which variables it cannot build")

    def test_every_placeholder_is_substituted(self):
        used = set(PLACEHOLDER.findall(RUN.read_text("utf-8")))
        declared = set(re.findall(r'"templates/run\.R":\s*\((.*?)\)',
                                  (WEB / "build_site.py").read_text("utf-8"), re.S)[0]
                       .replace('"', "").replace("\n", "").split(","))
        declared = {d.strip() for d in declared if d.strip()}
        self.assertEqual(used - declared, set(),
                         "run.R placeholders build_site.py does not know about")

    def test_the_bundler_fills_all_of_them(self):
        """An unfilled placeholder reaches the researcher's disk as a literal."""
        used = set(PLACEHOLDER.findall(RUN.read_text("utf-8")))
        fill = re.search(r"const scaffoldFill = \{(.*?)\n  \};",
                         BUNDLER.read_text("utf-8"), re.S)
        self.assertIsNotNone(fill, "bundle.js no longer builds a scaffold fill map")
        # Both spellings: `project: folder` and the shorthand `root,`.
        keys = set(re.findall(r"^\s*([a-z_]+)\s*[:,]$|^\s*([a-z_]+):",
                              fill.group(1), re.M))
        keys = {a or b for a, b in keys}
        self.assertEqual(used - keys, set(),
                         "run.R placeholders bundle.js would leave as literals")


class TheIdentifierIsNotAVariable(unittest.TestCase):
    """The identifier is in every dictionary, so the atlas can offer it — and
    must not.

    It is the key every variable is joined on and is already the first column
    of any download. Worse, a passthrough of it cannot run at all: `load_tab()`
    renames whichever column matches it case-insensitively to lower case, so a
    spec carrying a deposit's own casing of it names a column that no longer
    exists by the time the runner narrows to it.
    """

    def test_the_basket_refuses_it(self):
        body = (WEB / "atlas" / "basket.js").read_text("utf-8")
        self.assertIn("isIdentifier", body,
                      "basket.js no longer recognises the identifier, so it "
                      "could be added as a raw variable and the bundle would "
                      "fail with 'source_vars not found'")
        self.assertIn("!isIdentifier(b.name)", body,
                      "restoreBundle no longer drops the identifier, so a "
                      "basket saved before this fix stays broken")

    def test_the_metadata_view_offers_no_control_for_it(self):
        body = (WEB / "atlas" / "metadata.js").read_text("utf-8")
        self.assertIn("basket.isIdentifier(row[0])", body,
                      "the results list still draws an add control for the "
                      "identifier")

    def test_both_entry_points_check_it(self):
        """`R/runner.R` runs against data; `scripts/build_registry.R` is what CI
        runs. A spec rule wired into only the first goes green in CI and fails
        on a human's real-data run, which is the failure it exists to pre-empt.
        """
        for rel in ("R/runner.R", "scripts/build_registry.R"):
            self.assertIn("check_source_vars", (REPO / rel).read_text("utf-8"),
                          f"{rel} does not validate source_vars")

    def test_the_output_name_is_reserved_too(self):
        """Refusing the identifier as a SOURCE name does not cover it.

        The output column name is typed separately, by hand, in the bundle
        view. A raw column renamed to the identifier generates
        `out[[<identifier>]] <- data[["<var>"]]` — overwriting the key with the
        raw codes — and `runner.R` cannot catch it, because `derive()` returned
        both of the names it requires: they are the same string.
        """
        body = (WEB / "atlas" / "basket.js").read_text("utf-8")
        self.assertIn("state.dataset?.identifier", body)
        self.assertRegex(
            body, r"if \(id\) out\.add\(id\)",
            "takenColumns() no longer reserves the identifier, so a raw column "
            "can be renamed onto the join key")
        self.assertIn("if (identifier) seen.set(identifier, null)", body,
                      "problems() no longer reports a column renamed onto the "
                      "identifier")

    def test_the_identifier_comes_from_the_config(self):
        """Not hard-coded: another study's atlas has another identifier."""
        body = (WEB / "atlas" / "basket.js").read_text("utf-8")
        self.assertIn("state.dataset?.identifier", body)


class TheProjectProfile(unittest.TestCase):
    """`templates/project-Rprofile.R` ships as `.Rprofile` in the bundle.

    R sources a `.Rprofile` in the working directory for *every* session
    started there, `Rscript run.R` included, and a project one SHADOWS the
    user's own rather than adding to it. Both are easy to get wrong and neither
    is visible until it bites someone else's machine.
    """

    def test_it_only_acts_in_an_interactive_session(self):
        """Otherwise `Rscript run.R` prints a banner into whatever is parsing
        its output, and registers a hook in a session that has no RStudio."""
        body = RPROFILE.read_text("utf-8")
        self.assertIn("if (interactive())", body,
                      ".Rprofile no longer guards on interactive(), so a "
                      "scripted run would see its side effects")

    def test_it_chains_the_user_own_profile(self):
        """R loads the FIRST profile it finds, so a project one silently
        disables the user's CRAN mirror, prompt, and everything else."""
        body = RPROFILE.read_text("utf-8")
        self.assertIn('path.expand("~/.Rprofile")', body,
                      ".Rprofile no longer loads the user's own, so opening "
                      "this project would silently disable their settings")
        self.assertIn("silent = TRUE", body,
                      "a failure in the user's own profile must not stop ours")

    def test_opening_the_readme_cannot_break_a_session(self):
        """rstudioapi ships with RStudio but is an ordinary package and can be
        missing; the hook fires in a session that may have no README."""
        body = RPROFILE.read_text("utf-8")
        self.assertIn("rstudio.sessionInit", body,
                      "RStudio is not ready to be asked for anything at "
                      "profile time — the request has to wait for the hook")
        self.assertIn('requireNamespace("rstudioapi", quietly = TRUE)', body)
        self.assertIn('file.exists("README.md")', body)

    def test_the_bundler_writes_it_as_a_dotfile(self):
        body = BUNDLER.read_text("utf-8")
        self.assertIn("${folder}/.Rprofile", body,
                      "the profile is not written as .Rprofile, so R would "
                      "never source it")


class BuildShipsIt(unittest.TestCase):
    """`build_site.py` has to put the template where the browser can fetch it."""

    def test_the_templates_are_listed_for_the_bundle(self):
        source = (WEB / "build_site.py").read_text("utf-8")
        for rel in ("templates/passthrough.R", "templates/run.R",
                    "templates/project.Rproj", "templates/data-README.md",
                    "templates/project-Rprofile.R"):
            self.assertIn(rel, source,
                          f"build_site.py no longer ships {rel}, so a download "
                          f"would be missing part of its project")

    def test_the_lookup_name_reaches_the_bundle(self):
        """run.R checks for the lookup by name before anything opens it, so the
        name has to travel with the pipeline rather than be hard-coded."""
        source = (WEB / "build_site.py").read_text("utf-8")
        self.assertIn('"lookup": cfg.lookup_csv', source)


if __name__ == "__main__":
    unittest.main()
