const test = require("node:test");
const assert = require("node:assert/strict");
const { Terminal } = require("../Bridge/node_modules/@xterm/headless");
const { readComposer, DraftReader } = require("../Bridge/draft.cjs");

async function screen(content) {
  const term = new Terminal({ cols: 60, rows: 8, allowProposedApi: true });
  await new Promise(resolve => term.write(content, resolve));
  return term;
}

test("the Claude composer excludes both prior output and the footer", async () => {
  const term = await screen("Previous reply\r\n────────────\r\n❯ Write here\r\n  Next line\r\n────────────\r\n  Footer\x1b[4;12H");
  assert.equal(readComposer(term, "claude").text, "Write here\nNext line");
  term.dispose();
});

test("a Codex hint or menu is not an English draft", async () => {
  const hint = await screen("› \x1b[2mAsk Codex to do anything\x1b[0m\x1b[1;3H");
  assert.equal(readComposer(hint, "codex").text, "");
  const menu = await screen("› 1. Update now\x1b[1;4H");
  assert.equal(readComposer(menu, "codex"), null);
  hint.dispose(); menu.dispose();
});

test("a collapsed bracketed paste retains the original full-width text", () => {
  const reader = new DraftReader();
  const original = "First\n" + String.fromCodePoint(0x4f60, 0x597d) + "\nLast";
  reader.input("\x1b[20");
  reader.input("0~" + original + "\x1b[201~");
  const marker = "[Pasted text #1 +2 lines]";
  assert.equal(reader.refresh({text:marker,before:marker,top:false,bottom:false}), original);
});

test("word-wrapped pastes do not displace the next collapsed paste", () => {
  const reader = new DraftReader();
  const paste = value => reader.input("\x1b[200~" + value + "\x1b[201~");
  const frame = text => ({text, before:text, top:false, bottom:false});
  paste("keep this space");
  assert.equal(reader.refresh(frame("keep this\nspace")), "keep this space");
  paste(" and this block");
  assert.equal(reader.refresh(frame("keep this\nspace[Pasted text #1]")), "keep this space and this block");
});
