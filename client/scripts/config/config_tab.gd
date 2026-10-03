extends ScrollContainer


@export var ailment_row_scene: PackedScene


var _ailment_rows: Dictionary = {}  # ailment_id -> row node
var left_container: VBoxContainer


func _ready() -> void:
	# Connect to Build changes
	Build.changed.connect(_on_build_changed)

	# Connect health select
	%HealthSelect.item_selected.connect(_on_health_selected)

	# Connect enemy kind select
	%KindSelect.item_selected.connect(_on_kind_selected)

	# Connect level spin
	%LevelSpin.value_changed.connect(_on_level_changed)

	# Connect armour spin
	%ArmourSpin.value_changed.connect(_on_armour_changed)

	# Find the Left container (first child of Columns)
	var columns: HBoxContainer = %Columns if has_node("%Columns") else null
	if columns:
		for child: Node in columns.get_children():
			if child is VBoxContainer:
				left_container = child as VBoxContainer
				break

	# Connect resistance spins from EnemyGrid
	if has_node("%EnemyGrid"):
		var enemy_grid: GridContainer = %EnemyGrid
		for child: Node in enemy_grid.get_children():
			if child is SpinBox and child.has_meta("res_index"):
				(child as SpinBox).value_changed.connect(_on_resistance_changed.bindv([child]))

	# Connect flag checkboxes from Left container
	if left_container:
		for child: Node in left_container.get_children():
			if child is CheckBox and child.has_meta("flag"):
				(child as CheckBox).toggled.connect(_on_flag_toggled.bindv([child]))

	# Connect filter
	%Filter.text_changed.connect(_on_filter_changed)

	# Populate ailments
	_populate_ailments()

	# Initialize from Build
	_sync_from_build()


func _sync_from_build() -> void:
	# Set block signals to prevent feedback loops
	set_block_signals(true)

	# Health
	var health: String = Build.player_state.get("health", "full") as String
	var health_index: int = ["full", "high", "normal", "low"].find(health)
	if health_index >= 0:
		%HealthSelect.select(health_index)

	# Enemy kind
	var kind: String = Build.enemy.get("kind", "boss") as String
	var kind_index: int = ["dummy", "normal", "magic", "rare", "miniboss", "boss"].find(kind)
	if kind_index >= 0:
		%KindSelect.select(kind_index)

	# Level
	var level: int = int(Build.enemy.get("level", 100))
	%LevelSpin.set_value_no_signal(float(level))

	# Armour
	var armour: int = int(Build.enemy.get("armour", 0))
	%ArmourSpin.set_value_no_signal(float(armour))

	# Resistances
	var res: Array = Build.enemy.get("res", [0, 0, 0, 0, 0, 0, 0]) as Array
	if has_node("%EnemyGrid"):
		var enemy_grid: GridContainer = %EnemyGrid
		for child: Node in enemy_grid.get_children():
			if child is SpinBox and child.has_meta("res_index"):
				var index: int = int(child.get_meta("res_index"))
				if index < res.size():
					(child as SpinBox).set_value_no_signal(float(res[index]))

	# Flags
	var flags: Dictionary = Build.enemy.get("flags", {}) as Dictionary
	_update_flags(flags)

	# Ailments (already populated, just sync values)
	var ailments: Dictionary = Build.enemy.get("ailments", {}) as Dictionary
	_update_ailments(ailments)

	set_block_signals(false)


func _update_flags(flags: Dictionary) -> void:
	if left_container:
		for child: Node in left_container.get_children():
			if child is CheckBox and child.has_meta("flag"):
				var flag_name: String = child.get_meta("flag") as String
				var flag_value: bool = flags.get(flag_name, false) as bool
				(child as CheckBox).set_pressed_no_signal(flag_value)


func _update_ailments(ailments: Dictionary) -> void:
	for ailment_id: Variant in _ailment_rows.keys():
		var row: HBoxContainer = _ailment_rows[ailment_id]
		var stacks: int = int(ailments.get(ailment_id, 0))
		var stacks_spin: SpinBox = row.get_node("%StacksSpin") as SpinBox
		stacks_spin.set_value_no_signal(float(stacks))


