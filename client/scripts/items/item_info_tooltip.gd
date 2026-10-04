class_name ItemInfoTooltip extends VBoxContainer

## Tooltip of a search-list entry (unique, base item or affix): what the entry is and its mods (item_info_tooltip.tscn).
## The show_* functions are called before the tooltip enters the tree, so the nodes are reached by unique names only.


## A unique or set item with its base mods at their full ranges.
func show_unique(unique_id: int) -> void:
	var unique: Dictionary = GameData.unique(unique_id)
	var is_set: bool = int(unique.get("isSetItem", 0)) != 0
	var base_id: int = int(unique.get("baseType", -1))
	var sub_types: Array = unique.get("subTypes", [])
	var sub: Dictionary = GameData.item_sub(base_id, int(sub_types[0])) if not sub_types.is_empty() else {}
	var title: Label = get_node("%Title")
	title.theme_type_variation = &"RaritySet" if is_set else &"RarityUnique"
	_set_text("%Title", GameData.display_name(unique))
	var sub_name: String = GameData.display_name(sub)
	_set_text("%Kind", (tr("Set item · %s") if is_set else tr("Unique item · %s")) % sub_name)
	var level: int = ItemCompare.unique_level(unique)
	_set_text("%Requirement", tr("Requires level %d") % level if level > 0 else "")
	_set_text("%Implicits", "\n".join(_range_lines(sub.get("implicits", []))))

	var mods: Array = []
	for mod: Dictionary in unique.get("mods", []):
		if int(mod.get("hideInTooltip", 0)) == 0:
			mods.append(mod)
	_set_text("%Mods", "\n".join(_range_lines(mods)))

	var description: PackedStringArray = []
	for desc_obj: Dictionary in unique.get("tooltipDescriptions", []):
		description.append(str(desc_obj.get("description", "")))
	var text: String = ItemCompare.expand_template("\n".join(description))
	_set_text("%Description", text)
	(get_node("%SetBox") as SetBlock).show_set(int(unique.get("setID", -1)) if is_set else -1)
	var lore: Variant = unique.get("loreText")
	_set_text("%Lore", str(lore) if lore is String else "")
	_update_separator()


## A base item (one subtype of a base type) with its implicits.
func show_sub(base_id: int, sub_id: int) -> void:
	var base: Dictionary = GameData.item_base(base_id)
	var sub: Dictionary = GameData.item_sub(base_id, sub_id)
	var title: Label = get_node("%Title")
	title.theme_type_variation = &"RarityNormal"
	_set_text("%Title", GameData.display_name(sub))
	_set_text("%Kind", tr("Base item · %s") % GameData.display_name(base))
	var level: int = int(sub.get("levelRequirement", 0))
	var requirement: String = tr("Requires level %d") % level if level > 0 else ""
	var classes: Array = sub.get("classRequirement", [])
	if not classes.is_empty():
		requirement += " · " + ", ".join(PackedStringArray(classes))
	_set_text("%Requirement", requirement)
	_set_text("%Implicits", "\n".join(_range_lines(sub.get("implicits", []))))
	_set_text("%Mods", "")
	_set_text("%Description", "")
	_set_text("%Lore", "")
	(get_node("%SetBox") as SetBlock).show_set(-1)
	_update_separator()


## An affix with the value range of every tier.
func show_affix(affix_id: int) -> void:
	var affix: Dictionary = GameData.affix(affix_id)
	var tiers: Array = affix.get("tiers", [])
	var title: Label = get_node("%Title")
	title.theme_type_variation = &"RarityAffix"
	_set_text("%Title", str(affix.get("name", "")))
	var kind: String = tr("Prefix") if str(affix.get("type", "")) == "PREFIX" else tr("Suffix")
	_set_text("%Kind", kind + " · " + tr("%d tiers") % tiers.size())
	var level: int = int(affix.get("levelRequirement", 0))
	_set_text("%Requirement", tr("Requires level %d") % level if level > 0 else "")
	_set_text("%Implicits", "")
	var props: Array = affix.get("properties", [])
	var lines: PackedStringArray = []
	for tier: Dictionary in tiers:
		var rolls: Array = tier.get("rolls", [])
		var parts: PackedStringArray = []
		for j in range(mini(props.size(), rolls.size())):
			var prop: Dictionary = props[j]
			parts.append("%s %s" % [ItemCompare.format_range(prop, float(rolls[j][0]), float(rolls[j][1])), ItemCompare.prop_title(prop)])
		lines.append("T%d: %s" % [int(tier.get("tier", 0)), ", ".join(parts)])
	_set_text("%Mods", "\n".join(lines))
	_set_text("%Description", "")
	_set_text("%Lore", "")
	(get_node("%SetBox") as SetBlock).show_set(-1)
	_update_separator()


## "+10–20% Fire Resistance" for every property of `props` (value … maxValue).
func _range_lines(props: Array) -> PackedStringArray:
	var lines: PackedStringArray = []
	for prop: Dictionary in props:
		var value: float = float(prop.get("value", 0.0))
		var range_text: String = ItemCompare.format_range(prop, value, float(prop.get("maxValue", value)))
		lines.append("%s %s" % [range_text, ItemCompare.prop_title(prop)])
	return lines


## Sets the text of a label and hides it when it is empty.
func _set_text(node_name: String, text: String) -> void:
	var label: Label = get_node(node_name)
	label.text = text
	label.visible = text != ""


## The separator under the header is only shown when a body block follows it.
func _update_separator() -> void:
	var any_body: bool = false
	for node_name: String in ["%Implicits", "%Mods", "%Description", "%SetBox", "%Lore"]:
		any_body = any_body or (get_node(node_name) as Control).visible
	(get_node("Separator") as Control).visible = any_body
