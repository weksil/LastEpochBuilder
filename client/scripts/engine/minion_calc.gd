class_name MinionCalc

## Summoned minions: snapshot of player stats by the SummonEntityOnDeath rule (research/07d §1.1), innate stats,
## damage components of their abilities and defence rows (docs/ENGINE.md §9.4).

## Player stats handled by the summoner itself, never transferred (HealthGain, WardGain, ManaGain, HasteOnHit, ChanceToCast*).
const SKIPPED_PROPERTIES: Array[int] = [38, 39, 40, 50, 126, 127]
## Mutators whose damage field scales the hit of the ability they are aimed at (_mutated_hit): class -> field.
const HIT_DAMAGE_MUTATORS: Dictionary = {"BasicMeleeMutator": "increasedDamage", "RaptorBasicMeleeMutator": "increasedDamage",
	"GenericSabertoothSkillMutator": "moreHitDamage"}
## The ones whose Mutate calls DamageStatsHolder.increaseAllDamage (verified: BasicMeleeMutator, GenericSabertoothSkillMutator): it
## multiplies the 7 base damages and the added damage effectiveness (addedDamageScaling) by 1 + field. Raptor's scales the damage only.
const INCREASE_ALL_DAMAGE_MUTATORS: Array[String] = ["BasicMeleeMutator", "GenericSabertoothSkillMutator"]
## Mutators that scale the use speed of the ability they are aimed at (AbilityMutator.mutateUseSpeed, applied by
## UsingAbility.getSpeedMultiplier after the speed stat and its maximumUseSpeed cap): class -> field.
const USE_SPEED_MUTATORS: Dictionary = {"ComplexGenericMutator": "increasedCastSpeed"}
## UsingAbility.baseUseSpeedMultiplier of a minion: 1.0 (prefab_use_speed.json.gz: serialised 1.0 on the 24 minion actors with a
## UsingAbility component; the UsingAbilityAI / UsingMultipleAbilitiesAI added at runtime keep the constructor value 0x3f800000,
## UsingAbilityAI.c:140; 1.1 is UsingAbilityPlayer's) and the speedScaler value that means "no speed stat".
const MINION_BASE_USE_SPEED: float = 1.0
const SPEED_NO_STAT: int = 54
## Mutators aimed at their ability by the id their Awake sets (AbilityMutator.SetInitialAbility(AbilityID)), without an abilityRef:
## class -> AbilityID value (DeathKnightHarvestMutator.Awake: SetInitialAbility_1(0x127) = DeathKnightHarvest).
const MUTATOR_TARGET_IDS: Dictionary = {"DeathKnightHarvestMutator": 295}
const TYPE_NAMES: Array[String] = ["Physical", "Fire", "Cold", "Lightning", "Necrotic", "Void", "Poison"]
const SUB_HITS_PATH: String = "res://data/minion_sub_hits.json"

