
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
