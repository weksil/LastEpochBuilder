class_name PassiveLink
extends Node2D

## Connection between two tree nodes: the game rail (art: TreeArt.connection — rail and its glowing fill, drawn along
## the segment) or a plain line when the tree has no art.

@export var active_color: Color = Color.WHITE
@export var inactive_color: Color = Color.GRAY

var _has_art: bool = false


func connect_points(from: Vector2, to: Vector2, art: Dictionary = {}) -> void:
	var rail_tex: Texture2D = TreeArt.texture(art.get("rail", {}).get("sprite"))
	_has_art = rail_tex != null
	%Art.visible = _has_art
	%Plain.visible = not _has_art
	if not _has_art:
		%Plain.points = PackedVector2Array([from, to])
		return
	var length: float = from.distance_to(to)
	# the rail sprites are vertical: +y of the rotated Art node runs from `from` to `to`
	%Art.position = from
	%Art.rotation = (to - from).angle() - PI / 2.0
	var rail: Dictionary = art["rail"]
	%Rail.texture = rail_tex
	TreeArt.apply_nine_slice(%Rail, str(rail["sprite"]), Vector2(TreeArt.size(rail).x, length))
	%Rail.self_modulate = TreeArt.color(rail)
	%Rail.size = Vector2(TreeArt.size(rail).x, length)
	%Rail.position = Vector2(-%Rail.size.x / 2.0, 0.0)
	var fill: Dictionary = art.get("fill", {})
	var fill_tex: Texture2D = TreeArt.texture(fill.get("sprite"))
	if fill_tex != null:
		%Fill.texture = fill_tex
		%Fill.self_modulate = TreeArt.color(fill)
		%Fill.size = Vector2(TreeArt.size(fill).x, length)
		%Fill.position = Vector2(-%Fill.size.x / 2.0, 0.0)


func set_active(on: bool) -> void:
	if _has_art:
		%Fill.visible = on and %Fill.texture != null
		return
	%Plain.default_color = active_color if on else inactive_color
