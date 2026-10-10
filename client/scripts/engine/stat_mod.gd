## A single modifier to a stat property.
class_name StatMod extends RefCounted


var property: int  # Stat property ID
var special: int = 0  # Special ID (e.g. ailment ID), 0 = unspecialized
var tags: int = 0  # Bitwise tag mask
var extra: int = 0  # Extra constraint (e.g. ability ID)
var added: float = 0.0  # Added value
var increased: float = 0.0  # Increased percentage (as 0-1 decimal)
var more: Array[float] = []  # Array of multiplicative modifiers
var source: String = ""  # Human-readable source (Russian)
var on_curse_hit: bool = false  # Ailment chance that applies only when the cursed enemy is hit (curse tree nodes)
var ailment_only: int = 0  # Damage more of one ailment instance (ActiveAilment.moreDamage, AilmentID): not part of hit or skill-wide damage
var chance_scaled: int = 0  # With ailment_only: the more value is multiplied by the AilmentChance stat of this AilmentID (0 = fixed value)
var holder_only: bool = false  # Damage more of a DamageConditionalEffect on the skill's DamageStatsHolder: hits and the holder's own damage, never the ailments it applies (AilmentCalc skips it)


## Stats.QuotientStat / Stats.StatOfType(QUOTIENT): more = 1/(1+x) - 1, and 0 when x is exactly -1
## (Stats.c Stats_QuotientStat: `if (param_3 == -1.0) { fVar2 = 0.0; } else { fVar2 = 1.0 / (param_3 + 1.0) - 1.0; }`).
static func quotient_more(x: float) -> float:
	if x == -1.0:
		return 0.0
	return 1.0 / (x + 1.0) - 1.0


## Create a StatMod with the given parameters.
## kind: "added" | "increased" | "more" | "quotient"
## quotient: more = 1/(1+x) - 1 (quotient_more)
static func make(prop: int, kind: String, value: float, tag_mask: int = 0, src: String = "", special_id: int = 0, extra_id: int = 0) -> StatMod:
	var mod = StatMod.new()
	mod.property = prop
	mod.tags = tag_mask
	mod.source = src
	mod.special = special_id
	mod.extra = extra_id

	match kind:
		"added":
			mod.added = value
		"increased":
			mod.increased = value
		"more":
			mod.more.append(value)
		"quotient":
			# quotient -> more: 1/(1+x) - 1, no floor (x < -1 gives the negative value the game gives)
			mod.more.append(quotient_more(value))
		_:
			push_error("Unknown mod kind: " + kind)

	return mod


## Return a scaled copy of this mod (added, increased, and each more multiplied by n).
func scaled(n: float) -> StatMod:
	var copy = StatMod.new()
	copy.property = property
	copy.special = special
	copy.tags = tags
	copy.extra = extra
	copy.source = source
	copy.on_curse_hit = on_curse_hit
	copy.ailment_only = ailment_only
	copy.chance_scaled = chance_scaled
	copy.holder_only = holder_only
	copy.added = added * n
	copy.increased = increased * n
	copy.more = more.duplicate()

	# Stats.Stat.multiplyValues: every more value × n with no clamp, the factor (1 + m·n) may go negative
	for i in range(copy.more.size()):
		copy.more[i] = copy.more[i] * n

	return copy


## Return a human-readable description of this mod.
## Example: "+12 (Passive «Arcanist» ×3)" or "+30% inc (Helmet: Added Health T5)" or "×1.15 more (source)".
func describe() -> String:
	var result = ""

	if added != 0.0:
		result = LE.fmt_num(added)
		if added > 0:
			result = "+" + result
		result += " (" + source + ")"
		return result

	if increased != 0.0:
		result = LE.fmt_pct(increased)
		if increased > 0:
			result = "+" + result
		result += " inc (" + source + ")"
		return result

	if more.size() > 0:
		var prod: float = 1.0
		for m in more:
			prod *= (1.0 + m)
		result = "×" + LE.fmt_num(prod) + " more (" + source + ")"
		return result

	return "0 (" + source + ")"
