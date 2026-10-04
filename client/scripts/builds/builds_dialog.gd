class_name BuildsDialog extends Window

## Dialog "Builds": named saves in user://builds and the build code (copy / load). All nodes are defined in the scene.

## Emitted after a build was applied to the Build autoload (main.gd syncs the top bar).
signal loaded

const WARNINGS_SHOWN: int = 30


func _ready() -> void:
	close_requested.connect(hide)
	about_to_popup.connect(_on_about_to_popup)
	%CloseButton.pressed.connect(hide)
	%SaveButton.pressed.connect(_on_save_pressed)
	%NameEdit.text_submitted.connect(func(_text: String) -> void: _on_save_pressed())
	%LoadButton.pressed.connect(_load_selected)
	%DeleteButton.pressed.connect(_on_delete_pressed)
	%OpenFolderButton.pressed.connect(_on_open_folder_pressed)
	%CopyCodeButton.pressed.connect(_on_copy_code_pressed)
	%LoadCodeButton.pressed.connect(_on_load_code_pressed)
	%BuildList.item_selected.connect(_on_item_selected)
	%BuildList.item_activated.connect(func(_index: int) -> void: _load_selected())
	%DeleteConfirm.confirmed.connect(_on_delete_confirmed)


func _on_about_to_popup() -> void:
	_refresh()
	_status(tr("No saved builds yet.") if %BuildList.item_count == 0 else "")


## Rebuilds the list of saves; selects the entry whose file is `select_path`.
func _refresh(select_path: String = "") -> void:
	var list: ItemList = %BuildList
	list.clear()
	var offset: int = int((Time.get_time_zone_from_system()["bias"] as int) * 60)
	for save: Dictionary in BuildCodec.list_saves():
		var class_data: Dictionary = GameData.get_class_data(int(save["class_id"]))
		var mastery: int = int(save["mastery"])
		var masteries: Array = class_data.get("masteries", [])
		var mastery_name: String = tr("no mastery") if mastery <= 0 or mastery >= masteries.size() else str(masteries[mastery].get("name", ""))
		var when: String = Time.get_datetime_string_from_unix_time(int(save["saved"]) + offset, true)
		var index: int = list.add_item(tr("%s — %s, %s, level %d · %s") % [save["name"], class_data.get("className", "?"), mastery_name, int(save["level"]), when])
		list.set_item_metadata(index, save)
		if save["path"] == select_path:
			list.select(index)
	_update_buttons()


func _selected() -> Dictionary:
	var picked: PackedInt32Array = %BuildList.get_selected_items()
	return %BuildList.get_item_metadata(picked[0]) if not picked.is_empty() else {}


func _update_buttons() -> void:
	var has_selection: bool = not _selected().is_empty()
	%LoadButton.disabled = not has_selection
	%DeleteButton.disabled = not has_selection


func _on_item_selected(_index: int) -> void:
	_update_buttons()
	%NameEdit.text = str(_selected().get("name", ""))


func _on_save_pressed() -> void:
	var build_name: String = %NameEdit.text.strip_edges()
	if build_name == "":
		_status(tr("Enter a build name."))
		return
	var replaced: bool = FileAccess.file_exists(BuildCodec.SAVE_DIR.path_join(BuildCodec.file_name(build_name)))
	var path: String = BuildCodec.save_build(build_name, Build)
	if path == "":
		_status(tr("Could not save the build."))
		return
	_refresh(path)
	_status(tr("Build \"%s\" saved (the previous version was replaced).") % build_name if replaced else tr("Build \"%s\" saved.") % build_name)


func _load_selected() -> void:
	var save: Dictionary = _selected()
	if save.is_empty():
		return
	var doc: Dictionary = BuildCodec.load_save(str(save["path"]))
	if not doc["ok"]:
		_status(_warning_text(doc["warnings"]))
		return
	%NameEdit.text = str(doc["name"])
	_apply(doc, tr("Build \"%s\" loaded.") % doc["name"])


func _apply(doc: Dictionary, message: String) -> void:
	BuildCodec.apply(Build, doc)
	var lines: PackedStringArray = [message]
	if not (doc["warnings"] as Array).is_empty():
		lines.append(_warning_text(doc["warnings"]))
	_status("\n".join(lines))
	loaded.emit()


func _on_delete_pressed() -> void:
	var save: Dictionary = _selected()
	if save.is_empty():
		return
	%DeleteConfirm.dialog_text = tr("Delete the build \"%s\"? The file is removed for good.") % save["name"]
	%DeleteConfirm.popup_centered()


func _on_delete_confirmed() -> void:
	var save: Dictionary = _selected()
	if save.is_empty():
		return
	BuildCodec.delete_save(str(save["path"]))
	_refresh()
	_status(tr("Build \"%s\" deleted.") % save["name"])


func _on_open_folder_pressed() -> void:
	DirAccess.make_dir_recursive_absolute(BuildCodec.SAVE_DIR)
	OS.shell_open(ProjectSettings.globalize_path(BuildCodec.SAVE_DIR))


func _on_copy_code_pressed() -> void:
	var code: String = BuildCodec.encode(Build)
	%CodeEdit.text = code
	DisplayServer.clipboard_set(code)
	_status(tr("The build code is copied to the clipboard (%d characters).") % code.length())


func _on_load_code_pressed() -> void:
	var text: String = %CodeEdit.text
	if text.strip_edges() == "":
		text = DisplayServer.clipboard_get()
		%CodeEdit.text = text
	if text.strip_edges() == "":
		_status(tr("Paste a build code first."))
		return
	var doc: Dictionary = BuildCodec.decode(text)
	if not doc["ok"]:
		_status(_warning_text(doc["warnings"]))
		return
	_apply(doc, tr("Build loaded from the code."))


func _warning_text(warnings: Array) -> String:
	if warnings.is_empty():
		return ""
	var lines: PackedStringArray = [tr("Warnings (%d):") % warnings.size()]
	for i in range(mini(warnings.size(), WARNINGS_SHOWN)):
		lines.append("- " + str(warnings[i]))
	if warnings.size() > WARNINGS_SHOWN:
		lines.append(tr("… and %d more.") % (warnings.size() - WARNINGS_SHOWN))
	return "\n".join(lines)


func _status(text: String) -> void:
	%StatusLabel.text = text
