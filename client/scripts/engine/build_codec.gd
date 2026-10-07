class_name BuildCodec

## Saving, sharing and loading builds. Pure functions: the Build autoload -> JSON-safe snapshot -> validated document ->
## Build, a compact URL-safe base64 "build code" (JSON -> deflate -> base64, like Path of Building) and save files in
## user://builds. Data format: client/docs/UI.md "Builds".

const BuildScript: GDScript = preload("res://scripts/autoload/build.gd")

const FORMAT: String = "le-builder"
const VERSION: int = 1
const SAVE_DIR: String = "user://builds"
const MAX_DECODED_BYTES: int = 1 << 24
const SKILL_SLOTS: int = 5
const SKILL_LEVEL_MAX: int = 20
const LEVEL_MAX: int = 100


# ============================================================================
# SNAPSHOT
# ============================================================================

## JSON-safe snapshot of the build (dictionary keys are strings).
static func to_dict(build: Node) -> Dictionary:
	var skills: Array = []
	for skill: Dictionary in build.skills:
		skills.append({
			"ability": str(skill["ability"]),
			"level": int(skill["level"]),
			"tree": _string_keys(skill["tree"]),
			"inputs": (skill["inputs"] as Dictionary).duplicate(true),
			"hits": float(skill["hits"]),
			"projectile_mode": str(skill.get("projectile_mode", "average")),
		})
	var blessings: Dictionary = {}
	for timeline: Variant in build.blessings:
		blessings[str(timeline)] = (build.blessings[timeline] as Dictionary).duplicate()
	var enemy: Dictionary = (build.enemy as Dictionary).duplicate(true)
	enemy["ailments"] = _string_keys(enemy.get("ailments", {}))
	return {
		"format": FORMAT,
		"version": VERSION,
		"class": build.class_id,
		"mastery": build.mastery,
		"level": build.level,
		"quest_points": build.quest_passive_points,
		"passives": _string_keys(build.passives),
		"skills": skills,
		"selected_skill": build.selected_skill,
		"items": (build.items as Dictionary).duplicate(true),
		"stash": (build.stash as Array).duplicate(true),
		"blessings": blessings,
		"enemy": enemy,
		"player": _player_out(build.player_state),
		"defense": DefenseCalc.normalized(build.defense),
	}


