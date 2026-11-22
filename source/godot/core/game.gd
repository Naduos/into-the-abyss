## =====================================================================
## Into the Abyss – Spiel-Engine (1:1-Port der Browser-Version)
## Ohne Grafik: Die Oberfläche hängt sich über das Signal "fx" ein und
## übernimmt über "presenter" die Wartezeiten (sleep). Headless läuft alles sofort.
## Automatisch zusammengesetzt aus core/parts/*.gd – dort bearbeiten! (Stand 22.11.2026, Biom-Umbau + Auto-Update)
## =====================================================================
class_name Game
extends RefCounted

signal fx(kind: String, data: Dictionary)

## Spielversion (aus res://version.json, wird von tools/release.sh hochgezählt).
## Koop: Host und Gäste müssen dieselbe Version haben, sonst laufen die Spiele auseinander.
static func game_version() -> int:
	var f := FileAccess.open("res://version.json", FileAccess.READ)
	if f == null: return 0
	var v = JSON.parse_string(f.get_as_text())
	return int(v.get("version", 0)) if typeof(v) == TYPE_DICTIONARY else 0
static func version_mismatch_text(host_v: int) -> String:
	if host_v == game_version(): return ""
	if host_v > game_version(): return "Der Host hat Version %d, du hast %d. Bitte das Spiel neu starten, dann wird automatisch aktualisiert." % [host_v, game_version()]
	return "Der Host hat die ältere Version %d (du: %d). Der Host muss das Spiel neu starten, um zu aktualisieren." % [host_v, game_version()]

# ---------- Konstanten (wie in der HTML) ----------
const HAND_SIZE := 4
const MAX_ENERGY := 5
const MAX_SAVED_ENERGY := 10
const HEAL_AFTER_FIGHT := 10
const WEAK_MULT := 0.5
const ENEMY_HP_MULT := 1.75
const ELITE_FROM := 4
const REMOVE_COST := 100
const MIN_DECK := 10
const CAMP_EVERY := 5
const CAMP_HEAL := 0.3
const REVIVE_HP := 0.25
const FOIL_CHANCE := 0.03
const FLEET_MULT := 2
const FLEET_CHANCE := 0.3
const VAMPIRE_CAP := 10
const SURGE_MULT := 1.5
const POWER_DMG := 4
const FURY_NEED := 5
const GUARD_PCT := 0.1
const GUARD_MAX := 0.5
const VULN_MULT := 1.5
const ICE_NORMAL := 10
const ICE_BOSS := 20
const SERVANT_MAX := 5
const SANITY_MAX := 30
const NIGHTMARE_PCT := 0.2
const NIGHTMARE_BOSS_PCT := 0.1
const DREAM_MAX := 10
const SHIFT_LIMIT := 10
const ROOMS_PER_RUN := 60
const BOSS_EVERY := 15
const SUPPORT_CHANCE := 0.12
const SPEC_GEM_CHANCE := 0.2
const EVENT_TYPES := ["forge", "arena", "anomaly", "buddy", "campfire"]
const HERO_CONDS := ["block", "thorns", "lowHp", "invis", "gold100", "afterAttack", "afterSkill", "momentum"]
const HERO_DEBUFFS := [["poison", "poison"], ["burn", "burn"], ["weak", "weak"], ["brittle", "vulnerable"], ["drained", "weak"]]
const STAT_KEYS := ["dmg", "heal", "block", "debuff", "buff"]
const GIFT_BY_SPEC := {"acolyte": "giftvoid", "dreamweaver": "giftdreams", "tidecaller": "gifttide"}

# ---------- Daten ----------
var D: Dictionary
var CARDS: Dictionary
var GEM_TYPES: Dictionary
var GEM_ORDER: Array
var RARITY: Dictionary
var RARITY_ORDER: Array
var STATUS: Dictionary
var SERVANTS: Dictionary

# ---------- Zustand ----------
var r := Rng.new()
var uid := 1
var S := {}
var Q: Array = []
var q_running := false
var presenter = null          # UI-Objekt mit "sleep(ms)" (Coroutine); null = headless
var my_role := "host"         # 'host', 'g1', 'g2', 'g3' (wird vom Netzwerk gesetzt)
var net = null                # Netzwerk-Objekt mit host_commit(a) / send_request(a)

func _init() -> void:
	DB.ensure()
	D = DB.D
	CARDS = D["CARDS"].duplicate(true)          # eigene Kopie: Buddy-Karten werden zur Laufzeit ergänzt
	GEM_TYPES = D["GEM_TYPES"]
	GEM_ORDER = D["GEM_ORDER"]
	RARITY = D["RARITY"]
	RARITY_ORDER = D["RARITY_ORDER"]
	STATUS = D["STATUS"]
	SERVANTS = D["SERVANTS"]
	for id in D.get("BE", {}):                       # Biom-Elites: eigene KI-Schlüssel
		var el: Dictionary = D["BE"][id]
		if T(el.get("parts")):
			for p in el["parts"]: p["aiKey"] = "el_" + p["key"]
		else: el["aiKey"] = "el_" + id
	S = {"runId": 0, "paused": false, "runActive": false, "mode": "solo", "roles": {"knight": "host", "mage": "host"},
		"fight": 0, "round": 0, "phase": "idle", "active": null, "heroes": {}, "enemies": [], "eliteBag": [], "elitesBeaten": 0,
		"post": {}, "selected": null, "selKind": null, "uiHero": null, "waiting": false}

# ---------- kleine JS-Helfer ----------
static func T(v) -> bool: return JS.T(v)
static func nz(d: Dictionary, k: String): return JS.n(d, k)
## "d.k || def"
static func orv(d: Dictionary, k: String, def):
	var v = d.get(k)
	return v if JS.T(v) else def
## [].concat(x || [])
static func as_list(v) -> Array:
	if v == null or (typeof(v) == TYPE_BOOL and not v): return []
	if typeof(v) == TYPE_ARRAY: return v
	return [v]
static func st(u: Dictionary, k: String):
	return JS.n(u["status"], k)
func rng() -> float: return r.next()
func rand(a: int, b: int) -> int: return r.rand(a, b)
func pick(a: Array): return r.pick(a)
func shuffle(a: Array) -> Array: return r.shuffle(a)
func new_card(key: String) -> Dictionary:
	var c := {"id": uid, "key": key, "gems": []}
	uid += 1
	return c
func roll_foil() -> bool: return rng() < FOIL_CHANCE

# ---------- Präsentation (headless = nichts) ----------
func sleep(ms: float) -> void:
	if presenter == null: return
	await presenter.sleep(ms)
func float_text(u: Dictionary, text: String, cls: String) -> void: fx.emit("float", {"u": u, "text": text, "cls": cls})
func retrigger(u, cls: String) -> void: fx.emit("retrigger", {"u": u, "cls": cls})
func slash_fx(u: Dictionary) -> void: fx.emit("slash", {"u": u})
func toast(text: String) -> void: fx.emit("toast", {"text": text})
func update_unit(u: Dictionary) -> void: fx.emit("unit", {"u": u})
func render_hand(new_ids: Array = []) -> void: fx.emit("hand", {"new": new_ids})
func refresh_ui() -> void: fx.emit("refresh", {})
func update_counters() -> void: fx.emit("counters", {})
func soul_beam(a, b, color: String, big := false) -> void: fx.emit("beam", {"a": a, "b": b, "color": color, "big": big})
func banner(text: String, sub := "", ms := 850) -> void:
	fx.emit("banner", {"text": text, "sub": sub, "ms": ms})
	await sleep(ms)

# ---------- Zugriff ----------
func party_dmg_mult() -> float:
	return float(D["PARTY_DMG"].get(str(S.get("party", []).size()), 1))
func party_hp_mult() -> float:
	return float(D["PARTY_HP"].get(str(S.get("party", []).size()), 1))
func mine(id) -> bool: return S["roles"].get(id) == my_role
func hero_list() -> Array:
	var out := []
	for id in S.get("party", []):
		if S["heroes"].has(id): out.append(S["heroes"][id])
	return out
func living() -> Array: return hero_list().filter(func(h): return not h["dead"])
func alive() -> Array: return S["enemies"].filter(func(e): return not e["dead"])
func rearmost() -> Variant:
	var a := alive()
	return a[a.size() - 1] if a.size() else null
func active_hero() -> Variant:
	return S["heroes"].get(S["active"]) if S["active"] != null else null
func all_heroes_dead() -> bool: return living().is_empty()
# ---------- Formation: wer steht vorne? (für Gegner-/Klassenmechaniken) ----------
func formation_order() -> Array:                         # vorne -> hinten; noch nicht platzierte Helden hinten dran
	var f: Array = (S.get("formation", []) if S.get("formation") != null else []).filter(func(id): return T(id) and S.get("heroes", {}).has(id))
	return f + S.get("party", []).filter(func(id): return not f.has(id) and S.get("heroes", {}).has(id))
func hero_pos(h: Dictionary) -> int: return formation_order().find(h["id"])      # 0 = ganz vorne
func formation_living() -> Array:
	return formation_order().map(func(id): return S["heroes"][id]).filter(func(h): return not h["dead"])
func front_hero() -> Variant:
	var l := formation_living()
	return l[0] if l.size() else null
func back_hero() -> Variant:
	var l := formation_living()
	return l[l.size() - 1] if l.size() else null
func spec_of(hero_id: String, spec_id) -> Variant:
	for x in D["SPECS"].get(hero_id, []):
		if x["id"] == spec_id: return x
	return null
func slots_of(rarity: String) -> int: return RARITY_ORDER.find(rarity) + 1
func gem_fits(t: String, tier: int) -> bool:
	var g: Dictionary = GEM_TYPES[t]
	return g["minTier"] <= tier and (not T(g.get("maxTier")) or g["maxTier"] >= tier)
func is_foil(c: Dictionary) -> bool:
	if T(c.get("foil")): return true
	for g in c.get("gems", []):
		if g["type"] == "foilgem": return true
	return false
func gem_rarity(g: Dictionary) -> String: return "rare" if T(g.get("rune")) else RARITY_ORDER[g["tier"] - 1]
func gem_title(g: Dictionary) -> String:
	if T(g.get("rune")): return D["RUNE_TYPES"][g["type"]]["name"]
	return "%s %s%s Gem" % [RARITY[gem_rarity(g)]["name"], "Fleeting " if T(g.get("fleeting")) else "", GEM_TYPES[g["type"]]["name"]]
func hero_of_card(c: Dictionary) -> Variant:
	for h in hero_list():
		for x in h["deck"]:
			if x["id"] == c["id"]: return h
		for x in h["hand"]:
			if x["id"] == c["id"]: return h
	return null
func runes_in_deck(h: Dictionary) -> int:
	return h["deck"].filter(func(c): return T(c.get("rune"))).size()
func in_combat() -> bool:
	return S["phase"] in ["hero", "enemy", "fight", "won"] and S.get("enemies", []).size() > 0
func active_links() -> int:
	return S["links"].size() if in_combat() and S.get("links") != null else 0
func corruption_of() -> int:
	if S.get("heroes", {}).has("eldritch"): return nz(S["heroes"]["eldritch"], "corruption")
	return 0
func corrupt_stage(u: Dictionary) -> int:
	var c: int = nz(u, "corruption")
	return 4 if c >= 100 else 3 if c >= 50 else 2 if c >= 25 else 1 if c >= 10 else 0

# =====================================================================
#   KARTENWERTE (stats), Upgrades, Foil, Namen (Stand 22.11.2026)
# =====================================================================
func stats(c: Dictionary) -> Dictionary:
	var d: Dictionary = CARDS[c["key"]]
	var s := {"cost": d["cost"], "dmg": nz(d, "dmg"), "hits": orv(d, "hits", 1), "aoe": T(d.get("aoe")), "random": T(d.get("random")),
		"block": nz(d, "block"), "weak": nz(d, "weak"), "vuln": nz(d, "vuln"), "vulnAll": nz(d, "vulnAll"),
		"weakAll": nz(d, "weakAll"), "draw": nz(d, "draw"), "energy": nz(d, "energy"), "poison": nz(d, "poison"), "poisonAll": nz(d, "poisonAll"),
		"burn": nz(d, "burn"), "burnAll": nz(d, "burnAll"), "ice": nz(d, "ice"), "iceAll": nz(d, "iceAll"), "healAll": nz(d, "healAll"), "heal": nz(d, "heal"),
		"leech": 0, "leechCap": 0, "extra": nz(d, "chain"), "repeats": 1,
		"dmgMin": nz(d, "dmgMin"), "dmgMax": nz(d, "dmgMax"), "hitsMin": nz(d, "hitsMin"), "hitsMax": nz(d, "hitsMax"), "selfDmg": nz(d, "selfDmg"), "blockAll": nz(d, "blockAll"),
		"thorns": nz(d, "thorns"), "thornsAll": nz(d, "thornsAll"), "flameArmor": nz(d, "flameArmor"), "frostArmor": nz(d, "frostArmor"), "staticArmor": nz(d, "staticArmor"),
		"blizzard": orv(d, "blizzard", null), "lowHpDouble": T(d.get("lowHpDouble")),
		"crit": T(d.get("crit")), "invis": T(d.get("invis")), "backstab": d["backstab"].duplicate() if T(d.get("backstab")) else null,
		"gold": orv(d, "gold", null), "makeGem": T(d.get("makeGem")), "exhaust": T(d.get("exhaust")) or d["type"] == "buff",
		"buff": orv(d, "buff", null), "buffAll": T(d.get("buffAll")), "execute": T(d.get("execute")),
		"soloMult": nz(d, "soloMult"), "returnOnKill": T(d.get("returnOnKill")), "poisonTrigger": T(d.get("poisonTrigger")), "poisonDouble": T(d.get("poisonDouble")),
		"poisonPop": T(d.get("poisonPop")), "bonusRange": 0,
		"mark": nz(d, "mark"), "markAll": nz(d, "markAll"), "momentum": nz(d, "momentum"), "detonate": nz(d, "detonate"), "detonateAll": nz(d, "detonateAll"),
		"spendMomentum": nz(d, "spendMomentum"), "momentumDouble": T(d.get("momentumDouble")), "createCard": orv(d, "createCard", null),
		"makeRune": T(d.get("makeRune")), "runeScale": nz(d, "runeScale"),
		"spendCrit": orv(d, "spendCrit", null), "momentumSparks": T(d.get("momentumSparks")), "riftFinish": T(d.get("riftFinish")),
		"taunt": T(d.get("taunt")), "guard": nz(d, "guard"), "power": nz(d, "power"), "combo": nz(d, "combo"), "reach": nz(d, "reach"), "fury": nz(d, "fury"),
		"owed": nz(d, "owed"), "consumeOwed": T(d.get("consumeOwed")), "consumePayback": nz(d, "consumePayback"), "cleanseSelf": T(d.get("cleanseSelf")),
		"selfWeak": nz(d, "selfWeak"), "style": orv(d, "style", null),
		"link": nz(d, "link"), "linkResonant": T(d.get("linkResonant")), "imprint": orv(d, "imprint", null), "imprintTimes": orv(d, "imprintTimes", 1),
		"imprintCards": orv(d, "imprintCards", 1), "imprintPerm": T(d.get("imprintPerm")),
		"amplify": T(d.get("amplify")), "linkBlock": nz(d, "linkBlock"), "craft": orv(d, "craft", null),
		"corrupt": nz(d, "corrupt"), "sanity": nz(d, "sanity"), "sanityCost": nz(d, "sanityCost"), "dream": nz(d, "dream"), "dreamStun": nz(d, "dreamStun"), "dreamAll": nz(d, "dreamAll"),
		"bleed": T(d.get("bleed")), "collapse": orv(d, "collapse", null), "spread": nz(d, "spread"),
		"allyDraw": nz(d, "allyDraw"), "dreamDouble": T(d.get("dreamDouble")), "eatAll": orv(d, "eatAll", null), "depthGain": nz(d, "depthGain"),
		"summon": orv(d, "summon", null), "feed": nz(d, "feed"), "sacrifice": orv(d, "sacrifice", null), "fuse": nz(d, "fuse"),
		"depthCost": SERVANTS[d["summon"]]["depth"] if T(d.get("summon")) else 0, "mindStun": false, "leechFlat": 0,
		"resonateAll": T(d.get("resonateAll")), "drawAll": nz(d, "drawAll")}
	if T(c.get("upgraded")): apply_upgrade(s, d)
	if is_foil(c): apply_foil(s, d)
	if T(c.get("rune")):                                                  # Rift Architect: Rune im Runen-Slot
		var t: String = c["rune"]["type"]
		if t == "marking": s.mark += 10
		if t == "flow": s.momentum += 2
		if t == "ruin": s.detonate += 1
		if t == "precision" and T(s.dmg): s.crit = true
		s.runeFx = t
	if T(c.get("tmp")): s.cost = 0; s.exhaust = true                     # Folgekarte: gratis, einmalig
	if s.riftFinish:
		s.riftKey = c["rune"]["type"] if T(c.get("rune")) else "none"
		s.spendMomentum = nz(D["RIFT_FINISH"][s.riftKey], "dmg")
	# Gladiator-Ruhm
	var bd = nz(c, "bonusDmg")
	if T(bd) and T(s.dmg):
		if s.backstab != null: s.backstab = s.backstab.map(func(v): return v + bd)
		s.dmg += bd
		if T(s.dmgMax): s.dmgMin += bd; s.dmgMax += bd
	if T(d.get("blockStrike")): s.blockStrike = true; s.dmg += 1
	if T(c.get("bonusBlock")) and T(s.block): s.block += c["bonusBlock"]
	if T(c.get("bonus")):
		for k in c["bonus"]:
			if T(s.get(k)): s[k] += c["bonus"][k]
	for g in c["gems"]:
		var t: int = g["tier"]
		var f: int = FLEET_MULT if T(g.get("fleeting")) else 1
		if T(g.get("fleeting")): s.exhaust = true
		match g["type"]:
			"poison": s.poison += t * f
			"damage":
				s.dmg += t * f
				if T(s.dmgMax): s.dmgMax += 2 * t * f
				if s.backstab != null: s.backstab = s.backstab.map(func(v): return v + t * f)
			"lightning": s.bonusRange += (2 * t - 1) * f
			"protection": s.block += t * f
			"knowledge": s.draw += (t - 1) * f
			"radius": s.extra += (t - 2) * f
			"cuts": s.repeats += (t - 3) * f; s.cost += 1
			"infinite": s.cost -= f
			"energy": s.energy += f
			"vampire": s.leech += (t - 1) * f; s.leechCap += VAMPIRE_CAP * f
			"burn": s.burn += t * f
			"ice": s.ice += (t - 1) * f
			_:
				if GEM_TYPES.has(g["type"]) and T(GEM_TYPES[g["type"]].get("spec")): apply_spec_gem(s, g["type"], t, f)
	# Soulbinder
	if T(d.get("perLink")): s.dmg += d["perLink"] * active_links()
	if T(d.get("perLinkBlock")): s.blockAll += d["perLinkBlock"] * active_links()
	if T(d.get("perImprint")): s.dmg += d["perImprint"] * team_imprints()
	if T(d.get("perImprintBlock")): s.block += d["perImprintBlock"] * team_imprints()
	if T(c.get("imprints")):
		for x in c["imprints"]:
			if x["type"] == "edge" and T(s.dmg):
				s.dmg += x["n"]
				if T(s.dmgMax): s.dmgMin += x["n"]; s.dmgMax += x["n"]
				if s.backstab != null: s.backstab = s.backstab.map(func(v): return v + x["n"])
			if x["type"] == "ward": s.block += x["n"]
			if x["type"] == "haste": s.cost -= x["n"]
			if x["type"] == "mend": s.heal += x["n"]
			if x["type"] == "echo": s.repeats += 1
	apply_tiers(s, d)                                                     # Eldritch: Corruption-Stufen
	if in_combat() and S["heroes"].has("eldritch"):
		var eh: Dictionary = S["heroes"]["eldritch"]
		var sv: int = eh.get("servants", []).size()
		if T(d.get("perDepth")): s.dmg += d["perDepth"] * st(eh, "depth")
		if T(d.get("perServant")): s.dmg += d["perServant"] * sv
		if T(d.get("perServantBlock")): s.block += d["perServantBlock"] * sv
	if T(c.get("resonant")) and T(c.get("link")):
		var m := func(v): return JS.rnd(v * SURGE_MULT)
		s.dmg = m.call(s.dmg); s.block = m.call(s.block); s.blockAll = m.call(s.blockAll); s.heal = m.call(s.heal); s.healAll = m.call(s.healAll)
		if T(s.dmgMax): s.dmgMin = m.call(s.dmgMin); s.dmgMax = m.call(s.dmgMax)
		if s.backstab != null: s.backstab = s.backstab.map(m)
		s.surge = true
	if T(d.get("punchCard")):                                             # Knockout Punch: Werte inkl. Edelsteine gelten für den Fury-Schlag
		s.punchDmg = s.dmg; s.punchHits = s.hits; s.punchRange = s.bonusRange
		s.punchExtra = s.extra; s.punchRepeats = s.repeats; s.punchLeech = s.leech; s.punchLeechCap = s.leechCap; s.repeats = 1; s.leechCap = 0
		s.punchFx = {"poison": s.poison, "burn": s.burn, "weak": s.weak, "vuln": s.vuln, "ice": s.ice}
		s.dmg = 0; s.hits = 1; s.aoe = false; s.random = false; s.crit = false
		s.poison = 0; s.burn = 0; s.weak = 0; s.vuln = 0; s.ice = 0
		s.bonusRange = 0; s.extra = 0; s.leech = 0; s.dmgMin = 0; s.dmgMax = 0
	s.cost = maxi(0, s.cost)
	if T(c.get("replayTax")) and in_combat(): s.cost += c["replayTax"]; s["replayTax"] = c["replayTax"]   # erneut gezogen
	return s

func sanity_of(h: Dictionary) -> int: return h["sanity"] if h.get("sanity") != null else SANITY_MAX
func lacks_sanity(h: Dictionary, s: Dictionary) -> bool: return s.sanityCost > 0 and s.sanityCost > sanity_of(h)
func needs_target(s: Dictionary) -> bool:
	return (T(s.dmg) and not s.aoe and not s.random) or ((T(s.weak) or T(s.burn) or T(s.ice) or T(s.poison) or T(s.vuln) or s.poisonDouble or T(s.mark) or T(s.detonate) or T(s.owed) or s.get("runeFx") == "siphon" or T(s.dream) or T(s.collapse) or T(s.spread) or s.dreamDouble or s.mindStun) and not s.aoe and not T(s.dmg))
func hero_targetable(d: Dictionary) -> bool:
	return not T(d.get("selfOnly")) and (T(d.get("allyTarget")) or (not T(d.get("dmg")) and not T(d.get("blockAll")) and not T(d.get("healAll")) and (T(d.get("block")) or T(d.get("heal")))))

