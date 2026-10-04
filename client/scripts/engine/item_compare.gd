class_name ItemCompare

## Path-of-Building-style "equipping this item will give you" stat diff, plus item helpers shared by the item views
## (docs/UI.md "Items"). Static functions only.

const ONE_HANDED_TYPES: Array[String] = [
	"ONE_HANDED_AXE", "ONE_HANDED_DAGGER", "ONE_HANDED_MACES", "ONE_HANDED_SCEPTRE", "ONE_HANDED_SWORD", "WAND", "ONE_HANDED_FIST"]
const SLOT_TYPES: Dictionary = {
	"helmet": ["HELMET"], "body": ["BODY_ARMOR"], "belt": ["BELT"], "boots": ["BOOTS"], "gloves": ["GLOVES"],
	"amulet": ["AMULET"], "ring1": ["RING"], "ring2": ["RING"], "relic": ["RELIC"],
	"offhand": ["SHIELD", "QUIVER", "CATALYST"],
	"altar": ["IDOL_ALTAR"],
}
const EPSILON: float = 1.0e-6


# ============================================================================
# ITEM HELPERS
# ============================================================================

## True when the base (GameData.item_base record) fits an equipment slot of BuildMods.SLOTS (idols are not handled).
static func fits_slot(slot: String, base: Dictionary) -> bool:
	var type_name: String = str(base.get("typeName", ""))
	if slot == "weapon":
		return bool(base.get("isWeapon", false)) and type_name != "CROSSBOW"
	if slot == "offhand" and type_name in ONE_HANDED_TYPES:
		return true
	return type_name in SLOT_TYPES.get(slot, [])


## `preferred` if the item's base fits it, otherwise the first slot of BuildMods.SLOTS that fits, "" if none.
static func target_slot(item: Dictionary, preferred: String) -> String:
	var base: Dictionary = GameData.item_base(int(item.get("base", -1)))
	if base.is_empty():
		return ""
	if preferred != "" and fits_slot(preferred, base):
		return preferred
	for slot: String in BuildMods.SLOTS:
		if fits_slot(slot, base):
			return slot
	return ""


## Translated slot name.
static func slot_title(slot: String) -> String:
	return LE.t(str(ItemMods.SLOT_NAMES.get(slot, slot)))


## Rarity suffix of theme variations: "Set" for a set item, "Unique" for another unique, "" otherwise.
static func rarity(item: Dictionary) -> String:
	if not item.has("unique"):
		return ""
	return "Set" if int(GameData.unique(int(item["unique"])).get("isSetItem", 0)) != 0 else "Unique"


## Display name: the name the user gave the item, otherwise default_title().
static func item_title(item: Dictionary) -> String:
	var custom: Variant = item.get("name")
	if custom is String and not (custom as String).is_empty():
		return custom
	return default_title(item)


## The name without the user's custom one: the unique's name, otherwise the subtype's, falling back to the base
## type name; "—" for an empty item.
static func default_title(item: Dictionary) -> String:
	if item.is_empty():
		return "—"
	if item.has("unique"):
		return GameData.display_name(GameData.unique(int(item["unique"])))
	if item.has("base"):
		var base_id: int = int(item["base"])
		var sub: Dictionary = GameData.item_sub(base_id, int(item.get("sub", 0)))
		if not sub.is_empty():
			return GameData.display_name(sub)
		return str(GameData.item_base(base_id).get("typeName", "—"))
	return "—"


## Second tooltip line: the subtype name for uniques, the base name for regular items; "" if empty.
static func item_subtitle(item: Dictionary) -> String:
	if item.is_empty() or not item.has("base"):
		return ""
	var base_id: int = int(item["base"])
	if item.has("unique"):
		return GameData.display_name(GameData.item_sub(base_id, int(item.get("sub", 0))))
	return GameData.display_name(GameData.item_base(base_id))


