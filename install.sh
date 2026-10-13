#!/usr/bin/env bash
# Builds Checkmate.app, installs it to /Applications, and (re)launches it.
set -euo pipefail
cd "$(dirname "$0")"

./build-app.sh

app="/Applications/Checkmate.app"
pkill -x Checkmate || true
rm -rf "$app"
cp -R dist/Checkmate.app "$app"
open "$app"
echo "Installed $app"