static func _string_keys(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in source:
		result[str(key)] = source[key]
	return result


# ============================================================================
# VALIDATION
# ============================================================================

## Snapshot (usually parsed from JSON: numbers are floats, keys are strings) -> normalized document for apply().
## {"ok": false, "warnings"} when the data cannot be used at all; otherwise {"ok": true, "warnings", class_id, mastery,
## level, quest_points, passives, skills, selected_skill, items, stash, blessings, enemy, player, defense}.
static func from_dict(data: Variant) -> Dictionary:
	var warnings: Array[String] = []
	if not data is Dictionary or data.get("format") != FORMAT:
		return _fail(LE.t("This is not a Last Epoch Builder build."))
	var version: int = int(data.get("version", 0))
	if version > VERSION:
		return _fail(LE.t("The build was saved by a newer version of the planner (format %d).") % version)
	var class_id: int = int(data.get("class", -1))
	var class_data: Dictionary = GameData.get_class_data(class_id)
	if class_data.is_empty():
		return _fail(LE.t("Unknown class: %d.") % class_id)

	var mastery: int = int(data.get("mastery", 0))
	if mastery < 0 or mastery >= class_data.get("masteries", []).size():
		warnings.append(LE.t("Unknown mastery: %d, \"No mastery\" selected.") % mastery)
		mastery = 0

	var passives: Dictionary = _points(data.get("passives"), _node_ids(GameData.get_passive_tree(class_id)))
	if passives["unknown"] > 0:
		warnings.append(LE.t("Passives: %d unknown nodes skipped.") % passives["unknown"])

	var items: Dictionary = {}
	var raw_items: Variant = _ints(data.get("items", {}))
	for slot: Variant in raw_items if raw_items is Dictionary else {}:
		var item: Variant = raw_items[slot]
		if item is Dictionary and not GameData.item_base(int(item.get("base", -1))).is_empty():
			items[str(slot)] = item
		else:
			warnings.append(LE.t("Unknown slot \"%s\", skipped.") % slot)

	var stash: Array = []
	var skipped_stash: int = 0
	var raw_stash: Variant = _ints(data.get("stash", []))
	for item: Variant in raw_stash if raw_stash is Array else []:
		if item is Dictionary and not GameData.item_base(int(item.get("base", -1))).is_empty():
			stash.append(item)
		else:
			skipped_stash += 1
	if skipped_stash > 0:
		warnings.append(LE.t("Unequipped items: %d unknown items skipped.") % skipped_stash)

	var blessings: Dictionary = {}
	var raw_blessings: Variant = _ints(data.get("blessings", {}))
	for timeline: Variant in raw_blessings if raw_blessings is Dictionary else {}:
		var blessing: Variant = raw_blessings[timeline]
		if str(timeline).is_valid_int() and blessing is Dictionary and blessing.has("id"):
			blessings[int(timeline)] = {"id": int(blessing["id"]), "roll": int(blessing.get("roll", 255))}

	return {
		"ok": true,
		"warnings": warnings,
		"class_id": class_id,
		"mastery": mastery,
		"level": clampi(int(data.get("level", LEVEL_MAX)), 1, LEVEL_MAX),
		"quest_points": clampi(int(data.get("quest_points", BuildScript.QUEST_PASSIVE_POINTS_MAX)), 0, BuildScript.QUEST_PASSIVE_POINTS_MAX),
		"passives": passives["points"],
		"skills": _skills(data.get("skills"), warnings),
		"selected_skill": clampi(int(data.get("selected_skill", 0)), 0, SKILL_SLOTS - 1),
		"items": items,
		"stash": stash,
		"blessings": blessings,
		"enemy": _enemy(data.get("enemy")),
		"player": _player(data.get("player")),
		"defense": DefenseCalc.normalized(data.get("defense")),
	}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "warnings": [message]}


## Whole-valued floats -> ints, recursively (JSON turns every number into a float).
static func _ints(value: Variant) -> Variant:
	if value is Dictionary:
		var dict: Dictionary = {}
		for key: Variant in value:
			dict[key] = _ints(value[key])
		return dict
	if value is Array:
		var list: Array = []
		for element: Variant in value:
			list.append(_ints(element))
		return list
	if value is float and absf(value) < 1.0e15 and value == floorf(value):
		return int(value)
	return value


static func _node_ids(tree: Dictionary) -> Dictionary:
	var known: Dictionary = {}
	for node: Variant in tree.get("nodes", []):
		if node is Dictionary:
			known[int(node.get("id", -1))] = true
	return known


## {"points": {node id: points}, "unknown": n}: positive points of known nodes only.
static func _points(raw: Variant, known: Dictionary) -> Dictionary:
	var points: Dictionary = {}
	var unknown: int = 0
	for key: Variant in raw if raw is Dictionary else {}:
		var count: int = int(raw[key])
		if count <= 0:
			continue
		if str(key).is_valid_int() and known.has(int(key)):
			points[int(key)] = count
		else:
			unknown += 1
	return {"points": points, "unknown": unknown}


