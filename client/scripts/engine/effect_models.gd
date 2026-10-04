class_name EffectModels

## Effect model computation for unique items and skill tree nodes (docs/ENGINE.md §9.2).
## Context: ctx = {build: Node, store: StatStore, slot: int, item_slot: String}

const ATTR_SP: Dictionary = {"str": LE.STRENGTH, "vit": LE.VITALITY, "int": LE.INTELLIGENCE, "dex": LE.DEXTERITY, "att": LE.ATTUNEMENT}
const ATTR_NAMES: Dictionary = {"str": "Strength", "vit": "Vitality", "int": "Intelligence", "dex": "Dexterity", "att": "Attunement"}
const TWO_HANDED_MELEE_TYPES: Array[int] = [12, 13, 14, 15, 16]  # 2H axes, maces, polearms, staffs, swords
const PLAYER_FLAG_NAMES: Dictionary = {
	"hit_recently": "Hit recently", "crit_recently": "Crit recently", "moving": "Moving",
	"leeching": "Leech active", "low_mana": "Mana below 50%", "haste": "Haste on me", "frenzy": "Frenzy on me",
	"low_life": "Low health",
}
const PLAYER_VALUE_NAMES: Dictionary = {
	"ward": "Current ward", "curses": "Curses on me", "ignite_stacks": "Ignite stacks on me", "damned_stacks": "Damned stacks on me",
}
const STORE_SOURCES: Array[String] = ["attr", "total_attr", "added", "value", "increased", "added_exact", "res", "ele_res",
	"total_res", "max_health", "max_mana", "endurance_threshold"]


## "" if the model applies now, otherwise the unmet condition (translated).
static func blocked(model: Dictionary, ctx: Dictionary) -> String:
	ConfigRelevance.note_model(model, ctx)
	if model.has("at_least"):
		var v: float = source(str(model["at_least"]["per"]), ctx, model)
		if v < float(model["at_least"]["value"]):
			return LE.t("%s ≥ %s (now %s)") % [source_name(str(model["at_least"]["per"]), ctx, model), LE.fmt_num(float(model["at_least"]["value"])), LE.fmt_num(v)]
	if model.has("below"):
		var w: float = source(str(model["below"]["per"]), ctx, model)
		if w >= float(model["below"]["value"]):
			return LE.t("%s < %s (now %s)") % [source_name(str(model["below"]["per"]), ctx, model), LE.fmt_num(float(model["below"]["value"])), LE.fmt_num(w)]
	for cond: String in model.get("when", []):
		if cond.begins_with("input:") and model.has("input") and str(model["input"].get("key", "")) == cond.get_slice(":", 1):
			# the model's own input: unset means its declared default (the UI shows the default, not "off")
			var slot: int = ctx.get("slot", -1)
			var build: Node = ctx["build"]
			var inputs: Dictionary = build.skills[slot].get("inputs", {}) if slot >= 0 and slot < build.skills.size() else {}
			if not bool(inputs.get(cond.get_slice(":", 1), model["input"].get("default", false))):
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
		if model.has("src_max"):
			src = minf(src, float(model["src_max"]))
		x = v * (src - float(model.get("offset", 0.0))) * float(model.get("factor", 1.0))
		text = "(%s × %s = %s)" % [LE.fmt_num(v), source_name(str(model["per"]), ctx, model), LE.fmt_num(src)]
	if model.has("min"):
		x = maxf(x, float(model["min"]))
	if model.has("max"):
		x = minf(x, float(model["max"]))
	return {"x": x, "text": text}


## StatMod from the model (null if SP is unknown).
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
		special = maxi(0, GameData.enum_value("AilmentID", str(model["ailment"])))
	var mod: StatMod = StatMod.make(property, str(model.get("mod", "added")), x, LE.tag_mask(str(model.get("tags", ""))), source_text, special)
	mod.on_curse_hit = bool(model.get("on_curse_hit", false))
	return mod


## Source value (attributes, stats, conditions, etc).
static func source(per: String, ctx: Dictionary, model: Dictionary = {}) -> float:
	var build: Node = ctx["build"]
	var store: StatStore = ctx["store"]
	var kind: String = per.get_slice(":", 0)
	var arg: String = per.get_slice(":", 1) if per.contains(":") else ""
	match kind:
		"attr":
			return float(_attribute(store, int(ATTR_SP.get(arg, -1))))
		"total_attr":
			var total: int = 0
			for key: String in ATTR_SP:
				total += _attribute(store, ATTR_SP[key])
			return float(total)
		"added":
			return store.query_untagged(GameData.sp_id(arg)).added
		"value":
			return store.query_untagged(GameData.sp_id(arg)).value()
		"increased":
			return store.query_untagged(GameData.sp_id(arg)).increased
		"added_exact":
			var sp: int = GameData.sp_id(arg)
			var mask: int = int(per.get_slice(":", 2))
			var sum: float = 0.0
			for mod: StatMod in store.all_mods():
				if mod.property == sp and mod.tags == mask:
					sum += mod.added
			return sum
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
		"complete_sets":
			return float(BuildMods.complete_sets(build))
		"input":
			var default: float = 0.0
			if model.has("input"):
				var inp: Dictionary = model["input"]
				if inp.has("default") and inp.get("key") == arg:
					default = float(inp.get("default", 0.0))
			var slot: int = ctx.get("slot", -1)
			if slot >= 0 and slot < build.skills.size():
				return float(build.skills[slot].get("inputs", {}).get(arg, default))
			return default
	return 0.0


