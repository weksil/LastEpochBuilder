extends VBoxContainer

class_name CalcsTab

@export var section_scene: PackedScene
@export var row_scene: PackedScene
@export var input_row_scene: PackedScene

@onready var skill_select: OptionButton = %SkillSelect
@onready var sections_container: VBoxContainer = %Sections
@onready var hits_spin: SpinBox = %HitsSpin
@onready var inputs_container: VBoxContainer = %Inputs


func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	visibility_changed.connect(_on_visibility_changed)
	skill_select.item_selected.connect(_on_skill_selected)
	hits_spin.value_changed.connect(_on_hits_changed)
	_populate_skill_options()
	_update_calcs()


func _on_visibility_changed() -> void:
	if visible:
		_update_calcs()


func _on_build_changed() -> void:
	_populate_skill_options()
	call_deferred("_update_calcs")


func _on_skill_selected(index: int) -> void:
	Build.selected_skill = index
	call_deferred("_update_calcs")


func _populate_skill_options() -> void:
	skill_select.clear()

	for i in range(5):
		var skill: Dictionary = Build.skills[i] if i < Build.skills.size() else {}
		var ability_id: String = skill.get("ability", "")
		var skill_name: String = "—"

		if ability_id != "":
			var ability: Dictionary = GameData.get_ability(ability_id)
			if not ability.is_empty():
				skill_name = GameData.display_name(ability)

		skill_select.add_item("%d. %s" % [i + 1, skill_name])

	skill_select.select(Build.selected_skill)


func _update_calcs() -> void:
	if not visible:
		return

	# Clear existing sections
	for child: Node in sections_container.get_children():
		child.queue_free()

	# Clear existing input rows
	for child: Node in inputs_container.get_children():
		child.queue_free()

	var result: Dictionary = SkillCalc.compute(Build, Build.selected_skill)

	# Update hits spinbox
	var hits: float = result.get("hits", 1.0)
	hits_spin.set_value_no_signal(hits)

	# Add input rows
	for inp: Dictionary in result.get("inputs", []):
		var input_instance: Node = input_row_scene.instantiate()
		inputs_container.add_child(input_instance)
		input_instance.setup(Build.selected_skill, inp)

	# Add sections with rows
	for section: Dictionary in result.get("sections", []):
		var section_instance: Node = section_scene.instantiate()
		sections_container.add_child(section_instance)

		var title_label: Label = section_instance.get_node("%Title") as Label
		var rows_container: VBoxContainer = section_instance.get_node("%Rows") as VBoxContainer

		title_label.text = section.get("title", "")

		# Add rows to section
		for row: Dictionary in section.get("rows", []):
			var row_instance: Node = row_scene.instantiate()
			rows_container.add_child(row_instance)

			var name_label: Label = row_instance.get_node("%NameLabel") as Label
			var value_label: Label = row_instance.get_node("%ValueLabel") as Label
			var details_label: Label = row_instance.get_node("%Details") as Label
			var expand_button: Button = row_instance.get_node("%ExpandButton") as Button

			name_label.text = row.get("label", "")
			value_label.text = row.get("text", "")

			var breakdown: String = row.get("breakdown", "")
			if breakdown != "":
				details_label.text = breakdown
				expand_button.visible = true
				expand_button.toggled.connect(func(toggled: bool) -> void:
					details_label.visible = toggled
				)
			else:
				expand_button.visible = false
				details_label.visible = false

	# Add "Не учтено" section if there are notes
	var notes: Array = result.get("notes", [])
	if notes.size() > 0:
		var section_instance: Node = section_scene.instantiate()
		sections_container.add_child(section_instance)

		var title_label: Label = section_instance.get_node("%Title") as Label
		var rows_container: VBoxContainer = section_instance.get_node("%Rows") as VBoxContainer

		title_label.text = "Не учтено"

		for note: String in notes:
			var row_instance: Node = row_scene.instantiate()
			rows_container.add_child(row_instance)

			var name_label: Label = row_instance.get_node("%NameLabel") as Label
			var value_label: Label = row_instance.get_node("%ValueLabel") as Label
			var expand_button: Button = row_instance.get_node("%ExpandButton") as Button

			name_label.text = note
			value_label.text = ""
			expand_button.visible = false


func _on_hits_changed(value: float) -> void:
	Build.set_skill_hits(Build.selected_skill, value)
