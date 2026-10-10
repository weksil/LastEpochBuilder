extends ScrollContainer

## "Conditions" tab (docs/UI.md): player conditions, enemy and its ailments. Only conditions with a source in the build are shown
## (ConfigRelevance), already switched-on ones always; every group has a one-line summary of what is on.

const RELEVANCE_PATH: String = "res://scripts/engine/config_relevance.gd"
const HEALTH_VALUES: PackedStringArray = ["full", "high", "normal", "low"]
const KIND_VALUES: PackedStringArray = ["dummy", "normal", "magic", "rare", "miniboss", "boss"]
const MAX_LISTED: int = 8
## Enemy flags that are on by default (Build._init_defaults); only a deviation counts as "set".
const ENEMY_FLAG_DEFAULTS: Dictionary = {"high_health": true, "full_health": true}
## Player numbers whose default is not 0 (Build.default_player_state); the default is not shown as an active override.
const PLAYER_VALUE_DEFAULTS: Dictionary = {"target_distance": 1.0, "attacker_distance": 1.0}

@export var ailment_row_scene: PackedScene
@export var minion_row_scene: PackedScene

var _pending: bool = false
var _relevance: Dictionary = {}
var _relevance_known: bool = false
var _ailment_rows: Dictionary = {}  # ailment id -> AilmentRow
var _ailment_order: String = ""
var _minion_rows: Dictionary = {}  # MinionCount key or actor name -> MinionRow
var _minions_shown: int = 0
var _buff_rows: Dictionary = {}  # ailment id -> AilmentRow of a buff on the player
var _buffs_shown: int = 0
var _player_flag_checks: Array[CheckBox] = []
var _player_value_spins: Array[SpinBox] = []
var _enemy_flag_checks: Array[CheckBox] = []
var _resistance_spins: Array[SpinBox] = []
var _player_shown: int = 0
var _enemy_shown: int = 0
var _ailments_shown: int = 0

@onready var _show_all: CheckBox = %ShowAllCheck
@onready var _empty_hint: Label = %EmptyHint
@onready var _player_flags_grid: GridContainer = %PlayerFlags
@onready var _player_values_box: VBoxContainer = %PlayerValues
@onready var _enemy_flags_title: Label = %FlagsTitle
@onready var _enemy_flags_grid: GridContainer = %EnemyFlags
@onready var _player_summary: Label = %PlayerSummary
@onready var _enemy_summary: Label = %EnemySummary
@onready var _ailment_summary: Label = %AilmentSummary
@onready var _ailment_list: VBoxContainer = %AilmentList
@onready var _buff_summary: Label = %BuffSummary
@onready var _minion_summary: Label = %MinionSummary
@onready var _minion_list: VBoxContainer = %MinionList
@onready var _buff_list: VBoxContainer = %BuffList
@onready var _filter: LineEdit = %Filter
@onready var _health_select: OptionButton = %HealthSelect
@onready var _kind_select: OptionButton = %KindSelect
@onready var _level_spin: SpinBox = %LevelSpin
@onready var _area_level_spin: SpinBox = %AreaLevelSpin
@onready var _armour_spin: SpinBox = %ArmourSpin
@onready var _corruption_spin: SpinBox = %CorruptionSpin


