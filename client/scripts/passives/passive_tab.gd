extends VBoxContainer

@export var node_scene: PackedScene
@export var link_scene: PackedScene
@export var margin: float = 60.0

var _built_class: int = -1
var _tree_id: String = ""
var _nodes: Dictionary = {}
var _links: Array[Array] = []

func _ready() -> void:
	Build.changed.connect(_on_build_changed)
	%MasteryTabs.tab_changed.connect(_on_tab_changed)

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
		rebuild_canvas(0)

	refresh()

func _on_tab_changed(tab: int) -> void:
	rebuild_canvas(tab)

func rebuild_canvas(mastery_index: int) -> void:
	for child in %Links.get_children():
		child.queue_free()
	for child in %Nodes.get_children():
		child.queue_free()

	var tree_data: Dictionary = GameData.get_passive_tree(Build.class_id)
	var all_nodes: Array = tree_data.get("nodes", [])

	var mastery_nodes: Array = []
	for node in all_nodes:
		if int(node.get("mastery", -1)) == mastery_index:
			mastery_nodes.append(node)

	_nodes.clear()
	_links.clear()

	if mastery_nodes.is_empty():
		%Canvas.custom_minimum_size = Vector2.ZERO
		return

	var positions: Array[Vector2] = []
	var node_map: Dictionary = {}

	for node in mastery_nodes:
		var node_pos_raw: Array = node.get("position", [0, 0])
		var node_pos: Vector2 = Vector2(float(node_pos_raw[0]), -float(node_pos_raw[1]))
		positions.append(node_pos)
		node_map[int(node["id"])] = node_pos

	var min_x: float = positions[0].x
	var min_y: float = positions[0].y
	var max_x: float = positions[0].x
	var max_y: float = positions[0].y

	for pos in positions:
		min_x = min(min_x, pos.x)
		min_y = min(min_y, pos.y)
		max_x = max(max_x, pos.x)
		max_y = max(max_y, pos.y)

	var offset: Vector2 = Vector2(margin - min_x, margin - min_y)
	var canvas_size: Vector2 = Vector2(max_x - min_x + margin * 2, max_y - min_y + margin * 2)
	%Canvas.custom_minimum_size = canvas_size

	var mastery_node_ids: Array[int] = []
	for node in mastery_nodes:
		mastery_node_ids.append(int(node["id"]))

	for node in mastery_nodes:
		var node_id: int = int(node["id"])
		var node_pos: Vector2 = node_map[node_id] + offset
		var stats: Dictionary = GameData.get_node_stats(_tree_id, node_id)

		var node_instance: PassiveNode = node_scene.instantiate() as PassiveNode
		%Nodes.add_child(node_instance)
		node_instance.setup(node, stats)
		node_instance.position = node_pos - node_instance.custom_minimum_size / 2.0

		node_instance.add_requested.connect(func(id: int) -> void: Build.add_point(id))
		node_instance.remove_requested.connect(func(id: int) -> void: Build.remove_point(id))

		_nodes[node_id] = node_instance

		var requirements: Array = node.get("requirements", [])
		for requirement in requirements:
			var req_node_id: int = int(requirement.get("nodeID", -1))
			if req_node_id in mastery_node_ids:
				var req_pos: Vector2 = node_map[req_node_id] + offset

				var link_instance: PassiveLink = link_scene.instantiate() as PassiveLink
				%Links.add_child(link_instance)
				link_instance.points = PackedVector2Array([req_pos, node_pos])

				_links.append([link_instance, req_node_id, node_id])

	refresh()

func refresh() -> void:
	for node_id: int in _nodes:
		var node_instance: PassiveNode = _nodes[node_id]
		var points: int = Build.get_points(node_id)
		var can_add: bool = Build.can_add(node_id)
		node_instance.set_state(points, can_add)

	for link_data in _links:
		var link_instance: PassiveLink = link_data[0]
		var req_node_id: int = link_data[1]
		var node_id: int = link_data[2]

		var req_points: int = Build.get_points(req_node_id)
		var node_points: int = Build.get_points(node_id)

		link_instance.set_active(req_points > 0 and node_points > 0)

	%PointsLabel.text = "Потрачено очков: %d" % Build.spent_points()
