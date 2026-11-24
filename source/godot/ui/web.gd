## =====================================================================
##   SPIEL IN DER EXE = DIE HTML-VERSION (1:1 gleiches Aussehen und Verhalten)
##   Ein eingebautes Browserfenster (godot_wry: WebView2 unter Windows) zeigt
##   res://web/index.html. Godot übernimmt nur, was ein Browser nicht kann:
##     - Direktverbindung per IP (ENet, UDP-Port 24565) mit UPnP-Portfreigabe
##     - Beenden, Vollbild, Versionsabgleich der Mitspieler
##   Nachrichten zwischen Seite und exe laufen als JSON:
##     Seite -> exe: window.ipc.postMessage({cmd, ...})   (Signal ipc_message)
##     exe -> Seite: post_message(json) -> document-Event "message" (ev.detail)
##   Fehlt das WebView (z. B. Linux-Tests ohne Bildschirm), startet die alte
##   Godot-Oberfläche ui/main.tscn als Ersatz.
## =====================================================================
extends Control

const PORT := 24565
const MAX_GUESTS := 3
const PAGE := "res://web/index.html"
const FALLBACK := "res://ui/main.tscn"

var wv: Control
var peer: ENetMultiplayerPeer
var is_host := false
var joined := false                     # Gast: vom Host angenommen
var verified := {}                      # Host: peer_id -> true (Version geprüft)
var upnp: UPNP
var upnp_thread: Thread
var info := {"type": "info"}
var version := 0
var test_posts = null                   # nur für Tests: Array statt Browserfenster
const WIN_CFG := "user://window.cfg"    # zuletzt gezogene Fenstergröße/-position (wird beim Start wiederhergestellt)
var _win_save_t := 0.0

func _ready() -> void:
	version = int(_read_version().get("version", 0))
	info["version"] = version
	if test_posts != null: return                       # Test ohne Fenster (tests/web_net_test.gd)
	if not ClassDB.class_exists("WebView") or DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred(FALLBACK); return
	var bg := ColorRect.new(); bg.color = Color("#07060a"); bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	wv = ClassDB.instantiate("WebView")
	wv.set("full_window_size", true)
	wv.set("url", PAGE)
	wv.set("data_directory", "user://webview")
	wv.set("background_color", Color("#07060a"))
	wv.set("devtools", OS.get_cmdline_user_args().has("--devtools"))
	wv.set("autoplay", true)
	wv.set("zoom_hotkeys", false)
	wv.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wv)
	wv.connect("ipc_message", _on_ipc)
	_restore_window()
	get_window().size_changed.connect(func(): _win_save_t = 0.6)   # gespeichert, kurz nachdem man aufhört zu ziehen
	print("WEB_READY version=", version)
	_self_update()

# ---------- Seite -> exe ----------
func _on_ipc(msg: String) -> void:
	var m = JSON.parse_string(msg)
	if typeof(m) != TYPE_DICTIONARY: return
	match str(m.get("cmd", "")):
		"ready": _post(info)
		"net_host": _host()
		"net_join": _join(str(m.get("ip", "")))
		"net_send": _send({"topic": m.get("topic"), "data": m.get("data")})
		"net_leave": _leave()
		"display": _display(str(m.get("mode", "windowed")))
		"quit": _leave(); get_tree().quit()
		"log": print("[page] ", m.get("text", ""))

## Anzeige: Fenster / Vollbild. (Exklusives Vollbild und ein randloses Fenster funktionieren mit dem
## eingebauten Browserfenster nicht – beides wurde entfernt; alte Einstellung "borderless" = Vollbild.)
func _display(mode: String) -> void:
	var w := get_window()
	var scr := DisplayServer.window_get_current_screen()
	match mode:
		"fullscreen", "borderless":
			w.borderless = false
			w.mode = Window.MODE_FULLSCREEN
		_:
			var was_big := w.mode != Window.MODE_WINDOWED or w.borderless
			w.mode = Window.MODE_WINDOWED
			w.borderless = false
			if was_big:
				var saved := _saved_window()
				w.size = saved.get("size", Vector2i(1280, 720))
				w.position = saved.get("pos", DisplayServer.screen_get_position(scr) + (DisplayServer.screen_get_size(scr) - w.size) / 2)

# ---------- Fenstergröße merken ----------
func _tick_window_save(delta: float) -> void:
	if _win_save_t > 0.0:
		_win_save_t -= delta
		if _win_save_t <= 0.0: _save_window()

func _save_window() -> void:
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED or w.borderless: return
	var cf := ConfigFile.new()
	cf.set_value("window", "size", w.size)
	cf.set_value("window", "pos", w.position)
	cf.save(WIN_CFG)

