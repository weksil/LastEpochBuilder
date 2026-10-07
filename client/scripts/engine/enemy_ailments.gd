class_name EnemyAilments

## Enemy ailments the calculation uses (docs/ENGINE.md §9.11). A value set on the Conditions tab (a key of
## Build.enemy.ailments, 0 included) wins; every other ailment takes the average the skill keeps on the target by itself,
## from the applications of its hit components (AilmentCalc: chance × hits per second, duration with its modifiers):
##   stacks = min(Σ applications/s × duration, maxInstances); a single-instance ailment counts its uptime;
##   uptime («the enemy has it») = 1 − e^(−Σ applications/s × duration) (independent applications, refreshed duration).
## The effective enemy keeps the stacks in `ailments` and the uptimes in `uptime` (Enemy.presence reads them).

## Marks an enemy dictionary that already holds the automatic values (nested calculations do not add them again).
const APPLIED_KEY: String = "auto_applied"
const CACHE_LIMIT: int = 64

## Off: only the Conditions values (tests that compare with measurements on a dummy without ailments).
static var enabled: bool = true
static var _cache: Dictionary = {}
static var _busy: bool = false


## {AilmentID: {stacks, uptime, rate, duration, max}} the skill in `slot` keeps on the target; {} while it is computed.
## The pass runs the skill against the Conditions values only, so chances that depend on enemy ailments see those.
static func auto(build: Node, slot: int) -> Dictionary:
	if not enabled or _busy or slot < 0 or slot >= build.skills.size() or bool(build.enemy.get(APPLIED_KEY, false)):
		return {}
	var key: String = _signature(build, slot)
	if _cache.has(key):
		return _cache[key]
	_busy = true
	var r: Dictionary = SkillCalc.compute(build, slot)
	_busy = false
	var sums: Dictionary = {}  # id -> {rate, load, max}
	for a: Dictionary in r.get("ailments_applied", []):
		var id: int = int(a["id"])
		if not sums.has(id):
			sums[id] = {"rate": 0.0, "load": 0.0, "max": int(a["max"])}
		sums[id]["rate"] += float(a["rate"])
		sums[id]["load"] += float(a["rate"]) * float(a["duration"])
	var out: Dictionary = {}
	for id: int in sums:
		var rate: float = float(sums[id]["rate"])
		var load: float = float(sums[id]["load"])
		if rate <= 0.0 or load <= 0.0:
			continue
		var max_inst: int = int(sums[id]["max"])
		var uptime: float = 1.0 - exp(-load)
		var stacks: float = load
		if max_inst == 1:
			stacks = uptime
		elif max_inst > 1:
			stacks = minf(load, float(max_inst))
		out[id] = {"stacks": stacks, "uptime": uptime, "rate": rate, "duration": load / rate, "max": max_inst}
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


## Short breakdown of one automatic value (the Conditions tab shows it on the row).
static func describe(entry: Dictionary) -> String:
	var text: String = LE.t("auto: %s/s × %s s = %s") % [LE.fmt_num(float(entry["rate"])), LE.fmt_num(float(entry["duration"])),
		LE.fmt_num(float(entry["rate"]) * float(entry["duration"]))]
	if int(entry["max"]) > 0:
		text += LE.t(", limit %d") % int(entry["max"])
	return text + LE.t(", uptime %s") % LE.fmt_pct(float(entry["uptime"]))


static func _signature(build: Node, slot: int) -> String:
	return str(slot) + var_to_str([build.class_id, build.mastery, build.level, build.quest_passive_points, build.passives,
		build.skills, build.items, build.blessings, build.enemy, build.player_state])
