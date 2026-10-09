extends Node

## Headless check of the offline save import: file guards, the EPOCH prefix, a synthetic character save
## (tests/fixtures/save_synthetic.json: old and new item blobs, unknown ids, truncated and legacy items), applying it to
## Build and the "Save file" panel. At the end a read-only smoke pass over the local game saves (printed, not asserted).
## Run: Godot_console.exe --headless --path client res://tests/save_import_test.tscn

const FIXTURE: String = "res://tests/fixtures/save_synthetic.json"
const PanelScene: PackedScene = preload("res://scenes/import/save_import_panel.tscn")

var _failed: int = 0


func _ready() -> void:
	# a script error stops this coroutine; never hang the headless run
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("SAVE IMPORT TEST: TIMEOUT")
		get_tree().quit(1))
	TranslationServer.set_locale("en")  # the checks look at English texts
	_guards()
	var parsed: Dictionary = _synthetic()
	_apply(parsed)
	_panel()
	_local_smoke()
	print("SAVE IMPORT TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, got: Variant, want: Variant) -> void:
	if str(got) != str(want):
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


## "EPOCH" + the JSON text, as the game writes it.
func _file(text: String) -> PackedByteArray:
	return ("EPOCH" + text).to_utf8_buffer()


func _fixture_text() -> String:
	return FileAccess.get_file_as_string(FIXTURE)


func _guards() -> void:
	_check("empty file", SaveImport.parse(PackedByteArray())["ok"], false)
	_check("JSON without EPOCH", SaveImport.parse(_fixture_text().to_utf8_buffer())["error"].contains("EPOCH prefix"), true)
	_check("text without EPOCH", SaveImport.parse("hello".to_utf8_buffer())["error"].contains("does not start with EPOCH"), true)
	_check("BOM only", SaveImport.parse(PackedByteArray([0xEF, 0xBB, 0xBF]))["ok"], false)
	_check("corrupt JSON", SaveImport.parse(_file(_fixture_text().substr(0, 400)))["error"].contains("damaged"), true)
	_check("EPOCH alone", SaveImport.parse("EPOCH".to_utf8_buffer())["ok"], false)
	_check("stash file (no character)", SaveImport.parse(_file("{\"stashTabs\":[],\"cycle\":2}"))["error"].contains("holds no character"), true)
	_check("JSON array", SaveImport.parse(_file("[1,2,3]"))["ok"], false)
	_check("unknown class", SaveImport.parse(_file("{\"characterClass\":77}"))["ok"], false)
	var huge := PackedByteArray()
	huge.resize(SaveImport.MAX_BYTES + 1)
	_check("too big", SaveImport.parse(huge)["error"].contains("too big"), true)
	var bom: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF]) + _file(_fixture_text())
	_check("UTF-8 BOM before EPOCH accepted", SaveImport.parse(bom)["ok"], true)


func _synthetic() -> Dictionary:
	var parsed: Dictionary = SaveImport.parse(_file(_fixture_text()))
	_check("synthetic ok", [parsed["ok"], parsed["error"]], [true, ""])
	var s: Dictionary = parsed["summary"]
	_check("summary", [s["name"], s["class_id"], s["class_name"], s["mastery"], s["mastery_name"], s["level"]], ["Synthetic Tester", 3, "Acolyte", 1, "Necromancer", 60])
	_check("summary passive points", s["passive_points"], 8 + 5 + 8 + 1 + 6 + 8)
	var doc: Dictionary = parsed["build"]
	print("warnings:")
	for w: String in parsed["warnings"]:
		print("  - " + w)
	_check("skills", doc["skills"].map(func(k: Dictionary) -> String: return k["ability"]).slice(0, 3), ["ss37kl", "ds4d3", ""])
	_check("skill 0 tree nodes", doc["skills"][0]["tree"].size(), 3)
	_check("skill 1 unknown node skipped", doc["skills"][1]["tree"].size(), 2)
	var items: Dictionary = doc["items"]
	var helmet: Array = items["helmet"]["affixes"].map(func(a: Dictionary) -> Array: return [a["id"], a["tier"], a["roll"]])
	helmet.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	_check("helmet", [items["helmet"]["base"], items["helmet"]["sub"], items["helmet"]["implicit_rolls"], helmet], [0, 61, [142, 167, 55], [[90, 6, 140], [765, 6, 232], [802, 5, 212]]])
	_check("body: unknown affix skipped, known kept", items["body"]["affixes"].map(func(a: Dictionary) -> int: return a["id"]), [90])
	_check("gloves from a version 2 blob", [items["gloves"]["base"], items["gloves"]["sub"], items["gloves"]["affixes"].size()], [4, 1, 4])
	_check("weapon: set item 79", [items["weapon"]["unique"], items["weapon"]["unique_rolls"].size()], [79, 8])
	_check("unknown unique skipped", items.has("boots"), false)
	_check("truncated item skipped", items.has("belt"), false)
	_check("legacy item without data skipped", items.has("amulet"), false)
	_check("stash container ignored", items.size(), 4)
	var text: String = "\n".join(PackedStringArray(parsed["warnings"]))
	_check("warning: unknown affix", text.contains("4095"), true)
	_check("warning: unknown unique", text.contains("65000"), true)
	_check("warnings (node, affix, unique, belt, amulet)", parsed["warnings"].size(), 5)
	return parsed


