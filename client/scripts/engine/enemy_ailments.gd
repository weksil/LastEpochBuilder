class_name EnemyAilments

## Enemy ailments the calculation uses (docs/ENGINE.md §9.11). A value set on the Conditions tab (a key of
## Build.enemy.ailments, 0 included) wins; every other ailment takes the average kept on the target:
## - sources: every application of the skill (hits of its components and minions, its zones, threshold strikes) plus the
##   parallel sources of the other bar skills: their minions and zones always, everything of a skill limited by its
##   cooldown (used on cooldown);
## - stacks = min(Σ applications/s × duration, maxInstances); a single-instance ailment counts its uptime;
##   uptime («the enemy has it») = 1 − e^(−rate × duration) (independent applications, refreshed duration);
## - consumption: a skill whose node spends the stacks on its hits (CONSUMERS) wipes them once per use, so with the period
##   P = 1 / uses the average is rate × P / 2 (rate × (T − T² / 2P) when the duration T is shorter);
## - threshold ailments (THRESHOLDS: Shadow Daggers strike at 4 stacks) average (N − 1) / 2 stacks; the strike is a
##   damage component of the skill (threshold_components).
## The effective enemy keeps the stacks in `ailments` and the uptimes in `uptime` (Enemy.presence reads them).
## Buffs on you («Buffs on me», GameData.player_buffs) work the same way (`buffs`): positive ailments of the skill's hits
## (AilmentCalc `self` applications), «on you» prefab ailments per use (ApplyAilmentToCreator), PlayerProperty chances
## (PP_BUFFS: per use of a melee or throwing attack that hits — CharacterMutator.OnFirstMeleeOrThrowingHit —, per enemy hit
## taken, per dodge; the enemy hits come from the Defense tab attack), Dusk Shroud per consumed shadow (CreateShadow 6).

## Marks an enemy dictionary that already holds the automatic values (nested calculations do not add them again).
const APPLIED_KEY: String = "auto_applied"
const CACHE_LIMIT: int = 16
## Kinds of applications that act in parallel with the other skills (minions, zones).
const PARALLEL_KINDS: Array[String] = ["minion", "zone"]
## Flag texts (field_models.json) of nodes whose hits spend the target's stacks -> the ailments they spend.
const CONSUMERS: Dictionary = {
	"Bleed stacks spent, remainder damage dealt instantly": ["Bleed"],
	"Dive Bomb absorbs target bleed for instant damage": ["Bleed"],
	"Large hit absorbs bleeds and deals their damage instantly": ["Bleed"],
	"Hit absorbs ignite stacks and deals instant damage": ["Ignite"],
	"Pass consumes ignites and gives ward": ["Ignite"],
	"Absorbs Ignite stacks (up to 20) and grants Flame Drinker: Phys penetration per stack": ["Ignite"],
	"Hits absorb poison stacks from target": ["Poison"],
}
## PlayerProperty index -> buff and event (CharacterMutator constants playerPropertyDuskShroudWhenHitChance = 97,
## …OnMeleeOrThrowingThatHits = 102, …CrimsonShroudOnMeleeOrThrowingAttackThatHits = 107, duskShroudOnDodgeChance = 470).
const PP_BUFFS: Dictionary = {
	97: {"ailment": "DuskShroud", "event": "hit_taken"},
	102: {"ailment": "DuskShroud", "event": "melee_throwing_use"},
	107: {"ailment": "CrimsonShroud", "event": "melee_throwing_use"},
	470: {"ailment": "DuskShroud", "event": "dodge"},
}
## Skill parameters (field_models.json `param`) that give buffs on you: stacks per use (Smoke Bomb «Moonlight Bomb»: Silver
## Shroud on the initial burst) or stacks per second while you stand in the skill's zone (Smoke Bomb «Smoke Blades»: the
## cloud lasts `zone` seconds, «Lasts 4 seconds»). `spent_by_hits`: one stack is spent by every enemy hit (Silver Shroud
## «Dodge your next hit»; PlayerProperty 534 = chance not to spend it).
const PARAM_BUFFS: Dictionary = {
	"silver_shroud_stacks": {"ailment": "SilverShroud", "per": "use", "spent_by_hits": true},
	"smoke_blades_stacks": {"ailment": "SmokeBlades", "per": "second_in_zone", "zone": 4.0},
}
const KEEP_SILVER_PROPERTY: int = 534
## Chance of Dusk Shroud per consumed shadow: AbilityProperty 6 of CreateShadow.
const SHADOW_SHROUD_PROPERTY: int = 6

