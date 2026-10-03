extends VBoxContainer

var _built_class: int = -1
var _tree_id: String = ""

func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	%MasteryTabs.tab_changed.connect(_on_tab_changed)
	%TreeCanvas.add_requested.connect(func(id: int) -> void: Build.add_point(id))
	%TreeCanvas.remove_requested.connect(func(id: int) -> void: Build.remove_point(id))

func _on_build_changed() -> void:
	if Build.class_id != _built_class:
		_built_class = Build.class_id
		var class_data: Dictionary = GameData.get_class_data(Build.class_id)
		var masteries: Array = class_data.get("masteries", [])

		%MasteryTabs.set_block_signals(true)
		%MasteryTabs.clear_tabs()
		for mastery in masteries:
			%MasteryTabs.add_tab(mastery.get("name", ""))

		%MasteryTabs.current_tab = 0
		%MasteryTabs.set_block_signals(false)
		_tree_id = str(GameData.get_passive_tree(Build.class_id).get("treeID", ""))
		_show_mastery(0)

	refresh()

func _on_tab_changed(tab: int) -> void:
	_show_mastery(tab)

func _show_mastery(mastery_index: int) -> void:
	var tree_data: Dictionary = GameData.get_passive_tree(Build.class_id)
	var all_nodes: Array = tree_data.get("nodes", [])

	var mastery_nodes: Array = []
	for node in all_nodes:
		if int(node.get("mastery", -1)) == mastery_index:
			mastery_nodes.append(node)

	%TreeCanvas.show_tree(mastery_nodes, _tree_id)
	refresh()

func refresh() -> void:
	%TreeCanvas.refresh(Build.get_points, Build.can_add)
	%PointsLabel.text = "Потрачено очков: %d" % Build.spent_points()
