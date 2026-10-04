extends Node

## Headless check of the Last Epoch Tools import: LZString, id decoding, link / hash parsing, conversion of the
## saved sample response and applying it to Build.
## Run: Godot_console.exe --headless --path client res://tests/letools_import_test.tscn

const LZStringScript: GDScript = preload("res://scripts/engine/lz_string.gd")
const ImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")
const FIXTURE: String = "res://tests/fixtures/letools_A83KxJq5.json"

var _failed: int = 0


func _ready() -> void:
	# a script error stops this coroutine; never hang the headless run
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("LETOOLS IMPORT TEST: TIMEOUT")
		get_tree().quit(1))
	_lz_string()
	_decode_ids()
	_urls()
	_hash()
	var doc: Dictionary = _convert()
	_apply(doc)
	_bad_input()
	_altar_idols()
	await _main_ui()
	print("LETOOLS IMPORT TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, got: Variant, want: Variant) -> void:
	if str(got) != str(want):
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


func _lz_string() -> void:
	_check("lz IwBjINgZnI", LZStringScript.decompress_from_encoded_uri("IwBjINgZnI"), "1000063000")
	_check("lz AzDMwFmI", LZStringScript.decompress_from_encoded_uri("AzDMwFmI"), "003040")
	_check("lz KwBmQ", LZStringScript.decompress_from_encoded_uri("KwBmQ"), "505")
	_check("lz space as plus", LZStringScript.decompress_from_encoded_uri("KwBmQ "), LZStringScript.decompress_from_encoded_uri("KwBmQ+"))
	_check("lz empty", LZStringScript.decompress_from_encoded_uri(""), "")
	_check("lz bad char", LZStringScript.decompress_from_encoded_uri("!!"), "")


func _decode_ids() -> void:
	var cases: Dictionary = {
		"IIwBjINgZnI": {"kind": "I", "base": 0, "sub": 63},
		"IIwBhoNgJjEg": {"kind": "I", "base": 1, "sub": 62},
		"UAzDMwFmI": {"kind": "U", "sub": 3, "unique": 40},
		"UAzCMCYE4GYg": {"kind": "U", "sub": 1, "unique": 293},
		"IIwBhCYwNjEg": {"kind": "I", "base": 2, "sub": 6},
		"IIwBhGYwVjEg": {"kind": "I", "base": 3, "sub": 5},
		"IIwBgTKJVQ": {"kind": "I", "base": 21, "sub": 0},
		"UAzAsCYE5SA": {"kind": "U", "sub": 4, "unique": 294},
		"IIwBgTCmpQ": {"kind": "I", "base": 20, "sub": 1},
		"IIwBgTGLAzCdA": {"kind": "I", "base": 22, "sub": 13},
		"IIwBgzATC7SQ": {"kind": "I", "base": 32, "sub": 3},
		"AKwBmQ": {"kind": "A", "affix": 505},
		"AIwBgTAHEA": {"kind": "A", "affix": 1028},
	}
	for id: String in cases:
		var got: Dictionary = ImportScript.decode_id(id)
		for key: String in cases[id]:
			_check("decode %s.%s" % [id, key], got.get(key, "<missing>"), cases[id][key])
	_check("decode garbage", ImportScript.decode_id("Zzz"), {})
	_check("decode empty", ImportScript.decode_id(""), {})


func _urls() -> void:
	var want: String = "https://www.lastepochtools.com/planner/A83KxJq5"
	for input: String in [
		"https://www.lastepochtools.com/planner/A83KxJq5",
		"https://www.lastepochtools.com/planner/A83KxJq5/",
		"http://lastepochtools.com/planner/A83KxJq5?x=1#top",
		"www.lastepochtools.com/planner/A83KxJq5",
		"lastepochtools.com/planner/A83KxJq5",
		"  https://WWW.LastEpochTools.com/planner/A83KxJq5  ",
		"A83KxJq5",
	]:
		_check("planner_url '%s'" % input, ImportScript.planner_url(input), want)
	for bad: String in ["", "https://example.com/planner/A83KxJq5", "https://evil.com/lastepochtools.com/planner/A83KxJq5",
			"https://www.lastepochtools.com/", "a b", "https://www.lastepochtools.com/planner/"]:
		_check("planner_url rejects '%s'" % bad, ImportScript.planner_url(bad), "")


func _hash() -> void:
	var html: String = "<html><script>var jsj34pii='c77046754682dc2a3c6dd8e3aa5551b0';\nfunction f(){ fetch('/api/internal/planner_data/' + jsj34pii).then(r => r.json()); }</script></html>"
	_check("hash", ImportScript.extract_data_hash(html), "c77046754682dc2a3c6dd8e3aa5551b0")
	var dollar: String = "a='11111111111111111111111111111111'; $h='deadbeef'; fetch('/api/internal/planner_data/' + $h)"
	_check("hash with $ variable", ImportScript.extract_data_hash(dollar), "deadbeef")
	_check("hash fallback", ImportScript.extract_data_hash("zz='0123456789abcdef0123456789abcdef'"), "0123456789abcdef0123456789abcdef")
	_check("hash missing", ImportScript.extract_data_hash("<html></html>"), "")


func _load_fixture() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not parsed is Dictionary:
		_failed += 1
		print("FAIL fixture not loaded")
		return {}
	return parsed


func _convert() -> Dictionary:
	var response: Dictionary = _load_fixture()
	var doc: Dictionary = ImportScript.to_build(response)
	_check("class", doc["class_id"], 3)
	_check("mastery", doc["mastery"], 2)
	_check("level", doc["level"], 58)
	var passive_sum: int = 0
	for points: Variant in doc["passives"].values():
		passive_sum += int(points)
	_check("passive points", passive_sum, 71)

	var abilities: Array = []
	var tree_sums: Array = []
	for skill: Dictionary in doc["skills"]:
		abilities.append(skill["ability"])
		var sum: int = 0
		for points: Variant in skill["tree"].values():
			sum += int(points)
		tree_sums.append(sum)
	_check("skills count", doc["skills"].size(), 5)
	_check("abilities", abilities, ["bc53", "rf1azz", "sp5g2", "ts50pl", "ha84"])
	_check("tree sums", tree_sums, [17, 17, 14, 17, 18])
	_check("ha84 level capped to 20", doc["skills"][4]["level"], 20)

	var items: Dictionary = doc["items"]
	var equipment: Array = []
	var idols: int = 0
	for slot: String in items:
		if IdolGrid.is_idol_key(slot):
			idols += 1
		else:
			equipment.append(slot)
	equipment.sort()
	_check("equipment slots", equipment, ["amulet", "belt", "body", "boots", "gloves", "helmet", "relic", "ring1", "ring2", "weapon"])
	_check("idols", idols, 11)
	_check("weapon unique", items["weapon"].get("unique"), 40)
	_check("weapon base from unique", items["weapon"]["base"], int(GameData.unique(40)["baseType"]))
	_check("weapon sub", items["weapon"]["sub"], 3)
	_check("weapon unique rolls", items["weapon"]["unique_rolls"], [188, 30, 25, 128, 175, 123, 84, 148])
	_check("helmet base/sub", [items["helmet"]["base"], items["helmet"]["sub"]], [0, 63])
	_check("helmet implicit rolls", items["helmet"]["implicit_rolls"], [154, 78, 90])
	_check("helmet affixes = 4 + sealed", items["helmet"]["affixes"].size(), 5)
	_check("helmet first affix", items["helmet"]["affixes"][0], {"id": 505, "tier": 6, "roll": 68})
	_check("ring1 corrupted affix appended", items["ring1"]["affixes"].back()["id"], 1028)
	_check("ring1 affix count", items["ring1"]["affixes"].size(), 5)
	var idol: Dictionary = items[IdolGrid.key(0, 3)]
	_check("idol (x4,y1) base/sub", [idol["base"], idol["sub"]], [32, 3])
	_check("idol (x4,y1) corrupted", idol.get("corrupted", false), true)
	var idol_affixes: Array = []
	for affix: Dictionary in idol["affixes"]:
		idol_affixes.append(affix["id"])
	_check("idol (x4,y1) affixes", idol_affixes, [134, 297, 1035])
	_check("idol without corruption", items[IdolGrid.key(4, 2)].get("corrupted", false), false)

	var missing: int = 0
	for slot: String in items:
		for affix: Dictionary in items[slot]["affixes"]:
			if GameData.affix(int(affix["id"])).is_empty():
				missing += 1
	_check("every affix exists in GameData", missing, 0)

	_check("no blessings", doc["blessings"].size(), 0)
	print("warnings (%d):" % doc["warnings"].size())
	for w: String in doc["warnings"]:
		print("  - " + w)

	# the inner data alone is accepted too
	var inner: Dictionary = ImportScript.to_build(response["data"])
	_check("inner data: class/level", [inner["class_id"], inner["level"]], [3, 58])
	return doc


func _apply(doc: Dictionary) -> void:
	var changes: Array[int] = [0]
	var counter: Callable = func() -> void: changes[0] += 1
	Build.changed.connect(counter)
	ImportScript.apply(Build, doc)
	Build.changed.disconnect(counter)
	print("Build.changed emitted %d times" % changes[0])

	_check("Build.class_id", Build.class_id, 3)
	_check("Build.mastery", Build.mastery, 2)
	_check("Build.level", Build.level, 58)
	_check("Build.spent_points", Build.spent_points(), 71)
	_check("Build.skills[0]", Build.skills[0]["ability"], "bc53")
	_check("Build.skill_points_spent(4)", Build.skill_points_spent(4), 18)
	_check("Build.items size", Build.items.size(), 21)

	var g: Dictionary = BuildMods.global_store(Build)
	var store: StatStore = g["store"]
	_check("global_store has mods", store.all_mods().size() > 0, true)
	for slot: int in range(5):
		Build.selected_skill = slot
		var r: Dictionary = SkillCalc.compute(Build, slot)
		_check("SkillCalc slot %d title" % slot, r["title"] != "", true)
		_check("SkillCalc slot %d sections" % slot, r["sections"].size() > 0, true)
		if slot == 4:
			# Harvest bleeds: its «Айлмент: Bleed» section has its own «DPS по врагу»; the headline must be the total
			var total: Dictionary = CalcSummary.find_row(r, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION)
			var hit_dps: Dictionary = CalcSummary.find_row(r, "DPS удара по врагу", CalcSummary.ENEMY_SECTION)
			_check("Harvest headline DPS > hit DPS", float(total.get("text", "0")) > float(hit_dps.get("text", "0")), true)
			_check("Harvest headline DPS > 11000", float(total.get("text", "0")) > 11000.0, true)
		if slot == 0:
			print("--- %s" % r["title"])
			for section: Dictionary in r["sections"]:
				print("  [%s]" % section["title"])
				for row: Dictionary in section["rows"]:
					print("    %s: %s" % [row["label"], row["text"]])


## Build ApbrXYvx (tests/fixtures): altar subtype 4 with 12 idols. unlockMatrix is [x][y]; read as [row][col] the grid was
## transposed and 5 idols did not fit. Refracted cells of this altar are (row 3, col 2) and (row 3, col 4) as in the game.
func _altar_idols() -> void:
	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/letools_ApbrXYvx.json")
	var doc: Dictionary = ImportScript.to_build(JSON.parse_string(text))
	var idol_warnings: Array = doc["warnings"].filter(func(w: String) -> bool: return w.begins_with("Идол"))
	_check("ApbrXYvx idol warnings", idol_warnings, [])
	var idols: int = 0
	for slot: String in doc["items"]:
		if IdolGrid.is_idol_key(slot):
			idols += 1
	_check("ApbrXYvx idols placed", idols, 12)
	_check("ApbrXYvx altar subtype", int(doc["items"].get(IdolGrid.ALTAR_SLOT, {}).get("sub", -1)), 4)
	_check("ApbrXYvx refracted (3,2)", IdolGrid.is_refracted(2, 1, doc["items"]), true)
	_check("ApbrXYvx refracted (3,4)", IdolGrid.is_refracted(2, 3, doc["items"]), true)
	_check("ApbrXYvx blocked (1,3)", IdolGrid.is_open(0, 2, doc["items"]), false)
	_check("ApbrXYvx open (1,5)", IdolGrid.is_open(0, 4, doc["items"]), true)


func _bad_input() -> void:
	var bad: Dictionary = ImportScript.to_build({})
	_check("empty response: class -1", bad["class_id"], -1)
	_check("empty response: warning", bad["warnings"].size() > 0, true)
	var response: Dictionary = _load_fixture()
	var broken: Dictionary = response["data"].duplicate(true)
	broken["bio"]["characterClass"] = 99
	_check("unknown class", ImportScript.to_build(broken)["class_id"], -1)
	broken = response["data"].duplicate(true)
	broken["equipment"]["head"]["id"] = "Inonsense"
	broken["hud"][0] = "zz_unknown"
	broken["charTree"]["selected"]["99999"] = 3
	broken["idols"][1]["x"] = 4
	broken["idols"][1]["y"] = 1
	var doc: Dictionary = ImportScript.to_build(broken)
	_check("broken: helmet skipped", doc["items"].has("helmet"), false)
	_check("broken: skill 1 skipped", doc["skills"][0]["ability"], "")
	_check("broken: unknown passive skipped", doc["passives"].has(99999), false)
	_check("broken: overlapping idol skipped", doc["items"].size(), 19)
	_check("broken: warnings", doc["warnings"].size() >= 4, true)
	for w: String in doc["warnings"]:
		print("  - " + w)


## Main scene: the «Импорт…» button opens the dialog, a pasted JSON replaces the build and the top bar follows it.
func _main_ui() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var dialog: Window = main.get_node("%ImportDialog")
	var button: Button = main.get_node("%ImportButton")
	_check("import dialog hidden at start", dialog.visible, false)
	button.pressed.emit()
	await get_tree().process_frame
	_check("import button opens the dialog", dialog.visible, true)

	dialog.get_node("%LinkEdit").text = FileAccess.get_file_as_string(FIXTURE)
	dialog.get_node("%LoadButton").pressed.emit()
	await get_tree().process_frame
	var status: String = dialog.get_node("%StatusLabel").text
	print(status)
	_check("status says imported", status.begins_with("Импортировано: Acolyte, Lich, уровень 58"), true)
	var class_select: OptionButton = main.get_node("%ClassSelect")
	var mastery_select: OptionButton = main.get_node("%MasterySelect")
	_check("top bar class", class_select.get_item_id(class_select.selected), 3)
	_check("top bar mastery", mastery_select.selected, 2)
	_check("top bar mastery text", mastery_select.get_item_text(mastery_select.selected), "Lich")
	_check("top bar level", int(main.get_node("%LevelSpin").value), 58)
	_check("build kept after sync (no set_class re-trigger)", [Build.class_id, Build.mastery, Build.items.size()], [3, 2, 21])

	dialog.get_node("%LinkEdit").text = "https://example.com/x"
	dialog.get_node("%LoadButton").pressed.emit()
	_check("bad link message", dialog.get_node("%StatusLabel").text.begins_with("Некорректная ссылка"), true)
	dialog.get_node("%LinkEdit").text = "{not json"
	dialog.get_node("%LoadButton").pressed.emit()
	_check("bad json message", dialog.get_node("%StatusLabel").text.begins_with("Ответ не является"), true)
	dialog.hide()
	main.queue_free()