## Ailments that strike and reset at a number of stacks (ability description «Upon reaching 4 stacks of Shadow Daggers»).
const THRESHOLDS: Dictionary = {"ShadowDaggers": {"stacks": 4, "ability": "ShadowDaggersFinisher"}}
## Shadow Daggers finisher (AbilityID 508): property 0 = more damage against rares and bosses.
const FINISHER_ID: String = "shadowDaggersFinisher"
const FINISHER_INDEX: int = 508

## Off: only the Conditions values (tests that compare with measurements on a dummy without ailments).
static var enabled: bool = true
static var _cache: Dictionary = {}
static var _busy: bool = false


## {AilmentID: {stacks, uptime, rate, duration, max, sources, note}} kept on the target for the skill in `slot`;
## {} while the bar is computed.
static func auto(build: Node, slot: int) -> Dictionary:
	if not enabled or _busy or slot < 0 or slot >= build.skills.size() or bool(build.enemy.get(APPLIED_KEY, false)):
		return {}
	var raw: Dictionary = _raw(build)
	if not raw.has(slot):
		return {}
	var sums: Dictionary = {}  # id -> {rate, load, max, sources}
	var consume_rate: Dictionary = {}  # id -> uses/s of the skills that spend it
	for other: Variant in raw:
		if not other is int:
			continue
		var r: Dictionary = raw[other]
		var all: bool = other == slot or bool(r["cooldown"])
		for a: Dictionary in r["applied"]:
			if bool(a.get("self", false)) or (not all and not PARALLEL_KINDS.has(str(a.get("kind", "")))):
				continue
			var id: int = int(a["id"])
			if not sums.has(id):
				sums[id] = {"rate": 0.0, "load": 0.0, "max": int(a["max"]), "sources": {}}
			var rate: float = float(a["rate"])
			sums[id]["rate"] += rate
			sums[id]["load"] += rate * float(a["duration"])
			var label: String = str(r["name"]) if str(a.get("source", "")) == "" else "%s: %s" % [r["name"], a["source"]]
			sums[id]["sources"][label] = float(sums[id]["sources"].get(label, 0.0)) + rate
		if all:
			for flag: String in r["flag_keys"]:
				for name: String in CONSUMERS.get(flag, []):
					var cid: int = GameData.ailment_id_by_name(name)
					consume_rate[cid] = float(consume_rate.get(cid, 0.0)) + float(r["uses"])
	var out: Dictionary = {}
	for id: int in sums:
		var rate: float = float(sums[id]["rate"])
		var load: float = float(sums[id]["load"])
		if rate <= 0.0 or load <= 0.0:
			continue
		var max_inst: int = int(sums[id]["max"])
		var duration: float = load / rate
		var note: String = ""
		var name: String = str(GameData.ailment(id).get("name", ""))
		var uptime: float = 1.0 - exp(-load)
		if THRESHOLDS.has(name):
			var n: float = float(THRESHOLDS[name]["stacks"])
			load = (n - 1.0) / 2.0 * minf(1.0, load / n)
			uptime *= (n - 1.0) / n
			note = LE.t("strikes and resets at %d stacks: on average (%d − 1) / 2") % [int(n), int(n)]
		elif float(consume_rate.get(id, 0.0)) > 0.0:
			var period: float = 1.0 / float(consume_rate[id])
			load = consumed_load(rate, duration, period)
			uptime = 1.0 - exp(-rate * minf(duration, period))
			note = LE.t("spent by hits every %s s") % LE.fmt_num(period)
		var stacks: float = load
		if max_inst == 1:
			stacks = uptime
		elif max_inst > 1:
			stacks = minf(load, float(max_inst))
		out[id] = {"stacks": stacks, "uptime": uptime, "rate": rate, "duration": duration, "max": max_inst,
			"sources": sums[id]["sources"], "note": note}
	return out


## Average stacks of an ailment applied `rate` times per second for `duration` seconds and wiped every `period` seconds.
static func consumed_load(rate: float, duration: float, period: float) -> float:
	if duration >= period:
		return rate * period / 2.0
	return rate * (duration - duration * duration / (2.0 * period))


