## Character statistics calculation engine.
class_name CharacterCalc


## Compute character statistics from a StatStore and build configuration.
## Returns an array of stat rows: {group, label, value, text, breakdown}
static func compute(store: StatStore, build) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# Ensure store is not null
	if store == null:
		return rows

	var level: int = build.level if build and "level" in build else 100

	# Group: Атрибуты (Attributes)
	rows.append_array(_compute_attributes(store))

	# Group: Ресурсы (Resources)
	rows.append_array(_compute_resources(store))

	# Group: Защита (Defence)
	rows.append_array(_compute_defence(store, level))

	# Group: Прочее (Other)
	rows.append_array(_compute_other(store))

	return rows


## Атрибуты: Strength, Vitality, Intelligence, Dexterity, Attunement
static func _compute_attributes(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	var attr_ids: Array[int] = [LE.STRENGTH, LE.VITALITY, LE.INTELLIGENCE, LE.DEXTERITY, LE.ATTUNEMENT]
	var attr_names_ru: Array[String] = ["Сила", "Живучесть", "Интеллект", "Ловкость", "Настройка"]

	for i in range(attr_ids.size()):
		var attr_id: int = attr_ids[i]
		var attr_name: String = attr_names_ru[i]

		# Sum added from attribute and ALL_ATTRIBUTES (46)
		var properties: Array[int] = [attr_id, LE.ALL_ATTRIBUTES]
		var added_sum: float = store.sum_added_untagged(properties)
		var value: int = LE.round_half_even(added_sum)

		var mods: Array[StatMod] = store.untagged_mods(properties)
		var breakdown: String = _format_breakdown(mods, float(value), "")

		rows.append({
			"group": "Атрибуты",
			"label": attr_name,
			"value": float(value),
			"text": str(value),
			"breakdown": breakdown
		})

	return rows


## Ресурсы: Health, Mana, Health Regen, Mana Regen
static func _compute_resources(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# Health (7)
	var health_query: StatQuery = store.query_untagged(LE.HEALTH)
	var health_value: int = LE.round_half_even(health_query.value())
	rows.append({
		"group": "Ресурсы",
		"label": "Здоровье",
		"value": float(health_value),
		"text": str(health_value),
		"breakdown": health_query.breakdown()
	})

	# Mana (8)
	var mana_query: StatQuery = store.query_untagged(LE.MANA)
	var mana_value: int = LE.round_half_even(mana_query.value())
	rows.append({
		"group": "Ресурсы",
		"label": "Мана",
		"value": float(mana_value),
		"text": str(mana_value),
		"breakdown": mana_query.breakdown()
	})

	# Health Regen (17)
	var health_regen_query: StatQuery = store.query_untagged(LE.HEALTH_REGEN)
	var health_regen_value: float = health_regen_query.value()
	rows.append({
		"group": "Ресурсы",
		"label": "Регенерация здоровья",
		"value": health_regen_value,
		"text": LE.fmt_num(health_regen_value),
		"breakdown": health_regen_query.breakdown()
	})

	# Mana Regen (18)
	var mana_regen_query: StatQuery = store.query_untagged(LE.MANA_REGEN)
	var mana_regen_value: float = mana_regen_query.value()
	rows.append({
		"group": "Ресурсы",
		"label": "Регенерация маны",
		"value": mana_regen_value,
		"text": LE.fmt_num(mana_regen_value),
		"breakdown": mana_regen_query.breakdown()
	})

	return rows


## Защита: Armour, Dodge, Block, Parry, Endurance, Stun Avoidance, Resistances
static func _compute_defence(store: StatStore, level: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# Armour (10) - Броня
	var armour_query: StatQuery = store.query_untagged(LE.ARMOUR)
	var neg_armour_sum: float = store.sum_added_untagged([LE.NEG_ARMOUR])
	var armour_value: float = armour_query.value() - neg_armour_sum
	rows.append({
		"group": "Защита",
		"label": "Броня",
		"value": armour_value,
		"text": LE.fmt_num(armour_value),
		"breakdown": armour_query.breakdown() + "\n− (" + LE.fmt_num(neg_armour_sum) + ") из -броня"
	})

	# Armour Mitigation - Снижение физического урона от брони
	var armour_mit: float = Enemy.armour_mitigation(armour_value, level, false)
	rows.append({
		"group": "Защита",
		"label": "Снижение физ. урона от брони",
		"value": armour_mit,
		"text": LE.fmt_pct(armour_mit),
		"breakdown": "Броня: %s\nФормула: 0.55·0.0015x²/(0.0015x² + 180L) + 0.30·1.2x/(0.05L² + 80 + 1.2x), где L = %d" % [LE.fmt_num(armour_value), level + 5]
	})

	# Dodge Rating (11) - Рейтинг уклонения
	var dodge_rating_query: StatQuery = store.query_untagged(LE.DODGE_RATING)
	var dodge_rating_value: float = dodge_rating_query.value()
	rows.append({
		"group": "Защита",
		"label": "Рейтинг уклонения",
		"value": dodge_rating_value,
		"text": LE.fmt_num(dodge_rating_value),
		"breakdown": dodge_rating_query.breakdown()
	})

	# Dodge Chance - Шанс уклонения
	var dodge_chance: float = _compute_dodge_chance(dodge_rating_value, level)
	rows.append({
		"group": "Защита",
		"label": "Шанс уклонения",
		"value": dodge_chance,
		"text": LE.fmt_pct(dodge_chance),
		"breakdown": _explain_dodge_chance(dodge_rating_value, level)
	})

	# Block Chance (29) - Шанс блока
	var block_query: StatQuery = store.query_untagged(LE.BLOCK_CHANCE)
	var block_value: float = block_query.value()
	rows.append({
		"group": "Защита",
		"label": "Шанс блока",
		"value": block_value,
		"text": LE.fmt_pct(block_value),
		"breakdown": block_query.breakdown()
	})

	# Block Effectiveness (53) - Эффективность блока
	var block_eff_query: StatQuery = store.query_untagged(LE.BLOCK_EFFECTIVENESS)
	var block_eff_value: float = block_eff_query.value()
	rows.append({
		"group": "Защита",
		"label": "Эффективность блока",
		"value": block_eff_value,
		"text": LE.fmt_pct(block_eff_value),
		"breakdown": block_eff_query.breakdown()
	})

	# Parry (121) - Шанс парирования
	var parry_query: StatQuery = store.query_untagged(LE.PARRY)
	var parry_value: float = min(0.75, parry_query.value())
	rows.append({
		"group": "Защита",
		"label": "Шанс парирования",
		"value": parry_value,
		"text": LE.fmt_pct(parry_value),
		"breakdown": "min(0.75, %s)\n%s" % [LE.fmt_pct(parry_query.value()), parry_query.breakdown()]
	})

	# Endurance (75) - Выносливость
	var endurance_sum: float = store.sum_added_untagged([LE.ENDURANCE])
	var endurance_value: float = min(0.6, endurance_sum)
	var endurance_mods: Array[StatMod] = store.untagged_mods([LE.ENDURANCE])
	rows.append({
		"group": "Защита",
		"label": "Выносливость",
		"value": endurance_value,
		"text": LE.fmt_pct(endurance_value),
		"breakdown": _format_breakdown(endurance_mods, endurance_value * 100.0, "min(0.6,)")
	})

	# Endurance Threshold (76)
	var endurance_threshold: float = _compute_endurance_threshold(store)
	rows.append({
		"group": "Защита",
		"label": "Порог выносливости",
		"value": endurance_threshold,
		"text": LE.fmt_num(endurance_threshold),
		"breakdown": _explain_endurance_threshold(store)
	})

	# Stun Avoidance (12) - Избежание оглушения
	var stun_query: StatQuery = store.query_untagged(LE.STUN_AVOIDANCE)
	var stun_value: float = stun_query.value()
	rows.append({
		"group": "Защита",
		"label": "Избежание оглушения",
		"value": stun_value,
		"text": LE.fmt_num(stun_value),
		"breakdown": stun_query.breakdown()
	})

	# Resistances (7 rows) - Сопротивления
	rows.append_array(_compute_resistances(store))

	# Damage taken multipliers (SP 6): hits and damage over time, per damage type
	rows.append(_damage_taken_row(store, LE.HIT, "Получаемый урон от ударов"))
	rows.append(_damage_taken_row(store, LE.DOT, "Получаемый урон от DoT"))

	# Ward per second (92) and ward decay threshold (119)
	for entry: Array in [[LE.WARD_REGEN, "Ward в секунду"], [LE.WARD_DECAY_THRESHOLD, "Порог распада ward"]]:
		var q: StatQuery = store.query_untagged(entry[0])
		rows.append({"group": "Защита", "label": entry[1], "value": q.value(), "text": LE.fmt_num(q.value()), "breakdown": q.breakdown()})

	return rows


## Прочее: Movespeed, Ward Retention, Crit Avoidance
static func _compute_other(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# Movespeed (9) - Скорость передвижения
	var movespeed_query: StatQuery = store.query_untagged(LE.MOVESPEED)
	var movespeed_more: float = movespeed_query.more - 1.0
	rows.append({
		"group": "Прочее",
		"label": "Скорость передвижения",
		"value": movespeed_more,
		"text": LE.fmt_pct(movespeed_more),
		"breakdown": movespeed_query.breakdown() + "\nИспользуется только more компонент: more - 1"
	})

	# Ward Retention (16) - Удержание защиты
	var ward_query: StatQuery = store.query_untagged(LE.WARD_RETENTION)
	var ward_value: float = ward_query.value()
	rows.append({
		"group": "Прочее",
		"label": "Удержание защиты",
		"value": ward_value,
		"text": LE.fmt_pct(ward_value),
		"breakdown": ward_query.breakdown()
	})

	# Thorns (85) - Отражение урона атакующим
	var thorns_query: StatQuery = store.query_untagged(LE.THORNS)
	rows.append({
		"group": "Прочее",
		"label": "Отражение урона атакующим",
		"value": thorns_query.value(),
		"text": LE.fmt_num(thorns_query.value()),
		"breakdown": thorns_query.breakdown()
	})

	# Crit Avoidance (89) - Избежание крита
	var crit_avoid_query: StatQuery = store.query_untagged(LE.CRIT_AVOIDANCE)
	var crit_avoid_value: float = crit_avoid_query.value()
	rows.append({
		"group": "Прочее",
		"label": "Избежание крита",
		"value": crit_avoid_value,
		"text": LE.fmt_pct(crit_avoid_value),
		"breakdown": crit_avoid_query.breakdown()
	})

	return rows


## Compute dodge chance: 0.6·0.001x²/(0.001x² + 32L) + 0.25x/(0.05L² + 80 + x)
## L = level + 5, x <= 0 => 0
static func _compute_dodge_chance(dodge_rating: float, level: int) -> float:
	if dodge_rating <= 0:
		return 0.0

	var L: float = float(level) + 5.0
	var x: float = dodge_rating

	var term1: float = 0.6 * (0.001 * x * x) / (0.001 * x * x + 32.0 * L)
	var term2: float = 0.25 * x / (0.05 * L * L + 80.0 + x)

	return term1 + term2


## Explain dodge chance calculation
static func _explain_dodge_chance(dodge_rating: float, level: int) -> String:
	if dodge_rating <= 0:
		return "Рейтинг уклонения = 0, поэтому шанс = 0"

	var L: float = float(level) + 5.0
	var x: float = dodge_rating

	var term1: float = 0.6 * (0.001 * x * x) / (0.001 * x * x + 32.0 * L)
	var term2: float = 0.25 * x / (0.05 * L * L + 80.0 + x)
	var result: float = term1 + term2

	return "L = %d + 5 = %.0f, x = %s\nТерм1 = 0.6·0.001x²/(0.001x² + 32L) = %s\nТерм2 = 0.25x/(0.05L² + 80 + x) = %s\nИтого = %s" % [
		level,
		L,
		LE.fmt_num(x),
		LE.fmt_pct(term1),
		LE.fmt_pct(term2),
		LE.fmt_pct(result)
	]


## Compute endurance threshold: I76·((maxMore96 + A96)·maxHealth + A76)·M76
static func _compute_endurance_threshold(store: StatStore) -> float:
	var I76_query: StatQuery = store.query_untagged(LE.ENDURANCE_THRESHOLD)
	var I76: float = 1.0 + I76_query.increased

	var query96: StatQuery = store.query_untagged(LE.MAX_HEALTH_AS_ET)
	var A96: float = query96.added

	var health_query: StatQuery = store.query_untagged(LE.HEALTH)
	var max_health: float = float(LE.round_half_even(health_query.value()))

	var query76: StatQuery = store.query_untagged(LE.ENDURANCE_THRESHOLD)
	var A76: float = query76.added
	var M76: float = query76.more

	# Find largest individual more value in SP 96
	var max_more96_val: float = 0.0
	for mod in query96.mods:
		for m_val in mod.more:
			max_more96_val = max(max_more96_val, m_val)

	var threshold: float = I76 * ((max_more96_val + A96) * max_health + A76) * M76
	return threshold


## Explain endurance threshold calculation
static func _explain_endurance_threshold(store: StatStore) -> String:
	var query76: StatQuery = store.query_untagged(LE.ENDURANCE_THRESHOLD)
	var I76: float = 1.0 + query76.increased
	var M76: float = query76.more
	var A76: float = query76.added

	var query96: StatQuery = store.query_untagged(LE.MAX_HEALTH_AS_ET)
	var A96: float = query96.added
	var max_more96_val: float = 0.0
	for mod in query96.mods:
		for m_val in mod.more:
			max_more96_val = max(max_more96_val, m_val)

	var health_query: StatQuery = store.query_untagged(LE.HEALTH)
	var max_health: float = float(LE.round_half_even(health_query.value()))

	var threshold: float = I76 * ((max_more96_val + A96) * max_health + A76) * M76

	return "I76·((maxMore96 + A96)·maxHealth + A76)·M76\nI76 = %s, maxMore96 = %s, A96 = %s, maxHealth = %s, A76 = %s, M76 = %s\n= %s" % [
		LE.fmt_num(I76),
		LE.fmt_num(max_more96_val),
		LE.fmt_num(A96),
		LE.fmt_num(max_health),
		LE.fmt_num(A76),
		LE.fmt_num(M76),
		LE.fmt_num(threshold)
	]


## Damage taken multiplier (1 + added)·(1 + increased)·Πmore for a hit or DoT, by damage type.
static func _damage_taken_row(store: StatStore, kind_tag: int, label: String) -> Dictionary:
	var lines: PackedStringArray = []
	var low: float = INF
	var high: float = -INF
	var seen: Dictionary = {}
	for i in range(7):
		var q: StatQuery = store.query(LE.DAMAGE_TAKEN, kind_tag | LE.DT_TAG[i])
		var m: float = (1.0 + q.added) * (1.0 + q.increased) * q.more
		low = minf(low, m)
		high = maxf(high, m)
		lines.append("%s: ×%s" % [LE.DT_NAME_RU[i], LE.fmt_num(m)])
		for mod: StatMod in q.mods:
			if not seen.has(mod):
				seen[mod] = true
	for mod: StatMod in seen:
		lines.append(mod.describe())
	var text: String = "×" + LE.fmt_num(low) if is_equal_approx(low, high) else "×%s … ×%s" % [LE.fmt_num(low), LE.fmt_num(high)]
	return {"group": "Защита", "label": label, "value": low, "text": text, "breakdown": "
".join(lines)}


## Compute resistances (7 rows)
static func _compute_resistances(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for i in range(7):
		var res_name: String = LE.DT_NAME_RU[i]
		var res_query: StatQuery = Enemy.resistance(store, i)
		var res_value: float = res_query.value()

		# Cap at 75%
		var capped_res: float = min(res_value, 0.75)
		var uncapped_text: String = LE.fmt_pct(res_value)

		rows.append({
			"group": "Защита",
			"label": "Сопротивление " + res_name,
			"value": res_value,
			"text": LE.fmt_pct(capped_res) + " (без капа " + uncapped_text + ")",
			"breakdown": res_query.breakdown()
		})

	return rows


## Format breakdown with mods
static func _format_breakdown(mods: Array[StatMod], percent_value: float, prefix: String) -> String:
	var lines: Array[String] = []

	if prefix != "":
		lines.append(prefix + " " + LE.fmt_pct(percent_value))
	else:
		lines.append(LE.fmt_pct(percent_value))

	for mod in mods:
		lines.append(mod.describe())

	return "\n".join(lines)
