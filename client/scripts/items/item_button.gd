class_name ItemButton extends Button

## A button for one item (stash list entry or choice popup row) with the stat-diff hover tooltip.
## Used by stash_item_button.tscn and item_choice_button.tscn.

@export var tooltip_scene: PackedScene

var _item: Dictionary = {}
var _slot: String = ""
var _changes: Dictionary = {}


## slot: the slot the tooltip diffs against ("" when the item fits none); changes: see ItemDiffTooltip.show_item().
func setup(item: Dictionary, slot: String, changes: Dictionary = {}) -> void:
	_item = item
	_slot = slot
	_changes = changes
	text = tr("— none —") if item.is_empty() else ItemCompare.item_title(item)
	tooltip_text = text  # must stay non-empty, or the custom tooltip is not shown


func _make_custom_tooltip(_for_text: String) -> Object:
	var tooltip: ItemDiffTooltip = tooltip_scene.instantiate()
	tooltip.show_item(_item, _slot, _changes)
	return tooltip
