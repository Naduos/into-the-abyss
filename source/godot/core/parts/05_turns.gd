
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
