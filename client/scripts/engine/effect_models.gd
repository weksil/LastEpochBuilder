class_name EffectModels

## Effect model computation for unique items and skill tree nodes (docs/ENGINE.md §9.2).
## Context: ctx = {build: Node, store: StatStore, slot: int, item_slot: String}

const ATTR_SP: Dictionary = {"str": LE.STRENGTH, "vit": LE.VITALITY, "int": LE.INTELLIGENCE, "dex": LE.DEXTERITY, "att": LE.ATTUNEMENT}
const ATTR_NAMES: Dictionary = {"str": "Strength", "vit": "Vitality", "int": "Intelligence", "dex": "Dexterity", "att": "Attunement"}
## Hidden attributes of a corrupted attribute ("Vitality Converted to Rampancy", 07a §2.2), by attribute key.
const CONVERTED_NAMES: Dictionary = {"str": "Brutality", "vit": "Rampancy", "int": "Madness", "dex": "Guile", "att": "Apathy"}
const TWO_HANDED_MELEE_TYPES: Array[int] = [12, 13, 14, 15, 16]  # 2H axes, maces, polearms, staffs, swords
const PLAYER_FLAG_NAMES: Dictionary = {
	"hit_recently": "Hit recently", "crit_recently": "Crit recently", "moving": "Moving",
	"leeching": "Leech active", "low_mana": "Mana below 50%", "haste": "Haste on me", "frenzy": "Frenzy on me",
	"low_life": "Low health", "high_life": "Health above 65%",
	"killed_recently": "Killed recently", "minion_killed_recently": "Minions killed recently",
	"transformed": "Transformed",
}
const PLAYER_VALUE_NAMES: Dictionary = {
	"ward": "Current ward", "curses": "Curses on me", "ignite_stacks": "Ignite stacks on me", "damned_stacks": "Damned stacks on me",
	"shadows": "Active shadows",
}
const STORE_SOURCES: Array[String] = ["attr", "total_attr", "added", "value", "increased", "added_exact", "increased_exact", "res", "ele_res",
	"total_res", "max_health", "max_mana", "endurance_threshold", "converted_attr", "ailment_chance", "total_modifier", "stat_value", "total_added"]


## "" if the model applies now, otherwise the unmet condition (translated).
static func blocked(model: Dictionary, ctx: Dictionary) -> String:
	ConfigRelevance.note_model(model, ctx)
	if model.has("at_least"):
		var v: float = source(str(model["at_least"]["per"]), ctx, model)
		# «value_per_v»: the threshold follows the effect value (Careful Assault: 0.25 more per point, 1 shadow per point)
		var need: float = float(model["at_least"]["value"]) if model["at_least"].has("value") 			else roundf(float(ctx.get("v", 0.0)) * float(model["at_least"].get("value_per_v", 0.0)))
		if v < need:
			return LE.t("%s ≥ %s (now %s)") % [source_name(str(model["at_least"]["per"]), ctx, model), LE.fmt_num(need), LE.fmt_num(v)]
	if model.has("below"):
		var w: float = source(str(model["below"]["per"]), ctx, model)
		if w >= float(model["below"]["value"]):
			return LE.t("%s < %s (now %s)") % [source_name(str(model["below"]["per"]), ctx, model), LE.fmt_num(float(model["below"]["value"])), LE.fmt_num(w)]
	var scales: bool = PRESENCE_KINDS.has(str(model.get("kind", "stat")))
	for cond: String in model.get("when", []):
		if scales:
			var share: float = _ailment_presence(cond, ctx)
			if share >= 0.0:
				if share <= 0.0:
					return condition_name(cond, ctx)
				continue
		if cond.begins_with("input:") and model.has("input") and str(model["input"].get("key", "")) == cond.get_slice(":", 1):
			# the model's own input: unset means its declared default (the UI shows the default, not "off")
			var slot: int = _input_slot(ctx)
			var build: Node = ctx["build"]
			var skill_inputs: Dictionary = build.skills[slot].get("inputs", {}) if slot >= 0 and slot < build.skills.size() else {}
			if not bool(skill_inputs.get(cond.get_slice(":", 1), model["input"].get("default", false))):
				return condition_name(cond, ctx)
			continue
		if not holds(cond, ctx):
			return condition_name(cond, ctx)
	return ""


