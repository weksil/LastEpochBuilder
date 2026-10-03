class_name IdolGrid

## Idol placement on the 5×5 grid. Idols are stored in Build.items under "idol_<row>_<col>"
## (top-left cell); base gridSize is [width, height].

const PREFIX: String = "idol_"
const BLOCKED: int = 99
const ALTAR_SLOT: String = "altar"
const ALTAR_BASE: int = 41


static func key(row: int, col: int) -> String:
	return "%s%d_%d" % [PREFIX, row, col]


static func is_idol_key(slot: String) -> bool:
	return slot.begins_with(PREFIX)


static func anchor(slot: String) -> Vector2i:
	var parts: PackedStringArray = slot.trim_prefix(PREFIX).split("_")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)


## Altar item in the items dictionary ({} when no altar is set).
static func altar(items: Variant = null) -> Dictionary:
	var src: Dictionary = items if items is Dictionary else Build.items
	var item: Dictionary = src.get(ALTAR_SLOT, {})
	return item if int(item.get("base", -1)) == ALTAR_BASE else {}


## 5×5 unlockMatrix of the altar subtype when an altar is set, otherwise the default grid.
static func grid(items: Variant = null) -> Array:
	var item: Dictionary = altar(items)
	if item.is_empty():
		return GameData.idol_grid()
	return GameData.altar_grid(int(item.get("sub", 0)))


static func cell_code(row: int, col: int, items: Variant = null) -> int:
	var g: Array = grid(items)
	if row < 0 or row >= g.size() or col < 0 or col >= g[row].size():
		return BLOCKED
	return int(g[row][col])


static func is_open(row: int, col: int, items: Variant = null) -> bool:
	return cell_code(row, col, items) != BLOCKED


## Refracted slot: unlockMatrix value + 100 (idols there get the altar's effect on affixes).
static func is_refracted(row: int, col: int, items: Variant = null) -> bool:
	return cell_code(row, col, items) > BLOCKED


static func size_of(base_id: int) -> Vector2i:
	var gs: Array = GameData.item_base(base_id).get("gridSize", [1, 1])
	return Vector2i(int(gs[0]), int(gs[1]))


## Cells (row, col) covered by an idol of base_id placed at (row, col).
static func cells(row: int, col: int, base_id: int) -> Array[Vector2i]:
	var size: Vector2i = size_of(base_id)
	var out: Array[Vector2i] = []
	for dr in range(size.y):
		for dc in range(size.x):
			out.append(Vector2i(row + dr, col + dc))
	return out


## Map Vector2i(row, col) -> slot key for every occupied cell.
static func occupancy(items: Dictionary) -> Dictionary:
	var occ: Dictionary = {}
	for slot: String in items:
		if not is_idol_key(slot) or not items[slot].has("base"):
			continue
		var a: Vector2i = anchor(slot)
		for cell: Vector2i in cells(a.x, a.y, int(items[slot]["base"])):
			occ[cell] = slot
	return occ


## True if base_id fits at (row, col) on open cells not used by other idols (ignore_slot may overlap itself).
static func fits(items: Dictionary, row: int, col: int, base_id: int, ignore_slot: String = "") -> bool:
	var occ: Dictionary = occupancy(items)
	for cell: Vector2i in cells(row, col, base_id):
		if not is_open(cell.x, cell.y, items):
			return false
		if occ.has(cell) and occ[cell] != ignore_slot:
			return false
	return true
