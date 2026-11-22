## Einfache Spiel-Logik für automatische Tests (gleich wie tests/bot.gd)
extends RefCounted
var g
var stuck := {}
func _init(game): g = game
func step(spec_idx := 0):
	var S: Dictionary = g.S
	var ph: String = S["phase"]
	if ph == "formation":                                 # Wartebank -> erster freier Platz, dann bestätigen
		var o: Array = S["formation"].duplicate()
		var bench: Array = S["party"].filter(func(id): return not o.has(id))
		if bench.size():
			o[o.find(null)] = bench[0]
			return {"t": "formation", "h": S["party"][0], "order": o}
		return {"t": "fready", "h": S["party"][0]}
	if ph == "spec":
		for id in S["party"]:
			var h: Dictionary = S["heroes"][id]
			if not Game.T(h.get("spec")):
				var L: Array = g.D["SPECS"][id]
				return {"t": "spec", "h": id, "spec": L[spec_idx % L.size()]["id"]}
		return null
	if ph == "hero":
		for h in g.hero_list():
			if h["dead"] or Game.T(h.get("turnDone")): continue
			for i in h["hand"].size():
				var c: Dictionary = h["hand"][i]
				var d: Dictionary = g.CARDS[c["key"]]
				var s: Dictionary = g.stats(c)
				if Game.T(d.get("unplayable")) or s.cost > h["energy"] or s.depthCost > Game.st(h, "depth") or g.lacks_sanity(h, s): continue
				if stuck.has(c["id"]): continue
				var target = null
				if g.needs_target(s):
					var al: Array = g.alive()
					if al.is_empty(): continue
					var best: Dictionary = al[0]
					for e in al:
						if e["hp"] < best["hp"]: best = e
					target = best["id"]
				return {"t": "play", "h": h["id"], "card": c["id"], "target": target}
			return {"t": "end", "h": h["id"]}
		return null
	if ph == "post":
		for id in S["party"]:
			var p = S["post"].get(id)
			if p == null or Game.T(p.get("ready")): continue
			if p["kind"] == "reward" and not p["picked"]: return {"t": "pick", "h": id, "key": p["cards"][0] if p["cards"].size() else null}
			if p["kind"] == "camp" and not Game.T(p.get("restDone")) and not Game.T(p.get("campDone")): return {"t": "rest", "h": id}
			if p["kind"] == "camp" and not Game.T(p.get("campDone")): return {"t": "campdone", "h": id}
			return {"t": "ready", "h": id}
		return null
	if ph == "biome": return {"t": "biomego", "h": S["party"][0]}
	if ph == "map": return {"t": "room", "type": S["mapOpts"][0]}
	if ph == "event": return {"t": "ev", "op": "leave"}
	return null