## Resulting value and the explanation of its source.
static func value(model: Dictionary, v: float, ctx: Dictionary) -> Dictionary:
	var x: float = v * float(model.get("factor", 1.0))
	var text: String = ""
	if model.has("per"):
		var src: float = source(str(model["per"]), ctx, model)
		src = minf(src, source_cap(model, ctx))
		if model.has("steps"):
			# step function of the source: the factor of the last step whose "at_least" the source reaches ("steps_base" below the first)
			var step_factor: float = float(model.get("steps_base", 0.0))
			for step: Variant in model["steps"]:
				if src >= float((step as Dictionary)["at_least"]):
					step_factor = float((step as Dictionary)["factor"])
			x = v * step_factor
			text = "(%s × %s: %s = %s)" % [LE.fmt_num(v), LE.fmt_num(step_factor), source_name(str(model["per"]), ctx, model), LE.fmt_num(src)]
		else:
			x = v * (src - float(model.get("offset", 0.0))) * float(model.get("factor", 1.0))
			text = "(%s × %s = %s)" % [LE.fmt_num(v), source_name(str(model["per"]), ctx, model), LE.fmt_num(src)]
		if bool(model.get("v_caps_source", false)):
			# the effect value is the cap of the source, not a multiplier (Chronostasis: up to v ward consumed per attack)
			x = minf(src, v) * float(model.get("factor", 1.0))
			text = "(min(%s %s, %s) × %s)" % [source_name(str(model["per"]), ctx, model), LE.fmt_num(src), LE.fmt_num(v), LE.fmt_num(float(model.get("factor", 1.0)))]
	if bool(model.get("inverse", false)):
		# a «more» that cancels another one: 1 / (1 + x) − 1
		x = 1.0 / (1.0 + x) - 1.0
		text = "(1 / (1 + %s) − 1)" % LE.fmt_num(v)
	if model.has("effect_of"):
		# CharacterAilmentMutator / CharacterMutator: value × (1 + Stats.GetTotalIncreased(SP 120 EffectOfAilmentOnYou, ailment))
		var effect_f: float = 1.0 + player_store(ctx).query(LE.EFFECT_OF_AILMENT_ON_YOU, 0, GameData.enum_value("AilmentID", str(model["effect_of"]))).increased
		x *= effect_f
		text += LE.t(" (×%s: effect of %s on you)") % [LE.fmt_num(effect_f), str(model["effect_of"])]
	if model.has("min"):
		x = maxf(x, float(model["min"]))
	if model.has("max"):
		x = minf(x, float(model["max"]))
	if model.has("max_field"):
		# the whole value is capped by a CharacterMutator field of the passives (CharacterMutator.UpdateDynamicStat: no cap while it is <= 0)
		var field_cap: float = field_total(str(model["max_field"]), ctx)
		if field_cap > 0.0:
			x = minf(x, field_cap)
	var present: float = presence_factor(model, ctx)
	if present != 1.0:
		x *= present
		text += LE.t(" (present %s of the time)") % LE.fmt_pct(present)
	return {"x": x, "text": text}


