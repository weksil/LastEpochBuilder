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
	for other: int in raw:
		var r: Dictionary = raw[other]
		var all: bool = other == slot or bool(r["cooldown"])
		for a: Dictionary in r["applied"]:
			if not all and not PARALLEL_KINDS.has(str(a.get("kind", ""))):
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
		out[slot] = {"name": GameData.display_name(ab), "applied": r.get("ailments_applied", []),
			"uses": float(r.get("rates", {}).get("uses", 0.0)), "cooldown": bool(r.get("cooldown", false)),
			"flag_keys": r.get("flag_keys", [])}
	_busy = false
	if _cache.size() >= CACHE_LIMIT:
		_cache.clear()
	_cache[key] = out
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
