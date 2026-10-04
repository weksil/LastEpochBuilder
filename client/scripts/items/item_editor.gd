class_name ItemEditor extends PanelContainer

## Edits one equipment slot of Build.items (docs/UI.md "Items"). Controls live in item_editor.tscn.

const EMPTY_ID: int = 99999
const UNIQUE_EMPTY_ID: int = 99998
const AFFIX_ROWS: Array[String] = ["Prefix1", "Prefix2", "Suffix1", "Suffix2"]
const ONE_HANDED_TYPES: Array[String] = [
	"ONE_HANDED_AXE", "ONE_HANDED_DAGGER", "ONE_HANDED_MACES", "ONE_HANDED_SCEPTRE", "ONE_HANDED_SWORD", "WAND", "ONE_HANDED_FIST"]
const SLOT_TYPES: Dictionary = {
	"helmet": ["HELMET"], "body": ["BODY_ARMOR"], "belt": ["BELT"], "boots": ["BOOTS"], "gloves": ["GLOVES"],
	"amulet": ["AMULET"], "ring1": ["RING"], "ring2": ["RING"], "relic": ["RELIC"],
	"offhand": ["SHIELD", "QUIVER", "CATALYST"],
	"altar": ["IDOL_ALTAR"],
}

@export var implicit_row_scene: PackedScene

var _slot: String = ""
var _filling: bool = false
var _shown_item: Dictionary = {}


func _ready() -> void:
	%UniqueSelect.item_selected.connect(_on_unique_selected)
	%BaseSelect.item_selected.connect(_on_base_selected)
	%SubSelect.item_selected.connect(_on_sub_selected)
	%ClearButton.pressed.connect(_on_clear)
	for row_name: String in AFFIX_ROWS:
		var row: Node = %Affixes.get_node(row_name)
		row.get_node("Top/KindLabel").text = tr("Prefix") if row_name.begins_with("Prefix") else tr("Suffix")
		row.get_node("Top/AffixSelect").item_selected.connect(func(_i: int) -> void: _store_affixes(true))
		row.get_node("Top/TierSpin").value_changed.connect(func(_v: float) -> void: _store_affixes(false))
		row.get_node("Bottom/RollSlider").value_changed.connect(func(_v: float) -> void: _store_affixes(false))
	Build.changed.connect(_on_build_changed)


func edit_slot(slot: String, title: String) -> void:
	_slot = slot
	%SlotTitle.text = title
	_fill()


func _item() -> Dictionary:
	return Build.items.get(_slot, {})


func _on_build_changed() -> void:
	if _slot != "" and not _filling and _item() != _shown_item:
		_fill.call_deferred()


# --- filling controls from Build ---------------------------------------------------

