#!/bin/bash
# Spieldaten aus der HTML neu exportieren (nach jeder Änderung an der HTML-Version ausführen)
cd "$(dirname "$0")"
NAMES=$(grep -oP "^\s*const \K[A-Z][A-Z0-9_]+(?= =)" ../into-the-abyss.html | sort -u | tr '\n' ',')
node dump.js ../into-the-abyss.html /tmp/data.json "$NAMES" && python3 - <<'P'
import json
d=json.load(open('/tmp/data.json'))
ART={'SVG','SPEC_ART','ART_ANIM','ART_FX','SERVANT_ART','RHUD_MAGIC'}; UI={'DRAG','NET','OPT'}
json.dump({k:v for k,v in d.items() if k not in ART|UI},open('../data/game_data.json','w'),separators=(',',':'),ensure_ascii=False)
json.dump({k:d[k] for k in ART},open('../data/art_data.json','w'),separators=(',',':'),ensure_ascii=False)
print("Daten exportiert")
P
# Grafiken + Kartentexte für die Godot-Oberfläche
node dump_ui.js ../into-the-abyss.html ../data/ui_data.json
