## Enemy configuration and stat calculations for damage calculations.
class_name Enemy


## Build a StatStore from enemy configuration with ailment effects.
## enemy config: {level, kind, res[], armour, corruption, ailments{}, flags{}}
static func store(enemy: Dictionary) -> StatStore:
	var s := StatStore.new()

	# Resistances: res[i]/100 added to RES_SP[i]
	for i in range(7):
		var res_sp = LE.RES_SP[i]
		var res_value: float = enemy.get("res", [0,0,0,0,0,0,0])[i] / 100.0
		s.add(StatMod.make(res_sp, "added", res_value, 0, LE.t("Enemy resistance")))

	# Armour: added to SP 10
	var armour_value: float = enemy.get("armour", 0)
	s.add(StatMod.make(LE.ARMOUR, "added", armour_value, 0, LE.t("Enemy armor")))

	# Ailments with stacks
	var ailments: Dictionary = enemy.get("ailments", {})
	var enemy_kind: String = enemy.get("kind", "dummy")
	var is_boss: bool = enemy_kind == "boss" or enemy_kind == "miniboss"

	for ailment_id in ailments:
		var stacks: float = float(ailments[ailment_id])
		if stacks <= 0.0:
			continue

		var ailment_data: Dictionary = GameData.ailment(int(ailment_id))
		if ailment_data.is_empty():
			continue

		var ailment_name: String = ailment_data.get("name", "Unknown")

		# Calculate effective stacks
		var n_eff: float = stacks
		var max_instances: int = int(ailment_data.get("maxInstances", 0))
		if max_instances > 0:
			n_eff = minf(n_eff, float(max_instances))

		var buff_scaling_type: int = int(ailment_data.get("buffScalingType", 0))
		if buff_scaling_type == 2:
			var max_stacks_buff: int = int(ailment_data.get("maxStacksThatApplyBuffs", 0))
			if max_stacks_buff > 0:
				n_eff = minf(n_eff, float(max_stacks_buff))

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
			mod.source = "%s ×%s" % [ailment_name, LE.fmt_num(n_eff)]
			s.add(mod.scaled(n_eff * (1.0 + penalty)))

	return s


## Return resistance for damage type i (0..6).
## Returns a StatQuery with added = final resistance value and mods = contributing mods.
## Only considers added values; increased/more are ignored per spec.
static func resistance(stat_store: StatStore, i: int) -> StatQuery:
	var res_group: int = LE.RES_GROUP[i]
	var res_sp: int = LE.RES_SP[i]
	var neg_res_sp: int = LE.NEG_RES_SP[i]

	# Start with base resistance for this type
	var q := stat_store.query_untagged(res_sp)

	# Add ALL_RES contribution
	var all_res_q = stat_store.query_untagged(LE.ALL_RES)

	# Build result with only added values
	var result := StatQuery.new()
	result.added = q.added + all_res_q.added
	result.increased = 0.0
	result.more = 1.0
	result.mods = q.mods + all_res_q.mods

	# Add group-specific resistances
	if res_group == 1:  # Elemental
		var elem_res_q = stat_store.query_untagged(LE.ELEMENTAL_RES)
		result.added += elem_res_q.added
		result.mods += elem_res_q.mods
	elif res_group == 2:  # Phys/Void
		var phys_void_res_q = stat_store.query_untagged(LE.PHYS_VOID_RES)
		result.added += phys_void_res_q.added
		result.mods += phys_void_res_q.mods
	elif res_group == 4:  # Necrotic/Poison
		var necro_poison_res_q = stat_store.query_untagged(LE.NECRO_POISON_RES)
		result.added += necro_poison_res_q.added
		result.mods += necro_poison_res_q.mods

	# Subtract negative resistances
	var neg_res_q = stat_store.query_untagged(neg_res_sp)
	result.added -= neg_res_q.added
	result.mods += neg_res_q.mods

	if res_group == 1:  # Elemental
		var neg_elem_res_q = stat_store.query_untagged(LE.NEG_ELEMENTAL_RES)
		result.added -= neg_elem_res_q.added
		result.mods += neg_elem_res_q.mods

	return result


## Calculate effective armour value.
static func armour(stat_store: StatStore) -> float:
	var armour_q = stat_store.query_untagged(LE.ARMOUR)
	var neg_armour_q = stat_store.query_untagged(LE.NEG_ARMOUR)
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


const KIND_NAMES: Dictionary = {"dummy": "training dummy", "normal": "normal", "magic": "magic", "rare": "rare",
	"miniboss": "miniboss", "boss": "boss"}


## Short description of the target for summaries: "boss lvl 100", "boss lvl 100, corruption 300", "training dummy".
static func describe(enemy: Dictionary) -> String:
	var kind: String = str(enemy.get("kind", "dummy"))
	var kind_name: String = LE.t(str(KIND_NAMES.get(kind, kind)))
	var text: String = kind_name if kind == "dummy" else LE.t("%s lvl %d") % [kind_name, int(enemy.get("level", 100))]
	var corruption: int = int(enemy.get("corruption", 0))
	if corruption > 0:
		text = LE.t("%s, corruption %d") % [text, corruption]
	return text


