#!/bin/sh
# =====================================================================
#   UPDATE VERÖFFENTLICHEN (GitHub-Repo als Update-Server)
#   tools/release.sh            -> Update: neue game-<v>.pck + latest.json ins Repo (Spiele laden es beim Start)
#   tools/release.sh --full     -> zusätzlich download/IntoTheAbyss.zip (exe + pck) – beim ersten Mal
#                                  und wenn sich die Godot-Version ändert
#   Repo-Klon:  ../into-the-abyss (siehe tools/release.cfg)
# =====================================================================
set -e
cd "$(dirname "$0")/.."
. tools/release.cfg
FULL=0; [ "$1" = "--full" ] && FULL=1
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
OUT=../release; mkdir -p "$OUT"; rm -f "$OUT"/*

# 1. Daten aus der HTML exportieren, Engine zusammensetzen
cp "$HTML" into-the-abyss.html
sh tools/export_data.sh >/dev/null
./build.sh

# 2. Versionsnummer erhöhen, Update-Adresse eintragen
V=$(python3 -c "import json;print(int(json.load(open('version.json'))['version'])+1)")
printf '{"version": %s, "date": "%s"}\n' "$V" "$(date +%F)" > version.json
sed -i "s#^const UPDATE_URL := .*#const UPDATE_URL := \"$RAW/updates/latest.json\"#" boot/boot.gd

# 3. Exportieren
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-pack "Windows Desktop" "$OUT/game-$V.pck" >/dev/null 2>&1
if [ $FULL = 1 ]; then
  godot --headless --path . --export-release "Windows Desktop" "$OUT/IntoTheAbyss.exe" >/dev/null 2>&1
  (cd "$OUT" && zip -q IntoTheAbyss.zip IntoTheAbyss.exe IntoTheAbyss.pck)
fi
ENG=$(godot --headless -s tools/engine_version.gd 2>/dev/null | tail -1)
SHA=$(sha256sum "$OUT/game-$V.pck" | cut -d' ' -f1)

# 4. Ins Repo legen (alte Update-Pakete löschen) und hochladen
mkdir -p "$CLONE/updates" "$CLONE/download"
rm -f "$CLONE"/updates/game-*.pck
cp "$OUT/game-$V.pck" "$CLONE/updates/"
cat > "$CLONE/updates/latest.json" <<EOF
{"version": $V, "engine": "$ENG", "sha256": "$SHA",
 "pck_url": "$RAW/updates/game-$V.pck",
 "full_url": "https://github.com/$REPO#download"}
EOF
[ $FULL = 1 ] && cp "$OUT/IntoTheAbyss.zip" "$CLONE/download/IntoTheAbyss.zip"
cp "$HTML" "$CLONE/into-the-abyss.html"
# Quelltext mitsichern (ohne Exporte)
mkdir -p "$CLONE/source/godot" "$CLONE/source/cards"
rm -rf "$CLONE/source/godot"; mkdir -p "$CLONE/source/godot"
tar --exclude='./.godot' --exclude='./tools/node_modules' --exclude='*.html' -cf - . | tar -xf - -C "$CLONE/source/godot"
cp "$(dirname "$HTML")"/exp/*.js "$(dirname "$HTML")"/exp/inject.py "$CLONE/source/cards/" 2>/dev/null || true
cd "$CLONE"
git add -A
git commit -q -m "Into the Abyss Version $V${NOTES:+ – $NOTES}

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01VL2RaEuLfFe5JqWnxBQh1H"
git -c push.negotiate=true push -q origin "HEAD:$BRANCH"
echo "Veröffentlicht: Version $V"
