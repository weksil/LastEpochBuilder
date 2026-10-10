class_name DefenseConversions

## Defensive mechanics of the character mutator and the protection class that are not plain stats (docs/ENGINE.md §10.2,
## research/07n, research/data/game/conditional_defenses.json): dodge / block conversions, the maximum block chance, the
## endurance mode, CharacterMutator.ApplyConditionalDefenses (slots f0 less/more damage, f1 block, f2 armor, f3/f4 endurance
## threshold, f5 crit avoidance, f7 delayed share, f8 extra endurance), per-type multipliers of over-capped resistances and
## "damage taken as another type" (ProtectionClass.ConvertDamageTaken).
## PlayerProperty values come from uniques, item and idol affixes, passives and skill tree nodes (`pp_values`). Unique
## effects that UniqueEffects already turned into stats (client/data/unique_effect_models.json, kind stat / overcap_taken)
## are left out here so they are not counted twice.

## Source type order of ConvertDamageTaken: Phys, Lightning, Cold, Fire, Void, Necrotic, Poison (AT bits), as LE.DT_* indices.
const CONVERT_SOURCE_ORDER: Array[int] = [0, 3, 2, 1, 5, 4, 6]
## SP 31..37 DamageTakenAsX: target index in LE.DT_* order (Phys, Fire, Cold, Lightning, Necrotic, Void, Poison).
const TAKEN_AS_TARGET: Dictionary = {31: 0, 32: 1, 33: 2, 34: 3, 35: 4, 36: 5, 37: 6}
const NEAR_DISTANCE_TEXT: String = "within 4 m"


## Sum of every PlayerProperty value of the build: {ppIndex: {value, lines: PackedStringArray}}. Unique effects already
## counted as stats are skipped (see the header).
static func pp_values(build: Node) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in UniqueEffects.entries(build):
		var effect: Dictionary = e["effect"]
		if str(effect.get("source", "")) != "PlayerProperty":
			continue
		var kind: String = str((e["model"] as Dictionary).get("kind", "stat")) if not (e["model"] as Dictionary).is_empty() else ""
		if kind == "stat" or kind == "overcap_taken":
			continue
		_add_pp(out, int(effect.get("ppIndex", -1)), float(e["pp"]), str(e["label"]))
	for slot: String in build.items:
		if not (BuildMods.SLOTS.has(slot) or IdolGrid.is_idol_key(slot)):
			continue
		for mod: StatMod in ItemMods.item_mods(slot, build.items[slot]):
			if mod.property == LE.PLAYER_PROPERTY:
				_add_pp(out, mod.tags, mod.added, mod.source)
				for m: float in mod.more:  # affixes of modType MORE (PP 275, 636, 677)
					_add_pp_more(out, mod.tags, m, mod.source)
	for entry: Dictionary in BuildMods._passive_entries(build):
		_add_node_pps(out, entry["node"], int(entry["points"]), str(entry["source"]), true)
	for slot in range(build.skills.size()):
		var skill: Dictionary = build.skills[slot]
		var ability: Dictionary = GameData.get_ability(str(skill.get("ability", "")))
		if ability.is_empty():
			continue
		var effects: Dictionary = GameData.skill_effects(str(ability.get("skillTree", "")))
		var tree: Dictionary = skill.get("tree", {})
		for node_id: Variant in tree:
			var node: Dictionary = effects.get(int(node_id), {})
			if not node.is_empty():
				_add_node_pps(out, node, int(tree[node_id]), "%s: %s" % [GameData.display_name(ability), GameData.display_name(node)])
	return out


static func _add_node_pps(out: Dictionary, node: Dictionary, points: int, source: String, passive: bool = false) -> void:
	if points <= 0:
		return
	for effect: Dictionary in node.get("effects", []):
		var stat: Variant = effect.get("stat")
		if effect.get("op") != "add_stat" or not stat is Dictionary:
			continue
		var kind: String = str(stat.get("kind", ""))
		if kind != "player_property" and kind != "more_player_property":
			continue
		if points < int(effect.get("minPoints", 0)):
			continue
		var index: int = int(stat.get("playerPropertyIndex", -1))
		var model: Dictionary = GameData.unique_player_model(index)
		if passive and not model.is_empty() and ["stat", "overcap_taken"].has(str(model.get("kind", "stat"))):
			continue  # already a stat (UniqueEffects passive entries), as for uniques
		var value: float = BuildMods.eval_value(stat.get("value"), points)
		if kind == "more_player_property":
			_add_pp_more(out, index, value, source)
		else:
			_add_pp(out, index, value, source)


