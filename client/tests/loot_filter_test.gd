extends Node

## Loot filter: rules made from imported builds match the build's own items, the XML has the game's shape
## (ItemFiltering.ItemFilter: rules bottom-up, Order N-1 … 0), unchecked rules and entries are dropped.
## Run: Godot_console.exe --headless --path client res://tests/loot_filter_test.tscn
## `-- --out=<file>` also writes the filter of the last fixture there (to load it in the game by hand).

const FIXTURES: Array[String] = ["res://tests/fixtures/maxroll_char_palading.json", "res://tests/fixtures/maxroll_char_chudlet.json",
	"res://tests/fixtures/letools_A83KxJq5.json", "res://tests/fixtures/letools_Q0V6XDLG.json"]

var _failed: int = 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("LOOT FILTER TEST TIMEOUT")
		get_tree().quit(1))
	var xml: String = ""
	for fixture: String in FIXTURES:
		_load(fixture)
		xml = _check_build(fixture)
	_check_legendary()
	_check_choices()
	_check_options()
	_check(LootFilter.file_name(" a/b:c ") == "a_b_c.xml", "file name: %s" % LootFilter.file_name(" a/b:c "))
	_check(LootFilter.file_name("") == "Build filter.xml", "empty file name")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			file.store_string(xml)
			file.close()
	print("LOOT FILTER TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		print("FAIL: " + message)


func _load(fixture: String) -> void:
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	LEToolsImport.apply(Build, MaxrollImport.to_build(json) if fixture.contains("maxroll") else LEToolsImport.to_build(json))


func _check_build(fixture: String) -> String:
	var result: Dictionary = LootFilter.plan(Build.items, Build.stash, {"min_affixes": 2})
	var rules: Array = result["rules"]
	_check(not rules.is_empty(), "%s: no rules" % fixture)
	_check(rules.back()["outcome"] == "HIDE", "%s: the hide rule is not the last one" % fixture)
	var keys: Dictionary = {}
	for spec: Dictionary in rules:
		_check(not keys.has(spec["key"]), "%s: repeated rule key %s" % [fixture, spec["key"]])
		keys[spec["key"]] = true
		_check(str(spec["title"]) != "", "%s: rule %s has no title" % [fixture, spec["key"]])
		for id: int in spec["affixes"]:
			_check(not GameData.affix(id).is_empty(), "%s: unknown affix %d" % [fixture, id])
		for id: int in spec["uniques"]:
			_check(not GameData.unique(id).is_empty(), "%s: unknown unique %d" % [fixture, id])
		if not (spec["affixes"] as Array).is_empty():
			_check(int(spec["min_same"]) >= 1 and int(spec["min_same"]) <= (spec["affixes"] as Array).size(),
				"%s: rule %s needs %d of %d affixes" % [fixture, spec["key"], spec["min_same"], (spec["affixes"] as Array).size()])

	# every regular item and idol of the build is shown by a craft / idol rule, every unique by the unique rule
	var any_unique: bool = false
	var any_idol: bool = false
	for slot: Variant in Build.items:
		var item: Dictionary = Build.items[slot]
		var base: int = int(item.get("base", -1))
		if base < 0 or base > LootFilter.LAST_FILTERED_BASE:
			continue
		if item.has("unique"):
			any_unique = true
			_check(_shown_by(rules, "unique", item), "%s: unique %s not shown" % [fixture, ItemCompare.item_title(item)])
			continue
		if LootFilter.wanted_affixes(item).is_empty():
			continue
		var idol: bool = GameData.is_idol_type(base)
		any_idol = any_idol or idol
		_check(_shown_by(rules, "idol" if idol else "craft", item), "%s: %s (%s) not shown by its rule" % [fixture, ItemCompare.item_title(item), slot])
	_check(any_unique or not fixture.contains("palading"), "%s: the fixture has no uniques" % fixture)
	_check(any_idol or not fixture.contains("maxroll"), "%s: the fixture has no idols" % fixture)

	var xml: String = LootFilter.to_xml("Test & <filter>", "", rules)
	_check_xml(fixture, xml, rules)
	return xml


## The rule of `kind` that would show `item` (base, subtype and enough wanted affixes, or the unique id).
func _shown_by(rules: Array, kind: String, item: Dictionary) -> bool:
	for spec: Dictionary in rules:
		if spec["kind"] != kind:
			continue
		if kind == "unique":
			if (spec["uniques"] as Array).has(int(item["unique"])):
				return true
			continue
		if not (spec["types"] as Array).has(int(item["base"])):
			continue
		if not (spec["subs"] as Array).is_empty() and not (spec["subs"] as Array).has(int(item.get("sub", 0))):
			continue
		var hits: int = 0
		for id: int in LootFilter.wanted_affixes(item):
			if (spec["affixes"] as Array).has(id):
				hits += 1
		if hits >= int(spec["min_same"]):
			return true
	return false


func _check_xml(fixture: String, xml: String, rules: Array) -> void:
	var parser: XMLParser = XMLParser.new()
	_check(parser.open_buffer(xml.to_utf8_buffer()) == OK, "%s: XML does not open" % fixture)
	var orders: Array = []
	var stack: Array = []
	var text_of: Dictionary = {}
	var types: Array = []
	var element_types: Array = []
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag: String = parser.get_node_name()
				if tag == "Condition":
					types.append(parser.get_named_attribute_value_safe("i:type"))
				if not parser.is_empty():
					stack.append(tag)
			XMLParser.NODE_ELEMENT_END:
				stack.pop_back()
			XMLParser.NODE_TEXT:
				if stack.is_empty():
					continue
				var text: String = parser.get_node_data().strip_edges()
				if text == "":
					continue
				var tag: String = stack.back()
				text_of[tag] = text
				if tag == "Order":
					orders.append(int(text))
				elif tag == "EquipmentType":
					element_types.append(text)
	_check(stack.is_empty(), "%s: unbalanced XML" % fixture)
	_check(text_of.get("name", "") == "Test &amp; &lt;filter&gt;" or text_of.get("name", "") == "Test & <filter>", "%s: name %s" % [fixture, text_of.get("name", "")])
	_check(int(text_of.get("lootFilterVersion", 0)) == LootFilter.LF_VERSION, "%s: lootFilterVersion" % fixture)
	var expected: Array = []
	for i in range(rules.size() - 1, -1, -1):
		expected.append(i)
	_check(orders == expected, "%s: Order values %s, expected %s" % [fixture, str(orders), str(expected)])
	for t: String in types:
		_check(t in ["RarityCondition", "SubTypeCondition", "AffixCondition", "UniqueModifiersCondition", "PotentialCondition"],
			"%s: condition type %s" % [fixture, t])
	var valid: Array = []
	for base in range(LootFilter.LAST_FILTERED_BASE + 1):
		valid.append(str(GameData.item_base(base).get("typeName", "")))
	for t: String in element_types:
		_check(t != "" and valid.has(t), "%s: EquipmentType %s" % [fixture, t])
	_check(xml.find("<type>HIDE</type>") < xml.find("<type>SHOW</type>"), "%s: the hide rule must be the first <Rule> (bottom of the list)" % fixture)


## A unique with affixes: a legendary rule with its legendary potential and its affixes in the exalted rule of its type.
func _check_legendary() -> void:
	var unique_id: int = -1
	var base: int = -1
	for unique: Dictionary in GameData.uniques:
		if str(unique.get("legendaryType", "")) == "LegendaryPotential" and int(unique.get("baseType", -1)) == 0:
			unique_id = int(unique["uniqueID"])
			base = 0
			break
	var affixes: Array = GameData.affixes_for_type(base)
	var item: Dictionary = {"base": base, "sub": 0, "unique": unique_id, "affixes": [
		{"id": int(affixes[0]["affixId"]), "tier": 7, "roll": 255, "kind": "prefix", "index": 0},
		{"id": int(affixes[1]["affixId"]), "tier": 6, "roll": 255, "kind": "prefix", "index": 1},
		{"id": int(affixes[2]["affixId"]), "tier": 6, "roll": 0, "kind": "suffix", "index": 5, "corrupted": true}]}
	var rules: Array = LootFilter.plan({"helmet": item}, [], {})["rules"]
	var legendary: Dictionary = _rule(rules, "legendary:2")
	_check(not legendary.is_empty() and legendary["uniques"] == [unique_id], "legendary rule: %s" % str(legendary))
	var exalted: Dictionary = _rule(rules, "exalted:0")
	_check(not exalted.is_empty() and exalted["affixes"] == [int(affixes[0]["affixId"]), int(affixes[1]["affixId"])],
		"exalted rule of the legendary (corrupted affix left out): %s" % str(exalted))
	_check(not exalted.is_empty() and (exalted["subs"] as Array).is_empty() and int(exalted["min_tier"]) == 6, "exalted rule: any helmet, T6+")
	var xml: String = LootFilter.to_xml("x", "", rules)
	_check(xml.contains("<MinLegendaryPotential>2</MinLegendaryPotential>"), "PotentialCondition missing")
	_check(xml.contains("<MaxLegendaryPotential i:nil=\"true\" />"), "PotentialCondition nil fields missing")
	_check(xml.contains("<comparsion>MORE_OR_EQUAL</comparsion>") and xml.contains("<advanced>true</advanced>"), "exalted affix condition")


func _check_choices() -> void:
	var affixes: Array = GameData.affixes_for_type(0)
	var ids: Array = [int(affixes[0]["affixId"]), int(affixes[1]["affixId"]), int(affixes[2]["affixId"])]
	var item: Dictionary = {"base": 0, "sub": 1, "affixes": []}
	for i in range(3):
		item["affixes"].append({"id": ids[i], "tier": 5, "roll": 100, "kind": "prefix" if i < 2 else "suffix", "index": i})
	var rules: Array = LootFilter.plan({"helmet": item}, [], {"min_affixes": 3})["rules"]
	_check(_rule(rules, "craft:0")["min_same"] == 3, "craft rule needs 3 affixes")
	var out: Array = LootFilter.apply_choices(rules, {}, {"craft:0": {ids[0]: true}})
	_check(_rule(out, "craft:0")["affixes"] == [ids[1], ids[2]] and _rule(out, "craft:0")["min_same"] == 2,
		"an unchecked affix is dropped and min_same capped: %s" % str(_rule(out, "craft:0")))
	_check(_rule(rules, "craft:0")["affixes"].size() == 3, "apply_choices must not change the plan")
	out = LootFilter.apply_choices(rules, {}, {"craft:0": {ids[0]: true, ids[1]: true, ids[2]: true}})
	_check(_rule(out, "craft:0").is_empty(), "a rule without affixes is dropped")
	out = LootFilter.apply_choices(rules, {"hide": true}, {})
	_check(_rule(out, "hide").is_empty() and out.size() == rules.size() - 1, "an unchecked rule is dropped")


func _check_options() -> void:
	var affixes: Array = GameData.affixes_for_type(21)
	var ring: Dictionary = {"base": 21, "sub": 2, "affixes": [{"id": int(affixes[0]["affixId"]), "tier": 4, "roll": 1, "kind": "prefix", "index": 0}]}
	var stash_ring: Dictionary = {"base": 21, "sub": 5, "affixes": [{"id": int(affixes[1]["affixId"]), "tier": 4, "roll": 1, "kind": "prefix", "index": 0}]}
	var rules: Array = LootFilter.plan({"ring1": ring}, [stash_ring], {"exact_base": false, "exalted": false, "hide_others": false, "bases": true})["rules"]
	_check(_rule(rules, "craft:21")["min_same"] == 1 and (_rule(rules, "craft:21")["subs"] as Array).is_empty(), "one-affix ring, any base")
	_check(_rule(rules, "exalted:21").is_empty() and _rule(rules, "hide").is_empty(), "options off")
	_check(not _rule(rules, "base:21").is_empty(), "bases rule")
	rules = LootFilter.plan({"ring1": ring}, [stash_ring], {"stash": true, "hide_exalted": true})["rules"]
	_check(_rule(rules, "craft:21")["subs"] == [2, 5], "stash ring subtype: %s" % str(_rule(rules, "craft:21")))
	_check(_rule(rules, "hide")["rarity"] == "NORMAL MAGIC RARE EXALTED", "hide exalted")


func _rule(rules: Array, key: String) -> Dictionary:
	for spec: Dictionary in rules:
		if spec["key"] == key:
			return spec
	return {}
