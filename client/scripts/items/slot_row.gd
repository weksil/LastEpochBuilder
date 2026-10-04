class_name SlotRow extends HBoxContainer

## One equipment slot of the Items tab: the slot icon (a plain picture) and a dropdown button showing the equipped item;
## pressing it selects the slot in the editor and opens the list of items that fit the slot. Nodes live in slot_row.tscn.

signal selected(slot: String)
signal choices_requested(slot: String, anchor: Control)

@export var slot: String
## English source of the slot name, translated for display.
@export var slot_name: String
@export var slot_icon: Texture2D

var _rarity: String = ""
var _selected: bool = false


func _ready() -> void:
	%SlotIcon.texture = slot_icon
	%ItemButton.pressed.connect(func() -> void:
		selected.emit(slot)
		choices_requested.emit(slot, %ItemButton))


func update_item(item: Dictionary) -> void:
	%ItemButton.text = ItemCompare.item_title(item)
	_rarity = ItemCompare.rarity(item)
	_update_variation()


## Highlights the row of the slot shown in the editor.
func set_selected(on: bool) -> void:
	_selected = on
	_update_variation()


## SlotItemSelected* for the edited slot, SlotItemUnique / SlotItemSet colour unique and set item names.
func _update_variation() -> void:
	if _selected:
		%ItemButton.theme_type_variation = StringName("SlotItemSelected" + _rarity)
	else:
		%ItemButton.theme_type_variation = StringName("SlotItem" + _rarity) if _rarity != "" else &""
