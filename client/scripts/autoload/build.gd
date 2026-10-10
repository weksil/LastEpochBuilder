extends Node

signal changed
## The unequipped items (`stash`) changed. They do not affect the stats, so `changed` is not emitted for them alone.
signal stash_changed

const QUEST_PASSIVE_POINTS_MAX: int = 15

# Passive tree
var class_id: int = -1
var mastery: int = 0
var level: int = 100
var passives: Dictionary = {}
var _nodes: Dictionary = {}
## Passive points granted by completed quests (the game caps the sum at 15, docs/ENGINE.md §3).
var quest_passive_points: int = QUEST_PASSIVE_POINTS_MAX
## Test hook: when >= 0 replaces the computed passive point cap.
var passive_cap_override: int = -1

# Skills (5 slots)
var skills: Array[Dictionary] = []
## Slot shown in "Skills" / "Calculations" and in the stats summary; changing it emits `changed` so every view follows.
var selected_skill: int = 0:
	set(value):
		if value == selected_skill:
			return
		selected_skill = value
		changed.emit()
var _skill_nodes: Array[Dictionary] = []  # skill tree nodes per slot

# Items
var items: Dictionary = {}
## Unequipped (inactive) equipment items, same dict shape as items[slot] (docs/UI.md "Items").
var stash: Array[Dictionary] = []

# Blessings (timelineID -> {"id": int, "roll": int})
var blessings: Dictionary = {}

# Enemy config
var enemy: Dictionary = {}

# Player state
var player_state: Dictionary = {}

# Defense tab: the enemy attack and the area level (DefenseCalc.default_settings)
var defense: Dictionary = {}

# Cached "+N to skill level" totals per slot from items (reset on every change)
var _skill_bonus_cache: Dictionary = {}


func _ready() -> void:
	changed.connect(_on_self_changed)
	_init_defaults()


func _on_self_changed() -> void:
	_skill_bonus_cache.clear()


func _init_defaults() -> void:
	skills.clear()
	_skill_nodes.clear()
	for i in range(5):
		skills.append(default_skill())
		_skill_nodes.append({})
	enemy = default_enemy()
	player_state = default_player_state()
	defense = DefenseCalc.default_settings()
	items = {}
	stash.clear()


## Empty skill slot.
static func default_skill() -> Dictionary:
	return {"ability": "", "level": 20, "tree": {}, "inputs": {}, "hits": 1.0, "projectile_mode": "average"}


## Enemy config by default: the training dummy, so the numbers match in-game dummy hits.
static func default_enemy() -> Dictionary:
	return {
		"level": 100,
		"kind": "dummy",
		"res": [0, 0, 0, 0, 0, 0, 0],
		"armour": 0,
		"corruption": 0,
		"ailments": {},
		"flags": {
			"moving": false,
			"stunned": false,
			"low_health": false,
			"high_health": true,
			"full_health": true,
			"frozen": false
		}
	}


## Player state by default (flags and numbers used by unique special effects, docs/ENGINE.md §5.4.3).
static func default_player_state() -> Dictionary:
	return {
		"health": "full",
		"hit_recently": false,
		"crit_recently": false,
		"moving": false,
		"leeching": false,
		"low_mana": false,
		"haste": false,
		"frenzy": false,
		"killed_recently": false,
		"minion_killed_recently": false,
		# transformed (Reaper Form, Werebear …): stats with the Transform tag also apply without it (BuildMods)
		"transformed": false,
		"ward": 0,
		"curses": 0,
		"ignite_stacks": 0,
		"damned_stacks": 0,
		"shadows": 0,
		# events per second the calculation cannot derive (EnemyAilments.EVENT_INPUTS)
		"kills_per_second": 0.0,
		"stuns_per_second": 0.0,
		"arrow_pickups_per_second": 0.0,
		"health_drops_per_second": 0.0,
		# active minions set by hand: actor name or MinionCount count key -> count (the rest are automatic)
		"minions": {},
		# buffs on the player: AilmentID -> stacks (positive ailments of ailments.json, the "Buffs on me" list)
		"buffs": {}
	}


func set_class(id: int) -> void:
	class_id = id
	mastery = 0
	passives.clear()
	_nodes.clear()

	# Reset skills and items
	for i in range(skills.size()):
		skills[i] = default_skill()
	for i in range(_skill_nodes.size()):
		_skill_nodes[i] = {}
	items.clear()
	stash.clear()
	blessings.clear()

	var tree: Dictionary = GameData.get_passive_tree(class_id)
	if "nodes" in tree and tree["nodes"] is Array:
		for node: Variant in tree["nodes"]:
			if node is Dictionary:
				var node_entry: Dictionary = node
				if "id" in node_entry:
					var node_id: int = int(node_entry["id"])
					_nodes[node_id] = node_entry

	stash_changed.emit()
	changed.emit()

