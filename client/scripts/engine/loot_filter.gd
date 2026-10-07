class_name LootFilter

## A Last Epoch loot filter made from the build's items and idols (docs/UI.md "Loot filter").
## plan() turns the build into rule specs (highest priority first), apply_choices() drops what the user unchecked,
## to_xml() writes the game's ItemFilter XML (format of ItemFiltering.ItemFilter, CURRENT_LF_VERSION 9).

const LF_VERSION: int = 9
const GAME_VERSION: String = "1.5.0"
## Item types the filter rules can name: equipment 0-24 and idols 25-33 (the altar and the lenses are left out).
const LAST_FILTERED_BASE: int = 33
## Affix kinds that never drop on an item (corruption, unique mods shown as affixes).
const SKIPPED_AFFIX_KINDS: Array[String] = ["Corrupted", "FakeUniqueMod"]
## The game's rule name field is short; longer titles are cut.
const RULE_NAME_MAX: int = 80
## Folder where the game reads loot filters on Windows (relative to the user profile).
const GAME_FILTERS_DIR: String = "AppData/LocalLow/Eleventh Hour Games/Last Epoch/Filters"

## Words of RarityCondition.rarity, shown in the preview.
const RARITY_NAMES: Dictionary = {"NORMAL": "normal", "MAGIC": "magic", "RARE": "rare", "EXALTED": "exalted"}


static func default_options() -> Dictionary:
	return {
		"stash": false,           # also the unequipped items
		"exact_base": true,       # craft and idol rules name the build's subtypes, not every base of the type
		"min_affixes": 2,         # wanted affixes a craft base needs (capped by the item's own count)
		"exalted": true,          # exalted items of the build's types with a wanted affix at exalted_tier+
		"exalted_tier": 6,
		"uniques": true,          # the build's uniques and set items
		"legendary": true,        # the build's legendaries: the unique with enough legendary potential
		"idol_one": false,        # idols with only one wanted affix
		"bases": false,           # the build's bases with any affixes
		"hide_others": true,      # hide every other normal, magic and rare item
		"hide_exalted": false,    # ...and other exalted items
	}


