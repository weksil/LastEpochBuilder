extends PanelContainer

@export var row_scene: PackedScene
@export var group_scene: PackedScene

@onready var rows_container: VBoxContainer = %Rows
@onready var skill_summary_label: Label = %SkillSummary


func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	_update_stats()


func _on_build_changed() -> void:
	call_deferred("_update_stats")


func _update_stats() -> void:
	# Clear existing rows
	for child: Node in rows_container.get_children():
		child.queue_free()

	# Get class data
	var class_data: Dictionary = GameData.get_class_data(Build.class_id)

	# Add class row
	var class_title: String = "—"
	if not class_data.is_empty():
		class_title = class_data.get("className", "—")
	_add_simple_row("Класс", class_title)

	# Add mastery row
	var mastery_name: String = "Нет"
	if Build.mastery > 0 and not class_data.is_empty():
		var masteries: Array = class_data.get("masteries", [])
		if Build.mastery < masteries.size():
			var mastery_data: Dictionary = masteries[Build.mastery] as Dictionary
			if not mastery_data.is_empty():
				mastery_name = mastery_data.get("name", "Нет")
	_add_simple_row("Мастерство", mastery_name)

	# Add level row
	_add_simple_row("Уровень", str(Build.level))

	# Add spent points row
	_add_simple_row("Пассивных очков", str(Build.spent_points()))

	# Compute global mods and character stats
	var g: Dictionary = BuildMods.global_store(Build)
	var global_store: StatStore = g["store"]

	var char_rows: Array[Dictionary] = CharacterCalc.compute(global_store, Build)

	# Group rows by group name
	var groups: Dictionary = {}
	for row: Dictionary in char_rows:
		var group_name: String = row.get("group", "")
		if group_name not in groups:
			groups[group_name] = []
		groups[group_name].append(row)

	# Add rows by group
	for group_name: String in groups.keys():
		# Add group label
		var group_instance: Node = group_scene.instantiate()
		rows_container.add_child(group_instance)
		var group_label: Label = group_instance as Label
		group_label.text = group_name

		# Add rows in group
		for row: Dictionary in groups[group_name]:
			_add_stat_row(
				row.get("label", ""),
				row.get("text", ""),
				row.get("breakdown", "")
			)

	# Update skill summary
	_update_skill_summary()


func _add_simple_row(title: String, value: String) -> void:
	var row_instance: Node = row_scene.instantiate()
	rows_container.add_child(row_instance)

	var name_label: Label = row_instance.get_node("NameLabel") as Label
	var value_label: Label = row_instance.get_node("ValueLabel") as Label

	name_label.text = title
	value_label.text = value


func _add_stat_row(title: String, value: String, breakdown: String) -> void:
	var row_instance: Node = row_scene.instantiate()
	rows_container.add_child(row_instance)

	var name_label: Label = row_instance.get_node("NameLabel") as Label
	var value_label: Label = row_instance.get_node("ValueLabel") as Label

	name_label.text = title
	value_label.text = value

	if breakdown != "":
		row_instance.tooltip_text = breakdown


func _update_skill_summary() -> void:
	skill_summary_label.text = ""

	# Check if selected skill has an ability
	if Build.selected_skill < 0 or Build.selected_skill >= Build.skills.size():
		return

	var skill: Dictionary = Build.skills[Build.selected_skill] as Dictionary
	if skill.is_empty() or skill.get("ability", "") == "":
		return

	# Compute skill
	var result: Dictionary = SkillCalc.compute(Build, Build.selected_skill)
	var sections: Array = result.get("sections", [])

	# Extract DPS from "Против врага" or "DPS" sections
	var dps_value: String = ""
	var tooltip: String = ""

	var enemy_dps: String = ""
	var tooltip_dps: String = ""
	for section: Dictionary in sections:
		for row: Dictionary in section.get("rows", []):
			if row.get("label") == "DPS по врагу":
				enemy_dps = str(row.get("text", ""))
				tooltip = str(row.get("breakdown", ""))
			elif row.get("label") == "DPS" and str(section.get("title", "")).begins_with("DPS"):
				tooltip_dps = str(row.get("text", ""))
	dps_value = enemy_dps

	if dps_value != "":
		skill_summary_label.text = "%s: DPS по врагу %s (подсказка игры %s)" % [str(result.get("title", "")), enemy_dps, tooltip_dps]
		skill_summary_label.tooltip_text = tooltip
