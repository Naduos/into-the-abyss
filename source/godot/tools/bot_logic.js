// Bot-Logik für den Paritätstest (die Godot-Version in tests/bot.gd ist identisch aufgebaut).
// Entscheidungen hängen NUR vom Spielzustand ab, nie vom Zufall. (Stand 22.11.2026: inkl. Biom-Auswahl)
var BOTSTATE = {stuck: {}};
function botNum(v){ return typeof v === 'number' ? Math.round(v * 1000) / 1000 : v; }
function botSortObj(o){ const r = {}; Object.keys(o || {}).sort().forEach(k => { const v = o[k]; if(typeof v === 'number' || typeof v === 'boolean') r[k] = botNum(v); }); return r; }
function botDigest(){
  const H = heroList().map(h => [h.id, h.hp, h.block, h.energy, h.dead ? 1 : 0, h.gold, h.hand.map(c => c.key + (c.tmp ? '*' : '')).join('|'),
    h.draw.length, h.discard.length, (h.vanished || []).length, h.deck.length, h.gems.length, botSortObj(h.status), h.spec || '', h.sanity ?? 30, h.corruption || 0]);
  const E = (S.enemies || []).map(e => [e.key, e.hp, e.maxHp, e.block, e.dead ? 1 : 0, botSortObj(e.status), e.intent ? (e.intent.name || '') : '', e.intent && e.intent.dmg ? e.intent.dmg : 0]);
  return JSON.stringify({p:S.phase, r:S.room || 0, t:S.round || 0, uid, H, E, m:(S.mapOpts || []).join(',')});
}
function botStep(specIdx){
  const ph = S.phase;
  if(ph === 'formation'){                                       // Wartebank -> erster freier Platz, dann bestätigen
    const o = S.formation.slice(), bench = S.party.filter(id => !o.includes(id));
    if(bench.length){ o[o.indexOf(null)] = bench[0]; return {t:'formation', h:S.party[0], order:o}; }
    return {t:'fready', h:S.party[0]};
  }
  if(ph === 'spec'){
    for(const id of S.party){ const h = S.heroes[id]; if(!h.spec){ const L = SPECS[id]; return {t:'spec', h:id, spec:L[specIdx % L.length].id}; } }
    return null;
  }
  if(ph === 'hero'){
    for(const h of heroList()){
      if(h.dead || h.turnDone) continue;
      for(let i = 0; i < h.hand.length; i++){
        const c = h.hand[i], d = CARDS[c.key], s = stats(c);
        if(d.unplayable || s.cost > h.energy || s.depthCost > (h.status.depth || 0) || lacksSanity(h, s)) continue;
        if(BOTSTATE.stuck[c.id]) continue;
        let target = null;
        if(needsTarget(s)){ const al = alive(); if(!al.length) continue; let best = al[0]; for(const e of al) if(e.hp < best.hp) best = e; target = best.id; }
        return {t:'play', h:h.id, card:c.id, target};
      }
      return {t:'end', h:h.id};
    }
    return null;
  }
  if(ph === 'post'){
    for(const id of S.party){
      const p = S.post[id]; if(!p || p.ready) continue;
      if(p.kind === 'reward' && !p.picked) return {t:'pick', h:id, key:p.cards[0] || null};
      if(p.kind === 'camp' && !p.restDone && !p.campDone) return {t:'rest', h:id};
      if(p.kind === 'camp' && !p.campDone) return {t:'campdone', h:id};
      return {t:'ready', h:id};
    }
    return null;
  }
  if(ph === 'biome') return {t:'biomego', h:S.party[0]};
  if(ph === 'map') return {t:'room', type:S.mapOpts[0]};
  if(ph === 'event') return {t:'ev', op:'leave'};
  return null;
}
function botApply(a){
  if(a.t === 'play'){
    const h = S.heroes[a.h]; const before = h.energy + ':' + h.hand.length;
    BOTSTATE.last = {id:a.card, h:a.h, before};
  } else BOTSTATE.last = null;
  dispatch(a);
}
// nach der Aktion prüfen, ob eine Karte nicht spielbar war (dann nicht nochmal versuchen)
const _botDigest = botDigest;
botDigest = function(){
  const L = BOTSTATE.last;
  if(L){ const h = S.heroes[L.h]; if(h && h.energy + ':' + h.hand.length === L.before && h.hand.some(c => c.id === L.id)) BOTSTATE.stuck[L.id] = true; BOTSTATE.last = null; }
  return _botDigest();
};