static func _add_pp(out: Dictionary, pp: int, value: float, source: String) -> void:
	if pp < 0 or is_zero_approx(value):
		return
	if not out.has(pp):
		out[pp] = {"value": 0.0, "lines": PackedStringArray()}
	out[pp]["value"] = float(out[pp]["value"]) + value
	out[pp]["lines"].append("%s: %s" % [source, LE.fmt_num(value)])


## A `more` PlayerProperty stat (Stats.MorePlayerPropertyStat, an affix of modType MORE): the character mutator folds it as
## field = (1 + field)(1 + m) − 1 (applyModifiersBeforeExternalStatsCalculation, getMoreMultiplier cases).
static func _add_pp_more(out: Dictionary, pp: int, m: float, source: String) -> void:
	if pp < 0 or is_zero_approx(m):
		return
	if not out.has(pp):
		out[pp] = {"value": 0.0, "lines": PackedStringArray()}
	out[pp]["value"] = (1.0 + float(out[pp]["value"])) * (1.0 + m) - 1.0
	out[pp]["lines"].append("%s: %s" % [source, LE.fmt_num(m)])


static func _pp(pps: Dictionary, index: int) -> float:
	return float(pps.get(index, {}).get("value", 0.0))


## Damage over time taken while you have Haste (PP 275, ApplyConditionalDefenses): max(−0.75, (1 + increased effect of Haste on you)·pp).
static func haste_dot_more(pp275: float, haste_effect_increased: float) -> float:
	return maxf((1.0 + haste_effect_increased) * pp275, -0.75)


## attack: DefenseCalc.enemy_attack (is_hit, attacker_kind); layers fields used: res, block_dr.
## {dodge_conversion, block_conversion, max_block, endurance_mode, endurance_extra, delayed, block_dot,
##  hit_more, dot_more (f0 for hits / DoT), block_add (f1), armour_more (f2), threshold_add (f3 + f4), crit_avoid_add (f5),
##  type_more: Array[float] (7), taken_as: [{source, target, share, text}], lines: PackedStringArray, unknown: PackedStringArray}
static func collect(build: Node, store: StatStore, attack: Dictionary = {}) -> Dictionary:
	var pps: Dictionary = pp_values(build)
	var out: Dictionary = {
		"dodge_conversion": 0, "block_conversion": 0, "max_block": 0.0, "endurance_mode": 0, "endurance_extra": 0.0,
		"delayed": 0.0, "block_dot": 0.0, "hit_more": 1.0, "dot_more": 1.0, "block_add": 0.0, "armour_more": 0.0,
		"threshold_add": 0.0, "crit_avoid_add": 0.0, "type_more": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
		"ward_bypass": false, "health_cap": 0.0, "ward_cap": 0.0,
		"taken_as": [], "lines": PackedStringArray(), "unknown": PackedStringArray(), "pps": pps,
	}
	var lines: PackedStringArray = out["lines"]
	# conversions and modes (applyModifiersBeforeExternalStatsCalculation, 07n §2)
	if _pp(pps, 425) > 0.1:
		out["dodge_conversion"] = 3
	elif _pp(pps, 194) > 0.1:
		out["dodge_conversion"] = 2
	elif _pp(pps, 177) > 0.1:
		out["dodge_conversion"] = 1
	if int(out["dodge_conversion"]) != 0:
		lines.append(LE.t("Dodge rating converted to %s: you cannot dodge") % LE.t(["", "armor", "glancing blow chance (2 × dodge chance)",
			"endurance threshold"][int(out["dodge_conversion"])]))
	if _pp(pps, 531) > 0.1 and not _has_shield(build):
		out["block_conversion"] = 2
	elif _pp(pps, 392) > 0.1:
		out["block_conversion"] = 1
	if int(out["block_conversion"]) != 0:
		lines.append(LE.t("Block chance converted to %s: you cannot block") % LE.t(["", "glancing blow chance", "parry chance"][int(out["block_conversion"])]))
	out["max_block"] = _pp(pps, 614)
	if float(out["max_block"]) > 0.0:
		lines.append(LE.t("Maximum block chance %s") % LE.fmt_pct(float(out["max_block"])))
	if _pp(pps, 310) > 0.1:
		out["endurance_mode"] = 2
		lines.append(LE.t("Endurance applies to all damage (before ward)"))
	elif _pp(pps, 309) > 0.1:
		out["endurance_mode"] = 1
		lines.append(LE.t("Endurance also reduces the mana spent by mana before health"))
	_conditional(build, store, attack, pps, out)
	_ward_and_health_caps(build, attack, pps, out)
	_taken_as(store, out)
	return out