# ---------- Upgrades ----------
static func up_val(v) -> int: return maxi(v + 1, JS.rnd(v * 1.25))
func upgrade_kind(d: Dictionary) -> Variant:
	if d["type"] == "curse" or T(d.get("unplayable")) or T(d.get("custom")): return null
	if d["cost"] >= 5: return "cost"
	for k in D["UP_STATS"]:
		var v = d.get(k)
		if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and v > 0: return "stats"
	if T(d.get("backstab")) or T(d.get("blizzard")): return "stats"
	if T(d.get("draw")) or T(d.get("energy")): return "extra"
	if T(d.get("buff")) and not (STATUS.has(d["buff"]["key"]) and T(STATUS[d["buff"]["key"]].get("flag"))): return "extra"
	return "cost" if d["cost"] >= 1 else null
func can_upgrade(c: Dictionary) -> bool: return not T(c.get("upgraded")) and upgrade_kind(CARDS[c["key"]]) != null
func apply_upgrade(s: Dictionary, d: Dictionary) -> void:
	var kind = upgrade_kind(d)
	if kind == "cost": s.cost = maxi(0, s.cost - 1); return
	if kind == "extra":
		if T(s.draw): s.draw += 1
		elif T(s.energy): s.energy += 2
		if s.buff != null:
			s.buff = s.buff.duplicate(); s.buff["n"] = up_val(s.buff["n"])
		return
	if kind != "stats": return
	for k in D["UP_STATS"]:
		if T(s.get(k)): s[k] = up_val(s[k])
	if s.backstab != null: s.backstab = s.backstab.map(func(v): return up_val(v))
	if T(d.get("blizzard")):
		s.blizzard = d["blizzard"].duplicate()
		s.blizzard["dmg"] = up_val(nz(d["blizzard"], "dmg")); s.blizzard["ice"] = up_val(nz(d["blizzard"], "ice"))
func apply_foil(s: Dictionary, _d: Dictionary) -> void:
	var f := func(v): return maxi(v + 1, JS.rnd(v * 1.5))
	var any := false
	for k in D["UP_STATS"]:
		var v = s.get(k)
		if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and v > 0: s[k] = f.call(v); any = true
	if s.backstab != null: s.backstab = s.backstab.map(f); any = true
	if s.blizzard != null:
		var b: Dictionary = s.blizzard.duplicate()
		b["dmg"] = f.call(nz(s.blizzard, "dmg")); b["ice"] = f.call(nz(s.blizzard, "ice")); s.blizzard = b; any = true
	if s.buff != null:
		s.buff = s.buff.duplicate(); s.buff["n"] = JS.cel(s.buff["n"] * 1.5); any = true
	if not any or T(s.draw): s.draw = JS.cel(s.draw * 1.5) if T(s.draw) else s.draw
	if not any and T(s.energy): s.energy = JS.cel(s.energy * 1.5)

func card_name(c: Dictionary) -> String: return base_card_name(c) + ("+" if T(c.get("upgraded")) else "")
func base_card_name(c: Dictionary) -> String:
	var d: Dictionary = CARDS[c["key"]]
	var types := []
	for g in c["gems"]:
		if not types.has(g["type"]): types.append(g["type"])
	JS.jsort(types, func(a, b): return GEM_ORDER.find(a) - GEM_ORDER.find(b))
	if types.is_empty(): return d["name"]
	var adj := func(t): return GEM_TYPES[t]["adj"]
	if types.size() == 1: return "%s %s" % [adj.call(types[0]), d["name"]]
	var PN: Dictionary = D["PAIR_NAMES"]
	var pair = PN.get(types[0] + "+" + types[1], PN.get(types[1] + "+" + types[0], "%s %s" % [adj.call(types[0]), adj.call(types[1])]))
	if types.size() == 2: return "%s %s" % [pair, d["name"]]
	if types.size() == 3: return "%s %s %s" % [adj.call(types[2]), pair, d["name"]]
	return "%s %s %s" % ["Mythic" if types.size() == 4 else "Godforged", pair, d["name"]]

# ---------- Bedingungen ----------
func cond_target(key: String, t) -> bool:
	if t == null or t["dead"]: return false
	var stt: Dictionary = t.get("status", {})
	var ice: bool = nz(stt, "ice") > 0 or T(t.get("frozen"))
	match key:
		"burning": return nz(stt, "burn") > 0
		"frozen": return T(t.get("frozen"))
		"iced": return ice
		"burnIce": return nz(stt, "burn") > 0 and ice
		"poisoned": return nz(stt, "poison") > 0
		"vulnerable": return nz(stt, "vulnerable") > 0
		"weakened": return nz(stt, "weak") > 0
		"marked": return nz(stt, "mark") > 0
		"marked3": return nz(stt, "mark") >= 15
	return false

# =====================================================================
#   AKTIONEN & WARTESCHLANGE (Lockstep: alle Geräte führen dieselben Aktionen aus) – Stand 22.11.2026
# =====================================================================
func enqueue(a: Dictionary) -> void:
	if a.get("t") == "start": S["runId"] += 1; Q.clear(); q_running = false
	Q.append(a)
	if not q_running: run_queue()

func run_queue() -> void:
	q_running = true
	var run = S["runId"]
	refresh_ui()
	while Q.size() and S["runId"] == run:
		var a: Dictionary = Q.pop_front()
		await execute(a)
		S["waiting"] = false
		refresh_ui()
	if S["runId"] == run:
		q_running = false
		refresh_ui()
		fx.emit("postflow", {})

func busy() -> bool: return q_running or S["waiting"]

func dispatch(a: Dictionary) -> void:
	if S["mode"] == "solo": enqueue(a); return
	if S["mode"] == "host": net.host_commit(a); return
	S["waiting"] = true; refresh_ui()
	net.send_request(a)

func execute(a: Dictionary) -> void:
	var h = S["heroes"].get(a["h"]) if T(a.get("h")) else null
	match a["t"]:
		"start": start_run(a)
		"tolobby": fx.emit("tolobby", {})
		"play":
			if S["phase"] != "hero" or h == null or h["dead"] or T(h.get("turnDone")): return
			var i := -1
			for k in h["hand"].size():
				if h["hand"][k]["id"] == a["card"]: i = k; break
			if i < 0: return
			var c: Dictionary = h["hand"][i]
			var s := stats(c)
			if T(CARDS[c["key"]].get("unplayable")) or s.cost > h["energy"] or s.depthCost > st(h, "depth") or lacks_sanity(h, s): return
			var target = null
			if T(a.get("target")):
				for e in S["enemies"]:
					if e["id"] == a["target"]: target = e; break
				if target == null: target = S["heroes"].get(a["target"])
			if target != null and not T(target.get("hero")) and not T(target["status"].get("etaunt")) and T(s.dmg):   # Gegner-Taunt
				for o in alive():
					if T(o["status"].get("etaunt")) and not T(o["status"].get("intangible")): target = o; float_text(o, "Taunted!", "dmg"); break
			S["playOpt"] = a.get("opt")
			S["playPick"] = a.get("pick")
			S["playReplace"] = a.get("replace")
			await play_card(h, i, target)
		"end":
			if S["phase"] == "hero" and h != null and not T(h.get("turnDone")): await end_hero_turn(h)
		"pick":
			var p = S["post"].get(a["h"])
			if p == null or p["picked"]: return
			p["picked"] = true
			if T(a.get("key")) and p["cards"].has(a["key"]):
				var nc := new_card(a["key"])
				if T(p.get("foils")) and p["foils"][p["cards"].find(a["key"])]: nc["foil"] = true
				h["deck"].append(nc)
				toast("%s added %s%s" % [h["name"], "FOIL " if T(nc.get("foil")) else "", CARDS[a["key"]]["name"]])
			else:
				h["rerolls"] += 1
				toast("%s skipped and got a Reroll Token" % h["name"])
		"reroll":
			var p = S["post"].get(a["h"])
			if p == null or p["picked"] or h["rerolls"] < 1: return
			h["rerolls"] -= 1
			p["cards"] = reward_choices(h["id"])
			p["foils"] = p["cards"].map(func(_k): return roll_foil())
		"fuse":
			var ids: Array = a.get("gems", [])
			var gs := []
			for id in ids:
				var found = null
				for g in h["gems"]:
					if g["id"] == id: found = g; break
				gs.append(found)
			var uniq := {}
			for id in ids: uniq[id] = true
			if gs.size() != 3 or gs.has(null) or uniq.size() != 3: return
			var tier: int = gs[0]["tier"]
			if tier >= 5: return
			for g in gs:
				if g["tier"] != tier or T(g.get("rune")): return
			h["gems"] = h["gems"].filter(func(g): return not JS.has(gs, g))
			var types := GEM_ORDER.filter(func(t): return gem_fits(t, tier + 1))
			var nt: String = pick(types)
			var ng := {"id": uid, "type": nt, "tier": tier + 1, "fleeting": not T(GEM_TYPES[nt].get("noFleet")) and rng() < FLEET_CHANCE}
			uid += 1
			h["gems"].append(ng)
			var p = S["post"].get(a["h"])
			if p != null: p["lastFused"] = ng["id"]
			toast("%s fused 3 gems into a %s!" % [h["name"], gem_title(ng)])
		"socket":
			var c = _find_by_id(h["deck"], a["card"])
			var g = _find_by_id(h["gems"], a["gem"])
			if c == null or g == null or can_socket(c, g) != "": return
			if T(g.get("rune")): c["rune"] = g
			else: c["gems"].append(g)
			h["gems"] = JS.without(h["gems"], g)
		"remove":
			var p = S["post"].get(a["h"])
			var c = _find_by_id(h["deck"], a["card"])
			if p == null or T(p.get("removed")) or c == null or h["gold"] < REMOVE_COST or h["deck"].size() <= MIN_DECK: return
			h["deck"] = JS.without(h["deck"], c); h["gold"] -= REMOVE_COST; p["removed"] = true
		"rest":
			var p = S["post"].get(a["h"])
			if p == null or p["kind"] != "camp" or _camp_used(p): return
			p["restDone"] = true; heal(h, JS.rnd(h["maxHp"] * CAMP_HEAL))
		"unsocket":
			var p = S["post"].get(a["h"])
			if p == null or p["kind"] != "camp" or T(p.get("unsocketDone")) or T(p.get("restDone")) or T(p.get("upgradeDone")) or T(p.get("campDone")): return
			var c = _find_by_id(h["deck"], a["card"])
			var g = _find_by_id(c["gems"], a["gem"]) if c != null else null
			if g == null: return
			c["gems"] = JS.without(c["gems"], g); h["gems"].append(g); p["unsocketDone"] = true
		"campup":
			var p = S["post"].get(a["h"])
			if p == null or p["kind"] != "camp" or _camp_used(p): return
			var c = _find_by_id(h["deck"], a["card"])
			if c == null or not can_upgrade(c): return
			c["upgraded"] = true; p["upgradeDone"] = true
			toast("%s upgraded %s" % [h["name"], card_name(c)])
		"campdone":
			var p = S["post"].get(a["h"])
			if p != null and p["kind"] == "camp": p["campDone"] = true
		"buy":
			var p = S["post"].get(a["h"])
			if p == null or p["kind"] != "shop": return
			var lst: Array = p["shop"]["cards"] if a.get("kind") == "card" else p["shop"]["gems"]
			var idx: int = a.get("idx", -1)
			if idx < 0 or idx >= lst.size(): return
			var item: Dictionary = lst[idx]
			if item["sold"] or h["gold"] < item["price"]: return
			h["gold"] -= item["price"]; item["sold"] = true
			if a.get("kind") == "card":
				var nc := new_card(item["key"])
				if T(item.get("foil")): nc["foil"] = true
				h["deck"].append(nc)
				toast("%s bought %s%s" % [h["name"], "FOIL " if T(nc.get("foil")) else "", CARDS[item["key"]]["name"]])
			else:
				h["gems"].append(item["gem"])
				toast("%s bought a %s" % [h["name"], gem_title(item["gem"])])
		"sellgem":
			var p = S["post"].get(a["h"])
			if p == null or p["kind"] != "shop": return
			var g = _find_by_id(h["gems"], a["gem"])
			if g == null: return
			h["gems"] = JS.without(h["gems"], g); h["gold"] += sell_price(g)
			toast("%s sold a %s for %d Gold" % [h["name"], gem_title(g), sell_price(g)])
		"biomego":                                         # Biom-Intro bestätigt
			if S["phase"] != "biome": return
			S["biomeFor"] = S["room"]; fx.emit("biomego", {})
			if S["room"] == 0: S["room"] = 1; await start_fight("normal"); return
			enter_map()
		"sendgold":                                        # Gold an Mitspieler: 25 % Steuer
			var to = S["heroes"].get(a.get("to"))
			var n := JS.flr(float(a.get("n", 0)))
			if h == null or to == null or is_same(to, h) or not S["party"].has(a["to"]) or n < 1 or n > h["gold"]: return
			var got: int = n - JS.cel(n * 0.25)
			h["gold"] -= n; to["gold"] += got
			toast("%s sent %d Gold to %s – %d arrived (%d taxes)" % [h["name"], n, to["name"], got, n - got])
			update_counters()
		"room":
			if S["phase"] != "map" or not S["mapOpts"].has(a["type"]): return
			await enter_room(a["type"])
		"ev": await event_action(a)
		"spec":
			if S["phase"] != "spec" or h == null or T(h.get("spec")) or spec_of(a["h"], a["spec"]) == null: return
			h["spec"] = a["spec"]
			h["deck"] = spec_of(a["h"], a["spec"])["starter"].map(func(k): return new_card(k))
			if a["spec"] == "knockout": h["maxHp"] = KO_MAXHP; h["hp"] = KO_MAXHP
			if a["spec"] == "drunkmaster" or a["spec"] == "nightfighter": h["maxHp"] += 8; h["hp"] = h["maxHp"]
			update_unit(h)
			if hero_list().all(func(x): return T(x.get("spec"))):
				if S["party"].size() > 1:                    # alle auf die Wartebank
					S["phase"] = "formation"; S["formation"] = S["party"].map(func(_id): return null); S["formReady"] = {}; return
				S["room"] = 0; S["sinceElite"] = 1
				choose_biome()
		"formation":                                       # neue Reihenfolge (vorne -> hinten)
			if S["phase"] != "formation" or typeof(a.get("order")) != TYPE_ARRAY or a["order"].size() != S["party"].size(): return
			var placed: Array = a["order"].filter(func(id): return T(id))
			var seen := {}
			for id in placed:
				if not S["party"].has(id) or seen.has(id): return
				seen[id] = true
			S["formation"] = a["order"].map(func(id): return id if T(id) else null); S["formReady"] = {}
			fx.emit("formation", {})
		"fready":                                          # Spieler bestätigt die Formation
			if S["phase"] != "formation" or h == null: return
			if not T(a.get("off")) and S["formation"].any(func(x): return not T(x)): return   # erst wenn alle Plätze belegt sind
			var slot = S["roles"][a["h"]]
			S["formReady"][slot] = not T(a.get("off"))
			var slots := []
			for id in S["party"]:
				if not slots.has(S["roles"][id]): slots.append(S["roles"][id])
			if slots.all(func(sl): return T(S["formReady"].get(sl))):
				fx.emit("formation", {}); S["room"] = 0; S["sinceElite"] = 1
				choose_biome()
		"ready":
			var p = S["post"].get(a["h"])
			if p == null or T(p.get("ready")) or S["phase"] != "post": return
			p["ready"] = true
			if hero_list().all(func(x): return T(S["post"][x["id"]].get("ready"))): enter_map()

func _camp_used(p: Dictionary) -> bool:
	return T(p.get("restDone")) or T(p.get("unsocketDone")) or T(p.get("upgradeDone")) or T(p.get("campDone"))
static func _find_by_id(arr: Array, id) -> Variant:
	for x in arr:
		if x["id"] == id: return x
	return null

# =====================================================================
#   KAMPFREGELN
# =====================================================================
func deal_damage(t: Dictionary, amount) -> int:
	amount = affix_dmg(t, amount)
	if amount < 0: return 0
	var hero := T(t.get("hero"))
	if not hero and T(t["status"].get("bulwark")): amount = JS.rnd(amount * (1 - t["status"]["bulwark"] / 100.0))
	if not hero and nz(t["status"], "vulnerable"): amount = JS.flr(amount * VULN_MULT)
	if not hero and nz(t["status"], "dream") >= 7: amount = JS.flr(amount * 1.25)
	if not hero and T(t.get("passive")) and T(t["passive"].get("armor")): amount = maxi(0, amount - t["passive"]["armor"])
	if not hero and T(t["status"].get("intangible")): amount = mini(amount, 1)
	if not hero and T(t["status"].get("aegis")):
		var ab: int = mini(t["status"]["aegis"], amount)
		t["status"]["aegis"] -= ab; amount -= ab
		var ac = S.get("actor")
		if ac != null and T(ac.get("hero")): stat_add(ac, "dmg", ab, "shield")
		if not T(t["status"]["aegis"]):
			t["status"].erase("aegis"); float_text(t, "Aegis broken!", "crit-f"); retrigger(t, "hit")
	if hero and T(t["status"].get("guard")):
		amount = JS.cel(amount * (1 - minf(GUARD_MAX, t["status"]["guard"] * GUARD_PCT)) - 1e-9)
		t["status"]["guard"] -= 1
		if not T(t["status"]["guard"]): t["status"].erase("guard")
	var blocked: int = mini(t["block"], amount)
	var actor = S.get("actor")
	if actor != null and hero != T(actor.get("hero")): stat_add(actor, "dmg", blocked, "shield"); stat_add(actor, "dmg", mini(amount - blocked, t["hp"]), "hp")
	t["block"] -= blocked
	var dmg: int = amount - blocked
	t["hp"] = maxi(0, t["hp"] - dmg)
	retrigger(t, "hit"); slash_fx(t)
	float_text(t, ("-%d" % dmg) if dmg > 0 else "Blocked", "dmg" if dmg > 0 else "blk")
	if not hero and dmg > 0 and t["hp"] > 0 and T(t.get("passive")) and T(t["passive"].get("rage")):
		t["status"]["strength"] = st(t, "strength") + t["passive"]["rage"]
	update_unit(t)
	var act = S.get("actor")
	if S.get("affix") == "bloodMoon" and dmg > 0 and act != null and not act["dead"] and T(act.get("hero")) != hero:
		var v := JS.flr(dmg * 0.15)
		if v: heal(act, v)
	return dmg

func stat_add(h, key: String, n, sub = null) -> void:
	if h == null or not T(n) or n <= 0 or not T(S.get("stats")): return
	var bump := func(o: Dictionary):
		o[key] += n
		if sub != null:
			if not o.has("det"): o["det"] = {}
			if not o["det"].has(key): o["det"][key] = {}
			o["det"][key][sub] = nz(o["det"][key], sub) + n
	if not T(h.get("hero")):
		if not S["stats"]["fight"].has(h["id"]): S["stats"]["fight"][h["id"]] = {"dmg": 0, "heal": 0, "block": 0, "debuff": 0, "buff": 0}
		bump.call(S["stats"]["fight"][h["id"]])
		return
	for scope in ["fight", "run"]:
		if not S["stats"][scope].has(h["id"]): S["stats"][scope][h["id"]] = {"dmg": 0, "heal": 0, "block": 0, "debuff": 0, "buff": 0}
		bump.call(S["stats"][scope][h["id"]])

func lose_hp(t: Dictionary, amount, cls: String) -> void:
	if not T(t.get("hero")) and T(t["status"].get("vulnerable")): amount = JS.flr(amount * VULN_MULT)
	var actor = S.get("actor")
	if actor != null and T(t.get("hero")) != T(actor.get("hero")): stat_add(actor, "dmg", mini(amount, t["hp"]), "hp")
	t["hp"] = maxi(0, t["hp"] - amount); retrigger(t, "hit"); float_text(t, "-%d" % amount, cls); update_unit(t)

func heal(t: Dictionary, amount) -> void:
	if amount <= 0 or t["dead"]: return
	if S.get("affix") == "verdantBloom": amount = JS.rnd(amount * 1.25)
	var actor = S.get("actor")
	if actor != null and T(t.get("hero")) == T(actor.get("hero")): stat_add(actor, "heal", mini(amount, t["maxHp"] - t["hp"]))
	t["hp"] = mini(t["maxHp"], t["hp"] + amount); float_text(t, "+%d" % amount, "heal-f"); update_unit(t)

func gain_block(u: Dictionary, amount, from_card := false) -> void:
	if from_card and T(u["status"].get("brittle")): amount = maxi(0, amount - u["status"]["brittle"])
	if amount <= 0: float_text(u, "Brittle!", "status-f"); return
	if S.get("affix") == "ironVeins": amount = JS.rnd(amount * 1.25)
	if T(u["status"].get("overgrown")): amount = JS.rnd(amount * 1.25)
	if T(u.get("hero")) and u.get("spec") == "knockout":
		amount = JS.flr(amount * KO_BLOCK)
		if amount <= 0: return
	var actor = S.get("actor")
	if actor != null and T(u.get("hero")) == T(actor.get("hero")): stat_add(actor, "block", amount, "self" if is_same(u, actor) else "others")
	u["block"] += amount; retrigger(u, "shield"); float_text(u, "+%d Block" % amount, "blk"); update_unit(u)

func apply_status(u: Dictionary, key: String, n) -> void:
	if u["dead"] or not T(n): return
	var actor = S.get("actor")
	if actor != null and n > 0 and not T(actor.get("hero")):
		stat_add(actor, "debuff" if T(u.get("hero")) else "buff", n, key)
	elif actor != null and n > 0:
		if not T(u.get("hero")):
			stat_add(actor, "debuff", n, key)
			if key == "poison" or key == "burn":
				if not T(u.get("dotBy")): u["dotBy"] = {}
				u["dotBy"][key] = actor["id"]
		elif not key in ["weak", "poison", "burn", "brittle", "drained"]: stat_add(actor, "buff", n, key)
	u["status"][key] = st(u, key) + n
	var lbl = D["STATUS_LABEL"].get(key, "undefined")
	float_text(u, ("+%d " % n if key == "strength" else "") + str(lbl), D["STATUS_CLS"].get(key, "status-f"))
	if key == "ice": check_freeze(u)
	update_unit(u)
	if key == "taunt":
		for e in alive(): update_unit(e)

func check_freeze(e: Dictionary) -> void:
	var th := ICE_BOSS if T(e.get("boss")) else ICE_NORMAL
	if not T(e.get("frozen")) and not T(e.get("freezeCD")) and st(e, "ice") >= th:
		e["status"]["ice"] -= th; e["frozen"] = true
		float_text(e, "Frozen!", "ice-f"); retrigger(e, "shield")
	update_unit(e)

