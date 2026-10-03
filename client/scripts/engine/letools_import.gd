class_name LEToolsImport

## Import of a build from a lastepochtools.com planner link. Pure functions: URL / hash parsing, id decoding,
## conversion of the planner_data JSON into the client build model and applying it to the Build autoload.
## Data format: client/docs/UI.md «Импорт из Last Epoch Tools».
## Requests carry no browser User-Agent on purpose: Cloudflare answers 403 to a Chrome UA that comes with a non-Chrome
## TLS fingerprint, while the engine default User-Agent passes.

const LZStringScript: GDScript = preload("res://scripts/engine/lz_string.gd")

const PLANNER_URL: String = "https://www.lastepochtools.com/planner/"
const DATA_URL: String = "https://www.lastepochtools.com/api/internal/planner_data/"
const SKILL_SLOTS: int = 5
const SKILL_LEVEL_MAX: int = 20
const LEVEL_MAX: int = 100
const BLESSING_BASE: int = 34

## LE Tools equipment slot -> client slot (IdolGrid.ALTAR_SLOT for the idol altar).
const SLOT_MAP: Dictionary = {
	"head": "helmet",
	"chest": "body",
	"waist": "belt",
	"feet": "boots",
	"hands": "gloves",
	"weapon1": "weapon",
	"weapon2": "offhand",
	"amulet": "amulet",
	"ring1": "ring1",
	"ring2": "ring2",
	"relic": "relic",
	"idol_altar": "altar",
}


# ============================================================================
# LINKS AND PAGE PARSING
# ============================================================================

## Canonical planner URL from a full link (with or without scheme / www, trailing slash, query) or a bare code; "" if invalid.
static func planner_url(input: String) -> String:
	var text: String = input.strip_edges()
	if text == "":
		return ""
	var link := RegEx.new()
	link.compile("^(?:(?i:https?)://)?(?:(?i:www)\\.)?(?i:lastepochtools\\.com)/planner/([A-Za-z0-9_-]+)")
	var found: RegExMatch = link.search(text)
	if found != null:
		return PLANNER_URL + found.get_string(1)
	var bare := RegEx.new()
	bare.compile("^[A-Za-z0-9_-]{4,32}$")
	if bare.search(text) != null:
		return PLANNER_URL + text
	return ""


## Hash of the planner_data request from the planner page HTML ("" if not found). The variable holding the hash is
## obfuscated and may be renamed, so it is found through the fetch call; fallback: the first quoted 32-digit hex string.
static func extract_data_hash(html: String) -> String:
	var fetch := RegEx.new()
	fetch.compile("planner_data/['\"]\\s*\\+\\s*([A-Za-z_$][\\w$]*)")
	var name_match: RegExMatch = fetch.search(html)
	if name_match != null:
		var var_name: String = name_match.get_string(1).replace("$", "\\$")
		var assign := RegEx.new()
		assign.compile("(?<![\\w$])%s\\s*=\\s*['\"]([0-9a-f]+)['\"]" % var_name)
		var hash_match: RegExMatch = assign.search(html)
		if hash_match != null:
			return hash_match.get_string(1)
	var fallback := RegEx.new()
	fallback.compile("=\\s*['\"]([0-9a-f]{32})['\"]")
	var fb: RegExMatch = fallback.search(html)
	return fb.get_string(1) if fb != null else ""


# ============================================================================
# ID DECODING
# ============================================================================

## Decodes an id of LE Tools: first char = kind, the rest = LZString of a digit string.
## "I" item: {kind, base, sub, rarity, unique}; "U" unique: {kind, sub, unique}; "A" affix: {kind, affix};
## "S" set item: {kind, raw}. {} when the id cannot be decoded.
static func decode_id(id: String) -> Dictionary:
	if id.length() < 2:
		return {}
	var kind: String = id[0]
	var digits: String = LZStringScript.decompress_from_encoded_uri(id.substr(1))
	if digits == "" or not digits.is_valid_int():
		return {}
	match kind:
		"I":
			# "1" + base(3) + sub(3) + rarity(1) + uniqueId(rest, >= 2 digits)
			if digits.length() < 10 or digits[0] != "1":
				return {}
			return {
				"kind": "I",
				"base": int(digits.substr(1, 3)),
				"sub": int(digits.substr(4, 3)),
				"rarity": int(digits.substr(7, 1)),
				"unique": int(digits.substr(8)),
			}
		"U":
			# sub(3) + uniqueId(rest)
			if digits.length() < 4:
				return {}
			return {"kind": "U", "sub": int(digits.substr(0, 3)), "unique": int(digits.substr(3))}
		"A":
			return {"kind": "A", "affix": int(digits)}
		"S":
			return {"kind": "S", "raw": digits}
	return {}


