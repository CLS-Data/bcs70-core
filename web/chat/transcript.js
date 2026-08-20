/* The message list: what was said, what was looked up, and what is happening
   right now. */

import { $ } from "./dom.js";
import { esc, md } from "./markup.js";
import { A, chat, modelUsesTools, wavePlural, waveTerm } from "./state.js";

export function groupRows(groups) {
  return groups.map((g) => {
    const payload = JSON.stringify({
      kind: "variable", name: g.names[0], label: g.label || "",
      file: (g.files || [])[0] || "", wave: (g.waves || [])[0] || "",
    });
    const waveOf = g.wave_of || {};
    const names = g.names.slice(0, 5).map((n) =>
      `<button class="varlink" data-open='${esc(JSON.stringify({ name: n, wave: waveOf[n] || null }))}'
         title="Open ${esc(n)} in the atlas">${esc(n)}</button>`).join(", ");
    return `<li class="hit" draggable="true" data-hit='${esc(payload)}'>
      <span class="hit-names">${names}${
        g.names.length > 5 ? ` <span class="hit-more">+${g.names.length - 5}</span>` : ""}</span>
      <span class="hit-label">${esc(g.label || "no label recorded")}</span>
      <span class="hit-meta">${(g.waves || []).map(esc).join(" · ")}</span>
      <button class="hit-pin" data-pin='${esc(payload)}' title="Pin to the conversation">pin</button>
    </li>`;
  }).join("");
}

/* What the model went and looked at, shown as it happens. The arguments
   are on display, not just the fact of a search: "it searched" tells you
   nothing, "it searched for cigarettes at 16y and found none" is the thing
   you might disagree with.

   A function rather than a lookup table because coverage's verb names the
   wave term, which belongs to the dataset and not to this file. */
export function toolVerb(name) {
  return {
    search_variables: "searched the dictionaries",
    inspect_variable: "read the coding for",
    coverage: `checked which ${wavePlural()} have`,
    list_harmonised: "checked this repository's harmonised variables",
  }[name] || name;
}

/* One row per wave, in the study's own order, saying which of the three
   answers this wave got. Coverage reports all of them including the empty
   ones — that is the whole reason the tool exists — so the card has to draw
   the empty ones too, or it becomes a search with worse formatting. */
function coverageRows(waves) {
  return waves.map((w) => {
    const names = (w.matches || []).map((m) => `<button class="varlink"
        data-open='${esc(JSON.stringify({ name: m.name, wave: w.wave }))}'
        title="Open ${esc(m.name)} in the atlas">${esc(m.name)}</button>`).join(", ");
    const state = w.measured ? "is-measured"
      : (w.matches || []).length ? "is-possible" : "is-nothing";
    const verdict = w.measured ? "measured"
      : (w.matches || []).length ? "possible" : "nothing";
    return `<li class="cov ${state}">
      <span class="cov-wave">${esc(w.wave)}</span>
      <span class="cov-verdict">${verdict}</span>
      <span class="cov-names">${names || "—"}</span>
      <span class="cov-label">${esc((w.matches || [])[0]?.label || "")}</span>
    </li>`;
  }).join("");
}

