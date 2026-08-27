# The assistant

A LangGraph running two agents over one runtime: a general one that answers
questions about the study, and a specialist that interviews a researcher until
a variable request is complete enough to implement. Both search the data
dictionaries on their own initiative as they go.

They are not two graphs. What differs between an agent here is its prompt and
its lifecycle — when its turn ends, whether the checklist moves, whether the
extractor runs. Everything else is shared: the streaming, the choices parser,
the hop budget, the four lookups. A second graph would have duplicated all of
it to change a system prompt.

`../chat.js` and `../chat/` only draw this. Nothing about *what it asks* lives
in the browser, and nothing dataset-specific lives in this directory — the
study, its waves, its categories, the assistant's capabilities and the whole
interview come from `../dataset.toml`.

## The graph

```mermaid
flowchart TD
    START([START]) --> RT

    RT{"route<br/>which intent does this turn run in?"}
    RT -- "a proposal is outstanding" --> HO
    RT -- "chat · interview" --> RES

    HO["handoff<br/>name the concept, offer to start,<br/>and stop there"]
    RES["respond<br/>stream a reply in that intent, strip the reasoning<br/>and the choices marker, publish the buttons"]
    LOOK["lookups<br/>run the tools it asked for,<br/>show each call and its result"]
    PRESS["press<br/>withhold the tools and make it ask"]
    DRAFT["draft<br/>read the conversation back, fill in the request,<br/>advance the checklist only if interviewing"]

    RES -- "asked for tools,<br/>hops left" --> LOOK
    RES -- "asked for tools,<br/>hops spent" --> PRESS
    RES -- "answered" --> EX
    LOOK --> RES
    PRESS --> EX
    EX{"does this intent extract?"}
    EX -- "yes" --> DRAFT
    EX -- "no" --> STOP
    HO --> STOP
    DRAFT --> STOP([END])

    subgraph tools ["the four lookups"]
        direction LR
        T1["search_variables<br/>was it measured, by meaning"]
        T2["coverage<br/>which waves have it"]
        T3["inspect_variable<br/>one variable, by name"]
        T4["list_harmonised<br/>has it been done here already"]
    end
    LOOK -.-> tools

    classDef node fill:#f5f7f3,stroke:#8e2f6b,color:#131a22
    classDef decision fill:#eef2ee,stroke:#8e2f6b,color:#131a22
    classDef terminal fill:#dfe3dc,stroke:#78838c,color:#4d5862
    classDef toolbox fill:#eef2ee,stroke:#2a5c8a,color:#2a5c8a
    class RES,LOOK,PRESS,DRAFT,HO node
    class RT,EX decision
    class START,STOP terminal
    class T1,T2,T3,T4 toolbox
    style tools fill:#eef2ee,stroke:#c5ccc3,color:#78838c
```

One message runs the graph once. The loop between `respond` and `lookups` is
the model deciding what it needs to know; `press` is the escape hatch when it
never stops deciding.

| node | |
|---|---|
| **route** | Which intent does this turn run in? Supplies the model and publishes the answer; the deciding is `router.transition`, which is standard library and pure so CI can test it. |
| **handoff** | Reached when the researcher has asked for something derived. Names the concept back to them and offers to start. The turn ends there — nothing is looked up, no step is asked, and the extractor does not run, because none of it means anything until they say yes. |
| **respond** | Streams one reply in that intent's terms. Separates the model's reasoning from its answer, pulls out the answer buttons it marked, publishes both. Binds only the lookups the intent declares. |
| **lookups** | Runs the tools it asked for, publishes each call *with its arguments* and its result, and records what was found. |
| **press** | Reached only when the hop budget is gone. Re-asks with the tools withheld, because a model mid-search returns nothing rather than change course. If it still says nothing, `_carry_on` takes over. |
| **draft** | Reads the conversation back and fills in the request. Runs after the answer, never before, and only for an intent that declares `extracts` — it is the slowest node here, and it used to run on every turn including the ones that could not move the checklist. Advances the checklist only when the intent says to. |

## Intents

