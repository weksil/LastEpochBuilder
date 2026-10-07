class_name LootFilterDialog extends Window
## Dialog "Loot filter": a Last Epoch loot filter from the build's items and idols (LootFilter, docs/UI.md "Loot filter").
## Unchecked rules and entries are kept by rule key while the options change. All nodes are defined in the scene.

var _rules: Array = []
var _off_rules: Dictionary = {}
var _off_entries: Dictionary = {}
var _filling: bool = false


func _ready() -> void:
	close_requested.connect(hide)
	about_to_popup.connect(_on_about_to_popup)
	%CloseButton.pressed.connect(hide)
	%CopyButton.pressed.connect(_on_copy_pressed)
	%SaveGameButton.pressed.connect(_on_save_game_pressed)
	%SaveFileButton.pressed.connect(_on_save_file_pressed)
	%ReplaceConfirm.confirmed.connect(_write_game_file)
	%SaveFileDialog.file_selected.connect(_write_file)
	%RuleTree.item_edited.connect(_on_tree_edited)

	for check: CheckBox in [%StashCheck, %ExactBaseCheck, %ExaltedCheck, %LegendaryCheck,
			%UniquesCheck, %IdolOneCheck, %BasesCheck, %HideCheck, %HideExaltedCheck]:
		check.toggled.connect(func(_on: bool) -> void: _refresh())

	%MinAffixesSpin.value_changed.connect(func(_v: float) -> void: _refresh())
	%ExaltedTierSpin.value_changed.connect(func(_v: float) -> void: _refresh())

	%RuleTree.set_column_expand(0, true)
	%RuleTree.set_column_expand(1, true)
	%RuleTree.set_column_expand_ratio(0, 3)
	%RuleTree.set_column_expand_ratio(1, 2)

	var web: bool = OS.has_feature("web")
	if web:
		%SaveGameButton.visible = false
		%SaveFileButton.text = tr("Download .xml")


func _on_about_to_popup() -> void:
	if %NameEdit.text.strip_edges() == "":
		%NameEdit.text = _default_name()
	var web: bool = OS.has_feature("web")
	%SaveGameButton.visible = not web and LootFilter.game_filters_dir() != ""
	_refresh()
	_status("")


func _default_name() -> String:
	var class_data: Dictionary = GameData.get_class_data(Build.class_id)
	var masteries: Array = class_data.get("masteries", [])
	var name_str: String = ""
	if 0 < Build.mastery and Build.mastery < masteries.size():
		name_str = str(masteries[Build.mastery].get("name", ""))
	if name_str == "":
		name_str = str(class_data.get("className", ""))
	if name_str == "":
		return tr("Build filter")
	return tr("%s build") % name_str


func _options() -> Dictionary:
	var opts: Dictionary = {
		"stash": %StashCheck.button_pressed,
		"exact_base": %ExactBaseCheck.button_pressed,
		"min_affixes": int(%MinAffixesSpin.value),
		"exalted": %ExaltedCheck.button_pressed,
		"exalted_tier": int(%ExaltedTierSpin.value),
		"legendary": %LegendaryCheck.button_pressed,
		"uniques": %UniquesCheck.button_pressed,
		"idol_one": %IdolOneCheck.button_pressed,
		"bases": %BasesCheck.button_pressed,
		"hide_others": %HideCheck.button_pressed,
		"hide_exalted": %HideExaltedCheck.button_pressed,
	}
	%HideExaltedCheck.disabled = not %HideCheck.button_pressed
	%ExaltedTierSpin.editable = %ExaltedCheck.button_pressed
	return opts


func _refresh() -> void:
	var result: Dictionary = LootFilter.plan(Build.items, Build.stash, _options())
	_rules = result["rules"]
	_fill_tree()
	var notes: Array = result["notes"]
	%NotesLabel.visible = not notes.is_empty()
	%NotesLabel.text = "\n".join(PackedStringArray(notes))
	if _rules.is_empty():
		_status(tr("The build has no items or idols to filter."))


