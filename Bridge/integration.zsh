# Only changes interactive zsh. Invoke the real executable via PATH inside agent-en.
[[ -o interactive ]] || return 0
typeset -g AGENT_ENGLISH_BRIDGE="${${(%):-%x}:A:h}/agent-en"
claude() { "$AGENT_ENGLISH_BRIDGE" claude "$@"; }
codex() { "$AGENT_ENGLISH_BRIDGE" codex "$@"; }
