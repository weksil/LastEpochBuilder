class_name SkillComponents

## Damage components of a skill: the primary hit, sub-abilities spawned by the prefab, damage computed in code,
## tree/unique components and triggers (docs/ENGINE.md §9.3).
## component = {name, kind: primary|sub|trigger|minion, ab, base, per_use, rate, note}.

const SUB_REASONS: Array[String] = [
	"prefab:CreateAbilityObjectOnDeath", "prefab:CreateAbilityObjectOnStart", "prefab:CastAfterDuration",
]
const TYPE_ORDER: Array[String] = ["Physical", "Fire", "Cold", "Lightning", "Necrotic", "Void", "Poison"]


static func collect(build: Node, slot: int, ab: Dictionary, s: Dictionary, out_notes: Array[String] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ab_name: String = str(ab.get("name", ""))
	var primary: Dictionary = ab.get("primaryDamage", {}) if ab.get("primaryDamage") is Dictionary else {}
	if not primary.is_empty():
		result.append(_component(str(ab.get("abilityName", ab_name)), "primary", ab, primary, 1.0, 0.0, ""))

	for sub: Dictionary in GameData.sub_abilities(ab_name):
		if not _is_spawned(str(sub.get("spawn_reason", ""))):
			continue
		var entry: Dictionary = _first_damage(sub)
		if entry.is_empty():
			continue
		result.append(_component(str(sub.get("name", "")), "sub", sub, entry, 1.0, 0.0, str(sub.get("spawn_reason", "")).trim_prefix("prefab:")))

	if primary.is_empty():
		_add_code_damage(result, ab_name, ab, out_notes)

	for extra: Variant in s.get("components", []):
		if not extra is Dictionary:
			continue
		var sub: Dictionary = GameData.ability_by_name(str(extra.get("ability", "")))
		var entry: Dictionary = _first_damage(sub)
		if entry.is_empty():
			_skip_note(out_notes, "Узел «%s»: у под-умения «%s» нет урона — не учтено." % [extra.get("node", "?"), extra.get("ability", "?")])
			continue
		result.append(_component(str(sub.get("name", "")), "sub", sub, entry, float(extra.get("count", 1.0)), 0.0, "узел «%s»" % extra.get("node", "")))

	for trig: Variant in s.get("triggers", []):
		if not trig is Dictionary:
			continue
		var sub: Dictionary = GameData.ability_by_name(str(trig.get("ability", "")))
		var entry: Dictionary = _first_damage(sub)
		if entry.is_empty():
			_skip_note(out_notes, "Триггер «%s»: у умения «%s» нет урона — не учтено." % [trig.get("label", "?"), trig.get("ability", "?")])
			continue
		var rate: float = float(trig.get("rate", 0.0))
		if rate <= 0.0:
			continue
		var label: String = str(trig.get("label", ""))
		result.append(_component(label if label != "" else str(sub.get("name", "")), "trigger", sub, entry, 1.0, rate, str(trig.get("note", label))))

	# minions summoned by the skill (§9.4): own stores built from the player's snapshot
	if not MinionCalc.minions_for(ab_name).is_empty() and s.get("store") is StatStore:
		var count: float = 0.0
		if slot >= 0 and slot < build.skills.size():
			count = float(build.skills[slot].get("inputs", {}).get("minions", 0.0))
		if s.get("inputs") is Array:
			s["inputs"].append({"key": "minions", "label": "Миньонов активно (0 — по лимиту призыва)", "default": 0.0})
		result.append_array(MinionCalc.components(s["store"], ab, s.get("minion_mods", []), count))
	return result


static func _component(comp_name: String, kind: String, ab: Dictionary, base: Dictionary, per_use: float, rate: float, note: String) -> Dictionary:
	return {"name": comp_name, "kind": kind, "ab": ab, "base": base, "per_use": per_use, "rate": rate, "note": note}


static func _is_spawned(reason: String) -> bool:
	for r: String in SUB_REASONS:
		if reason.begins_with(r):
			return true
	return false


## First entry of a record's `damage` list (same shape as primaryDamage), {} if none.
static func _first_damage(rec: Dictionary) -> Dictionary:
	var list: Array = rec.get("damage", [])
	if list.is_empty() or not list[0] is Dictionary:
		return {}
	return list[0]


static func _skip_note(out_notes: Array[String], text: String) -> void:
	if not out_notes.has(text):
		out_notes.append(text)


## Components of abilities_code_damage.json with plain numbers; the rest are only reported in the notes.
static func _add_code_damage(result: Array[Dictionary], ab_name: String, ab: Dictionary, out_notes: Array[String]) -> void:
	var code: Dictionary = GameData.code_damage(ab_name)
	for comp: Dictionary in code.get("components", []):
		var id: String = str(comp.get("id", "")) if comp.get("id") != null else ""
		var label: String = id if id != "" else ab_name
		if not comp.get("damage") is Dictionary or (comp["damage"] as Dictionary).is_empty():
			continue
		var damage: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var numeric: bool = true
		for type_name: String in comp["damage"]:
			var v: Variant = comp["damage"][type_name]
			var idx: int = TYPE_ORDER.find(type_name)
			if (v is float or v is int) and idx >= 0:
				damage[idx] = float(v)
			else:
				numeric = false
		if not numeric:
			_skip_note(out_notes, "Урон «%s» у умения «%s» считается кодом по значениям узлов, а не числом — не учтён." % [label, ab_name])
			continue
		var ade_v: Variant = comp.get("ADE")
		var crit_v: Variant = comp.get("crit")
		var hit_v: Variant = comp.get("isHit")
		var is_hit: bool = bool(hit_v) if hit_v != null else crit_v is Dictionary
		var base: Dictionary = {
			"damage": damage, "critChance": 0.0, "critMultiplier": 1.0, "critType": 1,
			"addedDamageScaling": float(ade_v) if (ade_v is float or ade_v is int) else 0.0,
			"isHit": 1 if is_hit else 0, "go": "",
		}
		if crit_v is Dictionary:
			base["critChance"] = float(crit_v.get("chance", 0.0))
			base["critMultiplier"] = float(crit_v.get("multiplier", 1.0))
			base["critType"] = 0
		result.append(_component(label, "sub", ab, base, 1.0, 0.0, "урон кодом (abilities_code_damage.json)"))
