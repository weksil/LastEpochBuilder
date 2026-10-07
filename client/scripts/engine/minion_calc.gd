class_name MinionCalc

## Summoned minions: snapshot of player stats by the SummonEntityOnDeath rule (research/07d §1.1), innate stats,
## damage components of their abilities and defence rows (docs/ENGINE.md §9.4).

## Player stats handled by the summoner itself, never transferred (HealthGain, WardGain, ManaGain, HasteOnHit, ChanceToCast*).
const SKIPPED_PROPERTIES: Array[int] = [38, 39, 40, 50, 126, 127]
const TYPE_NAMES: Array[String] = ["Physical", "Fire", "Cold", "Lightning", "Necrotic", "Void", "Poison"]

static var _minions: Array[Dictionary] = []
static var _abilities: Dictionary = {}  # ability name -> record (abilities.json)
static var _loaded: bool = false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data_dir: String = LE.game_data_dir()
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


## AbilityProperties of a summon that are stats of its minions (ability_property_fields_c.json, AbilityStatsMutatorManager
## fields: addedCritChanceForSkeletons, increasedSummonSkeletonDamage, physicalPenetrationForSkeletons,
## poisonPenetrationForSkeletons, summonSkeletonAddedArmor, summonSkeletonIncAttackSpeed / IncCastSpeed /
## IncCooldownRecoverySpeed, addedCritChanceForSkeletonMages, increasedSkeletonMageDamage): summon name ->
## {id, index, props: [{special, stat (SP name), tags, mod}]}.
const MINION_PROPERTIES: Dictionary = {
	"SummonSkeleton": {"id": "summonSkeleton", "index": 120, "props": [
		{"special": 0, "stat": "CriticalChance", "mod": "added"},
		{"special": 3, "stat": "Damage", "mod": "increased"},
		{"special": 7, "stat": "Penetration", "tags": "Physical", "mod": "added"},
		{"special": 8, "stat": "Penetration", "tags": "Poison", "mod": "added"},
		{"special": 16, "stat": "Armour", "mod": "added"},
		{"special": 17, "stat": "AttackSpeed", "mod": "increased"},
		{"special": 18, "stat": "CastSpeed", "mod": "increased"},
		{"special": 19, "stat": "IncreasedCooldownRecoverySpeed", "mod": "added"},
	]},
	"SummonMage": {"id": "summonMage", "index": 291, "props": [
		{"special": 0, "stat": "CriticalChance", "mod": "added"},
		{"special": 5, "stat": "Damage", "mod": "increased"},
	]},
}


## Minion mods from MINION_PROPERTIES of the summon (passives, items, uniques; ShadowCalc.ability_property sums them).
static func property_mods(build: Node, summon_name: String) -> Array[StatMod]:
	var out: Array[StatMod] = []
	var spec: Dictionary = MINION_PROPERTIES.get(summon_name, {})
	for prop: Dictionary in spec.get("props", []):
		var pp: Dictionary = ShadowCalc.ability_property(build, str(spec["id"]), int(spec["index"]), int(prop["special"]))
		var sp: int = GameData.sp_id(str(prop["stat"]))
		if float(pp["value"]) == 0.0 or sp < 0:
			continue
		out.append(StatMod.make(sp, str(prop["mod"]), float(pp["value"]), LE.tag_mask(str(prop.get("tags", ""))),
			", ".join(pp["lines"]), 0))
	return out


## The AbilityProperty of a passive / item effect is counted for minions (MINION_PROPERTIES) or summon limits
## (MinionCount.LIMIT_PROPERTIES).
static func handles_effect(effect: Dictionary) -> bool:
	var stat: Variant = effect.get("stat")
	if not stat is Dictionary or not (stat as Dictionary).has("abilityID"):
		return false
	var id: String = str(stat["abilityID"])
	var special: int = int(str(stat.get("abilityPropertyIndex", "-1")))
	for spec: Dictionary in MINION_PROPERTIES.values():
		if str(spec["id"]) == id:
			for prop: Dictionary in spec["props"]:
				if int(prop["special"]) == special:
					return true
	for list: Array in MinionCount.LIMIT_PROPERTIES.values():
		for prop: Dictionary in list:
			if str(prop["id"]) == id and int(prop["special"]) == special:
				return true
	return false


