// Lädt die HTML-Version in jsdom und exportiert alle Spieldaten als JSON.
// Funktionen werden als {"__fn": "<quelltext>"} gespeichert (für die manuelle Übersetzung).
const fs = require('fs');
const { JSDOM, VirtualConsole } = require('jsdom');
const src = process.argv[2], out = process.argv[3];
let html = fs.readFileSync(src, 'utf8');
html = html.replace(/<script src="https:\/\/unpkg[^>]*><\/script>/, '<script>window.Peer=function(){};</script>');
const NAMES = (process.argv[4] || '').split(',').filter(Boolean);
const dumpScript = `<script>
window.__dump = (function(){
  const names = ${JSON.stringify(NAMES)};
  const seen = new WeakSet();
  const conv = v => {
    if (typeof v === 'function') return {__fn: v.toString()};
    if (v && typeof v === 'object') {
      if (v.nodeType) return {__dom: true};
      if (Array.isArray(v)) return v.map(conv);
      const o = {}; for (const k of Object.keys(v)) o[k] = conv(v[k]); return o;
    }
    return v;
  };
  const r = {};
  for (const n of names) { try { r[n] = conv(eval(n)); } catch(e) { r[n] = {__err: String(e)}; } }
  return JSON.stringify(r, null, 1);
})();
</script>`;
html = html.replace(/<\/body>/, dumpScript + '</body>');
const vc = new VirtualConsole(); vc.on('jsdomError', e => console.error('JSDOM', e.message.slice(0, 200)));
const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: vc });
setTimeout(() => {
  const d = dom.window.__dump;
  if (!d) { console.error('no dump'); process.exit(1); }
  fs.writeFileSync(out, d); console.log('ok', d.length); process.exit(0);
}, 500);
