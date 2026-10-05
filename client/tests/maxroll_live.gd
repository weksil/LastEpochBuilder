extends Node

## Live check of the Maxroll account import (needs network, NOT part of the regular suite): enters an account name,
## waits for the character list, picks a character, imports it and prints the status and the resulting build.
## Run: Godot_console.exe --headless --path client res://tests/maxroll_live.tscn

const ACCOUNT: String = "LeonardDaVinci"
const CHARACTER: String = "palading"
const TIMEOUT: float = 60.0

var _done: bool = false


func _ready() -> void:
	# a script error stops this coroutine; never hang the headless run
	get_tree().create_timer(TIMEOUT * 2 + 15.0).timeout.connect(func() -> void:
		print("MAXROLL LIVE: TIMEOUT")
		get_tree().quit(1))
	var saved_account: String = Settings.maxroll_account
	var dialog: Window = load("res://scenes/import/letools_import_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.imported.connect(func() -> void: _done = true)
	await get_tree().process_frame

	var panel: Node = dialog.get_node("%MaxrollPanel")
	var status: Label = panel.get_node("%StatusLabel")
	var find: Button = panel.get_node("%FindButton")
	var list: ItemList = panel.get_node("%CharacterList")
	panel.get_node("%AccountEdit").text = ACCOUNT
	find.pressed.emit()
	await _wait(func() -> bool: return not find.disabled)
	print("--- list (%d)" % list.item_count)
	print(status.text)
	var index: int = -1
	for i in range(list.item_count):
		if str(list.get_item_metadata(i)["name"]) == CHARACTER:
			index = i
	if index >= 0:
		list.select(index)
		list.item_activated.emit(index)
		await _wait(func() -> bool: return _done or not find.disabled)
	print("--- status")
	print(status.text)
	print("--- build")
	print("class=%d mastery=%d level=%d passives=%d" % [Build.class_id, Build.mastery, Build.level, Build.spent_points()])
	var abilities: Array = []
	for skill: Dictionary in Build.skills:
		abilities.append(skill["ability"])
	print("skills=%s items=%d blessings=%d" % [abilities, Build.items.size(), Build.blessings.size()])
	Settings.set_maxroll_account(saved_account)
	var ok: bool = _done and Build.class_id == 2 and Build.mastery == 1 and Build.level == 100 and Build.blessings.size() == 10
	print("MAXROLL LIVE: %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _wait(finished: Callable) -> void:
	var waited: float = 0.0
	await get_tree().create_timer(0.25).timeout
	while not finished.call() and waited < TIMEOUT:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
