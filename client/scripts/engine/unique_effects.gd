class_name UniqueEffects

## Special effects of equipped uniques (docs/ENGINE.md §5.4.3). PlayerProperty / AbilityProperty effects that have a
## planner model in unique_effect_models.json become StatMods; everything else is listed in notes with the reason.

const ATTR_SP: Dictionary = {"str": LE.STRENGTH, "vit": LE.VITALITY, "int": LE.INTELLIGENCE, "dex": LE.DEXTERITY, "att": LE.ATTUNEMENT}
const ATTR_RU: Dictionary = {"str": "Сила", "vit": "Живучесть", "int": "Интеллект", "dex": "Ловкость", "att": "Настрой"}
const TWO_HANDED_MELEE_TYPES: Array[int] = [12, 13, 14, 15, 16]  # 2H axes, maces, polearms, staffs, swords
const PLAYER_FLAGS_RU: Dictionary = {
	"hit_recently": "Был поражён недавно", "crit_recently": "Критовал недавно", "moving": "Двигаюсь",
	"leeching": "Вампиризм активен", "low_mana": "Мана ниже 50%", "haste": "Haste на мне", "frenzy": "Frenzy на мне",
}
const PLAYER_VALUES_RU: Dictionary = {
	"ward": "Текущий ward", "curses": "Проклятий на мне", "ignite_stacks": "Стаков Ignite на мне", "damned_stacks": "Стаков Damned на мне",
}
const DERIVED_SOURCES: Array[String] = ["GlobalConditionalDamage(more)", "DamagePerStackOfAilment", "AilmentConversion"]
const STORE_SOURCES: Array[String] = ["attr", "total_attr", "added", "value", "increased", "added_exact", "res", "ele_res",
	"total_res", "max_health", "max_mana", "endurance_threshold"]


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
		if model.is_empty() or e["ability_index"] >= 0 or model.has("skill_any") or _phase(model) != phase:
			continue
		var reason: String = _blocked(build, store, model, e)
		if reason != "":
			notes.append("%s — учитывается при условии: %s" % [e["label"], reason])
			continue
		if str(model.get("kind", "stat")) == "overcap_taken":
			_apply_overcap_taken(store, e)
			continue
		var mod: StatMod = _make_mod(build, store, model, e)
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
		var reason: String = _blocked(build, store, model, e)
		if reason != "":
			result["notes"].append("%s — учитывается при условии: %s" % [e["label"], reason])
			continue
		if str(model.get("kind", "stat")) == "mana_added":
			result["mana_added"] += e["pp"]
			result["mana_sources"].append("%s %s" % [LE.fmt_num(e["pp"]), e["label"]])
			continue
		var mod: StatMod = _make_mod(build, store, model, e)
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


static func _make_mod(build: Node, store: StatStore, model: Dictionary, e: Dictionary) -> StatMod:
	var property: int = GameData.sp_id(str(model.get("stat", "")))
	if property < 0:
		return null
	var pp: float = e["pp"]
	var x: float = pp * float(model.get("factor", 1.0))
	var source: String = e["label"]
	if model.has("per"):
		var src: float = _source(build, store, str(model["per"]))
		if model.has("src_max"):
			src = minf(src, float(model["src_max"]))
		x = pp * (src - float(model.get("offset", 0.0))) * float(model.get("factor", 1.0))
		source = "%s (%s × %s = %s)" % [e["label"], LE.fmt_num(pp), _source_name(str(model["per"])), LE.fmt_num(src)]
	if model.has("min"):
		x = maxf(x, float(model["min"]))
	if model.has("max"):
		x = minf(x, float(model["max"]))
	var special: int = 0
	if model.has("ailment"):
		special = maxi(0, GameData.enum_value("AilmentID", str(model["ailment"])))
	if model.has("note"):
		source += " — " + str(model["note"])
	return StatMod.make(property, str(model.get("mod", "added")), x, LE.tag_mask(str(model.get("tags", ""))), source, special)


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


# --- sources and conditions ---------------------------------------------------------

static func _phase(model: Dictionary) -> String:
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


static func _source(build: Node, store: StatStore, per: String) -> float:
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
	return 0.0


