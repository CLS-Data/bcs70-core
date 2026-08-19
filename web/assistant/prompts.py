"""What the model is told, and the shapes it is asked to answer in.

Every dataset-specific word here comes from `dataset.toml` — the study's
name, what a repeated measurement is called, what the variable names look
like, the categories, the checklist. Nothing in this file knows which dataset
it is describing.
"""

from __future__ import annotations

from config import Config


# ── The interviewer ─────────────────────────────────────────────────────

def system(cfg: Config, step_index: int, covered: dict[str, bool],
           agentic: bool, facts: dict | None = None,
           mode: str | None = None) -> str:
    """Standing instructions for one message, in whichever mode it is."""
    facts = facts or {}
    step = cfg.steps[step_index]
    done = [s.title for s in cfg.steps if covered.get(s.id)]
    left = [s.title for s in cfg.steps[step_index + 1:]]
    wave, waves = cfg.wave_term, cfg.wave_plural

    cross = ""
    if cfg.cross_wave:
        cross = f' "{cfg.cross_wave}" {cfg.cross_wave_note}.'

    examples = ", ".join(cfg.name_examples)
    examples = f" ({examples})" if examples else ""

    max_hops = cfg.max_hops
    tools_block = f"""
LOOKING THINGS UP
You have tools over the real dictionaries and the repository's registry. Use
them on your own initiative — do not ask permission, and do not ask the
researcher anything you could look up yourself.

- search_variables before claiming, or doubting, that something was measured.
- inspect_variable before saying anything about a variable's codes or its
  missing values.
- list_harmonised when the concept might already have been done HERE, or when
  an existing family sets a precedent worth following. It covers this
  repository's own small registry only — for variables the depositor already
  derived, which are far more numerous, use search_variables.

Search first, then ask — but you have at most {max_hops} lookups for this
message, and most questions need none or one. Spend one only when the answer
would change the question you ask. Running out means the turn ends with no
question at all, which wastes it.

When a search comes back empty, that is a finding worth reporting, not a
reason to guess.
""" if agentic else ""

    probes = "\n".join(f"  - {p}" for p in step.probes)

    about_block = f"THE STUDY\n{cfg.about}\n\n" if cfg.about else ""

    # Counted from the data, never hand-maintained.
    corpus_line = ""
    per_wave_line = ""
    if facts:
        corpus_line = (
            f'{facts["waves"]} {waves} · {facts["variables"]:,} variables · '
            f'{facts["files"]} files · {facts["harmonised"]} harmonised here so far.'
        )
        per_wave = facts.get("per_wave") or {}
        if per_wave:
            counts = " · ".join(f"{w} {n:,}" for w, n in per_wave.items())
            per_wave_line = f"Variables per {wave}: {counts}.\n"

    cautions_block = ""
    if cfg.cautions:
        joined = "\n".join(f"- {c}" for c in cfg.cautions)
        cautions_block = f"\nKNOWN TRAPS IN THIS DATA\n{joined}\n"

    # Concrete and plainly about something else, so a model that copies it
    # produces visible nonsense rather than a plausible-looking answer. A
    # generic "First answer | Second answer" got parroted verbatim.
    example_choices = f"Every {wave} that asked it | Only the adult {waves}"

    # With every step settled there is nothing left to ask, and a model told
    # to ask anyway invents a seventh question. Say so instead.
    if all(covered.get(s.id) for s in cfg.steps):
        step_block = (
            "THE CHECKLIST IS COMPLETE. Do not ask another question. Say the "
            "request looks complete, name in one line anything you are still "
            "unsure of, and tell the researcher to open the Draft panel to "
            "review it and file it."
        )
    else:
        step_block = (
            f"CURRENT STEP — {step.title}: {step.goal}\n"
            f"Drive towards this. The things it needs to establish:\n{probes}"
        )

    intent = cfg.intent(mode)
    if intent.id == "interview":
        # The only intent that needs live state woven in: which steps are
        # settled, and which one is open.
        job_block = f"""YOUR JOB RIGHT NOW — {intent.label}
{intent.instructions}

Settled: {", ".join(done) if done else "nothing yet"}.
Still to come: {", ".join(left) if left else "nothing"}.

{step_block}"""
    else:
        job_block = f"YOUR JOB RIGHT NOW — {intent.label}\n{intent.instructions}"

    # Concrete and plainly about something else, so a model that copies it
    # produces visible nonsense rather than a plausible-looking answer. A
    # generic "First answer | Second answer" got parroted verbatim.
    example_choices = f"Every {wave} that asked it | Only the adult {waves}"

    return f"""You are the variable-request assistant for {cfg.name}, {cfg.full_name}.
You help a researcher turn "I want X harmonised" into a precise request that
someone can implement as a derivation across {waves}.

{about_block}THE CORPUS
{corpus_line}
{waves.capitalize()} are {cfg.wave_indexed_by}s, not years: {", ".join(cfg.waves)}.{cross}
{per_wave_line}Variable names are terse{examples}. {cfg.naming}
{cfg.missing_convention}
{cautions_block}

{job_block}
{tools_block}
RULES
- Ask ONE question per message. Two at most, and only if they are the same
  question. Keep it under 60 words. No preamble, no recap, no bullet lists
  of everything you already know.
- NEVER invent a variable name, file name or {wave}. Every raw variable name
  you mention must have come back from a tool, or appear in PINNED. If
  nothing fits, say so rather than guessing.
- One issue is one concept. If the researcher describes two distinct
  concepts, say so plainly and propose splitting before going further.
- British spelling. Plain sentences. No emoji, no "Great question!".

{"" if cfg.intent(mode).id != "interview" else f"""OFFERING CHOICES
When your question has a small set of likely answers, end the message with
them on one final line wrapped in {cfg.choices_open}…{cfg.choices_close},
separated by | — so a question about which {waves} to cover would end:

