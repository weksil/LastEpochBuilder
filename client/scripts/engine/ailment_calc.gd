class_name AilmentCalc

## Ailment (DoT) damage applied by a skill (research/06d):
## chance → stacks per second → damage of one stack (buildDamageStats on the ailment's base damage) → DPS.

## A stack that displaces another at the cap gets no early tick (ApplyAilmentWithDamageStats sets firstTickApplied for it):
## it is paid on the global ticks of the receiver, every AilmentReceiver.baseTickInterval (0.5 s unless the receiver is a player
## actor). `displaced_share` averages over the unknown phase of those ticks.
const ENEMY_TICK_INTERVAL: float = 0.5
## Ailments that are not paid on the generic ticks (damage at the end / when hit / on a hit of the target …) keep the old
## estimate (age + k) / (T + k), k = 0.5 − 0.1 (06d §4.3).
const ENEMY_TICK_K: float = 0.4
## PlayerProperty indices of the mutator fields that CharacterAilmentMutator.GetAilmentDamageModifier reads
## (research/data/game/player_property_fields.json).
const PP_TIME_ROT_PER_SLOW_CHANCE: int = 491  # moreTimeRotDamagePerGlobalSlowChance (0x1A20)
const PP_TIME_ROT_PER_TIME_ROT_CHANCE: int = 492  # moreTimeRotDamagePerGlobalTimeRotChanceWithVoidSkills (0x1A24)
const PP_TIME_ROT_PER_SPEED: int = 493  # moreTimeRotDamagePerLowestAttackCastOrThrowSpeed (0x1A28)
const PP_BRAND_OF_DECEPTION_PER_SHOCK_CHANCE: int = 307  # moreBrandOfDeceptionDamagePerShockChance (0x14E4)
const PP_WITCHFIRE_PER_IGNITE_CHANCE: int = 376  # moreWitchfireDamagePerIgniteChanceWithFireSkills (0x1768)
const PP_WITCHFIRE_PER_DAMNED_CHANCE: int = 377  # moreWitchfireDamagePerDamnedChanceWithNecroticSkills (0x176C)