func _ready() -> void:
	_health_select.item_selected.connect(_on_health_selected)
	_kind_select.item_selected.connect(_on_kind_selected)
	_level_spin.value_changed.connect(func(value: float) -> void: Build.set_enemy("level", int(value)))
	_area_level_spin.value_changed.connect(func(value: float) -> void: Build.set_enemy("area_level", int(value)))
	_armour_spin.value_changed.connect(func(value: float) -> void: Build.set_enemy("armour", int(value)))
	_corruption_spin.value_changed.connect(func(value: float) -> void: Build.set_enemy("corruption", int(value)))
	_show_all.toggled.connect(func(_on: bool) -> void: _refresh())
	_filter.text_changed.connect(func(_text: String) -> void:
		_apply_ailments()
		_apply_buffs())
	%ResetAilmentsButton.pressed.connect(func() -> void: Build.clear_enemy_ailments())
	%ResetPlayerButton.pressed.connect(func() -> void: Build.reset_player_conditions())
	%ResetBuffsButton.pressed.connect(func() -> void: Build.clear_player_buffs())
	%ResetMinionsButton.pressed.connect(func() -> void: Build.clear_minion_counts())

	for node: Node in %PlayerFlags.find_children("*", "CheckBox", true, false):
		var check: CheckBox = node as CheckBox
		_player_flag_checks.append(check)
		check.toggled.connect(_on_player_flag_toggled.bind(check))
	for node: Node in %PlayerValues.find_children("*", "SpinBox", true, false):
		var spin: SpinBox = node as SpinBox
		_player_value_spins.append(spin)
		spin.value_changed.connect(_on_player_value_changed.bind(spin))
	for node: Node in %EnemyFlags.find_children("*", "CheckBox", true, false):
		var check: CheckBox = node as CheckBox
		_enemy_flag_checks.append(check)
		check.toggled.connect(_on_enemy_flag_toggled.bind(check))
	for node: Node in %EnemyGrid.get_children():
		if node is SpinBox and node.has_meta("res_index"):
			var spin: SpinBox = node as SpinBox
			_resistance_spins.append(spin)
			spin.value_changed.connect(_on_resistance_changed.bind(spin))

	_populate_ailments()
	_populate_buffs()
	Build.changed.connect(_on_build_changed)
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _on_build_changed() -> void:
	_schedule_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_schedule_refresh()


## At most one refresh per frame, and only while the tab is shown.
func _schedule_refresh() -> void:
	if _pending:
		return
	_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	_pending = false
	if not is_visible_in_tree():
		return
	_compute_relevance()
	_sync_values()
	_apply_player()
	_apply_enemy()
	_apply_ailments()
	_apply_buffs()
	_apply_minions()
	_empty_hint.visible = _relevance_known and not _show_all.button_pressed and _player_shown == 0 and _enemy_shown == 0 		and _ailments_shown == 0 and _buffs_shown == 0 and _minions_shown == 0


# --- relevance ------------------------------------------------------------------------

## ConfigRelevance.compute(Build): {player_flags, player_values, ailments, enemy} → reason text per relevant key.
## Without the file (or when it fails to load) every condition counts as relevant.
func _compute_relevance() -> void:
	_relevance_known = false
	_relevance = {}
	if not ResourceLoader.exists(RELEVANCE_PATH):
		return
	var script: Variant = load(RELEVANCE_PATH)
	if not script is GDScript:
		return
	var result: Variant = (script as GDScript).call("compute", Build)
	if result is Dictionary:
		_relevance = result
		_relevance_known = true


## Reason text of `key` in a relevance group; has_source false only when relevance is known and the key is absent.
func _source(group: String, key: Variant) -> Dictionary:
	if not _relevance_known:
		return {"has": true, "reason": ""}
	var entries: Dictionary = _relevance.get(group, {})
	if entries.has(key):
		return {"has": true, "reason": str(entries[key])}
	return {"has": false, "reason": ""}


# --- values from Build -------------------------------------------------------------------

func _sync_values() -> void:
	var health_index: int = HEALTH_VALUES.find(str(Build.player_state.get("health", "full")))
	if health_index >= 0 and _health_select.selected != health_index:
		_health_select.select(health_index)
	var kind_index: int = KIND_VALUES.find(str(Build.enemy.get("kind", "dummy")))
	if kind_index >= 0 and _kind_select.selected != kind_index:
		_kind_select.select(kind_index)
	_set_spin(_level_spin, float(int(Build.enemy.get("level", 100))))
	_set_spin(_area_level_spin, float(int(Build.enemy.get("area_level", 0))))
	_set_spin(_armour_spin, float(int(Build.enemy.get("armour", 0))))
	_set_spin(_corruption_spin, float(int(Build.enemy.get("corruption", 0))))
	var res: Array = Build.enemy.get("res", [0, 0, 0, 0, 0, 0, 0]) as Array
	for spin: SpinBox in _resistance_spins:
		var index: int = int(spin.get_meta("res_index"))
		if index < res.size():
			_set_spin(spin, float(res[index]))