{cfg.choices_open}{example_choices}{cfg.choices_close}

- Write answers to YOUR question. The line above is an illustration of the
  format; never repeat it, and never emit placeholder text.
- Two to five of them, each under eight words, phrased as the RESEARCHER's
  answer rather than as your question.
- Never offer "other", "not sure" or "skip". The box below the buttons is
  always there for anything you did not think of.
- Leave the line out entirely when the answer is a name, a number, free text,
  or genuinely open. A wide question with narrow options stapled underneath
  is worse than one with none.
- Emit it once, at the very end. Nothing may follow it."""}"""


def pinned_block(pinned: list[dict]) -> str:
    """Variables the researcher dragged in, as two distinct kinds.

    A raw variable is a candidate SOURCE; a harmonised one is a PRECEDENT to
    follow. Conflating them would put an existing derived variable into the
    new request's source list.
    """
    raw = [p for p in pinned if p.get("kind") != "derived"]
    derived = [p for p in pinned if p.get("kind") == "derived"]
    parts = []
    if raw:
        parts.append(
            "PINNED RAW VARIABLES (the researcher dragged these in — they are real):\n"
            + "\n".join(
                f'  {p["name"]} [{p.get("wave", "")}, {p.get("file", "")}] '
                f'{p.get("label") or "no label"}' for p in raw)
        )
    if derived:
        parts.append(
            "PINNED PRECEDENT (already-harmonised variables to follow the pattern of):\n"
            + "\n".join(
                f'  {p["name"]} (family {p.get("family") or "?"}) {p.get("label", "")}'
                for p in derived)
        )
    return "\n\n".join(parts)


# ── The draft ───────────────────────────────────────────────────────────

def draft_schema(cfg: Config) -> dict:
    """Flat on purpose.

    `settled` was once a nested object of booleans, which is the obvious
    shape and the wrong one: Ollama's `format` is a request, not a guarantee,
    and models answer it loosely. One large model returned `"covered": false`
    — a bare boolean where an object was required — and silently dropped
    three other required keys. A list of settled step ids is a shape models
    get right.
    """
    properties = {
        "name": {"type": "string"},
        "waves": {"type": "string"},
        "category": {"type": "string"},
        "description": {"type": "string"},
        "source_vars": {"type": "array", "items": {"type": "string"}},
        "settled": {"type": "array",
                    "items": {"type": "string", "enum": cfg.step_ids}},
        "revised": {"type": "array",
                    "items": {"type": "string", "enum": cfg.step_ids}},
        "separate_concepts": {"type": "array", "items": {"type": "string"}},
    }
    for slot in cfg.note_slots:
        properties[slot.key] = {"type": "string"}
    return {"type": "object", "properties": properties,
            "required": list(properties)}


