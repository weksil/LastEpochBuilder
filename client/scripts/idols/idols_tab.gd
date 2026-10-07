class_name IdolsTab extends HBoxContainer

## Idol grid editor (docs/UI.md "Idols"). Grid cells are pre-defined in idols_tab.tscn.

const NO_ALTAR: int = -1
const PICTURE_SCENE: PackedScene = preload("res://scenes/idols/idol_picture.tscn")
## Gap between an idol picture and the edges of its cells, so the cell frame (selection, refracted) stays visible.
const PICTURE_INSET: float = 4.0

var _selected_slot: String = ""
var _filling: bool = false


func _ready() -> void:
	Build.changed.connect(_on_build_changed)

	for cell: Node in %Grid.get_children():
		cell.pressed.connect(_on_cell_pressed.bindv([cell.get_meta("row"), cell.get_meta("col")]))

	%AltarSelect.add_item(tr("no altar"), NO_ALTAR)
	for sub: Dictionary in GameData.item_base(IdolGrid.ALTAR_BASE).get("subItems", []):
		%AltarSelect.add_item(GameData.display_name(sub), int(sub["subTypeID"]))
	%AltarSelect.item_selected.connect(_on_altar_selected)
	%AltarEditButton.pressed.connect(_on_altar_edit)

	_update_grid()


func _on_cell_pressed(row: int, col: int) -> void:
	var occ: Dictionary = IdolGrid.occupancy(Build.items)
	var cell: Vector2i = Vector2i(row, col)

	var slot: String
	if occ.has(cell):
		slot = occ[cell]
	else:
		slot = IdolGrid.key(row, col)

	_edit(slot, tr("Idol %d:%d") % [row + 1, col + 1])


## Shows the item editor (hidden until a cell or the altar is picked) for an idol cell or the altar.
func _edit(slot: String, title: String) -> void:
	_selected_slot = slot
	%EditorHint.visible = false
	%EditorScroll.visible = true
	%ItemEditor.edit_slot(slot, title)
	_update_grid()


func _on_altar_selected(index: int) -> void:
	if _filling:
		return
	var sub_id: int = %AltarSelect.get_item_id(index)
	if sub_id == NO_ALTAR:
		Build.clear_item(IdolGrid.ALTAR_SLOT)
		if _selected_slot == IdolGrid.ALTAR_SLOT:
			_close_editor()
	else:
		var old: Dictionary = Build.items.get(IdolGrid.ALTAR_SLOT, {})
		var rolls: Array = []
		for _imp: Variant in GameData.item_sub(IdolGrid.ALTAR_BASE, sub_id).get("implicits", []):
			rolls.append(255)
		Build.set_item(IdolGrid.ALTAR_SLOT, {"base": IdolGrid.ALTAR_BASE, "sub": sub_id, "implicit_rolls": rolls,
			"affixes": old.get("affixes", []).duplicate(true)})
	_drop_misplaced_idols()
	if _selected_slot == IdolGrid.ALTAR_SLOT:
		_edit(IdolGrid.ALTAR_SLOT, tr("Idol altar"))


## Hides the item editor until another cell or the altar is picked.
func _close_editor() -> void:
	_selected_slot = ""
	%EditorScroll.visible = false
	%EditorHint.visible = true


func _on_altar_edit() -> void:
	_edit(IdolGrid.ALTAR_SLOT, tr("Idol altar"))


## Idols that no longer sit on open cells of the chosen altar are removed.
func _drop_misplaced_idols() -> void:
	for slot: String in Build.items.keys():
		if IdolGrid.is_idol_key(slot) and Build.items[slot].has("base"):
			var a: Vector2i = IdolGrid.anchor(slot)
			if not IdolGrid.fits(Build.items, a.x, a.y, int(Build.items[slot]["base"]), slot):
				if _selected_slot == slot:
					_close_editor()
				Build.clear_item(slot)


func _on_build_changed() -> void:
	_update_grid()


