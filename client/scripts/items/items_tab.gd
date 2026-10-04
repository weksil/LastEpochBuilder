class_name ItemsTab extends HBoxContainer

## Items tab (docs/UI.md "Items"): the equipment slots with a dropdown of the character's items, the list of
## unequipped items and the item editor. Nodes live in items_tab.tscn.

@export var stash_button_scene: PackedScene
@export var choice_button_scene: PackedScene
## Shared by the unequipped item buttons: the edited one stays pressed.
@export var select_group: ButtonGroup

var _rows: Array[SlotRow] = []
## The equipment slot being edited (also the slot a stash item is compared against).
var _slot: String = ""
## Index of the stash entry being edited, -1 when an equipment slot is edited.
var _stash_index: int = -1
var _pending: bool = false


func _ready() -> void:
	for child: Node in %SlotList.get_children():
		var row: SlotRow = child as SlotRow
		if row == null:
			continue
		_rows.append(row)
		row.selected.connect(_edit_slot)
		row.choices_requested.connect(_show_choices)
	Build.changed.connect(_queue_refresh)
	Build.stash_changed.connect(_queue_refresh)
	%ItemEditor.slot_requested.connect(_edit_slot)

	%AddButton.pressed.connect(_add_item)

	if not _rows.is_empty():
		_edit_slot(_rows[0].slot)


func _row(slot: String) -> SlotRow:
	for row: SlotRow in _rows:
		if row.slot == slot:
			return row
	return null


func _edit_slot(slot: String) -> void:
	_slot = slot
	_stash_index = -1
	for other: SlotRow in _rows:
		other.set_selected(other.slot == slot)
	var row: SlotRow = _row(slot)
	if row != null:
		%ItemEditor.edit_slot(slot, tr(row.slot_name))
	_refresh()


func _edit_stash(index: int) -> void:
	_stash_index = index
	for row: SlotRow in _rows:
		row.set_selected(false)
	%ItemEditor.edit_stash(index)
	_refresh()


func _queue_refresh() -> void:
	if _pending:
		return
	_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	_pending = false
	if _stash_index >= Build.stash.size():
		_edit_slot(_slot)  # the edited stash item is gone; _edit_slot refreshes again
		return
	for row: SlotRow in _rows:
		row.update_item(Build.items.get(row.slot, {}))
	for child: Node in %StashRows.get_children():
		%StashRows.remove_child(child)
		child.queue_free()
	for i in range(Build.stash.size()):
		var item: Dictionary = Build.stash[i]
		var button: ItemButton = stash_button_scene.instantiate()
		%StashRows.add_child(button)
		button.button_group = select_group
		button.setup(item, ItemCompare.target_slot(item, _slot))
		button.pressed.connect(_edit_stash.bind(i))
		if i == _stash_index:
			button.button_pressed = true
	%StashEmpty.visible = Build.stash.is_empty()


# --- item choice popup --------------------------------------------------------------

## Fills and opens the list of the character's items that fit `slot`, under `anchor`.
func _show_choices(slot: String, anchor: Control) -> void:
	for child: Node in %ChoiceRows.get_children():
		%ChoiceRows.remove_child(child)
		child.queue_free()

	# leave the slot empty
	var none_button: ItemButton = choice_button_scene.instantiate()
	%ChoiceRows.add_child(none_button)
	none_button.setup({}, slot)
	none_button.disabled = not Build.items.has(slot)
	none_button.pressed.connect(_choose.bind(slot, func() -> void: Build.unequip_to_stash(slot)))

	# equipped items (of this slot or another one) that fit
	var current: Dictionary = Build.items.get(slot, {})
	for equipped_slot: String in BuildMods.SLOTS:
		var item: Dictionary = Build.items.get(equipped_slot, {})
		if item.is_empty() or not ItemCompare.fits_slot(slot, GameData.item_base(int(item.get("base", -1)))):
			continue
		var changes: Dictionary = {slot: item}
		if equipped_slot != slot:
			var swaps_back: bool = not current.is_empty() \
				and ItemCompare.fits_slot(equipped_slot, GameData.item_base(int(current.get("base", -1))))
			changes[equipped_slot] = current if swaps_back else {}
		var button: ItemButton = choice_button_scene.instantiate()
		%ChoiceRows.add_child(button)
		button.theme_type_variation = StringName("ItemChoice" + ItemCompare.rarity(item))
		button.icon = _row(equipped_slot).slot_icon
		button.setup(item, slot, changes)
		if equipped_slot != slot:
			button.pressed.connect(_choose.bind(slot, func() -> void: Build.move_item(equipped_slot, slot)))
		else:
			button.pressed.connect(_choose.bind(slot, Callable()))

	# unequipped items that fit
	for i in range(Build.stash.size()):
		var item: Dictionary = Build.stash[i]
		if not ItemCompare.fits_slot(slot, GameData.item_base(int(item.get("base", -1)))):
			continue
		var button: ItemButton = choice_button_scene.instantiate()
		%ChoiceRows.add_child(button)
		button.theme_type_variation = &"ItemChoiceStashed"
		button.setup(item, slot, {slot: item})
		button.pressed.connect(_choose.bind(slot, func() -> void: Build.equip_from_stash(i, slot)))

	var rect := Rect2(anchor.get_screen_position(), anchor.size)
	%ChoicePopup.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y)), Vector2i(int(rect.size.x), 0)))


## Runs a choice popup action (an invalid Callable does nothing), closes the popup and shows the slot.
func _choose(slot: String, action: Callable) -> void:
	if action.is_valid():
		action.call()
	%ChoicePopup.hide()
	_edit_slot(slot)


# --- new items ----------------------------------------------------------------------

## "+": a new empty-affix item of the first base fitting the selected slot, added to the unequipped items and opened
## in the editor (its Type row changes the kind).
func _add_item() -> void:
	var base_id: int = ItemCompare.first_base(_slot)
	if base_id < 0:
		return
	var class_name_str: String = str(GameData.get_class_data(Build.class_id).get("className", ""))
	var sub_id: int = ItemCompare.default_sub(GameData.item_base(base_id), class_name_str)
	Build.stash_add(ItemCompare.new_item(base_id, sub_id, []))
	_edit_stash(Build.stash.size() - 1)
	%ItemEditor.focus_type()