func roll_intent(e: Dictionary) -> void:
	e["turn"] = nz(e, "turn") + 1
	var it: Dictionary = role_intent(e, enemy_ai(e)).duplicate()
	if not T(it.get("dmg")): it.erase("dmg")
	var mult: float = e["mult"]
	for k in ["protect", "blockAllies", "healLow", "dmg", "block"]:
		if T(it.get(k)): it[k] = maxi(1, JS.rnd(it[k] * mult))
	if T(it.get("aegis")): it["aegis"] = maxi(1, JS.rnd(it["aegis"] * mult * ENEMY_HP_MULT * party_hp_mult()))
	if T(it.get("healAllies")): it["healAllies"] = JS.rnd(it["healAllies"] * mult)
	if T(it.get("healSelf")): it["healSelf"] = maxi(1, JS.rnd(it["healSelf"] * mult))
	if T(it.get("dmg")) and atk_of(it) != "aoe": it["dmg"] = maxi(1, JS.rnd(it["dmg"] * party_dmg_mult()))
	roll_target(it)
	e["intent"] = it; e["intentDone"] = false
	update_unit(e)

func draw_cards(h: Dictionary, n: int) -> void:
	var drawn := []
	for i in n:
		if h["draw"].is_empty():
			if h["discard"].is_empty(): break
			h["draw"] = shuffle(h["discard"]); h["discard"] = []
		var c: Dictionary = h["draw"].pop_back()
		h["hand"].append(c); drawn.append(c["id"])
		c["replayTax"] = nz(orv(h, "turnPlayed", {}), str(c["id"]))
	if S["active"] == h["id"]: render_hand(drawn)
	else: update_unit(h)

func with_neighbors(primary: Dictionary, n: int) -> Array:
	var lst := alive()
	var i0 := JS.idx(lst, primary)
	var others := lst.filter(func(e): return not is_same(e, primary))
	JS.jsort(others, func(a, b): return absi(JS.idx(lst, a) - i0) - absi(JS.idx(lst, b) - i0))
	return [primary] + others.slice(0, n)

func check_hero_deaths() -> void:
	for h in hero_list():
		if not h["dead"] and h["hp"] <= 0 and S.get("affix") == "restlessDead" and T(S.get("restless")) and not S["restless"]["hero"] and alive().size():
			S["restless"]["hero"] = true; h["hp"] = maxi(1, JS.rnd(h["maxHp"] * 0.3)); float_text(h, "Rises again!", "heal-f"); update_unit(h)
	for h in hero_list():
		if not h["dead"] and h["hp"] <= 0:
			h["dead"] = true; h["block"] = 0; h["status"] = {}; float_text(h, "Fallen!", "dmg"); update_unit(h)


# =====================================================================
#   KARTE AUSSPIELEN – Stand 22.11.2026
# =====================================================================
func _attack_value(e: Dictionary, base) -> int:
	var v: int = base + st(e, "strength")
	if st(e, "dream") >= 4: v = JS.flr(v * 0.75)
	return JS.flr(v * WEAK_MULT) if T(e["status"].get("weak")) else v

func _ice(x: Dictionary, n) -> int: return n + x.iceBonus if T(n) else 0

func _show_cond(x: Dictionary) -> void:
	if not x.condShown: x.condShown = true; float_text(x.h, "Bonus!", "gold-f")

func _on_hit_effects(x: Dictionary, t: Dictionary, met: Array = []) -> void:
	var s: Dictionary = x.s
	if T(s.poison): apply_status(t, "poison", s.poison)
	if T(s.weak): apply_status(t, "weak", s.weak)
	if T(s.vuln): apply_status(t, "vulnerable", s.vuln)
	if T(s.burn): apply_status(t, "burn", s.burn)
	if T(s.ice): apply_status(t, "ice", _ice(x, s.ice))
	if T(s.mark): apply_status(t, "mark", s.mark)
	if T(s.owed): apply_status(t, "owed", s.owed)
	var conds: Array = x.conds
	for j in conds.size():
		if j >= met.size() or not met[j]: continue
		var cd: Dictionary = conds[j]
		if T(cd.get("mark")): apply_status(t, "mark", cd["mark"])
		if T(cd.get("poison")): apply_status(t, "poison", cd["poison"])
		if T(cd.get("weak")): apply_status(t, "weak", cd["weak"])
		if T(cd.get("vuln")): apply_status(t, "vulnerable", cd["vuln"])
		if T(cd.get("burn")): apply_status(t, "burn", cd["burn"])
		if T(cd.get("ice")): apply_status(t, "ice", _ice(x, cd["ice"]))

func _hero_cond_of(x: Dictionary, cd: Dictionary) -> bool:
	if cd["if"] == "momentum": return x.momAtStart >= orv(cd, "n", 1)
	return x.heroCond.get(cd["if"], false)

func _met_for(x: Dictionary, t) -> Array:
	var out := []
	var conds: Array = x.conds
	for j in conds.size():
		var cd: Dictionary = conds[j]
		if HERO_CONDS.has(cd["if"]): out.append(_hero_cond_of(x, cd))
		elif cd["if"] == "crit" or cd["if"] == "kill": out.append(false)
		else:
			var pre = null
			for pm in x.preMet:
				if is_same(pm[0], t): pre = pm[1]; break
			out.append(pre[j] if pre != null else cond_target(cd["if"], t))
	return out

func _detonate_on(x: Dictionary, e: Dictionary, per) -> void:
	var n: int = st(e, "mark")
	if not n or e["dead"]: return
	var boom := JS.rnd(n * per * (1 + n / 100.0))
	e["status"]["mark"] = 0; update_unit(e); float_text(e, "Detonate!", "crit-f"); retrigger(e, "hit")
	deal_damage(e, boom)
	if e["hp"] <= 0:
		kill_enemy(e); x.killed = true
		var nxt := alive().filter(func(o): return not is_same(o, e))
		if nxt.size():
			var to: Dictionary = nxt[JS.flr(rng() * nxt.size())]
			apply_status(to, "mark", n); float_text(to, "Chain!", "crit-f")
	await sleep(260)

func play_card(h: Dictionary, i: int, target) -> void:
	S["actor"] = h
	var c: Dictionary = h["hand"][i]
	var d: Dictionary = CARDS[c["key"]]
	var s := stats(c)
	var was_resonant := T(c.get("resonant")) and T(c.get("link"))
	S["selected"] = null; S["selKind"] = null
	fx.emit("playing", {"h": h, "i": i})
	h["energy"] -= s.cost
	if T(s.sanityCost): h["sanity"] = maxi(0, sanity_of(h) - s.sanityCost); float_text(h, "-%d Sanity" % s.sanityCost, "status-f")
	update_unit(h)
	await sleep(160)
	h["hand"].remove_at(i); h["discard"].append(c)
	render_hand()
	var recipient: Dictionary = target if (target != null and T(target.get("hero")) and not target["dead"] and hero_targetable(d)) else h
	var x := {"h": h, "c": c, "s": s, "iceBonus": 1 if h.get("spec") == "ice" else 0, "conds": as_list(d.get("cond")),
		"condShown": false, "killed": false, "anyCrit": false}
	x.enemyTarget = target if target != null and not T(target.get("hero")) else null
	var leeched := 0
	var conds: Array = x.conds
	x.heroCond = {"block": h["block"] > 0, "thorns": T(h["status"].get("thorns")), "lowHp": h["hp"] < h["maxHp"] / 2.0, "invis": T(h["status"].get("invis")),
		"gold100": h["gold"] >= 100, "afterAttack": h.get("lastType") == "attack", "afterSkill": T(h.get("lastType")) and h.get("lastType") != "attack"}
	x.momAtStart = st(h, "momentum")
	var start_met := []
	for cd in conds:
		if HERO_CONDS.has(cd["if"]): start_met.append(_hero_cond_of(x, cd))
		elif cd["if"] == "crit" or cd["if"] == "kill": start_met.append(false)
		elif s.aoe or s.random or x.enemyTarget == null: start_met.append(alive().any(func(e): return cond_target(cd["if"], e)))
		else: start_met.append(cond_target(cd["if"], x.enemyTarget))
	x.preMet = []
	for e in alive(): x.preMet.append([e, conds.map(func(cd): return cond_target(cd["if"], e))])
	for j in conds.size():
		if conds[j]["if"] == "momentum" and start_met[j]:
			h["status"]["momentum"] = maxi(0, st(h, "momentum") - orv(conds[j], "n", 1)); update_unit(h)
	var mom_spent: int = st(h, "momentum") if (T(s.spendMomentum) or T(s.spendCrit) or s.momentumSparks or s.riftFinish) else 0
	if mom_spent:
		h["status"]["momentum"] = 0; update_unit(h); float_text(h, "Momentum ×%d!" % mom_spent, "crit-f")
	var marked_before: bool = st(x.enemyTarget, "mark") > 0 if x.enemyTarget != null else false
	if T(s.selfDmg):
		lose_hp(h, s.selfDmg, "dmg"); await sleep(250); check_hero_deaths()
	h["_consumeOwed"] = s.consumeOwed
	var opt = (S.get("playOpt") if T(S.get("playOpt")) else D["DRUNK_OPTS"][s.style][0]["id"]) if s.style != null else null
	var solo_crit: bool = opt == "solo" and alive().size() == 1
	var plundered := []
	var payback_spent := 0
	if T(s.consumePayback) and T(h["status"].get("payback")):
		payback_spent = h["status"]["payback"]; h["status"].erase("payback"); update_unit(h)
	if s.style != null:
		for o in D["DRUNK_OPTS"][s.style]:
			if o["id"] == opt: float_text(h, o["name"] + "!", "status-f"); break
	var invis_atk: bool = T(s.dmg) and T(h["status"].get("invis"))
	if invis_atk:
		h["status"].erase("invis"); update_unit(h); float_text(h, "Ambush!", "dmg")
	var dream_touched := []
	for rr in s.repeats:
		if h["dead"] or (alive().is_empty() and (T(s.dmg) or needs_target(s))): break
		if rr > 0: await sleep(260)
		if x.enemyTarget != null and x.enemyTarget["dead"]: x.enemyTarget = pick(alive()) if alive().size() else null
		if T(s.block): gain_block(recipient, s.block, true); await sleep(150)
		if T(s.blockAll):
			for y in living(): gain_block(y, s.blockAll, true)
			await sleep(150)
		if T(s.thorns): apply_status(recipient, "thorns", s.thorns)
		if T(s.thornsAll):
			for y in living(): apply_status(y, "thorns", s.thornsAll)
		if T(s.flameArmor): apply_status(recipient, "flameArmor", s.flameArmor)
		if T(s.frostArmor): apply_status(recipient, "frostArmor", s.frostArmor)
		if T(s.staticArmor): apply_status(recipient, "staticArmor", s.staticArmor)
		if T(s.dmg):
			retrigger(h, "lunge")
			await sleep(120)
			var hits: int = rand(s.hitsMin, s.hitsMax) if T(s.hitsMax) else s.hits
			var first_hit := true
			for k in hits:
				if alive().is_empty() or h["dead"]: break
				var group: Array
				if s.aoe: group = alive()
				else:
					var primary
					if s.random or h.get("spec") == "drunkmaster": primary = pick(alive())
					else: primary = x.enemyTarget if x.enemyTarget != null and not x.enemyTarget["dead"] else pick(alive())
					group = with_neighbors(primary, s.extra)
				var broke := false
				for t in group:
					var left := alive().size()
					var maxed = h["status"].get("maxRange")
					var amount: int
					if T(s.get("blockStrike")): amount = h["block"] + s.dmg - 1
					elif s.backstab != null: amount = s.backstab[mini(left, 3) - 1]
					elif T(s.dmgMax): amount = s.dmgMax if T(maxed) else rand(s.dmgMin, s.dmgMax)
					else: amount = s.dmg
					if T(s.bonusRange): amount += s.bonusRange if T(maxed) else rand(0, s.bonusRange)
					if T(h["status"].get("might")): amount += h["status"]["might"]
					if s.execute and t["hp"] < t["maxHp"] / 2.0: amount *= 2
					if h.get("spec") == "thief": amount += JS.flr(h["gold"] / 50.0)
					if T(s.soloMult) and left == 1: amount = JS.flr(amount * s.soloMult) if typeof(s.soloMult) == TYPE_FLOAT else amount * s.soloMult
					if s.lowHpDouble and h["hp"] < h["maxHp"] / 2.0: amount *= 2
					var met := _met_for(x, t)
					for j in conds.size():
						if met[j] and T(conds[j].get("dmg")): amount += conds[j]["dmg"]; _show_cond(x)
					if mom_spent and T(s.spendMomentum): amount += s.spendMomentum * mom_spent
					if T(h["status"].get("power")):
						amount += h["status"]["power"] * POWER_DMG; h["status"].erase("power"); update_unit(h)
					if T(h["status"].get("payback")) and h.get("spec") == "nightfighter": amount += h["status"]["payback"]
					if first_hit and payback_spent:
						amount += s.consumePayback * payback_spent; heal(h, JS.flr(payback_spent / 2.0))
					amount += cash_owed(h, t)
					first_hit = false
					if T(s.runeScale): amount += s.runeScale * runes_in_deck(h)
					var crit_hit := false
					if solo_crit: amount *= 2; float_text(t, "CRIT!", "crit-f")
					if s.crit and (T(h["status"].get("critBuff")) or is_same(t, rearmost()) or (h.get("spec") == "deadeye" and st(t, "mark") >= 10)):
						amount *= 2; float_text(t, "CRIT!", "crit-f"); crit_hit = true; x.anyCrit = true
					for j in conds.size():
						if conds[j]["if"] == "crit": met[j] = crit_hit
					if mom_spent and s.spendCrit != null: amount += (s.spendCrit["crit"] if crit_hit else s.spendCrit["base"]) * mom_spent
					if invis_atk: amount *= 2
					if h.get("spec") == "acolyte": amount += JS.flr(nz(h, "corruption") / 25.0)
					var bleed_fx = null
					if s.bleed:
						var dn: int = st(t, "dream")
						bleed_fx = 4 if dn >= 10 else 3 if dn >= 7 else 2 if dn >= 5 else 1 if dn >= 3 else 0
						amount += [0, 4, 4, 10, 17][bleed_fx]
					if T(t["status"].get("mark")): amount = JS.rnd(amount * (1 + t["status"]["mark"] / 100.0))
					if T(h["status"].get("weak")): amount = JS.flr(amount * WEAK_MULT)
					var block_before: int = t["block"]
					var dealt: int
					if opt == "pierce":
						var b0: int = t["block"]; t["block"] = 0; dealt = deal_damage(t, amount)
						if not t["dead"]: t["block"] = b0
					else: dealt = deal_damage(t, amount)
					if opt == "steal":
						var got: int = block_before - t["block"]
						if got > 0: gain_block(h, got)
					if opt == "heal": heal(h, 1)
					if opt == "transfer":
						for dbf in HERO_DEBUFFS:
							if st(h, dbf[0]) > 0:
								h["status"][dbf[0]] -= 1
								if not T(h["status"][dbf[0]]): h["status"].erase(dbf[0])
								update_unit(h)
								if not t["dead"]: apply_status(t, dbf[1], 1)
								break
					if opt == "plunder" and not JS.has(plundered, t) and not t["dead"]:
						if st(t, "strength") > 0:
							plundered.append(t); var pn: int = mini(3, t["status"]["strength"]); t["status"].erase("strength"); update_unit(t)
							apply_status(h, "power", pn); float_text(t, "Plundered!", "status-f")
						elif T(t["status"].get("intangible")):
							plundered.append(t); t["status"].erase("intangible"); update_unit(t); float_text(t, "Plundered!", "status-f")
					if T(s.leech) and dealt > 0 and leeched < s.leechCap:
						var lx: int = mini(s.leech, s.leechCap - leeched); leeched += lx; heal(h, lx)
					if t["hp"] <= 0:
						kill_enemy(t); x.killed = true
						if h.get("spec") == "assassin": apply_status(h, "invis", 1)
						if h.get("spec") == "barbarian" and not T(h.get("killBonus")):
							h["killBonus"] = true; h["energy"] += 2; update_unit(h)
							float_text(h, "Bloodthirst!", "dmg"); draw_cards(h, 1)
					else:
						_on_hit_effects(x, t, met)
						if T(s.dream): add_dream(t, s.dream)
						if bleed_fx != null and bleed_fx >= 2 and not t["dead"]: apply_status(t, "weak", 1)
						if bleed_fx != null and bleed_fx >= 3 and not t["dead"]: apply_status(t, "vulnerable", 1)
						if bleed_fx == 4 and not t["dead"]: nightmare(t)
						if not t["dead"] and T(t["status"].get("dream")) and not JS.has(dream_touched, t) and living().any(func(y): return y.get("spec") == "dreamweaver"):
							dream_touched.append(t); add_dream(t, 1)
						if h.get("spec") == "fire": apply_status(t, "burn", 1)
						if T(h["status"].get("venomEdge")): apply_status(t, "poison", h["status"]["venomEdge"])
					if T(t.get("passive")) and T(t["passive"].get("thorns")):
						await sleep(90); deal_damage(h, t["passive"]["thorns"]); check_hero_deaths()
						if h["dead"]: broke = true; break
				await sleep(150 if hits > 2 else 230)
		elif x.enemyTarget != null and not x.enemyTarget["dead"]: _on_hit_effects(x, x.enemyTarget, _met_for(x, x.enemyTarget))
		# Einmal-Boni der Bedingungen
		for j in conds.size():
			var cd: Dictionary = conds[j]
			var ok: bool = x.anyCrit if cd["if"] == "crit" else x.killed if cd["if"] == "kill" else start_met[j]
			if not ok or h["dead"]: continue
			var any := false
			if T(cd.get("block")): gain_block(recipient, cd["block"], true); any = true
			if T(cd.get("blockAll")):
				for y in living(): gain_block(y, cd["blockAll"], true)
				any = true
			if T(cd.get("thorns")): apply_status(recipient, "thorns", cd["thorns"]); any = true
			if T(cd.get("heal")): heal(recipient, cd["heal"]); any = true
			if T(cd.get("gold")): h["gold"] += cd["gold"]; float_text(h, "+%d Gold" % cd["gold"], "gold-f"); update_counters(); any = true
			if T(cd.get("energy")):
				h["energy"] = mini(MAX_SAVED_ENERGY, h["energy"] + cd["energy"]); update_unit(h); float_text(h, "+%d Energy" % cd["energy"], "blk"); any = true
			if T(cd.get("draw")): draw_cards(h, cd["draw"]); any = true
			if T(cd.get("momentum")): gain_momentum(h, cd["momentum"]); any = true
			if any: _show_cond(x)
		var et = x.enemyTarget
		if s.poisonDouble and et != null and not et["dead"] and T(et["status"].get("poison")):
			et["status"]["poison"] *= 2; update_unit(et); await sleep(200)
			lose_hp(et, et["status"]["poison"], "poison-f")
			if et["hp"] <= 0: kill_enemy(et); x.killed = true
			await sleep(250)
		if s.poisonPop and et != null and not et["dead"] and T(et["status"].get("poison")):
			await sleep(200); lose_hp(et, et["status"]["poison"], "poison-f")
			if et["hp"] <= 0: kill_enemy(et); x.killed = true
			await sleep(250)
		# Brawler
		if s.taunt: apply_status(h, "taunt", 1); float_text(h, "Come at me!", "dmg")
		if T(s.guard): apply_status(h, "guard", s.guard)
		if T(s.power): apply_status(h, "power", s.power)
		if T(s.combo): apply_status(h, "combo", s.combo)
		if T(s.reach): apply_status(h, "reach", s.reach)
		if s.cleanseSelf:
			for dbf in HERO_DEBUFFS: h["status"].erase(dbf[0])
			float_text(h, "Cleansed", "heal-f"); update_unit(h)
		if T(s.selfWeak): apply_status(h, "weak", s.selfWeak)
		if T(s.fury): gain_fury(h, s.fury); await check_punch(h)
		# Ranger
		if T(s.markAll):
			for e in alive(): apply_status(e, "mark", s.markAll)
			await sleep(200)
		if T(s.detonate):
			var tgt = x.enemyTarget if x.enemyTarget != null and not x.enemyTarget["dead"] else null
			if tgt != null: await _detonate_on(x, tgt, s.detonate)
			elif s.aoe or s.random:
				var lst := alive()
				JS.jsort(lst, func(a, b): return st(b, "mark") - st(a, "mark"))
				if lst.size(): await _detonate_on(x, lst[0], s.detonate)
		if T(s.detonateAll):
			for e in alive().duplicate(): await _detonate_on(x, e, s.detonateAll)
		if mom_spent and s.momentumSparks: add_temp_card(h, "sparkarrow", mom_spent)
		if mom_spent and s.riftFinish:
			var f: Dictionary = D["RIFT_FINISH"][s.riftKey]
			if T(f.get("mark")) and x.enemyTarget != null and not x.enemyTarget["dead"]: apply_status(x.enemyTarget, "mark", f["mark"] * mom_spent)
			if T(f.get("drawPer")) and JS.flr(float(mom_spent) / f["drawPer"]): draw_cards(h, JS.flr(float(mom_spent) / f["drawPer"]))
			if T(f.get("sparkPer")) and JS.flr(float(mom_spent) / f["sparkPer"]): add_temp_card(h, "sparkarrow", JS.flr(float(mom_spent) / f["sparkPer"]))
			if T(f.get("energyPer")) and JS.flr(float(mom_spent) / f["energyPer"]):
				var en := JS.flr(float(mom_spent) / f["energyPer"])
				h["energy"] = mini(MAX_SAVED_ENERGY, h["energy"] + en); update_unit(h); float_text(h, "+%d Energy" % en, "blk")
			if T(f.get("grow")) and not T(c.get("tmp")):
				c["bonusDmg"] = nz(c, "bonusDmg") + mom_spent; float_text(h, "+%d damage forever" % mom_spent, "gold-f")
		if T(s.momentum): gain_momentum(h, s.momentum)
		if s.momentumDouble: gain_momentum(h, st(h, "momentum"))
		if s.createCard != null: add_temp_card(h, s.createCard["key"], s.createCard["n"])
		if s.makeRune:
			var rn := roll_rune(); h["gems"].append(rn); toast("%s found a %s!" % [h["name"], D["RUNE_TYPES"][rn["type"]]["name"]]); update_counters()
		if s.get("runeFx") == "siphon" and marked_before:
			h["energy"] = mini(MAX_SAVED_ENERGY, h["energy"] + 2); update_unit(h); float_text(h, "+2 Energy", "blk")
		if s.poisonTrigger:
			for e in alive():
				if T(e["status"].get("poison")):
					lose_hp(e, e["status"]["poison"], "poison-f")
					if e["hp"] <= 0: kill_enemy(e); x.killed = true
			await sleep(300)
		if s.invis: apply_status(h, "invis", 1)
		if s.buff != null:
			for y in (living() if s.buffAll else [h]): apply_status(y, s.buff["key"], s.buff["n"])
			retrigger(h, "shield"); await sleep(250)
		if s.gold != null:
			var gg := rand(s.gold[0], s.gold[1]); h["gold"] += gg; float_text(h, "+%d Gold" % gg, "gold-f"); update_counters()
		if s.makeGem:
			var tier := 1
			while tier < 2: tier = RARITY_ORDER.find(roll_rarity()) + 1
			var types := GEM_ORDER.filter(func(t): return gem_fits(t, tier))
			var nt: String = pick(types)
			var ng := {"id": uid, "type": nt, "tier": tier, "fleeting": not T(GEM_TYPES[nt].get("noFleet")) and rng() < FLEET_CHANCE}
			uid += 1
			h["gems"].append(ng); toast("%s stole a %s!" % [h["name"], gem_title(ng)]); update_counters()
		if T(s.weakAll):
			for e in alive(): apply_status(e, "weak", s.weakAll)
			await sleep(200)
		if T(s.vulnAll):
			for e in alive(): apply_status(e, "vulnerable", s.vulnAll)
			await sleep(200)
		if T(s.poisonAll):
			for e in alive(): apply_status(e, "poison", s.poisonAll)
			await sleep(200)
		if T(s.burnAll):
			for e in alive(): apply_status(e, "burn", s.burnAll)
			await sleep(200)
		if T(s.iceAll):
			for e in alive(): apply_status(e, "ice", _ice(x, s.iceAll))
			await sleep(200)
		if s.blizzard != null:
			h["blizzardFx"] = {"dmg": s.blizzard["dmg"], "ice": s.blizzard["ice"] + x.iceBonus}
			apply_status(h, "blizzard", s.blizzard["turns"])
		if T(s.heal): heal(recipient, s.heal); await sleep(150)
		if T(s.healAll):
			for y in living(): heal(y, s.healAll)
			await sleep(150)
		if T(s.energy):
			h["energy"] = mini(MAX_SAVED_ENERGY, h["energy"] + s.energy); update_unit(h); float_text(h, "+%d Energy" % s.energy, "blk")
		if T(s.draw): draw_cards(h, s.draw)
	if s.exhaust:
		h["discard"] = JS.without(h["discard"], c)
		if not h.has("vanished"): h["vanished"] = []
		h["vanished"].append(c)
		if not T(c.get("tmp")): float_text(h, "Once per fight", "status-f")
	if not T(h.get("turnPlayed")): h["turnPlayed"] = {}
	h["turnPlayed"][str(c["id"])] = nz(h["turnPlayed"], str(c["id"])) + 1; c["replayTax"] = 0
	if not h["dead"]:
		await soul_effects(h, c, s, target); await soul_link_trigger(h, c, was_resonant); kinship(c)
	if not h["dead"]: await eldritch_effects(h, c, s, target)
	if s.get("runeFx") == "echo" and not T(c.get("tmp")) and not h["dead"]: add_temp_card(h, c["key"], 1)
	if s.get("runeFx") == "growth" and T(d.get("dmg")) and not T(c.get("tmp")): c["bonusDmg"] = nz(c, "bonusDmg") + 2
	if h["id"] == "ranger" and not h["dead"]:
		if T(h.get("lastType")) and h["lastType"] != d["type"]: gain_momentum(h, 1)
		h["lastType"] = d["type"]; h["turnPlays"] = nz(h, "turnPlays") + 1; update_unit(h)
		if h.get("spec") == "stormweaver" and h["turnPlays"] % 3 == 0: add_temp_card(h, "sparkarrow", 1)
	if s.returnOnKill and x.killed and JS.has(h["discard"], c):
		h["discard"] = JS.without(h["discard"], c); h["hand"].append(c); float_text(h, "Returns!", "dmg")
	if h.get("spec") == "templar" and d["type"] != "attack" and not h["dead"]:
		gain_block(h, 1); apply_status(h, "thorns", 2)
	render_hand()
	for e in S["enemies"].duplicate():
		if T(e.get("boss")) and not e["dead"]: await check_boss_phase(e)
	check_hero_deaths()
	if all_heroes_dead(): await sleep(500); defeat(); return
	if alive().is_empty(): S["phase"] = "won"; await sleep(600); await victory(); return
	var shifter = null
	for e in alive():
		if T(e["passive"].get("interrupt")): shifter = e; break
	if shifter != null:
		S["shiftCount"] = nz(S, "shiftCount") + 1; update_unit(shifter)
		if S["shiftCount"] >= SHIFT_LIMIT:
			S["shiftCount"] = 0
			await banner("%s interrupts!" % shifter["name"], "He acts immediately and changes form.", 1300)
			if not T(shifter.get("frozen")): await enemy_act(shifter)
			check_hero_deaths()
			if all_heroes_dead(): await sleep(400); defeat(); return
			if not shifter["dead"]: shift_form(shifter); roll_intent(shifter)
			refresh_ui()
	if h["dead"]: h["turnDone"] = true; await check_team_done()

