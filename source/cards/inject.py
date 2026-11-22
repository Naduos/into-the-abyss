#!/usr/bin/env python3
"""Fügt alle Kartenerweiterungen (exp/*.js) zwischen Markern in game.html ein.
Mehrfach ausführbar: der alte Block wird jedes Mal ersetzt."""
import glob, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
HTML = os.path.join(HERE, '..', 'game.html')
START, END = '/* === KARTEN-ERWEITERUNG START === */', '/* === KARTEN-ERWEITERUNG ENDE === */'
ANCHOR = '/* einbinden: jede Karte bekommt ihr eigenes Bild */'
HELPER = r'''/* Neue Karten je Spezialisierung (4 je Seltenheit + 2 Legendär), jede mit eigenem Bild.
   Neue Karten nur hier anlegen (Datei exp/<nr>_<spec>.js) – Glossar, Spec-Vorschau, Belohnungen,
   Shop und Godot (über den Datenexport) übernehmen sie automatisch. */
const EXP_SPEC_CHAR = {};
for(const h in SPECS) SPECS[h].forEach(sp => { EXP_SPEC_CHAR[sp.id] = h; });
function addExpansion(cards, arts){
  for(const k in cards){
    if(CARDS[k]) console.warn('duplicate card key', k);
    if(!arts[k]) console.warn('card without own art', k);
    const d = cards[k]; d.char = EXP_SPEC_CHAR[d.spec]; d.costConverted = true;
    d.art = () => SVG['card_' + k];
    CARDS[k] = d;
  }
  for(const k in arts){ if(CARD_ART[k]) console.warn('duplicate art key', k); }
  Object.assign(CARD_ART, arts);
}
'''
src = open(HTML, encoding='utf-8').read()
src = re.sub(re.escape(START) + r'.*?' + re.escape(END) + r'\n', '', src, flags=re.S)
existing = set(re.findall(r'^\s*([a-zA-Z_]\w*)\s*:\s*\{\s*name\s*:', src, flags=re.M))
existing |= set(re.findall(r'^([a-zA-Z_]\w*):`', src, flags=re.M))          # vorhandene Kartenbilder
parts = [open(f, encoding='utf-8').read() for f in sorted(glob.glob(os.path.join(HERE, '[0-9]*.js')))]
new = []
for p in parts: new += re.findall(r'^  ([a-zA-Z_]\w*):\s*\{name:', p, flags=re.M)
dups = sorted({k for k in new if k in existing} | {k for k in new if new.count(k) > 1})
if dups: sys.exit('Doppelte Kartenschlüssel: ' + ', '.join(dups))
block = START + '\n' + HELPER + '\n'.join(parts) + END + '\n'
if ANCHOR not in src: sys.exit('Anker nicht gefunden')
src = src.replace(ANCHOR, block + ANCHOR, 1)
open(HTML, 'w', encoding='utf-8').write(src)
print('eingefügt:', len(parts), 'Dateien')
