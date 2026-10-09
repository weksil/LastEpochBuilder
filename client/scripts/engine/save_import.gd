class_name SaveImport

## Import of a character from the game's own offline save file (CharacterSlot file: ASCII "EPOCH" + the UTF-8 JSON of
## CharacterData). Pure functions: file bytes -> checked JSON -> the build description of MaxrollImport.to_build (the JSON is
## the same format that Maxroll serves) and applying it to the Build autoload with LEToolsImport.apply.
## Format: research/07e_save_format.md; reference parser: tools/extract/save_parser.py.

const PREFIX: String = "EPOCH"
## Files of the game are some KB .. a few MB; anything bigger is not a save.
const MAX_BYTES: int = 20 * 1024 * 1024
const SAVES_DIR: String = "AppData/LocalLow/Eleventh Hour Games/Last Epoch/Saves"
## Folder of the game's saves as shown to the user.
const SAVES_DIR_TEXT: String = "%USERPROFILE%\\AppData\\LocalLow\\Eleventh Hour Games\\Last Epoch\\Saves"


## The game's save folder on Windows, "" elsewhere or when the game was never started.
static func saves_dir() -> String:
	if OS.get_name() != "Windows":
		return ""
	var profile: String = OS.get_environment("USERPROFILE")
	if profile == "":
		return ""
	var dir: String = profile.replace("\\", "/").path_join(SAVES_DIR)
	return dir if DirAccess.dir_exists_absolute(dir) else ""


## File bytes -> {ok, error, summary, warnings, build}. `summary` = {name, class_id, class_name, mastery, mastery_name, level,
## passive_points, items} for the confirmation line; `build` = the description for apply(). On failure `error` is a readable
## message and the other fields are empty.
static func parse(bytes: PackedByteArray) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "summary": {}, "warnings": [], "build": {}}
	if bytes.is_empty():
		result["error"] = LE.t("The file is empty.")
		return result
	if bytes.size() > MAX_BYTES:
		result["error"] = LE.t("The file is too big (%d MB): a character save is far smaller.") % ceili(bytes.size() / 1048576.0)
		return result
	var start: int = 3 if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF else 0
	if bytes.slice(start, start + PREFIX.length()).get_string_from_ascii() != PREFIX:
		var first: int = bytes[start] if bytes.size() > start else 0
		if first == 0x7B:  # "{"
			result["error"] = LE.t("This is a JSON file without the EPOCH prefix, not a file written by the game. Pick the character file from the game's Saves folder.")
		else:
			result["error"] = LE.t("This is not a Last Epoch save file: it does not start with EPOCH.")
		return result
	var text: String = bytes.slice(start + PREFIX.length()).get_string_from_utf8()
	var json := JSON.new()
	if text == "" or json.parse(text) != OK or not json.data is Dictionary:
		result["error"] = LE.t("The save file is damaged: its data could not be read.")
		return result
	var save: Dictionary = json.data
	if not save.has("characterClass"):
		result["error"] = LE.t("This file holds no character (stash and global data files cannot be imported). Pick a file named like 1CHARACTERSLOT_BETA_0.")
		return result

	var doc: Dictionary = MaxrollImport.to_build(save)
	var class_id: int = int(doc["class_id"])
	if class_id < 0:
		var warnings: Array = doc["warnings"]
		result["error"] = LE.t("Could not import the character.") + ("" if warnings.is_empty() else "\n" + "\n".join(PackedStringArray(warnings)))
		return result
	var class_data: Dictionary = GameData.get_class_data(class_id)
	var mastery: int = int(doc["mastery"])
	var masteries: Array = class_data.get("masteries", [])
	var passive_points: int = 0
	for points: Variant in (doc["passives"] as Dictionary).values():
		passive_points += int(points)
	result["ok"] = true
	result["warnings"] = doc["warnings"]
	result["build"] = doc
	result["summary"] = {
		"name": str(save.get("characterName", "")),
		"class_id": class_id,
		"class_name": str(class_data.get("className", "")),
		"mastery": mastery,
		"mastery_name": "" if mastery == 0 or mastery >= masteries.size() else str(masteries[mastery].get("name", "")),
		"level": int(doc["level"]),
		"passive_points": passive_points,
		"items": (doc["items"] as Dictionary).size(),
	}
	return result


## Replaces the build of the Build autoload (`build`) with a successful parse() result. One `changed` burst = one undo step
## of BuildHistory, as for the other importers.
static func apply(build: Node, parsed: Dictionary) -> void:
	if not bool(parsed.get("ok", false)):
		return
	LEToolsImport.apply(build, parsed["build"])
