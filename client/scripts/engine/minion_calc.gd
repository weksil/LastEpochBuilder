class_name MinionCalc

## Summoned minions: snapshot of player stats by the SummonEntityOnDeath rule (research/07d §1.1), innate stats,
## damage components of their abilities and defence rows (docs/ENGINE.md §9.4).

## Player stats handled by the summoner itself, never transferred (HealthGain, WardGain, ManaGain, HasteOnHit, ChanceToCast*).
const SKIPPED_PROPERTIES: Array[int] = [38, 39, 40, 50, 126, 127]
const TYPE_NAMES: Array[String] = ["Физический", "Огонь", "Холод", "Молния", "Некротический", "Void", "Яд"]

static var _minions: Array[Dictionary] = []
static var _abilities: Dictionary = {}  # ability name -> record (abilities.json)
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data_dir: String = ProjectSettings.globalize_path("res://").path_join("../research/data/game").simplify_path()
	var stats: Variant = _read_json(data_dir.path_join("minion_base_stats.json"))
	if stats is Dictionary:
		for rec: Variant in stats.get("data", []):
			if rec is Dictionary:
				_minions.append(rec)
	var abilities: Variant = _read_json(data_dir.path_join("abilities.json"))
	if abilities is Array:
		for rec: Variant in abilities:
			if rec is Dictionary:
				var rec_name: String = str(rec.get("name", ""))
				if not _abilities.has(rec_name):
					_abilities[rec_name] = rec


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Minion records summoned by the ability (`summonedBy` contains its `name`).
static func minions_for(ability_name: String) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for rec: Dictionary in _minions:
		if (rec.get("summonedBy", []) as Array).has(ability_name):
			result.append(rec)
	return result


static func _copy(mod: StatMod, tags: int, extra: int, source: String) -> StatMod:
	var copy := StatMod.new()
	copy.property = mod.property
	copy.special = mod.special
	copy.tags = tags
	copy.extra = extra
	copy.added = mod.added
	copy.increased = mod.increased
	copy.more = mod.more.duplicate()
	copy.source = source
	return copy


static func _summon_id(summon_ab: Dictionary) -> int:
	var enum_rec: Variant = summon_ab.get("abilityIDEnum")
	if enum_rec is Dictionary:
		return int(enum_rec.get("value", 0))
	return 0


## Minion stats: transferred player mods (07d §1.1) + innate stats + tree mods (as is).
static func minion_store(player_store: StatStore, summon_ab: Dictionary, minion: Dictionary, minion_mods: Array) -> StatStore:
	var store := StatStore.new()
	var idx: int = _summon_id(summon_ab)
	var is_totem: bool = (int(summon_ab.get("tags", 0)) & LE.TOTEM) != 0
	for mod: StatMod in player_store.all_mods():
		if SKIPPED_PROPERTIES.has(mod.property):
			continue
		if mod.extra != 0 and mod.extra != idx:
			store.add(_copy(mod, mod.tags, mod.extra, "Игрок → миньон (как есть): %s" % mod.source))
		elif (mod.tags & LE.MINION) != 0 or (is_totem and (mod.tags & LE.TOTEM) != 0) or (idx != 0 and mod.extra == idx):
			store.add(_copy(mod, mod.tags & ~(LE.MINION | LE.TOTEM), 0, "Игрок → миньон: %s" % mod.source))
	for stat: Variant in minion.get("innateStats", []):
		if not stat is Dictionary:
			continue
		var innate := StatMod.new()
		innate.property = int(stat.get("property", 0))
		innate.added = float(stat.get("added", 0.0))
		innate.increased = float(stat.get("increased", 0.0))
		for m: Variant in stat.get("more", []):
			innate.more.append(float(m))
		innate.source = "Миньон: врождённо"
		store.add(innate)
	for mod: Variant in minion_mods:
		if mod is StatMod:
			store.add(mod)
	return store


static func _minion_count(minion: Dictionary, count_input: float) -> float:
	if count_input > 0.0:
		return count_input
	var settings: Array = minion.get("summonSettings", [])
	if not settings.is_empty() and settings[0] is Dictionary:
		var first: Dictionary = settings[0]
		var limit: float = float(first.get("limit", 0.0))
		return limit if limit > 0.0 else maxf(float(first.get("numberToSummon", 1.0)), 1.0)
	return 1.0


static func _use_duration(minion: Dictionary, ability: Dictionary) -> float:
	var first: float = 0.0
	for entry: Variant in minion.get("castSpeedOverrides", []):
		if not entry is Dictionary:
			continue
		var duration: float = float(entry.get("useDuration", 0.0))
		if entry.get("ability") == ability.get("name") and duration > 0.0:
			return duration
		if first <= 0.0:
			first = duration
	if first > 0.0:
		return first
	return float(ability.get("useDuration", 0.0))


