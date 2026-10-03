extends HBoxContainer

class_name SkillInputRow

@onready var name_label: Label = %NameLabel
@onready var value_spin: SpinBox = %ValueSpin
@onready var flag_check: CheckBox = %FlagCheck

var _slot: int = 0
var _key: String = ""


func setup(slot: int, inp: Dictionary) -> void:
	_slot = slot
	_key = inp.get("key", "")

	name_label.text = inp.get("label", "")

	var value = inp.get("value", 0)
	var is_bool = value is bool

	if is_bool:
		# Show checkbox for boolean inputs
		value_spin.hide()
		flag_check.show()
		flag_check.set_pressed_no_signal(value as bool)
		flag_check.toggled.connect(_on_flag_toggled)
	else:
		# Show spinbox for numeric inputs
		flag_check.hide()
		value_spin.show()

		if inp.has("max"):
			value_spin.max_value = inp.get("max", 1000.0)

		value_spin.set_value_no_signal(value as float)
		value_spin.value_changed.connect(_on_spin_changed)


func _on_spin_changed(new_value: float) -> void:
	Build.set_skill_input(_slot, _key, new_value)


func _on_flag_toggled(toggled: bool) -> void:
	Build.set_skill_input(_slot, _key, toggled)
