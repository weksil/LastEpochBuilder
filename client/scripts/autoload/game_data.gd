extends Node

## Game data loaded from research/data (see docs/ENGINE.md §4).

var classes: Array = []
var hidden_base_mods: Array = []
var attributes: Array = []
var item_bases: Array = []
var uniques: Array = []                  # uniques.json, without hideFromPlayers

var _trees: Array = []
var _tree_node_stats: Dictionary = {}
var _abilities: Dictionary = {}          # playerAbilityID -> ability
var _affixes_by_id: Dictionary = {}      # affixId -> affix
var _affixes_list: Array = []
var _items_by_id: Dictionary = {}        # baseTypeID -> base
var _ailments_by_id: Dictionary = {}     # id -> ailment
var _ailment_names: Dictionary = {}      # normalised name -> id (lazy)
var _passive_effects: Dictionary = {}    # treeID -> {node_id -> node}
var _skill_effects: Dictionary = {}      # treeID -> {node_id -> node}
var _sp_id_map: Dictionary = {}
var _sp_name_map: Dictionary = {}
var _enums: Dictionary = {}              # enum name -> {value name -> id}
var _damage_reduction_values: Array = []
var _idol_grid: Array = []                # 5×5 unlockMatrix, 99 = blocked
var _conversions: Dictionary = {}        # "Mutator.field" -> rule (skill_conversions.json)
var _uniques_by_id: Dictionary = {}      # uniqueID -> unique (all, incl. hidden)
var _unique_effects: Dictionary = {}     # uniqueID -> effects[] (unique_effects.json)
var _sets: Dictionary = {}               # setID -> set (sets.json)
var _unique_models: Dictionary = {}      # {player: {ppIndex: model}, ability: {"abilityIndex:propertyIndex": model}}


func _ready() -> void:
	var data_dir: String = ProjectSettings.globalize_path("res://").path_join("../research/data/game").simplify_path()
	var parent_dir: String = data_dir.path_join("..").simplify_path()

	var classes_json: Variant = _load_json(data_dir.path_join("classes.json"))
	if classes_json is Dictionary:
		classes = classes_json.get("data", [])
		hidden_base_mods = classes_json.get("hiddenBaseMods", [])

	var trees_json: Variant = _load_json(data_dir.path_join("trees.json"))
	if trees_json is Array:
		_trees = trees_json

	var stats_json: Variant = _load_json(data_dir.path_join("tree_node_stats.json"))
	if stats_json is Dictionary:
		_tree_node_stats = stats_json

	var abilities_json: Variant = _load_json(data_dir.path_join("abilities.json"))
	if abilities_json is Array:
		for ab: Dictionary in abilities_json:
			var pid: String = str(ab.get("playerAbilityID", ""))
			if pid == "" or pid == "<null>":
				continue
			# several records share an ID (Swipe / Swipe2 / werebear swipes): prefer the player ability owning the tree
			if not _abilities.has(pid) or _ability_rank(ab, pid) > _ability_rank(_abilities[pid], pid):
				_abilities[pid] = ab

	var affixes_json: Variant = _load_json(data_dir.path_join("affixes.json"))
	if affixes_json is Dictionary:
		_affixes_list = affixes_json.get("data", [])
		for aff: Dictionary in _affixes_list:
			_affixes_by_id[int(aff["affixId"])] = aff

	var items_json: Variant = _load_json(data_dir.path_join("items.json"))
	if items_json is Dictionary:
		item_bases = items_json.get("data", [])
		for base: Dictionary in item_bases:
			_items_by_id[int(base["baseTypeID"])] = base

	var ailments_json: Variant = _load_json(data_dir.path_join("ailments.json"))
	if ailments_json is Dictionary:
		for ail: Dictionary in ailments_json.get("data", []):
			_ailments_by_id[int(ail["id"])] = ail

	var attributes_json: Variant = _load_json(data_dir.path_join("attributes.json"))
	if attributes_json is Dictionary:
		attributes = attributes_json.get("data", [])

	_passive_effects = _index_effects(_load_json(data_dir.path_join("passive_node_effects.json")))
	_skill_effects = _index_effects(_load_json(data_dir.path_join("skill_node_effects.json")))

	var sp_json: Variant = _load_json(parent_dir.path_join("sp_enum.json"))
	if sp_json is Array:
		for entry: Dictionary in sp_json:
			_sp_id_map[str(entry["name"])] = int(entry["id"])
			_sp_name_map[int(entry["id"])] = str(entry["name"])

	var enums_json: Variant = _load_json(parent_dir.path_join("stat_tag_enums.json"))
	if enums_json is Dictionary:
		for enum_name: String in enums_json:
			var values: Dictionary = {}
			var enum_data: Variant = enums_json[enum_name]
			if enum_data is Dictionary:
				for v: Dictionary in enum_data.get("values", []):
					values[str(v["name"])] = int(v["id"])
			_enums[enum_name] = values

	var idols_json: Variant = _load_json(data_dir.path_join("idols.json"))
	if idols_json is Dictionary:
		_idol_grid = idols_json.get("containerGrids", {}).get("defaultData", [])

	var conv_json: Variant = _load_json(data_dir.path_join("skill_conversions.json"))
	if conv_json is Dictionary:
		for rule: Dictionary in conv_json.get("data", []):
			_conversions[str(rule["key"])] = rule

	var uniques_json: Variant = _load_json(data_dir.path_join("uniques.json"))
	if uniques_json is Dictionary:
		for u: Dictionary in uniques_json.get("data", []):
			_uniques_by_id[int(u["uniqueID"])] = u
			if not u.get("hideFromPlayers", false):
				uniques.append(u)
		uniques.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return display_name(a) < display_name(b))

	var effects_json: Variant = _load_json(data_dir.path_join("unique_effects.json"))
	if effects_json is Dictionary:
		for u: Dictionary in effects_json.get("data", []):
			_unique_effects[int(u["uniqueID"])] = u.get("effects", [])

	var sets_json: Variant = _load_json(data_dir.path_join("sets.json"))
	if sets_json is Dictionary:
		for st: Dictionary in sets_json.get("data", []):
			_sets[int(st["setID"])] = st

	# hand-written planner models (client/data, not extracted game data)
	var models_json: Variant = _load_json(ProjectSettings.globalize_path("res://data/unique_effect_models.json"))
	if models_json is Dictionary:
		_unique_models = models_json

	var dr_json: Variant = _load_json(parent_dir.path_join("monster_level_damage_reduction.json"))
	if dr_json is Dictionary:
		_damage_reduction_values = dr_json.get("values", [])


