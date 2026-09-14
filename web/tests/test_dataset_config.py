"""The R pipeline and the atlas must describe the same dataset.

    python3 -m unittest discover -s web/tests

`web/dataset.toml` tells the atlas where the deposits are, what the identifier
is called and what the lookup is named. `R/lib/dataset.R` tells the pipeline the
same four things. They are separate files because a downloaded bundle ships
`R/` alone -- no TOML parser, no Python -- and must still run.

Separate files that must agree is exactly the shape that drifts, and it would
drift silently: change `identifier` in the TOML and the atlas follows while the
pipeline does not, so the site would refuse a raw column the runner would then
happily mis-join. Hence this.
"""

from __future__ import annotations

import re
import tomllib
import unittest
from pathlib import Path

WEB = Path(__file__).resolve().parent.parent
REPO = WEB.parent
TOML = WEB / "dataset.toml"
RCONFIG = REPO / "R" / "lib" / "dataset.R"


def r_constants() -> dict[str, str]:
    """The `name <- "value"` assignments in R/lib/dataset.R."""
    return dict(re.findall(r'^(\w+)\s*<-\s*"([^"]*)"', RCONFIG.read_text("utf-8"), re.M))


def toml_dataset() -> dict:
    with TOML.open("rb") as fh:
        return tomllib.load(fh)


class TheTwoHalvesAgree(unittest.TestCase):

    def setUp(self):
        self.r = r_constants()
        self.toml = toml_dataset()

    def test_r_config_exists_and_is_readable(self):
        self.assertTrue(RCONFIG.exists(), f"{RCONFIG} is missing")
        for key in ("data_dir_default", "data_dir_env", "lookup_file",
                    "identifier_column", "identifier_pattern"):
            self.assertIn(key, self.r, f"R/lib/dataset.R no longer defines {key}")

    def test_the_deposits_directory_matches(self):
        self.assertEqual(self.r["data_dir_default"], self.toml["dataset"]["root"])

    def test_the_data_root_override_matches(self):
        self.assertEqual(self.r["data_dir_env"],
                         self.toml["dataset"].get("data_env", ""))

    def test_the_identifier_matches(self):
        """The atlas refuses to package this column and draws it as the output's
        first; the pipeline renames every file's key column to it. A mismatch
        makes those two statements about different columns."""
        self.assertEqual(self.r["identifier_column"],
                         self.toml["dataset"]["identifier"])

    def test_the_lookup_name_matches(self):
        self.assertEqual(self.r["lookup_file"], self.toml["metadata"]["lookup"])


class NothingElseNamesTheStudy(unittest.TestCase):
    """The framework reads the dataset's name from config; it never spells it.

    `R/variables/` and its tests are the dataset's own content and are exempt --
    a variable derived from this study is allowed to name it. Everything listed
    here is framework, and a study name appearing in it is something a port
    would have to find and edit by hand.

    Deliberately NOT listed, and why:

      templates/variable.R, variable_test.R   skeletons a human copies and
          edits for THIS dataset's variables. They have no substitution
          mechanism, and the identifier appearing in their example fixture is
          the same category as it appearing in R/variables/.
      scripts/search_metadata.R               reads dataset.R, but its usage
          text names the dictionary file suffix, which is a UKDS convention
          rather than a study name.

    Porting therefore means editing R/lib/dataset.R, web/dataset.toml, and
    those two skeletons -- and nothing else in the framework.
    """

    FRAMEWORK = [
        "R/lib/io.R",
        "R/lib/discovery.R",
        "R/lib/utils.R",
        "R/runner.R",
        "web/atlas/basket.js",
        "web/bundle.js",
        "web/build_site.py",
        "templates/passthrough.R",
        "templates/run.R",
        "templates/project-Rprofile.R",
        "templates/data-README.md",
    ]

    def test_no_framework_file_names_the_study(self):
        # Read from the config rather than spelled here, so this test ports too.
        toml = toml_dataset()["dataset"]
        names = {toml["key"], toml["name"], toml["root"]}
        names |= {toml.get("data_env", ""), toml["identifier"]}
        names.discard("")
        pattern = re.compile("|".join(re.escape(n) for n in sorted(names)), re.I)

        offenders = []
        for rel in self.FRAMEWORK:
            path = REPO / rel
            if not path.exists():
                self.fail(f"{rel} is listed as framework but does not exist")
            for i, line in enumerate(path.read_text("utf-8").splitlines(), 1):
                if pattern.search(line):
                    offenders.append(f"{rel}:{i}: {line.strip()[:90]}")

        self.assertEqual(offenders, [], "framework files naming the study:\n" +
                         "\n".join(offenders))


if __name__ == "__main__":
    unittest.main()
