## Constants and utility functions for the damage calculation engine.
class_name LE


# Damage type tags (AT - bitwise masks)
const PHYSICAL: int = 1
const LIGHTNING: int = 2
const COLD: int = 4
const FIRE: int = 8
const VOID: int = 16
const NECROTIC: int = 32
const POISON: int = 64
const ELEMENTAL: int = 128
const SPELL: int = 256
const MELEE: int = 512
const THROWING: int = 1024
const BOW: int = 2048
const DOT: int = 4096
const MINION: int = 8192
const TOTEM: int = 16384
const PET_RESISTED: int = 32768
const POTION: int = 65536
const BUFF: int = 131072
const CHANNELLING: int = 262144
const TRANSFORM: int = 524288
const LOW_LIFE: int = 1048576
const HIGH_LIFE: int = 2097152
const FULL_LIFE: int = 4194304
const HIT: int = 8388608
const CURSE: int = 16777216
const AILMENT: int = 33554432

const ELEMENTS: int = LIGHTNING | COLD | FIRE  # 14


# Stat properties (SP - ids)
const DAMAGE: int = 0
const AILMENT_CHANCE: int = 1
const ATTACK_SPEED: int = 2
const CAST_SPEED: int = 3
const CRIT_CHANCE: int = 4
const CRIT_MULTI: int = 5
const DAMAGE_TAKEN: int = 6
const HEALTH: int = 7
const MANA: int = 8
const MOVESPEED: int = 9
const ARMOUR: int = 10
const DODGE_RATING: int = 11
const STUN_AVOIDANCE: int = 12
const FIRE_RES: int = 13
const COLD_RES: int = 14
const LIGHTNING_RES: int = 15
const WARD_RETENTION: int = 16
const HEALTH_REGEN: int = 17
const MANA_REGEN: int = 18
const STRENGTH: int = 19
const VITALITY: int = 20
const INTELLIGENCE: int = 21
const DEXTERITY: int = 22
const ATTUNEMENT: int = 23
const VOID_RES: int = 26
const NECROTIC_RES: int = 27
const POISON_RES: int = 28
const BLOCK_CHANCE: int = 29
const ALL_RES: int = 30
const ADAPTIVE_SPELL_DAMAGE: int = 41
const ALL_ATTRIBUTES: int = 46
const ELEMENTAL_RES: int = 52
const BLOCK_EFFECTIVENESS: int = 53
const ABILITY_PROPERTY: int = 58
const PENETRATION: int = 59
const GLANCING: int = 62
const PHYSICAL_RES: int = 64
const MANA_COST: int = 66
const MANA_EFFICIENCY: int = 69
const CDR: int = 70
const NEG_PHYSICAL_RES: int = 72
const ENDURANCE: int = 75
const ENDURANCE_THRESHOLD: int = 76
const NEG_ARMOUR: int = 77
const NEG_FIRE_RES: int = 78
const NEG_COLD_RES: int = 79
const NEG_LIGHTNING_RES: int = 80
const NEG_VOID_RES: int = 81
const NEG_NECROTIC_RES: int = 82
const NEG_POISON_RES: int = 83
const NEG_ELEMENTAL_RES: int = 84
const LEVEL_OF_SKILLS: int = 88
const CRIT_AVOIDANCE: int = 89
const WARD_REGEN: int = 92
const MAX_HEALTH_AS_ET: int = 96
const PLAYER_PROPERTY: int = 98
const PHYS_VOID_RES: int = 106
const NECRO_POISON_RES: int = 107
const DAMAGE_TAKEN_BUFF: int = 108
const CHANCE_TO_BE_CRIT: int = 112
const REDUCED_CRIT_BONUS_TAKEN: int = 114
const DAMAGE_PER_AILMENT_STACK: int = 115
const CONDITIONAL_DAMAGE: int = 117
const PARRY: int = 121
const CONDITIONAL_PEN: int = 131
const CONDITIONAL_CRIT_CHANCE: int = 132
const CONDITIONAL_CRIT_MULTI: int = 133