export function toolCard(m) {
  const d = m.display || {};
  const arg = m.name === "inspect_variable"
    ? m.args?.name
    : [m.args?.query, m.args?.concept, m.args?.[waveTerm()]].filter(Boolean).join(" · ");

  let body;
  if (!m.display) {
    body = `<p class="msg-note"><span class="dots">…</span></p>`;
  } else if (d.groups?.length) {
    body = `<ol class="hits">${groupRows(d.groups)}</ol>`;
  } else if (d.variable) {
    const v = d.variable;
    const vals = v.values || [];
    body = `<p class="hit-names"><button class="varlink"
        data-open='${esc(JSON.stringify({ name: v.name, wave: v.wave || null }))}'
        title="Open ${esc(v.name)} in the atlas">${esc(v.name)}</button>
      <span class="hit-meta">${esc(v.wave || "")}${v.file ? " · " + esc(v.file) : ""}</span></p>
      <table class="codes"><tbody>
      <tr><td class="val">label</td><td>${esc(v.label || "none")}</td></tr>
      <tr><td class="val">missing</td><td>${esc(v.missing || "none declared")}</td></tr>
      ${vals.slice(0, 12).map((x) => {
        const n = parseFloat(x.value);
        const miss = !Number.isNaN(n) && n < 0;
        return `<tr class="${miss ? "is-missing" : ""}">
          <td class="val">${esc(x.value)}</td><td>${esc(x.label)}</td></tr>`;
      }).join("")}
      ${vals.length > 12 ? `<tr><td class="val">…</td><td>${vals.length - 12} more</td></tr>` : ""}
    </tbody></table>`;
  } else if (d.coverage?.length) {
    body = `<ol class="coverage">${coverageRows(d.coverage)}</ol>`;
  } else if (d.derived?.length) {
    body = `<ol class="hits">${d.derived.map((x) => `
      <li class="hit"><span class="hit-names"><button class="varlink"
          data-derived="${esc(x.id)}" title="Open ${esc(x.id)} in the atlas"
          >${esc(x.id)}</button></span>
        <span class="hit-label">${esc(x.label || "")}</span>
        <span class="hit-meta">${esc(x.category)} / ${esc(x.family)} · ${esc(x.status)}</span>
      </li>`).join("")}</ol>`;
  } else {
    body = `<p class="msg-note">${esc(d.note || "nothing returned")}</p>`;
  }

  return `<div class="msg msg-tool${m.display ? "" : " is-running"}">
    <div class="msg-head">
      <span class="tool-mark">⌕</span>
      ${esc(toolVerb(m.name))}${arg ? ` <code>${esc(arg)}</code>` : ""}
      ${m.display?.note ? `<span class="msg-note">${esc(m.display.note)}</span>` : ""}
    </div>
    ${body}
  </div>`;
}

/* Ollama's failures are not interchangeable and the useful next step
   differs completely between them. A retired hosted model in particular
   still appears in /api/tags and only fails when you talk to it, which

   looks like a bug in this page unless it is named. */
export function errorTitle(msg, status) {
  if (status === 410 || /\b410\b|retired/i.test(msg)) return "That model is no longer available.";
  if (status === 404 || /\b404\b/.test(msg)) return "Ollama doesn't have that model.";
  if (/Could not reach Ollama/i.test(msg)) return "Couldn't reach Ollama.";
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) return "Couldn't reach the atlas server.";
  if (/Cannot read propert|is not a function|undefined is not|null is not/i.test(msg)) {
    return "A fault in this page, not the model.";
  }
  return "Something went wrong.";
}

export function errorHint(msg, status) {
  if (status === 410 || /\b410\b|retired/i.test(msg)) {
    return "Ollama still lists retired hosted models. Pick another in <strong>Setup</strong>.";
  }
  if (status === 404 || /\b404\b/.test(msg)) {
    return `Pull it first: <code>ollama pull ${esc(chat.settings.model)}</code>.`;
  }
  if (/Could not reach Ollama/i.test(msg)) {
    return "Check <code>ollama serve</code> is running, and that the address in " +
      "<strong>Setup</strong> is right.";
  }
  if (/Failed to fetch|NetworkError|Load failed/i.test(msg)) {
    return "The page is served by <code>web/server.py</code>; check it is still running.";
  }
  if (/Cannot read propert|is not a function|undefined is not|null is not/i.test(msg)) {
    return "Changing model will not help. Open <em>where it came from</em> below " +
           "and send that — it names the line.";
  }
  return "Check <strong>Setup</strong>, or try another model.";
}

