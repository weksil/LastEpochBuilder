extends PanelContainer

## Stats panel on the right (docs/UI.md "Stats panel"). Rows are updated in place while the set of
## stats is unchanged; changed values are highlighted by StatRow.

@export var row_scene: PackedScene
@export var group_scene: PackedScene

var _pending: bool = false
var _signature: String = ""
var _rows: Array[StatRow] = []  # stat rows only (group headers are not listed)

@onready var rows_container: VBoxContainer = %Rows
@onready var summary_card: PanelContainer = %SummaryCard
@onready var skill_name_label: Label = %SkillName
@onready var skill_summary_label: Label = %SkillSummary
@onready var skill_target_label: Label = %SkillTarget


func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	_update_stats()


## At most one recalculation per frame.
func _on_build_changed() -> void:
	if _pending:
		return
	_pending = true
	_update_stats.call_deferred()


func _update_stats() -> void:
	_pending = false
	var items: Array[Dictionary] = _collect_items()
	var sig: PackedStringArray = []
	for item: Dictionary in items:
		sig.append("%s:%s" % [item["kind"], item["key"]])
	var signature: String = "\n".join(sig)

	if signature == _signature:
		var index: int = 0
		for item: Dictionary in items:
			if item["kind"] == "row":
				_rows[index].update_row(str(item["text"]), str(item["tooltip"]), float(item["value"]))
				index += 1
	else:
		_signature = signature
		_rebuild(items)
	_update_skill_summary()


func _rebuild(items: Array[Dictionary]) -> void:
	for child: Node in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()
	_rows.clear()
	for item: Dictionary in items:
		if item["kind"] == "group":
			var group: Label = group_scene.instantiate() as Label
			rows_container.add_child(group)
			group.text = str(item["title"])
		else:
			var row: StatRow = row_scene.instantiate() as StatRow
			rows_container.add_child(row)
			row.setup(str(item["key"]), str(item["title"]), str(item["text"]), str(item["tooltip"]), float(item["value"]))
			_rows.append(row)


## Flat list of {kind: "group"|"row", key, title, text, tooltip, value (NAN if none)}.
func _collect_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []

	var class_data: Dictionary = GameData.get_class_data(Build.class_id)
	var class_title: String = "—"
	if not class_data.is_empty():
		class_title = str(class_data.get("className", "—"))
	items.append(_row_item("", tr("Class"), class_title))

	var mastery_name: String = tr("None")
	if Build.mastery > 0 and not class_data.is_empty():
		var masteries: Array = class_data.get("masteries", [])
		if Build.mastery < masteries.size():
			var mastery_data: Dictionary = masteries[Build.mastery] as Dictionary
			if not mastery_data.is_empty():
				mastery_name = str(mastery_data.get("name", tr("None")))
	items.append(_row_item("", tr("Mastery"), mastery_name))
	items.append(_row_item("", tr("Level"), str(Build.level)))
	items.append(_row_item("", tr("Passive points"), str(Build.spent_points())))

	var g: Dictionary = BuildMods.global_store(Build)
	var global_store: StatStore = g["store"]
	var char_rows: Array[Dictionary] = CharacterCalc.compute(global_store, Build)

	var groups: Dictionary = {}
	for row: Dictionary in char_rows:
		var group_name: String = str(row.get("group", ""))
		if group_name not in groups:
			groups[group_name] = []
		groups[group_name].append(row)

	for group_name: String in groups.keys():
		items.append({"kind": "group", "key": group_name, "title": group_name})
		for row: Dictionary in groups[group_name]:
			var number: float = NAN
			var raw: Variant = row.get("value")
			if raw is float or raw is int:
				number = float(raw)
			items.append(_row_item(group_name, str(row.get("label", "")), str(row.get("text", "")), str(row.get("breakdown", "")), number))
	return items


static func _row_item(group_name: String, title: String, text: String, tooltip: String = "", value: float = NAN) -> Dictionary:
	return {"kind": "row", "key": group_name + "|" + title, "title": title, "text": text, "tooltip": tooltip, "value": value}


func _update_skill_summary() -> void:
	summary_card.visible = false
	if Build.selected_skill < 0 or Build.selected_skill >= Build.skills.size():
		return
	var skill: Dictionary = Build.skills[Build.selected_skill] as Dictionary
	if skill.is_empty() or str(skill.get("ability", "")) == "":
		return

	var result: Dictionary = SkillCalc.compute(Build, Build.selected_skill)
	var dps: Dictionary = CalcSummary.find_row(result, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION)
	if dps.is_empty():
		return
	summary_card.visible = true
	skill_name_label.text = tr("%s · DPS vs enemy") % str(result.get("title", ""))
	skill_summary_label.text = str(dps.get("text", ""))
	skill_target_label.text = tr("target: %s") % Enemy.describe(Build.enemy)
	summary_card.tooltip_text = str(dps.get("breakdown", ""))
