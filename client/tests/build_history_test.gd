extends Node

## Undo / redo of build edits (BuildHistory autoload): steps, redo cleared by a new edit, merged bursts, the shown skill
## left out, class changes, the Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y keys and the focused-field rule.
## Run: Godot_console.exe --headless --path client res://tests/build_history_test.tscn

var _failed: int = 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("BUILD HISTORY TEST TIMEOUT")
		get_tree().quit(1))
	await _run()
	print("BUILD HISTORY TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		print("FAIL: " + message)


## Snapshots are taken at the end of the frame.
func _frame() -> void:
	await get_tree().process_frame


func _key(keycode: Key, shift: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.ctrl_pressed = true
	event.shift_pressed = shift
	event.pressed = true
	get_viewport().push_input(event)
	await _frame()


func _run() -> void:
	var classes: Array = GameData.classes
	var first: int = int(classes[0]["classID"])
	var second: int = int(classes[1]["classID"])
	BuildHistory.merge_msec = 0
	Build.set_class(first)
	await _frame()
	BuildHistory.clear()
	Build.set_level(100)
	await _frame()
	_check(not BuildHistory.can_undo(), "no steps after clear")

	Build.set_level(50)
	await _frame()
	Build.set_level(60)
	await _frame()
	Build.set_enemy("armour", 777)
	await _frame()
	BuildHistory.undo()
	_check(int(Build.enemy.get("armour", 0)) != 777 and Build.level == 60, "undo reverts the enemy armour only")
	BuildHistory.undo()
	_check(Build.level == 50, "second undo -> level 50, got %d" % Build.level)
	BuildHistory.redo()
	_check(Build.level == 60, "redo -> level 60, got %d" % Build.level)
	BuildHistory.redo()
	_check(int(Build.enemy.get("armour", 0)) == 777, "second redo -> armour 777")
	_check(not BuildHistory.can_redo(), "nothing left to redo")

	BuildHistory.undo()
	await _frame()
	Build.set_level(70)
	await _frame()
	_check(not BuildHistory.can_redo(), "a new edit clears redo")
	BuildHistory.undo()
	_check(Build.level == 60, "undo of the new edit -> level 60, got %d" % Build.level)
	BuildHistory.redo()

	var steps: int = BuildHistory._undo.size()
	Build.selected_skill = 3
	await _frame()
	_check(BuildHistory._undo.size() == steps, "switching the shown skill is not a step")
	BuildHistory.undo()
	_check(Build.selected_skill == 3, "undo keeps the shown skill")
	BuildHistory.redo()

	BuildHistory.merge_msec = 100000
	Build.set_level(80)
	await _frame()
	Build.set_level(81)
	await _frame()
	Build.set_level(82)
	await _frame()
	BuildHistory.undo()
	_check(Build.level == 70, "a burst of changes is one step, got level %d" % Build.level)
	BuildHistory.redo()
	_check(Build.level == 82, "redo of the burst -> 82, got %d" % Build.level)
	BuildHistory.merge_msec = 0

	Build.set_class(second)
	await _frame()
	_check(Build.class_id == second, "class changed")
	var restored: Array[bool] = [false]
	BuildHistory.restored.connect(func() -> void: restored[0] = true, CONNECT_ONE_SHOT)
	BuildHistory.undo()
	_check(Build.class_id == first and Build.level == 82, "undo of a class change restores the class and level")
	_check(restored[0], "restored is emitted")

	await _key(KEY_Z, true)
	_check(Build.class_id == second, "Ctrl+Shift+Z redoes")
	await _key(KEY_Z, false)
	_check(Build.class_id == first, "Ctrl+Z undoes")
	await _key(KEY_Y, false)
	_check(Build.class_id == second, "Ctrl+Y redoes")

	# a spin box keeps the focus after its arrows are clicked: Ctrl+Z still undoes the build
	var spin := SpinBox.new()
	add_child(spin)
	spin.get_line_edit().grab_focus()
	await _key(KEY_Z, false)
	_check(Build.class_id == first, "Ctrl+Z with a spin box focused undoes the build")
	# a text field keeps its own text undo
	var line := LineEdit.new()
	add_child(line)
	line.grab_focus()
	await _key(KEY_Z, true)
	_check(Build.class_id == first, "Ctrl+Shift+Z with a text field focused is left to the field")
	line.release_focus()
	await _key(KEY_Z, true)
	_check(Build.class_id == second, "Ctrl+Shift+Z redoes again once the field lost the focus")
