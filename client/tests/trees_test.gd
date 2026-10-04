extends Node

## Every node of every skill and passive tree must be allocatable with enough points.
## Run: Godot_console.exe --headless --path client res://tests/trees_test.tscn

var _failed: int = 0


func _ready() -> void:
	_skill_trees()
	_passive_trees()
	_removal_rules()
	Build.passive_cap_override = -1
	_caps()
	_art()
	print("TREES TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _skill_trees() -> void:
	var checked: int = 0
	var skipped: PackedStringArray = []
	for tree: Dictionary in GameData._trees:
		if tree.get("kind") != "skill" or tree.get("nodes", []).is_empty():
			continue
		var tree_id: String = str(tree["treeID"])
		# obsolete trees (version 0, e.g. Fire Shield) have no player ability pointing at them
		if GameData.get_ability(tree_id).get("skillTree") != tree_id:
			skipped.append("%s (%s)" % [tree["name"], tree_id])
			continue
		Build.set_skill(0, tree_id)
		Build.set_skill_level(0, 1000)
		_fill(func(id: int) -> bool: return Build.add_skill_point(0, id), tree["nodes"])
		var missing: PackedStringArray = []
		for node: Dictionary in tree["nodes"]:
			if int(node["maxPoints"]) > 0 and Build.get_skill_points(0, int(node["id"])) < int(node["maxPoints"]):
				missing.append("%s [%d] %d/%d" % [GameData.display_name(node), int(node["id"]), Build.get_skill_points(0, int(node["id"])), int(node["maxPoints"])])
		checked += 1
		if not missing.is_empty():
			_failed += 1
			print("FAIL skill tree %s (%s): %s" % [tree["name"], tree_id, ", ".join(missing)])
	print("skill trees checked: %d; without ability record (skipped): %s" % [checked, ", ".join(skipped)])


func _passive_trees() -> void:
	for class_data: Dictionary in GameData.classes:
		var class_id: int = int(class_data["classID"])
		Build.set_class(class_id)
		Build.passive_cap_override = 100000  # the real cap (level - 2 + quests) is smaller than the whole tree
		var tree: Dictionary = GameData.get_passive_tree(class_id)
		_fill(func(id: int) -> bool: return Build.add_point(id), tree["nodes"])
		var missing: PackedStringArray = []
		for node: Dictionary in tree["nodes"]:
			if int(node["maxPoints"]) > 0 and Build.get_points(int(node["id"])) < int(node["maxPoints"]):
				missing.append("%s [%d]" % [GameData.display_name(node), int(node["id"])])
		if missing.is_empty():
			print("ok   passive tree %s: all %d nodes" % [class_data["className"], tree["nodes"].size()])
		else:
			_failed += 1
			print("FAIL passive tree %s: %s" % [class_data["className"], ", ".join(missing)])


## Harvest: Great Scythe [5] and Spectral Whetstone [6] require each other; removing their path must be refused.
func _removal_rules() -> void:
	Build.set_class(3)
	Build.set_skill(0, "ha84")
	for i in range(3):
		Build.add_skill_point(0, 10)  # Mind Harvest
	for i in range(3):
		Build.add_skill_point(0, 5)  # Great Scythe (via Mind Harvest 3)
	for i in range(3):
		Build.add_skill_point(0, 6)  # Spectral Whetstone (via Great Scythe 3)
	var got: String = "%d/%d/%d" % [Build.get_skill_points(0, 10), Build.get_skill_points(0, 5), Build.get_skill_points(0, 6)]
	_check("Harvest path allocated", got == "3/3/3", got)
	var removed: bool = Build.remove_skill_point(0, 10)
	_check("cannot cut Mind Harvest below the Great Scythe requirement", not removed, str(removed))
	Build.add_skill_point(0, 2)  # Harrowing Blade 1 also unlocks Great Scythe
	removed = Build.remove_skill_point(0, 10)
	_check("can remove once another requirement holds", removed, str(removed))


func _caps() -> void:
	Build.set_class(3)
	Build.set_level(100)
	_check("passive cap at level 100 is 113", Build.passive_point_cap() == 113, str(Build.passive_point_cap()))
	Build.set_level(10)
	_check("passive cap at level 10 is 23", Build.passive_point_cap() == 23, str(Build.passive_point_cap()))
	Build.passive_cap_override = 0
	var any_added: bool = false
	for node: Dictionary in GameData.get_passive_tree(3)["nodes"]:
		any_added = any_added or Build.add_point(int(node["id"]))
	_check("no passive point when cap is 0", not any_added, str(any_added))
	Build.passive_cap_override = -1
	Build.set_level(100)
	Build.set_skill(0, "ha84")
	Build.set_skill_level(0, 1)
	Build.add_skill_point(0, 10)
	_check("skill cap = level 1", not Build.add_skill_point(0, 10) and Build.skill_point_cap(0) == 1, str(Build.skill_point_cap(0)))
	Build.set_skill_level(0, 20)


## Game visuals (TreeArt, tools/extract/extract_tree_art.py): every node of the active skill trees and of the passive trees
## has an icon texture, except the passive nodes whose name has no UI node in the game prefabs.
const ART_EXCEPTIONS: Array[String] = ["ac-1:60", "ac-1:12", "mg-1:66", "mg-1:67", "rg-1:11"]


func _art() -> void:
	var missing: PackedStringArray = []
	var checked: int = 0
	for tree: Dictionary in GameData._trees:
		var tree_id: String = str(tree["treeID"])
		var active_skill: bool = tree.get("kind") == "skill" and GameData.get_ability(tree_id).get("skillTree") == tree_id
		if not active_skill and tree.get("kind") != "passive":
			continue
		for node: Dictionary in tree.get("nodes", []):
			var key: String = "%s:%d" % [tree_id, int(node["id"])]
			if ART_EXCEPTIONS.has(key):
				continue
			checked += 1
			var icon: Dictionary = TreeArt.layer(TreeArt.node_art(tree_id, int(node["id"])), "IconMask/Icon")
			if TreeArt.texture(icon.get("sprite")) == null:
				missing.append(key)
	_check("tree art: %d nodes with icons" % checked, missing.is_empty(), ", ".join(missing.slice(0, 20)))
	_check("tree art: connection rail", not TreeArt.connection("fi9").is_empty(), "fi9 has no rail")
	_check("tree art: Fireball background", TreeArt.decor("fi9", 0).size() > 0, "no decor")


func _check(label: String, ok: bool, detail: String) -> void:
	if ok:
		print("ok   %s" % label)
	else:
		_failed += 1
		print("FAIL %s (%s)" % [label, detail])


## Repeatedly adds points to every node until nothing changes.
func _fill(add: Callable, nodes: Array) -> void:
	var progress: bool = true
	while progress:
		progress = false
		for node: Dictionary in nodes:
			while add.call(int(node["id"])):
				progress = true
