extends Node

## Live check of the Last Epoch Tools import dialog (needs network, NOT part of the regular suite):
## feeds a planner link to the dialog, waits for the import and prints the status and the resulting build.
## Run: Godot_console.exe --headless --path client res://tests/letools_live.tscn

const LINK: String = "https://www.lastepochtools.com/planner/A83KxJq5"
const TIMEOUT: float = 60.0

var _done: bool = false


func _ready() -> void:
	# a script error stops this coroutine; never hang the headless run
	get_tree().create_timer(TIMEOUT + 15.0).timeout.connect(func() -> void:
		print("LETOOLS LIVE: TIMEOUT")
		get_tree().quit(1))
	var dialog: Window = load("res://scenes/import/letools_import_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.imported.connect(func() -> void: _done = true)
	await get_tree().process_frame

	var status: Label = dialog.get_node("%StatusLabel")
	var button: Button = dialog.get_node("%LoadButton")
	dialog.get_node("%LinkEdit").text = LINK
	button.pressed.emit()

	var waited: float = 0.0
	while not _done and waited < TIMEOUT:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		# an error leaves the button enabled again without `imported`
		if not button.disabled and not _done:
			break
	print("--- status after %.2f s" % waited)
	print(status.text)
	print("--- build")
	print("class=%d mastery=%d level=%d passives=%d" % [Build.class_id, Build.mastery, Build.level, Build.spent_points()])
	var abilities: Array = []
	for skill: Dictionary in Build.skills:
		abilities.append(skill["ability"])
	print("skills=%s items=%d blessings=%d" % [abilities, Build.items.size(), Build.blessings.size()])
	var ok: bool = _done and Build.class_id == 3 and Build.mastery == 2 and Build.level == 58 and Build.spent_points() == 71
	print("LETOOLS LIVE: %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
