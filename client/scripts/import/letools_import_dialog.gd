class_name LEToolsImportDialog extends Window

## Dialog «Импорт из Last Epoch Tools»: link -> planner page -> data hash -> planner_data JSON -> LEToolsImport -> Build.
## A pasted raw JSON (starting with "{") is imported without network access. All nodes are defined in the scene.

signal imported

enum Stage { IDLE, PAGE, DATA }

const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")

const WARNINGS_SHOWN: int = 30

var _stage: Stage = Stage.IDLE
var _planner_url: String = ""


func _ready() -> void:
	close_requested.connect(hide)
	about_to_popup.connect(_on_about_to_popup)
	%LoadButton.pressed.connect(_on_load_pressed)
	%CloseButton.pressed.connect(hide)
	%LinkEdit.text_submitted.connect(_on_link_submitted)
	%Http.request_completed.connect(_on_request_completed)


func _on_about_to_popup() -> void:
	%LinkEdit.grab_focus.call_deferred()


func _on_link_submitted(_text: String) -> void:
	_on_load_pressed()


func _on_load_pressed() -> void:
	if _stage != Stage.IDLE:
		return
	var text: String = %LinkEdit.text.strip_edges()
	if text.begins_with("{"):
		_import_json(text)
		return
	_planner_url = LEToolsImportScript.planner_url(text)
	if _planner_url == "":
		_status("Некорректная ссылка. Ожидается https://www.lastepochtools.com/planner/<код>.")
		return
	_status("Загрузка страницы планировщика…")
	_start(Stage.PAGE, _planner_url, ["Accept: text/html,application/xhtml+xml"])


func _start(stage: Stage, url: String, accept: Array[String]) -> void:
	var headers: PackedStringArray = ["Referer: " + _planner_url]
	headers.append_array(accept)
	var err: int = %Http.request(url, headers)
	if err != OK:
		_fail("Не удалось отправить запрос (код ошибки %d)." % err)
		return
	_stage = stage
	%LoadButton.disabled = true


func _finish() -> void:
	_stage = Stage.IDLE
	%LoadButton.disabled = false


func _fail(message: String) -> void:
	_finish()
	_status(message)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var stage: Stage = _stage
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("Ошибка сети (код %d). Проверьте подключение к интернету." % result)
		return
	if code == 404:
		_fail("Планировщик не найден (HTTP 404). Проверьте ссылку.")
		return
	if code != 200:
		_fail("Сайт ответил ошибкой HTTP %d." % code)
		return
	var text: String = body.get_string_from_utf8()
	if stage == Stage.PAGE:
		var data_hash: String = LEToolsImportScript.extract_data_hash(text)
		if data_hash == "":
			_fail("Не найден идентификатор данных билда на странице: формат сайта мог измениться. Вставьте JSON planner_data вручную.")
			return
		_status("Загрузка данных билда…")
		_finish()
		_start(Stage.DATA, LEToolsImportScript.DATA_URL + data_hash, ["Accept: application/json"])
	elif stage == Stage.DATA:
		_finish()
		_import_json(text)


func _import_json(text: String) -> void:
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		_status("Ответ не является корректным JSON.")
		return
	var doc: Dictionary = LEToolsImportScript.to_build(parsed)
	var warnings: Array = doc["warnings"]
	if int(doc["class_id"]) < 0:
		_status("Не удалось импортировать билд.\n%s" % _warning_text(warnings))
		return
	LEToolsImportScript.apply(Build, doc)

	var class_data: Dictionary = GameData.get_class_data(int(doc["class_id"]))
	var mastery: int = int(doc["mastery"])
	var mastery_name: String = "без мастерства" if mastery == 0 else str(class_data["masteries"][mastery].get("name", ""))
	var lines: PackedStringArray = ["Импортировано: %s, %s, уровень %d" % [class_data.get("className", ""), mastery_name, int(doc["level"])]]
	lines.append("Пассивки: %d очков, предметов: %d, благословений: %d." % [_sum(doc["passives"]), (doc["items"] as Dictionary).size(), (doc["blessings"] as Dictionary).size()])
	if not warnings.is_empty():
		lines.append(_warning_text(warnings))
	_status("\n".join(lines))
	imported.emit()


func _warning_text(warnings: Array) -> String:
	if warnings.is_empty():
		return ""
	var lines: PackedStringArray = ["Предупреждения (%d):" % warnings.size()]
	for i in range(mini(warnings.size(), WARNINGS_SHOWN)):
		lines.append("- " + str(warnings[i]))
	if warnings.size() > WARNINGS_SHOWN:
		lines.append("… и ещё %d." % (warnings.size() - WARNINGS_SHOWN))
	return "\n".join(lines)


func _sum(points: Dictionary) -> int:
	var total: int = 0
	for value: Variant in points.values():
		total += int(value)
	return total


func _status(text: String) -> void:
	%StatusLabel.text = text
