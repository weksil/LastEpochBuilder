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
		var path: String = MODELS_PATH
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
## Model keys: see docs/ENGINE.md §9.7. Entry keys (stats[] and ability_properties[]): active_only / passive_only (mode of the
## model's active_input), active_value (explicit value in the active mode instead of value × active_multiplier), when_input
## (entry applies only while that input is on), per_input (value × input), no_m (not multiplied by M = 1 + effect_index property).
static func apply(build: Node, slot: int, ability: Dictionary, result: Dictionary) -> void:
	var model: Dictionary = find(str(ability.get("abilityName", "")))
	if model.is_empty():
		return
	var active_input: Dictionary = model.get("active_input", {})
	var active: bool = false
	if not active_input.is_empty():
		_declare_input(result, active_input)
		active = bool(input_value(build, slot, str(active_input["key"]), active_input.get("default", false)))
	var k: float = float(model.get("active_multiplier", 1.0)) if active else 1.0
	var ability_index: int = int(ability.get("abilityIDEnum", {}).get("value", 0)) if ability.get("abilityIDEnum") is Dictionary else 0
	var x: float = ability_property(build, str(model.get("ability_id", "")), ability_index, int(model.get("effect_index", -1)))
	var m: float = 1.0 + x
	var mode: String = LE.t(str(model.get("mode_active", "active mode"))) if active else LE.t(str(model.get("mode_passive", "always on")))
	var suffix: String = " ×M %s" % LE.fmt_num(m) if x != 0.0 else ""
	var out: Array = result["global_mods"]

	for entry: Dictionary in model.get("stats", []):
		if entry.has("off_with_component") and _has_component(result, str(entry["off_with_component"])):
			continue
		var base: float = float(entry["value"]) * k
		if active and entry.has("active_value"):
			base = float(entry["active_value"])
		var mod: StatMod = _entry_mod(build, slot, entry, base, active, m, "%s, %s%s" % [LE.t(str(entry.get("label", "base buff"))), mode, suffix], result)
		if mod != null and entry.has("less_by_property"):
			var less: float = ability_property(build, str(model.get("ability_id", "")), ability_index, int(entry["less_by_property"]))
			if less > 0.0:
				mod = mod.scaled(less_factor(less))
				mod.source += LE.t(" × (1 − %s: weaker activation damage reduction)") % LE.fmt_num(less)
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
					LE.t("Node \"%s\" ×%d, %s%s") % [title, points, mode, suffix])
				if mod == null:
					result["notes"].append(LE.t("Node \"%s\": aura stat (%s) — not counted") % [title, BuildMods._effect_label(effect)])
					continue
				out.append(mod.scaled(m))

	for entry: Dictionary in model.get("ability_properties", []):
		var v: float = ability_property(build, str(model.get("ability_id", "")), ability_index, int(entry["index"]))
		if v == 0.0:
			continue
		var factor: float = k if bool(entry.get("active_k", false)) else 1.0
		var mod: StatMod = _entry_mod(build, slot, entry, v * factor, active, m, "%s, %s%s" % [LE.t(str(entry.get("label", ""))), mode, suffix], result)
		if mod != null:
			out.append(mod)



## Factor of the activation damage reduction for an AbilityProperty value `less` (SigilsOfHopeActiveMutator.Mutate: 1 when it
## is <= 0, else 1 - less).
static func less_factor(less: float) -> float:
	return 1.0 if less <= 0.0 else 1.0 - less


## True if the skill's own tree adds `ability` as a component (result["components"] of BuildMods.skill_store).
static func _has_component(result: Dictionary, ability: String) -> bool:
	for comp: Variant in result.get("components", []):
		if comp is Dictionary and str(comp.get("ability", "")) == ability:
			return true
	return false

## StatMod of one model entry for the current mode, null if the entry is off (wrong mode, input off, unknown stat).
static func _entry_mod(build: Node, slot: int, entry: Dictionary, base: float, active: bool, m: float, source: String, result: Dictionary) -> StatMod:
	if bool(entry.get("active_only", false)) and not active:
		return null
	if bool(entry.get("passive_only", false)) and active:
		return null
	var when_input: Dictionary = entry.get("when_input", {})
	if not when_input.is_empty():
		_declare_input(result, when_input)
		if not bool(input_value(build, slot, str(when_input["key"]), when_input.get("default", false))):
			return null
	var value: float = base
	var per_input: Dictionary = entry.get("per_input", {})
	if not per_input.is_empty():
		_declare_input(result, per_input)
		var count: float = float(input_value(build, slot, str(per_input["key"]), per_input.get("default", 0)))
		value *= count
		source += " × %s %s" % [str(per_input.get("short", per_input["key"])), LE.fmt_num(count)]
	if not bool(entry.get("no_m", false)):
		value *= m
	return _make(entry, value, source)


## Declares an input of the model once per key (SkillCalc shows it in the skill's inputs).
static func _declare_input(result: Dictionary, input: Dictionary) -> void:
	for existing: Dictionary in result["inputs"]:
		if existing.get("key") == input.get("key"):
			return
	result["inputs"].append(input)


## Sum of the AbilityProperty values for `ability_id` (its index `ability_index` in the ability list) and property `index`:
## passives, mastery bonus, item and idol affixes and unique effects — the same sum the game's mutators read (07d §AbilityProperty).
static func ability_property(build: Node, ability_id: String, ability_index: int, index: int) -> float:
	if ability_id == "" or index < 0:
		return 0.0
	return float(ShadowCalc.ability_property(build, ability_id, ability_index, index)["value"])


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
		var path: String = LE.game_data_dir().path_join("skill_node_effects.json")
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
