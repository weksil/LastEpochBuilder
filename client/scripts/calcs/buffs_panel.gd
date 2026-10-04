class_name BuffsPanel extends PanelContainer

## "Skill buffs on the character": every equipped skill with the mods it gives the character (BuildMods.skill_buffs)
## and a switch bound to the skill input `buff_active`. Rows are reused while the set of skills is unchanged.

@export var row_scene: PackedScene

var _signature: String = ""
var _rows: Array[BuffSkillRow] = []

@onready var _list: VBoxContainer = %List


func refresh() -> void:
	var entries: Array[Dictionary] = BuildMods.skill_buffs(Build)
	var sig: PackedStringArray = []
	for entry: Dictionary in entries:
		sig.append("%d:%s" % [int(entry["slot"]), str(entry["ability_name"])])
	var signature: String = "|".join(sig)
	if signature != _signature:
		_signature = signature
		for row: BuffSkillRow in _rows:
			_list.remove_child(row)
			row.queue_free()
		_rows.clear()
		for _entry: Dictionary in entries:
			var row: BuffSkillRow = row_scene.instantiate() as BuffSkillRow
			_list.add_child(row)
			row.active_toggled.connect(_on_active_toggled)
			_rows.append(row)
	for i: int in range(entries.size()):
		_rows[i].show_entry(entries[i])
	visible = not entries.is_empty()


func _on_active_toggled(slot: int, on: bool) -> void:
	Build.set_skill_input(slot, "buff_active", on)
