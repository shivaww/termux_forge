#!/bin/bash
# ============================================================================
# Nexon Python Bridge Installer
# ============================================================================
set -e

echo "=== Nexon Python Bridge Setup ==="
echo "1. Checking and installing system packages..."
pkg update && pkg install -y curl python clang make

echo "2. Creating nexon_bridge directory..."
mkdir -p ~/nexon_bridge
cd ~/nexon_bridge

echo "3. Downloading Nexon tool execution files..."
BASE_URL="https://raw.githubusercontent.com/shivaww/Nexon/main/python_bridge"
files=(
  "mcp_server.py"
  "command_executor.py"
  "security.py"
  "github_hooks.py"
  "checkpoint_hooks.py"
  "media_hooks.py"
  "workflow_runner.py"
  "mcp_manager.py"
  "protocol.py"
  "requirements.txt"
  "tool_discovery.py"
  "termux_forge_bridge.py"
  "__init__.py"
  ".gitignore"
)

for f in "${files[@]}"; do
  echo "  -> Downloading $f..."
  curl -L -s -o "$f" "$BASE_URL/$f?v=$(date +%s)"
done

echo "4. Installing Python requirements..."
pip install -r requirements.txt

echo "=== Setup Complete! ==="
echo "You can start the bridge server now by running:"
echo "  cd ~/nexon_bridge && python3 mcp_server.py"
