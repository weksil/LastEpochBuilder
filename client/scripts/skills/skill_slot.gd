class_name SkillSlot extends PanelContainer

signal selected(slot_index: int)

@export var slot_index: int = 0

var _current_ability: String = ""
var _block_signals: bool = false
var _options_key: String = ""


func _ready() -> void:
	%SlotLabel.text = "Слот %d" % (slot_index + 1)

	%SkillSelect.add_item("— пусто —")
	%SkillSelect.set_item_metadata(0, "")
	%LevelSpin.value_changed.connect(_on_level_changed)
	%SkillSelect.item_selected.connect(_on_skill_selected)
	%SelectButton.toggled.connect(_on_select_button_toggled)

	Build.changed.connect(_on_build_changed)

	_on_build_changed()


func _on_build_changed() -> void:
	# Rebuild skill options only if class/mastery changed
	var key: String = "%d:%d" % [Build.class_id, Build.mastery]
	if key == _options_key:
		sync()
		return
	_options_key = key
	var skills_data: Array[String] = GameData.class_skills(Build.class_id, Build.mastery)

	# Clear and rebuild options (keep "— пусто —" at index 0)
	_block_signals = true
	%SkillSelect.clear()
	%SkillSelect.add_item("— пусто —")
	%SkillSelect.set_item_metadata(0, "")

	for ability_id: String in skills_data:
		var ability: Dictionary = GameData.get_ability(ability_id)
		var ability_name: String = ability.get("abilityName", ability_id)
		%SkillSelect.add_item(ability_name)
		%SkillSelect.set_item_metadata(%SkillSelect.item_count - 1, ability_id)
	_block_signals = false

	sync()


func sync() -> void:
	"""Update UI from Build.skills[slot_index]"""
	if slot_index < 0 or slot_index >= Build.skills.size():
		return

	var skill_data: Dictionary = Build.skills[slot_index]
	var ability_id: String = skill_data.get("ability", "")
	var skill_level: int = skill_data.get("level", 20)

	_block_signals = true

	# Update skill select
	if ability_id == "":
		%SkillSelect.select(0)
		_current_ability = ""
	else:
		for i in range(%SkillSelect.item_count):
			if %SkillSelect.get_item_metadata(i) == ability_id:
				%SkillSelect.select(i)
				break
		_current_ability = ability_id

	# Update level
	%LevelSpin.set_value_no_signal(float(skill_level))

	_block_signals = false

	_update_points_label()


func _on_skill_selected(index: int) -> void:
	if _block_signals:
		return

	var ability_id: String = %SkillSelect.get_item_metadata(index)
	Build.set_skill(slot_index, ability_id)


func _on_level_changed(value: float) -> void:
	if _block_signals:
		return

	Build.set_skill_level(slot_index, int(value))
	_update_points_label()


func _on_select_button_toggled(pressed: bool) -> void:
	if _block_signals:
		return

	if pressed:
		selected.emit(slot_index)
	else:
		# a second click on the shown slot keeps it shown
		set_selected(true)


func set_selected(on: bool) -> void:
	"""Update button state"""
	_block_signals = true
	%SelectButton.set_pressed_no_signal(on)
	_block_signals = false


func _update_points_label() -> void:
	if slot_index < 0 or slot_index >= Build.skills.size():
		return

	var skill_data: Dictionary = Build.skills[slot_index]
	var skill_level: int = skill_data.get("level", 20)
	var spent: int = Build.skill_points_spent(slot_index)
	var bonus: int = Build.skill_level_bonus(slot_index)

	%PointsLabel.text = "Уровень %d (+%d от предметов), очков %d / %d" % [skill_level, bonus, spent, skill_level + bonus]
