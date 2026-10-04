extends HBoxContainer

var _current_tree_id: String = ""
var _built_class: int = -1
var _built_skill: int = -1
var _built_ability: String = ""
var _tree_signals_connected: bool = false


func _ready() -> void:
	# Connect all skill slot selected signals
	for slot_child in %Slots.get_children():
		if slot_child is SkillSlot:
			slot_child.selected.connect(_on_skill_slot_selected)

	Build.changed.connect(_on_build_changed)


func _on_build_changed() -> void:
	# Sync all skill slots
	for slot_child in %Slots.get_children():
		if slot_child is SkillSlot:
			slot_child.sync()
			slot_child.set_selected(slot_child.slot_index == Build.selected_skill)

	# Rebuild tree if class changed
	if Build.class_id != _built_class:
		_built_class = Build.class_id
		_rebuild_tree()
		return

	# Rebuild tree if selected slot or its skill changed
	var ability_id: String = str(Build.skills[Build.selected_skill].get("ability", ""))
	if Build.selected_skill != _built_skill or ability_id != _built_ability:
		_built_skill = Build.selected_skill
		_rebuild_tree()
		return

	# Just refresh points
	_refresh_tree()


func _on_skill_slot_selected(slot_index: int) -> void:
	"""Handle skill slot selection"""
	Build.selected_skill = slot_index

	# Update button states for all slots
	for slot_child in %Slots.get_children():
		if slot_child is SkillSlot:
			slot_child.set_selected(slot_child.slot_index == slot_index)


func _rebuild_tree() -> void:
	"""Rebuild the skill tree for the currently selected skill"""
	var skill_data: Dictionary = Build.skills[Build.selected_skill]
	var ability_id: String = str(skill_data.get("ability", ""))
	_built_ability = ability_id

	if ability_id == "":
		# No skill selected - show empty state
		%TreeTitle.text = "Выберите умение"
		%TreePoints.text = ""
		%TreeCanvas.visible = false
		_tree_signals_connected = false
		return

	# Get ability info
	var ability: Dictionary = GameData.get_ability(ability_id)
	var ability_name: String = ability.get("abilityName", ability_id)
	var skill_tree_id: String = ability.get("skillTree", "")

	%TreeTitle.text = ability_name
	%TreeCanvas.visible = true

	if skill_tree_id != "":
		var tree_data: Dictionary = GameData.get_skill_tree(skill_tree_id)
		var nodes: Array = tree_data.get("nodes", [])
		var tree_id: String = tree_data.get("treeID", "")

		# Store for refresh
		_current_tree_id = tree_id

		# Show tree
		if not nodes.is_empty():
			%TreeCanvas.show_tree(nodes, tree_id)

			# Connect canvas signals if not already connected
			if not _tree_signals_connected:
				if %TreeCanvas.add_requested.is_connected(_on_tree_add_requested) == false:
					%TreeCanvas.add_requested.connect(_on_tree_add_requested)
				if %TreeCanvas.remove_requested.is_connected(_on_tree_remove_requested) == false:
					%TreeCanvas.remove_requested.connect(_on_tree_remove_requested)
				_tree_signals_connected = true

			# Refresh with current state
			_refresh_tree()

	_built_skill = Build.selected_skill


func _refresh_tree() -> void:
	"""Refresh the tree display without rebuilding"""
	if _current_tree_id == "":
		return

	var slot: int = Build.selected_skill
	var skill_data: Dictionary = Build.skills[slot]
	var skill_level: int = skill_data.get("level", 20)
	var spent: int = Build.skill_points_spent(slot)

	%TreePoints.text = "%d / %d" % [spent, skill_level]

	# Refresh node states if tree canvas has refresh method
	if %TreeCanvas.has_method("refresh"):
		%TreeCanvas.refresh(
			func(node_id: int) -> int: return Build.get_skill_points(slot, node_id),
			func(node_id: int) -> bool: return Build.can_add_skill_point(slot, node_id)
		)


func _on_tree_add_requested(node_id: int) -> void:
	"""Handle add point request from tree canvas"""
	Build.add_skill_point(Build.selected_skill, node_id)
	_refresh_tree()


func _on_tree_remove_requested(node_id: int) -> void:
	"""Handle remove point request from tree canvas"""
	Build.remove_skill_point(Build.selected_skill, node_id)
	_refresh_tree()
