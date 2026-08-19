"""The metadata the assistant searches.

Reads what `build_site.py` already emits into `web/data/`, rather than
re-reading the deposits: one build, one source of truth, and the assistant
can never see anything the published site could not. Dictionaries are loaded
lazily and cached, because all of them together are most of 20 MB and a
conversation touches a handful.

No raw data file is opened here.
"""

from __future__ import annotations

import json
from functools import cached_property
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "data"


class CorpusMissing(RuntimeError):
    pass


class Corpus:
    """Variables, files and derived specs, as the site's JSON has them."""

    def __init__(self, data_dir: Path = DATA):
        self.dir = data_dir
        manifest = data_dir / "manifest.json"
        if not manifest.exists():
            raise CorpusMissing(
                f"{manifest} not found. Run `python3 web/build_site.py` first."
            )
        self.manifest: dict = json.loads(manifest.read_text("utf-8"))
        # [name, label, fileIndex, waveIndex, levelIndex] per variable
        self.vars: list[list] = json.loads((data_dir / "variables.json").read_text("utf-8"))

        derived = data_dir / "derived.json"
        self.derived: list[dict] = (
            json.loads(derived.read_text("utf-8")) if derived.exists() else []
        )

        self.waves: list[str] = self.manifest.get("waves", [])
        self.files: list[dict] = self.manifest.get("files", [])
        self._dicts: dict[str, dict] = {}

        self._by_name: dict[str, list[int]] = {}
        for i, row in enumerate(self.vars):
            self._by_name.setdefault(str(row[0]).lower(), []).append(i)

    # -- lookups ---------------------------------------------------------

    def wave_of(self, doc: int) -> str:
        idx = self.vars[doc][3]
        return self.waves[idx] if 0 <= idx < len(self.waves) else "?"

    def file_of(self, doc: int) -> dict:
        idx = self.vars[doc][2]
        return self.files[idx] if 0 <= idx < len(self.files) else {}

    def rows_named(self, name: str) -> list[int]:
        return self._by_name.get(str(name).lower(), [])

    def known_name(self, name: str) -> bool:
        return str(name).lower() in self._by_name

    def dictionary(self, slug: str) -> dict:
        if slug not in self._dicts:
            path = self.dir / "dict" / f"{slug}.json"
            self._dicts[slug] = (
                json.loads(path.read_text("utf-8")) if path.exists()
                else {"variables": []}
            )
        return self._dicts[slug]

    def entry(self, doc: int) -> dict | None:
        """The full dictionary record for one variable, or None."""
        slug = self.file_of(doc).get("slug")
        if not slug:
            return None
        name = self.vars[doc][0]
        for variable in self.dictionary(slug).get("variables", []):
            if variable.get("variable") == name:
                return variable
        return None

    @property
    def counts(self) -> dict:
        return self.manifest.get("counts", {})

    @cached_property
    def facts(self) -> dict:
        """The shape of the corpus, for telling a model what it is looking at.

        Counted rather than configured: a hand-written "14 sweeps" is wrong
        the first time a deposit is added, and wrong silently.
        """
        per_wave: dict[str, int] = {w: 0 for w in self.waves}
        for row in self.vars:
            idx = row[3]
            if 0 <= idx < len(self.waves):
                per_wave[self.waves[idx]] += 1
        return {
            "waves": len(self.waves),
            "variables": len(self.vars),
            "files": len(self.files),
            "harmonised": len(self.derived),
            "per_wave": per_wave,
        }