static func _first_damage(rec: Dictionary) -> Dictionary:
	var list: Variant = rec.get("damage", [])
	if list is Array and not list.is_empty() and list[0] is Dictionary:
		return list[0]
	return {}


## Damage components (SkillComponents format, kind "minion") of every minion summoned by the ability.
static func components(player_store: StatStore, summon_ab: Dictionary, minion_mods: Array, count_input: float) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for minion: Dictionary in minions_for(str(summon_ab.get("name", ""))):
		var store: StatStore = minion_store(player_store, summon_ab, minion, minion_mods)
		var names: Array = (minion.get("abilityList", []) as Array).duplicate()
		if names.is_empty():
			for inline: Variant in minion.get("abilities", []):
				if inline is Dictionary:
					names.append(inline.get("ability", ""))
		var count: float = _minion_count(minion, count_input)
		for ab_name: Variant in names:
			var ability: Dictionary = _abilities.get(str(ab_name), {})
			var entry: Dictionary = _first_damage(ability)
			if entry.is_empty():
				continue
			var duration: float = _use_duration(minion, ability)
			if duration <= 0.0:
				continue
			var tags: int = int(ability.get("tags", 0))
			var is_cast: bool = (tags & LE.SPELL) != 0 or int(ability.get("speedScaler", 2)) == 3
			var speed_q: StatQuery = store.query(LE.CAST_SPEED if is_cast else LE.ATTACK_SPEED, tags)
			var speed: float = (1.0 + speed_q.added) * (1.0 + speed_q.increased) * speed_q.more
			var per_second: float = speed * 1.1 / duration
			result.append({
				"name": "%s: %s" % [minion.get("actorName", "?"), ability.get("abilityName", ab_name)],
				"kind": "minion", "ab": ability, "base": entry, "per_use": 0.0,
				"rate": per_second * count, "store": store,
				"note": "×%s миньонов, %s атак/с каждый" % [LE.fmt_num(count), LE.fmt_num(per_second)],
			})
	return result


static func _defence_base(label: String, base: float, q: StatQuery, extra_text: String = "") -> Dictionary:
	var value: float = (base + q.added) * (1.0 + q.increased) * q.more
	var head: String = "(%s база + %s) × (1 + %s) × %s = %s%s" % [
		LE.fmt_num(base), LE.fmt_num(q.added), LE.fmt_pct(q.increased), LE.fmt_num(q.more), LE.fmt_num(value), extra_text]
	return {"label": label, "text": str(LE.round_half_even(value)), "breakdown": head + "\n" + _mods_text(q), "value": value}


## Rows {label, text, breakdown}: health, armour, 7 resistances, damage taken multiplier.
static func defence_rows(minion_store: StatStore, minion: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var health: Dictionary = minion.get("health", {})
	rows.append(_defence_base("Здоровье миньона", float(health.get("maxHealth", 0.0)), minion_store.query_untagged(LE.HEALTH)))

	var protection: Dictionary = minion.get("protection", {})
	var shred: float = minion_store.sum_added_untagged([LE.NEG_ARMOUR])
	var armour_row: Dictionary = _defence_base("Броня", float(protection.get("armour", 0.0)), minion_store.query_untagged(LE.ARMOUR),
		(" − %s (шред)" % LE.fmt_num(shred)) if shred != 0.0 else "")
	armour_row["text"] = str(LE.round_half_even(float(armour_row["value"]) - shred))
	rows.append(armour_row)

	for i in range(LE.RES_SP.size()):
		var q: StatQuery = Enemy.resistance(minion_store, i)
		rows.append({"label": "Сопротивление: %s" % TYPE_NAMES[i], "text": LE.fmt_pct(q.added), "breakdown": q.breakdown()})

	var taken: StatQuery = minion_store.query(LE.DAMAGE_TAKEN, 0)
	var taken_pet: StatQuery = minion_store.query(LE.DAMAGE_TAKEN, LE.PET_RESISTED)
	var taken_value: float = (1.0 + taken.increased) * taken.more
	var taken_pet_value: float = (1.0 + taken_pet.increased) * taken_pet.more
	rows.append({
		"label": "Получаемый урон", "text": "×%s (с тегом PetResisted: ×%s)" % [LE.fmt_num(taken_value), LE.fmt_num(taken_pet_value)],
		"breakdown": "(1 + inc) × Π more = %s\n%s\nС тегом PetResisted: %s\n%s" % [
			LE.fmt_num(taken_value), _mods_text(taken), LE.fmt_num(taken_pet_value), _mods_text(taken_pet)],
	})
	return rows


static func _mods_text(q: StatQuery) -> String:
	var lines: Array[String] = []
	for mod: StatMod in q.mods:
		lines.append(mod.describe())
	return "\n".join(lines)
