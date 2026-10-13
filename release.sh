#!/usr/bin/env bash
# Builds Checkmate.app and publishes it as a GitHub release, e.g. ./release.sh v0.2
set -euo pipefail
cd "$(dirname "$0")"

version="$1"
./build-app.sh
rm -f dist/Checkmate.zip
ditto -c -k --keepParent dist/Checkmate.app dist/Checkmate.zip
gh release create "$version" dist/Checkmate.zip --title "Checkmate $version" --notes "Download **Checkmate.zip**, unzip it, and drag Checkmate.app into Applications. See the README for the one-time \"Open Anyway\" step."