## StatMod from the model (null if SP or the ailment is unknown).
static func make_mod(model: Dictionary, v: float, ctx: Dictionary, label: String) -> StatMod:
	var property: int = GameData.sp_id(str(model.get("stat", "")))
	if property < 0:
		return null
	var val_dict: Dictionary = value(model, v, ctx)
	var x: float = val_dict["x"]
	var source_text: String = label
	if val_dict["text"] != "":
		source_text = "%s %s" % [label, val_dict["text"]]
	if model.has("note"):
		source_text += " — " + LE.t(str(model["note"]))
	var special: int = 0
	if model.has("ailment"):
		special = GameData.enum_value("AilmentID", str(model["ailment"]))
		if special < 0:
			return null  # an unknown ailment must not become special 0 (= every ailment)
	var mod: StatMod = StatMod.make(property, str(model.get("mod", "added")), x, LE.tag_mask(str(model.get("tags", ""))), source_text, special)
	mod.on_curse_hit = bool(model.get("on_curse_hit", false))
	mod.holder_only = bool(model.get("holder_only", false))
	# a Damage more that the game folds into ONE ailment instance (ActiveAilment.moreDamage), not into the skill's damage
	if model.has("ailment_only"):
		mod.ailment_only = GameData.enum_value("AilmentID", str(model["ailment_only"]))
		if mod.ailment_only <= 0:
			return null
		if model.has("chance_scaled"):
			mod.chance_scaled = GameData.enum_value("AilmentID", str(model["chance_scaled"]))
			if mod.chance_scaled <= 0:
				return null
	return mod


## Mods of a model: one, or one per entry of its "variants" (each entry overrides keys of the model: stat, tags, per, ailment ...).
static func make_mods(model: Dictionary, v: float, ctx: Dictionary, label: String) -> Array[StatMod]:
	var out: Array[StatMod] = []
	if not model.has("variants"):
		var single: StatMod = make_mod(model, v, ctx, label)
		if single != null:
			out.append(single)
		return out
	for variant: Variant in model["variants"]:
		var merged: Dictionary = model.duplicate()
		merged.erase("variants")
		merged.merge(variant as Dictionary, true)
		var mod: StatMod = make_mod(merged, v, ctx, label)
		if mod != null:
			out.append(mod)
	return out


## Upper bound of the per-source value: model "src_max" and "src_max_field" (sum of the allocated passive effects that write that
## CharacterMutator field, e.g. maxArcaneMomentumStacks = 1 per point). INF if neither is set.
static func source_cap(model: Dictionary, ctx: Dictionary) -> float:
	var cap: float = INF
	if model.has("src_max"):
		cap = float(model["src_max"])
	if model.has("src_max_field") and ctx.has("build"):
		cap = minf(cap, field_total(str(model["src_max_field"]), ctx))
	return cap


## Sum of the allocated passive effects that write CharacterMutator.<field> (points >= minPoints); 0 without a build.
static func field_total(field: String, ctx: Dictionary) -> float:
	var total: float = 0.0
	if not ctx.has("build"):
		return total
	var target: String = "CharacterMutator.%s" % field
	for entry: Dictionary in BuildMods._passive_entries(ctx["build"]):
		var points: int = entry["points"]
		for effect: Dictionary in (entry["node"] as Dictionary).get("effects", []):
			if str(effect.get("target", "")) == target and points >= int(effect.get("minPoints", 0)) and effect.has("value"):
				total += BuildMods.eval_value(effect["value"], points)
	return total


## Copies of the player's stats (model key `copy_player`, SummonSkeletonMutator / FalconryMutator / PP 445): every stat of `stat`
## whose tags include one of `tags_any` becomes its scaled copy (k = v × factor: added, increased and each more × k). With
## `only_added` only the added value × k is copied, with the tags `clear_tags` removed and `set_tags` added.
static func copied_mods(model: Dictionary, v: float, ctx: Dictionary, label: String) -> Array[StatMod]:
	var spec: Dictionary = model["copy_player"]
	var out: Array[StatMod] = []
	var property: int = GameData.sp_id(str(spec.get("stat", "")))
	if property < 0:
		return out
	var any_mask: int = LE.tag_mask(str(spec.get("tags_any", "")))
	var k: float = v * float(model.get("factor", 1.0))
	for mod: StatMod in player_store(ctx).mods_of(property):
		if (mod.tags & any_mask) == 0:
			continue
		var copy: StatMod
		if bool(spec.get("only_added", false)):
			if mod.added == 0.0:
				continue
			var tags: int = (mod.tags & ~LE.tag_mask(str(spec.get("clear_tags", "")))) | LE.tag_mask(str(spec.get("set_tags", "")))
			copy = StatMod.make(property, "added", mod.added * k, tags, "", mod.special)
		else:
			copy = mod.scaled(k)
		copy.source = LE.t("%s — %s × %s") % [label, mod.source, LE.fmt_num(k)]
		out.append(copy)
	return out


