class_name UniqueEffects

## Special effects of equipped uniques (docs/ENGINE.md §5.4.3). PlayerProperty / AbilityProperty effects that have a
## planner model in unique_effect_models.json become StatMods; everything else is listed in notes with the reason.

const SKILL_KINDS: Array[String] = ["trigger", "component", "minion_stat", "param", "resource", "speed", "mana", "cooldown"]
const DERIVED_SOURCES: Array[String] = ["GlobalConditionalDamage(more)", "DamagePerStackOfAilment", "AilmentConversion"]
## Trigger events of the character, not of a skill's own uses or hits: such an item trigger is attached to one skill
## only (the first filled slot), otherwise every skill on the bar would count it again.
const BAR_SIZE: int = 5
const CHARACTER_EVENTS: Array[String] = ["second", "hit_taken", "block", "dodge", "potion"]
## Event of SP 127 ChanceToCastForTags by its specialTag.
const CAST_FOR_TAGS_EVENTS: Dictionary = {1: "hit", 2: "crit"}


## Every special effect of the equipped uniques: {slot, unique, effect, model, pp, label, ability_index}. Cached by the
## items and the locale (CalcCache): the entries are shared and must not be changed.
static func entries(build: Node) -> Array[Dictionary]:
	var key: PackedByteArray = var_to_bytes([build.items, build.passives, build.class_id, build.mastery, TranslationServer.get_locale()])
	var hit: Variant = CalcCache.lookup("unique_entries", key)
	if hit == null:
		hit = _entries(build)
		CalcCache.put("unique_entries", key, hit)
	return hit


