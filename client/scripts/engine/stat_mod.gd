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


## Create a StatMod with the given parameters.
## kind: "added" | "increased" | "more" | "quotient"
## quotient: more = 1/(1+x) - 1
static func make(property: int, kind: String, value: float, tags: int = 0, source: String = "", special: int = 0, extra: int = 0) -> StatMod:
	var mod = StatMod.new()
	mod.property = property
	mod.tags = tags
	mod.source = source
	mod.special = special
	mod.extra = extra

	match kind:
		"added":
			mod.added = value
		"increased":
			mod.increased = value
		"more":
			mod.more.append(value)
		"quotient":
			# quotient -> more: 1/(1+x) - 1
			mod.more.append(1.0 / (1.0 + value) - 1.0)
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
	copy.added = added * n
	copy.increased = increased * n
	copy.more = more.duplicate()

	for i in range(copy.more.size()):
		copy.more[i] *= n

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
