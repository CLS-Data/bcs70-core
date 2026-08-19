"""Separating a model's reply from the things it wraps in tags.

Two jobs, one mechanism. Models put text in the stream that is not the
answer: the choices they are offering, and — for reasoning models — their
working. Both arrive inline, both can be split across chunks, and neither
belongs in the transcript as prose.

The interviewer marks the choices it is offering on the last line of its
message. This is the whole reason the buttons are instant: the model has just
written the question, so it already knows what it is offering, and asking a
second model to reverse-engineer that from the prose was both slower — three
and a half to eight seconds, against about a fifth of one — and worse.

No LangGraph here on purpose: this runs whether or not the assistant extra is
installed, and it is the piece most worth testing on its own.
"""

from __future__ import annotations

from config import Config

MAX_OPTIONS = 5
MAX_OPTION_CHARS = 60


def _hold_partial(buffer: str, tag: str) -> tuple[str, str]:
    """Split off any tail that could still be the start of `tag`.

    A stream can break a tag anywhere, so text is held back as soon as it
    could be the beginning of one and released once it turns out not to be.
    """
    for n in range(min(len(tag) - 1, len(buffer)), 0, -1):
        if buffer.endswith(tag[:n]):
            return buffer[:-n], buffer[-n:]
    return buffer, ""


class TagSpan:
    """Pulls the text between two tags out of a live stream.

    Text outside the span is returned for display; text inside is captured.
    Crucially the stream RESUMES after the closing tag rather than being
    swallowed to the end — a model that emits an opening tag by mistake
    should cost one stray line, not the rest of its reply. Getting this wrong
    once discarded twenty-one seconds of a model's output.

    A closing tag with no opening one is treated as "everything so far was
    inside": some models, asked not to reason, reason anyway and emit only
    the closing half.
    """

    def __init__(self, open_tag: str, close_tag: str, *,
                 orphan_close: bool = False, separate: bool = False):
        self.open = open_tag
        self.close = close_tag
        self.orphan_close = orphan_close
        # Whether text either side of a removed span is two thoughts or one.
        # Choices sit BETWEEN sentences, so joining them raw runs a question
        # mark into the next capital. Reasoning is usually removed from the
        # middle of one, where a break would split it.
        self.separate = separate
        self.buffer = ""
        self.captured: list[str] = []
        self.inside = False
        self._just_closed = False   # a span ended; the next text needs a gap
        self._tail = ""             # last character emitted, to judge that gap

    def feed(self, chunk: str) -> str:
        self.buffer += chunk
        shown: list[str] = []

        while True:
            if self.inside:
                end = self.buffer.find(self.close)
                if end < 0:
                    # Hold back a tail that could still become the closing
                    # tag, or a tag split across chunks is captured as
                    # content and the span never ends.
                    safe, self.buffer = _hold_partial(self.buffer, self.close)
                    self.captured.append(safe)
                    break
                self.captured.append(self.buffer[:end])
                self.buffer = self.buffer[end + len(self.close):]
                self.inside = False
                self._just_closed = True
                continue

            start = self.buffer.find(self.open)
            orphan = self.buffer.find(self.close) if self.orphan_close else -1
            if orphan >= 0 and (start < 0 or orphan < start):
                # Closing half with nothing opened: the text before it was
                # never meant for the reader.
                self.captured.append(self.buffer[:orphan])
                self.buffer = self.buffer[orphan + len(self.close):]
                self._just_closed = True
                continue
            if start < 0:
                safe, self.buffer = _hold_partial(self.buffer, self.open)
                if self.orphan_close:
                    safe, held = _hold_partial(safe, self.close)
                    self.buffer = held + self.buffer
                shown.append(safe)
                break

            shown.append(self.buffer[:start])
            self.buffer = self.buffer[start + len(self.open):]
            self.inside = True

        return self._emit("".join(shown))

    def _emit(self, text: str) -> str:
        """Restore the gap where a removed span separated two thoughts."""
        if not text:
            return text
        if (self.separate and self._just_closed and self._tail
                and not self._tail.isspace() and not text[:1].isspace()):
            text = "\n\n" + text
        self._just_closed = False
        self._tail = text[-1:]
        return text

    def finish(self) -> tuple[str, str]:
        """Return (remaining display text, everything captured)."""
        tail = "" if self.inside else self._emit(self.buffer)
        if self.inside:
            self.captured.append(self.buffer)
        self.buffer = ""
        return tail, "".join(self.captured)


class ChoiceParser:
    """The model's own answer buttons, pulled out of its reply."""

    def __init__(self, cfg: Config):
        self.close = cfg.choices_close
        self.span = TagSpan(cfg.choices_open, cfg.choices_close, separate=True)

    def feed(self, chunk: str) -> str:
        """Return the text that is safe to display now."""
        return self.span.feed(chunk)

    def finish(self) -> tuple[str, list[str]]:
        """Return (any remaining display text, the parsed choices)."""
        tail, raw = self.span.finish()
        if self.close in raw:
            raw = raw.split(self.close, 1)[0]
        else:
            # The stream can end on a partial closing tag — "</choices" with
            # no ">" — and without this the fragment rides along on the last
            # option. Trim the longest prefix of the tag that ends the text.
            for n in range(len(self.close) - 1, 0, -1):
                if raw.endswith(self.close[:n]):
                    raw = raw[:-n]
                    break
        options = [o.strip(" \t-•").strip() for o in raw.replace("\n", "|").split("|")]
        options = [o for o in options if o and len(o) < MAX_OPTION_CHARS]
        return tail, options[:MAX_OPTIONS]