What the assistant can be asked for, and how a turn gets into it and out
again. Each is an `[[intent]]` in `dataset.toml`.

| | **chat** | **interview** |
|---|---|---|
| the message is | a question, or anything else | an answer, a request, a correction |
| it does | answers, and stops | drives the next unsettled step |
| entered by | the default; every conversation opens here | a proposal the researcher accepts |
| left by | a proposal accepted | an explicit stop, or the checklist completing |
| checklist | never advances | the answered step is credited |
| the draft | does not run | fills in |

**A question mid-interview does not leave the interview.** It used to: an
`explore` intent sat beside `interview` and the router picked between them
afresh on every message, so asking "which sweeps have this?" halfway through
routed you out of the very thing you asked to start. The interviewer now looks
it up, answers in a line, and puts its own question back in the same message.
`explore` is gone; its instructions are `chat`'s.

**Getting in takes a yes.** `entry = "handoff"` withholds an intent from the
router entirely. A wrong route costs a turn; being put into an interview
unasked costs more, and the confirmation is what pays the difference. The
proposal is also where the draft gets seeded — the extractor reads the whole
conversation, so everything said before agreeing is already in it, and the
interview opens on the first thing genuinely still open rather than re-asking
the concept.

**Adding a capability is a config change.** Everything an intent changes about
a turn is declared, never inferred from its name:

| | |
|---|---|
| `advances` | answering it credits a checklist step |
| `shows_checklist` | the prompt carries what is settled and what is open |
| `offers_choices` | the reply may end with answer buttons |
| `extracts` | the draft extractor runs after the reply |
| `entry` | `router` — chosen per message; `handoff` — only ever entered by an accepted proposal |
| `confirm` | how that proposal is phrased |
| `replies` | the answers offered with it |
| `sticky` | once here, stay until an explicit stop |
| `exits_to` | where leaving lands |
| `tools` | which lookups it may call |

The three after `advances` default to whatever it says. They exist because
they were once decided by comparing the id against `"interview"` in
`prompts.py` and `"explore"` in the browser, so a third intent got whatever
those comparisons happened to give it. `validate()` now refuses every shape
of intent nothing could reach — a sticky or handoff-entered fallback, a
handoff with nothing to propose with or no way to answer it, `exits_to`
naming nothing, sticky exiting into sticky.

## The router

`transition()` decides which intent a turn runs in, given the one the last
turn ran in. It is standard library and pure — the graph supplies `ask_model`
and stores the result — so every rule in it is tested in a checkout that
installed nothing.

The order is not arbitrary. A pending proposal is answered before anything
else, or a "yes" gets classified as a fresh message. Leaving a sticky intent
is decided before staying in it. Only a turn doing neither is free to route.

| in | the question | costs |
|---|---|---|
| a first message | none — it is the fallback, whatever it says | nothing |
| `chat` | is this a request to derive something? | one binary call |
| a proposal outstanding | did they say yes? | one binary call |
| `interview` | do they want out? | **nothing at all** |

That last row is the saving, and it is the common case: a sticky turn asks
the model nothing. Behind each question is a rule, chosen by
`[assistant] router` — **`model`**, **`heuristic`**, or **`auto`** (the
default: the model, with the rule as fallback, because a routing failure
should degrade a turn rather than end it).

