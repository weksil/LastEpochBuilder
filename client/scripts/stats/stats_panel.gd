extends PanelContainer

@export var row_scene: PackedScene

@onready var rows_container: VBoxContainer = %Rows

func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	_update_stats()

func _on_build_changed() -> void:
	_update_stats()

func _update_stats() -> void:
	# Clear existing rows
	for child: Node in rows_container.get_children():
		child.queue_free()

	# Get class data
	var class_data = GameData.get_class_data(Build.class_id)

	# Add class row
	var class_title: String = "—"
	if class_data:
		class_title = class_data.className
	add_row("Класс", class_title)

	# Add mastery row
	var mastery_name: String = "Нет"
	if Build.mastery > 0 and class_data:
		if Build.mastery < class_data.masteries.size():
			mastery_name = class_data.masteries[Build.mastery].name
	add_row("Мастерство", mastery_name)

	# Add level row
	add_row("Уровень", str(Build.level))

	# Add spent points row
	add_row("Пассивных очков", str(Build.spent_points()))

func add_row(title: String, value: String) -> void:
	var row_instance: Node = row_scene.instantiate()
	rows_container.add_child(row_instance)

	var name_label: Label = row_instance.get_node("NameLabel") as Label
	var value_label: Label = row_instance.get_node("ValueLabel") as Label

	name_label.text = title
	value_label.text = value
