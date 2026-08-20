"""Asking the same question in the words the dictionaries actually use.

The data dictionaries are transcribed questionnaires. They say "How is your
health generally" and "CM Self-Assessment Of Health"; a researcher asks for
"self-rated health". Those share no content word, so no lexical tuning
connects them - the two vocabularies simply do not meet.

Measured on this corpus, one phrasing reaches part of a concept and another
reaches the rest:

    "general health"      -> the 21y, 26y, 42y, 46y, 51y variables
    "self rated health"   -> the 34y and 38y ones
    "health status"       -> neither

So the model is asked for a few alternative phrasings and every one is
retrieved. It costs one extra model call per lookup, which is why it can be
turned off.

Standard library, over `ollama.complete`, deliberately. Retrieval is used by
the atlas's own `/api/search` as well as by the assistant, and a checkout that
installed nothing should not quietly get a worse search than one that did.
"""

from __future__ import annotations

import re

from . import ollama

# Enough to be useful, few enough that a model cannot turn one lookup into a
# dozen searches by being enthusiastic.
CEILING = 6


def instruction(cfg, query: str, count: int) -> str:
    return f"""Rewrite this search so it matches how a questionnaire would word it.

The search: "{query}"

You are searching {cfg.name}'s data dictionaries. Their text was transcribed
from the questionnaires themselves, so it uses the words asked of a
respondent, not the words a researcher uses to describe a concept. "Self-rated
health" is stored as "How is your health generally" and "Self-Assessment Of
Health"; "socioeconomic status" is stored as job titles and housing tenure.

Give {count} alternative wordings, each on its own line, no numbering and no
explanation, and do not repeat the original.

Make the FIRST one the shortest phrase that still identifies the concept —
two or three words, the plainest possible, with every qualifier dropped:
"self-rated general health" becomes "general health", "cigarettes smoked per
day" becomes "cigarettes a day". Short matters, because a wording is scored
on how much of it a label accounts for and every extra word makes a match
harder to confirm.

Make the rest genuinely different vocabulary — the words the question itself
would have used. A rephrasing that reuses the same content words finds the
same variables and is wasted. Keep each under about eight words.
"""


def _clean(line: str) -> str:
    """One candidate phrasing, or empty if the model editorialised."""
    line = line.strip()
    line = re.sub(r"^[\s\-\*•]+", "", line)      # bullets
    line = re.sub(r"^\d+[.):]\s*", "", line)          # numbering
    line = line.strip(" \"'`")
    # A sentence is an explanation, not a search.
    if len(line.split()) > 8 or line.endswith((":", ".")) and len(line.split()) > 6:
        return ""
    return line


def phrasings(cfg, query: str, *, count: int, model: str,
              base: str | None = None) -> list[str]:
    """The original first, then whatever alternatives came back.

    Never raises. Expansion is an enhancement, and a model that is slow,
    missing or talkative should cost the lookup nothing more than the
    alternatives it failed to supply.
    """
    original = (query or "").strip()
    if not original or count < 1 or not model:
        return [original] if original else []

    count = min(count, CEILING)
    try:
        reply = ollama.complete(
            instruction(cfg, original, count), model, base,
            timeout=cfg.expand_timeout,
        )
    except ollama.OllamaError:
        return [original]

    seen = {original.lower()}
    out = [original]
    for line in reply.splitlines():
        candidate = _clean(line)
        if not candidate or candidate.lower() in seen:
            continue
        seen.add(candidate.lower())
        out.append(candidate)
        if len(out) > count:
            break
    return out
