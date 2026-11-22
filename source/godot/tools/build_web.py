#!/usr/bin/env python3
"""Baut den Ordner web/ für die exe aus der HTML-Version.
   - web/index.html  = die HTML, Google-Schriften und PeerJS werden lokal eingebunden (läuft offline)
   - web/fonts/      = Schriftdateien (woff2) + fonts.css
   - web/peerjs.min.js
   Aufruf: python3 tools/build_web.py <game.html> [node_modules]"""
import os, re, shutil, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
src = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/src/game.html'
nm = sys.argv[2] if len(sys.argv) > 2 else '/home/claude/tools/node_modules'
web = os.path.join(root, 'web')
fonts = os.path.join(web, 'fonts')
os.makedirs(fonts, exist_ok=True)

# Schriften: dieselben Familien und Stärken wie der Google-Fonts-Link der HTML
FAMILIES = {'cinzel': [600, 800], 'inter': [400, 600, 800], 'uncial-antiqua': [400],
            'pirata-one': [400], 'germania-one': [400], 'aladin': [400]}
css = []
for fam, weights in FAMILIES.items():
    base = os.path.join(nm, '@fontsource', fam)
    for w in weights:
        text = open(os.path.join(base, f'{w}.css'), encoding='utf-8').read()
        for f in re.findall(r"url\(\./files/([^)]+\.woff2)\)", text):
            shutil.copy(os.path.join(base, 'files', f), os.path.join(fonts, f))
        # nur woff2 behalten (WebView2/WebKit können das alle)
        text = re.sub(r",\s*url\(\./files/[^)]+\.woff\) format\('woff'\)", '', text)
        css.append(text.replace('./files/', './'))
open(os.path.join(fonts, 'fonts.css'), 'w', encoding='utf-8').write('\n'.join(css))

shutil.copy(os.path.join(nm, 'peerjs', 'dist', 'peerjs.min.js'), os.path.join(web, 'peerjs.min.js'))

html = open(src, encoding='utf-8').read()
n0 = len(html)
html = re.sub(r'<link rel="preconnect" href="https://fonts\.googleapis\.com">\s*', '', html)
html, a = re.subn(r'<link href="https://fonts\.googleapis\.com/css2[^"]*" rel="stylesheet">', '<link href="fonts/fonts.css" rel="stylesheet">', html)
html, b = re.subn(r'<script src="https://unpkg\.com/peerjs@[^"]*"></script>', '<script src="peerjs.min.js"></script>', html)
if a != 1 or b != 1:
    sys.exit(f'build_web: Schrift-Link ({a}) oder PeerJS ({b}) nicht gefunden')
open(os.path.join(web, 'index.html'), 'w', encoding='utf-8').write(html)
print(f'web/ gebaut: index.html {len(html)//1024} KB, {len(os.listdir(fonts)) - 1} Schriftdateien')
