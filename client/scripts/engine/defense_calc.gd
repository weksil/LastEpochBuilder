class_name DefenseCalc

## Effective health against one enemy attack (docs/ENGINE.md §10): the damage pipeline of ProtectionClass.ApplyDamage
## (research/06c §1) run backwards and forwards like Path of Building's "Maximum hit taken" and "Total EHP".
## The attack is a boss preset from research/data/game/boss_attacks.json, scaled to the area level and the enemy
## corruption of the Conditions tab, or a custom hit typed by the user.

const CUSTOM_KEY: String = "custom"
## Boss presets are named "<boss>: <attack>"; the attack name drops the boss's internal ability prefix.
const BOSS_ATTACKS_FILE: String = "boss_attacks.json"
const ACTOR_SCALER_FILE: String = "actor_scaler.json"
## ProtectionClass constants (research/06c §0).
const RES_CAP: float = 0.75
const GLANCING_MITIGATION: float = 0.35
const ENDURANCE_CAP: float = 0.6
const PARRY_CAP: float = 0.75
const MANA_PER_DAMAGE: float = 5.0
## Hit damage variance Uniform(0.8, 1.2) (06c §1 step 5.5).
const VARIANCE_MAX: float = 1.2
## Hits counted by the "hits to die" simulation before giving up (the attack cannot kill).
const MAX_HITS: int = 100000

static var _presets: Array[Dictionary] = []
static var _presets_loaded: bool = false
static var _scaler: Dictionary = {}


