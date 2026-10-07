class_name ItemPictures

## Game pictures of items (tools/extract/extract_item_pictures.py): equipment in res://assets/equipment, idols and idol
## altars in res://assets/idols; files sub_<baseTypeID>_<subTypeID>.webp and unique_<uniqueID>.webp.

const EQUIPMENT_DIR: String = "res://assets/equipment"
const IDOL_DIR: String = "res://assets/idols"


## Picture of a stored item (unique picture first, then the subtype); null for an empty item or a missing picture.
static func picture(item: Dictionary) -> Texture2D:
	if not item.has("base"):
		return null
	var base_id: int = int(item["base"])
	var base_type: int = int(GameData.item_base(base_id).get("type", -1))
	var dir: String = IDOL_DIR if GameData.is_idol_type(base_type) or base_id == IdolGrid.ALTAR_BASE else EQUIPMENT_DIR
	if item.has("unique"):
		var unique_path: String = dir.path_join("unique_%d.webp" % int(item["unique"]))
		if ResourceLoader.exists(unique_path):
			return load(unique_path)
	var path: String = dir.path_join("sub_%d_%d.webp" % [base_id, int(item.get("sub", -1))])
	return load(path) if ResourceLoader.exists(path) else null
