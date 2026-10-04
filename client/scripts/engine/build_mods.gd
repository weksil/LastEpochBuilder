class_name BuildMods

## Collects StatMods from every build source (docs/ENGINE.md §5).

const STAT_KINDS: Array[String] = ["added", "increased", "more", "quotient"]
const ATTRIBUTE_NAMES: Array[String] = ["Strength", "Vitality", "Intelligence", "Dexterity", "Attunement"]
const BUFF_SKILLS: GDScript = preload("res://scripts/engine/buff_skills.gd")  # class_name BuffSkills
const SLOTS: Array[String] = ["helmet", "body", "belt", "boots", "gloves", "weapon", "offhand", "amulet", "ring1", "ring2", "relic"]


## {store: StatStore, notes: Array[String]} — all character-wide mods.
static func global_store(build: Node) -> Dictionary:
	var g: Dictionary = _store_without_skill_buffs(build)
	var store: StatStore = g["store"]
	var notes: Array[String] = g["notes"]
	_add_skill_buffs(build, store)
	UniqueEffects.add_notes(build, notes)
	return {"store": store, "notes": notes}


## Everything of global_store except the buffs of the equipped skills (those are computed on top of this store).
static func _store_without_skill_buffs(build: Node) -> Dictionary:
	var store := StatStore.new()
	var notes: Array[String] = []
	_add_class_base(build, store)
	_add_passives(build, store, notes)
	for slot: String in build.items:
		if SLOTS.has(slot) or IdolGrid.is_idol_key(slot):
			store.add_all(ItemMods.item_mods(slot, build.items[slot]))
	preload("res://scripts/engine/altar_mods.gd").apply(build, store, notes)
	_add_blessings(build, store, notes)
	_add_set_bonuses(build, store, notes)
	UniqueEffects.apply_global(build, store, notes, "pre")
	_add_attributes(store, notes)
	_add_player_ailments(build, store)
	_add_passives(build, store, notes, "post")
	UniqueEffects.apply_global(build, store, notes, "post")
	return {"store": store, "notes": notes}


const BUFF_SOURCE_PREFIX: String = "Skill \"%s\" (buff): "


## Buffs of the equipped skills on the character (docs/ENGINE.md §9.7): scope-global models of the skill tree and the
## base buffs of buff_skill_models.json. Each slot is computed by skill_store (it never calls global_store); mods are
## collected first and added together, so slot order does not matter. A skill counts once per ability and only while its
## input `buff_active` (default on) is on.
static func _add_skill_buffs(build: Node, store: StatStore) -> void:
	var collected: Array[StatMod] = []
	for entry: Dictionary in skill_buffs(build, store, true):
		collected.append_array(entry["mods"])
	store.add_all(collected)


## Read-only list of the equipped skills and their buffs on the character, one entry per distinct ability (the first slot
## that holds it): {slot, ability_name, active, toggle, mods: Array[StatMod]}. `active` is the input `buff_active`
## (default on), `toggle` tells that the skill declares that input (it has buffs to switch). A switched-off skill lists the mods it would give when on. `global` is the store the
## skills are computed over (null = the character store without skill buffs); only_active = true skips computing the
## mods of switched-off skills (their entries have empty mods). Mod sources carry the BUFF_SOURCE_PREFIX.
static func skill_buffs(build: Node, global: StatStore = null, only_active: bool = false) -> Array[Dictionary]:
	var parent: StatStore = global
	if parent == null:
		parent = _store_without_skill_buffs(build)["store"]
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for slot: int in range(build.skills.size()):
		var skill: Dictionary = build.skills[slot]
		var ability: Dictionary = GameData.get_ability(str(skill.get("ability", "")))
		if ability.is_empty() or seen.has(str(skill["ability"])):
			continue
		seen[str(skill["ability"])] = true
		var active: bool = bool(skill.get("inputs", {}).get("buff_active", true))
		var mods: Array[StatMod] = []
		var toggle: bool = false
		if active or not only_active:
			# a switched-off skill is shown as it would be when switched on (the skill models drop their global mods
			# while `buff_active` is off); the input is restored right away
			var inputs: Dictionary = skill.get("inputs", {})
			if not active:
				inputs["buff_active"] = true
			var s: Dictionary = skill_store(build, slot, parent)
			if not active:
				inputs["buff_active"] = false
			var prefix: String = LE.t(BUFF_SOURCE_PREFIX) % GameData.display_name(ability)
			for mod: StatMod in s["global_mods"]:
				mod.source = prefix + mod.source
				mods.append(mod)
			for inp: Dictionary in s["inputs"]:
				if inp.get("key") == "buff_active":
					toggle = true
		result.append({"slot": slot, "ability_name": GameData.display_name(ability), "active": active, "toggle": toggle, "mods": mods})
	return result


## "CriticalMultiplier" -> "Critical Multiplier".
static func _split_camel(text: String) -> String:
	var result: String = ""
	for i: int in range(text.length()):
		var c: String = text[i]
		if i > 0 and c != c.to_lower() and text[i - 1] == text[i - 1].to_lower() and text[i - 1] != " ":
			result += " "
		result += c
	return result