func _fill() -> void:
	_filling = true
	var item: Dictionary = _item()
	_shown_item = item.duplicate(true)
	var unique_id: int = int(item.get("unique", UNIQUE_EMPTY_ID))
	var base_id: int = int(item.get("base", EMPTY_ID))
	var base: Dictionary = GameData.item_base(base_id) if item.has("base") else {}

	# Fill unique select
	%UniqueSelect.clear()
	%UniqueSelect.add_item(tr("— regular item —"), UNIQUE_EMPTY_ID)
	var uniques: Array = GameData.uniques
	var unique_items: Array = []
	for u: Dictionary in uniques:
		var u_base: Dictionary = GameData.item_base(int(u.get("baseType", -1)))
		if _base_fits_slot(u_base):
			unique_items.append(u)
	unique_items.sort_custom(func(a, b): return str(GameData.display_name(a)) < str(GameData.display_name(b)))
	for u: Dictionary in unique_items:
		%UniqueSelect.add_item(GameData.display_name(u), int(u["uniqueID"]))
	%UniqueSelect.select(maxi(0, %UniqueSelect.get_item_index(unique_id)))

	%BaseSelect.clear()
	%BaseSelect.add_item(tr("— empty —"), EMPTY_ID)
	for b: Dictionary in GameData.item_bases:
		if _base_fits_slot(b):
			%BaseSelect.add_item(GameData.display_name(b), int(b["baseTypeID"]))
	%BaseSelect.select(maxi(0, %BaseSelect.get_item_index(base_id)))

	%SubSelect.clear()
	for sub: Dictionary in base.get("subItems", []):
		if _sub_allowed(sub):
			%SubSelect.add_item(GameData.display_name(sub), int(sub["subTypeID"]))
	if not base.is_empty():
		%SubSelect.select(maxi(0, %SubSelect.get_item_index(int(item.get("sub", 0)))))

	var has_unique: bool = unique_id != UNIQUE_EMPTY_ID
	_fill_implicits(item)
	if has_unique:
		_fill_unique(item, unique_id)
	_fill_affixes(item, base)

	var has_item: bool = not base.is_empty() or has_unique
	var is_idol: bool = IdolGrid.is_idol_key(_slot)
	%AffixesTitle.text = tr("Affixes (1 prefix, 1 suffix)") if is_idol else tr("Affixes (2 prefixes, 2 suffixes)")
	if has_unique:
		var unique: Dictionary = GameData.unique(unique_id)
		if str(unique.get("legendaryType", "")) == "LegendaryPotential":
			%AffixesTitle.text = tr("Legendary affixes")

	%BaseSelect.disabled = has_unique
	%SubSelect.disabled = has_unique
	%EmptyHint.visible = not has_item
	for node_name: String in ["%SubRow", "%AffixesTitle", "%Affixes", "%ClearButton"]:
		get_node(node_name).visible = has_item
	%ImplicitsTitle.visible = has_item and %Implicits.get_child_count() > 0
	%Implicits.visible = has_item
	%UniqueTitle.visible = has_unique
	%UniqueMods.visible = has_unique
	%UniqueText.visible = has_unique
	_filling = false
	_update_values()


func _base_fits_slot(base: Dictionary) -> bool:
	var type_name: String = str(base.get("typeName", ""))
	if IdolGrid.is_idol_key(_slot):
		var a: Vector2i = IdolGrid.anchor(_slot)
		return GameData.is_idol_type(int(base.get("type", -1))) 			and IdolGrid.fits(Build.items, a.x, a.y, int(base["baseTypeID"]), _slot)
	if _slot == "weapon":
		return bool(base.get("isWeapon", false)) and type_name != "CROSSBOW"
	if _slot == "offhand" and type_name in ONE_HANDED_TYPES:
		return true
	return type_name in SLOT_TYPES.get(_slot, [])


## Non-legacy subtypes usable by the current class.
func _sub_allowed(sub: Dictionary) -> bool:
	if int(sub.get("isLegacySubType", 0)) != 0:
		return false
	var classes: Array = sub.get("classRequirement", [])
	return classes.is_empty() or classes.has(str(GameData.get_class_data(Build.class_id).get("className", "")))


func _fill_implicits(item: Dictionary) -> void:
	for child: Node in %Implicits.get_children():
		%Implicits.remove_child(child)
		child.queue_free()
	var sub: Dictionary = GameData.item_sub(int(item.get("base", -1)), int(item.get("sub", -1)))
	var rolls: Array = item.get("implicit_rolls", [])
	var implicits: Array = sub.get("implicits", [])
	for j in range(implicits.size()):
		var imp: Dictionary = implicits[j]
		var row: Node = implicit_row_scene.instantiate()
		%Implicits.add_child(row)
		row.get_node("%NameLabel").text = _prop_title(imp)
		var slider: HSlider = row.get_node("%RollSlider")
		slider.visible = float(imp.get("maxValue", 0.0)) > float(imp.get("value", 0.0))
		slider.set_value_no_signal(float(rolls[j]) if j < rolls.size() else 255.0)
		slider.value_changed.connect(_on_implicit_roll.bind(j))


