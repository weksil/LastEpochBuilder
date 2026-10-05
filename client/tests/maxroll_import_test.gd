extends Node

## Headless check of the Maxroll character import: URLs, character list, item blob upgrade / decoding, conversion of two
## real characters (trimmed responses in tests/fixtures) and applying them to Build.
## Expected values of the blobs come from tools/extract/save_parser.py.
## Run: Godot_console.exe --headless --path client res://tests/maxroll_import_test.tscn

const FIXTURE_DIR: String = "res://tests/fixtures/"
const WEAVER_WARNING: String = "The Weaver tree and Weaver idols are not supported, skipped."

var _failed: int = 0


func _ready() -> void:
	# a script error stops this coroutine; never hang the headless run
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("MAXROLL IMPORT TEST: TIMEOUT")
		get_tree().quit(1))
	_urls()
	_character_list()
	_upgrade()
	_decode()
	_bad_input()
	var palading: Dictionary = _palading()
	var chudlet: Dictionary = _chudlet()
	_apply(chudlet, 3, 98)
	_apply(palading, 2, 100)
	print("MAXROLL IMPORT TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, got: Variant, want: Variant) -> void:
	if str(got) != str(want):
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


func _load(file_name: String) -> Variant:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_DIR + file_name))
	if parsed == null:
		_failed += 1
		print("FAIL fixture %s not loaded" % file_name)
	return parsed


## Data array of the first savedItems entry in `container`.
func _blob(save: Dictionary, container: int) -> Array:
	for entry: Dictionary in save["savedItems"]:
		if int(entry.get("containerID", 0)) == container:
			return entry["data"]
	return []


func _urls() -> void:
	_check("list_url", MaxrollImport.list_url("Jess rabbit"), "https://planners.maxroll.gg/lastepoch/characters/Jess%20rabbit")
	_check("list_url trims", MaxrollImport.list_url("  jessrabbit "), "https://planners.maxroll.gg/lastepoch/characters/jessrabbit")
	_check("list_url empty", MaxrollImport.list_url("   "), "")
	_check("character_url", MaxrollImport.character_url("jessrabbit", "Sandstorm_Chudlet"), "https://planners.maxroll.gg/lastepoch/characters/jessrabbit/Sandstorm_Chudlet")
	_check("character_url spaces and #", MaxrollImport.character_url(" my acc ", "A b#1"), "https://planners.maxroll.gg/lastepoch/characters/my%20acc/A%20b%231")


func _character_list() -> void:
	var list: Array = MaxrollImport.parse_character_list(_load("maxroll_list_jessrabbit.json"))
	_check("list count", list.size(), 18)
	_check("list first", [list[0]["name"], list[0]["level"], list[0]["class_id"], list[0]["mastery"], list[0]["cycle"], list[0]["legacy"]], ["10bildps", 100, 3, 2, 8, false])
	var order_ok: bool = true
	var seen_legacy: bool = false
	var max_cycle: int = 0
	for entry: Dictionary in list:
		max_cycle = maxi(max_cycle, int(entry["cycle"]))
	for entry: Dictionary in list:
		if entry["legacy"]:
			seen_legacy = true
		elif seen_legacy:
			order_ok = false
		if entry["legacy"] != (int(entry["cycle"]) < max_cycle):
			order_ok = false
	_check("list non-legacy first, legacy = older than cycle 8", [order_ok, max_cycle], [true, 8])
	_check("list JessSupp (cycle 2) is legacy", list.filter(func(e: Dictionary) -> bool: return e["name"] == "JessSupp")[0]["legacy"], true)
	_check("list keeps duplicate names", list.filter(func(e: Dictionary) -> bool: return e["name"] == "JessORBIN").size(), 2)
	_check("list not an array", MaxrollImport.parse_character_list({"a": 1}), [])
	var junk: Array = [1, "x", {"level": 5}, {"characterName": "", "level": 5}, {"characterName": "b", "level": 3, "cycle": 2}, {"characterName": "A", "level": 3, "cycle": 2}, {"characterName": "C", "level": 9, "cycle": 1}]
	_check("list skips junk, sorts", MaxrollImport.parse_character_list(junk).map(func(e: Dictionary) -> String: return "%s%s" % [e["name"], "L" if e["legacy"] else ""]), ["A", "b", "CL"])