static func _skills(raw_skills: Variant, warnings: Array[String]) -> Array:
	var skills: Array = []
	for i in range(SKILL_SLOTS):
		var skill: Dictionary = BuildScript.default_skill()
		skills.append(skill)
		var raw: Variant = raw_skills[i] if raw_skills is Array and i < raw_skills.size() else null
		var ability_id: String = str(raw.get("ability", "")) if raw is Dictionary else ""
		if ability_id == "":
			continue
		var ability: Dictionary = GameData.get_ability(ability_id)
		if ability.is_empty():
			warnings.append(LE.t("Skill %d: unknown id \"%s\", skipped.") % [i + 1, ability_id])
			continue
		skill["ability"] = ability_id
		skill["level"] = clampi(int(raw.get("level", SKILL_LEVEL_MAX)), 1, SKILL_LEVEL_MAX)
		var tree_id: String = str(ability.get("skillTree", ability_id))
		var tree: Dictionary = _points(raw.get("tree"), _node_ids(GameData.get_skill_tree(tree_id)))
		skill["tree"] = tree["points"]
		if tree["unknown"] > 0:
			warnings.append(LE.t("Skill %d (%s): %d unknown nodes skipped.") % [i + 1, ability_id, tree["unknown"]])
		if raw.get("inputs") is Dictionary:
			skill["inputs"] = (raw["inputs"] as Dictionary).duplicate(true)
		skill["hits"] = 1.0  # the "hits per use" field is hidden (projectile selector instead): old saved values are reset
		var mode: String = str(raw.get("projectile_mode", "average"))
		skill["projectile_mode"] = mode if SkillCalc.PROJECTILE_MODES.has(mode) else "average"
	return skills


## Saved keys over the defaults (whole-valued floats -> ints).
static func _merged(defaults: Dictionary, saved: Variant) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	var raw: Variant = _ints(saved)
	for key: Variant in raw if raw is Dictionary else {}:
		result[key] = raw[key]
	return result


static func _player_out(state: Dictionary) -> Dictionary:
	var player: Dictionary = state.duplicate(true)
	player["buffs"] = _string_keys(player.get("buffs", {}) if player.get("buffs") is Dictionary else {})
	return player


## Player state with defaults; buff stacks keyed by int AilmentID.
static func _player(saved: Variant) -> Dictionary:
	var player: Dictionary = _merged(BuildScript.default_player_state(), saved)
	var buffs: Dictionary = {}
	for key: Variant in player["buffs"] if player["buffs"] is Dictionary else {}:
		if str(key).is_valid_int():
			buffs[int(key)] = maxf(float(player["buffs"][key]), 0.0)  # 0 = set by hand to none
	player["buffs"] = buffs
	var minions: Dictionary = {}
	for key: Variant in player["minions"] if player["minions"] is Dictionary else {}:
		minions[str(key)] = maxf(float(player["minions"][key]), 0.0)
	player["minions"] = minions
	for key: String in EnemyAilments.EVENT_INPUTS:
		player[key] = maxf(float(player.get(key, 0.0)), 0.0)  # per second, fractional
	return player


static func _enemy(saved: Variant) -> Dictionary:
	var default: Dictionary = BuildScript.default_enemy()
	var enemy: Dictionary = _merged(default, saved)
	var flags: Dictionary = (default["flags"] as Dictionary).duplicate()
	if enemy["flags"] is Dictionary:
		flags.merge(enemy["flags"], true)
	enemy["flags"] = flags
	var ailments: Dictionary = {}
	for key: Variant in enemy["ailments"] if enemy["ailments"] is Dictionary else {}:
		if str(key).is_valid_int():
			ailments[int(key)] = float(enemy["ailments"][key])
	enemy["ailments"] = ailments
	return enemy


# ============================================================================
# APPLYING
# ============================================================================

## Replaces the build of the Build autoload (`build`) with a document from from_dict (ok == true) and emits `changed`.
static func apply(build: Node, doc: Dictionary) -> void:
	build.set_class(int(doc["class_id"]))  # resets mastery, passives, skills, items, stash and blessings
	build.mastery = int(doc["mastery"])
	build.level = int(doc["level"])
	build.quest_passive_points = int(doc["quest_points"])
	build.passives = (doc["passives"] as Dictionary).duplicate()
	var skills: Array = doc["skills"]
	for i in range(mini(skills.size(), build.skills.size())):
		var skill: Dictionary = skills[i]
		if str(skill["ability"]) == "":
			continue
		build.set_skill(i, str(skill["ability"]))  # loads the skill tree nodes
		build.skills[i]["tree"] = (skill["tree"] as Dictionary).duplicate()
		build.skills[i]["level"] = int(skill["level"])
		build.skills[i]["inputs"] = (skill["inputs"] as Dictionary).duplicate(true)
		build.skills[i]["hits"] = float(skill["hits"])
		build.skills[i]["projectile_mode"] = str(skill["projectile_mode"])
	build.items = (doc["items"] as Dictionary).duplicate(true)
	build.stash.assign((doc["stash"] as Array).duplicate(true))
	build.stash_changed.emit()
	build.blessings = (doc["blessings"] as Dictionary).duplicate(true)
	build.enemy = (doc["enemy"] as Dictionary).duplicate(true)
	build.player_state = (doc["player"] as Dictionary).duplicate(true)
	build.defense = (doc["defense"] as Dictionary).duplicate(true)
	build.selected_skill = int(doc["selected_skill"])
	build.changed.emit()


