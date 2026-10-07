class_name MinionRow extends PanelContainer

## One minion count of the Minions card of "Conditions": a minion type summoned by a bar skill or a count the models
## scale with (MinionCount). The «auto» box is on while no number is set; show_state() updates without signals.

signal count_changed(key: String, value: float)
signal auto_toggled(key: String, on: bool)

var key: String = ""

@onready var _name_label: Label = %NameLabel
@onready var _reason_label: Label = %ReasonLabel
@onready var _spin: SpinBox = %CountSpin
@onready var _auto_check: CheckBox = %AutoCheck


func _ready() -> void:
	_spin.value_changed.connect(func(v: float) -> void: count_changed.emit(key, v))
	_auto_check.toggled.connect(func(on: bool) -> void: auto_toggled.emit(key, on))


func setup(row_key: String, title: String) -> void:
	key = row_key
	_name_label.text = title


func value() -> float:
	return _spin.value


## count: current value; reason: where the row comes from; auto: the value is automatic, auto_text explains it.
func show_state(count: float, reason: String, has_source: bool, auto: bool, auto_text: String) -> void:
	if not is_equal_approx(_spin.value, count):
		_spin.set_value_no_signal(count)
	_auto_check.set_pressed_no_signal(auto)
	var lines: PackedStringArray = []
	if auto and auto_text != "":
		lines.append(auto_text)
	if reason != "":
		lines.append(reason)
	if not has_source and count > 0.0:
		lines = [tr("no source in the build — does not affect the calculation")]
	_reason_label.text = "\n".join(lines)
	_reason_label.visible = not lines.is_empty()
	if count > 0.0:
		theme_type_variation = &"RowActive" if has_source else &"RowNoSource"
	else:
		theme_type_variation = &"RowIdle"
	_name_label.theme_type_variation = &"ValueLabel" if count > 0.0 else &""


func has_edit_focus() -> bool:
	return _spin.get_line_edit().has_focus()
