class_name UniqueEffects

## Special effects of equipped uniques (docs/ENGINE.md §5.4.3). PlayerProperty / AbilityProperty effects that have a
## planner model in unique_effect_models.json become StatMods; everything else is listed in notes with the reason.

const DERIVED_SOURCES: Array[String] = ["GlobalConditionalDamage(more)", "DamagePerStackOfAilment", "AilmentConversion"]


## Every special effect of the equipped uniques: {slot, unique, effect, model, pp, label, ability_index}.
static func entries(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: String in build.items:
		var item: Dictionary = build.items[slot]
		if not item.has("unique"):
			continue
		var u: Dictionary = GameData.unique(int(item["unique"]))
		if u.is_empty():
			continue
		for effect: Dictionary in GameData.unique_effects(int(item["unique"])):
			var src: String = str(effect.get("source", ""))
			var model: Dictionary = {}
			var ability_index: int = -1
			if src == "PlayerProperty":
				model = GameData.unique_player_model(int(effect.get("ppIndex", -1)))
			elif src == "AbilityProperty":
				ability_index = int(effect.get("abilityIndex", -1))
				model = GameData.unique_ability_model(ability_index, int(effect.get("propertyIndex", -1)))
			out.append({
				"slot": slot, "item": item, "unique": u, "effect": effect, "model": model, "ability_index": ability_index,
				"pp": _effect_value(u, item, effect),
				"label": "%s: %s — %s" % [ItemMods.slot_label(slot, item), GameData.display_name(u), str(effect.get("name", src))],
			})
	return out


## Character-wide models. Phase "pre" runs before attributes are converted to stats, "post" after (sources read the store).
static func apply_global(build: Node, store: StatStore, notes: Array[String], phase: String) -> void:
	for e: Dictionary in entries(build):
		var model: Dictionary = e["model"]
		if model.is_empty() or e["ability_index"] >= 0 or model.has("skill_any") or EffectModels.phase(model) != phase:
			continue
		var ctx: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": e["slot"]}
		var reason: String = EffectModels.blocked(model, ctx)
		if reason != "":
			notes.append("%s — учитывается при условии: %s" % [e["label"], reason])
			continue
		if str(model.get("kind", "stat")) == "overcap_taken":
			_apply_overcap_taken(store, e)
			continue
		var mod: StatMod = EffectModels.make_mod(model, e["pp"], ctx, e["label"])
		if mod != null:
			store.add(mod)


## Skill-local models: AbilityProperty of this ability and player models limited to skill tags («skill_any»).
static func apply_skill(build: Node, ability: Dictionary, result: Dictionary) -> void:
	var store: StatStore = result["store"]
	var ability_index: int = int(ability.get("abilityIDEnum", {}).get("value", -2))
	var ability_tags: int = int(ability.get("tags", 0))
	for e: Dictionary in entries(build):
		var model: Dictionary = e["model"]
		if model.is_empty():
			continue
		if e["ability_index"] >= 0:
			if e["ability_index"] != ability_index:
				continue
		elif not model.has("skill_any") or (ability_tags & LE.tag_mask(str(model["skill_any"]))) == 0:
			continue
		var ctx: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": e["slot"]}
		var reason: String = EffectModels.blocked(model, ctx)
		if reason != "":
			result["notes"].append("%s — учитывается при условии: %s" % [e["label"], reason])
			continue
		if str(model.get("kind", "stat")) == "mana_added":
			result["mana_added"] += e["pp"]
			result["mana_sources"].append("%s %s" % [LE.fmt_num(e["pp"]), e["label"]])
			continue
		var mod: StatMod = EffectModels.make_mod(model, e["pp"], ctx, e["label"])
		if mod != null:
			store.add(mod)


## Notes for effects without a model (or modelled for a skill that is not on the bar).
static func add_notes(build: Node, notes: Array[String]) -> void:
	var bar: Dictionary = {}
	for skill: Dictionary in build.skills:
		var ab: Dictionary = GameData.get_ability(str(skill.get("ability", "")))
		if not ab.is_empty():
			bar[int(ab.get("abilityIDEnum", {}).get("value", -2))] = true
	for e: Dictionary in entries(build):
		var effect: Dictionary = e["effect"]
		var src: String = str(effect.get("source", ""))
		if DERIVED_SOURCES.has(src):
			continue  # ordinary mods of the item (SP 100 / 115 / 117), computed by the engine
		if not e["model"].is_empty():
			if e["ability_index"] >= 0 and not bar.has(e["ability_index"]):
				notes.append("%s — действует только на умение «%s», его нет на панели" % [e["label"], str(effect.get("ability", "?"))])
			continue
		notes.append("%s — %s" % [e["label"], _unmodelled_reason(effect)])
	for slot: String in build.items:
		var item: Dictionary = build.items[slot]
		if not item.has("unique"):
			continue
		var u: Dictionary = GameData.unique(int(item["unique"]))
		for umod: Dictionary in u.get("mods", []):
			if int(umod.get("property", 0)) == LE.LEVEL_OF_SKILLS:
				notes.append("%s: %s — +%s к уровню умений, поднимите уровень умения в слоте вручную" % [
					ItemMods.slot_label(slot, item), GameData.display_name(u), LE.fmt_num(float(umod.get("value", 0.0)))])


# --- value of the effect ----------------------------------------------------------

## Roll of the unique mod that carries the effect (property 98 tags = ppIndex, property 58 tags = AbilityID, specialTag = index).
static func _effect_value(u: Dictionary, item: Dictionary, effect: Dictionary) -> float:
	var src: String = str(effect.get("source", ""))
	var rolls: Array = item.get("unique_rolls", [])
	for umod: Dictionary in u.get("mods", []):
		var prop: int = int(umod.get("property", -1))
		var hit: bool = false
		if src == "PlayerProperty":
			hit = prop == LE.PLAYER_PROPERTY and int(umod.get("tags", -1)) == int(effect.get("ppIndex", -2))
		elif src == "AbilityProperty":
			hit = prop == LE.ABILITY_PROPERTY and int(umod.get("tags", -1)) == int(effect.get("abilityIndex", -2)) \
				and int(umod.get("specialTag", -1)) == int(effect.get("propertyIndex", -2))
		if hit:
			var roll_id: int = int(umod.get("rollID", 0)) if umod.get("rollID") != null else 0
			var roll: int = int(rolls[roll_id]) if roll_id < rolls.size() else 255
			return AffixMath.unique_value(umod, roll)
	return float(effect.get("value", {}).get("max", 0.0))


## Null Portent: for each damage type with uncapped resistance above 75%: more damage taken max(−cap, (res − 0.75)/0.02 · pp).
static func _apply_overcap_taken(store: StatStore, e: Dictionary) -> void:
	var cap_effect: Dictionary = {"source": "PlayerProperty", "ppIndex": int(e["model"].get("cap_pp", -1))}
	var cap: float = absf(_effect_value(e["unique"], e["item"], cap_effect))
	var mods: Array[StatMod] = []
	for i in range(7):
		var res: float = Enemy.resistance(store, i).value()
		if res <= 0.75:
			continue
		var x: float = maxf(-cap, (res - 0.75) / 0.02 * float(e["pp"]))
		mods.append(StatMod.make(LE.DAMAGE_TAKEN, "more", x, LE.DT_TAG[i],
			"%s (%s сверх капа %s)" % [e["label"], LE.DT_NAME_RU[i], LE.fmt_pct(res - 0.75)]))
	store.add_all(mods)


static func _unmodelled_reason(effect: Dictionary) -> String:
	var src: String = str(effect.get("source", ""))
	var pm: String = str(effect.get("plannerModel", ""))
	if src == "IdolAltarProperty":
		return "свойство алтаря идолов, алтари не поддерживаются"
	if pm in ["flag", "util", "skillMechanicFlag"]:
		return "не влияет на урон и защиту в расчёте"
	if pm in ["proc", "skillProc/chance"] or src.begins_with("Component"):
		return "срабатывание или отдельная механика, не моделируется (в коде: %s)" % str(effect.get("formula", ""))
	return "не моделируется (в коде: %s)" % str(effect.get("formula", ""))