func set_mastery(m: int) -> void:
	mastery = m
	changed.emit()

func set_level(l: int) -> void:
	level = l
	changed.emit()

func get_points(id: int) -> int:
	if id in passives:
		return passives[id] as int
	return 0

func spent_points() -> int:
	var total: int = 0
	for points: Variant in passives.values():
		total += int(points)
	return total

## Passive points earned at the current level (LocalTreeData.calculatePassivePointsEarnt, research/07e §6):
## level - 2 + min(15, quest points), clamped to 0..255.
func passive_point_cap() -> int:
	if passive_cap_override >= 0:
		return passive_cap_override
	return clampi(level - 2 + mini(QUEST_PASSIVE_POINTS_MAX, maxi(quest_passive_points, 0)), 0, 255)


func points_in_mastery(m: int) -> int:
	var total: int = 0
	for node_id: Variant in passives.keys():
		var nid: int = int(node_id)
		if nid in _nodes:
			var node: Dictionary = _nodes[nid]
			if "mastery" in node and int(node["mastery"]) == m:
				total += int(passives[nid])
	return total

func _points_below(threshold: int, node_mastery: int) -> int:
	var total: int = 0
	for nid: int in passives:
		var other: Dictionary = _nodes.get(nid, {})
		var m: int = int(other.get("mastery", -1))
		if (m == 0 or m == node_mastery) and int(other.get("masteryRequirement", 0)) < threshold:
			total += int(passives[nid])
	return total

func _is_valid(id: int) -> bool:
	if id not in _nodes:
		return false

	if get_points(id) == 0:
		return true

	var node: Dictionary = _nodes[id]

	if not requirements_met(node, passives):
		return false

	# Points threshold: count only points in lower-threshold nodes of the base tree and this node's mastery tree
	var mastery_req: int = int(node.get("masteryRequirement", 0))
	if mastery_req > 0 and _points_below(mastery_req, int(node.get("mastery", 0))) < mastery_req:
		return false

	return true

func can_add(id: int) -> bool:
	if id not in _nodes:
		return false

	var node: Dictionary = _nodes[id]

	if "maxPoints" not in node or int(node["maxPoints"]) <= 0:
		return false

	var current_points: int = get_points(id)
	var max_points: int = int(node["maxPoints"])
	if current_points >= max_points:
		return false

	if spent_points() >= passive_point_cap():
		return false

	# Simulate adding a point and check if it would be valid
	passives[id] = current_points + 1
	var valid: bool = _is_valid(id)

	# Restore original state
	if current_points > 0:
		passives[id] = current_points
	else:
		passives.erase(id)

	return valid

func add_point(id: int) -> bool:
	if not can_add(id):
		return false

	passives[id] = get_points(id) + 1
	changed.emit()
	return true

func remove_point(id: int) -> bool:
	if id not in passives or get_points(id) == 0:
		return false

	var current_points: int = get_points(id)
	var old_points: Dictionary = passives.duplicate()

	# Decrement or remove
	if current_points - 1 <= 0:
		passives.erase(id)
	else:
		passives[id] = current_points - 1

	# Check if any allocated node is now invalid or cut off from the root
	var ok: bool = all_connected(_nodes, passives)
	for node_id: Variant in passives.keys():
		ok = ok and _is_valid(int(node_id))
	if not ok:
		passives = old_points
		return false

	changed.emit()
	return true


## Game rule (LocalTreeData.ArePassiveNodeRequirementsMet): a node is unlocked when ANY of its
## requirements {nodeID, requirement} has at least `requirement` points; no requirements = unlocked.
static func requirements_met(node: Dictionary, points: Dictionary) -> bool:
	var reqs: Array = node.get("requirements", [])
	if reqs.is_empty():
		return true
	for req: Dictionary in reqs:
		if int(points.get(int(req["nodeID"]), 0)) >= int(req["requirement"]):
			return true
	return false


## Every allocated node must be reachable from a root (node without requirements or with maxPoints 0)
## through requirements that are met, so two nodes cannot keep each other alive after their path is removed.
static func all_connected(nodes: Dictionary, points: Dictionary) -> bool:
	var connected: Dictionary = {}
	for id: Variant in nodes:
		var node: Dictionary = nodes[id]
		if int(node.get("maxPoints", 0)) == 0 or node.get("requirements", []).is_empty():
			connected[int(id)] = true
	var grew: bool = true
	while grew:
		grew = false
		for id: Variant in points:
			var nid: int = int(id)
			if connected.has(nid) or int(points[id]) <= 0 or not nodes.has(nid):
				continue
			for req: Dictionary in nodes[nid].get("requirements", []):
				var rid: int = int(req["nodeID"])
				if connected.has(rid) and int(points.get(rid, 0)) >= int(req["requirement"]):
					connected[nid] = true
					grew = true
					break
	for id: Variant in points:
		if int(points[id]) > 0 and not connected.has(int(id)):
			return false
	return true


