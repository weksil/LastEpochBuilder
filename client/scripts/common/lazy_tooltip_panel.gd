class_name LazyTooltipPanel extends PanelContainer

## A panel whose tooltip text is built only when the pointer is over it (Control._get_tooltip), not every time the
## shown values change: set_tooltip_source(callable) — the callable returns the text, it is called once and the text
## is kept until the next set_tooltip_source. Without a source the plain tooltip_text is used.

var _tooltip_source: Callable = Callable()
var _tooltip_cache: Variant = null


func set_tooltip_source(source: Callable) -> void:
	_tooltip_source = source
	_tooltip_cache = null


func _get_tooltip(_at_position: Vector2) -> String:
	if not _tooltip_source.is_valid():
		return tooltip_text
	if _tooltip_cache == null:
		_tooltip_cache = str(_tooltip_source.call())
	return _tooltip_cache
