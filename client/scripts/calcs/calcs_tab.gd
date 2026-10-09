extends VBoxContainer

class_name CalcsTab

## "Calculations" tab (docs/UI.md): headline strip, calculation parameters, skill buffs on the character, sections of
## SkillCalc.compute in a fixed order. Everything is updated in place while the set of rows is unchanged, so typing in a
## SpinBox is never interrupted and expanded breakdowns stay open.

## Row whose value is highlighted as the main result.
## Fixed engine label (English source; compared with LE.t(KEY_ROW_LABEL)).
const KEY_ROW_LABEL: String = "DPS vs enemy"
## [title marker (English source, translated at match time), rank]: sections are shown in rank order (damage, conversions,
## crit, speed, ailments, parameters, enemy, sustain). A marker must start the title or follow a "Component: " prefix.
const SECTION_RULES: Array = [
	["Granted skill", -1], ["Against enemy", 6], ["Sustain", 7], ["Skill parameters", 5], ["Speed and mana", 3],
	["Penetration", 2], ["Crit", 2], ["Conversions and tags", 1], ["Damage per use (before enemy)", 0],
	["Effect damage over its whole duration (before enemy)", 0], ["Damage per hit on the cursed target (before enemy)", 0],
	["Ailment: %s", 4], ["Non-damaging ailments", 4],
]

@export var section_scene: PackedScene
@export var row_scene: PackedScene
@export var input_row_scene: PackedScene

var _pending: bool = false
var _skill_options_key: String = ""
## Granted skill (GrantedCalc) shown instead of a bar slot, "" for a bar skill. Not stored in the build: Build.selected_skill
## always stays a valid bar slot.
var _virtual_id: String = ""
var _granted: Array[Dictionary] = []
var _real_slot: int = 0
var _input_signature: String = ""
var _input_rows: Array[SkillInputRow] = []
var _section_signature: String = ""
var _row_nodes: Array[CalcRow] = []
var _expanded: Dictionary = {}  # row key -> true
var _lean: bool = false  # the shown result has no breakdowns (SkillCalc.compute without details)

@onready var skill_select: OptionButton = %SkillSelect
@onready var summary: CalcSummary = %Summary
@onready var scroll: ScrollContainer = %Scroll
@onready var left_column: VBoxContainer = %Left
@onready var right_column: VBoxContainer = %Right
@onready var hits_spin: SpinBox = %HitsSpin
@onready var inputs_container: GridContainer = %Inputs
@onready var buffs_panel: BuffsPanel = %Buffs
@onready var notes_block: CalcNotes = %Notes


func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	visibility_changed.connect(_on_visibility_changed)
	skill_select.item_selected.connect(_on_skill_selected)
	hits_spin.value_changed.connect(_on_hits_changed)
	_populate_skill_options()
	_schedule_update()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_populate_skill_options()
		_schedule_update()


func _on_build_changed() -> void:
	# another view moved the selected bar slot: follow it
	if _virtual_id != "" and Build.selected_skill != _real_slot:
		_virtual_id = ""
	_populate_skill_options()
	_schedule_update()


func _on_skill_selected(index: int) -> void:
	var id: Variant = skill_select.get_item_metadata(index)
	if id is String and id != "":
		_virtual_id = id
		_schedule_update()
		return
	_virtual_id = ""
	_real_slot = index
	Build.selected_skill = index
	_schedule_update()


## At most one recalculation per frame, and only while the tab is shown.
func _schedule_update() -> void:
	if _pending:
		return
	_pending = true
	_update_calcs.call_deferred()