func _saved_window() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(WIN_CFG) != OK: return {}
	var s: Vector2i = cf.get_value("window", "size", Vector2i(1280, 720))
	var p: Vector2i = cf.get_value("window", "pos", Vector2i(-99999, -99999))
	s = Vector2i(clampi(s.x, 640, 7680), clampi(s.y, 360, 4320))
	var d := {"size": s}
	# Position nur übernehmen, wenn sie noch auf einem Bildschirm liegt
	for i in DisplayServer.get_screen_count():
		if Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i)).has_point(p + Vector2i(40, 20)):
			d["pos"] = p; break
	return d

func _restore_window() -> void:
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED: return
	var d := _saved_window()
	if d.has("size"): w.size = d["size"]
	if d.has("pos"): w.position = d["pos"]

# ---------- Programmdateien selbst aktualisieren (exe/DLL) ----------
## Die pck-Updates können die exe nicht ändern (z. B. das Symbol im Explorer). Steht in latest.json
## eine andere exe/DLL, lädt das Spiel im Hintergrund die Zip, prüft die Prüfsummen und tauscht die
## Dateien: die laufende Datei wird in *.old umbenannt (unter Windows erlaubt), die neue nimmt ihren
## Platz ein. Wirksam ab dem nächsten Start.
func _self_update(test_dir := "", test_url := "") -> void:
	var exe := OS.get_executable_path()
	var dir := test_dir if test_dir != "" else exe.get_base_dir()
	if test_dir == "" and (not OS.has_feature("template") or not OS.has_feature("windows")): return
	for f in DirAccess.get_files_at(dir):                  # Reste vom letzten Tausch aufräumen
		if f.ends_with(".old"): DirAccess.remove_absolute(dir.path_join(f))
	var url: String = test_url if test_url != "" else load("res://boot/boot.gd").UPDATE_URL
	var req := HTTPRequest.new(); req.timeout = 10; add_child(req)
	if req.request(url) != OK: req.queue_free(); return
	var res = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200: return
	var remote = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(remote) != TYPE_DICTIONARY or typeof(remote.get("files")) != TYPE_DICTIONARY: return
	var todo := {}
	for name in remote["files"]:
		var path := dir.path_join(name)
		if FileAccess.get_sha256(path).to_lower() != str(remote["files"][name]).to_lower(): todo[name] = remote["files"][name]
	if todo.is_empty(): return
	print("Programmdateien veraltet: ", todo.keys())
	var zip_path := "user://program_update.zip"
	var dl := HTTPRequest.new(); dl.timeout = 0; dl.download_file = zip_path; add_child(dl)
	if dl.request(str(remote.get("zip_url", ""))) != OK: dl.queue_free(); return
	res = await dl.request_completed
	dl.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200: return
	var zr := ZIPReader.new()
	if zr.open(ProjectSettings.globalize_path(zip_path)) != OK: return
	var done := []
	for name in todo:
		var data := zr.read_file(name)
		var hc := HashingContext.new(); hc.start(HashingContext.HASH_SHA256); hc.update(data)
		if hc.finish().hex_encode() != str(todo[name]).to_lower(): continue
		var path := dir.path_join(name)
		var f := FileAccess.open(path + ".new", FileAccess.WRITE)
		if f == null: continue
		f.store_buffer(data); f.close()
		DirAccess.remove_absolute(path + ".old")
		if DirAccess.rename_absolute(path, path + ".old") == OK and DirAccess.rename_absolute(path + ".new", path) == OK:
			done.append(name)
		else:
			DirAccess.rename_absolute(path + ".old", path)        # zurück, falls etwas schiefging
			DirAccess.remove_absolute(path + ".new")
	zr.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip_path))
	if not done.is_empty():
		print("Programmdateien aktualisiert: ", done)
		_post({"type": "toast", "text": "Program files updated – they take effect the next time you start the game."})

func _post(d: Dictionary) -> void:
	if test_posts != null: test_posts.append(d.duplicate(true)); return
	if wv != null: wv.call("post_message", JSON.stringify(d))

# ---------- Direktverbindung ----------
func _host() -> void:
	_leave()
	peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_GUESTS) != OK:
		peer = null; _post({"type": "net_err", "code": "port"}); return
	is_host = true
	peer.peer_connected.connect(func(_id): pass)
	peer.peer_disconnected.connect(func(id):
		if verified.has(id): verified.erase(id); _post({"type": "peer_left", "peer": "ip%d" % id}))
	_post({"type": "net_ok"})
	info["lan"] = _lan_ip()
	info["upnp"] = "Opening port %d via UPnP…" % PORT
	_post(info)
	if upnp_thread == null or not upnp_thread.is_alive():
		upnp_thread = Thread.new(); upnp_thread.start(_upnp_open)

