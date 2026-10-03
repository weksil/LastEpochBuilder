extends Node

signal changed

# Passive tree
var class_id: int = -1
var mastery: int = 0
var level: int = 100
var passives: Dictionary = {}
var _nodes: Dictionary = {}

# Skills (5 slots)
var skills: Array[Dictionary] = []
var selected_skill: int = 0
var _skill_nodes: Array[Dictionary] = []  # skill tree nodes per slot

# Items
var items: Dictionary = {}

# Enemy config
var enemy: Dictionary = {}

# Player state
var player_state: Dictionary = {}


func _ready() -> void:
	_init_defaults()


func _init_defaults() -> void:
	# Initialize 5 empty skill slots
	skills.clear()
	for i in range(5):
		skills.append({
			"ability": "",
			"level": 20,
			"tree": {}
		})

	# Initialize skill nodes array
	_skill_nodes.clear()
	for i in range(5):
		_skill_nodes.append({})

	# Initialize enemy with defaults
	enemy = {
		"level": 100,
		"kind": "boss",
		"res": [0, 0, 0, 0, 0, 0, 0],
		"armour": 0,
		"ailments": {},
		"flags": {
			"moving": false,
			"stunned": false,
			"low_health": false,
			"full_health": true
		}
	}

	# Initialize player state
	player_state = {
		"health": "full"
	}

	# Initialize items (empty)
	items = {}


func set_class(id: int) -> void:
	class_id = id
	mastery = 0
	passives.clear()
	_nodes.clear()

	# Reset skills and items
	for i in range(skills.size()):
		skills[i] = {
			"ability": "",
			"level": 20,
			"tree": {}
		}
	for i in range(_skill_nodes.size()):
		_skill_nodes[i] = {}
	items.clear()

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

	if not requirements_met(node, passives):
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

	# Check if any allocated node is now invalid or cut off from the root
	var ok: bool = all_connected(_nodes, passives)
	for node_id: Variant in passives.keys():
		ok = ok and _is_valid(int(node_id))
	if not ok:
		passives = old_points
		return false

	changed.emit()
	return true


## Game rule (LocalTreeData.ArePassiveNodeRequirementsMet): a node is unlocked when ANY of its
## requirements {nodeID, requirement} has at least `requirement` points; no requirements = unlocked.
static func requirements_met(node: Dictionary, points: Dictionary) -> bool:
	var reqs: Array = node.get("requirements", [])
	if reqs.is_empty():
		return true
	for req: Dictionary in reqs:
		if int(points.get(int(req["nodeID"]), 0)) >= int(req["requirement"]):
			return true
	return false


## Every allocated node must be reachable from a root (node without requirements or with maxPoints 0)
## through requirements that are met, so two nodes cannot keep each other alive after their path is removed.
static func all_connected(nodes: Dictionary, points: Dictionary) -> bool:
	var connected: Dictionary = {}
	for id: Variant in nodes:
		var node: Dictionary = nodes[id]
		if int(node.get("maxPoints", 0)) == 0 or node.get("requirements", []).is_empty():
			connected[int(id)] = true
	var grew: bool = true
	while grew:
		grew = false
		for id: Variant in points:
			var nid: int = int(id)
			if connected.has(nid) or int(points[id]) <= 0 or not nodes.has(nid):
				continue
			for req: Dictionary in nodes[nid].get("requirements", []):
				var rid: int = int(req["nodeID"])
				if connected.has(rid) and int(points.get(rid, 0)) >= int(req["requirement"]):
					connected[nid] = true
					grew = true
					break
	for id: Variant in points:
		if int(points[id]) > 0 and not connected.has(int(id)):
			return false
	return true


# ============================================================================
# SKILLS
# ============================================================================

func set_skill(slot: int, ability_id: String) -> void:
	if slot < 0 or slot >= skills.size():
		return

	skills[slot] = {
		"ability": ability_id,
		"level": 20,
		"tree": {}
	}
	_skill_nodes[slot] = {}

	# Load skill tree nodes if ability is valid
	if ability_id != "":
		var ability: Dictionary = GameData.get_ability(ability_id)
		if "skillTree" in ability:
			var tree_id: String = ability["skillTree"]
			var tree: Dictionary = GameData.get_skill_tree(tree_id)
			if "nodes" in tree and tree["nodes"] is Array:
				for node: Variant in tree["nodes"]:
					if node is Dictionary:
						var node_entry: Dictionary = node
						if "id" in node_entry:
							var node_id: int = int(node_entry["id"])
							_skill_nodes[slot][node_id] = node_entry

	changed.emit()