# =====================================================================
#   GEGNER STERBEN, BOSS-PHASEN, ZUGABLAUF – Stand 22.11.2026
# =====================================================================
func kill_enemy(e: Dictionary) -> void:
	if S.get("affix") == "restlessDead" and T(S.get("restless")) and not S["restless"]["enemy"] and not T(e.get("minion")) and not e["dead"]:
		S["restless"]["enemy"] = true; e["hp"] = maxi(1, JS.rnd(e["maxHp"] * 0.3)); float_text(e, "Rises again!", "heal-f"); update_unit(e); return
	for y in living():
		if y.get("spec") == "tidecaller" and not e["dead"]: gain_depth(y, 1)
	var poison_left: int = st(e, "poison")
	e["dead"] = true; e["intentDone"] = true; e["status"] = {}; e["frozen"] = false
	if T(e.get("passive")) and T(e["passive"].get("split")):
		var at := JS.idx(S["enemies"], e)
		for k in 2:
			var m := make_enemy(D["MINIONS"]["slimeling"], e["mult"])
			at += 1
			S["enemies"].insert(at, m)
			fx.emit("summoned", {"u": m, "after": S["enemies"][at - 1]})
			roll_intent(m); m["intentDone"] = true; update_unit(m)
		float_text(e, "Splits!", "status-f")
	if T(e.get("passive")) and T(e["passive"].get("bond")):
		for o in S["enemies"].filter(func(o): return not o["dead"] and not is_same(o, e) and T(o.get("passive")) and T(o["passive"].get("bond"))):
			apply_status(o, "strength", 5); heal(o, JS.rnd(o["maxHp"] * 0.3)); float_text(o, "Enraged!", "dmg")
	if T(e.get("passive")) and T(e["passive"].get("regrow")) and alive().size():
		e["regrowIn"] = 3; update_unit(e); fx.emit("regrowing", {"u": e, "on": true})
	else:
		e["regrowIn"] = 0; update_unit(e)
		fx.emit("dead", {"u": e})
	if poison_left and living().any(func(y): return y.get("spec") == "deathbringer") and alive().size():
		var i0 := JS.idx(S["enemies"], e)
		var lst := alive()
		JS.jsort(lst, func(a, b): return absi(JS.idx(S["enemies"], a) - i0) - absi(JS.idx(S["enemies"], b) - i0))
		if lst.size():
			float_text(e, "Contagion!", "poison-f"); apply_status(lst[0], "poison", poison_left)
	if alive().is_empty():
		for o in S["enemies"]:
			if T(o.get("regrowIn")):
				o["regrowIn"] = 0; update_unit(o); fx.emit("regrowing", {"u": o, "on": false}); fx.emit("dead", {"u": o})
	if T(e.get("passive")) and T(e["passive"].get("summoner")):
		for m in S["enemies"].filter(func(m): return T(m.get("minion")) and not m["dead"]):
			m["dead"] = true; m["intentDone"] = true; update_unit(m)
			float_text(m, "Flees!", "status-f"); fx.emit("fled", {"u": m})

func check_boss_phase(e: Dictionary) -> void:
	var pk: String = "khepri" if e["key"] == "b_khepri" else e["key"]
	if not D["BOSS_PHASES"].has(pk): return
	var pct: float = float(e["hp"]) / e["maxHp"]
	var want := 3 if pct <= 1.0 / 3 else 2 if pct <= 2.0 / 3 else 1
	while e["phase"] < want and not e["dead"]:
		e["phase"] += 1
		var ph: Dictionary = D["BOSS_PHASES"][pk][str(e["phase"])]
		fx.emit("bossphase", {"u": e, "phase": e["phase"]})
		await banner("Phase %d: %s" % [e["phase"], ph["name"]], ph["desc"], 1900)
		for k in ["poison", "burn", "ice", "weak", "vulnerable"]: e["status"].erase(k)
		e["frozen"] = false; e["freezeCD"] = false
		float_text(e, "Cleansed!", "heal-f"); update_unit(e)
		await sleep(300)
		await boss_phase_enter(pk, e["phase"], e)
		e["turn"] = 0; roll_intent(e)

func start_round() -> void:
	S["round"] += 1; S["actor"] = null
	for h in hero_list():
		h["block"] = 0
		var gain := maxi(0, MAX_ENERGY + (2 if h.get("spec") == "storm" and S["round"] <= 2 else 0) - st(h, "drained"))
		h["status"].erase("drained")
		h["energy"] = mini(MAX_SAVED_ENERGY, h["energy"] + gain)
		update_unit(h)
	await start_team_turn()

func start_team_turn() -> void:
	S["phase"] = "hero"; S["uiHero"] = null; S["viewOverride"] = null
	for h in hero_list():
		h["turnDone"] = h["dead"]
		h["killBonus"] = false; h["lastType"] = null; h["turnPlays"] = 0; h["kinshipGot"] = 0; h["mindStun"] = false
		h["turnPlayed"] = {}
		for c in h["hand"] + h["draw"] + h["discard"]: c["replayTax"] = 0
		for k in ["thorns", "flameArmor", "frostArmor", "staticArmor", "invis", "taunt"]: h["status"].erase(k)
		for e in alive(): update_unit(e)
		if h.get("spec") == "nightfighter":
			if T(h["status"].get("paybackNext")): h["status"]["payback"] = h["status"]["paybackNext"]
			else: h["status"].erase("payback")
			h["status"].erase("paybackNext")
	pick_local_hero(true)
	refresh_ui()
	await affix_round_start()
	if all_heroes_dead(): await sleep(400); defeat(); return
	if alive().is_empty(): S["phase"] = "won"; await sleep(400); await victory(); return
	await banner("Your Turn", "Everyone plays at the same time" if S["mode"] != "solo" else ("Switch heroes any time" if living().size() > 1 else ""))
	var burned := false
	for h in living():
		if T(h["status"].get("burn")):
			burned = true; lose_hp(h, h["status"]["burn"], D["STATUS_CLS"]["burn"]); h["status"]["burn"] -= 1; update_unit(h)
	if burned: await sleep(400)
	check_hero_deaths()
	if all_heroes_dead(): await sleep(400); defeat(); return
	for h in hero_list():
		if h["dead"]: h["turnDone"] = true; continue
		if T(h["status"].get("fortify")): gain_block(h, h["status"]["fortify"])
		if T(h["status"].get("toughen")): apply_status(h, "guard", h["status"]["toughen"])
		if h["id"] == "eldritch" and eldritch_turn_start(h): continue
		if S["round"] == 1:
			var pc := -1
			for k in h["draw"].size():
				if T(CARDS[h["draw"][k]["key"]].get("punchCard")): pc = k; break
			if pc >= 0:
				var pcard = h["draw"][pc]; h["draw"].remove_at(pc); h["draw"].append(pcard)
		draw_cards(h, HAND_SIZE + st(h, "insight"))
	for h in living():
		if h.get("servants", []).any(func(sv): return sv["key"] == "guardian"):
			for y in living().filter(func(y): return not is_same(y, h)): gain_block(y, 3, true)
	for h in living():
		if T(h["status"].get("soulAnvil")):
			var allies := living().filter(func(y): return not is_same(y, h))
			var t = allies[JS.flr(rng() * allies.size())] if allies.size() else h
			craft_cards(h, {"kind": "gift", "n": 1, "to": "target"}, t)
	for h in living():
		if h.get("spec") == "knockout": await check_punch(h)
	if alive().is_empty(): S["phase"] = "won"; await sleep(500); await victory(); return
	if hero_list().all(func(y): return T(y.get("turnDone"))): await sleep(600); await check_team_done(); return
	pick_local_hero()
	refresh_ui()

func pick_local_hero(reset := false) -> void:
	var cur = S["heroes"].get(S["active"]) if S["active"] != null else null
	if not reset and cur != null and mine(cur["id"]) and not cur["dead"] and not T(cur.get("turnDone")): return
	var mine_list := hero_list().filter(func(h): return mine(h["id"]) and not h["dead"])
	var nxt = null
	for h in mine_list:
		if not T(h.get("turnDone")): nxt = h; break
	if nxt == null and mine_list.size(): nxt = mine_list[0]
	if nxt == null and living().size(): nxt = living()[0]
	S["active"] = nxt["id"] if nxt != null else null; S["selected"] = null; S["selKind"] = null

func switch_hero(id: String) -> void:
	var h = S["heroes"].get(id)
	if h == null or not mine(id) or h["dead"] or S["phase"] != "hero": return
	S["active"] = id; S["selected"] = null; S["selKind"] = null; refresh_ui()

func end_hero_turn(h: Dictionary) -> void:
	if T(h.get("turnDone")): return
	h["turnDone"] = true
	if h.get("servants", []).size() and not h["dead"]:
		S["actor"] = h; await servants_act(h); S["actor"] = null
		if alive().is_empty():
			h["discard"].append_array(h["hand"]); h["hand"] = []; render_hand(); S["phase"] = "won"; await sleep(500); await victory(); return
	if T(h["status"].get("weak")): h["status"]["weak"] -= 1; update_unit(h)
	var hexes: int = h["hand"].filter(func(c): return c["key"] == "hex").size()
	h["discard"].append_array(h["hand"]); h["hand"] = []; render_hand()
	if hexes and not h["dead"]:
		for k in hexes: deal_damage(h, 3); await sleep(250)
		check_hero_deaths()
		if all_heroes_dead(): await sleep(400); defeat(); return
	await check_team_done()

func check_team_done() -> void:
	for y in hero_list():
		if y["dead"]: y["turnDone"] = true
	pick_local_hero(); refresh_ui()
	if S["phase"] == "hero" and hero_list().all(func(y): return T(y.get("turnDone"))): await enemy_turn()

## Taunt: schwächster normaler Angriff dieses Gegners (mit Skalierung), ohne den Spielzufall zu verbrauchen
func weakest_attack(e: Dictionary) -> int:
	var key := "%s|%s|%d|%s" % [e.get("phase"), e.get("form", ""), alive().size(), e["mult"]]
	if T(e.get("_weak")) and e["_weak"]["k"] == key: return e["_weak"]["v"]
	var saved := r._seed
	var keep := {"turn": e.get("turn"), "lastMove": e.get("lastMove"), "lastName": e.get("lastName"), "cds": e["cds"].duplicate() if T(e.get("cds")) else e.get("cds")}
	var mn := INF
	if T(e.get("atk")): mn = e["atk"][0]
	for t in range(1, 13):
		for k in 6:
			r.seed_rng(t * 7919 + k * 104729 + 1); e["turn"] = t; e["lastMove"] = "block" if k % 2 else null; e["lastName"] = null
			var it: Dictionary = enemy_ai(e)
			if nz(it, "dmg") > 0: mn = minf(mn, it["dmg"])
	r._seed = saved
	for kk in keep: e[kk] = keep[kk]
	var v := 0 if mn == INF else maxi(1, JS.rnd(mn * e["mult"]))
	e["_weak"] = {"k": key, "v": v}
	return v

func taunt_extra(e: Dictionary) -> int:
	if e["dead"] or e.get("intent") == null or T(e["intent"].get("dmg")): return 0
	return weakest_attack(e) if living().any(func(y): return T(y["status"].get("taunt"))) else 0

func taunt_strike(e: Dictionary, amount: int) -> void:
	var h = null
	for y in living():
		if T(y["status"].get("taunt")): h = y; break
	if h == null or e["dead"]: return
	retrigger(e, "lunge"); float_text(e, "Taunted!", "dmg"); await sleep(130)
	if T(h["status"].get("invis")) and living().any(func(o): return not is_same(o, h)): float_text(h, "Evaded", "blk"); return
	var dealt := deal_damage(h, JS.flr(amount * 0.5) if T(h["status"].get("invis")) else amount)
	gain_fury(h, 1)
	var hs: Dictionary = h["status"]
	if T(hs.get("thorns")): deal_damage(e, hs["thorns"])
	if T(hs.get("staticArmor")): deal_damage(e, hs["staticArmor"] if T(hs.get("maxRange")) else rand(1, hs["staticArmor"]))
	if e["hp"] <= 0: kill_enemy(e)
	else:
		if T(hs.get("flameArmor")): apply_status(e, "burn", hs["flameArmor"])
		if T(hs.get("frostArmor")): apply_status(e, "ice", hs["frostArmor"])
		if T(e.get("passive")) and T(e["passive"].get("lifesteal")) and dealt > 0: await sleep(120); heal(e, dealt)
	check_hero_deaths()
	await sleep(200)

func enemy_act(e: Dictionary) -> void:
	var extra := taunt_extra(e)
	await enemy_action(e)
	if extra and not e["dead"] and not all_heroes_dead(): await taunt_strike(e, extra)

func enemy_action(e: Dictionary) -> void:
	var it: Dictionary = e["intent"]
	e["status"].erase("etaunt"); e["status"].erase("bulwark")
	if T(e.get("burrowed")): e["status"].erase("intangible"); e["burrowed"] = false; update_unit(e)
	if T(it.get("needsAegis")) and not T(e["status"].get("aegis")):
		float_text(e, "Staggered!", "crit-f"); apply_status(e, "vulnerable", 2); await sleep(500); return
	if T(it.get("aegis")):
		e["status"]["aegis"] = it["aegis"]; float_text(e, "Aegis %d" % it["aegis"], "blk"); retrigger(e, "shield"); update_unit(e); await sleep(300)
	if T(it.get("cleanse")):
		var ndb := func(o): 
			var sm := 0
			for k in ENEMY_DEBUFFS: sm += nz(o["status"], k)
			return sm
		var lst := alive()
		JS.jsort(lst, func(a, b): return ndb.call(b) - ndb.call(a))
		var w = lst[0] if lst.size() else null
		if w != null and ndb.call(w):
			for k in ENEMY_DEBUFFS: w["status"].erase(k)
			w["frozen"] = false; float_text(w, "Cleansed!", "heal-f"); update_unit(w); await sleep(250)
	if T(it.get("healAllies")):
		for o in alive():
			if not is_same(o, e): heal(o, it["healAllies"])
		heal(e, JS.rnd(it["healAllies"] / 2.0)); await sleep(250)
	if T(it.get("healLow")):
		var lst := alive()
		JS.jsort(lst, func(a, b): return float(a["hp"]) / a["maxHp"] - float(b["hp"]) / b["maxHp"])
		if lst.size(): heal(lst[0], it["healLow"])
		await sleep(200)
	if T(it.get("healSelf")): heal(e, it["healSelf"])
	if T(it.get("rallyStr")):
		for o in alive():
			if not is_same(o, e) or alive().size() == 1: apply_status(o, "strength", it["rallyStr"])
		float_text(e, "Rally!", "status-f"); await sleep(250)
	if T(it.get("protect")):
		var allies := alive().filter(func(o): return not is_same(o, e))
		var lst: Array = allies if allies.size() else [e]
		JS.jsort(lst, func(a, b): return float(a["hp"]) / a["maxHp"] - float(b["hp"]) / b["maxHp"])
		gain_block(lst[0], it["protect"]); await sleep(200)
	if T(it.get("blockAllies")):
		for o in alive(): gain_block(o, it["blockAllies"])
		await sleep(200)
	if T(it.get("block")): gain_block(e, it["block"])
	if T(it.get("taunt")) and not T(it.get("dmg")): e["status"]["etaunt"] = 1; float_text(e, "Taunt!", "dmg"); retrigger(e, "shield"); update_unit(e)
	if T(it.get("bulwark")): e["status"]["bulwark"] = it["bulwark"]; float_text(e, "Bulwark %d%%" % it["bulwark"], "blk"); update_unit(e)
	if T(it.get("armorUp")): e["passive"]["armor"] = nz(e["passive"], "armor") + it["armorUp"]; float_text(e, "Harden!", "blk"); update_unit(e)
	if T(it.get("thornsUp")): e["passive"]["thorns"] = nz(e["passive"], "thorns") + it["thornsUp"]; float_text(e, "+Thorns", "status-f"); update_unit(e)
	if T(it.get("burrow")): e["status"]["intangible"] = 1; e["burrowed"] = true; float_text(e, "Burrows!", "status-f"); update_unit(e)
	if T(it.get("strength")) and not T(it.get("dmg")): apply_status(e, "strength", it["strength"])
	if T(it.get("summon")): await summon_minion(e, it["summon"])
	var hit_set := []
	if T(it.get("dmg")):
		for k in orv(it, "hits", 1):
			retrigger(e, "lunge")
			await sleep(130)
			var total := 0
			for pr in atk_targets(e, it):
				var h: Dictionary = pr[0]
				var m: float = pr[1]
				if h["dead"]: continue
				if T(h["status"].get("invis")) and living().any(func(o): return not is_same(o, h)):
					float_text(h, "Evaded", "blk"); continue
				var v := _attack_value(e, it["dmg"])
				if m != 1.0: v = maxi(1, JS.rnd(v * m))
				if T(h["status"].get("invis")): v = JS.flr(v * 0.5)
				total += deal_damage(h, v)
				if not JS.has(hit_set, h): hit_set.append(h)
				gain_fury(h, 1)
				if e["dead"]: continue
				var hs: Dictionary = h["status"]
				if T(hs.get("thorns")): deal_damage(e, hs["thorns"])
				if T(hs.get("staticArmor")): deal_damage(e, hs["staticArmor"] if T(hs.get("maxRange")) else rand(1, hs["staticArmor"]))
				if e["hp"] <= 0: kill_enemy(e); continue
				if T(hs.get("flameArmor")): apply_status(e, "burn", hs["flameArmor"])
				if T(hs.get("frostArmor")): apply_status(e, "ice", hs["frostArmor"])
			if e["dead"]: check_hero_deaths(); return
			if ((T(e.get("passive")) and T(e["passive"].get("lifesteal"))) or T(it.get("leech"))) and total > 0: await sleep(120); heal(e, total)
			check_hero_deaths()
			if all_heroes_dead(): return
			if nz(it, "hits") > 1: await sleep(220)
		if T(it.get("strength")): await sleep(150); apply_status(e, "strength", it["strength"])
		if T(it.get("taunt")): e["status"]["etaunt"] = 1; float_text(e, "Taunt!", "dmg"); update_unit(e)
	elif T(it.get("poison")) or T(it.get("burn")) or T(it.get("brittle")) or T(it.get("weak")) or T(it.get("drain")):
		for pr in atk_targets(e, it):
			if not JS.has(hit_set, pr[0]): hit_set.append(pr[0])
	var targets := hit_set.filter(func(h): return not h["dead"])
	for k in ["poison", "burn", "brittle", "weak"]:
		if T(it.get(k)) and targets.size():
			await sleep(120)
			for h in targets: apply_status(h, k, it[k])
	if T(it.get("drain")) and targets.size():
		for h in targets: apply_status(h, "drained", it["drain"])
	if T(it.get("hex")):
		for h in living():
			for k in it["hex"]: h["discard"].append(new_card("hex"))
			float_text(h, "+%d Hex" % it["hex"], "status-f")
		render_hand()