# ============================================================================
# BUILD CODE
# ============================================================================

## One-line URL-safe base64 of the deflated JSON snapshot.
static func encode(build: Node) -> String:
	var bytes: PackedByteArray = JSON.stringify(to_dict(build)).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


## Build code (or the plain JSON text of a snapshot) -> from_dict result.
static func decode(text: String) -> Dictionary:
	var json_text: String = ""
	var trimmed: String = text.strip_edges()
	if trimmed.begins_with("{"):
		json_text = trimmed
	else:
		var code: String = trimmed
		for ch: String in [" ", "\n", "\r", "\t"]:
			code = code.replace(ch, "")
		var valid := RegEx.new()
		valid.compile("^[A-Za-z0-9_-]+$")
		if valid.search(code) != null:
			code = code.replace("-", "+").replace("_", "/")
			while code.length() % 4 != 0:
				code += "="
			var bytes: PackedByteArray = Marshalls.base64_to_raw(code)
			if bytes.size() > 2:
				json_text = bytes.decompress_dynamic(MAX_DECODED_BYTES, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()
	var json := JSON.new()
	if json_text == "" or json.parse(json_text) != OK:
		return _fail(LE.t("Could not read the build code: it is damaged or incomplete."))
	return from_dict(json.data)


# ============================================================================
# SAVE FILES
# ============================================================================

## Writes the build to <dir>/<file_name(name)>; returns the path, "" on failure.
static func save_build(name: String, build: Node, dir: String = SAVE_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join(file_name(name))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify({"name": name, "saved": int(Time.get_unix_time_from_system()), "build": to_dict(build)}, "\t"))
	file.close()
	return path


## Safe file name of a save: characters that Windows forbids become "_".
static func file_name(name: String) -> String:
	var result: String = ""
	for ch: String in name.strip_edges():
		result += "_" if ch in "<>:\"/\\|?*" or ch.unicode_at(0) < 32 else ch
	return (result if result != "" else "build") + ".json"


## Saves of the folder, newest first: {name, path, saved, class_id, mastery, level} (the build is not validated here).
static func list_saves(dir: String = SAVE_DIR) -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return saves
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() != "json":
			continue
		var path: String = dir.path_join(file)
		var parsed: Variant = _read_json(path)
		if not parsed is Dictionary or not parsed.get("build") is Dictionary:
			continue
		var build: Dictionary = parsed["build"]
		saves.append({
			"name": str(parsed.get("name", file.get_basename())),
			"path": path,
			"saved": int(parsed.get("saved", 0)),
			"class_id": int(build.get("class", -1)),
			"mastery": int(build.get("mastery", 0)),
			"level": int(build.get("level", 1)),
		})
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["saved"] > b["saved"])
	return saves


## from_dict of a save file plus its "name".
static func load_save(path: String) -> Dictionary:
	var parsed: Variant = _read_json(path)
	if not parsed is Dictionary:
		return _fail(LE.t("Could not read the save file."))
	var doc: Dictionary = from_dict(parsed.get("build"))
	doc["name"] = str(parsed.get("name", path.get_file().get_basename()))
	return doc


static func delete_save(path: String) -> bool:
	return DirAccess.remove_absolute(path) == OK


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
