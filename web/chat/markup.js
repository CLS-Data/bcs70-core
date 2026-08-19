/* Escaping, and the smallest markdown renderer that will do.

   Deliberately tiny. Local models emit markdown whether or not you ask, and a
   full parser is a dependency this site does not have. Everything is escaped
   first, so the worst a model can do with this is fail to make something bold. */

export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

export function md(text) {
  return esc(text)
    .replace(/```([\s\S]*?)```/g, (_, c) => `<pre class="chat-pre">${c.trim()}</pre>`)
    .replace(/`([^`\n]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|\s)_([^_\n]+)_(?=\s|$)/g, "$1<em>$2</em>")
    .replace(/^[-*]\s+(.*)$/gm, "<li>$1</li>")
    .replace(/(<li>[\s\S]*?<\/li>)(?!\s*<li>)/g, "<ul>$1</ul>")
    .replace(/\n{2,}/g, "</p><p>")
    .replace(/\n/g, "<br>")
    .replace(/^/, "<p>").replace(/$/, "</p>")
    .replace(/<p><\/p>/g, "");
}
