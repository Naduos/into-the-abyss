## =====================================================================
##   SPIELOBERFLÄCHE (Godot-Version der HTML-Oberfläche)
##   Die Regeln stecken komplett in der Engine (class Game). Diese Szene
##   zeigt nur den Zustand g.S an und schickt Aktionen per g.dispatch().
##   Jede Engine-Meldung (Signal fx) löst ein Neuzeichnen im nächsten Frame aus.
## =====================================================================
extends Control

const BG := Color("#17121f")
const PANEL := Color("#241c30")
const GOLD := Color("#ffd27a")
const ROOM_NAMES := {"normal": "Fight", "elite": "Elite", "camp": "Campfire", "shop": "Shop", "event": "Event", "boss": "BOSS"}
const ROOM_ICONS := {"normal": "sword", "elite": "skull", "camp": "flame", "shop": "flask", "event": "eye", "boss": "bigaxe"}

var g
var speed := 0.7
var dirty := true
var selected = null                 # Karten-ID, die auf ein Ziel wartet
var post_hero := ""                 # welcher Held im Belohnungs-/Lager-Bildschirm angezeigt wird
var camp_mode := ""                 # "upgrade" oder ""
var ev_mode := ""
var deck_view := false
var sel_gem = null                  # gewählter Edelstein zum Einsetzen
var fuse_pick: Array = []           # Edelsteine zum Fusionieren (3 gleiche Stufe)
var overlay_view := ""              # "", "glossary", "stats", "gold"
var gloss_class := "knight"
var gloss_spec = null
var gloss_tab := "cards"
var stats_scope := "fight"
var join_ip := "127.0.0.1"
var net_msg := ""
var net: Node = null
var sprites := {}                   # unit-id -> TextureRect (für Animationen)
var party_pick := {"knight": true, "mage": true}
var unit_nodes := {}                # id -> Control (für schwebende Texte)
var root: Control
var overlay: Control
var toast_box: VBoxContainer

func _ready() -> void:
	Art.ensure()
	var th := Theme.new()
	th.default_font_size = 14
	theme = th
	var bg := ColorRect.new(); bg.color = BG; bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(root)
	overlay = Control.new(); overlay.set_anchors_preset(Control.PRESET_FULL_RECT); overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(overlay)
	toast_box = VBoxContainer.new(); toast_box.position = Vector2(12, 560); toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; overlay.add_child(toast_box)
	g = load("res://core/game.gd").new()
	g.presenter = self
	g.fx.connect(_on_fx)
	net = load("res://ui/net.gd").new(); net.name = "Net"; add_child(net)
	net.lobby_changed.connect(func(): dirty = true)
	net.closed.connect(func(r): net.leave(); net_msg = r; g.S["runActive"] = false; g.S["phase"] = "idle"; dirty = true)
	print("Into the Abyss bereit – Version ", g.game_version())

# ---------- Engine-Anbindung ----------
func sleep(ms: float) -> void:
	await get_tree().create_timer(maxf(0.01, ms / 1000.0 * speed)).timeout

func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"float": _float_text(data["u"], data["text"], data["cls"])
		"banner": _banner(data["text"], data.get("sub", ""), data.get("ms", 850))
		"toast": _toast(data["text"])
		"retrigger": _anim(data["u"], data["cls"])
		_: dirty = true

func act(a: Dictionary) -> void:
	selected = null
	if a.get("t") == "start" and a.get("mode") == "coop" and net.is_host: net.host_commit(a)   # Start geht immer an alle
	else: g.dispatch(a)
	dirty = true

func _process(_d: float) -> void:
	if dirty:
		dirty = false
		_render()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		selected = null; deck_view = false; sel_gem = null; camp_mode = ""; overlay_view = ""; fuse_pick.clear(); dirty = true
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_E and g.S.get("phase") == "hero":
		var h = g.active_hero()
		if h != null: act({"t": "end", "h": h["id"]})

# ---------- Hilfen zum Bauen ----------
func lbl(text: String, size := 14, col := Color.WHITE, parent: Node = null) -> Label:
	var l := Label.new(); l.text = text; l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	if parent: parent.add_child(l)
	return l

func rich(text: String, size := 13, w := 140.0, parent: Node = null) -> RichTextLabel:
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false
	r.custom_minimum_size = Vector2(w, 0); r.text = text; r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size); r.mouse_filter = Control.MOUSE_FILTER_PASS
	if parent: parent.add_child(r)
	return r

func btn(text: String, cb: Callable, parent: Node = null, size := 15, minw := 0.0) -> Button:
	var b := Button.new(); b.text = text; b.add_theme_font_size_override("font_size", size); b.pressed.connect(cb)
	if minw > 0: b.custom_minimum_size.x = minw
	if parent: parent.add_child(b)
	return b

func panel(col := PANEL, border := Color("#4a3a5a"), radius := 8, bw := 2) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = col; sb.border_color = border; sb.set_border_width_all(bw); sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p

func texrect(t: Texture2D, parent: Node = null) -> TextureRect:
	var r := TextureRect.new(); r.texture = t; r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED; r.mouse_filter = Control.MOUSE_FILTER_PASS
	if parent: parent.add_child(r)
	return r

func centered_vbox(parent: Node, top := 40) -> VBoxContainer:
	var c := CenterContainer.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT); c.offset_top = top; parent.add_child(c)
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", 12); c.add_child(v)
	return v

# ---------- Neuzeichnen ----------
func _render() -> void:
	for c in root.get_children(): c.queue_free()
	unit_nodes.clear(); sprites.clear()
	var S: Dictionary = g.S
	var ph: String = S.get("phase", "idle")
	if not S.get("runActive", false) or ph == "idle":
		if net.connected: _lobby()
		else: _title()
		if overlay_view == "glossary": _glossary()
		return
	_background()
	_topbar()
	if overlay_view == "glossary": _glossary(); return
	if overlay_view == "stats": _stats(); return
	if overlay_view == "gold": _gold_screen(); return
	if deck_view: _deck_screen(); return
	match ph:
		"spec": _spec_screen()
		"formation": _formation_screen()
		"biome": _biome_screen()
		"map": _map_screen()
		"won":
			if int(S.get("room", 0)) >= g.ROOMS_PER_RUN and g.alive().is_empty(): _end_screen(true)
			else: _battle()
		"hero", "enemy", "fight": _battle()
		"post": _post_screen()
		"event": _event_screen()
		"lost": _end_screen(false)
		_: lbl("…", 20, Color.WHITE, centered_vbox(root))

func _topbar() -> void:
	var S: Dictionary = g.S
	var bar := HBoxContainer.new(); bar.position = Vector2(10, 6); bar.size = Vector2(1260, 30); bar.add_theme_constant_override("separation", 18); root.add_child(bar)
	lbl("Into the Abyss", 18, GOLD, bar)
	if int(S.get("room", 0)) > 0: lbl("Room %d / %d" % [S["room"], g.ROOMS_PER_RUN], 15, Color("#d8d0e8"), bar)
	var b = S.get("biome")
	if b != null and Art.U["biomes"].has(b):
		var bl := lbl(Art.U["biomes"][b]["name"], 15, Color(Art.U["biomes"][b]["color"]), bar)
		var af = S.get("affix")
		if af != null and Art.U["affixes"].has(af):
			bl.text += "  ·  " + Art.U["affixes"][af]["name"]
			bl.tooltip_text = Art.U["affixes"][af]["desc"]; bl.mouse_filter = Control.MOUSE_FILTER_PASS
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bar.add_child(sp)
	if S.get("heroes", {}).size() and S["phase"] != "spec":
		btn("Deck", func(): deck_view = not deck_view; overlay_view = ""; dirty = true, bar, 13)
		btn("Stats", func(): overlay_view = "" if overlay_view == "stats" else "stats"; dirty = true, bar, 13)
		if S["party"].size() > 1: btn("Send Gold", func(): overlay_view = "" if overlay_view == "gold" else "gold"; dirty = true, bar, 13)
	btn("Glossary", func(): overlay_view = "" if overlay_view == "glossary" else "glossary"; dirty = true, bar, 13)
	btn("Speed ×%s" % ("1" if speed >= 0.7 else "2" if speed >= 0.35 else "4"), func(): speed = 0.35 if speed >= 0.7 else 0.15 if speed >= 0.35 else 0.7; dirty = true, bar, 13)
	btn("Menu", func():
		if net.connected: net.leave()
		g.S["runActive"] = false; g.S["phase"] = "idle"; dirty = true, bar, 13)

