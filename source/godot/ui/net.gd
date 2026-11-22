## =====================================================================
##   KOOP ÜBERS NETZ (Lockstep wie in der HTML-Version)
##   Host: führt jede Aktion aus und schickt sie in derselben Reihenfolge an alle.
##   Gast: schickt nur Anfragen an den Host und führt aus, was zurückkommt.
##   Alle Geräte rechnen mit demselben Seed -> identischer Spielverlauf.
##   UPnP öffnet den Port am Router automatisch (wenn der Router es erlaubt).
## =====================================================================
extends Node

signal lobby_changed
signal closed(reason: String)

const PORT := 24565
const MAX_GUESTS := 3

var g                                   # Game
var is_host := false
var my_slot := "host"                   # host / g1 / g2 / g3
var slots := {}                         # peer_id -> slot (nur beim Host vollständig)
var names := {"host": "Host"}           # slot -> Anzeigename
var lobby := {}                         # Stand der Lobby (Gruppe, Rollen) – vom Host verteilt
var upnp_info := ""
var connected := false
var _upnp: UPNP

func host(game) -> String:
	g = game
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, MAX_GUESTS)
	if err != OK: return "Could not open port %d (error %d)." % [PORT, err]
	multiplayer.multiplayer_peer = p
	is_host = true; my_slot = "host"; connected = true
	g.net = self; g.my_role = "host"
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	lobby = {"party": ["knight", "mage"], "roles": {"knight": "host", "mage": "host"}}
	upnp_info = "Opening port via UPnP…"
	var t := Thread.new(); t.start(_upnp_open)
	return ""

func join(game, ip: String) -> String:
	g = game
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip.strip_edges(), PORT)
	if err != OK: return "Could not connect (error %d)." % err
	multiplayer.multiplayer_peer = p
	is_host = false
	multiplayer.connected_to_server.connect(func(): connected = true; _hello.rpc_id(1, g.game_version()))
	multiplayer.connection_failed.connect(func(): closed.emit("Connection failed. Check the IP address and that the host's port %d is open." % PORT))
	multiplayer.server_disconnected.connect(func(): closed.emit("The host closed the game."))
	g.net = self
	return ""

func leave() -> void:
	if _upnp != null: _upnp.delete_port_mapping(PORT, "UDP")
	if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	connected = false; is_host = false; slots.clear()
	if g != null: g.net = null; g.my_role = "host"

# ---------- UPnP (im Hintergrund, damit nichts einfriert) ----------
func _upnp_open() -> void:
	var u := UPNP.new()
	var res := u.discover(2000, 2)
	var txt := ""
	if res == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		var r1 := u.add_port_mapping(PORT, PORT, "Into the Abyss", "UDP")
		var ext := u.query_external_address()
		if r1 == UPNP.UPNP_RESULT_SUCCESS:
			txt = "Friends over the internet join with: %s" % ext
			_upnp = u
		else: txt = "UPnP failed – forward UDP port %d on your router (internet IP: %s)." % [PORT, ext]
	else: txt = "No UPnP router found – forward UDP port %d manually for internet play." % PORT
	var lan := ""
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and not a.begins_with("172.17.")): lan = a; break
	if lan != "": txt += "\nSame network (LAN): %s" % lan
	call_deferred("_set_upnp", txt)

func _set_upnp(t: String) -> void:
	upnp_info = t; lobby_changed.emit()

# ---------- Lobby ----------
func _on_peer_joined(id: int) -> void:
	pass                                   # erst nach "hello" (Versionsprüfung) zählt der Gast

func _on_peer_left(id: int) -> void:
	if not slots.has(id): return
	var s: String = slots[id]; slots.erase(id); names.erase(s)
	for h in lobby["roles"]:
		if lobby["roles"][h] == s: lobby["roles"][h] = "host"
	if g.S.get("runActive", false):                # mitten im Lauf: Helden übernimmt der Host
		for h in g.S["roles"]:
			if g.S["roles"][h] == s: g.S["roles"][h] = "host"
	push_lobby()
	g.toast("A player left – the host takes over their heroes.")

@rpc("any_peer", "reliable")
func _hello(version: int) -> void:
	if not is_host: return
	var id := multiplayer.get_remote_sender_id()
	var msg: String = g.version_mismatch_text(version)
	if msg != "":
		_rejected.rpc_id(id, "Version mismatch: host has %d, you have %d. Restart the game to update." % [g.game_version(), version]); return
	if g.S.get("runActive", false):
		_rejected.rpc_id(id, "The run has already started."); return
	var free := ["g1", "g2", "g3"].filter(func(s): return not slots.values().has(s))
	if free.is_empty(): _rejected.rpc_id(id, "The lobby is full."); return
	slots[id] = free[0]; names[free[0]] = "Player %s" % free[0].substr(1)
	_welcome.rpc_id(id, free[0])
	push_lobby()

@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	closed.emit(reason)

@rpc("authority", "reliable")
func _welcome(slot: String) -> void:
	my_slot = slot; g.my_role = slot; lobby_changed.emit()

func push_lobby() -> void:
	if not is_host: return
	_lobby_state.rpc(JSON.stringify({"lobby": lobby, "names": names}))
	lobby_changed.emit()

@rpc("authority", "reliable")
func _lobby_state(js: String) -> void:
	var d = JSON.parse_string(js)
	lobby = d["lobby"]; names = d["names"]; lobby_changed.emit()

func players() -> Array:
	var out := ["host"]
	for id in slots: out.append(slots[id])
	out.sort()
	return out

# ---------- Lockstep (vom Spiel aufgerufen: g.dispatch -> host_commit / send_request) ----------
func host_commit(a: Dictionary) -> void:
	_exec.rpc(JSON.stringify(a))
	g.enqueue(a)

func send_request(a: Dictionary) -> void:
	_request.rpc_id(1, JSON.stringify(a))

@rpc("any_peer", "reliable")
func _request(js: String) -> void:
	if not is_host: return
	var a = JSON.parse_string(js)
	if typeof(a) != TYPE_DICTIONARY: return
	a = JS.normalize(a)
	var slot: String = slots.get(multiplayer.get_remote_sender_id(), "")
	var h = a.get("h")
	# Gäste dürfen nur für eigene Helden handeln (Start/Lobby nur der Host)
	if a.get("t") in ["start", "tolobby"]: return
	if h != null and g.S.get("roles", {}).has(h) and g.S["roles"][h] != slot and a.get("t") not in ["room", "ev", "biomego"]: return
	host_commit(a)

@rpc("authority", "reliable")
func _exec(js: String) -> void:
	var a = JS.normalize(JSON.parse_string(js))
	g.S["waiting"] = false
	g.enqueue(a)
