class_name DefenseRecovery

## Recovery of health and ward between enemy hits for the Defense tab (docs/ENGINE.md §10.3): regeneration, ward decay,
## the selected skill's leech and per-hit gains, and the resource effects of the build (skill tree, uniques, passives)
## whose amount is annotated in the models (`amount`, client/data/*.json). Everything becomes a list of sources
## {resource: health|ward, timing: rate|enemy_hit, base: flat|max|missing|current, k, label, text}:
## recovered = k × base (per second for "rate", per enemy hit for "enemy_hit"), base taken from the current health.

## Ward decay constants (GlobalPlayerProperties, research/06c §3.2).
const WARD_DECAY_Q: float = 0.00005
const WARD_DECAY_L: float = 0.2
const WARD_DECAY_MIN: float = 0.5
## Simulation: time step, and the number of hits after which the build counts as never dying.
const STEP: float = 0.05
const MAX_SIM_HITS: int = 2000
const STEPS_PER_SECOND: int = 20
const MAX_DOT_SECONDS: float = 600.0
## Own-event kinds of resource models and enemy-hit kinds (docs/ENGINE.md §9.1 `resource.on`).
const OWN_EVENTS: Array[String] = ["use", "hit", "crit", "second"]
const ENEMY_EVENTS: Array[String] = ["block", "dodge", "hit_taken", "glancing"]
const AMOUNT_BASES: Dictionary = {"flat": "flat", "max_health": "max", "missing_health": "missing", "current_health": "current"}
## HealthGain stats with a hit-event specialTag that are not the skill's own hits (ResourceGainEvents.UpdateResourceGainTotals).
## Only stats with tags 0 and extraTag 0 are totals; the health goes through BaseHealth.restoreHealth. The ward of these events
## (ProtectionClass.GainWard, its ward gain multiplier not modelled) is not counted.
## {special, prop (SP), label, input}: input "" = per blocked enemy hit, else the rate input of the player state.
const EVENT_GAINS: Array[Dictionary] = [
	{"special": 6, "prop": 38, "label": "Health gained on block", "input": ""},
	{"special": 3, "prop": 38, "label": "Health gained on kill", "input": "kills_per_second"},
	{"special": 5, "prop": 38, "label": "Health gained on stun", "input": "stuns_per_second"},
]


## {sources: Array[Dictionary], rows: Array, notes: Array[String], skill: String}
## avoid = {dodge, block, land}: chances of the enemy-hit events per enemy hit.
static func collect(build: Node, layers: Dictionary, avoid: Dictionary, interval: float) -> Dictionary:
	var sources: Array[Dictionary] = []
	var notes: Array[String] = []
	var mana: float = float(layers["mana"])
	_add(sources, "health", "rate", "flat", float(layers["health_regen"]), LE.t("Health regen"), "")
	_add(sources, "ward", "rate", "flat", float(layers["ward_regen"]), LE.t("Ward per second"), "")
	var slot: int = int(build.selected_skill)
	var skill_name: String = ""
	var r: Dictionary = SkillCalc.compute(build, slot)
	if not str(r.get("title", "")).is_empty():
		skill_name = str(r["title"])
		var rates: Dictionary = r.get("rates", {})
		var dps: float = 0.0
		for section: Dictionary in r.get("sections", []):
			for row: Dictionary in section.get("rows", []):
				var key: String = str(row.get("sustain", ""))
				if key == "leech" or key == "health_gain":
					_add(sources, "health", "rate", "flat", float(row["value"]), "%s: %s" % [skill_name, row["label"]], str(row.get("breakdown", "")))
				elif key == "ward_gain" or key == "ward_from_mana":
					_add(sources, "ward", "rate", "flat", float(row["value"]), "%s: %s" % [skill_name, row["label"]], str(row.get("breakdown", "")))
				if str(section.get("title", "")) == LE.t("Against enemy") and str(row.get("label", "")) == LE.t("DPS vs enemy"):
					dps = float(row.get("value", 0.0))
		for res: Dictionary in r.get("resources", []):
			_add_resource(sources, notes, res["model"], float(res["x"]), str(res["source"]), rates, dps, avoid, interval, mana)
	for res: Dictionary in passive_resources(build):
		_add_resource(sources, notes, res["model"], float(res["x"]), str(res["source"]), r.get("rates", {}), 0.0, avoid, interval, mana)
	sources.append_array(event_gains(BuildMods.global_store(build)["store"], build.player_state, avoid))
	return {"sources": sources, "notes": notes, "skill": skill_name}


