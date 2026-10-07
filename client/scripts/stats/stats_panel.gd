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
@onready var skill_breakdown_label: Label = %SkillBreakdown
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

	# the buffs on you of the "Buffs on me" list without a number set take the averages of the selected skill
	var saved: Dictionary = EnemyAilments.apply(Build, Build.selected_skill)
	var g: Dictionary = BuildMods.global_store(Build)
	var global_store: StatStore = g["store"]
	var char_rows: Array[Dictionary] = CharacterCalc.compute(global_store, Build)
	EnemyAilments.restore(Build, saved)

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


## Total DPS vs enemy of every skill on the bar, with the share of each skill below it.
func _update_skill_summary() -> void:
	var parts: Array[Dictionary] = []
	var total: float = 0.0
	for slot: int in range(Build.skills.size()):
		if str((Build.skills[slot] as Dictionary).get("ability", "")) == "":
			continue
		var result: Dictionary = SkillCalc.compute(Build, slot)
		var dps: Dictionary = CalcSummary.find_row(result, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION)
		var value: Variant = dps.get("value")
		if not (value is float or value is int) or float(value) <= 0.0:
			continue
		total += float(value)
		var title: String = str(result.get("title", ""))
		var breakdown: String = str(dps.get("breakdown", ""))
		var proj: Dictionary = result.get("projectiles", {})
		if not proj.is_empty():
			# projectiles hitting the target used for the DPS, then shotgun and the max per use in the tooltip
			title = tr("%s (%s proj)") % [title, LE.fmt_num(float(proj["factor"]))]
			breakdown = tr("Projectiles: %s in the calculation, max %s per use, shotgun: %s") % [LE.fmt_num(float(proj["factor"])),
				LE.fmt_num(float(proj["count"])), tr("yes") if bool(proj["shotgun"]) else tr("no")] + "
" + breakdown
		parts.append({"title": title, "value": float(value), "breakdown": breakdown})
	summary_card.visible = not parts.is_empty()
	if parts.is_empty():
		return
	parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])
	var lines: PackedStringArray = []
	var tips: PackedStringArray = []
	for part: Dictionary in parts:
		lines.append("%s — %s" % [part["title"], LE.fmt_num(part["value"])])
		tips.append("%s: %s
%s" % [part["title"], LE.fmt_num(part["value"]), part["breakdown"]])
	skill_summary_label.text = LE.fmt_num(total)
	skill_breakdown_label.text = "
".join(lines)
	skill_target_label.text = tr("target: %s") % Enemy.describe(Build.enemy)
	summary_card.tooltip_text = "

".join(tips)
