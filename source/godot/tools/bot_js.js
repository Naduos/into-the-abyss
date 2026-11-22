// Paritäts-Bot: spielt die ECHTE HTML-Version headless und protokolliert den Zustand nach jeder Aktion.
// Aufruf: node bot_js.js game.html seed party(kommagetrennt) specIdx maxSteps out.txt
const fs = require('fs');
const { JSDOM, VirtualConsole } = require('jsdom');
const [,, file, seedS, partyS, specIdxS, maxStepsS, out] = process.argv;
let html = fs.readFileSync(file, 'utf8').replace(/<script src="https:\/\/unpkg[^>]*><\/script>/, '');
const vc = new VirtualConsole(); vc.on('jsdomError', e => { if(!/Not implemented/.test(e.message)) console.error('JSDOM', e.message.slice(0, 300)); });
const dom = new JSDOM(html, { runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: vc });
const w = dom.window;
const BOT = fs.readFileSync(__dirname + '/bot_logic.js', 'utf8');
setTimeout(async () => {
  w.eval(BOT);
  w.eval('OPT.speed = 1e7; hideTitle && hideTitle(); postFlow = function(){};');
  const lines = [];
  const party = partyS.split(',');
  w.eval(`dispatch({t:'start', seed:${+seedS}, roles:Object.fromEntries(${JSON.stringify(party)}.map(id => [id,'host'])), party:${JSON.stringify(party)}, mode:'solo'})`);
  const idle = async () => { for(let i = 0; i < 20000; i++){ if(!w.eval('busy()')) return; await new Promise(r => setTimeout(r, 0)); } throw new Error('queue stuck'); };
  await idle();
  lines.push('0 start ' + w.eval('botDigest()'));
  const maxSteps = +maxStepsS;
  for(let step = 1; step <= maxSteps; step++){
    const a = w.eval(`JSON.stringify(botStep(${+specIdxS}))`);
    if(a === 'null') { lines.push(step + ' END ' + w.eval('S.phase')); break; }
    w.eval(`botApply(${a})`);
    await idle();
    lines.push(step + ' ' + a + ' ' + w.eval('botDigest()'));
  }
  fs.writeFileSync(out, lines.join('\n') + '\n');
  console.log('js steps', lines.length, 'last phase', w.eval('S.phase'), 'room', w.eval('S.room'));
  process.exit(0);
}, 800);
