class_name LEToolsImportDialog extends Window

## Dialog "Import a build" with two source tabs. "Maxroll account" is MaxrollImportPanel (its own scene and script);
## "Last Epoch Tools": link -> planner page -> data hash -> planner_data JSON -> LEToolsImport -> Build.
## A pasted raw JSON (starting with "{") is imported without network access. All nodes are defined in the scene.

signal imported

enum Stage { IDLE, PAGE, DATA }

const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")

const WARNINGS_SHOWN: int = 30
const MAX_RETRIES: int = 3
const RETRY_DELAY: float = 3.0  # keep in sync with RetryTimer.wait_time in the scene

var _stage: Stage = Stage.IDLE
var _planner_url: String = ""
var _request_url: String = ""
var _request_headers: PackedStringArray = []
var _retries: int = 0


func _ready() -> void:
	close_requested.connect(hide)
	%SourceTabs.set_tab_title(0, tr("Maxroll account"))
	%SourceTabs.set_tab_title(1, tr("Last Epoch Tools link"))
	# The browser build cannot read lastepochtools.com: its CORS allows only its own origin.
	%SourceTabs.set_tab_hidden(1, OS.has_feature("web"))
	%MaxrollPanel.imported.connect(imported.emit)
	about_to_popup.connect(_on_about_to_popup)
	%LoadButton.pressed.connect(_on_load_pressed)
	%CloseButton.pressed.connect(hide)
	%OpenSiteButton.pressed.connect(func() -> void: OS.shell_open(LEToolsImportScript.PLANNER_URL))
	%LinkEdit.text_submitted.connect(_on_link_submitted)
	%Http.request_completed.connect(_on_request_completed)
	%RetryTimer.timeout.connect(_on_retry_timeout)


func _on_about_to_popup() -> void:
	if %SourceTabs.current_tab == 0:
		%MaxrollPanel.get_node("%AccountEdit").grab_focus.call_deferred()
	else:
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
		_status(tr("Invalid link. Expected https://www.lastepochtools.com/planner/<code>."))
		return
	_status(tr("Loading the planner page…"))
	_start(Stage.PAGE, _planner_url, ["Accept: text/html,application/xhtml+xml"])


func _start(stage: Stage, url: String, accept: Array[String]) -> void:
	var headers: PackedStringArray = ["Referer: " + _planner_url]
	headers.append_array(accept)
	_request_url = url
	_request_headers = headers
	_retries = 0
	_send(stage)


func _send(stage: Stage) -> void:
	var err: int = %Http.request(_request_url, _request_headers)
	if err != OK:
		_fail(tr("Could not send the request (error code %d).") % err)
		return
	_stage = stage
	%LoadButton.disabled = true


func _on_retry_timeout() -> void:
	_status(tr("Retrying the request (attempt %d of %d)…") % [_retries, MAX_RETRIES])
	_send(_stage)


func _finish() -> void:
	_stage = Stage.IDLE
	%LoadButton.disabled = false


func _fail(message: String) -> void:
	_finish()
	_status(message)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var stage: Stage = _stage
	if result == HTTPRequest.RESULT_TIMEOUT and _retries < MAX_RETRIES:
		_retries += 1
		_status(tr("The site did not answer in time. Retrying in %d s (attempt %d of %d)…") % [int(RETRY_DELAY), _retries, MAX_RETRIES])
		%RetryTimer.start()
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(tr("Network error (code %d). Check your internet connection.") % result)
		return
	if code == 404:
		_fail(tr("Planner not found (HTTP 404). Check the link."))
		return
	if code != 200:
		_fail(tr("The site answered with HTTP error %d.") % code)
		return
	var text: String = body.get_string_from_utf8()
	if stage == Stage.PAGE:
		var data_hash: String = LEToolsImportScript.extract_data_hash(text)
		if data_hash == "":
			_fail(tr("Build data id not found on the page: the site format may have changed. Paste the planner_data JSON manually."))
			return
		_status(tr("Loading build data…"))
		_finish()
		_start(Stage.DATA, LEToolsImportScript.DATA_URL + data_hash, ["Accept: application/json"])
	elif stage == Stage.DATA:
		_finish()
		_import_json(text)


func _import_json(text: String) -> void:
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		_status(tr("The response is not valid JSON."))
		return
	var doc: Dictionary = LEToolsImportScript.to_build(parsed)
	var warnings: Array = doc["warnings"]
	if int(doc["class_id"]) < 0:
		_status(tr("Could not import the build.\n%s") % _warning_text(warnings))
		return
	LEToolsImportScript.apply(Build, doc)

	var class_data: Dictionary = GameData.get_class_data(int(doc["class_id"]))
	var mastery: int = int(doc["mastery"])
	var mastery_name: String = tr("no mastery") if mastery == 0 else str(class_data["masteries"][mastery].get("name", ""))
	var lines: PackedStringArray = [tr("Imported: %s, %s, level %d") % [class_data.get("className", ""), mastery_name, int(doc["level"])]]
	lines.append(tr("Passives: %d points, items: %d, blessings: %d.") % [_sum(doc["passives"]), (doc["items"] as Dictionary).size(), (doc["blessings"] as Dictionary).size()])
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