# Damage type data
# Order: Physical, Fire, Cold, Lightning, Necrotic, Void, Poison
const DT_TAG: Array[int] = [PHYSICAL, FIRE, COLD, LIGHTNING, NECROTIC, VOID, POISON]
const DT_NAME_RU: Array[String] = ["Физический", "Огонь", "Холод", "Молния", "Некротика", "Пустота", "Яд"]
const RES_SP: Array[int] = [PHYSICAL_RES, FIRE_RES, COLD_RES, LIGHTNING_RES, NECROTIC_RES, VOID_RES, POISON_RES]
const NEG_RES_SP: Array[int] = [NEG_PHYSICAL_RES, NEG_FIRE_RES, NEG_COLD_RES, NEG_LIGHTNING_RES, NEG_NECROTIC_RES, NEG_VOID_RES, NEG_POISON_RES]
const RES_GROUP: Array[int] = [2, 1, 1, 1, 4, 2, 4]  # 1 elemental, 2 Phys/Void, 4 Necrotic/Poison

# Tag names for parsing
const TAG_NAMES: Array[String] = [
	"Physical", "Lightning", "Cold", "Fire", "Void", "Necrotic", "Poison", "Elemental",
	"Spell", "Melee", "Throwing", "Bow", "DoT", "Minion", "Totem", "PetResisted",
	"Potion", "Buff", "Channelling", "Transform", "LowLife", "HighLife", "FullLife",
	"Hit", "Curse", "Ailment"
]


## Parse a tag string like "Fire|Spell" or "Fire | Spell" into a bitwise mask.
static func tag_mask(s: String) -> int:
	if s == "None" or s == "":
		return 0

	var mask: int = 0
	var tags = s.split("|")

	for tag in tags:
		var trimmed = tag.strip_edges()
		if trimmed == "":
			continue

		# Find tag index
		var idx = TAG_NAMES.find(trimmed)
		if idx >= 0:
			# Calculate bit position based on tag order
			match idx:
				0: mask |= PHYSICAL
				1: mask |= LIGHTNING
				2: mask |= COLD
				3: mask |= FIRE
				4: mask |= VOID
				5: mask |= NECROTIC
				6: mask |= POISON
				7: mask |= ELEMENTAL
				8: mask |= SPELL
				9: mask |= MELEE
				10: mask |= THROWING
				11: mask |= BOW
				12: mask |= DOT
				13: mask |= MINION
				14: mask |= TOTEM
				15: mask |= PET_RESISTED
				16: mask |= POTION
				17: mask |= BUFF
				18: mask |= CHANNELLING
				19: mask |= TRANSFORM
				20: mask |= LOW_LIFE
				21: mask |= HIGH_LIFE
				22: mask |= FULL_LIFE
				23: mask |= HIT
				24: mask |= CURSE
				25: mask |= AILMENT

	return mask


## Check if mod tags match the check tags (06a §3).
## Returns true if (mod & check) == mod OR (mod & ELEMENTAL and check & ELEMENTS and ((check | ELEMENTAL) & mod) == mod).
static func tags_match(mod_tags: int, check: int) -> bool:
	if (mod_tags & check) == mod_tags:
		return true

	if (mod_tags & ELEMENTAL) != 0 and (check & ELEMENTS) != 0:
		if ((check | ELEMENTAL) & mod_tags) == mod_tags:
			return true

	return false


## Banker's rounding (round half to even).
static func round_half_even(x: float) -> int:
	var lower = floor(x)
	var frac = x - lower

	if frac < 0.5:
		return int(lower)
	elif frac > 0.5:
		return int(lower) + 1
	else:
		# Exactly 0.5: round to nearest even
		if int(lower) % 2 == 0:
			return int(lower)
		else:
			return int(lower) + 1


## Format a float as percentage (0.125 -> "12.5%").
static func fmt_pct(x: float) -> String:
	return fmt_num(x * 100.0) + "%"


## Format a float: up to 2 decimals for |x| >= 10, up to 4 below that; no trailing zeros.
static func fmt_num(x: float) -> String:
	var decimals: int = 2 if absf(x) >= 10.0 else 4
	var formatted: String = ("%." + str(decimals) + "f") % x
	if formatted.contains("."):
		formatted = formatted.rstrip("0").rstrip(".")
	if formatted == "-0":
		formatted = "0"
	return formatted
