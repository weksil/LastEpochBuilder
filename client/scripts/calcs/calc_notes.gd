class_name CalcNotes extends PanelContainer

## Collapsible «Не учтено» block of the «Расчёты» tab: mechanics of the build that the engine does not count.

@onready var _toggle: Button = %ToggleButton
@onready var _notes_label: Label = %NotesLabel

var _count: int = 0


func _ready() -> void:
	_toggle.toggled.connect(func(_on: bool) -> void: _refresh())


## Empty list hides the block; the expanded state survives updates.
func show_notes(notes: Array) -> void:
	_count = notes.size()
	visible = _count > 0
	var lines: PackedStringArray = []
	for note: Variant in notes:
		lines.append("• " + str(note))
	_notes_label.text = "\n".join(lines)
	_refresh()


func _refresh() -> void:
	_notes_label.visible = _toggle.button_pressed and _count > 0
	_toggle.text = "%s Не учтено (%d)" % ["▾" if _toggle.button_pressed else "▸", _count]