## Source value (attributes, stats, conditions, etc).
static func source(per: String, ctx: Dictionary, model: Dictionary = {}) -> float:
	var build: Node = ctx["build"]
	var store: StatStore = ctx["store"]
	var kind: String = per.get_slice(":", 0)
	var arg: String = per.get_slice(":", 1) if per.contains(":") else ""
	match kind:
		"attr":
			return float(_attribute(store, int(ATTR_SP.get(arg, -1))))
		"converted_attr":
			# the hidden attribute exists only while the attribute is converted; it then has the attribute's value
			var sp: int = int(ATTR_SP.get(arg, -1))
			if BuildMods.converted_attribute(store, GameData.attribute_by_property(sp)) == "":
				return 0.0
			return float(_attribute(store, sp))
		"total_attr":
			var total: int = 0
			for key: String in ATTR_SP:
				total += _attribute(store, ATTR_SP[key])
			return float(total)
		"added":
			return store.query(GameData.sp_id(arg), 0, 0, 0, false).added
		"weapon_added":
			# added damage of one tag (melee …) on the equipped weapons: implicits and affixes of the weapon and off-hand items
			var tag: int = LE.tag_mask(arg.capitalize())
			var sum: float = 0.0
			for slot: String in ["weapon", "offhand"]:
				var item: Dictionary = build.items.get(slot, {})
				if item.is_empty() or not bool(GameData.item_base(int(item.get("base", -1))).get("isWeapon", false)):
					continue
				for mod: StatMod in ItemMods.item_mods(slot, item):
					if mod.property == LE.DAMAGE and mod.added > 0.0 and (mod.tags & tag) != 0:
						sum += mod.added
			return sum
		"value":
			return store.query(GameData.sp_id(arg), 0, 0, 0, false).value()
		"increased":
			return store.query(GameData.sp_id(arg), 0, 0, 0, false).increased
		"added_exact":
			var sp: int = GameData.sp_id(arg)
			var mask: int = int(per.get_slice(":", 2))
			var sum: float = 0.0
			for mod: StatMod in store.mods_of(sp):
				if mod.tags == mask:
					sum += mod.added
			return sum
		"increased_exact":
			# increased mods of the stat whose tags are exactly the mask and whose specialTag / extraTag are 0 (GetTotalIncreasedExactMatch)
			var inc_sp: int = GameData.sp_id(arg)
			var inc_mask: int = int(per.get_slice(":", 2))
			var inc_sum: float = 0.0
			for mod: StatMod in store.mods_of(inc_sp):
				if mod.tags == inc_mask and mod.special == 0 and mod.extra == 0:
					inc_sum += mod.increased
			return inc_sum
		"ailment_chance":
			# Stats.GetAilmentChance(ailment): untagged chance mods whose special is 0 or the ailment (the ailment's own chance and
			# the chance to any ailment), added × (1 + increased) × more
			return player_store(ctx).query(LE.AILMENT_CHANCE, 0, GameData.enum_value("AilmentID", arg)).value()
		"total_modifier":
			# Stats.GetTotalModifier(SP, AT): (1 + Σ increased) × Π(1 + more) − 1 over the stats whose tags fit the mask (untagged included)
			var tm_q: StatQuery = player_store(ctx).query(GameData.sp_id(arg), int(per.get_slice(":", 2)), 0, 0, false)
			return (1.0 + tm_q.increased) * tm_q.more - 1.0
		"stat_value":
			# Stats.GetStatValue(SP, AT, base): (base + Σ added) × (1 + Σ increased) × Π(1 + more) over the stats whose tags fit the mask
			var sv_q: StatQuery = player_store(ctx).query(GameData.sp_id(arg), int(per.get_slice(":", 2)))
			return (float(per.get_slice(":", 3)) + sv_q.added) * (1.0 + sv_q.increased) * sv_q.more
		"weapon_count":
			return float(_weapon_count(build, arg))
		"total_added":
			# Stats.GetTotalAdded(SP, AT mask): sum of added of the stats applicable to the mask (untagged ones included)
			return player_store(ctx).query(GameData.sp_id(arg), int(per.get_slice(":", 2))).added
		"mastery_points":
			return float(build.points_in_mastery(int(arg)))  # LocalTreeData.masteryLevels[arg]
		"skill_mana_cost":
			return float(ctx.get("mana_cost", 0.0))  # BaseMana.getManaCost of the skill, set by BuildMods._add_cost_models
		"level":
			return float(build.level)  # the character level (CharacterDataTracker.charData.Level)
		"res":
			return Enemy.resistance(store, int(arg)).value()
		"ele_res":
			return Enemy.resistance(store, 1).value() + Enemy.resistance(store, 2).value() + Enemy.resistance(store, 3).value()
		"total_res":
			var res: float = 0.0
			for i in range(7):
				res += Enemy.resistance(store, i).value()
			return res
		"max_health":
			return float(LE.round_half_even(store.query_untagged(LE.HEALTH).value()))
		"max_mana":
			return float(LE.round_half_even(store.query_untagged(LE.MANA).value()))
		"endurance_threshold":
			return CharacterCalc._compute_endurance_threshold(store)
		"enemy_stacks":
			return float(build.enemy.get("ailments", {}).get(GameData.enum_value("AilmentID", arg), 0))
		"player":
			return float(build.player_state.get(arg, 0))
		"buff":
			return BuildMods.buff_stacks(build, GameData.enum_value("AilmentID", arg))
		"complete_sets":
			return float(BuildMods.complete_sets(build))
		"input":
			# minion counts are global (the Minions card of the Conditions tab), not fields of one skill
			if MinionCount.is_count_key(arg):
				return float(MinionCount.count(build, arg)["value"])
			var default: float = 0.0
			if model.has("input"):
				var inp: Dictionary = model["input"]
				if inp.has("default") and inp.get("key") == arg:
					default = float(inp.get("default", 0.0))
			var slot: int = _input_slot(ctx)
			if slot >= 0 and slot < build.skills.size():
				return float(build.skills[slot].get("inputs", {}).get(arg, default))
			return default
	return 0.0


