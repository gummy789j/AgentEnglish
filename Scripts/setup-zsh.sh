#!/bin/bash
set -eu
config="$1"
line='[[ ! -r "$HOME/Applications/AgentEnglish.app/Contents/Resources/Bridge/integration.zsh" ]] || source "$HOME/Applications/AgentEnglish.app/Contents/Resources/Bridge/integration.zsh" # AgentEnglish'
if ! /usr/bin/grep -Fxq "$line" "$config" 2>/dev/null; then printf '\n%s\n' "$line" >> "$config"; fi
