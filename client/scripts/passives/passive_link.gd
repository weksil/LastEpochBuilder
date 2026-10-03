class_name PassiveLink
extends Line2D

@export var active_color: Color = Color.WHITE
@export var inactive_color: Color = Color.GRAY

func set_active(on: bool) -> void:
	if on:
		default_color = active_color
	else:
		default_color = inactive_color