func _apply(parsed: Dictionary) -> void:
	SaveImport.apply(Build, parsed)
	_check("Build class/mastery/level", [Build.class_id, Build.mastery, Build.level], [3, 1, 60])
	_check("Build.spent_points", Build.spent_points(), 36)
	_check("Build.items", Build.items.keys().size(), 4)
	_check("Build skills", [Build.skills[0]["ability"], Build.skills[1]["ability"], Build.skills[2]["ability"]], ["ss37kl", "ds4d3", ""])
	Build.selected_skill = 0
	var r: Dictionary = SkillCalc.compute(Build, 0)
	_check("SkillCalc runs on the imported build", r["title"] != "" and r["sections"].size() > 0, true)
	var before: String = JSON.stringify(Build.passives)
	SaveImport.apply(Build, {"ok": false})
	_check("apply of a failed parse keeps the build", JSON.stringify(Build.passives), before)


func _panel() -> void:
	var panel: SaveImportPanel = PanelScene.instantiate()
	add_child(panel)
	var imports: Array = [0]
	panel.imported.connect(func() -> void: imports[0] += 1)
	var import_button: Button = panel.get_node("%ImportButton")
	_check("panel: Import disabled at first", import_button.disabled, true)
	panel._load_bytes("nope".to_utf8_buffer(), "x.txt")
	_check("panel: error shown, Import disabled", [import_button.disabled, panel.get_node("%StatusLabel").text.contains("EPOCH")], [true, true])
	Build.set_class(0)
	panel._load_bytes(_file(_fixture_text()), "1CHARACTERSLOT_BETA_0")
	_check("panel: summary", panel.get_node("%SummaryLabel").text, "Synthetic Tester — Acolyte, Necromancer, level 60")
	_check("panel: Import enabled, build untouched until pressed", [import_button.disabled, Build.class_id], [false, 0])
	import_button.pressed.emit()
	_check("panel: imported", [imports[0], Build.class_id, Build.level], [1, 3, 60])
	_check("panel: warnings listed", panel.get_node("%StatusLabel").text.contains("(5)"), true)
	panel.queue_free()


## Read-only pass over the game's own saves on this machine (nothing is written, the character name is not printed).
func _local_smoke() -> void:
	var dir: String = SaveImport.saves_dir()
	if dir == "":
		print("local smoke: no game Saves folder here")
		return
	for file_name: String in DirAccess.get_files_at(dir):
		if not file_name.contains("CHARACTERSLOT"):
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(dir.path_join(file_name))
		var parsed: Dictionary = SaveImport.parse(bytes)
		if not parsed["ok"]:
			print("local smoke %s: FAILED %s" % [file_name, parsed["error"]])
			continue
		var s: Dictionary = parsed["summary"]
		print("local smoke %s: %s / %s, level %d, passive points %d, items %d, warnings %d" % [file_name, s["class_name"], s["mastery_name"], s["level"], s["passive_points"], s["items"], parsed["warnings"].size()])
		for w: String in parsed["warnings"]:
			print("    - " + w)