## One readable line for a buff mod, e.g. "+15% inc Damage (Fire, Spell) — Holy Aura": value, property, tags, source
## without the skill prefix.
static func describe_mod(mod: StatMod) -> String:
	var value: String = ""
	if mod.added != 0.0:
		value = ("+" if mod.added > 0.0 else "") + LE.fmt_num(mod.added)
	elif mod.increased != 0.0:
		value = ("+" if mod.increased > 0.0 else "") + LE.fmt_pct(mod.increased) + " inc"
	elif not mod.more.is_empty():
		var prod: float = 1.0
		for m: float in mod.more:
			prod *= 1.0 + m
		value = "×" + LE.fmt_num(prod) + " more"
	else:
		value = "0"
	var prop: String = _split_camel(GameData.sp_name(mod.property))
	if prop == "":
		prop = "#%d" % mod.property
	var tag_names: PackedStringArray = []
	for i: int in range(LE.TAG_NAMES.size()):
		if mod.tags & (1 << i) != 0:
			tag_names.append(LE.TAG_NAMES[i])
	var text: String = "%s %s" % [value, prop]
	if not tag_names.is_empty():
		text += " (%s)" % ", ".join(tag_names)
	var source: String = mod.source
	var prefix_parts: PackedStringArray = LE.t(BUFF_SOURCE_PREFIX).split("%s")
	if prefix_parts.size() == 2 and source.begins_with(prefix_parts[0]):
		var cut: int = source.find(prefix_parts[1], prefix_parts[0].length())
		if cut >= 0:
			source = source.substr(cut + prefix_parts[1].length())
	if source != "":
		text += " — " + source
	return text


