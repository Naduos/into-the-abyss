## Koop-Test: zwei Instanzen (host / client) spielen über ENet auf localhost.
## godot --headless --path . -s tests/coop_test.gd -- host|client <ausgabe.txt> [maxRaum]
extends SceneTree
var m
var role := "host"
func _init(): _run.call_deferred()
func idle(max_s := 8.0) -> void:
	var t := 0.0
	while (m.g.q_running or m.g.Q.size()) and t < max_s:
		await create_timer(0.03).timeout; t += 0.03
	await create_timer(0.08).timeout
func digest() -> String:
	var S: Dictionary = m.g.S
	var H := []
	for h in m.g.hero_list(): H.append([h["id"], h["hp"], h["maxHp"], h["gold"], h["deck"].size(), h["gems"].size(), h.get("spec")])
	var E := []
	for e in S.get("enemies", []): E.append([e["key"], e["hp"], e["dead"]])
	return JSON.stringify({"room": S.get("room"), "phase": S["phase"], "uid": m.g.uid, "H": H, "E": E})
func _run():
	var a := OS.get_cmdline_user_args()
	role = a[0]; var out: String = a[1]; var max_room := int(a[2]) if a.size() > 2 else 4
	root.size = Vector2i(1280, 720)
	m = load("res://ui/main.tscn").instantiate(); root.add_child(m)
	m.speed = 0.0
	await process_frame
	if role == "host":
		print("host: ", m.net.host(m.g))
		var t := 0.0
		while m.net.slots.size() < 1 and t < 30: await create_timer(0.2).timeout; t += 0.2
		print("host: guest joined ", m.net.slots)
		m.act({"t": "start", "seed": 4242, "roles": {"knight": "host", "mage": "g1"}, "party": ["knight", "mage"], "mode": "coop"})
	else:
		await create_timer(1.0).timeout
		print("client: ", m.net.join(m.g, "127.0.0.1"))
		var t := 0.0
		while not m.g.S.get("runActive", false) and t < 40: await create_timer(0.2).timeout; t += 0.2
		print("client: run started, slot ", m.net.my_slot)
	await idle()
	var bot = load("res://tests/bot_driver.gd").new(m.g)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		var S: Dictionary = m.g.S
		if S["phase"] == "lost" or int(S.get("room", 0)) >= max_room: break
		if S.get("waiting", false) or m.g.q_running: await create_timer(0.05).timeout; continue
		var act = null
		if S["phase"] == "formation":
			var me := ""
			for id in S["party"]:
				if m.g.mine(id): me = id
			if not m.g.T(S["formReady"].get(m.net.my_slot)):
				act = {"t": "fready", "h": me} if not S["formation"].any(func(x): return not m.g.T(x)) else ({"t": "formation", "h": me, "order": S["party"].duplicate()} if role == "host" else null)
		else:
			act = bot.step(0)
			if act != null and act.has("h") and act["h"] != null and S["heroes"].has(act["h"]) and not m.g.mine(act["h"]): act = null
			if act != null and act["t"] in ["room", "ev", "biomego"] and role != "host": act = null
		if act == null: await create_timer(0.1).timeout; continue
		m.act(act)
		await create_timer(0.15).timeout
		await idle()
		if act["t"] == "play":
			for hh in m.g.hero_list():
				for c in hh["hand"]:
					if c["id"] == act["card"]: bot.stuck[c["id"]] = true
	await create_timer(3.0).timeout
	var f := FileAccess.open(out, FileAccess.WRITE); f.store_string(digest()); f.close()
	print(role, " done room=", m.g.S.get("room"), " phase=", m.g.S["phase"])
	m.net.leave()
	quit()