## Ward bypass of this attack and the caps of current health and ward (ProtectionClass.ApplyDamage, BaseHealth.restoreHealth,
## ProtectionClass.GainWard): hits skip the ward with PP 685, damage over time with the Acolyte node Impact Ward (3+ points);
## Corrupted Form (2+ points) caps current health and ward at 50% of maximum health, PP 609 caps ward at v × maximum health.
static func _ward_and_health_caps(build: Node, attack: Dictionary, pps: Dictionary, out: Dictionary) -> void:
	var dots_bypass: bool = false
	var health_cap: float = 0.0
	var ward_cap_tree: float = 0.0
	for entry: Dictionary in BuildMods._passive_entries(build):
		var points: int = int(entry["points"])
		for effect: Dictionary in (entry["node"] as Dictionary).get("effects", []):
			if points < int(effect.get("minPoints", 0)) or not effect.has("value"):
				continue
			var v: float = BuildMods.eval_value(effect.get("value"), points)
			match str(effect.get("target", "")):
				"CharacterMutator.dotsBypassWard":
					dots_bypass = dots_bypass or v > 0.0
				"CharacterMutator.maxHealthCapForCurrentHealth":
					if v > 0.0:
						health_cap = v
				"CharacterMutator.maxHealthCapForWardFromAcolyteTree":
					if v > 0.0:
						ward_cap_tree = v
	var is_hit: bool = bool(attack.get("is_hit", true))
	var bypass: bool = (_pp(pps, 685) > 0.1) if is_hit else dots_bypass
	out["ward_bypass"] = bypass
	out["health_cap"] = health_cap
	out["ward_cap"] = ward_cap_share(ward_cap_tree, _pp(pps, 609))
	if bypass:
		out["lines"].append(LE.t("Hit damage taken bypasses ward (PP 685)") if is_hit else LE.t("Damage over time taken bypasses ward"))
	if health_cap > 0.0:
		out["lines"].append(LE.t("Current health cannot exceed %s of maximum health") % LE.fmt_pct(health_cap))
	if float(out["ward_cap"]) > 0.0:
		out["lines"].append(LE.t("Ward cannot exceed %s of maximum health") % LE.fmt_pct(float(out["ward_cap"])))


## CharacterMutator: the ward cap is the smaller of the non-zero values of the Acolyte tree field (0x670) and PP 609 (0x1EE8).
static func ward_cap_share(tree: float, pp609: float) -> float:
	if tree == 0.0:
		return maxf(pp609, 0.0)
	if pp609 == 0.0:
		return tree
	return minf(tree, pp609)


