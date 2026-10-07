class_name BuildMods

## Collects StatMods from every build source (docs/ENGINE.md §5).

const STAT_KINDS: Array[String] = ["added", "increased", "more", "quotient"]
const ATTRIBUTE_NAMES: Array[String] = ["Strength", "Vitality", "Intelligence", "Dexterity", "Attunement"]
const BUFF_SKILLS: GDScript = preload("res://scripts/engine/buff_skills.gd")  # class_name BuffSkills
const SLOTS: Array[String] = ["helmet", "body", "belt", "boots", "gloves", "weapon", "offhand", "amulet", "ring1", "ring2", "relic"]


## {store: StatStore, notes: Array[String]} — all character-wide mods. Cached by the build state (CalcCache): the store
## is shared and must not be changed. Not cached while ConfigRelevance records (it needs the models to run) and keyed
## apart while MinionCount computes a summon limit (minion counts are their bases then).
static func global_store(build: Node) -> Dictionary:
	if ConfigRelevance._recording:
		return _global_store(build)
	var key: Array = [CalcCache.build_key(build), MinionCount._busy]
	var hit: Variant = CalcCache.lookup("global_store", key)
	if hit == null:
		hit = _global_store(build)
		CalcCache.put("global_store", key, hit)
	return {"store": hit["store"], "notes": (hit["notes"] as Array[String]).duplicate()}