func summon_minion(leader: Dictionary, kind: String) -> void:
	var g := make_enemy(D["MINIONS"][kind], leader["mult"])
	var in_front := rng() < 0.5
	var at := JS.idx(S["enemies"], leader)
	S["enemies"].insert(at if in_front else at + 1, g)
	fx.emit("summoned", {"u": g, "leader": leader, "front": in_front})
	roll_intent(g); g["intentDone"] = true; update_unit(g)
	await sleep(300)

func enemy_turn() -> void:
	S["phase"] = "enemy"; S["active"] = null; S["actor"] = null; refresh_ui()
	await banner("Enemy Turn")
	for h in hero_list():
		if T(h["status"].get("blizzard")) and T(h.get("blizzardFx")) and alive().size():
			float_text(h, "Blizzard!", "ice-f")
			for e in alive():
				deal_damage(e, h["blizzardFx"]["dmg"])
				if e["hp"] <= 0: kill_enemy(e)
				else: apply_status(e, "ice", h["blizzardFx"]["ice"])
			h["status"]["blizzard"] -= 1; update_unit(h)
			await sleep(500)
			for e in S["enemies"].duplicate():
				if T(e.get("boss")) and not e["dead"]: await check_boss_phase(e)
	if alive().is_empty(): S["phase"] = "won"; await sleep(500); await victory(); return
	var acting := alive()
	for e in acting: e["block"] = 0; update_unit(e)
	for e in acting:
		if e["dead"]: continue
		await sleep(200)
		if T(e["status"].get("burn")):
			S["actor"] = S["heroes"].get(e["dotBy"]["burn"]) if T(e.get("dotBy")) and e["dotBy"].has("burn") else null
			lose_hp(e, e["status"]["burn"], "burn-f"); S["actor"] = null; e["status"]["burn"] -= 1; update_unit(e); await sleep(350)
			if e["hp"] <= 0: kill_enemy(e); await sleep(300); continue
			if T(e.get("boss")): await check_boss_phase(e)
		if T(e.get("mindStun")):
			float_text(e, "Corrupted Mind", "status-f"); e["mindStun"] = false; e["mindCD"] = true; e["intentDone"] = true; update_unit(e)
			await sleep(400)
		elif T(e.get("frozen")):
			float_text(e, "Frozen", "ice-f"); e["frozen"] = false; e["freezeCD"] = true; e["intentDone"] = true; update_unit(e)
			await sleep(400)
		else:
			if not T(e.get("intentDone")): S["actor"] = e; await enemy_act(e); S["actor"] = null
			e["lastMove"] = "block" if T(e["intent"].get("block")) and not T(e["intent"].get("dmg")) else "attack"
			e["lastName"] = e["intent"].get("name")
			e["intentDone"] = true
			if T(e["status"].get("weak")): e["status"]["weak"] -= 1
			if T(e["status"].get("vulnerable")): e["status"]["vulnerable"] -= 1
			if T(e["passive"].get("interrupt")) and not e["dead"]: shift_form(e)
			if T(e.get("freezeCD")): e["freezeCD"] = false; check_freeze(e)
			e["mindCD"] = false
			update_unit(e)
			await sleep(330)
		if all_heroes_dead(): await sleep(500); defeat(); return
		if T(e["status"].get("poison")) and not e["dead"]:
			S["actor"] = S["heroes"].get(e["dotBy"]["poison"]) if T(e.get("dotBy")) and e["dotBy"].has("poison") else null
			lose_hp(e, e["status"]["poison"], "poison-f"); S["actor"] = null; e["status"]["poison"] -= 1; update_unit(e); await sleep(350)
			if e["hp"] <= 0: kill_enemy(e); await sleep(300); continue
			if T(e.get("boss")): await check_boss_phase(e)
	if alive().is_empty(): S["phase"] = "won"; await sleep(500); await victory(); return
	for e in alive():
		if T(e["passive"].get("phase")):
			if T(e["status"].get("intangible")): e["status"].erase("intangible")
			else: e["status"]["intangible"] = 1
			update_unit(e)
	for e in S["enemies"].filter(func(o): return T(o.get("regrowIn"))):
		e["regrowIn"] -= 1
		if e["regrowIn"] == 0:
			e["dead"] = false; e["hp"] = JS.cel(e["maxHp"] / 2.0); e["block"] = 0; e["status"] = {}; e["frozen"] = false
			fx.emit("regrowing", {"u": e, "on": false}); fx.emit("revived", {"u": e}); float_text(e, "Regrown!", "heal-f")
		update_unit(e)
	var poisoned := false
	for h in living():
		if T(h["status"].get("poison")):
			poisoned = true
			deal_damage(h, h["status"]["poison"])
			h["status"]["poison"] -= 1; update_unit(h)
	if poisoned:
		await sleep(450); check_hero_deaths()
		if all_heroes_dead(): await sleep(400); defeat(); return
	for e in alive(): roll_intent(e)
	await sleep(250)
	await start_round()

# =====================================================================
#   GEGNER, RÄUME, LAUF, BELOHNUNGEN, EVENTS – Stand 22.11.2026
# =====================================================================
func make_enemy(t: Dictionary, mult: float, extra: Dictionary = {}) -> Dictionary:
	var ex := extra.duplicate()
	if T(t.get("support")) and not ex.has("support"): ex["support"] = true
	if t.get("id") == "shifter" and not ex.has("form"): ex["form"] = "wolf"
	var base_hp: int = rand(t["hp"][0], t["hp"][1]) if typeof(t["hp"]) == TYPE_ARRAY else t["hp"]
	var hp := maxi(1, JS.rnd(base_hp * mult * ENEMY_HP_MULT * party_hp_mult()))
	var e := {"id": "e%d" % uid, "key": t["key"], "name": t["name"], "desc": t.get("desc", ""), "flyer": t.get("flyer"), "minion": t.get("minion"),
		"cls": t.get("cls", ""), "boss": T(t.get("boss")), "hp": hp, "maxHp": hp, "block": 0, "status": {},
		"passive": (t.get("passive", {}) as Dictionary).duplicate(), "mult": mult, "ai": _ai_key(t),
		"atk": t.get("atk"), "blk": t.get("blk"), "atkChance": t.get("atkChance"), "intent": null, "intentDone": false, "dead": false, "turn": 0, "phase": 1,
		"moves": t.get("moves"), "ecls": orv(t, "ecls", "")}
	uid += 1
	for k in ex: e[k] = ex[k]
	return e

## KI-Schlüssel: Biom-Normalgegner = "move", Biom-Elites = "el_<id>", sonst der Grafik-Schlüssel
func _ai_key(t: Dictionary) -> String:
	if T(t.get("moves")): return "move"
	if T(t.get("aiKey")): return t["aiKey"]
	return t["key"] if t.has("ai") else "basic"

func role_intent(e: Dictionary, it: Dictionary) -> Dictionary:
	if not T(e.get("role")) or alive().size() < 2: return it
	if e["role"] == "guardian" and e["turn"] % 2 == 0: return {"protect": 8, "name": "Protect Ally"}
	if e["role"] == "tactician" and e["turn"] % 3 == 0: return {"rallyStr": 1, "dmg": JS.cel(it["dmg"] / 2.0) if T(it.get("dmg")) else 0, "name": "Battle Cry"}
	return it

func room_mult(rm: int, kind: String) -> float:
	var a := mini(rm - 1, 14)
	var b := maxi(0, rm - 15)
	if kind == "normal": return 1 + a * 0.08 + b * 0.035
	if kind == "elite": return 1 + a * 0.06 + b * 0.03
	return 1 + a * 0.04 + b * 0.025

func _elite_by_id(id: String) -> Dictionary:
	for x in D["ELITES"]:
		if x["id"] == id: return x
	return {}

func pick_elites(n: int) -> Array:
	var out := []
	while out.size() < n:
		if S["eliteBag"].is_empty(): S["eliteBag"] = shuffle(D["ELITES"].map(func(x): return x["id"]))
		var id: String = S["eliteBag"].pop_back()
		var el := _elite_by_id(id)
		var units := 0
		for x in out: units += x["parts"].size() if T(x.get("parts")) else 1
		units += el["parts"].size() if T(el.get("parts")) else 1
		if not JS.has(out, el) and units <= 5: out.append(el)
	return out

func elite_units(el: Dictionary, mult: float) -> Array:
	if T(el.get("parts")): return el["parts"].map(func(p): return make_enemy(p, mult, {"elite": true, "group": el["id"]}))
	return [make_enemy(el, mult, {"elite": true})]

func spawn_enemies(kind: String) -> Dictionary:
	if T(S.get("biome")): return spawn_biome(kind)
	var rm: int = S["room"]
	if kind == "normal":
		var count: int = 1 if rm == 1 else rand(1, 2) if rm == 2 else 2 if rm == 3 else rand(2, mini(4, 2 + JS.flr(rm / 5.0)))
		var pool: Array = D["NORMALS"].filter(func(t): return t["minFight"] <= rm)
		var mult := room_mult(rm, "normal")
		var lst := []
		for k in count: lst.append(make_enemy(pick(pool), mult))
		if rm >= 3 and rng() < SUPPORT_CHANCE:
			var sup: Dictionary = D["SUPPORTS"][D["SUPPORT_THEME"].get(lst[0]["key"], "drummer")]
			if lst.size() >= 4: lst.pop_back()
			lst.append(make_enemy(sup, mult))
		var fighters := lst.filter(func(e): return not T(e.get("support")))
		if fighters.size() >= 2:
			var n_roles := 2 if fighters.size() >= 4 else 1
			for e in shuffle(fighters.duplicate()).slice(0, n_roles):
				e["role"] = "guardian" if rng() < 0.5 else "tactician"
				e["passive"]["roleGuard" if e["role"] == "guardian" else "roleTactic"] = 1
		return {"list": lst, "special": null}
	var mult := room_mult(rm, "elite")
	if kind == "boss":
		if not T(S.get("bossesSeen")): S["bossesSeen"] = []
		var bosses := [D["BOSS"], D["AEGIS_BOSS"], D["SHIFTER_BOSS"]]
		var left := bosses.filter(func(b): return not S["bossesSeen"].has(b["id"]))
		var B: Dictionary = (left if left.size() else bosses)[JS.flr(rng() * (left.size() if left.size() else bosses.size()))]
		S["bossesSeen"].append(B["id"])
		return {"list": [make_enemy(B, room_mult(rm, "boss"))], "special": B}
	if kind == "smith": return {"list": [make_enemy(D["SMITH"], mult, {"elite": true})], "special": D["SMITH"]}
	if kind == "double":
		var ab := pick_elites(2)
		return {"list": elite_units(ab[0], mult) + elite_units(ab[1], mult),
			"special": {"name": "%s & %s" % [ab[0]["name"], ab[1]["name"]], "desc": "Two elites at once!", "double": true}}
	var el: Dictionary = pick_elites(1)[0]
	return {"list": elite_units(el, mult), "special": el}

func start_fight(kind: String) -> void:
	S["post"] = {}; S["uiHero"] = null; S["phase"] = "fight"
	fx.emit("hidescreens", {})
	S["fight"] += 1; S["round"] = 0; S["fightKind"] = kind; S["shiftCount"] = 0
	S["links"] = {}; S["linkSeq"] = 0; S["actor"] = null
	if T(S.get("stats")): S["stats"]["fight"] = {}
	for h in hero_list():
		clear_soul_state(h); h["servants"] = []; h["mindStun"] = false
		if h["id"] == "eldritch": h["sanity"] = SANITY_MAX
		h["draw"] = shuffle(h["deck"].duplicate()); h["hand"] = []; h["discard"] = []; h["vanished"] = []
		h["block"] = 0; h["status"] = {}; h["energy"] = 0; h["blizzardFx"] = null; update_unit(h)
	for h in hero_list():
		if h.get("spec") == "tidecaller": h["status"]["depth"] = 3; update_unit(h)
	var sp := spawn_enemies(kind)
	S["enemies"] = sp["list"]; S["special"] = sp["special"]
	fx.emit("enemies", {"list": sp["list"], "special": sp["special"]})
	await affix_fight_start()
	for e in sp["list"]: roll_intent(e)
	refresh_ui()
	var special = sp["special"]
	var arena: String = ("Arena (%s) – " % S["arena"]) if T(S.get("arena")) else ""
	if special != null and T(special.get("boss")): await banner(special["name"], special.get("desc", ""), 2400)
	elif special != null: await banner("%sElite: %s" % [arena, special["name"]], special.get("desc", ""), 2200)
	elif T(S.get("arena")): await banner("Arena", "Easy fight", 1200)
	await start_round()

func events_left() -> Array:
	return EVENT_TYPES.filter(func(t): return not S.get("eventsSeen", []).has(t))

func enter_map() -> void:
	if S["room"] > 0 and S["room"] % BIOME_ROOMS == 0 and S.get("biomeFor") != S["room"] and S["room"] < ROOMS_PER_RUN:
		S["post"] = {}; choose_biome(); refresh_ui(); return
	S["phase"] = "map"; S["post"] = {}; S["active"] = null; S["arena"] = null
	fx.emit("hidescreens", {})
	var nxt: int = S["room"] + 1
	if nxt % BOSS_EVERY == 0: S["mapOpts"] = ["boss"]
	elif S["sinceElite"] >= 3: S["mapOpts"] = ["elite"]
	else:
		var weights := {"normal": 30, "elite": 14, "camp": 16, "shop": 16, "event": 24 if events_left().size() else 0}
		var n := rand(1, 3)
		var opts := []
		while opts.size() < n:
			var pool := weights.keys().filter(func(k): return not opts.has(k))
			var tot := 0
			for k in pool: tot += weights[k]
			var xx := rng() * tot
			for k in pool:
				xx -= weights[k]
				if xx < 0: opts.append(k); break
		S["mapOpts"] = opts
	refresh_ui()

func enter_room(type: String) -> void:
	S["room"] += 1
	S["sinceElite"] = 0 if type == "elite" or type == "boss" else S["sinceElite"] + 1
	if type in ["normal", "elite", "boss"]: await start_fight(type); return
	S["enemies"] = []
	fx.emit("enemies", {"list": [], "special": null})
	if type == "camp" or type == "shop":
		S["phase"] = "post"
		for h in hero_list():
			if h["dead"]: h["dead"] = false; h["hp"] = maxi(1, JS.rnd(h["maxHp"] * REVIVE_HP))
			var p := {"kind": type, "picked": true, "gemsDone": true, "ready": false}
			if type == "shop": p["shop"] = make_shop(h)
			S["post"][h["id"]] = p; update_unit(h)
		refresh_ui(); return
	S["phase"] = "event"
	var ev_type: String = pick(events_left() if events_left().size() else EVENT_TYPES)
	S["eventsSeen"].append(ev_type)
	S["event"] = {"type": ev_type, "upgrades": 0, "tries": 0, "stage": "roll", "mods": []}
	if ev_type == "campfire":
		await banner("A hidden campfire!", "You stumble upon a quiet campfire.", 1500)
		enter_room_camp(); return
	refresh_ui()

func enter_room_camp() -> void:
	S["phase"] = "post"; S["event"] = null
	for h in hero_list():
		if h["dead"]: h["dead"] = false; h["hp"] = maxi(1, JS.rnd(h["maxHp"] * REVIVE_HP))
		S["post"][h["id"]] = {"kind": "camp", "picked": true, "gemsDone": true, "ready": false}; update_unit(h)
	refresh_ui()

func sell_price(g: Dictionary) -> int: return JS.flr(D["PRICES"][gem_rarity(g)] * 0.5)

func make_shop(h: Dictionary) -> Dictionary:
	var price := func(rr): return JS.rnd(D["PRICES"][rr] * (0.9 + rng() * 0.2))
	var pool := card_pool(h["id"], h.get("spec"))
	var cards := []
	var gems := []
	var nc := rand(2, 4)
	var ng := rand(2, 4)
	var guard := 0
	while cards.size() < nc and guard < 200:
		guard += 1
		var rr := roll_rarity()
		var opts := pool.filter(func(k): return CARDS[k]["rarity"] == rr and not cards.any(func(c): return c["key"] == k))
		if opts.size():
			var key: String = pick(opts)
			cards.append({"key": key, "price": price.call(rr), "sold": false, "foil": roll_foil()})
	for k in ng:
		var g := roll_gem()
		gems.append({"gem": g, "price": price.call(gem_rarity(g)), "sold": false})
	return {"cards": cards, "gems": gems}

func start_run(a: Dictionary) -> void:
	fx.emit("runstart", {})
	S["runId"] += 0      # runId wurde schon beim Einreihen erhöht
	S["paused"] = false; S["waiting"] = false; S["selected"] = null; S["selKind"] = null; S["phase"] = "idle"; S["active"] = null
	S["enemies"] = []; S["post"] = {}; S["uiHero"] = null
	S["runActive"] = true
	S["mode"] = ("host" if net != null and net.is_host else "guest") if a.get("mode") == "coop" else "solo"
	S["roles"] = a["roles"]
	r.seed_rng(a["seed"]); uid = 1
	CARDS = D["CARDS"].duplicate(true)
	S["fight"] = 0; S["room"] = 0; S["sinceElite"] = 0; S["eventsSeen"] = []; S["bossesSeen"] = []; S["eliteBag"] = []; S["eliteSeen"] = []
	S["elitesBeaten"] = 0; S["arena"] = null; S["event"] = null; S["mapOpts"] = []
	S["biome"] = null; S["affix"] = null; S["biomesSeen"] = []; S["biomeIdx"] = 0; S["biomeFor"] = null
	S["heroes"] = {}; S["stats"] = {"fight": {}, "run": {}}; S["actor"] = null
	var party_in: Array = a.get("party", ["knight", "mage"])
	S["party"] = D["CLASS_ORDER"].filter(func(id): return party_in.has(id))
	var rev: Array = S["party"].duplicate(); rev.reverse()
	for id in rev:
		var def: Dictionary = D["HEROES"][id]
		S["heroes"][id] = {"id": id, "hero": true, "name": def["name"], "key": def["key"], "hp": def["maxHp"], "maxHp": def["maxHp"], "block": 0, "status": {},
			"energy": MAX_ENERGY, "deck": [], "spec": null, "draw": [], "hand": [], "discard": [], "gems": [], "gold": 0, "rerolls": 0, "dead": false,
			"corruption": 0, "sanity": SANITY_MAX, "servants": []}
	S["formation"] = S["party"].duplicate(); S["formReady"] = {}
	fx.emit("heroes", {})
	S["phase"] = "spec"                                  # erst Spezialisierung, danach Formation
	refresh_ui()

func roll_rarity(elite := false) -> String:
	var ch := func(rr): return D["ELITE_CHANCE"][rr] if elite else RARITY[rr]["chance"]
	var total := 0.0
	for rr in RARITY_ORDER: total += ch.call(rr)
	var xx := rng() * total
	for rr in RARITY_ORDER:
		xx -= ch.call(rr)
		if xx < 0: return rr
	return "common"

func card_pool(hero_id: String, spec) -> Array:
	return CARDS.keys().filter(func(k):
		var c: Dictionary = CARDS[k]
		return c.get("char") == hero_id and not T(c.get("basic")) and not T(c.get("custom")) and (not T(c.get("spec")) or c["spec"] == spec))

func reward_choices(hero_id: String, n := 3, min_rarity = null, elite := false) -> Array:
	var min_idx: int = RARITY_ORDER.find(min_rarity) if min_rarity != null else 0
	var pool0 := card_pool(hero_id, S["heroes"][hero_id].get("spec")).filter(func(k): return RARITY_ORDER.find(CARDS[k]["rarity"]) >= min_idx)
	var picks := []
	var guard := 0
	while picks.size() < n and guard < 300:
		guard += 1
		var rr := roll_rarity(elite)
		if RARITY_ORDER.find(rr) < min_idx: rr = RARITY_ORDER[min_idx + JS.flr(rng() * (RARITY_ORDER.size() - min_idx))]
		var pool := pool0.filter(func(k): return CARDS[k]["rarity"] == rr and not picks.has(k))
		if pool.size(): picks.append(pick(pool))
	return picks

func roll_gem(elite := false, h = null) -> Dictionary:
	var tier := RARITY_ORDER.find(roll_rarity(elite)) + 1
	if h != null and T(h.get("spec")) and D["SPEC_GEM"].has(h["spec"]) and tier >= 2 and rng() < SPEC_GEM_CHANCE:
		var g := {"id": uid, "type": D["SPEC_GEM"][h["spec"]], "tier": tier, "fleeting": rng() < FLEET_CHANCE}
		uid += 1
		return g
	var types := GEM_ORDER.filter(func(t): return gem_fits(t, tier))
	var type: String = pick(types)
	var g2 := {"id": uid, "type": type, "tier": tier, "fleeting": not T(GEM_TYPES[type].get("noFleet")) and rng() < FLEET_CHANCE}
	uid += 1
	return g2

func victory() -> void:
	S["phase"] = "post"; S["active"] = null
	lasting_etch()
	for h in hero_list(): clear_soul_state(h)
	S["links"] = {}
	var was_boss: bool = S.get("special") != null and T(S["special"].get("boss"))
	if was_boss and S["room"] >= ROOMS_PER_RUN: run_won(); return
	if was_boss: await banner("%s has fallen!" % S["special"]["name"], "The heroes recover fully. %d rooms to go." % (ROOMS_PER_RUN - S["room"]), 2000)
	var was_elite: bool = was_boss or S["enemies"].any(func(e): return T(e.get("elite")))
	var arena = S.get("arena"); S["arena"] = null
	for h in hero_list():
		if h["dead"]:
			h["dead"] = false; h["hp"] = maxi(1, JS.rnd(h["maxHp"] * REVIVE_HP)); float_text(h, "Revived", "heal-f")
		h["block"] = 0; h["status"] = {}
		heal(h, h["maxHp"] if was_boss else HEAL_AFTER_FIGHT)
		var gold := rand(60, 80) if was_boss else rand(20, 30) if was_elite else rand(10, 20)
		h["gold"] += gold
		var cards := reward_choices(h["id"], 3, "epic" if was_boss else "rare" if arena == "hard" else null, was_elite)
		var foils := cards.map(func(_k): return roll_foil())
		var gem := roll_gem(was_elite, h); h["gems"].append(gem)
		var bonus := []
		if arena == "medium":
			var g := {"id": uid, "type": pick(GEM_ORDER.filter(func(t): return gem_fits(t, 3))), "tier": 3}
			uid += 1; h["gems"].append(g); bonus.append(gem_title(g))
		if arena == "hard":
			var g := {"id": uid, "type": pick(GEM_ORDER.filter(func(t): return gem_fits(t, 5))), "tier": 5}
			uid += 1; h["gems"].append(g); bonus.append(gem_title(g))
		var glory = null
		if h.get("spec") == "gladiator":
			var atk: Array = h["deck"].filter(func(c): return T(CARDS[c["key"]].get("dmg")))
			var c1 = pick(atk) if atk.size() else null
			var dfn: Array = h["deck"].filter(func(c): return T(CARDS[c["key"]].get("block")) and not is_same(c, c1))
			var c2 = pick(dfn) if dfn.size() else null
			if c1 != null: c1["bonusDmg"] = nz(c1, "bonusDmg") + 1
			if c2 != null: c2["bonusBlock"] = nz(c2, "bonusBlock") + 1
			glory = {"dmg": c1["id"] if c1 != null else null, "block": c2["id"] if c2 != null else null}
		S["post"][h["id"]] = {"kind": "reward", "gold": gold, "cards": cards, "foils": foils, "gem": gem, "glory": glory, "bonus": bonus,
			"arena": arena, "picked": false, "removed": false, "ready": false}
		update_unit(h)
	refresh_ui()