## Display name of the source.
static func source_name(per: String, _ctx: Dictionary, model: Dictionary = {}) -> String:
	var kind: String = per.get_slice(":", 0)
	var arg: String = per.get_slice(":", 1) if per.contains(":") else ""
	match kind:
		"attr":
			return LE.t(str(ATTR_NAMES.get(arg, arg)))
		"converted_attr":
			return LE.t(str(CONVERTED_NAMES.get(arg, arg)))
		"total_attr":
			return LE.t("sum of attributes")
		"added", "increased":
			return "%s %s" % [kind, arg]
		"weapon_added":
			return LE.t("added %s damage on equipped weapons") % arg
		"value":
			return arg
		"added_exact":
			return LE.t("added %s (tags %s)") % [arg, per.get_slice(":", 2)]
		"increased_exact":
			return LE.t("increased %s (tags %s)") % [arg, per.get_slice(":", 2)]
		"ailment_chance":
			return LE.t("%s chance (stats without tags)") % arg
		"total_modifier":
			return LE.t("total modifier of %s (tags %s)") % [arg, per.get_slice(":", 2)]
		"stat_value":
			return LE.t("%s with base %s (tags %s)") % [arg, per.get_slice(":", 3), per.get_slice(":", 2)]
		"weapon_count":
			return LE.t("equipped swords") if arg == "sword" else LE.t("equipped daggers")
		"total_added":
			return LE.t("total added %s (tags %s)") % [arg, per.get_slice(":", 2)]
		"mastery_points":
			return LE.t("points in mastery %s") % arg
		"skill_mana_cost":
			return LE.t("mana cost of the skill")
		"level":
			return LE.t("character level")
		"res":
			return LE.t("%s resistance without cap") % LE.t(LE.DT_NAME[int(arg)])
		"ele_res":
			return LE.t("sum of elemental resistances without cap")
		"total_res":
			return LE.t("sum of resistances without cap")
		"max_health":
			return LE.t("max health")
		"max_mana":
			return LE.t("max mana")
		"endurance_threshold":
			return LE.t("endurance threshold")
		"enemy_stacks":
			return LE.t("%s stacks on the enemy") % arg
		"player":
			return LE.t(str(PLAYER_VALUE_NAMES.get(arg, arg)))
		"buff":
			var ail: Dictionary = GameData.ailment(GameData.enum_value("AilmentID", arg))
			return LE.t("%s stacks on me") % str(ail.get("displayName", arg))
		"complete_sets":
			return LE.t("complete sets")
		"input":
			if MinionCount.is_count_key(arg):
				return LE.t(str(MinionCount.COUNT_KEYS[MinionCount.canonical(arg)]["label"]))
			if model.has("input") and model["input"].get("key") == arg:
				return LE.t(str(model["input"].get("label", arg)))
			return arg
	return per