func _populate_ailments() -> void:
	var ailment_list: VBoxContainer = %AilmentList
	for child: Node in ailment_list.get_children():
		child.queue_free()
	_ailment_rows.clear()

	var ailments: Array = GameData.enemy_ailments()
	for ailment_data: Variant in ailments:
		if ailment_data is Dictionary:
			var ail: Dictionary = ailment_data
			var ailment_id: int = int(ail.get("id", -1))
			if ailment_id < 0:
				continue

			# Instantiate ailment row
			var row: HBoxContainer = ailment_row_scene.instantiate() as HBoxContainer
			ailment_list.add_child(row)
			_ailment_rows[ailment_id] = row

			# Set name
			var name_label: Label = row.get_node("%NameLabel") as Label
			var ailment_name: String = ail.get("name", "") as String
			name_label.text = ailment_name

			# Set tooltip with buffs and max instances
			var tooltip_parts: PackedStringArray = []

			# Add buff information
			var buffs: Array = ail.get("buffs", []) as Array
			if not buffs.is_empty():
				for buff: Variant in buffs:
					if buff is Dictionary:
						var buff_dict: Dictionary = buff
						var prop_name: String = buff_dict.get("propertyName", "") as String
						var added: float = buff_dict.get("added", 0) as float
						var increased: float = buff_dict.get("increased", 0) as float
						var more_arr: Array = buff_dict.get("more", []) as Array

						if added != 0.0 or increased != 0.0 or not more_arr.is_empty():
							tooltip_parts.append("%s: добавлено %.1f, увеличено %.1f%%" % [prop_name, added, increased * 100])

			# Add max instances
			var max_instances: int = int(ail.get("maxInstances", 0))
			if max_instances > 0:
				tooltip_parts.append("Макс.стаки: %d" % max_instances)

			# Add boss bonus
			var more_buff: float = ail.get("moreBuffEffectAgainstBosses", 0) as float
			if more_buff != 0.0:
				tooltip_parts.append("Против боссов: ×%.2f" % (1.0 + more_buff))

			if not tooltip_parts.is_empty():
				name_label.tooltip_text = "\n".join(tooltip_parts)

			# Set stacks spin max
			var stacks_spin: SpinBox = row.get_node("%StacksSpin") as SpinBox
			if max_instances > 0:
				stacks_spin.max_value = float(max_instances)
			else:
				stacks_spin.max_value = 200.0

			# Connect stacks spin signal
			stacks_spin.value_changed.connect(_on_ailment_stacks_changed.bindv([ailment_id]))


func _on_health_selected(index: int) -> void:
	var health_values: PackedStringArray = ["full", "high", "normal", "low"]
	if index >= 0 and index < health_values.size():
		Build.set_player_state("health", health_values[index])


func _on_kind_selected(index: int) -> void:
	var kind_values: PackedStringArray = ["dummy", "normal", "magic", "rare", "miniboss", "boss"]
	if index >= 0 and index < kind_values.size():
		Build.set_enemy("kind", kind_values[index])


func _on_level_changed(value: float) -> void:
	Build.set_enemy("level", int(value))


func _on_armour_changed(value: float) -> void:
	Build.set_enemy("armour", int(value))


func _on_resistance_changed(value: float, spin: SpinBox) -> void:
	if not spin.has_meta("res_index"):
		return

	var index: int = int(spin.get_meta("res_index"))
	var res: Array = (Build.enemy.get("res", [0, 0, 0, 0, 0, 0, 0]) as Array).duplicate()

	# Ensure array is large enough
	while res.size() <= index:
		res.append(0)

	res[index] = int(value)
	Build.set_enemy("res", res)


func _on_flag_toggled(pressed: bool, check: CheckBox) -> void:
	if not check.has_meta("flag"):
		return

	var flag_name: String = check.get_meta("flag") as String
	var flags: Dictionary = (Build.enemy.get("flags", {}) as Dictionary).duplicate()
	flags[flag_name] = pressed
	Build.set_enemy("flags", flags)


func _on_ailment_stacks_changed(value: float, ailment_id: int) -> void:
	Build.set_enemy_ailment(ailment_id, int(value))


func _on_filter_changed(text: String) -> void:
	var filter_lower: String = text.to_lower()
	for ailment_id: Variant in _ailment_rows.keys():
		var row: HBoxContainer = _ailment_rows[ailment_id]
		var name_label: Label = row.get_node("%NameLabel") as Label
		var ailment_name: String = name_label.text.to_lower()
		row.visible = (filter_lower.is_empty() or ailment_name.contains(filter_lower))


func _on_build_changed() -> void:
	_sync_from_build()
