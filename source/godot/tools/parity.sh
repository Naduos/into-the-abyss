#!/bin/bash
# Paritätstest HTML <-> Godot. Aufruf: tools/parity.sh seed party(kommagetrennt) specIdx steps
# Voraussetzungen: node + jsdom (npm i jsdom@24 im tools-Ordner), godot im PATH, HTML unter ../into-the-abyss.html
cd "$(dirname "$0")"
s=$1; p=$2; i=$3; n=$4; tag="${s}_${p//,/-}_$i"; mkdir -p /tmp/par
node bot_js.js ../into-the-abyss.html $s $p $i $n /tmp/par/js_$tag.txt > /dev/null 2>&1
(cd .. && godot --headless --path . -s tests/bot.gd -- $s $p $i $n /tmp/par/gd_$tag.txt > /dev/null 2>&1)
if cmp -s /tmp/par/js_$tag.txt /tmp/par/gd_$tag.txt; then echo "OK   $tag $(wc -l < /tmp/par/js_$tag.txt) steps"
else echo "DIFF $tag: $(diff /tmp/par/js_$tag.txt /tmp/par/gd_$tag.txt | head -1)"; fi