## Non-stat models (trigger, resource, flag, param) keep an on/off «the enemy has the ailment» condition: it holds when the
## ailment is present at least this share of the time (automatic averages, EnemyAilments; D?). Stat models scale by the
## presence instead (presence_factor): the game checks the condition on every hit (DamageConditionalEffect.apply).
const PRESENT_SHARE: float = 0.5
const PRESENCE_KINDS: Array[String] = ["stat", "minion_stat"]


## Presence (0..1) of the ailment(s) in an «enemy:<Ailment>» / «enemy_any:A|B» condition; -1 for every other condition.
static func _ailment_presence(cond: String, ctx: Dictionary) -> float:
	var build: Node = ctx["build"]
	var kind: String = cond.get_slice(":", 0)
	var arg: String = cond.get_slice(":", 1)
	if kind == "enemy" and arg != "boss_or_rare":
		return Enemy.presence_id(build.enemy, GameData.enum_value("AilmentID", arg))
	if kind == "enemy_any":
		var none: float = 1.0
		for a: String in arg.split("|"):
			none *= 1.0 - Enemy.presence_id(build.enemy, GameData.enum_value("AilmentID", a))
		return 1.0 - none
	return -1.0


## Share of the hits whose target has the ailments of the model's conditions (1 = none, or a model that is not a plain stat).
## A per-hit DamageConditionalEffect gives 1 + f × presence on average.
static func presence_factor(model: Dictionary, ctx: Dictionary) -> float:
	if not PRESENCE_KINDS.has(str(model.get("kind", "stat"))) or not ctx.has("build"):
		return 1.0
	var factor: float = 1.0
	for cond: String in model.get("when", []):
		var share: float = _ailment_presence(cond, ctx)
		if share >= 0.0:
			factor *= share
	return factor