func defeat() -> void:
	S["phase"] = "lost"; S["active"] = null; refresh_ui()
	fx.emit("defeat", {})

func run_won() -> void:
	S["phase"] = "won"; refresh_ui()
	fx.emit("runwon", {})

# ---------- Events ----------
func roll_buddy_option() -> Dictionary:
	var kind: String = pick(["damage", "debuff", "buff", "draw", "energy"])
	if kind == "damage": return {"kind": kind, "field": "dmg", "v": 6, "label": "+6 Damage"}
	if kind == "draw": return {"kind": kind, "field": "draw", "v": 1, "label": "Draw +1 card"}
	if kind == "energy": return {"kind": kind, "field": "energy", "v": 2, "label": "+2 Energy"}
	if kind == "debuff": return pick([
		{"kind": kind, "field": "weak", "v": 2, "label": "Apply 2 Weak"}, {"kind": kind, "field": "vuln", "v": 2, "label": "Apply 2 Vulnerable"},
		{"kind": kind, "field": "poison", "v": 4, "label": "Apply 4 Poison"}, {"kind": kind, "field": "burn", "v": 4, "label": "Apply 4 Burn"},
		{"kind": kind, "field": "ice", "v": 3, "label": "Apply 3 Ice"}])
	return pick([{"kind": kind, "field": "block", "v": 6, "label": "Gain 6 Block"}, {"kind": kind, "field": "thorns", "v": 3, "label": "Gain 3 Thorns"},
		{"kind": kind, "field": "heal", "v": 4, "label": "Heal 4 HP"}])

func roll_buddy_options(ev: Dictionary) -> Array:                # zwei verschiedene Modifikationen, oft eine Klassen-Modifikation
	var h = S["heroes"].get(ev.get("hero"))
	var cls: Array = D["BUDDY_CLASS"].get(h.get("spec"), []) if h != null and T(h.get("spec")) else []
	var a := roll_buddy_option()
	var b := {}
	if cls.size() and rng() < 0.5:
		b = (pick(cls) as Dictionary).duplicate(true); b["kind"] = "class"
	else:
		for k in 30:
			b = roll_buddy_option()
			if b["label"] != a["label"]: break
	return [a, b] if rng() < 0.5 else [b, a]

func buddy_def(ev: Dictionary) -> Dictionary:
	var d := {"name": "Buddy", "rarity": ev["rarity"], "cost": 1, "custom": true, "art": {"__fn": "()=>SVG.laurel"}}
	for m in ev["mods"]:
		if T(m.get("field")): d[m["field"]] = nz(d, m["field"]) + m["v"]
		for k in m.get("add", {}): d[k] = nz(d, k) + m["add"][k]
		for k in m.get("set", {}): d[k] = m["set"][k]
	if T(d.get("hits")): d["hits"] += 1
	if T(d.get("chain")) and not T(d.get("dmg")): d["dmg"] = 3
	if T(d.get("lowHpDouble")): d["lowHpDouble"] = true
	if T(d.get("imprint")): d["imprintCards"] = 1
	d["type"] = "attack" if T(d.get("dmg")) else "block" if T(d.get("block")) else "skill"
	if T(d.get("heal")) or T(d.get("block")) or T(d.get("thorns")): d["selfOnly"] = true
	return d

func buddy_action(a: Dictionary) -> void:
	var ev: Dictionary = S["event"]
	if a["op"] == "buddyroll" and ev["stage"] == "roll":
		var rr := roll_rarity()
		while rr == "common": rr = roll_rarity()
		ev["rarity"] = rr; ev["stage"] = "hero"; ev["rolled"] = Time.get_ticks_msec(); return
	if a["op"] == "buddyhero" and ev["stage"] == "hero" and S["heroes"].has(a.get("h")):
		ev["hero"] = a["h"]; ev["stage"] = "mods"; ev["options"] = roll_buddy_options(ev); return
	if a["op"] == "buddymod" and ev["stage"] == "mods" and a.get("i", -1) >= 0 and a["i"] < ev["options"].size() and a.get("h") == ev["hero"]:
		ev["mods"].append(ev["options"][a["i"]])
		if ev["mods"].size() >= slots_of(ev["rarity"]):
			var key := "buddy%d" % uid
			uid += 1
			var d := buddy_def(ev); d["char"] = ev["hero"]
			CARDS[key] = d
			var h: Dictionary = S["heroes"][ev["hero"]]
			h["deck"].append(new_card(key))
			ev["stage"] = "done"; ev["cardKey"] = key
			toast("%s got a new Buddy card!" % h["name"])
		else: ev["options"] = roll_buddy_options(ev)

func event_action(a: Dictionary) -> void:
	var ev = S.get("event")
	if S["phase"] != "event" or ev == null: return
	if a["op"] == "leave": enter_map(); return
	if a["op"] == "arena" and ev["type"] == "arena":
		S["arena"] = a["tier"]
		await start_fight("normal" if a["tier"] == "easy" else "elite" if a["tier"] == "medium" else "double"); return
	if ev["type"] == "buddy": buddy_action(a); return
	var h = S["heroes"].get(a.get("h"))
	if h == null: return
	var c = _find_by_id(h["deck"], a.get("card"))
	if c == null: return
	if a["op"] == "forge" and ev["type"] == "forge":
		if not can_upgrade(c): return
		c["upgraded"] = true
		ev["upgrades"] += 1
		toast("%s upgraded %s" % [h["name"], card_name(c)])
		if rng() < ev["upgrades"] * 0.2:
			fx.emit("hidescreens", {})
			await banner("The blacksmith is back!", "And he wants his hammer.", 1600)
			await start_fight("smith")
		return
	if a["op"] == "transform" and ev["type"] == "anomaly":
		if not T(ev.get("triesBy")): ev["triesBy"] = {}
		var cost: int = nz(ev["triesBy"], h["id"]) * 10
		if h["gold"] < cost: return
		h["gold"] -= cost; ev["triesBy"][h["id"]] = nz(ev["triesBy"], h["id"]) + 1
		var old := card_name(c)
		var rr := roll_rarity()
		var pool := card_pool(h["id"], h.get("spec")).filter(func(k): return CARDS[k]["rarity"] == rr and k != c["key"])
		if pool.is_empty(): pool = card_pool(h["id"], h.get("spec")).filter(func(k): return k != c["key"])
		c["key"] = pick(pool); c.erase("bonusDmg"); c.erase("bonusBlock"); c.erase("bonus")
		var gems: Array = c["gems"]; c["gems"] = []
		for g in gems:
			if can_socket(c, g) == "": c["gems"].append(g)
			else: h["gems"].append(g)
		toast("%s became %s!" % [old, card_name(c)])
		fx.emit("anomaly", {"h": h["id"], "new": c.duplicate(true)})   # UI: Verwandlungs-Animation

# =====================================================================
#   KLASSEN-MECHANIKEN – Stand 22.11.2026
# =====================================================================
# ---------- Ranger ----------
func roll_rune() -> Dictionary:
	var g := {"id": uid, "rune": true, "type": pick(D["RUNE_ORDER"]), "tier": 3}
	uid += 1
	return g
func gain_momentum(h: Dictionary, n: int) -> void:
	if not n or h["dead"]: return
	n += st(h, "plan")
	var before: int = st(h, "momentum")
	h["status"]["momentum"] = mini(10, before + n)
	if h["status"]["momentum"] > before: float_text(h, "+%d Momentum" % (h["status"]["momentum"] - before), "blk")
	update_unit(h)
func add_temp_card(h: Dictionary, key: String, n := 1) -> void:
	for k in n:
		var c := new_card(key); c["tmp"] = true
		h["hand"].append(c)
	float_text(h, "+%d %s%s" % [n, CARDS[key]["name"], "s" if n > 1 else ""], "status-f")

# ---------- Brawler ----------
func gain_fury(h: Dictionary, n: int) -> void:
	if h["dead"] or h.get("spec") != "knockout": return
	h["status"]["fury"] = st(h, "fury") + n; update_unit(h)
func punch_card_of(h: Dictionary) -> Variant:
	for c in h["deck"]:
		if T(CARDS[c["key"]].get("punchCard")): return c
	return null
const PUNCH_HP_PCT := 0.10
const PUNCH_HEAL := 0.35
const KO_BLOCK := 0.5
const KO_MAXHP := 60
func punch_targets() -> Array:                                     # meiste aktuelle HP zuerst
	var t := alive().filter(func(e): return not T(e["status"].get("intangible")))
	var lst: Array = (t if t.size() else alive()).duplicate()
	JS.jsort(lst, func(a, b): return b["hp"] - a["hp"])
	return lst
func punch_base(h: Dictionary, s: Dictionary) -> int:
	return s.punchDmg + st(h, "training") + st(h, "might") + JS.rnd(h["maxHp"] * PUNCH_HP_PCT)
func knockout_punch(h: Dictionary) -> void:
	var c = punch_card_of(h)
	if c == null or h["dead"]: return
	var s := stats(c)
	if punch_targets().is_empty(): return
	var prev_actor = S.get("actor"); S["actor"] = h
	var reach: int = st(h, "reach")
	var combo: int = st(h, "combo")
	var n_targets: int = 1 + reach + nz(s, "punchExtra")
	var hits: int = orv(s, "punchHits", 1) + combo
	var reps: int = maxi(1, nz(s, "punchRepeats"))
	h["status"].erase("reach"); h["status"].erase("combo")
	float_text(h, "KNOCKOUT!", "crit-f"); retrigger(h, "lunge")
	await banner("%s: Knockout Punch!" % h["name"], "", 700)
	var total := 0
	var leeched := 0
	var rr := 0
	while rr < reps and not h["dead"]:
		var lst := punch_targets().slice(0, n_targets)
		for t in lst:
			for k in hits:
				if t["dead"] or h["dead"]: break
				var amount: int = punch_base(h, s)
				if T(s.get("punchRange")): amount += s.punchRange if T(h["status"].get("maxRange")) else rand(0, s.punchRange)
				if T(h["status"].get("power")): amount += h["status"]["power"] * POWER_DMG; h["status"].erase("power")
				amount += cash_owed(h, t)
				if T(t["status"].get("mark")): amount = JS.rnd(amount * (1 + t["status"]["mark"] / 100.0))
				if T(h["status"].get("weak")): amount = JS.flr(amount * WEAK_MULT)
				var dealt := deal_damage(t, amount)
				total += dealt
				if T(s.get("punchLeech")) and dealt > 0 and leeched < s.punchLeechCap:
					var x: int = mini(s.punchLeech, s.punchLeechCap - leeched)
					leeched += x; heal(h, x)
				if t["hp"] <= 0: kill_enemy(t)
				else:
					for k2 in ["poison", "burn", "weak", "vuln"]:
						var v = s.punchFx[k2]
						if T(v): apply_status(t, "vulnerable" if k2 == "vuln" else k2, v)
				if not t["dead"] and T(s.punchFx["ice"]): apply_status(t, "ice", s.punchFx["ice"])
				await sleep(260)
		rr += 1
	if total > 0: heal(h, JS.flr(total * PUNCH_HEAL))
	if not h["dead"]: h["maxHp"] += 1; h["hp"] += 1; float_text(h, "+1 Max HP", "heal-f")
	S["actor"] = prev_actor
	update_unit(h)
	for e in S["enemies"].duplicate():
		if T(e.get("boss")) and not e["dead"]: await check_boss_phase(e)
func check_punch(h: Dictionary) -> void:
	while not h["dead"] and h.get("spec") == "knockout" and st(h, "fury") >= FURY_NEED and alive().size():
		h["status"]["fury"] -= FURY_NEED
		await knockout_punch(h)
func cash_owed(h: Dictionary, t: Dictionary) -> int:
	var n: int = st(t, "owed")
	if not n: return 0
	if h.get("spec") == "nightfighter" and not T(h.get("_consumeOwed")): return 0
	t["status"].erase("owed"); update_unit(t)
	float_text(t, "Paid in full! +%d" % n, "crit-f")
	var blk := JS.flr(n / 2.0)
	if blk:
		for y in living(): gain_block(y, blk)
	for y in hero_list():
		if y.get("spec") == "nightfighter" and not y["dead"]:
			y["status"]["paybackNext"] = st(y, "paybackNext") + n; update_unit(y)
	return n

# ---------- Edelsteine ----------
func apply_spec_gem(s: Dictionary, type: String, t: int, f: int) -> void:
	match type:
		"holygem": s.thorns += t * f
		"bloodgem":
			if T(s.dmg): s.dmg += 2 * (t - 1) * f
			s.selfDmg += 1
		"glorygem":
			if T(s.dmg): s.dmg += (t - 1) * f
			s.block += (t - 1) * f
		"goldgem": s.gold = [(s.gold[0] if s.gold != null else 0) + 3 * t * f, (s.gold[1] if s.gold != null else 0) + 5 * t * f]
		"shadowgem":
			s.crit = true
			if T(s.dmg) and t > 2: s.dmg += (t - 2) * f
		"toxingem": s.poison += (t + 1) * f
		"pyregem": s.burnAll += (t - 1) * f
		"glaciergem": s.iceAll += (t - 1) * f
		"stormgem":
			s.extra += f
			if t >= 4: s.energy += f
		"markgem": s.mark += 5 * (t - 1) * f
		"flowgem": s.momentum += (t - 1) * f
		"riftgem": s.runeScale += (t - 1) * f
		"furygem": s.fury += (2 if t >= 4 else 1) * f
		"swiggem": s.hits += (2 if t >= 4 else 1) * f
		"debtgem": s.owed += (t - 1) * f
		"linkgem":
			s.block += t * f
			if t >= 3: s.resonateAll = true
		"etchgem":
			if s.imprint == null: s.imprint = {"type": "smart", "n": (t - 1) * f}
		"giftgem":
			if s.craft == null: s.craft = {"kind": "gift", "n": (2 if t >= 4 else 1) * f, "to": "ally"}
		"corruptgem":
			if corruption_of() >= 100:
				if T(s.dmg): s.dmg += 2 * (t - 1) * f
				else: s.block += 2 * (t - 1) * f
			else: s.corrupt += (t - 1) * f
		"dreamgem": s.dream += (t - 1) * f
		"summongem": s.gemSummon = ["", "", "spawn", "guardian", "leviathan", "sleeper"][t]; s.gemSummonN = f

func can_socket(c: Dictionary, g: Dictionary) -> String:
	if T(g.get("rune")):
		var o = hero_of_card(c)
		if o == null or o.get("spec") != "rift": return "No Rune slot"
		return "Rune slot full" if T(c.get("rune")) else ""
	var d: Dictionary = CARDS[c["key"]]
	var t: Dictionary = GEM_TYPES[g["type"]]
	if c["gems"].size() >= slots_of(d["rarity"]): return "No free slot"
	if T(t.get("spec")):
		var o = hero_of_card(c)
		if o == null or o.get("spec") != t["spec"]:
			var oid := "knight"
			if o != null: oid = o["id"]
			var sp = spec_of(oid, t["spec"])
			return ("%s only" % sp["name"]) if sp != null else "Other specialization only"
	if g["type"] == "foilgem" and is_foil(c): return "Already Foil"
	if T(t.get("attackOnly")) and not T(d.get("dmg")) and not T(d.get("blockStrike")): return "Attacks only"
	if T(t.get("noAoe")) and T(d.get("aoe")): return "Already hits ALL"
	return ""

# ---------- Soulbinder ----------
func combat_cards(h: Dictionary) -> Array: return h.get("hand", []) + h.get("draw", []) + h.get("discard", [])
func team_imprints() -> int:
	if not in_combat(): return 0
	var n := 0
	for h in living():
		for c in combat_cards(h): n += c.get("imprints", []).size()
	return n
func find_card(id) -> Variant:
	for h in hero_list():
		for pile in [h["hand"], h["draw"], h["discard"], h.get("vanished", []), h["deck"]]:
			for c in pile:
				if c["id"] == id: return {"h": h, "c": c}
	return null
func link_partner(c: Dictionary) -> Variant:
	if not T(c.get("link")) or S.get("links") == null or not S["links"].has(c["link"]): return null
	var L: Dictionary = S["links"][c["link"]]
	return find_card(L["b"] if L["a"] == c["id"] else L["a"])
func resolve_imprint_type(t: String, s: Dictionary) -> String:
	if t == "smart": return "edge" if T(s.dmg) else "ward"
	return t
func imprint_ok(t: String, c: Dictionary) -> bool:
	var d = CARDS.get(c["key"])
	if d == null or T(d.get("unplayable")): return false
	var s := stats(c)
	if t == "edge": return s.dmg > 0
	if t == "haste": return s.cost > 0
	if t == "echo": return not c.get("imprints", []).any(func(x): return x["type"] == "echo")
	return true
func add_imprint(c: Dictionary, type: String, n: int, by, perm := false) -> void:
	if not c.has("imprints"): c["imprints"] = []
	for x in c["imprints"]:
		if x["type"] == type:
			if type != "echo": x["n"] += n
			if perm: x["perm"] = true
			return
	c["imprints"].append({"type": type, "n": n, "by": by, "perm": perm})
func link_cards(c1: Dictionary, c2: Dictionary, resonant: bool) -> void:
	if S.get("links") == null: S["links"] = {}
	S["linkSeq"] = nz(S, "linkSeq") + 1
	var id := "L%d" % S["linkSeq"]
	S["links"][id] = {"a": c1["id"], "b": c2["id"], "hue": D["LINK_HUES"][(S["linkSeq"] - 1) % D["LINK_HUES"].size()], "n": S["linkSeq"]}
	c1["link"] = id; c2["link"] = id
	if resonant: c1["resonant"] = true; c2["resonant"] = true
func gift_for(t: Dictionary) -> String:
	if GIFT_BY_SPEC.has(t.get("spec")): return GIFT_BY_SPEC[t["spec"]]
	return D["GIFT_BY_CLASS"].get(t["id"], "soulspark")
func craft_cards(h: Dictionary, craft: Dictionary, target) -> void:
	var to: Array
	if craft.get("to") == "all": to = living()
	elif craft.get("to") == "ally":
		var others := living().filter(func(y): return not is_same(y, h))
		JS.jsort(others, func(a, b): return a["hand"].size() - b["hand"].size())
		to = [others[0] if others.size() else h]
	else: to = [target if target != null and T(target.get("hero")) and not target["dead"] else h]
	for t in to:
		var key: String = gift_for(t) if craft["kind"] == "gift" else craft["kind"]
		for k in craft["n"]:
			var nc := new_card(key); nc["tmp"] = true; nc["by"] = h["id"]
			if craft.get("where") == "draw":
				var at := JS.flr(rng() * (t["draw"].size() + 1)); t["draw"].insert(at, nc)
			else: t["hand"].append(nc)
		float_text(t, "+%d %s%s%s" % [craft["n"], CARDS[key]["name"], "s" if craft["n"] > 1 else "", " (deck)" if craft.get("where") == "draw" else ""], "status-f")
		if not is_same(t, h): soul_beam(h, t, "#ffb03a")
		if S["active"] == t["id"]: render_hand()
		else: update_unit(t)
func pick_eligible(h: Dictionary, c: Dictionary, s: Dictionary) -> Array:
	var hands := []
	for y in living():
		for z in y["hand"]:
			if (not is_same(z, c) and not T(z.get("tmp"))) or (not is_same(z, c) and s.imprint != null and T(z.get("tmp"))):
				hands.append({"h": y, "c": z})
	if T(s.link): return hands.filter(func(o): return not T(o.c.get("link")) and not T(CARDS[o.c["key"]].get("unplayable")) and not T(o.c.get("tmp")))
	if s.amplify: return hands.filter(func(o): return o.c.get("imprints", []).size() > 0)
	if s.imprint != null:
		var t: String = s.imprint["type"]
		return hands.filter(func(o): return not T(CARDS[o.c["key"]].get("unplayable")) if t == "smart" or t == "master" else imprint_ok(t, o.c))
	return []
func pick_count(s: Dictionary) -> int:
	if T(s.link): return s.link * 2
	if s.imprint != null: return orv(s, "imprintCards", 1)
	return 1 if s.amplify else 0
func card_worth(o: Dictionary) -> float:
	var s := stats(o.c)
	return (s.dmg * s.hits * (1.5 if s.aoe else 1.0) + s.block + s.blockAll + s.heal) + s.cost * 2
func auto_pick(h: Dictionary, c: Dictionary, s: Dictionary) -> Array:
	var el := pick_eligible(h, c, s)
	var n := pick_count(s)
	var prio := func(o): return (-100 if T(o.h.get("turnDone")) else 0) + (8 if not is_same(o.h, h) else 0)
	if T(s.link):
		var out := []
		for p in s.link:
			var free := el.filter(func(o): return not out.has(o.c["id"]))
			JS.jsort(free, func(a, b): return prio.call(b) + card_worth(b) - prio.call(a) - card_worth(a))
			if free.is_empty(): break
			var first = free[0]
			var second = null
			for o in free:
				if not is_same(o, first) and not is_same(o.h, first.h): second = o; break
			if second == null:
				for o in free:
					if not is_same(o, first): second = o; break
			if second == null: break
			out.append(first.c["id"]); out.append(second.c["id"])
		return out
	var t = s.imprint["type"] if s.imprint != null else null
	var score := func(o):
		var stt := stats(o.c)
		var v: float = prio.call(o)
		if t == "edge" or ((t == "smart" or t == "master") and T(stt.dmg)): v += stt.hits * (2 if stt.aoe else 1) * 4 * orv(stt, "repeats", 1)
		elif t == "haste": v += stt.cost * 4
		elif t == "echo": v += card_worth(o)
		else: v += 4 - stt.cost
		if s.amplify:
			var sm := 0
			for x in o.c.get("imprints", []): sm += x["n"]
			v += sm * 3
		return v
	JS.jsort(el, func(a, b): return score.call(b) - score.call(a))
	return el.slice(0, n).map(func(o): return o.c["id"])