export function renderTranscript() {
  const box = $("#chat-log");
  if (!box) return;

  if (!chat.messages.length) {
    box.innerHTML = `
      <div class="chat-intro">
        <h3>Describe what you want harmonised</h3>
        <p>Say it however you'd say it to a colleague — “income at each ${esc(waveTerm())}”, “whether they were ever unemployed before 30”. I'll ask
           about the ${chat.interview.steps.length} things a derivation needs
           settled and compose the issue.</p>
        <p>${modelUsesTools()
          ? "I search the dictionaries myself when I need to, rather than on " +
            "every message. You'll see each lookup and what it returned, so " +
            "you can tell what the answer was actually built on."
          : "This model can't call tools, so it can't search for itself. Pick a " +
            "tools-capable model in <strong>Setup</strong>."}</p>
        <p class="chat-intro-hint">Drag any variable from the search results,
           the derived list or the scratchpad into this panel to pin it as
           context.</p>
        <p class="chat-intro-hint">Or start from one of these:</p>
        <div class="chat-seeds">
          ${(A().state.dataset.examples || []).map((s) =>
            `<button class="seed" data-seed="${esc(s)}">${esc(s)}</button>`).join("")}
        </div>
      </div>`;
    return;
  }

  box.innerHTML = chat.messages.map((m, i) => {
    if (m.role === "tool") return toolCard(m);
    if (m.role === "user") {
      // The last question gets a marker when the server read it as a
      // question about the data rather than an answer — otherwise a turn
      // that ticks nothing off looks like a turn that went wrong.
      const asking = chat.mode === "explore" && i === lastUserIndex();
      return `<div class="msg msg-user">${asking
        ? `<span class="msg-mode">asking about the data</span>` : ""}
        <div class="msg-body">${md(m.content)}</div></div>`;
    }

    // An assistant turn that only asked for tools has no prose of its own:
    // the tool cards below it are its visible output, so it draws nothing.
    const asked = m.tool_calls?.length && !m.content.trim();
    const streaming = i === chat.messages.length - 1 && chat.busy;
    if (asked && !streaming) return "";

    const think = m.thinking?.trim()
      ? `<details class="msg-think"><summary>reasoning · ${
           m.thinking.trim().split(/\s+/).length} words</summary
         ><pre>${esc(m.thinking.trim())}</pre></details>`
      : "";
    const err = m.error ? `<div class="warn"><span>⚠</span><div>
         <strong>${esc(errorTitle(m.error, m.status))}</strong> ${esc(m.error)}
         <br>${errorHint(m.error, m.status)}${m.stack ? `
         <details class="warn-stack"><summary>where it came from</summary
           ><pre>${esc(m.stack)}</pre></details>` : ""}</div></div>` : "";

    return `<div class="msg msg-bot" data-i="${i}">
      ${think}
      <div class="msg-body">${m.content ? md(m.content) : ""}</div>
      ${err}
    </div>`;
  }).join("");

  box.insertAdjacentHTML("beforeend", workingRow());
  box.scrollTop = box.scrollHeight;
}

/* One line at the foot of the transcript saying what is happening, with
   dots that actually move. Only while there is nothing else to look at:

   once words are streaming, the words are the progress. */
export function workingRow() {
  const label = {
    thinking: "Thinking",
    searching: "Searching the dictionaries",
    drafting: "Updating the draft",
  }[chat.phase];
  if (!label) return "";
  const quiet = chat.phase === "drafting" ? " is-quiet" : "";
  return `<p class="working${quiet}" role="status">${esc(label)}<span class="ellipsis"
    ><span>.</span><span>.</span><span>.</span></span></p>`;
}

// Cheap path while tokens arrive: rewriting the whole transcript on every
// frame throws away the user's scroll position and their text selection.
export function renderStreaming(reply) {
  const box = $("#chat-log");
  const node = box?.querySelector(`.msg-bot[data-i="${chat.messages.indexOf(reply)}"] .msg-body`);
  if (!node) { renderTranscript(); return; }
  const atBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 60;
  node.innerHTML = md(reply.content) || `<span class="dots">…</span>`;
  if (atBottom) box.scrollTop = box.scrollHeight;
}

export const lastUserIndex = () => {
  for (let i = chat.messages.length - 1; i >= 0; i--) {
    if (chat.messages[i].role === "user") return i;
  }
  return -1;
};