## Rule specs and notes from the build. A spec: {key, kind, title, outcome: "SHOW"|"HIDE", types: [base ids],
## subs: [subtype ids], affixes: [affix ids], min_same, min_tier, uniques: [unique ids], lp, rarity, emphasized}.
## Notes are translated lines about items that gave no rule.
static func plan(items: Dictionary, stash: Array, opts: Dictionary) -> Dictionary:
	var o: Dictionary = default_options()
	o.merge(opts, true)
	var sources: Array = []
	var slots: Array = items.keys()
	slots.sort_custom(func(a: Variant, b: Variant) -> bool: return _slot_rank(str(a)) < _slot_rank(str(b)))
	for slot: Variant in slots:
		sources.append(items[slot])
	if o["stash"]:
		sources.append_array(stash)

	var craft: Dictionary = {}     # base -> {subs, affixes, min_same}
	var idols: Dictionary = {}     # base -> {subs, affixes, min_same}
	var exalted: Dictionary = {}   # base -> affix ids
	var uniques: Array = []
	var legendary: Dictionary = {} # unique id -> wanted legendary affix count
	var notes: Array = []
	for item: Variant in sources:
		if not item is Dictionary or not (item as Dictionary).has("base"):
			continue
		var base: int = int(item["base"])
		if base < 0 or base > LAST_FILTERED_BASE:
			continue
		var wanted: Array = wanted_affixes(item)
		if item.has("unique"):
			var uid: int = int(item["unique"])
			if not uniques.has(uid):
				uniques.append(uid)
			if not wanted.is_empty() and str(GameData.unique(uid).get("legendaryType", "")) == "LegendaryPotential":
				legendary[uid] = maxi(int(legendary.get(uid, 0)), wanted.size())
				if not GameData.is_idol_type(base):
					_add_ids(exalted, base, wanted)
			continue
		if wanted.is_empty():
			var note: String = LE.t("%s: no wanted affixes, no rule.") % ItemCompare.item_title(item)
			if not notes.has(note):
				notes.append(note)
			continue
		var sub: int = int(item.get("sub", 0))
		var is_idol: bool = GameData.is_idol_type(base)
		var groups: Dictionary = idols if is_idol else craft
		var group: Dictionary = groups.get(base, {"subs": [], "affixes": [], "min_same": 99})
		if not (group["subs"] as Array).has(sub):
			group["subs"].append(sub)
		for id: int in wanted:
			if not (group["affixes"] as Array).has(id):
				group["affixes"].append(id)
		group["min_same"] = mini(int(group["min_same"]), wanted.size())
		groups[base] = group
		if not is_idol:
			_add_ids(exalted, base, wanted)

	var rules: Array = []
	if o["legendary"]:
		var by_lp: Dictionary = {}
		for uid: int in legendary:
			_add_ids(by_lp, int(legendary[uid]), [uid])
		var lps: Array = by_lp.keys()
		lps.sort()
		lps.reverse()
		for lp: int in lps:
			rules.append(_spec("legendary:%d" % lp, "legendary", LE.t("Build uniques with %d+ legendary potential") % lp,
				{"uniques": by_lp[lp], "lp": lp, "emphasized": true}))
	if o["exalted"]:
		var tier: int = clampi(int(o["exalted_tier"]), 1, 7)
		for base: int in _sorted_keys(exalted):
			rules.append(_spec("exalted:%d" % base, "exalted", LE.t("Exalted %s: a wanted affix of tier %d+") % [_type_name(base), tier],
				{"types": [base], "affixes": exalted[base], "min_same": 1, "min_tier": tier, "emphasized": true}))
	for base: int in _sorted_keys(craft):
		var group: Dictionary = craft[base]
		var need: int = clampi(mini(int(o["min_affixes"]), int(group["min_same"])), 1, 4)
		rules.append(_spec("craft:%d" % base, "craft", LE.t("%s: %d+ wanted affixes") % [_type_name(base), need],
			{"types": [base], "subs": group["subs"] if o["exact_base"] else [], "affixes": group["affixes"],
			"min_same": need, "emphasized": true}))
	for base: int in _sorted_keys(idols):
		var group: Dictionary = idols[base]
		var need: int = clampi(int(group["min_same"]), 1, 2)
		rules.append(_spec("idol:%d" % base, "idol", LE.t("%s: %d+ wanted affixes") % [_type_name(base), need],
			{"types": [base], "subs": group["subs"] if o["exact_base"] else [], "affixes": group["affixes"],
			"min_same": need, "emphasized": true}))
	if o["uniques"] and not uniques.is_empty():
		rules.append(_spec("unique", "unique", LE.t("Build uniques and set items"), {"uniques": uniques, "emphasized": true}))
	if o["idol_one"]:
		for base: int in _sorted_keys(idols):
			if int(idols[base]["min_same"]) >= 2:
				rules.append(_spec("idol_one:%d" % base, "idol_one", LE.t("%s: one wanted affix") % _type_name(base),
					{"types": [base], "subs": idols[base]["subs"] if o["exact_base"] else [], "affixes": idols[base]["affixes"], "min_same": 1}))
	if o["bases"]:
		for base: int in _sorted_keys(craft):
			rules.append(_spec("base:%d" % base, "base", LE.t("%s bases with any affixes") % _type_name(base),
				{"types": [base], "subs": craft[base]["subs"] if o["exact_base"] else []}))
	if o["hide_others"]:
		var rarity: String = "NORMAL MAGIC RARE EXALTED" if o["hide_exalted"] else "NORMAL MAGIC RARE"
		var title: String = LE.t("Hide other normal, magic, rare and exalted items") if o["hide_exalted"] \
			else LE.t("Hide other normal, magic and rare items")
		rules.append(_spec("hide", "hide", title, {"outcome": "HIDE", "rarity": rarity}))
	return {"rules": rules, "notes": notes}


## Affix ids of an item that can drop on items (no corrupted or unique-only affixes), without repeats.
static func wanted_affixes(item: Dictionary) -> Array:
	var ids: Array = []
	for entry: Variant in item.get("affixes", []):
		if not entry is Dictionary or bool(entry.get("corrupted", false)):
			continue
		var id: int = int(entry.get("id", -1))
		var affix: Dictionary = GameData.affix(id)
		if affix.is_empty() or SKIPPED_AFFIX_KINDS.has(str(affix.get("specialAffixType", ""))) or ids.has(id):
			continue
		ids.append(id)
	return ids


## The specs without the unchecked rules (`off_rules`: key -> true) and entries (`off_entries`: key -> {id: true},
## affix or unique ids); a rule left with no affixes or uniques it needs is dropped.
static func apply_choices(rules: Array, off_rules: Dictionary, off_entries: Dictionary) -> Array:
	var out: Array = []
	for spec: Dictionary in rules:
		if off_rules.has(spec["key"]):
			continue
		var off: Dictionary = off_entries.get(spec["key"], {})
		var copy: Dictionary = spec.duplicate(true)
		for field: String in ["affixes", "uniques"]:
			var had: bool = not (copy[field] as Array).is_empty()
			copy[field] = (copy[field] as Array).filter(func(id: Variant) -> bool: return not off.has(id))
			if had and (copy[field] as Array).is_empty():
				copy = {}
				break
		if copy.is_empty():
			continue
		if not (copy["affixes"] as Array).is_empty() and int(copy["min_same"]) > (copy["affixes"] as Array).size():
			copy["min_same"] = (copy["affixes"] as Array).size()
		out.append(copy)
	return out


