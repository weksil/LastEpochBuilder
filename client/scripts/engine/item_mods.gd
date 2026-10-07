## Item modifier extraction per §5.4.
class_name ItemMods


## Map slot names to display names (English source text, translated with LE.t where shown).
static var SLOT_NAMES: Dictionary = {
	"helmet": "Helmet",
	"body": "Body armor",
	"belt": "Belt",
	"boots": "Boots",
	"gloves": "Gloves",
	"amulet": "Amulet",
	"ring1": "Ring 1",
	"ring2": "Ring 2",
	"relic": "Relic",
	"weapon": "Weapon",
	"offhand": "Off-hand",
	"altar": "Idol altar",
}


## Translated label of an equipment slot or idol cell ("Helmet", "Idol Small Idol (2:3)").
static func slot_label(slot: String, item: Dictionary) -> String:
	if IdolGrid.is_idol_key(slot):
		var cell: Vector2i = IdolGrid.anchor(slot)
		return LE.t("Idol %s (%d:%d)") % [GameData.display_name(GameData.item_base(int(item.get("base", -1)))), cell.x + 1, cell.y + 1]
	return LE.t(str(SLOT_NAMES.get(slot, slot)))


## Key of an affix in an effect_scale dictionary: idol enchantments / weaver affixes "enchant", otherwise "prefix"/"suffix".
static func scale_key(affix: Dictionary) -> String:
	var special: String = str(affix.get("specialAffixType", ""))
	if special == "IdolEnchantment" or special == "IdolWeaver":
		return "enchant"
	return "prefix" if str(affix.get("type", "")) == "PREFIX" else "suffix"


## Extract all modifiers from an equipped item.
## slot: item slot name ("helmet", "body", etc.)
## item: Dictionary with {base: int, sub: int, implicit_rolls: Array[int], affixes: Array[{id, tier, roll}]}
## effect_scale: optional multipliers of the affix effect {"prefix", "suffix", "enchant"} (default 1) — idols in refracted
## altar slots (AltarMods); applied to the affix effect modifier like the base's affixEffectModifier.
## Returns: Array[StatMod] for implicits and affixes. Cached by the arguments and the locale (CalcCache): the array is a
## copy, the StatMods are shared and must not be changed.
static func item_mods(slot: String, item: Dictionary, effect_scale: Dictionary = {}) -> Array[StatMod]:
	var key: PackedByteArray = var_to_bytes([slot, item, effect_scale, TranslationServer.get_locale()])
	var hit: Variant = CalcCache.lookup("item_mods", key)
	if hit == null:
		hit = _item_mods(slot, item, effect_scale)
		CalcCache.put("item_mods", key, hit, 1024)
	return (hit as Array[StatMod]).duplicate()


## items.json globals.omenIdolAffixEffectModifier: the affix effect modifier of omen idol subtypes (affixEffectiveness
## "OmenIdol"), in place of the base's affixEffectModifier (07a §6).
const OMEN_IDOL_AEM: float = 0.0


static func _item_mods(slot: String, item: Dictionary, effect_scale: Dictionary) -> Array[StatMod]:
	var mods: Array[StatMod] = []

	if not item or item.is_empty():
		return mods

	var base_id: int = item.get("base", -1)
	var sub_id: int = item.get("sub", -1)

	if base_id < 0 or sub_id < 0:
		return mods

	var slot_name: String = slot_label(slot, item)

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

		# Get roll value (0-255); an implicit without a stored roll takes the maximum (255)
		var roll: int = int(implicit_rolls[j]) if j < implicit_rolls.size() else 255

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

		mod.source = LE.t("%s: %s (implicit)") % [slot_name, implicit.get("propertyName", "Unknown")]
		mods.append(mod)

	# Unique / set item mods (special PlayerProperty 98 and AbilityProperty 58 mods are reported by BuildMods)
	if item.has("unique"):
		var u: Dictionary = GameData.unique(int(item["unique"]))
		var unique_rolls: Array = item.get("unique_rolls", [])
		for umod: Dictionary in u.get("mods", []):
			var prop_id: int = int(umod.get("property", 0))
			if prop_id == LE.PLAYER_PROPERTY or prop_id == LE.ABILITY_PROPERTY:
				continue
			var roll_id: int = int(umod.get("rollID", 0))
			var uroll: int = int(unique_rolls[roll_id]) if roll_id < unique_rolls.size() else 255
			var uvalue: float = AffixMath.unique_value(umod, uroll)
			var um := StatMod.make(prop_id, str(umod.get("modType", "ADDED")).to_lower(), uvalue, int(umod.get("tags", 0)),
				"%s: %s" % [slot_name, GameData.display_name(u)], int(umod.get("specialTag", 0)), int(umod.get("extraTag", 0)))
			mods.append(um)

	# Process affixes
	var omen: bool = str(sub.get("affixEffectiveness", "")) == "OmenIdol"
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
		# omen idols use the global ItemList.omenIdolAffixEffectModifier instead of the base's value (07a §6)
		var item_aem: float = OMEN_IDOL_AEM if omen else float(base.get("affixEffectModifier", 0.0))
		var std_aem: float = affix.get("standardAffixEffectModifier", 0.0)
		var m: float = AffixMath.effect_modifier(item_aem, std_aem)
		if not effect_scale.is_empty():
			m = (1.0 + m) * float(effect_scale.get(scale_key(affix), 1.0)) - 1.0

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
			mod.source = "%s: %s T%d" % [slot_name, affix_name, tier]
			mods.append(mod)

	return mods