# ============================================================================
# SKILLS
# ============================================================================

func set_skill(slot: int, ability_id: String) -> void:
	if slot < 0 or slot >= skills.size():
		return

	skills[slot] = default_skill()
	skills[slot]["ability"] = ability_id
	_skill_nodes[slot] = {}

	# Load skill tree nodes if ability is valid
	if ability_id != "":
		var ability: Dictionary = GameData.get_ability(ability_id)
		if "skillTree" in ability:
			var tree_id: String = ability["skillTree"]
			var tree: Dictionary = GameData.get_skill_tree(tree_id)
			if "nodes" in tree and tree["nodes"] is Array:
				for node: Variant in tree["nodes"]:
					if node is Dictionary:
						var node_entry: Dictionary = node
						if "id" in node_entry:
							var node_id: int = int(node_entry["id"])
							_skill_nodes[slot][node_id] = node_entry

	changed.emit()


func set_skill_level(slot: int, lvl: int) -> void:
	if slot < 0 or slot >= skills.size():
		return

	skills[slot]["level"] = lvl
	changed.emit()


## Bonus to the skill level from equipped items: LevelOfSkills (SP 88) mods whose tags fit the
## ability tags and whose extra is 0 or the ability's AbilityID (research/06e §6); «+N to Level of <skill>» affixes carry
## specialTag 1 and the AbilityID in tags.
func skill_level_bonus(slot: int) -> int:
	if slot < 0 or slot >= skills.size():
		return 0
	if _skill_bonus_cache.has(slot):
		return int(_skill_bonus_cache[slot])
	var ability: Dictionary = GameData.get_ability(str(skills[slot].get("ability", "")))
	var total: float = 0.0
	if not ability.is_empty():
		var ability_tags: int = int(ability.get("tags", 0))
		var enum_rec: Variant = ability.get("abilityIDEnum")
		var ability_index: int = int((enum_rec as Dictionary).get("value", -1)) if enum_rec is Dictionary else -1
		var store: StatStore = BuildMods.global_store(self)["store"]
		for mod: StatMod in store.all_mods():
			if mod.property != LE.LEVEL_OF_SKILLS:
				continue
			# "+N to Level of <skill>" affixes: specialTag 1 and the ability index stored in `tags` (all 138 such affixes)
			if mod.special == 1:
				if mod.tags == ability_index:
					total += mod.added
				continue
			if mod.extra != 0 and mod.extra != ability_index:
				continue
			if LE.tags_match(mod.tags, ability_tags):
				total += mod.added
	var bonus: int = maxi(roundi(total), 0)
	_skill_bonus_cache[slot] = bonus
	return bonus


## Skill tree point cap = skill level + bonus from items.
func skill_point_cap(slot: int) -> int:
	if slot < 0 or slot >= skills.size():
		return 0
	return int(skills[slot].get("level", 20)) + skill_level_bonus(slot)


func get_skill_points(slot: int, node_id: int) -> int:
	if slot < 0 or slot >= skills.size():
		return 0

	var tree: Dictionary = skills[slot].get("tree", {})
	if node_id in tree:
		return tree[node_id] as int
	return 0


func skill_points_spent(slot: int) -> int:
	if slot < 0 or slot >= skills.size():
		return 0

	var total: int = 0
	var tree: Dictionary = skills[slot].get("tree", {})
	for points: Variant in tree.values():
		total += int(points)
	return total


func _skill_is_valid(slot: int, node_id: int) -> bool:
	if slot < 0 or slot >= skills.size():
		return false

	if node_id not in _skill_nodes[slot]:
		return false

	if get_skill_points(slot, node_id) == 0:
		return true

	var node: Dictionary = _skill_nodes[slot][node_id]
	return requirements_met(node, skills[slot].get("tree", {}))


