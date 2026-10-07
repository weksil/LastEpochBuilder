class_name UniqueEffects

## Special effects of equipped uniques (docs/ENGINE.md §5.4.3). PlayerProperty / AbilityProperty effects that have a
## planner model in unique_effect_models.json become StatMods; everything else is listed in notes with the reason.

const SKILL_KINDS: Array[String] = ["trigger", "component", "minion_stat", "param", "resource", "speed", "mana", "cooldown"]
const DERIVED_SOURCES: Array[String] = ["GlobalConditionalDamage(more)", "DamagePerStackOfAilment", "AilmentConversion"]
## Trigger events of the character, not of a skill's own uses or hits: such an item trigger is attached to one skill
## only (the first filled slot), otherwise every skill on the bar would count it again.
const CHARACTER_EVENTS: Array[String] = ["second", "hit_taken", "block", "dodge", "potion"]
## Event of SP 127 ChanceToCastForTags by its specialTag.
const CAST_FOR_TAGS_EVENTS: Dictionary = {1: "hit", 2: "crit"}


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
	out.append_array(_affix_triggers(build))
	return out


## "Chance to cast X" affixes of items and idols (SP 98 / 58 with a trigger model, SP 127 ChanceToCastForTags): entries
## in the format of `entries`. Only trigger models are taken: other SP 98 / 58 affix effects are not modelled for affixes.
static func _affix_triggers(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: String in build.items:
		if not (BuildMods.SLOTS.has(slot) or IdolGrid.is_idol_key(slot)):
			continue
		var item: Dictionary = build.items[slot]
		for mod: StatMod in ItemMods.item_mods(slot, item):
			var model: Dictionary = {}
			var ability_index: int = -1
			if mod.property == LE.PLAYER_PROPERTY:
				model = GameData.unique_player_model(mod.tags)
			elif mod.property == LE.ABILITY_PROPERTY:
				ability_index = mod.tags
				model = GameData.unique_ability_model(mod.tags, mod.special)
			elif mod.property == LE.CHANCE_TO_CAST_FOR_TAGS and CAST_FOR_TAGS_EVENTS.has(mod.special):
				var cast: Dictionary = GameData.ability_by_index(mod.extra)
				if not cast.is_empty():
					model = {"kind": "trigger", "ability": str(cast.get("name", "")), "on": CAST_FOR_TAGS_EVENTS[mod.special],
						"chance": "v", "skill_mask": mod.tags}
			if str(model.get("kind", "")) != "trigger":
				continue
			var cast_name: String = str(model.get("ability", ""))
			var cast_title: String = str(GameData.ability_by_name(cast_name).get("abilityName", cast_name))
			out.append({
				"slot": slot, "item": item, "unique": {}, "effect": {"source": "Affix", "ability": cast_name}, "model": model,
				"ability_index": ability_index, "pp": mod.added,
				"label": "%s — %s" % [mod.source, LE.t("chance to cast %s") % cast_title],
			})
	return out


## Character-wide models. Phase "pre" runs before attributes are converted to stats, "post" after (sources read the store).
## Only stat models with global scope become StatMods here; skill-level kinds are applied by apply_skill.
static func apply_global(build: Node, store: StatStore, notes: Array[String], phase: String) -> void:
	for e: Dictionary in entries(build):
		var model: Dictionary = e["model"]
		if model.is_empty() or e["ability_index"] >= 0 or model.has("skill_any") or EffectModels.phase(model) != phase:
			continue
		var kind: String = str(model.get("kind", "stat"))
		if kind == "resource":
			if phase == "pre":
				notes.append(LE.t("%s: %s (special effect, does not affect the damage calculation)") % [e["label"], LE.t(str(model.get("label", model.get("resource", ""))))])
			continue
		if (kind != "stat" and kind != "overcap_taken") or _is_skill_scoped(model):
			continue  # flag is listed by add_notes; trigger / param / speed … are skill-level; conversion is handled by §5.5
		var ctx: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": e["slot"]}
		var reason: String = EffectModels.blocked(model, ctx)
		if reason != "":
			notes.append(LE.t("%s — counted when: %s") % [e["label"], reason])
			continue
		if kind == "overcap_taken":
			_apply_overcap_taken(store, e)
			continue
		var mod: StatMod = EffectModels.make_mod(model, e["pp"], ctx, e["label"])
		if mod != null:
			store.add(mod)


## Skill-local models: AbilityProperty of this ability, player / component models of skill-level kinds (trigger, component,
## minion_stat, param, resource, speed, mana, cooldown) and player models limited to skill tags («skill_any»).
static func apply_skill(build: Node, ability: Dictionary, result: Dictionary) -> void:
	var store: StatStore = result["store"]
	var ability_index: int = int(ability.get("abilityIDEnum", {}).get("value", -2))
	var ability_tags: int = int(ability.get("tags", 0))
	for e: Dictionary in entries(build):
		var model: Dictionary = e["model"]
		if model.is_empty():
			continue
		var kind: String = str(model.get("kind", "stat"))
		var routed: bool = false
		if e["ability_index"] >= 0:
			if e["ability_index"] != ability_index:
				continue
			routed = kind != "mana_added"
		elif model.has("skill_any") or model.has("skill_mask"):
			var mask: int = int(model["skill_mask"]) if model.has("skill_mask") else LE.tag_mask(str(model["skill_any"]))
			if (ability_tags & mask) == 0:
				continue
			routed = kind == "trigger"
		elif SKILL_KINDS.has(kind) or (kind == "stat" and _is_skill_scoped(model)):
			routed = true
		else:
			continue
		if routed and kind == "trigger" and CHARACTER_EVENTS.has(str(model.get("on", ""))) 				and int(result["ctx"].get("slot", -1)) != first_skill_slot(build):
			continue
		if routed:
			var ctx: Dictionary = result["ctx"]
			var prev_slot: Variant = ctx.get("item_slot", "")
			ctx["item_slot"] = e["slot"]
			BuildMods._apply_model(model, e["pp"], e["label"], e["label"], result)
			ctx["item_slot"] = prev_slot
			continue
		var ctx2: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": e["slot"]}
		var reason: String = EffectModels.blocked(model, ctx2)
		if reason != "":
			result["notes"].append(LE.t("%s — counted when: %s") % [e["label"], reason])
			continue
		if kind == "mana_added":
			result["mana_added"] += e["pp"]
			result["mana_sources"].append("%s %s" % [LE.fmt_num(e["pp"]), e["label"]])
			continue
		var mod: StatMod = EffectModels.make_mod(model, e["pp"], ctx2, e["label"])
		if mod != null:
			store.add(mod)


## First slot of the bar that holds a skill (-1 if none): character-event item triggers are counted there.
static func first_skill_slot(build: Node) -> int:
	for slot: int in range(build.skills.size()):
		if str((build.skills[slot] as Dictionary).get("ability", "")) != "":
			return slot
	return -1


## Stat model that belongs to the skill (minion or damage-component scope), not to the character.
static func _is_skill_scoped(model: Dictionary) -> bool:
	var scope: String = str(model.get("scope", "global"))
	return scope == "minion" or scope.begins_with("component:")


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
		if e["ability_index"] == ShadowCalc.ABILITY_INDEX and ShadowCalc.HANDLED.has(int(effect.get("propertyIndex", -1))):
			continue  # CreateShadow properties: counted by the shadow components (ShadowCalc)
		if e["ability_index"] == EnemyAilments.FINISHER_INDEX and int(effect.get("propertyIndex", -1)) == 0:
			continue  # Shadow Daggers more damage vs rares and bosses: counted by the finisher component
		if not e["model"].is_empty():
			if str(e["model"].get("kind", "")) == "flag":
				notes.append("%s — %s" % [e["label"], LE.t(str(e["model"].get("text", "")))])
			elif e["ability_index"] >= 0 and not bar.has(e["ability_index"]):
				notes.append(LE.t("%s — applies only to skill \"%s\", it is not on the skill bar") % [e["label"], str(effect.get("ability", "?"))])
			continue
		notes.append("%s — %s" % [e["label"], _unmodelled_reason(effect)])
	# +levels of skills (SP 88) raise the skill-tree point cap (Build.skill_point_cap)


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
			LE.t("%s (%s above cap %s)") % [e["label"], LE.t(LE.DT_NAME[i]), LE.fmt_pct(res - 0.75)]))
	store.add_all(mods)


static func _unmodelled_reason(effect: Dictionary) -> String:
	var src: String = str(effect.get("source", ""))
	var pm: String = str(effect.get("plannerModel", ""))
	if src == "IdolAltarProperty":
		return LE.t("idol altar property, altars are not supported")
	if pm in ["flag", "util", "skillMechanicFlag"]:
		return LE.t("does not affect damage or defence in the calculation")
	if pm in ["proc", "skillProc/chance"] or src.begins_with("Component"):
		return LE.t("trigger or a separate mechanic, not modelled (in code: %s)") % str(effect.get("formula", ""))
	return LE.t("not modelled (in code: %s)") % str(effect.get("formula", ""))
