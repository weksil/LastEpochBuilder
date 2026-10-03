class_name FieldModels

## Planner models of skill-tree / passive mutator fields and special stat lists (docs/ENGINE.md §9.1):
## client/data/field_models.json, key "Mutator.field" or "Mutator.list". Loaded lazily once.

static var _models: Dictionary = {}
static var _loaded: bool = false


static func find(key: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var path: String = ProjectSettings.globalize_path("res://data/field_models.json")
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_models = parsed
	return _models.get(key, {})


static func count() -> int:
	find("")
	return _models.size()
