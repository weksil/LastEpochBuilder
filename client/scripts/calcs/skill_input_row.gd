class_name SkillInputRow extends HBoxContainer

## One declared input of the selected skill (docs/UI.md «Расчёты»): a number (SpinBox) or a switch (CheckBox).
## Values come back in place through update_input(); signals are blocked then, so typing is never interrupted.

var key: String = ""
var is_flag: bool = false

var _slot: int = 0

@onready var name_label: Label = %NameLabel
@onready var value_spin: SpinBox = %ValueSpin
@onready var flag_check: CheckBox = %FlagCheck


func _ready() -> void:
	value_spin.value_changed.connect(_on_spin_changed)
	flag_check.toggled.connect(_on_flag_toggled)


## True if `inp` ({key, label, value[, max]}) has the same key and kind as this row (it can be updated in place).
func fits(inp: Dictionary) -> bool:
	return str(inp.get("key", "")) == key and (inp.get("value", 0) is bool) == is_flag


func setup(slot: int, inp: Dictionary) -> void:
	_slot = slot
	key = str(inp.get("key", ""))
	is_flag = inp.get("value", 0) is bool
	var label: String = str(inp.get("label", ""))
	name_label.text = label
	flag_check.text = label
	name_label.visible = not is_flag
	value_spin.visible = not is_flag
	flag_check.visible = is_flag
	update_input(slot, inp)


## Shows the current value without emitting signals.
func update_input(slot: int, inp: Dictionary) -> void:
	_slot = slot
	var value: Variant = inp.get("value", 0)
	if is_flag:
		flag_check.set_pressed_no_signal(bool(value))
		return
	if inp.has("max") and not is_equal_approx(value_spin.max_value, float(inp["max"])):
		value_spin.set_block_signals(true)
		value_spin.max_value = float(inp["max"])
		value_spin.set_block_signals(false)
	if not is_equal_approx(value_spin.value, float(value)):
		value_spin.set_value_no_signal(float(value))


func _on_spin_changed(new_value: float) -> void:
	Build.set_skill_input(_slot, key, new_value)


func _on_flag_toggled(toggled: bool) -> void:
	Build.set_skill_input(_slot, key, toggled)
