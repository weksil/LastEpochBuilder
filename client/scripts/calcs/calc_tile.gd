class_name CalcTile extends LazyTooltipPanel

## One big number of the "Calculations" headline strip (docs/UI.md).

const FLASH_SECONDS: float = 1.2

@export var caption: String = "Metric"
## The main tile (accent frame, larger number).
@export var main_tile: bool = false

var _flash_token: int = 0

@onready var _caption: Label = %Caption
@onready var _value: Label = %Value
@onready var _sub: Label = %Sub


func _ready() -> void:
	_caption.text = tr(caption)
	theme_type_variation = &"TilePanelMain" if main_tile else &"TilePanel"
	_value.theme_type_variation = _base_variation()


## text "" shows an em dash. sub: small line below the number; tooltip: breakdown of the number, or tooltip_source:
## a callable that builds it when the pointer is over the tile (the breakdown of a lean result).
func show_value(text: String, sub: String = "", tooltip: String = "", tooltip_source: Callable = Callable()) -> void:
	var shown: String = text if text != "" else "—"
	if shown != _value.text and _value.text != "—" and shown != "—":
		_flash()
	_value.text = shown
	_sub.text = sub
	_sub.visible = sub != ""
	tooltip_text = tooltip
	set_tooltip_source(tooltip_source)


func _base_variation() -> StringName:
	return &"HeroValueMain" if main_tile else &"HeroValue"


func _flash() -> void:
	_flash_token += 1
	_value.theme_type_variation = &"HeroValueMainChanged" if main_tile else &"HeroValueChanged"
	get_tree().create_timer(FLASH_SECONDS).timeout.connect(_end_flash.bind(_flash_token))


func _end_flash(token: int) -> void:
	if token == _flash_token and is_instance_valid(_value):
		_value.theme_type_variation = _base_variation()