func can_add_skill_point(slot: int, node_id: int) -> bool:
	if slot < 0 or slot >= skills.size():
		return false

	if node_id not in _skill_nodes[slot]:
		return false

	var node: Dictionary = _skill_nodes[slot][node_id]

	if "maxPoints" not in node or int(node["maxPoints"]) <= 0:
		return false

	var current_points: int = get_skill_points(slot, node_id)
	var max_points: int = int(node["maxPoints"])
	if current_points >= max_points:
		return false

	# Check if total skill points would exceed level (+ item bonus)
	if skill_points_spent(slot) >= skill_point_cap(slot):
		return false

	# Simulate adding a point and check if it would be valid
	var tree: Dictionary = skills[slot]["tree"] as Dictionary
	tree[node_id] = current_points + 1
	var valid: bool = _skill_is_valid(slot, node_id)

	# Restore original state
	if current_points > 0:
		tree[node_id] = current_points
	else:
		tree.erase(node_id)

	return valid


func add_skill_point(slot: int, node_id: int) -> bool:
	if not can_add_skill_point(slot, node_id):
		return false

	var tree: Dictionary = skills[slot]["tree"] as Dictionary
	tree[node_id] = get_skill_points(slot, node_id) + 1
	changed.emit()
	return true


func remove_skill_point(slot: int, node_id: int) -> bool:
	if slot < 0 or slot >= skills.size():
		return false

	var tree: Dictionary = skills[slot]["tree"] as Dictionary
	if node_id not in tree or get_skill_points(slot, node_id) == 0:
		return false

	var current_points: int = get_skill_points(slot, node_id)
	var old_tree: Dictionary = tree.duplicate()

	# Decrement or remove
	if current_points - 1 <= 0:
		tree.erase(node_id)
	else:
		tree[node_id] = current_points - 1

	# Check if any allocated node is now invalid or cut off from the root
	var ok: bool = all_connected(_skill_nodes[slot], tree)
	for allocated_node_id: Variant in tree.keys():
		ok = ok and _skill_is_valid(slot, int(allocated_node_id))
	if not ok:
		skills[slot]["tree"] = old_tree
		return false

	changed.emit()
	return true


func set_skill_input(slot: int, key: String, value: Variant) -> void:
	if slot < 0 or slot >= skills.size():
		return

	skills[slot]["inputs"][key] = value
	changed.emit()


func get_skill_input(slot: int, key: String, default: Variant) -> Variant:
	if slot < 0 or slot >= skills.size():
		return default

	var inputs: Dictionary = skills[slot].get("inputs", {})
	return inputs.get(key, default)


func set_skill_hits(slot: int, hits: float) -> void:
	if slot < 0 or slot >= skills.size():
		return

	skills[slot]["hits"] = maxf(hits, 0.0)
	changed.emit()


## How many projectiles of one use hit the target: one of SkillCalc.PROJECTILE_MODES.
func set_skill_projectile_mode(slot: int, mode: String) -> void:
	if slot < 0 or slot >= skills.size() or not SkillCalc.PROJECTILE_MODES.has(mode):
		return
	skills[slot]["projectile_mode"] = mode
	changed.emit()


# ============================================================================
# BLESSINGS
# ============================================================================

func set_blessing(timeline_id: int, id: int, roll: int) -> void:
	if id < 0:
		# Negative ID means remove blessing for this timeline
		if timeline_id in blessings:
			blessings.erase(timeline_id)
	else:
		blessings[timeline_id] = {"id": id, "roll": roll}
	changed.emit()


# ============================================================================
# ITEMS
# ============================================================================

func set_item(slot: String, item_dict: Dictionary) -> void:
	items[slot] = item_dict.duplicate()
	changed.emit()


func clear_item(slot: String) -> void:
	if slot in items:
		items.erase(slot)
		changed.emit()


## Puts a copy of the item into the stash (unequipped items).
func stash_add(item: Dictionary) -> void:
	if item.is_empty():
		return
	stash.append(item.duplicate(true))
	stash_changed.emit()


func stash_remove(index: int) -> void:
	if index < 0 or index >= stash.size():
		return
	stash.remove_at(index)
	stash_changed.emit()


## Replaces the stash entry with a copy of `item` (the item editor writes its edits here).
func stash_set(index: int, item: Dictionary) -> void:
	if index < 0 or index >= stash.size():
		return
	stash[index] = item.duplicate(true)
	stash_changed.emit()


## Moves the item of `from_slot` into `to_slot`. The item that was in `to_slot` swaps into `from_slot` when its base
## fits there, otherwise it goes to the stash.
func move_item(from_slot: String, to_slot: String) -> void:
	if from_slot == to_slot or not items.has(from_slot):
		return
	var moved: Dictionary = items[from_slot]
	var old: Dictionary = items.get(to_slot, {})
	items[to_slot] = moved
	var stashed: bool = false
	if old.is_empty():
		items.erase(from_slot)
	elif ItemCompare.fits_slot(from_slot, GameData.item_base(int(old.get("base", -1)))):
		items[from_slot] = old
	else:
		stash.append(old)
		items.erase(from_slot)
		stashed = true
	if stashed:
		stash_changed.emit()
	changed.emit()