## Skill-local store (parent = global store) plus mutator-field totals. Scope-global mods are returned in
## result["global_mods"] (not in the skill store): global_store puts them on the character, and the skill sees them
## through its parent.
static func skill_store(build: Node, slot: int, global: StatStore) -> Dictionary:
	var store := StatStore.new()
	store.parent = global
	var result: Dictionary = {
		"store": store, "notes": [] as Array[String],
		"use_speed_inc": 0.0, "use_speed_more": 1.0, "mana_inc": 0.0, "mana_added": 0.0,
		"mana_sources": [] as Array[String], "conversions": [],
		# §9: field models of the skill tree
		"params": {}, "triggers": [], "components": [], "minion_mods": [] as Array[StatMod], "component_mods": {},
		"flags": [] as Array[String], "cooldown": {}, "cooldown_base": {}, "inputs": [] as Array[Dictionary],
		"global_mods": [] as Array[StatMod], "ability_name": "",
		"ctx": {"build": build, "store": store, "slot": slot, "item_slot": ""},
	}
	if slot < 0 or slot >= build.skills.size():
		return result
	var skill: Dictionary = build.skills[slot]
	var ability: Dictionary = GameData.get_ability(str(skill.get("ability", "")))
	if ability.is_empty():
		return result

	result["ability_name"] = str(ability.get("abilityName", ""))
	var effects: Dictionary = GameData.skill_effects(str(ability.get("skillTree", "")))
	var tree: Dictionary = skill.get("tree", {})
	for node_id: Variant in tree:
		var points: int = int(tree[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		_add_skill_node(node, points, result)

	_add_skill_passives(build, ability, result)
	BUFF_SKILLS.apply(build, slot, ability, result)
	_add_ability_scaling(build, ability, global, store, result["conversions"])
	UniqueEffects.apply_skill(build, ability, result)
	_declare_buff_input(result)
	return result


## Input "buff active" for a skill that has global-scope mods (global_store reads it from Build.skills[slot].inputs).
static func _declare_buff_input(result: Dictionary) -> void:
	if result["global_mods"].is_empty() and not result.has("has_global"):
		return
	for inp: Dictionary in result["inputs"]:
		if inp.get("key") == "buff_active":
			return
	result["inputs"].append({"key": "buff_active", "label": LE.t("Skill buff active"), "default": true})


# --- 5.1.5 blessings -------------------------------------------------------

static func _add_blessings(build: Node, store: StatStore, notes: Array[String]) -> void:
	for timeline_id: Variant in build.blessings:
		var blessing_data: Dictionary = build.blessings[timeline_id]
		var blessing_id: int = int(blessing_data.get("id", -1))
		var roll: int = int(blessing_data.get("roll", 0))
		if blessing_id < 0:
			continue
		var blessing: Dictionary = GameData.blessing(blessing_id)
		if blessing.is_empty():
			continue
		var display_name: String = str(blessing.get("displayName", str(blessing_id)))
		var implicits: Array = blessing.get("implicits", [])
		for implicit: Dictionary in implicits:
			var property: int = int(implicit.get("property", 0))
			# Skip property 104 (IncreasedDropRate)
			if property == 104:
				continue
			var modType: String = str(implicit.get("modType", "ADDED"))
			var value: float = float(implicit.get("value", 0.0))
			var maxValue: float = float(implicit.get("maxValue", value))
			var rounding: String = str(implicit.get("rounding", "Integer"))
			var rolled_value: float = AffixMath.roll_value(value, maxValue, rounding, modType, roll, 0.0)
			var tags: int = int(implicit.get("tags", 0))
			var specialTag: int = int(implicit.get("specialTag", 0))
			var extraTag: int = int(implicit.get("extraTag", 0))
			var mod: StatMod = StatMod.make(property, modType.to_lower(), rolled_value, tags,
				LE.t("Blessing \"%s\"") % display_name, specialTag, extraTag)
			store.add(mod)


# --- 5.1 class base ---------------------------------------------------------

static func _add_class_base(build: Node, store: StatStore) -> void:
	var class_data: Dictionary = GameData.get_class_data(build.class_id)
	for entry: Dictionary in class_data.get("levelMods", []):
		var value: float = float(entry.get("base", 0.0)) + float(entry.get("perLevel", 0.0)) * build.level
		if value != 0.0:
			store.add(StatMod.make(int(entry["property"]), str(entry["modType"]).to_lower(), value,
				int(entry.get("tags", 0)), LE.t("Class base (level %d)") % build.level))
	for entry: Dictionary in GameData.hidden_base_mods:
		store.add(StatMod.make(int(entry["property"]), str(entry["modType"]).to_lower(), float(entry["value"]),
			int(entry.get("tags", 0)), LE.t("Hidden character base")))


# --- 5.2 passives -------------------------------------------------------------

## phase "pre": plain stats and models without store-dependent sources; "post": models read after items and attributes
## (EffectModels.phase). Effects without a model are listed in the notes once, in the "pre" phase.
static func _add_passives(build: Node, store: StatStore, notes: Array[String], phase: String = "pre") -> void:
	var tree: Dictionary = GameData.get_passive_tree(build.class_id)
	var effects: Dictionary = GameData.passive_effects(str(tree.get("treeID", "")))
	var ctx: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": ""}
	for node_id: Variant in build.passives:
		var points: int = int(build.passives[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		var title: String = GameData.display_name(node)
		var source: String = LE.t("Passive \"%s\" ×%d") % [title, points]
		for effect: Dictionary in node.get("effects", []):
			if points < int(effect.get("minPoints", 0)):
				continue
			var target: String = str(effect.get("target", ""))
			if target == "CharacterMutator.stats" and effect.get("op") == "add_stat":
				if phase != "pre":
					continue
				var mod: StatMod = stat_from_effect(effect.get("stat", {}), points, source)
				if mod != null:
					store.add(mod)
				else:
					_passive_unmodelled(notes, title, effect)
				continue
			if not target.begins_with("CharacterMutator.") and BUFF_SKILLS.equipped_owner(build, target) != "":
				continue  # effect on the mutator of an equipped skill: applied in skill_store (_add_skill_passives)
			var model: Dictionary = _passive_model(target)
			if model.is_empty():
				if phase == "pre":
					_passive_unmodelled(notes, title, effect)
				continue
			if EffectModels.phase(model) != phase:
				continue
			_apply_passive_model(model, effect, target, points, source, title, store, notes, ctx)


## Passive effects aimed at the mutators of this ability (target "LungeMutator.field" ↔ ability, BUFF_SKILLS.owns_mutator):
## through the same field models as skill tree nodes (docs/ENGINE.md §9.7).
static func _add_skill_passives(build: Node, ability: Dictionary, result: Dictionary) -> void:
	var tree: Dictionary = GameData.get_passive_tree(build.class_id)
	var effects: Dictionary = GameData.passive_effects(str(tree.get("treeID", "")))
	for node_id: Variant in build.passives:
		var points: int = int(build.passives[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		var title: String = GameData.display_name(node)
		var source: String = LE.t("Passive \"%s\" ×%d") % [title, points]
		for effect: Dictionary in node.get("effects", []):
			var target: String = str(effect.get("target", ""))
			if points < int(effect.get("minPoints", 0)) or target.begins_with("CharacterMutator."):
				continue
			var owned: String = BUFF_SKILLS.owned_target(ability, target)
			if owned == "":
				continue
			if effect.get("op") == "add_stat":
				if not _apply_list_effect(effect, owned, points, source, title, result):
					result["notes"].append(LE.t("Passive \"%s\": %s — skill mechanic, not counted yet") % [title, _effect_label(effect)])
				continue
			var v: float = eval_value(effect.get("value"), points) if effect.has("value") else 0.0
			var rule: Dictionary = _conversion_rule(owned)
			if not rule.is_empty():
				result["conversions"].append({"rule": rule, "value": v, "node": title, "points": points})
			elif not _apply_field_models(owned, v, source, title, result):
				result["notes"].append(LE.t("Passive \"%s\": %s — skill mechanic, not counted yet") % [title, _effect_label(effect)])


## First part of the target ("A & B") that has a field model.
static func _passive_model(target: String) -> Dictionary:
	for part: String in target.split(" & "):
		var model: Dictionary = FieldModels.find(part.strip_edges())
		if not model.is_empty():
			return model
	return {}


static func _passive_unmodelled(notes: Array[String], title: String, effect: Dictionary) -> void:
	notes.append(LE.t("Passive \"%s\": %s — not counted") % [title, _effect_label(effect)])


## "global" / "minion" for the model's scope, "" if it cannot be applied to the character (component, ability-only field).
static func _passive_scope(model: Dictionary, target: String) -> String:
	var scope: String = str(model.get("scope", ""))
	if scope == "":
		return "global" if target.begins_with("CharacterMutator.") else ""
	if scope == "global" or scope == "skill":
		return "global"
	return scope if scope == "minion" else ""


## Base type of the main-hand or off-hand item is one of `types` (StatWithWeaponRequirement, EquipmentType).
static func _holds_weapon_type(build: Node, types: Array[int]) -> bool:
	for slot: String in ["weapon", "offhand"]:
		if types.has(int(build.items.get(slot, {}).get("base", -1))):
			return true
	return false


## Minion stats from passives reach minions through the Minion tag (07d §1.2).
static func _passive_add(store: StatStore, mod: StatMod, scope: String) -> void:
	if scope == "minion" and (mod.tags & LE.MINION) == 0:
		mod.tags |= LE.MINION
	store.add(mod)


static func _apply_passive_model(model: Dictionary, effect: Dictionary, target: String, points: int, source: String, title: String,
		store: StatStore, notes: Array[String], ctx: Dictionary) -> void:
	var kind: String = str(model.get("kind", ""))
	var is_stat_effect: bool = effect.get("op") == "add_stat"
	var v: float = eval_value(effect.get("value"), points) if effect.has("value") else 0.0
	match kind:
		"stat_list", "stat", "cooldown":
			var scope: String = _passive_scope(model, target)
			var mod: StatMod = null
			var weapon_types: Array[int] = []
			if kind == "stat_list" and is_stat_effect:
				var stat: Dictionary = effect.get("stat", {})
				if str(stat.get("wrapper", "")).begins_with("StatWithWeaponRequirement") and stat.get("stat") is Dictionary:
					var other: Array = stat.get("other", [])
					for o: Variant in other:
						if str(o).begins_with("EquipmentType="):
							weapon_types.append(int(str(o).get_slice("=", 1)))
						elif not str(o).begins_with("Boolean="):
							# WeaponRequirementType / animation type: semantics unknown, not applied
							notes.append(LE.t("Passive \"%s\": stats with a specific weapon (%s) — not counted") % [title, _effect_label(effect)])
							return
					stat = stat["stat"]
				mod = stat_from_effect(stat, points, source)
			elif kind == "stat" and not is_stat_effect:
				mod = EffectModels.make_mod(model, v, ctx, source)
			elif kind == "cooldown" and not is_stat_effect and str(model.get("cooldown", "")) == "recovery_increased" and scope == "global":
				mod = StatMod.make(LE.CDR, "increased", v, 0, source)
			if mod == null or scope == "" or (kind == "cooldown" and not target.begins_with("CharacterMutator.")):
				# ability-specific cooldown/field or an unsupported stat: left to the skill that owns the mutator
				_passive_unmodelled(notes, title, effect)
				return
			var reason: String = EffectModels.blocked(model, ctx)
			if reason != "":
				notes.append(LE.t("Passive \"%s\" — counted when: %s") % [title, reason])
				return
			if not weapon_types.is_empty() and not _holds_weapon_type(ctx["build"], weapon_types):
				var names: PackedStringArray = []
				for t: int in weapon_types:
					names.append(GameData.display_name(GameData.item_base(t)))
				notes.append(LE.t("Passive \"%s\" — counted when: holding %s") % [title, " / ".join(names)])
				return
			if kind == "stat_list":
				if model.has("per"):
					if str(model["per"]) == "points":
						_passive_unmodelled(notes, title, effect)
						return
					var n: float = EffectModels.source(str(model["per"]), ctx, model)
					if model.has("src_max"):
						n = minf(n, float(model["src_max"]))
					mod = mod.scaled(n)
					mod.source += " × %s" % LE.fmt_num(n)
				if model.has("note"):
					mod.source += " — " + LE.t(str(model["note"]))
			_passive_add(store, mod, scope)
		"flag", "param", "resource":
			var text: String = LE.t(str(model.get("text", model.get("label", model.get("param", model.get("resource", ""))))))
			if kind != "flag" and effect.has("value"):
				text += ": %s" % LE.fmt_num(v)
			var line: String = LE.t("Passive \"%s\": %s") % [title, text]
			if not notes.has(line):
				notes.append(line)
		_:
			_passive_unmodelled(notes, title, effect)


# --- 5.4.2 uniques and sets ------------------------------------------------------

const LEGENDS_ENTWINED: int = 423  # "Counts as a part of every equipped item set"
const PLAYER_AILMENTS: Dictionary = {"haste": 33, "frenzy": 34}


## Set piece counts: setID -> distinct equipped uniqueIDs of the set + Legends Entwined (07d §2.3).
static func set_counts(build: Node) -> Dictionary:
	var members: Dictionary = {}  # setID -> {uniqueID: true}
	var entwined: int = 0
	for slot: String in build.items:
		var item: Dictionary = build.items[slot]
		if not item.has("unique"):
			continue
		var uid: int = int(item["unique"])
		if uid == LEGENDS_ENTWINED:
			entwined += 1
		var u: Dictionary = GameData.unique(uid)
		if u.get("isSetItem", false) and u.get("setID") != null:
			if not members.has(int(u["setID"])):
				members[int(u["setID"])] = {}
			members[int(u["setID"])][uid] = true
	var counts: Dictionary = {}
	for set_id: int in members:
		counts[set_id] = members[set_id].size() + entwined
	return counts


## Number of complete sets (all pieces of the set counted), used by Legends Entwined (PP 566–568).
static func complete_sets(build: Node) -> int:
	var counts: Dictionary = set_counts(build)
	var complete: int = 0
	for set_id: int in counts:
		if counts[set_id] >= GameData.set_data(set_id).get("items", []).size():
			complete += 1
	return complete


## Set bonuses: active if setRequirement <= set_counts() (07d §2.3).
static func _add_set_bonuses(build: Node, store: StatStore, notes: Array[String]) -> void:
	var counts: Dictionary = set_counts(build)
	for set_id: int in counts:
		var st: Dictionary = GameData.set_data(set_id)
		var count: int = counts[set_id]
		var source: String = LE.t("Set \"%s\" (%d items)") % [str(st.get("setName", set_id)), count]
		for bonus: Dictionary in st.get("bonuses", []):
			if int(bonus.get("setRequirement", 99)) > count:
				continue
			var prop_id: int = int(bonus.get("property", 0))
			if prop_id == LE.PLAYER_PROPERTY or prop_id == LE.ABILITY_PROPERTY:
				notes.append(LE.t("%s: special bonus (%s) — not counted") % [source, str(bonus.get("propertyName", prop_id))])
				continue
			store.add(StatMod.make(prop_id, str(bonus.get("modType", "ADDED")).to_lower(),
				AffixMath.fixed_value(float(bonus.get("value", 0.0)), str(bonus.get("rounding", "Hundredth")), str(bonus.get("modType", "ADDED"))),
				int(bonus.get("tags", 0)), source, int(bonus.get("specialTag", 0)), int(bonus.get("extraTag", 0))))


## Haste / Frenzy on the player (Conditions tab): ailment buffs × (1 + increased effect of the ailment on you, SP 120).
static func _add_player_ailments(build: Node, store: StatStore) -> void:
	for key: String in PLAYER_AILMENTS:
		if not build.player_state.get(key, false):
			continue
		var id: int = PLAYER_AILMENTS[key]
		var ail: Dictionary = GameData.ailment(id)
		var effect: float = 1.0 + store.query(LE.EFFECT_OF_AILMENT_ON_YOU, 0, id).increased
		for buff: Dictionary in ail.get("buffs", []):
			var mod: StatMod = stat_from_record(buff, LE.t("%s on you (effect ×%s)") % [str(ail.get("name", key)), LE.fmt_num(effect)])
			store.add(mod.scaled(effect))


# --- 5.3 attributes -----------------------------------------------------------

static func _add_attributes(store: StatStore, notes: Array[String]) -> void:
	var all_attr: float = _sum_added_any_tags(store, LE.ALL_ATTRIBUTES)
	for attr: Dictionary in GameData.attributes:
		var index: int = int(attr.get("attribute", 0))
		var n: int = LE.round_half_even(_sum_added_any_tags(store, int(attr["statProperty"])) + all_attr)
		if n == 0:
			continue
		for per_point: Dictionary in attr.get("perPoint", []):
			var mod: StatMod = stat_from_record(per_point, "%s ×%d" % [LE.t(ATTRIBUTE_NAMES[index]), n])
			store.add(mod.scaled(float(n)))


static func _sum_added_any_tags(store: StatStore, property: int) -> float:
	var total: float = 0.0
	for mod: StatMod in store.all_mods():
		if mod.property == property:
			total += mod.added
	return total


# --- 5.5 skill tree -----------------------------------------------------------

static func _add_skill_node(node: Dictionary, points: int, result: Dictionary) -> void:
	var store: StatStore = result["store"]
	var notes: Array[String] = result["notes"]
	var title: String = str(node.get("name", ""))
	var source: String = LE.t("Node \"%s\" ×%d") % [title, points]
	for effect: Dictionary in node.get("effects", []):
		var target: String = str(effect.get("target", ""))
		var op: String = str(effect.get("op", ""))
		if op == "add_stat" and (_is_unconditional_temp(target) or target == "CharacterMutator.stats"):
			var mod: StatMod = stat_from_effect(effect.get("stat", {}), points, source)
			if mod != null:
				store.add(mod)
				continue
		elif op == "automatic_node_stat":
			var auto_mod: StatMod = _automatic_stat(effect, points, source)
			if auto_mod != null:
				store.add(auto_mod)
				continue
		elif op == "add_stat":
			if _apply_list_effect(effect, target, points, source, title, result):
				continue
		elif op == "cooldown":
			for key: String in effect.get("args", {}):
				result["cooldown_base"][key] = eval_value(effect["args"][key], points)
			continue
		elif op == "" and effect.has("value") and target.contains("."):
			var field: String = target.get_slice(".", target.get_slice_count(".") - 1)
			var v: float = eval_value(effect["value"], points)
			var rule: Dictionary = _conversion_rule(target)
			if not rule.is_empty():
				result["conversions"].append({"rule": rule, "value": v, "node": title, "points": points})
				continue
			if _apply_field_models(target, v, source, title, result):
				continue
			match field:
				"increasedCastSpeed", "increasedAttackSpeed":
					result["use_speed_inc"] += v
					continue
				"moreCastSpeed", "moreAttackSpeed":
					result["use_speed_more"] *= 1.0 + v
					continue
				"increasedManaCost":
					result["mana_inc"] += v
					continue
				"addedManaCost":
					result["mana_added"] += v
					continue
		notes.append(LE.t("Node \"%s\": %s — skill mechanic, not counted yet") % [title, _effect_label(effect)])


## Field effect through its models (client/data/field_models.json, §9.1); false if no part of the target has a model.
static func _apply_field_models(target: String, v: float, source: String, title: String, result: Dictionary) -> bool:
	var parts: PackedStringArray = target.split(" & ")
	var any: bool = false
	var done: Dictionary = {}
	var skill_scoped: Dictionary = {}
	for part: String in parts:
		var m: Dictionary = FieldModels.find(part.strip_edges())
		if not m.is_empty() and str(m.get("scope", "skill")) == "skill":
			skill_scoped[_model_signature(m)] = true
	for part: String in parts:
		var model: Dictionary = FieldModels.find(part.strip_edges())
		if model.is_empty():
			continue
		any = true
		var sig: String = _model_signature(model)
		# the same effect written into the skill and its sub-ability mutators counts once
		if done.has(sig) or (str(model.get("scope", "skill")) != "skill" and skill_scoped.has(sig)):
			continue
		done[sig] = true
		_apply_model(model, v, source, title, result)
	return any


static func _model_signature(m: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [m.get("kind", "stat"), m.get("stat", ""), m.get("mod", ""), m.get("tags", ""),
		m.get("param", ""), m.get("ability", ""), str(m.get("when", []))]


## A scope-global model was met (even if its condition is off): the skill gets the input «buff active».
static func _note_global_scope(model: Dictionary, result: Dictionary) -> void:
	if str(model.get("scope", "skill")) == "global":
		result["has_global"] = true


static func _add_scoped(mod: StatMod, scope: String, result: Dictionary) -> void:
	if scope.begins_with("component:"):
		var comp: String = scope.get_slice(":", 1)
		if not result["component_mods"].has(comp):
			result["component_mods"][comp] = [] as Array[StatMod]
		result["component_mods"][comp].append(mod)
	elif scope == "minion":
		result["minion_mods"].append(mod)
	elif scope == "global":
		result["global_mods"].append(mod)
	else:
		result["store"].add(mod)


## Routes one model (§9.1) into the skill result.
static func _apply_model(model: Dictionary, v: float, source: String, title: String, result: Dictionary) -> void:
	var ctx: Dictionary = result["ctx"]
	_note_global_scope(model, result)
	for inp: Dictionary in EffectModels.inputs(model):
		result["inputs"].append(inp)
	var reason: String = EffectModels.blocked(model, ctx)
	if reason != "":
		result["notes"].append(LE.t("Node \"%s\" — counted when: %s") % [title, reason])
		return
	var x: float = float(EffectModels.value(model, v, ctx)["x"])
	match str(model.get("kind", "stat")):
		"stat":
			var mod: StatMod = EffectModels.make_mod(model, v, ctx, source)
			if mod != null:
				_add_scoped(mod, str(model.get("scope", "skill")), result)
		"minion_stat":
			var mmod: StatMod = EffectModels.make_mod(model, v, ctx, source)
			if mmod != null:
				result["minion_mods"].append(mmod)
		"speed":
			if str(model.get("speed", "")) == "more":
				result["use_speed_more"] *= 1.0 + x
			else:
				result["use_speed_inc"] += x
		"mana":
			if str(model.get("mana", "")) == "increased":
				result["mana_inc"] += x
			else:
				result["mana_added"] += x
				result["mana_sources"].append("%s %s" % [LE.fmt_num(x), source])
		"cooldown":
			var ck: String = str(model.get("cooldown", ""))
			if ck == "recovery_more":
				result["cooldown"][ck] = (1.0 + float(result["cooldown"].get(ck, 0.0))) * (1.0 + x) - 1.0
			else:
				result["cooldown"][ck] = float(result["cooldown"].get(ck, 0.0)) + x
		"param", "resource":
			var key: String = str(model.get("param", model.get("resource", "")))
			var label: String = LE.t(str(model.get("label", key)))
			var entry: Dictionary = result["params"].get(label, {"param": key, "added": 0.0, "increased": 0.0, "more": 1.0, "set": null, "sources": []})
			match str(model.get("mod", "added")):
				"increased":
					entry["increased"] += x
				"more":
					entry["more"] *= 1.0 + x
				"set":
					entry["set"] = x
				_:
					entry["added"] += x
			entry["sources"].append("%s  (%s)" % [LE.fmt_num(x), source])
			result["params"][label] = entry
		"trigger":
			result["triggers"].append({"ability": str(model["ability"]), "on": str(model.get("on", "use")),
				"chance": _num(model.get("chance", 1.0), v), "count": _num(model.get("count", 1.0), v),
				"icd": float(model.get("icd", 0.0)), "node": title})
		"component":
			result["components"].append({"ability": str(model["ability"]), "count": _num(model.get("count", 1.0), v), "node": title})
		"flag":
			var text: String = LE.t("Node \"%s\": %s") % [title, LE.t(str(model.get("text", "")))]
			if not result["flags"].has(text):
				result["flags"].append(text)
		_:
			pass


static func _num(raw: Variant, v: float) -> float:
	if raw is String and str(raw) == "v":
		return v
	return float(raw)


## add_stat into a special list (statsInForm, statsPerStack …): the stat comes from the effect, the model (kind stat_list)
## gives scope, conditions and scaling. false if there is no model.
static func _apply_list_effect(effect: Dictionary, target: String, points: int, source: String, title: String, result: Dictionary) -> bool:
	if BUFF_SKILLS.owns_list(str(result.get("ability_name", "")), target):
		return true  # base buff skill (Holy Aura): the list is applied by BUFF_SKILLS.apply with its own multipliers
	for part: String in target.split(" & "):
		var model: Dictionary = FieldModels.find(part.strip_edges())
		if model.is_empty() or str(model.get("kind", "")) != "stat_list":
			continue
		var mod: StatMod = stat_from_effect(effect.get("stat", {}), points, source)
		if mod == null:
			return false
		var ctx: Dictionary = result["ctx"]
		_note_global_scope(model, result)
		for inp: Dictionary in EffectModels.inputs(model):
			result["inputs"].append(inp)
		var reason: String = EffectModels.blocked(model, ctx)
		if reason != "":
			result["notes"].append(LE.t("Node \"%s\" — counted when: %s") % [title, reason])
			return true
		if model.has("per"):
			var n: float = EffectModels.source(str(model["per"]), ctx, model)
			if model.has("src_max"):
				n = minf(n, float(model["src_max"]))
			mod = mod.scaled(n)
			mod.source += " × %s" % LE.fmt_num(n)
		_add_scoped(mod, str(model.get("scope", "skill")), result)
		return true
	return false


## AutomaticNodeStat: PerPoint → p·value, None → value, Threshold → value if p ≥ threshold (06a §7.2).
static func _automatic_stat(effect: Dictionary, points: int, source: String) -> StatMod:
	var property: int = GameData.sp_id(str(effect.get("property", "")))
	if property < 0:
		return null
	var value: float = float(effect.get("value", 0.0))
	match str(effect.get("scaling", "PerPoint")):
		"PerPoint":
			value *= points
		"Threshold":
			value = value if points >= int(effect.get("threshold", 0)) else 0.0
	return StatMod.make(property, str(effect.get("modType", "ADDED")).to_lower(), value,
		LE.tag_mask(str(effect.get("tags", ""))), source, int(effect.get("specialTag", 0)))


## Conversion / tag-change rule for any "Mutator.field" part of a target ({} if none or kind "none").
static func _conversion_rule(target: String) -> Dictionary:
	for part: String in target.split(" & "):
		var rule: Dictionary = GameData.conversion_rule(part.strip_edges())
		if not rule.is_empty() and str(rule.get("kind", "none")) != "none":
			return rule
	return {}


static func _is_unconditional_temp(target: String) -> bool:
	for part: String in target.split(" & "):
		if part.ends_with(".unconditionalTempStats"):
			return true
	return false


## Conversion rules whose mutator also re-types the added damage of the ability's attribute scaling (evidence in
## skill_conversions.json: «Dex/attribute scaling»). Calibrated in game: Harvest with Physical conversion, Dex 21 →
## «Gains 2 (42) Melee Physical Damage» in the tooltip and dummy hits 995 / 2487 (crit) only with physical Dex damage.
const ATTRIBUTE_SCALING_CONVERSIONS: Array[String] = [
	"HarvestMutator.physicalConversion", "HarvestMutator.coldConversion", "FlayMutator.coldConversion",
]


## attributeScaling × attribute value, levelScaling × character level (06a §6.6).
static func _add_ability_scaling(build: Node, ability: Dictionary, global: StatStore, store: StatStore, conversions: Array = []) -> void:
	for entry: Dictionary in ability.get("attributeScaling", []):
		var index: int = int(entry.get("attribute", 0))
		var attr_sp: int = LE.STRENGTH + _attr_sp_offset(index)
		var n: int = LE.round_half_even(_sum_added_any_tags(global, attr_sp) + _sum_added_any_tags(global, LE.ALL_ATTRIBUTES))
		for stat: Dictionary in entry.get("stats", []):
			var mod: StatMod = stat_from_record(stat, LE.t("Skill: per %s ×%d") % [LE.t(ATTRIBUTE_NAMES[index]), n])
			_convert_scaling_type(mod, conversions)
			store.add(mod.scaled(float(n)))
	for entry: Dictionary in ability.get("levelScaling", []):
		for stat: Dictionary in entry.get("stats", []):
			var mod: StatMod = stat_from_record(stat, LE.t("Skill: per character level ×%d") % build.level)
			store.add(mod.scaled(float(build.level)))


## Re-types added damage of an attribute-scaling stat by the active conversion rules of ATTRIBUTE_SCALING_CONVERSIONS.
static func _convert_scaling_type(mod: StatMod, conversions: Array) -> void:
	if mod.property != LE.DAMAGE or mod.added == 0.0:
		return
	for c: Dictionary in conversions:
		var rule: Dictionary = c.get("rule", {})
		if not ATTRIBUTE_SCALING_CONVERSIONS.has(str(rule.get("key", ""))) or float(c.get("value", 0.0)) <= 0.0:
			continue
		for conv: Dictionary in rule.get("convert", []):
			var from_i: int = SkillComponents.TYPE_ORDER.find(str(conv.get("from", "")))
			var to_i: int = SkillComponents.TYPE_ORDER.find(str(conv.get("to", "")))
			if from_i < 0 or to_i < 0 or (mod.tags & LE.DT_TAG[from_i]) == 0:
				continue
			mod.tags = (mod.tags & ~LE.DT_TAG[from_i]) | LE.DT_TAG[to_i]
			mod.source += LE.t(" (%s → %s, node \"%s\")") % [LE.t(LE.DT_NAME[from_i]), LE.t(LE.DT_NAME[to_i]), c.get("node", "")]


## CoreAttribute enum order is Str 0, Vit 1, Int 2, Dex 3, Att 4; SP order is Str 19, Vit 20, Int 21, Dex 22, Att 23.
static func _attr_sp_offset(attribute_index: int) -> int:
	return attribute_index


# --- conversions ----------------------------------------------------------------

## Effect "stat" object from *_node_effects.json → StatMod (null if the kind is unsupported).
static func stat_from_effect(stat: Dictionary, points: int, source: String) -> StatMod:
	var kind: String = str(stat.get("kind", ""))
	var property: int = -1
	var special: int = 0
	var value_kind: String = kind
	match kind:
		"added", "increased", "more", "quotient":
			property = GameData.sp_id(str(stat.get("property", "")))
			if stat.has("specialTag"):
				special = maxi(0, GameData.enum_value("AilmentID", str(stat["specialTag"])))
		"ailment_chance":
			property = LE.AILMENT_CHANCE
			special = GameData.enum_value("AilmentID", str(stat.get("ailment", "")))
			value_kind = "added"
		"ailment_duration":
			property = 42
			special = GameData.enum_value("AilmentID", str(stat.get("ailment", "")))
			value_kind = "added"
		"ailment_effect":
			property = 43
			special = GameData.enum_value("AilmentID", str(stat.get("ailment", "")))
			value_kind = "added"
		"conditional_more_damage":
			property = LE.CONDITIONAL_DAMAGE
			special = GameData.enum_value("ConditionalDamageProperty", str(stat.get("condition", "")))
			value_kind = "more"
		_:
			return null
	if property < 0 or special < 0:
		return null
	var raw: Variant = stat.get(kind, stat.get("value", null))
	if raw == null:
		raw = stat.get("value", null)
	if raw == null:
		return null
	return StatMod.make(property, value_kind, eval_value(raw, points), LE.tag_mask(str(stat.get("tags", ""))), source, special)


## Stat-like record ({property, specialTag, tags, extraTag, added|addedValue, increased|increasedValue, more|moreValues}).
static func stat_from_record(rec: Dictionary, source: String) -> StatMod:
	var mod := StatMod.new()
	mod.property = int(rec.get("property", 0))
	mod.special = int(rec.get("specialTag", 0))
	mod.tags = int(rec.get("tags", 0))
	mod.extra = int(rec.get("extraTag", 0))
	mod.added = float(rec.get("added", rec.get("addedValue", 0.0)))
	mod.increased = float(rec.get("increased", rec.get("increasedValue", 0.0)))
	for m: Variant in rec.get("more", rec.get("moreValues", [])):
		mod.more.append(float(m))
	mod.source = source
	return mod


## {per_point, flat} or {expr} evaluated for p points.
static func eval_value(raw: Variant, points: int) -> float:
	if raw is float or raw is int:
		return float(raw)
	if not raw is Dictionary:
		return 0.0
	if raw.has("expr"):
		var expr: Expression = _expression(str(raw["expr"]))
		if expr == null:
			return 0.0
		var out: Variant = expr.execute([float(points)], null, false)
		if expr.has_execute_failed():
			# game code the client does not have (EpochExtensions.AreaToRadius, TheWeaver.…): counts as 0 from now on
			_expressions[str(raw["expr"])] = null
			return 0.0
		if out is float or out is int:
			return float(out)
		return 0.0
	return float(raw.get("per_point", 0.0)) * points + float(raw.get("flat", 0.0))


## Parsed node effect expressions by text; null for the ones that do not parse or failed to run.
static var _expressions: Dictionary = {}


static func _expression(text: String) -> Expression:
	if not _expressions.has(text):
		var expr := Expression.new()
		_expressions[text] = expr if expr.parse(text, ["p"]) == OK else null
	return _expressions[text]


static func _effect_label(effect: Dictionary) -> String:
	var stat: Dictionary = effect.get("stat", {}) if effect.get("stat") is Dictionary else {}
	var target: String = str(effect.get("target", ""))
	var field: String = target.get_slice(".", target.get_slice_count(".") - 1) if target.contains(".") else target
	var parts: PackedStringArray = []
	if field != "":
		parts.append(field)
	if stat.has("kind"):
		parts.append(str(stat["kind"]))
	if stat.has("property"):
		parts.append(str(stat["property"]))
	if stat.has("abilityID"):
		parts.append(LE.t("skill property %s") % stat["abilityID"])
	if stat.has("playerPropertyName"):
		parts.append(str(stat["playerPropertyName"]))
	return " / ".join(parts) if not parts.is_empty() else str(effect.get("op", LE.t("effect")))
