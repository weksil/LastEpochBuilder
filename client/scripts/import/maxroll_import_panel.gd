class_name MaxrollImportPanel extends VBoxContainer

## Import tab "Maxroll account": account name -> character list -> pick a character -> character JSON -> MaxrollImport -> Build.

signal imported

enum Stage { IDLE, LIST, CHARACTER }

const MaxrollImportScript: GDScript = preload("res://scripts/engine/maxroll_import.gd")
const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")

const WARNINGS_SHOWN: int = 30

var _stage: Stage = Stage.IDLE
var _account: String = ""


func _ready() -> void:
	%AccountEdit.text = Settings.maxroll_account
	%FindButton.pressed.connect(_find)
	%AccountEdit.text_submitted.connect(func(_text: String) -> void: _find())
	%CharacterList.item_selected.connect(_on_character_selected)
	%CharacterList.item_activated.connect(_on_character_activated)
	%ImportButton.pressed.connect(_import_selected)
	%Http.request_completed.connect(_on_request_completed)


func _on_character_selected(_index: int) -> void:
	%ImportButton.disabled = false


func _on_character_activated(_index: int) -> void:
	_import_selected()


func _find() -> void:
	if _stage != Stage.IDLE:
		return
	var account: String = %AccountEdit.text.strip_edges()
	var url: String = MaxrollImportScript.list_url(account)
	if url == "":
		_status(tr("Enter the account name."))
		return
	%CharacterList.clear()
	%ImportButton.disabled = true
	Settings.set_maxroll_account(account)
	_account = account
	_status(tr("Loading the character list…"))
	_start(Stage.LIST, url)


func _start(stage: Stage, url: String) -> void:
	var err: int = %Http.request(url, ["Accept: application/json"])
	if err != OK:
		_fail(tr("Could not send the request (error code %d).") % err)
		return
	_stage = stage
	%FindButton.disabled = true
	%ImportButton.disabled = true


func _finish() -> void:
	_stage = Stage.IDLE
	%FindButton.disabled = false
	%ImportButton.disabled = %CharacterList.get_selected_items().is_empty()


func _fail(message: String) -> void:
	_finish()
	_status(message)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var stage: Stage = _stage
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(tr("Network error (code %d). Check your internet connection.") % result)
		return
	if stage == Stage.LIST:
		if code != 200:
			_fail(tr("Account not found or its Maxroll profile is not public (HTTP %d).") % code)
			return
		_on_list_loaded(body)
	elif stage == Stage.CHARACTER:
		if code != 200:
			_fail(tr("The character could not be loaded (HTTP %d).") % code)
			return
		_on_character_loaded(body)


func _on_list_loaded(body: PackedByteArray) -> void:
	var text: String = body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail(tr("The response is not valid JSON."))
		return
	var characters: Array = MaxrollImportScript.parse_character_list(json.data)
	if characters.is_empty():
		_fail(tr("The account has no characters."))
		return
	for ch: Dictionary in characters:
		var class_id: int = int(ch.get("class_id", -1))
		var mastery: int = int(ch.get("mastery", 0))
		var level: int = int(ch.get("level", 0))
		var name: String = str(ch.get("name", ""))
		var legacy: bool = bool(ch.get("legacy", false))
		var hardcore: bool = bool(ch.get("hardcore", false))

		var class_data: Dictionary = GameData.get_class_data(class_id)
		var class_mastery_name: String = ""
		if mastery == 0:
			class_mastery_name = class_data.get("className", "")
		else:
			var masteries: Array = class_data.get("masteries", [])
			if mastery > 0 and mastery < masteries.size():
				class_mastery_name = str(masteries[mastery].get("name", ""))

		var item_text: String = tr("%s — %s, level %d") % [name, class_mastery_name, level]
		if legacy:
			item_text += " · " + tr("Legacy")
		if hardcore:
			item_text += " · " + tr("Hardcore")

		var idx: int = %CharacterList.add_item(item_text)
		%CharacterList.set_item_metadata(idx, ch)

	%CharacterList.deselect_all()
	_finish()
	_status(tr("Characters found: %d. Pick one and press Import.") % characters.size())


func _import_selected() -> void:
	if _stage != Stage.IDLE:
		return
	var selected: PackedInt32Array = %CharacterList.get_selected_items()
	if selected.is_empty():
		return
	var idx: int = selected[0]
	var ch: Dictionary = %CharacterList.get_item_metadata(idx)
	var name: String = str(ch.get("name", ""))
	var url: String = MaxrollImportScript.character_url(_account, name)
	_status(tr("Loading character %s…") % name)
	_start(Stage.CHARACTER, url)


func _on_character_loaded(body: PackedByteArray) -> void:
	var text: String = body.get_string_from_utf8()
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		_fail(tr("The response is not valid JSON."))
		return
	var doc: Dictionary = MaxrollImportScript.to_build(parsed)
	var warnings: Array = doc.get("warnings", [])
	if int(doc.get("class_id", -1)) < 0:
		_fail(tr("Could not import the build.\n%s") % _warning_text(warnings))
		return
	_finish()
	LEToolsImportScript.apply(Build, doc)

	var class_id: int = int(doc.get("class_id", 0))
	var class_data: Dictionary = GameData.get_class_data(class_id)
	var mastery: int = int(doc.get("mastery", 0))
	var mastery_name: String = tr("no mastery") if mastery == 0 else str(class_data["masteries"][mastery].get("name", ""))
	var lines: PackedStringArray = [tr("Imported: %s, %s, level %d") % [class_data.get("className", ""), mastery_name, int(doc.get("level", 0))]]
	lines.append(tr("Passives: %d points, items: %d, blessings: %d.") % [_sum(doc.get("passives", {})), (doc.get("items", {}) as Dictionary).size(), (doc.get("blessings", {}) as Dictionary).size()])
	if not warnings.is_empty():
		lines.append(_warning_text(warnings))
	_status("\n".join(lines))
	imported.emit()


func _warning_text(warnings: Array) -> String:
	if warnings.is_empty():
		return ""
	var lines: PackedStringArray = [tr("Warnings (%d):") % warnings.size()]
	for i in range(mini(warnings.size(), WARNINGS_SHOWN)):
		lines.append("- " + str(warnings[i]))
	if warnings.size() > WARNINGS_SHOWN:
		lines.append(tr("… and %d more.") % (warnings.size() - WARNINGS_SHOWN))
	return "\n".join(lines)


func _sum(points: Dictionary) -> int:
	var total: int = 0
	for value: Variant in points.values():
		total += int(value)
	return total


func _status(text: String) -> void:
	%StatusLabel.text = text
