## Paritäts-Bot: spielt die Godot-Engine headless mit derselben Logik wie tools/bot_logic.js
## und schreibt nach jeder Aktion denselben Zustands-Digest. (Stand 22.11.2026: inkl. Biom-Auswahl)
## Aufruf: godot --headless --path . -s tests/bot.gd -- seed party(kommagetrennt) specIdx maxSteps out.txt
extends SceneTree

var g: Game
var stuck := {}
var last = null

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0])
	var party: Array = Array(args[1].split(","))
	var spec_idx := int(args[2])
	var max_steps := int(args[3])
	var out_path: String = args[4]
	g = Game.new()
	var roles := {}
	for id in party: roles[id] = "host"
	g.dispatch({"t": "start", "seed": seed, "roles": roles, "party": party, "mode": "solo"})
	var lines := ["0 start " + digest()]
	for step in range(1, max_steps + 1):
		var a = bot_step(spec_idx)
		if a == null:
			lines.append("%d END %s" % [step, g.S["phase"]]); break
		bot_apply(a)
		lines.append("%d %s %s" % [step, js_json(a), digest()])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("gd steps ", lines.size(), " last phase ", g.S["phase"], " room ", g.S.get("room"))
	quit()

# ---------- JSON exakt wie JSON.stringify ----------
func js_json(v) -> String:
	match typeof(v):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "true" if v else "false"
		TYPE_INT: return str(v)
		TYPE_FLOAT:
			if v == floor(v) and abs(v) < 1e15: return str(int(v))
			return str(v)
		TYPE_STRING, TYPE_STRING_NAME: return JSON.stringify(str(v))
		TYPE_ARRAY: return "[" + ",".join(v.map(func(x): return js_json(x))) + "]"
		TYPE_DICTIONARY:
			var parts := []
			for k in v: parts.append(JSON.stringify(str(k)) + ":" + js_json(v[k]))
			return "{" + ",".join(parts) + "}"
	return str(v)

func bot_num(v):
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT: return JS.rnd(v * 1000) / 1000.0 if typeof(v) == TYPE_FLOAT else v
	return v
func sort_obj(o) -> Dictionary:
	var r := {}
	if o == null: return r
	var ks: Array = o.keys().map(func(k): return str(k))
	ks.sort()
	for k in ks:
		var v = o[k]
		if typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]: r[k] = bot_num(v)
	return r

func digest() -> String:
	var L = last
	if L != null:
		var h: Dictionary = g.S["heroes"][L.h]
		if "%d:%d" % [h["energy"], h["hand"].size()] == L.before and h["hand"].any(func(c): return c["id"] == L.id): stuck[L.id] = true
		last = null
	var S: Dictionary = g.S
	var H := []
	for h in g.hero_list():
		H.append([h["id"], h["hp"], h["block"], h["energy"], 1 if h["dead"] else 0, h["gold"],
			"|".join(h["hand"].map(func(c): return c["key"] + ("*" if Game.T(c.get("tmp")) else ""))),
			h["draw"].size(), h["discard"].size(), h.get("vanished", []).size(), h["deck"].size(), h["gems"].size(), sort_obj(h["status"]),
			h["spec"] if Game.T(h.get("spec")) else "", h["sanity"] if h.get("sanity") != null else 30, Game.nz(h, "corruption")])
	var E := []
	for e in S.get("enemies", []):
		var it = e.get("intent")
		E.append([e["key"], e["hp"], e["maxHp"], e["block"], 1 if e["dead"] else 0, sort_obj(e["status"]),
			(it.get("name", "") if it != null else ""), (it["dmg"] if it != null and Game.T(it.get("dmg")) else 0)])
	return js_json({"p": S["phase"], "r": S.get("room", 0) if Game.T(S.get("room")) else 0, "t": S.get("round", 0) if Game.T(S.get("round")) else 0,
		"uid": g.uid, "H": H, "E": E, "m": ",".join(S.get("mapOpts", []) if S.get("mapOpts") != null else [])})

func bot_step(spec_idx: int):
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
				var s := g.stats(c)
				if Game.T(d.get("unplayable")) or s.cost > h["energy"] or s.depthCost > Game.st(h, "depth") or g.lacks_sanity(h, s): continue
				if stuck.has(c["id"]): continue
				var target = null
				if g.needs_target(s):
					var al := g.alive()
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

func bot_apply(a: Dictionary) -> void:
	if a["t"] == "play":
		var h: Dictionary = g.S["heroes"][a["h"]]
		last = {"id": a["card"], "h": a["h"], "before": "%d:%d" % [h["energy"], h["hand"].size()]}
	else: last = null
	g.dispatch(a)
