
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
