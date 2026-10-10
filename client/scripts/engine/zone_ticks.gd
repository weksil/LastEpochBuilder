class_name ZoneTicks

## Damage ticks of zone objects over their lifetime (client/data/zone_ticks.json, tools/extract/distill_prefab_zone_ticks.py).
## A RepeatedlyDamageEnemiesWithinRadius object hits the enemy once per damageInterval while it lives; the enemy is assumed to
## stay inside for the whole lifetime (user decision: maximum damage, D?). Loaded lazily once.

static var _data: Dictionary = {}
static var _loaded: bool = false
## An exact multiple of the interval counts its last tick (the float32 interval and lifetime are not exact in binary).
const EPS: float = 1e-6


static func _load() -> Dictionary:
	if not _loaded:
		_loaded = true
		var path: String = "res://data/zone_ticks.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_data = parsed
	return _data


## Top-level entry of the file (e.g. "hammer_throw"), {} if none.
static func entry(key: String) -> Dictionary:
	var v: Variant = _load().get(key, {})
	return v if v is Dictionary else {}


## Object entry of an ability record name (e.g. "BlackHole"), {} if the object is not counted by ticks.
static func object_entry(ab_name: String) -> Dictionary:
	var objects: Variant = _load().get("objects", {})
	if objects is Dictionary:
		var v: Variant = (objects as Dictionary).get(ab_name, {})
		if v is Dictionary:
			return v
	return {}


## Ticks over a lifetime. Tick k needs the accumulated age to exceed k * interval (tick k happens in the frame that crosses it:
## RepeatedlyDamageEnemiesWithinRadius.OnUpdateTick), the crossing frame is still alive (DestroyAfterDuration.OnUpdateTick
## ends the object on the next update). A delay is counted down first, damageAtStart adds one tick at once.
static func ticks(lifetime: float, interval: float, delay: float, start: bool) -> int:
	var n: float = (lifetime - delay) / interval
	return maxi(int(floor(n + EPS)), 0) + (1 if start else 0)


## Ticks of the object of ability `ab_name` per use with the skill's lifetime parameter (tree «duration» increase):
## {ticks, lifetime, text}, or {} when the object is not counted. A channelled object lives as long as the channel (player
## behaviour): one tick, as before.
static func per_use(ab_name: String, s: Dictionary, build: Node) -> Dictionary:
	var obj: Dictionary = object_entry(ab_name)
	if obj.is_empty():
		return {}
	var chan: Dictionary = obj.get("channel_property", {})
	if not chan.is_empty() and float(ShadowCalc.ability_property(build, str(chan["ability_id"]), int(chan["index"]), int(chan["special"]))["value"]) > 0.0:
		return {"ticks": 1.0, "lifetime": 0.0, "text": LE.t("channelled: the object lives while the channel is held (player behaviour), counted as one tick")}
	var inc: float = SkillCalc._param_total(s, str(obj.get("duration_param", "")))
	var lifetime: float = float(obj["lifetime"]) * (1.0 + inc)
	var interval: float = float(obj["interval"])
	var count: int = ticks(lifetime, interval, float(obj.get("delay", 0.0)), int(obj.get("start", 0)) == 1)
	var text: String = LE.t("%d ticks of %s s over the lifetime %s s (D?: the enemy stays in the zone)") % [
		count, LE.fmt_num(interval), LE.fmt_num(lifetime)]
	return {"ticks": float(count), "lifetime": lifetime, "text": text}
