class_name MaxrollImport

## Import of a character from Maxroll's character API (planners.maxroll.gg). Pure functions: request URLs, the account
## character list, decoding of the item byte blobs and conversion of the character JSON into the build description of
## LEToolsImport (apply() of that class is reused).
## The character JSON is the game's offline-save format (CharacterData), the items are its binary blobs:
## research/07e_save_format.md; reference decoder: tools/extract/save_parser.py (upgrade_to_v6, decode_item).

const CHARACTERS_URL: String = "https://planners.maxroll.gg/lastepoch/characters/"
const CURRENT_ITEM_VERSION: int = 6
const FIRST_NON_EQUIPMENT_TYPE: int = 101
const IDOL_AREA_ROWS: int = 5

## Container ids of the save: equipment slot, idol grid, idol inventory (holds the altar), blessings, Weaver items.
const EQUIPMENT_CONTAINERS: Dictionary = {
	2: "helmet",
	3: "body",
	4: "weapon",
	5: "offhand",
	6: "gloves",
	7: "belt",
	8: "boots",
	10: "ring1",
	9: "ring2",
	11: "amulet",
	12: "relic",
}
const IDOL_CONTAINER: int = 29
const IDOL_INVENTORY_CONTAINER: int = 123
const BLESSING_CONTAINERS: Array[int] = [33, 34, 35, 36, 37, 38, 39, 43, 44, 45]
const WEAVER_CONTAINERS: Array[int] = [91, 92, 93, 94, 95, 96]

const SEALED_NONE: String = ""
const SEALED_REGULAR: String = "regular"
const SEALED_PRIMORDIAL: String = "primordial"
const SEALED_CORRUPTION: String = "corruption"


# ============================================================================
# URLS AND CHARACTER LIST
# ============================================================================

## Character list of an account ("" when the account is empty).
static func list_url(account: String) -> String:
	var name: String = account.strip_edges()
	return "" if name == "" else CHARACTERS_URL + name.uri_encode()


## One character of an account.
static func character_url(account: String, name: String) -> String:
	return CHARACTERS_URL + account.strip_edges().uri_encode() + "/" + name.uri_encode()


## Parsed list response -> [{name, level, class_id, mastery, cycle, hardcore, legacy}]. Legacy = a cycle older than the
## newest one of the account. Order: current cycle first, then level descending, then name. Names may repeat.
static func parse_character_list(data: Variant) -> Array:
	var result: Array = []
	if not data is Array:
		return result
	var max_cycle: int = 0
	for raw: Variant in data:
		if not raw is Dictionary or str(raw.get("characterName", "")) == "":
			continue
		var cycle: int = int(raw.get("cycle", 0))
		max_cycle = maxi(max_cycle, cycle)
		result.append({
			"name": str(raw["characterName"]),
			"level": int(raw.get("level", 1)),
			"class_id": int(raw.get("characterClass", -1)),
			"mastery": int(raw.get("chosenMastery", 0)),
			"cycle": cycle,
			"hardcore": bool(raw.get("hardcore", false)),
			"legacy": false,
		})
	for entry: Dictionary in result:
		entry["legacy"] = int(entry["cycle"]) < max_cycle
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["legacy"] != b["legacy"]:
			return not a["legacy"]
		if a["level"] != b["level"]:
			return int(a["level"]) > int(b["level"])
		return str(a["name"]).nocasecmp_to(str(b["name"])) < 0)
	return result


# ============================================================================
# ITEM BLOBS
# ============================================================================

## Item data (JSON int array or base64 string) -> bytes.
static func _bytes_of(data: Variant) -> PackedByteArray:
	if data is PackedByteArray:
		return data
	if data is String:
		return Marshalls.base64_to_raw(data)
	var bytes := PackedByteArray()
	if data is Array:
		for value: Variant in data:
			bytes.append(int(value) & 0xFF)
	return bytes