## {sections: Array, enemy_dps: float, applied: Array[{id, rate, duration, max, self, effect}]} — `applied` feeds the automatic enemy
## ailments (EnemyAilments). `effect` is the increased ailment effect (SP 43) of the application, 0 unless the ailment's
## effectOfIncreasedEffectiveness is 0 (it then scales the buffs of Individual ailments, Enemy.store).
## `uses` is the number of hits per second that roll the chances. `curse_hit`: the hits are hits on a cursed enemy
## (docs/ENGINE.md §9.3): only chances that the skill tree attaches to «when the cursed enemy is hit» apply to them
## (the generic «chance to apply on hit» of items and passives does not), and the events are hits, not casts.
## `zone` (one entry of `zones()`): the applications of a zone that applies ailments every `interval` seconds to the
## enemies in it (RepeatedlyApplyAilmentsInRadius, no hit); `uses` is then ignored.
## `events_text` explains where `uses` (hits on the target per second) comes from. Positive ailments (Dusk Shroud, Haste …)
## go to you, not to the target: `applied` entries with `self` and the section «Buffs on you».
static func compute(build: Node, ctx: Dictionary, uses: float, notes: Array[String], curse_hit: bool = false,
		zone: Dictionary = {}, events_text: String = "") -> Dictionary:
	var health: int = SkillCalc._health_tags(build)
	var ability_tags: int = int(ctx["tags"]) | health
	var chances: Dictionary = _chances(ctx, ability_tags, curse_hit, zone)
	var unit: String = LE.t("hits on the cursed target") if curse_hit else LE.t("uses")
	if not zone.is_empty():
		uses = 1.0 / float(zone["interval"])
		unit = LE.t("zone applications")
	elif events_text != "":
		unit = LE.t("hits on the target")
	var sections: Array = []
	var applied_rows: Array = []
	var self_rows: Array = []
	var enemy_total: float = 0.0
	var applied: Array[Dictionary] = []
	var ids: Array = chances.keys()
	ids.sort()
	for id: int in ids:
		var c: Dictionary = chances[id]
		var ail: Dictionary = GameData.ailment(id)
		if ail.is_empty() or c["chance"] <= 0.0:
			continue
		var name: String = str(ail.get("name", c["name"]))
		var duration: float = float(ail.get("duration", 0.0)) * (1.0 + float(c["inc_dur"]))
		var max_inst: int = int(ail.get("maxInstances", 0))
		var chance_text: PackedStringArray = [LE.t("Chance per hit: %s (expected number of stacks = chance, 06d §1.1)") % LE.fmt_pct(c["chance"])]
		chance_text.append_array(c["lines"])
		# ApplyAilment: a chance above 100% adds stacks only for an ailment that holds more than one
		var one_stack_cap: bool = max_inst == 1 and float(c["chance"]) > 1.0
		if one_stack_cap:
			c = c.duplicate()
			c["chance"] = 1.0
		var rate: float = uses * float(c["chance"])
		var stacks: float = rate * duration if max_inst <= 0 else minf(rate * duration, float(max_inst))
		var on_self: bool = int(ail.get("positive", 0)) != 0
		# increased effect (SP 43) of this application: scales the buffs of Individual ailments (IndividualActiveBuffsForStackingAilment)
		var effect_applied: float = float(c["inc_eff"]) if int(ail.get("effectOfIncreasedEffectiveness", 1)) == 0 else 0.0
		applied.append({"id": id, "rate": rate, "duration": duration, "max": max_inst, "self": on_self, "effect": effect_applied})
		if one_stack_cap:
			chance_text.append(LE.t("The ailment holds one stack at most: a chance above 100% still applies it once per hit."))
		if not zone.is_empty():
			chance_text.append(LE.t("The zone \"%s\" applies it every %s s to the enemies in it (no hit); the target is assumed to stay in the zone (D?).") % [
				str(zone["name"]), LE.fmt_num(float(zone["interval"]))])
		elif curse_hit:
			chance_text.append(LE.t("Every hit on the cursed target counts (yours and others\'); the generic \"chance on hit\" from items and passives does not apply to them."))
		else:
			chance_text.append(events_text if events_text != "" else LE.t("One hit on the target per skill use counts."))
		if on_self:
			self_rows.append({"label": LE.t("%s: stacks on you") % name, "text": LE.fmt_num(stacks),
				"breakdown": "\n".join(chance_text) + "\n" + LE.t("Gains per second: %s × %s = %s; duration %s s%s → on average %s stacks. Used for \"Buffs on me\" unless a number is set on the Conditions tab.") % [
					LE.fmt_num(uses), LE.fmt_pct(c["chance"]), LE.fmt_num(rate), LE.fmt_num(duration),
					"" if max_inst <= 0 else LE.t(", maximum %d") % max_inst, LE.fmt_num(stacks)]})
			continue
		if not _deals_periodic_damage(ail):
			applied_rows.append({"label": LE.t("%s: stacks on target") % name, "text": LE.fmt_num(stacks),
				"breakdown": "\n".join(chance_text) + LE.t("\nApplications per second: %s × %s = %s; duration %s s%s → on average %s stacks.\nUsed as the enemy's stacks unless a number is set on the Conditions tab.") % [
					LE.fmt_num(uses), LE.fmt_pct(c["chance"]), LE.fmt_num(rate), LE.fmt_num(duration),
					"" if max_inst <= 0 else LE.t(", maximum %d") % max_inst, LE.fmt_num(stacks)]})
			continue
		var r: Dictionary = _damaging_ailment(build, ctx, ail, c, health, rate, duration, stacks, chance_text, unit)
		sections.append({"title": LE.t("Ailment: %s") % name, "rows": r["rows"]})
		enemy_total += float(r["enemy_dps"])
	if not applied_rows.is_empty():
		sections.append({"title": LE.t("Non-damaging ailments"), "rows": applied_rows})
	if not self_rows.is_empty():
		sections.append({"title": LE.t("Buffs on you"), "rows": self_rows})
	for conv: Dictionary in ctx.get("ailment_conversions", []):
		if GameData.ailment_id_by_name(str(conv["from"])) < 0 or GameData.ailment_id_by_name(str(conv["to"])) < 0:
			notes.append(LE.t("Node \"%s\": conversion %s → %s not recognised") % [conv["node"], conv["from"], conv["to"]])
	return {"sections": sections, "enemy_dps": enemy_total, "applied": applied}


