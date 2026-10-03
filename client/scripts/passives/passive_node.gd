class_name PassiveNode
extends Button

signal add_requested(node_id: int)
signal remove_requested(node_id: int)

var node_id: int
var max_points: int

func setup(node: Dictionary, stats: Dictionary) -> void:
	node_id = int(node["id"])
	max_points = int(node["maxPoints"])

	var title: String = str(node["displayName"]) if node.get("displayName") != null else str(node.get("name", ""))
	var name_label: Label = %NameLabel
	name_label.text = title

	var tooltip_parts: PackedStringArray = []

	tooltip_parts.append(title)

	if stats.get("nodeDescription") is String and stats["nodeDescription"] != "":
		tooltip_parts.append(stats["nodeDescription"])

	if stats.has("tooltipStats"):
		for stat in stats["tooltipStats"]:
			if stat.has("statName") and stat.has("value"):
				tooltip_parts.append("%s %s" % [str(stat["statName"]), str(stat["value"])])

	tooltip_parts.append("Макс. очков: %d" % max_points)

	tooltip_text = "\n".join(tooltip_parts)

func set_state(points: int, can_add: bool) -> void:
	var points_label: Label = %PointsLabel
	points_label.text = "%d/%d" % [points, max_points]

	if points > 0:
		theme_type_variation = &"PassiveNodeAllocated"
	elif can_add:
		theme_type_variation = &"PassiveNodeAvailable"
	else:
		theme_type_variation = &"PassiveNodeLocked"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			add_requested.emit(node_id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			remove_requested.emit(node_id)
			accept_event()
