## Test der Direktverbindung der exe ohne Browserfenster:
## Host + Gast (gleiche Version) tauschen Nachrichten aus, Gast mit falscher Version wird abgewiesen.
## Aufruf: godot --headless --path . -s tests/web_net_test.gd
extends SceneTree

var W = load("res://ui/web.gd")

func mk(ver_override := -1) -> Node:
	var n: Node = W.new()
	n.test_posts = []
	root.add_child(n)
	if ver_override >= 0: n.version = ver_override
	return n

func wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame

func types(n) -> Array: return n.test_posts.map(func(d): return d.get("type"))

func _init() -> void:
	await process_frame
	var ok := true
	var host := mk(); var guest := mk()
	host._on_ipc('{"cmd":"net_host"}')
	guest._on_ipc('{"cmd":"net_join","ip":"127.0.0.1"}')
	await wait(2.0)
	print("host: ", types(host)); print("guest: ", types(guest))
	ok = ok and types(host).has("net_ok") and types(guest).has("net_ok")
	host._on_ipc('{"cmd":"net_send","topic":"lobby","data":{"assign":{"knight":"g1"}}}')
	guest._on_ipc('{"cmd":"net_send","topic":"hello","data":{"me":"abc"}}')
	await wait(1.0)
	var gnet = guest.test_posts.filter(func(d): return d.get("type") == "net")
	var hnet = host.test_posts.filter(func(d): return d.get("type") == "net")
	print("guest got: ", gnet); print("host got: ", hnet)
	ok = ok and gnet.size() == 1 and gnet[0]["topic"] == "lobby" and gnet[0]["data"]["assign"]["knight"] == "g1"
	ok = ok and hnet.size() == 1 and hnet[0]["topic"] == "hello" and str(hnet[0]["peer"]).begins_with("ip")
	# falsche Version
	var bad := mk(999)
	bad._on_ipc('{"cmd":"net_join","ip":"127.0.0.1"}')
	await wait(2.0)
	var err = bad.test_posts.filter(func(d): return d.get("type") == "net_err")
	print("bad: ", bad.test_posts)
	ok = ok and err.size() == 1 and err[0]["code"] == "version" and int(err[0]["host"]) == host.version
	# Gast verlässt -> Host bekommt peer_left
	guest._on_ipc('{"cmd":"net_leave"}')
	await wait(1.5)
	var left = host.test_posts.filter(func(d): return d.get("type") == "peer_left")
	print("host peer_left: ", left)
	ok = ok and left.size() == 1 and left[0]["peer"] == hnet[0]["peer"]
	# Host weg -> Gast bekommt peer_left ip1
	var g2 := mk(); g2._on_ipc('{"cmd":"net_join","ip":"127.0.0.1:24565"}')
	await wait(1.5)
	host._on_ipc('{"cmd":"net_leave"}')
	await wait(1.5)
	print("g2: ", types(g2))
	ok = ok and types(g2).has("net_ok") and g2.test_posts.any(func(d): return d.get("type") == "peer_left" and d.get("peer") == "ip1")
	# niemand da -> Fehler
	var g3 := mk(); g3._on_ipc('{"cmd":"net_join","ip":"127.0.0.1"}')
	await wait(8.0)
	print("g3: ", g3.test_posts)
	ok = ok and g3.test_posts.size() == 1 and g3.test_posts[0]["code"] == "no_game"
	print("WEB_NET_TEST ", "OK" if ok else "FAIL")
	quit()