func soul_effects(h: Dictionary, c: Dictionary, s: Dictionary, target) -> void:
	if T(s.link) or s.imprint != null or s.amplify:
		var ids: Array = S["playPick"] if typeof(S.get("playPick")) == TYPE_ARRAY else auto_pick(h, c, s)
		var ok := {}
		for o in pick_eligible(h, c, s): ok[o.c["id"]] = true
		var chosen := []
		for id in ids:
			var o = find_card(id)
			if o != null and ok.has(o.c["id"]) and JS.has(o.h["hand"], o.c): chosen.append(o)
		if T(s.link):
			var p := 0
			while p + 1 < chosen.size():
				var A: Dictionary = chosen[p]
				var B: Dictionary = chosen[p + 1]
				p += 2
				if T(A.c.get("link")) or T(B.c.get("link")) or is_same(A.c, B.c): continue
				link_cards(A.c, B.c, s.linkResonant)
				float_text(A.h, "Soulbound!", "status-f")
				if not is_same(B.h, A.h): float_text(B.h, "Soulbound!", "status-f")
				soul_beam(A.h, B.h, S["links"][A.c["link"]]["hue"])
				if T(s.linkBlock):
					gain_block(A.h, s.linkBlock, true)
					if not is_same(B.h, A.h): gain_block(B.h, s.linkBlock, true)
		if s.imprint != null:
			var bonus := 0
			for o in chosen:
				var kinds: Array = [["edge", s.imprint["n"]], ["ward", s.imprint["n"]], ["haste", 1]] if s.imprint["type"] == "master" else [[resolve_imprint_type(s.imprint["type"], stats(o.c)), s.imprint["n"]]]
				for kn in kinds:
					var k: String = kn[0]
					if k == "edge" and not T(stats(o.c).dmg): continue
					if k == "haste" and not T(stats(o.c).cost): continue
					for rr in orv(s, "imprintTimes", 1): add_imprint(o.c, k, kn[1] + bonus if k in ["edge", "ward", "mend"] else kn[1], h["id"], s.imprintPerm)
				float_text(o.h, "Imprint: %s" % card_name(o.c), "gold-f")
				if not is_same(o.h, h): soul_beam(h, o.h, "#b47cff")
				if S["active"] == o.h["id"]: render_hand()
				else: update_unit(o.h)
		if s.amplify:
			for o in chosen:
				for x in o.c.get("imprints", []):
					if x["type"] != "echo": x["n"] *= 2
				float_text(o.h, "Runes doubled!", "gold-f")
	if s.resonateAll:
		var n := 0
		for y in living():
			for z in y["hand"]:
				if T(z.get("link")) and not T(z.get("resonant")): z["resonant"] = true; n += 1
		if n: float_text(h, "%d Resonating!" % n, "crit-f")
	if s.craft != null: craft_cards(h, s.craft, target)
	if T(s.drawAll):
		for y in living():
			if not is_same(y, h): draw_cards(y, s.drawAll)
		draw_cards(h, s.drawAll)
	render_hand()
	for y in hero_list(): update_unit(y)
func soul_link_trigger(h: Dictionary, c: Dictionary, was_resonant: bool) -> void:
	if not T(c.get("link")) or S.get("links") == null or not S["links"].has(c["link"]): return
	var p = link_partner(c)
	var L: Dictionary = S["links"][c["link"]]
	if was_resonant:
		c["resonant"] = false
		float_text(h, "Soul Surge!", "crit-f")
		if p != null:
			soul_beam(h, p.h, L["hue"], true)
			if not p.h["dead"]: draw_cards(p.h, 1)
		var weavers := living().filter(func(y): return y.get("spec") == "chainweaver")
		if weavers.size() and alive().size():
			var dmg := 3 * active_links() * weavers.size()
			await sleep(150)
			for e in alive().duplicate():
				deal_damage(e, dmg); float_text(e, "Soul Network", "crit-f")
				if e["hp"] <= 0: kill_enemy(e)
			await sleep(250)
	elif p != null and not T(p.c.get("resonant")):
		p.c["resonant"] = true; float_text(p.h, "Resonance!", "crit-f"); soul_beam(h, p.h, L["hue"])
		if S["active"] == p.h["id"]: render_hand()
		else: update_unit(p.h)
func kinship(c: Dictionary) -> void:
	if not T(c.get("by")): return
	var f = S["heroes"].get(c["by"])
	if f == null or f["dead"] or f.get("spec") != "soulforger": return
	if nz(f, "kinshipGot") >= 3: return
	f["kinshipGot"] = nz(f, "kinshipGot") + 1
	f["energy"] = mini(MAX_SAVED_ENERGY, f["energy"] + 1); float_text(f, "+1 Energy (Kinship)", "blk"); update_unit(f)
func clear_soul_state(h: Dictionary) -> void:
	for c in h["deck"]:
		c.erase("link"); c.erase("resonant")
		if c.has("imprints"):
			c["imprints"] = c["imprints"].filter(func(x): return T(x.get("perm")))
			if c["imprints"].is_empty(): c.erase("imprints")
func lasting_etch() -> void:
	if not hero_list().any(func(y): return y.get("spec") == "runebinder" and not y["dead"]): return
	var pool := []
	for h in hero_list():
		for c in h["deck"]:
			for x in c.get("imprints", []):
				if not T(x.get("perm")): pool.append({"h": h, "c": c, "x": x})
	if pool.is_empty(): return
	var o: Dictionary = pool[JS.flr(rng() * pool.size())]
	o.x["perm"] = true
	toast("Lasting Etch: %s on %s's %s is now permanent!" % [D["IMPRINTS"][o.x["type"]]["name"], o.h["name"], card_name(o.c)])

# ---------- Eldritch Horror ----------
func tiers_of(d: Dictionary) -> Variant:
	if T(d.get("tiers")): return d["tiers"]
	var eh = S.get("heroes", {}).get("eldritch")
	if d.get("char") != "eldritch" or T(d.get("crafted")) or eh == null or eh.get("spec") != "acolyte": return null
	return D["ACOLYTE_TIERS"].get(d["type"])
func apply_tiers(s: Dictionary, d: Dictionary) -> void:
	var tiers = tiers_of(d)
	if tiers == null: return
	var cor := corruption_of()
	for tier in tiers:
		if cor < tier[0]: continue
		var fxs: Dictionary = tier[1]
		for k in fxs:
			var v = fxs[k]
			if k == "morph":
				if typeof(v) == TYPE_STRING and v == "auto":
					var base: int = maxi(s.block, s.blockAll * 2)
					s.aoe = T(d.get("blockAll")); s.dmg = base; s.leechFlat = JS.cel(base / 2.0)
				else: s.dmg = v["dmg"]; s.leechFlat = v["leech"]
				s.block = 0; s.blockAll = 0; s.morphed = true
			elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT: s[k] = nz(s, k) + v
			else: s[k] = v
func add_corruption(h: Dictionary, n: int) -> void:
	if not n or h["id"] != "eldritch": return
	var before := corrupt_stage(h)
	var over := maxi(0, nz(h, "corruption") + n - 100)
	h["corruption"] = mini(100, nz(h, "corruption") + n)
	if over and h.get("spec") == "acolyte": h["sanity"] = maxi(0, sanity_of(h) - over); float_text(h, "-%d Sanity" % over, "status-f")
	float_text(h, "+%d Corruption" % n, "poison-f")
	if corrupt_stage(h) > before: toast("%s is changing… (%d Corruption)" % [h["name"], h["corruption"]]); retrigger(h, "shield")
	update_unit(h); render_hand()
func eldritch_turn_start(h: Dictionary) -> bool:
	if h["id"] != "eldritch" or h["dead"]: return false
	if h.get("spec") == "tidecaller": gain_depth(h, 1)
	if h.get("spec") != "acolyte": return false
	var loss := JS.flr(nz(h, "corruption") / 10.0)
	if loss:
		h["sanity"] = maxi(0, (h["sanity"] if h.get("sanity") != null else SANITY_MAX) - loss); float_text(h, "-%d Sanity" % loss, "status-f")
	if h["sanity"] <= 0:
		h["sanity"] = SANITY_MAX; h["mindStun"] = true; h["turnDone"] = true; h["energy"] = 0
		float_text(h, "Corrupted Mind!", "dmg"); update_unit(h); return true
	update_unit(h); return false
func nightmare(e: Dictionary) -> void:
	if e["dead"]: return
	e["status"].erase("dream")
	float_text(e, "NIGHTMARE!", "crit-f"); retrigger(e, "hit")
	lose_hp(e, JS.rnd(e["maxHp"] * (NIGHTMARE_BOSS_PCT if T(e.get("boss")) else NIGHTMARE_PCT)), "crit-f")
	if e["hp"] <= 0: kill_enemy(e)
func mind_stun_enemy(e: Dictionary) -> void:
	if e["dead"] or T(e.get("mindCD")): return
	e["mindStun"] = true; float_text(e, "Corrupted Mind", "status-f"); update_unit(e)
func add_dream(e: Dictionary, n: int) -> void:
	if not n or e["dead"] or T(e.get("hero")): return
	apply_status(e, "dream", n)
	if st(e, "dream") >= DREAM_MAX: nightmare(e)
func gain_depth(h: Dictionary, n: int) -> void:
	if not n or h["dead"]: return
	h["status"]["depth"] = st(h, "depth") + n; float_text(h, "+%d Depth" % n, "blk"); update_unit(h)
func servants_of(h: Dictionary) -> Array:
	if not T(h.get("servants")) and typeof(h.get("servants")) != TYPE_ARRAY: h["servants"] = []
	return h["servants"]
func summon_servant(h: Dictionary, key: String) -> void:
	var sv: Dictionary = SERVANTS[key]
	var lst := servants_of(h)
	if lst.size() >= SERVANT_MAX:
		var k := -1
		for i in lst.size():
			if lst[i]["id"] == S.get("playReplace"): k = i; break
		var gone: Dictionary = lst[k if k >= 0 else 0]
		lst.remove_at(k if k >= 0 else 0)
		float_text(h, "%s returns to the deep" % SERVANTS[gone["key"]]["name"], "status-f")
	lst.append({"key": key, "atk": sv["atk"], "id": uid}); uid += 1
	float_text(h, "%s!" % sv["name"], "crit-f")
	if key == "guardian": gain_block(h, 8, true)
	if key == "sleeper":
		for y in living(): gain_block(y, 10, true); draw_cards(y, 1)
	update_unit(h)
func servants_act(h: Dictionary) -> void:
	var lst := servants_of(h)
	if lst.is_empty() or h["dead"]: return
	for sv in lst.duplicate():
		if alive().is_empty(): break
		var d: Dictionary = SERVANTS[sv["key"]]
		if not T(sv["atk"]): continue
		if T(d.get("aoe")):
			for e in alive().duplicate():
				deal_damage(e, sv["atk"])
				if e["hp"] <= 0: kill_enemy(e)
		else:
			var e: Dictionary = pick(alive()); deal_damage(e, sv["atk"])
			if e["hp"] <= 0: kill_enemy(e)
		if sv["key"] == "leviathan": gain_depth(h, 1)
		await sleep(220)
	for e in S["enemies"].duplicate():
		if T(e.get("boss")) and not e["dead"]: await check_boss_phase(e)
func eldritch_effects(h: Dictionary, c: Dictionary, s: Dictionary, target) -> void:
	var enemy = target if target != null and not T(target.get("hero")) and not target["dead"] else null
	if T(s.corrupt): add_corruption(h, s.corrupt)
	if T(s.sanity) and h["id"] == "eldritch":
		h["sanity"] = mini(SANITY_MAX, (h["sanity"] if h.get("sanity") != null else SANITY_MAX) + s.sanity)
		float_text(h, "+%d Sanity" % s.sanity, "heal-f"); update_unit(h)
	if s.mindStun and enemy != null: mind_stun_enemy(enemy)
	if T(s.leechFlat): heal(h, s.leechFlat)
	if T(s.dream) and enemy != null and not T(s.dmg): add_dream(enemy, s.dream)
	if T(s.dreamStun) and enemy != null and not enemy["dead"] and st(enemy, "dream") >= s.dreamStun: mind_stun_enemy(enemy)
	if T(s.dreamAll):
		for e in alive().duplicate(): add_dream(e, s.dreamAll)
	if s.dreamDouble and enemy != null and T(enemy["status"].get("dream")): add_dream(enemy, enemy["status"]["dream"])
	if T(s.spread) and enemy != null and T(enemy["status"].get("dream")):
		var n := JS.flr(enemy["status"]["dream"] * s.spread)
		for e in alive().filter(func(y): return not is_same(y, enemy)): add_dream(e, n)
	if s.collapse != null and enemy != null and T(enemy["status"].get("dream")):
		var n: int = enemy["status"]["dream"]; enemy["status"].erase("dream"); update_unit(enemy)
		float_text(enemy, "Collapse!", "crit-f"); deal_damage(enemy, n * s.collapse["per"])
		if enemy["hp"] <= 0: kill_enemy(enemy)
		elif JS.flr(float(n) / s.collapse["weakPer"]): apply_status(enemy, "weak", JS.flr(float(n) / s.collapse["weakPer"]))
		await sleep(250)
	if s.eatAll != null:
		var total := 0
		for e in alive().duplicate():
			var n: int = st(e, "dream")
			if not n: continue
			e["status"].erase("dream"); total += n; deal_damage(e, n * s.eatAll["per"])
			if e["hp"] <= 0: kill_enemy(e)
		if total: heal(h, total * s.eatAll["heal"]); float_text(h, "Dreams devoured", "crit-f")
		await sleep(250)
	if T(s.allyDraw):
		var t = target if target != null and T(target.get("hero")) and not target["dead"] else h
		draw_cards(t, s.allyDraw)
	if T(s.depthGain): gain_depth(h, s.depthGain)
	if s.summon != null:
		h["status"]["depth"] = maxi(0, st(h, "depth") - s.depthCost); summon_servant(h, s.summon)
	for k in nz(s, "gemSummonN"):
		var cost: int = SERVANTS[s.gemSummon]["depth"]
		if st(h, "depth") < cost: float_text(h, "Not enough Depth", "status-f"); break
		h["status"]["depth"] -= cost; summon_servant(h, s.gemSummon)
	var lst := servants_of(h)
	if T(s.feed) and lst.size():
		var cand := lst.filter(func(y): return T(y["atk"]))
		JS.jsort(cand, func(a, b): return b["atk"] - a["atk"])
		if cand.size():
			cand[0]["atk"] += s.feed; float_text(h, "%s +%d" % [SERVANTS[cand[0]["key"]]["name"], s.feed], "gold-f")
	if s.sacrifice != null and lst.size():
		var srt := lst.duplicate()
		JS.jsort(srt, func(a, b): return a["atk"] - b["atk"])
		var sv: Dictionary = srt[0]
		h["servants"] = JS.without(lst, sv); float_text(h, "Sacrificed %s" % SERVANTS[sv["key"]]["name"], "status-f")
		if T(s.sacrifice.get("depth")): gain_depth(h, s.sacrifice["depth"])
		if T(s.sacrifice.get("draw")): draw_cards(h, s.sacrifice["draw"])
		if T(s.sacrifice.get("blockAll")):
			for y in living(): gain_block(y, s.sacrifice["blockAll"] + JS.flr(sv["atk"] / 2.0), true)
	if T(s.fuse):
		var small := lst.filter(func(y): return y["key"] == "spawn")
		JS.jsort(small, func(a, b): return a["atk"] - b["atk"])
		if small.size() >= 2:
			var a: Dictionary = small[0]
			var b: Dictionary = small[1]
			h["servants"] = JS.without(lst, b); a["atk"] = a["atk"] + b["atk"] + s.fuse; float_text(h, "Fused!", "crit-f")
	update_unit(h)

# ---------- Gestaltwandler-Boss ----------
func shift_form(e: Dictionary, form = null) -> void:
	var opts: Array = D["SHIFT_FORMS"].keys().filter(func(f): return f != e.get("form"))
	e["form"] = form if form != null else opts[JS.flr(rng() * opts.size())]
	var F: Dictionary = D["SHIFT_FORMS"][e["form"]]
	e["passive"]["armor"] = nz(F, "armor")
	e["name"] = "Morrgan (%s)" % F["name"]
	fx.emit("shift", {"u": e, "art": F["art"]})

# =====================================================================
#   GEGNER-KI (1:1 aus der Browser-Version) – Stand 22.11.2026 (Biom-Umbau)
# =====================================================================
func basic_ai(e: Dictionary) -> Dictionary:
	if e.get("lastMove") == "block" or rng() < e["atkChance"]: return {"dmg": rand(e["atk"][0], e["atk"][1]), "name": "Attack"}
	return {"block": rand(e["blk"][0], e["blk"][1]), "name": "Defend"}

