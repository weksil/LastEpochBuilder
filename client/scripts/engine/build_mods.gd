class_name BuildMods

## Collects StatMods from every build source (docs/ENGINE.md §5).

const STAT_KINDS: Array[String] = ["added", "increased", "more", "quotient"]
const ATTRIBUTE_NAMES_RU: Array[String] = ["Сила", "Живучесть", "Интеллект", "Ловкость", "Настрой"]
const SLOTS: Array[String] = ["helmet", "body", "belt", "boots", "gloves", "weapon", "offhand", "amulet", "ring1", "ring2", "relic"]


## {store: StatStore, notes: Array[String]} — all character-wide mods.
static func global_store(build: Node) -> Dictionary:
	var store := StatStore.new()
	var notes: Array[String] = []
	_add_class_base(build, store)
	_add_passives(build, store, notes)
	for slot: String in build.items:
		if SLOTS.has(slot) or IdolGrid.is_idol_key(slot):
			store.add_all(ItemMods.item_mods(slot, build.items[slot]))
	_add_blessings(build, store, notes)
	_add_set_bonuses(build, store, notes)
	UniqueEffects.apply_global(build, store, notes, "pre")
	_add_attributes(store, notes)
	_add_player_ailments(build, store)
	UniqueEffects.apply_global(build, store, notes, "post")
	UniqueEffects.add_notes(build, notes)
	return {"store": store, "notes": notes}


