class_name SearchSelect extends Button

## A drop-in for OptionButton with a search box: the button shows the chosen item, pressing it opens a popup with a
## filterable list. Controls live in search_select.tscn.

## The user picked an item (not emitted by select()).
signal item_selected(index: int)

const NOTHING_TEXT: String = "—"

var item_count: int:
	get:
		return _texts.size()
var selected: int:
	get:
		return _selected

## Takes an item id, returns the hover tooltip of that item (a Control) or null.
var tooltip_builder: Callable

var _texts: PackedStringArray = PackedStringArray()
var _ids: PackedInt32Array = PackedInt32Array()
## Theme type per item whose "font_color" colours its list row (&"" = the list's default colour).
var _variations: Array[StringName] = []
var _selected: int = -1
## Item index of every %List row while the list is filtered.
var _rows: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	# item texts are data (or were already translated by the caller)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	%List.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	pressed.connect(_open)
	%Search.text_changed.connect(_on_search_changed)
	%Search.text_submitted.connect(_on_search_submitted)
	%Search.gui_input.connect(_on_search_gui_input)
	%List.item_clicked.connect(_on_list_clicked)
	%List.tooltip_builder = func(row: int) -> Control:
		if not tooltip_builder.is_valid() or row < 0 or row >= _rows.size():
			return null
		return tooltip_builder.call(_ids[_rows[row]])
	_update_text()


func clear() -> void:
	_texts.clear()
	_ids.clear()
	_variations.clear()
	_selected = -1
	_update_text()


func add_item(label: String, id: int = -1) -> void:
	_texts.append(label)
	_ids.append(id if id != -1 else _texts.size() - 1)
	_variations.append(&"")


## Colours the item's list row with the "font_color" of a theme type, e.g. &"RarityUnique".
func set_item_variation(index: int, variation: StringName) -> void:
	if index >= 0 and index < _variations.size():
		_variations[index] = variation


## Marks an item as shown on the button, without emitting item_selected.
func select(index: int) -> void:
	_selected = index if index >= 0 and index < _texts.size() else -1
	_update_text()


func get_selected() -> int:
	return _selected


func get_selected_id() -> int:
	return get_item_id(_selected) if _selected >= 0 else -1


func get_item_id(index: int) -> int:
	return _ids[index] if index >= 0 and index < _ids.size() else -1


## Index of the item with this id, -1 when there is none.
func get_item_index(id: int) -> int:
	return _ids.find(id)


func get_item_text(index: int) -> String:
	return _texts[index] if index >= 0 and index < _texts.size() else ""


func _update_text() -> void:
	text = _texts[_selected] if _selected >= 0 and _selected < _texts.size() else NOTHING_TEXT


# --- popup ------------------------------------------------------------------------------

func _open() -> void:
	%Search.text = ""
	_fill_list("")
	# the current item is the highlighted row (the list shows every item)
	if _selected >= 0:
		%List.select(_selected)
		%List.ensure_current_is_visible()
	var width: int = maxi(int(size.x), int(%Popup.get_contents_minimum_size().x))
	%Popup.popup(Rect2i(Vector2i(get_screen_position()) + Vector2i(0, int(size.y)), Vector2i(width, 0)))
	%Search.grab_focus.call_deferred()


## Fills %List with the items matching the query and selects the first row.
func _fill_list(query: String) -> void:
	%List.clear()
	_rows.clear()
	var needle: String = query.strip_edges().to_lower()
	var words: PackedStringArray = needle.split(" ", false)
	for i in range(_texts.size()):
		if _matches(_texts[i].to_lower(), needle, words):
			_rows.append(i)
			%List.add_item(_texts[i])
			# a non-empty tooltip makes the list ask for the custom one (tooltip_builder)
			%List.set_item_tooltip(%List.item_count - 1, _texts[i])
			if _variations[i] != &"":
				%List.set_item_custom_fg_color(%List.item_count - 1, get_theme_color("font_color", _variations[i]))
	if _rows.size() > 0:
		%List.select(0)
	%Empty.visible = _rows.is_empty()


func _matches(item_text: String, needle: String, words: PackedStringArray) -> bool:
	if needle.is_empty() or item_text.contains(needle):
		return true
	for word: String in words:
		if not item_text.contains(word):
			return false
	return true


func _on_search_changed(query: String) -> void:
	_fill_list(query)


func _on_search_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_DOWN or key.keycode == KEY_UP:
		if _rows.size() > 0:
			var selection: PackedInt32Array = %List.get_selected_items()
			var row: int = selection[0] if selection.size() > 0 else -1
			row = clampi(row + (1 if key.keycode == KEY_DOWN else -1), 0, _rows.size() - 1)
			%List.select(row)
			%List.ensure_current_is_visible()
		%Search.accept_event()


func _on_search_submitted(_query: String) -> void:
	var selection: PackedInt32Array = %List.get_selected_items()
	if selection.size() > 0:
		_pick(selection[0])


func _on_list_clicked(row: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		_pick(row)


## Chooses the item shown in a %List row.
func _pick(row: int) -> void:
	if row < 0 or row >= _rows.size():
		return
	_selected = _rows[row]
	_update_text()
	%Popup.hide()
	item_selected.emit(_selected)