static func _entries(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: String in build.items:
		var item: Dictionary = build.items[slot]
		if not item.has("unique"):
			continue
		var u: Dictionary = GameData.unique(int(item["unique"]))
		if u.is_empty():
			continue
		var effects: Array = GameData.unique_effects(int(item["unique"]))
		for effect_index: int in range(effects.size()):
			var effect: Dictionary = effects[effect_index]
			var src: String = str(effect.get("source", ""))
			var model: Dictionary = {}
			var ability_index: int = -1
			if src == "PlayerProperty":
				model = GameData.unique_player_model(int(effect.get("ppIndex", -1)))
			elif src == "AbilityProperty":
				ability_index = int(effect.get("abilityIndex", -1))
				model = GameData.unique_ability_model(ability_index, int(effect.get("propertyIndex", -1)))
			elif src.begins_with("Component"):
				# unique_effect_models.json "component": key "uniqueID:effectIndex", the index is the position in the unique's effects
				model = GameData.unique_component_model(int(item["unique"]), effect_index)
			var label: String = "%s: %s" % [ItemMods.slot_label(slot, item), GameData.display_name(u)]
			if not src.begins_with("Component"):  # a component effect has no name of its own (the raw class name must not reach the UI)
				label += " — %s" % str(effect.get("name", src))
			out.append({
				"slot": slot, "item": item, "unique": u, "effect": effect, "model": model, "ability_index": ability_index,
				"pp": _effect_value(u, item, effect),
				"label": label,
			})
	out.append_array(_passive_property_entries(build))
	out.append_array(_set_entries(build))
	out.append_array(_affix_triggers(build))
	return out


## Planner model of the PlayerProperty / AbilityProperty stat of a passive effect ({} if the effect is something else or has no model).
static func property_effect_model(effect: Dictionary) -> Dictionary:
	var stat: Variant = effect.get("stat")
	if effect.get("op") != "add_stat" or not stat is Dictionary:
		return {}
	match str(stat.get("kind", "")):
		"player_property", "more_player_property":
			return GameData.unique_player_model(int(str(stat.get("playerPropertyIndex", "-1"))))
		"ability_property", "more_ability_property":
			return GameData.unique_ability_model(BuildMods.ability_index_of(str(stat.get("abilityID", ""))), int(str(stat.get("abilityPropertyIndex", "-1"))))
	return {}


## PlayerProperty / AbilityProperty stats of allocated passives, in the format of `entries`. Effects that ShadowCalc / MinionCalc
## count themselves (handles_effect) are left out; effects without a model keep the old "not counted" note.
static func _passive_property_entries(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in BuildMods._passive_entries(build):
		var points: int = entry["points"]
		for effect: Dictionary in (entry["node"] as Dictionary).get("effects", []):
			if points < int(effect.get("minPoints", 0)):
				continue
			var model: Dictionary = property_effect_model(effect)
			if model.is_empty() or ShadowCalc.handles_effect(effect) or MinionCalc.handles_effect(effect):
				continue
			var stat: Dictionary = effect["stat"]
			var is_player: bool = str(stat["kind"]).ends_with("player_property")
			var label_name: String = str(stat.get("playerPropertyName", stat.get("abilityID", "")))
			var record: Dictionary = {"source": "PassivePlayerProperty" if is_player else "PassiveAbilityProperty", "name": label_name}
			if is_player:
				record["ppIndex"] = int(str(stat.get("playerPropertyIndex", "-1")))
			else:
				record["ability"] = str(stat.get("abilityID", ""))
			out.append({
				"slot": "", "item": {}, "unique": {}, "effect": record, "model": model,
				"ability_index": -1 if is_player else BuildMods.ability_index_of(str(stat.get("abilityID", ""))),
				"pp": BuildMods.eval_value(stat.get("value"), points),
				"label": "%s — %s" % [entry["source"], label_name],
			})
	return out


## Active set bonuses of type PlayerProperty (98) / AbilityProperty (58): same shape and sources as a unique's effect.
static func _set_entries(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var counts: Dictionary = BuildMods.set_counts(build)
	for set_id: int in counts:
		var st: Dictionary = GameData.set_data(set_id)
		var count: int = counts[set_id]
		var source: String = LE.t("Set \"%s\" (%d items)") % [str(st.get("setName", set_id)), count]
		for bonus: Dictionary in st.get("bonuses", []):
			var prop_id: int = int(bonus.get("property", 0))
			if int(bonus.get("setRequirement", 99)) > count or (prop_id != LE.PLAYER_PROPERTY and prop_id != LE.ABILITY_PROPERTY):
				continue
			var value: float = AffixMath.fixed_value(float(bonus.get("value", 0.0)), str(bonus.get("rounding", "Hundredth")), str(bonus.get("modType", "ADDED")))
			var tag: int = int(bonus.get("tags", 0))
			var record: Dictionary = {}
			var model: Dictionary = {}
			var ability_index: int = -1
			var label_name: String = ""
			if prop_id == LE.PLAYER_PROPERTY:
				var info: Dictionary = GameData.player_property_info(tag)
				label_name = str(info.get("propertyName", "PlayerProperty %d" % tag))
				record = {"source": "PlayerProperty", "ppIndex": tag, "name": label_name, "formula": str(info.get("field", ""))}
				model = GameData.unique_player_model(tag)
			else:
				var special: int = int(bonus.get("specialTag", 0))
				ability_index = tag
				label_name = "AbilityProperty %d:%d" % [tag, special]
				record = {"source": "AbilityProperty", "abilityIndex": tag, "propertyIndex": special, "name": label_name,
					"ability": str(GameData.ability_by_index(tag).get("abilityName", "?"))}
				model = GameData.unique_ability_model(tag, special)
			out.append({"slot": "", "item": {}, "unique": {}, "effect": record, "model": model, "ability_index": ability_index,
				"pp": value, "label": "%s — %s" % [source, label_name]})
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
				"ability_index": ability_index, "pp": _affix_value(mod),
				"label": "%s — %s" % [mod.source, LE.t("chance to cast %s") % cast_title],
			})
	return out


## Value of an affix mod that carries a trigger chance: added, increased or more (the data has only added ones for triggers).
static func _affix_value(mod: StatMod) -> float:
	var v: float = mod.added + mod.increased
	for m: float in mod.more:
		v += m
	return v


## Character-wide models. Phase "pre" runs before attributes are converted to stats, "post" after (sources read the store).
## Only stat models with global scope become StatMods here; skill-level kinds are applied by apply_skill.
static func apply_global(build: Node, store: StatStore, notes: Array[String], phase: String) -> void:
	var input_slot: int = first_skill_slot(build)  # a character-wide model reads its inputs from the first damaging skill (apply_skill declares them there)
	# model key «converts»: stat name -> {amount, label}, removed from that stat after the loop (both Salt the Wound models read the same total)
	var converted: Dictionary = {}
	for e: Dictionary in entries(build):
		var model: Dictionary = e["model"]
		if model.is_empty() or e["ability_index"] >= 0 or _is_skill_filtered(model) or EffectModels.phase(model) != phase:
			continue
		var kind: String = str(model.get("kind", "stat"))
		if kind == "resource":
			if phase == "pre":
				notes.append(LE.t("%s: %s (special effect, does not affect the damage calculation)") % [e["label"], LE.t(str(model.get("label", model.get("resource", ""))))])
			continue
		if (kind != "stat" and kind != "overcap_taken") or _is_skill_scoped(model):
			continue  # flag is listed by add_notes; trigger / param / speed … are skill-level; conversion is handled by §5.5
		var ctx: Dictionary = {"build": build, "store": store, "slot": -1, "item_slot": e["slot"], "input_slot": input_slot}
		var reason: String = EffectModels.blocked(model, ctx)
		if reason != "":
			notes.append(LE.t("%s — counted when: %s") % [e["label"], reason])
			continue
		if kind == "overcap_taken":
			_apply_overcap_taken(store, e)
			continue
		for mod: StatMod in EffectModels.make_mods(model, e["pp"], ctx, e["label"]):
			store.add(mod)
			if model.has("converts"):
				var stat_key: String = str(model["converts"])
				var acc: Dictionary = converted.get(stat_key, {"amount": 0.0, "label": e["label"]})
				acc["amount"] = float(acc["amount"]) + mod.added
				converted[stat_key] = acc
	for stat_key: Variant in converted:
		var property: int = GameData.sp_id(str(stat_key))
		var amount: float = float(converted[stat_key]["amount"])
		if property >= 0 and amount != 0.0:
			store.add(StatMod.make(property, "added", -amount, 0, LE.t("%s — converted to ailment effect") % str(converted[stat_key]["label"])))


## Skill-local models: AbilityProperty of this ability, player / component models of skill-level kinds (trigger, component,
## minion_stat, param, resource, speed, mana, cooldown) and player models limited to skills («skill_any»: one of the tags,
## «skill_all»: all the tags, «skill_flag»: a true flag of the ability record).
static func apply_skill(build: Node, ability: Dictionary, result: Dictionary) -> void:
	var store: StatStore = result["store"]
	var ability_index: int = int(ability.get("abilityIDEnum", {}).get("value", -2))
	var ability_tags: int = int(ability.get("tags", 0))
	var input_slot: int = first_skill_slot(build)
	var is_input_slot: bool = int(result["ctx"].get("slot", -1)) == input_slot
	for e: Dictionary in entries(build):
		var model: Dictionary = e["model"]
		if model.is_empty():
			continue
		if EffectModels.phase(model) == "skill":
			continue  # cost models are applied by BuildMods._add_cost_models
		var kind: String = str(model.get("kind", "stat"))
		var routed: bool = false
		if e["ability_index"] >= 0:
			if e["ability_index"] != ability_index:
				continue
			routed = kind != "mana_added"
		elif model.has("skill_mask") or _is_skill_filtered(model):
			if model.has("skill_mask"):
				if (ability_tags & int(model["skill_mask"])) == 0:
					continue
			elif not _skill_matches(model, ability, ability_tags):
				continue
			routed = kind == "trigger" or kind == "stat"  # the model's inputs, use conditions and scope are honoured
		elif SKILL_KINDS.has(kind) or (kind == "stat" and _is_skill_scoped(model)):
			routed = true
		else:
			# a character-wide stat model (applied by apply_global) keeps its input row on the first damaging skill
			if is_input_slot and kind == "stat" and e["ability_index"] < 0:
				for inp: Dictionary in EffectModels.inputs(model):
					result["inputs"].append(EffectModels.declared_input(inp, {"build": build, "slot": -1}))
			continue
		if routed and kind == "trigger" and CHARACTER_EVENTS.has(str(model.get("on", ""))) 				and int(result["ctx"].get("slot", -1)) != first_skill_slot(build):
			continue
		# a use triggered by another skill is not a direct use: item triggers on use / cast do not fire from it
		if routed and kind == "trigger" and str(result["ctx"].get("use", "")) == "triggered" and ["use", "cast", "end"].has(str(model.get("on", "use"))):
			continue
		if routed:
			var ctx: Dictionary = result["ctx"]
			var prev_slot: Variant = ctx.get("item_slot", "")
			ctx["item_slot"] = e["slot"]
			ctx["character"] = e["ability_index"] < 0  # PlayerProperty / affix casts are made by the character
			BuildMods._apply_model(model, e["pp"], e["label"], e["label"], result)
			ctx.erase("character")
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
		for mod: StatMod in EffectModels.make_mods(model, e["pp"], ctx2, e["label"]):
			store.add(mod)


## Slot of the bar that character-level triggers (item and passive triggers on "second", hit taken, kill …) are counted in:
## the first skill that deals damage by itself (a buff such as Enchant Weapon would only show them as a side effect), else the
## first filled slot, -1 if the bar is empty.
static func first_skill_slot(build: Node) -> int:
	var filled: int = -1
	for slot: int in range(mini(build.skills.size(), BAR_SIZE)):  # not the temporary slot of the basic attack (GrantedCalc)
		var ab: Dictionary = GameData.get_ability(str((build.skills[slot] as Dictionary).get("ability", "")))
		if ab.is_empty():
			continue
		if filled < 0:
			filled = slot
		if ab.get("primaryDamage") is Dictionary and not (ab["primaryDamage"] as Dictionary).is_empty():
			return slot
	return filled


## The model applies to some skills only (see apply_skill).
static func _is_skill_filtered(model: Dictionary) -> bool:
	return model.has("skill_any") or model.has("skill_all") or model.has("skill_flag")


static func _skill_matches(model: Dictionary, ability: Dictionary, ability_tags: int) -> bool:
	if model.has("skill_any") and (ability_tags & LE.tag_mask(str(model["skill_any"]))) == 0:
		return false
	if model.has("skill_all"):
		var need: int = LE.tag_mask(str(model["skill_all"]))
		if (ability_tags & need) != need:
			return false
	return not model.has("skill_flag") or bool(ability.get(str(model["skill_flag"]), 0))


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
		if src == "PlayerProperty" and MinionCount.COMPANION_FLAGS.has(int(effect.get("ppIndex", -1))):
			continue  # companion limit flags: counted by MinionCount.max_companions / limit_of
		if e["ability_index"] == ShadowCalc.ABILITY_INDEX and ShadowCalc.HANDLED.has(int(effect.get("propertyIndex", -1))):
			continue  # CreateShadow properties: counted by the shadow components (ShadowCalc)
		if e["ability_index"] >= 0 and MinionCalc.handles_property(int(e["ability_index"]), int(effect.get("propertyIndex", -1))):
			continue  # summon limits / minion stats: counted by MinionCount / MinionCalc
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
	if src.begins_with("Component"):
		return 1.0  # no rolled carrier mod: the model of the component holds its own constants (factor, chance, ...)
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
