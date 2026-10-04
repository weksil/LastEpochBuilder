class_name CalcRow extends PanelContainer

## One row of a "Calculations" section (docs/UI.md): name, value, "+" that expands the breakdown.
## update_row() refreshes the texts in place and briefly marks a changed value.

signal expanded_changed(key: String, expanded: bool)

const FLASH_SECONDS: float = 1.2

var row_key: String = ""
var _key_row: bool = false
var _flash_token: int = 0

@onready var _expand_button: Button = %ExpandButton
@onready var _name_label: Label = %NameLabel
@onready var _value_label: Label = %ValueLabel
@onready var _details_panel: PanelContainer = %DetailsPanel
@onready var _details: Label = %Details


func _ready() -> void:
	_expand_button.toggled.connect(_on_expand_toggled)


## key: unique id of the row (section title + label); alt: zebra background; key_row: highlighted result row.
func setup(key: String, row: Dictionary, alt: bool, expanded: bool, key_row: bool) -> void:
	row_key = key
	_key_row = key_row
	theme_type_variation = &"CalcRowAlt" if alt else &"CalcRow"
	_name_label.text = str(row.get("label", ""))
	_value_label.text = str(row.get("text", ""))
	_value_label.theme_type_variation = _base_variation()
	_apply_breakdown(str(row.get("breakdown", "")))
	_expand_button.set_pressed_no_signal(expanded and _expand_button.visible)
	_sync_expanded()


## Refreshes the texts without rebuilding; a changed value is highlighted for a moment.
func update_row(row: Dictionary) -> void:
	var text: String = str(row.get("text", ""))
	if text != _value_label.text:
		_value_label.text = text
		_flash()
	_apply_breakdown(str(row.get("breakdown", "")))


func _apply_breakdown(breakdown: String) -> void:
	_details.text = breakdown
	_expand_button.visible = breakdown != ""
	_sync_expanded()


func _sync_expanded() -> void:
	var on: bool = _expand_button.visible and _expand_button.button_pressed
	_details_panel.visible = on
	_expand_button.text = "−" if on else "+"


func _on_expand_toggled(_pressed: bool) -> void:
	_sync_expanded()
	expanded_changed.emit(row_key, _expand_button.button_pressed)


func _base_variation() -> StringName:
	return &"ValueLabelKey" if _key_row else &"ValueLabel"


func _flash() -> void:
	_flash_token += 1
	_value_label.theme_type_variation = &"ValueLabelKeyChanged" if _key_row else &"ValueLabelChanged"
	get_tree().create_timer(FLASH_SECONDS).timeout.connect(_end_flash.bind(_flash_token))


func _end_flash(token: int) -> void:
	if token == _flash_token and is_instance_valid(_value_label):
		_value_label.theme_type_variation = _base_variation()