## Monster power from corruption (EchoWeb.GetMonsterPowerMultiplierFromCorruption, research/06c §7):
## f(c) = 0.6c up to 100, 0.002·c^1.52 + 1.055c − 47.692955 above.
static func corruption_power(corruption: int) -> float:
	var c: float = float(maxi(corruption, 0))
	if c <= 100.0:
		return 0.6 * c
	return 0.002 * pow(c, 1.52) + 1.055 * c - 47.692955


## "Monster Power From Corruption" mod (research/07a §4.1): Health and Damage(Hit) MORE 0.01·f(c),
## Damage(DoT) MORE 0.005·f(c). Returns {health, hit, dot} as "more" fractions (0.6 = 60% more).
## It does not change the damage the player deals.
static func corruption_more(enemy: Dictionary) -> Dictionary:
	var f: float = corruption_power(int(enemy.get("corruption", 0)))
	return {"health": 0.01 * f, "hit": 0.01 * f, "dot": 0.005 * f}


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
	var kind: String = enemy.get("kind", "dummy")

	match cdp:
		0:  # Stunned
			return 1.0 if flags.get("stunned", false) else 0.0

		1:  # LowHealth
			return 1.0 if flags.get("low_health", false) else 0.0

		2:  # HighHealth: >= 65% (Stats.highHealthPercent); full health (>= 99%) is high too (research/06a)
			return 1.0 if flags.get("high_health", false) or flags.get("full_health", false) else 0.0

		3:  # FullHealth
			return 1.0 if flags.get("full_health", false) else 0.0

		4:  # Bosses&Rares
			return 1.0 if (kind in ["rare", "boss", "miniboss"]) else 0.0

		5:  # Ignited
			return presence(enemy, "Ignite")

		6:  # PerPoisonStack
			return minf(stacks_of(enemy, "Poison"), 30.0)

		7:  # PerBleedStack
			return minf(stacks_of(enemy, "Bleed"), 30.0)

		8:  # Chilled
			return presence(enemy, "Chill")

		9:  # Slowed
			return presence(enemy, "Slow")

		10:  # Shocked
			return presence(enemy, "Shock")

		13:  # Cursed (any isCurse ailment)
			return _curse_presence(enemy)

		16:  # Moving
			return 1.0 if flags.get("moving", false) else 0.0

		17:  # Bosses
			return 1.0 if (kind in ["boss", "miniboss"]) else 0.0

		18:  # PerArmourShred
			return minf(stacks_of(enemy, "ArmourShred"), 14.0)

		19:  # Bleeding
			return presence(enemy, "Bleed")

		20:  # Frozen (a state, not an AilmentID: enemy flag)
			return 1.0 if flags.get("frozen", false) else 0.0

		21:  # PerNegAilment (count of different ailments)
			return _ailment_count(enemy)

		25:  # Damned
			return presence(enemy, "Damned")

		26:  # PerNegAilment<=8
			return minf(_ailment_count(enemy), 8.0)

		32:  # Frozen|Chilled
			return 1.0 if flags.get("frozen", false) else presence(enemy, "Chill")

		33:  # Ignited|Shocked
			return 1.0 - (1.0 - presence(enemy, "Ignite")) * (1.0 - presence(enemy, "Shock"))

		36:  # Electrified
			return presence(enemy, "Electrify")

		44:  # Poisoned
			return presence(enemy, "Poison")

		46:  # Blinded
			return presence(enemy, "Blind")

		47:  # Frostbitten
			return presence(enemy, "Frostbite")

		_:
			return 0.0


## Stacks of an ailment by name (fractional for the automatic averages, EnemyAilments).
static func stacks_of(enemy: Dictionary, ailment_name: String) -> float:
	var id: int = GameData.enum_value("AilmentID", ailment_name)
	return float(enemy.get("ailments", {}).get(id, 0.0)) if id >= 0 else 0.0


## Share of the time the enemy has the ailment: the uptime of an automatic value (EnemyAilments.effective), else 1 when
## it has stacks.
static func presence_id(enemy: Dictionary, id: int) -> float:
	var uptime: Dictionary = enemy.get("uptime", {})
	if uptime.has(id):
		return float(uptime[id])
	return 1.0 if float(enemy.get("ailments", {}).get(id, 0.0)) > 0.0 else 0.0


static func presence(enemy: Dictionary, ailment_name: String) -> float:
	var id: int = GameData.enum_value("AilmentID", ailment_name)
	return presence_id(enemy, id) if id >= 0 else 0.0


## Share of the time the enemy is cursed: the largest presence of an isCurse ailment.
static func _curse_presence(enemy: Dictionary) -> float:
	var best: float = 0.0
	for id: Variant in enemy.get("ailments", {}):
		if bool(GameData.ailment(int(id)).get("isCurse", false)):
			best = maxf(best, presence_id(enemy, int(id)))
	return best


## Average number of different ailments on the enemy: the sum of their presences.
static func _ailment_count(enemy: Dictionary) -> float:
	var n: float = 0.0
	for id: Variant in enemy.get("ailments", {}):
		n += presence_id(enemy, int(id))
	return n
