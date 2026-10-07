extends Node

## Undo / redo of build edits (Ctrl+Z, Ctrl+Shift+Z or Ctrl+Y). Every edit of the Build autoload is stored as a whole
## BuildCodec.to_dict snapshot, so all tabs are covered without per-setter commands. Changes that come faster than
## `merge_msec` after the previous one (a dragged slider, a spin box held down) merge into one step.
## A focused text field keeps its own Ctrl+Z.

## Emitted after a snapshot was applied to Build (main.gd syncs the top bar, as after an import).
signal restored

const LIMIT: int = 200
const LONG_AGO: int = -1000000000

## Changes closer than this merge into one step (tests set 0).
var merge_msec: int = 300

var _undo: Array[String] = []
var _redo: Array[String] = []
## JSON of the build as it is now ("" until the first snapshot).
var _current: String = ""
var _last_change_msec: int = LONG_AGO
var _capture_queued: bool = false


func _ready() -> void:
	Build.changed.connect(_queue_capture)
	Build.stash_changed.connect(_queue_capture)


## Read before the GUI: a spin box keeps the focus after its arrows are clicked and would take Ctrl+Z for its text.
func _input(event: InputEvent) -> void:
	var is_redo: bool = event.is_action_pressed("ui_redo", false, true)  # built-in: Ctrl+Shift+Z, Ctrl+Y
	if not is_redo and not event.is_action_pressed("ui_undo", false, true):
		return
	if _text_field_focused():
		return
	if is_redo:
		redo()
	else:
		undo()
	get_viewport().set_input_as_handled()


## Text fields (names, search, the build code) keep their own text undo; the line edit of a spin box does not.
func _text_field_focused() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus is TextEdit or (focus is LineEdit and not focus.get_parent() is SpinBox)


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	_flush()
	if _undo.is_empty():
		return
	_redo.append(_current)
	_restore(_undo.pop_back())


func redo() -> void:
	_flush()
	if _redo.is_empty():
		return
	_undo.append(_current)
	_restore(_redo.pop_back())


## Forgets every step; the next change starts a new history.
func clear() -> void:
	_undo.clear()
	_redo.clear()
	_current = ""


## Several `changed` emits of one action (set_class, BuildCodec.apply) land in one frame: snapshot once, at its end.
func _queue_capture() -> void:
	if _capture_queued:
		return
	_capture_queued = true
	_capture.call_deferred()


func _flush() -> void:
	if _capture_queued:
		_capture()


func _capture() -> void:
	_capture_queued = false
	var snapshot: String = _snapshot()
	if snapshot == _current:
		return  # only the shown skill changed, or an undo / redo re-emitted `changed`
	var now: int = Time.get_ticks_msec()
	if _current != "" and now - _last_change_msec >= merge_msec:
		_undo.append(_current)
		if _undo.size() > LIMIT:
			_undo.pop_front()
	if _current != "":
		_redo.clear()
	_current = snapshot
	_last_change_msec = now


## The shown skill slot is a view choice, not an edit: it is left out of the snapshot and kept on restore.
func _snapshot() -> String:
	var data: Dictionary = BuildCodec.to_dict(Build)
	data.erase("selected_skill")
	return JSON.stringify(data)


func _restore(snapshot: String) -> void:
	var data: Dictionary = JSON.parse_string(snapshot)
	data["selected_skill"] = Build.selected_skill
	var doc: Dictionary = BuildCodec.from_dict(data)
	if not doc["ok"]:
		push_error("BuildHistory: cannot restore a snapshot: %s" % [doc["warnings"]])
		return
	BuildCodec.apply(Build, doc)
	_capture_queued = false
	_current = _snapshot()  # the round trip may normalize values; compare later edits with what Build really holds
	_last_change_msec = LONG_AGO
	restored.emit()