## AilmentID -> {name, chance, lines, inc_dur, inc_eff, more}: prefab chances + AilmentChance stats + conversions.
## For a zone: its own ailments per application plus `zone.mods` (the AilmentChance stats of the skill's own store when
## the zone is the skill itself).
static func _chances(ctx: Dictionary, ability_tags: int, curse_hit: bool = false, zone: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	var base: Dictionary = ctx["base"]
	var entries: Array = ctx["ab"].get("ailmentsOnHit", [])
	if not zone.is_empty():
		entries = [{"class": "zone", "ailments": zone["ailments"]}]
	for entry: Dictionary in entries:
		var zone_entry: bool = str(entry.get("class", "")) == "zone"
		if curse_hit or not (zone_entry or str(entry.get("class", "")) == "ChanceToApplyAilmentsOnHit"):
			continue
		if not zone_entry and not base.is_empty() and str(entry.get("go", "")) != str(base.get("go", "")):
			continue
		for a: Dictionary in entry.get("ailments", []):
			var id: int = GameData.ailment_id_by_name(str(a.get("ailment", "")))
			if id < 0:
				continue
			var c: Dictionary = _entry(out, id)
			c["chance"] += float(a.get("chance", 0.0))
			c["inc_dur"] += float(a.get("increasedDuration", 0.0))
			c["inc_eff"] += float(a.get("increasedEffect", 0.0))
			c["more"] *= 1.0 + float(a.get("damageModifier", 0.0))
			c["lines"].append(LE.t("  +%s  (skill base chance)") % LE.fmt_pct(float(a.get("chance", 0.0))))
	# a zone has no hits: only the chances its own skill writes into it (tree nodes, skill specials), never «on hit» ones
	var chance_mods: Array = ctx["mods"] if zone.is_empty() else zone.get("mods", [])
	for mod: StatMod in chance_mods:
		if mod.special <= 0 or mod.added == 0.0 or not LE.tags_match(mod.tags, ability_tags):
			continue
		# chances of the «when the cursed enemy is hit» nodes belong to the curse hits only; generic ones to ordinary hits only
		if mod.property == LE.AILMENT_CHANCE and mod.on_curse_hit == curse_hit:
			var c: Dictionary = _entry(out, mod.special)
			c["chance"] += mod.added
			c["lines"].append("  +%s  (%s)" % [LE.fmt_pct(mod.added), mod.source])
	# conversions from skill-tree rules move the whole chance (06d §1.2, property 100)
	for conv: Dictionary in ctx.get("ailment_conversions", []):
		var from: int = GameData.ailment_id_by_name(str(conv["from"]))
		var to: int = GameData.ailment_id_by_name(str(conv["to"]))
		if from < 0 or to < 0 or from == to or not out.has(from):
			continue
		var src: Dictionary = out[from]
		var dst: Dictionary = _entry(out, to)
		dst["chance"] += src["chance"]
		dst["lines"].append(LE.t("  +%s  (conversion from %s, node \"%s\")") % [LE.fmt_pct(src["chance"]), src["name"], conv["node"]])
		src["chance"] = 0.0
	# conversions from item stats: property 100, specialTag = from, tags = to, applied when value > 0.1 (06d §1.2)
	for mod: StatMod in ctx["mods"]:
		# `tags` carries the target ailment id here: 0 is no target, from == to is no conversion (it would zero the chance)
		if mod.property != LE.AILMENT_CONVERSION or mod.added <= 0.1 or not out.has(mod.special) or mod.tags <= 0 or mod.tags == mod.special:
			continue
		var from_c: Dictionary = out[mod.special]
		var to_c: Dictionary = _entry(out, mod.tags)
		to_c["chance"] += from_c["chance"]
		to_c["lines"].append(LE.t("  +%s  (conversion from %s, %s)") % [LE.fmt_pct(from_c["chance"]), from_c["name"], mod.source])
		from_c["chance"] = 0.0
	# duration and effect stats (property 42 / 43, added value, 06d §1.2)
	for id: int in out:
		var c: Dictionary = out[id]
		for mod: StatMod in ctx["mods"]:
			if mod.special != id or mod.added == 0.0 or not LE.tags_match(mod.tags, ability_tags):
				continue
			if mod.property == 42:
				c["inc_dur"] += mod.added
				c["dur_lines"].append("  +%s  (%s)" % [LE.fmt_pct(mod.added), mod.source])
			elif mod.property == 43:
				c["inc_eff"] += mod.added
				c["eff_lines"].append("  +%s  (%s)" % [LE.fmt_pct(mod.added), mod.source])
	return out


## Zones of an ability that apply negative ailments every `interval` seconds without a hit (RepeatedlyApplyAilmentsInRadius):
## [{name, interval, ailments}]; an interval of 0 (every frame) counts as 0.1 s.
static func zones(ab: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in ab.get("ailmentsOnHit", []):
		if str(entry.get("class", "")) != "RepeatedlyApplyAilmentsInRadius":
			continue
		var ailments: Array = []
		for a: Dictionary in entry.get("ailments", []):
			var id: int = GameData.ailment_id_by_name(str(a.get("ailment", "")))
			if id >= 0 and int(GameData.ailment(id).get("positive", 0)) == 0:
				ailments.append(a)
		if ailments.is_empty():
			continue
		var interval: float = float(entry.get("other", {}).get("applicationInterval", 1.0))
		out.append({"name": str(entry.get("go", ab.get("name", ""))), "interval": maxf(interval, 0.1), "ailments": ailments})
	return out


## Tick interval of a zone after the skill's «increased ailment frequency» f (AuraOfDecayMutator.OnAbilityUse): interval / (1 + f);
## f <= -1 counts as -0.99.
static func zone_interval(interval: float, freq: float) -> float:
	if freq <= -1.0:
		freq = -0.99
	return interval / (freq + 1.0)


static func _entry(out: Dictionary, id: int) -> Dictionary:
	if not out.has(id):
		out[id] = {"name": str(GameData.ailment(id).get("name", id)), "chance": 0.0, "lines": [], "inc_dur": 0.0, "inc_eff": 0.0,
			"more": 1.0, "dur_lines": [], "eff_lines": []}
	return out[id]


static func _deals_periodic_damage(ail: Dictionary) -> bool:
	if not ail.get("dealsDamage", false):
		return false
	for v: Variant in ail.get("baseDamage", {}).get("damage", []):
		if float(v) > 0.0:
			return true
	return false


## Damage of one stack, DPS without enemy (Little's law, cap handling) and against the configured enemy.
static func _damaging_ailment(build: Node, ctx: Dictionary, ail: Dictionary, c: Dictionary, health: int,
		rate: float, duration: float, stacks: float, chance_text: PackedStringArray, unit: String = LE.t("uses")) -> Dictionary:
	var bd: Dictionary = ail.get("baseDamage", {})
	var atags: int = ((int(ail.get("tags", 0)) | LE.AILMENT | LE.DOT) & ~LE.HIT) | health
	var dmg: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var raw: Array = bd.get("damage", [])
	var type_bits: int = 0
	for i in range(mini(7, raw.size())):
		dmg[i] = float(raw[i])
		if dmg[i] > 0.0:
			type_bits |= LE.DT_TAG[i]
	# the conditional effects of the skill's DamageStatsHolder are not part of the ailment's DamageStats (AilmentReceiver.ApplyAilment
	# -> DamageStats.buildDamageStats copies only the ailment's own)
	var amods: Array[StatMod] = []
	for mod: StatMod in ctx["mods"]:
		if not mod.holder_only:
			amods.append(mod)
	var actx: Dictionary = {
		"ab": ctx["ab"], "base": bd, "tags": atags, "hit": false, "src": atags, "dmg": dmg, "type_bits": type_bits,
		"minion": 0, "ade": float(bd.get("addedDamageScaling", 0.0)), "mods": amods, "store": ctx["store"],
		"base_before": dmg.duplicate(), "conversion_lines": [[], [], [], [], [], [], []],
	}
	var ds: Dictionary = SkillCalc._build_damage(actx)

	# increased effect: more damage (effectOfIncreasedEffectiveness 0) or penetration of its type (1); 06d §2.1
	var inc_eff: float = float(c["inc_eff"])
	var eff_more: float = inc_eff if int(ail.get("effectOfIncreasedEffectiveness", 1)) == 0 else 0.0
	var eff_pen: float = inc_eff if int(ail.get("effectOfIncreasedEffectiveness", 1)) == 1 else 0.0
	var pen_type: int = int(ail.get("additionalPenetrationDamageType", 0))
	var dur_more: float = float(c["inc_dur"]) if _duration_increases_damage(ail) else 0.0
	var inst: Dictionary = _instance_more(build, ctx, ail, health)
	var more_total: float = (1.0 + eff_more) * (1.0 + dur_more) * float(c["more"]) * float(inst["factor"])
	var stack_damage: float = 0.0
	for i in range(7):
		stack_damage += float(ds["final"][i]) * more_total

	var max_inst: int = int(ail.get("maxInstances", 0))
	var dps: float = rate * stack_damage
	var cap_text: String = LE.t("No stack limit: DPS = applications/s × stack damage (stacks do not interfere with each other).")
	if max_inst > 0 and rate * duration > float(max_inst):
		var life: float = float(max_inst) / rate
		if _pays_on_generic_ticks(ail):
			var share: float = displaced_share(life, duration)
			dps = rate * stack_damage * share
			cap_text = LE.t("Limit of %d stacks: a new stack displaces the stack with the least time left, its damage is lost. The new stack has no early tick, it is paid on the global ticks every %s s (phase unknown, averaged): a stack that lives %s s of its %s s manages to deal %s of its damage.") % [
				max_inst, LE.fmt_num(ENEMY_TICK_INTERVAL), LE.fmt_num(life), LE.fmt_num(duration), LE.fmt_pct(share)]
		else:
			life = maxf(life, 0.1)
			var share_old: float = (life + ENEMY_TICK_K) / (duration + ENEMY_TICK_K)
			dps = rate * stack_damage * share_old
			cap_text = LE.t("Limit of %d stacks: a new stack displaces the stack with the least time left, its damage is lost. A stack lives %s s and manages to deal (%s + 0.4) / (%s + 0.4) = %s of its damage (06d §4.4).") % [
				max_inst, LE.fmt_num(life), LE.fmt_num(life), LE.fmt_num(duration), LE.fmt_pct(share_old)]

	var rows: Array = []
	rows.append({"label": LE.t("Application chance"), "text": LE.fmt_pct(c["chance"]), "breakdown": "\n".join(chance_text)})
	rows.append({"label": LE.t("Applications per second"), "text": LE.fmt_num(rate), "breakdown":
		LE.t("%s %s/s × chance %s = %s") % [LE.fmt_num(rate / maxf(float(c["chance"]), 0.000001)), unit, LE.fmt_pct(c["chance"]), LE.fmt_num(rate)]})
	var dur_text: PackedStringArray = [LE.t("%s s × (1 + %s) = %s s") % [LE.fmt_num(float(ail.get("duration", 0.0))), LE.fmt_pct(c["inc_dur"]), LE.fmt_num(duration)]]
	dur_text.append_array(c["dur_lines"])
	rows.append({"label": LE.t("Duration, s"), "text": LE.fmt_num(duration), "breakdown": "\n".join(dur_text)})
	rows.append({"label": LE.t("Average stacks on target"), "text": LE.fmt_num(stacks), "breakdown":
		LE.t("Applications/s × duration = %s × %s = %s%s") % [LE.fmt_num(rate), LE.fmt_num(duration), LE.fmt_num(rate * duration),
			"" if max_inst <= 0 else LE.t(", capped at %d") % max_inst]})
	for row: Dictionary in ds["rows"]:
		if row["label"] != LE.t("Total per hit (no crit)"):
			rows.append({"label": LE.t("Stack damage: %s") % row["label"], "text": row["text"], "breakdown": row["breakdown"] +
				LE.t("\nMods with the tags Hit/Melee/Spell/Bow/Throwing do not apply to ailments (ailment tags: %s).") % SkillCalc._tag_names(atags)})
	var stack_text: PackedStringArray = [LE.t("Sum over types × %s = %s") % [LE.fmt_num(more_total), LE.fmt_num(stack_damage)]]
	if eff_more != 0.0:
		stack_text.append(LE.t("Effect +%s increases damage: ×%s") % [LE.fmt_pct(eff_more), LE.fmt_num(1.0 + eff_more)])
	if dur_more != 0.0:
		stack_text.append(LE.t("Duration +%s stretches the stack and increases its total damage: ×%s (stack DPS is unchanged)") % [LE.fmt_pct(dur_more), LE.fmt_num(1.0 + dur_more)])
	if float(c["more"]) != 1.0:
		stack_text.append(LE.t("Damage modifier from the skill: ×%s") % LE.fmt_num(c["more"]))
	stack_text.append_array(inst["lines"])
	if eff_pen != 0.0:
		stack_text.append(LE.t("Effect +%s of this ailment gives penetration (%s), not damage (06d §2.1)") % [LE.fmt_pct(eff_pen), LE.t(LE.DT_NAME[pen_type])])
	stack_text.append_array(c["eff_lines"])
	stack_text.append(LE.t("Damage is fixed on application and dealt over the whole duration."))
	stack_text.append(LE.t("Skill tree mods and attribute scaling apply to its ailments the same way as to the hit (D?: assembly of the skill object\'s stats in the game code is not fully traced, 06d \"Could not\" item 2)."))
	rows.append({"label": LE.t("Total damage of one stack"), "text": LE.fmt_num(stack_damage), "breakdown": "\n".join(stack_text)})
	rows.append({"label": LE.t("DPS (without enemy)"), "text": LE.fmt_num(dps), "breakdown":
		LE.t("%s applications/s × %s stack damage = %s\n%s") % [LE.fmt_num(rate), LE.fmt_num(stack_damage), LE.fmt_num(rate * stack_damage), cap_text]})

	# against the enemy: same per-type mitigation as hits, without crit, armour only via property 118 (06d §3)
	var enemy: Dictionary = build.enemy
	var e: StatStore = Enemy.store(enemy)
	var dr: float = Enemy.level_dr(enemy)
	var armour: float = Enemy.armour(e)
	var armour_share: float = minf(1.0, e.query(LE.ARMOUR_VS_DOT).added)  # the victim's own SP 118 (ProtectionClass +0xCC), not the attacker's
	var cond_mods: Array[StatMod] = []
	for mod: StatMod in ctx["mods"]:
		if mod.property == LE.CONDITIONAL_DAMAGE or mod.property == LE.DAMAGE_PER_AILMENT_STACK:
			cond_mods.append(mod)
	var enemy_dps: float = 0.0
	var eb: PackedStringArray = []
	for i in range(7):
		var part: float = float(ds["final"][i]) * more_total
		if part <= 0.0:
			continue
		var lines: PackedStringArray = []
		var cond: float = SkillCalc._condition_factor(cond_mods, enemy, atags, i, lines, build.player_state)
		var res: float = Enemy.resistance(e, i).added
		var pen: float = float(ds["pen"][i]) + (eff_pen if i == pen_type else 0.0)
		var res_mult: float = (0.25 if res > 0.75 else 1.0 - res) + pen
		var dt_q: StatQuery = e.query(LE.DAMAGE_TAKEN, (atags & ~0xFF) | LE.DT_TAG[i])
		var dt: float = maxf(0.0, (1.0 + dt_q.added) * (1.0 + dt_q.increased) * dt_q.more)
		var arm: float = 1.0
		if armour != 0.0 and armour_share > 0.0:
			arm = 1.0 - Enemy.armour_mitigation(armour, int(enemy.get("level", 100)), i != 0) * armour_share
		var mult: float = cond * res_mult * dt * (1.0 - dr) * arm
		enemy_dps += dps * (part / stack_damage) * mult
		eb.append(LE.t("%s: share %s, resistance %s, penetration %s → ×%s; damage taken ×%s; level reduction ×%s%s%s → ×%s") % [
			LE.t(LE.DT_NAME[i]), LE.fmt_pct(part / stack_damage), LE.fmt_pct(res), LE.fmt_pct(pen), LE.fmt_num(res_mult), LE.fmt_num(dt),
			LE.fmt_num(1.0 - dr), "" if arm == 1.0 else LE.t("; armor ×%s") % LE.fmt_num(arm),
			"" if cond == 1.0 else LE.t("; conditions ×%s") % LE.fmt_num(cond), LE.fmt_num(mult)])
		eb.append_array(lines)
	eb.append(LE.t("Crit, dodge, block and variance do not apply to ailment damage; armor only with \"Armour Mitigation Applies to DoT\"."))
	rows.append({"label": LE.t("DPS vs enemy"), "text": LE.fmt_num(enemy_dps), "breakdown": "\n".join(eb)})
	return {"rows": rows, "dps": dps, "enemy_dps": enemy_dps}


## Share of its damage that a capped stack has been paid when it is removed `life` seconds after its creation. The stack has no
## early tick; the receiver's global ticks come every I = ENEMY_TICK_INTERVAL and each pays I / (I + remaining) of the unpaid
## damage (OnUpdateTick), so n ticks starting at u have paid n·I / (T − u + I). The first tick u after the creation is uniform in
## (0, I]; n = floor((life − u) / I) + 1 for u ≤ life, else 0. Averaged over u this is (q+1)·ln((T+I)/(T+I−r)) + q·ln((T+I−r)/T)
## with life = q·I + r. `life` must be below `duration` (a stack that expires is paid in full).
static func displaced_share(life: float, duration: float) -> float:
	var interval: float = ENEMY_TICK_INTERVAL
	var q: float = floorf(life / interval)
	var r: float = life - q * interval
	var top: float = duration + interval
	return (q + 1.0) * log(top / (top - r)) + q * log((top - r) / duration)


## The damaging ailment is paid by the generic ticks of OnUpdateTick (not at its end, when hit, when the holder hits or on a
## hit of the target).
static func _pays_on_generic_ticks(ail: Dictionary) -> bool:
	for flag: String in ["dealsAllDamageAtEnd", "dealsDamageWhenHit", "dealsDamageWhenAffectedHitsOthers", "dealsDamageOnAnguish", "movementAilment", "stopsWhenHit"]:
		if ail.get(flag, false):
			return false
	return true


## «More damage» that the game folds into ONE ailment instance (ActiveAilment.moreDamage, set when it is applied): the mods with
## `ailment_only` of this ailment and the modifier of the character mutator for Time Rot, Brand of Deception and Witchfire
## (CharacterAilmentMutator.GetAilmentDamageModifier). {factor, lines}
static func _instance_more(build: Node, ctx: Dictionary, ail: Dictionary, health: int) -> Dictionary:
	var id: int = int(ail.get("id", 0))
	var ability_tags: int = int(ctx["tags"]) | health
	var factor: float = 1.0
	var lines: PackedStringArray = []
	var chance_mods: Array[StatMod] = []
	var chance_loaded: bool = false
	for mod: StatMod in ctx["mods"]:
		if mod.ailment_only != id or mod.property != LE.DAMAGE or mod.more.is_empty():
			continue
		var scale: float = 1.0
		var scale_text: String = ""
		if mod.chance_scaled != 0:
			if not chance_loaded:
				# the caster's stats (Actor.stats = the character-wide store), not the skill's own mod list
				chance_mods = BuildMods.global_store(build)["store"].mods_of(LE.AILMENT_CHANCE)
				chance_loaded = true
			scale = stat_chance(chance_mods, mod.chance_scaled, ability_tags)
			scale_text = LE.t(" × %s chance %s") % [str(GameData.ailment(mod.chance_scaled).get("name", mod.chance_scaled)), LE.fmt_pct(scale)]
		for m: float in mod.more:
			var x: float = maxf(m * scale, -1.0)
			factor *= 1.0 + x
			lines.append(LE.t("Damage modifier of this ailment only: ×%s%s (%s)") % [LE.fmt_num(1.0 + x), scale_text, mod.source])
	var chars: Dictionary = _character_more(build, id, health)
	if float(chars["x"]) != 0.0:
		factor *= 1.0 + float(chars["x"])
		lines.append_array(chars["lines"])
	return {"factor": factor, "lines": lines}


## CharacterAilmentMutator.GetAilmentDamageModifier for the ailments of the character mutator (AilmentID 9, 107, 122): the
## chances are AilmentChance stats of the character for the stated tags (Stats.GetAilmentChance of CharacterMutator.stats), the
## factors are the PlayerProperty fields of passives, items and uniques. {x, lines}. The Witchfire term of PlayerProperty 521 is
## the `ailment_only` mod of its unique effect model.
static func _character_more(build: Node, id: int, health: int) -> Dictionary:
	var x: float = 0.0
	var lines: PackedStringArray = []
	if id == GameData.enum_value("AilmentID", "TimeRot"):
		var f_slow: float = float(EnemyAilments.player_property(build, PP_TIME_ROT_PER_SLOW_CHANCE)["value"])
		var f_rot: float = float(EnemyAilments.player_property(build, PP_TIME_ROT_PER_TIME_ROT_CHANCE)["value"])
		var f_speed: float = float(EnemyAilments.player_property(build, PP_TIME_ROT_PER_SPEED)["value"])
		if f_slow != 0.0 or f_rot != 0.0 or f_speed != 0.0:
			var store: StatStore = BuildMods.global_store(build)["store"]
			var chance_mods: Array[StatMod] = store.mods_of(LE.AILMENT_CHANCE)
			var slow: float = stat_chance(chance_mods, GameData.enum_value("AilmentID", "Slow"), LE.VOID | health)
			var rot: float = stat_chance(chance_mods, id, LE.VOID | health)
			var speed: float = lowest_speed_increase(store, health)
			x = (speed * f_speed + 1.0) * (rot * f_rot + 1.0) * (slow * f_slow + 1.0) - 1.0
			lines.append(LE.t("Damage modifier of the character (passives): (%s × %s + 1)(%s × %s + 1)(%s × %s + 1) − 1 = %s: lowest attack / cast / throwing speed, Time Rot chance with Void skills, Slow chance with Void skills") % [
				LE.fmt_pct(speed), LE.fmt_num(f_speed), LE.fmt_pct(rot), LE.fmt_num(f_rot), LE.fmt_pct(slow), LE.fmt_num(f_slow), LE.fmt_pct(x)])
	elif id == GameData.enum_value("AilmentID", "BrandOfDeception"):
		var f_shock: float = float(EnemyAilments.player_property(build, PP_BRAND_OF_DECEPTION_PER_SHOCK_CHANCE)["value"])
		if f_shock != 0.0:
			var shock_mods: Array[StatMod] = BuildMods.global_store(build)["store"].mods_of(LE.AILMENT_CHANCE)
			var shock: float = stat_chance(shock_mods, GameData.enum_value("AilmentID", "Shock"), health)
			x = shock * f_shock
			lines.append(LE.t("Damage modifier of the character (passives): Shock chance %s × %s = %s") % [LE.fmt_pct(shock), LE.fmt_num(f_shock), LE.fmt_pct(x)])
	elif id == GameData.enum_value("AilmentID", "Witchfire"):
		var f_ignite: float = float(EnemyAilments.player_property(build, PP_WITCHFIRE_PER_IGNITE_CHANCE)["value"])
		var f_damned: float = float(EnemyAilments.player_property(build, PP_WITCHFIRE_PER_DAMNED_CHANCE)["value"])
		if f_ignite != 0.0 or f_damned != 0.0:
			var fire_mods: Array[StatMod] = BuildMods.global_store(build)["store"].mods_of(LE.AILMENT_CHANCE)
			var ignite: float = stat_chance(fire_mods, GameData.enum_value("AilmentID", "Ignite"), LE.FIRE | health) if f_ignite != 0.0 else 0.0
			var damned: float = stat_chance(fire_mods, GameData.enum_value("AilmentID", "Damned"), LE.NECROTIC | health) if f_damned != 0.0 else 0.0
			x = ignite * f_ignite + damned * f_damned
			lines.append(LE.t("Damage modifier of the character (passives): Ignite chance with Fire skills %s × %s + Damned chance with Necrotic skills %s × %s = %s") % [
				LE.fmt_pct(ignite), LE.fmt_num(f_ignite), LE.fmt_pct(damned), LE.fmt_num(f_damned), LE.fmt_pct(x)])
	return {"x": x, "lines": lines}


## Stats.GetAilmentChance: Σ added · (1 + Σ increased) · Π(1 + more) of the AilmentChance stats of the ailment whose tags are
## contained in `tags` (the «cursed enemy is hit» chances are not stats of this kind). Stats with an extraTag (AutomaticNodeStats of
## one ability) are not counted: the game queries with extraTag 0 (Stats.GetStatValue matches extraTag == query, or 0).
static func stat_chance(mods: Array, id: int, tags: int) -> float:
	var added: float = 0.0
	var inc: float = 0.0
	var more: float = 1.0
	for mod: StatMod in mods:
		if mod.property != LE.AILMENT_CHANCE or mod.on_curse_hit or mod.extra != 0 or (mod.special != 0 and mod.special != id) or not LE.tags_match(mod.tags, tags):
			continue
		added += mod.added
		inc += mod.increased
		for m: float in mod.more:
			more *= 1.0 + m
	return added * (1.0 + inc) * more


## CharacterMutator.GetLowestAttackCastOrThrowSpeed: the lowest of the increased melee attack speed, throwing attack speed and
## cast speed (Stats.GetTotalIncreased: stats whose tags are contained in the queried ones), not below 0.
static func lowest_speed_increase(store: StatStore, health: int) -> float:
	var melee: float = store.query(LE.ATTACK_SPEED, LE.MELEE | health, 0, 0, false).increased
	var throwing: float = store.query(LE.ATTACK_SPEED, LE.THROWING | health, 0, 0, false).increased
	var cast: float = store.query(LE.CAST_SPEED, health, 0, 0, false).increased
	return maxf(minf(minf(melee, throwing), cast), 0.0)


## Longer duration raises total stack damage unless damage is dealt at the end / on hit (06d §1.3).
static func _duration_increases_damage(ail: Dictionary) -> bool:
	for flag: String in ["dealsAllDamageAtEnd", "dealsDamageWhenHit", "dealsDamageWhenAffectedHitsOthers", "dealsDamageOnAnguish"]:
		if ail.get(flag, false):
			return false
	return true