# ---------- Titel / Gruppe ----------
func _title() -> void:
	var v := centered_vbox(root, 0)
	lbl("INTO THE ABYSS", 44, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl("Choose your party (1–4 heroes)", 16, Color("#cfc6e0"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); v.add_child(row)
	var n := 0
	for id in g.D["CLASS_ORDER"]:
		if party_pick.get(id, false): n += 1
	for id in g.D["CLASS_ORDER"]:
		var on: bool = party_pick.get(id, false)
		var p := panel(Color("#2e2440") if on else PANEL, GOLD if on else Color("#4a3a5a"), 10, 3 if on else 2)
		p.custom_minimum_size = Vector2(150, 200); row.add_child(p)
		var vb := VBoxContainer.new(); vb.alignment = BoxContainer.ALIGNMENT_CENTER; p.add_child(vb)
		texrect(Art.svg(g.D["HEROES"][id]["key"], 120), vb)
		lbl(g.D["HEROES"][id]["name"], 15, GOLD if on else Color.WHITE, vb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cid: String = id
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if party_pick.get(cid, false): party_pick.erase(cid)
				elif n < 4: party_pick[cid] = true
				dirty = true)
	var b := btn("Start Run (%d heroes)" % n, _start_run, v, 20)
	b.disabled = n == 0
	var coop := HBoxContainer.new(); coop.alignment = BoxContainer.ALIGNMENT_CENTER; coop.add_theme_constant_override("separation", 10); v.add_child(coop)
	btn("Host Co-op", func():
		var e: String = net.host(g)
		net_msg = e; dirty = true, coop, 16)
	var ipf := LineEdit.new(); ipf.text = join_ip; ipf.custom_minimum_size.x = 170; ipf.placeholder_text = "Host IP"; coop.add_child(ipf)
	ipf.text_changed.connect(func(t): join_ip = t)
	btn("Join", func():
		var e: String = net.join(g, join_ip)
		net_msg = e if e != "" else "Connecting to %s…" % join_ip; dirty = true, coop, 16)
	btn("Glossary", func(): overlay_view = "glossary"; dirty = true, coop, 16)
	if net_msg != "": lbl(net_msg, 13, Color("#ffb36a"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl("Tip: Right click cancels, E ends your turn.", 12, Color("#8a80a0"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl("Version %d" % g.game_version(), 11, Color("#6a6080"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _start_run() -> void:
	var party := []
	for id in g.D["CLASS_ORDER"]:
		if party_pick.get(id, false): party.append(id)
	var roles := {}
	for id in party: roles[id] = "host"
	act({"t": "start", "seed": randi() % 2000000000, "roles": roles, "party": party, "mode": "solo"})

# ---------- Spezialisierung ----------
func _spec_screen() -> void:
	var S: Dictionary = g.S
	var h = null
	for id in S["party"]:
		if not g.T(S["heroes"][id].get("spec")) and g.mine(id): h = S["heroes"][id]; break
	if h == null:
		lbl("Waiting for the other players to choose…", 20, Color.WHITE, centered_vbox(root)); return
	var v := centered_vbox(root)
	lbl("%s – choose a specialization" % h["name"], 24, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 14); v.add_child(row)
	for sp in g.D["SPECS"][h["id"]]:
		var p := panel(PANEL, Color(sp.get("color", "#888")), 10, 3); p.custom_minimum_size = Vector2(360, 470); row.add_child(p)
		var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6); p.add_child(vb)
		var art: String = Art.U["spec_art"].get(sp["id"], Art.U["svg"].get(h["key"], ""))
		texrect(Art.tex(art, 140), vb)
		lbl(sp["name"], 20, Color(sp.get("color", "#fff")), vb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl(sp.get("tag", ""), 13, Color("#b8b0c8"), vb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rich(Art.bb(sp.get("desc", "")), 13, 340, vb)
		rich("[b][color=#ffd27a]%s:[/color][/b] %s" % [sp.get("passiveName", ""), Art.bb(sp.get("passive", ""))], 12, 340, vb)
		var hid: String = h["id"]; var sid: String = sp["id"]
		btn("Choose %s" % sp["name"], func(): act({"t": "spec", "h": hid, "spec": sid}), vb, 15)

# ---------- Formation ----------
func _formation_screen() -> void:
	var S: Dictionary = g.S
	var order: Array = S["formation"].filter(func(x): return g.T(x))
	for id in S["party"]:
		if not order.has(id): order.append(id)
	var v := centered_vbox(root)
	lbl("Formation – front to back", 24, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl("Front heroes take front attacks, back heroes take back attacks.", 13, Color("#b8b0c8"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 12); v.add_child(row)
	for i in order.size():
		var p := panel(); p.custom_minimum_size = Vector2(170, 230); row.add_child(p)
		var vb := VBoxContainer.new(); p.add_child(vb)
		lbl("Front" if i == 0 else "Back" if i == order.size() - 1 else "Middle", 13, GOLD, vb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var h: Dictionary = S["heroes"][order[i]]
		texrect(Art.unit_tex(h, 130), vb)
		lbl(h["name"], 14, Color.WHITE, vb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; vb.add_child(hb)
		var ii: int = i
		if i > 0: btn("◀", func(): var o := order.duplicate(); var t = o[ii - 1]; o[ii - 1] = o[ii]; o[ii] = t; act({"t": "formation", "h": S["party"][0], "order": o}), hb)
		if i < order.size() - 1: btn("▶", func(): var o := order.duplicate(); var t = o[ii + 1]; o[ii + 1] = o[ii]; o[ii] = t; act({"t": "formation", "h": S["party"][0], "order": o}), hb)
	var me: String = S["party"][0]
	for id in S["party"]:
		if g.mine(id): me = id; break
	var rdy: bool = g.T(S.get("formReady", {}).get(S["roles"][me]))
	btn("Waiting for others…" if rdy else "Ready!", func():
		if S["formation"].any(func(x): return not g.T(x)): g.dispatch({"t": "formation", "h": me, "order": order})
		act({"t": "fready", "h": me}), v, 20).disabled = rdy

# ---------- Biom ----------
func _biome_screen() -> void:
	var S: Dictionary = g.S
	var v := centered_vbox(root)
	var b = S.get("biome")
	var info: Dictionary = Art.U["biomes"].get(b, {"name": "?", "sub": "", "color": "#fff"})
	lbl(info["name"], 40, Color(info["color"]), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := rich("[center]%s[/center]" % info["sub"], 16, 700, v)
	var af = S.get("affix")
	if af != null and Art.U["affixes"].has(af):
		rich("[center][b][color=#ffb36a]Affix: %s[/color][/b]\n%s[/center]" % [Art.U["affixes"][af]["name"], Art.bb(Art.U["affixes"][af]["desc"])], 14, 700, v)
	btn("Enter", func(): act({"t": "biomego", "h": S["party"][0]}), v, 22)

# ---------- Karte ----------
func _map_screen() -> void:
	var S: Dictionary = g.S
	var v := centered_vbox(root)
	lbl("Where to next?", 28, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl("Room %d" % (int(S["room"]) + 1), 15, Color("#b8b0c8"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 18); row.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(row)
	for t in S["mapOpts"]:
		var p := panel(PANEL, Color("#ff6a5a") if t in ["elite", "boss"] else Color("#6a5a8a"), 12, 3); p.custom_minimum_size = Vector2(170, 170); row.add_child(p)
		var vb := VBoxContainer.new(); vb.alignment = BoxContainer.ALIGNMENT_CENTER; p.add_child(vb)
		texrect(Art.svg(ROOM_ICONS.get(t, "sword"), 80), vb)
		lbl(ROOM_NAMES.get(t, t), 20, Color.WHITE, vb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tt: String = t
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: act({"t": "room", "type": tt}))
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hero_strip(v)

func _hero_strip(parent: Node) -> void:
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 20); parent.add_child(row)
	for h in g.hero_list():
		var vb := VBoxContainer.new(); row.add_child(vb)
		texrect(Art.unit_tex(h, 90), vb)
		lbl("%s  %d/%d HP  ·  %d Gold" % [h["name"], h["hp"], h["maxHp"], h["gold"]], 13, Color("#e8e0f0"), vb)

# ---------- Kampf ----------
func _battle() -> void:
	var S: Dictionary = g.S
	var active = g.active_hero()
	# Helden (Formation: vorne = rechts, nahe an den Gegnern)
	var heroes: Array = g.formation_order().map(func(id): return S["heroes"][id])
	heroes.reverse()
	var hx := 20.0
	var hw := minf(170.0, 600.0 / maxf(1, heroes.size()))
	for h in heroes:
		_unit(h, Vector2(hx, 60), hw, true, active != null and h["id"] == active["id"])
		hx += hw + 6
	var en: Array = S["enemies"].filter(func(e): return not e["dead"] or g.T(e.get("regrowIn")))
	var ew := minf(150.0, 600.0 / maxf(1, en.size()))
	var ex := 660.0
	for e in en:
		_unit(e, Vector2(ex, 60), ew, false, false)
		ex += ew + 6
	# untere Leiste: Energie, Hand, Zug beenden
	var bottom := Control.new(); bottom.position = Vector2(0, 455); bottom.size = Vector2(1280, 265); root.add_child(bottom)
	if active == null: return
	var h: Dictionary = active
	var info := VBoxContainer.new(); info.position = Vector2(14, 8); bottom.add_child(info)
	lbl(h["name"] + ("  (%s)" % g.spec_of(h["id"], h["spec"])["name"] if g.T(h.get("spec")) else ""), 15, GOLD, info)
	lbl("Energy  %d" % h["energy"], 26, Color("#7ad0ff"), info)
	lbl("Draw %d · Discard %d" % [h["draw"].size(), h["discard"].size()], 12, Color("#a8a0b8"), info)
	lbl("Gold %d" % h["gold"], 13, GOLD, info)
	if h["id"] == "eldritch" and h.get("spec") == "acolyte": lbl("Sanity %d · Corruption %d" % [g.sanity_of(h), h.get("corruption", 0)], 12, Color("#c8a8ff"), info)
	if selected != null: lbl("Choose a target (right click = cancel)", 13, Color("#ff9a7a"), info)
	var hand := HBoxContainer.new(); hand.position = Vector2(200, 12); hand.add_theme_constant_override("separation", -10 if h["hand"].size() > 7 else 6); bottom.add_child(hand)
	var my_turn: bool = S["phase"] == "hero" and not g.T(h.get("turnDone")) and g.mine(h["id"]) and not S.get("waiting", false)
	for c in h["hand"]:
		var cw := _card(c, h, my_turn)
		hand.add_child(cw)
	var endb := btn("End Turn", func(): act({"t": "end", "h": h["id"]}), bottom, 18)
	endb.position = Vector2(1140, 180); endb.custom_minimum_size = Vector2(120, 44); endb.disabled = not my_turn

func _unit(u: Dictionary, pos: Vector2, w: float, is_hero: bool, is_active: bool) -> void:
	var S: Dictionary = g.S
	var frame := PanelContainer.new(); frame.position = pos; frame.custom_minimum_size = Vector2(w, 385)
	frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new()); frame.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(frame)
	var box := VBoxContainer.new(); box.alignment = BoxContainer.ALIGNMENT_END; box.add_theme_constant_override("separation", 2); frame.add_child(box)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	unit_nodes[u["id"]] = frame
	if not is_hero:
		box.add_child(_intent(u))
	var spr := texrect(Art.unit_tex(u, 150 if not u.get("boss") else 190), box)
	sprites[u["id"]] = spr
	spr.custom_minimum_size = Vector2(w, 150 if not u.get("boss") else 190)
	spr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if u["dead"]: spr.modulate = Color(1, 1, 1, 0.25)
	elif is_hero and g.T(u.get("turnDone")) and S["phase"] == "hero": spr.modulate = Color(0.6, 0.6, 0.6)
	var nm: String = (("ELITE · " if u.get("elite") else "BOSS · " if u.get("boss") else "") + u["name"])
	var nl := lbl(nm, 13, GOLD if is_active else Color.WHITE, box); nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.clip_text = true
	if not is_hero and u.get("desc", "") != "": nl.tooltip_text = u["desc"]; nl.mouse_filter = Control.MOUSE_FILTER_PASS
	var hp := ProgressBar.new(); hp.max_value = u["maxHp"]; hp.value = maxi(0, u["hp"]); hp.show_percentage = false; hp.custom_minimum_size = Vector2(w - 10, 16)
	var fill := StyleBoxFlat.new(); fill.bg_color = Color("#d83a3a") if not is_hero else Color("#3ac85a"); fill.set_corner_radius_all(4); hp.add_theme_stylebox_override("fill", fill)
	var bgs := StyleBoxFlat.new(); bgs.bg_color = Color("#3a1a1a"); bgs.set_corner_radius_all(4); hp.add_theme_stylebox_override("background", bgs)
	box.add_child(hp)
	var hpl := lbl("%d/%d" % [maxi(0, u["hp"]), u["maxHp"]] + ("   🛡 %d" % u["block"] if u["block"] > 0 else ""), 12, Color.WHITE, hp)
	hpl.set_anchors_preset(Control.PRESET_FULL_RECT); hpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hpl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if u["block"] > 0: hpl.add_theme_color_override("font_color", Color("#9fd0ff"))
	if is_hero: lbl("⚡ %d" % u["energy"] + ("  ✔" if g.T(u.get("turnDone")) else ""), 12, Color("#7ad0ff"), box).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sts := HFlowContainer.new(); sts.custom_minimum_size = Vector2(w, 22); box.add_child(sts)
	var all := {}
	for k in u.get("passive", {}): all[k] = u["passive"][k]
	for k in u["status"]: all[k] = u["status"][k]
	if u.get("frozen"): all["frozen"] = 1
	if u.get("mindStun"): all["corruptedMind"] = 1
	for k in Art.U["status"]:
		if not all.has(k) or not g.T(all[k]): continue
		var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 0); sts.add_child(hb)
		hb.tooltip_text = Art.status_tip(k, all[k]); hb.mouse_filter = Control.MOUSE_FILTER_PASS
		texrect(Art.tex(Art.U["status"][k]["icon"], 18), hb)
		if not Art.U["status"][k]["flag"]: lbl(str(all[k]), 11, Color.WHITE, hb)
	# Klicks: Ziel wählen / Held wechseln (Rahmen leuchtet, wenn die gewählte Karte hierauf gespielt werden kann)
	if _can_target(u, is_hero):
		var hl := StyleBoxFlat.new(); hl.bg_color = Color(1, 0.8, 0.3, 0.10); hl.border_color = GOLD; hl.set_border_width_all(2); hl.set_corner_radius_all(8)
		frame.add_theme_stylebox_override("panel", hl)
	var uid0: String = u["id"]
	frame.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: _unit_clicked(uid0, is_hero))

func _intent(e: Dictionary) -> Control:
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.custom_minimum_size.y = 30
	var it = e.get("intent")
	if e["dead"] or it == null: return hb
	var p := panel(Color(0.23, 0.02, 0.04, 0.9), Color("#7a2a2a"), 10, 2)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4); p.add_child(row); hb.add_child(p)
	var tip := "[b]%s[/b]" % it.get("name", "")
	if g.T(it.get("dmg")):
		var at: String = it.get("atk", "aoe")
		texrect(Art.tex(Art.U["atk"].get(at, ""), 22), row)
		var v: int = g._attack_value(e, it["dmg"])
		lbl(str(v) + ("×%d" % it["hits"] if g.nz(it, "hits") > 1 else ""), 17, Color("#ff6a6a"), row)
		tip += "\n%s – %s" % [Art.U["atk_types"][at]["name"], Art.U["atk_types"][at]["desc"]]
	if g.T(it.get("block")) or g.T(it.get("aegis")) or g.T(it.get("blockAllies")) or g.T(it.get("protect")):
		lbl("🛡", 15, Color("#8fc7ff"), row)
	if g.T(it.get("strength")) or g.T(it.get("rallyStr")) or g.T(it.get("summon")): lbl("▲", 15, Color("#ffb03a"), row)
	if g.T(it.get("healAllies")) or g.T(it.get("healLow")) or g.T(it.get("healSelf")): lbl("✚", 15, Color("#6aff8a"), row)
	for k in ["poison", "burn", "weak", "brittle", "hex", "drain"]:
		if g.T(it.get(k)): lbl("☠", 15, Color("#c88aff"), row); break
	if row.get_child_count() == 0: lbl("?", 15, Color.WHITE, row)
	p.tooltip_text = Art.bb(tip.replace("[b]", "").replace("[/b]", ""))
	return hb

func _can_target(u: Dictionary, is_hero: bool) -> bool:
	if selected == null or u["dead"]: return false
	var h = g.active_hero()
	if h == null: return false
	var c = _hand_card(h, selected)
	if c == null: return false
	var s: Dictionary = g.stats(c)
	if is_hero: return g.hero_targetable(g.CARDS[c["key"]])
	return g.needs_target(s)

func _hand_card(h: Dictionary, id) -> Variant:
	for c in h["hand"]:
		if c["id"] == id: return c
	return null

func _unit_clicked(id: String, is_hero: bool) -> void:
	var S: Dictionary = g.S
	if selected != null:
		var h = g.active_hero()
		var u = S["heroes"].get(id) if is_hero else null
		if not is_hero:
			for e in S["enemies"]:
				if e["id"] == id: u = e
		if h != null and u != null and _can_target(u, is_hero):
			_play(h, selected, id); return
	if is_hero and S["phase"] == "hero":
		g.switch_hero(id); selected = null; dirty = true

func _play(h: Dictionary, card_id, target) -> void:
	var c = _hand_card(h, card_id)
	if c == null: return
	var s: Dictionary = g.stats(c)
	if s.style != null:
		_style_popup(h, card_id, target, s.style); return
	act({"t": "play", "h": h["id"], "card": card_id, "target": target})

func _style_popup(h: Dictionary, card_id, target, style: String) -> void:
	var p := panel(Color("#1e1828"), GOLD, 10, 2); p.position = Vector2(440, 200); root.add_child(p)
	var v := VBoxContainer.new(); p.add_child(v)
	lbl("Choose your style", 16, GOLD, v)
	for o in g.D["DRUNK_OPTS"][style]:
		var oid: String = o["id"]
		var b := btn("%s – %s" % [o["name"], o["text"]], func(): act({"t": "play", "h": h["id"], "card": card_id, "target": target, "opt": oid}), v, 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT

func _card(c: Dictionary, h: Dictionary, playable_turn: bool) -> Control:
	var d: Dictionary = g.CARDS[c["key"]]
	var s: Dictionary = g.stats(c)
	var can: bool = playable_turn and not g.T(d.get("unplayable")) and s.cost <= h["energy"] and s.depthCost <= g.st(h, "depth") and not g.lacks_sanity(h, s)
	var col: Color = Art.RARITY_COL.get(d.get("rarity", "common"), Color.GRAY)
	var p := panel(Color("#2c2438") if c["id"] != selected else Color("#4a3a20"), GOLD if c["id"] == selected else col, 10, 3)
	p.custom_minimum_size = Vector2(150, 235)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); p.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	var cost := lbl(str(s.cost), 18, Color("#7ad0ff") if not c.get("replayTax") else Color("#ff5a5a"), top)
	if c.get("replayTax"): cost.tooltip_text = "Already played this turn: +%d Energy" % c["replayTax"]; cost.mouse_filter = Control.MOUSE_FILTER_PASS
	var nm := lbl(g.card_name(c), 13, Color.WHITE if not g.is_foil(c) else Color("#9affff"), top); nm.clip_text = true; nm.custom_minimum_size.x = 112
	var art := texrect(Art.card_tex(c["key"], 72), v); art.custom_minimum_size = Vector2(130, 74)
	var ty := lbl(str(d.get("type", "")).capitalize() + ("  ◆%d" % c["gems"].size() if c["gems"].size() else ""), 10, col, v); ty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rich(Art.card_text(c), 11, 134, v)
	if not can: p.modulate = Color(0.6, 0.6, 0.6)
	var cid = c["id"]
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and can: _card_clicked(h, cid))
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if can else Control.CURSOR_ARROW
	return p

func _card_clicked(h: Dictionary, cid) -> void:
	if selected == cid: selected = null; dirty = true; return
	var c = _hand_card(h, cid)
	var s: Dictionary = g.stats(c)
	var d: Dictionary = g.CARDS[c["key"]]
	var heroes_ok: bool = g.hero_targetable(d) and g.living().size() > 1
	if g.needs_target(s) and g.alive().size() > 1 or heroes_ok:
		selected = cid; dirty = true; return
	var tgt = g.alive()[0]["id"] if g.needs_target(s) and g.alive().size() == 1 else null
	_play(h, cid, tgt)

# ---------- Karten-Mini (Belohnung, Shop, Deck) ----------
func _card_static(key_or_card, on_click: Callable = Callable(), extra: String = "") -> Control:
	var c: Dictionary = key_or_card if typeof(key_or_card) == TYPE_DICTIONARY else {"key": key_or_card, "id": -1, "gems": []}
	var d: Dictionary = g.CARDS[c["key"]]
	var col: Color = Art.RARITY_COL.get(d.get("rarity", "common"), Color.GRAY)
	var p := panel(Color("#2c2438"), col, 10, 3); p.custom_minimum_size = Vector2(160, 245)
	var v := VBoxContainer.new(); p.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	lbl(str(g.stats(c).cost), 18, Color("#7ad0ff"), top)
	var nm := lbl(g.card_name(c), 13, Color.WHITE, top); nm.clip_text = true; nm.custom_minimum_size.x = 120
	var art := texrect(Art.card_tex(c["key"], 72), v); art.custom_minimum_size = Vector2(140, 74)
	lbl(str(d.get("rarity", "")).capitalize() + " " + str(d.get("type", "")), 10, col, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rich(Art.card_text(c), 11, 144, v)
	for gm in c.get("gems", []): lbl("◆ " + g.gem_title(gm), 10, Art.RARITY_COL.get(g.gem_rarity(gm), Color.WHITE), v)
	if extra != "": lbl(extra, 13, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if on_click.is_valid():
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: on_click.call())
	return p

# ---------- Nach dem Kampf / Lager / Shop ----------
func _post_screen() -> void:
	var S: Dictionary = g.S
	var ids: Array = S["party"].filter(func(id): return S["post"].has(id) and g.mine(id))
	if post_hero == "" or not ids.has(post_hero) or g.T(S["post"][post_hero].get("ready")):
		post_hero = ""
		for id in ids:
			if not g.T(S["post"][id].get("ready")): post_hero = id; break
	if post_hero == "":
		var wv := centered_vbox(root)
		lbl("Waiting for the other players…", 20, Color.WHITE, wv)
		for id in S["party"]:
			if S["post"].has(id): lbl("%s %s" % [S["heroes"][id]["name"], "✔" if g.T(S["post"][id].get("ready")) else "…"], 15, Color("#cfc6e0"), wv)
		return
	var h: Dictionary = S["heroes"][post_hero]
	var p: Dictionary = S["post"][post_hero]
	var v := centered_vbox(root)
	var tabs := HBoxContainer.new(); tabs.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(tabs)
	for id in ids:
		var hid: String = id
		var b := btn(S["heroes"][id]["name"] + (" ✔" if g.T(S["post"][id].get("ready")) else ""), func(): post_hero = hid; camp_mode = ""; dirty = true, tabs, 13)
		b.disabled = id == post_hero
	lbl("%s  ·  %d/%d HP  ·  %d Gold" % [h["name"], h["hp"], h["maxHp"], h["gold"]], 16, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if sel_gem != null:
		_socket_screen(v, h); return
	match p["kind"]:
		"reward": _reward(v, h, p)
		"camp": _camp(v, h, p)
		"shop": _shop(v, h, p)

func _gem_bar(v: Node, h: Dictionary) -> void:
	if h["gems"].is_empty(): return
	lbl("Gems – click one to socket it into a card:", 13, Color("#9affd8"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var fl := HFlowContainer.new(); fl.custom_minimum_size.x = 1000; fl.alignment = FlowContainer.ALIGNMENT_CENTER; v.add_child(fl)
	var fusing := fuse_pick.size() > 0
	for gm in h["gems"]:
		var gg: Dictionary = gm
		var b := btn(("☑ " if fuse_pick.has(gg["id"]) else "") + g.gem_title(gm), func(): _gem_clicked(h, gg), fl, 12)
		b.tooltip_text = _gem_tip(gm)
		b.add_theme_color_override("font_color", Art.RARITY_COL.get(g.gem_rarity(gm), Color.WHITE))
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(hb)
	if fusing:
		lbl("Fuse: pick 3 gems of the same rarity (%d/3)" % fuse_pick.filter(func(x): return x != -1).size(), 13, Color("#ffd27a"), hb)
		var picks: Array = fuse_pick.filter(func(x): return x != -1)
		var fb := btn("Fuse!", func(): act({"t": "fuse", "h": h["id"], "gems": picks}); fuse_pick.clear(), hb, 13)
		fb.disabled = picks.size() != 3
		btn("Cancel", func(): fuse_pick.clear(); dirty = true, hb, 13)
	elif h["gems"].size() >= 3:
		btn("Fuse 3 gems → 1 of the next rarity", func(): fuse_pick.append(-1); dirty = true, hb, 13)

func _gem_tip(gm: Dictionary) -> String:
	if gm.get("rune"): return g.gem_title(gm)
	var fx: Array = Art.U.get("gem_fx", {}).get(gm["type"], [])
	var t: String = Art.bb(str(fx[int(gm["tier"]) - 1])) if fx.size() >= int(gm["tier"]) else ""
	if gm.get("fleeting"): t += "\nFleeting: double effect, but the card can only be played once per fight."
	return t

func _gem_clicked(h: Dictionary, gm: Dictionary) -> void:
	if fuse_pick.size() > 0:
		fuse_pick.erase(-1)
		if fuse_pick.has(gm["id"]): fuse_pick.erase(gm["id"])
		elif fuse_pick.size() < 3 and not gm.get("rune"):
			var tier := int(gm["tier"])
			var same := fuse_pick.all(func(id): return h["gems"].any(func(x): return x["id"] == id and int(x["tier"]) == tier))
			if same and tier < 5: fuse_pick.append(gm["id"])
		if fuse_pick.is_empty(): fuse_pick.append(-1)
		dirty = true; return
	sel_gem = gm["id"]; dirty = true

func _socket_screen(v: Node, h: Dictionary) -> void:
	var gm = null
	for x in h["gems"]:
		if x["id"] == sel_gem: gm = x
	if gm == null: sel_gem = null; dirty = true; return
	lbl("Socket %s – choose a card (right click = back)" % g.gem_title(gm), 16, Color("#9affd8"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(1220, 500); v.add_child(sc)
	var fl := HFlowContainer.new(); fl.custom_minimum_size.x = 1200; sc.add_child(fl)
	for c in h["deck"]:
		var why: String = g.can_socket(c, gm)
		var cid = c["id"]; var gid = gm["id"]
		var w := _card_static(c, func(): sel_gem = null; act({"t": "socket", "h": h["id"], "card": cid, "gem": gid}) if why == "" else null, why)
		if why != "": w.modulate = Color(0.5, 0.5, 0.5)
		fl.add_child(w)
	btn("Back", func(): sel_gem = null; dirty = true, v)

func _reward(v: Node, h: Dictionary, p: Dictionary) -> void:
	lbl("Victory!  +%d Gold" % p.get("gold", 0), 26, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if p.get("gem") != null: lbl("Found: " + g.gem_title(p["gem"]), 14, Color("#9affd8"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not p["picked"]:
		lbl("Choose a card", 16, Color.WHITE, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 14); v.add_child(row)
		for k in p["cards"]:
			var kk: String = k
			row.add_child(_card_static(k, func(): act({"t": "pick", "h": h["id"], "key": kk})))
		var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(hb)
		btn("Skip (+1 Reroll)", func(): act({"t": "pick", "h": h["id"], "key": null}), hb)
		if h["rerolls"] > 0: btn("Reroll (%d)" % h["rerolls"], func(): act({"t": "reroll", "h": h["id"]}), hb)
	else:
		btn("Continue", func(): act({"t": "ready", "h": h["id"]}), v, 20)
	_gem_bar(v, h)

func _camp(v: Node, h: Dictionary, p: Dictionary) -> void:
	lbl("Campfire", 30, Color("#ffb03a"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if g._camp_used(p):
		btn("Continue", func(): act({"t": "ready", "h": h["id"]}), v, 20); return
	if camp_mode == "upgrade":
		lbl("Choose a card to upgrade", 16, Color.WHITE, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(1200, 470); v.add_child(sc)
		var fl := HFlowContainer.new(); fl.custom_minimum_size.x = 1180; sc.add_child(fl)
		for c in h["deck"]:
			if not g.can_upgrade(c): continue
			var cid = c["id"]
			var up: Dictionary = c.duplicate(); up["upgraded"] = true
			fl.add_child(_card_static(up, func(): camp_mode = ""; act({"t": "campup", "h": h["id"], "card": cid})))
		btn("Back", func(): camp_mode = ""; dirty = true, v)
		return
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 20); v.add_child(row)
	btn("Rest (heal %d HP)" % JS.rnd(h["maxHp"] * g.CAMP_HEAL), func(): act({"t": "rest", "h": h["id"]}), row, 18)
	btn("Upgrade a card", func(): camp_mode = "upgrade"; dirty = true, row, 18)
	btn("Leave", func(): act({"t": "campdone", "h": h["id"]}), row, 18)
	_gem_bar(v, h)

func _shop(v: Node, h: Dictionary, p: Dictionary) -> void:
	lbl("Shop", 30, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 12); v.add_child(row)
	var cards: Array = p["shop"]["cards"]
	for i in cards.size():
		var it: Dictionary = cards[i]
		if it["sold"]: continue
		var ii: int = i
		var w := _card_static(it["key"], func(): act({"t": "buy", "h": h["id"], "kind": "card", "idx": ii}), "%d Gold" % it["price"])
		if h["gold"] < it["price"]: w.modulate = Color(0.6, 0.6, 0.6)
		row.add_child(w)
	var gems := HBoxContainer.new(); gems.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(gems)
	var gl: Array = p["shop"]["gems"]
	for i in gl.size():
		var it: Dictionary = gl[i]
		if it["sold"]: continue
		var ii: int = i
		var b := btn("%s – %d Gold" % [g.gem_title(it["gem"]), it["price"]], func(): act({"t": "buy", "h": h["id"], "kind": "gem", "idx": ii}), gems, 13)
		b.disabled = h["gold"] < it["price"]
	btn("Leave Shop", func(): act({"t": "ready", "h": h["id"]}), v, 18)
	_gem_bar(v, h)

# ---------- Events ----------
func _event_screen() -> void:
	var S: Dictionary = g.S
	var ev: Dictionary = S["event"]
	var info: Dictionary = g.D["EVENTS"].get(ev["type"], {"name": ev["type"], "desc": ""})
	var v := centered_vbox(root)
	lbl(info["name"], 30, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rich("[center]%s[/center]" % Art.bb(info["desc"]), 14, 820, v)
	match ev["type"]:
		"arena":
			var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(row)
			for t in ["easy", "medium", "hard"]:
				var tt: String = t
				btn(t.capitalize(), func(): act({"t": "ev", "op": "arena", "tier": tt}), row, 18)
		"forge", "anomaly":
			var op := "forge" if ev["type"] == "forge" else "transform"
			var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(hb)
			var mine_ids: Array = S["party"].filter(func(id): return g.mine(id))
			for id in mine_ids:
				var hid: String = id
				var b := btn(S["heroes"][id]["name"], func(): post_hero = hid; dirty = true, hb, 13)
				b.disabled = post_hero == id
			if not mine_ids.has(post_hero): post_hero = mine_ids[0] if mine_ids.size() else S["party"][0]
			var h: Dictionary = S["heroes"][post_hero]
			if ev["type"] == "anomaly":
				var tries: int = g.nz(ev.get("triesBy", {}), post_hero)
				lbl("Next transform: %d Gold (you have %d)" % [tries * 10, h["gold"]], 14, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(1200, 400); v.add_child(sc)
			var fl := HFlowContainer.new(); fl.custom_minimum_size.x = 1180; sc.add_child(fl)
			for c in h["deck"]:
				if op == "forge" and not g.can_upgrade(c): continue
				var cid = c["id"]
				fl.add_child(_card_static(c, func(): act({"t": "ev", "op": op, "h": post_hero, "card": cid})))
		"buddy":
			var st: String = ev["stage"]
			if st == "roll": btn("Roll the rarity", func(): act({"t": "ev", "op": "buddyroll"}), v, 18)
			elif st == "hero":
				lbl("Rarity: %s – who gets the card?" % str(ev["rarity"]).capitalize(), 16, Art.RARITY_COL[ev["rarity"]], v)
				var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(hb)
				for id in S["party"]:
					var hid: String = id
					btn(S["heroes"][id]["name"], func(): act({"t": "ev", "op": "buddyhero", "h": hid}), hb, 16)
			elif st == "mods":
				lbl("Modification %d / %d" % [ev["mods"].size() + 1, g.slots_of(ev["rarity"])], 16, Color.WHITE, v)
				var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(hb)
				for i in ev["options"].size():
					var ii: int = i
					btn(ev["options"][i].get("label", "?"), func(): act({"t": "ev", "op": "buddymod", "i": ii, "h": ev["hero"]}), hb, 16).disabled = not g.mine(ev["hero"])
			elif st == "done" and ev.get("cardKey") != null:
				v.add_child(_card_static(ev["cardKey"]))
	btn("Leave", func(): act({"t": "ev", "op": "leave"}), v, 18)

# ---------- Deck ----------
func _deck_screen() -> void:
	var S: Dictionary = g.S
	var h = g.active_hero()
	if h == null: h = S["heroes"][S["party"][0]]
	var v := centered_vbox(root)
	lbl("%s's deck (%d cards) – right click or Deck to close" % [h["name"], h["deck"].size()], 18, GOLD, v)
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(hb)
	for id in S["party"]:
		var hid: String = id
		btn(S["heroes"][id]["name"], func(): g.S["active"] = hid; dirty = true, hb, 13)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(1240, 560); v.add_child(sc)
	var fl := HFlowContainer.new(); fl.custom_minimum_size.x = 1220; sc.add_child(fl)
	for c in h["deck"]: fl.add_child(_card_static(c))

# ---------- Ende ----------
func _end_screen(won: bool) -> void:
	var v := centered_vbox(root)
	lbl("VICTORY!" if won else "DEFEAT", 48, GOLD if won else Color("#ff5a5a"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl("You reached room %d." % g.S.get("room", 0), 18, Color.WHITE, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn("New Run", func(): g.S["runActive"] = false; g.S["phase"] = "idle"; dirty = true, v, 20)

# ---------- Effekte ----------
func _float_text(u, text: String, cls: String) -> void:
	if typeof(u) != TYPE_DICTIONARY or not unit_nodes.has(u.get("id")): return
	var n: Control = unit_nodes[u["id"]]
	if not is_instance_valid(n): return
	var col := Color.WHITE
	if cls.contains("heal"): col = Color("#6aff8a")
	elif cls.contains("blk") or cls.contains("ice"): col = Color("#8fc7ff")
	elif cls.contains("gold"): col = GOLD
	elif cls.contains("poison"): col = Color("#9dff4a")
	elif cls.contains("crit") or cls == "dmg": col = Color("#ff5a4a")
	elif cls.contains("status"): col = Color("#d8b4ff")
	var l := lbl(text, 18, col, overlay)
	l.add_theme_color_override("font_outline_color", Color.BLACK); l.add_theme_constant_override("outline_size", 5)
	l.position = n.global_position + Vector2(n.size.x / 2 - 30 + randf_range(-20, 20), 120 + randf_range(-10, 10))
	var tw := create_tween(); tw.tween_property(l, "position:y", l.position.y - 60, 0.9 * maxf(speed, 0.4)); tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9 * maxf(speed, 0.4))
	tw.tween_callback(l.queue_free)

func _banner(text: String, sub: String, ms: float) -> void:
	var p := panel(Color(0.05, 0.03, 0.08, 0.88), GOLD, 12, 2)
	var v := VBoxContainer.new(); p.add_child(v)
	lbl(text, 30, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if sub != "": lbl(sub, 15, Color("#d8d0e8"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(p)
	p.reset_size(); p.position = Vector2(640 - p.size.x / 2, 230)
	var tw := create_tween(); tw.tween_interval(ms / 1000.0 * speed); tw.tween_property(p, "modulate:a", 0.0, 0.2); tw.tween_callback(p.queue_free)

func _toast(text: String) -> void:
	var l := lbl(text, 13, Color("#f0e8ff"), toast_box)
	l.add_theme_color_override("font_outline_color", Color.BLACK); l.add_theme_constant_override("outline_size", 4)
	var tw := create_tween(); tw.tween_interval(3.0); tw.tween_property(l, "modulate:a", 0.0, 0.5); tw.tween_callback(l.queue_free)

# ---------- Koop-Lobby ----------
func _lobby() -> void:
	var v := centered_vbox(root, 0)
	lbl("CO-OP LOBBY", 34, GOLD, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if net.is_host:
		rich("[center]%s[/center]" % net.upnp_info, 14, 760, v)
	else:
		lbl("Connected as %s – waiting for the host to start." % net.names.get(net.my_slot, net.my_slot) if net.my_slot != "host" else "Connecting…", 15, Color("#cfc6e0"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pl: Array = net.players() if net.is_host else ["host"] + net.names.keys().filter(func(k): return k != "host")
	lbl("Players: " + ", ".join(pl.map(func(sl): return net.names.get(sl, sl) + (" (you)" if sl == net.my_slot else ""))), 15, Color.WHITE, v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var party: Array = net.lobby.get("party", [])
	var roles: Dictionary = net.lobby.get("roles", {})
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); v.add_child(row)
	for id in g.D["CLASS_ORDER"]:
		var on: bool = party.has(id)
		var p := panel(Color("#2e2440") if on else PANEL, GOLD if on else Color("#4a3a5a"), 10, 3 if on else 2)
		p.custom_minimum_size = Vector2(150, 220); row.add_child(p)
		var vb := VBoxContainer.new(); vb.alignment = BoxContainer.ALIGNMENT_CENTER; p.add_child(vb)
		texrect(Art.svg(g.D["HEROES"][id]["key"], 110), vb)
		lbl(g.D["HEROES"][id]["name"], 14, GOLD if on else Color.WHITE, vb).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cid: String = id
		if on:
			var owner: String = roles.get(id, "host")
			var ob := btn("Player: " + net.names.get(owner, owner), func():
				var i := pl.find(owner); net.lobby["roles"][cid] = pl[(i + 1) % pl.size()]; net.push_lobby(), vb, 12)
			ob.disabled = not net.is_host
		if net.is_host:
			p.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					var pt: Array = net.lobby["party"]
					if pt.has(cid): pt.erase(cid); net.lobby["roles"].erase(cid)
					elif pt.size() < 4: pt.append(cid); net.lobby["roles"][cid] = "host"
					net.push_lobby())
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 12); v.add_child(hb)
	if net.is_host:
		var b := btn("Start Co-op Run (%d heroes)" % party.size(), func():
			var pt: Array = g.D["CLASS_ORDER"].filter(func(x): return net.lobby["party"].has(x))
			act({"t": "start", "seed": randi() % 2000000000, "roles": net.lobby["roles"].duplicate(), "party": pt, "mode": "coop"}), hb, 18)
		b.disabled = party.is_empty()
	btn("Leave", func(): net.leave(); net_msg = ""; dirty = true, hb, 15)
	lbl("Each player controls the heroes assigned to them. Version %d" % g.game_version(), 12, Color("#8a80a0"), v).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# ---------- Hintergrund des aktuellen Bioms ----------
func _background() -> void:
	var b = g.S.get("biome")
	var svg: String = Art.U.get("biome_bg", {}).get(b if b != null else "night", "")
	if svg == "": return
	var t := Art.tex(svg, 470)
	var r := TextureRect.new(); r.texture = t; r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.position = Vector2(0, 0); r.size = Vector2(1280, 470); r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ph: String = g.S.get("phase", "")
	r.modulate = Color(1, 1, 1, 0.95 if ph in ["hero", "enemy", "fight", "won"] else 0.35)
	root.add_child(r)
	if ph in ["hero", "enemy", "fight", "won"]:
		var floor := ColorRect.new(); floor.color = Color(0.06, 0.04, 0.09, 0.92); floor.position = Vector2(0, 450); floor.size = Vector2(1280, 270)
		floor.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(floor)

# ---------- Animationen ----------
func _anim(u, cls: String) -> void:
	if typeof(u) != TYPE_DICTIONARY or not sprites.has(u.get("id")): return
	var spr: TextureRect = sprites[u["id"]]
	if not is_instance_valid(spr): return
	var t := maxf(speed, 0.25)
	var tw := create_tween()
	match cls:
		"lunge":
			var dir := 26.0 if u.get("hero") else -26.0
			tw.tween_property(spr, "position:x", spr.position.x + dir, 0.12 * t)
			tw.tween_property(spr, "position:x", spr.position.x, 0.18 * t)
		"hit":
			spr.modulate = Color(1, 0.35, 0.35)
			tw.tween_property(spr, "position:x", spr.position.x + 6, 0.05 * t)
			tw.tween_property(spr, "position:x", spr.position.x - 6, 0.05 * t)
			tw.tween_property(spr, "position:x", spr.position.x, 0.05 * t)
			tw.parallel().tween_property(spr, "modulate", Color.WHITE, 0.3 * t)
		"shield":
			spr.modulate = Color(0.6, 0.85, 1.4)
			tw.tween_property(spr, "modulate", Color.WHITE, 0.4 * t)
		_:
			spr.modulate = Color(1.3, 1.3, 1.0)
			tw.tween_property(spr, "modulate", Color.WHITE, 0.3 * t)

# ---------- Glossar ----------
func _glossary() -> void:
	var p := panel(Color("#17121f"), GOLD, 8, 2); p.position = Vector2(10, 40); p.size = Vector2(1260, 672); p.custom_minimum_size = Vector2(1260, 672); root.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); p.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	lbl("Glossary", 22, GOLD, top)
	for t in [["cards", "Cards"], ["status", "Keywords & Status"], ["gems", "Gems"]]:
		var tk: String = t[0]
		btn(t[1], func(): gloss_tab = tk; dirty = true, top, 14).disabled = gloss_tab == tk
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(sp)
	btn("Close", func(): overlay_view = ""; dirty = true, top, 14)
	if gloss_tab == "cards":
		var row := HBoxContainer.new(); v.add_child(row)
		for id in g.D["CLASS_ORDER"]:
			var cid: String = id
			btn(g.D["HEROES"][id]["name"], func(): gloss_class = cid; gloss_spec = null; dirty = true, row, 13).disabled = gloss_class == id
		var row2 := HBoxContainer.new(); v.add_child(row2)
		btn("Class cards", func(): gloss_spec = null; dirty = true, row2, 12).disabled = gloss_spec == null
		for spx in g.D["SPECS"][gloss_class]:
			var sid: String = spx["id"]
			btn(spx["name"], func(): gloss_spec = sid; dirty = true, row2, 12).disabled = gloss_spec == sid
		var order := ["common", "uncommon", "rare", "epic", "legendary"]
		var keys: Array = g.CARDS.keys().filter(func(k):
			var c: Dictionary = g.CARDS[k]
			return c.get("char") == gloss_class and not g.T(c.get("custom")) and not g.T(c.get("crafted")) and not g.T(c.get("token")) and (c.get("spec") if g.T(c.get("spec")) else null) == gloss_spec)
		keys.sort_custom(func(a, b): return order.find(g.CARDS[a]["rarity"]) < order.find(g.CARDS[b]["rarity"]))
		lbl("%d cards" % keys.size(), 11, Color("#8a80a0"), v)
		var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(1240, 520); v.add_child(sc)
		var fl := HFlowContainer.new(); fl.custom_minimum_size.x = 1220; sc.add_child(fl)
		for k in keys: fl.add_child(_card_static(k))
	elif gloss_tab == "status":
		var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(1240, 600); v.add_child(sc)
		var vb := VBoxContainer.new(); vb.custom_minimum_size.x = 1200; sc.add_child(vb)
		for k in Art.U["status"]:
			var st: Dictionary = Art.U["status"][k]
			var hb := HBoxContainer.new(); vb.add_child(hb)
			texrect(Art.tex(st["icon"], 22), hb)
			rich(Art.status_tip(k, "X"), 13, 1150, hb)
		for k in Art.U["atk_types"]:
			var hb := HBoxContainer.new(); vb.add_child(hb)
			texrect(Art.tex(Art.U["atk"].get(k, ""), 22), hb)
			rich("[b]%s:[/b] %s" % [Art.U["atk_types"][k]["name"], Art.U["atk_types"][k]["desc"]], 13, 1150, hb)
	else:
		var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(1240, 600); v.add_child(sc)
		var vb := VBoxContainer.new(); vb.custom_minimum_size.x = 1200; sc.add_child(vb)
		for k in g.GEM_ORDER:
			var gt: Dictionary = g.GEM_TYPES[k]
			var fx: Array = Art.U.get("gem_fx", {}).get(k, [])
			var tiers := []
			for t in range(int(gt.get("minTier", 1)), int(gt.get("maxTier", 5)) + 1): tiers.append("%s: %s" % [g.RARITY_ORDER[t - 1].capitalize(), Art.bb(str(fx[t - 1])) if fx.size() >= t else ""])
			rich("[b][color=%s]%s[/color][/b]%s  –  %s" % [gt.get("color", "#fff"), gt.get("name", k), (" (%s only)" % g.spec_of(_spec_owner(gt["spec"]), gt["spec"])["name"]) if g.T(gt.get("spec")) and g.spec_of(_spec_owner(gt["spec"]), gt["spec"]) != null else "", " · ".join(tiers)], 12, 1180, vb)

func _spec_owner(spec: String) -> String:
	for h in g.D["SPECS"]:
		for x in g.D["SPECS"][h]:
			if x["id"] == spec: return h
	return "knight"

# ---------- Statistik ----------
func _stats() -> void:
	var p := panel(Color("#17121f"), GOLD, 8, 2); p.position = Vector2(140, 60); p.custom_minimum_size = Vector2(1000, 0); root.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); p.add_child(v)
	var top := HBoxContainer.new(); v.add_child(top)
	lbl("Stats", 22, GOLD, top)
	for t in [["fight", "Current fight"], ["run", "Whole run"]]:
		var tk: String = t[0]
		btn(t[1], func(): stats_scope = tk; dirty = true, top, 13).disabled = stats_scope == tk
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(sp)
	btn("Close", func(): overlay_view = ""; dirty = true, top, 13)
	var data: Dictionary = g.S.get("stats", {}).get(stats_scope, {})
	var cols := [["dmg", "Damage", Color("#ff7a6e")], ["heal", "Healing", Color("#7cd47c")], ["block", "Block", Color("#8fc7ff")], ["debuff", "Debuffs", Color("#c77dff")], ["buff", "Buffs", Color("#ffcf6a")]]
	var grid := GridContainer.new(); grid.columns = 6; grid.add_theme_constant_override("h_separation", 30); grid.add_theme_constant_override("v_separation", 8); v.add_child(grid)
	lbl("Hero", 14, GOLD, grid)
	for c in cols: lbl(c[1], 14, c[2], grid)
	var tot := {}
	for c in cols:
		tot[c[0]] = 0
		for h in g.hero_list(): tot[c[0]] += int(data.get(h["id"], {}).get(c[0], 0))
	for h in g.hero_list():
		var o: Dictionary = data.get(h["id"], {})
		var hb := HBoxContainer.new(); grid.add_child(hb)
		texrect(Art.unit_tex(h, 34), hb)
		lbl(h["name"], 14, Color.WHITE, hb)
		for c in cols:
			var val := int(o.get(c[0], 0))
			var cell := lbl("%d  (%d%%)" % [val, int(round(100.0 * val / tot[c[0]])) if tot[c[0]] > 0 else 0], 14, Color.WHITE, grid)
			var det: Dictionary = o.get("det", {}).get(c[0], {})
			if det.size(): cell.tooltip_text = "\n".join(det.keys().map(func(k): return "%s: %d" % [{"hp": "vs. HP", "shield": "vs. Block/Shields"}.get(k, k), det[k]])); cell.mouse_filter = Control.MOUSE_FILTER_PASS
	if stats_scope == "fight" and g.S.get("enemies", []).size():
		lbl("Enemies (this fight)", 15, Color("#ff9a8a"), v)
		var eg := GridContainer.new(); eg.columns = 6; eg.add_theme_constant_override("h_separation", 30); v.add_child(eg)
		for e in g.S["enemies"]:
			var o: Dictionary = data.get(e["id"], {})
			lbl(e["name"] + (" ✝" if e["dead"] else ""), 13, Color("#d8d0e8"), eg)
			for c in cols: lbl(str(int(o.get(c[0], 0))), 13, c[2], eg)

# ---------- Gold senden (25 % Steuer) ----------
func _gold_screen() -> void:
	var S: Dictionary = g.S
	var p := panel(Color("#17121f"), GOLD, 8, 2); p.position = Vector2(340, 120); p.custom_minimum_size = Vector2(600, 0); root.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 10); p.add_child(v)
	lbl("Send Gold – 25% is lost as taxes", 20, GOLD, v)
	var from = g.active_hero()
	if from == null or not g.mine(from["id"]):
		for id in S["party"]:
			if g.mine(id): from = S["heroes"][id]; break
	if from == null: return
	lbl("From %s (%d Gold)" % [from["name"], from["gold"]], 15, Color.WHITE, v)
	for id in S["party"]:
		if id == from["id"]: continue
		var to: Dictionary = S["heroes"][id]
		var hb := HBoxContainer.new(); v.add_child(hb)
		lbl("To %s (%d Gold):" % [to["name"], to["gold"]], 14, Color("#d8d0e8"), hb)
		for n in [10, 25, 50, 100]:
			var nn: int = n; var tid: String = id; var fid: String = from["id"]
			var b := btn("%d (→ %d)" % [n, n - int(ceil(n * 0.25))], func(): act({"t": "sendgold", "h": fid, "to": tid, "n": nn}), hb, 13)
			b.disabled = from["gold"] < n
	btn("Close", func(): overlay_view = ""; dirty = true, v, 14)
