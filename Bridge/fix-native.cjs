// The npm archive may strip the executable bit from node-pty's macOS helper.
if (process.platform === "darwin") {
  const fs = require("node:fs"),
    path = require("node:path");
  const helper = path.join(
    __dirname,
    "node_modules/node-pty/prebuilds/darwin-" + process.arch,
    "spawn-helper",
  );
  if (fs.existsSync(helper)) fs.chmodSync(helper, 0o755);
}
