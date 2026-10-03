class_name IdolGrid

## Idol placement on the 5×5 grid. Idols are stored in Build.items under "idol_<row>_<col>"
## (top-left cell); base gridSize is [width, height].

const PREFIX: String = "idol_"
const BLOCKED: int = 99


static func key(row: int, col: int) -> String:
	return "%s%d_%d" % [PREFIX, row, col]


static func is_idol_key(slot: String) -> bool:
	return slot.begins_with(PREFIX)


static func anchor(slot: String) -> Vector2i:
	var parts: PackedStringArray = slot.trim_prefix(PREFIX).split("_")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)


static func is_open(row: int, col: int) -> bool:
	var grid: Array = GameData.idol_grid()
	if row < 0 or row >= grid.size() or col < 0 or col >= grid[row].size():
		return false
	return int(grid[row][col]) != BLOCKED


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
		if not is_open(cell.x, cell.y):
			return false
		if occ.has(cell) and occ[cell] != ignore_slot:
			return false
	return true
