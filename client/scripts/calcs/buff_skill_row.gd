class_name BuffSkillRow extends PanelContainer

## One equipped skill in the "Skill buffs on the character" panel: switch (input `buff_active`) and the buff mods it gives.

signal active_toggled(slot: int, on: bool)

var slot: int = -1

var _mod_count: int = 0

@onready var _check: CheckBox = %ActiveCheck
@onready var _plain: Label = %PlainLabel
@onready var _status: Label = %StatusLabel
@onready var _toggle: Button = %ModsToggle
@onready var _mods_panel: PanelContainer = %ModsPanel
@onready var _mods_label: Label = %ModsLabel


func _ready() -> void:
	_check.toggled.connect(func(on: bool) -> void: active_toggled.emit(slot, on))
	_toggle.toggled.connect(func(_on: bool) -> void: _sync_mods_visibility())


## entry: one element of BuildMods.skill_buffs.
func show_entry(entry: Dictionary) -> void:
	slot = int(entry.get("slot", -1))
	var title: String = tr("Slot %d · %s") % [slot + 1, str(entry.get("ability_name", ""))]
	var mods: Array = entry.get("mods", [])
	var active: bool = bool(entry.get("active", true))
	var has_buff: bool = not mods.is_empty()
	_check.visible = has_buff
	_plain.visible = not has_buff
	_check.text = title
	_plain.text = title
	_check.set_pressed_no_signal(active)
	if not has_buff:
		_status.text = tr("no buffs on the character")
	elif active:
		_status.text = tr("active · mods: %d") % mods.size()
	else:
		_status.text = tr("off — no effect")
	var lines: PackedStringArray = []
	for mod: StatMod in mods:
		lines.append(BuildMods.describe_mod(mod))
	_mods_label.text = "\n".join(lines)
	_toggle.visible = not lines.is_empty()
	_mod_count = lines.size()
	_sync_mods_visibility()
	theme_type_variation = &"RowActive" if (has_buff and active) else &"RowIdle"


func _sync_mods_visibility() -> void:
	_mods_panel.visible = _toggle.visible and _toggle.button_pressed
	_toggle.text = tr("%s mods (%d)") % ["▾" if _toggle.button_pressed else "▸", _mod_count]