## Check if condition holds.
static func holds(cond: String, ctx: Dictionary) -> bool:
	var build: Node = ctx["build"]
	var item_slot: String = ctx.get("item_slot", "")
	var kind: String = cond.get_slice(":", 0)
	var arg: String = cond.get_slice(":", 1)
	match kind:
		"enemy":
			if arg == "boss_or_rare":
				return str(build.enemy.get("kind", "")) in ["rare", "miniboss", "boss"]
			return Enemy.presence_id(build.enemy, GameData.enum_value("AilmentID", arg)) >= PRESENT_SHARE
		"enemy_any":
			for a: String in arg.split("|"):
				if Enemy.presence_id(build.enemy, GameData.enum_value("AilmentID", a)) >= PRESENT_SHARE:
					return true
			return false
		"enemy_flag":
			if arg.begins_with("!"):
				return not _enemy_flag(build, arg.substr(1))
			return _enemy_flag(build, arg)
		"player":
			if arg.begins_with("!"):
				return not _player_flag(build, arg.substr(1))
			return _player_flag(build, arg)
		"gear":
			if arg == "dual_wield":
				return _is_weapon(build.items.get("weapon", {})) and _is_weapon(build.items.get("offhand", {}))
			if arg == "two_handed_melee":
				return TWO_HANDED_MELEE_TYPES.has(int(build.items.get("weapon", {}).get("base", -1)))
			if arg == "dual_wield_diff":  # WeaponInfoHolder.dualWieldingDifferentItemTypes: two weapons of different base types
				var main_hand: Dictionary = build.items.get("weapon", {})
				var off_hand: Dictionary = build.items.get("offhand", {})
				return _is_weapon(main_hand) and _is_weapon(off_hand) and int(main_hand.get("base", -1)) != int(off_hand.get("base", -2))
			return false
		"gear_any":
			# a weapon base type (EquipmentType numbers, comma separated) in either hand (WeaponInfoHolder.hasWeaponType)
			for hand: String in ["weapon", "offhand"]:
				var held: Dictionary = build.items.get(hand, {})
				if not held.is_empty() and arg.split(",").has(str(int(held.get("base", -1)))):
					return true
			return false
		"slot":
			return item_slot == arg
		"use":
			# who uses the skill: "shadow" = a use repeated by a shadow (ShadowCalc), "echo" = a Void Knight echo (EchoCalc),
			# "direct" = your own use
			return str(ctx.get("use", "")) == ("" if arg == "direct" else arg)
		"input":
			var slot: int = _input_slot(ctx)
			if slot >= 0 and slot < build.skills.size():
				return bool(build.skills[slot].get("inputs", {}).get(arg, false))
			return false
	return false


## Enemy flag of the Conditions tab; high health is also true at full health (Enemy.has_condition 2, Stats.highHealthPercent).
static func _enemy_flag(build: Node, flag: String) -> bool:
	if flag == "high_health":
		return Enemy.has_condition(build.enemy, 2) > 0.0
	return bool(build.enemy.get("flags", {}).get(flag, false))


## Player flag of a condition; "low_life" is the "low" choice of the Health select, not a checkbox.
static func _player_flag(build: Node, flag: String) -> bool:
	if flag == "low_life":
		return str(build.player_state.get("health", "full")) == "low"
	if flag == "high_life":
		return ["full", "high"].has(str(build.player_state.get("health", "full")))  # the Health select: Full (>=99%) and High (>65%) are above 65%
	return bool(build.player_state.get(flag, false))


## Display name of the condition.
static func condition_name(cond: String, _ctx: Dictionary) -> String:
	var kind: String = cond.get_slice(":", 0)
	var arg: String = cond.get_slice(":", 1)
	match kind:
		"enemy":
			return LE.t("enemy is rare or a boss") if arg == "boss_or_rare" else LE.t("enemy has %s (Conditions tab)") % arg
		"enemy_any":
			return LE.t("enemy has %s (Conditions tab)") % arg.replace("|", LE.t(" or "))
		"enemy_flag":
			if arg == "!high_health":
				return LE.t("enemy is not at high health (Conditions tab)")
			return LE.t("enemy is %s (Conditions tab)") % (LE.t("frozen") if arg == "frozen" else arg)
		"player":
			if arg.begins_with("!"):
				return LE.t("\"%s\" is off (Conditions tab)") % LE.t(str(PLAYER_FLAG_NAMES.get(arg.substr(1), arg)))
			return LE.t("\"%s\" is on (Conditions tab)") % LE.t(str(PLAYER_FLAG_NAMES.get(arg, arg)))
		"gear":
			if arg == "dual_wield_diff":
				return LE.t("dual wielding different weapon types")
			return LE.t("dual wielding") if arg == "dual_wield" else LE.t("two-handed melee weapon")
		"gear_any":
			var names: PackedStringArray = []
			for t: String in arg.split(","):
				names.append(GameData.display_name(GameData.item_base(int(t))))
			return LE.t("holding %s") % " / ".join(names)
		"slot":
			return LE.t("item in slot \"%s\"") % LE.t(str(ItemMods.SLOT_NAMES.get(arg, arg)))
		"use":
			if arg == "shadow":
				return LE.t("the skill is used by a shadow")
			return LE.t("the skill is echoed") if arg == "echo" else LE.t("you use the skill yourself")
		"input":
			# Get the model to find the label, but we need context info
			# For now, just use the arg as fallback
			return LE.t("\"%s\" is on (Calculations tab)") % arg
	return cond