## Minion record by actor name ({} if none).
static func minion_by_actor(actor: String) -> Dictionary:
	_load()
	for rec: Dictionary in _minions:
		if str(rec.get("actorName", "")) == actor:
			return rec
	return {}


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
	copy.on_curse_hit = mod.on_curse_hit
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
		# with no ability index (idx == 0) there is nothing to compare an extra with: the usual rules below decide
		if idx != 0 and mod.extra != 0 and mod.extra != idx:
			store.add(_copy(mod, mod.tags, mod.extra, LE.t("Player → minion (as is): %s") % mod.source))
		elif (mod.tags & LE.MINION) != 0 or (is_totem and (mod.tags & LE.TOTEM) != 0) or (idx != 0 and mod.extra == idx):
			store.add(_copy(mod, mod.tags & ~(LE.MINION | LE.TOTEM), 0, LE.t("Player → minion: %s") % mod.source))
	for stat: Variant in minion.get("innateStats", []):
		if not stat is Dictionary:
			continue
		var innate := StatMod.new()
		innate.property = int(stat.get("property", 0))
		innate.added = float(stat.get("added", 0.0))
		innate.increased = float(stat.get("increased", 0.0))
		for m: Variant in stat.get("more", []):
			innate.more.append(float(m))
		innate.source = LE.t("Minion: innate")
		store.add(innate)
	for mod: Variant in minion_mods:
		if mod is StatMod:
			store.add(mod)
	return store


## Use duration of a minion ability: its castSpeedOverrides entry, else the ability's own, else the first override.
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
	var own: float = float(ability.get("useDuration", 0.0))
	return own if own > 0.0 else first


## Most uses per second the charges or the cooldown of a minion ability allow (the minion record's ability entry, else
## abilities.json, plus addedCharges / addedChargeRegen of the minion's mutators aimed at it), sped up by the minion's
## cooldown recovery; INF when the ability has neither.
static func _use_cap(minion: Dictionary, ability: Dictionary, store: StatStore) -> float:
	var rec: Dictionary = ability
	for entry: Variant in minion.get("abilities", []):
		if entry is Dictionary and entry.get("ability") == ability.get("name"):
			rec = entry
	var charges: float = _num_or_zero(rec.get("maxCharges"))
	var regen: float = _num_or_zero(rec.get("chargesGainedPerSecond"))
	var cooldown: float = _num_or_zero(rec.get("cooldown"))
	var mutators: Variant = minion.get("mutators", {})
	if mutators is Dictionary:
		for list: Variant in (mutators as Dictionary).values():
			for m: Variant in list:
				if m is Dictionary and m.get("abilityRef") == ability.get("name"):
					var nz: Dictionary = m.get("nonZero", {})
					charges += float(nz.get("addedCharges", 0.0))
					regen += float(nz.get("addedChargeRegen", 0.0))
	var cap: float = INF
	if charges > 0.0 and regen > 0.0:
		cap = regen
	elif cooldown > 0.0:
		cap = 1.0 / cooldown
	if is_inf(cap):
		return cap
	var cdr: int = GameData.sp_id("IncreasedCooldownRecoverySpeed")
	if cdr >= 0:
		var q: StatQuery = store.query(cdr, int(ability.get("tags", 0)))
		cap *= maxf(1.0 + q.added + q.increased, 0.0)
	return cap


static func _num_or_zero(v: Variant) -> float:
	return 0.0 if v == null else float(v)


static func _first_damage(rec: Dictionary) -> Dictionary:
	var list: Variant = rec.get("damage", [])
	if list is Array and not list.is_empty() and list[0] is Dictionary:
		return list[0]
	return {}


