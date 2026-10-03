## Enemy configuration and stat calculations for damage calculations.
class_name Enemy


## Build a StatStore from enemy configuration with ailment effects.
## enemy config: {level, kind, res[], armour, ailments{}, flags{}}
static func store(enemy: Dictionary) -> StatStore:
	var s := StatStore.new()

	# Resistances: res[i]/100 added to RES_SP[i]
	for i in range(7):
		var res_sp = LE.RES_SP[i]
		var res_value: float = enemy.get("res", [0,0,0,0,0,0,0])[i] / 100.0
		s.add(StatMod.make(res_sp, "added", res_value, 0, "Сопротивление врага"))

	# Armour: added to SP 10
	var armour_value: float = enemy.get("armour", 0)
	s.add(StatMod.make(LE.ARMOUR, "added", armour_value, 0, "Броня врага"))

	# Ailments with stacks
	var ailments: Dictionary = enemy.get("ailments", {})
	var enemy_kind: String = enemy.get("kind", "dummy")
	var is_boss: bool = enemy_kind == "boss" or enemy_kind == "miniboss"

	for ailment_id in ailments:
		var stacks: int = int(ailments[ailment_id])
		if stacks <= 0:
			continue

		var ailment_data: Dictionary = GameData.ailment(int(ailment_id))
		if ailment_data.is_empty():
			continue

		var ailment_name: String = ailment_data.get("name", "Unknown")

		# Calculate effective stacks
		var n_eff: int = stacks
		var max_instances: int = int(ailment_data.get("maxInstances", 0))
		if max_instances > 0:
			n_eff = mini(n_eff, max_instances)

		var buff_scaling_type: int = int(ailment_data.get("buffScalingType", 0))
		if buff_scaling_type == 2:
			var max_stacks_buff: int = int(ailment_data.get("maxStacksThatApplyBuffs", 0))
			if max_stacks_buff > 0:
				n_eff = mini(n_eff, max_stacks_buff)

		# Penalty for bosses
		var penalty: float = 0.0
		if is_boss:
			penalty = ailment_data.get("moreBuffEffectAgainstBosses", 0.0)

		# Add buffs from ailment
		var buffs = ailment_data.get("buffs", [])
		for buff: Dictionary in buffs:
			var mod := StatMod.new()
			mod.property = int(buff.get("property", 0))
			mod.special = int(buff.get("specialTag", 0))
			mod.tags = int(buff.get("tags", 0))
			mod.extra = int(buff.get("extraTag", 0))
			mod.added = float(buff.get("added", 0.0))
			mod.increased = float(buff.get("increased", 0.0))
			for m in buff.get("more", []):
				mod.more.append(float(m))
			mod.source = "%s ×%d" % [ailment_name, n_eff]
			s.add(mod.scaled(float(n_eff) * (1.0 + penalty)))

	return s


## Return resistance for damage type i (0..6).
## Returns a StatQuery with added = final resistance value and mods = contributing mods.
## Only considers added values; increased/more are ignored per spec.
static func resistance(store: StatStore, i: int) -> StatQuery:
	var res_group: int = LE.RES_GROUP[i]
	var res_sp: int = LE.RES_SP[i]
	var neg_res_sp: int = LE.NEG_RES_SP[i]

	# Start with base resistance for this type
	var q := store.query_untagged(res_sp)

	# Add ALL_RES contribution
	var all_res_q = store.query_untagged(LE.ALL_RES)

	# Build result with only added values
	var result := StatQuery.new()
	result.added = q.added + all_res_q.added
	result.increased = 0.0
	result.more = 1.0
	result.mods = q.mods + all_res_q.mods

	# Add group-specific resistances
	if res_group == 1:  # Elemental
		var elem_res_q = store.query_untagged(LE.ELEMENTAL_RES)
		result.added += elem_res_q.added
		result.mods += elem_res_q.mods
	elif res_group == 2:  # Phys/Void
		var phys_void_res_q = store.query_untagged(LE.PHYS_VOID_RES)
		result.added += phys_void_res_q.added
		result.mods += phys_void_res_q.mods
	elif res_group == 4:  # Necrotic/Poison
		var necro_poison_res_q = store.query_untagged(LE.NECRO_POISON_RES)
		result.added += necro_poison_res_q.added
		result.mods += necro_poison_res_q.mods

	# Subtract negative resistances
	var neg_res_q = store.query_untagged(neg_res_sp)
	result.added -= neg_res_q.added
	result.mods += neg_res_q.mods

	if res_group == 1:  # Elemental
		var neg_elem_res_q = store.query_untagged(LE.NEG_ELEMENTAL_RES)
		result.added -= neg_elem_res_q.added
		result.mods += neg_elem_res_q.mods

	return result


## Calculate effective armour value.
static func armour(store: StatStore) -> float:
	var armour_q = store.query_untagged(LE.ARMOUR)
	var neg_armour_q = store.query_untagged(LE.NEG_ARMOUR)
	return armour_q.value() - neg_armour_q.added


