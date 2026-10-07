class_name AilmentRow extends PanelContainer

## One ailment / shred / curse of the enemy in "Conditions" (docs/UI.md): readable name, kind, where it comes from, stacks.
## show_state() updates everything in place without emitting signals.

signal stacks_changed(ailment_id: int, stacks: int)

var ailment_id: int = -1
var display_name: String = ""
## Lower-cased names used by the search field.
var search_text: String = ""

@onready var _name_label: Label = %NameLabel
@onready var _kind_label: Label = %KindLabel
@onready var _reason_label: Label = %ReasonLabel
@onready var _spin: SpinBox = %StacksSpin


func _ready() -> void:
	_spin.value_changed.connect(func(value: float) -> void: stacks_changed.emit(ailment_id, int(value)))


## data: one element of GameData.enemy_ailments().
func setup(data: Dictionary) -> void:
	ailment_id = int(data.get("id", -1))
	var title: String = str(data.get("displayName", ""))
	var raw_name: String = str(data.get("name", ""))
	if title == "":
		title = raw_name
	display_name = title
	_name_label.text = title
	var kind: String = ""
	if int(data.get("positive", 0)) != 0:
		kind = tr("buff")
	elif bool(data.get("isCurse", false)):
		kind = tr("curse")
	elif raw_name.contains("Shred") or title.begins_with("Shred"):
		kind = tr("shred")
	_kind_label.text = kind
	search_text = (title + " " + raw_name + " " + kind).to_lower()

	var max_instances: int = int(data.get("maxInstances", 0))
	_spin.max_value = float(max_instances) if max_instances > 0 else 100000.0
	tooltip_text = _tooltip(data, max_instances)


## stacks: current value; reason: short source text ("" if unknown); has_source: false marks an active row without a source.
func show_state(stacks: int, reason: String, has_source: bool) -> void:
	if int(_spin.value) != stacks:
		_spin.set_value_no_signal(float(stacks))
	_reason_label.text = reason
	_reason_label.visible = reason != ""
	if stacks > 0:
		theme_type_variation = &"RowActive" if has_source else &"RowNoSource"
		_reason_label.text = reason if has_source else tr("no source in the build — does not affect the calculation")
		_reason_label.visible = true
	else:
		theme_type_variation = &"RowIdle"
	_name_label.theme_type_variation = &"ValueLabel" if stacks > 0 else &""


func has_edit_focus() -> bool:
	return _spin.get_line_edit().has_focus()


static func _tooltip(data: Dictionary, max_instances: int) -> String:
	var parts: PackedStringArray = []
	var description: String = str(data.get("description", ""))
	if description != "":
		parts.append(description)
	for buff: Variant in data.get("buffs", []):
		if buff is Dictionary:
			var added: float = float((buff as Dictionary).get("added", 0))
			var increased: float = float((buff as Dictionary).get("increased", 0))
			var more: Array = (buff as Dictionary).get("more", [])
			if added != 0.0 or increased != 0.0 or not more.is_empty():
				parts.append(LE.t("%s: added %s, increased %s") % [str((buff as Dictionary).get("propertyName", "")), LE.fmt_num(added), LE.fmt_pct(increased)])
	if max_instances > 0:
		parts.append(LE.t("Max stacks: %d") % max_instances)
	var more_boss: float = float(data.get("moreBuffEffectAgainstBosses", 0))
	if more_boss != 0.0:
		parts.append(LE.t("Vs bosses: ×%s") % LE.fmt_num(1.0 + more_boss))
	return "\n".join(parts)
