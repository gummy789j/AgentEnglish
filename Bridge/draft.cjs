"use strict";

// Both TUIs repaint their own editor. The terminal's cursor must be inside
// that editor before any of its visible rows can become a translation request.
function readComposer(term, agent) {
  const buf = term.buffer.active;
  const rows = Array.from(
    { length: term.rows },
    (_, i) => buf.getLine(buf.baseY + i)?.translateToString(true) ?? "",
  );
  const y = buf.cursorY;
  const prefix = agent === "claude" ? /^❯[ \u00a0]/u : /^› /u;
  let start = y;
  while (start >= 0 && !prefix.test(rows[start])) start--;
  if (start < 0) return null;

  const rule = /^\s*[─━]{5,}\s*$/u;
  let end = start + 1;
  if (agent === "claude") {
    if (!rule.test(rows[start - 1] ?? "")) return null;
    while (end < rows.length && !rule.test(rows[end])) end++;
    if (end === rows.length) return null;
  } else {
    // The Codex editor starts at column 0. Continuation rows are indented
    // two columns. The blank separator before the status line ends the editor.
    while (end < rows.length) {
      if (rows[end] === "") {
        let next = end;
        while (next < rows.length && rows[next] === "") next++;
        if (
          next >= rows.length ||
          next === rows.length - 1 ||
          /(?: · |for shortcuts|tab to queue|context left|esc to interrupt)/i.test(
            rows[next],
          )
        )
          break;
        if (end > y && !rows.slice(next).some((line) => line === "")) break;
      } else if (!rows[end].startsWith("  ")) break;
      end++;
    }
    // Refuse menu options and history bullets when the cursor is elsewhere.
    if (/^› (?:\d+[.)] |\[.\] )/.test(rows[start])) return null;
  }
  if (y < start || y >= end || buf.cursorX < 2) return null;
  const first = buf.getLine(buf.baseY + start);
  if (y === start && buf.cursorX === 2 && first?.getCell(2)?.isDim()) {
    return { text: "", before: "", top: false, bottom: false };
  }
  const lines = rows.slice(start, end);
  const clip = / {2,}[↑↓↕]\s*$/u;
  const top = clip.test(lines[0]) && /[↑↕]\s*$/u.test(lines[0]);
  const bottom = lines.some((s) => clip.test(s) && /[↓↕]\s*$/u.test(s));
  const strip = (s, i) =>
    (i ? s.replace(/^ {1,2}/, "") : s.replace(prefix, "")).replace(clip, "");
  const partial = buf
    .getLine(buf.baseY + y)
    .translateToString(false, 0, buf.cursorX);
  const before = [...lines.slice(0, y - start), partial].map(strip).join("\n");
  return { text: lines.map(strip).join("\n").trimEnd(), before, top, bottom };
}

