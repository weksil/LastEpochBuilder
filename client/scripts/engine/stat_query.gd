## Result of a stat query: aggregated values and the mods that contributed.
class_name StatQuery extends RefCounted


var added: float = 0.0  # Sum of all added values
var increased: float = 0.0  # Sum of all increased percentages (as 0-1 decimals)
var more: float = 1.0  # Product of (1 + each more), starts at 1
var mods: Array[StatMod] = []  # The mods that matched


## Calculate the final value: added·(1 + increased)·more
func value() -> float:
	return added * (1.0 + increased) * more


## Return a multi-line breakdown:
## Line 1: formula "(Σ added) × (1 + Σ inc) × Π more = A × B × C = V"
## Lines 2+: each mod's describe()
func breakdown() -> String:
	var lines: Array[String] = []

	# Calculate components
	var added_str = LE.fmt_num(added)
	var inc_factor = 1.0 + increased
	var inc_str = LE.fmt_num(inc_factor)
	var more_str = LE.fmt_num(more)
	var final = value()
	var final_str = LE.fmt_num(final)

	# First line: formula
	var formula = "(%s) × (1 + %s%%) × %s = %s × %s × %s = %s" % [
		added_str,
		LE.fmt_num(increased * 100.0),
		more_str,
		added_str,
		inc_str,
		more_str,
		final_str
	]
	lines.append(formula)

	# Each mod's description
	for mod in mods:
		lines.append(mod.describe())

	return "\n".join(lines)
