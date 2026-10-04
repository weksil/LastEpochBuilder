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


## result: SkillCalc.compute output. Empty sections (no skill in the slot) clear the strip.
func show_result(result: Dictionary) -> void:
	var dps: Dictionary = find_row(result, DPS_LABEL, ENEMY_SECTION)
	var target: Dictionary = find_row(result, TARGET_LABEL, ENEMY_SECTION)
	_title.text = str(result.get("title", ""))
	_target.text = (tr("Target: %s") % str(target.get("text", ""))) if not target.is_empty() else ""
	_dps.show_value(str(dps.get("text", "")), tr("damage per second vs target"), str(dps.get("breakdown", "")))
	var hit: Dictionary = find_row(result, HIT_LABEL, ENEMY_SECTION)
	_hit.show_value(str(hit.get("text", "")), tr("including crit chance"), str(hit.get("breakdown", "")))
	var uses: Dictionary = find_row(result, USES_LABEL, SPEED_SECTION)
	if uses.is_empty():  # skills whose only component is prefixed (minions, triggers)
		uses = find_row(result, USES_LABEL)
	_uses.show_value(str(uses.get("text", "")), "", str(uses.get("breakdown", "")))
	var crit: Dictionary = find_row(result, CRIT_LABEL, CRIT_SECTION)
	if crit.is_empty():
		crit = find_row(result, CRIT_LABEL)
	_crit.show_value(str(crit.get("text", "")), "", str(crit.get("breakdown", "")))


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