## Any item version (0..6) -> the layout of version 6, as ItemData.setValuesFromSerialisation does on load. Random
## individual ids become 0. Empty array for a version above 6.
static func upgrade_item(data: Variant) -> PackedByteArray:
	var b: PackedByteArray = _bytes_of(data)
	if b.size() < 2:
		b = PackedByteArray([0, 0, 0, 0, 0, 0, 0])  # the game substitutes a 7-byte default array
	var version: int = b[0]
	if version > CURRENT_ITEM_VERSION:
		return PackedByteArray()
	if version < 2 and b[1] < FIRST_NON_EQUIPMENT_TYPE:
		# v0/v1 -> v2: equipment gets the flag byte 0x80 (alwaysUntradeable) at index 4
		var head: PackedByteArray = PackedByteArray([2, b[1], b[2] if b.size() > 2 else 0, b[3] if b.size() > 3 else 0, 0x80])
		if b.size() > 4:
			head.append_array(b.slice(4))
		b = head
	if version < 3:
		# v2 -> v3: a 2-byte individual id after the version byte
		var wide := PackedByteArray([6, 0, 0])
		wide.append_array(b.slice(1))
		b = wide
	if version < 6:
		# v3..v5 -> v6: the 2-byte individual id (bit 7 of byte 1 = duplicated) becomes 4 bytes
		var dup: int = b[1] & 0x80
		var old_id: int = ((b[1] & 0x7F) << 8) | b[2]
		var widened := PackedByteArray([6, dup | ((old_id >> 24) & 0x7F), (old_id >> 16) & 0xFF, (old_id >> 8) & 0xFF, old_id & 0xFF])
		widened.append_array(b.slice(3))
		b = widened
	b[0] = CURRENT_ITEM_VERSION
	return b


## Affix triplet [tier << 4 | id high 4 bits][id low 8 bits][roll]; {} when the bytes are missing.
static func _affix(b: PackedByteArray, offset: int, sealed: String) -> Dictionary:
	if b.size() < offset + 3:
		return {}
	var nibble: int = b[offset] >> 4
	if sealed == SEALED_NONE and nibble == 7:
		sealed = SEALED_PRIMORDIAL  # T8
	return {"id": ((b[offset] & 0x0F) << 8) | b[offset + 1], "tier": nibble + 1, "roll": b[offset + 2], "sealed": sealed}


## One item blob -> {base, sub, rarity, corrupted, implicit_rolls, unique, unique_rolls, affixes: [{id, tier, roll, sealed}]}
## for equipment-like items (type < 101: gear, idols, blessings, altar). {} for anything else and for truncated data.
static func decode_item(data: Variant) -> Dictionary:
	var b: PackedByteArray = upgrade_item(data)
	if b.size() < 12 or b[5] >= FIRST_NON_EQUIPMENT_TYPE:
		return {}
	var base: int = b[5]
	var rarity: int = b[7] & 0x3F
	var corrupted: bool = (b[8] & 0x10) != 0 or base == IdolGrid.ALTAR_BASE
	var item: Dictionary = {
		"base": base,
		"sub": b[6],
		"rarity": rarity,
		"corrupted": corrupted,
		"implicit_rolls": [b[9], b[10], b[11]],
		"unique": -1,
		"unique_rolls": [],
		"affixes": [],
	}
	var affixes: Array = item["affixes"]
	if rarity >= 7 and rarity <= 9:
		if b.size() < 23:
			return {}
		item["unique"] = (b[12] << 8) | b[13]
		item["unique_rolls"] = Array(b.slice(14, 22))
		if rarity < 9:
			# unique / set: bits 5-7 = affix count (bits 0-4: legendary potential / weaver's will)
			var count: int = b[22] >> 5
			for i in range(count):
				var affix: Dictionary = _affix(b, 23 + 3 * i, SEALED_NONE)
				if not affix.is_empty():
					affixes.append(affix)
		else:
			# legendary: bits 0-2 = affix count; corrupted: bit 7 = the last affix is corruption-sealed
			var count: int = b[22] & 0x07
			var last_sealed: bool = corrupted and (b[22] >> 7) != 0
			if b.size() >= 23 + 3 * count:
				for i in range(count):
					var affix: Dictionary = _affix(b, 23 + 3 * i, SEALED_CORRUPTION if last_sealed and i == count - 1 else SEALED_NONE)
					if not affix.is_empty():
						affixes.append(affix)
	elif rarity < 5:
		# the reader loads affixes only for rarity < 5; rarity 5..6 stays without
		if b.size() < 14:
			return {}
		var sealed_regular: bool = (b[13] & 0x80) != 0
		var sealed_corruption: bool = (b[13] & 0x40) != 0
		var primordial: bool = false
		for i in range(b[13] & 0x3F):
			var sealed: String = SEALED_NONE
			if sealed_regular and i == 0:
				sealed = SEALED_REGULAR
			elif sealed_corruption and i == (1 if sealed_regular else 0):
				sealed = SEALED_CORRUPTION
			var affix: Dictionary = _affix(b, 14 + 3 * i, sealed)
			if not affix.is_empty():
				primordial = primordial or affix["sealed"] == SEALED_PRIMORDIAL
				affixes.append(affix)
		# the rarity is re-derived from the number of unsealed affixes (0..4)
		item["rarity"] = clampi(affixes.size() - int(sealed_regular) - int(primordial) - int(sealed_corruption), 0, 4)
	return item