func _fill_unique(item: Dictionary, unique_id: int) -> void:
	for child: Node in %UniqueMods.get_children():
		%UniqueMods.remove_child(child)
		child.queue_free()

	var unique: Dictionary = GameData.unique(unique_id)
	var mods: Array = unique.get("mods", [])
	var unique_rolls: Array = item.get("unique_rolls", [])

	for mod: Dictionary in mods:
		if int(mod.get("hideInTooltip", 0)) != 0:
			continue
		var roll_id: int = int(mod.get("rollID", 0))
		var row: Node = implicit_row_scene.instantiate()
		%UniqueMods.add_child(row)
		row.get_node("%NameLabel").text = _prop_title(mod)
		var slider: HSlider = row.get_node("%RollSlider")
		var can_roll: int = int(mod.get("canRoll", 0))
		var max_val: float = float(mod.get("maxValue", 0.0))
		var curr_val: float = float(mod.get("value", 0.0))
		slider.visible = can_roll == 1 and max_val > curr_val
		slider.set_value_no_signal(float(unique_rolls[roll_id]) if roll_id < unique_rolls.size() else 255.0)
		slider.value_changed.connect(_on_unique_roll.bind(roll_id))

	# Set unique text (descriptions and set info)
	var text_lines: PackedStringArray = []
	var descriptions: Array = unique.get("tooltipDescriptions", [])
	for desc_obj: Dictionary in descriptions:
		text_lines.append(str(desc_obj.get("description", "")))

	if int(unique.get("isSetItem", 0)) != 0:
		text_lines.append("")
		var set_id: int = int(unique.get("setID", -1))
		var set_data: Dictionary = GameData.set_data(set_id)
		var set_name: String = set_data.get("setName", "")
		text_lines.append(tr("Set \"%s\":") % set_name)
		var set_descriptions: Array = set_data.get("tooltipDescriptions", [])
		for i in range(set_descriptions.size()):
			var desc_obj: Dictionary = set_descriptions[i]
			var req_str: String = ""
			if "setRequirement" in desc_obj:
				req_str = " (%d)" % int(desc_obj["setRequirement"])
			text_lines.append(req_str + " " + str(desc_obj.get("description", "")))

	# tooltip templates "[min,max,rollID]" -> "min–max"
	var template := RegEx.new()
	template.compile("\\[(-?[0-9.]+),(-?[0-9.]+),[0-9]+\\]")
	%UniqueText.text = template.sub("\n".join(text_lines), "$1–$2", true)


func _fill_affixes(item: Dictionary, base: Dictionary) -> void:
	var stored: Array = item.get("affixes", [])
	var options: Dictionary = {"PREFIX": [], "SUFFIX": []}
	if not base.is_empty():
		var class_name_str: String = str(GameData.get_class_data(Build.class_id).get("className", ""))
		for aff: Dictionary in GameData.affixes_for_type(int(base.get("type", -1)), class_name_str):
			if options.has(str(aff.get("type", ""))):
				options[str(aff["type"])].append(aff)
	for r in range(AFFIX_ROWS.size()):
		var row: Node = %Affixes.get_node(AFFIX_ROWS[r])
		var select: OptionButton = row.get_node("Top/AffixSelect")
		var kind: String = "PREFIX" if AFFIX_ROWS[r].begins_with("Prefix") else "SUFFIX"
		select.clear()
		select.add_item(tr("— none —"), EMPTY_ID)
		for aff: Dictionary in options[kind]:
			select.add_item(str(aff.get("name", "")), int(aff["affixId"]))
		var entry: Dictionary = {}
		for e: Dictionary in stored:
			if int(e.get("index", -1)) == r:
				entry = e
		var affix_id: int = int(entry.get("id", EMPTY_ID))
		select.select(maxi(0, select.get_item_index(affix_id)))
		var tiers: int = GameData.affix(affix_id).get("tiers", []).size()
		var spin: SpinBox = row.get_node("Top/TierSpin")
		spin.max_value = maxi(1, tiers)
		spin.set_value_no_signal(float(entry.get("tier", mini(5, maxi(1, tiers)))))
		row.get_node("Bottom/RollSlider").set_value_no_signal(float(entry.get("roll", 255)))
		for path: String in ["Top/TierLabel", "Top/TierSpin", "Bottom"]:
			row.get_node(path).visible = affix_id != EMPTY_ID
		# idols have one prefix and one suffix
		row.visible = not (IdolGrid.is_idol_key(_slot) and (r == 1 or r == 3))


# --- storing user edits ---------------------------------------------------------------

