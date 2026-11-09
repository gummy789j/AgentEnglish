// Runs in a disposable, trusted test directory. Never submits a prompt.
const path = require("node:path"),
  net = require("node:net");
const dep = (n) => require(path.join(__dirname, "../Bridge/node_modules", n));
const { Terminal } = dep("@xterm/headless"),
  pty = dep("node-pty");
const agent = process.argv[2],
  cwd = process.argv[3] || process.cwd();
const outer = new Terminal({ cols: 86, rows: 29, allowProposedApi: true });
const cmd = [path.join(__dirname, "../Bridge/run.cjs"), agent];
if (agent === "codex") cmd.push("-c", "check_for_update_on_startup=false");
const p = pty.spawn(process.execPath, cmd, {
  cols: 86,
  rows: 29,
  cwd,
  env: {
    ...process.env,
    TERM: "xterm-256color",
    TERM_PROGRAM: "ghostty",
    DISABLE_AUTOUPDATER: "1",
  },
});
p.onData((s) => outer.write(s));
outer.onData((s) => p.write(s));
const delay = (ms) => new Promise((r) => setTimeout(r, ms));
async function snapshot() {
  return new Promise((resolve, reject) => {
    const s = net.createConnection(
      "/tmp/agentenglish-" + process.getuid() + "/" + p.pid + ".sock",
    );
    let str = "";
    s.setTimeout(700, () => s.destroy(Error("timeout")));
    s.on("connect", () => s.write("com.mitchellh.ghostty\n"));
    s.on("data", (v) => (str += v));
    s.on("end", () => {
      try {
        resolve(JSON.parse(str));
      } catch (e) {
        reject(e);
      }
    });
    s.on("error", reject);
  });
}
async function until(f, msg) {
  let value;
  for (let i = 0; i < 100; i++) {
    try {
      value = await snapshot();
      if (f(value)) return value;
    } catch {}
    await delay(100);
  }
  throw Error(msg + "; snapshot=" + JSON.stringify(value));
}
(async () => {
  await until((s) => s.active, "editor never became ready");
  const paste = (s) => p.write("\x1b[200~" + s + "\x1b[201~");
  const greeting = String.fromCodePoint(0x4f60, 0x597d);
  const src = greeting + " auth.ts.\nKeep token.";
  paste(src);
  await until((s) => s.text === src, "two-line paste");
  p.write("\x1b[D");
  await delay(120);
  p.write(" valid");
  await until(
    (s) => s.text === greeting + " auth.ts.\nKeep token valid.",
    "cursor edit",
  );
  const block = "Multiple lines\n" + Array(12).fill("Test line N").join("\n");
  paste(block);
  await until((s) => s.text?.includes(block), "large paste");
  p.write("\x1b[O");
  await until((s) => !s.active && !s.text, "blur");
  p.write("\x1b[I");
  await until((s) => s.active && s.text.includes(block), "focus");
  const longer = "\n\n" + (greeting + "long line").repeat(14);
  paste(longer);
  await until(
    (s) => s.text?.includes(longer) && s.text?.startsWith(src.split("\n")[0]),
    "blank lines and soft wraps",
  );
  const huge = " " + (greeting + "long paste").repeat(130);
  paste(huge);
  await until(
    (s) => s.text?.includes(huge) && s.text?.includes(longer),
    "collapsed long single-line paste",
  );

  console.log(agent + ": multiline, cursor edit, large paste and focus passed");
})()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => {
    p.kill();
    setTimeout(() => process.exit(process.exitCode || 0), 300);
  });