## Skill-local store (parent = global store) plus mutator-field totals.
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
		"ctx": {"build": build, "store": store, "slot": slot, "item_slot": ""},
	}
	if slot < 0 or slot >= build.skills.size():
		return result
	var skill: Dictionary = build.skills[slot]
	var ability: Dictionary = GameData.get_ability(str(skill.get("ability", "")))
	if ability.is_empty():
		return result

	var effects: Dictionary = GameData.skill_effects(str(ability.get("skillTree", "")))
	var tree: Dictionary = skill.get("tree", {})
	for node_id: Variant in tree:
		var points: int = int(tree[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		_add_skill_node(node, points, result)

	_add_ability_scaling(build, ability, global, store)
	UniqueEffects.apply_skill(build, ability, result)
	return result


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
				"Благословение «%s»" % display_name, specialTag, extraTag)
			store.add(mod)


# --- 5.1 class base ---------------------------------------------------------

static func _add_class_base(build: Node, store: StatStore) -> void:
	var class_data: Dictionary = GameData.get_class_data(build.class_id)
	for entry: Dictionary in class_data.get("levelMods", []):
		var value: float = float(entry.get("base", 0.0)) + float(entry.get("perLevel", 0.0)) * build.level
		if value != 0.0:
			store.add(StatMod.make(int(entry["property"]), str(entry["modType"]).to_lower(), value,
				int(entry.get("tags", 0)), "База класса (уровень %d)" % build.level))
	for entry: Dictionary in GameData.hidden_base_mods:
		store.add(StatMod.make(int(entry["property"]), str(entry["modType"]).to_lower(), float(entry["value"]),
			int(entry.get("tags", 0)), "Скрытая база персонажа"))


# --- 5.2 passives -------------------------------------------------------------

static func _add_passives(build: Node, store: StatStore, notes: Array[String]) -> void:
	var tree: Dictionary = GameData.get_passive_tree(build.class_id)
	var effects: Dictionary = GameData.passive_effects(str(tree.get("treeID", "")))
	for node_id: Variant in build.passives:
		var points: int = int(build.passives[node_id])
		var node: Dictionary = effects.get(int(node_id), {})
		if points <= 0 or node.is_empty():
			continue
		var title: String = GameData.display_name(node)
		var source: String = "Пассивка «%s» ×%d" % [title, points]
		for effect: Dictionary in node.get("effects", []):
			var mod: StatMod = null
			if effect.get("op") == "add_stat" and effect.get("target") == "CharacterMutator.stats":
				mod = stat_from_effect(effect.get("stat", {}), points, source)
			if mod != null:
				store.add(mod)
			else:
				notes.append("Пассивка «%s»: %s — не учитывается" % [title, _effect_label(effect)])


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
		var source: String = "Сет «%s» (%d предм.)" % [str(st.get("setName", set_id)), count]
		for bonus: Dictionary in st.get("bonuses", []):
			if int(bonus.get("setRequirement", 99)) > count:
				continue
			var prop_id: int = int(bonus.get("property", 0))
			if prop_id == LE.PLAYER_PROPERTY or prop_id == LE.ABILITY_PROPERTY:
				notes.append("%s: особый бонус (%s) — не считается" % [source, str(bonus.get("propertyName", prop_id))])
				continue
			store.add(StatMod.make(prop_id, str(bonus.get("modType", "ADDED")).to_lower(),
				AffixMath.fixed_value(float(bonus.get("value", 0.0)), str(bonus.get("rounding", "Hundredth")), str(bonus.get("modType", "ADDED"))),
				int(bonus.get("tags", 0)), source, int(bonus.get("specialTag", 0)), int(bonus.get("extraTag", 0))))


## Haste / Frenzy on the player (Условия): ailment buffs × (1 + increased effect of the ailment on you, SP 120).
static func _add_player_ailments(build: Node, store: StatStore) -> void:
	for key: String in PLAYER_AILMENTS:
		if not build.player_state.get(key, false):
			continue
		var id: int = PLAYER_AILMENTS[key]
		var ail: Dictionary = GameData.ailment(id)
		var effect: float = 1.0 + store.query(LE.EFFECT_OF_AILMENT_ON_YOU, 0, id).increased
		for buff: Dictionary in ail.get("buffs", []):
			var mod: StatMod = stat_from_record(buff, "%s на вас (эффект ×%s)" % [str(ail.get("name", key)), LE.fmt_num(effect)])
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
			var mod: StatMod = stat_from_record(per_point, "%s ×%d" % [ATTRIBUTE_NAMES_RU[index], n])
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
	var source: String = "Узел «%s» ×%d" % [title, points]
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
		notes.append("Узел «%s»: %s — механика умения, пока не считается" % [title, _effect_label(effect)])


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


static func _add_scoped(mod: StatMod, scope: String, result: Dictionary) -> void:
	if scope.begins_with("component:"):
		var comp: String = scope.get_slice(":", 1)
		if not result["component_mods"].has(comp):
			result["component_mods"][comp] = [] as Array[StatMod]
		result["component_mods"][comp].append(mod)
	elif scope == "minion":
		result["minion_mods"].append(mod)
	else:
		result["store"].add(mod)


## Routes one model (§9.1) into the skill result.
static func _apply_model(model: Dictionary, v: float, source: String, title: String, result: Dictionary) -> void:
	var ctx: Dictionary = result["ctx"]
	for inp: Dictionary in EffectModels.inputs(model):
		result["inputs"].append(inp)
	var reason: String = EffectModels.blocked(model, ctx)
	if reason != "":
		result["notes"].append("Узел «%s» — учитывается при условии: %s" % [title, reason])
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
			var label: String = str(model.get("label", key))
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
			var text: String = "Узел «%s»: %s" % [title, str(model.get("text", ""))]
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
	for part: String in target.split(" & "):
		var model: Dictionary = FieldModels.find(part.strip_edges())
		if model.is_empty() or str(model.get("kind", "")) != "stat_list":
			continue
		var mod: StatMod = stat_from_effect(effect.get("stat", {}), points, source)
		if mod == null:
			return false
		var ctx: Dictionary = result["ctx"]
		for inp: Dictionary in EffectModels.inputs(model):
			result["inputs"].append(inp)
		var reason: String = EffectModels.blocked(model, ctx)
		if reason != "":
			result["notes"].append("Узел «%s» — учитывается при условии: %s" % [title, reason])
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


## attributeScaling × attribute value, levelScaling × character level (06a §6.6).
static func _add_ability_scaling(build: Node, ability: Dictionary, global: StatStore, store: StatStore) -> void:
	for entry: Dictionary in ability.get("attributeScaling", []):
		var index: int = int(entry.get("attribute", 0))
		var attr_sp: int = LE.STRENGTH + _attr_sp_offset(index)
		var n: int = LE.round_half_even(_sum_added_any_tags(global, attr_sp) + _sum_added_any_tags(global, LE.ALL_ATTRIBUTES))
		for stat: Dictionary in entry.get("stats", []):
			var mod: StatMod = stat_from_record(stat, "Умение: за %s ×%d" % [ATTRIBUTE_NAMES_RU[index], n])
			store.add(mod.scaled(float(n)))
	for entry: Dictionary in ability.get("levelScaling", []):
		for stat: Dictionary in entry.get("stats", []):
			var mod: StatMod = stat_from_record(stat, "Умение: за уровень персонажа ×%d" % build.level)
			store.add(mod.scaled(float(build.level)))


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
		var expr := Expression.new()
		if expr.parse(str(raw["expr"]), ["p"]) == OK:
			var out: Variant = expr.execute([float(points)])
			if out is float or out is int:
				return float(out)
		return 0.0
	return float(raw.get("per_point", 0.0)) * points + float(raw.get("flat", 0.0))


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
		parts.append("свойство умения %s" % stat["abilityID"])
	if stat.has("playerPropertyName"):
		parts.append(str(stat["playerPropertyName"]))
	return " / ".join(parts) if not parts.is_empty() else str(effect.get("op", "эффект"))