static func _set_spin(spin: SpinBox, value: float) -> void:
	if not is_equal_approx(spin.value, value):
		spin.set_value_no_signal(value)


# --- player group ------------------------------------------------------------------------

func _apply_player() -> void:
	var show_all: bool = _show_all.button_pressed
	var active: PackedStringArray = []
	var hidden_count: int = 0
	var no_source_on: int = 0
	var shown: int = 0

	for check: CheckBox in _player_flag_checks:
		var key: String = str(check.get_meta("player_flag"))
		var on: bool = bool(Build.player_state.get(key, false))
		check.set_pressed_no_signal(on)
		var source: Dictionary = _source("player_flags", key)
		var has_source: bool = bool(source["has"])
		check.visible = show_all or has_source or on
		if check.visible:
			shown += 1
		else:
			hidden_count += 1
		check.theme_type_variation = &"CheckBoxNoSource" if (on and not has_source) else &""
		check.tooltip_text = _source_tooltip(str(source["reason"]), has_source)
		if on:
			active.append(check.text)
			if not has_source:
				no_source_on += 1

	for spin: SpinBox in _player_value_spins:
		var key: String = str(spin.get_meta("player_value"))
		var value: float = float(Build.player_state.get(key, 0))
		var idle: float = float(PLAYER_VALUE_DEFAULTS.get(key, 0.0))
		_set_spin(spin, value)
		var source: Dictionary = _source("player_values", key)
		var has_source: bool = bool(source["has"])
		var row: PanelContainer = spin.get_parent().get_parent() as PanelContainer
		var keep: bool = spin.get_line_edit().has_focus()
		row.visible = show_all or has_source or not is_equal_approx(value, idle) or keep
		if row.visible:
			shown += 1
		else:
			hidden_count += 1
		row.theme_type_variation = &"RowIdle" if is_equal_approx(value, idle) else (&"RowActive" if has_source else &"RowNoSource")
		row.tooltip_text = _source_tooltip(str(source["reason"]), has_source)
		if not is_equal_approx(value, idle):
			var label: Label = spin.get_parent().get_child(0) as Label
			active.append("%s %s" % [tr(label.text), LE.fmt_num(value)])
			if not has_source:
				no_source_on += 1

	_player_flags_grid.visible = _any_visible(_player_flag_checks)
	_player_values_box.visible = _any_visible(_player_value_spins, 2)
	_player_shown = shown
	_set_summary(_player_summary, active, tr("Nothing enabled"), hidden_count, no_source_on)


static func _source_tooltip(reason: String, has_source: bool) -> String:
	if reason != "":
		return LE.t("Source: ") + reason
	if not has_source:
		return LE.t("No source in the build: the condition has no effect")
	return ""


# --- enemy group ---------------------------------------------------------------------------

func _apply_enemy() -> void:
	var show_all: bool = _show_all.button_pressed
	var flags: Dictionary = Build.enemy.get("flags", {}) as Dictionary
	var active: PackedStringArray = []
	var hidden_count: int = 0
	var shown: int = 0
	var no_source_on: int = 0
	for check: CheckBox in _enemy_flag_checks:
		var key: String = str(check.get_meta("flag"))
		var on: bool = bool(flags.get(key, false))
		check.set_pressed_no_signal(on)
		var source: Dictionary = _source("enemy", key)
		var has_source: bool = bool(source["has"])
		var changed_from_default: bool = on != bool(ENEMY_FLAG_DEFAULTS.get(key, false))
		check.visible = show_all or has_source or changed_from_default
		if check.visible:
			shown += 1
		else:
			hidden_count += 1
		check.theme_type_variation = &"CheckBoxNoSource" if (changed_from_default and not has_source) else &""
		check.tooltip_text = _source_tooltip(str(source["reason"]), has_source)
		if on:
			active.append(check.text)
		if changed_from_default and not has_source:
			no_source_on += 1
	_enemy_flags_grid.visible = shown > 0
	_enemy_flags_title.visible = shown > 0
	_enemy_shown = shown
	_set_summary(_enemy_summary, active, tr("No special states"), hidden_count, no_source_on)


static func _any_visible(controls: Array, parent_levels: int = 0) -> bool:
	for control: Control in controls:
		var node: Control = control
		for _i in range(parent_levels):
			node = node.get_parent() as Control
		if node.visible:
			return true
	return false


