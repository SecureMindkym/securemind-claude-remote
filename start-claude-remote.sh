#!/bin/bash
# Starts Claude Code with --remote-control inside a tmux session

export NVM_DIR="/home/securemind/.nvm"
source "$NVM_DIR/nvm.sh"
export HOME="/home/securemind"

SESSION="claude-remote-$(hostname)"

# Kill existing session if running
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Start new tmux session running claude --remote-control
tmux new-session -d -s "$SESSION" -x 220 -y 50
tmux send-keys -t "$SESSION" "claude --remote-control --name \"$(hostname)\"" Enter

echo "Claude Code Remote Control started in tmux session: $SESSION"
echo "View session: tmux attach -t $SESSION"
