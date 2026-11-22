
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