## CharacterMutator.ApplyConditionalDefenses (research/07n §3): only the conditions UniqueEffects does not already count.
static func _conditional(build: Node, store: StatStore, attack: Dictionary, pps: Dictionary, out: Dictionary) -> void:
	var lines: PackedStringArray = out["lines"]
	var enemy: Dictionary = build.enemy
	var ailments: Dictionary = enemy.get("ailments", {})
	var kind: String = str(attack.get("attacker_kind", enemy.get("kind", "dummy")))
	var rare_boss: bool = kind == "rare" or kind == "boss" or kind == "miniboss"
	var is_hit: bool = bool(attack.get("is_hit", true))
	var ps: Dictionary = build.player_state

	var more: Callable = func(pp: int, x: float, text: String, hit: bool, dot: bool) -> void:
		if is_zero_approx(x):
			return
		if hit:
			out["hit_more"] = float(out["hit_more"]) * (1.0 + x)
		if dot:
			out["dot_more"] = float(out["dot_more"]) * (1.0 + x)
		lines.append(LE.t("%s: damage taken ×%s (PP %d)") % [text, LE.fmt_num(1.0 + x), pp])

	var stacks: Callable = func(name: String) -> int:
		return int(ailments.get(GameData.ailment_id_by_name(name), 0))

	# Maths.distanceLessThan(player, attacker, 4.0) is a strict 3D distance test; the distance is the Conditions value `attacker_distance` (default 1)
	var near: bool = float(ps.get("attacker_distance", 1.0)) < 4.0
	if near:
		more.call(257, _pp(pps, 257), LE.t("Enemy within 4 m"), true, true)
		if _pp(pps, 258) != 0.0:
			out["block_add"] = float(out["block_add"]) + _pp(pps, 258)
			lines.append(LE.t("Enemy within 4 m: block chance +%s (PP 258)") % LE.fmt_pct(_pp(pps, 258)))
	# BaseMana.currentMana (CharacterMutator.ApplyConditionalDefenses): the Conditions value, 0 = the maximum
	var mana: float = EffectModels.current_mana(build, store.query_untagged(LE.MANA).value())
	if mana >= 400.0 and not bool(ps.get("low_mana", false)):
		more.call(262, _pp(pps, 262), LE.t("At least 400 current mana"), true, true)
	# Haste on you: damage over time taken ×(1 + max(−0.75, (1 + increased Haste effect on you)·PP 275)) (ApplyConditionalDefenses)
	if not is_hit and _pp(pps, 275) != 0.0 and (bool(ps.get("haste", false)) or BuildMods.buff_stacks(build, int(BuildMods.PLAYER_AILMENTS["haste"])) > 0.0):
		var haste_inc: float = store.query(LE.EFFECT_OF_AILMENT_ON_YOU, 0, int(BuildMods.PLAYER_AILMENTS["haste"])).increased
		more.call(275, haste_dot_more(_pp(pps, 275), haste_inc), LE.t("Damage over time taken while you have Haste"), false, true)
	var cold_over: float = Enemy.resistance(store, 2).value() - 0.75
	if cold_over > 0.0 and _pp(pps, 677) != 0.0:
		more.call(677, minf(2.0, cold_over) * _pp(pps, 677) * 12.5, LE.t("Damage over time per 8% overcapped cold resistance"), false, true)
	# attacker ailments (the enemy of the Conditions tab)
	if stacks.call("Chill") > 0:
		more.call(250, _pp(pps, 250), LE.t("Chilled attacker"), true, true)
	if stacks.call("Slow") > 0:
		more.call(561, _pp(pps, 561), LE.t("Slowed attacker"), true, true)
	if stacks.call("TimeRot") > 0:
		more.call(490, _pp(pps, 490), LE.t("Time Rotted attacker"), true, true)
	var shock: int = stacks.call("Shock")
	var ignite: int = stacks.call("Ignite")
	if shock > 0:
		more.call(252, _pp(pps, 252), LE.t("Shocked attacker"), true, true)
		if _pp(pps, 321) != 0.0:
			out["crit_avoid_add"] = float(out["crit_avoid_add"]) + _pp(pps, 321)
			lines.append(LE.t("Shocked attacker: crit avoidance +%s (PP 321)") % LE.fmt_pct(_pp(pps, 321)))
		var armour_shock: float = (1.0 + shock * _pp(pps, 323))
		if not is_equal_approx(armour_shock, 1.0):
			out["armour_more"] = (1.0 + float(out["armour_more"])) * armour_shock - 1.0
			lines.append(LE.t("Shocked attacker: armor ×%s for %d Shock stacks (PP 323)") % [LE.fmt_num(armour_shock), shock])
	if ignite > 0:
		more.call(251, _pp(pps, 251), LE.t("Ignited attacker"), true, true)
		var th: float = ignite * _pp(pps, 322) + shock * _pp(pps, 549)
		if th != 0.0:
			out["threshold_add"] = float(out["threshold_add"]) + th
			lines.append(LE.t("Ignited attacker: endurance threshold +%s (PP 322, 549)") % LE.fmt_num(th))
	if ignite > 0 or stacks.call("Damned") > 0 or stacks.call("Bleed") > 0:
		more.call(346, _pp(pps, 346), LE.t("Ignited, Damned or Bleeding attacker"), true, true)
	if stacks.call("Chill") > 0 or stacks.call("Bleed") > 0:
		more.call(711, _pp(pps, 711), LE.t("Chilled or Bleeding attacker"), true, true)
	var curses: int = _curses(ailments)
	if curses > 0:
		more.call(347, _pp(pps, 347), LE.t("Cursed attacker"), true, true)
		more.call(356, curses * _pp(pps, 356), LE.t("%d curses on the attacker") % curses, true, true)
		if _pp(pps, 354) != 0.0:
			out["armour_more"] = (1.0 + float(out["armour_more"])) * (1.0 + curses * _pp(pps, 354)) - 1.0
			lines.append(LE.t("%d curses on the attacker: armor ×%s (PP 354)") % [curses, LE.fmt_num(1.0 + curses * _pp(pps, 354))])
	if stacks.call("Withering") > 0:
		more.call(373, _pp(pps, 373), LE.t("Withering attacker"), true, true)
	# minions taking a share of the damage: the planner assumes the minion is alive
	var h: float = minf(_pp(pps, 496), 0.75)
	var l: float = minf(_pp(pps, 562), 0.75 - h)
	if h > 0.0:
		more.call(496, -h, LE.t("Damage redirected to your highest health minion (assumed alive)"), true, true)
	if l > 0.0:
		more.call(562, -l, LE.t("Damage redirected to your lowest health minion (assumed alive)"), true, true)
	more.call(670, -_pp(pps, 670), LE.t("Damage redirected to your Summoned Bear (assumed above half health)"), true, true)
	# block effectiveness against damage over time (Countenance of Majasa)
	out["block_dot"] = _pp(pps, 524)
	# delayed share of hits (slot f7)
	if is_hit:
		var x: float = (1.0 - _pp(pps, 498)) if rare_boss and _pp(pps, 498) != 0.0 else 1.0
		if _pp(pps, 671) != 0.0 and stacks.call("SpiritPlague") > 0:
			x *= 1.0 - _pp(pps, 671)
		out["delayed"] = clampf(1.0 - (1.0 - _pp(pps, 564)) * x, 0.0, 1.0)
		if float(out["delayed"]) > 0.0:
			lines.append(LE.t("%s of the hit is taken over 4 s instead (PP 498, 564, 671)") % LE.fmt_pct(float(out["delayed"])))
	# extra endurance f8 (pp 525): while the delayed damage still to be taken exceeds 10% of max health. The pool decides it per hit
	# (DefenseCalc.endurance_of); below the threshold it also needs base endurance above 0 (modes 0 and 1)
	if _pp(pps, 525) != 0.0:
		out["endurance_extra"] = _pp(pps, 525)
		lines.append(LE.t("Extra endurance %s while the delayed damage left exceeds a tenth of maximum health (PP 525)") % LE.fmt_pct(_pp(pps, 525)))
	# per-type multipliers of over-capped resistances (damage array, not a slot)
	var fire_over: float = Enemy.resistance(store, 1).value() - 0.75
	if fire_over > 0.0 and _pp(pps, 436) != 0.0:
		var f: float = maxf(_pp(pps, 437), fire_over / 0.1 * _pp(pps, 436))
		out["type_more"][1] = float(out["type_more"][1]) * (1.0 + f)
		lines.append(LE.t("Fire damage taken ×%s from %s fire resistance above the cap (PP 436, 437)") % [LE.fmt_num(1.0 + f), LE.fmt_pct(fire_over)])
	# Knight "Battle Hardened": more physical damage taken per 5% over-capped physical resistance, at most −10% (tree field)
	var phys_field: float = 0.0
	for entry: Dictionary in BuildMods._passive_entries(build):
		for effect: Dictionary in (entry["node"] as Dictionary).get("effects", []):
			if str(effect.get("target", "")) == "CharacterMutator.morePhysDamageTakenPer5OvercappedPhysResUpTo10Percent" \
					and int(entry["points"]) >= int(effect.get("minPoints", 0)):
				phys_field += BuildMods.eval_value(effect.get("value"), int(entry["points"]))
	var phys_over: float = Enemy.resistance(store, 0).value() - 0.75
	if phys_field != 0.0 and phys_over > 0.0:
		var pf: float = maxf(-0.1, phys_over / 0.05 * phys_field)
		out["type_more"][0] = float(out["type_more"][0]) * (1.0 + pf)
		lines.append(LE.t("Physical damage taken ×%s from %s physical resistance above the cap (Battle Hardened)") % [LE.fmt_num(1.0 + pf), LE.fmt_pct(phys_over)])
	# trackers on the attacker that the planner cannot see
	for pp: int in [619, 650]:
		if _pp(pps, pp) > 0.1:
			out["unknown"].append(LE.t("PP %d: less damage from enemies hit by your Hail of Arrows / Drain Life — not counted") % pp)