## Damage components (SkillComponents format, kind "minion") of every minion summoned by the ability; the number of each
## minion is MinionCount (the Conditions tab, else the summon limit; a summon whose tree chooses the minions — Summon
## Skeleton, Summon Skeletal Mage — splits its count between the types of its rotation). `actor_mods`: {actor: mods} of
## one minion type only.
static func components(player_store: StatStore, summon_ab: Dictionary, minion_mods: Array, build: Node,
		actor_mods: Dictionary = {}) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	var entries: Array[Array] = []  # [minion record, count]
	var summon_name: String = str(summon_ab.get("name", ""))
	if MinionCount.GROUPS.has(summon_name):
		for m: Dictionary in MinionCount.members(build, summon_name):
			var rec: Dictionary = minion_by_actor(str(m["actor"]))
			if not rec.is_empty() and float(m["count"]) > 0.0:
				entries.append([rec, float(m["count"])])
	else:
		for minion: Dictionary in minions_for(summon_name):
			entries.append([minion, MinionCount.of_minion(build, minion, summon_name)])
	# the property mods do not depend on the minion
	var prop_mods: Array = property_mods(build, summon_name)
	for item: Array in entries:
		var minion: Dictionary = item[0]
		var mods: Array = minion_mods.duplicate()
		mods.append_array(actor_mods.get(str(minion.get("actorName", "")), []))
		mods.append_array(prop_mods)
		var store: StatStore = minion_store(player_store, summon_ab, minion, mods)
		var names: Array = (minion.get("abilityList", []) as Array).duplicate()
		if names.is_empty():
			for inline: Variant in minion.get("abilities", []):
				if inline is Dictionary:
					names.append(inline.get("ability", ""))
		var count: float = float(item[1])
		# the minion AI (UsingMultipleAbilitiesAI.chooseAbility) takes the first ability of its list that is not on cooldown
		# and has a charge: abilities with a cooldown / charges are used whenever ready, the first one without takes all
		# the remaining time, the ones after it are never used (the target is assumed within range of every ability, D?)
		var free: float = 1.0
		var order: int = 0
		for ab_name: Variant in names:
			if free <= 0.0:
				break
			var ability: Dictionary = _abilities.get(str(ab_name), {})
			var duration: float = _use_duration(minion, ability)
			if ability.is_empty() or duration <= 0.0:
				continue
			order += 1
			var tags: int = int(ability.get("tags", 0))
			var is_cast: bool = (tags & LE.SPELL) != 0 or int(ability.get("speedScaler", 2)) == 3
			var speed_q: StatQuery = store.query(LE.CAST_SPEED if is_cast else LE.ATTACK_SPEED, tags)
			var speed: float = (1.0 + speed_q.added) * (1.0 + speed_q.increased) * speed_q.more
			var per_second: float = speed * 1.1 / duration
			var cap: float = _use_cap(minion, ability, store)
			var rate: float = free * per_second
			if not is_inf(cap):
				rate = minf(cap, rate)
			var share: float = rate / per_second if per_second > 0.0 else 0.0
			free -= share
			var entry: Dictionary = _first_damage(ability)
			if entry.is_empty() or rate <= 0.0:
				continue
			var limit_text: String = "" if is_inf(cap) else LE.t(", limited to %s/s by its cooldown or charges") % LE.fmt_num(cap)
			result.append({
				"name": "%s: %s" % [minion.get("actorName", "?"), ability.get("abilityName", ab_name)],
				"kind": "minion", "ab": ability, "base": entry, "per_use": 0.0,
				"rate": rate * count, "store": store,
				"note": LE.t("×%s minions, %s uses/s each (priority %d, %s of the time%s)") % [LE.fmt_num(count), LE.fmt_num(rate),
					order, LE.fmt_pct(share), limit_text],
			})
	return result


static func _defence_base(label: String, base: float, q: StatQuery, extra_text: String = "") -> Dictionary:
	var value: float = (base + q.added) * (1.0 + q.increased) * q.more
	var head: String = LE.t("(%s base + %s) × (1 + %s) × %s = %s%s") % [
		LE.fmt_num(base), LE.fmt_num(q.added), LE.fmt_pct(q.increased), LE.fmt_num(q.more), LE.fmt_num(value), extra_text]
	return {"label": label, "text": str(LE.round_half_even(value)), "breakdown": head + "\n" + _mods_text(q), "value": value}


## Rows {label, text, breakdown}: health, armour, 7 resistances, damage taken multiplier.
static func defence_rows(stats: StatStore, minion: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var health: Dictionary = minion.get("health", {})
	rows.append(_defence_base(LE.t("Minion health"), float(health.get("maxHealth", 0.0)), stats.query_untagged(LE.HEALTH)))

	var protection: Dictionary = minion.get("protection", {})
	var shred: float = stats.sum_added_untagged([LE.NEG_ARMOUR])
	var armour_row: Dictionary = _defence_base(LE.t("Armor"), float(protection.get("armour", 0.0)), stats.query_untagged(LE.ARMOUR),
		(LE.t(" − %s (shred)") % LE.fmt_num(shred)) if shred != 0.0 else "")
	armour_row["value"] = float(armour_row["value"]) - shred
	armour_row["text"] = str(LE.round_half_even(float(armour_row["value"])))
	rows.append(armour_row)

	for i in range(LE.RES_SP.size()):
		var q: StatQuery = Enemy.resistance(stats, i)
		rows.append({"label": LE.t("Resistance: %s") % LE.t(TYPE_NAMES[i]), "text": LE.fmt_pct(q.added), "breakdown": q.breakdown()})

	var taken: StatQuery = stats.query(LE.DAMAGE_TAKEN, 0)
	var taken_pet: StatQuery = stats.query(LE.DAMAGE_TAKEN, LE.PET_RESISTED)
	var taken_value: float = (1.0 + taken.increased) * taken.more
	var taken_pet_value: float = (1.0 + taken_pet.increased) * taken_pet.more
	rows.append({
		"label": LE.t("Damage taken"), "text": LE.t("×%s (with the PetResisted tag: ×%s)") % [LE.fmt_num(taken_value), LE.fmt_num(taken_pet_value)],
		"breakdown": LE.t("(1 + inc) × Π more = %s\n%s\nWith the PetResisted tag: %s\n%s") % [
			LE.fmt_num(taken_value), _mods_text(taken), LE.fmt_num(taken_pet_value), _mods_text(taken_pet)],
	})
	return rows


static func _mods_text(q: StatQuery) -> String:
	var lines: Array[String] = []
	for mod: StatMod in q.mods:
		lines.append(mod.describe())
	return "\n".join(lines)