## Phase when this model should be applied (pre = before attributes, post = after).
static func phase(model: Dictionary) -> String:
	if model.has("effect_of"):
		return "late"  # reads SP 120, which other post-phase models (pp 606 per Strength) add
	var parts: Array[Dictionary] = [model]
	for variant: Variant in model.get("variants", []):
		parts.append(variant as Dictionary)
	var post: bool = false
	for part: Dictionary in parts:
		var sources: Array[String] = []
		if part.has("per"):
			sources.append(str(part["per"]))
		for key: String in ["at_least", "below"]:
			if part.has(key):
				sources.append(str(part[key]["per"]))
		for per: String in sources:
			var kind: String = per.get_slice(":", 0)
			if kind == "skill_mana_cost":
				return "skill"  # computed per skill (BuildMods._add_cost_models), never in pre / post / late
			if kind == "endurance_threshold":
				return "late"  # reads the threshold that post-phase models add (PP 483 / 485 / 515)
			if STORE_SOURCES.has(kind):
				post = true
	if post or str(model.get("kind", "")) == "overcap_taken":
		return "post"
	return "pre"


## Declared input parameters of the model.
static func inputs(model: Dictionary) -> Array[Dictionary]:
	if model.has("input") and not MinionCount.is_count_key(str(model["input"].get("key", ""))):
		return [model["input"]]
	return []


# --- private helpers ---

## The player's stats (the global store): the parent of a skill's store, the store itself in a character-wide context.
static func player_store(ctx: Dictionary) -> StatStore:
	var store: StatStore = ctx["store"]
	return store.parent if store.parent != null else store


## Skill slot whose inputs a model reads: the skill being computed; a character-wide model (slot -1) reads the first damaging
## skill of the bar (ctx["input_slot"], set by UniqueEffects.apply_global), where apply_skill declares its inputs.
static func _input_slot(ctx: Dictionary) -> int:
	var slot: int = int(ctx.get("slot", -1))
	return slot if slot >= 0 else int(ctx.get("input_slot", -1))


static func _attribute(store: StatStore, sp: int) -> int:
	if sp < 0:
		return 0
	return BuildMods.attribute_value(store, sp)  # tags are not checked, as for the per-point stats (06a §5.1)


static func _is_weapon(item: Dictionary) -> bool:
	return not item.is_empty() and bool(GameData.item_base(int(item.get("base", -1))).get("isWeapon", false))


## WeaponInfoHolder.swordCount / daggerCount from the base types in the weapon and offhand slots (EquipmentType: 6 dagger, 9 1H sword, 16 2H sword).
static func _weapon_count(build: Node, kind: String) -> int:
	var main_type: int = int(build.items.get("weapon", {}).get("base", -1))
	var off_type: int = int(build.items.get("offhand", {}).get("base", -1))
	if kind == "sword":
		return (1 if main_type == 9 or main_type == 16 else 0) + (1 if off_type == 9 else 0)
	return (1 if main_type == 6 else 0) + (1 if off_type == 6 else 0)
