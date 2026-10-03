extends Control

@onready var class_select: OptionButton = %ClassSelect
@onready var mastery_select: OptionButton = %MasterySelect
@onready var level_spin: SpinBox = %LevelSpin

func _ready() -> void:
	# Fill ClassSelect with class names
	for class_data in GameData.classes:
		class_select.add_item(class_data.className, int(class_data.classID))

	# Connect ClassSelect to update class and refill masteries
	class_select.item_selected.connect(_on_class_selected)

	# Connect MasterySelect
	mastery_select.item_selected.connect(_on_mastery_selected)

	# Connect LevelSpin
	level_spin.value_changed.connect(_on_level_changed)

	# Initialize LevelSpin value
	level_spin.value = Build.level

	# Select the first class and trigger initial setup
	class_select.select(0)
	_on_class_selected(0)

func _on_class_selected(index: int) -> void:
	var class_id: int = int(class_select.get_item_id(index))
	Build.set_class(class_id)

	# Refill MasterySelect
	mastery_select.clear()
	mastery_select.add_item("Без мастерства", 0)

	var class_data = GameData.get_class_data(class_id)
	if class_data:
		for i: int in range(1, class_data.masteries.size()):
			mastery_select.add_item(class_data.masteries[i].name, i)

func _on_mastery_selected(index: int) -> void:
	Build.set_mastery(index)

func _on_level_changed(value: float) -> void:
	Build.set_level(int(value))
