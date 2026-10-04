extends ScrollContainer

## The stat summary is recomputed at most this often (20 times a second) while a roll slider is dragged.
const DIFF_INTERVAL_MSEC: int = 50

@export var row_scene: PackedScene
@export var diff_line_scene: PackedScene

var _rows: Array[Node] = []
var _diff_queued: bool = false
var _last_diff_msec: int = -DIFF_INTERVAL_MSEC


func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	%DiffTimer.timeout.connect(update_summary)
	visibility_changed.connect(_queue_summary)
	_create_rows()
	_queue_summary()


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
	_queue_summary()


## Recomputes %Summary after the edits at most every DIFF_INTERVAL_MSEC; only while the tab is shown.
func _queue_summary() -> void:
	if _diff_queued or not is_visible_in_tree():
		return
	_diff_queued = true
	var wait_msec: int = _last_diff_msec + DIFF_INTERVAL_MSEC - Time.get_ticks_msec()
	if wait_msec <= 0:
		update_summary.call_deferred()
	else:
		%DiffTimer.start(wait_msec / 1000.0)


## The stat changes of all chosen blessings against none (same lines as the item diff); hidden without blessings.
func update_summary() -> void:
	_diff_queued = false
	_last_diff_msec = Time.get_ticks_msec()
	for child: Node in %SummaryLines.get_children():
		%SummaryLines.remove_child(child)
		child.queue_free()
	%Summary.visible = not Build.blessings.is_empty()
	if not %Summary.visible:
		return
	var before: Dictionary = ItemCompare.snapshot_with_blessings(Build, {})
	var after: Dictionary = ItemCompare.snapshot(Build)
	_show_dps(before.get("dps", {}), after.get("dps", {}))
	before.erase("dps")
	after.erase("dps")
	var lines: Array[Dictionary] = ItemCompare.diff(before, after)
	for line: Dictionary in lines:
		var label: Label = diff_line_scene.instantiate()
		%SummaryLines.add_child(label)
		label.text = str(line.get("text", ""))
		label.theme_type_variation = &"DeltaUp" if float(line.get("delta", 0.0)) > 0.0 else &"DeltaDown"
	%SummaryLines.visible = not lines.is_empty()
	%SummaryNone.visible = lines.is_empty() and not %SummaryDps.visible


## %SummaryDps: DPS vs enemy of the skill selected in Calculations without and with the blessings (hidden without DPS).
func _show_dps(before: Dictionary, after: Dictionary) -> void:
	var dps_label: Label = %SummaryDps
	var source: Dictionary = after if not after.is_empty() else before
	dps_label.visible = not source.is_empty()
	if source.is_empty():
		return
	var old_value: float = float(before.get("value", 0.0))
	var new_value: float = float(after.get("value", 0.0))
	var delta: float = new_value - old_value
	var title: String = str(source.get("label", ""))
	if absf(delta) < ItemCompare.EPSILON:
		dps_label.text = tr("%s: %s (no change)") % [title, LE.fmt_num(new_value)]
		dps_label.theme_type_variation = &"MutedLabel"
	else:
		dps_label.text = "%s: %s → %s (%s)" % [title, LE.fmt_num(old_value), LE.fmt_num(new_value), ItemCompare.format_delta(delta, false)]
		dps_label.theme_type_variation = &"DeltaUp" if delta > 0.0 else &"DeltaDown"
