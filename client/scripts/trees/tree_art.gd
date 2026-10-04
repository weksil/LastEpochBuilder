class_name TreeArt

## Game visuals of the skill and passive trees: research/data/game/tree_art.json (tools/extract/extract_tree_art.py) and
## the sprites in res://assets/trees/. Offsets and positions are Unity UI coordinates (y up), like trees.json positions.
## Layer: {part, sprite, color [r,g,b,a], size [w,h], offset [x,y], active, type, mask?}. Loaded lazily once.

const ART_DIR: String = "res://assets/trees/"

static var _art: Dictionary = {}
static var _loaded: bool = false
static var _textures: Dictionary = {}


static func _data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var path: String = ProjectSettings.globalize_path("res://").path_join("../research/data/game/tree_art.json").simplify_path()
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_art = parsed
	return _art


## {layers, size, mastery, borderInactive, borderActive} of a node, {} if the tree has no art.
static func node_art(tree_id: String, node_id: int) -> Dictionary:
	return _data().get("trees", {}).get(tree_id, {}).get("nodes", {}).get(str(node_id), {})


## First active layer whose part path ends with `suffix` ("IconMask/Icon", "Border", "BorderBright" …), {} if none.
static func layer(art: Dictionary, suffix: String) -> Dictionary:
	for l: Dictionary in art.get("layers", []):
		var part: String = str(l["part"])
		if l.get("sprite") != null and (part == suffix or part.ends_with("/" + suffix)):
			return l
	return {}


## Background and ornaments of a tree panel (passive trees: one per mastery; skill trees: "0").
static func decor(tree_id: String, mastery: int) -> Array:
	return _data().get("trees", {}).get(tree_id, {}).get("panels", {}).get(str(mastery), [])


## Rail layers of the tree's connection prefab: {"rail": layer, "fill": layer}, {} if none.
static func connection(tree_id: String) -> Dictionary:
	var key: Variant = _data().get("trees", {}).get(tree_id, {}).get("connection")
	if key == null:
		return {}
	var out: Dictionary = {}
	for l: Dictionary in _data().get("connections", {}).get(str(key), {}).get("layers", []):
		if str(l["part"]).ends_with("/SingleRail"):
			out["rail"] = l
		elif str(l["part"]).ends_with("/SingleRailFill"):
			out["fill"] = l
	return out


## Nine-slice margins of a sprite in pixels: [left, bottom, right, top].
static func border(file: String) -> Array:
	return _data().get("sprites", {}).get(file, {}).get("border", [0, 0, 0, 0])


## Sets nine-slice margins of `rect` for sprite `file`, scaled down so that they fit `target_size` (Unity scales
## the borders of sliced images with the reference pixels per unit; a NinePatchRect never gets smaller than its margins).
static func apply_nine_slice(rect: NinePatchRect, file: String, target_size: Vector2) -> void:
	var b: Array = border(file)
	var k: float = 1.0
	if float(b[0]) + float(b[2]) > 0.0:
		k = minf(k, target_size.x / (float(b[0]) + float(b[2])))
	if float(b[1]) + float(b[3]) > 0.0:
		k = minf(k, target_size.y / (float(b[1]) + float(b[3])))
	rect.patch_margin_left = int(float(b[0]) * k)
	rect.patch_margin_bottom = int(float(b[1]) * k)
	rect.patch_margin_right = int(float(b[2]) * k)
	rect.patch_margin_top = int(float(b[3]) * k)


static func texture(file: Variant) -> Texture2D:
	if file == null or str(file) == "":
		return null
	var key: String = str(file)
	if not _textures.has(key):
		var path: String = ART_DIR + key
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]


static func color(l: Dictionary) -> Color:
	var c: Array = l.get("color", [1, 1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))


## Unity offset (y up) -> Godot offset (y down).
static func offset(l: Dictionary) -> Vector2:
	var o: Array = l.get("offset", [0, 0])
	return Vector2(float(o[0]), -float(o[1]))


static func size(l: Dictionary) -> Vector2:
	var s: Array = l.get("size", [0, 0])
	return Vector2(float(s[0]), float(s[1]))