## Per bar slot: {name, applied, uses, cooldown, flag_keys} of a pass against the Conditions values only (cached).
static func _raw(build: Node) -> Dictionary:
	var key: String = _signature(build)
	if _cache.has(key):
		return _cache[key]
	_busy = true
	var out: Dictionary = {}
	for slot: int in range(build.skills.size()):
		var ab: Dictionary = GameData.get_ability(str(build.skills[slot].get("ability", "")))
		if ab.is_empty():
			continue
		var r: Dictionary = SkillCalc.compute(build, slot)
		var uses: float = float(r.get("rates", {}).get("uses", 0.0))
		var applied: Array = (r.get("ailments_applied", []) as Array).duplicate()
		applied.append_array(_self_sources(build, ab, uses, float(r.get("rates", {}).get("hits", 0.0))))
		applied.append_array(_param_sources(build, r.get("params", {}), uses))
		out[slot] = {"name": GameData.display_name(ab), "applied": applied, "uses": uses,
			"cooldown": bool(r.get("cooldown", false)), "flag_keys": r.get("flag_keys", [])}
	out["defense"] = _defense_sources(build)
	_busy = false
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_cache[key] = out
	return out


## {AilmentID: {stacks, uptime, rate, duration, max, sources, note}} of the «Buffs on me» list kept on you while the skill
## in `slot` is used (its own gains, the parallel sources of the other bar skills, the Defense tab events); {} while the
## bar is computed.
static func buffs(build: Node, slot: int) -> Dictionary:
	if not enabled or _busy or slot < 0 or slot >= build.skills.size() or bool(build.player_state.get(APPLIED_KEY, false)):
		return {}
	var raw: Dictionary = _raw(build)
	if not raw.has(slot):
		return {}
	var listed: Dictionary = {}
	for ail: Dictionary in GameData.player_buffs():
		listed[int(ail["id"])] = true
	var gains: Array[Array] = []  # [application, label]
	for other: Variant in raw:
		if not other is int:
			continue
		var r: Dictionary = raw[other]
		var all: bool = other == slot or bool(r["cooldown"])
		for a: Dictionary in r["applied"]:
			if bool(a.get("self", false)) and (all or PARALLEL_KINDS.has(str(a.get("kind", "")))):
				gains.append([a, str(r["name"]) if str(a.get("source", "")) == "" else "%s: %s" % [r["name"], a["source"]]])
	for a: Dictionary in raw.get("defense", []):
		gains.append([a, str(a["source"])])
	var sums: Dictionary = {}
	for g: Array in gains:
		var a: Dictionary = g[0]
		var id: int = int(a["id"])
		if not listed.has(id) or float(a["rate"]) <= 0.0:
			continue
		if not sums.has(id):
			sums[id] = {"rate": 0.0, "load": 0.0, "max": int(a["max"]), "sources": {}}
		sums[id]["rate"] += float(a["rate"])
		sums[id]["load"] += float(a["rate"]) * float(a["duration"])
		sums[id]["sources"][g[1]] = float(sums[id]["sources"].get(g[1], 0.0)) + float(a["rate"])
	var out: Dictionary = {}
	for id: int in sums:
		var rate: float = float(sums[id]["rate"])
		var load: float = float(sums[id]["load"])
		if load <= 0.0:
			continue
		var max_inst: int = int(sums[id]["max"])
		var uptime: float = 1.0 - exp(-load)
		var stacks: float = load
		if max_inst == 1:
			stacks = uptime
		elif max_inst > 1:
			stacks = minf(load, float(max_inst))
		out[id] = {"stacks": stacks, "uptime": uptime, "rate": rate, "duration": load / rate, "max": max_inst,
			"sources": sums[id]["sources"], "note": ""}
	return out


