class_name AilmentCalc

## Ailment (DoT) damage applied by a skill (research/06d):
## chance → stacks per second → damage of one stack (buildDamageStats on the ailment's base damage) → DPS.

## Against enemies the first tick comes 0.1 s after application and ticks run every 0.5 s,
## so a stack replaced early still delivered (age + k) / (T + k) of its damage, k = 0.5 − 0.1 (06d §4.3).
const ENEMY_TICK_K: float = 0.4


## {sections: Array, tooltip_dps: float, enemy_dps: float}
static func compute(build: Node, ctx: Dictionary, uses: float, notes: Array[String]) -> Dictionary:
	var health: int = SkillCalc._health_tags(build)
	var ability_tags: int = int(ctx["tags"]) | health
	var chances: Dictionary = _chances(ctx, ability_tags)
	var sections: Array = []
	var applied_rows: Array = []
	var tooltip_total: float = 0.0
	var enemy_total: float = 0.0
	var ids: Array = chances.keys()
	ids.sort()
	for id: int in ids:
		var c: Dictionary = chances[id]
		var ail: Dictionary = GameData.ailment(id)
		if ail.is_empty() or c["chance"] <= 0.0:
			continue
		var name: String = str(ail.get("name", c["name"]))
		var rate: float = uses * float(c["chance"])
		var duration: float = float(ail.get("duration", 0.0)) * (1.0 + float(c["inc_dur"]))
		var max_inst: int = int(ail.get("maxInstances", 0))
		var stacks: float = rate * duration if max_inst <= 0 else minf(rate * duration, float(max_inst))
		var chance_text: PackedStringArray = ["Шанс за попадание: %s (ожидание числа стаков = шанс, 06d §1.1)" % LE.fmt_pct(c["chance"])]
		chance_text.append_array(c["lines"])
		chance_text.append("Считается одно попадание по цели за применение умения.")
		if not _deals_periodic_damage(ail):
			applied_rows.append({"label": "%s: стаков на цели" % name, "text": LE.fmt_num(stacks),
				"breakdown": "\n".join(chance_text) + "\nНаложений в секунду: %s × %s = %s; длительность %s с%s → в среднем %s стаков.\nЭффект на враге задаётся во вкладке «Условия» числом стаков." % [
					LE.fmt_num(uses), LE.fmt_pct(c["chance"]), LE.fmt_num(rate), LE.fmt_num(duration),
					"" if max_inst <= 0 else ", максимум %d" % max_inst, LE.fmt_num(stacks)]})
			continue
		var r: Dictionary = _damaging_ailment(build, ctx, ail, c, health, rate, duration, stacks, chance_text)
		sections.append({"title": "Айлмент: %s" % name, "rows": r["rows"]})
		tooltip_total += float(r["dps"])
		enemy_total += float(r["enemy_dps"])
	if not applied_rows.is_empty():
		sections.append({"title": "Наложение айлментов без урона", "rows": applied_rows})
	for conv: Dictionary in ctx.get("ailment_conversions", []):
		if GameData.ailment_id_by_name(str(conv["from"])) < 0 or GameData.ailment_id_by_name(str(conv["to"])) < 0:
			notes.append("Узел «%s»: конверсия %s → %s не распознана" % [conv["node"], conv["from"], conv["to"]])
	return {"sections": sections, "tooltip_dps": tooltip_total, "enemy_dps": enemy_total}