# ============================================================================
# CONVERSION TO THE CLIENT MODEL
# ============================================================================

## planner_data response (full {data: {...}} or only the inner data) -> client build description:
## {class_id, mastery, level, passives, skills: [{ability, level, tree} x5], items: {slot: item}, blessings, warnings}.
static func to_build(response: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	var data: Dictionary = response
	if not data.has("bio") and response.get("data") is Dictionary:
		data = response["data"]

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
	var bio: Variant = data.get("bio")
	if not bio is Dictionary:
		warnings.append("В данных нет блока bio (класс, мастерство, уровень).")
		return doc

	var class_id: int = int(bio.get("characterClass", -1))
	var class_data: Dictionary = GameData.get_class_data(class_id)
	if class_data.is_empty():
		warnings.append("Неизвестный класс: %d." % class_id)
		return doc
	doc["class_id"] = class_id
	doc["level"] = clampi(int(bio.get("level", 100)), 1, LEVEL_MAX)

	var mastery: int = int(bio.get("chosenMastery", 0))
	if mastery < 0 or mastery >= class_data.get("masteries", []).size():
		warnings.append("Неизвестное мастерство: %d, выбрано «Без мастерства»." % mastery)
		mastery = 0
	doc["mastery"] = mastery

	doc["passives"] = _passives(class_id, data.get("charTree"), warnings)
	doc["skills"] = _skills(data, warnings)

	var items: Dictionary = {}
	_equipment(data.get("equipment"), items, warnings)
	_idols(data.get("idols"), items, warnings)
	doc["items"] = items
	doc["blessings"] = _blessings(data.get("blessings"), warnings)

	var weaver: Variant = data.get("weaverTree")
	var weaver_used: bool = weaver is Dictionary and weaver.get("selected") is Dictionary and not weaver["selected"].is_empty()
	var containers: Variant = data.get("weaverTreeContainers")
	if weaver_used or (containers is Array and not containers.is_empty()):
		warnings.append("Дерево Weaver и идолы Weaver не поддерживаются, пропущены.")
	return doc


static func _passives(class_id: int, tree: Variant, warnings: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if not tree is Dictionary or not tree.get("selected") is Dictionary:
		return result
	var known: Dictionary = {}
	for node: Variant in GameData.get_passive_tree(class_id).get("nodes", []):
		if node is Dictionary:
			known[int(node.get("id", -1))] = true
	var unknown: int = 0
	var selected: Dictionary = tree["selected"]
	for key: Variant in selected:
		var points: int = int(selected[key])
		if points <= 0:
			continue
		if not known.has(int(key)):
			unknown += 1
			continue
		result[int(key)] = points
	if unknown > 0:
		warnings.append("Пассивки: %d неизвестных узлов пропущено." % unknown)
	return result


static func _skills(data: Dictionary, warnings: Array[String]) -> Array:
	var skills: Array = []
	var hud: Variant = data.get("hud")
	var trees_by_id: Dictionary = {}
	var trees: Variant = data.get("skillTrees")
	if trees is Array:
		for entry: Variant in trees:
			if entry is Dictionary:
				trees_by_id[str(entry.get("treeID", ""))] = entry

	for i in range(SKILL_SLOTS):
		var slot: Dictionary = {"ability": "", "level": SKILL_LEVEL_MAX, "tree": {}}
		skills.append(slot)
		var raw: Variant = hud[i] if hud is Array and i < hud.size() else null
		var ability_id: String = "" if raw == null else str(raw)
		if ability_id == "" or ability_id == "-1" or ability_id == "<null>":
			continue
		var ability: Dictionary = GameData.get_ability(ability_id)
		if ability.is_empty():
			warnings.append("Умение %d: неизвестный id «%s», пропущено." % [i + 1, ability_id])
			continue
		slot["ability"] = ability_id

		var tree_id: String = str(ability.get("skillTree", ability_id))
		var entry: Variant = trees_by_id.get(tree_id)
		if not entry is Dictionary:
			continue
		slot["level"] = clampi(int(entry.get("level", SKILL_LEVEL_MAX)), 1, SKILL_LEVEL_MAX)
		var known: Dictionary = {}
		for node: Variant in GameData.get_skill_tree(tree_id).get("nodes", []):
			if node is Dictionary:
				known[int(node.get("id", -1))] = true
		var selected: Variant = entry.get("selected")
		var unknown: int = 0
		var tree: Dictionary = {}
		if selected is Dictionary:
			for key: Variant in selected:
				var points: int = int(selected[key])
				if points <= 0:
					continue
				if not known.has(int(key)):
					unknown += 1
					continue
				tree[int(key)] = points
		slot["tree"] = tree
		if unknown > 0:
			warnings.append("Умение %d (%s): %d неизвестных узлов пропущено." % [i + 1, ability_id, unknown])
	return skills


static func _equipment(equipment: Variant, items: Dictionary, warnings: Array[String]) -> void:
	if not equipment is Dictionary:
		return
	for le_slot: Variant in equipment:
		var raw: Variant = equipment[le_slot]
		if not raw is Dictionary:
			continue
		var slot: String = str(SLOT_MAP.get(str(le_slot), ""))
		if slot == "":
			warnings.append("Неизвестный слот «%s», пропущен." % le_slot)
			continue
		var item: Dictionary = _convert_item(raw, ItemMods.SLOT_NAMES_RU.get(slot, slot), warnings)
		if item.is_empty():
			continue
		if slot == IdolGrid.ALTAR_SLOT and int(item["base"]) != IdolGrid.ALTAR_BASE:
			warnings.append("Алтарь идолов: предмет не является алтарём, пропущен.")
			continue
		items[slot] = item


static func _idols(idols: Variant, items: Dictionary, warnings: Array[String]) -> void:
	if not idols is Array:
		return
	for raw: Variant in idols:
		if not raw is Dictionary:
			continue
		var row: int = int(raw.get("y", 0)) - 1
		var col: int = int(raw.get("x", 0)) - 1
		var label: String = "Идол (%d:%d)" % [row + 1, col + 1]
		var item: Dictionary = _convert_item(raw, label, warnings)
		if item.is_empty():
			continue
		if row < 0 or col < 0:
			warnings.append("%s: неверная позиция, пропущен." % label)
			continue
		if not GameData.is_idol_type(int(item["base"])):
			warnings.append("%s: предмет не является идолом, пропущен." % label)
			continue
		if not IdolGrid.fits(items, row, col, int(item["base"])):
			warnings.append("%s: не помещается в сетку идолов (занято или закрыто), пропущен." % label)
			continue
		if raw.get("corruptedAffix") is Dictionary:
			item["corrupted"] = true
		items[IdolGrid.key(row, col)] = item


## One LE Tools item/idol -> client item dictionary; {} (plus a warning) when the item cannot be built.
static func _convert_item(raw: Dictionary, label: String, warnings: Array[String]) -> Dictionary:
	var dec: Dictionary = decode_id(str(raw.get("id", "")))
	var kind: String = str(dec.get("kind", ""))
	var base_id: int
	var sub_id: int = int(dec.get("sub", -1))
	var unique_id: int = -1
	match kind:
		"I":
			base_id = int(dec["base"])
		"U":
			unique_id = int(dec["unique"])
			var unique: Dictionary = GameData.unique(unique_id)
			if unique.is_empty():
				warnings.append("%s: неизвестный уникальный предмет %d, пропущен." % [label, unique_id])
				return {}
			base_id = int(unique.get("baseType", -1))
		"S":
			warnings.append("%s: сетовый предмет (id типа S) не поддерживается, пропущен." % label)
			return {}
		_:
			warnings.append("%s: не удалось разобрать id предмета, пропущен." % label)
			return {}
	if GameData.item_base(base_id).is_empty() or GameData.item_sub(base_id, sub_id).is_empty():
		warnings.append("%s: неизвестная база %d / подтип %d, пропущен." % [label, base_id, sub_id])
		return {}

	var implicit_rolls: Array = []
	for roll: Variant in raw.get("ir", []):
		implicit_rolls.append(int(roll))
	var item: Dictionary = {"base": base_id, "sub": sub_id, "implicit_rolls": implicit_rolls, "affixes": []}
	if unique_id >= 0:
		var unique_rolls: Array = []
		for roll: Variant in raw.get("ur", []):
			unique_rolls.append(int(roll))
		item["unique"] = unique_id
		item["unique_rolls"] = unique_rolls

	var raw_affixes: Array = []
	if raw.get("affixes") is Array:
		raw_affixes.append_array(raw["affixes"])
	raw_affixes.append(raw.get("sealedAffix"))
	raw_affixes.append(raw.get("corruptedAffix"))
	for entry: Variant in raw_affixes:
		if not entry is Dictionary:
			continue
		var affix_dec: Dictionary = decode_id(str(entry.get("id", "")))
		if affix_dec.get("kind", "") != "A" or GameData.affix(int(affix_dec["affix"])).is_empty():
			warnings.append("%s: неизвестный аффикс «%s», пропущен." % [label, entry.get("id", "")])
			continue
		item["affixes"].append({"id": int(affix_dec["affix"]), "tier": int(entry.get("tier", 1)), "roll": int(entry.get("r", 255))})
	return item


## Blessings of the planner: list of null / {id, ir}. The mapping (base 34, sub = blessing id, roll = ir[0]) is UNVERIFIED:
## the sample build had no blessings.
static func _blessings(raw_list: Variant, warnings: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	if not raw_list is Array:
		return result
	for raw: Variant in raw_list:
		if not raw is Dictionary:
			continue
		var dec: Dictionary = decode_id(str(raw.get("id", "")))
		if dec.get("kind", "") != "I" or int(dec["base"]) != BLESSING_BASE:
			warnings.append("Благословение: не удалось разобрать id, пропущено.")
			continue
		var blessing_id: int = int(dec["sub"])
		var blessing: Dictionary = GameData.blessing(blessing_id)
		var timelines: Array = blessing.get("timelines", [])
		if blessing.is_empty() or timelines.is_empty():
			warnings.append("Благословение %d неизвестно, пропущено." % blessing_id)
			continue
		var rolls: Variant = raw.get("ir")
		var roll: int = int(rolls[0]) if rolls is Array and not rolls.is_empty() else 255
		result[int(timelines[0].get("timelineID", -1))] = {"id": blessing_id, "roll": roll}
	return result


# ============================================================================
# APPLYING
# ============================================================================

## Replaces the build of the Build autoload (`build`) with the result of to_build and emits `changed`.
static func apply(build: Node, doc: Dictionary) -> void:
	var class_id: int = int(doc.get("class_id", -1))
	if class_id < 0:
		return
	build.set_class(class_id)  # resets mastery, passives, skills, items and blessings
	build.mastery = int(doc["mastery"])
	build.level = int(doc["level"])
	build.passives = (doc["passives"] as Dictionary).duplicate()

	var skills: Array = doc["skills"]
	for i in range(mini(skills.size(), build.skills.size())):
		var skill: Dictionary = skills[i]
		if str(skill["ability"]) == "":
			continue
		build.set_skill(i, str(skill["ability"]))  # loads the skill tree nodes
		build.skills[i]["tree"] = (skill["tree"] as Dictionary).duplicate()
		build.skills[i]["level"] = int(skill["level"])

	for slot: Variant in doc["items"]:
		build.items[slot] = (doc["items"][slot] as Dictionary).duplicate(true)
	for timeline: Variant in doc["blessings"]:
		build.blessings[timeline] = (doc["blessings"][timeline] as Dictionary).duplicate()
	build.changed.emit()