# --- ailments ----------------------------------------------------------------------------------

func _populate_ailments() -> void:
	for child: Node in _ailment_list.get_children():
		_ailment_list.remove_child(child)
		child.queue_free()
	_ailment_rows.clear()
	for data: Variant in GameData.enemy_ailments():
		if data is Dictionary and int((data as Dictionary).get("id", -1)) >= 0:
			var row: AilmentRow = ailment_row_scene.instantiate() as AilmentRow
			_ailment_list.add_child(row)
			row.setup(data as Dictionary)
			row.enable_auto()
			row.stacks_changed.connect(_on_ailment_stacks_changed)
			row.auto_toggled.connect(_on_ailment_auto_toggled.bind(row))
			_ailment_rows[row.ailment_id] = row


func _apply_ailments() -> void:
	var show_all: bool = _show_all.button_pressed
	var needle: String = _filter.text.strip_edges().to_lower()
	var ailments: Dictionary = Build.enemy.get("ailments", {}) as Dictionary
	# ailments without a number set here take the average the selected skill keeps on the target (EnemyAilments)
	var auto: Dictionary = EnemyAilments.auto(Build, Build.selected_skill)
	var active: PackedStringArray = []
	var hidden_count: int = 0
	var no_source_on: int = 0
	var order: PackedStringArray = []
	var listed_count: int = 0

	for ailment_id: int in _ailment_rows:
		var row: AilmentRow = _ailment_rows[ailment_id]
		var is_auto: bool = not ailments.has(ailment_id)
		var auto_entry: Dictionary = auto.get(ailment_id, {})
		var stacks: float = float(auto_entry.get("stacks", 0.0)) if is_auto else float(ailments[ailment_id])
		var source: Dictionary = _source("ailments", ailment_id)
		var has_source: bool = bool(source["has"]) or (is_auto and not auto_entry.is_empty())
		row.show_state(stacks, str(source["reason"]), has_source, is_auto,
			"" if auto_entry.is_empty() or not is_auto else EnemyAilments.describe(auto_entry))
		var listed: bool = show_all or has_source or stacks > 0.0 or row.has_edit_focus()
		if not listed:
			hidden_count += 1
		row.visible = listed and (needle == "" or row.search_text.contains(needle))
		if listed:
			listed_count += 1
		if _relevance_known and has_source:
			order.append(str(ailment_id))
		if stacks > 0.0:
			active.append("%s ×%s%s" % [row.display_name, LE.fmt_num(stacks), tr(" (auto)") if is_auto else ""])
			if not has_source:
				no_source_on += 1

	# rows with a source go first (only reordered when that set changes)
	var order_key: String = ",".join(order)
	if order_key != _ailment_order:
		_ailment_order = order_key
		var index: int = 0
		for id_text: String in order:
			_ailment_list.move_child(_ailment_rows[int(id_text)], index)
			index += 1

	_ailments_shown = listed_count
	_set_summary(_ailment_summary, active, tr("Nothing applied"), hidden_count, no_source_on)


# --- buffs on the player -------------------------------------------------------------------------

func _populate_buffs() -> void:
	for child: Node in _buff_list.get_children():
		_buff_list.remove_child(child)
		child.queue_free()
	_buff_rows.clear()
	for data: Variant in GameData.player_buffs():
		if data is Dictionary and int((data as Dictionary).get("id", -1)) >= 0:
			var row: AilmentRow = ailment_row_scene.instantiate() as AilmentRow
			_buff_list.add_child(row)
			row.setup(data as Dictionary)
			row.enable_auto()
			row.stacks_changed.connect(func(id: int, stacks: float) -> void: Build.set_player_buff(id, stacks))
			row.auto_toggled.connect(_on_buff_auto_toggled.bind(row))
			_buff_rows[row.ailment_id] = row


