class_name ItemDiffTooltip extends VBoxContainer

## Tooltip of an item button: its mods and the stat changes of equipping it (item_diff_tooltip.tscn).

@export var line_scene: PackedScene


## Called before the tooltip enters the tree, so the nodes are reached by unique names only.
## slot: the equipment slot the item would go to ("" when it fits none).
## changes: every slot that changes (slot -> item, {} empties it); empty means just `{slot: item}`.
## An empty `item` shows what leaving the slot empty gives.
func show_item(item: Dictionary, slot: String, changes: Dictionary = {}) -> void:
	var title: Label = get_node("%Title")
	var base: Label = get_node("%Base")
	var mods: Label = get_node("%Mods")
	var header: Label = get_node("%Header")
	var replacing: Label = get_node("%Replacing")
	var lines_box: VBoxContainer = get_node("%Lines")
	var no_change: Label = get_node("%NoChange")

	var set_unique: Dictionary = GameData.unique(int(item["unique"])) if item.has("unique") else {}
	(get_node("%SetBox") as SetBlock).show_set(int(set_unique.get("setID", -1)) if int(set_unique.get("isSetItem", 0)) != 0 else -1)

	if item.is_empty():
		title.text = tr("— none —")
		base.visible = false
		mods.visible = false
	else:
		title.text = ItemCompare.item_title(item)
		if item.has("unique"):
			var is_set: bool = int(GameData.unique(int(item["unique"])).get("isSetItem", 0)) != 0
			title.theme_type_variation = &"RaritySet" if is_set else &"RarityUnique"
		var subtitle: String = ItemCompare.item_subtitle(item)
		base.text = subtitle
		base.visible = subtitle != ""
		var mod_lines: PackedStringArray = ItemCompare.item_lines(item)
		mods.text = "\n".join(mod_lines)
		mods.visible = not mod_lines.is_empty()

	if slot == "":
		header.text = tr("This item does not fit any equipment slot.")
		replacing.visible = false
		lines_box.visible = false
		no_change.visible = false
		return

	if item.is_empty():
		header.text = tr("Leaving %s empty will give you:") % ItemCompare.slot_title(slot)
	else:
		header.text = tr("Equipping this item in %s will give you:") % ItemCompare.slot_title(slot)
	var current: Dictionary = Build.items.get(slot, {})
	var is_replacing: bool = not item.is_empty() and not current.is_empty() and current != item
	replacing.visible = is_replacing
	if is_replacing:
		replacing.text = tr("(replacing %s)") % ItemCompare.item_title(current)

	if changes.is_empty():
		changes = {slot: item}
	var lines: Array[Dictionary] = ItemCompare.diff(ItemCompare.snapshot(Build), ItemCompare.snapshot_with_items(Build, changes))
	for line: Dictionary in lines:
		var label: Label = line_scene.instantiate() as Label
		lines_box.add_child(label)
		label.text = str(line.get("text", ""))
		label.theme_type_variation = &"DeltaUp" if float(line.get("delta", 0.0)) > 0.0 else &"DeltaDown"
	lines_box.visible = not lines.is_empty()
	no_change.visible = lines.is_empty()
