extends Node

## Headless check that the Skills tab shows every imported skill by name: each saved build of tests/fixtures is applied
## to Build and the dropdown of every filled skill slot must read the ability's display name (also for abilities that are
## not in the class list), with the slot's level in the spin box.
## Run: Godot_console.exe --headless --path client res://tests/skill_slot_import_test.tscn

const FIXTURE_DIR: String = "res://tests/fixtures/"

var _failed: int = 0


func _ready() -> void:
	# a script error stops this coroutine; never hang the headless run
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("SKILL SLOT IMPORT TEST: TIMEOUT")
		get_tree().quit(1))
	var tab: Node = load("res://scenes/skills/skills_tab.tscn").instantiate()
	add_child(tab)
	await get_tree().process_frame
	var dir: DirAccess = DirAccess.open(FIXTURE_DIR)
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".json") or file_name.begins_with("maxroll_list"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_DIR + file_name))
		if not parsed is Dictionary:
			_failed += 1
			print("FAIL fixture %s not loaded" % file_name)
			continue
		var doc: Dictionary = MaxrollImport.to_build(parsed) if file_name.begins_with("maxroll_") else LEToolsImport.to_build(parsed)
		LEToolsImport.apply(Build, doc)
		await get_tree().process_frame
		_check_slots(file_name, tab)
	print("SKILL SLOT IMPORT TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, got: Variant, want: Variant) -> void:
	if str(got) != str(want):
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


func _check_slots(file_name: String, tab: Node) -> void:
	var filled: int = 0
	for slot: SkillSlot in tab.find_children("*", "SkillSlot", true, false):
		var skill: Dictionary = Build.skills[slot.slot_index]
		var ability_id: String = str(skill.get("ability", ""))
		if ability_id == "":
			continue
		filled += 1
		var select: OptionButton = slot.get_node("%SkillSelect")
		var want: String = str(GameData.get_ability(ability_id).get("abilityName", ability_id))
		_check("%s slot %d name" % [file_name, slot.slot_index + 1], select.get_item_text(select.selected), want)
		_check("%s slot %d metadata" % [file_name, slot.slot_index + 1], select.get_item_metadata(select.selected), ability_id)
		_check("%s slot %d level" % [file_name, slot.slot_index + 1], int(slot.get_node("%LevelSpin").value), int(skill["level"]))
	_check("%s has filled slots" % file_name, filled > 0, true)
