class_name SearchSelectList extends ItemList

## The row list of a SearchSelect popup: hovering a row shows a custom tooltip built by the owner.

## Takes the ROW index, returns the tooltip Control or null.
var tooltip_builder: Callable


func _make_custom_tooltip(_for_text: String) -> Object:
	if not tooltip_builder.is_valid():
		return null
	var row: int = get_item_at_position(get_local_mouse_position(), true)
	if row < 0:
		return null
	return tooltip_builder.call(row)
