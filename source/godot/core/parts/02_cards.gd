
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