## Old item versions, crafted from the v2 sample of research/07e_save_format.md; expected v6 bytes from save_parser.upgrade_to_v6.
func _upgrade() -> void:
	var affixes: Array = [17, 247, 41, 16, 8, 181, 17, 248, 110, 0, 13, 151]
	var v1: Array = [1, 4, 1, 4, 61, 20, 192, 20, 4] + affixes + [0]
	var v2: Array = [2, 4, 1, 4, 0, 61, 20, 192, 20, 4] + affixes + [0]
	var v5: Array = [5, 0x80 | 0x12, 0x34, 4, 1, 4, 0, 61, 20, 192, 20, 4] + affixes
	var tail: Array = [4, 1, 4, 0, 61, 20, 192, 20, 4] + affixes
	_check("upgrade v1", Array(MaxrollImport.upgrade_item(v1)), [6, 0, 0, 0, 0, 4, 1, 4, 128, 61, 20, 192, 20, 4, 17, 247, 41, 16, 8, 181, 17, 248, 110, 0, 13, 151, 0])
	_check("upgrade v2", Array(MaxrollImport.upgrade_item(v2)), [6, 0, 0, 0, 0] + tail + [0])
	_check("upgrade v5 keeps id and duplicated flag", Array(MaxrollImport.upgrade_item(v5)), [6, 128, 0, 18, 52] + tail)
	var v6: Array = [6, 0, 0, 0, 0] + tail
	_check("upgrade v6 unchanged", Array(MaxrollImport.upgrade_item(v6)), v6)
	_check("upgrade version 7 rejected", MaxrollImport.upgrade_item([7, 0, 0, 0, 0, 4]).size(), 0)
	_check("upgrade base64", Array(MaxrollImport.upgrade_item(Marshalls.raw_to_base64(PackedByteArray(v6)))), v6)
	_check("upgrade floats from JSON", Array(MaxrollImport.upgrade_item(JSON.parse_string(JSON.stringify(v2)))), [6, 0, 0, 0, 0] + tail + [0])
	for blob: Array in [v1, v2, v5]:
		var item: Dictionary = MaxrollImport.decode_item(blob)
		_check("decode old v%d" % blob[0], [item["base"], item["sub"], item["rarity"], item["implicit_rolls"], _affix_rows(item)],
				[4, 1, 4, [61, 20, 192], [[503, 2, 41, ""], [8, 2, 181, ""], [504, 2, 110, ""], [13, 1, 151, ""]]])


func _affix_rows(item: Dictionary) -> Array:
	var rows: Array = []
	for affix: Dictionary in item["affixes"]:
		rows.append([affix["id"], affix["tier"], affix["roll"], affix["sealed"]])
	return rows


func _decode() -> void:
	var palading: Dictionary = _load("maxroll_char_palading.json")
	var helmet: Dictionary = MaxrollImport.decode_item(_blob(palading, 2))
	_check("helmet base/sub/rarity/corrupted/unique", [helmet["base"], helmet["sub"], helmet["rarity"], helmet["corrupted"], helmet["unique"]], [0, 61, 4, false, -1])
	_check("helmet implicit rolls", helmet["implicit_rolls"], [142, 167, 55])
	_check("helmet affixes (regular-sealed first)", _affix_rows(helmet), [[370, 1, 116, "regular"], [90, 6, 140, ""], [765, 6, 232, ""], [802, 5, 212, ""], [560, 7, 149, ""]])

	var boots: Dictionary = MaxrollImport.decode_item(_blob(palading, 8))
	_check("legendary boots base/sub/rarity/corrupted/unique", [boots["base"], boots["sub"], boots["rarity"], boots["corrupted"], boots["unique"]], [3, 2, 9, true, 253])
	_check("legendary boots unique rolls", boots["unique_rolls"].size(), 8)
	_check("legendary boots corruption-sealed last affix", _affix_rows(boots), [[28, 7, 206, ""], [27, 7, 232, ""], [80, 5, 113, "corruption"]])

	var sceptre: Dictionary = MaxrollImport.decode_item(_blob(palading, 4))
	_check("legendary weapon (not corrupted)", [sceptre["base"], sceptre["rarity"], sceptre["corrupted"], sceptre["unique"], _affix_rows(sceptre)], [8, 9, false, 355, [[57, 7, 244, ""], [72, 7, 48, ""]]])
	var belt: Dictionary = MaxrollImport.decode_item(_blob(palading, 7))
	_check("rare with regular + corruption seals", _affix_rows(belt), [[65, 2, 143, "regular"], [771, 3, 85, "corruption"], [52, 7, 206, ""], [67, 2, 14, ""], [27, 7, 252, ""], [958, 1, 0, ""]])
	_check("rare: rarity re-derived (6 affixes - 2 seals)", belt["rarity"], 4)
	var primordial: Dictionary = MaxrollImport.decode_item([6, 0, 0, 0, 1, 0, 61, 4, 0, 1, 2, 3, 0, 1, 0x71, 0xF5, 100])
	_check("primordial (tier nibble 7), rarity 0", [_affix_rows(primordial), primordial["rarity"]], [[[501, 8, 100, "primordial"]], 0])
	var altar: Dictionary = MaxrollImport.decode_item(_blob(palading, 123))
	_check("altar", [altar["base"], altar["sub"], altar["corrupted"]], [41, 11, true])
	_check("non-equipment rejected", MaxrollImport.decode_item([6, 0, 0, 0, 1, 101, 0, 9]), {})
	_check("truncated rejected", MaxrollImport.decode_item([6, 0, 0, 0, 1, 4, 1]), {})
	_check("truncated unique rejected", MaxrollImport.decode_item([6, 0, 0, 0, 1, 4, 1, 7, 0, 0, 0, 0, 0, 79]), {})
	_check("empty data", MaxrollImport.decode_item([]), {})


