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
## (PP_BUFFS: per use of a melee or throwing attack that hits — CharacterMutator.OnFirstMeleeOrThrowingHit —, per spell
## cast, per direct use of a skill of an element, per crit, per companion skill use, per enemy hit taken, per dodge; the
## enemy hits come from the Defense tab attack), timed PlayerProperty buffs (Apocalypse every 3 s at high health, Damage
## Immunity after a hit on a 15 s cooldown), skill parameters (PARAM_BUFFS), unique AbilityProperty chances
## (ABILITY_PROPERTY_BUFFS) and Dusk Shroud per consumed shadow (CreateShadow 6).
## Events a single-target calculation cannot derive come from the player numbers of the Conditions tab (EVENT_INPUTS, per
## second): kills, stuns, arrows picked up, drops below high health; «moving after attacking» is the Moving checkbox.

## Marks an enemy dictionary that already holds the automatic values (nested calculations do not add them again).
const APPLIED_KEY: String = "auto_applied"
const CACHE_LIMIT: int = 16
## Kinds of applications that act in parallel with the other skills (minions, zones).
## «input»: gains driven by an EVENT_INPUTS rate, the same whatever skill is used.
const PARALLEL_KINDS: Array[String] = ["minion", "zone", "input"]
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
## `flag`: the property switches the gain on (chance 1); `duration`: PlayerProperty of increased duration; `tag`: the
## damage tag of the skill used directly (CharacterMutator.OnStartedUsingAbilityOrBeforeInstantAbilityUse).
const PP_BUFFS: Dictionary = {
	27: {"ailment": "CriticalEffluence", "event": "spell_use"},
	97: {"ailment": "DuskShroud", "event": "hit_taken"},
	102: {"ailment": "DuskShroud", "event": "melee_throwing_use"},
	107: {"ailment": "CrimsonShroud", "event": "melee_throwing_use"},
	315: {"ailment": "Runeword Cataclysm", "event": "crit", "duration": 319},
	316: {"ailment": "Runeword Hurricane", "event": "tag_use", "tag": LE.LIGHTNING, "duration": 319},
	317: {"ailment": "Runeword Avalanche", "event": "tag_use", "tag": LE.COLD, "duration": 319},
	318: {"ailment": "Runeword Inferno", "event": "tag_use", "tag": LE.FIRE, "duration": 319},
	470: {"ailment": "DuskShroud", "event": "dodge"},
	680: {"ailment": "AspectOfTheGroleVisuals", "event": "companion_use", "flag": true},
}
## Player numbers of the Conditions tab (Build.player_state, per second) that drive gains on events the calculation has no
## rate for.
const EVENT_INPUTS: Array[String] = ["kills_per_second", "stuns_per_second", "arrow_pickups_per_second", "health_drops_per_second"]
## PlayerProperties on those events: {ailment, input, flag (chance 1), stacks (the value is stacks per event), void (only
## kills by a void skill — the selected one)}.
const PP_INPUT_BUFFS: Dictionary = {
	8: {"ailment": "Inspiration", "input": "stuns_per_second", "flag": true},
	50: {"ailment": "VoidEssence", "input": "kills_per_second"},
	60: {"ailment": "Inspiration", "input": "kills_per_second", "void": true},
	104: {"ailment": "SilverShroud", "input": "health_drops_per_second", "stacks": true},
}
## «Seconds of Ancient Flight when you move after attacking»: on while the Moving checkbox is on.
const ANCIENT_FLIGHT_PROPERTY: int = 139
## Event labels of PP_BUFFS (translated in ru.po).
const PP_EVENT_TEXT: Dictionary = {
	"melee_throwing_use": "melee or throwing attack that hits", "spell_use": "spell cast", "crit": "critical strike",
	"companion_use": "companion skill use", "hit_taken": "hit taken", "dodge": "dodge",
}
const INPUT_TEXT: Dictionary = {
	"kills_per_second": "kills/s", "stuns_per_second": "stuns/s", "arrow_pickups_per_second": "arrows picked up/s",
	"health_drops_per_second": "drops below high health/s",
}
const TAG_USE_TEXT: Dictionary = {2: "direct use of a lightning skill", 4: "direct use of a cold skill", 8: "direct use of a fire skill"}
## «Every 3 seconds if you are on high health you lose 25% of your current health and gain Apocalypse for 3 seconds».
const APOCALYPSE_PROPERTY: int = 80
const APOCALYPSE_PERIOD: float = 3.0
## «Seconds of Damage Immunity After being Hit (15 second cooldown)».
const IMMUNITY_PROPERTY: int = 217
const IMMUNITY_COOLDOWN: float = 15.0
## Skill parameters (field_models.json `param`) that give buffs on you: stacks per use (Smoke Bomb «Moonlight Bomb»: Silver
## Shroud on the initial burst) or stacks per second while you stand in the skill's zone (Smoke Bomb «Smoke Blades»: the
## cloud lasts `zone` seconds, «Lasts 4 seconds»). `spent_by_hits`: one stack is spent by every enemy hit (Silver Shroud
## «Dodge your next hit»; PlayerProperty 534 = chance not to spend it).
## Other kinds: `chance` (the value is a chance, at most 1) per use, hit or crit; `interval_in_zone`: one stack every
## `value` seconds while in the zone, faster by the `frequency` parameter (Smoke Bomb Dusk Shroud); `interval`: one stack
## every `value` seconds of use (Drain Life Contempt per seconds of channel); `unless_flag`: a node flag that limits the
## gain to an event the calculation does not have (Void Cleave «only on hit vs own minion»).
## Per use: Umbral Blades (on use), Shadow Rend (the hit of its shadow, once per use), Rebuke (final hit), Volatile
## Reversal, Devouring Orb (orb expiry), Vengeance (its hit).
const PARAM_BUFFS: Dictionary = {
	"silver_shroud_stacks": {"ailment": "SilverShroud", "per": "use", "spent_by_hits": true},
	"smoke_blades_stacks": {"ailment": "SmokeBlades", "per": "second_in_zone", "zone": 4.0},
	"dusk_shroud_interval": {"ailment": "DuskShroud", "per": "interval_in_zone", "zone": 4.0, "frequency": "dusk_shroud_frequency"},
	"dusk_shroud_chance": {"ailment": "DuskShroud", "per": "use", "chance": true},
	"crimson_shroud_stacks": {"ailment": "CrimsonShroud", "per": "use"},
	"void_essence_chance": {"ailment": "VoidEssence", "per": "use", "chance": true},
	"void_essence_crit_chance": {"ailment": "VoidEssence", "per": "crit", "chance": true},
	"molten_stacks": {"ailment": "MoltenInfusion", "per": "hit", "unless_flag": "Molten Infusion only on hit vs own minion"},
	"contempt_interval": {"ailment": "Contempt", "per": "interval"},
	"crimson_shroud_chance": {"ailment": "CrimsonShroud", "per": "kill_in_zone", "chance": true, "zone": 4.0, "input": "kills_per_second"},
	"dusk_shroud_stacks": {"ailment": "DuskShroud", "per": "input", "input": "arrow_pickups_per_second"},
}
## AbilityProperty chances of uniques (item_procs.json) per use or per hit of the ability:
## Lament of the Lost Refuge — Corrupted Heraldry on Volcanic Orb cast (7) and on a hit of its shrapnel (8).
const ABILITY_PROPERTY_BUFFS: Dictionary = {
	"VolcanicOrb": [
		{"ability_id": "volcanicOrb", "ability_index": 78, "index": 7, "ailment": "CorruptedHeraldry", "per": "use"},
		{"ability_id": "volcanicOrb", "ability_index": 78, "index": 8, "ailment": "CorruptedHeraldry", "per": "hit"},
	],
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
		var rates: Dictionary = r.get("rates", {})
		applied.append_array(_self_sources(build, ab, uses, float(rates.get("hits", 0.0)), float(rates.get("crit", 0.0))))
		applied.append_array(_param_sources(build, r.get("params", {}), rates, r.get("flag_keys", [])))
		out[slot] = {"name": GameData.display_name(ab), "applied": applied, "uses": uses,
			"cooldown": bool(r.get("cooldown", false)), "flag_keys": r.get("flag_keys", [])}
	out["defense"] = _defense_sources(build)
	out["defense"].append_array(_timed_sources(build))
	out["defense"].append_array(_input_sources(build))
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
	for a: Dictionary in _void_kill_sources(build, GameData.get_ability(str(build.skills[slot].get("ability", "")))):
		gains.append([a, str(a["source"])])
	var sums: Dictionary = {}
	for g: Array in gains:
		var a: Dictionary = g[0]
		var id: int = int(a["id"])
		if not listed.has(id) or float(a["rate"]) <= 0.0:
			continue
		if not sums.has(id):
			sums[id] = {"rate": 0.0, "load": 0.0, "periodic": 0.0, "max": int(a["max"]), "sources": {}}
		sums[id]["rate"] += float(a["rate"])
		sums[id]["load"] += float(a["rate"]) * float(a["duration"])
		if bool(a.get("periodic", false)):
			sums[id]["periodic"] += float(a["rate"]) * float(a["duration"])
		sums[id]["sources"][g[1]] = float(sums[id]["sources"].get(g[1], 0.0)) + float(a["rate"])
	var out: Dictionary = {}
	for id: int in sums:
		var rate: float = float(sums[id]["rate"])
		var load: float = float(sums[id]["load"])
		if load <= 0.0:
			continue
		var max_inst: int = int(sums[id]["max"])
		# periodic gains (a fixed timer) cover their share of the time exactly; random ones as independent applications
		var periodic: float = minf(float(sums[id]["periodic"]), 1.0)
		var uptime: float = 1.0 - (1.0 - periodic) * exp(-(load - float(sums[id]["periodic"])))
		var stacks: float = load
		if max_inst == 1:
			stacks = uptime
		elif max_inst > 1:
			stacks = minf(load, float(max_inst))
		out[id] = {"stacks": stacks, "uptime": uptime, "rate": rate, "duration": load / rate, "max": max_inst,
			"sources": sums[id]["sources"], "note": ""}
	return out


## Gains of buffs on you from one bar skill that are not ailment chances of its hits: «on you» prefab ailments per use,
## the PlayerProperty chances of the skill's events (PP_BUFFS), unique AbilityProperty chances, Dusk Shroud per consumed
## shadow. `crit`: the crit chance of the skill's hits.
static func _self_sources(build: Node, ab: Dictionary, uses: float, hits: float, crit: float = 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in ab.get("ailmentsOnHit", []):
		if str(entry.get("class", "")) != "ApplyAilmentToCreator":
			continue
		for a: Dictionary in entry.get("ailments", []):
			var id: int = GameData.ailment_id_by_name(str(a.get("ailment", "")))
			if id >= 0 and int(GameData.ailment(id).get("positive", 0)) != 0:
				out.append(_gain(id, uses * float(a.get("chance", 1.0)), float(a.get("increasedDuration", 0.0)), LE.t("on use")))
	var tags: int = int(ab.get("tags", 0))
	for index: int in PP_BUFFS:
		var spec: Dictionary = PP_BUFFS[index]
		var events: float = 0.0
		match str(spec["event"]):
			"melee_throwing_use":
				events = uses if hits > 0.0 and (tags & (LE.MELEE | LE.THROWING)) != 0 else 0.0
			"spell_use":
				events = uses if (tags & LE.SPELL) != 0 else 0.0
			"tag_use":
				events = uses if (tags & int(spec["tag"])) != 0 else 0.0
			"crit":
				events = hits * clampf(crit, 0.0, 1.0)
			"companion_use":
				events = uses if bool(ab.get("companion", false)) else 0.0
		if events <= 0.0:
			continue
		var chance: float = float(player_property(build, index)["value"])
		if bool(spec.get("flag", false)):
			chance = 1.0 if chance > 0.0 else 0.0
		var id: int = GameData.ailment_id_by_name(str(spec["ailment"]))
		if chance <= 0.0 or id < 0:
			continue
		var inc: float = float(player_property(build, int(spec["duration"]))["value"]) if spec.has("duration") else 0.0
		var what: String = str(TAG_USE_TEXT[int(spec["tag"])]) if spec.has("tag") else str(PP_EVENT_TEXT[str(spec["event"])])
		out.append(_gain(id, events * minf(chance, 1.0), inc, LE.t("%s, chance %s") % [LE.t(what), LE.fmt_pct(chance)]))
	for prop: Dictionary in ABILITY_PROPERTY_BUFFS.get(str(ab.get("name", "")), []):
		var chance_p: float = float(ShadowCalc.ability_property(build, str(prop["ability_id"]), int(prop["ability_index"]), int(prop["index"]))["value"])
		var id_p: int = GameData.ailment_id_by_name(str(prop["ailment"]))
		if chance_p <= 0.0 or id_p < 0:
			continue
		var per_hit: bool = str(prop["per"]) == "hit"
		out.append(_gain(id_p, (hits if per_hit else uses) * minf(chance_p, 1.0), 0.0,
			(LE.t("%s per hit") if per_hit else LE.t("%s per use")) % LE.fmt_pct(chance_p)))
	if ShadowCalc.imitates(ab) and ShadowCalc.count(build) > 0.0:
		var chance_s: float = float(ShadowCalc.property(build, SHADOW_SHROUD_PROPERTY)["value"])
		if chance_s > 0.0:
			var consumed: float = ShadowCalc.count(build) * maxf(uses, 1.0 / ShadowCalc.LIFETIME)
			out.append(_gain(GameData.ailment_id_by_name("DuskShroud"), consumed * minf(chance_s, 1.0), 0.0,
				LE.t("consumed shadows, %s each") % LE.fmt_pct(chance_s)))
	return out


## Buff gains from skill parameters (PARAM_BUFFS); `rates` = SkillCalc rates {uses, hits, crit}. A buff spent by enemy hits
## lives min(duration, k / hits per second) for its k-th stack of a burst (the stacks are spent one per hit), so its
## average lifetime replaces the duration.
static func _param_sources(build: Node, params: Dictionary, rates: Dictionary, flag_keys: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var uses: float = float(rates.get("uses", 0.0))
	var by_param: Dictionary = {}
	for label: Variant in params:
		by_param[str(params[label].get("param", ""))] = params[label]
	for label: Variant in params:
		var p: Dictionary = params[label]
		var spec: Dictionary = PARAM_BUFFS.get(str(p.get("param", "")), {})
		if spec.is_empty() or flag_keys.has(str(spec.get("unless_flag", ""))):
			continue
		var n: float = _param_value(p)
		var id: int = GameData.ailment_id_by_name(str(spec["ailment"]))
		if n <= 0.0 or id < 0:
			continue
		if spec.has("input"):
			var rate_in: float = input_rate(build, str(spec["input"]))
			if rate_in <= 0.0:
				continue
			var g_in: Dictionary
			if str(spec["per"]) == "kill_in_zone":
				var share: float = minf(1.0, uses * float(spec["zone"]))
				g_in = _gain(id, rate_in * share * minf(n, 1.0), 0.0, LE.t("%s: chance %s per kill in the zone (%s of the time), %s kills/s (Conditions)") % [
					str(label), LE.fmt_pct(n), LE.fmt_pct(share), LE.fmt_num(rate_in)])
			else:
				g_in = _gain(id, rate_in * n, 0.0, LE.t("%s: %s stacks × %s/s (Conditions)") % [str(label), LE.fmt_num(n), LE.fmt_num(rate_in)])
			g_in["kind"] = "input"
			out.append(g_in)
		elif bool(spec.get("chance", false)):
			var events: float = uses
			match str(spec["per"]):
				"hit":
					events = float(rates.get("hits", 0.0))
				"crit":
					events = float(rates.get("hits", 0.0)) * clampf(float(rates.get("crit", 0.0)), 0.0, 1.0)
			out.append(_gain(id, events * minf(n, 1.0), 0.0, LE.t("%s: chance %s per %s") % [str(label), LE.fmt_pct(n),
				LE.t({"use": "use", "hit": "hit", "crit": "critical strike"}[str(spec["per"])])]))
		elif str(spec["per"]) == "hit":
			out.append(_gain(id, float(rates.get("hits", 0.0)) * n, 0.0, LE.t("%s: %s stacks per hit") % [str(label), LE.fmt_num(n)]))
		elif str(spec["per"]) == "interval":
			out.append(_gain(id, 1.0 / n, 0.0, LE.t("%s: a stack every %s s of use") % [str(label), LE.fmt_num(n)]))
		elif str(spec["per"]) == "interval_in_zone":
			var freq: float = 0.0
			if spec.has("frequency") and by_param.has(str(spec["frequency"])):
				freq = float(by_param[str(spec["frequency"])].get("increased", 0.0)) + float(by_param[str(spec["frequency"])].get("added", 0.0))
			var every: float = n / (1.0 + freq)
			var zone_share: float = minf(1.0, uses * float(spec["zone"]))
			out.append(_gain(id, zone_share / every, 0.0, LE.t("%s: a stack every %s s in the zone, %s of the time") % [
				str(label), LE.fmt_num(every), LE.fmt_pct(zone_share)]))
		elif str(spec["per"]) == "use":
			var g: Dictionary = _gain(id, uses * n, 0.0, LE.t("%s: %s stacks per use") % [str(label), LE.fmt_num(n)])
			if bool(spec.get("spent_by_hits", false)):
				_spend_silver(build, g, n)
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


## Silver Shroud dodges your next hit: the k-th stack of a burst of `n` lives min(duration, k / spends per second), so the
## average lifetime replaces the duration of the gain `g`.
static func _spend_silver(build: Node, g: Dictionary, n: float) -> void:
	var spend: float = float(_enemy_hits(build)["rate"]) * (1.0 - clampf(float(player_property(build, KEEP_SILVER_PROPERTY)["value"]), 0.0, 1.0))
	if spend <= 0.0:
		return
	var total: float = 0.0
	var k: int = 1
	while k <= int(ceil(n)):
		total += minf(float(g["duration"]), float(k) / spend)
		k += 1
	g["duration"] = total / ceilf(n)
	g["source"] = str(g["source"]) + LE.t(", spent by %s enemy hits/s (Defense tab)") % LE.fmt_num(spend)


## Rate of an EVENT_INPUTS player number (per second, at least 0).
static func input_rate(build: Node, key: String) -> float:
	return maxf(float(build.player_state.get(key, 0.0)), 0.0)


## Gains from PP_INPUT_BUFFS (not the void-kill ones, which follow the selected skill) and Ancient Flight while moving.
static func _input_sources(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index: int in PP_INPUT_BUFFS:
		var spec: Dictionary = PP_INPUT_BUFFS[index]
		if not bool(spec.get("void", false)):
			var g: Dictionary = _input_gain(build, index, spec)
			if not g.is_empty():
				out.append(g)
	var seconds: float = float(player_property(build, ANCIENT_FLIGHT_PROPERTY)["value"])
	var id: int = GameData.ailment_id_by_name("AncientFlight")
	if seconds > 0.0 and id >= 0 and bool(build.player_state.get("moving", false)):
		var g_f: Dictionary = _gain(id, 1.0 / seconds, 0.0, LE.t("moving after attacking (Moving on the Conditions tab), %s s") % LE.fmt_num(seconds))
		g_f["duration"] = seconds
		g_f["periodic"] = true
		out.append(g_f)
	return out


## Inspiration on kills with a void skill: the kills are those of the selected skill (`ab`).
static func _void_kill_sources(build: Node, ab: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if (int(ab.get("tags", 0)) & LE.VOID) == 0:
		return out
	for index: int in PP_INPUT_BUFFS:
		if bool(PP_INPUT_BUFFS[index].get("void", false)):
			var g: Dictionary = _input_gain(build, index, PP_INPUT_BUFFS[index])
			if not g.is_empty():
				out.append(g)
	return out


static func _input_gain(build: Node, index: int, spec: Dictionary) -> Dictionary:
	var rate: float = input_rate(build, str(spec["input"]))
	var value: float = float(player_property(build, index)["value"])
	var id: int = GameData.ailment_id_by_name(str(spec["ailment"]))
	if rate <= 0.0 or value <= 0.0 or id < 0:
		return {}
	var what: String = LE.t(str(INPUT_TEXT[str(spec["input"])]))
	if bool(spec.get("stacks", false)):
		var g: Dictionary = _gain(id, rate * value, 0.0, LE.t("%s stacks per event, %s %s (Conditions)") % [LE.fmt_num(value), LE.fmt_num(rate), what])
		if str(spec["ailment"]) == "SilverShroud":
			_spend_silver(build, g, value)
		return g
	var chance: float = 1.0 if bool(spec.get("flag", false)) else minf(value, 1.0)
	return _gain(id, rate * chance, 0.0, LE.t("chance %s per event, %s %s (Conditions)") % [LE.fmt_pct(chance), LE.fmt_num(rate), what])


## Why each EVENT_INPUTS number (and the Moving checkbox) matters to the build: {"player_values": {key: reason},
## "player_flags": {key: reason}}; `params` = the param names of the bar skills -> skill name.
static func input_reasons(build: Node, params: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var flags: Dictionary = {}
	for index: int in PP_INPUT_BUFFS:
		var spec: Dictionary = PP_INPUT_BUFFS[index]
		var pp: Dictionary = player_property(build, index)
		if float(pp["value"]) > 0.0:
			values[str(spec["input"])] = LE.t("%s on you: %s") % [GameData.display_name(GameData.ailment(GameData.ailment_id_by_name(str(spec["ailment"])))),
				", ".join(pp["lines"])]
	for param: String in PARAM_BUFFS:
		var spec_p: Dictionary = PARAM_BUFFS[param]
		if spec_p.has("input") and params.has(param):
			values[str(spec_p["input"])] = LE.t("%s on you: %s") % [GameData.display_name(GameData.ailment(GameData.ailment_id_by_name(str(spec_p["ailment"])))),
				str(params[param])]
	var flight: Dictionary = player_property(build, ANCIENT_FLIGHT_PROPERTY)
	if float(flight["value"]) > 0.0:
		flags["moving"] = LE.t("Ancient Flight on you: %s") % ", ".join(flight["lines"])
	return {"player_values": values, "player_flags": flags}


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


## Buffs on a timer of PlayerProperties: Apocalypse every 3 s while on high health (the Health select of the Conditions
## tab is full or high); Damage Immunity for `value` seconds after a hit, then 15 s of cooldown and the wait for the next
## landed hit of the Defense tab attack.
static func _timed_sources(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var health: String = str(build.player_state.get("health", "full"))
	var id_a: int = GameData.ailment_id_by_name("Apocalypse")
	if id_a >= 0 and float(player_property(build, APOCALYPSE_PROPERTY)["value"]) > 0.0 and (health == "full" or health == "high"):
		var g: Dictionary = _gain(id_a, 1.0 / APOCALYPSE_PERIOD, 0.0, LE.t("every %s s while on high health") % LE.fmt_num(APOCALYPSE_PERIOD))
		g["duration"] = APOCALYPSE_PERIOD
		g["periodic"] = true
		out.append(g)
	var seconds: float = float(player_property(build, IMMUNITY_PROPERTY)["value"])
	var id_i: int = GameData.ailment_id_by_name("DamageImmunity")
	if seconds > 0.0 and id_i >= 0:
		var hits: Dictionary = _enemy_hits(build)
		if float(hits["rate"]) > 0.0:
			var period: float = IMMUNITY_COOLDOWN + 1.0 / float(hits["rate"])
			var g_i: Dictionary = _gain(id_i, 1.0 / period, 0.0, LE.t("%s s after a hit, once per %s s (15 s cooldown + the next enemy hit, Defense tab)") % [
				LE.fmt_num(seconds), LE.fmt_num(period)])
			g_i["duration"] = seconds
			g_i["periodic"] = true
			out.append(g_i)
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