## Equips the stash item into `slot`; the item that was in the slot takes its place in the stash.
func equip_from_stash(index: int, slot: String) -> void:
	if index < 0 or index >= stash.size():
		return
	var old: Dictionary = items.get(slot, {})
	items[slot] = stash[index].duplicate(true)
	if old.is_empty():
		stash.remove_at(index)
	else:
		stash[index] = old
	stash_changed.emit()
	changed.emit()


## Equips a new item (for example a unique from the database); the item that was in the slot goes to the stash.
func equip_item(slot: String, item: Dictionary) -> void:
	var old: Dictionary = items.get(slot, {})
	var stashed: bool = not old.is_empty()
	if stashed:
		stash.append(old)
	items[slot] = item.duplicate(true)
	if stashed:
		stash_changed.emit()
	changed.emit()


## Takes the item out of the slot into the stash.
func unequip_to_stash(slot: String) -> void:
	var old: Dictionary = items.get(slot, {})
	if old.is_empty():
		return
	stash.append(old)
	items.erase(slot)
	stash_changed.emit()
	changed.emit()


# ============================================================================
# ENEMY
# ============================================================================

func set_enemy(key: String, value: Variant) -> void:
	enemy[key] = value
	changed.emit()


## Returns every enemy ailment / shred / curse to its automatic value (one `changed`).
func clear_enemy_ailments() -> void:
	enemy["ailments"] = {}
	changed.emit()


## Sets the enemy's stacks of an ailment by hand (0 included: «never on the enemy»); the automatic value no longer applies.
func set_enemy_ailment(ailment_id: int, stacks: float) -> void:
	var ailments: Dictionary = enemy.get("ailments", {}) as Dictionary
	ailments[ailment_id] = maxf(stacks, 0.0)
	enemy["ailments"] = ailments
	changed.emit()


## Returns one enemy ailment to the average the selected skill keeps on the target (EnemyAilments).
func clear_enemy_ailment(ailment_id: int) -> void:
	var ailments: Dictionary = enemy.get("ailments", {}) as Dictionary
	if ailments.erase(ailment_id):
		enemy["ailments"] = ailments
		changed.emit()


# ============================================================================
# DEFENSE
# ============================================================================

func set_defense(key: String, value: Variant) -> void:
	defense[key] = value
	changed.emit()


# ============================================================================
# PLAYER STATE
# ============================================================================

func set_player_state(key: String, value: Variant) -> void:
	player_state[key] = value
	changed.emit()


## Switches off every player condition flag and zeroes the player numbers (health level stays); one `changed`.
func reset_player_conditions() -> void:
	for key: String in player_state:
		var value: Variant = player_state[key]
		if value is bool:
			player_state[key] = false
		elif value is Dictionary:
			continue  # buffs have their own reset (clear_player_buffs)
		elif value is float:
			player_state[key] = 0.0
		elif key != "health":
			player_state[key] = 0
	changed.emit()


## Sets the number of active minions of a type (actor name) or of a MinionCount count key by hand.
func set_minion_count(key: String, value: float) -> void:
	var minions: Dictionary = player_state.get("minions", {}) as Dictionary
	minions[key] = maxf(value, 0.0)
	player_state["minions"] = minions
	changed.emit()


## Returns one minion count to automatic.
func clear_minion_count(key: String) -> void:
	var minions: Dictionary = player_state.get("minions", {}) as Dictionary
	if minions.erase(key):
		changed.emit()


## Returns every minion count to automatic.
func clear_minion_counts() -> void:
	player_state["minions"] = {}
	changed.emit()


## Sets the stacks of a buff on you by hand (0 included: «never on me»); the automatic value no longer applies.
func set_player_buff(ailment_id: int, stacks: float) -> void:
	var buffs: Dictionary = player_state.get("buffs", {}) as Dictionary
	buffs[ailment_id] = maxf(stacks, 0.0)
	player_state["buffs"] = buffs
	changed.emit()


## Returns one buff on you to the average kept while the selected skill is used (EnemyAilments.buffs).
func clear_player_buff(ailment_id: int) -> void:
	var buffs: Dictionary = player_state.get("buffs", {}) as Dictionary
	if buffs.erase(ailment_id):
		player_state["buffs"] = buffs
		changed.emit()


## Returns every buff on you to its automatic value.
func clear_player_buffs() -> void:
	player_state["buffs"] = {}
	changed.emit()
