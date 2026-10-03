extends Node

var classes: Array
var _trees: Array
var _tree_node_stats: Dictionary

func _ready() -> void:
	var data_dir: String = ProjectSettings.globalize_path("res://").path_join("../research/data/game").simplify_path()

	# Load classes.json
	var classes_path: String = data_dir.path_join("classes.json")
	var classes_content: String = FileAccess.get_file_as_string(classes_path)
	if FileAccess.get_open_error() != OK:
		push_error("Failed to load classes.json from: %s" % classes_path)
		return

	var classes_json: Variant = JSON.parse_string(classes_content)
	if classes_json == null:
		push_error("Failed to parse classes.json")
		return

	if classes_json is Dictionary and "data" in classes_json:
		classes = classes_json["data"] as Array
	else:
		push_error("classes.json does not contain 'data' array")
		return

	# Load trees.json
	var trees_path: String = data_dir.path_join("trees.json")
	var trees_content: String = FileAccess.get_file_as_string(trees_path)
	if FileAccess.get_open_error() != OK:
		push_error("Failed to load trees.json from: %s" % trees_path)
		return

	var trees_json: Variant = JSON.parse_string(trees_content)
	if trees_json == null:
		push_error("Failed to parse trees.json")
		return

	if trees_json is Array:
		_trees = trees_json as Array
	else:
		push_error("trees.json is not an array")
		return

	# Load tree_node_stats.json
	var stats_path: String = data_dir.path_join("tree_node_stats.json")
	var stats_content: String = FileAccess.get_file_as_string(stats_path)
	if FileAccess.get_open_error() != OK:
		push_error("Failed to load tree_node_stats.json from: %s" % stats_path)
		return

	var stats_json: Variant = JSON.parse_string(stats_content)
	if stats_json == null:
		push_error("Failed to parse tree_node_stats.json")
		return

	if stats_json is Dictionary:
		_tree_node_stats = stats_json as Dictionary
	else:
		push_error("tree_node_stats.json is not a dictionary")
		return

func get_class_data(class_id: int) -> Dictionary:
	for class_entry: Variant in classes:
		if class_entry is Dictionary:
			var entry: Dictionary = class_entry
			if "classID" in entry and int(entry["classID"]) == class_id:
				return entry
	return {}

func get_passive_tree(class_id: int) -> Dictionary:
	for tree: Variant in _trees:
		if tree is Dictionary:
			var tree_entry: Dictionary = tree
			if "kind" in tree_entry and tree_entry["kind"] == "passive":
				var tree_classes: Array = tree_entry.get("classes", [])
				if not tree_classes.is_empty() and int(tree_classes[0].get("classID", -1)) == class_id:
					return tree_entry
	return {}

func get_node_stats(tree_id: String, node_id: int) -> Dictionary:
	var key: String = "%s:%d" % [tree_id, node_id]
	if key in _tree_node_stats:
		return _tree_node_stats[key] as Dictionary
	return {}
