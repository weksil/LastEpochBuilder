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

	# Group: Attributes
	rows.append_array(_compute_attributes(store))

	# Group: Resources
	rows.append_array(_compute_resources(store))

	# Group: Defense
	rows.append_array(_compute_defence(store, level))

	# Group: Other
	rows.append_array(_compute_other(store))

	return rows


## Attributes: Strength, Vitality, Intelligence, Dexterity, Attunement
static func _compute_attributes(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	var attr_ids: Array[int] = [LE.STRENGTH, LE.VITALITY, LE.INTELLIGENCE, LE.DEXTERITY, LE.ATTUNEMENT]
	var attr_names: Array[String] = [LE.t("Strength"), LE.t("Vitality"), LE.t("Intelligence"), LE.t("Dexterity"), LE.t("Attunement")]

	for i in range(attr_ids.size()):
		var attr_id: int = attr_ids[i]
		var attr_name: String = attr_names[i]

		# Sum added from attribute and ALL_ATTRIBUTES (46)
		var properties: Array[int] = [attr_id, LE.ALL_ATTRIBUTES]
		var added_sum: float = store.sum_added_untagged(properties)
		var value: int = LE.round_half_even(added_sum)

		var mods: Array[StatMod] = store.untagged_mods(properties)
		var breakdown: String = _format_breakdown(mods, str(value))
		var converted: String = BuildMods.converted_attribute(store, _attribute_record(i))
		if converted != "":
			# the game shows the converted attribute in place of the original one
			attr_name = LE.t(converted)
			breakdown += "\n" + LE.t("100%% of %s converted to %s") % [attr_names[i], attr_name]

		rows.append({
			"group": LE.t("Attributes"),
			"label": attr_name,
			"value": float(value),
			"text": str(value),
			"breakdown": breakdown
		})

	return rows


## attributes.json record of an attribute index (0 Strength … 4 Attunement), {} if absent.
static func _attribute_record(index: int) -> Dictionary:
	for attr: Dictionary in GameData.attributes:
		if int(attr.get("attribute", -1)) == index:
			return attr
	return {}


## Resources: Health, Mana, Health Regen, Mana Regen
static func _compute_resources(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# Health (7)
	var health_query: StatQuery = store.query_untagged(LE.HEALTH)
	var health_value: int = LE.round_half_even(health_query.value())
	rows.append({
		"group": LE.t("Resources"),
		"label": LE.t("Health"),
		"value": float(health_value),
		"text": str(health_value),
		"breakdown": health_query.breakdown()
	})

	# Mana (8)
	var mana_query: StatQuery = store.query_untagged(LE.MANA)
	var mana_value: int = LE.round_half_even(mana_query.value())
	rows.append({
		"group": LE.t("Resources"),
		"label": LE.t("Mana"),
		"value": float(mana_value),
		"text": str(mana_value),
		"breakdown": mana_query.breakdown()
	})

	# Health Regen (17)
	var health_regen_query: StatQuery = store.query_untagged(LE.HEALTH_REGEN)
	var health_regen_value: float = health_regen_query.value()
	rows.append({
		"group": LE.t("Resources"),
		"label": LE.t("Health regen"),
		"value": health_regen_value,
		"text": LE.fmt_num(health_regen_value),
		"breakdown": health_regen_query.breakdown()
	})

	# Mana Regen (18)
	var mana_regen_query: StatQuery = store.query_untagged(LE.MANA_REGEN)
	var mana_regen_value: float = mana_regen_query.value()
	rows.append({
		"group": LE.t("Resources"),
		"label": LE.t("Mana regen"),
		"value": mana_regen_value,
		"text": LE.fmt_num(mana_regen_value),
		"breakdown": mana_regen_query.breakdown()
	})

	return rows


## Defense: Armour, Dodge, Block, Parry, Endurance, Stun Avoidance, Resistances
static func _compute_defence(store: StatStore, level: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# Armour (10) - armor
	var armour_query: StatQuery = store.query_untagged(LE.ARMOUR)
	var neg_armour_sum: float = store.sum_added_untagged([LE.NEG_ARMOUR])
	var armour_value: float = armour_query.value() - neg_armour_sum
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Armor"),
		"value": armour_value,
		"text": LE.fmt_num(armour_value),
		"breakdown": armour_query.breakdown() + LE.t("\n− (%s) from -armor") % LE.fmt_num(neg_armour_sum)
	})

	# Armour Mitigation - armor physical damage reduction
	var armour_mit: float = Enemy.armour_mitigation(armour_value, level, false)
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Armor physical damage reduction"),
		"value": armour_mit,
		"text": LE.fmt_pct(armour_mit),
		"breakdown": LE.t("Armor: %s\nFormula: 0.55·0.0015x²/(0.0015x² + 180L) + 0.30·1.2x/(0.05L² + 80 + 1.2x), where L = %d") % [LE.fmt_num(armour_value), level + 5]
	})

	# Dodge Rating (11) - dodge rating
	var dodge_rating_query: StatQuery = store.query_untagged(LE.DODGE_RATING)
	var dodge_rating_value: float = dodge_rating_query.value()
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Dodge rating"),
		"value": dodge_rating_value,
		"text": LE.fmt_num(dodge_rating_value),
		"breakdown": dodge_rating_query.breakdown()
	})

	# Dodge Chance - dodge chance
	var dodge_chance: float = _compute_dodge_chance(dodge_rating_value, level)
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Dodge chance"),
		"value": dodge_chance,
		"text": LE.fmt_pct(dodge_chance),
		"breakdown": _explain_dodge_chance(dodge_rating_value, level)
	})

	# Block Chance (29) - block chance
	var block_query: StatQuery = store.query_untagged(LE.BLOCK_CHANCE)
	var block_value: float = block_query.value()
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Block chance"),
		"value": block_value,
		"text": LE.fmt_pct(block_value),
		"breakdown": block_query.breakdown()
	})

	# Block Effectiveness (53) - block effectiveness
	var block_eff_query: StatQuery = store.query_untagged(LE.BLOCK_EFFECTIVENESS)
	var block_eff_value: float = block_eff_query.value()
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Block effectiveness"),
		"value": block_eff_value,
		"text": LE.fmt_num(block_eff_value),
		"breakdown": block_eff_query.breakdown()
	})

	# Block mitigation - share of hit damage removed by a block (character sheet, research/06c §2.3)
	var block_mit: float = block_mitigation(block_eff_value, level)
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Block damage reduction"),
		"value": block_mit,
		"text": LE.fmt_pct(block_mit),
		"breakdown": _explain_block_mitigation(block_eff_value, level)
	})

	# Parry (121) - parry chance
	var parry_query: StatQuery = store.query_untagged(LE.PARRY)
	var parry_value: float = min(0.75, parry_query.value())
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Parry chance"),
		"value": parry_value,
		"text": LE.fmt_pct(parry_value),
		"breakdown": "min(0.75, %s)\n%s" % [LE.fmt_pct(parry_query.value()), parry_query.breakdown()]
	})

	# Endurance (75) - endurance
	var endurance_sum: float = store.sum_added_untagged([LE.ENDURANCE])
	var endurance_value: float = min(0.6, endurance_sum)
	var endurance_mods: Array[StatMod] = store.untagged_mods([LE.ENDURANCE])
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Endurance"),
		"value": endurance_value,
		"text": LE.fmt_pct(endurance_value),
		"breakdown": _format_breakdown(endurance_mods, "min(0.6, %s)" % LE.fmt_pct(endurance_sum))
	})

	# Endurance Threshold (76)
	var endurance_threshold: float = _compute_endurance_threshold(store)
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Endurance threshold"),
		"value": endurance_threshold,
		"text": LE.fmt_num(endurance_threshold),
		"breakdown": _explain_endurance_threshold(store)
	})

	# Stun Avoidance (12) - stun avoidance
	var stun_query: StatQuery = store.query_untagged(LE.STUN_AVOIDANCE)
	var stun_value: float = stun_query.value()
	rows.append({
		"group": LE.t("Defense"),
		"label": LE.t("Stun avoidance"),
		"value": stun_value,
		"text": LE.fmt_num(stun_value),
		"breakdown": stun_query.breakdown()
	})

	# Resistances (7 rows) - resistances
	rows.append_array(_compute_resistances(store))

	# Damage taken multipliers (SP 6): hits and damage over time, per damage type
	rows.append(_damage_taken_row(store, LE.HIT, LE.t("Damage taken from hits")))
	rows.append(_damage_taken_row(store, LE.DOT, LE.t("Damage taken from DoT")))

	# Ward per second (92) and ward decay threshold (119)
	for entry: Array in [[LE.WARD_REGEN, LE.t("Ward per second")], [LE.WARD_DECAY_THRESHOLD, LE.t("Ward decay threshold")]]:
		var q: StatQuery = store.query_untagged(entry[0])
		rows.append({"group": LE.t("Defense"), "label": entry[1], "value": q.value(), "text": LE.fmt_num(q.value()), "breakdown": q.breakdown()})

	return rows


