extends Node

## Build code and saves: a build survives encode -> decode -> apply and save -> list -> load unchanged.
## Run: Godot_console.exe --headless --path client res://tests/build_codec_test.tscn

const FIXTURE: String = "res://tests/fixtures/letools_A83KxJq5.json"
const TEST_DIR: String = "user://test_builds"

var _failed: int = 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("BUILD CODEC TEST TIMEOUT")
		get_tree().quit(1))
	_prepare_build()
	_roundtrip()
	_code_format()
	_saves()
	print("BUILD CODEC TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		print("FAIL: " + message)


func _prepare_build() -> void:
	var doc: Dictionary = LEToolsImport.to_build(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	LEToolsImport.apply(Build, doc)
	Build.set_enemy("armour", 500)
	Build.set_enemy_ailment(3, 2)
	Build.set_player_state("haste", true)
	Build.set_skill_input(0, "buff_active", false)
	Build.set_skill_hits(1, 2.5)
	Build.selected_skill = 2
	for unique: Dictionary in GameData.uniques:
		if ItemCompare.target_slot({"base": int(unique.get("baseType", -1))}, "") != "":
			Build.stash_add(ItemCompare.unique_item(int(unique["uniqueID"])))
			break
	var named: Dictionary = (Build.items[Build.items.keys()[0]] as Dictionary).duplicate(true)
	named["name"] = "Named test item"
	Build.stash_add(named)


func _other_class() -> int:
	for class_data: Dictionary in GameData.classes:
		if int(class_data["classID"]) != Build.class_id:
			return int(class_data["classID"])
	return 0


func _roundtrip() -> void:
	var before: String = var_to_str(BuildCodec.to_dict(Build))
	var code: String = BuildCodec.encode(Build)
	var class_id: int = Build.class_id
	Build.set_class(_other_class())
	var doc: Dictionary = BuildCodec.decode(code)
	_check(doc["ok"], "decode failed: %s" % str(doc["warnings"]))
	_check((doc["warnings"] as Array).is_empty(), "unexpected warnings: %s" % str(doc["warnings"]))
	BuildCodec.apply(Build, doc)
	var after: String = var_to_str(BuildCodec.to_dict(Build))
	_check(before == after, "snapshot differs after the roundtrip:\n%s\n---\n%s" % [before, after])
	_check(Build.class_id == class_id, "class id differs")

	# field types after apply
	var any_tree: bool = false
	for key: Variant in Build.passives:
		_check(key is int and Build.passives[key] is int, "passives must be int -> int")
	for skill: Dictionary in Build.skills:
		any_tree = any_tree or not (skill["tree"] as Dictionary).is_empty()
		for key: Variant in skill["tree"]:
			_check(key is int and skill["tree"][key] is int, "skill tree must be int -> int")
	_check(any_tree, "the fixture has no skill tree points")
	_check(not Build.items.is_empty(), "items are empty")
	for slot: Variant in Build.items:
		_check(slot is String and Build.items[slot]["base"] is int, "item %s: base must be int" % str(slot))
	var ailments: Dictionary = Build.enemy["ailments"]
	_check(not ailments.is_empty(), "enemy ailments are empty")
	for key: Variant in ailments:
		_check(key is int and ailments[key] is int, "ailments must be int -> int")
	_check(Build.skills[1]["hits"] is float and Build.skills[1]["hits"] == 2.5, "hits must be float 2.5")
	_check(Build.skills[0]["inputs"].get("buff_active") == false, "skill input lost")
	_check(Build.enemy["armour"] is int and Build.enemy["armour"] == 500, "enemy armour must be int 500")
	_check(Build.player_state["haste"] == true, "player haste lost")
	_check(Build.selected_skill == 2, "selected skill lost")
	_check(Build.quest_passive_points is int, "quest points must be int")
	_check(Build.stash.size() == 2, "stash must keep 2 items, has %d" % Build.stash.size())
	for item: Dictionary in Build.stash:
		_check(item["base"] is int, "stash item: base must be int")
	_check(str(Build.stash[1].get("name", "")) == "Named test item", "the custom item name was lost")


func _code_format() -> void:
	var code: String = BuildCodec.encode(Build)
	_check(code != "" and not ("+" in code or "/" in code or "=" in code), "the code is not URL-safe")
	var spaced: String = code.substr(0, 40) + "\n" + code.substr(40, 40) + " \t " + code.substr(80) + "\n"
	_check(BuildCodec.decode(spaced)["ok"], "a code with whitespace does not decode")
	var garbage: Dictionary = BuildCodec.decode("garbage!!")
	_check(not garbage["ok"] and not (garbage["warnings"] as Array).is_empty(), "garbage must fail with a warning")
	_check(not BuildCodec.decode("")["ok"], "an empty code must fail")
	_check(not BuildCodec.decode("QUJDREVGR0g")["ok"], "valid base64 that is not a build must fail")
	var from_json: Dictionary = BuildCodec.decode(JSON.stringify(BuildCodec.to_dict(Build)))
	_check(from_json["ok"], "plain JSON does not decode")
	_check(not BuildCodec.from_dict({"format": "other"})["ok"], "foreign format must fail")
	var newer: Dictionary = BuildCodec.to_dict(Build)
	newer["version"] = BuildCodec.VERSION + 1
	_check(not BuildCodec.from_dict(newer)["ok"], "a newer version must fail")
	var broken: Dictionary = BuildCodec.to_dict(Build)
	broken["passives"]["999999"] = 1
	broken["skills"][0]["ability"] = "nope"
	var doc: Dictionary = BuildCodec.from_dict(JSON.parse_string(JSON.stringify(broken)))
	_check(doc["ok"] and (doc["warnings"] as Array).size() == 2, "unknown passive / skill must give 2 warnings: %s" % str(doc["warnings"]))
	_check((doc["skills"] as Array).size() == 5 and doc["skills"][0]["ability"] == "", "skill slot must be emptied")


func _saves() -> void:
	for file: String in DirAccess.get_files_at(TEST_DIR) if DirAccess.dir_exists_absolute(TEST_DIR) else PackedStringArray():
		DirAccess.remove_absolute(TEST_DIR.path_join(file))
	var name: String = "Test / build?"
	var path: String = BuildCodec.save_build(name, Build, TEST_DIR)
	_check(path != "", "save_build failed")
	_check(not ("/" in path.get_file() or "?" in path.get_file()), "file name is not sanitized: %s" % path)
	var saves: Array[Dictionary] = BuildCodec.list_saves(TEST_DIR)
	_check(saves.size() == 1 and saves[0]["name"] == name, "list_saves: %s" % str(saves))
	if saves.size() == 1:
		_check(saves[0]["class_id"] == Build.class_id and saves[0]["level"] == Build.level, "list entry fields differ")
	var doc: Dictionary = BuildCodec.load_save(path)
	_check(doc["ok"] and doc["name"] == name, "load_save failed")
	_check(not BuildCodec.load_save(TEST_DIR.path_join("missing.json"))["ok"], "a missing save must fail")
	_check(BuildCodec.delete_save(path), "delete_save failed")
	_check(BuildCodec.list_saves(TEST_DIR).is_empty(), "the saves list is not empty after delete")
