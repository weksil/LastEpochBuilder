## Item modifier extraction per §5.4.
class_name ItemMods


## Map slot names to Russian display names.
static var SLOT_NAMES_RU: Dictionary = {
	"helmet": "Шлем",
	"body": "Нагрудник",
	"belt": "Пояс",
	"boots": "Сапоги",
	"gloves": "Перчатки",
	"amulet": "Амулет",
	"ring1": "Кольцо 1",
	"ring2": "Кольцо 2",
	"relic": "Реликвия",
	"weapon": "Оружие",
	"offhand": "Вторая рука",
}


## Extract all modifiers from an equipped item.
## slot: item slot name ("helmet", "body", etc.)
## item: Dictionary with {base: int, sub: int, implicit_rolls: Array[int], affixes: Array[{id, tier, roll}]}
## Returns: Array[StatMod] for implicits and affixes.
static func item_mods(slot: String, item: Dictionary) -> Array[StatMod]:
	var mods: Array[StatMod] = []

	if not item or item.is_empty():
		return mods

	var base_id: int = item.get("base", -1)
	var sub_id: int = item.get("sub", -1)

	if base_id < 0 or sub_id < 0:
		return mods

	var slot_ru: String = SLOT_NAMES_RU.get(slot, slot)

	# Get base and sub data
	var base: Dictionary = GameData.item_base(base_id)
	var sub: Dictionary = GameData.item_sub(base_id, sub_id)

	if base.is_empty() or sub.is_empty():
		return mods

	# Process implicits
	var implicits: Array = sub.get("implicits", [])
	var implicit_rolls: Array = item.get("implicit_rolls", [])

	for j in range(implicits.size()):
		var implicit: Dictionary = implicits[j]
		if implicit.is_empty():
			continue

		# Get roll value (0-255), default to 0 if not provided
		var roll: int = implicit_rolls[j] if j < implicit_rolls.size() else 0

		# Calculate rolled value
		var value: float = implicit.get("value", 0.0)
		var max_value: float = implicit.get("maxValue", value)
		var rounding: String = implicit.get("rounding", "Integer")
		var mod_type: String = implicit.get("modType", "ADDED")

		var rolled: float = AffixMath.roll_value(value, max_value, rounding, mod_type, roll, 0.0)

		# Create mod
		var property: int = implicit.get("property", 0)
		var special_tag: int = implicit.get("specialTag", 0)
		var tags: int = implicit.get("tags", 0)
		var extra_tag: int = implicit.get("extraTag", 0)

		var mod: StatMod = StatMod.new()
		mod.property = property
		mod.special = special_tag
		mod.tags = tags
		mod.extra = extra_tag

		# Set mod value based on type
		match mod_type:
			"ADDED":
				mod.added = rolled
			"INCREASED":
				mod.increased = rolled
			"MORE":
				mod.more.append(rolled)
			"QUOTIENT":
				# quotient -> more: 1/(1+x) - 1
				mod.more.append(1.0 / (1.0 + rolled) - 1.0)

		mod.source = "%s: %s (implicit)" % [slot_ru, implicit.get("propertyName", "Unknown")]
		mods.append(mod)

	# Process affixes
	var affixes_list: Array = item.get("affixes", [])
	for affix_entry in affixes_list:
		if not affix_entry is Dictionary:
			continue

		var affix_id: int = affix_entry.get("id", -1)
		var tier: int = affix_entry.get("tier", 1)
		var roll: int = affix_entry.get("roll", 0)

		if affix_id < 0 or tier < 1:
			continue

		# Get affix data
		var affix: Dictionary = GameData.affix(affix_id)
		if affix.is_empty():
			continue

		# Get tier data (tier is 1-indexed, tiers array is 0-indexed)
		var tiers: Array = affix.get("tiers", [])
		if tier - 1 >= tiers.size():
			continue

		var tier_data: Dictionary = tiers[tier - 1]
		if tier_data.is_empty():
			continue

		# Calculate effect modifier
		var item_aem: float = base.get("affixEffectModifier", 0.0)
		var std_aem: float = affix.get("standardAffixEffectModifier", 0.0)
		var m: float = AffixMath.effect_modifier(item_aem, std_aem)

		# Process each property in this affix
		var properties: Array = affix.get("properties", [])
		var rolls_array: Array = tier_data.get("rolls", [])

		for j in range(properties.size()):
			if j >= rolls_array.size():
				break

			var prop: Dictionary = properties[j]
			var roll_range: Array = rolls_array[j]

			if roll_range.size() < 2:
				continue

			var lo: float = float(roll_range[0])
			var hi: float = float(roll_range[1])
			var rounding: String = prop.get("rounding", "Integer")
			var mod_type: String = prop.get("modType", "ADDED")

			# Calculate rolled value
			var rolled: float = AffixMath.roll_value(lo, hi, rounding, mod_type, roll, m)

			# Create mod
			var property: int = prop.get("property", 0)
			var special_tag: int = prop.get("specialTag", 0)
			var tags: int = prop.get("tags", 0)
			var extra_tag: int = prop.get("extraTag", 0)

			var mod: StatMod = StatMod.new()
			mod.property = property
			mod.special = special_tag
			mod.tags = tags
			mod.extra = extra_tag

			# Set mod value based on type
			match mod_type:
				"ADDED":
					mod.added = rolled
				"INCREASED":
					mod.increased = rolled
				"MORE":
					mod.more.append(rolled)
				"QUOTIENT":
					# quotient -> more: 1/(1+x) - 1
					mod.more.append(1.0 / (1.0 + rolled) - 1.0)

			var affix_name: String = affix.get("name", "Unknown")
			mod.source = "%s: %s T%d" % [slot_ru, affix_name, tier]
			mods.append(mod)

	return mods
