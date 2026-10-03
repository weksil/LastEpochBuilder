class_name TreeCanvas
extends ScrollContainer

signal add_requested(node_id: int)
signal remove_requested(node_id: int)

@export var node_scene: PackedScene
@export var link_scene: PackedScene
@export var margin: float = 60.0

var _nodes: Dictionary[int, PassiveNode] = {}
var _links: Array[Array] = []

func _ready() -> void:
	pass

func show_tree(nodes: Array, tree_id: String) -> void:
	# Clear existing nodes and links
	for child in %Links.get_children():
		child.queue_free()
	for child in %Nodes.get_children():
		child.queue_free()

	_nodes.clear()
	_links.clear()

	if nodes.is_empty():
		%Canvas.custom_minimum_size = Vector2.ZERO
		return

	# Calculate positions and bounds
	var positions: Array[Vector2] = []
	var node_map: Dictionary[int, Vector2] = {}

	for node in nodes:
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

	var node_ids: Array[int] = []
	for node in nodes:
		node_ids.append(int(node["id"]))

	# Create node instances
	for node in nodes:
		var node_id: int = int(node["id"])
		var node_pos: Vector2 = node_map[node_id] + offset
		var stats: Dictionary = GameData.get_node_stats(tree_id, node_id)

		var node_instance: PassiveNode = node_scene.instantiate() as PassiveNode
		%Nodes.add_child(node_instance)
		node_instance.setup(node, stats)
		node_instance.position = node_pos - node_instance.custom_minimum_size / 2.0

		# Bubble up signals
		node_instance.add_requested.connect(func(id: int) -> void: add_requested.emit(id))
		node_instance.remove_requested.connect(func(id: int) -> void: remove_requested.emit(id))

		_nodes[node_id] = node_instance

		# Create link instances for requirements
		var requirements: Array = node.get("requirements", [])
		for requirement in requirements:
			var req_node_id: int = int(requirement.get("nodeID", -1))
			if req_node_id in node_ids:
				var req_pos: Vector2 = node_map[req_node_id] + offset

				var link_instance: PassiveLink = link_scene.instantiate() as PassiveLink
				%Links.add_child(link_instance)
				link_instance.points = PackedVector2Array([req_pos, node_pos])

				_links.append([link_instance, req_node_id, node_id])

func refresh(get_points: Callable, can_add: Callable) -> void:
	# Update node states
	for node_id: int in _nodes:
		var node_instance: PassiveNode = _nodes[node_id]
		var points: int = get_points.call(node_id)
		var can_add_node: bool = can_add.call(node_id)
		node_instance.set_state(points, can_add_node)

	# Update link states
	for link_data in _links:
		var link_instance: PassiveLink = link_data[0]
		var req_node_id: int = link_data[1]
		var node_id: int = link_data[2]

		var req_points: int = get_points.call(req_node_id)
		var node_points: int = get_points.call(node_id)

		link_instance.set_active(req_points > 0 and node_points > 0)