static var _minions: Array[Dictionary] = []
static var _abilities: Dictionary = {}  # ability name -> record (abilities.json)
static var _sub_hits_table: Dictionary = {}  # minion ability name -> [{sub, hits, via}] (minion_sub_hits.json)
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
	if FileAccess.file_exists(SUB_HITS_PATH):
		var sub_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(SUB_HITS_PATH))
		if sub_json is Dictionary:
			_sub_hits_table = (sub_json as Dictionary).get("parents", {})


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Sub-abilities that the prefab of a minion ability spawns, with their hits per use (minion_sub_hits.json: CreateAbilityObjectOnDeath
## 1 cast per object death, CastAfterDuration limitCasts * castsPerInterval or floor(lifetime / interval), CastAtRandomPointAfterDuration
## strikes, zone / beam ticks, ExtraProjectiles copies with a shared hit list = 1; research/11 #85).
## [{sub: ability name, hits, via, env}]; env: the count assumes the target takes every strike / stays in the zone (D?).
static func sub_hits(ability_name: String) -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for e: Variant in _sub_hits_table.get(ability_name, []):
		if e is Dictionary:
			out.append(e)
	return out


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
	if stat is Dictionary and str((stat as Dictionary).get("kind", "")) == "player_property":
		return MinionCount.COMPANION_FLAGS.has(int(str((stat as Dictionary).get("playerPropertyIndex", "-1"))))
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


## True if an AbilityProperty (ability index, specialTag) is counted by MINION_PROPERTIES or MinionCount.LIMIT_PROPERTIES.
static func handles_property(ability_index: int, special: int) -> bool:
	for spec: Dictionary in MINION_PROPERTIES.values():
		if int(spec["index"]) == ability_index:
			for prop: Dictionary in spec["props"]:
				if int(prop["special"]) == special:
					return true
	for list: Array in MinionCount.LIMIT_PROPERTIES.values():
		for prop: Dictionary in list:
			if int(prop["index"]) == ability_index and int(prop["special"]) == special:
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
		for cls: Variant in (mutators as Dictionary):
			for m: Variant in (mutators as Dictionary)[cls]:
				if m is Dictionary and _aims_at(str(cls), m, ability):
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


## True if the mutator (a minion record's `mutators[class]` entry) is aimed at the ability: its abilityRef (GenericMutator.Awake),
## else the AbilityID its Awake sets (MUTATOR_TARGET_IDS).
static func _aims_at(cls: String, mutator: Dictionary, ability: Dictionary) -> bool:
	if mutator.has("abilityRef"):
		return mutator["abilityRef"] == ability.get("name")
	var id: int = int(MUTATOR_TARGET_IDS.get(cls, -1))
	var enum_rec: Variant = ability.get("abilityIDEnum")
	return id >= 0 and enum_rec is Dictionary and int((enum_rec as Dictionary).get("value", -2)) == id


## The hit of a minion ability after the damage fields of HIT_DAMAGE_MUTATORS aimed at it (abilityRef). The mutators of
## INCREASE_ALL_DAMAGE_MUTATORS multiply the base damages and addedDamageScaling by 1 + field (DamageStatsHolder.increaseAllDamage).
## The other mutators' damage fields are not applied (their readers are not traced, WolfMeleeMutator has no abilityRef).
static func _mutated_hit(minion: Dictionary, ability: Dictionary, entry: Dictionary) -> Dictionary:
	var mutators: Variant = minion.get("mutators", {})
	if entry.is_empty() or not mutators is Dictionary:
		return entry
	var mult: float = 1.0
	var effectiveness: float = 1.0
	for cls: String in HIT_DAMAGE_MUTATORS:
		for m: Variant in (mutators as Dictionary).get(cls, []):
			if m is Dictionary and m.get("abilityRef") == ability.get("name"):
				var factor: float = 1.0 + float(m.get("nonZero", {}).get(HIT_DAMAGE_MUTATORS[cls], 0.0))
				mult *= factor
				if INCREASE_ALL_DAMAGE_MUTATORS.has(cls):
					effectiveness *= factor
	if mult == 1.0:
		return entry
	var hit: Dictionary = entry.duplicate(true)
	hit["damage"] = (entry.get("damage", []) as Array).map(func(v: Variant) -> float: return float(v) * mult)
	if entry.has("addedDamageScaling"):
		hit["addedDamageScaling"] = float(entry["addedDamageScaling"]) * effectiveness
	return hit


## Product of (1 + field) of the USE_SPEED_MUTATORS entries aimed at the ability (AbilityMutator.mutateUseSpeed).
static func _speed_mutator_factor(minion: Dictionary, ability: Dictionary) -> float:
	var factor: float = 1.0
	var mutators: Variant = minion.get("mutators", {})
	if not mutators is Dictionary:
		return factor
	for cls: String in USE_SPEED_MUTATORS:
		for m: Variant in (mutators as Dictionary).get(cls, []):
			if m is Dictionary and m.get("abilityRef") == ability.get("name"):
				factor *= 1.0 + float(m.get("nonZero", {}).get(USE_SPEED_MUTATORS[cls], 0.0))
	return factor


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
		# the remaining time, the ones after it are never used. The AbilityRangeList gates (pursuit range, health thresholds) are not
		# applied: the calculator has no target distance (research/11 #93)
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
			# UsingAbility.getSpeedMultiplierStat: the ability's speedScaler is the speed stat id (54: no stat, 1 + the
			# increase), the tags do not choose it; getSpeedMultiplier: speedScale = speed * Ability.speedMultiplier *
			# baseUseSpeedMultiplier (1.0 for a minion unless its prefab says otherwise, the 1.1 is the player's constant)
			var scaler: int = int(ability.get("speedScaler", LE.ATTACK_SPEED))
			var speed: float = 1.0
			if scaler != SPEED_NO_STAT:
				var speed_q: StatQuery = store.query(scaler, tags)
				speed = (1.0 + speed_q.added) * (1.0 + speed_q.increased) * speed_q.more
			if int(ability.get("speedScalerAppliedAsIncrease", 0)) == 1:
				speed = maxf(speed - 1.0, 0.0) * float(ability.get("speedScalerEffectiveness", 1.0)) + 1.0
			var max_speed: float = float(ability.get("maximumUseSpeed", 0.0))
			if max_speed > 0.0 and speed > max_speed:
				speed = max_speed
			# the mutators' mutateUseSpeed (x 1 + increasedCastSpeed of the ComplexGenericMutator aimed at the ability) comes after the cap
			speed *= _speed_mutator_factor(minion, ability)
			var speed_scale: float = speed * float(ability.get("speedMultiplier", 1.0)) * MINION_BASE_USE_SPEED
			if speed_scale <= 0.0:
				speed_scale = 0.1
			var per_second: float = speed_scale / duration
			var cap: float = _use_cap(minion, ability, store)
			var rate: float = free * per_second
			if not is_inf(cap):
				rate = minf(cap, rate)
			var share: float = rate / per_second if per_second > 0.0 else 0.0
			free -= share
			# the hits of one use: the ability's own damage[0] and the sub-abilities its prefab spawns (sub_hits)
			var hits: Array[Dictionary] = []
			var entry: Dictionary = _mutated_hit(minion, ability, _first_damage(ability))
			if not entry.is_empty():
				hits.append({"ab": ability, "base": entry, "per_use": 1.0, "sub": false, "env": false,
					"name": "%s: %s" % [minion.get("actorName", "?"), ability.get("abilityName", ab_name)]})
			for sub: Dictionary in sub_hits(str(ability.get("name", ""))):
				var sub_ab: Dictionary = _abilities.get(str(sub["sub"]), {})
				var sub_entry: Dictionary = _mutated_hit(minion, sub_ab, _first_damage(sub_ab))
				if not sub_entry.is_empty():
					hits.append({"ab": sub_ab, "base": sub_entry, "per_use": float(sub["hits"]), "sub": true,
						"env": bool(sub.get("env", false)),
						"name": "%s: %s" % [minion.get("actorName", "?"), sub_ab.get("name", "")]})
			if hits.is_empty() or rate <= 0.0:
				continue
			var limit_text: String = "" if is_inf(cap) else LE.t(", limited to %s/s by its cooldown or charges") % LE.fmt_num(cap)
			for hit: Dictionary in hits:
				var note: String = LE.t("×%s minions, %s uses/s each (priority %d, %s of the time%s)") % [LE.fmt_num(count),
					LE.fmt_num(rate), order, LE.fmt_pct(share), limit_text]
				if hit["sub"]:
					note += LE.t(", ×%s per use of «%s»") % [LE.fmt_num(float(hit["per_use"])), ability.get("abilityName", ab_name)]
					if hit["env"]:
						note += LE.t(" (D?: every strike hits the target / the target stays inside for the whole lifetime of the object)")
				result.append({
					"name": hit["name"], "kind": "minion", "ab": hit["ab"], "base": hit["base"], "per_use": 0.0,
					"rate": rate * count * float(hit["per_use"]), "store": store, "note": note,
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

	var shred: float = stats.sum_added_untagged([LE.NEG_ARMOUR])
	# base armour is 0: BaseStats.ApplyExternalStats overwrites the prefab's serialized armour with (1+inc)·Σadded·Πmore − shred
	var armour_row: Dictionary = _defence_base(LE.t("Armor"), 0.0, stats.query_untagged(LE.ARMOUR),
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