## Other: Movespeed, Ward Retention, Crit Avoidance
static func _compute_other(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	# Movespeed (9) - movement speed
	var movespeed_query: StatQuery = store.query_untagged(LE.MOVESPEED)
	var movespeed_more: float = movespeed_query.more - 1.0
	rows.append({
		"group": LE.t("Other"),
		"label": LE.t("Movement speed"),
		"value": movespeed_more,
		"text": LE.fmt_pct(movespeed_more),
		"breakdown": movespeed_query.breakdown() + LE.t("\nOnly the more component is used: more - 1")
	})

	# Ward Retention (16) - ward retention
	var ward_query: StatQuery = store.query_untagged(LE.WARD_RETENTION)
	var ward_value: float = ward_query.value()
	rows.append({
		"group": LE.t("Other"),
		"label": LE.t("Ward retention"),
		"value": ward_value,
		"text": LE.fmt_pct(ward_value),
		"breakdown": ward_query.breakdown()
	})

	# Thorns (85) - thorns
	var thorns_query: StatQuery = store.query_untagged(LE.THORNS)
	rows.append({
		"group": LE.t("Other"),
		"label": LE.t("Thorns"),
		"value": thorns_query.value(),
		"text": LE.fmt_num(thorns_query.value()),
		"breakdown": thorns_query.breakdown()
	})

	# Crit Avoidance (89) - crit avoidance
	var crit_avoid_query: StatQuery = store.query_untagged(LE.CRIT_AVOIDANCE)
	var crit_avoid_value: float = crit_avoid_query.value()
	rows.append({
		"group": LE.t("Other"),
		"label": LE.t("Crit avoidance"),
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


## Block mitigation (blockMitigation, research/06c §2.3): x = block effectiveness, L = level + 5, x <= 0 => 0
## 0.6·(0.0006x² + 1.2x)/(0.0006x² + 1.2x + 60L) + 0.25·3x/(0.03L² + 40 + 3x)
static func block_mitigation(block_effectiveness: float, level: int) -> float:
	if block_effectiveness <= 0:
		return 0.0
	var L: float = float(level) + 5.0
	var x: float = block_effectiveness
	var q: float = 0.0006 * x * x + 1.2 * x
	return 0.6 * q / (q + 60.0 * L) + 0.25 * 3.0 * x / (0.03 * L * L + 40.0 + 3.0 * x)


static func _explain_block_mitigation(block_effectiveness: float, level: int) -> String:
	if block_effectiveness <= 0:
		return LE.t("Block effectiveness = 0, so the reduction = 0")
	var L: float = float(level) + 5.0
	var x: float = block_effectiveness
	var q: float = 0.0006 * x * x + 1.2 * x
	var term1: float = 0.6 * q / (q + 60.0 * L)
	var term2: float = 0.25 * 3.0 * x / (0.03 * L * L + 40.0 + 3.0 * x)
	return LE.t("L = %d + 5 = %.0f, x = %s\nTerm 1 = 0.6·(0.0006x² + 1.2x)/(0.0006x² + 1.2x + 60L) = %s\nTerm 2 = 0.25·3x/(0.03L² + 40 + 3x) = %s\nTotal = %s") % [
		level, L, LE.fmt_num(x), LE.fmt_pct(term1), LE.fmt_pct(term2), LE.fmt_pct(term1 + term2)
	]


## Explain dodge chance calculation
static func _explain_dodge_chance(dodge_rating: float, level: int) -> String:
	if dodge_rating <= 0:
		return LE.t("Dodge rating = 0, so the chance = 0")

	var L: float = float(level) + 5.0
	var x: float = dodge_rating

	var term1: float = 0.6 * (0.001 * x * x) / (0.001 * x * x + 32.0 * L)
	var term2: float = 0.25 * x / (0.05 * L * L + 80.0 + x)
	var result: float = term1 + term2

	return LE.t("L = %d + 5 = %.0f, x = %s\nTerm 1 = 0.6·0.001x²/(0.001x² + 32L) = %s\nTerm 2 = 0.25x/(0.05L² + 80 + x) = %s\nTotal = %s") % [
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
		lines.append("%s: ×%s" % [LE.t(LE.DT_NAME[i]), LE.fmt_num(m)])
		for mod: StatMod in q.mods:
			if not seen.has(mod):
				seen[mod] = true
	for mod: StatMod in seen:
		lines.append(mod.describe())
	var text: String = "×" + LE.fmt_num(low) if is_equal_approx(low, high) else "×%s … ×%s" % [LE.fmt_num(low), LE.fmt_num(high)]
	return {"group": LE.t("Defense"), "label": label, "value": low, "text": text, "breakdown": "\n".join(lines)}


## Compute resistances (7 rows)
static func _compute_resistances(store: StatStore) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for i in range(7):
		var res_name: String = LE.t(LE.DT_NAME[i])
		var res_query: StatQuery = Enemy.resistance(store, i)
		var res_value: float = res_query.value()

		# Cap at 75%
		var capped_res: float = min(res_value, 0.75)
		var uncapped_text: String = LE.fmt_pct(res_value)

		rows.append({
			"group": LE.t("Defense"),
			"label": LE.t("Resistance %s") % res_name,
			"value": res_value,
			"text": LE.fmt_pct(capped_res) + LE.t(" (uncapped %s)") % uncapped_text,
			"breakdown": res_query.breakdown()
		})

	return rows


## Breakdown: the header line (the formatted value or its formula), then one line per mod.
static func _format_breakdown(mods: Array[StatMod], header: String) -> String:
	var lines: Array[String] = [header]
	for mod in mods:
		lines.append(mod.describe())

	return "\n".join(lines)
