class_name StatRow extends PanelContainer

## One row of the stats panel: name, value, tooltip = breakdown. update_row() changes the texts in place;
## a changed value highlights the row for a moment and shows the difference when both values are numbers.

const FLASH_SECONDS: float = 1.5

var row_key: String = ""

var _value: float = NAN
var _flash_token: int = 0

@onready var _name_label: Label = %NameLabel
@onready var _delta_label: Label = %DeltaLabel
@onready var _value_label: Label = %ValueLabel


func setup(key: String, title: String, text: String, tooltip: String = "", value: float = NAN) -> void:
	row_key = key
	_name_label.text = title
	_value_label.text = text
	tooltip_text = tooltip
	_value = value


## numeric `value` (NAN if the row has none) is used for the shown difference.
func update_row(text: String, tooltip: String = "", value: float = NAN) -> void:
	tooltip_text = tooltip
	if text != _value_label.text:
		_value_label.text = text
		_flash(value, text)
	_value = value


func _flash(value: float, text: String) -> void:
	_flash_token += 1
	theme_type_variation = &"StatRowChanged"
	if not is_nan(value) and not is_nan(_value) and not is_equal_approx(value, _value):
		var delta: float = value - _value
		var shown: String = LE.fmt_pct(absf(delta)) if text.contains("%") else LE.fmt_num(absf(delta))
		_delta_label.text = ("+" if delta > 0.0 else "−") + shown
		_delta_label.theme_type_variation = &"DeltaUp" if delta > 0.0 else &"DeltaDown"
		_delta_label.visible = true
	get_tree().create_timer(FLASH_SECONDS).timeout.connect(_end_flash.bind(_flash_token))


func _end_flash(token: int) -> void:
	if token != _flash_token or not is_instance_valid(self):
		return
	theme_type_variation = &"StatRowPlain"
	_delta_label.visible = false