# ============================================================================
# CONVERSION TO THE CLIENT MODEL
# ============================================================================

## Character JSON -> the build description of LEToolsImport.to_build:
## {class_id, mastery, level, passives, skills: [{ability, level, tree} x5], items: {slot: item}, blessings, warnings}.
static func to_build(save: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var doc: Dictionary = {
		"class_id": -1,
		"mastery": 0,
		"level": 100,
		"passives": {},
		"skills": [],
		"items": {},
		"blessings": {},
		"warnings": warnings,
	}
	var class_id: int = int(save.get("characterClass", -1))
	var class_data: Dictionary = GameData.get_class_data(class_id)
	if class_data.is_empty():
		warnings.append(LE.t("Unknown class: %d.") % class_id)
		return doc
	doc["class_id"] = class_id
	doc["level"] = clampi(int(save.get("level", 100)), 1, LEToolsImport.LEVEL_MAX)

	var mastery: int = int(save.get("chosenMastery", 0))
	if mastery < 0 or mastery >= class_data.get("masteries", []).size():
		warnings.append(LE.t("Unknown mastery: %d, \"No mastery\" selected.") % mastery)
		mastery = 0
	doc["mastery"] = mastery

	var tree: Variant = save.get("savedCharacterTree")
	doc["passives"] = LEToolsImport.passives_from(class_id, {"selected": _selected(tree)}, warnings)
	doc["skills"] = LEToolsImport.skills_from(_skill_data(save), warnings)

	var weaver_used: bool = _points_sum(save.get("savedWeaverTree")) > 0
	var equipment: Dictionary = {}  # slot -> decoded item
	var altar: Dictionary = {}
	var idols: Array = []  # [{x, y, item}]
	var blessing_items: Array = []
	for entry: Variant in save.get("savedItems", []):
		if not entry is Dictionary:
			continue
		var container: int = int(entry.get("containerID", 0))
		if WEAVER_CONTAINERS.has(container):
			weaver_used = true
			continue
		var is_equipment: bool = EQUIPMENT_CONTAINERS.has(container)
		var is_idol: bool = container == IDOL_CONTAINER
		var is_blessing: bool = BLESSING_CONTAINERS.has(container)
		var is_altar: bool = container == IDOL_INVENTORY_CONTAINER
		if not (is_equipment or is_idol or is_blessing or is_altar):
			continue
		var decoded: Dictionary = decode_item(entry.get("data"))
		if decoded.is_empty():
			if not is_altar:
				warnings.append(LE.t("%s: could not read the item data, skipped.") % _container_label(container))
			continue
		if is_equipment:
			equipment[EQUIPMENT_CONTAINERS[container]] = decoded
		elif is_altar:
			if int(decoded["base"]) == IdolGrid.ALTAR_BASE:
				altar = decoded
		elif is_idol:
			var position: Variant = entry.get("inventoryPosition")
			var pos: Dictionary = position if position is Dictionary else {}
			idols.append({"x": int(pos.get("x", 0)), "y": int(pos.get("y", 0)), "item": decoded})
		elif int(decoded["base"]) == LEToolsImport.BLESSING_BASE:
			blessing_items.append(decoded)

	var items: Dictionary = {}
	for slot: String in equipment:
		var item: Dictionary = _convert_item(equipment[slot], LE.t(str(ItemMods.SLOT_NAMES.get(slot, slot))), warnings)
		if not item.is_empty():
			items[slot] = item
	if not altar.is_empty():  # before the idols: the grid depends on the altar
		var item: Dictionary = _convert_item(altar, LE.t(str(ItemMods.SLOT_NAMES.get(IdolGrid.ALTAR_SLOT, IdolGrid.ALTAR_SLOT))), warnings)
		if not item.is_empty():
			items[IdolGrid.ALTAR_SLOT] = item
	_idols(idols, items, warnings)
	doc["items"] = items
	doc["blessings"] = _blessings(blessing_items, warnings)
	if weaver_used:
		warnings.append(LE.t("The Weaver tree is skipped: it changes echoes, not the character."))
	return doc


static func _container_label(container: int) -> String:
	if EQUIPMENT_CONTAINERS.has(container):
		var slot: String = EQUIPMENT_CONTAINERS[container]
		return LE.t(str(ItemMods.SLOT_NAMES.get(slot, slot)))
	return LE.t("Item")


## {nodeIDs, nodePoints} of a saved tree -> {node id: points}.
static func _selected(tree: Variant) -> Dictionary:
	var selected: Dictionary = {}
	if not tree is Dictionary:
		return selected
	var ids: Variant = tree.get("nodeIDs")
	var points: Variant = tree.get("nodePoints")
	if not ids is Array or not points is Array:
		return selected
	for i in range(mini(ids.size(), points.size())):
		selected[int(ids[i])] = int(points[i])
	return selected


static func _points_sum(tree: Variant) -> int:
	var sum: int = 0
	for points: Variant in _selected(tree).values():
		sum += int(points)
	return sum


## savedSkillTrees + abilityBar -> the skillTrees / hud shape that LEToolsImport.skills_from reads.
## treeID of the save is the playerAbilityID, which is also the skill tree id.
static func _skill_data(save: Dictionary) -> Dictionary:
	var trees: Array = []
	var saved: Variant = save.get("savedSkillTrees")
	if saved is Array:
		for entry: Variant in saved:
			if not entry is Dictionary:
				continue
			var selected: Dictionary = _selected(entry)
			var spent: int = 0
			for points: Variant in selected.values():
				spent += int(points)
			trees.append({
				"treeID": str(entry.get("treeID", "")),
				"slotNumber": int(entry.get("slotNumber", 0)),
				"level": clampi(spent + int(entry.get("unspentPoints", 0)), 1, LEToolsImport.SKILL_LEVEL_MAX),
				"selected": selected,
			})
	return {"skillTrees": trees, "hud": save.get("abilityBar", [])}


## The grid y axis of the game goes up from the bottom and the position is the bottom-left cell of the idol.
static func _idols(idols: Array, items: Dictionary, warnings: Array[String]) -> void:
	for entry: Dictionary in idols:
		var decoded: Dictionary = entry["item"]
		var base_id: int = int(decoded["base"])
		var size: Vector2i = IdolGrid.size_of(base_id)
		var row: int = IDOL_AREA_ROWS - int(entry["y"]) - size.y
		var col: int = int(entry["x"])
		var label: String = LE.t("Idol (%d:%d)") % [row + 1, col + 1]
		var item: Dictionary = _convert_item(decoded, label, warnings)
		if item.is_empty():
			continue
		if row < 0 or col < 0:
			warnings.append(LE.t("%s: invalid position, skipped.") % label)
			continue
		if not GameData.is_idol_type(int(item["base"])):
			warnings.append(LE.t("%s: the item is not an idol, skipped.") % label)
			continue
		if not IdolGrid.fits(items, row, col, int(item["base"])):
			warnings.append(LE.t("%s: does not fit in the idol grid (occupied or locked), skipped.") % label)
			continue
		items[IdolGrid.key(row, col)] = item


## Blessing items (base 34): id = subtype, roll = the first implicit roll, slot = the first timeline of the blessing.
static func _blessings(blessing_items: Array, warnings: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for decoded: Dictionary in blessing_items:
		var blessing_id: int = int(decoded["sub"])
		var blessing: Dictionary = GameData.blessing(blessing_id)
		var timelines: Array = blessing.get("timelines", [])
		if blessing.is_empty() or timelines.is_empty():
			warnings.append(LE.t("Blessing %d is unknown, skipped.") % blessing_id)
			continue
		var timeline_id: int = int(timelines[0].get("timelineID", -1))
		result[timeline_id] = {"id": blessing_id, "roll": int(decoded["implicit_rolls"][0])}
	return result


## Affix id after the redirect of ItemAffix (convertOnIncompatibleItemType, up to 100 hops); -1 for an unknown id.
static func _resolve_affix(affix_id: int, item_type: int) -> int:
	var affix: Dictionary = GameData.affix(affix_id)
	if affix.is_empty():
		return -1
	for _hop in range(100):
		if int(affix.get("convertOnIncompatibleItemType", 0)) == 0 or affix_id == 25:
			break
		var can_roll_on: Array = affix.get("canRollOn", [])
		var allowed: bool = false
		for type_id: Variant in can_roll_on:
			if int(type_id) == item_type:
				allowed = true
				break
		if allowed:
			break
		affix_id = int(affix.get("affixIDToConvertTo", 0))
		affix = GameData.affix(affix_id)
		if affix.is_empty():
			return -1
	return affix_id


## One decoded item -> client item dictionary; {} (plus a warning) when the item cannot be built.
static func _convert_item(decoded: Dictionary, label: String, warnings: Array[String]) -> Dictionary:
	var base_id: int = int(decoded["base"])
	var sub_id: int = int(decoded["sub"])
	var unique_id: int = int(decoded["unique"])
	if unique_id >= 0:
		var unique: Dictionary = GameData.unique(unique_id)
		if unique.is_empty():
			warnings.append(LE.t("%s: unknown unique item %d, skipped.") % [label, unique_id])
			return {}
		base_id = int(unique.get("baseType", -1))
		var sub_types: Array = unique.get("subTypes", [])
		var known: bool = false
		for candidate: Variant in sub_types:
			if int(candidate) == sub_id:
				known = true
				break
		if not known and not sub_types.is_empty():
			sub_id = int(sub_types[0])
	if GameData.item_base(base_id).is_empty() or GameData.item_sub(base_id, sub_id).is_empty():
		warnings.append(LE.t("%s: unknown base %d / subtype %d, skipped.") % [label, base_id, sub_id])
		return {}

	var item: Dictionary = {"base": base_id, "sub": sub_id, "implicit_rolls": (decoded["implicit_rolls"] as Array).duplicate(), "affixes": []}
	if unique_id >= 0:
		item["unique"] = unique_id
		item["unique_rolls"] = (decoded["unique_rolls"] as Array).duplicate()
	if bool(decoded["corrupted"]) and base_id != IdolGrid.ALTAR_BASE:
		item["corrupted"] = true

	var is_idol: bool = GameData.is_idol_type(base_id)
	for raw: Dictionary in decoded["affixes"]:
		var affix_id: int = _resolve_affix(int(raw["id"]), base_id)
		if affix_id < 0:
			warnings.append(LE.t("%s: unknown affix \"%s\", skipped.") % [label, raw["id"]])
			continue
		var tier: int = int(raw["tier"])
		if is_idol and str(GameData.affix(affix_id).get("specialAffixType", "")) != "IdolEnchantment":
			tier = 1  # idol affixes have a single tier
		var affix: Dictionary = {"id": affix_id, "tier": tier, "roll": int(raw["roll"])}
		match str(raw["sealed"]):
			SEALED_REGULAR, SEALED_PRIMORDIAL:
				affix["sealed"] = true
			SEALED_CORRUPTION:
				affix["corrupted"] = true
		item["affixes"].append(affix)
	item["affixes"] = ItemCompare.place_affixes(item["affixes"], is_idol)
	return item
