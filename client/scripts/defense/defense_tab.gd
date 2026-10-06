class_name DefenseTab extends VBoxContainer

## "Defense" tab (docs/UI.md): the enemy attack (boss preset or a custom hit), fight parameters, the effective health
## strip and the sections of DefenseCalc.compute. Rows are updated in place like the "Calculations" tab.

@export var section_scene: PackedScene
@export var row_scene: PackedScene

var _pending: bool = false
var _section_signature: String = ""
var _row_nodes: Array[CalcRow] = []
var _expanded: Dictionary = {}  # row key -> true
var _keys: Array[String] = []
var _dmg_spins: Array[SpinBox] = []

@onready var attack_select: SearchSelect = %AttackSelect
@onready var attack_title: Label = %AttackTitle
@onready var context_label: Label = %ContextLabel
@onready var one_shot_label: Label = %OneShotLabel
@onready var ehp_tile: CalcTile = %EhpTile
@onready var max_hit_tile: CalcTile = %MaxHitTile
@onready var hits_tile: CalcTile = %HitsTile
@onready var taken_tile: CalcTile = %TakenTile
@onready var scroll: ScrollContainer = %Scroll
@onready var area_level_spin: SpinBox = %AreaLevelSpin
@onready var corruption_spin: SpinBox = %CorruptionSpin
@onready var ward_spin: SpinBox = %WardSpin
@onready var custom_panel: PanelContainer = %CustomPanel
@onready var crit_chance_spin: SpinBox = %CritChanceSpin
@onready var crit_multi_spin: SpinBox = %CritMultiSpin
@onready var left_column: VBoxContainer = %Left
@onready var right_column: VBoxContainer = %Right
@onready var notes_block: CalcNotes = %Notes


func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	visibility_changed.connect(_on_visibility_changed)

	attack_select.clear()
	attack_select.add_item(tr("Custom hit"), 0)
	_keys.clear()
	_keys.append(DefenseCalc.CUSTOM_KEY)
	for i in range(DefenseCalc.presets().size()):
		var p: Dictionary = DefenseCalc.presets()[i]
		attack_select.add_item("%s: %s" % [p["boss"], p["label"]], i + 1)
		_keys.append(str(p["key"]))

	attack_select.item_selected.connect(_on_attack_selected)
	area_level_spin.value_changed.connect(func(v: float) -> void: Build.set_defense("area_level", int(v)))
	corruption_spin.value_changed.connect(func(v: float) -> void: Build.set_enemy("corruption", int(v)))
	ward_spin.value_changed.connect(func(v: float) -> void: Build.set_player_state("ward", v))

	for i in range(7):
		var spin: SpinBox = get_node("%Dmg" + str(i))
		_dmg_spins.append(spin)
		spin.value_changed.connect(_on_dmg_changed.bind(i))

	crit_chance_spin.value_changed.connect(func(v: float) -> void: Build.set_defense("custom_crit_chance", v / 100.0))
	crit_multi_spin.value_changed.connect(func(v: float) -> void: Build.set_defense("custom_crit_multi", v))
	_schedule_update()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_schedule_update()


func _on_build_changed() -> void:
	_schedule_update()


func _on_attack_selected(index: int) -> void:
	var id: int = attack_select.get_item_id(index)
	if id < _keys.size():
		Build.set_defense("attack", _keys[id])


## `bind(i)` appends the spin index after the new value.
func _on_dmg_changed(value: float, index: int) -> void:
	var dmg: Array = (DefenseCalc.settings_of(Build)["custom_damage"] as Array).duplicate()
	dmg[index] = value
	Build.set_defense("custom_damage", dmg)


func _schedule_update() -> void:
	if _pending:
		return
	_pending = true
	_update.call_deferred()


func _update() -> void:
	_pending = false
	if not is_visible_in_tree():
		return
	var r: Dictionary = DefenseCalc.compute(Build)
	var settings: Dictionary = DefenseCalc.settings_of(Build)
	_sync_controls(settings)
	var attack: Dictionary = r["attack"]
	attack_title.text = str(attack["label"])
	context_label.text = tr("Area level %d · corruption %d") % [int(settings["area_level"]), int(Build.enemy.get("corruption", 0))]
	var s: Dictionary = r["summary"]
	ehp_tile.show_value(_num(float(s["ehp"])), tr("raw damage you can take"))
	max_hit_tile.show_value(_num(float(s["max_hit"])), tr("one hit, no avoidance"))
	hits_tile.show_value(_num(float(s["hits"])), tr("average hits from full health") if attack["is_hit"] else tr("seconds of the damage over time"))
	taken_tile.show_value(LE.fmt_pct(float(s["taken"])), tr("of the raw damage, on average"))
	one_shot_label.visible = bool(s.get("one_shot", false))
	_update_sections(r)
	notes_block.show_notes(r.get("notes", []))


func _sync_controls(settings: Dictionary) -> void:
	var key: String = str(settings["attack"])
	var id: int = _keys.find(key)
	if id < 0:
		id = 0
	var index: int = attack_select.get_item_index(id)
	if index >= 0 and attack_select.get_selected_id() != id:
		attack_select.select(index)
	if not is_equal_approx(area_level_spin.value, float(settings["area_level"])):
		area_level_spin.set_value_no_signal(float(settings["area_level"]))
	if not is_equal_approx(corruption_spin.value, float(Build.enemy.get("corruption", 0))):
		corruption_spin.set_value_no_signal(float(Build.enemy.get("corruption", 0)))
	if not is_equal_approx(ward_spin.value, float(Build.player_state.get("ward", 0))):
		ward_spin.set_value_no_signal(float(Build.player_state.get("ward", 0)))
	for i in range(7):
		var v: float = float((settings["custom_damage"] as Array)[i])
		if not is_equal_approx(_dmg_spins[i].value, v):
			_dmg_spins[i].set_value_no_signal(v)
	if not is_equal_approx(crit_chance_spin.value, float(settings["custom_crit_chance"]) * 100.0):
		crit_chance_spin.set_value_no_signal(float(settings["custom_crit_chance"]) * 100.0)
	if not is_equal_approx(crit_multi_spin.value, float(settings["custom_crit_multi"])):
		crit_multi_spin.set_value_no_signal(float(settings["custom_crit_multi"]))
	custom_panel.visible = settings["attack"] == DefenseCalc.CUSTOM_KEY


func _update_sections(result: Dictionary) -> void:
	var sections: Array = result.get("sections", [])
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
			var is_key: bool = str(data.get("label", "")) == LE.t("Effective health")
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
	else:
		_expanded.erase(key)


static func _unique_key(seen: Dictionary, base: String) -> String:
	var count: int = int(seen.get(base, 0))
	seen[base] = count + 1
	return base if count == 0 else "%s#%d" % [base, count]


static func _num(x: float) -> String:
	if is_inf(x) or x > 1e12:
		return "∞"
	return LE.fmt_num(x)
