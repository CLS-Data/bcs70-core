#!/usr/bin/env python3
"""Serve the variable atlas, and the assistant behind it.

    python3 web/server.py              # http://localhost:8000
    python3 web/server.py --port 8080

One process serves both the static site and `/api`, so there is nothing to
start alongside it. `web/data/` must exist first:

    python3 web/build_site.py

The server itself is standard library. The assistant behind `/api/chat` is an
optional extra (`uv sync --extra assistant`); without it every other route
still works and the drawer turns itself off.

WHAT THIS PROCESS CAN SEE: the metadata under `web/data/`, and whatever
Ollama address it is given. It never opens a deposited data file, and it has
no route that could serve one.
"""

from __future__ import annotations

import argparse
import json
import sys
import traceback
from collections.abc import Iterator
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WEB = Path(__file__).resolve().parent
sys.path.insert(0, str(WEB))

import assistant                                        # noqa: E402
from assistant import Corpus, CorpusMissing             # noqa: E402
from assistant import ollama                            # noqa: E402
from assistant import vectors                           # noqa: E402
from assistant.retrieval import (                       # noqa: E402
    Bm25, Retriever, Settings, search_grouped,
)
from config import Config, ConfigError, get as get_config  # noqa: E402

MAX_BODY = 8 * 1024 * 1024


class Handler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, app, **kwargs):
        self.app = app
        super().__init__(*args, directory=str(WEB), **kwargs)

    # -- plumbing --------------------------------------------------------

    def log_message(self, fmt, *args):
        if self.app["verbose"]:
            super().log_message(fmt, *args)

    def _json(self, payload, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {}

    def _stream(self, events: Iterator[dict]) -> None:
        """NDJSON over a chunked response, flushed per event.

        Chunked rather than a close-delimited body so HTTP/1.1 keep-alive
        survives the request; the browser reads it by splitting on newlines.
        """
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def emit(obj: dict) -> None:
            data = (json.dumps(obj) + "\n").encode("utf-8")
            self.wfile.write(b"%X\r\n" % len(data) + data + b"\r\n")
            self.wfile.flush()

        try:
            for event in events:
                emit(event)
        except (BrokenPipeError, ConnectionResetError):
            return          # the reader navigated away mid-turn
        except Exception as err:                        # noqa: BLE001
            traceback.print_exc()
            try:
                emit({"type": "error", "message": f"{type(err).__name__}: {err}"})
            except OSError:
                return
        try:
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    # -- routes ----------------------------------------------------------

    def do_GET(self) -> None:                           # noqa: N802
        route = self.path.split("?", 1)[0]
        if not route.startswith("/api/"):
            return super().do_GET()     # the static site, including data/

        cfg, corpus = self.app["cfg"], self.app["corpus"]

        if route == "/api/health":
            index = self.app["retriever"].vectors
            return self._json({
                "ok": True,
                "assistant": self.app["agent"] is not None,
                "dataset": cfg.for_browser(),
                "counts": corpus.counts,
                "waves": corpus.waves,
                # So the drawer can offer semantic search only where there is
                # an index, and say why when there is not, rather than
                # presenting a switch that silently does nothing.
                "semantic": {
                    "available": index is not None,
                    "model": getattr(index, "model", None),
                    "dims": getattr(index, "dim", None),
                    "reason": None if index is not None
                              else getattr(corpus, "vectors_unavailable", None),
                },
                "retrieval": cfg.retrieval_defaults(),
            })

        if route == "/api/interview":
            return self._json({
                "steps": [s.as_json() for s in cfg.steps],
                "categories": cfg.category_labels,
            })

        if route == "/api/models":
            return self._models(cfg.ollama)

        return self._json({"error": "no such endpoint"}, 404)

    def do_POST(self) -> None:                          # noqa: N802
        route = self.path.split("?", 1)[0]
        body = self._body()
        cfg = self.app["cfg"]

        if route == "/api/models":
            return self._models((body.get("baseUrl") or cfg.ollama).rstrip("/"))

        if route == "/api/search":
            cfg = self.app["cfg"]
            # The atlas's own search gets the same retrieval the assistant
            # does - it is the same corpus and the same question.
            return self._json(search_grouped(
                self.app["corpus"], self.app["bm25"],
                str(body.get("query") or ""),
                limit=int(body.get("limit") or 15),
                wave=body.get("wave") or None,
                retriever=self.app["retriever"],
                settings=Settings.from_json(body.get("retrieval"), cfg),
            ))

        if route == "/api/chat":
            agent = self.app["agent"]
            if agent is None:
                # Streamed rather than returned as an HTTP error, so the
                # drawer renders it in the transcript like any other failure
                # instead of showing a bare status code.
                return self._stream(iter([
                    {"type": "error", "message": assistant.MISSING, "status": None},
                    {"type": "done"},
                ]))
            request = self.app["TurnRequest"].from_json(body, cfg)
            return self._stream(agent.run(request))

        return self._json({"error": "no such endpoint"}, 404)

    def _models(self, base: str) -> None:
        try:
            return self._json({"models": ollama.list_models(base)})
        except ollama.OllamaError as err:
            return self._json({"models": [], "error": str(err)}, 200)


def build_app(cfg, verbose: bool) -> dict:
    corpus = Corpus()
    print(f"Indexing {len(corpus.vars):,} variable descriptions…", flush=True)
    bm25 = Bm25(corpus, cfg)

    # Semantic search is optional and its absence is normal: the index is
    # built locally and is not in the repository. Say which mode this process
    # is in, once, rather than letting it be inferred from the results.
    index = vectors.load(WEB / "data", corpus, cfg) if cfg.semantic else None
    if index is not None:
        print(f"Semantic index: {index.count:,} × {index.dim} "
              f"({index.model}).", flush=True)
    elif cfg.semantic:
        print(f"Lexical search only. "
              f"{getattr(corpus, 'vectors_unavailable', '')}", flush=True)
    retriever = Retriever(corpus, bm25, cfg, index)

    # The assistant is an optional extra. Without it the atlas, the metadata
    # search and the registry all still work, so this is a note rather than a
    # failure — and the drawer turns itself off and says the same thing.
    print("Loading the assistant (LangGraph imports take a moment)…", flush=True)
    agent = None
    turn_request = None
    try:
        Agent, turn_request = assistant.load()
        agent = Agent(corpus, bm25, cfg, retriever)
    except ImportError:
        print(f"\nAssistant disabled.\n{assistant.MISSING}\n",
              file=sys.stderr, flush=True)

    return {
        "cfg": cfg,
        "corpus": corpus,
        "bm25": bm25,
        "retriever": retriever,
        "agent": agent,
        "TurnRequest": turn_request,
        "verbose": verbose,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--config", help="path to a dataset .toml")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    try:
        cfg = Config.load(args.config) if args.config else get_config()
        app = build_app(cfg, args.verbose)
    except (ConfigError, CorpusMissing) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1

    server = ThreadingHTTPServer((args.host, args.port), partial(Handler, app=app))
    server.daemon_threads = True
    print(f"{cfg.name} atlas on http://{args.host}:{args.port}"
          f"  ·  Ollama at {cfg.ollama}"
          f"  ·  assistant {'ready' if app['agent'] else 'disabled'}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