## The game's ItemFilter XML. The game lists rules bottom-up: the first <Rule> is the lowest priority and has the
## largest Order, the last one has Order 0 (top of the in-game list).
static func to_xml(filter_name: String, description: String, rules: Array) -> String:
	var lines: PackedStringArray = []
	lines.append("<ItemFilter xmlns:i=\"http://www.w3.org/2001/XMLSchema-instance\">")
	lines.append("  <name>%s</name>" % _esc(filter_name))
	lines.append("  <filterIcon>0</filterIcon>")
	lines.append("  <filterIconColor>0</filterIconColor>")
	lines.append("  <description>%s</description>" % _esc(description) if description != "" else "  <description />")
	lines.append("  <lastModifiedInVersion>%s</lastModifiedInVersion>" % GAME_VERSION)
	lines.append("  <lootFilterVersion>%d</lootFilterVersion>" % LF_VERSION)
	if rules.is_empty():
		lines.append("  <rules />")
	else:
		lines.append("  <rules>")
		for order in range(rules.size() - 1, -1, -1):
			_rule_xml(lines, rules[order], order)
		lines.append("  </rules>")
	lines.append("</ItemFilter>")
	return "\n".join(lines) + "\n"


## File name for a filter name: characters Windows does not allow become "_".
static func file_name(filter_name: String) -> String:
	var clean: String = filter_name.strip_edges().validate_filename()
	return (clean if clean != "" else "Build filter") + ".xml"


## The game's filter folder on Windows, "" elsewhere or when the game was never started.
static func game_filters_dir() -> String:
	if OS.get_name() != "Windows":
		return ""
	var profile: String = OS.get_environment("USERPROFILE")
	if profile == "":
		return ""
	var dir: String = profile.replace("\\", "/").path_join(GAME_FILTERS_DIR)
	return dir if DirAccess.dir_exists_absolute(dir) else ""


## Readable lines of one spec (what the rule matches), for the preview.
static func describe(spec: Dictionary) -> String:
	var parts: PackedStringArray = []
	if not (spec["types"] as Array).is_empty():
		var names: PackedStringArray = []
		if (spec["subs"] as Array).is_empty():
			for base: int in spec["types"]:
				names.append(LE.t("any %s") % _type_name(base))
		else:
			for base: int in spec["types"]:
				for sub: int in spec["subs"]:
					names.append(GameData.display_name(GameData.item_sub(base, sub)))
		parts.append(", ".join(names))
	if spec["rarity"] != "":
		var rarities: PackedStringArray = []
		for word: String in str(spec["rarity"]).split(" ", false):
			rarities.append(LE.t(str(RARITY_NAMES.get(word, word))))
		parts.append(LE.t("rarity: %s") % ", ".join(rarities))
	if int(spec["lp"]) > 0:
		parts.append(LE.t("legendary potential %d+") % int(spec["lp"]))
	return "; ".join(parts)


static func affix_name(id: int) -> String:
	var affix: Dictionary = GameData.affix(id)
	return GameData.display_name(affix) if not affix.is_empty() else "#%d" % id


static func unique_name(id: int) -> String:
	var unique: Dictionary = GameData.unique(id)
	return GameData.display_name(unique) if not unique.is_empty() else "#%d" % id


static func _spec(key: String, kind: String, title: String, fields: Dictionary) -> Dictionary:
	var spec: Dictionary = {"key": key, "kind": kind, "title": title, "outcome": "SHOW", "types": [], "subs": [],
		"affixes": [], "min_same": 0, "min_tier": 0, "uniques": [], "lp": 0, "rarity": "", "emphasized": false}
	spec.merge(fields, true)
	return spec