static func _global_store(build: Node) -> Dictionary:
	var g: Dictionary = _store_without_skill_buffs(build)
	var store: StatStore = g["store"]
	var notes: Array[String] = g["notes"]
	_add_skill_buffs(build, store)
	_add_attributes(build, store, notes, g["attributes"])  # attributes given by the buffs
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
	var attributes: Dictionary = _add_attributes(build, store, notes)
	_add_player_ailments(build, store)
	_add_passives(build, store, notes, "post")
	UniqueEffects.apply_global(build, store, notes, "post")
	# attributes given by the models above (the game re-applies the per-point stats on every change of the value)
	_add_attributes(build, store, notes, attributes)
	return {"store": store, "notes": notes, "attributes": attributes}


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
## `use` = "shadow" builds the store of a use repeated by a shadow (ShadowCalc): models with the condition «use:shadow»
## apply, «use:direct» ones do not; "" is your own use.
static func skill_store(build: Node, slot: int, global: StatStore, use: String = "") -> Dictionary:
	var store := StatStore.new()
	store.parent = global
	var result: Dictionary = {
		"store": store, "notes": [] as Array[String],
		"use_speed_inc": 0.0, "use_speed_more": 1.0, "mana_inc": 0.0, "mana_added": 0.0,
		"mana_sources": [] as Array[String], "conversions": [],
		# §9: field models of the skill tree
		"params": {}, "triggers": [], "components": [], "minion_mods": [] as Array[StatMod], "component_mods": {},
		# minion mods of one minion type only (scope "minion:<actor name>": Summon Skeleton's warrior / archer / rogue lists)
		"minion_actor_mods": {},
		# flags: shown texts; flag_keys: the untranslated model texts, for code that checks a mechanic
		"flags": [] as Array[String], "flag_keys": [] as Array[String], "cooldown": {}, "cooldown_base": {}, "inputs": [] as Array[Dictionary],
		"global_mods": [] as Array[StatMod], "ability_name": "",
		# resource models that passed their conditions: {model, v, x, source} (the Defense tab turns them into recovery)
		"resources": [] as Array[Dictionary],
		"ctx": {"build": build, "store": store, "slot": slot, "item_slot": "", "use": use},
	}
	if slot < 0 or slot >= build.skills.size():
		return result
	var skill: Dictionary = build.skills[slot]
	var ability: Dictionary = GameData.get_ability(str(skill.get("ability", "")))
	if ability.is_empty():
		return result

	result["ability_name"] = str(ability.get("abilityName", ""))
	result["main_name"] = str(ability.get("name", ""))
	result["own_mutator"] = str(ability.get("mutator", {}).get("class", "")) if ability.get("mutator") is Dictionary else ""
	var effects: Dictionary = GameData.skill_effects(str(ability.get("skillTree", "")))
	var tree: Dictionary = skill.get("tree", {})
	for node_id: Variant in tree:
		var points: int = int(tree[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		_add_skill_node(node, points, result)
	_add_other_skill_nodes(build, slot, result)

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

static func _add_blessings(build: Node, store: StatStore, _notes: Array[String]) -> void:
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
	var ctx: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": ""}
	for entry: Dictionary in _passive_entries(build):
		var points: int = entry["points"]
		var title: String = entry["title"]
		var source: String = entry["source"]
		for effect: Dictionary in (entry["node"] as Dictionary).get("effects", []):
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


## Allocated passive nodes plus the base bonus of the chosen mastery (one "point", research/07f §2):
## [{node, points, title, source}].
## Cached by the class, mastery, passives and locale (CalcCache): the entries are shared and must not be changed.
static func _passive_entries(build: Node) -> Array[Dictionary]:
	var key: PackedByteArray = var_to_bytes([build.class_id, build.mastery, build.passives, TranslationServer.get_locale()])
	var hit: Variant = CalcCache.lookup("passive_entries", key)
	if hit == null:
		hit = _collect_passive_entries(build)
		CalcCache.put("passive_entries", key, hit)
	return hit


static func _collect_passive_entries(build: Node) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var tree_id: String = str(GameData.get_passive_tree(build.class_id).get("treeID", ""))
	var effects: Dictionary = GameData.passive_effects(tree_id)
	for node_id: Variant in build.passives:
		var points: int = int(build.passives[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		var title: String = GameData.display_name(node)
		entries.append({"node": node, "points": points, "title": title, "source": LE.t("Passive \"%s\" ×%d") % [title, points]})
	var bonus: Dictionary = GameData.mastery_bonus(tree_id, build.mastery)
	if not bonus.is_empty():
		var title: String = LE.t("%s mastery bonus") % GameData.display_name(bonus)
		entries.append({"node": bonus, "points": 1, "title": title, "source": title})
	return entries


## Passive effects aimed at the mutators of this ability (target "LungeMutator.field" ↔ ability, BUFF_SKILLS.owns_mutator):
## through the same field models as skill tree nodes (docs/ENGINE.md §9.7).
static func _add_skill_passives(build: Node, ability: Dictionary, result: Dictionary) -> void:
	for entry: Dictionary in _passive_entries(build):
		var points: int = entry["points"]
		var title: String = entry["title"]
		var source: String = entry["source"]
		for effect: Dictionary in (entry["node"] as Dictionary).get("effects", []):
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
	if ShadowCalc.handles_effect(effect):
		return  # CreateShadow properties: counted by the shadow components (ShadowCalc)
	if MinionCalc.handles_effect(effect):
		return  # summon properties: minion stats and summon limits (MinionCalc.MINION_PROPERTIES, MinionCount)
	notes.append(LE.t("Passive \"%s\": %s — not counted") % [title, _effect_label(effect)])


## "global" / "minion" for the model's scope, "" if it cannot be applied to the character (component, ability-only field).
static func _passive_scope(model: Dictionary, target: String) -> String:
	var scope: String = str(model.get("scope", ""))
	if scope == "":
		return "global" if target.begins_with("CharacterMutator.") else ""
	if scope == "skill":
		# a skill-scoped field of another skill's mutator: its skill is not on the bar (equipped ones are applied in
		# skill_store), so it must not leak to the character
		return "global" if target.begins_with("CharacterMutator.") else ""
	if scope == "global":
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
## Buff stats with these properties are effects of a skill or player property, not stats: listed, not added.
const BUFF_SPECIAL_PROPERTIES: Array[int] = [LE.ABILITY_PROPERTY, LE.PLAYER_PROPERTY]


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
		if buff_stacks(build, id) > 0.0:
			continue  # the «Buffs on me» stacks of the same ailment are counted below (not twice)
		var ail: Dictionary = GameData.ailment(id)
		var effect: float = 1.0 + store.query(LE.EFFECT_OF_AILMENT_ON_YOU, 0, id).increased
		for buff: Dictionary in ail.get("buffs", []):
			if BUFF_SPECIAL_PROPERTIES.has(int(buff.get("property", -1))):
				continue
			var mod: StatMod = stat_from_record(buff, LE.t("%s on you (effect ×%s)") % [str(ail.get("name", key)), LE.fmt_num(effect)])
			store.add(mod.scaled(effect))
	# stacks of the "Buffs on me" list: every stack adds the buff's stats (at most maxInstances stacks when it is set)
	var buffs: Variant = build.player_state.get("buffs", {})
	for key: Variant in buffs if buffs is Dictionary else {}:
		var id: int = int(key)
		var stacks: float = buff_stacks(build, id)
		if stacks <= 0.0:
			continue
		var ail: Dictionary = GameData.ailment(id)
		var effect: float = 1.0 + store.query(LE.EFFECT_OF_AILMENT_ON_YOU, 0, id).increased
		for buff: Dictionary in ail.get("buffs", []):
			if BUFF_SPECIAL_PROPERTIES.has(int(buff.get("property", -1))):
				continue
			var mod: StatMod = stat_from_record(buff, LE.t("%s on you: %s stacks (effect ×%s)") % [
				str(ail.get("displayName", ail.get("name", id))), LE.fmt_num(stacks), LE.fmt_num(effect)])
			store.add(mod.scaled(effect * stacks))


## Stacks of a buff on the player (Conditions tab, "Buffs on me"), at most its maxInstances.
static func buff_stacks(build: Node, ailment_id: int) -> float:
	var buffs: Variant = build.player_state.get("buffs", {})
	if not buffs is Dictionary:
		return 0.0
	var stacks: float = float(buffs.get(ailment_id, buffs.get(str(ailment_id), 0)))
	var max_inst: int = int(GameData.ailment(ailment_id).get("maxInstances", 0))
	return minf(stacks, float(max_inst)) if max_inst > 0 else stacks


# --- 5.3 attributes -----------------------------------------------------------

## Per-point stats of every attribute. A corrupted attribute ("Vitality Converted to Rampancy": SP 98 with the tags of
## corruptedFlag, e.g. a corrupted amulet affix) gives corruptedPerPoint instead of perPoint (07a §2.2); its special
## PlayerProperty stats go through the player models of unique_effect_models.json, those without a model (and the
## AbilityProperty ones) go to the notes.
## `done` = the values already converted by an earlier call ({attribute index: {n, converted}}): only the change since then
## is added (the same per-point stats × the delta), nothing if the attribute was converted or un-converted meanwhile.
## Returns the values after this call, in the format of `done`.
static func _add_attributes(build: Node, store: StatStore, notes: Array[String], done: Dictionary = {}) -> Dictionary:
	var values: Dictionary = {}
	var all_attr: float = _sum_added_any_tags(store, LE.ALL_ATTRIBUTES)
	for attr: Dictionary in GameData.attributes:
		var index: int = int(attr.get("attribute", 0))
		var total: int = LE.round_half_even(_sum_added_any_tags(store, int(attr["statProperty"])) + all_attr)
		var converted: String = converted_attribute(store, attr)
		values[index] = {"n": total, "converted": converted}
		var n: int = total
		if done.has(index):
			if str(done[index]["converted"]) != converted:
				continue
			n = total - int(done[index]["n"])
		if n == 0:
			continue
		var name: String = LE.t(converted if converted != "" else ATTRIBUTE_NAMES[index])
		var source: String = "%s ×%d" % [name, n]
		for per_point: Dictionary in attr.get("corruptedPerPoint" if converted != "" else "perPoint", []):
			var prop_id: int = int(per_point.get("property", 0))
			if prop_id == LE.PLAYER_PROPERTY or prop_id == LE.ABILITY_PROPERTY:
				_add_attribute_special(build, store, notes, per_point, n, source)
				continue
			var mod: StatMod = stat_from_record(per_point, source)
			store.add(mod.scaled(float(n)))
	return values


## Special per-point stat of a corrupted attribute: the player model of its PlayerProperty index with value = per point × N.
static func _add_attribute_special(build: Node, store: StatStore, notes: Array[String], per_point: Dictionary, n: int, source: String) -> void:
	var label: String = str(per_point.get("playerPropertyName", per_point.get("propertyName", "")))
	var model: Dictionary = {}
	if int(per_point.get("property", 0)) == LE.PLAYER_PROPERTY:
		model = GameData.unique_player_model(int(per_point.get("tags", -1)))
	if str(model.get("kind", "")) != "stat":
		notes.append(LE.t("%s: special stat (%s) — not counted") % [source, label])
		return
	var ctx: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": ""}
	var reason: String = EffectModels.blocked(model, ctx)
	if reason != "":
		notes.append(LE.t("%s: %s — counted when: %s") % [source, label, reason])
		return
	var more: Array = per_point.get("more", [])
	var v: float = (float(more[0]) if not more.is_empty() else float(per_point.get("added", 0.0)) + float(per_point.get("increased", 0.0))) * n
	var mod: StatMod = EffectModels.make_mod(model, v, ctx, source)
	if mod != null:
		store.add(mod)


## Name of the attribute this one is converted to ("Rampancy" for "Vitality Converted to Rampancy"), "" if it is not.
static func converted_attribute(store: StatStore, attr: Dictionary) -> String:
	var flag: Dictionary = attr.get("corruptedFlag", {})
	if flag.is_empty():
		return ""
	for mod: StatMod in store.mods_of(int(flag.get("property", LE.PLAYER_PROPERTY))):
		if mod.tags == int(flag.get("tags", -1)) and mod.added > 0.0:
			return str(flag.get("playerPropertyName", "")).get_slice(" Converted to ", 1)
	return ""


## Attribute value of a store as the game counts it: round_half_even(Σ added SP of the attribute + Σ added AllAttributes),
## tags are not checked (06a §5.1). `sp` = the attribute's stat property.
static func attribute_value(store: StatStore, sp: int) -> int:
	return LE.round_half_even(_sum_added_any_tags(store, sp) + _sum_added_any_tags(store, LE.ALL_ATTRIBUTES))


static func _sum_added_any_tags(store: StatStore, property: int) -> float:
	var total: float = 0.0
	for mod: StatMod in store.mods_of(property):
		total += mod.added
	return total


# --- 5.5 skill tree -----------------------------------------------------------

## A node often writes the same field into the mutators of every part of a skill (Umbral Blades: first throw, second
## throw, recall — UmbralBladesMutator / UmbralBlades2Mutator / UmbralBladesRecallMutator; Flay and its blood explosion).
## All parts share the skill's store, so a stat the node also writes into the skill's own mutator counts once (counts of
## damage components and triggers still add up: Volatile Reversal casts void bolts on the jump and on the return, both
## within one cooldown). Stats written only into the mutator of a combo part (Ability.comboAbilities) or of another
## player skill go to that ability's damage component (dropped when the skill has no such component), not to the main hit.
static func _add_skill_node(node: Dictionary, points: int, result: Dictionary) -> void:
	var own: String = str(result.get("own_mutator", ""))
	var own_fields: Dictionary = {}
	if own != "":
		for effect: Dictionary in node.get("effects", []):
			for part: String in str(effect.get("target", "")).split(" & "):
				if part.strip_edges().begins_with(own + "."):
					own_fields[part.strip_edges().get_slice(".", 1)] = true
	var title: String = str(node.get("name", ""))
	for effect: Dictionary in node.get("effects", []):
		var target: String = str(effect.get("target", ""))
		var other: Dictionary = _other_part(target, own, str(result.get("main_name", "")))
		if not other.is_empty():
			var first: String = target.split(" & ")[0].strip_edges()
			var kind: String = str(FieldModels.find(first).get("kind", ""))
			if own_fields.has(first.get_slice(".", 1)) and kind != "component" and kind != "trigger":
				continue  # the same stat of another part: counted once, through the own mutator
			var reasons: Array = other.get("reasons", [])
			if not (reasons.has("Ability.comboAbilities") or str(other.get("category", "")) == "player"):
				_add_skill_effect(effect, points, title, result)
				continue
			result["scope_override"] = "component:" + str(other["name"])
			if reasons.has("Ability.comboAbilities"):
				result["scope_override_note"] = LE.t("Node \"%s\": stats of \"%s\" (another part of the skill) count only for its own damage component") % [title, str(other["name"])]
			else:
				result["scope_override_note"] = LE.t("Node \"%s\": stats of the skill \"%s\" count in its own calculation (when it is on the bar) and here only for its damage component") % [title, GameData.display_name(other)]
		_add_skill_effect(effect, points, title, result)
		result.erase("scope_override")
		result.erase("scope_override_note")


## Nodes of the other bar skills' trees that write into this skill's mutator (Firebrand → Flame Reave ignite chance,
## Summon Bear → Swipe damage, Multistrike → Void Cleave damage): only the parts of the target aimed at this skill count
## here, with the other skill named in the source.
static func _add_other_skill_nodes(build: Node, slot: int, result: Dictionary) -> void:
	var own: String = str(result.get("own_mutator", ""))
	if own == "":
		return
	for other_slot: int in range(build.skills.size()):
		if other_slot == slot:
			continue
		var other_ab: Dictionary = GameData.get_ability(str(build.skills[other_slot].get("ability", "")))
		if other_ab.is_empty() or str(other_ab.get("name", "")) == str(result.get("main_name", "")):
			continue
		var effects: Dictionary = GameData.skill_effects(str(other_ab.get("skillTree", "")))
		var tree: Dictionary = build.skills[other_slot].get("tree", {})
		for node_id: Variant in tree:
			var points: int = int(tree[node_id])
			var node: Dictionary = effects.get(int(node_id), {})
			if points <= 0 or node.is_empty():
				continue
			var title: String = "%s: %s" % [GameData.display_name(other_ab), str(node.get("name", ""))]
			for effect: Dictionary in node.get("effects", []):
				var own_target: String = _own_parts(str(effect.get("target", "")), own)
				if own_target == "":
					continue
				var mine: Dictionary = effect.duplicate()
				mine["target"] = own_target
				_add_skill_effect(mine, points, title, result)


## The parts ("A & B") of a target on the mutator `own`, joined back with " & "; "" if none (memoized).
static func _own_parts(target: String, own: String) -> String:
	var key: String = own + "|" + target
	if not _own_parts_memo.has(key):
		var parts: PackedStringArray = []
		for part: String in target.split(" & "):
			if part.strip_edges().begins_with(own + "."):
				parts.append(part.strip_edges())
		_own_parts_memo[key] = " & ".join(parts)
	return _own_parts_memo[key]


static var _own_parts_memo: Dictionary = {}


## Ability of the mutator of a target that is not the skill's own mutator and belongs to another ability (a combo part,
## sub-ability or another skill); {} when a part is the own mutator, the target is the character's or unknown.
static func _other_part(target: String, own: String, main_name: String) -> Dictionary:
	if own == "":
		return {}
	var key: String = "%s|%s|%s" % [target, own, main_name]
	if not _other_parts.has(key):
		_other_parts[key] = _find_other_part(target, own, main_name)
	return _other_parts[key]


static var _other_parts: Dictionary = {}  # memo of _other_part (game data only)


static func _find_other_part(target: String, own: String, main_name: String) -> Dictionary:
	var cls: String = ""
	for part: String in target.split(" & "):
		var p: String = part.strip_edges()
		if p.begins_with(own + "."):
			return {}
		if cls == "":
			cls = p.get_slice(".", 0)
	if cls == "" or cls == "CharacterMutator" or not cls.ends_with("Mutator"):
		return {}
	var ab: Dictionary = GameData.ability_by_mutator_class(cls)
	var ab_name: String = str(ab.get("name", ""))
	return ab if ab_name != "" and ab_name != main_name else {}


static func _add_skill_effect(effect: Dictionary, points: int, title: String, result: Dictionary) -> void:
	var notes: Array[String] = result["notes"]
	var source: String = LE.t("Node \"%s\" ×%d") % [title, points]
	var target: String = str(effect.get("target", ""))
	var op: String = str(effect.get("op", ""))
	if op == "add_stat" and (_is_unconditional_temp(target) or target == "CharacterMutator.stats"):
		var mod: StatMod = stat_from_effect(effect.get("stat", {}), points, source)
		if mod != null:
			_add_scoped(mod, "skill", result)
			return
	elif op == "automatic_node_stat":
		var auto_mod: StatMod = _automatic_stat(effect, points, source)
		if auto_mod != null:
			_add_scoped(auto_mod, "skill", result)
			return
	elif op == "add_stat":
		if _apply_list_effect(effect, target, points, source, title, result):
			return
	elif op == "cooldown":
		for key: String in effect.get("args", {}):
			result["cooldown_base"][key] = eval_value(effect["args"][key], points)
		return
	elif op == "" and effect.has("value") and target.contains("."):
		var field: String = target.get_slice(".", target.get_slice_count(".") - 1)
		var v: float = eval_value(effect["value"], points)
		var rule: Dictionary = _conversion_rule(target)
		if not rule.is_empty():
			result["conversions"].append({"rule": rule, "value": v, "node": title, "points": points})
			return
		if _apply_field_models(target, v, source, title, result):
			return
		match field:
			"increasedCastSpeed", "increasedAttackSpeed":
				result["use_speed_inc"] += v
				return
			"moreCastSpeed", "moreAttackSpeed":
				result["use_speed_more"] *= 1.0 + v
				return
			"increasedManaCost":
				result["mana_inc"] += v
				return
			"addedManaCost":
				result["mana_added"] += v
				return
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


## Identity of a model for the «same effect written into several mutators» check: everything that changes what the model
## does (not its scope, note or confidence).
const SIGNATURE_KEYS: Array[String] = ["stat", "mod", "tags", "param", "resource", "ability", "when", "text", "label", "count", "chance",
	"on", "icd", "speed", "mana", "cooldown", "ailment", "per", "factor", "offset", "src_max", "min", "max", "inverse", "at_least", "below"]


static func _model_signature(m: Dictionary) -> String:
	var parts: PackedStringArray = [str(m.get("kind", "stat"))]
	for key: String in SIGNATURE_KEYS:
		parts.append(str(m.get(key, "")))
	return "|".join(parts)


## A scope-global model was met (even if its condition is off): the skill gets the input «buff active».
static func _note_global_scope(model: Dictionary, result: Dictionary) -> void:
	if str(model.get("scope", "skill")) == "global":
		result["has_global"] = true


static func _add_scoped(mod: StatMod, scope: String, result: Dictionary) -> void:
	if result.has("scope_override") and (scope == "skill" or scope == ""):
		scope = str(result["scope_override"])
		var line: String = str(result.get("scope_override_note", ""))
		if line != "" and not result["notes"].has(line):
			result["notes"].append(line)
	if scope.begins_with("component:"):
		var comp: String = scope.get_slice(":", 1)
		if not result["component_mods"].has(comp):
			result["component_mods"][comp] = [] as Array[StatMod]
		result["component_mods"][comp].append(mod)
	elif scope == "minion":
		result["minion_mods"].append(mod)
	elif scope.begins_with("minion:"):
		var actor: String = scope.get_slice(":", 1)
		if not result["minion_actor_mods"].has(actor):
			result["minion_actor_mods"][actor] = [] as Array[StatMod]
		result["minion_actor_mods"][actor].append(mod)
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
	# models of another user (a shadow-only node on your own use and back) are left to that store, without a note
	var cur_use: String = str(ctx.get("use", ""))
	for cond: Variant in model.get("when", []):
		if str(cond).begins_with("use:") and str(cond) != "use:" + (cur_use if cur_use != "" else "direct"):
			return
	ctx["v"] = v
	var reason: String = EffectModels.blocked(model, ctx)
	ctx.erase("v")
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
				var mscope: String = str(model.get("scope", "minion"))
				_add_scoped(mmod, mscope if mscope.begins_with("minion:") else "minion", result)
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
			if str(model.get("kind", "")) == "resource" and result.has("resources"):
				result["resources"].append({"model": model, "v": v, "x": x, "source": source})
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
			if not result["flag_keys"].has(str(model.get("text", ""))):
				result["flag_keys"].append(str(model.get("text", "")))
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
	var extra: int = ability_index_of(effect.get("extraTag", 0))
	if extra < 0:
		return null  # an ability the data does not know: the stat cannot be pinned to it
	return StatMod.make(property, str(effect.get("modType", "ADDED")).to_lower(), value,
		LE.tag_mask(str(effect.get("tags", ""))), source, int(effect.get("specialTag", 0)), extra)


## AbilityID value of an `extraTag` of effect data: 0 for none ("none", 0, ""), an int or numeric text as is, the
## abilityIDEnum value of the ability named so ("entanglingRoots" → EntanglingRoots); -1 if no such ability.
static func ability_index_of(tag: Variant) -> int:
	if tag is int or tag is float:
		return int(tag)
	var text: String = str(tag)
	if text == "" or text == "none" or text == "None":
		return 0
	if text.is_valid_int():
		return text.to_int()
	var ab: Dictionary = GameData.ability_by_name(text.substr(0, 1).to_upper() + text.substr(1))
	var enum_rec: Variant = ab.get("abilityIDEnum")
	if enum_rec is Dictionary and str(enum_rec.get("name", "")) == text:
		return int(enum_rec.get("value", -1))
	return -1


## Conversion / tag-change rule for any "Mutator.field" part of a target ({} if none or kind "none").
static func _conversion_rule(target: String) -> Dictionary:
	if not _conversion_rules.has(target):
		var found: Dictionary = {}
		for part: String in target.split(" & "):
			var rule: Dictionary = GameData.conversion_rule(part.strip_edges())
			if not rule.is_empty() and str(rule.get("kind", "none")) != "none":
				found = rule
				break
		_conversion_rules[target] = found
	return _conversion_rules[target]


static var _conversion_rules: Dictionary = {}  # memo of _conversion_rule (game data only)


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
				special = special_id(stat["specialTag"])  # -1 (unknown name) drops the mod below, it must not become «any ailment»
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
	var extra: int = ability_index_of(stat.get("extraTag", 0))
	if extra < 0:
		return null
	var raw: Variant = stat.get(kind, stat.get("value", null))
	if raw == null:
		raw = stat.get("value", null)
	if raw == null:
		return null
	return StatMod.make(property, value_kind, eval_value(raw, points), LE.tag_mask(str(stat.get("tags", ""))), source, special, extra)


## specialTag of effect data: a number (or numeric text: the special id of the property, e.g. an AilmentID) as is, otherwise
## the AilmentID of the name; -1 if the name is unknown.
static func special_id(tag: Variant) -> int:
	if tag is int or tag is float:
		return int(tag)
	var text: String = str(tag)
	if text.is_valid_int():
		return text.to_int()
	return GameData.enum_value("AilmentID", text)


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
			push_warning("BuildMods: node expression failed to run, counted as 0: %s" % str(raw["expr"]))
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
		var parsed: bool = expr.parse(text, ["p"]) == OK
		if not parsed:
			push_warning("BuildMods: node expression does not parse, counted as 0: %s" % text)
		_expressions[text] = expr if parsed else null
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
