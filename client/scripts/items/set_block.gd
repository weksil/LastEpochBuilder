class_name SetBlock extends VBoxContainer

## Set block of item tooltips (set_block.tscn); show_set() may be called before the node enters the tree.

## One Label line (set members and set bonuses).
@export var line_scene: PackedScene


## The set block of a set item: its members (equipped ones highlighted) and the bonuses by the number of pieces,
## active ones (for the pieces equipped now) green, the others grey. set_id -1 hides the block.
func show_set(set_id: int) -> void:
	visible = set_id >= 0
	if set_id < 0:
		return
	var set_data: Dictionary = GameData.set_data(set_id)
	var count: int = int(BuildMods.set_counts(Build).get(set_id, 0))
	var members: Array = set_data.get("items", [])
	var title_label: Label = get_node("%SetTitle")
	title_label.text = tr("Set \"%s\": %d/%d items equipped") % [str(set_data.get("setName", "")), count, members.size()]
	var equipped: Dictionary = {}
	for slot: String in Build.items:
		if (Build.items[slot] as Dictionary).has("unique"):
			equipped[int(Build.items[slot]["unique"])] = true
	for member: Dictionary in members:
		var unique: Dictionary = GameData.unique(int(member.get("uniqueID", -1)))
		var base_name: String = GameData.display_name(GameData.item_base(int(unique.get("baseType", -1))))
		var line: Label = line_scene.instantiate()
		get_node("%SetItems").add_child(line)
		line.text = "%s (%s)" % [GameData.display_name(unique), base_name]
		line.theme_type_variation = &"SetBonusActive" if equipped.has(int(member.get("uniqueID", -1))) else &"SetBonusInactive"
	var bonuses: Array = (set_data.get("tooltipDescriptions", []) as Array).duplicate()
	bonuses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("setRequirement", 0)) < int(b.get("setRequirement", 0)))
	for bonus: Dictionary in bonuses:
		var requirement: int = int(bonus.get("setRequirement", 0))
		var line: Label = line_scene.instantiate()
		get_node("%SetBonuses").add_child(line)
		line.text = tr("%d items: %s") % [requirement, ItemCompare.expand_template(str(bonus.get("description", "")))]
		line.theme_type_variation = &"SetBonusActive" if requirement <= count else &"SetBonusInactive"