static func _rule_xml(lines: PackedStringArray, spec: Dictionary, order: int) -> void:
	lines.append("    <Rule>")
	lines.append("      <type>%s</type>" % spec["outcome"])
	var conditions: PackedStringArray = []
	if spec["rarity"] != "":
		conditions.append("        <Condition i:type=\"RarityCondition\">")
		conditions.append("          <rarity>%s</rarity>" % spec["rarity"])
		conditions.append("        </Condition>")
	if not (spec["types"] as Array).is_empty():
		conditions.append("        <Condition i:type=\"SubTypeCondition\">")
		conditions.append("          <type>")
		for base: int in spec["types"]:
			conditions.append("            <EquipmentType>%s</EquipmentType>" % str(GameData.item_base(base).get("typeName", "")))
		conditions.append("          </type>")
		_int_list(conditions, "subTypes", spec["subs"], "          ")
		conditions.append("        </Condition>")
	if not (spec["affixes"] as Array).is_empty():
		var tier: int = int(spec["min_tier"])
		conditions.append("        <Condition i:type=\"AffixCondition\">")
		_int_list(conditions, "affixes", spec["affixes"], "          ")
		conditions.append("          <comparsion>%s</comparsion>" % ("MORE_OR_EQUAL" if tier > 0 else "ANY"))
		conditions.append("          <comparsionValue>%d</comparsionValue>" % tier)
		conditions.append("          <minOnTheSameItem>%d</minOnTheSameItem>" % maxi(int(spec["min_same"]), 1))
		conditions.append("          <combinedComparsion>ANY</combinedComparsion>")
		conditions.append("          <combinedComparsionValue>%d</combinedComparsionValue>" % maxi(tier, 1))
		conditions.append("          <advanced>%s</advanced>" % ("true" if tier > 0 else "false"))
		conditions.append("        </Condition>")
	if not (spec["uniques"] as Array).is_empty():
		conditions.append("        <Condition i:type=\"UniqueModifiersCondition\">")
		for uid: int in spec["uniques"]:
			conditions.append("          <Uniques>")
			conditions.append("            <UniqueId>%d</UniqueId>" % uid)
			conditions.append("            <Rolls />")
			conditions.append("          </Uniques>")
		conditions.append("        </Condition>")
	if int(spec["lp"]) > 0:
		conditions.append("        <Condition i:type=\"PotentialCondition\">")
		conditions.append("          <MinLegendaryPotential>%d</MinLegendaryPotential>" % int(spec["lp"]))
		for field: String in ["MaxLegendaryPotential", "MinWeaversWill", "MaxWeaversWill", "MinWeaversTouch", "MaxWeaversTouch",
				"MinForgingPotential", "MaxForgingPotential"]:
			conditions.append("          <%s i:nil=\"true\" />" % field)
		conditions.append("        </Condition>")
	if conditions.is_empty():
		lines.append("      <conditions />")
	else:
		lines.append("      <conditions>")
		lines.append_array(conditions)
		lines.append("      </conditions>")
	lines.append("      <recolor>false</recolor>")
	lines.append("      <color>0</color>")
	lines.append("      <isEnabled>true</isEnabled>")
	lines.append("      <levelDependent_deprecated>false</levelDependent_deprecated>")
	lines.append("      <minLvl_deprecated>0</minLvl_deprecated>")
	lines.append("      <maxLvl_deprecated>0</maxLvl_deprecated>")
	lines.append("      <emphasized>%s</emphasized>" % ("true" if spec["emphasized"] else "false"))
	var title: String = str(spec["title"]).left(RULE_NAME_MAX)
	lines.append("      <nameOverride>%s</nameOverride>" % _esc(title) if title != "" else "      <nameOverride />")
	lines.append("      <SoundId>0</SoundId>")
	lines.append("      <MapIconId>0</MapIconId>")
	lines.append("      <BeamOverride>false</BeamOverride>")
	lines.append("      <BeamSizeOverride>NONE</BeamSizeOverride>")
	lines.append("      <BeamColorOverride>0</BeamColorOverride>")
	lines.append("      <Order>%d</Order>" % order)
	lines.append("    </Rule>")


static func _int_list(lines: PackedStringArray, tag: String, ids: Array, indent: String) -> void:
	if ids.is_empty():
		lines.append("%s<%s />" % [indent, tag])
		return
	lines.append("%s<%s>" % [indent, tag])
	for id: Variant in ids:
		lines.append("%s  <int>%d</int>" % [indent, int(id)])
	lines.append("%s</%s>" % [indent, tag])


static func _esc(text: String) -> String:
	return text.xml_escape()


static func _type_name(base: int) -> String:
	return GameData.display_name(GameData.item_base(base))


static func _add_ids(groups: Dictionary, key: int, ids: Array) -> void:
	var list: Array = groups.get(key, [])
	for id: Variant in ids:
		if not list.has(id):
			list.append(id)
	groups[key] = list


static func _sorted_keys(groups: Dictionary) -> Array:
	var keys: Array = groups.keys()
	keys.sort()
	return keys


## Equipment slots in BuildMods order first, then the idols by their key.
static func _slot_rank(slot: String) -> String:
	var index: int = BuildMods.SLOTS.find(slot)
	return "%03d" % index if index >= 0 else "999" + slot