func _bad_input() -> void:
	var doc: Dictionary = MaxrollImport.to_build({})
	_check("empty save: class -1 and a warning", [doc["class_id"], doc["warnings"].size()], [-1, 1])
	var broken: Dictionary = _load("maxroll_char_palading.json")
	broken["chosenMastery"] = 9
	broken["level"] = 500
	broken["savedItems"][0]["data"] = [6, 0, 0, 0, 1]
	# body armor with the affix id 4095, which does not exist
	broken["savedItems"][1]["data"] = [6, 0, 0, 0, 1, 1, 61, 4, 0, 255, 255, 255, 12, 1, 0x0F, 0xFF, 7]
	broken["savedCharacterTree"]["nodeIDs"][0] = 250
	var result: Dictionary = MaxrollImport.to_build(broken)
	_check("broken: mastery fallback and level clamp", [result["mastery"], result["level"]], [0, 100])
	_check("broken: truncated helmet skipped", result["items"].has("helmet"), false)
	_check("broken: unknown affix skipped, item kept", [result["items"].has("body"), result["items"]["body"]["affixes"].size()], [true, 0])
	_check("broken: unknown passive skipped", result["passives"].has(250), false)
	print("broken warnings:")
	for w: String in result["warnings"]:
		print("  - " + w)
	_check("broken: warnings (mastery, helmet, affix, passive, weaver)", result["warnings"].size(), 5)


func _print_warnings(doc: Dictionary) -> void:
	print("warnings (%d):" % doc["warnings"].size())
	for w: String in doc["warnings"]:
		print("  - " + w)


func _passive_sum(doc: Dictionary) -> int:
	var sum: int = 0
	for points: Variant in doc["passives"].values():
		sum += int(points)
	return sum


func _idol_keys(doc: Dictionary) -> Array:
	var keys: Array = []
	for slot: String in doc["items"]:
		if IdolGrid.is_idol_key(slot):
			keys.append(slot)
	keys.sort()
	return keys


func _abilities(doc: Dictionary) -> Array:
	return doc["skills"].map(func(s: Dictionary) -> String: return s["ability"])