## Number of curses on the enemy of the Conditions tab.
static func _curses(ailments: Dictionary) -> int:
	var n: int = 0
	for id: Variant in ailments:
		if int(ailments[id]) > 0 and bool(GameData.ailment(int(id)).get("isCurse", false)):
			n += 1
	return n


static func _has_shield(build: Node) -> bool:
	var off: Dictionary = build.items.get("offhand", {})
	if off.is_empty():
		return false
	return str(GameData.item_base(int(off.get("base", -1))).get("typeName", "")) == "SHIELD"


## SP 31–37 "damage taken as X": stat tags = source type, SP = target type; added only, each (SP, tags) share capped at 1,
## not normalised, every stat reads the original damage (07n §1).
static func _taken_as(store: StatStore, out: Dictionary) -> void:
	var shares: Dictionary = {}  # "sp|tags" -> {sp, tags, value, lines}
	for mod: StatMod in store.all_mods():
		if not TAKEN_AS_TARGET.has(mod.property) or is_zero_approx(mod.added):
			continue
		var key: String = "%d|%d" % [mod.property, mod.tags]
		if not shares.has(key):
			shares[key] = {"sp": mod.property, "tags": mod.tags, "value": 0.0, "sources": PackedStringArray()}
		shares[key]["value"] = float(shares[key]["value"]) + mod.added
		shares[key]["sources"].append(mod.describe())
	for key: String in shares:
		var sh: Dictionary = shares[key]
		var sources: Array[int] = []
		for i: int in CONVERT_SOURCE_ORDER:
			if int(sh["tags"]) & LE.DT_TAG[i]:
				sources.append(i)
		if sources.is_empty():
			out["unknown"].append(LE.t("Damage taken as %s without a source damage type does nothing in the game") % LE.t(LE.DT_NAME[TAKEN_AS_TARGET[sh["sp"]]]))
			continue
		out["taken_as"].append({"sources": sources, "target": int(TAKEN_AS_TARGET[sh["sp"]]), "share": minf(float(sh["value"]), 1.0),
			"text": "\n".join(sh["sources"])})


## Applies the "taken as" shares to a raw damage array (ConvertDamageTaken): {damage: Array[float], lines}.
static func convert_damage(taken_as: Array, damage: Array[float]) -> Dictionary:
	var result: Array[float] = damage.duplicate()
	var lines: PackedStringArray = []
	for c: Dictionary in taken_as:
		for i: int in c["sources"]:
			if damage[i] == 0.0:
				continue
			var m: float = float(c["share"]) * damage[i]
			result[int(c["target"])] += m
			result[i] -= m
			lines.append(LE.t("%s of %s damage taken as %s: %s") % [LE.fmt_pct(float(c["share"])), LE.t(LE.DT_NAME[i]),
				LE.t(LE.DT_NAME[int(c["target"])]), LE.fmt_num(m)])
			break
	for i in range(7):
		result[i] = maxf(result[i], 0.0)
	return {"damage": result, "lines": lines}