## Rows with a source in the build (or with stacks) are shown; the search field filters this list too.
func _apply_buffs() -> void:
	var show_all: bool = _show_all.button_pressed
	var needle: String = _filter.text.strip_edges().to_lower()
	var buffs: Dictionary = Build.player_state.get("buffs", {}) as Dictionary
	# buffs without a number set here take the average kept while the selected skill is used (EnemyAilments.buffs)
	var auto: Dictionary = EnemyAilments.buffs(Build, Build.selected_skill)
	var active: PackedStringArray = []
	var hidden_count: int = 0
	var no_source_on: int = 0
	var shown: int = 0
	for ailment_id: int in _buff_rows:
		var row: AilmentRow = _buff_rows[ailment_id]
		var is_auto: bool = not buffs.has(ailment_id)
		var auto_entry: Dictionary = auto.get(ailment_id, {})
		var stacks: float = float(auto_entry.get("stacks", 0.0)) if is_auto else float(buffs[ailment_id])
		var source: Dictionary = _source("player_buffs", ailment_id)
		var has_source: bool = bool(source["has"]) or (is_auto and not auto_entry.is_empty())
		row.show_state(stacks, str(source["reason"]), has_source, is_auto,
			"" if auto_entry.is_empty() or not is_auto else EnemyAilments.describe(auto_entry))
		var listed: bool = show_all or has_source or stacks > 0.0 or row.has_edit_focus()
		if not listed:
			hidden_count += 1
		row.visible = listed and (needle == "" or row.search_text.contains(needle))
		if listed:
			shown += 1
		if stacks > 0.0:
			active.append("%s ×%s%s" % [row.display_name, LE.fmt_num(stacks), tr(" (auto)") if is_auto else ""])
			if not has_source:
				no_source_on += 1
	_buffs_shown = shown
	(_buff_list.get_parent().get_parent() as Control).visible = shown > 0
	_set_summary(_buff_summary, active, tr("Nothing enabled"), hidden_count, no_source_on)


# --- active minions --------------------------------------------------------------------------------

## Rows: every minion type summoned by a bar skill (its summon limit by default) and the counts the build's models scale
## with (MinionCount.COUNT_KEYS: all minions, totems, wolves …; the sum of the summoned types by default). A count row is
## shown only when a model of the build reads it (or with «Show all conditions», or when set by hand).
func _apply_minions() -> void:
	var show_all: bool = _show_all.button_pressed
	var given: Dictionary = MinionCount.explicit(Build)
	var wanted: Array[Array] = []  # [key, title, is_type, limit, limit text]
	for t: Dictionary in MinionCount.types(Build):
		wanted.append([str(t["actor"]), "%s (%s)" % [str(t["actor"]), str(t["skill"])], true, float(t["limit"]), str(t["limit_text"])])
	for key: String in MinionCount.COUNT_KEYS:
		wanted.append([key, tr(str(MinionCount.COUNT_KEYS[key]["label"])), false, 0.0, ""])
	var keys: Array = wanted.map(func(w: Array) -> String: return str(w[0]))
	if keys != _minion_rows.keys():
		for child: Node in _minion_list.get_children():
			_minion_list.remove_child(child)
			child.queue_free()
		_minion_rows.clear()
		for w: Array in wanted:
			var row: MinionRow = minion_row_scene.instantiate() as MinionRow
			_minion_list.add_child(row)
			row.setup(str(w[0]), str(w[1]))
			row.count_changed.connect(func(key: String, v: float) -> void: Build.set_minion_count(key, v))
			row.auto_toggled.connect(_on_minion_auto_toggled.bind(row))
			_minion_rows[str(w[0])] = row
	var active: PackedStringArray = []
	var hidden_count: int = 0
	var no_source_on: int = 0
	var shown: int = 0
	for w: Array in wanted:
		var key: String = str(w[0])
		var row: MinionRow = _minion_rows[key]
		var value: float
		var auto_text: String = ""
		if bool(w[2]):
			value = float(MinionCount.type_count(Build, key, float(w[3]))["value"])
			auto_text = tr("summon limit: %s") % str(w[4])
			var split: PackedStringArray = []
			for t: Dictionary in MinionCount.types(Build):
				if str(t["actor"]) == key and t.has("rotation"):
					for m: Dictionary in MinionCount.members(Build, str(t["ability"])):
						split.append("%s %s" % [str(m["actor"]), LE.fmt_num(float(m["count"]))])
			if not split.is_empty():
				auto_text += "\n" + tr("split between the types: %s") % ", ".join(split)
		else:
			var c: Dictionary = MinionCount.count(Build, key)
			value = float(c["value"])
			auto_text = str(c["text"])
		var is_auto: bool = not given.has(key)
		var source: Dictionary = _source("minions", key)
		var has_source: bool = bool(source["has"])
		row.show_state(value, str(source["reason"]), has_source, is_auto, auto_text)
		var listed: bool = show_all or has_source or not is_auto or row.has_edit_focus()
		row.visible = listed
		if listed:
			shown += 1
		else:
			hidden_count += 1
		if listed and value > 0.0:
			active.append("%s %s%s" % [str(w[1]), LE.fmt_num(value), tr(" (auto)") if is_auto else ""])
			if not has_source:
				no_source_on += 1
	_minions_shown = shown
	(_minion_list.get_parent().get_parent() as Control).visible = shown > 0
	_set_summary(_minion_summary, active, tr("Nothing enabled"), hidden_count, no_source_on)