func _populate_skill_options() -> void:
	if is_visible_in_tree():
		_granted = GrantedCalc.skills(Build)
	var granted_ids: Array[String] = []
	for entry: Dictionary in _granted:
		granted_ids.append(str(entry["id"]))
	# the granted skill is gone after a change of the build: back to the bar slot
	if _virtual_id != "" and not granted_ids.has(_virtual_id) and is_visible_in_tree():
		_virtual_id = ""
	var names: PackedStringArray = []
	for i in range(5):
		var skill: Dictionary = Build.skills[i] if i < Build.skills.size() else {}
		var ability_id: String = str(skill.get("ability", ""))
		var skill_name: String = "—"
		if ability_id != "":
			var ability: Dictionary = GameData.get_ability(ability_id)
			if not ability.is_empty():
				skill_name = GameData.display_name(ability)
		names.append("%d. %s" % [i + 1, skill_name])
	for entry: Dictionary in _granted:
		names.append(GrantedCalc.label(entry))
	var key: String = "|".join(names) + "#" + ",".join(granted_ids)
	if key != _skill_options_key:
		_skill_options_key = key
		skill_select.clear()
		for i in range(5):
			skill_select.add_item(names[i])
		if not _granted.is_empty():
			skill_select.add_separator(tr("Granted skills"))
			for i in range(_granted.size()):
				skill_select.add_item(names[5 + i])
				skill_select.set_item_metadata(skill_select.item_count - 1, granted_ids[i])
	var selected: int = Build.selected_skill
	if _virtual_id != "":
		for i in range(skill_select.item_count):
			if skill_select.get_item_metadata(i) == _virtual_id:
				selected = i
	_real_slot = Build.selected_skill
	if skill_select.selected != selected:
		skill_select.select(selected)


func _update_calcs() -> void:
	_pending = false
	if not is_visible_in_tree():
		return
	# breakdowns are built only while a row is expanded; otherwise the rows show "+" and build them on demand
	var result: Dictionary
	if _virtual_id != "":
		result = GrantedCalc.compute(Build, _virtual_id, not _expanded.is_empty())
	else:
		result = SkillCalc.compute(Build, Build.selected_skill, not _expanded.is_empty())
	_lean = bool(result.get("lean", false))
	summary.show_result(result)
	_update_inputs(result)
	_update_sections(result)
	notes_block.show_notes(result.get("notes", []))
	buffs_panel.refresh()


# --- parameters ---------------------------------------------------------------------

func _update_inputs(result: Dictionary) -> void:
	var hits: float = float(result.get("hits", 1.0))
	if not is_equal_approx(hits_spin.value, hits):
		hits_spin.set_value_no_signal(hits)

	var inputs: Array = result.get("inputs", [])
	# a granted skill edits the event rates of the bar skill that owns it
	var input_slot: int = int(result.get("input_slot", Build.selected_skill))
	var sig: PackedStringArray = [str(input_slot), _virtual_id]
	for inp: Dictionary in inputs:
		sig.append("%s|%s" % [str(inp.get("key", "")), "f" if inp.get("value", 0) is bool else "n"])
	var signature: String = ";".join(sig)
	if signature != _input_signature:
		_input_signature = signature
		for row: SkillInputRow in _input_rows:
			inputs_container.remove_child(row)
			row.queue_free()
		_input_rows.clear()
		for inp: Dictionary in inputs:
			var row: SkillInputRow = input_row_scene.instantiate() as SkillInputRow
			inputs_container.add_child(row)
			row.setup(input_slot, inp)
			_input_rows.append(row)
		return
	for i in range(inputs.size()):
		_input_rows[i].update_input(input_slot, inputs[i])


# --- sections ------------------------------------------------------------------------

func _update_sections(result: Dictionary) -> void:
	var sections: Array = ordered_sections(result.get("sections", []))
	if sections.is_empty():
		sections = [{
			"title": tr("No skill"),
			"rows": [{"label": tr("Pick a skill in the \"Skills\" tab"), "text": "", "breakdown": ""}],
		}]

	# identity of every section and row: title / label, repeated ones get a counter
	var entries: Array[Dictionary] = []
	var sig: PackedStringArray = []
	var section_seen: Dictionary = {}
	for section: Dictionary in sections:
		var title: String = str(section.get("title", ""))
		var section_key: String = _unique_key(section_seen, title)
		sig.append("S:" + section_key)
		var row_seen: Dictionary = {}
		var section_rows: Array = []
		for row: Dictionary in section.get("rows", []):
			var row_key: String = section_key + "|" + _unique_key(row_seen, str(row.get("label", "")))
			sig.append("R:" + row_key)
			section_rows.append({"key": row_key, "row": row})
		entries.append({"title": title, "rows": section_rows})
	var signature: String = "\n".join(sig)

	if signature == _section_signature:
		var index: int = 0
		for entry: Dictionary in entries:
			for item: Dictionary in entry["rows"]:
				_row_nodes[index].update_row(item["row"])
				index += 1
		return

	_section_signature = signature
	var scroll_pos: int = scroll.scroll_vertical
	_rebuild_sections(entries)
	_restore_scroll.call_deferred(scroll_pos)