func _fill_tree() -> void:
	_filling = true
	var tree: Tree = %RuleTree
	tree.clear()
	var root: TreeItem = tree.create_item()

	for spec: Dictionary in _rules:
		var row: TreeItem = tree.create_item(root)
		row.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		row.set_editable(0, true)
		row.set_checked(0, not _off_rules.has(spec["key"]))
		row.set_text(0, ("%s: " % (tr("Hide") if spec["outcome"] == "HIDE" else tr("Show"))) + str(spec["title"]))
		row.set_text(1, LootFilter.describe(spec))
		row.set_tooltip_text(1, LootFilter.describe(spec))
		row.set_metadata(0, {"rule": spec["key"], "id": -1})

		var child_count: int = 0
		for affix_id: int in spec.get("affixes", []):
			child_count += 1
			var child: TreeItem = tree.create_item(row)
			child.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			child.set_editable(0, true)
			child.set_checked(0, not (_off_entries.get(spec["key"], {}) as Dictionary).has(affix_id))
			child.set_text(0, LootFilter.affix_name(affix_id))
			child.set_metadata(0, {"rule": spec["key"], "id": affix_id})

		for unique_id: int in spec.get("uniques", []):
			child_count += 1
			var child: TreeItem = tree.create_item(row)
			child.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			child.set_editable(0, true)
			child.set_checked(0, not (_off_entries.get(spec["key"], {}) as Dictionary).has(unique_id))
			child.set_text(0, LootFilter.unique_name(unique_id))
			child.set_metadata(0, {"rule": spec["key"], "id": unique_id})

		if child_count > 8:
			row.collapsed = true

	_filling = false


func _on_tree_edited() -> void:
	if _filling:
		return
	var item: TreeItem = %RuleTree.get_edited()
	if item != null:
		_apply_check(item)


## Stores the check state of a rule row or an entry row of the rule tree.
func _apply_check(item: TreeItem) -> void:
	var meta: Dictionary = item.get_metadata(0)
	var key: String = str(meta["rule"])
	var id: int = int(meta["id"])
	var on: bool = item.is_checked(0)

	if id < 0:
		if on:
			_off_rules.erase(key)
		else:
			_off_rules[key] = true
	else:
		var off: Dictionary = _off_entries.get(key, {})
		if on:
			off.erase(id)
		else:
			off[id] = true
		_off_entries[key] = off


func _xml() -> String:
	return LootFilter.to_xml(_filter_name(), tr("Made with Last Epoch Builder for this build."),
		LootFilter.apply_choices(_rules, _off_rules, _off_entries))


func _filter_name() -> String:
	var typed: String = %NameEdit.text.strip_edges()
	return typed if typed != "" else _default_name()


func _on_copy_pressed() -> void:
	var xml: String = _xml()
	DisplayServer.clipboard_set(xml)
	_status(tr("The filter XML is copied to the clipboard (%d rules).") % _rule_count())


func _rule_count() -> int:
	return LootFilter.apply_choices(_rules, _off_rules, _off_entries).size()


func _on_save_game_pressed() -> void:
	var dir: String = LootFilter.game_filters_dir()
	if dir == "":
		_status(tr("The game's filter folder was not found."))
		return
	var path: String = dir.path_join(LootFilter.file_name(_filter_name()))
	if FileAccess.file_exists(path):
		%ReplaceConfirm.dialog_text = tr("The game already has the filter \"%s\". Replace it?") % _filter_name()
		%ReplaceConfirm.popup_centered()
		return
	_write_game_file()


func _write_game_file() -> void:
	var dir: String = LootFilter.game_filters_dir()
	if dir == "":
		_status(tr("The game's filter folder was not found."))
		return
	_write_file(dir.path_join(LootFilter.file_name(_filter_name())))


func _on_save_file_pressed() -> void:
	var web: bool = OS.has_feature("web")
	if web:
		JavaScriptBridge.download_buffer(_xml().to_utf8_buffer(), LootFilter.file_name(_filter_name()), "application/xml")
		_status(tr("The filter is downloaded as %s.") % LootFilter.file_name(_filter_name()))
		return
	%SaveFileDialog.current_file = LootFilter.file_name(_filter_name())
	%SaveFileDialog.popup_centered()


func _write_file(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status(tr("Could not write %s.") % path)
		return
	file.store_string(_xml())
	file.close()
	_status(tr("The filter is saved to %s (%d rules). Pick it in the game's loot filter panel.") % [path, _rule_count()])


func _status(text: String) -> void:
	%StatusLabel.text = text
