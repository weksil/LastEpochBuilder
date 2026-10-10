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

	# Apply the modifier and scale: the game computes min·(1+m)·s in float32 (07a, open issue 8); it matters only at .5 boundaries
	var f: float = f32(1.0 + m)
	var a: int = LE.round_half_even(f32(f32(f32(lo) * f) * s))
	var b: int = LE.round_half_even(f32(f32(f32(hi) * f) * s))

	# Descending range (max < min as written; GetValueAfterRounding compares the raw floats, DescendingValueAfterPropertyRounding):
	# roll 0 gives the first number, roll 255 the second: max(ceil((b - a - 1) * roll / 255 + a), b) / s
	if hi < lo:
		return float(max(int(ceil(float(b - a - 1) * float(roll) / 255.0 + float(a))), b)) / s

	# Ascending: min(floor((b - a + 1) * roll / 255 + a), b) / s
	var v: float = float(min(int(floor(float(b - a + 1) * float(roll) / 255.0 + float(a))), b)) / s

	return v


## x rounded to float32 (the game's float arithmetic).
static func f32(x: float) -> float:
	return PackedFloat32Array([x])[0]


## Value on the rounding grid without a roll (GetFixedValueAfterRounding).
static func fixed_value(value: float, rounding: String, mod_type: String) -> float:
	var s: float = float(SCALE.get("Hundredth" if mod_type == "INCREASED" else rounding, 1))
	return float(LE.round_half_even(value * s)) / s


## Unique item mod value (UniqueItemMod.getValue, 07d §2.1): rolls only if canRoll, maxValue > value and roll ≠ 0.
static func unique_value(mod: Dictionary, roll: int) -> float:
	var lo: float = float(mod.get("value", 0.0))
	var hi: float = float(mod.get("maxValue", lo))
	var rounding: String = str(mod.get("rounding", "Hundredth"))
	var mod_type: String = str(mod.get("modType", "ADDED"))
	if int(mod.get("canRoll", 0)) == 0 or hi <= lo or roll == 0:
		return fixed_value(lo, rounding, mod_type)
	return roll_value(lo, hi, rounding, mod_type, roll, 0.0)
