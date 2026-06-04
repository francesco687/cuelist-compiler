#!/usr/bin/env bash
# Start the WebSocket->OSC bridge (macOS/Linux). Mirrors start.bat.
set -e
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing dependencies (ws)..."
  npm install
fi
exec node ws2osc.js
