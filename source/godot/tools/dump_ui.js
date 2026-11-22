// Exportiert alles, was die Godot-Oberfläche zum Anzeigen braucht (aus der HTML berechnet):
// Kartenbilder, Kartentexte (normal + aufgewertet), Einheiten-/Spec-Bilder, Status-Symbole und -Texte,
// Angriffssymbole, Biom-Namen. Aufruf: node dump_ui.js ../into-the-abyss.html ../data/ui_data.json
const fs = require('fs');
const { JSDOM, VirtualConsole } = require('jsdom');
const [,, src, out] = process.argv;
let html = fs.readFileSync(src, 'utf8').replace(/<script src="https:\/\/unpkg[^>]*><\/script>/, '<script>window.Peer=function(){};</script>');
const vc = new VirtualConsole();
const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: vc });
setTimeout(() => {
  const r = dom.window.eval(`(() => {
    const str = v => typeof v === 'function' ? (() => { try { return v(1); } catch(e){ return ''; } })() : (v || '');
    const R = {card_art:{}, card_text:{}, svg:{}, spec_art:{}, status:{}, atk:{}, atk_types:ATK_TYPES, biomes:{}, affixes:{}};
    for(const k in CARDS){
      const d = CARDS[k];
      try { R.card_art[k] = str(d.art); } catch(e){ R.card_art[k] = ''; }
      try { R.card_text[k] = [cardDesc({key:k, id:-1, gems:[]}), cardDesc({key:k, id:-1, gems:[], upgraded:true})]; } catch(e){ R.card_text[k] = [String(e), '']; }
    }
    for(const k in SVG) R.svg[k] = str(SVG[k]);
    for(const k in SPEC_ART) R.spec_art[k] = str(SPEC_ART[k]);
    for(const k in STATUS){ const d = STATUS[k]; let tip = ''; try { tip = d.tip('#', {status:{}, hero:true, passive:{}}); } catch(e){}
      R.status[k] = {icon: str(SVG[d.icon]), tip, flag: !!d.flag, name: (STATUS_LABEL && STATUS_LABEL[k]) || k}; }
    for(const k in ATK_SVG) R.atk[k] = ATK_SVG[k](1.4);
    for(const k in BIOMES){ const b = BIOMES[k]; R.biomes[k] = {name: b.name, sub: b.sub || b.desc || '', color: b.color || b.accent || '#fff'}; }
    for(const k in AFFIXES){ const a = AFFIXES[k]; R.affixes[k] = {name: a.name, desc: a.desc || ''}; }
    R.biome_bg = {};
    for(const k in BIOME_BG){ try { R.biome_bg[k] = '<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="470" viewBox="0 0 1280 470">' + BIOME_BG[k]() + '</svg>'; } catch(e){} }
    R.gem_fx = {};
    for(const k in GEM_TYPES){ const g = GEM_TYPES[k]; R.gem_fx[k] = [1,2,3,4,5].map(t => { try { return typeof g.fx === 'function' ? g.fx(t) : (g.fx || g.desc || ''); } catch(e){ return ''; } }); }
    return JSON.stringify(R);
  })()`);
  fs.writeFileSync(out, r); console.log('ui ok', r.length); process.exit(0);
}, 800);