## Defense settings by default (Build.defense): the attack key, area level, the custom hit.
static func default_settings() -> Dictionary:
	return {
		"attack": CUSTOM_KEY,
		"area_level": 100,
		"custom_damage": [1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		"custom_crit_chance": 0.05,
		"custom_crit_multi": 2.0,
	}


# --- presets ----------------------------------------------------------------------------

## Every selectable attack: the custom hit first, then boss attacks grouped by boss (timeline bosses, then pinnacle).
## {key, boss, group, timeline, label, level0, damage: Array[float] (7), is_hit, crit_chance, crit_multi,
##  pen: Array[float] (7), more: float, more_lines: PackedStringArray, interval}
static func presets() -> Array[Dictionary]:
	if not _presets_loaded:
		_presets_loaded = true
		_presets = _load_presets()
	return _presets


static func preset(key: String) -> Dictionary:
	for p: Dictionary in presets():
		if str(p["key"]) == key:
			return p
	return {}


static func _load_presets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path: String = LE.game_data_dir().path_join(BOSS_ATTACKS_FILE)
	if not FileAccess.file_exists(path):
		return out
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not json is Dictionary:
		return out
	for boss: Dictionary in (json as Dictionary).get("data", []):
		var boss_name: String = str(boss.get("actorName", boss.get("actorData", "")))
		var damage_stats: Array[Dictionary] = []
		for stat: Dictionary in boss.get("actorStats", []):
			if int(stat.get("property", -1)) == LE.DAMAGE and not (stat.get("more", []) as Array).is_empty():
				damage_stats.append(stat)
		var seen: Dictionary = {}
		for ability: Dictionary in boss.get("abilities", []):
			# abilities of actors the boss spawns (adds, the Harbingers' Aberroth) use those actors' own stats
			if ability.get("viaActor") != null:
				continue
			var ability_name: String = _attack_name(str(ability.get("name", "")), str(ability.get("abilityName", "")))
			var components: Array = ability.get("components", [])
			for c in range(components.size()):
				var comp: Dictionary = components[c]
				var base: Array[float] = _floats(comp.get("damage", []), 7)
				var total: float = 0.0
				for v: float in base:
					total += v
				if total <= 0.0:
					continue
				var label: String = ability_name
				if components.size() > 1:
					label += " · " + str(comp.get("go", str(c + 1))).get_file()
				if seen.has(label):
					continue
				seen[label] = true
				var is_hit: bool = bool(int(comp.get("isHit", 1)))
				var comp_tags: int = int(comp.get("damageTags", 0)) | (LE.HIT if is_hit else LE.DOT)
				var comp_more: float = 1.0 + float(comp.get("damageModifier", 0.0))
				var lines: PackedStringArray = []
				if not is_equal_approx(comp_more, 1.0):
					lines.append(LE.t("damage modifier of the attack %s") % LE.fmt_pct(comp_more - 1.0))
				# the boss's own Damage MORE stats, matched per damage type like any stat (06a §3)
				var dmg: Array[float] = []
				for i in range(7):
					var m: float = comp_more
					for stat: Dictionary in damage_stats:
						if LE.tags_match(int(stat.get("tags", 0)), comp_tags | LE.DT_TAG[i]):
							for v: Variant in stat["more"]:
								m *= 1.0 + float(v)
					dmg.append(base[i] * m)
				for stat: Dictionary in damage_stats:
					var tag_text: String = SkillCalc._tag_names(int(stat.get("tags", 0))) if int(stat.get("tags", 0)) != 0 else ""
					for v: Variant in stat["more"]:
						lines.append(LE.t("%s: damage more %s%s") % [boss_name, LE.fmt_pct(float(v)), (" (" + tag_text + ")") if tag_text != "" else ""])
				var timing: Dictionary = comp.get("timing", {}) if comp.get("timing") is Dictionary else {}
				out.append({
					"key": "%s|%s|%d" % [str(boss.get("actorData", "")), str(ability.get("name", "")), c],
					"boss": boss_name, "group": str(boss.get("group", "")), "timeline": boss.get("timeline", null),
					"label": label, "level0": int(boss.get("actorLevel", 0)), "base": base, "damage": dmg,
					"is_hit": is_hit, "crit_chance": float(comp.get("critChance", 0.0)),
					"crit_multi": float(comp.get("critMultiplier", 1.0)), "pen": _floats(comp.get("penetration", []), 7),
					"more_lines": lines, "interval": float(timing.get("damageInterval", 0.0)),
				})
	return out


## The ability asset name ("Uber Aterroth 03 Lingering Damage Projectile") tells attacks of one boss apart; the display
## name ("Spirit Decay") is only a fallback, several attacks share it.
static func _attack_name(asset_name: String, display_name: String) -> String:
	return asset_name if asset_name != "" else display_name


static func _floats(raw: Variant, size: int) -> Array[float]:
	var out: Array[float] = []
	out.resize(size)
	out.fill(0.0)
	if raw is Array:
		for i in range(mini(size, (raw as Array).size())):
			out[i] = float(raw[i])
	return out


# --- enemy scaling ------------------------------------------------------------------------

static func _scaler_tables() -> Dictionary:
	if _scaler.is_empty():
		var path: String = LE.game_data_dir().path_join(ACTOR_SCALER_FILE)
		var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if json is Dictionary:
			_scaler = (json as Dictionary).get("data", {}).get("tables", {})
	return _scaler


## ActorScaler damage MOREs for a monster authored at level0 spawned at `level` (research/06c §7):
## (damageModifier[L] + 1)·1.06 and originalDamageApproximation[L] / originalDamageApproximation[L0].
## Returns {level_more, original_more}.
static func level_scaling(level: int, level0: int) -> Dictionary:
	var t: Dictionary = _scaler_tables()
	var dm: Array = t.get("damageModifier", [])
	var oda: Array = t.get("originalDamageApproximation", [])
	var l: int = clampi(level, 0, 100)
	var l0: int = clampi(level0, 0, 100)
	var level_more: float = (float(dm[l]) + 1.0) * 1.06 if l < dm.size() else 1.0
	var original_more: float = 1.0
	if l < oda.size() and l0 < oda.size() and float(oda[l0]) > 0.0:
		original_more = float(oda[l]) / float(oda[l0])
	return {"level_more": level_more, "original_more": original_more}


## Enemy penetration from the area level against players: 1% per level, max 75% (06c §2.4, GetPenetrationForZoneLevel).
static func zone_penetration(area_level: int) -> float:
	return minf(0.01 * float(maxi(area_level, 0)), 0.75)


## The attack as it lands on the player before any defense: per-type damage, crit and penetration, with the lines that
## explain the scaling. {damage: Array[float], total, is_hit, crit_chance, crit_multi, pen: Array[float], lines, label}
static func enemy_attack(build: Node) -> Dictionary:
	var settings: Dictionary = settings_of(build)
	var area_level: int = int(settings["area_level"])
	var key: String = str(settings["attack"])
	var p: Dictionary = preset(key) if key != CUSTOM_KEY else {}
	var lines: PackedStringArray = []
	var damage: Array[float] = []
	var is_hit: bool = true
	var crit_chance: float = 0.0
	var crit_multi: float = 1.0
	var pen: Array[float] = _floats([], 7)
	var label: String = LE.t("Custom hit")
	var interval: float = 0.0
	if p.is_empty():
		damage = _floats(settings["custom_damage"], 7)
		crit_chance = float(settings["custom_crit_chance"])
		crit_multi = float(settings["custom_crit_multi"])
		lines.append(LE.t("Custom hit: the numbers are the final enemy damage, no level or corruption scaling"))
	else:
		label = "%s: %s" % [str(p["boss"]), str(p["label"])]
		is_hit = bool(p["is_hit"])
		crit_chance = float(p["crit_chance"])
		crit_multi = float(p["crit_multi"])
		pen = (p["pen"] as Array[float]).duplicate()
		interval = float(p["interval"])
		var scaling: Dictionary = level_scaling(area_level, int(p["level0"]))
		var corruption: int = int(build.enemy.get("corruption", 0))
		var corr: Dictionary = Enemy.corruption_more(build.enemy)
		var corr_more: float = 1.0 + (float(corr["hit"]) if is_hit else float(corr["dot"]))
		# a repeating damage area deals its damage every damageInterval seconds: shown per second
		var per_second: float = 1.0 / interval if not is_hit and interval > 0.0 else 1.0
		var mult: float = float(scaling["level_more"]) * float(scaling["original_more"]) * corr_more * per_second
		var base: Array[float] = p["base"]
		var base_parts: PackedStringArray = []
		for i in range(7):
			if base[i] > 0.0:
				base_parts.append("%s %s" % [LE.t(LE.DT_NAME[i]), LE.fmt_num(base[i])])
		lines.append(LE.t("Base damage of the attack: %s (boss authored at level %d)") % [", ".join(base_parts), int(p["level0"])])
		for line: String in p["more_lines"]:
			lines.append("× " + line)
		lines.append(LE.t("× %s level damage modifier: (damageModifier[%d] + 1)·1.06") % [LE.fmt_num(float(scaling["level_more"])), area_level])
		lines.append(LE.t("× %s damage approximation: original[%d] / original[%d]") % [LE.fmt_num(float(scaling["original_more"])), area_level, int(p["level0"])])
		lines.append(LE.t("× %s corruption %d: 1 + %s·f(c), f(c) = %s") % [LE.fmt_num(corr_more), corruption,
			"0.01" if is_hit else "0.005", LE.fmt_num(Enemy.corruption_power(corruption))])
		if per_second != 1.0:
			lines.append(LE.t("× %s: damage every %s s, shown per second") % [LE.fmt_num(per_second), LE.fmt_num(interval)])
		var scaled: Array[float] = p["damage"]
		for i in range(7):
			damage.append(scaled[i] * mult)
	var total: float = 0.0
	for v: float in damage:
		total += v
	return {"damage": damage, "total": total, "is_hit": is_hit, "crit_chance": crit_chance, "crit_multi": crit_multi,
		"pen": pen, "lines": lines, "label": label, "interval": interval}


## Build.defense merged over the defaults (older builds have no defense settings).
static func settings_of(build: Node) -> Dictionary:
	return normalized(build.get("defense"))


## Saved defense settings (any numbers, e.g. parsed JSON) over the defaults, with fixed value types.
static func normalized(saved: Variant) -> Dictionary:
	var settings: Dictionary = default_settings()
	if saved is Dictionary:
		settings.merge(saved, true)
	settings["attack"] = str(settings["attack"])
	settings["area_level"] = clampi(int(settings["area_level"]), 1, 100)
	settings["custom_damage"] = _floats(settings["custom_damage"], 7)
	settings["custom_crit_chance"] = float(settings["custom_crit_chance"])
	settings["custom_crit_multi"] = float(settings["custom_crit_multi"])
	return settings


# --- player defenses ----------------------------------------------------------------------

## The player's defensive layers at the area level (06c §0, §2). Every value with its breakdown.
static func player_layers(build: Node, store: StatStore, area_level: int) -> Dictionary:
	var health_tags: int = SkillCalc._health_tags(build)
	var moving: bool = bool(build.player_state.get("moving", false))
	var health: float = float(LE.round_half_even(store.query_untagged(LE.HEALTH).value()))
	var mana: float = float(LE.round_half_even(store.query_untagged(LE.MANA).value()))
	var armour: float = store.query_untagged(LE.ARMOUR).value() - store.sum_added_untagged([LE.NEG_ARMOUR])
	var dodge_rating: float = store.query_untagged(LE.DODGE_RATING).value()
	var block_q: StatQuery = store.query_untagged(LE.BLOCK_CHANCE)
	var block_eff: float = store.query_untagged(LE.BLOCK_EFFECTIVENESS).value()
	var glancing: float = store.query_untagged(LE.GLANCING).value()
	var endurance: float = minf(ENDURANCE_CAP, store.sum_added_untagged([LE.ENDURANCE]))
	var res: Array[float] = []
	var taken_hit: Array[float] = []
	var taken_dot: Array[float] = []
	for i in range(7):
		res.append(Enemy.resistance(store, i).value())
		taken_hit.append(_taken(store, LE.HIT | LE.DT_TAG[i] | health_tags))
		taken_dot.append(_taken(store, LE.DOT | LE.DT_TAG[i] | health_tags))
	var buff_q: StatQuery = store.query_untagged(LE.DAMAGE_TAKEN_BUFF)
	var buff: float = (buff_q.more - 1.0) * (1.0 + maxf(buff_q.increased, -1.0))
	var moving_q: StatQuery = store.query_untagged(LE.MORE_DAMAGE_TAKEN_WHILE_MOVING)
	var moving_more: float = ((1.0 + moving_q.increased) * moving_q.more - 1.0) if moving else 0.0
	return {
		"health": health, "mana": mana,
		"ward": maxf(0.0, float(build.player_state.get("ward", 0))),
		"armour": armour, "armour_dot": minf(store.sum_added_untagged([LE.ARMOUR_VS_DOT]), 1.0),
		"dodge": CharacterCalc._compute_dodge_chance(dodge_rating, area_level), "dodge_rating": dodge_rating,
		"block": maxf(block_q.value(), 0.0), "block_eff": block_eff,
		"block_dr": CharacterCalc.block_mitigation(block_eff, area_level),
		"glancing": maxf(glancing, 0.0), "parry": clampf(store.query_untagged(LE.PARRY).value(), 0.0, PARRY_CAP),
		"endurance": maxf(endurance, 0.0), "threshold": CharacterCalc._compute_endurance_threshold(store),
		"crit_avoid": store.sum_added_untagged([LE.CRIT_AVOIDANCE]) * store.query_untagged(LE.CRIT_AVOIDANCE).more,
		"crit_taken": store.sum_added_untagged([LE.CHANCE_TO_BE_CRIT]),
		"crit_reduced": store.sum_added_untagged([LE.REDUCED_CRIT_BONUS_TAKEN]),
		"mana_before_health": clampf(store.sum_added_untagged([LE.MANA_BEFORE_HEALTH]), 0.0, 1.0),
		"mana_before_ward": clampf(store.sum_added_untagged([LE.MANA_BEFORE_WARD]), 0.0, 1.0),
		"res": res, "taken_hit": taken_hit, "taken_dot": taken_dot,
		"buff": buff, "moving_more": moving_more, "moving": moving,
		"health_regen": store.query_untagged(LE.HEALTH_REGEN).value(),
		"ward_regen": store.query_untagged(LE.WARD_REGEN).value(),
		"ward_threshold": store.query_untagged(LE.WARD_DECAY_THRESHOLD).value(),
		"ward_retention": store.query_untagged(LE.WARD_RETENTION).value(),
	}


## Damage taken multiplier (1 + Σadded)·(1 + Σinc)·Πmore (06c §2.10).
static func _taken(store: StatStore, tags: int) -> float:
	var q: StatQuery = store.query(LE.DAMAGE_TAKEN, tags)
	return (1.0 + q.added) * (1.0 + q.increased) * q.more


## Share of one damage type that reaches the pool, without avoidance, block, glancing and crit (06c §1 step 7):
## resistance with penetration, damage taken, moving, armor (hits; DoT only by the SP 118 share), damage taken buff.
## {mult, lines}
static func type_multiplier(layers: Dictionary, i: int, is_hit: bool, pen: float, area_level: int) -> Dictionary:
	var lines: PackedStringArray = []
	var res: float = float(layers["res"][i])
	var zone: float = zone_penetration(area_level)
	var res_mult: float = 1.0 - minf(res, RES_CAP) + zone + pen
	lines.append(LE.t("Resistance: 1 − min(%s, 75%%) + %s area penetration + %s attack penetration = ×%s") % [
		LE.fmt_pct(res), LE.fmt_pct(zone), LE.fmt_pct(pen), LE.fmt_num(res_mult)])
	var taken: float = float(layers["taken_hit" if is_hit else "taken_dot"][i])
	lines.append(LE.t("Damage taken: ×%s") % LE.fmt_num(taken))
	var mult: float = res_mult * taken
	if bool(layers["moving"]) and not is_zero_approx(float(layers["moving_more"])):
		mult *= 1.0 + float(layers["moving_more"])
		lines.append(LE.t("More damage taken while moving: ×%s") % LE.fmt_num(1.0 + float(layers["moving_more"])))
	var armour_dr: float = Enemy.armour_mitigation(float(layers["armour"]), area_level, i != 0)
	if not is_hit:
		armour_dr *= float(layers["armour_dot"])
	mult *= 1.0 - armour_dr
	lines.append(LE.t("Armor %s: ×%s") % [LE.fmt_num(float(layers["armour"])), LE.fmt_num(1.0 - armour_dr)]
		+ ("" if is_hit else LE.t(" (DoT: armor mitigation × %s)") % LE.fmt_pct(float(layers["armour_dot"]))))
	if not is_zero_approx(float(layers["buff"])):
		mult *= 1.0 + float(layers["buff"])
		lines.append(LE.t("Damage taken buff: ×%s") % LE.fmt_num(1.0 + float(layers["buff"])))
	mult = maxf(mult, 0.0)
	lines.append("= ×%s" % LE.fmt_num(mult))
	return {"mult": mult, "lines": lines}


## Chance that an enemy hit crits you and its damage factor (06c §2.8).
static func crit_against(layers: Dictionary, crit_chance: float, crit_multi: float) -> Dictionary:
	var chance: float = clampf(crit_chance + float(layers["crit_taken"]), 0.0, 1.0) * (1.0 - clampf(float(layers["crit_avoid"]), 0.0, 1.0))
	var factor: float = crit_multi
	var r: float = float(layers["crit_reduced"])
	if not is_zero_approx(r) and crit_multi > 1.0:
		factor = maxf(1.0, 1.0 + (1.0 - r) * (crit_multi - 1.0))
	return {"chance": chance, "factor": maxf(factor, 1.0)}


# --- pool ---------------------------------------------------------------------------------

## Pool state at full health: {health, ward, mana}.
static func full_pool(layers: Dictionary) -> Dictionary:
	return {"health": float(layers["health"]), "ward": float(layers["ward"]), "mana": float(layers["mana"])}


## Applies `d` damage that already passed every per-type layer, block and crit (06c §1 steps 10–16) to `pool` in place:
## mana before ward, ward, mana before health, endurance under the threshold. Returns the health lost.
static func take_damage(layers: Dictionary, pool: Dictionary, d: float) -> float:
	var pw: float = float(layers["mana_before_ward"])
	if pw > 0.0 and d > 0.0:
		var lost: float = minf(pw * d / MANA_PER_DAMAGE, float(pool["mana"]))
		pool["mana"] = float(pool["mana"]) - lost
		d -= MANA_PER_DAMAGE * lost
	var ward: float = float(pool["ward"])
	if d <= ward:
		pool["ward"] = ward - d
		return 0.0
	var r: float = d - ward
	pool["ward"] = 0.0
	var p: float = float(layers["mana_before_health"])
	if p > 0.0:
		var q: float = r * p / MANA_PER_DAMAGE
		var lost_mana: float = minf(q, float(pool["mana"]))
		pool["mana"] = float(pool["mana"]) - lost_mana
		r -= r * p * (lost_mana / q)
	var e: float = float(layers["endurance"])
	var h: float = float(pool["health"])
	if e > 0.0:
		var t: float = float(layers["threshold"])
		if h - r >= t:
			pass
		elif t > h:
			r = (1.0 - e) * r
		else:
			r = (h - t) + (1.0 - e) * (t - (h - r))
	pool["health"] = h - r
	return r


## Smallest damage (after per-type layers) that kills from a full pool: binary search over take_damage.
static func lethal_damage(layers: Dictionary) -> float:
	if float(layers["health"]) <= 0.0:
		return 0.0
	var lo: float = 0.0
	var hi: float = maxf(1.0, float(layers["health"]) + float(layers["ward"]))
	while not _kills(layers, hi):
		hi *= 2.0
		if hi > 1e12:
			return INF
	for _i in range(60):
		var mid: float = (lo + hi) * 0.5
		if _kills(layers, mid):
			hi = mid
		else:
			lo = mid
	return hi


static func _kills(layers: Dictionary, d: float) -> bool:
	var pool: Dictionary = full_pool(layers)
	take_damage(layers, pool, d)
	return float(pool["health"]) <= 0.0


## Number of identical hits of `d` damage that kill from a full pool (fractional last hit); INF if they never do.
static func hits_to_die(layers: Dictionary, d: float) -> float:
	if d <= 0.0:
		return INF
	var pool: Dictionary = full_pool(layers)
	for n in range(1, MAX_HITS + 1):
		var before: Dictionary = pool.duplicate()
		take_damage(layers, pool, d)
		if float(pool["health"]) <= 0.0:
			# the share of the last hit that was needed, found on the copy of the pool before it
			var lo: float = 0.0
			var hi: float = 1.0
			for _i in range(40):
				var mid: float = (lo + hi) * 0.5
				var trial: Dictionary = before.duplicate()
				take_damage(layers, trial, d * mid)
				if float(trial["health"]) <= 0.0:
					hi = mid
				else:
					lo = mid
			return float(n - 1) + hi
	return INF


## Ward the regeneration holds against decay (06c §3.2): regen = (q·x² + l·x)/(1 + 0.5·max(retention, −0.9)), x = W − T.
static func ward_equilibrium(layers: Dictionary) -> float:
	var regen: float = float(layers["ward_regen"])
	if regen <= 0.0:
		return 0.0
	var k: float = regen * (1.0 + 0.5 * maxf(float(layers["ward_retention"]), -0.9))
	var q: float = 0.00005
	var l: float = 0.2
	var x: float = (-l + sqrt(l * l + 4.0 * q * k)) / (2.0 * q)
	return maxf(float(layers["ward_threshold"]), 0.0) + x


# --- result -------------------------------------------------------------------------------

## {attack, summary: {ehp, max_hit, hits, taken_share}, sections: [{title, rows: [{label, text, breakdown}]}], notes}
static func compute(build: Node) -> Dictionary:
	var g: Dictionary = BuildMods.global_store(build)
	var store: StatStore = g["store"]
	var settings: Dictionary = settings_of(build)
	var area_level: int = int(settings["area_level"])
	var layers: Dictionary = player_layers(build, store, area_level)
	var attack: Dictionary = enemy_attack(build)
	var is_hit: bool = bool(attack["is_hit"])
	var sections: Array = []
	var notes: Array[String] = []

	# enemy attack
	var attack_rows: Array = []
	attack_rows.append(_row(LE.t("Attack"), str(attack["label"]), ""))
	attack_rows.append(_row(LE.t("Kind"), LE.t("Hit") if is_hit else LE.t("Damage over time"), ""))
	var scale_text: String = "\n".join(attack["lines"])
	var raw_lines: PackedStringArray = []
	for i in range(7):
		var v: float = float(attack["damage"][i])
		if v > 0.0:
			attack_rows.append(_row(LE.t("%s damage") % LE.t(LE.DT_NAME[i]), LE.fmt_num(v), scale_text))
			raw_lines.append("%s %s" % [LE.t(LE.DT_NAME[i]), LE.fmt_num(v)])
	attack_rows.append(_row(LE.t("Total damage per hit") if is_hit else LE.t("Total damage per second"),
		LE.fmt_num(float(attack["total"])), " + ".join(raw_lines)))
	var crit: Dictionary = crit_against(layers, float(attack["crit_chance"]), float(attack["crit_multi"]))
	if is_hit:
		attack_rows.append(_row(LE.t("Enemy crit chance against you"), LE.fmt_pct(float(crit["chance"])),
			LE.t("(%s attack + %s added chance to be crit) × (1 − %s crit avoidance)") % [LE.fmt_pct(float(attack["crit_chance"])),
			LE.fmt_pct(float(layers["crit_taken"])), LE.fmt_pct(float(layers["crit_avoid"]))]))
		attack_rows.append(_row(LE.t("Enemy crit multiplier against you"), "×" + LE.fmt_num(float(crit["factor"])),
			LE.t("Attack crit multiplier ×%s, reduced bonus damage taken from crits %s") % [LE.fmt_num(float(attack["crit_multi"])),
			LE.fmt_pct(float(layers["crit_reduced"]))]))
	attack_rows.append(_row(LE.t("Area level"), str(area_level),
		LE.t("Sets the enemy penetration (1% per level, max 75%) and the armor, dodge and block formulas")))
	sections.append({"title": LE.t("Enemy attack"), "rows": attack_rows})

	# per-type mitigation
	var mit_rows: Array = []
	var d_unit: float = 0.0  # damage after per-type layers for one attack
	var shown: Array[int] = []
	for i in range(7):
		if float(attack["damage"][i]) > 0.0:
			shown.append(i)
	var type_mult: Array[float] = []
	for i in range(7):
		var tm: Dictionary = type_multiplier(layers, i, is_hit, float(attack["pen"][i]), area_level)
		type_mult.append(float(tm["mult"]))
		var raw: float = float(attack["damage"][i])
		d_unit += raw * float(tm["mult"])
		if shown.has(i):
			mit_rows.append(_row(LE.t("%s: damage taken") % LE.t(LE.DT_NAME[i]),
				"%s → %s (%s)" % [LE.fmt_num(raw), LE.fmt_num(raw * float(tm["mult"])), LE.fmt_pct(float(tm["mult"]))],
				"\n".join(tm["lines"])))
	var total_raw: float = float(attack["total"])
	mit_rows.append(_row(LE.t("After resistances, armor and damage taken"), LE.fmt_num(d_unit),
		LE.t("%s of the raw %s") % [LE.fmt_pct(d_unit / total_raw if total_raw > 0.0 else 0.0), LE.fmt_num(total_raw)]))
	sections.append({"title": LE.t("Mitigation by damage type"), "rows": mit_rows})

	# avoidance
	var avoid_rows: Array = []
	var expected: float = d_unit
	var exp_lines: PackedStringArray = [LE.t("After per-type layers: %s") % LE.fmt_num(d_unit)]
	if is_hit:
		var dodge: float = clampf(float(layers["dodge"]), 0.0, 1.0)
		var parry: float = float(layers["parry"])
		var glance: float = clampf(float(layers["glancing"]), 0.0, 1.0)
		var block: float = clampf(float(layers["block"]), 0.0, 1.0)
		var block_dr: float = float(layers["block_dr"])
		avoid_rows.append(_row(LE.t("Dodge chance"), LE.fmt_pct(dodge), LE.t("Dodge rating %s at area level %d") % [LE.fmt_num(float(layers["dodge_rating"])), area_level]))
		avoid_rows.append(_row(LE.t("Parry chance"), LE.fmt_pct(parry), LE.t("A parried hit deals no damage; max 75%")))
		avoid_rows.append(_row(LE.t("Glancing blow chance"), LE.fmt_pct(glance), LE.t("A glancing blow takes 35% less damage")))
		avoid_rows.append(_row(LE.t("Block chance"), LE.fmt_pct(block), ""))
		avoid_rows.append(_row(LE.t("Block damage reduction"), LE.fmt_pct(block_dr),
			LE.t("Block effectiveness %s at area level %d") % [LE.fmt_num(float(layers["block_eff"])), area_level]))
		var f_avoid: float = (1.0 - dodge) * (1.0 - parry)
		var f_glance: float = 1.0 - GLANCING_MITIGATION * glance
		var f_block: float = 1.0 - block * block_dr
		var f_crit: float = 1.0 + float(crit["chance"]) * (float(crit["factor"]) - 1.0)
		expected = d_unit * f_avoid * f_glance * f_block * f_crit
		exp_lines.append(LE.t("× %s not dodged and not parried: (1 − %s)·(1 − %s)") % [LE.fmt_num(f_avoid), LE.fmt_pct(dodge), LE.fmt_pct(parry)])
		exp_lines.append(LE.t("× %s glancing: 1 − 35%%·%s") % [LE.fmt_num(f_glance), LE.fmt_pct(glance)])
		exp_lines.append(LE.t("× %s block: 1 − %s·%s") % [LE.fmt_num(f_block), LE.fmt_pct(block), LE.fmt_pct(block_dr)])
		exp_lines.append(LE.t("× %s crit: 1 + %s·(%s − 1)") % [LE.fmt_num(f_crit), LE.fmt_pct(float(crit["chance"])), LE.fmt_num(float(crit["factor"]))])
		exp_lines.append("= %s" % LE.fmt_num(expected))
		avoid_rows.append(_row(LE.t("Average damage per hit"), LE.fmt_num(expected), "\n".join(exp_lines)))
		sections.append({"title": LE.t("Avoidance"), "rows": avoid_rows})

	# pool
	var pool_rows: Array = []
	pool_rows.append(_row(LE.t("Health"), LE.fmt_num(float(layers["health"])), ""))
	pool_rows.append(_row(LE.t("Current ward"), LE.fmt_num(float(layers["ward"])),
		LE.t("Current ward from the fight parameters. Ward your regeneration holds against decay: %s") % LE.fmt_num(ward_equilibrium(layers))))
	pool_rows.append(_row(LE.t("Endurance"), LE.fmt_pct(float(layers["endurance"])),
		LE.t("Less damage taken for the part of a hit below the endurance threshold")))
	pool_rows.append(_row(LE.t("Endurance threshold"), LE.fmt_num(float(layers["threshold"])), ""))
	if float(layers["mana_before_health"]) > 0.0 or float(layers["mana_before_ward"]) > 0.0:
		pool_rows.append(_row(LE.t("Mana"), LE.fmt_num(float(layers["mana"])), LE.t("1 mana absorbs 5 damage")))
		pool_rows.append(_row(LE.t("Damage taken from mana before health"), LE.fmt_pct(float(layers["mana_before_health"])), ""))
		pool_rows.append(_row(LE.t("Damage taken from mana before ward"), LE.fmt_pct(float(layers["mana_before_ward"])), ""))
	sections.append({"title": LE.t("Pool"), "rows": pool_rows})

	# effective health
	var ehp_rows: Array = []
	var lethal: float = lethal_damage(layers)
	var summary: Dictionary = {}
	var pool_text: String = LE.t("Full health %s, ward %s, endurance %s under the threshold %s") % [LE.fmt_num(float(layers["health"])),
		LE.fmt_num(float(layers["ward"])), LE.fmt_pct(float(layers["endurance"])), LE.fmt_num(float(layers["threshold"]))]
	if is_hit:
		var share: float = d_unit / total_raw if total_raw > 0.0 else 0.0
		var max_hit: float = lethal / share if share > 0.0 else INF
		var max_crit_hit: float = max_hit / float(crit["factor"])
		var hits: float = hits_to_die(layers, expected)
		var ehp: float = hits * total_raw
		var worst: float = d_unit * float(crit["factor"]) * VARIANCE_MAX
		ehp_rows.append(_row(LE.t("Damage that kills from full health"), LE.fmt_num(lethal),
			LE.t("After every per-type layer, without avoidance. %s") % pool_text))
		ehp_rows.append(_row(LE.t("Maximum hit taken"), _num(max_hit),
			LE.t("The largest raw hit of this attack's damage mix you survive without dodge, block, glancing or crit:\n%s / %s = %s") % [
			LE.fmt_num(lethal), LE.fmt_pct(share), _num(max_hit)]))
		ehp_rows.append(_row(LE.t("Maximum crit taken"), _num(max_crit_hit),
			LE.t("Maximum hit taken / crit multiplier ×%s") % LE.fmt_num(float(crit["factor"]))))
		ehp_rows.append(_row(LE.t("Worst hit of this attack"), LE.fmt_num(worst),
			LE.t("%s × crit ×%s × variance 1.2, no dodge or block") % [LE.fmt_num(d_unit), LE.fmt_num(float(crit["factor"]))]
			+ ("\n" + LE.t("It kills you from full health") if worst >= lethal else "")))
		ehp_rows.append(_row(LE.t("Hits to die"), _num(hits),
			LE.t("Average hits of %s from a full pool, no regeneration between hits") % LE.fmt_num(expected)))
		ehp_rows.append(_row(LE.t("Effective health"), _num(ehp),
			LE.t("Hits to die × raw damage per hit: %s × %s") % [_num(hits), LE.fmt_num(total_raw)]))
		summary = {"ehp": ehp, "max_hit": max_hit, "hits": hits, "taken": expected / total_raw if total_raw > 0.0 else 0.0,
			"worst": worst, "lethal": lethal, "one_shot": worst >= lethal}
	else:
		var dps_taken: float = d_unit
		var net_health: float = dps_taken - float(layers["health_regen"])
		var seconds: float = (float(layers["health"]) + float(layers["ward"])) / dps_taken if dps_taken > 0.0 else INF
		ehp_rows.append(_row(LE.t("Damage taken per second"), LE.fmt_num(dps_taken), LE.t("Endurance and block do not apply to this calculation of damage over time")))
		ehp_rows.append(_row(LE.t("Net health loss per second"), LE.fmt_num(net_health),
			LE.t("Damage taken per second − health regen %s") % LE.fmt_num(float(layers["health_regen"]))))
		ehp_rows.append(_row(LE.t("Seconds to die"), _num(seconds), LE.t("(Health + ward) / damage taken per second, no regeneration")))
		summary = {"ehp": seconds * total_raw, "max_hit": INF, "hits": seconds, "taken": dps_taken / total_raw if total_raw > 0.0 else 0.0,
			"worst": dps_taken, "lethal": lethal, "one_shot": false}
	sections.append({"title": LE.t("Effective health"), "rows": ehp_rows})

	# maximum hit by damage type, as Path of Building shows it
	var type_rows: Array = []
	for i in range(7):
		var m: float = type_mult[i] if is_hit else float(type_multiplier(layers, i, true, 0.0, area_level)["mult"])
		var mh: float = lethal / m if m > 0.0 else INF
		type_rows.append(_row(LE.t("%s maximum hit") % LE.t(LE.DT_NAME[i]), _num(mh),
			LE.t("%s / ×%s (resistance, area penetration, damage taken, armor)") % [LE.fmt_num(lethal), LE.fmt_num(m)]))
	sections.append({"title": LE.t("Maximum hit taken by damage type"), "rows": type_rows})

	for note: String in ["Damage taken as another type (SP 31–37)", "Dodge and block conversions (to armor, glancing blow, parry, endurance threshold)",
			"Conditional defenses of the character mutator (less damage taken, delayed damage by conditions)",
			"Health, ward and mana regenerated or leeched between hits", "Boss mechanics without damage numbers (adds, phases, arenas)"]:
		notes.append(LE.t(note))
	if not is_hit:
		notes.append(LE.t("Damage over time is shown per second: endurance, block and crit do not apply to it"))
	return {"attack": attack, "summary": summary, "sections": sections, "notes": notes, "layers": layers}


static func _row(label: String, text: String, breakdown: String) -> Dictionary:
	return {"label": label, "text": text, "breakdown": breakdown}


static func _num(x: float) -> String:
	if is_inf(x) or x > 1e12:
		return "∞"
	return LE.fmt_num(x)
