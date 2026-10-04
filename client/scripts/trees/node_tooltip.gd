class_name NodeTooltip
extends VBoxContainer

## Tooltip of a skill/passive tree node split into parts: description, per-point stats, fixed stats, the bonus at a
## point threshold (noScalingType 1), altText. Contract: client/docs/UI.md "Tree".

@export var stat_scene: PackedScene


## Cleans a string: removes "{" and "}", strips edges. null → "".
static func _clean(s: Variant) -> String:
	if s == null:
		return ""
	var text: String = str(s)
	text = text.replace("{", "").replace("}", "")
	return text.strip_edges()


## Models tooltip data from game stats. Returns a dictionary with sections and presentation rules.
static func model(stats: Dictionary, title: String, max_points: int, points: int) -> Dictionary:
	var description: String = _clean(stats.get("description"))
	if description.is_empty():
		description = _clean(stats.get("nodeDescription"))
	var alt: String = _clean(stats.get("altText"))

	var single: bool = max_points <= 1
	var threshold_mode: bool = (
		int(stats.get("noScalingType", 0)) == 1 and
		int(stats.get("noScalingPointThreshold", 0)) > 0
	)
	var threshold: int = int(stats.get("noScalingPointThreshold", 0))

	var per_point: Array = []
	var fixed: Array = []
	var bonus_stats: Array = []

	# Process tooltip stats
	if stats.has("tooltipStats"):
		for stat in stats["tooltipStats"]:
			var value: String = str(stat.get("value", "")).strip_edges()
			var stat_name: String = str(stat.get("statName", "")).strip_edges()
			var line_text: String = (value + " " + stat_name).strip_edges()

			if line_text.is_empty():
				continue

			var downside: bool = int(stat.get("downside", 0)) != 0
			var no_scaling: int = int(stat.get("noScaling", 0))

			var line: Dictionary = {"text": line_text, "downside": downside}

			if no_scaling == 0:
				# Per-point stat
				per_point.append(line)

				# Add total points info if applicable
				if not single and points >= 2:
					var num: Variant = stat.get("num")
					if num is float or num is int:
						num = float(num)
						var total: String = ""
						var explicit_sign: bool = bool(stat.get("explicitSign", false))
						if explicit_sign and num * points >= 0:
							total = "+"
						var amount: float = snappedf(num * points, 0.01)
						total += str(int(amount)) if amount == floorf(amount) else str(amount)
						var unit: Variant = stat.get("unit")
						if unit is String:
							total += unit
						line_text = line_text + "  " + LE.t("(%d points: %s)") % [points, total]
						per_point[-1]["text"] = line_text
			elif threshold_mode:
				# Bonus stat
				bonus_stats.append(line)
			else:
				# Fixed stat
				fixed.append(line)

	# If single point mode, move fixed to end of per_point
	if single and not fixed.is_empty():
		per_point.append_array(fixed)
		fixed.clear()

	# Build bonus section
	var bonus: Dictionary = {}
	if threshold_mode:
		bonus = {
			"threshold": threshold,
			"description": _clean(stats.get("pointBonusDescription")),
			"stats": bonus_stats,
			"active": points >= threshold
		}

	return {
		"title": title,
		"points": points,
		"max_points": max_points,
		"description": description,
		"alt": alt,
		"per_point": per_point,
		"fixed": fixed,
		"single": single,
		"bonus": bonus
	}