func _join(addr: String) -> void:
	_leave()
	var host := addr.strip_edges()
	var port := PORT
	if host.begins_with("["):                               # [IPv6]:Port
		var e := host.find("]")
		if e > 0:
			if host.substr(e + 1).begins_with(":"): port = int(host.substr(e + 2))
			host = host.substr(1, e - 1)
	elif host.count(":") == 1:
		port = int(host.get_slice(":", 1)); host = host.get_slice(":", 0)
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(host, port) != OK:
		peer = null; _post({"type": "net_err", "code": "no_game"}); return
	is_host = false; joined = false
	var p := peer
	get_tree().create_timer(7.0).timeout.connect(func():   # niemand antwortet -> Fehler statt langem Warten
		if peer == p and not joined: _guest_lost())
	peer.peer_connected.connect(func(id):
		if id == 1: _raw(1, {"ctl": "ver", "v": version}))
	peer.peer_disconnected.connect(func(id):
		if id == 1: _guest_lost.call_deferred())      # nicht innerhalb von poll() schließen

func _guest_lost() -> void:                             # Gast: Verbindung zum Host weg (oder nie zustande gekommen)
	if peer == null: return                             # selbst getrennt
	if joined: _post({"type": "peer_left", "peer": "ip1"})
	else: _post({"type": "net_err", "code": "no_game"})
	_leave()

func _leave() -> void:
	if peer != null:
		var p := peer; peer = null; p.close()
	is_host = false; joined = false; verified.clear()

func _send(d: Dictionary) -> void:
	if peer == null: return
	if is_host:
		for id in verified: _raw(id, d)
	elif joined: _raw(1, d)

func _raw(id: int, d: Dictionary) -> void:
	peer.set_target_peer(id)
	peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	peer.put_packet(JSON.stringify(d).to_utf8_buffer())

func _process(_d: float) -> void:
	_tick_window_save(_d)
	if peer == null: return
	peer.poll()
	if peer != null and not is_host and peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_guest_lost(); return
	while peer != null and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var m = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if typeof(m) != TYPE_DICTIONARY: continue
		if m.has("ctl"): _control(from, m); continue
		if is_host and not verified.has(from): continue
		_post({"type": "net", "topic": m.get("topic"), "data": m.get("data"), "peer": "ip%d" % from})

func _control(from: int, m: Dictionary) -> void:
	match str(m["ctl"]):
		"ver":                                              # Host: Version des Gastes prüfen
			if not is_host: return
			if int(m.get("v", -1)) == version:
				verified[from] = true; _raw(from, {"ctl": "ok"})
			else:
				_raw(from, {"ctl": "reject", "v": version})   # der Gast trennt sich daraufhin selbst
		"ok":
			joined = true; _post({"type": "net_ok"})
		"reject":
			_post({"type": "net_err", "code": "version", "host": int(m.get("v", 0))})
			_leave()

# ---------- UPnP (im Hintergrund) ----------
func _upnp_open() -> void:
	var res := {}
	var u := UPNP.new()
	if u.discover(2000, 2) == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		var ext := u.query_external_address()
		if ext != "": res["ext"] = ext
		if u.add_port_mapping(PORT, PORT, "Into the Abyss", "UDP") == UPNP.UPNP_RESULT_SUCCESS:
			res["upnp"] = "Port %d opened automatically (UPnP) – friends over the internet can join." % PORT
			res["ok"] = true
		else: res["upnp"] = "UPnP failed – for internet play forward UDP port %d on your router." % PORT
	else: res["upnp"] = "No UPnP router found – for internet play forward UDP port %d on your router." % PORT
	call_deferred("_upnp_done", res, u)

func _upnp_done(res: Dictionary, u: UPNP) -> void:
	if res.get("ok", false): upnp = u
	info["upnp"] = res["upnp"]
	if res.has("ext"): info["ext"] = res["ext"]
	_post(info)

func _lan_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and not a.begins_with("172.17.")): return a
	return "127.0.0.1"

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_leave()
		if upnp != null: upnp.delete_port_mapping(PORT, "UDP"); upnp = null

func _exit_tree() -> void:
	if upnp_thread != null: upnp_thread.wait_to_finish()

static func _read_version() -> Dictionary:
	var f := FileAccess.open("res://version.json", FileAccess.READ)
	if f == null: return {"version": 0}
	var v = JSON.parse_string(f.get_as_text())
	return v if typeof(v) == TYPE_DICTIONARY else {"version": 0}
