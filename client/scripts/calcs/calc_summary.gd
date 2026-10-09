class_name CalcSummary extends PanelContainer

## Headline strip of the "Calculations" tab: the four numbers that matter, taken from the rows of SkillCalc.compute
## by label (docs/UI.md). A missing row shows an em dash.

## Fixed engine labels and section titles: English sources, compared translated (find_row applies LE.t to them).
const DPS_LABEL: String = "DPS vs enemy"
const HIT_LABEL: String = "Average hit vs enemy"
const USES_LABEL: String = "Uses per second"
const CRIT_LABEL: String = "Crit chance"
const TARGET_LABEL: String = "Target"
## Sections that hold the totals of the main component. Labels repeat elsewhere (every "Ailment: ..." section has its own
## "DPS vs enemy", components have prefixed "X: Crit" ...), so the rows are looked up in these exact sections.
const ENEMY_SECTION: String = "Against enemy"
const SPEED_SECTION: String = "Speed and mana"
const CRIT_SECTION: String = "Crit"

@onready var _title: Label = %SkillTitle
@onready var _target: Label = %TargetLabel
@onready var _dps: CalcTile = %DpsTile
@onready var _hit: CalcTile = %HitTile
@onready var _uses: CalcTile = %UsesTile
@onready var _crit: CalcTile = %CritTile
@onready var _projectile_row: HBoxContainer = %ProjectileRow
@onready var _projectile_buttons: Array[Button] = [%ProjectileOne, %ProjectileAverage, %ProjectileAll]
@onready var _projectile_count: Label = %ProjectileCount


func _ready() -> void:
	for button: Button in _projectile_buttons:
		button.toggled.connect(_on_projectile_toggled.bind(str(button.get_meta("mode"))))


func _on_projectile_toggled(pressed: bool, mode: String) -> void:
	if pressed:
		Build.set_skill_projectile_mode(Build.selected_skill, mode)


## result: SkillCalc.compute output. Empty sections (no skill in the slot) clear the strip. The tile tooltips of a lean
## result are built on hover from the result with details of the selected skill.
func show_result(result: Dictionary) -> void:
	var target: Dictionary = find_row(result, TARGET_LABEL, ENEMY_SECTION)
	_title.text = str(result.get("title", ""))
	_target.text = (tr("Target: %s") % str(target.get("text", ""))) if not target.is_empty() else ""
	_show_tile(_dps, result, DPS_LABEL, ENEMY_SECTION, false, tr("damage per second vs target"))
	_show_tile(_hit, result, HIT_LABEL, ENEMY_SECTION, false, tr("including crit chance"))
	# uses and crit: skills whose only component is prefixed (minions, triggers) have them in another section
	_show_tile(_uses, result, USES_LABEL, SPEED_SECTION, true, "")
	_show_tile(_crit, result, CRIT_LABEL, CRIT_SECTION, true, "")
	_show_projectiles(result.get("projectiles", {}))


func _show_tile(tile: CalcTile, result: Dictionary, label: String, section: String, any_section: bool, sub: String) -> void:
	var row: Dictionary = _tile_row(result, label, section, any_section)
	var source: Callable = Callable()
	if bool(result.get("lean", false)) and not row.is_empty():
		source = _detailed_breakdown.bind(str(result.get("virtual_id", "")), Build.selected_skill, label, section, any_section)
	tile.show_value(str(row.get("text", "")), sub, str(row.get("breakdown", "")), source)


static func _tile_row(result: Dictionary, label: String, section: String, any_section: bool) -> Dictionary:
	var row: Dictionary = find_row(result, label, section)
	if row.is_empty() and any_section:
		row = find_row(result, label)
	return row


## `virtual_id` is the granted skill shown instead of the bar slot (GrantedCalc), "" for a bar skill.
static func _detailed_breakdown(virtual_id: String, slot: int, label: String, section: String, any_section: bool) -> String:
	var full: Dictionary = GrantedCalc.compute(Build, virtual_id, true) if virtual_id != "" else SkillCalc.compute(Build, slot, true)
	return str(_tile_row(full, label, section, any_section).get("breakdown", ""))


## Selector "how many projectiles of one use hit the target", only for skills that fire projectiles. Without shotgun
## every mode means one projectile per target, so the buttons are disabled.
func _show_projectiles(proj: Dictionary) -> void:
	_projectile_row.visible = not proj.is_empty()
	if proj.is_empty():
		return
	var shotgun: bool = bool(proj.get("shotgun", false))
	var tip: String = str(proj.get("row", {}).get("breakdown", ""))
	for button: Button in _projectile_buttons:
		button.set_pressed_no_signal(str(button.get_meta("mode")) == str(proj.get("mode", "")))
		button.disabled = not shotgun
		button.tooltip_text = tip
	if shotgun:
		_projectile_count.text = tr("in the calculation %s of max %s per use · shotgun: yes") % [LE.fmt_num(float(proj["factor"])), LE.fmt_num(float(proj["count"]))]
	else:
		_projectile_count.text = tr("max %s per use · shotgun: no, one projectile per target") % LE.fmt_num(float(proj["count"]))
	_projectile_count.tooltip_text = tip


## First row with this label in the section titled exactly `section` (any section when empty); {} if none.
## label / section_title are English sources (or already translated text): both are compared translated.
static func find_row(result: Dictionary, label: String, section_title: String = "") -> Dictionary:
	label = LE.t(label)
	section_title = LE.t(section_title)
	for section: Dictionary in result.get("sections", []):
		if section_title != "" and str(section.get("title", "")) != section_title:
			continue
		for row: Dictionary in section.get("rows", []):
			if str(row.get("label", "")) == label:
				return row
	return {}
