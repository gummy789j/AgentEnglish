#!/usr/bin/env node
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const net = require("node:net");
const { StringDecoder } = require("node:string_decoder");
const { Terminal } = require("@xterm/headless");
const pty = require("node-pty");
const { readComposer, DraftReader } = require("./draft.cjs");

const [agent, ...args] = process.argv.slice(2);
if (
  !["claude", "codex"].includes(agent) ||
  !process.stdin.isTTY ||
  !process.stdout.isTTY
) {
  console.error(
    "Usage: agent-en {claude|codex} [arguments] in an interactive terminal",
  );
  process.exit(2);
}
const hosts = {
  Apple_Terminal: "com.apple.Terminal",
  ghostty: "com.mitchellh.ghostty",
  "iTerm.app": "com.googlecode.iterm2",
};
const host =
  hosts[process.env.TERM_PROGRAM] || process.env.__CFBundleIdentifier || "";
const uid = process.getuid();
const dir = "/tmp/agentenglish-" + uid;
fs.mkdirSync(dir, { mode: 0o700, recursive: true });
const stat = fs.lstatSync(dir);
if (!stat.isDirectory() || stat.uid !== uid || stat.mode & 0o077)
  throw Error("Unsafe IPC directory");
const sock = path.join(dir, process.pid + ".sock");
const cols = process.stdout.columns,
  rows = process.stdout.rows;
const term = new Terminal({
  cols,
  rows,
  allowProposedApi: true,
  scrollback: 0,
});
const child = pty.spawn(agent, args, {
  cols,
  rows,
  env: process.env,
  cwd: process.cwd(),
  name: process.env.TERM || "xterm-256color",
  encoding: null,
});
const decoder = new StringDecoder("utf8"),
  inputDecoder = new StringDecoder("utf8");
const reader = new DraftReader();
let focus = true,
  stamp = Date.now(),
  editing = false,
  lastDraft = null;
// Empty composers often paint a gray English suggestion. Keep it out of
// the preview until there has been an edit or a history navigation.
let touched = false;
let ended = false;
const server = net.createServer((client) => {
  client.on("error", () => {});
  client.setTimeout(500, () => client.destroy());
  client.once("data", (request) => {
    if (editing && lastDraft == null) refresh();
    const visible = request.toString().trim() === host && focus && editing;
    client.end(
      JSON.stringify({
        host,
        stamp,
        active: visible,
        agent,
        filtersHints: true,
        text: visible && touched ? lastDraft : null,
      }) + "\n",
    );
  });
});
server.on("error", (e) =>
  process.stderr.write("AgentEnglish preview unavailable: " + e.message + "\n"),
);
server.listen(sock);
function refresh() {
  const raw = readComposer(term, agent);
  editing = raw !== null;
  lastDraft = reader.refresh(raw);
}
child.onData((data) => {
  const raw = Buffer.from(data);
  if (!process.stdout.write(raw)) {
    child.pause();
    process.stdout.once("drain", () => {
      if (!ended) child.resume();
    });
  }
  term.write(decoder.write(raw), refresh);
});
process.stdin.setRawMode(true);
process.stdin.resume();
process.stdout.write("\x1b[?1004h");
process.stdin.on("data", (data) => {
  const input = inputDecoder.write(data);
  if (input === "\x1b[O" && !reader.pastes.inside) focus = false;
  else {
    focus = true;
    stamp = Date.now();
  }
  if (editing) {
    if (!reader.pastes.inside && (input === "\r" || input === "\x03")) touched = false;
    else if (!["\x1b[I", "\x1b[O"].includes(input)) touched = true;
    reader.input(input);
  }
  // Report focus to the child only when it requested this terminal mode.
  if (
    term.modes.sendFocusMode ||
    reader.pastes.inside ||
    !["\x1b[I", "\x1b[O"].includes(input)
  )
    child.write(data);
});
process.stdout.on("resize", () => {
  const { columns, rows } = process.stdout;
  if (columns && rows) {
    term.resize(columns, rows);
    child.resize(columns, rows);
  }
});
function clean() {
  ended = true;
  if (process.stdin.isTTY) process.stdin.setRawMode(false);
  process.stdout.write("\x1b[?1004l");
  server.close();
  try {
    fs.unlinkSync(sock);
  } catch {}
}
process.on("exit", clean);
for (const sig of ["SIGTERM", "SIGHUP"])
  process.on(sig, () => {
    child.kill();
    process.exit(1);
  });
child.onExit(({ exitCode, signal }) => {
  process.exitCode = exitCode || (signal ? 128 + signal : 0);
  process.stdin.pause();
  server.close();
  process.exit(process.exitCode);
});
