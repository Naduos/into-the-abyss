## Automatischer Oberflächen-Test: spielt einen Lauf über die Oberfläche und macht Screenshots.
## xvfb-run godot --path . -s tests/ui_shot.gd -- <ausgabeordner>
extends SceneTree
var m
var out := "/tmp/ui"
func _init(): _run.call_deferred()
func shot(name: String) -> void:
	await process_frame; await process_frame; await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name]); print("shot ", name)
func wait_idle(max_s := 20.0) -> void:
	var t := 0.0
	while (m.g.q_running or m.g.Q.size()) and t < max_s:
		await create_timer(0.1).timeout; t += 0.1
	await create_timer(0.3).timeout
func _run():
	var a := OS.get_cmdline_user_args(); if a.size(): out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	m = load("res://ui/main.tscn").instantiate(); root.add_child(m)
	m.speed = 0.05
	m.party_pick = {"brawler": true, "mage": true}
	m.dirty = true
	await shot("01_title")
	m._start_run(); await wait_idle(); await shot("02_spec")
	m.act({"t": "spec", "h": "brawler", "spec": "knockout"}); await wait_idle()
	m.act({"t": "spec", "h": "mage", "spec": "fire"}); await wait_idle(); await shot("03_formation")
	m.act({"t": "formation", "h": "brawler", "order": ["brawler", "mage"]}); m.act({"t": "fready", "h": "brawler"}); await wait_idle(); await shot("04_biome")
	m.act({"t": "biomego", "h": "brawler"}); await wait_idle(); await shot("05_fight")
	# erste Karte des Magiers anklicken, die ein Ziel braucht
	m.g.switch_hero("mage"); m.dirty = true; await wait_idle()
	var h = m.g.S["heroes"]["mage"]
	for c in h["hand"]:
		if m.g.needs_target(m.g.stats(c)): m._card_clicked(h, c["id"]); break
	m.dirty = true; await shot("06_target")
	m.selected = null
	# Bot spielt bis zur ersten Belohnung
	var bot = load("res://tests/bot_driver.gd").new(m.g)
	for i in 400:
		if m.g.S["phase"] == "post": break
		var act = bot.step(); if act == null: break
		m.act(act); await wait_idle(5)
		if act["t"] == "play":
			for hh in m.g.hero_list():
				for c in hh["hand"]:
					if c["id"] == act["card"]: bot.stuck[c["id"]] = true
	m.dirty = true; await shot("07_reward")
	for i in 600:
		if m.g.S["phase"] == "map": break
		var act = bot.step(); if act == null: break
		m.act(act); await wait_idle(5)
		if act["t"] == "play":
			for hh in m.g.hero_list():
				for c in hh["hand"]:
					if c["id"] == act["card"]: bot.stuck[c["id"]] = true
	m.dirty = true; await shot("08_map")
	m.deck_view = true; m.dirty = true; await shot("09_deck")
	m.deck_view = false; m.overlay_view = "glossary"; m.gloss_class = "brawler"; m.gloss_spec = "knockout"; m.dirty = true; await shot("10_glossary")
	m.overlay_view = "stats"; m.stats_scope = "run"; m.dirty = true; await shot("11_stats")
	m.overlay_view = "gold"; m.dirty = true; await shot("12_gold")
	m.overlay_view = ""; m.net.host(m.g); m.g.S["runActive"] = false; m.g.S["phase"] = "idle"; m.dirty = true
	await create_timer(3.0).timeout; m.dirty = true; await shot("13_lobby")
	m.net.leave()
	quit()
