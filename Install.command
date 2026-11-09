#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
source_app="$root/AgentEnglish.app"
if ! command -v node >/dev/null; then
  for bin in /opt/homebrew/bin /usr/local/bin; do [[ ! -x "$bin/node" ]] || export PATH="$bin:$PATH"; done
fi
if ! command -v node >/dev/null || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
  echo 'Install Node.js 22 or later, then run this installer again.'; exit 1
fi
if [[ ! -d "$source_app" ]]; then
  source_app="$root/dist/AgentEnglish.app"
  "$root/Scripts/build.sh" "$source_app"
fi
apps="$HOME/Applications"
mkdir -p "$apps"
dest="$apps/AgentEnglish.app"
if [[ -e "$dest" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$dest/Contents/Info.plist" 2>/dev/null || true)" != local.agentenglish.mac ]]; then
  echo "A different application already exists at $dest"; exit 1
fi
stage="$(mktemp -d "$apps/.agentenglish-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$source_app" "$stage/AgentEnglish.app"
codesign --verify --deep --strict "$stage/AgentEnglish.app"
if [[ -d "$dest" ]]; then
  pkill -x -u "$(id -u)" AgentEnglish || true
  mv "$dest" "$stage/previous.app"
fi
if ! mv "$stage/AgentEnglish.app" "$dest"; then
  [[ ! -d "$stage/previous.app" ]] || mv "$stage/previous.app" "$dest"; exit 1
fi
config="${ZDOTDIR:-$HOME}/.zshrc"
"$root/Scripts/setup-zsh.sh" "$config"
open -g "$dest"
printf '\nInstalled in %s.\nOpen a new zsh tab and start claude or codex.\n' "$dest"