## AilmentID -> {name, chance, lines, inc_dur, inc_eff, more}: prefab chances + AilmentChance stats + conversions.
static func _chances(ctx: Dictionary, ability_tags: int) -> Dictionary:
	var out: Dictionary = {}
	var base: Dictionary = ctx["base"]
	for entry: Dictionary in ctx["ab"].get("ailmentsOnHit", []):
		if str(entry.get("class", "")) != "ChanceToApplyAilmentsOnHit":
			continue
		if not base.is_empty() and str(entry.get("go", "")) != str(base.get("go", "")):
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
			c["lines"].append("  +%s  (базовый шанс умения)" % LE.fmt_pct(float(a.get("chance", 0.0))))
	for mod: StatMod in ctx["mods"]:
		if mod.special <= 0 or mod.added == 0.0 or not LE.tags_match(mod.tags, ability_tags):
			continue
		if mod.property == LE.AILMENT_CHANCE:
			var c: Dictionary = _entry(out, mod.special)
			c["chance"] += mod.added
			c["lines"].append("  +%s  (%s)" % [LE.fmt_pct(mod.added), mod.source])
	# conversions from skill-tree rules move the whole chance (06d §1.2, property 100)
	for conv: Dictionary in ctx.get("ailment_conversions", []):
		var from: int = GameData.ailment_id_by_name(str(conv["from"]))
		var to: int = GameData.ailment_id_by_name(str(conv["to"]))
		if from < 0 or to < 0 or not out.has(from):
			continue
		var src: Dictionary = out[from]
		var dst: Dictionary = _entry(out, to)
		dst["chance"] += src["chance"]
		dst["lines"].append("  +%s  (конверсия из %s, узел «%s»)" % [LE.fmt_pct(src["chance"]), src["name"], conv["node"]])
		src["chance"] = 0.0
	# conversions from item stats: property 100, specialTag = from, tags = to, applied when value > 0.1 (06d §1.2)
	for mod: StatMod in ctx["mods"]:
		if mod.property != LE.AILMENT_CONVERSION or mod.added <= 0.1 or not out.has(mod.special):
			continue
		var from_c: Dictionary = out[mod.special]
		var to_c: Dictionary = _entry(out, mod.tags)
		to_c["chance"] += from_c["chance"]
		to_c["lines"].append("  +%s  (конверсия из %s, %s)" % [LE.fmt_pct(from_c["chance"]), from_c["name"], mod.source])
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
		rate: float, duration: float, stacks: float, chance_text: PackedStringArray) -> Dictionary:
	var bd: Dictionary = ail.get("baseDamage", {})
	var atags: int = ((int(ail.get("tags", 0)) | LE.AILMENT | LE.DOT) & ~LE.HIT) | health
	var dmg: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var raw: Array = bd.get("damage", [])
	var type_bits: int = 0
	for i in range(mini(7, raw.size())):
		dmg[i] = float(raw[i])
		if dmg[i] > 0.0:
			type_bits |= LE.DT_TAG[i]
	var actx: Dictionary = {
		"ab": ctx["ab"], "base": bd, "tags": atags, "hit": false, "src": atags, "dmg": dmg, "type_bits": type_bits,
		"minion": 0, "ade": float(bd.get("addedDamageScaling", 0.0)), "mods": ctx["mods"], "store": ctx["store"],
		"base_before": dmg.duplicate(), "conversion_lines": [[], [], [], [], [], [], []],
	}
	var ds: Dictionary = SkillCalc._build_damage(actx)

	# increased effect: more damage (effectOfIncreasedEffectiveness 0) or penetration of its type (1); 06d §2.1
	var inc_eff: float = float(c["inc_eff"])
	var eff_more: float = inc_eff if int(ail.get("effectOfIncreasedEffectiveness", 1)) == 0 else 0.0
	var eff_pen: float = inc_eff if int(ail.get("effectOfIncreasedEffectiveness", 1)) == 1 else 0.0
	var pen_type: int = int(ail.get("additionalPenetrationDamageType", 0))
	var dur_more: float = float(c["inc_dur"]) if _duration_increases_damage(ail) else 0.0
	var more_total: float = (1.0 + eff_more) * (1.0 + dur_more) * float(c["more"])
	var stack_damage: float = 0.0
	for i in range(7):
		stack_damage += float(ds["final"][i]) * more_total

	var max_inst: int = int(ail.get("maxInstances", 0))
	var dps: float = rate * stack_damage
	var cap_text: String = "Лимита стаков нет: DPS = наложений/с × урон стака (стаки не мешают друг другу)."
	if max_inst > 0 and rate * duration > float(max_inst):
		var life: float = maxf(float(max_inst) / rate, 0.1)
		var share: float = (life + ENEMY_TICK_K) / (duration + ENEMY_TICK_K)
		dps = rate * stack_damage * share
		cap_text = "Лимит %d стаков: новый стак вытесняет стак с наименьшим остатком, его урон теряется. Стак живёт %s с и успевает нанести (%s + 0.4) / (%s + 0.4) = %s урона (06d §4.4)." % [
			max_inst, LE.fmt_num(life), LE.fmt_num(life), LE.fmt_num(duration), LE.fmt_pct(share)]

	var rows: Array = []
	rows.append({"label": "Шанс наложения", "text": LE.fmt_pct(c["chance"]), "breakdown": "\n".join(chance_text)})
	rows.append({"label": "Наложений в секунду", "text": LE.fmt_num(rate), "breakdown":
		"%s применений/с × шанс %s = %s" % [LE.fmt_num(rate / maxf(float(c["chance"]), 0.000001)), LE.fmt_pct(c["chance"]), LE.fmt_num(rate)]})
	var dur_text: PackedStringArray = ["%s с × (1 + %s) = %s с" % [LE.fmt_num(float(ail.get("duration", 0.0))), LE.fmt_pct(c["inc_dur"]), LE.fmt_num(duration)]]
	dur_text.append_array(c["dur_lines"])
	rows.append({"label": "Длительность, с", "text": LE.fmt_num(duration), "breakdown": "\n".join(dur_text)})
	rows.append({"label": "Стаков на цели в среднем", "text": LE.fmt_num(stacks), "breakdown":
		"Наложений/с × длительность = %s × %s = %s%s" % [LE.fmt_num(rate), LE.fmt_num(duration), LE.fmt_num(rate * duration),
			"" if max_inst <= 0 else ", ограничено %d" % max_inst]})
	for row: Dictionary in ds["rows"]:
		if row["label"] != "Всего за удар (без крита)":
			rows.append({"label": "Урон стака: %s" % row["label"], "text": row["text"], "breakdown": row["breakdown"] +
				"\nМоды с тегами Hit/Melee/Spell/Bow/Throwing к айлментам не применяются (теги айлмента: %s)." % SkillCalc._tag_names(atags)})
	var stack_text: PackedStringArray = ["Сумма по типам × %s = %s" % [LE.fmt_num(more_total), LE.fmt_num(stack_damage)]]
	if eff_more != 0.0:
		stack_text.append("Эффект +%s увеличивает урон: ×%s" % [LE.fmt_pct(eff_more), LE.fmt_num(1.0 + eff_more)])
	if dur_more != 0.0:
		stack_text.append("Длительность +%s растягивает стак и увеличивает его полный урон: ×%s (DPS стака не меняется)" % [LE.fmt_pct(dur_more), LE.fmt_num(1.0 + dur_more)])
	if float(c["more"]) != 1.0:
		stack_text.append("Модификатор урона из умения: ×%s" % LE.fmt_num(c["more"]))
	if eff_pen != 0.0:
		stack_text.append("Эффект +%s у этого айлмента даёт пробивание (%s), а не урон (06d §2.1)" % [LE.fmt_pct(eff_pen), LE.DT_NAME_RU[pen_type]])
	stack_text.append_array(c["eff_lines"])
	stack_text.append("Урон фиксируется при наложении и наносится за всю длительность.")
	stack_text.append("Моды дерева умения и масштабирование от атрибутов применяются к его айлментам так же, как к удару (D?: сборка статов объекта умения в коде игры прослежена не полностью, 06d «Не удалось» п. 2).")
	rows.append({"label": "Полный урон одного стака", "text": LE.fmt_num(stack_damage), "breakdown": "\n".join(stack_text)})
	rows.append({"label": "DPS (без врага)", "text": LE.fmt_num(dps), "breakdown":
		"%s наложений/с × %s урона стака = %s\n%s" % [LE.fmt_num(rate), LE.fmt_num(stack_damage), LE.fmt_num(rate * stack_damage), cap_text]})

	# against the enemy: same per-type mitigation as hits, without crit, armour only via property 118 (06d §3)
	var enemy: Dictionary = build.enemy
	var e: StatStore = Enemy.store(enemy)
	var dr: float = Enemy.level_dr(enemy)
	var armour: float = Enemy.armour(e)
	var armour_share: float = minf(1.0, ctx["store"].query(118).added)
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
		var cond: float = SkillCalc._condition_factor(cond_mods, enemy, atags, i, lines)
		var res: float = Enemy.resistance(e, i).added
		var pen: float = float(ds["pen"][i]) + (eff_pen if i == pen_type else 0.0)
		var res_mult: float = (0.25 if res > 0.75 else 1.0 - res) + pen
		var dt_q: StatQuery = e.query(LE.DAMAGE_TAKEN, (atags & ~0xFF) | LE.DT_TAG[i])
		var dt: float = (1.0 + dt_q.added) * (1.0 + dt_q.increased) * dt_q.more
		var arm: float = 1.0
		if armour != 0.0 and armour_share > 0.0:
			arm = 1.0 - Enemy.armour_mitigation(armour, int(enemy.get("level", 100)), i != 0) * armour_share
		var mult: float = cond * res_mult * dt * (1.0 - dr) * arm
		enemy_dps += dps * (part / stack_damage) * mult
		eb.append("%s: доля %s, сопротивление %s, пробивание %s → ×%s; получаемый урон ×%s; снижение по уровню ×%s%s%s → ×%s" % [
			LE.DT_NAME_RU[i], LE.fmt_pct(part / stack_damage), LE.fmt_pct(res), LE.fmt_pct(pen), LE.fmt_num(res_mult), LE.fmt_num(dt),
			LE.fmt_num(1.0 - dr), "" if arm == 1.0 else "; броня ×%s" % LE.fmt_num(arm),
			"" if cond == 1.0 else "; условия ×%s" % LE.fmt_num(cond), LE.fmt_num(mult)])
		eb.append_array(lines)
	eb.append("Крит, уклонение, блок и разброс к урону айлментов не применяются; броня — только при «Armour Mitigation Applies to DoT».")
	rows.append({"label": "DPS по врагу", "text": LE.fmt_num(enemy_dps), "breakdown": "\n".join(eb)})
	return {"rows": rows, "dps": dps, "enemy_dps": enemy_dps}


## Longer duration raises total stack damage unless damage is dealt at the end / on hit (06d §1.3).
static func _duration_increases_damage(ail: Dictionary) -> bool:
	for flag: String in ["dealsAllDamageAtEnd", "dealsDamageWhenHit", "dealsDamageWhenAffectedHitsOthers", "dealsDamageOnAnguish"]:
		if ail.get(flag, false):
			return false
	return true
