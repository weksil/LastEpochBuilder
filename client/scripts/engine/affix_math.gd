## Affix value calculation mathematics per §7a §6.
class_name AffixMath


## Map rounding type to scale factor.
static var SCALE: Dictionary = {
	"Hundredth": 100,
	"Integer": 1,
	"Tenth": 10,
	"Thousandth": 1000,
}


## Calculate effective modifier based on item vs standard affix effect modifier.
## Returns 0 if item_aem == standard aem, otherwise (1+item_aem)/(1+std) - 1.
static func effect_modifier(item_aem: float, std: float) -> float:
	if is_equal_approx(item_aem, std):
		return 0.0
	return (1.0 + item_aem) / (1.0 + std) - 1.0


## Calculate rolled value for an affix property.
## lo, hi: min/max values from affix tier
## rounding: "Hundredth"|"Integer"|"Tenth"|"Thousandth" (INCREASED always Hundredth)
## mod_type: "ADDED"|"INCREASED"|"MORE"|"QUOTIENT"
## roll: roll value 0-255
## m: effect modifier (from effect_modifier())
## Returns the rolled and scaled value.
static func roll_value(lo: float, hi: float, rounding: String, mod_type: String, roll: int, m: float) -> float:
	# INCREASED always uses Hundredth scale
	var scale_type: String = "Hundredth" if mod_type == "INCREASED" else rounding
	var s: float = float(SCALE.get(scale_type, 1))

	# Apply modifier
	var lo2: float = lo * (1.0 + m)
	var hi2: float = hi * (1.0 + m)

	# Scale and round
	var a: int = LE.round_half_even(lo2 * s)
	var b: int = LE.round_half_even(hi2 * s)

	# Ensure a <= b
	if a > b:
		var temp: int = a
		a = b
		b = temp

	# Calculate rolled value: min(floor((b - a + 1) * roll / 255 + a), b) / s
	var v: float = float(min(int(floor(float(b - a + 1) * float(roll) / 255.0 + float(a))), b)) / s

	return v