func _on_minion_auto_toggled(key: String, on: bool, row: MinionRow) -> void:
	if on:
		Build.clear_minion_count(key)
	else:
		Build.set_minion_count(key, row.value())


# --- summaries ------------------------------------------------------------------------------------

func _set_summary(label: Label, active: PackedStringArray, empty_text: String, hidden_count: int, no_source_on: int) -> void:
	var text: String = empty_text
	var shown: PackedStringArray = active
	if active.size() > MAX_LISTED:
		shown = active.slice(0, MAX_LISTED)
		shown.append(tr("and %d more") % (active.size() - MAX_LISTED))
	if not active.is_empty():
		text = tr("Active: %s") % ", ".join(shown)
	label.theme_type_variation = &"SummaryActive" if not active.is_empty() else &"SummaryOff"
	if no_source_on > 0:
		text += tr(" · without source: %d") % no_source_on
	if hidden_count > 0:
		text += tr(" · %d hidden without source") % hidden_count
	label.text = text


# --- user edits ------------------------------------------------------------------------------------

func _on_health_selected(index: int) -> void:
	if index >= 0 and index < HEALTH_VALUES.size():
		Build.set_player_state("health", HEALTH_VALUES[index])


func _on_kind_selected(index: int) -> void:
	if index >= 0 and index < KIND_VALUES.size():
		Build.set_enemy("kind", KIND_VALUES[index])


func _on_resistance_changed(value: float, spin: SpinBox) -> void:
	var index: int = int(spin.get_meta("res_index"))
	var res: Array = (Build.enemy.get("res", [0, 0, 0, 0, 0, 0, 0]) as Array).duplicate()
	while res.size() <= index:
		res.append(0)
	res[index] = int(value)
	Build.set_enemy("res", res)


func _on_enemy_flag_toggled(pressed: bool, check: CheckBox) -> void:
	var flags: Dictionary = (Build.enemy.get("flags", {}) as Dictionary).duplicate()
	flags[str(check.get_meta("flag"))] = pressed
	Build.set_enemy("flags", flags)


func _on_player_flag_toggled(pressed: bool, check: CheckBox) -> void:
	Build.set_player_state(str(check.get_meta("player_flag")), pressed)


func _on_player_value_changed(value: float, spin: SpinBox) -> void:
	# per-second numbers (step below 1) stay fractional
	Build.set_player_state(str(spin.get_meta("player_value")), value if spin.step < 1.0 else int(value))


func _on_ailment_stacks_changed(ailment_id: int, stacks: float) -> void:
	Build.set_enemy_ailment(ailment_id, stacks)


func _on_buff_auto_toggled(ailment_id: int, on: bool, row: AilmentRow) -> void:
	if on:
		Build.clear_player_buff(ailment_id)
	else:
		Build.set_player_buff(ailment_id, row.value())


## «auto» on: back to the automatic value; off: the shown value becomes a number set by hand.
func _on_ailment_auto_toggled(ailment_id: int, on: bool, row: AilmentRow) -> void:
	if on:
		Build.clear_enemy_ailment(ailment_id)
	else:
		Build.set_enemy_ailment(ailment_id, row.value())