**The exit rule is narrower than it looks, and every narrowing is a message
that ended an interview by accident.** "stop" runs through this corpus
mid-sentence — stopping smoking, stopping work, stopping school. So: a
question is never an exit however it is worded; only an unambiguous
multi-word phrase may open a longer message ("never mind, let's do something
else" yes, "go back to the 16y sweep" no); and anything else has to be four
words or fewer. Six was the first threshold, and *"did they stop smoking by
29y?"* is exactly six.

A two-word "stop smoking" still reads as an exit. That is the residue of a
rule with no model behind it — the visible stop control is the reliable way
out, this is the courtesy — and leaving is recoverable, since the draft is
kept and the interview is one sentence away.

## The tools

| | |
|---|---|
| `search_variables` | **By meaning.** Whether a concept was measured, what it was called, at which waves. Optionally scoped to one wave. |
| `coverage` | **By wave.** One concept reported across every wave, including the ones with nothing. See below — `search_variables` cannot answer this. |
| `inspect_variable` | **By name.** One variable's full entry — declared missing values and every value label. What the sentinels *actually* mean. On a miss it offers similar names but never picks one. |
| `list_harmonised` | Whether **this repository** has already done it. A small registry — not the study's own `(Derived)` variables, which `search_variables` finds. Conflating the two once answered "which sweeps have a derived self-rated health variable?" with "no precedent". |

Every call appears in the transcript with its arguments, and every variable
name it surfaces links through to that variable in the atlas.

**The split between the first two is the whole design.** One tool guessing at
both intents is what produced the worst ranking bug this has had: a bonus for
query words that happen to be variable names, which put `day` ("DAY NUMBER")
above every cigarette variable for *"cigarettes per day"*. The bonus was also
unnecessary — a name is indexed whole, so it is a term in exactly one document
and BM25 ranks it first unaided. It is gone; the model declares which kind of
lookup it wants by choosing a tool.

**`coverage` exists because ranking and coverage are different questions.**
`search_variables` scores every wave against every other and returns the best
ten groups overall, so a wave whose variable ranks lower is missing from the
answer rather than absent from the study — for *"general health"* the 29y and
38y variables sit at rank 72 and 76 of a 150-document pool. `coverage` scores
the same single pass and buckets by wave instead of truncating, reporting all
fourteen including the empty ones. 0.4 ms, no extra model call.

It answers in **three** states, not two. A wave is *measured* when a label
accounts for enough of the query's idf mass, *possible* when it accounts for
some, and *nothing* otherwise. The middle state is the point rather than a
hedge: `hlthgen` ("How is your health generally") does not match the term
`general` at all — "generally" does not stem to it — so a strict floor would
drop the very wave the tool was built to surface. Its own result text says so
in as many words, because a model told only "unconfirmed at 29y" folds that in
with the waves that have nothing and reports a real variable as absent. That
happened, and the wording is the fix.

## Words, meaning, and other wordings

BM25 matches words. The dictionaries are transcribed questionnaires, so they
say *"How is your health generally"* where a researcher says *"self-rated
health"* — the two vocabularies share no content word, and no lexical tuning
joins them. Two things now sit over BM25, both optional, both configurable in
`dataset.toml` and adjustable per conversation in the drawer.

**Semantic search** (`vectors.py`) embeds every label once, offline, and scans
the lot per query. **Query expansion** (`expansion.py`) asks the helper model
to rephrase the search the way a questionnaire would and retrieves each
wording. Results are combined by **reciprocal rank fusion** — a document
scores `1/(k + rank)` in each list it appears in, summed. Scores are never
added directly: a BM25 score and a cosine are not on one scale, and
normalising them invents a relationship that changes with every query. RRF
reads only position, so a variable two methods agree on beats one that a
single method liked loudly.

Measured on this corpus, finding the eight variables that record self-rated
health:

| | found | cost |
|---|---|---|
| lexical only | **2 of 8** | ~1 ms |
| + semantic | **6 of 8** | ~325 ms |
| + expansion | **7 of 8** | ~2 s |

**The index is optional and is not in the repository.** It is built locally by
`python3 web/build_embeddings.py` against a local embedding model, takes about
four minutes, and lands in the gitignored `web/data/`. CI has neither Ollama
nor the file, so everything degrades to lexical search and says so — in the
server's first line, in `/api/health`, and as a disabled switch in the drawer
carrying the reason.

**No numpy, and none wanted.** The vectors live in an `array('f')` and a dot
product over a slice of one is C-backed: a full scan of 32,454 variables costs
about 150 ms at 256 dimensions. Truncating `nomic-embed-text` from 768 to 256
still agrees with the full vector on 95% of the top ten while being 2.8×
faster and a third the size, so 256 is the default — and only safe because
that model is trained for it.

**Vectors are positional, so a stale index is refused rather than used.** Row
8,000 of the file is row 8,000 of `variables.json`; rebuild the site with one
variable inserted and every vector after it describes something else, with
plausible scores and real names and nothing that looks wrong. The index
therefore carries a fingerprint of the names it was built from, and a mismatch
disables semantic search with the rebuild command. Refusing to search is
recoverable; silently searching the wrong corpus is not.

**What none of this fixes is `coverage`'s confirmation bar.** A semantically
found variable has, by definition, a poor lexical share, so it skips the floor
that keeps coincidences out — but it never counts as *measured*, because the
thresholds are calibrated on idf mass and mean nothing against a cosine. It
surfaces as a candidate for the reader to judge, which is what the middle tier
is for.

`inspect_variable` **never resolves a name it was not given.** Where a lookup
misses, it suggests names differing only in their digits — the same question at
another wave, `b8hlthgn` → `b9hlthgn` — and leaves the choice to the model.
Edit distance would be the obvious thing here and is the wrong thing: 93% of
this study's 31,947 names have another *real* variable one edit away, and one
edit from `b960434` includes height in feet, in metres and in centimetres. A
fuzzy match would return a plausible, wrong, unfalsifiable answer.

## The state

```
messages     the conversation, as LangChain messages
pinned       variables dragged in — raw ones are SOURCES, derived ones PRECEDENT
covered      {step_id: True} — ratchets forward; only a revision moves it back
draft        the request being assembled
options      the answer buttons for the reply just given
asked_step   which step the question was about
separate     concepts that should be split into their own issues
hops         tool round-trips used this turn
mode         which intent this turn is running in
awaiting     an intent offered, waiting on a yes
entering     this turn entered `mode` by acceptance
seen         every variable the lookups surfaced, as records
```

`mode` and `awaiting` come IN as well as out. The server keeps nothing
between turns, so a sticky intent that the browser did not hand back would be
forgotten the moment the response ended — and whether "yes" means anything
depends on what was asked. `entering` is turn-local: it is derived fresh from
`awaiting` and the message, never posted back.

`seen` is a reduced field: each lookup adds to one working set rather than
replacing it. It exists because the alternative was re-parsing the *rendered
text* of every tool result on every turn — splitting on pipes, stripping
punctuation, hoping — which kept only the name and broke whenever the wording
changed.

No checkpointer is configured and none is wanted: the browser holds the
conversation and posts it back each turn, so a server restart is invisible and
nothing accumulates per user. The graph's state exists for exactly one turn.

## The event stream

Nodes publish through `get_stream_writer()` in the shape `../chat.js` already
reads, so `stream_mode="custom"` is the only mode used.

| event | |
|---|---|
| `mode` | which intent; the transcript marks an exploration |
| `thinking` | the model's working — buffered and sent **once**, shown collapsed |
| `content` | prose, streamed |
| `tool_call` / `tool_result` | what it looked up, with arguments, and what came back |
| `options` | the answer buttons, and the step the question was about |
| `draft` | the assembled request, plus checklist progress |
| `error` / `done` | |

## The files

```
standard library — these work with nothing installed
  router.py      the state machine: which intent this turn runs in, how one
                 is entered and left. Model, with a rule behind it
  prompts.py     the system prompt, schemas, extraction instructions
  choices.py     TagSpan: pulls tagged spans out of a live stream
  retrieval.py   BM25, coverage, rank fusion, and the per-turn settings
  vectors.py     the semantic index: load it, scan it, refuse a stale one
  expansion.py   other wordings of the same search, from the helper model
  corpus.py      the metadata build_site.py emits, and its shape
  transcript.py  the conversation the browser posts back, planned into
                 messages: ids minted, results paired, orphans dropped
  tools.py       the four lookups: schemas, and executors
  ollama.py      listing models, embedding, and one-shot completions

needs `uv sync --extra assistant`
  graph.py       the diagram above
  llm.py         ChatOllama for the interviewer and the helper
  agent.py       drives one turn, translates it for the browser
```

The split is deliberate: the atlas, the metadata search and the model picker
depend on the top half and must keep working in a checkout that installed
nothing. Importing this package does not pull in LangGraph; `assistant.load()`
does, and names the fix when it cannot.

It also decides what can be tested. CI installs nothing, so a test that
imports `graph.py` or `agent.py` cannot run there — which is why the rules
worth guarding have been moved out of them: the hop budget to
`Config.hops_spent`, the message pairing to `transcript.plan`, and the whole
mode machine to `router.transition`. All three were wrong once, in ways
nothing downstream could show you. What is left in the
bottom half is a graph, two model builders and a mapping.

## Eight things that are not what you would write first

Each was a bug before it was a decision.

**Tokens are written by hand, not streamed by LangGraph.** `messages` stream
mode emits raw model tokens, and those include the marker the model uses to
declare its answer buttons — which must never reach the transcript and arrives
split across chunks.

**Tools are executed in the node, not by `ToolNode`.** Each lookup produces two
things: a terse string for the model and a richer structure for the transcript
card. A tool's return value has room for one.

**The choices come from the model, inline.** It ends the message with
`<choices>…</choices>`, parsed off the stream — about 200 ms to buttons, against
3.5–8.6 s when a second model reverse-engineered them from the prose. The span
**closes at the closing tag** and normal output resumes; swallowing to the end
of the stream once discarded twenty-one seconds of a reply. Text either side of
the removed span gets its paragraph break back, or a question mark runs into
the next capital.

**Reasoning is stripped from the answer as well as read from the API field.**
Some models emit `<think>` inline, and one — told *not* to reason — reasons
anyway, stops using the field, and dumps it into the reply trailing a stray
`</think>`. `llm.py` may therefore keep sending `reasoning=False`, which is a
real saving where honoured. The two changes only work together.

**The hop budget is announced, not just enforced.** Stated in the prompt and
counted down in the tool results from two remaining. Warning only on the last
hop comes too late — the turn is already spent.

**A silent model does not end the turn.** `_carry_on` asks the next open step's
own probe, with that step's answers as buttons; with every step settled it says
the request is complete and points at the Draft panel. It used to leave a shrug
in the transcript, which hands back a conversation the researcher came here to
be led through.

**Stickiness is cheaper than routing, not just steadier.** The obvious reading
of "stay in the interview until they leave" is that it costs an extra check
each turn. It removes one: the intent is already known, so the only question
is whether to leave, and the rule answers that without a model. The round trip
that used to open every single message now happens only in `chat`.

**A correction may reopen a step.** The checklist ratchets forward so a model
forgetting turn two on turn six cannot un-tick it. A researcher changing their
mind is the opposite case: the extractor reports `revised`, and those steps go
back to unsettled. The `options` event names the step its question was about,
because crediting whichever step happened to be *next* meant answering one
question ticked another off.

## When something goes wrong

The transcript gets a sentence; the browser console gets the stack. A
client-side fault is otherwise indistinguishable from a model or network
failure — one showed up as *"Something went wrong. Cannot read properties of
undefined (reading 'map')"*, which had nothing to do with the model:
`/api/interview` had answered without its `steps`. That payload is now checked
once at boot, so the same cause disables the drawer with the actual fix in its
tooltip. The usual reason is an older `server.py` still holding the port.

## Changing things

| to change | edit |
|---|---|
| how the dictionaries are searched | `../dataset.toml` → `[retrieval]`, or the drawer's settings for one conversation |
| the embedding model, or its dimensions | `../dataset.toml` → `[retrieval] embed_model`, `embed_dims`, then rebuild the index |
| what it knows about the study | `../dataset.toml` → `[dataset] about`, `cautions` |
| what it asks, or the answers it offers | `../dataset.toml` → `[[interview.step]]` |
| what it can be asked to do, and how a turn enters or leaves it | `../dataset.toml` → `[[intent]]` |
| how it is told to behave | `prompts.py` |
| what it can look up | `tools.py`, and the diagram above |
| the shape of the conversation | `graph.py` |
| how any of it looks | `../chat/` |
