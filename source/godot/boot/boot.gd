## =====================================================================
##   AUTO-UPDATE (Startszene)
##   1. Lädt ein bereits heruntergeladenes Update (user://update.pck).
##   2. Fragt UPDATE_URL nach latest.json und lädt eine neuere game.pck.
##   3. Prüft die SHA-256-Prüfsumme, aktiviert das Update, startet das Spiel.
##   Offline / Fehler -> das Spiel startet einfach mit der vorhandenen Version.
##   WICHTIG: Dieses Skript darf die Klasse "Game" nicht direkt verwenden,
##   sonst würde die alte Engine geladen, bevor das Update aktiv ist.
## =====================================================================
extends Control

## Wird von tools/release.sh automatisch eingetragen (GitHub: <besitzer>/<repo>).
const UPDATE_URL := "https://raw.githubusercontent.com/Naduos/into-the-abyss/main/updates/latest.json"
const PATCH := "user://update.pck"
const PATCH_TMP := "user://update_download.pck"
const PATCH_INFO := "user://update.json"                # Version des heruntergeladenen Updates
const MAIN_SCENE := "res://ui/web.tscn"
## Kennung der Programmdatei: ändert sich nur, wenn eine neue exe nötig ist (z. B. neue DLL).
const APP_ENGINE := "4.4.1-wry1"
const TIMEOUT := 8.0

var label: Label
var bar: ProgressBar
var http: HTTPRequest

func _ready() -> void:
	_build_ui()
	var base := int(read_version().get("version", 0))
	if FileAccess.file_exists(PATCH):
		# ein altes Update darf eine neuer heruntergeladene Vollversion nicht überschreiben
		if _patch_version() <= base or not ProjectSettings.load_resource_pack(PATCH, true): _drop_patch()
	var url := UPDATE_URL
	for a in OS.get_cmdline_user_args():                # nur für Tests: --update-url=… / --quit
		if a.begins_with("--update-url="): url = a.substr(13)
	var local := read_version()
	_say("Version %s – suche nach Updates…" % vlabel(local))
	if url.contains("OWNER"):
		start_game(); return
	var remote = await fetch_json(url)
	if remote == null or int(remote.get("version", 0)) <= int(local.get("version", 0)):
		start_game(); return
	if remote.has("engine") and remote["engine"] != APP_ENGINE:
		_say("Version %s ist da, braucht aber eine neue Programmdatei.\nBitte das komplette Spiel neu herunterladen:\n%s" % [vlabel(remote), remote.get("full_url", "")])
		await get_tree().create_timer(6.0).timeout
		start_game(); return
	_say("Lade Update auf Version %s…" % vlabel(remote))
	if await download(remote["pck_url"], PATCH_TMP) and _sha_ok(PATCH_TMP, remote.get("sha256", "")):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(PATCH_TMP), ProjectSettings.globalize_path(PATCH))
		ProjectSettings.load_resource_pack(PATCH, true)
		var f := FileAccess.open(PATCH_INFO, FileAccess.WRITE); f.store_string(JSON.stringify({"version": int(remote["version"])})); f.close()
		_say("Update auf Version %s installiert." % vlabel(remote))
	else:
		_say("Update fehlgeschlagen – starte mit der bisherigen Version.")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATCH_TMP))
	await get_tree().create_timer(0.6).timeout
	start_game()

func _patch_version() -> int:
	var f := FileAccess.open(PATCH_INFO, FileAccess.READ)
	if f == null: return 0
	var v = JSON.parse_string(f.get_as_text())
	return int(v.get("version", 0)) if typeof(v) == TYPE_DICTIONARY else 0

func _drop_patch() -> void:
	for p in [PATCH, PATCH_INFO]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

static func vlabel(v: Dictionary) -> String:
	# Anzeige-Version (z. B. „0.5“); intern zählt weiter die ganze Zahl „version“ für die Updates
	return str(v.get("label", int(v.get("version", 0))))

static func read_version() -> Dictionary:
	var f := FileAccess.open("res://version.json", FileAccess.READ)
	if f == null: return {"version": 0}
	var v = JSON.parse_string(f.get_as_text())
	return v if typeof(v) == TYPE_DICTIONARY else {"version": 0}

func fetch_json(url: String):
	var req := _request()
	if req.request(url) != OK: return null
	var res = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200: return null
	var v = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return v if typeof(v) == TYPE_DICTIONARY else null

func download(url: String, path: String) -> bool:
	var req := _request()
	req.timeout = 0                                   # große Datei: kein Gesamt-Timeout
	req.download_file = path
	if req.request(url) != OK: return false
	var state := {"done": false, "code": 0}           # Dictionary, weil Lambdas lokale Variablen nur kopieren
	req.request_completed.connect(func(res, code, _h, _b): state.done = true; state.code = code if res == HTTPRequest.RESULT_SUCCESS else -1)
	while not state.done:
		var total := req.get_body_size()
		if total > 0: bar.value = 100.0 * req.get_downloaded_bytes() / total
		await get_tree().process_frame
	var ok: bool = state.code == 200 and FileAccess.file_exists(path)
	req.queue_free()
	return ok

func _request() -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	req.max_redirects = 10                            # GitHub leitet "latest/download" weiter
	add_child(req)
	return req

func _sha_ok(path: String, want: String) -> bool:
	if want == "": return true
	return FileAccess.get_sha256(path).to_lower() == want.to_lower()

func start_game() -> void:
	if OS.get_cmdline_user_args().has("--quit"): print("BOOT_DONE version=", int(read_version().get("version", 0))); get_tree().quit(); return
	if ResourceLoader.exists(MAIN_SCENE): get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
	else: _say("Into the Abyss – Version %s\n(Die Spieloberfläche folgt in Phase 2.)" % vlabel(read_version()))

func _build_ui() -> void:
	var bg := ColorRect.new(); bg.color = Color(0.04, 0.03, 0.07); bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	label = Label.new(); label.set_anchors_preset(Control.PRESET_CENTER); label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH; label.grow_vertical = Control.GROW_DIRECTION_BOTH; add_child(label)
	bar = ProgressBar.new(); bar.custom_minimum_size = Vector2(420, 18); bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position.y -= 80; bar.position.x -= 210; add_child(bar)

func _say(t: String) -> void:
	label.text = t; print(t)