## Display name of the source.
static func source_name(per: String, ctx: Dictionary, model: Dictionary = {}) -> String:
	var build: Node = ctx["build"]
	var kind: String = per.get_slice(":", 0)
	var arg: String = per.get_slice(":", 1) if per.contains(":") else ""
	match kind:
		"attr":
			return LE.t(str(ATTR_NAMES.get(arg, arg)))
		"total_attr":
			return LE.t("sum of attributes")
		"added", "increased":
			return "%s %s" % [kind, arg]
		"value":
			return arg
		"added_exact":
			return LE.t("added %s (tags %s)") % [arg, per.get_slice(":", 2)]
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
		"complete_sets":
			return LE.t("complete sets")
		"input":
			if model.has("input") and model["input"].get("key") == arg:
				return LE.t(str(model["input"].get("label", arg)))
			return arg
	return per


## Check if condition holds.
static func holds(cond: String, ctx: Dictionary) -> bool:
	var build: Node = ctx["build"]
	var item_slot: String = ctx.get("item_slot", "")
	var kind: String = cond.get_slice(":", 0)
	var arg: String = cond.get_slice(":", 1)
	var ailments: Dictionary = build.enemy.get("ailments", {})
	match kind:
		"enemy":
			if arg == "boss_or_rare":
				return str(build.enemy.get("kind", "")) in ["rare", "miniboss", "boss"]
			return int(ailments.get(GameData.enum_value("AilmentID", arg), 0)) > 0
		"enemy_any":
			for a: String in arg.split("|"):
				if int(ailments.get(GameData.enum_value("AilmentID", a), 0)) > 0:
					return true
			return false
		"enemy_flag":
			return bool(build.enemy.get("flags", {}).get(arg, false))
		"player":
			if arg.begins_with("!"):
				return not _player_flag(build, arg.substr(1))
			return _player_flag(build, arg)
		"gear":
			if arg == "dual_wield":
				return _is_weapon(build.items.get("weapon", {})) and _is_weapon(build.items.get("offhand", {}))
			if arg == "two_handed_melee":
				return TWO_HANDED_MELEE_TYPES.has(int(build.items.get("weapon", {}).get("base", -1)))
			return false
		"slot":
			return item_slot == arg
		"input":
			var slot: int = ctx.get("slot", -1)
			if slot >= 0 and slot < build.skills.size():
				return bool(build.skills[slot].get("inputs", {}).get(arg, false))
			return false
	return false


## Player flag of a condition; "low_life" is the "low" choice of the Health select, not a checkbox.
static func _player_flag(build: Node, flag: String) -> bool:
	if flag == "low_life":
		return str(build.player_state.get("health", "full")) == "low"
	return bool(build.player_state.get(flag, false))


## Display name of the condition.
static func condition_name(cond: String, ctx: Dictionary) -> String:
	var build: Node = ctx["build"]
	var kind: String = cond.get_slice(":", 0)
	var arg: String = cond.get_slice(":", 1)
	match kind:
		"enemy":
			return LE.t("enemy is rare or a boss") if arg == "boss_or_rare" else LE.t("enemy has %s (Conditions tab)") % arg
		"enemy_any":
			return LE.t("enemy has %s (Conditions tab)") % arg.replace("|", LE.t(" or "))
		"enemy_flag":
			return LE.t("enemy is %s (Conditions tab)") % (LE.t("frozen") if arg == "frozen" else arg)
		"player":
			if arg.begins_with("!"):
				return LE.t("\"%s\" is off (Conditions tab)") % LE.t(str(PLAYER_FLAG_NAMES.get(arg.substr(1), arg)))
			return LE.t("\"%s\" is on (Conditions tab)") % LE.t(str(PLAYER_FLAG_NAMES.get(arg, arg)))
		"gear":
			return LE.t("dual wielding") if arg == "dual_wield" else LE.t("two-handed melee weapon")
		"slot":
			return LE.t("item in slot \"%s\"") % LE.t(str(ItemMods.SLOT_NAMES.get(arg, arg)))
		"input":
			# Get the model to find the label, but we need context info
			# For now, just use the arg as fallback
			return LE.t("\"%s\" is on (Calculations tab)") % arg
	return cond


## Phase when this model should be applied (pre = before attributes, post = after).
static func phase(model: Dictionary) -> String:
	var sources: Array[String] = []
	if model.has("per"):
		sources.append(str(model["per"]))
	for key: String in ["at_least", "below"]:
		if model.has(key):
			sources.append(str(model[key]["per"]))
	for per: String in sources:
		if STORE_SOURCES.has(per.get_slice(":", 0)):
			return "post"
	if str(model.get("kind", "")) == "overcap_taken":
		return "post"
	return "pre"


## Declared input parameters of the model.
static func inputs(model: Dictionary) -> Array[Dictionary]:
	if model.has("input"):
		return [model["input"]]
	return []


# --- private helpers ---

static func _attribute(store: StatStore, sp: int) -> int:
	if sp < 0:
		return 0
	return LE.round_half_even(store.sum_added_untagged([sp, LE.ALL_ATTRIBUTES]))


static func _is_weapon(item: Dictionary) -> bool:
	return not item.is_empty() and bool(GameData.item_base(int(item.get("base", -1))).get("isWeapon", false))