func _on_unique_selected(index: int) -> void:
	if _filling:
		return
	var unique_id: int = %UniqueSelect.get_item_id(index)
	if unique_id == UNIQUE_EMPTY_ID:
		var item: Dictionary = _item().duplicate(true)
		item.erase("unique")
		item.erase("unique_rolls")
		_commit(item)
	else:
		var unique: Dictionary = GameData.unique(unique_id)
		var base_type_id: int = int(unique.get("baseType", -1))
		var sub_types: Array = unique.get("subTypes", [0])
		var sub_type_id: int = int(sub_types[0]) if not sub_types.is_empty() else 0

		# Create unique_rolls array with 255 for each mod's rollID
		var unique_rolls: Array = []
		var mods: Array = unique.get("mods", [])
		var max_roll_id: int = -1
		for mod: Dictionary in mods:
			var roll_id: int = int(mod.get("rollID", 0))
			max_roll_id = maxi(max_roll_id, roll_id)
		for i in range(max_roll_id + 1):
			unique_rolls.append(255)

		var item: Dictionary = _item().duplicate(true)
		var affixes: Array = item.get("affixes", [])
		var new_item: Dictionary = _new_item(base_type_id, sub_type_id, [])
		new_item.merge({
			"unique": unique_id,
			"unique_rolls": unique_rolls,
			"affixes": affixes,
		}, true)
		_commit(new_item)
	_fill()


func _on_unique_roll(value: float, roll_id: int) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	var unique_rolls: Array = item.get("unique_rolls", [])
	while unique_rolls.size() <= roll_id:
		unique_rolls.append(255)
	unique_rolls[roll_id] = int(value)
	item["unique_rolls"] = unique_rolls
	_commit(item)


func _on_base_selected(index: int) -> void:
	if _filling:
		return
	var base_id: int = %BaseSelect.get_item_id(index)
	if base_id == EMPTY_ID:
		Build.clear_item(_slot)
	else:
		var base: Dictionary = GameData.item_base(base_id)
		var sub_id: int = 0
		for sub: Dictionary in base.get("subItems", []):
			if _sub_allowed(sub):
				sub_id = int(sub["subTypeID"])
				break
		# Clear unique when manually changing base
		var item: Dictionary = _new_item(base_id, sub_id, [])
		Build.set_item(_slot, item)
	_fill()


func _on_sub_selected(index: int) -> void:
	if _filling:
		return
	var item: Dictionary = _item()
	Build.set_item(_slot, _new_item(int(item.get("base", 0)), %SubSelect.get_item_id(index), item.get("affixes", [])))
	_fill()


func _new_item(base_id: int, sub_id: int, affixes: Array) -> Dictionary:
	var rolls: Array = []
	for _imp: Variant in GameData.item_sub(base_id, sub_id).get("implicits", []):
		rolls.append(255)
	return {"base": base_id, "sub": sub_id, "implicit_rolls": rolls, "affixes": affixes.duplicate(true)}


func _on_implicit_roll(value: float, index: int) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	var rolls: Array = item.get("implicit_rolls", [])
	while rolls.size() <= index:
		rolls.append(255)
	rolls[index] = int(value)
	item["implicit_rolls"] = rolls
	_commit(item)


func _on_clear() -> void:
	Build.clear_item(_slot)
	_fill()


## Reads the four affix rows into Build. refill = true when the affix choice changed (tier range may differ).
func _store_affixes(refill: bool) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	var affixes: Array = []
	for r in range(AFFIX_ROWS.size()):
		var row: Node = %Affixes.get_node(AFFIX_ROWS[r])
		var affix_id: int = row.get_node("Top/AffixSelect").get_selected_id()
		if affix_id == EMPTY_ID or not row.visible:
			continue
		var tiers: int = GameData.affix(affix_id).get("tiers", []).size()
		affixes.append({
			"id": affix_id, "index": r, "kind": "prefix" if r < 2 else "suffix",
			"tier": clampi(int(row.get_node("Top/TierSpin").value), 1, maxi(1, tiers)),
			"roll": int(row.get_node("Bottom/RollSlider").value),
		})
	item["affixes"] = affixes
	_commit(item)
	if refill:
		_fill()


func _commit(item: Dictionary) -> void:
	_shown_item = item.duplicate(true)
	Build.set_item(_slot, item)
	_update_values()


# --- value labels ----------------------------------------------------------------------