## Recovery sources of the EVENT_GAINS health: per blocked enemy hit (k = amount x avoid["block"]) or per second (k = amount x rate input).
static func event_gains(store: StatStore, player_state: Dictionary, avoid: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in EVENT_GAINS:
		var amount: float = 0.0
		for mod: StatMod in store.mods_of(int(e["prop"])):
			if mod.special == int(e["special"]) and mod.tags == 0 and mod.extra == 0:
				amount += mod.added
		if is_zero_approx(amount):
			continue
		var label: String = LE.t(str(e["label"]))
		if str(e["input"]) == "":
			var p: float = float(avoid.get("block", 0.0))
			_add(out, "health", "enemy_hit", "flat", amount * p, label, LE.t("%s per event × %s per enemy hit") % [LE.fmt_num(amount), LE.fmt_num(p)])
		else:
			var rate: float = float(player_state.get(str(e["input"]), 0.0))
			_add(out, "health", "rate", "flat", amount * rate, label, LE.t("%s per event × %s events/s") % [LE.fmt_num(amount), LE.fmt_num(rate)])
	return out


static func _add(sources: Array[Dictionary], resource: String, timing: String, base: String, k: float, label: String, text: String,
		below: float = 0.0) -> void:
	if is_zero_approx(k):
		return
	var src: Dictionary = {"resource": resource, "timing": timing, "base": base, "k": k, "label": label, "text": text}
	if below > 0.0:
		src["below"] = below  # gained only when health after the hit is below this share of the maximum
	sources.append(src)


## Resource models of allocated passives aimed at the character (CharacterMutator.*): BuildMods lists them only as notes.
static func passive_resources(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in BuildMods._passive_entries(build):
		var points: int = entry["points"]
		for effect: Dictionary in (entry["node"] as Dictionary).get("effects", []):
			var target: String = str(effect.get("target", ""))
			if points < int(effect.get("minPoints", 0)) or not target.begins_with("CharacterMutator.") or effect.get("op") == "add_stat":
				continue
			var model: Dictionary = BuildMods._passive_model(target)
			if str(model.get("kind", "")) != "resource":
				continue
			var v: float = BuildMods.eval_value(effect.get("value"), points) if effect.has("value") else 0.0
			var ctx: Dictionary = {"build": build, "store": StatStore.new(), "slot": -1, "item_slot": ""}
			out.append({"model": model, "x": float(EffectModels.value(model, v, ctx)["x"]), "source": str(entry["source"])})
	return out


## One resource model → a recovery source, or a note when it cannot be counted.
static func _add_resource(sources: Array[Dictionary], notes: Array[String], model: Dictionary, x: float, source: String,
		rates: Dictionary, dps: float, avoid: Dictionary, interval: float, max_mana: float) -> void:
	var resource: String = str(model.get("resource", ""))
	var on: String = str(model.get("on", ""))
	var amount: String = str(model.get("amount", ""))
	var label: String = "%s — %s" % [source, LE.t(str(model.get("label", resource)))]
	if resource != "health" and resource != "ward":
		return
	if amount == "" or amount == "none" or bool(model.get("costs_health", false)):
		notes.append(LE.t("Recovery not counted: %s") % label)
		return
	var k: float = x * float(model.get("amount_factor", 1.0))
	var chance: float = float(model.get("amount_chance", 1.0))
	var cap: float = float(model.get("per_second_cap", 0.0))
	var base: String = str(AMOUNT_BASES.get(amount, "flat"))
	match amount:
		"max_mana", "current_mana":
			k *= max_mana  # the mana pool is not simulated: counted with full mana
		"mana_cost":
			k *= float(rates.get("mana", 0.0))
		"damage":
			if on != "hit" and on != "crit":
				notes.append(LE.t("Recovery not counted: %s") % label)
				return
			# a share of the damage dealt: per second of the selected skill's DPS
			var share: float = 1.0 if on == "hit" else float(rates.get("crit", 0.0))
			_add(sources, resource, "rate", "flat", k * dps * share * chance, label,
				LE.t("%s × DPS vs enemy %s") % [LE.fmt_pct(k), LE.fmt_num(dps)])
			return
	if OWN_EVENTS.has(on):
		var events: float = 1.0
		match on:
			"use":
				events = float(rates.get("uses", 0.0))
			"hit":
				events = float(rates.get("hits", 0.0))
			"crit":
				events = float(rates.get("hits", 0.0)) * float(rates.get("crit", 0.0))
		events *= chance
		if cap > 0.0:
			events = minf(events, cap)
		_add(sources, resource, "rate", base, k * events, label, LE.t("%s per event × %s events/s") % [LE.fmt_num(k), LE.fmt_num(events)])
	elif ENEMY_EVENTS.has(on):
		var p: float = float(avoid.get(on if on != "hit_taken" else "land", 0.0)) * chance
		if cap > 0.0 and interval > 0.0:
			p = minf(p, cap * interval)
		_add(sources, resource, "enemy_hit", base, k * p, label, LE.t("%s per event × %s per enemy hit") % [LE.fmt_num(k), LE.fmt_num(p)],
			float(model.get("health_below", 0.0)))
	else:
		notes.append(LE.t("Recovery not counted: %s") % label)


# --- simulation ---------------------------------------------------------------------------

static func _base(base: String, pool: Dictionary, max_health: float) -> float:
	match base:
		"max":
			return max_health
		"missing":
			return maxf(0.0, max_health - float(pool["health"]))
		"current":
			return maxf(0.0, float(pool["health"]))
	return 1.0


## Ward decay per second above the threshold (06c §3.2). `regen` = wardRegen + wardRegenFromStats: the minimum decay
## applies when it is not above 0 (ward gained by skills is not regeneration).
static func ward_decay(layers: Dictionary, ward: float, regen: float) -> float:
	var t: float = maxf(float(layers["ward_threshold"]), 0.0)
	if ward <= t:
		return 0.0
	var x: float = ward - t
	var decay: float = (WARD_DECAY_Q * x * x + WARD_DECAY_L * x) / (1.0 + 0.5 * maxf(float(layers["ward_retention"]), -0.9))
	if decay < WARD_DECAY_MIN and regen <= 0.0:
		decay = WARD_DECAY_MIN
	return minf(decay, x / STEP)


## Advances the pool by `seconds` of recovery (rate sources) and of the current health drain (SP 60) in place. Recovery clamps
## health at the cap of current health and ward at its cap (BaseHealth.restoreHealth, ProtectionClass.GainWard).
static func recover(layers: Dictionary, sources: Array[Dictionary], pool: Dictionary, seconds: float) -> void:
	var max_health: float = float(layers["health"])
	var health_cap: float = float(layers.get("health_limit", max_health))
	var ward_limit: float = float(layers.get("ward_limit", 0.0))
	var drain: float = float(layers.get("health_drain", 0.0))
	var t: float = 0.0
	while t < seconds - 1e-9:
		var dt: float = minf(STEP, seconds - t)
		var dh: float = 0.0
		var dw: float = 0.0
		for s: Dictionary in sources:
			if s["timing"] != "rate":
				continue
			var amount: float = float(s["k"]) * _base(str(s["base"]), pool, max_health)
			if s["resource"] == "health":
				dh += amount
			else:
				dw += amount
		pool["health"] = minf(health_cap, float(pool["health"]) + dh * dt)
		if drain > 0.0:
			# ProtectionClass.Update: HealthDamage(drain · currentHealth · dt), exponential decay; the ward does not take part
			pool["health"] = float(pool["health"]) * exp(-drain * dt)
		var w: float = float(pool["ward"]) + dw * dt
		if ward_limit > 0.0:
			w = minf(w, ward_limit)
		pool["ward"] = maxf(0.0, w - ward_decay(layers, w, float(layers.get("ward_regen", 0.0))) * dt)
		slow_damage(pool, dt)
		t += dt


## Delayed damage ticks (SlowDamageInstance): direct damage, only ward absorbs it (06c §2.10, §5.3).
static func slow_damage(pool: Dictionary, dt: float) -> void:
	var slow: Array = pool.get("slow", [])
	if slow.is_empty():
		return
	var dmg: float = 0.0
	var left: Array = []
	for entry: Array in slow:
		var step: float = minf(dt, float(entry[1]))
		dmg += float(entry[0]) * step
		if float(entry[1]) - step > 1e-9:
			left.append([entry[0], float(entry[1]) - step])
	pool["slow"] = left
	var ward: float = float(pool["ward"])
	var to_ward: float = minf(ward, dmg)
	pool["ward"] = ward - to_ward
	pool["health"] = float(pool["health"]) - (dmg - to_ward)


## Recovery right after an enemy hit (block / dodge / hit taken events).
static func on_enemy_hit(layers: Dictionary, sources: Array[Dictionary], pool: Dictionary) -> void:
	var max_health: float = float(layers["health"])
	for s: Dictionary in sources:
		if s["timing"] != "enemy_hit":
			continue
		var below: float = float(s.get("below", 0.0))
		# BaseHealth.valueWouldBeLowHealth: health after the hit strictly below 35% of the maximum
		if below > 0.0 and float(pool["health"]) >= below * max_health:
			continue
		var amount: float = float(s["k"]) * _base(str(s["base"]), pool, max_health)
		if s["resource"] == "health":
			pool["health"] = minf(float(layers.get("health_limit", max_health)), float(pool["health"]) + amount)
		else:
			pool["ward"] = float(pool["ward"]) + amount
			var cap: float = float(layers.get("ward_limit", 0.0))
			if cap > 0.0:
				pool["ward"] = minf(float(pool["ward"]), cap)


## True when the pool after a cycle is no worse than before it: health, ward and mana not lower, no more delayed damage queued.
static func _holds(before: Dictionary, pool: Dictionary) -> bool:
	return float(pool["health"]) >= float(before["health"]) - 1e-6 and float(pool["ward"]) >= float(before["ward"]) - 1e-6 \
		and float(pool.get("mana", 0.0)) >= float(before.get("mana", 0.0)) - 1e-6 \
		and DefenseCalc.pending_slow(pool) <= DefenseCalc.pending_slow(before) + 1e-6


## Hits of `d` (after every layer, average) every `interval` seconds until death, with recovery in between; the last hit is
## fractional. INF when the pool holds (a full cycle leaves health, ward and mana no lower and no more delayed damage queued);
## after MAX_SIM_HITS hits an estimate from the pool lost in the last cycle (INF if it lost nothing).
static func hits_to_die(layers: Dictionary, sources: Array[Dictionary], d: float, interval: float) -> float:
	if d <= 0.0:
		return INF
	var pool: Dictionary = DefenseCalc.full_pool(layers)
	var before: Dictionary = pool
	for n in range(1, MAX_SIM_HITS + 1):
		before = pool.duplicate(true)
		DefenseCalc.take_damage(layers, pool, d)
		if float(pool["health"]) <= 0.0:
			var lo: float = 0.0
			var hi: float = 1.0
			for _i in range(40):
				var mid: float = (lo + hi) * 0.5
				var trial: Dictionary = before.duplicate(true)
				DefenseCalc.take_damage(layers, trial, d * mid)
				if float(trial["health"]) <= 0.0:
					hi = mid
				else:
					lo = mid
			return float(n - 1) + hi
		on_enemy_hit(layers, sources, pool)
		recover(layers, sources, pool, interval)
		if float(pool["health"]) <= 0.0:
			return float(n)  # killed by the delayed share of the hits while waiting for the next one
		if n > 1 and _holds(before, pool):
			return INF
	return DefenseCalc.extrapolate_hits(MAX_SIM_HITS, before, pool)


## Seconds a constant damage over time (after every per-type layer) takes to kill from a full pool, recovering at the same
## time; ward, mana before health and endurance apply like to any damage (06c §1). INF when the pool holds.
static func seconds_to_die(layers: Dictionary, sources: Array[Dictionary], dps: float) -> float:
	if dps <= 0.0:
		return INF
	var pool: Dictionary = DefenseCalc.full_pool(layers)
	var steps: int = 0
	var t: float = 0.0
	var mark: Dictionary = pool.duplicate(true)
	while t < MAX_DOT_SECONDS:
		var before: Dictionary = pool.duplicate(true)
		DefenseCalc.take_damage(layers, pool, dps * STEP)
		if float(pool["health"]) <= 0.0:
			var lost: float = float(before["health"]) - float(pool["health"])
			return t + STEP * (float(before["health"]) / lost if lost > 0.0 else 1.0)
		recover(layers, sources, pool, STEP)
		steps += 1
		t = float(steps) / float(STEPS_PER_SECOND)
		if steps % STEPS_PER_SECOND == 0:
			if t > 1.5 and _holds(mark, pool):
				return INF
			if t >= MAX_DOT_SECONDS - 1e-6:
				var loss: float = DefenseCalc.pool_value(mark) - DefenseCalc.pool_value(pool)
				return INF if loss <= 1e-9 else t + maxf(DefenseCalc.pool_value(pool), 0.0) / loss
			mark = pool.duplicate(true)
	return INF


## Health and ward recovered per second at half health (for the rows): {health, ward}.
static func per_second(layers: Dictionary, sources: Array[Dictionary], interval: float) -> Dictionary:
	var pool: Dictionary = DefenseCalc.full_pool(layers)
	pool["health"] = float(layers["health"]) * 0.5
	var out: Dictionary = {"health": 0.0, "ward": 0.0}
	for s: Dictionary in sources:
		var below: float = float(s.get("below", 0.0))
		if below > 0.0 and float(pool["health"]) >= below * float(layers["health"]):
			continue  # gained only below the low-health line (half health is not)
		var amount: float = float(s["k"]) * _base(str(s["base"]), pool, float(layers["health"]))
		if s["timing"] == "enemy_hit":
			amount = amount / interval if interval > 0.0 else 0.0
		out[s["resource"]] = float(out[s["resource"]]) + amount
	return out
