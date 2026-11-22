#!/bin/sh
# Baut die spielbare Windows-Version lokal (ohne Hochladen): ../release/IntoTheAbyss.zip
set -e
cd "$(dirname "$0")/.."
./build.sh
OUT=../release; mkdir -p "$OUT"; rm -f "$OUT"/IntoTheAbyss.*
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-release "Windows Desktop" "$OUT/IntoTheAbyss.exe"
(cd "$OUT" && rm -f IntoTheAbyss.zip && zip -q IntoTheAbyss.zip IntoTheAbyss.exe IntoTheAbyss.pck)
ls -la "$OUT"
