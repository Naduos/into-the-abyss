
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
