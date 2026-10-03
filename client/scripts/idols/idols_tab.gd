class_name IdolsTab extends HBoxContainer

## Idol grid editor (docs/UI.md «Идолы»). Grid cells are pre-defined in idols_tab.tscn.

var _selected_slot: String = ""


func _ready() -> void:
	Build.changed.connect(_on_build_changed)

	for cell: Node in %Grid.get_children():
		cell.pressed.connect(_on_cell_pressed.bindv([cell.get_meta("row"), cell.get_meta("col")]))

	_update_grid()


func _on_cell_pressed(row: int, col: int) -> void:
	var occ: Dictionary = IdolGrid.occupancy(Build.items)
	var cell: Vector2i = Vector2i(row, col)

	var slot: String
	if occ.has(cell):
		slot = occ[cell]
	else:
		slot = IdolGrid.key(row, col)

	_selected_slot = slot
	%ItemEditor.edit_slot(slot, "Идол %d:%d" % [row + 1, col + 1])
	_update_grid()


func _on_build_changed() -> void:
	_update_grid()


func _update_grid() -> void:
	var occ: Dictionary = IdolGrid.occupancy(Build.items)

	for cell: Node in %Grid.get_children():
		var row: int = cell.get_meta("row")
		var col: int = cell.get_meta("col")
		var cell_pos: Vector2i = Vector2i(row, col)

		# Determine cell state
		var is_blocked: bool = not IdolGrid.is_open(row, col)
		var is_occupied: bool = occ.has(cell_pos)
		var is_selected: bool = false

		if is_occupied:
			is_selected = (occ[cell_pos] == _selected_slot)
		else:
			is_selected = (_selected_slot == IdolGrid.key(row, col))

		# Update cell appearance
		if is_blocked:
			cell.disabled = true
			cell.theme_type_variation = &"IdolCellBlocked"
			cell.text = ""
		elif is_occupied:
			cell.disabled = false
			cell.theme_type_variation = &"IdolCellOccupied"

			# Get the slot key for this cell
			var slot: String = occ[cell_pos]
			var anchor_pos: Vector2i = IdolGrid.anchor(slot)

			# Show name only at anchor (top-left)
			if cell_pos == anchor_pos:
				var item: Dictionary = Build.items.get(slot, {})
				var item_name: String = ""
				if "unique" in item:
					var unique_id: int = int(item.get("unique", 0))
					var unique_item: Dictionary = GameData.unique(unique_id)
					item_name = GameData.display_name(unique_item)
				else:
					var base_id: int = int(item.get("base", 0))
					var base: Dictionary = GameData.item_base(base_id)
					item_name = GameData.display_name(base)
				cell.text = item_name
			else:
				cell.text = ""

			# Set tooltip
			_set_idol_tooltip(cell, slot)
		else:
			cell.disabled = false
			cell.theme_type_variation = &"IdolCellOpen"
			cell.text = ""
			cell.tooltip_text = ""

		# Set selected state
		if is_selected:
			cell.theme_type_variation = &"IdolCellSelected"


func _set_idol_tooltip(cell: Node, slot: String) -> void:
	var item: Dictionary = Build.items.get(slot, {})
	var lines: PackedStringArray = []

	if "unique" in item:
		var unique_id: int = int(item.get("unique", 0))
		var unique_item: Dictionary = GameData.unique(unique_id)
		lines.append(GameData.display_name(unique_item))
	else:
		var base_id: int = int(item.get("base", 0))
		var sub_id: int = int(item.get("sub", 0))
		var base: Dictionary = GameData.item_base(base_id)
		var sub: Dictionary = {}

		for s: Dictionary in base.get("subItems", []):
			if int(s.get("subTypeID", -1)) == sub_id:
				sub = s
				break

		if not sub.is_empty():
			lines.append(GameData.display_name(sub))

	var affixes: Array = item.get("affixes", [])
	for affix_data: Dictionary in affixes:
		var affix_id: int = int(affix_data.get("id", 0))
		var affix: Dictionary = GameData.affix(affix_id)
		var tier: int = int(affix_data.get("tier", 1))
		lines.append("%s (%d)" % [affix.get("name", "?"), tier])

	cell.tooltip_text = "\n".join(lines)