## Gains of buffs on you from one bar skill that are not ailment chances of its hits: «on you» prefab ailments per use,
## the PlayerProperty chances per use of a melee or throwing attack that hits, Dusk Shroud per consumed shadow.
static func _self_sources(build: Node, ab: Dictionary, uses: float, hits: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in ab.get("ailmentsOnHit", []):
		if str(entry.get("class", "")) != "ApplyAilmentToCreator":
			continue
		for a: Dictionary in entry.get("ailments", []):
			var id: int = GameData.ailment_id_by_name(str(a.get("ailment", "")))
			if id >= 0 and int(GameData.ailment(id).get("positive", 0)) != 0:
				out.append(_gain(id, uses * float(a.get("chance", 1.0)), float(a.get("increasedDuration", 0.0)), LE.t("on use")))
	var tags: int = int(ab.get("tags", 0))
	if hits > 0.0 and (tags & (LE.MELEE | LE.THROWING)) != 0:
		for index: int in PP_BUFFS:
			if str(PP_BUFFS[index]["event"]) != "melee_throwing_use":
				continue
			var chance: float = float(player_property(build, index)["value"])
			if chance > 0.0:
				out.append(_gain(GameData.ailment_id_by_name(str(PP_BUFFS[index]["ailment"])), uses * minf(chance, 1.0), 0.0,
					LE.t("melee or throwing attack that hits, %s per use") % LE.fmt_pct(chance)))
	if ShadowCalc.imitates(ab) and ShadowCalc.count(build) > 0.0:
		var chance_s: float = float(ShadowCalc.property(build, SHADOW_SHROUD_PROPERTY)["value"])
		if chance_s > 0.0:
			var consumed: float = ShadowCalc.count(build) * maxf(uses, 1.0 / ShadowCalc.LIFETIME)
			out.append(_gain(GameData.ailment_id_by_name("DuskShroud"), consumed * minf(chance_s, 1.0), 0.0,
				LE.t("consumed shadows, %s each") % LE.fmt_pct(chance_s)))
	return out


## Buff gains from skill parameters (PARAM_BUFFS). A buff spent by enemy hits lives min(duration, k / hits per second) for
## its k-th stack of a burst (the stacks are spent one per hit), so its average lifetime replaces the duration.
static func _param_sources(build: Node, params: Dictionary, uses: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for label: Variant in params:
		var p: Dictionary = params[label]
		var spec: Dictionary = PARAM_BUFFS.get(str(p.get("param", "")), {})
		if spec.is_empty():
			continue
		var n: float = _param_value(p)
		var id: int = GameData.ailment_id_by_name(str(spec["ailment"]))
		if n <= 0.0 or id < 0:
			continue
		if str(spec["per"]) == "use":
			var g: Dictionary = _gain(id, uses * n, 0.0, LE.t("%s: %s stacks per use") % [str(label), LE.fmt_num(n)])
			if bool(spec.get("spent_by_hits", false)):
				var hits: Dictionary = _enemy_hits(build)
				var spend: float = float(hits["rate"]) * (1.0 - clampf(float(player_property(build, KEEP_SILVER_PROPERTY)["value"]), 0.0, 1.0))
				if spend > 0.0:
					var total: float = 0.0
					var k: int = 1
					while k <= int(ceil(n)):
						total += minf(float(g["duration"]), float(k) / spend)
						k += 1
					g["duration"] = total / ceilf(n)
					g["source"] = str(g["source"]) + LE.t(", spent by %s enemy hits/s (Defense tab)") % LE.fmt_num(spend)
			out.append(g)
		else:
			var in_zone: float = minf(1.0, uses * float(spec["zone"]))
			out.append(_gain(id, n * in_zone, 0.0, LE.t("%s: %s stacks per second in the zone, %s of the time") % [
				str(label), LE.fmt_num(n), LE.fmt_pct(in_zone)]))
	return out


## Value of a skill parameter: set, or added × (1 + increased) × more.
static func _param_value(p: Dictionary) -> float:
	if p.get("set") != null:
		return float(p["set"])
	return float(p.get("added", 0.0)) * (1.0 + float(p.get("increased", 0.0))) * float(p.get("more", 1.0))


## The enemy's hits on you (the attack of the Defense tab): {interval, dodge, rate = landed hits per second}; rate 0 for a
## DoT attack.
static func _enemy_hits(build: Node) -> Dictionary:
	var settings: Dictionary = DefenseCalc.settings_of(build)
	var attack: Dictionary = DefenseCalc.enemy_attack(build)
	if not bool(attack.get("is_hit", true)):
		return {"interval": 0.0, "dodge": 0.0, "rate": 0.0, "hit": false}
	var interval: float = float(settings["interval"])
	if interval <= 0.0:
		interval = float(attack["every"]) if float(attack["every"]) > 0.0 else DefenseCalc.DEFAULT_INTERVAL
	var layers: Dictionary = DefenseCalc.player_layers(build, BuildMods.global_store(build)["store"], int(settings["area_level"]), attack)
	var dodge: float = clampf(float(layers["dodge"]), 0.0, 1.0)
	return {"interval": interval, "dodge": dodge, "rate": (1.0 - dodge) / interval, "hit": true}


## Gains from the enemy's hits (the attack of the Defense tab): per hit taken and per dodge.
static func _defense_sources(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chances: Dictionary = {}
	var any: bool = false
	for index: int in PP_BUFFS:
		var ev: String = str(PP_BUFFS[index]["event"])
		if ev == "hit_taken" or ev == "dodge":
			chances[index] = float(player_property(build, index)["value"])
			any = any or float(chances[index]) > 0.0
	if not any:
		return out
	var hits: Dictionary = _enemy_hits(build)
	if not bool(hits["hit"]):
		return out
	var interval: float = float(hits["interval"])
	var dodge: float = float(hits["dodge"])
	for index: int in chances:
		if float(chances[index]) <= 0.0:
			continue
		var on_dodge: bool = str(PP_BUFFS[index]["event"]) == "dodge"
		var events: float = (dodge if on_dodge else 1.0 - dodge) / interval
		out.append(_gain(GameData.ailment_id_by_name(str(PP_BUFFS[index]["ailment"])), events * minf(float(chances[index]), 1.0), 0.0,
			LE.t("Defense tab attack: every %s s, dodge chance %s, %s per %s") % [LE.fmt_num(interval), LE.fmt_pct(dodge),
				LE.fmt_pct(float(chances[index])), LE.t("dodge") if on_dodge else LE.t("hit taken")]))
	return out


static func _gain(id: int, rate: float, inc_duration: float, source: String) -> Dictionary:
	var ail: Dictionary = GameData.ailment(id)
	return {"id": id, "rate": rate, "duration": float(ail.get("duration", 0.0)) * (1.0 + inc_duration),
		"max": int(ail.get("maxInstances", 0)), "self": true, "kind": "self", "source": source}


## Sum of a PlayerProperty: passives and the mastery bonus (Stats.PlayerPropertyStat), item / idol affixes, unique effects.
## {value, lines}
static func player_property(build: Node, index: int) -> Dictionary:
	var lines: PackedStringArray = []
	var total: float = 0.0
	var tree_id: String = str(GameData.get_passive_tree(build.class_id).get("treeID", ""))
	var effects: Dictionary = GameData.passive_effects(tree_id)
	var nodes: Array[Array] = []
	for node_id: Variant in build.passives:
		var points: int = int(build.passives[node_id])
		if points > 0 and effects.has(int(node_id)):
			nodes.append([effects[int(node_id)], points])
	var bonus: Dictionary = GameData.mastery_bonus(tree_id, int(build.mastery))
	if not bonus.is_empty():
		nodes.append([bonus, 1])
	for entry: Array in nodes:
		var node: Dictionary = entry[0]
		var points: int = entry[1]
		for effect: Dictionary in node.get("effects", []):
			var stat: Variant = effect.get("stat")
			if not stat is Dictionary or str(stat.get("kind", "")) != "player_property" or points < int(effect.get("minPoints", 0)):
				continue
			if int(str(stat.get("playerPropertyIndex", "-1"))) != index:
				continue
			var v: float = BuildMods.eval_value(stat.get("value"), points)
			if v != 0.0:
				total += v
				lines.append(LE.t("Passive \"%s\" ×%d: %s") % [str(node.get("displayName", "")), points, LE.fmt_num(v)])
	for slot: String in build.items:
		if not (BuildMods.SLOTS.has(slot) or IdolGrid.is_idol_key(slot)):
			continue
		for mod: StatMod in ItemMods.item_mods(slot, build.items[slot]):
			if mod.property == LE.PLAYER_PROPERTY and mod.tags == index:
				total += mod.added
				lines.append("%s: %s" % [mod.source, LE.fmt_num(mod.added)])
	for e: Dictionary in UniqueEffects.entries(build):
		if int(e["effect"].get("ppIndex", -1)) == index and str(e["effect"].get("source", "")) == "PlayerProperty":
			total += float(e["pp"])
			lines.append("%s: %s" % [e["label"], LE.fmt_num(float(e["pp"]))])
	return {"value": total, "lines": lines}


## Puts the automatic enemy ailments and buffs on you for the skill in `slot` into the build (SkillCalc, DefenseCalc, the
## character stats); returns what `restore` puts back ({enemy, player_state, auto, buffs}).
static func apply(build: Node, slot: int) -> Dictionary:
	var saved: Dictionary = {"enemy": build.enemy, "player_state": build.player_state}
	var enemy_auto: Dictionary = auto(build, slot)
	var buff_auto: Dictionary = buffs(build, slot)
	build.enemy = effective(saved["enemy"], enemy_auto)
	build.player_state = effective_player(saved["player_state"], buff_auto)
	saved["auto"] = enemy_auto
	saved["buffs"] = buff_auto
	return saved


static func restore(build: Node, saved: Dictionary) -> void:
	build.enemy = saved["enemy"]
	build.player_state = saved["player_state"]


## Copy of the player state with the automatic stacks for the buffs the Conditions tab leaves unset.
static func effective_player(state: Dictionary, buff_auto: Dictionary) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	var stacks: Dictionary = out.get("buffs", {})
	for id: int in buff_auto:
		if not stacks.has(id) and not stacks.has(str(id)):
			stacks[id] = float(buff_auto[id]["stacks"])
	out["buffs"] = stacks
	out[APPLIED_KEY] = true
	return out


## Copy of the enemy with the automatic values for the ailments the Conditions tab leaves unset.
static func effective(enemy: Dictionary, auto_values: Dictionary) -> Dictionary:
	var out: Dictionary = enemy.duplicate(true)
	var ailments: Dictionary = out.get("ailments", {})
	var uptime: Dictionary = {}
	for id: Variant in ailments:
		uptime[int(id)] = 1.0 if float(ailments[id]) > 0.0 else 0.0
	for id: int in auto_values:
		if ailments.has(id):
			continue
		ailments[id] = float(auto_values[id]["stacks"])
		uptime[id] = float(auto_values[id]["uptime"])
	out["ailments"] = ailments
	out["uptime"] = uptime
	out[APPLIED_KEY] = true
	return out


## Breakdown of one automatic value (the Conditions tab shows it on the row).
static func describe(entry: Dictionary) -> String:
	var text: String = LE.t("auto: %s/s × %s s = %s") % [LE.fmt_num(float(entry["rate"])), LE.fmt_num(float(entry["duration"])),
		LE.fmt_num(float(entry["rate"]) * float(entry["duration"]))]
	if str(entry.get("note", "")) != "":
		text += "; %s → %s" % [entry["note"], LE.fmt_num(float(entry["stacks"]))]
	if int(entry["max"]) > 0:
		text += LE.t(", limit %d") % int(entry["max"])
	text += LE.t(", uptime %s") % LE.fmt_pct(float(entry["uptime"]))
	var sources: Dictionary = entry.get("sources", {})
	if sources.size() > 1:
		var parts: PackedStringArray = []
		for label: String in sources:
			parts.append("%s %s/s" % [label, LE.fmt_num(float(sources[label]))])
		text += "\n" + "; ".join(parts)
	return text


## Damage components for the strikes of the threshold ailments the skill builds up (Shadow Daggers: one strike per 4
## applications; fewer when the stacks expire before reaching 4, D?). Kind `trigger` with a fixed rate.
static func threshold_components(build: Node, store: StatStore, comp_results: Array[Dictionary],
		_notes: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name: String in THRESHOLDS:
		var id: int = GameData.ailment_id_by_name(name)
		var rate: float = 0.0
		var load: float = 0.0
		for cr: Dictionary in comp_results:
			for a: Dictionary in cr["ail"].get("applied", []):
				if int(a["id"]) == id:
					rate += float(a["rate"])
					load += float(a["rate"]) * float(a["duration"])
		if rate <= 0.0:
			continue
		var n: float = float(THRESHOLDS[name]["stacks"])
		var fab: Dictionary = GameData.ability_by_name(str(THRESHOLDS[name]["ability"]))
		var entry: Dictionary = SkillComponents._first_damage(fab)
		if entry.is_empty():
			continue
		var strikes: float = rate / n * minf(1.0, load / n)
		var note: String = LE.t("%s at %d stacks: applications %s/s / %d = %s strikes/s") % [
			GameData.display_name(fab), int(n), LE.fmt_num(rate), int(n), LE.fmt_num(strikes)]
		var comp: Dictionary = SkillComponents._component(GameData.display_name(fab), "trigger", fab, entry, 1.0, strikes, note)
		var more: Dictionary = ShadowCalc.ability_property(build, FINISHER_ID, FINISHER_INDEX, 0)
		if float(more["value"]) != 0.0 and str(build.enemy.get("kind", "")) in ["rare", "boss", "miniboss"]:
			var child := StatStore.new()
			child.parent = store
			child.add(StatMod.make(LE.DAMAGE, "more", float(more["value"]), 0,
				LE.t("More damage against rares and bosses (%s)") % "; ".join(more["lines"])))
			comp["store"] = child
		out.append(comp)
	return out


static func _signature(build: Node) -> String:
	return var_to_str([build.class_id, build.mastery, build.level, build.quest_passive_points, build.passives,
		build.skills, build.items, build.blessings, build.enemy, build.player_state])