const token = /\[Pasted (?:text #\d+(?: \+\d+ lines?)?|Content [^\]]+)\]/gi;
class Pastes {
  constructor() {
    this.reset();
  }
  reset() {
    this.parts = "";
    this.inside = false;
    this.body = "";
    this.pending = [];
    this.known = new Map();
  }
  input(chunk) {
    let insertion = null;
    this.parts += chunk;
    const begin = "\x1b[200~",
      end = "\x1b[201~";
    while (this.parts) {
      const marker = this.inside ? end : begin;
      const at = this.parts.indexOf(marker);
      if (at < 0) {
        let keep = 0;
        for (let n = 1; n < marker.length; n++)
          if (this.parts.endsWith(marker.slice(0, n))) keep = n;
        if (this.inside)
          this.body = (
            this.body + this.parts.slice(0, this.parts.length - keep)
          ).slice(0, 160001);
        this.parts = keep ? this.parts.slice(-keep) : "";
        return insertion;
      }
      if (this.inside) {
        const body = (this.body + this.parts.slice(0, at)).replace(
          /\r\n?/g,
          "\n",
        );
        insertion = body.length <= 160000 ? body : null;
        this.pending.push(insertion);
        if (this.pending.length > 8) this.pending.shift();
        this.body = "";
      }
      this.inside = !this.inside;
      this.parts = this.parts.slice(at + marker.length);
    }
    return insertion;
  }
  expand(draft) {
    if (draft == null) return null;
    const unknown = [...new Set(draft.match(token) ?? [])].filter(
      (x) => !this.known.has(x),
    );
    if (unknown.length && unknown.length === this.pending.length) {
      unknown.forEach((key, i) => this.known.set(key, this.pending[i]));
      this.pending = [];
    }
    // A short paste was rendered literally. Consume it so a subsequent
    // collapsed paste cannot accidentally refer back to the previous text.
    this.pending = this.pending.filter(
      (s) => !s || !flat(draft).includes(flat(s)),
    );
    if ([...(draft.match(token) ?? [])].some((k) => !this.known.get(k)))
      return null;
    return draft.replace(token, (key) => this.known.get(key));
  }
}
// TUI wrapping is a display operation. Accept an original insertion only
// after its visible characters agree with what the editor actually painted.
const flat = (s) => s.replace(/\n/g, "");
function align(candidate, visible, before, clipping, preferred) {
  if (candidate == null || visible == null || before == null) return null;
  const exact = alignProjected(candidate, visible, before, clipping, preferred, flat);
  if (exact != null || !visible.includes("\n")) return exact;
  // Word wrapping may consume the space between two rendered rows. Require
  // each row, including its internal spaces, to agree with the original.
  const lines = visible.split("\n").filter(Boolean);
  const original = flat(candidate);
  if (!lines.every(line => original.includes(line))) return null;
  return alignProjected(candidate, visible, before, clipping, preferred, s => s.replace(/\s/g, ""));
}
function alignProjected(candidate, visible, before, { top, bottom }, preferred, project) {
  const full = project(candidate),
    part = project(visible);
  let offset = top && !bottom ? full.length - part.length : 0;
  if (top && bottom) {
    offset = full.indexOf(part);
    if (offset < 0 || full.indexOf(part, offset + 1) >= 0) return null;
  }
  if (
    (!top && !bottom && full !== part) ||
    offset < 0 ||
    !full.startsWith(part, offset)
  )
    return null;
  const prefix = offset + project(before).length;
  if (preferred >= 0 && project(candidate.slice(0, preferred)).length === prefix)
    return preferred;
  let index = 0,
    chars = 0;
  while (index < candidate.length && chars < prefix)
    if (project(candidate[index++]).length) chars++;
  return index;
}
class DraftReader {
  constructor() {
    this.pastes = new Pastes();
    this.reset();
  }
  reset() {
    this.text = null;
    this.insertion = null;
    this.cursor = 0;
    this.expected = null;
    this.expectedCursor = -1;
    this.pastes.reset();
  }
  input(input) {
    if (!this.pastes.inside && (input === "\r" || input === "\x03")) {
      this.reset();
      return;
    }
    const paste = this.pastes.input(input);
    if (this.pastes.inside || this.pastes.parts) return;
    const entry =
      paste ?? (/^[^\u0000-\u001f\u007f]+$/u.test(input) ? input : null);
    if (entry == null) return;
    if (Date.now() > this.deadline) {
      this.expected = null;
      this.insertion = null;
    }
    const base = this.expected ?? this.text ?? "",
      i = this.expected == null ? this.cursor : this.expectedCursor;
    this.expected = base.slice(0, i) + entry + base.slice(i);
    this.expectedCursor = i + entry.length;
    this.insertion = entry;
    this.deadline = Date.now() + 1800;
  }
  refresh(screen) {
    if (!screen) return null;
    const value = this.pastes.expand(screen.text);
    if (value == null) return null;
    const before = screen.before.replace(
      token,
      (k) => this.pastes.known.get(k) ?? k,
    );
    for (const [candidate, preferred] of [
      [this.expected, this.expectedCursor],
      [this.insertion, -1],
      [this.text, this.cursor],
    ]) {
      const cursor = align(candidate, value, before, screen, preferred);
      if (cursor == null) continue;
      this.text = candidate;
      this.cursor = cursor;
      if (candidate === this.expected || candidate === this.insertion) {
        // A wrapped literal paste may never appear as a contiguous substring
        // on screen. The validated insertion now accounts for that paste.
        const pending = this.pastes.pending.indexOf(this.insertion);
        if (pending >= 0) this.pastes.pending.splice(pending, 1);
        this.expected = null;
        this.insertion = null;
      }
      return candidate;
    }
    // Cursor-addressed repaints can leave old cells visible for one frame.
    // Keep the insertion until the repaint settles instead of trusting this frame.
    if (this.expected != null && Date.now() < this.deadline) return null;
    if (screen.top || screen.bottom) return null;
    this.text = value;
    this.cursor = before.length;
    this.expected = null;
    this.insertion = null;
    return value;
  }
}
module.exports = { readComposer, DraftReader };