func _ability_rank(ab: Dictionary, pid: String) -> int:
	return (2 if ab.get("skillTree") == pid else 0) + (1 if ab.get("category") == "player" else 0)


func _load_json(path: String) -> Variant:
	var content: String = FileAccess.get_file_as_string(path)
	if content == "":
		push_error("Failed to load %s" % path)
		return null
	var json: Variant = JSON.parse_string(content)
	if json == null:
		push_error("Failed to parse %s" % path)
	return json


## [{treeID, nodes: [{id, ...}]}] -> {treeID: {node_id: node}}
func _index_effects(json: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not json is Array:
		return result
	for tree: Dictionary in json:
		var by_node: Dictionary = {}
		for node: Dictionary in tree.get("nodes", []):
			by_node[int(node["id"])] = node
		result[str(tree.get("treeID", ""))] = by_node
	return result


## Human-readable name of a data record: displayName → abilityName → name.
func display_name(rec: Dictionary) -> String:
	for key: String in ["displayName", "abilityName", "name"]:
		var v: Variant = rec.get(key)
		if v != null and str(v) != "":
			return str(v)
	return ""


func get_class_data(class_id: int) -> Dictionary:
	for entry: Dictionary in classes:
		if int(entry.get("classID", -1)) == class_id:
			return entry
	return {}


func get_passive_tree(class_id: int) -> Dictionary:
	for tree: Dictionary in _trees:
		if tree.get("kind") != "passive":
			continue
		var tree_classes: Array = tree.get("classes", [])
		if not tree_classes.is_empty() and int(tree_classes[0].get("classID", -1)) == class_id:
			return tree
	return {}


func get_node_stats(tree_id: String, node_id: int) -> Dictionary:
	return _tree_node_stats.get("%s:%d" % [tree_id, node_id], {})


func get_ability(pid: String) -> Dictionary:
	return _abilities.get(pid, {})


## Skills available to a class with the chosen mastery (playerAbilityIDs, no duplicates).
func class_skills(class_id: int, mastery: int) -> Array[String]:
	var result: Array[String] = []
	var class_data: Dictionary = get_class_data(class_id)
	if class_data.is_empty():
		return result
	var refs: Array = []
	var masteries: Array = class_data.get("masteries", [])
	if masteries.size() > 0:
		refs.append_array(masteries[0].get("abilities", []))
	if mastery > 0 and mastery < masteries.size():
		refs.append_array(masteries[mastery].get("abilities", []))
		if masteries[mastery].get("masteryAbility") is Dictionary:
			refs.append(masteries[mastery]["masteryAbility"])
	refs.append_array(class_data.get("knownAbilities", []))
	refs.append_array(class_data.get("unlockableAbilities", []))
	for ref: Variant in refs:
		if not ref is Dictionary:
			continue
		var pid: String = str(ref.get("playerAbilityID", ""))
		if pid == "" or pid == "na28" or pid == "ba1" or result.has(pid) or get_ability(pid).is_empty():
			continue
		result.append(pid)
	return result


func get_skill_tree(tree_id: String) -> Dictionary:
	for tree: Dictionary in _trees:
		if tree.get("kind") == "skill" and tree.get("treeID") == tree_id:
			return tree
	return {}


func passive_effects(tree_id: String) -> Dictionary:
	return _passive_effects.get(tree_id, {})


func skill_effects(tree_id: String) -> Dictionary:
	return _skill_effects.get(tree_id, {})


func affix(id: int) -> Dictionary:
	return _affixes_by_id.get(id, {})


func item_base(base_type_id: int) -> Dictionary:
	return _items_by_id.get(base_type_id, {})


func item_sub(base: int, sub: int) -> Dictionary:
	for st: Dictionary in item_base(base).get("subItems", []):
		if int(st.get("subTypeID", -1)) == sub:
			return st
	return {}


## Standard affixes that can roll on an equipment or idol type. Idol affixes are also filtered by class.
func affixes_for_type(type_id: int, class_filter: String = "") -> Array:
	var result: Array = []
	var rolls_on: String = "Idols" if is_idol_type(type_id) else "Equipment"
	for aff: Dictionary in _affixes_list:
		if aff.get("rollsOn") != rolls_on or aff.get("specialAffixType") != "Standard":
			continue
		var classes_ok: Array = aff.get("classSpecificity", [])
		if rolls_on == "Idols" and class_filter != "" and not classes_ok.is_empty() 				and not classes_ok.has("NonSpecific") and not classes_ok.has(class_filter):
			continue
		for t: Variant in aff.get("canRollOn", []):
			if int(t) == type_id:
				result.append(aff)
				break
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	return result


func is_idol_type(type_id: int) -> bool:
	return type_id >= 25 and type_id <= 33


## Idol grid without an altar: rows of cell codes (99 blocked, 1..8 unlocked by quest rewards).
func idol_grid() -> Array:
	return _idol_grid


## Conversion / tag-change rule for a skill-tree mutator field ("Mutator.field"), {} if none.
func conversion_rule(key: String) -> Dictionary:
	return _conversions.get(key, {})


func unique(id: int) -> Dictionary:
	return _uniques_by_id.get(id, {})


## Special effects of a unique (PlayerProperty / AbilityProperty / Component …) with formula text from the client code.
func unique_effects(id: int) -> Array:
	return _unique_effects.get(id, [])


func set_data(set_id: int) -> Dictionary:
	return _sets.get(set_id, {})


## Planner model of a PlayerProperty special effect (unique_effect_models.json), {} if not modelled.
func unique_player_model(pp_index: int) -> Dictionary:
	return _unique_models.get("player", {}).get(str(pp_index), {})


## Planner model of an AbilityProperty special effect, {} if not modelled.
func unique_ability_model(ability_index: int, property_index: int) -> Dictionary:
	return _unique_models.get("ability", {}).get("%d:%d" % [ability_index, property_index], {})


func ailment(id: int) -> Dictionary:
	return _ailments_by_id.get(id, {})


## Ailment id by asset name or AilmentID name, ignoring spaces and case ("Time Rot" == "TimeRot"); -1 if unknown.
func ailment_id_by_name(ailment_name: String) -> int:
	if _ailment_names.is_empty():
		for ail: Dictionary in _ailments_by_id.values():
			for key: String in [str(ail.get("name", "")), str(ail.get("ailmentIDName", ""))]:
				var norm: String = key.replace(" ", "").to_lower()
				if norm != "" and (not _ailment_names.has(norm) or ail.get("inList", false)):
					_ailment_names[norm] = int(ail["id"])
	return int(_ailment_names.get(ailment_name.replace(" ", "").to_lower(), -1))


## Negative ailments that can be configured on the enemy.
func enemy_ailments() -> Array:
	var result: Array = []
	for ail: Dictionary in _ailments_by_id.values():
		if not ail.get("inList", false) or int(ail.get("positive", 0)) != 0:
			continue
		var buffs: Array = ail.get("buffs", [])
		if buffs.is_empty() and not ail.get("dealsDamage", false):
			continue
		result.append(ail)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	return result


func sp_name(id: int) -> String:
	return _sp_name_map.get(id, "")


func sp_id(sp: String) -> int:
	return _sp_id_map.get(sp, -1)


func damage_reduction(level: int) -> float:
	if level > 100 or level < 0 or level >= _damage_reduction_values.size():
		return 0.0
	return float(_damage_reduction_values[level])


## Value of a named entry in research/data/stat_tag_enums.json, -1 if missing.
func enum_value(enum_name: String, value_name: String) -> int:
	return _enums.get(enum_name, {}).get(value_name, -1)