func _update_values() -> void:
	var item: Dictionary = _item()
	var unique_id: int = int(item.get("unique", UNIQUE_EMPTY_ID))

	# Update unique mod values
	if unique_id != UNIQUE_EMPTY_ID:
		var unique: Dictionary = GameData.unique(unique_id)
		var mods: Array = unique.get("mods", [])
		var unique_rolls: Array = item.get("unique_rolls", [])
		var unique_mod_rows: Array = %UniqueMods.get_children()
		var mod_row_index: int = 0
		for mod: Dictionary in mods:
			if int(mod.get("hideInTooltip", 0)) != 0:
				continue
			if mod_row_index >= unique_mod_rows.size():
				break
			var roll_id: int = int(mod.get("rollID", 0))
			var roll: int = int(unique_rolls[roll_id]) if roll_id < unique_rolls.size() else 255
			var v: float = AffixMath.unique_value(mod, roll)
			unique_mod_rows[mod_row_index].get_node("%ValueLabel").text = _format(mod, v)
			unique_mod_rows[mod_row_index].get_node("%RollSlider").set_value_no_signal(float(roll))
			mod_row_index += 1

	# Implicits of the base apply to regular and unique items
	var base: Dictionary = GameData.item_base(int(item.get("base", -1)))
	var sub: Dictionary = GameData.item_sub(int(item.get("base", -1)), int(item.get("sub", -1)))
	var rolls: Array = item.get("implicit_rolls", [])
	var implicits: Array = sub.get("implicits", [])
	var rows: Array = %Implicits.get_children()
	for j in range(mini(rows.size(), implicits.size())):
		var imp: Dictionary = implicits[j]
		var roll: int = int(rolls[j]) if j < rolls.size() else 255
		var v: float = AffixMath.roll_value(float(imp["value"]), float(imp.get("maxValue", imp["value"])),
			str(imp.get("rounding", "Integer")), str(imp.get("modType", "ADDED")), roll, 0.0)
		rows[j].get_node("%ValueLabel").text = _format(imp, v)

	var used: Array[int] = []
	for entry: Dictionary in item.get("affixes", []):
		var index: int = int(entry.get("index", 0))
		var aff: Dictionary = GameData.affix(int(entry["id"]))
		var tiers: Array = aff.get("tiers", [])
		var tier: int = int(entry.get("tier", 1))
		if index < 0 or index >= AFFIX_ROWS.size() or tier < 1 or tier > tiers.size():
			continue
		used.append(index)
		var m: float = AffixMath.effect_modifier(float(base.get("affixEffectModifier", 0.0)), float(aff.get("standardAffixEffectModifier", 0.0)))
		var lines: PackedStringArray = []
		var props: Array = aff.get("properties", [])
		var ranges: Array = tiers[tier - 1].get("rolls", [])
		for j in range(mini(props.size(), ranges.size())):
			var prop: Dictionary = props[j]
			var v: float = AffixMath.roll_value(float(ranges[j][0]), float(ranges[j][1]), str(prop.get("rounding", "Integer")),
				str(prop.get("modType", "ADDED")), int(entry.get("roll", 255)), m)
			lines.append("%s %s" % [_format(prop, v), _prop_title(prop)])
		%Affixes.get_node(AFFIX_ROWS[index]).get_node("Bottom/ValueLabel").text = "\n".join(lines)
	for r in range(AFFIX_ROWS.size()):
		if not used.has(r):
			%Affixes.get_node(AFFIX_ROWS[r]).get_node("Bottom/ValueLabel").text = ""


func _prop_title(prop: Dictionary) -> String:
	var tags: Array = prop.get("tagNames", [])
	var title: String = str(prop.get("propertyName", ""))
	if not tags.is_empty():
		title += " (%s)" % ", ".join(PackedStringArray(tags))
	return title


## INCREASED/MORE and fractional ADDED values (resistances, crit multiplier…) are shown as percentages.
func _format(prop: Dictionary, v: float) -> String:
	var mod_type: String = str(prop.get("modType", "ADDED"))
	var rounding: String = str(prop.get("rounding", "Integer"))
	var pct: bool = mod_type != "ADDED" or rounding == "Hundredth" or rounding == "Thousandth"
	var text: String = LE.fmt_pct(v) if pct else LE.fmt_num(v)
	if mod_type == "MORE":
		text += " more"
	return ("+" if v > 0.0 else "") + text