func enemy_ai(e: Dictionary) -> Dictionary:
	var t: int = e["turn"]
	match e["ai"]:
		"basic": return basic_ai(e)
		# ---- Normale Gegner ----
		"bat": return {"dmg": 2, "hits": 3, "name": "Blood Frenzy"} if t % 3 == 0 else {"dmg": rand(4, 5), "name": "Bite"}
		"slime": return [{"block": 7, "name": "Harden"}, {"dmg": 3, "poison": 2, "name": "Acid Spit"}, {"dmg": 6, "name": "Body Slam"}][t % 3]
		"goblin":
			var rr := rng()
			if e.get("lastName") != "Dirty Trick" and rr < 0.3: return {"dmg": 3, "weak": 1, "name": "Dirty Trick"}
			if rr < 0.7: return {"dmg": 6, "name": "Stab"}
			return {"dmg": 2, "hits": 2, "name": "Throw Daggers"}
		"skeleton": return [{"block": 9, "strength": 1, "name": "Reassemble"}, {"dmg": 7, "name": "Rusty Slash"}, {"dmg": 4, "brittle": 1, "name": "Bone Crack"}][t % 3]
		"orc":
			if t == 1: return {"strength": 2, "block": 5, "name": "War Cry"}
			return {"dmg": 11, "name": "Smash"} if t % 2 == 0 else {"dmg": 6, "hits": 2, "name": "Double Chop"}
		"rat": return {"dmg": 3, "poison": 2, "name": "Plague Bite"} if t % 2 else {"dmg": 5, "name": "Gnaw"}
		"spider": return {"dmg": 2, "weak": 1, "name": "Web Shot"} if t % 3 == 1 else {"dmg": 4, "hits": 2, "name": "Double Bite"}
		"cultist": return {"strength": 2, "name": "Dark Ritual"} if t == 1 else {"dmg": 4, "strength": 1, "name": "Ritual Strike"}
		"archer": return {"dmg": 3, "hits": 3, "name": "Arrow Volley"} if t % 2 else {"dmg": 7, "name": "Aimed Shot"}
		"fireimp": return {"dmg": 4, "burn": 3, "name": "Fire Bolt"} if t % 2 else {"dmg": 3, "hits": 2, "burn": 1, "name": "Ember Spray"}
		"ghoul": return {"dmg": 3, "hits": 2, "name": "Frenzy"} if t % 3 == 0 else {"dmg": 7, "name": "Rend"}
		"shellbeast": return {"block": 10, "name": "Curl Up"} if t % 2 else {"dmg": 10, "name": "Shell Ram"}
		"wisp": return {"dmg": 6, "weak": 1, "name": "Lure"} if t % 2 else {"dmg": 3, "hits": 2, "name": "Flicker"}
		"darkknight": return [{"block": 14, "name": "Shield Wall"}, {"dmg": 12, "brittle": 1, "name": "Crushing Blow"}, {"dmg": 6, "hits": 2, "name": "Twin Cut"}][t % 3]
		"gargoyle": return {"block": 22, "name": "Stone Form"} if t % 2 else {"dmg": 17, "name": "Dive"}
		# ---- Elites ----
		"wraith": return {"dmg": 4, "hits": 2, "brittle": 1, "name": "Corrode"} if t % 3 == 2 else {"dmg": 7, "brittle": 1, "name": "Rust Grasp"}
		"warchief": return {"summon": "grunt", "dmg": 5, "name": "Call to Arms"} if alive().size() < 5 else {"dmg": 11, "name": "Cleaving Axe"}
		"colossus": return {"dmg": 6, "strength": 3, "name": "Crushing Fist"}
		"witch": return {"dmg": 6, "poison": 3, "name": "Toxic Bolt"} if t % 2 else {"poison": 5, "block": 8, "name": "Miasma"}
		"bramble": return {"dmg": 10, "name": "Thorn Slam"} if t % 2 else {"block": 12, "dmg": 5, "name": "Bark Shield"}
		"vampire": return {"dmg": 4, "hits": 3, "name": "Blood Feast"} if t % 3 == 0 else {"dmg": 9, "name": "Drain Bite"}
		"lich": return {"hex": 2, "block": 8, "name": "Curse"} if t % 3 == 1 else {"dmg": 11, "name": "Soul Bolt"}
		"juggernaut":
			if t % 3 == 0: return {"dmg": 18, "name": "Steamroll"}
			return {"block": 14, "dmg": 6, "name": "Grind"} if t % 3 == 1 else {"dmg": 9, "brittle": 1, "name": "Piston Punch"}
		"berserker": return {"dmg": 5, "hits": 2, "name": "Twin Axes"} if t % 2 else {"dmg": 11, "name": "Reckless Chop"}
		"necromancer":
			var minions := alive().filter(func(m): return T(m.get("minion"))).size()
			if minions < 2 and alive().size() < 5: return {"summon": "bones", "block": 8, "name": "Raise Dead"}
			if t % 2: return {"healAllies": 10, "dmg": 6, "name": "Dark Mending"}
			return {"dmg": 5, "hits": 2, "weak": 1, "name": "Soul Drain"}
		"slimeking": return [{"dmg": 12, "name": "Royal Slam"}, {"dmg": 5, "poison": 3, "name": "Acid Wave"}, {"block": 15, "strength": 1, "name": "Absorb"}][t % 3]
		"phantom": return {"dmg": 14, "name": "Lunge"} if t % 2 else {"dmg": 4, "hits": 3, "name": "Flurry"}
		"leech": return {"dmg": 6, "drain": 2, "name": "Mana Drain"} if t % 2 else {"dmg": 10, "name": "Latch On"}
		"shaman":
			if t % 3 == 0: return {"dmg": 6, "hits": 4, "name": "Lightning Storm!"}
			return {"block": 10, "strength": 1, "name": "Gather Storm (1/2)"} if t % 3 == 1 else {"block": 10, "strength": 1, "name": "Gather Storm (2/2)"}
		"hydraHeadL": return {"dmg": 7, "name": "Bite"} if t % 2 else {"dmg": 4, "hits": 2, "name": "Snap"}
		"hydraBody": return {"block": 10, "name": "Harden Scales"} if t % 2 else {"dmg": 9, "name": "Tail Lash"}
		"hydraHeadR": return {"dmg": 4, "poison": 2, "name": "Venom Spit"} if t % 2 else {"dmg": 7, "name": "Bite"}
		"twinfire": return {"dmg": 5, "burn": 3, "name": "Searing Touch"} if t % 2 else {"dmg": 9, "name": "Flame Lash"}
		"twinice": return {"block": 12, "weak": 1, "name": "Frost Veil"} if t % 2 else {"dmg": 10, "name": "Ice Spear"}
		# ---- Unterstützer ----
		"drummer": return {"rallyStr": 2, "name": "War Drums"} if t % 2 else {"dmg": 3, "name": "Drumstick"}
		"acolyte": return {"healLow": 9, "name": "Dark Mending"} if t % 2 else {"dmg": 3, "weak": 1, "name": "Hex Bolt"}
		"sporeling": return {"healAllies": 5, "name": "Healing Spores"} if t % 2 else {"dmg": 2, "poison": 2, "name": "Spore Puff"}
		"shieldbearer": return {"blockAllies": 7, "name": "Shield Wall"} if t % 2 else {"dmg": 4, "name": "Shield Bash"}
		# ---- Bosse ----
		"boss":                                                # Malgrath (Ewige Nacht)
			if e["phase"] == 1: return [{"atk": "front", "dmg": 15, "name": "Sovereign's Edge"}, {"atk": "normal", "dmg": 10, "brittle": 1, "name": "Dread Command"}, {"block": 20, "strength": 2, "name": "Iron Will"}][(t - 1) % 3]
			if e["phase"] == 2:
				var imps := alive().filter(func(m): return m["key"] == "imp").size()
				if imps < 2 and t % 3 == 1: return {"summon": "imp", "block": 12, "name": "Call the Shadows"}
				return {"atk": "aoe", "dmg": 6, "hits": 2, "burn": 2, "name": "Hellfire"} if t % 2 == 0 else {"atk": "pierce", "dmg": 15, "name": "Molten Cleave"}
			return {"block": 25, "strength": 3, "name": "Gathering Doom (Cataclysm next!)"} if t % 2 == 1 else {"atk": "aoe", "dmg": 19, "name": "Cataclysm"}
		"aegis":                                               # Vaelor (Gipfel)
			var low: bool = e["hp"] < e["maxHp"] / 2.0
			if t % 3 == 1: return {"aegis": 24 if low else 18, "atk": "normal", "dmg": 8, "name": "Raise Aegis"}
			if t % 3 == 2: return {"atk": "pierce", "dmg": 30 if low else 24, "needsAegis": true, "name": "Annihilation Beam"}
			return {"atk": "front", "dmg": 10, "hits": 2, "brittle": 1, "name": "Shield Bash"}
		"wolfform":                                            # Morrgan (Wald)
			match e.get("form", "wolf") if T(e.get("form")) else "wolf":
				"bear": return {"atk": "front", "dmg": 12, "block": 14, "name": "Maul"}
				"serpent": return {"atk": "splash", "dmg": 5, "poison": 3, "weak": 1, "name": "Venom Fang"}
				"hawk": return {"atk": "normal", "dmg": 6, "hits": 2, "brittle": 1, "name": "Diving Talons"}
				_: return {"atk": "back", "dmg": 4, "hits": 3, "name": "Flanking Pounce"}
		"b_khepri":                                            # Khepri (Wüste)
			if e["phase"] == 1: return [{"atk": "pierce", "dmg": 16, "name": "Solar Beam"}, {"atk": "aoe", "dmg": 7, "burn": 2, "name": "Sun Flare"}, {"block": 22, "name": "Golden Shell"}][(t - 1) % 3]
			if e["phase"] == 2: return [{"burrow": 1, "summon": "scarab", "block": 10, "name": "Sand Tomb"}, {"atk": "aoe", "dmg": 7, "weak": 1, "name": "Quicksand"}, {"atk": "front", "dmg": 20, "name": "Emerge"}][(t - 1) % 3]
			return {"atk": "aoe", "dmg": 11, "burn": 2, "name": "Eclipse"} if t % 2 else {"atk": "front", "dmg": 24, "leech": 1, "name": "Devour the Sun"}
		# ---- Biome ----
		"move": return move_ai(e)
		"grunt", "imp", "bones":
			if e.get("lastMove") == "block" or rng() < e["atkChance"]: return {"atk": "normal", "dmg": rand(e["atk"][0], e["atk"][1]), "name": "Attack"}
			return {"block": rand(e["blk"][0], e["blk"][1]), "name": "Defend"}
		"b_burrower": return {"burrow": 1, "block": 6, "name": "Burrow"} if t % 2 else {"atk": "back", "dmg": 13, "name": "Ambush"}
		"el_thornwood": return [{"atk": "front", "dmg": 16, "name": "Root Smash"}, {"atk": "aoe", "dmg": 6, "name": "Thorn Barrage"}, {"block": 18, "thornsUp": 1, "name": "Barkskin"}][(t - 1) % 3]
		"el_bloodbloom":
			var sp := alive().filter(func(m): return T(m.get("minion"))).size()
			if t % 4 == 1 and sp < 2 and alive().size() < 5: return {"summon": "sprout", "block": 8, "name": "Royal Seedling"}
			if alive().any(func(o): return o["hp"] < o["maxHp"] * 0.7) and t % 2 == 0: return {"healAllies": 10, "name": "Royal Nectar"}
			return {"atk": "splash", "dmg": 9, "poison": 2, "name": "Pollen Burst"} if t % 3 else {"atk": "aoe", "dmg": 5, "name": "Petal Storm"}
		"el_b_briarblade": return {"atk": "pierce", "dmg": 10, "name": "Thorn Lunge"} if t % 2 else {"atk": "front", "dmg": 13, "name": "Cross Cut"}
		"el_b_thornblade": return {"atk": "aoe", "dmg": 5, "name": "Whirling Thorns"} if t % 2 else {"atk": "back", "dmg": 11, "name": "Backstab"}
		"el_bramblegolem": return [{"atk": "front", "dmg": 14, "taunt": 1, "name": "Thorn Hug"}, {"atk": "splash", "dmg": 8, "name": "Bramble Burst"}, {"healSelf": 12, "block": 8, "name": "Regrowth"}][(t - 1) % 3]
		"el_vampirelord":
			if t % 4 == 3 and alive().size() < 5: return {"summon": "nightbat", "block": 10, "name": "Bat Swarm"}
			return {"atk": "normal", "dmg": 13, "name": "Drain Bite"} if t % 2 else {"atk": "aoe", "dmg": 4, "hits": 3, "name": "Blood Feast"}
		"el_lichking": return [{"hex": 2, "block": 9, "name": "Curse of Ages"}, {"atk": "back", "dmg": 15, "name": "Soul Spear"}, {"atk": "aoe", "dmg": 7, "weak": 1, "name": "Frost Nova"}][(t - 1) % 3]
		"el_necromancer":
			var mn := alive().filter(func(o): return T(o.get("minion"))).size()
			if mn < 2 and alive().size() < 5: return {"summon": "bones", "block": 8, "name": "Raise Dead"}
			return {"healAllies": 10, "atk": "normal", "dmg": 7, "name": "Dark Mending"} if t % 2 else {"atk": "splash", "dmg": 7, "weak": 1, "name": "Soul Drain"}
		"el_phantomduel": return {"atk": "pierce", "dmg": 15, "name": "Lunge"} if t % 2 else {"atk": "normal", "dmg": 5, "hits": 3, "name": "Flurry"}
		"el_juggernaut": return [{"atk": "front", "dmg": 18, "name": "Steamroll"}, {"block": 14, "atk": "normal", "dmg": 7, "name": "Grind"}, {"atk": "pierce", "dmg": 10, "brittle": 1, "name": "Piston Punch"}][t % 3]
		"el_granitetitan": return [{"atk": "aoe", "dmg": 7, "name": "Earthquake"}, {"atk": "front", "dmg": 16, "name": "Titan Fist"}, {"block": 16, "bulwark": 30, "name": "Stone Skin"}][(t - 1) % 3]
		"el_dwarfthane":
			if t % 4 == 1 and alive().size() < 5: return {"summon": "pebble", "rallyStr": 1, "name": "War Horn"}
			return {"atk": "front", "dmg": 15, "name": "Hammerfall"} if t % 2 else {"atk": "pierce", "dmg": 11, "blockAllies": 6, "name": "Shield Throw"}
		"el_runeshaman": return {"atk": "aoe", "dmg": 6, "hits": 4, "name": "Lightning Storm!"} if t % 3 == 0 else {"block": 10, "strength": 1, "atk": "normal", "dmg": 6, "name": "Gather Storm (%d/2)" % (t % 3)}
		"el_colossalworm": return [{"burrow": 1, "block": 10, "name": "Burrow"}, {"atk": "aoe", "dmg": 9, "name": "Erupt"}, {"atk": "front", "dmg": 17, "leech": 1, "name": "Devour"}][(t - 1) % 3]
		"el_scarabqueen":
			if t % 3 == 1 and alive().size() < 5: return {"summon": "scarab", "block": 10, "name": "Hatch Brood"}
			return {"atk": "splash", "dmg": 9, "poison": 2, "name": "Acid Spray"} if t % 3 == 2 else {"block": 14, "rallyStr": 1, "atk": "normal", "dmg": 8, "name": "Royal Mandible"}
		"el_cactuswarlord": return [{"atk": "aoe", "dmg": 6, "name": "Whirling Scimitars"}, {"atk": "pierce", "dmg": 12, "name": "Spine Lance"}, {"atk": "front", "dmg": 7, "hits": 2, "name": "Desert Fury"}][(t - 1) % 3]
		"el_miragedjinn": return [{"atk": "aoe", "dmg": 7, "name": "Sand Blast"}, {"atk": "back", "dmg": 13, "name": "Mirage Strike"}, {"weak": 1, "brittle": 1, "block": 8, "name": "Sandstorm Curse"}][(t - 1) % 3]
		"smith":
			if t == 1: return {"strength": 2, "block": 8, "name": "Stoke the Forge"}
			if t % 3 == 2: return {"dmg": 13, "name": "Hammer Blow"}
			if t % 3 == 0: return {"dmg": 5, "burn": 3, "name": "Molten Spray"}
			return {"block": 12, "strength": 1, "name": "Temper"}
	push_error("Unbekannte Gegner-KI: %s" % e["ai"])
	return basic_ai(e)

## Boss-Phasen (BOSS_PHASES in der HTML)
func boss_phase_enter(pk: String, phase: int, e: Dictionary) -> void:
	if pk == "boss" and phase == 2:
		apply_status(e, "strength", 3); await sleep(250)
		var k := 0
		while k < 2 and alive().size() < 5: await summon_minion(e, "imp"); k += 1
	elif pk == "boss" and phase == 3:
		gain_block(e, JS.rnd(30 * e["mult"])); e["passive"]["lifesteal"] = 1
	elif pk == "khepri" and phase == 2:
		var k := 0
		while k < 2 and alive().size() < 5: await summon_minion(e, "scarab"); k += 1
	elif pk == "khepri" and phase == 3:
		apply_status(e, "strength", 3); e["passive"]["lifesteal"] = 1

# =====================================================================
#   BIOME: Angriffsarten & Ziele, Zug-KI, Spawnen, Affixe, Biom-Ablauf
#   (1:1 aus der Browser-Version: atkTargets, moveAI, spawnBiome, chooseBiome, affix*)
# =====================================================================
const ENEMY_DEBUFFS := ["poison", "burn", "weak", "vulnerable", "ice", "mark", "dream", "owed"]
const HERO_DEBUFF_KEYS := ["poison", "burn", "weak", "brittle", "drained"]
const BIOME_ROOMS := 15

func atk_of(it: Dictionary) -> Variant:
	if T(it.get("atk")): return it["atk"]
	return "aoe" if T(it.get("dmg")) else null

func atk_pool() -> Array:
	var L := formation_living()
	var vis := L.filter(func(h): return not T(h["status"].get("invis")))
	return vis if vis.size() else L

## -> [[Held, Faktor], …]
func atk_targets(e: Dictionary, it: Dictionary) -> Array:
	var L := formation_living()
	if L.is_empty(): return []
	for h in L:
		if T(h["status"].get("taunt")): return [[h, 1.0]]
	var type = atk_of(it)
	if type == null: type = "normal"
	var pool := atk_pool()
	var t = S["heroes"].get(it["tgt"]) if T(it.get("tgt")) else null
	if t == null or t["dead"]: t = pool[0]
	var i := JS.idx(L, t)
	match type:
		"front": return [[L[0], 1.0]]
		"back": return [[L[L.size() - 1], 1.0]]
		"aoe": return L.map(func(h): return [h, 1.0])
		"splash":
			var out := []
			if i - 1 >= 0: out.append([L[i - 1], 1.0])
			out.append([t, 1.0])
			if i + 1 < L.size(): out.append([L[i + 1], 1.0])
			return out
		"pierce":
			var out := [[t, 1.0]]
			if i + 1 < L.size(): out.append([L[i + 1], 0.5])
			return out
	return [[t, 1.0]]

func roll_target(it: Dictionary) -> void:
	var a = atk_of(it)
	var curse := not T(it.get("dmg")) and (T(it.get("poison")) or T(it.get("burn")) or T(it.get("weak")) or T(it.get("brittle")) or T(it.get("drain"))) and not T(it.get("atk"))
	if a == "normal" or a == "splash" or a == "pierce" or curse:
		var p := atk_pool()
		if p.size(): it["tgt"] = p[JS.flr(rng() * p.size())]["id"]
		if not T(it.get("dmg")) and not T(it.get("atk")): it["atk"] = "normal"

# ---------- Zug-KI der Normalgegner ----------
func biome_tier() -> int: return orv(S, "biomeIdx", 0)

func move_ok(e: Dictionary, m: Dictionary) -> bool:
	if nz(m, "minTier") > biome_tier(): return false
	if T(m.get("cd")) and nz(orv(e, "cds", {}), m["name"]) > 0: return false
	var A := alive()
	match m.get("if"):
		"hurt": return A.any(func(o): return o["hp"] < o["maxHp"] * 0.75)
		"debuffed": return A.any(func(o): return ENEMY_DEBUFFS.any(func(k): return T(o["status"].get(k))))
		"canSummon": return A.size() < 5 and A.filter(func(o): return T(o.get("minion"))).size() < 2
		"noTaunt": return not A.any(func(o): return T(o["status"].get("etaunt")))
	return true

func _move_w(e: Dictionary, m: Dictionary) -> float:
	var x: float = orv(m, "w", 1)
	if e.get("lastName") == m["name"]: x *= 0.6 if T(m.get("dmg")) else 0.25
	if e.get("ecls") == "berserker" and T(m.get("dmg")): x *= 2
	if m.get("if") == "hurt": x *= 1.5
	return x

func move_ai(e: Dictionary) -> Dictionary:
	if not T(e.get("cds")): e["cds"] = {}
	for k in e["cds"]:
		if e["cds"][k] > 0: e["cds"][k] -= 1
	var moves: Array = orv(e, "moves", [])
	var opts := moves.filter(func(m): return move_ok(e, m))
	if opts.is_empty(): opts = moves.filter(func(m): return T(m.get("dmg")))
	var tot := 0.0
	for m in opts: tot += _move_w(e, m)
	var rr := rng() * tot
	var pm: Dictionary = opts[0]
	for m in opts:
		rr -= _move_w(e, m)
		if rr <= 0: pm = m; break
	if T(pm.get("cd")): e["cds"][pm["name"]] = pm["cd"] + 1
	var it := {}
	for k in pm:
		if not k in ["w", "if", "cd", "minTier", "up"]: it[k] = pm[k]
	var ups: Array = orv(pm, "up", [])
	for u in ups.slice(0, biome_tier()):
		for k in u:
			var v = u[k]
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				if k == "dmg" and not T(it.get("dmg")): continue
				if k == "heal":
					for hk in ["healLow", "healAllies", "healSelf"]:
						if T(it.get(hk)): it[hk] += v
					continue
				it[k] = nz(it, k) + v
			else: it[k] = v
	return it

# ---------- Spawnen ----------
func _bt(k: String) -> Dictionary: return D["BT"][k]
func biome_spawn_normal(rm: int) -> Array:
	var B: Dictionary = D["BIOMES"][S["biome"]]
	var n: int = S["party"].size()
	var max_c := 5
	var min_c := 2
	if rm <= 5: max_c = maxi(1, n); min_c = mini(2, max_c)
	var count := rand(min_c, max_c)
	var mult: float = room_mult(rm, "normal") * float(D["COUNT_MULT"][str(count)])
	var lst := []
	var heal_n := 0
	var summ := 0
	var spec := 0
	var spec_ok := rng() < 0.4
	var tries := 0
	while lst.size() < count and tries < 60:
		var k: String = pick(B["normals"])
		var d: Dictionary = D["BIOME_ENEMIES"][k]
		var skip := false
		if tries < 25 and lst.any(func(x): return x["key"] == "b_" + k): skip = true
		elif d["cls"] == "healer" and heal_n >= 1: skip = true
		elif d["cls"] == "summoner" and summ >= 1: skip = true
		elif d["cls"] == "special" and (spec >= 1 or not spec_ok): skip = true
		elif lst.size() == count - 1 and lst.all(func(x): return x["ecls"] == "healer" or x["ecls"] == "summoner") and (d["cls"] == "healer" or d["cls"] == "summoner"): skip = true
		tries += 1
		if skip: continue
		if d["cls"] == "healer": heal_n += 1
		if d["cls"] == "summoner": summ += 1
		if d["cls"] == "special": spec += 1
		lst.append(make_enemy(_bt(k), mult))
	JS.jsort(lst, func(a, b): return _bt(a["key"].substr(2))["pos"] - _bt(b["key"].substr(2))["pos"])
	return lst

func biome_extras(rm: int, room: int, mx := 1) -> Array:
	var B: Dictionary = D["BIOMES"][S["biome"]]
	var out := []
	var k := 0
	while k < mx and room > 0:
		var pool: Array = B["normals"].filter(func(x): return not D["BIOME_ENEMIES"][x]["cls"] in ["special", "summoner", "healer"])
		out.append(make_enemy(_bt(pick(pool)), room_mult(rm, "normal"))); room -= 1
		k += 1
	return out

func biome_elites(n: int) -> Array:
	var B: Dictionary = D["BIOMES"][S["biome"]]
	var out := []
	while out.size() < n:
		if not T(S.get("eliteBag")) or S["eliteBag"].is_empty(): S["eliteBag"] = shuffle(B["elites"].duplicate())
		var id: String = S["eliteBag"].pop_back()
		var el: Dictionary = D["BE"][id]
		if not JS.has(out, el): out.append(el)
	return out

func biome_elite_units(el: Dictionary, mult: float) -> Array:
	if T(el.get("parts")): return el["parts"].map(func(p): return make_enemy(p, mult, {"elite": true, "group": el["id"]}))
	return [make_enemy(el, mult, {"elite": true})]

func biome_boss_t() -> Dictionary:
	match D["BIOMES"][S["biome"]]["boss"]:
		"morrgan": return D["SHIFTER_BOSS"]
		"malgrath": return D["BOSS"]
		"vaelor": return D["AEGIS_BOSS"]
	return D["KHEPRI_BOSS"]

func spawn_biome(kind: String) -> Dictionary:
	var rm: int = S["room"]
	if kind == "normal": return {"list": biome_spawn_normal(rm), "special": null}
	var mult := room_mult(rm, "elite")
	if kind == "boss":
		var Tb := biome_boss_t()
		var lst := [make_enemy(Tb, room_mult(rm, "boss"))]
		if rng() < 0.35:
			var mx := 2 if rng() < 0.4 else 1
			lst = biome_extras(rm, 2, mx) + lst
		return {"list": lst, "special": Tb}
	if kind == "smith": return {"list": [make_enemy(D["SMITH"], mult, {"elite": true})], "special": D["SMITH"]}
	if kind == "double":
		var ab := biome_elites(2)
		var units: Array = biome_elite_units(ab[0], mult) + biome_elite_units(ab[1], mult)
		return {"list": units.slice(0, 5), "special": {"name": "%s & %s" % [ab[0]["name"], ab[1]["name"]], "desc": "Two elites at once!", "double": true}}
	var el: Dictionary = biome_elites(1)[0]
	var lst := biome_elite_units(el, mult)
	if rng() < 0.4: lst = biome_extras(rm, 5 - lst.size(), 1) + lst
	return {"list": lst, "special": el}

# ---------- Biom-Ablauf ----------
func choose_biome() -> void:
	if not T(S.get("biomesSeen")): S["biomesSeen"] = []
	var keys: Array = D["BIOME_KEYS"]
	var left := keys.filter(func(k): return not S["biomesSeen"].has(k))
	var src: Array = left if left.size() else keys
	var k: String = src[JS.flr(rng() * src.size())]
	S["biomesSeen"].append(k); S["biome"] = k; S["biomeIdx"] = S["biomesSeen"].size() - 1
	S["affix"] = pick(D["BIOMES"][k]["affixes"]); S["eliteBag"] = []
	S["phase"] = "biome"
	fx.emit("biome", {"biome": k, "affix": S["affix"]})

# ---------- Affixe ----------
func affix_fight_start() -> void:
	S["restless"] = {"hero": false, "enemy": false}
	if S.get("affix") == "overgrowth":
		var h = pick(living()) if living().size() else null
		var e = pick(alive()) if alive().size() else null
		if h != null: apply_status(h, "overgrown", 1)
		if e != null: apply_status(e, "overgrown", 1)

func affix_round_start() -> void:
	var A = S.get("affix")
	if not T(A) or alive().is_empty(): return
	var all: Array = living() + alive()
	var prev = S.get("actor"); S["actor"] = null
	if A == "naturesHealing" and S["round"] % 5 == 0:
		for u in all:
			for k in HERO_DEBUFF_KEYS + ENEMY_DEBUFFS + ["vulnerable"]:
				var v = u["status"].get(k)
				if T(v):
					u["status"][k] = v - JS.cel(v / 2.0)
					if not T(u["status"][k]): u["status"].erase(k)
		for u in all: update_unit(u)
		toast("Nature's Healing: half of all debuffs fade.")
	if A == "witchingHour" and S["round"] % 4 == 0:
		for u in all: apply_status(u, "witching", 1)
		toast("Witching Hour: everyone hits harder!")
	if A == "stoneskin":
		for u in all: gain_block(u, 3)
	if A == "rockslide" and S["round"] % 3 == 0:
		toast("Rockslide!")
		for u in all: deal_damage(u, 5)
		for e in alive():
			if e["hp"] <= 0: kill_enemy(e)
		check_hero_deaths(); await sleep(350)
	if A == "scorchingSun":
		for u in all: u["status"]["burn"] = st(u, "burn") + 1; update_unit(u)
	if A == "shiftingSands":
		var h = pick(living()) if living().size() else null
		var e = pick(alive()) if alive().size() else null
		if h != null: apply_status(h, "weak", 1)
		if e != null: apply_status(e, "weak", 1)
	S["actor"] = prev

## Treffer von einer Seite auf die andere: Overgrown, Witching Hour, Sandstorm (-1 = verfehlt)
func affix_dmg(t: Dictionary, amount: int) -> int:
	var a = S.get("actor")
	if a == null or T(a.get("hero")) == T(t.get("hero")): return amount
	if T(a["status"].get("overgrown")): amount = JS.rnd(amount * 1.25)
	if T(a["status"].get("witching")): amount += 2 * a["status"]["witching"]
	if S.get("affix") == "sandstorm" and amount > 0 and rng() < 0.15: float_text(t, "Miss!", "blk"); return -1
	return amount
