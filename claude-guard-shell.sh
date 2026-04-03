#!/usr/bin/env bash
set -euo pipefail

REAL_SHELL="/bin/bash"
RULES_FILE="${CLAUDE_GUARD_RULES:-$HOME/.claude-guard/destructive_matchers.rules}"

if [[ ! -f "$RULES_FILE" ]]; then
  echo "claude-guard: rules file not found: $RULES_FILE" >&2
  exit 2
fi

if [[ $# -ge 2 && "$1" == "-lc" ]]; then
  cmd="$2"
else
  exec "$REAL_SHELL" "$@"
fi

if [[ "${CLAUDE_ALLOW_DESTRUCTIVE:-0}" == "1" ]]; then
  echo "claude-guard: CLAUDE_ALLOW_DESTRUCTIVE=1 set — skipping all rule checks" >&2
  exec "$REAL_SHELL" -lc "$cmd"
fi

while IFS='|' read -r action rule_id regex; do
  [[ -z "${action:-}" ]] && continue
  [[ "${action:0:1}" == "#" ]] && continue
  if [[ "$cmd" =~ $regex ]]; then
    case "$action" in
      deny)
        echo "claude-guard: [DENY] rule '$rule_id' — command permanently blocked" >&2
        echo "cmd: $cmd" >&2
        exit 126
        ;;
      confirm)
        echo "claude-guard: [BLOCK] rule '$rule_id' — requires explicit override" >&2
        echo "cmd: $cmd" >&2
        echo "To run intentionally: CLAUDE_ALLOW_DESTRUCTIVE=1 claude-remote-control" >&2
        exit 126
        ;;
      *)
        echo "claude-guard: invalid action '$action' in rules file" >&2
        exit 2
        ;;
    esac
  fi
done < "$RULES_FILE"

exec "$REAL_SHELL" -lc "$cmd"
