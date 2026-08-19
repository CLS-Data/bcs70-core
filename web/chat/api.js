/* Talking to web/server.py. The turn arrives as NDJSON, one event a line. */

export async function api(path, body) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  if (!res.ok) throw new Error(`${path}: ${res.status}`);
  return res.json();
}

/* NDJSON, one event per line, exactly as the server emits it. */
export async function* streamTurn(payload, signal) {
  const res = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
    signal,
  });
  if (!res.ok) throw new Error(`/api/chat: ${res.status} ${await res.text()}`);

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      try { yield JSON.parse(line); } catch { /* partial frame */ }
    }
  }
}

/* ── One turn ──────────────────────────────────────────────────────── */
