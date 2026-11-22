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
