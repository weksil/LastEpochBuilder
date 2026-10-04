extends Node

## ConfigRelevance: an empty build needs no condition controls; the sample LE Tools build (tests/fixtures) needs exactly
## the ailments it applies or reads, Haste from its Harvest tree and the enemy health flags of Swaddling of the Erased.
## Headless: prints «RELEVANCE TEST: OK» and quits with code 0, otherwise lists the failures and quits with code 1.

const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")

var _failed: bool = false


func _ready() -> void:
	var empty: Dictionary = ConfigRelevance.compute(Build)
	for group: String in empty:
		_check(empty[group].is_empty(), "empty build: %s should be empty, got %s" % [group, str(empty[group].keys())])

	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/letools_A83KxJq5.json")
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(JSON.parse_string(text)))
	var r: Dictionary = ConfigRelevance.compute(Build)
	var names: Array[String] = []
	for id: int in r["ailments"]:
		names.append(str(GameData.ailment(id).get("name", id)))
	for expected: String in ["ArmourShred", "Poison", "BoneCurse", "Bleed", "Frailty"]:
		_check(names.has(expected), "sample build: ailment %s expected in %s" % [expected, str(names)])
	for absent: String in ["Ignite", "Shock", "Chill"]:
		_check(not names.has(absent), "sample build: ailment %s has no source" % absent)
	_check(r["player_flags"].has("haste"), "sample build: haste expected (Harvest tree)")
	_check(r["enemy"].has("high_health"), "sample build: enemy high_health expected (Swaddling of the Erased)")
	_check(not r["enemy"].has("frozen"), "sample build: frozen has no source")
	# recording must be off after compute: a later global_store does not leak into the next result
	BuildMods.global_store(Build)
	_check(ConfigRelevance.compute(Build)["ailments"].size() == r["ailments"].size(), "repeated compute changed the result")

	print("RELEVANCE TEST: %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: " + message)
