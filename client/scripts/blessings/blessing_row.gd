extends HBoxContainer

var _timeline: Dictionary = {}
var _current_blessing_id: int = -1


func _ready() -> void:
	%BlessingSelect.item_selected.connect(_on_blessing_selected)
	%RollSlider.value_changed.connect(_on_roll_changed)
	Build.changed.connect(_on_build_changed)


func setup(timeline: Dictionary) -> void:
	_timeline = timeline
	var timeline_id: int = int(timeline.get("timelineID", -1))
	var display_name: String = str(timeline.get("displayName", ""))

	%TimelineLabel.text = display_name

	# Fill blessing select with "— нет —" + blessings
	%BlessingSelect.clear()
	%BlessingSelect.add_item("— нет —", -1)

	var blessing_ids: Array[int] = GameData.blessings_for_timeline(timeline_id)
	for blessing_id: int in blessing_ids:
		var blessing: Dictionary = GameData.blessing(blessing_id)
		if blessing.is_empty():
			continue
		var blessing_name: String = str(blessing.get("displayName", str(blessing_id)))
		%BlessingSelect.add_item(blessing_name, blessing_id)

	# Restore current selection from Build
	_on_build_changed()


func _on_blessing_selected(index: int) -> void:
	var meta: Variant = %BlessingSelect.get_item_metadata(index)
	if meta == null:
		return
	var blessing_id: int = int(meta)
	var timeline_id: int = int(_timeline.get("timelineID", -1))
	if blessing_id < 0:
		Build.set_blessing(timeline_id, -1, 0)
	else:
		var roll: int = int(%RollSlider.value)
		Build.set_blessing(timeline_id, blessing_id, roll)


func _on_roll_changed(value: float) -> void:
	var roll: int = int(value)
	var timeline_id: int = int(_timeline.get("timelineID", -1))

	# Update value label
	_update_value_label()

	# Only update if a blessing is selected
	if _current_blessing_id >= 0:
		Build.set_blessing(timeline_id, _current_blessing_id, roll)


func _on_build_changed() -> void:
	var timeline_id: int = int(_timeline.get("timelineID", -1))

	# Get current blessing from Build
	var blessing_data: Dictionary = Build.blessings.get(timeline_id, {})
	var selected_id: int = int(blessing_data.get("id", -1))
	var roll: int = int(blessing_data.get("roll", 255))

	_current_blessing_id = selected_id
	%RollSlider.value = roll

	# Update select
	for i in range(%BlessingSelect.item_count):
		var meta: Variant = %BlessingSelect.get_item_metadata(i)
		if meta != null and int(meta) == selected_id:
			%BlessingSelect.select(i)
			break

	_update_value_label()


func _update_value_label() -> void:
	if _current_blessing_id < 0:
		%ValueLabel.text = ""
		return

	var blessing: Dictionary = GameData.blessing(_current_blessing_id)
	if blessing.is_empty():
		%ValueLabel.text = ""
		return

	var roll: int = int(%RollSlider.value)
	var implicits: Array = blessing.get("implicits", [])
	var parts: Array[String] = []

	for implicit: Dictionary in implicits:
		var property: int = int(implicit.get("property", 0))
		if property == 104:  # Skip IncreasedDropRate
			continue

		var modType: String = str(implicit.get("modType", "ADDED"))
		var value: float = float(implicit.get("value", 0.0))
		var maxValue: float = float(implicit.get("maxValue", value))
		var rounding: String = str(implicit.get("rounding", "Integer"))

		var rolled_value: float = AffixMath.roll_value(value, maxValue, rounding, modType, roll, 0.0)
		var formatted: String = LE.fmt_num(rolled_value)

		if modType == "INCREASED" or modType == "MORE":
			formatted += "%"

		parts.append(formatted)

	%ValueLabel.text = " / ".join(parts)