func set_skill_level(slot: int, lvl: int) -> void:
	if slot < 0 or slot >= skills.size():
		return

	skills[slot]["level"] = lvl
	changed.emit()


func get_skill_points(slot: int, node_id: int) -> int:
	if slot < 0 or slot >= skills.size():
		return 0

	var tree: Dictionary = skills[slot].get("tree", {})
	if node_id in tree:
		return tree[node_id] as int
	return 0


func skill_points_spent(slot: int) -> int:
	if slot < 0 or slot >= skills.size():
		return 0

	var total: int = 0
	var tree: Dictionary = skills[slot].get("tree", {})
	for points: Variant in tree.values():
		total += int(points)
	return total


func _skill_is_valid(slot: int, node_id: int) -> bool:
	if slot < 0 or slot >= skills.size():
		return false

	if node_id not in _skill_nodes[slot]:
		return false

	if get_skill_points(slot, node_id) == 0:
		return true

	var node: Dictionary = _skill_nodes[slot][node_id]
	return requirements_met(node, skills[slot].get("tree", {}))


func can_add_skill_point(slot: int, node_id: int) -> bool:
	if slot < 0 or slot >= skills.size():
		return false

	if node_id not in _skill_nodes[slot]:
		return false

	var node: Dictionary = _skill_nodes[slot][node_id]

	if "maxPoints" not in node or int(node["maxPoints"]) <= 0:
		return false

	var current_points: int = get_skill_points(slot, node_id)
	var max_points: int = int(node["maxPoints"])
	if current_points >= max_points:
		return false

	# Check if total skill points would exceed level
	var total_spent: int = skill_points_spent(slot)
	if total_spent >= skills[slot]["level"]:
		return false

	# Simulate adding a point and check if it would be valid
	var tree: Dictionary = skills[slot]["tree"] as Dictionary
	tree[node_id] = current_points + 1
	var valid: bool = _skill_is_valid(slot, node_id)

	# Restore original state
	if current_points > 0:
		tree[node_id] = current_points
	else:
		tree.erase(node_id)

	return valid


func add_skill_point(slot: int, node_id: int) -> bool:
	if not can_add_skill_point(slot, node_id):
		return false

	var tree: Dictionary = skills[slot]["tree"] as Dictionary
	tree[node_id] = get_skill_points(slot, node_id) + 1
	changed.emit()
	return true


func remove_skill_point(slot: int, node_id: int) -> bool:
	if slot < 0 or slot >= skills.size():
		return false

	var tree: Dictionary = skills[slot]["tree"] as Dictionary
	if node_id not in tree or get_skill_points(slot, node_id) == 0:
		return false

	var current_points: int = get_skill_points(slot, node_id)
	var old_tree: Dictionary = tree.duplicate()

	# Decrement or remove
	if current_points - 1 <= 0:
		tree.erase(node_id)
	else:
		tree[node_id] = current_points - 1

	# Check if any allocated node is now invalid or cut off from the root
	var ok: bool = all_connected(_skill_nodes[slot], tree)
	for allocated_node_id: Variant in tree.keys():
		ok = ok and _skill_is_valid(slot, int(allocated_node_id))
	if not ok:
		skills[slot]["tree"] = old_tree
		return false

	changed.emit()
	return true


# ============================================================================
# ITEMS
# ============================================================================

func set_item(slot: String, item_dict: Dictionary) -> void:
	items[slot] = item_dict.duplicate()
	changed.emit()


func clear_item(slot: String) -> void:
	if slot in items:
		items.erase(slot)
		changed.emit()


# ============================================================================
# ENEMY
# ============================================================================

func set_enemy(key: String, value: Variant) -> void:
	enemy[key] = value
	changed.emit()


func set_enemy_ailment(ailment_id: int, stacks: int) -> void:
	var ailments: Dictionary = enemy.get("ailments", {}) as Dictionary
	if stacks > 0:
		ailments[ailment_id] = stacks
	elif ailment_id in ailments:
		ailments.erase(ailment_id)

	enemy["ailments"] = ailments
	changed.emit()


# ============================================================================
# PLAYER STATE
# ============================================================================

func set_player_state(key: String, value: Variant) -> void:
	player_state[key] = value
	changed.emit()