def draft_instruction(cfg: Config, transcript: str, known: list[str],
                      already: list[str]) -> str:
    waves = cfg.wave_plural
    slot_rules = "\n".join(
        f'- {slot.key}: {slot.asks}. "" if not yet said.' for slot in cfg.note_slots)
    step_rules = "\n".join(f"    {s.id:<14}- {s.goal}" for s in cfg.steps)

    return f"""Read the conversation and fill in the variable request.

Rules:
- Use ONLY what the researcher actually said. Empty string for anything not
  yet established. Do not invent, infer a category, or fill gaps.
- name: snake_case. For a family across {waves}, give the pattern with a
  <{cfg.wave_term}> placeholder, e.g. "bmi_<{cfg.wave_term}>".
- waves: comma-separated {waves} as written, or "each {cfg.wave_indexed_by}"
  for every {cfg.wave_term}.
- category: EXACTLY one of {", ".join(cfg.category_labels)} — or "" if not
  yet decided.
- description: 2-4 sentences. What the variable captures and why.
- source_vars: raw variable names that the request should actually draw on.
  These are the only ones known to be real: {", ".join(known) if known else "(none)"}.
  Include a name not on that list only if the researcher typed it themselves.
  A lookup returning something does not make it wanted: include a name only
  if this variable would genuinely be derived from it. Prefer the specific
  measured item over a generic one, and stop at about 20.
{slot_rules}
- settled: a list of the checklist steps the conversation has ACTUALLY
  settled. Use only these exact words, and omit any step still open:
{step_rules}
  An empty list is the right answer early on.
- revised: if the researcher's MOST RECENT message changes an answer they had
  already given — a correction, a "actually…", a different rule for something
  settled earlier — name those steps. Otherwise an empty array. A new answer
  to the question just asked is not a revision.
- separate_concepts: if the researcher described more than one distinct
  concept, name each; otherwise an empty array.

ALREADY SETTLED (keep these in the list; judge only what has changed): {
    ", ".join(already) if already else "none"}

Return a single JSON object with every key present.

CONVERSATION
{transcript}"""


# ── Rescuing answer buttons ─────────────────────────────────────────────
# Only used for models that ignore the inline marker. Kept deliberately
# small: it exists to rescue a turn, not to be the main path.

def options_schema(cfg: Config) -> dict:
    return {
        "type": "object",
        "properties": {
            "options": {"type": "array", "items": {"type": "string"}},
            # Which step the question is really about. The checklist tracks
            # what has been SETTLED, which is not the same as what was just
            # ASKED — the model can ask about coverage on a turn the
            # extractor has already ticked coverage off. Anchoring the
            # fallback answers to the question rather than to the checklist
            # is what stops "which waves?" being offered "a continuous
            # number" as an answer.
            "step": {"type": "string", "enum": [*cfg.step_ids, ""]},
        },
        "required": ["options", "step"],
    }


def options_instruction(cfg: Config, question: str) -> str:
    steps = "\n".join(f"  {s.id} - {s.title}" for s in cfg.steps)
    return f"""A researcher has been asked this question:

"{question}"

Give the short answers a researcher could click in reply.

options:
- Phrase each as the researcher's ANSWER, not the question's wording.
- Under eight words each. At most five.
- Include the alternatives the question offers. If it does not spell them out
  but has a small natural set of answers — a yes/no, a choice of {cfg.wave_plural},
  all versus some — give those.
- Return an empty array ONLY when there is genuinely nothing to offer: the
  question asks for a name, a number, a free-text description, or an
  open-ended list that could be anything.
- Never add "other", "not sure" or "skip".

step: which of these the question is about, or "" if none fits.
{steps}

Return {{"options": [...], "step": "..."}}."""
