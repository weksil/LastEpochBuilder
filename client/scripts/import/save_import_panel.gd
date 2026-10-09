class_name SaveImportPanel extends VBoxContainer

## Import tab "Save file": the game's offline character file -> SaveImport -> Build. The file comes from a FileDialog
## on desktop; in the browser from a hidden <input type="file"> (opened straight from the button handler, as browsers
## require a user gesture) or from a file dropped onto the page. One file is one character.

signal imported

const SaveImportScript: GDScript = preload("res://scripts/engine/save_import.gd")

const WARNINGS_SHOWN: int = 30

## Page side of the web file picker: a hidden file input and drag-and-drop (active while the panel is visible) read the
## file as text and call window._leSave.cb(name, text, error). Error: "" ok, "size" too big, "read" unreadable.
const WEB_SETUP_JS: String = """
(function () {
	var S = window._leSave;
	if (!S) {
		S = window._leSave = { drop: false, cb: null, max: 0, input: null };
		S.read = function (file) {
			if (!S.cb) { return; }
			if (file.size > S.max) { S.cb(file.name, '', 'size'); return; }
			var reader = new FileReader();
			reader.onload = function () { S.cb(file.name, String(reader.result), ''); };
			reader.onerror = function () { S.cb(file.name, '', 'read'); };
			reader.readAsText(file);
		};
		var input = document.createElement('input');
		input.type = 'file';
		input.style.display = 'none';
		document.body.appendChild(input);
		input.addEventListener('change', function () {
			var file = input.files && input.files[0];
			input.value = '';
			if (file) { S.read(file); }
		});
		S.input = input;
		window.addEventListener('dragover', function (e) { if (S.drop) { e.preventDefault(); } }, true);
		window.addEventListener('drop', function (e) {
			if (!S.drop) { return; }
			e.preventDefault();
			var file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
			if (file) { S.read(file); }
		}, true);
	}
	S.max = %d;
})();
"""

var _parsed: Dictionary = {}
## JavaScriptObject callback of the page; kept referenced, or it is freed and the page calls nothing.
var _web_callback: JavaScriptObject = null


func _ready() -> void:
	%ChooseButton.pressed.connect(_on_choose_pressed)
	%ImportButton.pressed.connect(_on_import_pressed)
	%FileDialog.file_selected.connect(_on_file_selected)
	if OS.has_feature("web"):
		%WebHint.visible = true
		_web_setup()
		visibility_changed.connect(_on_visibility_changed)
		get_window().visibility_changed.connect(_on_visibility_changed)  # the dialog is hidden, this panel does not know


func _on_choose_pressed() -> void:
	if OS.has_feature("web"):
		# the click has to happen inside this handler: the browser allows the file chooser only after a user gesture
		JavaScriptBridge.eval("window._leSave.input.click();")
		return
	var dir: String = SaveImportScript.saves_dir()
	if dir != "":
		%FileDialog.current_dir = dir
	%FileDialog.popup_centered()


func _on_file_selected(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_error(tr("Could not open %s.") % path.get_file())
		return
	if file.get_length() > SaveImportScript.MAX_BYTES:
		_show_error(tr("The file is too big (%d MB): a character save is far smaller.") % ceili(file.get_length() / 1048576.0))
		return
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	_load_bytes(bytes, path.get_file())


## Parses the chosen file; on success the character is shown and the Import button is enabled.
func _load_bytes(bytes: PackedByteArray, file_name: String) -> void:
	%FileLabel.text = file_name
	_parsed = SaveImportScript.parse(bytes)
	if not _parsed["ok"]:
		_show_error(str(_parsed["error"]))
		return
	var summary: Dictionary = _parsed["summary"]
	%SummaryLabel.text = _summary_text(summary)
	%ImportButton.disabled = false
	_status(tr("Press Import to replace the current build with this character."))


func _show_error(message: String) -> void:
	_parsed = {}
	%SummaryLabel.text = ""
	%ImportButton.disabled = true
	_status(message)


func _summary_text(summary: Dictionary) -> String:
	var mastery_name: String = str(summary["mastery_name"])
	if mastery_name == "":
		mastery_name = tr("no mastery")
	return tr("%s — %s, %s, level %d") % [summary["name"], summary["class_name"], mastery_name, int(summary["level"])]


func _on_import_pressed() -> void:
	if _parsed.is_empty() or not _parsed["ok"]:
		return
	SaveImportScript.apply(Build, _parsed)
	var summary: Dictionary = _parsed["summary"]
	var warnings: Array = _parsed["warnings"]
	var lines: PackedStringArray = [tr("Imported: %s, %s, level %d") % [summary["class_name"], summary["mastery_name"] if summary["mastery_name"] != "" else tr("no mastery"), int(summary["level"])]]
	lines.append(tr("Passives: %d points, items: %d, blessings: %d.") % [int(summary["passive_points"]), int(summary["items"]), (_parsed["build"]["blessings"] as Dictionary).size()])
	if not warnings.is_empty():
		lines.append(_warning_text(warnings))
	_status("\n".join(lines))
	imported.emit()


# ============================================================================
# BROWSER
# ============================================================================

func _web_setup() -> void:
	JavaScriptBridge.eval(WEB_SETUP_JS % SaveImportScript.MAX_BYTES)
	_web_callback = JavaScriptBridge.create_callback(_on_web_file)
	var bridge: Variant = JavaScriptBridge.get_interface("window")._leSave
	bridge.cb = _web_callback
	_on_visibility_changed()


## Dropping a file works only while this tab is on screen.
func _on_visibility_changed() -> void:
	var bridge: Variant = JavaScriptBridge.get_interface("window")._leSave
	if bridge != null:
		# is_visible_in_tree() ignores a hidden parent Window, so the dialog's own visibility is checked too
		bridge.drop = is_visible_in_tree() and get_window().visible


func _on_web_file(args: Array) -> void:
	var error: String = str(args[2])
	if error == "size":
		_show_error(tr("The file is too big (%d MB): a character save is far smaller.") % ceili(SaveImportScript.MAX_BYTES / 1048576.0))
		return
	if error != "":
		_show_error(tr("Could not read the file."))
		return
	_load_bytes(str(args[1]).to_utf8_buffer(), str(args[0]))


func _warning_text(warnings: Array) -> String:
	var lines: PackedStringArray = [tr("Warnings (%d):") % warnings.size()]
	for i in range(mini(warnings.size(), WARNINGS_SHOWN)):
		lines.append("- " + str(warnings[i]))
	if warnings.size() > WARNINGS_SHOWN:
		lines.append(tr("… and %d more.") % (warnings.size() - WARNINGS_SHOWN))
	return "\n".join(lines)


func _status(text: String) -> void:
	%StatusLabel.text = text
