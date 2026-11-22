
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
