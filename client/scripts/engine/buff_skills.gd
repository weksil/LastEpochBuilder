class_name BuffSkills

## Base buffs of skills that are written in mutator code and skill-to-mutator matching (docs/ENGINE.md §9.7).
## Models: client/data/buff_skill_models.json, key = ability name. Loaded lazily once.

const MODELS_PATH: String = "res://data/buff_skill_models.json"

static var _models: Dictionary = {}
static var _loaded: bool = false
static var _tree_mutators: Dictionary = {}  # treeID -> Array[String]
static var _tree_loaded: bool = false


static func find(ability_name: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var path: String = ProjectSettings.globalize_path(MODELS_PATH)
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				for key: String in parsed:
					if not key.begins_with("_"):
						_models[key] = parsed[key]
	return _models.get(ability_name, {})


## True if the tree stat list `target` of this ability is applied by `apply` (not by the field models).
static func owns_list(ability_name: String, target: String) -> bool:
	var model: Dictionary = find(ability_name)
	if model.is_empty():
		return false
	var lists: Dictionary = model.get("tree_lists", {})
	for part: String in target.split(" & "):
		if lists.values().has(part.strip_edges()):
			return true
	return false


## Declared input `key` of the skill: Build.skills[slot].inputs[key] or `default`.
static func input_value(build: Node, slot: int, key: String, default: Variant) -> Variant:
	if slot < 0 or slot >= build.skills.size():
		return default
	return build.skills[slot].get("inputs", {}).get(key, default)


## Adds the base buff of the skill to result["global_mods"] (they reach the character through BuildMods.global_store).
static func apply(build: Node, slot: int, ability: Dictionary, result: Dictionary) -> void:
	var model: Dictionary = find(str(ability.get("abilityName", "")))
	if model.is_empty():
		return
	var active_input: Dictionary = model.get("active_input", {})
	var active: bool = false
	if not active_input.is_empty():
		result["inputs"].append(active_input)
		active = bool(input_value(build, slot, str(active_input["key"]), active_input.get("default", false)))
	var k: float = float(model.get("active_multiplier", 1.0)) if active else 1.0
	var x: float = ability_property(build, str(model.get("ability_id", "")), int(model.get("effect_index", -1)))
	var m: float = 1.0 + x
	var mode: String = "усиленный каст" if active else "пассивная аура"
	var suffix: String = " ×M %s" % LE.fmt_num(m) if x != 0.0 else ""
	var out: Array = result["global_mods"]

	for entry: Dictionary in model.get("stats", []):
		var mod: StatMod = _make(entry, float(entry["value"]) * k * m,
			"%s, %s%s" % [str(entry.get("label", "базовый бафф")), mode, suffix])
		if mod != null:
			out.append(mod)

	var lists: Dictionary = model.get("tree_lists", {})
	if not lists.is_empty():
		var list_target: String = str(lists.get("active" if active else "passive", ""))
		var tree: Dictionary = build.skills[slot].get("tree", {})
		var effects: Dictionary = GameData.skill_effects(str(ability.get("skillTree", "")))
		for node_id: Variant in tree:
			var points: int = int(tree[node_id])
			var node: Dictionary = effects.get(int(node_id), {})
			if points <= 0 or node.is_empty():
				continue
			var title: String = str(node.get("name", ""))
			for effect: Dictionary in node.get("effects", []):
				if str(effect.get("target", "")) != list_target or effect.get("op") != "add_stat":
					continue
				var mod: StatMod = BuildMods.stat_from_effect(effect.get("stat", {}), points,
					"Узел «%s» ×%d, %s%s" % [title, points, mode, suffix])
				if mod == null:
					result["notes"].append("Узел «%s»: стат ауры (%s) — не учитывается" % [title, BuildMods._effect_label(effect)])
					continue
				out.append(mod.scaled(m))

	for entry: Dictionary in model.get("ability_properties", []):
		if bool(entry.get("active_only", false)) and not active:
			continue
		var v: float = ability_property(build, str(model.get("ability_id", "")), int(entry["index"]))
		if v == 0.0:
			continue
		var factor: float = k if bool(entry.get("active_k", false)) else 1.0
		var mod: StatMod = _make(entry, v * factor * m, "%s, %s%s" % [str(entry.get("label", "")), mode, suffix])
		if mod != null:
			out.append(mod)


## Sum of the AbilityPropertyStat values (stat kind "ability_property") of the passives for `ability_id` and property `index`.
static func ability_property(build: Node, ability_id: String, index: int) -> float:
	if ability_id == "" or index < 0:
		return 0.0
	var tree: Dictionary = GameData.get_passive_tree(build.class_id)
	var effects: Dictionary = GameData.passive_effects(str(tree.get("treeID", "")))
	var total: float = 0.0
	for node_id: Variant in build.passives:
		var points: int = int(build.passives[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		for effect: Dictionary in node.get("effects", []):
			var stat: Variant = effect.get("stat")
			if not stat is Dictionary or str(stat.get("kind", "")) != "ability_property":
				continue
			if str(stat.get("abilityID", "")) != ability_id or int(str(stat.get("abilityPropertyIndex", "-1"))) != index:
				continue
			if points < int(effect.get("minPoints", 0)):
				continue
			total += BuildMods.eval_value(stat.get("value"), points)
	return total


static func _make(entry: Dictionary, value: float, source: String) -> StatMod:
	var property: int = GameData.sp_id(str(entry.get("stat", "")))
	if property < 0:
		return null
	return StatMod.make(property, str(entry.get("mod", "added")), value, LE.tag_mask(str(entry.get("tags", ""))), source)


# --- passive effects aimed at ability mutators (docs/ENGINE.md §9.7) -----------------------

## Mutators of the skill tree (skill_node_effects.json `mutators`); parsed once, only when a passive needs it.
static func tree_mutators(tree_id: String) -> Array:
	if not _tree_loaded:
		_tree_loaded = true
		var path: String = ProjectSettings.globalize_path("res://").path_join("../research/data/game/skill_node_effects.json").simplify_path()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if parsed is Array:
			for tree: Dictionary in parsed:
				_tree_mutators[str(tree.get("treeID", ""))] = tree.get("mutators", [])
	return _tree_mutators.get(tree_id, [])


## True if the mutator class (e.g. "LungeMutator") belongs to the ability: the mutator list of its skill tree, its own
## mutator class, or the ability name ("Lunge" ↔ "LungeMutator").
static func owns_mutator(ability: Dictionary, mutator: String) -> bool:
	if ability.is_empty() or mutator == "":
		return false
	if tree_mutators(str(ability.get("skillTree", ""))).has(mutator):
		return true
	var own: Variant = ability.get("mutator")
	if own is Dictionary and str(own.get("class", "")) == mutator:
		return true
	return mutator.trim_suffix("Mutator") == str(ability.get("name", ""))


## Parts ("A & B") of an effect target owned by the ability, joined back with " & "; "" if there are none.
static func owned_target(ability: Dictionary, target: String) -> String:
	var parts: PackedStringArray = []
	for part: String in target.split(" & "):
		var trimmed: String = part.strip_edges()
		if trimmed.contains(".") and owns_mutator(ability, trimmed.get_slice(".", 0)):
			parts.append(trimmed)
	return " & ".join(parts)


## Name of the first skill on the bar that owns some part of the target ("" if none).
static func equipped_owner(build: Node, target: String) -> String:
	for skill: Dictionary in build.skills:
		var ability: Dictionary = GameData.get_ability(str(skill.get("ability", "")))
		if not ability.is_empty() and owned_target(ability, target) != "":
			return GameData.display_name(ability)
	return ""
