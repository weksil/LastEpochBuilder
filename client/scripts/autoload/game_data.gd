extends Node

## Game data loaded from research/data (see docs/ENGINE.md §4).

var classes: Array = []
var hidden_base_mods: Array = []
var attributes: Array = []
var item_bases: Array = []

var _trees: Array = []
var _tree_node_stats: Dictionary = {}
var _abilities: Dictionary = {}          # playerAbilityID -> ability
var _affixes_by_id: Dictionary = {}      # affixId -> affix
var _affixes_list: Array = []
var _items_by_id: Dictionary = {}        # baseTypeID -> base
var _ailments_by_id: Dictionary = {}     # id -> ailment
var _passive_effects: Dictionary = {}    # treeID -> {node_id -> node}
var _skill_effects: Dictionary = {}      # treeID -> {node_id -> node}
var _sp_id_map: Dictionary = {}
var _sp_name_map: Dictionary = {}
var _enums: Dictionary = {}              # enum name -> {value name -> id}
var _damage_reduction_values: Array = []


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
			if not _abilities.has(pid) or ab.get("category") == "player":
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

	var dr_json: Variant = _load_json(parent_dir.path_join("monster_level_damage_reduction.json"))
	if dr_json is Dictionary:
		_damage_reduction_values = dr_json.get("values", [])


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


## Standard equipment affixes that can roll on an equipment type.
func affixes_for_type(type_id: int) -> Array:
	var result: Array = []
	for aff: Dictionary in _affixes_list:
		if aff.get("rollsOn") != "Equipment" or aff.get("specialAffixType") != "Standard":
			continue
		for t: Variant in aff.get("canRollOn", []):
			if int(t) == type_id:
				result.append(aff)
				break
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	return result


func ailment(id: int) -> Dictionary:
	return _ailments_by_id.get(id, {})


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
