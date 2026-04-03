#!/bin/bash
# =============================================================================
# Claude Code Remote Control - Setup Script
# For Ubuntu (bare metal, VM, or Proxmox LXC)
# Uses claude.ai Pro/Max subscription (no API key needed)
#
# Based on original script by SecureMind Tech Solutions
# Guard shell layer added for safe --dangerously-skip-permissions usage
# =============================================================================

set -e

# --- Config ---
SERVICE_USER="${SUDO_USER:-$(whoami)}"
SERVICE_NAME="claude-code"
WORK_DIR="/home/$SERVICE_USER"
NVM_DIR="/home/$SERVICE_USER/.nvm"
GUARD_DIR="/home/$SERVICE_USER/.claude-guard"
NODE_VERSION="20"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo "============================================="
echo "  Claude Code Remote Control Setup"
echo "  SecureMind Tech Solutions"
echo "  User: $SERVICE_USER"
echo "============================================="
echo ""

# Must be run as root
[ "$EUID" -eq 0 ] || error "Please run with sudo"

# --- 1. System dependencies ---
info "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq curl tmux git build-essential

# --- 2. Install NVM + Node.js ---
info "Installing NVM and Node.js $NODE_VERSION..."
sudo -u "$SERVICE_USER" bash <<NVMEOF
export NVM_DIR="$NVM_DIR"
if [ ! -d "\$NVM_DIR" ]; then
    curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
source "\$NVM_DIR/nvm.sh"
nvm install $NODE_VERSION
nvm use $NODE_VERSION
nvm alias default $NODE_VERSION
echo "Node: \$(node --version)"
echo "NPM:  \$(npm --version)"
NVMEOF

# --- 3. Install Claude Code ---
info "Installing Claude Code..."
sudo -u "$SERVICE_USER" bash -c "source $NVM_DIR/nvm.sh && npm install -g @anthropic-ai/claude-code"
CLAUDE_BIN=$(sudo -u "$SERVICE_USER" bash -c "source $NVM_DIR/nvm.sh && which claude")
info "Claude Code installed at: $CLAUDE_BIN"

# --- 4. Install guard shell ---
info "Installing claude-guard shell..."
mkdir -p "$GUARD_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 755 "$SCRIPT_DIR/claude-guard-shell.sh" "$GUARD_DIR/claude-guard-shell.sh"
install -m 644 "$SCRIPT_DIR/destructive_matchers.rules" "$GUARD_DIR/destructive_matchers.rules"
chown -R "$SERVICE_USER:$SERVICE_USER" "$GUARD_DIR"

info "Guard shell installed to: $GUARD_DIR"

# --- 5. Check login status ---
info "Checking Claude login status..."
if [ ! -f "/home/$SERVICE_USER/.claude/credentials.json" ]; then
    warn "Not logged in yet! After this script finishes, run:"
    warn "  claude login"
    warn "Then restart the service:"
    warn "  sudo systemctl restart $SERVICE_NAME"
else
    info "Claude credentials found — good to go."
fi

# --- 6. Create Remote Control start script ---
info "Creating start-claude-remote.sh..."
RC_SCRIPT="/home/$SERVICE_USER/start-claude-remote.sh"

cat > "$RC_SCRIPT" <<SCRIPT
#!/bin/bash
# Starts Claude Code Remote Control inside a tmux session
# Guard shell intercepts all bash commands for safety

export NVM_DIR="/home/$SERVICE_USER/.nvm"
source "\$NVM_DIR/nvm.sh"
export HOME="/home/$SERVICE_USER"
export SHELL="$GUARD_DIR/claude-guard-shell.sh"
export CLAUDE_GUARD_RULES="$GUARD_DIR/destructive_matchers.rules"

SESSION="claude-remote-\$(hostname)"

# Kill existing session if running
tmux kill-session -t "\$SESSION" 2>/dev/null || true

# Start new tmux session with guard shell + claude remote control
tmux new-session -d -s "\$SESSION" -x 220 -y 50
tmux send-keys -t "\$SESSION" "SHELL=$GUARD_DIR/claude-guard-shell.sh CLAUDE_GUARD_RULES=$GUARD_DIR/destructive_matchers.rules claude --remote-control --dangerously-skip-permissions --name \"\$(hostname)\"" Enter

echo ""
echo "Claude Code Remote Control started in tmux session: \$SESSION"
echo "Guard shell: ACTIVE ($GUARD_DIR/claude-guard-shell.sh)"
echo ""
echo "View session:  tmux attach -t \$SESSION"
echo "Detach:        Ctrl+B then D"
echo ""
echo "Override for intentional destructive ops:"
echo "  CLAUDE_ALLOW_DESTRUCTIVE=1 bash \$0"
SCRIPT

chmod +x "$RC_SCRIPT"
chown "$SERVICE_USER:$SERVICE_USER" "$RC_SCRIPT"

# --- 7. Create systemd service ---
info "Creating systemd service..."
cat > "/etc/systemd/system/$SERVICE_NAME.service" <<SERVICE
[Unit]
Description=Claude Code Remote Control (SecureMind)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=$SERVICE_USER
WorkingDirectory=$WORK_DIR
Environment="NVM_DIR=/home/$SERVICE_USER/.nvm"
Environment="HOME=$WORK_DIR"
Environment="SHELL=$GUARD_DIR/claude-guard-shell.sh"
Environment="CLAUDE_GUARD_RULES=$GUARD_DIR/destructive_matchers.rules"
ExecStart=$RC_SCRIPT
ExecStop=/usr/bin/tmux kill-session -t claude-remote-$(hostname)
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

# --- 8. Enable and start ---
info "Enabling and starting service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

sleep 3
systemctl status "$SERVICE_NAME" --no-pager || true

# --- Done ---
echo ""
echo "============================================="
echo -e "${GREEN}  Setup Complete!${NC}"
echo "============================================="
echo ""
echo "Guard shell status: ACTIVE"
echo "Rules file: $GUARD_DIR/destructive_matchers.rules"
echo ""
echo "Next steps:"
echo ""
echo "  1. If not logged in yet:"
echo "       claude login"
echo "       sudo systemctl restart $SERVICE_NAME"
echo ""
echo "  2. View the remote control session:"
echo "       tmux attach -t claude-remote-$(hostname)"
echo "       (Ctrl+B then D to detach and keep running)"
echo ""
echo "  3. On your phone:"
echo "       Open Claude app → menu → Pair with your desktop"
echo ""
echo "  4. To allow a destructive op intentionally:"
echo "       CLAUDE_ALLOW_DESTRUCTIVE=1 ~/start-claude-remote.sh"
echo ""
echo "Useful commands:"
echo "  sudo systemctl status $SERVICE_NAME"
echo "  sudo systemctl restart $SERVICE_NAME"
echo "  sudo systemctl stop $SERVICE_NAME"
echo "  tmux attach -t claude-remote-$(hostname)"
echo ""
