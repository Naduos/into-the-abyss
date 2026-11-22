
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