## Mod lines of the item with their rolled values, as the item editor shows them: implicits, the unique's mods,
## then every affix property ("+12% Fire Resistance (T5)").
static func item_lines(item: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var base_id: int = int(item.get("base", -1))
	var rolls: Array = item.get("implicit_rolls", [])
	var implicits: Array = GameData.item_sub(base_id, int(item.get("sub", -1))).get("implicits", [])
	for j in range(implicits.size()):
		var imp: Dictionary = implicits[j]
		var roll: int = int(rolls[j]) if j < rolls.size() else 255
		var v: float = AffixMath.roll_value(float(imp["value"]), float(imp.get("maxValue", imp["value"])),
			str(imp.get("rounding", "Integer")), str(imp.get("modType", "ADDED")), roll, 0.0)
		lines.append("%s %s" % [format_value(imp, v), prop_title(imp)])
	if item.has("unique"):
		var unique_rolls: Array = item.get("unique_rolls", [])
		for mod: Dictionary in GameData.unique(int(item["unique"])).get("mods", []):
			if int(mod.get("hideInTooltip", 0)) != 0:
				continue
			var roll_id: int = int(mod.get("rollID", 0))
			var roll: int = int(unique_rolls[roll_id]) if roll_id < unique_rolls.size() else 255
			lines.append("%s %s" % [format_value(mod, AffixMath.unique_value(mod, roll)), prop_title(mod)])
	var base: Dictionary = GameData.item_base(base_id)
	for entry: Dictionary in item.get("affixes", []):
		var aff: Dictionary = GameData.affix(int(entry.get("id", -1)))
		var tiers: Array = aff.get("tiers", [])
		var tier: int = int(entry.get("tier", 1))
		if tier < 1 or tier > tiers.size():
			continue
		var m: float = AffixMath.effect_modifier(float(base.get("affixEffectModifier", 0.0)), float(aff.get("standardAffixEffectModifier", 0.0)))
		var props: Array = aff.get("properties", [])
		var ranges: Array = tiers[tier - 1].get("rolls", [])
		for j in range(mini(props.size(), ranges.size())):
			var prop: Dictionary = props[j]
			var v: float = AffixMath.roll_value(float(ranges[j][0]), float(ranges[j][1]), str(prop.get("rounding", "Integer")),
				str(prop.get("modType", "ADDED")), int(entry.get("roll", 255)), m)
			lines.append("%s %s (T%d)" % [format_value(prop, v), prop_title(prop), tier])
	return lines


## Property name with its tags: "Increased Damage (Fire, Spell)".
static func prop_title(prop: Dictionary) -> String:
	var tags: Array = prop.get("tagNames", [])
	var title: String = str(prop.get("propertyName", ""))
	if not tags.is_empty():
		title += " (%s)" % ", ".join(PackedStringArray(tags))
	return title


## INCREASED/MORE and fractional ADDED values (resistances, crit multiplier…) are shown as percentages.
static func format_value(prop: Dictionary, v: float) -> String:
	var mod_type: String = str(prop.get("modType", "ADDED"))
	var rounding: String = str(prop.get("rounding", "Integer"))
	var pct: bool = mod_type != "ADDED" or rounding == "Hundredth" or rounding == "Thousandth"
	var text: String = LE.fmt_pct(v) if pct else LE.fmt_num(v)
	if mod_type == "MORE":
		text += " more"
	return ("+" if v > 0.0 else "") + text


## Value range "+10–20%" (a single value when lo == hi); " more" is only appended once, at the end.
static func format_range(prop: Dictionary, lo: float, hi: float) -> String:
	var first: String = format_value(prop, lo)
	# fixed values: maxValue equals the value, or is left at 0 in the data
	if is_equal_approx(lo, hi) or (is_zero_approx(hi) and not is_zero_approx(lo)):
		return first
	var second: String = format_value(prop, hi).trim_prefix("+")
	return first.trim_suffix(" more") + "–" + second


## Tooltip templates "[min,max,rollID]" -> "min–max".
static func expand_template(text: String) -> String:
	var template := RegEx.new()
	template.compile("\\[\\s*(-?[0-9.]+)\\s*,\\s*(-?[0-9.]+)\\s*,\\s*[0-9]+\\s*\\]")
	return template.sub(text, "$1–$2", true)


## Required level of a unique: its own, otherwise its first subtype's (0 when unknown).
static func unique_level(unique: Dictionary) -> int:
	var own: Variant = unique.get("levelRequirement")
	if own != null:
		return int(own)
	var sub_types: Array = unique.get("subTypes", [])
	if sub_types.is_empty():
		return 0
	return int(GameData.item_sub(int(unique.get("baseType", -1)), int(sub_types[0])).get("levelRequirement", 0))


## " (level 18)" for a list entry, "" when there is no level requirement.
static func level_suffix(level: int) -> String:
	return LE.t(" (level %d)") % level if level > 0 else ""


## A fresh regular item: every implicit rolled at maximum, a copy of `affixes`.
static func new_item(base_id: int, sub_id: int, affixes: Array) -> Dictionary:
	var rolls: Array = []
	for _imp: Variant in GameData.item_sub(base_id, sub_id).get("implicits", []):
		rolls.append(255)
	return {"base": base_id, "sub": sub_id, "implicit_rolls": rolls, "affixes": affixes.duplicate(true)}


## baseTypeID of the first base (GameData.item_bases order) that fits the slot, -1 if none.
static func first_base(slot: String) -> int:
	for base: Dictionary in GameData.item_bases:
		if fits_slot(slot, base):
			return int(base["baseTypeID"])
	return -1


## The first current (non-legacy) subtype of the base the class can use, 0 if none.
static func default_sub(base: Dictionary, class_name_str: String) -> int:
	for sub: Dictionary in base.get("subItems", []):
		if int(sub.get("isLegacySubType", 0)) != 0:
			continue
		var classes: Array = sub.get("classRequirement", [])
		if classes.is_empty() or classes.has(class_name_str):
			return int(sub["subTypeID"])
	return 0


## A fresh item for a unique with every roll at maximum.
static func unique_item(unique_id: int) -> Dictionary:
	var unique: Dictionary = GameData.unique(unique_id)
	var base_id: int = int(unique.get("baseType", -1))
	var sub_types: Array = unique.get("subTypes", [0])
	var sub_id: int = int(sub_types[0]) if not sub_types.is_empty() else 0
	var implicit_rolls: Array = []
	for _imp: Variant in GameData.item_sub(base_id, sub_id).get("implicits", []):
		implicit_rolls.append(255)
	var max_roll_id: int = -1
	for mod: Dictionary in unique.get("mods", []):
		max_roll_id = maxi(max_roll_id, int(mod.get("rollID", 0)))
	var unique_rolls: Array = []
	for _i in range(max_roll_id + 1):
		unique_rolls.append(255)
	return {
		"base": base_id, "sub": sub_id, "implicit_rolls": implicit_rolls, "affixes": [],
		"unique": unique_id, "unique_rolls": unique_rolls,
	}


# ============================================================================
# STAT DIFF
# ============================================================================

## Ordered stat values of the build: key -> {"label": String, "value": float, "pct": bool}. The DPS of the selected
## skill comes first (key "dps"), then every numeric row of the character stats (key "group|label").
static func snapshot(build: Node) -> Dictionary:
	var values: Dictionary = {}
	if build.selected_skill >= 0 and build.selected_skill < build.skills.size() \
			and str((build.skills[build.selected_skill] as Dictionary).get("ability", "")) != "":
		var result: Dictionary = SkillCalc.compute(build, build.selected_skill)
		var dps: Dictionary = CalcSummary.find_row(result, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION)
		var dps_value: Variant = dps.get("value")
		if dps_value is float or dps_value is int:
			values["dps"] = {"label": LE.t("%s · DPS vs enemy") % str(result.get("title", "")), "value": float(dps_value), "pct": false}
	var store: StatStore = BuildMods.global_store(build)["store"]
	for row: Dictionary in CharacterCalc.compute(store, build):
		var raw: Variant = row.get("value")
		if raw is float or raw is int:
			var label: String = str(row.get("label", ""))
			values[str(row.get("group", "")) + "|" + label] = {
				"label": label, "value": float(raw), "pct": str(row.get("text", "")).contains("%")}
	return values


## snapshot() with `item` equipped in `slot` (an empty dict empties the slot). The build is restored exactly.
static func snapshot_with_item(build: Node, slot: String, item: Dictionary) -> Dictionary:
	return snapshot_with_items(build, {slot: item})


## snapshot() with several slots changed at once: `changes` maps slot -> item ({} empties the slot). Every touched
## slot is restored exactly (an absent slot stays absent).
static func snapshot_with_items(build: Node, changes: Dictionary) -> Dictionary:
	var previous: Dictionary = {}  # slot -> the item it held, only for slots that had one
	for slot: String in changes:
		if build.items.has(slot):
			previous[slot] = build.items[slot]
		var item: Dictionary = changes[slot]
		if item.is_empty():
			build.items.erase(slot)
		else:
			build.items[slot] = item.duplicate(true)
	build._skill_bonus_cache.clear()
	var values: Dictionary = snapshot(build)
	for slot: String in changes:
		if previous.has(slot):
			build.items[slot] = previous[slot]
		else:
			build.items.erase(slot)
	build._skill_bonus_cache.clear()
	return values


## Changed values, in `after` order then keys only in `before` (a missing value counts as 0):
## [{"label", "delta", "before", "after", "pct", "text"}].
static func diff(before: Dictionary, after: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var keys: Array = after.keys()
	for key: Variant in before:
		if not after.has(key):
			keys.append(key)
	for key: Variant in keys:
		var old_entry: Dictionary = before.get(key, {})
		var new_entry: Dictionary = after.get(key, {})
		var old_value: float = float(old_entry.get("value", 0.0))
		var new_value: float = float(new_entry.get("value", 0.0))
		var delta: float = new_value - old_value
		if absf(delta) < EPSILON:
			continue
		var source: Dictionary = new_entry if not new_entry.is_empty() else old_entry
		var label: String = str(source.get("label", ""))
		var pct: bool = bool(source.get("pct", false))
		changes.append({
			"label": label, "delta": delta, "before": old_value, "after": new_value, "pct": pct,
			"text": format_delta(delta, pct) + " " + label,
		})
	return changes


## "+12.5" / "−3%": the sign ("+" or U+2212) then the absolute value.
static func format_delta(delta: float, pct: bool) -> String:
	var sign_text: String = "+" if delta > 0.0 else "−"
	return sign_text + (LE.fmt_pct(absf(delta)) if pct else LE.fmt_num(absf(delta)))
