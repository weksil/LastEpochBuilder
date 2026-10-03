## Storage for stat modifiers with optional parent chain.
class_name StatStore extends RefCounted


var mods: Array[StatMod] = []  # Mods stored locally
var parent: StatStore = null  # Optional parent store (for inheritance chain)


## Add a single mod to this store.
func add(mod: StatMod) -> void:
	mods.append(mod)


## Add multiple mods to this store.
func add_all(arr: Array) -> void:
	for mod in arr:
		if mod is StatMod:
			mods.append(mod)


## Return all mods: own mods plus entire parent chain.
func all_mods() -> Array[StatMod]:
	var result: Array[StatMod] = mods.duplicate()

	var current = parent
	while current != null:
		result.append_array(current.mods)
		current = current.parent

	return result


## Query mods for a property with optional filtering.
## Filters:
## - property must equal
## - mod.special == 0 or mod.special == special
## - mod.extra == extra or (extra_zero_matches and mod.extra == 0)
## - LE.tags_match(mod.tags, check_tags)
func query(property: int, check_tags: int = 0, special: int = 0, extra: int = 0, extra_zero_matches: bool = true) -> StatQuery:
	var result = StatQuery.new()

	for mod in all_mods():
		# Check property
		if mod.property != property:
			continue

		# Check special
		if mod.special != 0 and mod.special != special:
			continue

		# Check extra
		if mod.extra != extra and not (extra_zero_matches and mod.extra == 0):
			continue

		# Check tags
		if not LE.tags_match(mod.tags, check_tags):
			continue

		# This mod matches; add it to result
		result.added += mod.added
		result.increased += mod.increased

		for m in mod.more:
			result.more *= (1.0 + m)

		result.mods.append(mod)

	return result


## Query mods for a property with no tags/special/extra filtering.
## Only mods with tags == 0 and extra == 0 and special == 0 are included.
func query_untagged(property: int) -> StatQuery:
	return query(property, 0, 0, 0, false)


## Sum the added values of mods for multiple properties (untagged only).
func sum_added_untagged(properties: Array) -> float:
	var total: float = 0.0

	for prop in properties:
		if prop is int:
			var q = query_untagged(prop)
			total += q.added

	return total


## Get all untagged mods for multiple properties.
func untagged_mods(properties: Array) -> Array[StatMod]:
	var result: Array[StatMod] = []

	for prop in properties:
		if prop is int:
			var q = query_untagged(prop)
			result.append_array(q.mods)

	return result
