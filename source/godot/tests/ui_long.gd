## Längerer Oberflächen-Test: Bot spielt über die Oberfläche (alle Bildschirme werden gezeichnet).
extends SceneTree
var m
func _init(): _run.call_deferred()
func wait_idle(max_s := 10.0) -> void:
	var t := 0.0
	while (m.g.q_running or m.g.Q.size()) and t < max_s:
		await create_timer(0.05).timeout; t += 0.05
	await process_frame; await process_frame
func _run():
	root.size = Vector2i(1280, 720)
	m = load("res://ui/main.tscn").instantiate(); root.add_child(m)
	m.speed = 0.01
	var party: Array = Array(OS.get_cmdline_user_args()[0].split(","))
	m.party_pick = {}
	for id in party: m.party_pick[id] = true
	m._start_run(); await wait_idle()
	var bot = load("res://tests/bot_driver.gd").new(m.g)
	var seen := {}
	for i in 3000:
		var ph: String = m.g.S["phase"]; seen[ph] = true
		if ph == "lost" or (ph == "won" and m.g.S["room"] >= 60): break
		var act = bot.step(int(OS.get_cmdline_user_args()[1]))
		if act == null: await wait_idle(); continue
		m.act(act); await wait_idle()
		if act["t"] == "play":
			for hh in m.g.hero_list():
				for c in hh["hand"]:
					if c["id"] == act["card"]: bot.stuck[c["id"]] = true
	print("UI_LONG room=", m.g.S["room"], " phase=", m.g.S["phase"], " phases=", seen.keys())
	quit()
