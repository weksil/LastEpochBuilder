extends ScrollContainer

@export var row_scene: PackedScene

var _rows: Array[Node] = []


func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	_create_rows()


func _create_rows() -> void:
	# Clear existing rows
	for row: Node in _rows:
		row.queue_free()
	_rows.clear()

	# Create one row per timeline, filtering out Activities (timelineID 99)
	var timelines: Array = GameData.blessing_timelines()
	for timeline: Dictionary in timelines:
		var timeline_id: int = int(timeline.get("timelineID", -1))
		if timeline_id == 99:  # Skip Activities
			continue

		var display_name: Variant = timeline.get("displayName")
		if display_name == null:  # Skip timelines without display names
			continue

		if row_scene == null:
			push_error("BlessingsTab: row_scene not assigned")
			return

		var row: Node = row_scene.instantiate()
		%Rows.add_child(row)
		_rows.append(row)

		# Call setup with the timeline data
		if row.has_method("setup"):
			row.setup(timeline)


func _on_build_changed() -> void:
	# Rows handle their own updates via Build.changed signal
	pass
