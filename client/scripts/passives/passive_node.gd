class_name PassiveNode
extends Button

signal add_requested(node_id: int)
signal remove_requested(node_id: int)

var node_id: int
var max_points: int
var _has_art: bool = false


## art: TreeArt.node_art(...) — the node's game layers; empty → plain round button with the name under it.
func setup(node: Dictionary, stats: Dictionary, art: Dictionary = {}) -> void:
	node_id = int(node["id"])
	max_points = int(node["maxPoints"])

	var title: String = str(node["displayName"]) if node.get("displayName") != null else str(node.get("name", ""))
	var name_label: Label = %NameLabel
	name_label.text = title

	var tooltip_parts: PackedStringArray = []

	tooltip_parts.append(title)

	if stats.get("nodeDescription") is String and stats["nodeDescription"] != "":
		tooltip_parts.append(stats["nodeDescription"])

	if stats.has("tooltipStats"):
		for stat in stats["tooltipStats"]:
			if stat.has("statName") and stat.has("value"):
				tooltip_parts.append("%s %s" % [str(stat["statName"]), str(stat["value"])])

	tooltip_parts.append(tr("Max points: %d") % max_points)

	tooltip_text = "\n".join(tooltip_parts)
	_apply_art(art)


## Places the game layers (icon under its mask, frames, points plate) around the node centre.
func _apply_art(art: Dictionary) -> void:
	var icon_layer: Dictionary = TreeArt.layer(art, "IconMask/Icon")
	_has_art = not art.is_empty() and TreeArt.texture(icon_layer.get("sprite")) != null
	%Art.visible = _has_art
	%NameLabel.visible = not _has_art
	if not _has_art:
		return
	var s: Array = art.get("size", [60, 60])
	custom_minimum_size = Vector2(float(s[0]), float(s[1]))
	size = custom_minimum_size
	theme_type_variation = &"TreeNodeArt"
	var center: Vector2 = custom_minimum_size / 2.0

	var mask_layer: Dictionary = TreeArt.layer(art, "IconMask")
	var mask_center: Vector2 = center + TreeArt.offset(mask_layer)
	_place(%IconMask, mask_layer, center)
	# the icon is a child of the mask: its position is relative to the mask's top-left corner
	_place(%Icon, icon_layer, mask_center - %IconMask.position)
	_place(%Border, TreeArt.layer(art, "Border"), center)
	_place(%BorderBright, TreeArt.layer(art, "BorderBright"), center)
	_place(%Escape, TreeArt.layer(art, "Border-escape"), center)
	var plate: Dictionary = TreeArt.layer(art, "PointsAllocated/Image")
	if not plate.is_empty():
		TreeArt.apply_nine_slice(%PointsPlate, str(plate["sprite"]), TreeArt.size(plate))
	_place(%PointsPlate, plate, center)
	_place(%PointsFrame, TreeArt.layer(art, "PointsAllocated/Frame"), center)

	var points_label: Label = %PointsLabel
	points_label.theme_type_variation = &"TreeNodePoints"
	points_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if plate.is_empty():
		points_label.visible = false
	else:
		points_label.size = TreeArt.size(plate)
		points_label.position = center + TreeArt.offset(plate) - points_label.size / 2.0


## Texture, tint, size and centre of one layer; hidden when the node has no such layer.
func _place(target: Control, l: Dictionary, center: Vector2) -> void:
	var tex: Texture2D = TreeArt.texture(l.get("sprite"))
	target.visible = tex != null and bool(l.get("active", true))
	if tex == null:
		return
	if target is TextureRect:
		(target as TextureRect).texture = tex
	elif target is NinePatchRect:
		(target as NinePatchRect).texture = tex
	target.self_modulate = TreeArt.color(l)
	target.size = TreeArt.size(l)
	target.position = center + TreeArt.offset(l) - target.size / 2.0


func set_state(points: int, can_add: bool) -> void:
	var points_label: Label = %PointsLabel
	points_label.text = "%d/%d" % [points, max_points]

	if _has_art:
		# allocated: bright frame; available: dimmed icon; locked: dark icon (game FadeOverlay)
		%BorderBright.visible = points > 0 and %BorderBright.texture != null
		%FadeAvailable.visible = points == 0 and can_add and max_points > 0
		%FadeLocked.visible = points == 0 and not can_add and max_points > 0
		return

	if points > 0:
		theme_type_variation = &"PassiveNodeAllocated"
	elif can_add:
		theme_type_variation = &"PassiveNodeAvailable"
	else:
		theme_type_variation = &"PassiveNodeLocked"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			add_requested.emit(node_id)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			remove_requested.emit(node_id)
			accept_event()