## Calculate armour mitigation factor.
## Returns damage reduction ratio (0..1 range typical, negative possible).
static func armour_mitigation(x: float, area_level: int, non_phys: bool) -> float:
	if x < 0:
		return -armour_mitigation(-x, area_level, non_phys)

	var L: float = float(area_level) + 5.0

	var term1: float = 0.55 * (0.0015 * x * x) / (0.0015 * x * x + 180.0 * L)
	var term2: float = 0.30 * (1.2 * x) / (0.05 * L * L + 80.0 + 1.2 * x)

	var f: float = term1 + term2

	if non_phys:
		f *= 0.7

	return f


## Calculate level-based damage reduction.
## dummy enemies have no DR; others use GameData; boss/miniboss get bonus.
static func level_dr(enemy: Dictionary) -> float:
	var kind: String = enemy.get("kind", "dummy")

	if kind == "dummy":
		return 0.0

	var level: int = enemy.get("level", 100)
	var dr: float = GameData.damage_reduction(level)

	if kind == "boss" or kind == "miniboss":
		dr = dr + 0.05 * (1.0 - dr)

	return dr


## Check if enemy has a condition for ConditionalDamageProperty.
## Returns multiplier/count for damage scaling; 0 if condition not met.
static func has_condition(enemy: Dictionary, cdp: int) -> float:
	var flags: Dictionary = enemy.get("flags", {})
	var ailments: Dictionary = enemy.get("ailments", {})
	var kind: String = enemy.get("kind", "dummy")

	match cdp:
		0:  # Stunned
			return 1.0 if flags.get("stunned", false) else 0.0

		1:  # LowHealth
			return 1.0 if flags.get("low_health", false) else 0.0

		3:  # FullHealth
			return 1.0 if flags.get("full_health", false) else 0.0

		4:  # Bosses&Rares
			return 1.0 if (kind in ["rare", "boss", "miniboss"]) else 0.0

		5:  # Ignited
			return 1.0 if _get_ailment_stacks(ailments, "Ignite") > 0 else 0.0

		6:  # PerPoisonStack
			return float(mini(_get_ailment_stacks(ailments, "Poison"), 30))

		7:  # PerBleedStack
			return float(mini(_get_ailment_stacks(ailments, "Bleed"), 30))

		8:  # Chilled
			return 1.0 if _get_ailment_stacks(ailments, "Chill") > 0 else 0.0

		9:  # Slowed
			return 1.0 if _get_ailment_stacks(ailments, "Slow") > 0 else 0.0

		10:  # Shocked
			return 1.0 if _get_ailment_stacks(ailments, "Shock") > 0 else 0.0

		13:  # Cursed (any isCurse ailment)
			return 1.0 if _has_curse(ailments) else 0.0

		16:  # Moving
			return 1.0 if flags.get("moving", false) else 0.0

		17:  # Bosses
			return 1.0 if (kind in ["boss", "miniboss"]) else 0.0

		18:  # PerArmourShred
			return float(mini(_get_ailment_stacks(ailments, "ArmourShred"), 14))

		19:  # Bleeding
			return 1.0 if _get_ailment_stacks(ailments, "Bleed") > 0 else 0.0

		20:  # Frozen
			return 1.0 if _get_ailment_stacks(ailments, "Frozen") > 0 else 0.0

		21:  # PerNegAilment (count of different ailments)
			return float(_count_ailments(ailments))

		25:  # Damned
			return 1.0 if _get_ailment_stacks(ailments, "Damned") > 0 else 0.0

		26:  # PerNegAilment<=8
			return float(mini(_count_ailments(ailments), 8))

		32:  # Frozen|Chilled
			return 1.0 if (_get_ailment_stacks(ailments, "Frozen") > 0 or _get_ailment_stacks(ailments, "Chill") > 0) else 0.0

		33:  # Ignited|Shocked
			return 1.0 if (_get_ailment_stacks(ailments, "Ignite") > 0 or _get_ailment_stacks(ailments, "Shock") > 0) else 0.0

		36:  # Electrified
			return 1.0 if _get_ailment_stacks(ailments, "Electrify") > 0 else 0.0

		44:  # Poisoned
			return 1.0 if _get_ailment_stacks(ailments, "Poison") > 0 else 0.0

		46:  # Blinded
			return 1.0 if _get_ailment_stacks(ailments, "Blind") > 0 else 0.0

		47:  # Frostbitten
			return 1.0 if _get_ailment_stacks(ailments, "Frostbite") > 0 else 0.0

		_:
			return 0.0


## Helper: get stacks of ailment by name.
static func _get_ailment_stacks(ailments: Dictionary, ailment_name: String) -> int:
	var target_id = GameData.enum_value("AilmentID", ailment_name)
	if target_id < 0:
		return 0
	return ailments.get(target_id, 0)


## Helper: check if any ailment with isCurse is present.
static func _has_curse(ailments: Dictionary) -> bool:
	for ailment_id in ailments:
		var ailment_data = GameData.ailment(ailment_id)
		if not ailment_data.is_empty() and ailment_data.get("isCurse", false):
			return true
	return false


## Helper: count number of different ailments with stacks > 0.
static func _count_ailments(ailments: Dictionary) -> int:
	var count = 0
	for ailment_id in ailments:
		if ailments[ailment_id] > 0:
			count += 1
	return count