func _update_grid() -> void:
	var occ: Dictionary = IdolGrid.occupancy(Build.items)

	_filling = true
	var altar: Dictionary = IdolGrid.altar(Build.items)
	%AltarSelect.select(maxi(0, %AltarSelect.get_item_index(int(altar.get("sub", NO_ALTAR)) if not altar.is_empty() else NO_ALTAR)))
	%AltarEditButton.disabled = altar.is_empty()
	%AltarIcon.texture = null if altar.is_empty() else ItemPictures.picture(altar)
	_filling = false
	_update_weaver_limit()
	_update_pictures()

	for cell: Node in %Grid.get_children():
		var row: int = cell.get_meta("row")
		var col: int = cell.get_meta("col")
		var cell_pos: Vector2i = Vector2i(row, col)

		# Determine cell state
		var is_blocked: bool = not IdolGrid.is_open(row, col, Build.items)
		var is_refracted: bool = IdolGrid.is_refracted(row, col, Build.items)
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
			cell.tooltip_text = ""
		elif is_occupied:
			cell.disabled = false
			cell.theme_type_variation = &"IdolCellOccupiedRefracted" if is_refracted else &"IdolCellOccupied"

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
				# the picture stands for the name when there is one
				cell.text = item_name if ItemPictures.picture(item) == null else ""
			else:
				cell.text = ""

			# Set tooltip
			_set_idol_tooltip(cell, slot)
		else:
			cell.disabled = false
			cell.theme_type_variation = &"IdolCellRefracted" if is_refracted else &"IdolCellOpen"
			cell.text = ""
			cell.tooltip_text = tr("Refracted slot: idol affixes are boosted by the altar") if is_refracted else ""

		# Set selected state
		if is_selected:
			cell.theme_type_variation = &"IdolCellSelected"


## Idol pictures over the grid cells (%Pictures): one per idol, covering all its cells; clicks go through to the cells.
func _update_pictures() -> void:
	for child: Node in %Pictures.get_children():
		%Pictures.remove_child(child)
		child.queue_free()
	var cell_size: Vector2 = (%Grid.get_child(0) as Control).get_combined_minimum_size()
	var gap: Vector2 = Vector2(%Grid.get_theme_constant("h_separation"), %Grid.get_theme_constant("v_separation"))
	for slot: String in Build.items:
		if not IdolGrid.is_idol_key(slot) or not Build.items[slot].has("base"):
			continue
		var item: Dictionary = Build.items[slot]
		var texture: Texture2D = ItemPictures.picture(item)
		if texture == null:
			continue
		var anchor: Vector2i = IdolGrid.anchor(slot)  # (row, col)
		var cells: Vector2 = Vector2(IdolGrid.size_of(int(item["base"])))  # (columns, rows)
		var pic: TextureRect = PICTURE_SCENE.instantiate()
		pic.texture = texture
		pic.position = Vector2(anchor.y, anchor.x) * (cell_size + gap) + Vector2.ONE * PICTURE_INSET
		pic.size = cells * cell_size + (cells - Vector2.ONE) * gap - Vector2.ONE * 2.0 * PICTURE_INSET
		%Pictures.add_child(pic)


## "Weaver idols: n / limit" under the grid while the altar has a Weaver idol limit; a warning colour above the limit.
func _update_weaver_limit() -> void:
	var limit: int = AltarMods.weaver_limit(Build.items)
	%WeaverLimit.visible = limit > 0
	if limit <= 0:
		return
	var count: int = int(AltarMods.idol_counts(Build.items)["weaver"])
	var over: bool = AltarMods.weaver_excess(Build.items) > 0
	%WeaverLimit.text = tr("Weaver idols: %d / %d") % [count, limit]
	if over:
		%WeaverLimit.text += " — " + tr("above the altar limit, the game does not let them into the grid")
	%WeaverLimit.theme_type_variation = &"WarningLabel" if over else &"MutedLabel"


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

	if bool(item.get("corrupted", false)):
		lines.append(tr("Corrupted"))
	if AltarMods.in_refracted_slot(slot, item, Build.items):
		lines.append(tr("Refracted slot"))
	var affixes: Array = item.get("affixes", [])
	for affix_data: Dictionary in affixes:
		var affix_id: int = int(affix_data.get("id", 0))
		var affix: Dictionary = GameData.affix(affix_id)
		var tier: int = int(affix_data.get("tier", 1))
		lines.append("%s (%d)" % [affix.get("name", "?"), tier])

	cell.tooltip_text = "\n".join(lines)
