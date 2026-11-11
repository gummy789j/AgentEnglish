# Contributing

Use macOS 15 or later with the macOS 15+ SDK, Node.js 22+ and npm. Please keep source, interface copy, file names and documentation in English. Unicode test fixtures use code points where the actual script matters.

## Layout

- `Sources/` — AppKit menu bar lifecycle, SwiftUI panel, draft routing, speech and translation.
- `Bridge/` — interactive zsh integration, pseudo-terminal proxy and CLI-specific draft extraction.
- `Assets/` — the speech-wing mark, application icon and README logo. The menu bar uses a macOS template image.
- `Tests/` — parser regression tests, panel layout and clipboard checks, and optional real-agent tests.
- `Scripts/` — local build, installation helpers and asset generation.

## Verify a change

```sh
npm ci --prefix Bridge
node --test Tests/draft.test.cjs
./Scripts/build.sh
codesign --verify --deep --strict dist/AgentEnglish.app
```

With a graphical macOS session, run `./Scripts/test-panel.sh` to verify content-driven height, the scroll cap, and complete-only copying using a private pasteboard. Set `AGENTENGLISH_PREVIEW_PATH` to an absolute PNG path to save the panel preview. These tests require neither a model nor agent accounts.

For prompt changes, run `./Scripts/test-prompts.sh` with Ollama and `qwen3:4b-instruct` installed. It exercises the production generation path on synthetic translation and polishing samples, including CSV selection, retrieval sources, exclusions, speaker roles and relative dates. Each JSON output includes semantic review criteria. Compare the output against those criteria manually; a successful exit means generation completed, not that translation quality passed. Model output can vary. This optional check is not run in CI and does not access the example URLs.

For CLI changes, use a disposable directory that you have already trusted in the CLI. These tests type sample drafts without sending them:

```sh
node Tests/cli-live.cjs claude /absolute/path/to/test-project
node Tests/cli-live.cjs codex /absolute/path/to/test-project
```

To exercise the full Ghostty-to-model path, install Ghostty and prepare the local model as described in the README. Build a separate executable with the test probes enabled:

```sh
AGENTENGLISH_TEST_PROBES=1 ./Scripts/build.sh dist/test/AgentEnglish.app
./Tests/ghostty-live.sh dist/test/AgentEnglish.app claude /absolute/path/to/test-project --english
./Tests/ghostty-live.sh dist/test/AgentEnglish.app codex /absolute/path/to/test-project
```

To regenerate the Finder icon after changing the mark, run `swift Scripts/icons.swift Assets/mark.svg dist/AgentEnglish.iconset Assets/logo.png` followed by `iconutil -c icns dist/AgentEnglish.iconset -o Assets/AgentEnglish.icns`.

## Pull requests

Describe the user-visible behavior, include reproduction steps for a bug, and list the checks you ran. For a panel change, include a screenshot with a synthetic draft. Do not include private prompts, terminal history, access tokens, generated app bundles, or local machine paths.