static func _source_name(per: String) -> String:
	var kind: String = per.get_slice(":", 0)
	var arg: String = per.get_slice(":", 1) if per.contains(":") else ""
	match kind:
		"attr":
			return str(ATTR_RU.get(arg, arg))
		"total_attr":
			return "сумма атрибутов"
		"added", "increased":
			return "%s %s" % [kind, arg]
		"value":
			return arg
		"added_exact":
			return "added %s (теги %s)" % [arg, per.get_slice(":", 2)]
		"res":
			return "сопротивление %s без капа" % LE.DT_NAME_RU[int(arg)]
		"ele_res":
			return "сумма стихийных сопротивлений без капа"
		"total_res":
			return "сумма сопротивлений без капа"
		"max_health":
			return "макс. здоровье"
		"max_mana":
			return "макс. мана"
		"endurance_threshold":
			return "порог выносливости"
		"enemy_stacks":
			return "стаки %s на противнике" % arg
		"player":
			return str(PLAYER_VALUES_RU.get(arg, arg))
		"complete_sets":
			return "полные сеты"
	return per


static func _attribute(store: StatStore, sp: int) -> int:
	if sp < 0:
		return 0
	return LE.round_half_even(store.sum_added_untagged([sp, LE.ALL_ATTRIBUTES]))


## "" if the model applies now, otherwise the unmet condition in Russian.
static func _blocked(build: Node, store: StatStore, model: Dictionary, e: Dictionary) -> String:
	if model.has("at_least"):
		var v: float = _source(build, store, str(model["at_least"]["per"]))
		if v < float(model["at_least"]["value"]):
			return "%s ≥ %s (сейчас %s)" % [_source_name(str(model["at_least"]["per"])), LE.fmt_num(float(model["at_least"]["value"])), LE.fmt_num(v)]
	if model.has("below"):
		var w: float = _source(build, store, str(model["below"]["per"]))
		if w >= float(model["below"]["value"]):
			return "%s < %s (сейчас %s)" % [_source_name(str(model["below"]["per"])), LE.fmt_num(float(model["below"]["value"])), LE.fmt_num(w)]
	for cond: String in model.get("when", []):
		if not _holds(build, cond, e):
			return _condition_name(cond)
	return ""


static func _holds(build: Node, cond: String, e: Dictionary) -> bool:
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
				return not bool(build.player_state.get(arg.substr(1), false))
			return bool(build.player_state.get(arg, false))
		"gear":
			if arg == "dual_wield":
				return _is_weapon(build.items.get("weapon", {})) and _is_weapon(build.items.get("offhand", {}))
			if arg == "two_handed_melee":
				return TWO_HANDED_MELEE_TYPES.has(int(build.items.get("weapon", {}).get("base", -1)))
			return false
		"slot":
			return e["slot"] == arg
	return false


static func _condition_name(cond: String) -> String:
	var kind: String = cond.get_slice(":", 0)
	var arg: String = cond.get_slice(":", 1)
	match kind:
		"enemy":
			return "противник — редкий или босс" if arg == "boss_or_rare" else "на противнике есть %s (вкладка «Условия»)" % arg
		"enemy_any":
			return "на противнике есть %s (вкладка «Условия»)" % arg.replace("|", " или ")
		"enemy_flag":
			return "противник %s (вкладка «Условия»)" % ("заморожен" if arg == "frozen" else arg)
		"player":
			if arg.begins_with("!"):
				return "выключено «%s» (вкладка «Условия»)" % PLAYER_FLAGS_RU.get(arg.substr(1), arg)
			return "включено «%s» (вкладка «Условия»)" % PLAYER_FLAGS_RU.get(arg, arg)
		"gear":
			return "два оружия в руках" if arg == "dual_wield" else "двуручное оружие ближнего боя"
		"slot":
			return "предмет в слоте «%s»" % ItemMods.SLOT_NAMES_RU.get(arg, arg)
	return cond


static func _is_weapon(item: Dictionary) -> bool:
	return not item.is_empty() and bool(GameData.item_base(int(item.get("base", -1))).get("isWeapon", false))


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