## Converts model to plain text (for tooltip_text).
static func to_text(m: Dictionary) -> String:
	var lines: PackedStringArray = []

	# Title
	lines.append(m["title"])

	# Points
	if m.get("max_points", 0) > 0:
		lines.append(LE.t("Points: %d/%d") % [m["points"], m["max_points"]])

	# Description
	var description: String = m.get("description", "")
	if not description.is_empty():
		lines.append(description)

	# Per-point section
	var per_point: Array = m.get("per_point", [])
	if not per_point.is_empty():
		var header: String = "Effect" if m.get("single", false) else "Per point"
		lines.append("— " + LE.t(header) + " —")
		for line_obj in per_point:
			lines.append(line_obj["text"])

	# Fixed section
	var fixed: Array = m.get("fixed", [])
	if not fixed.is_empty():
		lines.append("— " + LE.t("Fixed: from the first point, does not grow with points") + " —")
		for line_obj in fixed:
			lines.append(line_obj["text"])

	# Bonus section
	var bonus: Dictionary = m.get("bonus", {})
	if not bonus.is_empty():
		var threshold: int = bonus.get("threshold", 0)
		lines.append("— " + LE.t("Bonus at %d points") % threshold + " —")
		var active: bool = bonus.get("active", false)
		if active:
			lines.append(LE.t("Active"))
		else:
			lines.append(LE.t("Inactive: %d/%d points") % [m["points"], threshold])
		var bonus_description: String = bonus.get("description", "")
		if not bonus_description.is_empty():
			lines.append(bonus_description)
		var bonus_stats: Array = bonus.get("stats", [])
		for line_obj in bonus_stats:
			lines.append(line_obj["text"])

	# Alt text
	var alt: String = m.get("alt", "")
	if not alt.is_empty():
		lines.append(alt)

	return "\n".join(lines)


## Populates the scene with model data.
func show_model(m: Dictionary) -> void:
	# Title
	%Title.text = m["title"]

	# Points
	%Points.text = LE.t("Points: %d/%d") % [m["points"], m["max_points"]]
	%Points.visible = m.get("max_points", 0) > 0

	# Description
	var description: String = m.get("description", "")
	%Description.text = description
	%Description.visible = not description.is_empty()

	# Per-point section
	var per_point: Array = m.get("per_point", [])
	%PerPointBox.visible = not per_point.is_empty()
	if not per_point.is_empty():
		var header: String = "Effect" if m.get("single", false) else "Per point"
		%PerPointHeader.text = LE.t(header)
		_fill_stat_container(%PerPointStats, per_point, false)

	# Fixed section
	var fixed: Array = m.get("fixed", [])
	%FixedBox.visible = not fixed.is_empty()
	if not fixed.is_empty():
		_fill_stat_container(%FixedStats, fixed, false)

	# Bonus section
	var bonus: Dictionary = m.get("bonus", {})
	%BonusBox.visible = not bonus.is_empty()
	if not bonus.is_empty():
		var threshold: int = bonus.get("threshold", 0)
		%BonusHeader.text = LE.t("Bonus at %d points") % threshold

		var active: bool = bonus.get("active", false)
		%BonusState.text = (
			LE.t("Active") if active
			else LE.t("Inactive: %d/%d points") % [m["points"], threshold]
		)
		%BonusState.theme_type_variation = &"SummaryActive" if active else &"SummaryOff"

		var bonus_description: String = bonus.get("description", "")
		%BonusDescription.text = bonus_description
		%BonusDescription.visible = not bonus_description.is_empty()

		var bonus_stats: Array = bonus.get("stats", [])
		_fill_stat_container(%BonusStats, bonus_stats, not active)

	# Alt text
	var alt: String = m.get("alt", "")
	%AltBox.visible = not alt.is_empty()
	if not alt.is_empty():
		%AltText.text = alt


## Helper to fill a stat container with labels.
func _fill_stat_container(container: VBoxContainer, lines: Array, inactive_bonus: bool) -> void:
	# Clear existing children
	for child in container.get_children():
		child.queue_free()

	# Add new labels
	for line_obj in lines:
		var label: Label = stat_scene.instantiate()
		label.text = line_obj["text"]

		if line_obj.get("downside", false):
			label.theme_type_variation = &"NodeTooltipDownside"
		elif inactive_bonus:
			label.theme_type_variation = &"MutedLabel"
		else:
			label.theme_type_variation = &""

		container.add_child(label)
