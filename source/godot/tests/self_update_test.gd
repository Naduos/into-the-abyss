## Test des Selbst-Updates der Programmdateien (ohne Windows): ein lokaler Server liefert latest.json + Zip.
## Aufruf: (Server auf Port 8765 mit latest.json) godot --headless --path . -s tests/self_update_test.gd -- <ordner>
extends SceneTree

func _init() -> void:
	await process_frame
	var dir: String = OS.get_cmdline_user_args()[0]
	var n: Node = load("res://ui/web.gd").new()
	n.test_posts = []
	root.add_child(n)
	await n._self_update(dir, "http://127.0.0.1:8765/latest.json")
	var exe := FileAccess.get_file_as_string(dir.path_join("IntoTheAbyss.exe"))
	var old_left := FileAccess.file_exists(dir.path_join("stale.old"))
	print("exe=", exe, " old_exe=", FileAccess.get_file_as_string(dir.path_join("IntoTheAbyss.exe.old")), " stale_removed=", not old_left, " posts=", n.test_posts)
	print("SELF_UPDATE_TEST ", "OK" if exe == "NEW-EXE-CONTENT" and not old_left and not FileAccess.file_exists(dir.path_join("godot_wry.dll.old")) else "FAIL")
	quit()