func _palading() -> Dictionary:
	var doc: Dictionary = MaxrollImport.to_build(_load("maxroll_char_palading.json"))
	_print_warnings(doc)
	_check("palading class/mastery/level", [doc["class_id"], doc["mastery"], doc["level"]], [2, 1, 100])
	_check("palading passives", _passive_sum(doc) > 0, true)
	_check("palading skills", _abilities(doc), ["do5vr", "ab0lh", "vr53sl", "an0my", "st31io"])
	var items: Dictionary = doc["items"]
	_check("palading altar sub", items[IdolGrid.ALTAR_SLOT]["sub"], 11)
	_check("palading altar has no corrupted flag", items[IdolGrid.ALTAR_SLOT].has("corrupted"), false)
	_check("palading equipment slots", items.keys().filter(func(k: String) -> bool: return not IdolGrid.is_idol_key(k) and k != IdolGrid.ALTAR_SLOT).size(), 11)
	# y goes up from the bottom, (x, y) is the bottom-left cell: row = 5 - y - height
	_check("palading idols", _idol_keys(doc), ["idol_0_2", "idol_1_1", "idol_1_2", "idol_1_3", "idol_2_4", "idol_3_0"])
	_check("palading blessings", doc["blessings"].size(), 10)
	_check("palading sceptre unique", [items["weapon"]["unique"], items["weapon"]["base"]], [355, int(GameData.unique(355)["baseType"])])
	_check("palading helmet", [items["helmet"]["base"], items["helmet"]["sub"], items["helmet"].has("corrupted")], [0, 61, false])
	var helmet: Array = items["helmet"]["affixes"].map(func(a: Dictionary) -> Array: return [a["id"], a["tier"], a["roll"], a.get("sealed", false)])
	helmet.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	_check("palading helmet affixes", helmet, [[90, 6, 140, false], [370, 1, 116, true], [560, 7, 149, false], [765, 6, 232, false], [802, 5, 212, false]])
	var boots_last: Dictionary = items["boots"]["affixes"].back()
	_check("palading boots corruption-sealed affix", [boots_last["id"], boots_last.get("corrupted", false), boots_last["index"]], [80, true, 5])
	_check("palading boots corrupted", items["boots"].get("corrupted", false), true)
	_check("palading ring2 is container 9", items["ring2"]["affixes"].map(func(a: Dictionary) -> int: return a["id"]), [501])
	_check("palading Weaver warning", doc["warnings"].has(LE.t(WEAVER_WARNING)), true)
	return doc


func _chudlet() -> Dictionary:
	var doc: Dictionary = MaxrollImport.to_build(_load("maxroll_char_chudlet.json"))
	_print_warnings(doc)
	_check("chudlet class/mastery/level", [doc["class_id"], doc["mastery"], doc["level"]], [3, 1, 98])
	_check("chudlet passives", _passive_sum(doc) > 0, true)
	_check("chudlet skills", _abilities(doc).size(), 5)
	var items: Dictionary = doc["items"]
	_check("chudlet altar sub", items[IdolGrid.ALTAR_SLOT]["sub"], 12)
	_check("chudlet idols", _idol_keys(doc), ["idol_0_0", "idol_0_2", "idol_0_4", "idol_1_0", "idol_1_3", "idol_2_1", "idol_2_2", "idol_3_0", "idol_3_3", "idol_4_2", "idol_4_4"])
	_check("chudlet blessings", doc["blessings"].size(), 10)
	_check("chudlet weapon is set item 79", [items["weapon"]["unique"], items["weapon"]["corrupted"], items["weapon"]["sub"]], [79, true, 3])
	_check("chudlet relic unique", items["relic"]["unique"], 413)
	_check("chudlet gloves corruption-sealed", items["gloves"]["affixes"].back().get("corrupted", false), true)
	var missing: int = 0
	for slot: String in items:
		for affix: Dictionary in items[slot]["affixes"]:
			if GameData.affix(int(affix["id"])).is_empty():
				missing += 1
	_check("chudlet every affix exists", missing, 0)
	var unexpected: Array = doc["warnings"].filter(func(w: String) -> bool: return w != LE.t(WEAVER_WARNING))
	# the bar holds Transplant without a specialized tree while bc53 is specialized but off the bar: the same rule as LE Tools
	_check("chudlet warnings other than Weaver: only the Transplant bar skill", [unexpected.size(), unexpected[0].contains("Transplant") if unexpected.size() > 0 else false], [1, true])

	return doc


func _apply(doc: Dictionary, class_id: int, level: int) -> void:
	LEToolsImport.apply(Build, doc)
	_check("Build class/level", [Build.class_id, Build.level], [class_id, level])
	_check("Build.spent_points", Build.spent_points(), _passive_sum(doc))
	_check("Build.items size", Build.items.size(), doc["items"].size())
	_check("Build.blessings", Build.blessings.size(), 10)
	_check("Build skill 0", Build.skills[0]["ability"], _abilities(doc)[0])
	var g: Dictionary = BuildMods.global_store(Build)
	var store: StatStore = g["store"]
	_check("global_store has mods", store.all_mods().size() > 0, true)
	Build.selected_skill = 0
	var r: Dictionary = SkillCalc.compute(Build, 0)
	_check("SkillCalc slot 0", r["title"] != "" and r["sections"].size() > 0, true)