func _rebuild_sections(entries: Array[Dictionary]) -> void:
	for column: VBoxContainer in [left_column, right_column]:
		for child: Node in column.get_children():
			column.remove_child(child)
			child.queue_free()
	_row_nodes.clear()

	var total: int = 0
	for entry: Dictionary in entries:
		total += (entry["rows"] as Array).size() + 2
	var placed: int = 0
	for entry: Dictionary in entries:
		# sequential fill: the first half of the sections (by rows) goes left, the rest right
		var column: VBoxContainer = left_column if placed * 2 < total else right_column
		placed += (entry["rows"] as Array).size() + 2
		var section: Node = section_scene.instantiate()
		column.add_child(section)
		(section.get_node("%Title") as Label).text = str(entry["title"])
		var rows_container: VBoxContainer = section.get_node("%Rows") as VBoxContainer
		var alt: bool = false
		for item: Dictionary in entry["rows"]:
			var row: CalcRow = row_scene.instantiate() as CalcRow
			rows_container.add_child(row)
			var key: String = str(item["key"])
			var data: Dictionary = item["row"]
			# the total of a component, not the "DPS vs enemy" of an ailment section
			var is_key: bool = str(data.get("label", "")) == LE.t(KEY_ROW_LABEL) and str(entry["title"]).ends_with(LE.t(CalcSummary.ENEMY_SECTION))
			row.setup(key, data, alt, _expanded.has(key), is_key)
			row.expanded_changed.connect(_on_row_expanded)
			_row_nodes.append(row)
			alt = not alt


func _restore_scroll(pos: int) -> void:
	await get_tree().process_frame
	if is_inside_tree():
		scroll.scroll_vertical = pos


func _on_row_expanded(key: String, expanded: bool) -> void:
	if expanded:
		_expanded[key] = true
		if _lean:
			_schedule_update()
	else:
		_expanded.erase(key)


## Position of a section marker in a title: at the start or right after a "Component: " prefix; -1 if absent.
static func _marker_at(title: String, source: String) -> int:
	var marker: String = LE.t(source).replace("%s", "")
	var from: int = 0
	while from <= title.length():
		var at: int = title.find(marker, from)
		if at < 0:
			return -1
		if at == 0 or title.substr(at - 2, 2) == ": ":
			return at
		from = at + 1
	return -1


static func _unique_key(seen: Dictionary, base: String) -> String:
	var count: int = int(seen.get(base, 0))
	seen[base] = count + 1
	return base if count == 0 else "%s#%d" % [base, count]


## Sections in a fixed reading order: the main component first (damage → conversions → crit → speed and mana →
## ailments → parameters → against the enemy → sustain), then every other component (summons, triggers) the same way.
static func ordered_sections(sections: Array) -> Array:
	var prefixes: Array[String] = [""]
	var keyed: Array[Dictionary] = []
	for i in range(sections.size()):
		var section: Dictionary = sections[i]
		var title: String = str(section.get("title", ""))
		var rank: int = SECTION_RULES.size() + 1
		var prefix: String = ""
		for rule: Array in SECTION_RULES:
			var at: int = _marker_at(title, str(rule[0]))
			if at >= 0:
				rank = int(rule[1])
				prefix = title.substr(0, at)
				break
		if not prefixes.has(prefix):
			prefixes.append(prefix)
		keyed.append({"group": prefixes.find(prefix), "rank": rank, "index": i, "section": section})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["group"] != b["group"]:
			return int(a["group"]) < int(b["group"])
		if a["rank"] != b["rank"]:
			return int(a["rank"]) < int(b["rank"])
		return int(a["index"]) < int(b["index"]))
	var result: Array = []
	for item: Dictionary in keyed:
		result.append(item["section"])
	return result


func _on_hits_changed(value: float) -> void:
	Build.set_skill_hits(Build.selected_skill, value)
