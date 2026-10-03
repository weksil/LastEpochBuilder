extends Node

signal changed

var class_id: int = -1
var mastery: int = 0
var level: int = 100
var passives: Dictionary = {}
var _nodes: Dictionary = {}

func set_class(id: int) -> void:
	class_id = id
	mastery = 0
	passives.clear()
	_nodes.clear()

	var tree: Dictionary = GameData.get_passive_tree(class_id)
	if "nodes" in tree and tree["nodes"] is Array:
		for node: Variant in tree["nodes"]:
			if node is Dictionary:
				var node_entry: Dictionary = node
				if "id" in node_entry:
					var node_id: int = int(node_entry["id"])
					_nodes[node_id] = node_entry

	changed.emit()

func set_mastery(m: int) -> void:
	mastery = m
	changed.emit()

func set_level(l: int) -> void:
	level = l
	changed.emit()

func get_points(id: int) -> int:
	if id in passives:
		return passives[id] as int
	return 0

func spent_points() -> int:
	var total: int = 0
	for points: Variant in passives.values():
		total += int(points)
	return total

func points_in_mastery(m: int) -> int:
	var total: int = 0
	for node_id: Variant in passives.keys():
		var nid: int = int(node_id)
		if nid in _nodes:
			var node: Dictionary = _nodes[nid]
			if "mastery" in node and int(node["mastery"]) == m:
				total += int(passives[nid])
	return total

func _points_below(threshold: int, node_mastery: int) -> int:
	var total: int = 0
	for nid: int in passives:
		var other: Dictionary = _nodes.get(nid, {})
		var m: int = int(other.get("mastery", -1))
		if (m == 0 or m == node_mastery) and int(other.get("masteryRequirement", 0)) < threshold:
			total += int(passives[nid])
	return total

func _is_valid(id: int) -> bool:
	if id not in _nodes:
		return false

	if get_points(id) == 0:
		return true

	var node: Dictionary = _nodes[id]

	# Check requirements
	if "requirements" in node and node["requirements"] is Array:
		for req: Variant in node["requirements"]:
			if req is Dictionary:
				var requirement: Dictionary = req
				if "nodeID" in requirement and "requirement" in requirement:
					var req_node_id: int = int(requirement["nodeID"])
					var req_points: int = int(requirement["requirement"])
					if get_points(req_node_id) < req_points:
						return false

	# Points threshold: count only points in lower-threshold nodes of the base tree and this node's mastery tree
	var mastery_req: int = int(node.get("masteryRequirement", 0))
	if mastery_req > 0 and _points_below(mastery_req, int(node.get("mastery", 0))) < mastery_req:
		return false

	return true

func can_add(id: int) -> bool:
	if id not in _nodes:
		return false

	var node: Dictionary = _nodes[id]

	if "maxPoints" not in node or int(node["maxPoints"]) <= 0:
		return false

	var current_points: int = get_points(id)
	var max_points: int = int(node["maxPoints"])
	if current_points >= max_points:
		return false

	# Simulate adding a point and check if it would be valid
	passives[id] = current_points + 1
	var valid: bool = _is_valid(id)

	# Restore original state
	if current_points > 0:
		passives[id] = current_points
	else:
		passives.erase(id)

	return valid

func add_point(id: int) -> bool:
	if not can_add(id):
		return false

	passives[id] = get_points(id) + 1
	changed.emit()
	return true

func remove_point(id: int) -> bool:
	if id not in passives or get_points(id) == 0:
		return false

	var current_points: int = get_points(id)
	var old_points: Dictionary = passives.duplicate()

	# Decrement or remove
	if current_points - 1 <= 0:
		passives.erase(id)
	else:
		passives[id] = current_points - 1

	# Check if any allocated node is now invalid
	for node_id: Variant in passives.keys():
		var nid: int = int(node_id)
		if not _is_valid(nid):
			# Revert
			passives = old_points
			return false

	changed.emit()
	return true
