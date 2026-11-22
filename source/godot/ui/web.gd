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
	print("WEB_READY version=", version)

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
		"fullscreen":
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		"quit": _leave(); get_tree().quit()
		"log": print("[page] ", m.get("text", ""))

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
