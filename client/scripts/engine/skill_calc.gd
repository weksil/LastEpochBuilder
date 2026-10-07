class_name SkillCalc

## Skill numbers with breakdowns (docs/ENGINE.md §8, research/06b).

const ATTACK_TAGS: int = LE.SPELL | LE.MELEE | LE.THROWING | LE.BOW
## Order in which a mod's damage-type bit is resolved (06b §1.2): Physical, Lightning, Cold, Fire, Void, Necrotic, Poison.
const TYPE_RESOLVE_ORDER: Array[int] = [0, 3, 2, 1, 5, 4, 6]
## Trigger events whose frequency follows from the skill itself (docs/ENGINE.md §9.6); the rest are skill inputs `events_<on>`.
const OWN_EVENTS: Array[String] = ["use", "cast", "end", "hit", "crit", "second"]
const EVENT_NAMES: Dictionary = {
	"use": "use", "cast": "use", "end": "end", "hit": "hit", "crit": "crit", "second": "second",
	"kill": "kill", "hit_taken": "hit taken", "block": "block", "dodge": "dodge", "potion": "potion",
	"minion_hit": "minion hit", "minion_death": "minion death", "stun": "stun", "death": "death",
}


## {title, sections: [{title, rows: [{label, text, breakdown}]}], notes: [String]}
## Values of Build.skills[slot].projectile_mode: how many projectiles of one use hit the target (default "average").
const PROJECTILE_MODES: Array[String] = ["one", "average", "all"]
const PROJECTILE_MODE_NAMES: Dictionary = {"one": "One projectile", "average": "Average", "all": "All projectiles"}


## The enemy ailments and the buffs on you the calculation sees: the Conditions values plus the averages kept while the
## skill is used (EnemyAilments, docs/ENGINE.md §9.11); `auto_ailments` / `auto_buffs` of the result list the averages.
## Cached by the build state, the slot and the engine flags it reads (CalcCache); every call gets its own deep copy.
## details = false: a lean result for callers that read numbers only or build the breakdowns on demand — every row
## breakdown of the sections is "" and the row has `lazy` = true, the result has `lean` = true, and the texts are not
## built at all (LE.details); numbers, row texts and notes are the same as with details.
static func compute(build: Node, slot: int, details: bool = true) -> Dictionary:
	if ConfigRelevance._recording:
		return _compute_with(build, slot, details)
	var key: Array = [CalcCache.build_key(build), slot, EnemyAilments.enabled, EnemyAilments._busy, MinionCount._busy]
	var hit: Variant = CalcCache.lookup("skill_calc", key + [details])
	if hit == null and not details:
		var full: Variant = CalcCache.lookup("skill_calc", key + [true])
		if full != null:
			hit = (full as Dictionary).duplicate(true)
			_make_lean(hit)
			CalcCache.put("skill_calc", key + [false], hit)
	if hit == null:
		hit = _compute_with(build, slot, details)
		CalcCache.put("skill_calc", key + [details], hit)
	return (hit as Dictionary).duplicate(true)


static func _compute_with(build: Node, slot: int, details: bool) -> Dictionary:
	var saved_details: bool = LE.details
	LE.details = details
	var result: Dictionary = _compute_applied(build, slot)
	LE.details = saved_details
	if not details:
		_make_lean(result)
	return result


## Empties the section row breakdowns of a result (they may be partly built while LE.details is off) and marks it lean.
## The projectile row (also a row of a section, the same dictionary) is cheap and keeps its breakdown as its own copy
## (the tooltip of the projectile selector).
static func _make_lean(result: Dictionary) -> void:
	var proj: Dictionary = result.get("projectiles", {})
	var proj_row: Dictionary = (proj["row"] as Dictionary).duplicate() if proj.has("row") else {}
	for section: Dictionary in result.get("sections", []):
		for row: Dictionary in section.get("rows", []):
			row["breakdown"] = ""
			row["lazy"] = true
	if proj.has("row"):
		proj["row"] = proj_row
	result["lean"] = true


static func _compute_applied(build: Node, slot: int) -> Dictionary:
	var saved: Dictionary = EnemyAilments.apply(build, slot)
	var result: Dictionary = _compute(build, slot)
	EnemyAilments.restore(build, saved)
	result["auto_ailments"] = saved["auto"]
	result["auto_buffs"] = saved["buffs"]
	return result


static func _compute(build: Node, slot: int) -> Dictionary:
	var result: Dictionary = {"title": "", "sections": [], "notes": [], "inputs": [], "hits": 1.0}
	if slot < 0 or slot >= build.skills.size():
		return result
	var ab: Dictionary = GameData.get_ability(str(build.skills[slot].get("ability", "")))
	if ab.is_empty():
		return result
	result["title"] = str(ab.get("abilityName", ab.get("name", "")))

	var g: Dictionary = BuildMods.global_store(build)
	var s: Dictionary = BuildMods.skill_store(build, slot, g["store"])
	var store: StatStore = s["store"]
	var notes: Array[String] = []
	for n: String in g["notes"] + s["notes"]:
		if not notes.has(n):
			notes.append(n)

	var primary_base: Dictionary = ab.get("primaryDamage", {}) if ab.get("primaryDamage") is Dictionary else {}
	var head_ctx: Dictionary = _context(build, ab, store, s["conversions"], notes, primary_base)
	var speed: Dictionary = _speed(build, ab, head_ctx, s)
	var uses: float = float(speed["uses"])
	var hits: float = float(build.skills[slot].get("hits", 1.0))
	# projectiles of one use that hit the target multiply the hits per use of every component (docs/ENGINE.md §9.9)
	var proj: Dictionary = projectile_hits(build, slot, ab, s)
	var target_hits: float = hits * float(proj.get("factor", 1.0))
	var inputs: Array[Dictionary] = []
	var s_comp: Dictionary = s.duplicate()
	s_comp["triggers"] = _resolve_triggers(build, slot, s, head_ctx, uses, target_hits, inputs, notes)
	var comp_notes: Array[String] = []
	var components: Array[Dictionary] = SkillComponents.collect(build, slot, ab, s_comp, comp_notes)
	# active shadows repeat the use of the skills they imitate (docs/ENGINE.md §9.10)
	var own_components: Array[Dictionary] = components.duplicate()
	components.append_array(ShadowCalc.components(build, slot, ab, g["store"], own_components, s, comp_notes))
	components.append_array(EchoCalc.components(build, slot, ab, g["store"], own_components, s))
	# minions that fire projectiles: their attack rate is multiplied the same way (the skill's mode and tree params)
	var proj_rows: Array = []
	if not proj.is_empty():
		proj_rows.append(proj["row"])
	for comp: Dictionary in components:
		if comp["kind"] != "minion":
			continue
		var mp: Dictionary = projectile_hits(build, slot, comp["ab"], s)
		if mp.is_empty():
			continue
		comp["rate"] = float(comp["rate"]) * float(mp["factor"])
		mp["row"]["label"] = "%s: %s" % [comp["name"], mp["row"]["label"]]
		proj_rows.append(mp["row"])
		if proj.is_empty() or (mp["shotgun"] and not proj["shotgun"]):
			proj = mp
	# inputs declared while collecting components (e.g. the number of minions)
	for inp: Variant in s.get("inputs", []):
		if inp is Dictionary:
			_add_input(inputs, inp)
	for n: String in comp_notes:
		if not notes.has(n):
			notes.append(n)
	var sections: Array = []
	var enemy_rows: Array = []
	var extra_enemy_sections: Array = []
	var comp_results: Array[Dictionary] = []
	var ail_notes: Array[String] = []
	var sustain_hits: Array[Dictionary] = []
	var main_crit: float = 0.0
	if components.is_empty():
		notes.push_front(LE.t("The skill has no hit damage in its main component (damage is set by code or sub-skills) — speed, mana and ailments are shown."))
		if not head_ctx["conversion_rows"].is_empty():
			sections.append({"title": LE.t("Conversions and tags"), "rows": head_ctx["conversion_rows"]})
		sections.append({"title": LE.t("Speed and mana"), "rows": speed["rows"]})
		# a skill that is a zone (Aura of Decay) applies its ailments through the zone below, not per use
		if AilmentCalc.zones(ab).is_empty():
			var head_ail: Dictionary = AilmentCalc.compute(build, head_ctx, uses, ail_notes)
			sections.append_array(head_ail["sections"])
			_tag_applied(head_ail, "use", "")
			comp_results.append({"name": "", "hit_enemy": 0.0, "ail": head_ail, "events": uses})
	var own_count: int = components.size()
	var idx: int = 0
	while idx < components.size():
		var comp: Dictionary = components[idx]
		var prefix: String = "" if idx == 0 else "%s: " % comp["name"]
		var comp_store: StatStore = _component_store(store, s, comp)
		var ctx: Dictionary = head_ctx if comp["kind"] == "primary" and comp_store == store else _context(build, comp["ab"], comp_store, comp.get("conversions", s["conversions"]), notes, comp["base"])
		var is_curse: bool = comp["kind"] == "curse_hit"
		var is_dot: bool = comp["kind"] == "dot"
		var events: float = float(comp["rate"])
		if events <= 0.0 and not is_curse:
			events = uses * float(comp["per_use"]) * (1.0 if comp["kind"] == "trigger" else (hits if comp.get("single_projectile", false) else target_hits))
		var comp_speed: Dictionary = {"uses": events, "rows": [], "unit": LE.t("damage events") if is_curse else LE.t("uses")}
		var ds: Dictionary = _build_damage(ctx)
		var damage_rows: Array = ds["rows"]
		if idx == 0 and not is_dot:
			main_crit = clampf(float(ds["cc"]), 0.0, 1.0)
		var damage_title: String = LE.t("Damage per use (before enemy)")
		if is_dot:
			comp_speed["dot_duration"] = float(comp["duration"])
			comp_speed["dot_duration_inc"] = float(comp.get("duration_inc", 0.0))
			comp_speed["unit"] = LE.t("effect instances")
			damage_rows = _dot_damage_rows(comp, ds, uses)
			damage_title = LE.t("Effect damage over its whole duration (before enemy)")
		elif idx > 0 or is_curse or not is_equal_approx(events, uses):
			damage_rows = [_events_row(comp, events, uses, hits if comp.get("single_projectile", false) else target_hits)] + damage_rows
		if is_curse:
			damage_title = LE.t("Damage per hit on the cursed target (before enemy)")
		sections.append({"title": prefix + damage_title, "rows": damage_rows})
		if not ctx["conversion_rows"].is_empty():
			sections.append({"title": prefix + LE.t("Conversions and tags"), "rows": ctx["conversion_rows"]})
		if is_dot:
			# a DoT cannot crit: only the penetration rows remain
			var pen_rows: Array = []
			for crit_row: Dictionary in ds["crit_rows"]:
				if str(crit_row["label"]).begins_with(LE.t("Penetration")):
					pen_rows.append(crit_row)
			if not pen_rows.is_empty():
				sections.append({"title": prefix + LE.t("Penetration"), "rows": pen_rows})
		else:
			sections.append({"title": prefix + LE.t("Crit"), "rows": ds["crit_rows"]})
		if idx == 0:
			sections.append({"title": LE.t("Speed and mana"), "rows": speed["rows"]})
		var comp_enemy: Array = _vs_enemy(build, ctx, ds, comp_speed, notes)
		# curse hits: damage (and leech) follow the weighted rate, per-hit gains and ailment chances the plain hit count
		# a maintained DoT is applied by the casts: ailment chances roll per cast, not per damage event
		var hit_events: float = float(comp.get("hit_rate", events)) if is_curse else (uses if is_dot else events)
		sustain_hits.append({"name": str(comp["name"]) if idx > 0 else "", "ctx": ctx, "speed": comp_speed, "gain_events": hit_events})
		var ail: Dictionary = AilmentCalc.compute(build, ctx, hit_events, ail_notes, is_curse, {},
			_hit_events_text(comp, uses, hits, proj, hit_events, is_dot))
		_tag_applied(ail, str(comp["kind"]), str(comp["name"]))
		for section: Dictionary in ail["sections"]:
			sections.append({"title": prefix + str(section["title"]), "rows": section["rows"]})
		if idx == 0:
			enemy_rows = comp_enemy
		else:
			extra_enemy_sections.append({"title": prefix + LE.t("Against enemy"), "rows": comp_enemy})
		comp_results.append({"name": str(comp["name"]), "hit_enemy": float(comp_speed["enemy_dps"]),
			"ail": ail, "events": events})
		idx += 1
		# after the skill's own components: the strikes of threshold ailments it builds up (Shadow Daggers at 4 stacks)
		if idx == own_count:
			components.append_array(EnemyAilments.threshold_components(build, store, comp_results, notes))
	# zones of the skill, its parts and the abilities its nodes grant that apply ailments every interval without a hit
	for zr: Dictionary in _zone_results(build, ab, s, components, store, notes, ail_notes):
		for section: Dictionary in zr["ail"]["sections"]:
			sections.append({"title": "%s: %s" % [zr["name"], section["title"]], "rows": section["rows"]})
		comp_results.append(zr)
	if comp_results.is_empty():
		comp_results.append({"name": "", "hit_enemy": 0.0, "ail": {"sections": [], "enemy_dps": 0.0, "applied": []}, "events": uses})
	for n: String in ail_notes:
		if not notes.has(n):
			notes.append(n)

	var total_enemy: float = 0.0
	var enemy_lines: PackedStringArray = []
	for cr: Dictionary in comp_results:
		var ail_e: float = float(cr["ail"]["enemy_dps"])
		total_enemy += float(cr["hit_enemy"]) + ail_e
		enemy_lines.append(LE.t("%s: hit %s + ailments %s = %s") % [cr["name"], LE.fmt_num(cr["hit_enemy"]), LE.fmt_num(ail_e), LE.fmt_num(float(cr["hit_enemy"]) + ail_e)])
	var main: Dictionary = comp_results[0]
	if float(main["ail"]["enemy_dps"]) > 0.0:
		enemy_rows.append({"label": LE.t("Ailment DPS vs enemy"), "text": LE.fmt_num(main["ail"]["enemy_dps"]), "breakdown": LE.t("Sum of the DPS of all ailments vs enemy (the \"Ailment: …\" sections).")})
	if comp_results.size() > 1:
		for cr: Dictionary in comp_results:
			enemy_rows.append({"label": LE.t("DPS vs enemy: %s") % cr["name"], "text": LE.fmt_num(float(cr["hit_enemy"]) + float(cr["ail"]["enemy_dps"])), "breakdown":
				LE.t("Damage events per second: %s.\nHit %s + ailments %s.") % [LE.fmt_num(cr["events"]), LE.fmt_num(cr["hit_enemy"]), LE.fmt_num(cr["ail"]["enemy_dps"])]})
	enemy_rows.push_front({"label": LE.t("Target"), "text": Enemy.describe(build.enemy), "breakdown":
		LE.t("Hidden level-based damage reduction of the target: %s (table from the game code; boss and mini-boss keep + 5%% of the remainder).\nTarget type, level and corruption are set on the Conditions tab.") % LE.fmt_pct(Enemy.level_dr(build.enemy))})
	var corruption: int = int(build.enemy.get("corruption", 0))
	if corruption > 0:
		var more: Dictionary = Enemy.corruption_more(build.enemy)
		enemy_rows.append({"label": LE.t("Corruption"), "text": LE.t("health and hits +%s more, DoT +%s more") % [
			LE.fmt_pct(more["health"]), LE.fmt_pct(more["dot"])], "breakdown":
			LE.t("Corruption %d: f(c) = %s (0.6c up to 100, 0.002·c^1.52 + 1.055c − 47.69 above).\nThe enemy gets %s more health and hit damage and %s more DoT damage.\nCorruption does not change your DPS.") % [
			corruption, LE.fmt_num(Enemy.corruption_power(corruption)), LE.fmt_pct(more["health"]), LE.fmt_pct(more["dot"])]})
	enemy_rows.append_array(proj_rows)
	enemy_rows.append({"label": LE.t("DPS vs enemy"), "text": LE.fmt_num(total_enemy), "value": total_enemy, "breakdown":
		"\n".join(enemy_lines) if comp_results.size() > 1 else LE.t("Hit %s + ailments %s = %s") % [
			LE.fmt_num(main["hit_enemy"]), LE.fmt_num(main["ail"]["enemy_dps"]), LE.fmt_num(total_enemy)]})
	var param_rows: Array = _param_rows(s)
	for flag: String in s.get("flags", []):
		param_rows.append({"label": LE.t("Mechanic"), "text": LE.t("yes"), "breakdown": flag})
	if not param_rows.is_empty():
		sections.append({"title": LE.t("Skill parameters"), "rows": param_rows})
	sections.append({"title": LE.t("Against enemy"), "rows": enemy_rows})
	sections.append_array(extra_enemy_sections)
	var sustain_rows: Array = _sustain_rows(head_ctx, sustain_hits, uses, float(speed["mana"]))
	sustain_rows.append_array(ShadowCalc.sustain_rows(build, ab, s, uses))
	if not sustain_rows.is_empty():
		sections.append({"title": LE.t("Sustain"), "rows": sustain_rows})
	result["sections"] = sections
	result["notes"] = notes
	result["inputs"] = _inputs_result(build, slot, inputs)
	result["hits"] = hits
	result["projectiles"] = proj
	# numbers for the Defense tab (recovery between enemy hits): events per second of the skill and its resource effects
	var hit_rate: float = 0.0
	for hs: Dictionary in sustain_hits:
		if bool(hs["ctx"].get("hit", false)):
			hit_rate += float(hs["gain_events"])
	result["rates"] = {"uses": uses, "hits": hit_rate, "crit": main_crit, "mana": float(speed["mana"])}
	result["cooldown"] = bool(speed.get("cooldown", false))
	result["flag_keys"] = s.get("flag_keys", [])
	result["params"] = s.get("params", {})
	var applied: Array[Dictionary] = []
	for cr: Dictionary in comp_results:
		applied.append_array(cr["ail"].get("applied", []))
	result["ailments_applied"] = applied
	result["resources"] = s.get("resources", [])
	return result


## Projectiles of a projectile skill (ability_projectiles.json plus the tree params "projectiles", "projectile_limit",
## "shotgun") and how many of them hit one target, by the slot's `projectile_mode` (one | average | all, default
## average). {} for skills without projectiles, else {count, shotgun, mode, factor, row}.
## Projectiles of one use share a hit list unless the skill can shotgun (research: Ability.sharedHitDetector), so then
## only one of them damages a given target, and the explosions they spawn inherit the same list.
static func projectile_hits(build: Node, slot: int, ab: Dictionary, s: Dictionary) -> Dictionary:
	var info: Dictionary = GameData.projectile_info(str(ab.get("name", "")))
	if info.is_empty():
		return {}
	var count: float = float(info.get("projectiles", 1))
	var shotgun: bool = bool(info.get("shotgun", false))
	var limit: float = -1.0
	var lines: PackedStringArray = [LE.t("Base projectiles per use: %s") % LE.fmt_num(count)]
	var params: Variant = s.get("params", {})
	if params is Dictionary:
		for label: Variant in params:
			var p: Dictionary = params[label]
			var value: float = (float(p["set"]) if p.get("set") != null else float(p.get("added", 0.0))) 				* (1.0 + float(p.get("increased", 0.0))) * float(p.get("more", 1.0))
			match str(p.get("param", "")):
				"projectiles":
					count += value
					lines.append("%s: %s" % [label, LE.fmt_num(value)])
				"projectile_limit":
					limit = value
				"shotgun":
					if value > 0.0:
						shotgun = true
						lines.append(str(label))
	if limit >= 0.0 and count > 1.0 + limit:
		count = 1.0 + limit
		lines.append(LE.t("Limited to %s extra projectiles") % LE.fmt_num(limit))
	count = maxf(count, 1.0)
	var mode: String = PROJECTILE_MODES[1]
	if slot >= 0 and slot < build.skills.size():
		mode = str(build.skills[slot].get("projectile_mode", mode))
	if not PROJECTILE_MODES.has(mode):
		mode = PROJECTILE_MODES[1]
	var factor: float = 1.0
	if not shotgun:
		lines.append(LE.t("Projectiles of one use cannot hit the same target: one projectile per target (their explosions share the same hit list)."))
	elif mode == "all":
		factor = count
		lines.append(LE.t("All projectiles hit the target: %s") % LE.fmt_num(factor))
	elif mode == "average":
		factor = (1.0 + count) / 2.0
		lines.append(LE.t("Average of one and all projectiles: (1 + %s) / 2 = %s") % [LE.fmt_num(count), LE.fmt_num(factor)])
	else:
		lines.append(LE.t("One projectile hits the target"))
	if str(info.get("confidence", "D")) != "D":
		lines.append(LE.t("Projectile count is an estimate: %s") % str(info.get("evidence", "")))
	lines.insert(0, LE.t("Shotgun (several projectiles of one use hit one target): %s") % (LE.t("yes") if shotgun else LE.t("no")))
	lines.insert(1, LE.t("Max projectiles per use: %s") % LE.fmt_num(count))
	var row: Dictionary = {"label": LE.t("Projectiles hitting the target"), "text": "%s / %s" % [LE.fmt_num(factor), LE.fmt_num(count)],
		"value": factor, "breakdown": "\n".join(lines)}
	return {"count": count, "shotgun": shotgun, "mode": mode, "factor": factor, "row": row}


# --- triggers, inputs, parameters (docs/ENGINE.md §9.6) ----------------------------

static func _event_name(on: String) -> String:
	return LE.t(str(EVENT_NAMES.get(on, on)))


## Event rate -> component rate: event × chance × count, at most count / icd. Returns {rate, event, text}.
## `event_rate` is the skill input events_<on> for events that do not follow from the skill itself.
static func trigger_rate(trig: Dictionary, uses: float, hits: float, crit: float, event_rate: float) -> Dictionary:
	var on: String = str(trig.get("on", "use"))
	var event: float
	var text: String
	match on:
		"use", "cast", "end":
			event = uses
			text = LE.t("event \"%s\" = uses/s %s") % [_event_name(on), LE.fmt_num(uses)]
		"hit":
			event = uses * hits
			text = LE.t("hits/s = uses/s %s × hits %s = %s") % [LE.fmt_num(uses), LE.fmt_num(hits), LE.fmt_num(event)]
		"crit":
			event = uses * hits * minf(1.0, crit)
			text = LE.t("crits/s = uses/s %s × hits %s × crit chance %s = %s") % [LE.fmt_num(uses), LE.fmt_num(hits), LE.fmt_pct(minf(1.0, crit)), LE.fmt_num(event)]
		"second":
			event = 1.0
			text = LE.t("once per second")
		_:
			event = event_rate
			text = LE.t("events \"%s\" per second (input \"events_%s\") = %s") % [_event_name(on), on, LE.fmt_num(event_rate)]
	var chance: float = float(trig.get("chance", 1.0))
	var count: float = float(trig.get("count", 1.0))
	var icd: float = float(trig.get("icd", 0.0))
	var rate: float = event * chance * count
	var line: String = LE.t("%s; chance %s × count %s → %s/s") % [text, LE.fmt_pct(chance), LE.fmt_num(count), LE.fmt_num(rate)]
	if icd > 0.0:
		var cap: float = count / icd
		if rate > cap:
			line += LE.t("; capped by cooldown %s s: %s/s") % [LE.fmt_num(icd), LE.fmt_num(cap)]
			rate = cap
		else:
			line += LE.t("; trigger cooldown %s s (limit %s/s) not reached") % [LE.fmt_num(icd), LE.fmt_num(cap)]
	return {"rate": rate, "event": event, "text": line}


## Triggers of the skill with `rate`, `label`, `note` filled in; collects the declared inputs (skill and event ones).
static func _resolve_triggers(build: Node, slot: int, s: Dictionary, head_ctx: Dictionary, uses: float, hits: float,
		inputs: Array[Dictionary], notes: Array[String]) -> Array:
	for inp: Variant in s.get("inputs", []):
		if inp is Dictionary:
			_add_input(inputs, inp)
	var result: Array = []
	var crit: float = -1.0
	for trig: Variant in s.get("triggers", []):
		if not trig is Dictionary:
			continue
		var on: String = str(trig.get("on", "use"))
		var event_rate: float = 0.0
		if not OWN_EVENTS.has(on):
			var key: String = "events_" + on
			_add_input(inputs, {"key": key, "label": LE.t("Events per second: %s") % _event_name(on), "default": 0.0})
			event_rate = float(build.skills[slot].get("inputs", {}).get(key, 0.0))
		if on == "crit" and crit < 0.0:
			crit = float(_build_damage(head_ctx)["cc"])
		var rate_info: Dictionary = trigger_rate(trig, uses, hits, maxf(crit, 0.0), event_rate)
		var sub: Dictionary = GameData.ability_by_name(str(trig.get("ability", "")))
		var label: String = str(sub.get("abilityName", sub.get("name", trig.get("ability", ""))))
		var copy: Dictionary = trig.duplicate()
		copy["rate"] = float(rate_info["rate"])
		copy["label"] = label
		copy["note"] = LE.t("trigger, node \"%s\": %s") % [trig.get("node", "?"), rate_info["text"]]
		result.append(copy)
		if float(rate_info["rate"]) <= 0.0:
			var note: String = LE.t("Trigger \"%s\" (%s): 0 events/s — set the rate on the Calculations tab") % [label, _event_name(on)]
			if not notes.has(note):
				notes.append(note)
	return result


static func _add_input(inputs: Array[Dictionary], inp: Dictionary) -> void:
	for existing: Dictionary in inputs:
		if existing["key"] == inp.get("key", ""):
			return
	inputs.append(inp.duplicate())


## Inputs with their current values: Build.skills[slot].inputs[key] or the default.
static func _inputs_result(build: Node, slot: int, inputs: Array[Dictionary]) -> Array[Dictionary]:
	var current: Dictionary = build.skills[slot].get("inputs", {})
	var out: Array[Dictionary] = []
	for inp: Dictionary in inputs:
		var entry: Dictionary = inp.duplicate()
		entry["value"] = current.get(str(inp["key"]), inp.get("default", 0.0))
		out.append(entry)
	return out


## Store with the mods meant for this component only (component_mods of the skill, matched by ability name).
## Where the hits on the target per second of a component come from (the ailment chances roll per hit): uses/s × per use ×
## hits per use × projectiles hitting the target (the slot's projectile mode); a fixed rate for triggers and minions.
static func _hit_events_text(comp: Dictionary, uses: float, hits: float, proj: Dictionary, events: float, is_dot: bool) -> String:
	if is_dot:
		return LE.t("A maintained DoT rolls its chances once per cast: uses/s %s.") % LE.fmt_num(uses)
	if float(comp["rate"]) > 0.0 or comp["kind"] == "trigger" or comp["kind"] == "curse_hit":
		return LE.t("Hits on the target per second: %s (fixed rate of the component).") % LE.fmt_num(events)
	var text: String = LE.t("Hits on the target per second = uses/s %s × per use %s × hits per use %s") % [
		LE.fmt_num(uses), LE.fmt_num(float(comp["per_use"])), LE.fmt_num(hits)]
	if not proj.is_empty() and not comp.get("single_projectile", false):
		text += LE.t(" × projectiles hitting the target %s (mode «%s»)") % [LE.fmt_num(float(proj["factor"])), LE.t(PROJECTILE_MODE_NAMES.get(str(proj["mode"]), str(proj["mode"])))]
	return text + " = %s" % LE.fmt_num(events)


## Marks the applications of an AilmentCalc result with the kind and the name of their source (EnemyAilments: parallel
## sources of the other bar skills, the breakdown on the Conditions tab).
static func _tag_applied(ail: Dictionary, kind: String, source: String) -> void:
	for a: Dictionary in ail.get("applied", []):
		a["kind"] = kind
		a["source"] = source


## Zones (AilmentCalc.zones) of the skill, of the abilities of its components and of the abilities its tree grants as
## components or triggers (with or without damage). Each zone is assumed to stand on the target all the time (D?).
## [{name, hit_enemy: 0, ail, events}]
static func _zone_results(build: Node, ab: Dictionary, s: Dictionary, components: Array[Dictionary], store: StatStore,
		notes: Array[String], ail_notes: Array[String]) -> Array[Dictionary]:
	var abilities: Array[Dictionary] = [ab]
	for comp: Dictionary in components:
		if comp["kind"] != "minion" and comp["ab"] is Dictionary:
			abilities.append(comp["ab"])
	for key: String in ["components", "triggers"]:
		for extra: Variant in s.get(key, []):
			if extra is Dictionary:
				abilities.append(GameData.ability_by_name(str(extra.get("ability", ""))))
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for zab: Dictionary in abilities:
		var zab_name: String = str(zab.get("name", ""))
		if zab_name == "" or seen.has(zab_name):
			continue
		seen[zab_name] = true
		for zone: Dictionary in AilmentCalc.zones(zab):
			zone["mods"] = (s["store"] as StatStore).mods if zab_name == str(ab.get("name", "")) else []
			var ctx: Dictionary = _context(build, zab, store, s["conversions"], notes, {})
			var ail: Dictionary = AilmentCalc.compute(build, ctx, 0.0, ail_notes, false, zone)
			var label: String = LE.t("Zone \"%s\"") % str(zone["name"])
			_tag_applied(ail, "zone", label)
			if not ail["applied"].is_empty():
				out.append({"name": label, "hit_enemy": 0.0, "ail": ail, "events": 1.0 / float(zone["interval"])})
	return out


static func _component_store(store: StatStore, s: Dictionary, comp: Dictionary) -> StatStore:
	if comp.get("store") is StatStore:
		return comp["store"]
	var by_name: Variant = s.get("component_mods", {})
	if not by_name is Dictionary or (by_name as Dictionary).is_empty():
		return store
	var extra: Array[StatMod] = []
	var comp_ab: Dictionary = comp["ab"]
	for key: String in [str(comp_ab.get("name", "")), str(comp_ab.get("abilityName", "")), str(comp["name"])]:
		if key != "" and by_name.has(key):
			for mod: Variant in by_name[key]:
				if mod is StatMod and not extra.has(mod):
					extra.append(mod)
	if extra.is_empty():
		return store
	var child := StatStore.new()
	child.parent = store
	child.add_all(extra)
	return child


static func _param_rows(s: Dictionary) -> Array:
	var rows: Array = []
	var params: Variant = s.get("params", {})
	if not params is Dictionary:
		return rows
	for label: Variant in params:
		var p: Dictionary = params[label]
		var inc: float = float(p.get("increased", 0.0))
		var more: float = float(p.get("more", 1.0))
		var is_set: bool = p.get("set") != null
		var base: float = float(p["set"]) if is_set else float(p.get("added", 0.0))
		var value: float = base * (1.0 + inc) * more
		var b: PackedStringArray = PackedStringArray(p.get("sources", []))
		var text: String = LE.fmt_num(value)
		if base == 0.0 and (inc != 0.0 or more != 1.0):
			var parts: PackedStringArray = []
			if inc != 0.0:
				parts.append("%s%s increased" % ["+" if inc > 0.0 else "", LE.fmt_pct(inc)])
			if more != 1.0:
				parts.append("×%s more" % LE.fmt_num(more))
			text = ", ".join(parts)
		b.append("%s %s × (1 + %s) × %s = %s" % [LE.t("Set") if is_set else LE.t("Added"), LE.fmt_num(base), LE.fmt_pct(inc), LE.fmt_num(more), LE.fmt_num(value)])
		rows.append({"label": str(label), "text": text, "breakdown": "\n".join(b)})
	return rows


static func _events_row(comp: Dictionary, events: float, uses: float, hits: float) -> Dictionary:
	var b: PackedStringArray = []
	if comp["kind"] == "curse_hit":
		b.append(str(comp["event_text"]))
	elif float(comp["rate"]) > 0.0:
		b.append((LE.t("Event rate: %s per second.") if comp["kind"] == "echo" else LE.t("Event rate (trigger): %s per second.")) % LE.fmt_num(events))
	else:
		var hits_text: String = LE.t(" × hits %s") % LE.fmt_num(hits) if comp["kind"] != "trigger" and hits != 1.0 else ""
		b.append(LE.t("Uses/s %s × per use %s%s = %s") % [LE.fmt_num(uses), LE.fmt_num(comp["per_use"]), hits_text, LE.fmt_num(events)])
	if str(comp["note"]) != "":
		b.append(LE.t("Source: %s") % comp["note"])
	return {"label": LE.t("Damage events per second"), "text": LE.fmt_num(events), "breakdown": "\n".join(b)}


## Rows of the damage section of a maintained DoT (kind `dot`): the total over the base duration and the damage per second.
static func _dot_damage_rows(comp: Dictionary, ds: Dictionary, uses: float) -> Array:
	var duration: float = float(comp["duration"])
	var rows: Array = []
	for row: Dictionary in ds["rows"]:
		if row["label"] != LE.t("Total per hit (no crit)"):
			rows.append(row)
	rows.append({"label": LE.t("Damage over the whole duration (%s s)") % LE.fmt_num(duration), "text": LE.fmt_num(ds["total"]), "breakdown":
		LE.t("Sum over damage types: the full damage of one instance over the base duration %s s (in the game data the base damage is the whole damage of the action, not damage per second).\nPeriodic damage has no crit and no variance.") % LE.fmt_num(duration)})
	rows.append({"label": LE.t("Damage per second"), "text": LE.fmt_num(float(ds["total"]) * float(comp["rate"])), "breakdown": _dot_rate_text(comp, float(ds["total"]), uses)})
	return rows


static func _dot_rate_text(comp: Dictionary, total: float, uses: float) -> String:
	var duration: float = float(comp["duration"])
	var b: PackedStringArray = []
	b.append(LE.t("One instance per target (maxInstances 1), kept up by recasting (uses/s %s, 100%% uptime): damage events per second = 1 / %s s = %s.") % [
		LE.fmt_num(uses), LE.fmt_num(duration), LE.fmt_num(float(comp["rate"]))])
	b.append(LE.t("Damage per second = %s / %s s = %s.") % [LE.fmt_num(total), LE.fmt_num(duration), LE.fmt_num(total * float(comp["rate"]))])
	var inc: float = float(comp.get("duration_inc", 0.0))
	if inc != 0.0:
		b.append(LE.t("Duration +%s: the effect lasts %s s and deals ×%s damage (%s) — damage per second is unchanged.") % [
			LE.fmt_pct(inc), LE.fmt_num(duration * (1.0 + inc)), LE.fmt_num(1.0 + inc), LE.fmt_num(total * (1.0 + inc))])
	else:
		b.append(LE.t("Increased duration stretches the effect and raises its total damage in the same proportion, so damage per second does not change."))
	b.append(LE.t("If used less often than once per %s s, the effect is idle and average damage per second is lower (D?: tick timing is not modelled).") % LE.fmt_num(duration))
	if str(comp["note"]) != "":
		b.append(LE.t("Source: %s") % comp["note"])
	return "\n".join(b)


# --- 8.1 context ------------------------------------------------------------------

static func _context(build: Node, ab: Dictionary, store: StatStore, conversions: Array, notes: Array[String], base: Dictionary) -> Dictionary:
	var tags: int = int(ab.get("tags", 0))
	var hit: bool = int(base.get("isHit", 1)) == 1
	var src: int = 0
	var dmg: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var damage: Array = base.get("damage", [])
	for i in range(mini(7, damage.size())):
		dmg[i] = float(damage[i])
	var conv: Dictionary = _apply_conversions(tags, dmg, conversions, notes)
	tags = conv["tags"]
	src = ((tags & ~LE.DOT) | LE.HIT) if hit else ((tags & ~LE.HIT) | LE.DOT)
	src |= _health_tags(build)
	var type_bits: int = 0
	for i in range(7):
		if dmg[i] > 0.0:
			type_bits |= LE.DT_TAG[i]
	var ability_index: int = int(ab.get("abilityIDEnum", {}).get("value", -1)) if ab.get("abilityIDEnum") is Dictionary else -1
	var mods: Array[StatMod] = []
	for mod: StatMod in store.all_mods():
		if mod.extra == 0 or mod.extra == ability_index:
			mods.append(mod)
	return {
		"ab": ab, "base": base, "tags": tags, "hit": hit, "src": src, "dmg": dmg, "type_bits": type_bits,
		"base_before": conv["before"], "conversion_lines": conv["lines"], "conversion_rows": conv["rows"],
		"ailment_conversions": conv["ailment_conversions"],
		"minion": tags & LE.MINION, "ade": float(base.get("addedDamageScaling", 1.0)), "mods": mods, "store": store,
	}


static func _health_tags(build: Node) -> int:
	match str(build.player_state.get("health", "full")):
		"full":
			return LE.HIGH_LIFE | LE.FULL_LIFE
		"high":
			return LE.HIGH_LIFE
		"low":
			return LE.LOW_LIFE
	return 0


## Applies skill-tree base-damage conversions and tag changes (skill_conversions.json rules).
## Base conversion happens before any modifier, like BaseDamageStats.convertBaseDamage (06b §1.7).
static func _apply_conversions(tags: int, dmg: Array[float], conversions: Array, notes: Array[String]) -> Dictionary:
	var before: Array[float] = dmg.duplicate()
	var lines: Array = [[], [], [], [], [], [], []]
	var rows: Array = []
	var seen: Dictionary = {}
	var tags_before: int = tags
	var ailment_conversions: Array = []
	for c: Dictionary in conversions:
		var rule: Dictionary = c["rule"]
		var v: float = float(c["value"])
		if v == 0.0:
			continue
		var field: String = str(rule["key"]).get_slice(".", 1)
		var full: bool = true
		for cv: Dictionary in rule.get("convert", []):
			var from: int = _type_index(str(cv.get("from", "")))
			var to: int = _type_index(str(cv.get("to", "")))
			var f: float = clampf(v, 0.0, 1.0) if str(cv.get("fraction", "value")) == "value" else clampf(float(cv["fraction"]), 0.0, 1.0)
			full = full and f >= 1.0
			var dedupe: String = "%s:%d:%d" % [field, from, to]
			if from < 0 or to < 0 or seen.has(dedupe):
				continue
			seen[dedupe] = true
			var moved: float = dmg[from] * f
			rows.append({"label": "%s → %s" % [LE.t(LE.DT_NAME[from]), LE.t(LE.DT_NAME[to])], "text": LE.fmt_pct(f),
				"breakdown": LE.t("Node \"%s\": %s of the base damage of type \"%s\" is converted to \"%s\" before any modifier (moved %s).\nRule: %s") % [
					c["node"], LE.fmt_pct(f), LE.t(LE.DT_NAME[from]), LE.t(LE.DT_NAME[to]), LE.fmt_num(moved), rule["key"]]})
			if moved <= 0.0:
				continue
			dmg[to] += moved
			dmg[from] -= moved
			lines[to].append(LE.t("  +%s from \"%s\" (conversion %s, node \"%s\")") % [LE.fmt_num(moved), LE.t(LE.DT_NAME[from]), LE.fmt_pct(f), c["node"]])
			lines[from].append(LE.t("  −%s to \"%s\" (conversion %s, node \"%s\")") % [LE.fmt_num(moved), LE.t(LE.DT_NAME[to]), LE.fmt_pct(f), c["node"]])
		var change_tags: bool = str(rule.get("tags_when", "active")) == "active" or full
		var add_mask: int = LE.tag_mask("|".join(PackedStringArray(rule.get("tags_add", []))))
		var remove_mask: int = LE.tag_mask("|".join(PackedStringArray(rule.get("tags_remove", []))))
		if change_tags and (add_mask != 0 or remove_mask != 0) and not seen.has("tags:" + field):
			seen["tags:" + field] = true
			tags = (tags & ~remove_mask) | add_mask
			rows.append({"label": LE.t("Tags: node \"%s\"") % c["node"], "text": _tag_text(add_mask, remove_mask),
				"breakdown": LE.t("Rule %s changes the skill's tags; the tags decide which mods apply to the skill.") % rule["key"]})
		for ac: Dictionary in rule.get("ailment_convert", []):
			var key: String = "ail:%s:%s" % [ac.get("from", "?"), ac.get("to", "?")]
			if seen.has(key):
				continue
			seen[key] = true
			ailment_conversions.append({"from": str(ac.get("from", "")), "to": str(ac.get("to", "")), "node": c["node"]})
			rows.append({"label": LE.t("Ailment: %s → %s") % [ac.get("from", "?"), ac.get("to", "?")], "text": "100%",
				"breakdown": LE.t("Node \"%s\": the %s application chance becomes %s (rule %s).") % [c["node"], ac.get("from", "?"), ac.get("to", "?"), rule["key"]]})
		if str(rule.get("note", "")) != "":
			var note: String = LE.t("Node \"%s\": %s") % [c["node"], LE.t(str(rule["note"]))]
			if not notes.has(note):
				notes.append(note)
	if tags != tags_before:
		rows.append({"label": LE.t("Resulting skill tags"), "text": _tag_names(tags),
			"breakdown": LE.t("Was: %s\nNow: %s") % [_tag_names(tags_before), _tag_names(tags)]})
	return {"tags": tags, "before": before, "lines": lines, "rows": rows, "ailment_conversions": ailment_conversions}


static func _type_index(type_name: String) -> int:
	return ["Physical", "Fire", "Cold", "Lightning", "Necrotic", "Void", "Poison"].find(type_name)


static func _tag_names(mask: int) -> String:
	var names: PackedStringArray = []
	for tag_name: String in LE.TAG_NAMES:
		if mask & LE.tag_mask(tag_name):
			names.append(tag_name)
	return ", ".join(names) if not names.is_empty() else "—"


static func _tag_text(add_mask: int, remove_mask: int) -> String:
	var parts: PackedStringArray = []
	if add_mask != 0:
		parts.append("+" + _tag_names(add_mask))
	if remove_mask != 0:
		parts.append("−" + _tag_names(remove_mask))
	return " ".join(parts)


static func _applicable(ctx: Dictionary, mod_tags: int) -> bool:
	return (mod_tags & ctx["minion"]) == ctx["minion"] and LE.tags_match(mod_tags, ctx["src"] | ctx["type_bits"])


## [type index or -1, is_elemental, other tags] of a damage mod (06b §1.2).
static func _split_tags(t: int) -> Array:
	var elemental: bool = (t & LE.ELEMENTAL) != 0
	var rest: int = t & ~LE.ELEMENTAL
	for idx: int in TYPE_RESOLVE_ORDER:
		if rest & LE.DT_TAG[idx]:
			return [idx, elemental, rest & ~LE.DT_TAG[idx]]
	return [-1, elemental, rest]


static func _targets(type_idx: int, elemental: bool) -> Array[int]:
	if type_idx >= 0:
		return [type_idx]
	if elemental:
		return [1, 2, 3]
	return [0, 1, 2, 3, 4, 5, 6]


# --- 8.2 buildDamageStats ---------------------------------------------------------

static func _build_damage(ctx: Dictionary) -> Dictionary:
	var base_dmg: Array[float] = ctx["dmg"]
	var ade: float = ctx["ade"]
	var src: int = ctx["src"]
	var flat_added: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var inc: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var more: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
	var pen: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var lines_added: Array = [[], [], [], [], [], [], []]
	var lines_inc: Array = [[], [], [], [], [], [], []]
	var lines_more: Array = [[], [], [], [], [], [], []]
	var lines_pen: Array = [[], [], [], [], [], [], []]
	var details: bool = LE.details

	# 1. untyped flat damage shared by base-damage proportion
	var total_base: float = 0.0
	for d: float in base_dmg:
		total_base += d
	if ade != 0.0 and (src & ATTACK_TAGS) != 0 and total_base > 0.0:
		for mod: StatMod in ctx["mods"]:
			if mod.added == 0.0 or mod.extra != 0:
				continue
			var adaptive: bool = mod.property == LE.ADAPTIVE_SPELL_DAMAGE and (src & LE.SPELL) != 0
			var untyped: bool = mod.property == LE.DAMAGE and (mod.tags & 0xFF) == 0 and (mod.tags & src & 0xF00) != 0
			if not (adaptive or untyped) or not _applicable(ctx, mod.tags):
				continue
			for i in range(7):
				if base_dmg[i] > 0.0:
					var share: float = mod.added * ade * base_dmg[i] / total_base
					flat_added[i] += share
					if details:
						lines_added[i].append(LE.t("  +%s × %s × share %s = %s  (%s, untyped)") % [
							LE.fmt_num(mod.added), LE.fmt_num(ade), LE.fmt_pct(base_dmg[i] / total_base), LE.fmt_num(share), mod.source])

	# 2. damage, crit, penetration
	var cc_add: float = 0.0
	var cc_inc: float = 0.0
	var cc_more: float = 1.0
	var cm_add: float = 0.0
	var cm_inc: float = 0.0
	var cm_more: float = 1.0
	var crit_lines: Array[String] = []
	var multi_lines: Array[String] = []
	for mod: StatMod in ctx["mods"]:
		if mod.property == LE.DAMAGE or mod.property == LE.PENETRATION:
			var split: Array = _split_tags(mod.tags)
			var other: int = split[2]
			if (mod.tags & ctx["minion"]) != ctx["minion"] or (other & src) != other:
				continue
			var targets: Array[int] = _targets(split[0], split[1])
			if mod.property == LE.PENETRATION:
				for i: int in targets:
					pen[i] += mod.added
					if details and mod.added != 0.0:
						lines_pen[i].append("  +%s  (%s)" % [LE.fmt_pct(mod.added), mod.source])
				continue
			if mod.added != 0.0 and split[0] >= 0 and ade != 0.0:
				var i_add: int = split[0]
				flat_added[i_add] += ade * mod.added
				if details:
					lines_added[i_add].append("  +%s × %s = %s  (%s)" % [LE.fmt_num(mod.added), LE.fmt_num(ade), LE.fmt_num(ade * mod.added), mod.source])
			for i: int in targets:
				if mod.increased != 0.0:
					inc[i] += mod.increased
					if details:
						lines_inc[i].append("  %s%s  (%s)" % ["+" if mod.increased > 0 else "", LE.fmt_pct(mod.increased), mod.source])
				for m: float in mod.more:
					more[i] *= 1.0 + m
					if details:
						lines_more[i].append("  ×%s  (%s)" % [LE.fmt_num(1.0 + m), mod.source])
		elif mod.property == LE.CRIT_CHANCE and _applicable(ctx, mod.tags):
			cc_add += mod.added
			cc_inc += mod.increased
			for m: float in mod.more:
				cc_more *= 1.0 + m
			if details:
				crit_lines.append("  " + mod.describe())
		elif mod.property == LE.CRIT_MULTI and _applicable(ctx, mod.tags):
			cm_add += mod.added
			cm_inc += mod.increased
			for m: float in mod.more:
				cm_more *= 1.0 + m
			if details:
				multi_lines.append("  " + mod.describe())

	# 3. final per type
	var final: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var rows: Array = []
	var total: float = 0.0
	for i in range(7):
		var pre: float = base_dmg[i] + flat_added[i]
		if pre <= 0.0:
			continue
		final[i] = maxf(0.0, pre * (1.0 + inc[i]) * more[i])
		total += final[i]
		if not details:
			rows.append({"label": LE.t(LE.DT_NAME[i]), "text": LE.fmt_num(final[i]), "breakdown": ""})
			continue
		var b: PackedStringArray = []
		if not ctx["conversion_lines"][i].is_empty():
			b.append(LE.t("Base before conversion: %s") % LE.fmt_num(ctx["base_before"][i]))
			b.append_array(ctx["conversion_lines"][i])
		b.append(LE.t("Base: %s (added damage effectiveness %s)") % [LE.fmt_num(base_dmg[i]), LE.fmt_num(ade)])
		if not lines_added[i].is_empty():
			b.append(LE.t("Added damage:"))
			b.append_array(lines_added[i])
		b.append(LE.t("Sum before multipliers: %s") % LE.fmt_num(pre))
		b.append("Increased: +%s" % LE.fmt_pct(inc[i]))
		b.append_array(lines_inc[i])
		b.append("More: ×%s" % LE.fmt_num(more[i]))
		b.append_array(lines_more[i])
		b.append(LE.t("Result: %s × %s × %s = %s") % [LE.fmt_num(pre), LE.fmt_num(1.0 + inc[i]), LE.fmt_num(more[i]), LE.fmt_num(final[i])])
		rows.append({"label": LE.t(LE.DT_NAME[i]), "text": LE.fmt_num(final[i]), "breakdown": "\n".join(b)})
	rows.append({"label": LE.t("Total per hit (no crit)"), "text": LE.fmt_num(total),
		"breakdown": LE.t("Sum over damage types. The ±20% spread averages to ×1.") if bool(ctx["hit"]) else LE.t("Damage of the periodic component.")})

	# 4. crit (06b §2.1)
	var base_cc: float = float(ctx["base"].get("critChance", 0.0))
	var base_cm: float = float(ctx["base"].get("critMultiplier", 1.0))
	var crit_type: int = int(ctx["base"].get("critType", 0))
	var cc: float = 0.0
	var cm: float = 1.0
	if crit_type != 1:
		cc = (1.0 + cc_inc) * (base_cc + cc_add) * cc_more
	if crit_type == 0:
		cm = maxf(1.0, (1.0 + cm_inc) * (base_cm + cm_add) * cm_more)
	var cc_text: PackedStringArray = [LE.t("(base %s + added %s) × (1 + %s) × %s = %s") % [
		LE.fmt_pct(base_cc), LE.fmt_pct(cc_add), LE.fmt_pct(cc_inc), LE.fmt_num(cc_more), LE.fmt_pct(cc)]]
	cc_text.append_array(crit_lines)
	var cm_text: PackedStringArray = [LE.t("(base %s + added %s) × (1 + %s) × %s = %s") % [
		LE.fmt_num(base_cm), LE.fmt_num(cm_add), LE.fmt_pct(cm_inc), LE.fmt_num(cm_more), LE.fmt_num(cm)]]
	cm_text.append_array(multi_lines)
	if crit_type == 1:
		cc_text = [LE.t("The skill cannot crit (critType NoCritChance).")]
	if crit_type != 0:
		cm_text = [LE.t("Crit multiplier is not used (critType %d).") % crit_type]
	var crit_rows: Array = [
		{"label": LE.t("Crit chance"), "text": LE.fmt_pct(cc), "breakdown": "\n".join(cc_text)},
		{"label": LE.t("Crit multiplier"), "text": "×" + LE.fmt_num(cm), "breakdown": "\n".join(cm_text)},
	]
	var pen_rows: Array = []
	for i in range(7):
		if final[i] > 0.0 and pen[i] != 0.0:
			pen_rows.append({"label": LE.t("Penetration: %s") % LE.t(LE.DT_NAME[i]), "text": LE.fmt_pct(pen[i]), "breakdown": "\n".join(lines_pen[i])})
	crit_rows.append_array(pen_rows)
	return {"final": final, "total": total, "cc": cc, "cm": cm, "pen": pen, "rows": rows, "crit_rows": crit_rows}


# --- 8.3 speed and cost -----------------------------------------------------------

static func _speed(build: Node, ab: Dictionary, ctx: Dictionary, s: Dictionary) -> Dictionary:
	var store: StatStore = ctx["store"]
	var scaler: int = int(ab.get("speedScaler", 54))
	var use_inc: float = float(s["use_speed_inc"])
	var use_more: float = float(s["use_speed_more"])
	var b: PackedStringArray = []
	var speed: float
	if scaler == 54:
		speed = 1.0 + use_inc
		b.append(LE.t("Speed is not scaled by stats: 1 + %s (tree)") % LE.fmt_pct(use_inc))
	else:
		var q: StatQuery = store.query(scaler, int(ctx["tags"]))
		speed = q.added * (1.0 + q.increased + use_inc) * q.more
		b.append(LE.t("%s: (Σ added %s) × (1 + %s + %s tree) × %s = %s") % [
			LE.t("Attack speed") if scaler == LE.ATTACK_SPEED else LE.t("Cast speed"),
			LE.fmt_num(q.added), LE.fmt_pct(q.increased), LE.fmt_pct(use_inc), LE.fmt_num(q.more), LE.fmt_num(speed)])
		for mod: StatMod in q.mods:
			b.append("  " + mod.describe())
		if scaler == LE.ATTACK_SPEED:
			var rate: float = _weapon_rate(build, int(ctx["tags"]))
			if rate > 0.0:
				speed *= rate
				b.append(LE.t("× weapon attack speed %s = %s") % [LE.fmt_num(rate), LE.fmt_num(speed)])
		if int(ab.get("speedScalerAppliedAsIncrease", 0)) == 1:
			speed = speed * float(ab.get("speedScalerEffectiveness", 1.0)) + 1.0
			b.append(LE.t("Speed as increased: × %s + 1 = %s") % [LE.fmt_num(float(ab.get("speedScalerEffectiveness", 1.0))), LE.fmt_num(speed)])
	var max_speed: float = float(ab.get("maximumUseSpeed", 0.0))
	if max_speed > 0.0 and speed > max_speed:
		speed = max_speed
		b.append(LE.t("maximumUseSpeed cap: %s") % LE.fmt_num(max_speed))
	if use_more != 1.0:
		speed *= use_more
		b.append(LE.t("× more from the tree %s = %s") % [LE.fmt_num(use_more), LE.fmt_num(speed)])
	var duration: float = float(ab.get("useDuration", 1.0))
	var mult: float = float(ab.get("speedMultiplier", 1.0))
	var instant: bool = int(ab.get("instantCastForPlayer", 0)) == 1
	var uses: float = speed * mult * 1.1 / (1.0 if instant or duration <= 0.0 else duration)
	b.append(LE.t("Uses/s = %s × speedMultiplier %s × 1.1 / useDuration %s = %s") % [
		LE.fmt_num(speed), LE.fmt_num(mult), "—" if instant else LE.fmt_num(duration), LE.fmt_num(uses)])

	var rows: Array = [{"label": LE.t("Uses per second"), "text": LE.fmt_num(uses), "breakdown": "\n".join(b)}]
	var mana_base: float = float(ab.get("manaCost", 0.0))
	var mana: float = (mana_base + float(s["mana_added"])) * (1.0 + float(s["mana_inc"]))
	var mana_lines: PackedStringArray = [LE.t("(base %s + added %s) × (1 + %s) = %s") % [
		LE.fmt_num(mana_base), LE.fmt_num(float(s["mana_added"])), LE.fmt_pct(float(s["mana_inc"])), LE.fmt_num(mana)]]
	for line: String in s.get("mana_sources", []):
		mana_lines.append("  " + line)
	mana_lines.append(LE.t("Added — tree nodes and properties of unique items; mana stats from affixes and passives are not counted yet."))
	rows.append({"label": LE.t("Mana cost"), "text": LE.fmt_num(mana), "breakdown": "\n".join(mana_lines)})
	var cd: Dictionary = cooldown_info(ab, store, int(ctx["tags"]), s)
	if bool(cd["has"]):
		rows.append({"label": LE.t("Cooldown, s"), "text": LE.fmt_num(cd["cd"]), "breakdown": cd["text"]})
		if float(cd["charges"]) > 1.0:
			rows.append({"label": LE.t("Cooldown charges"), "text": LE.fmt_num(cd["charges"]), "breakdown":
				LE.t("Charges: %s. Charges allow a series of uses in a row; in steady state the cooldown sets the rate.") % LE.fmt_num(cd["charges"])})
		var cap: float = 1.0 / float(cd["cd"])
		if uses > cap:
			rows[0]["text"] = LE.fmt_num(cap)
			rows[0]["breakdown"] += LE.t("\nCapped by cooldown: min(%s, 1 / %s s) = %s") % [LE.fmt_num(uses), LE.fmt_num(cd["cd"]), LE.fmt_num(cap)]
			uses = cap
	return {"uses": uses, "rows": rows, "mana": mana, "cooldown": bool(cd["has"])}


## Uses per second of the skill in `slot` from its speed pipeline only (no damage, no components: cheap and never recursive).
## `global` is the character store the skill store hangs on.
static func uses_per_second(build: Node, slot: int, global: StatStore) -> float:
	if slot < 0 or slot >= build.skills.size():
		return 0.0
	var ab: Dictionary = GameData.get_ability(str(build.skills[slot].get("ability", "")))
	if ab.is_empty():
		return 0.0
	var s: Dictionary = BuildMods.skill_store(build, slot, global)
	var primary: Dictionary = ab.get("primaryDamage", {}) if ab.get("primaryDamage") is Dictionary else {}
	var scratch: Array[String] = []
	var ctx: Dictionary = _context(build, ab, s["store"], s["conversions"], scratch, primary)
	return float(_speed(build, ab, ctx, s)["uses"])


## Default of the input «your hits on the cursed target per second» (docs/ENGINE.md §9.3): the sum of uses per second of the
## other skills on the bar that deal hit damage. Returns {rate, lines: ["Skill N/s"]}.
static func curse_own_hits_estimate(build: Node, slot: int, global: StatStore) -> Dictionary:
	var rate: float = 0.0
	var lines: Array[String] = []
	if global == null:
		return {"rate": 1.0, "lines": ["no character stats — assumed 1/s"]}
	for other: int in range(build.skills.size()):
		if other == slot:
			continue
		var ab: Dictionary = GameData.get_ability(str(build.skills[other].get("ability", "")))
		if ab.is_empty() or not SkillComponents.deals_hit_damage(ab):
			continue
		var u: float = uses_per_second(build, other, global)
		if u <= 0.0:
			continue
		rate += u
		lines.append("%s %s/s" % [GameData.display_name(ab), LE.fmt_num(u)])
	return {"rate": rate, "lines": lines}


## Cooldown of the skill (docs/ENGINE.md §9.6). Returns {has, cd, charges, text}.
static func cooldown_info(ab: Dictionary, store: StatStore, tags: int, s: Dictionary) -> Dictionary:
	var cdm: Dictionary = s.get("cooldown", {})
	var base_info: Dictionary = s.get("cooldown_base", {})
	var base: float = float(ab["cooldown"]) if ab.get("cooldown") != null and float(ab["cooldown"]) > 0.0 else float(base_info.get("baseCooldownLength", 0.0))
	var charges: float = float(base_info.get("charges", 1.0)) + float(cdm.get("charges", 0.0))
	if base <= 0.0:
		return {"has": false, "cd": 0.0, "charges": charges, "text": ""}
	var added: float = float(cdm.get("length_added", 0.0))
	var len_inc: float = float(cdm.get("length_increased", 0.0)) + float(base_info.get("increasedCooldownLength", 0.0))
	var length: float = (base + added) * (1.0 + len_inc)
	var cdr: StatQuery = store.query(LE.CDR, tags)
	var rec_inc: float = cdr.increased + float(cdm.get("recovery_increased", 0.0)) + float(base_info.get("increasedCooldownRecoverySpeed", 0.0))
	var rec_more: float = (1.0 + float(cdm.get("recovery_more", 0.0))) * (1.0 + float(base_info.get("moreCooldownRecoverySpeed", 0.0)))
	var recovery: float = maxf((1.0 + rec_inc) * rec_more, 0.0001)
	var cd: float = length / recovery
	var lines: PackedStringArray = [
		LE.t("Length: (%s + %s) × (1 + %s) = %s") % [LE.fmt_num(base), LE.fmt_num(added), LE.fmt_pct(len_inc), LE.fmt_num(length)],
		LE.t("Recovery: (1 + %s) × %s = %s") % [LE.fmt_pct(rec_inc), LE.fmt_num(rec_more), LE.fmt_num(recovery)],
		LE.t("Cooldown: %s / %s = %s s") % [LE.fmt_num(length), LE.fmt_num(recovery), LE.fmt_num(cd)]]
	for mod: StatMod in cdr.mods:
		lines.append("  " + mod.describe())
	return {"has": true, "cd": cd, "charges": charges, "text": "\n".join(lines)}


## Main-hand attack rate (average with an off-hand weapon); applies to Melee, and to Bow with a bow equipped.
static func _weapon_rate(build: Node, tags: int) -> float:
	var rates: Array[float] = []
	var is_bow: bool = false
	for slot: String in ["weapon", "offhand"]:
		var item: Dictionary = build.items.get(slot, {})
		if item.is_empty():
			continue
		var base: Dictionary = GameData.item_base(int(item.get("base", -1)))
		var sub: Dictionary = GameData.item_sub(int(item.get("base", -1)), int(item.get("sub", -1)))
		if base.get("isWeapon", false) and sub.has("attackRate"):
			rates.append(float(sub["attackRate"]))
			if slot == "weapon" and str(base.get("typeName", "")) == "BOW":
				is_bow = true
	if rates.is_empty():
		return 0.0
	if not ((tags & LE.MELEE) != 0 or ((tags & LE.BOW) != 0 and is_bow)):
		return 0.0
	var sum: float = 0.0
	for r: float in rates:
		sum += r
	return sum / rates.size()


# --- 8.5 against the enemy ----------------------------------------------------------

static func _vs_enemy(build: Node, ctx: Dictionary, ds: Dictionary, speed: Dictionary, _notes: Array[String]) -> Array:
	var enemy: Dictionary = build.enemy
	var e: StatStore = Enemy.store(enemy)
	var hit: bool = ctx["hit"]
	var src: int = ctx["src"]
	var area_level: int = int(enemy.get("level", 100))
	var dr: float = Enemy.level_dr(enemy)
	var armour: float = Enemy.armour(e)
	var armour_share: float = minf(1.0, ctx["store"].query(118).added)
	var rows: Array = []
	var total: float = 0.0
	var by_type: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	var cond_mods: Array[StatMod] = []
	for mod: StatMod in ctx["mods"]:
		if mod.property == LE.CONDITIONAL_DAMAGE or mod.property == LE.DAMAGE_PER_AILMENT_STACK:
			cond_mods.append(mod)

	for i in range(7):
		var d: float = ds["final"][i]
		if d <= 0.0:
			continue
		var b: PackedStringArray = [LE.t("Damage before enemy: %s") % LE.fmt_num(d)]
		var cond: float = _condition_factor(cond_mods, enemy, src, i, b)
		# resistance with penetration (06b §4.2)
		var res_q: StatQuery = Enemy.resistance(e, i)
		var res: float = res_q.added
		var pen: float = ds["pen"][i]
		var res_mult: float = (0.25 if res > 0.75 else 1.0 - res) + pen
		b.append(LE.t("Resistance %s (cap 75%%, no lower limit), penetration %s → ×%s") % [LE.fmt_pct(res), LE.fmt_pct(pen), LE.fmt_num(res_mult)])
		for mod: StatMod in res_q.mods:
			if mod.added != 0.0:
				b.append("  " + mod.describe())
		# damage taken (SP 6, base 1)
		var dt_q: StatQuery = e.query(LE.DAMAGE_TAKEN, (src & ~0xFF) | LE.DT_TAG[i])
		var dt: float = (1.0 + dt_q.added) * (1.0 + dt_q.increased) * dt_q.more
		if dt != 1.0:
			b.append(LE.t("Enemy damage taken: ×%s") % LE.fmt_num(dt))
			for mod: StatMod in dt_q.mods:
				b.append("  " + mod.describe())
		# armour (06c §2.2), hits only
		var arm: float = 1.0
		if hit and armour != 0.0:
			var mit: float = Enemy.armour_mitigation(armour, area_level, i != 0)
			arm = 1.0 - mit
			b.append(LE.t("Armor %s at area level %d: reduction %s%s → ×%s") % [
				LE.fmt_num(armour), area_level, LE.fmt_pct(mit), "" if i == 0 else LE.t(" (×0.7 for non-physical)"), LE.fmt_num(arm)])
		elif not hit and armour != 0.0 and armour_share > 0.0:
			# DoT: armour only through «Armour Mitigation Applies to DoT» (SP 118), like the ailments (06d §3)
			var mit_dot: float = Enemy.armour_mitigation(armour, area_level, i != 0) * armour_share
			arm = 1.0 - mit_dot
			b.append(LE.t("Armor %s (only the SP 118 share %s) at area level %d: reduction %s → ×%s") % [
				LE.fmt_num(armour), LE.fmt_pct(armour_share), area_level, LE.fmt_pct(mit_dot), LE.fmt_num(arm)])
		b.append(LE.t("Hidden level-based damage reduction: %s → ×%s") % [LE.fmt_pct(dr), LE.fmt_num(1.0 - dr)])
		var hit_i: float = d * cond * res_mult * dt * (1.0 - dr) * arm
		b.append(LE.t("Result: %s × %s × %s × %s × %s × %s = %s") % [LE.fmt_num(d), LE.fmt_num(cond), LE.fmt_num(res_mult), LE.fmt_num(dt), LE.fmt_num(1.0 - dr), LE.fmt_num(arm), LE.fmt_num(hit_i)])
		total += hit_i
		by_type[i] = hit_i
		rows.append({"label": LE.t(LE.DT_NAME[i]), "text": LE.fmt_num(hit_i), "breakdown": "\n".join(b)})

	if speed.has("dot_duration"):
		return _vs_enemy_dot(rows, total, by_type, speed)

	# crit against the target (06b §2.2)
	var cc: float = ds["cc"]
	var cm: float = ds["cm"]
	var ctbc: float = e.query(LE.CHANCE_TO_BE_CRIT).added
	var p: float = minf(1.0, cc + ctbc) if cc > 0.0 else 0.0
	var e_crit: float = 1.0 + p * (cm - 1.0)
	# single-hit numbers as the training dummy shows them (no per-hit variance there)
	var type_parts: PackedStringArray = []
	for i in range(7):
		if by_type[i] > 0.0:
			type_parts.append("%s %s" % [LE.t(LE.DT_NAME[i]), LE.fmt_num(by_type[i])])
	var variance_note: String = LE.t("\nIn the game a hit's damage usually varies ×0.8–1.2 per hit (research/06b §3.1); the training dummy does not show the variance.")
	rows.append({"label": LE.t("Hit without crit"), "text": LE.fmt_num(total), "breakdown":
		LE.t("Sum of damage over types against the target: %s = %s.") % [" + ".join(type_parts) if not type_parts.is_empty() else LE.t("no damage"), LE.fmt_num(total)] +
		LE.t("\nThe training dummy shows this number for a normal (non-crit) hit.") + variance_note})
	if hit and p > 0.0:
		rows.append({"label": LE.t("Hit with crit"), "text": LE.fmt_num(total * cm), "breakdown":
			LE.t("Hit without crit %s × crit multiplier %s = %s.") % [LE.fmt_num(total), LE.fmt_num(cm), LE.fmt_num(total * cm)] +
			LE.t("\nThe training dummy shows this number for a critical hit.") + variance_note})
	rows.append({"label": LE.t("Average crit multiplier"), "text": "×" + LE.fmt_num(e_crit), "breakdown":
		LE.t("Chance %s + target vulnerability %s = %s; 1 + %s × (%s − 1) = %s") % [
			LE.fmt_pct(cc), LE.fmt_pct(ctbc), LE.fmt_pct(p), LE.fmt_pct(p), LE.fmt_num(cm), LE.fmt_num(e_crit)]})
	var avg: float = total * e_crit
	var dps: float = avg * float(speed["uses"])
	rows.append({"label": LE.t("Average hit vs enemy"), "text": LE.fmt_num(avg), "breakdown":
		"%s × %s = %s" % [LE.fmt_num(total), LE.fmt_num(e_crit), LE.fmt_num(avg)]})
	speed["enemy_dps"] = dps
	speed["enemy_types"] = by_type
	speed["enemy_crit"] = e_crit
	rows.append({"label": LE.t("Hit DPS vs enemy"), "text": LE.fmt_num(dps), "breakdown":
		"%s × %s %s/s = %s" % [LE.fmt_num(avg), LE.fmt_num(speed["uses"]), speed.get("unit", LE.t("uses")), LE.fmt_num(dps)]})
	return rows


## Tail of `_vs_enemy` for a maintained DoT: no crit and no variance, so only the total of the instance and the damage per second.
static func _vs_enemy_dot(rows: Array, total: float, by_type: Array[float], speed: Dictionary) -> Array:
	var duration: float = float(speed["dot_duration"])
	var per_second: float = total * float(speed["uses"])
	var type_parts: PackedStringArray = []
	for i in range(7):
		if by_type[i] > 0.0:
			type_parts.append("%s %s" % [LE.t(LE.DT_NAME[i]), LE.fmt_num(by_type[i])])
	rows.append({"label": LE.t("Damage over the whole duration vs enemy (%s s)") % LE.fmt_num(duration), "text": LE.fmt_num(total), "breakdown":
		LE.t("Sum of damage over types against the target: %s = %s.\nPeriodic damage has no crit, variance or block; resistance and penetration work as for ailments; armor only with \"Armour Mitigation Applies to DoT\".") % [
			" + ".join(type_parts) if not type_parts.is_empty() else LE.t("no damage"), LE.fmt_num(total)]})
	var inc: float = float(speed.get("dot_duration_inc", 0.0))
	var text: String = LE.t("%s / %s s = %s.\nThe instance is kept up by recasting; damage events per second = 1 / %s s = %s.\n") % [
		LE.fmt_num(total), LE.fmt_num(duration), LE.fmt_num(per_second), LE.fmt_num(duration), LE.fmt_num(speed["uses"])]
	text += LE.t("Increased duration (now %s) stretches the effect and raises its total damage in the same proportion: damage per second does not change.") % LE.fmt_pct(inc)
	rows.append({"label": LE.t("Damage per second vs enemy"), "text": LE.fmt_num(per_second), "breakdown": text})
	speed["enemy_dps"] = per_second
	speed["enemy_types"] = by_type
	speed["enemy_crit"] = 1.0
	return rows


## Conditional more damage against the enemy for damage type i (SP 117 by condition, SP 115 per stack of an ailment
## on the target without a cap, 06b §6); appends breakdown lines.
static func _condition_factor(cond_mods: Array[StatMod], enemy: Dictionary, src: int, i: int, lines: PackedStringArray) -> float:
	var cond: float = 1.0
	for mod: StatMod in cond_mods:
		var split: Array = _split_tags(mod.tags)
		var required: int = mod.tags & ~0xFF
		if not _targets(split[0], split[1]).has(i) or (required & src) != required:
			continue
		var per_stack: bool = mod.property == LE.DAMAGE_PER_AILMENT_STACK
		var count: float = float(enemy.get("ailments", {}).get(mod.special, 0)) if per_stack else Enemy.has_condition(enemy, mod.special)
		# SP 115 item mods are ADDED: the per-stack value is in the added field
		var values: Array[float] = mod.more.duplicate()
		if per_stack and values.is_empty() and mod.added != 0.0:
			values.append(mod.added)
		for m: float in values:
			var f: float = 1.0 + m * count
			cond *= f
			if count > 0.0:
				var what: String = LE.t("per stack of %s ×%s") % [str(GameData.ailment(mod.special).get("name", mod.special)), LE.fmt_num(count)] if per_stack else _cdp_name(mod.special)
				if not per_stack and count < 1.0:
					what += LE.t(" (present %s of the time)") % LE.fmt_pct(count)
				lines.append(LE.t("Condition \"%s\": ×%s  (%s)") % [what, LE.fmt_num(f), mod.source])
	return cond


static func _cdp_name(cdp: int) -> String:
	const NAMES: Dictionary = {
		0: "stunned", 1: "low health", 2: "high health", 3: "full health", 4: "bosses and rares", 5: "ignited",
		6: "per poison stack", 7: "per bleed stack", 8: "chilled", 9: "slowed", 10: "shocked",
		13: "cursed", 16: "moving", 17: "bosses", 18: "per armor shred stack", 19: "bleeding",
		20: "frozen", 21: "per ailment", 25: "cursed (Damned)", 26: "per ailment (up to 8)",
		32: "frozen or chilled", 33: "ignited or shocked", 36: "electrified", 44: "poisoned",
		46: "blinded", 47: "frostbitten",
	}
	return LE.t(str(NAMES[cdp])) if NAMES.has(cdp) else LE.t("condition %d") % cdp


# --- 8.8 sustain: leech, gain on hit, ward from mana (docs/ENGINE.md §8.7, research/06c §3, §5) ----

const SP_HEALTH_GAIN: int = 38
const SP_WARD_GAIN: int = 39
const SP_MANA_GAIN: int = 40
const SP_HEALTH_LEECH: int = 51
const SP_MANA_SPENT_AS_WARD: int = 99
const SP_INCREASED_LEECH_RATE: int = 102
## Leech scale: the stat HealthLeech weighs 0.1 (tooltip % = stat x 10, 06c §5.2, scale D?).
const LEECH_SCALE: float = 0.1
## Default leech payout time of one instance, s (LeechTracker.defaultLeechDuration, 06c §5.1).
const LEECH_DURATION: float = 3.0


## Rows of the "Sustain" section: leech/s, health/mana/ward per hit, ward from mana spent. Empty when nothing applies.
## `hit_sources`: [{name, ctx, speed}] with the speed dictionary already filled by `_vs_enemy`.
static func _sustain_rows(head_ctx: Dictionary, hit_sources: Array[Dictionary], uses: float, mana: float) -> Array:
	var rows: Array = []
	var leech_total: float = 0.0
	var leech_lines: PackedStringArray = []
	var gain_total: Dictionary = {SP_HEALTH_GAIN: 0.0, SP_WARD_GAIN: 0.0, SP_MANA_GAIN: 0.0}
	var gain_lines: Dictionary = {SP_HEALTH_GAIN: PackedStringArray(), SP_WARD_GAIN: PackedStringArray(), SP_MANA_GAIN: PackedStringArray()}
	for hs: Dictionary in hit_sources:
		var ctx: Dictionary = hs["ctx"]
		var sp: Dictionary = hs["speed"]
		if not sp.has("enemy_types"):
			continue
		var prefix: String = "" if str(hs["name"]) == "" else "%s: " % hs["name"]
		var events: float = float(sp["uses"])
		var gain_events: float = float(hs.get("gain_events", events))
		var e_crit: float = float(sp["enemy_crit"])
		var store: StatStore = ctx["store"]
		var ability_index: int = _ability_index(ctx)
		var base_leech: float = float(ctx["base"].get("additionalLeech", 0.0))
		for i in range(7):
			var hit_i: float = float(sp["enemy_types"][i])
			if hit_i <= 0.0:
				continue
			var q: StatQuery = store.query(SP_HEALTH_LEECH, int(ctx["src"]) | LE.DT_TAG[i], 0, ability_index)
			var frac: float = (q.added + base_leech / LEECH_SCALE) * (1.0 + q.increased) * q.more * LEECH_SCALE
			if frac <= 0.0:
				continue
			var per_s: float = hit_i * e_crit * events * frac
			leech_total += per_s
			leech_lines.append(LE.t("%s%s: %s × crit %s × %s hits/s × leech %s = %s/s") % [
				prefix, LE.t(LE.DT_NAME[i]), LE.fmt_num(hit_i), LE.fmt_num(e_crit), LE.fmt_num(events), LE.fmt_pct(frac), LE.fmt_num(per_s)])
			leech_lines.append(LE.t("    leech = (Σ SP51 %s + skill additional damage %s) × (1 + %s) × %s × %s") % [
				LE.fmt_num(q.added), LE.fmt_num(base_leech / LEECH_SCALE), LE.fmt_pct(q.increased), LE.fmt_num(q.more), LE.fmt_num(LEECH_SCALE)])
			for mod: StatMod in q.mods:
				leech_lines.append("      " + mod.describe())
		if bool(ctx["hit"]):
			for prop: int in gain_total:
				var qg: StatQuery = store.query(prop, int(ctx["src"]), 0, ability_index)
				if qg.added == 0.0:
					continue
				gain_total[prop] += qg.added * gain_events
				gain_lines[prop].append(LE.t("%s%s per hit × %s hits/s = %s/s") % [prefix, LE.fmt_num(qg.added), LE.fmt_num(gain_events), LE.fmt_num(qg.added * gain_events)])
				for mod: StatMod in qg.mods:
					gain_lines[prop].append("    " + mod.describe())
	if leech_total > 0.0:
		var rate_q: StatQuery = head_ctx["store"].query(SP_INCREASED_LEECH_RATE, int(head_ctx["tags"]))
		var duration: float = LEECH_DURATION / (1.0 + rate_q.added)
		leech_lines.append(LE.t("Each hit is paid out evenly over %s / (1 + payout speed %s) = %s s (SP 102); no cap.") % [
			LE.fmt_num(LEECH_DURATION), LE.fmt_pct(rate_q.added), LE.fmt_num(duration)])
		leech_lines.append(LE.t("Healing runs while health is not full and is limited by the target's remaining health (06c §5.1–5.2): not counted in the calculation (D?)."))
		leech_lines.append(LE.t("The scale of the stat value (×0.1 of the mod value) is D?; check against the game tooltip."))
		rows.append({"label": LE.t("Health leech per second"), "text": LE.fmt_num(leech_total), "breakdown": "\n".join(leech_lines),
			"sustain": "leech", "value": leech_total})
		rows.append({"label": LE.t("Leech payout speed"), "text": "%s s" % LE.fmt_num(duration), "breakdown":
			LE.t("%s / (1 + %s) — Σ IncreasedLeechRate (SP 102) = %s. Does not affect average healing per second, only the payout speed.") % [
				LE.fmt_num(LEECH_DURATION), LE.fmt_pct(rate_q.added), LE.fmt_pct(rate_q.added)]})
	var gain_labels: Dictionary = {SP_HEALTH_GAIN: LE.t("Health on hit per second"), SP_WARD_GAIN: LE.t("Ward on hit per second"), SP_MANA_GAIN: LE.t("Mana on hit per second")}
	var gain_keys: Dictionary = {SP_HEALTH_GAIN: "health_gain", SP_WARD_GAIN: "ward_gain", SP_MANA_GAIN: "mana_gain"}
	for prop: int in gain_total:
		if float(gain_total[prop]) != 0.0:
			var lines: PackedStringArray = gain_lines[prop]
			lines.append(LE.t("SP %d stats with the skill's tags; sustain boosts (increased health gained etc.) are not counted (D?).") % prop)
			rows.append({"label": gain_labels[prop], "text": LE.fmt_num(float(gain_total[prop])), "breakdown": "\n".join(lines),
				"sustain": gain_keys[prop], "value": float(gain_total[prop])})
	var ward_q: StatQuery = head_ctx["store"].query(SP_MANA_SPENT_AS_WARD, int(head_ctx["tags"]), 0, _ability_index(head_ctx))
	if ward_q.added != 0.0 and mana > 0.0:
		var per_s_ward: float = mana * uses * ward_q.added
		var b: PackedStringArray = [LE.t("Mana cost %s × uses/s %s × SP 99 share %s = %s/s") % [
			LE.fmt_num(mana), LE.fmt_num(uses), LE.fmt_pct(ward_q.added), LE.fmt_num(per_s_ward)]]
		for mod: StatMod in ward_q.mods:
			b.append("  " + mod.describe())
		b.append(LE.t("The scale of the SP 99 value (share of mana spent) is D?."))
		rows.append({"label": LE.t("Ward from mana spent per second"), "text": LE.fmt_num(per_s_ward), "breakdown": "\n".join(b),
			"sustain": "ward_from_mana", "value": per_s_ward})
	return rows


static func _ability_index(ctx: Dictionary) -> int:
	var ab: Dictionary = ctx["ab"]
	return int(ab.get("abilityIDEnum", {}).get("value", 0)) if ab.get("abilityIDEnum") is Dictionary else 0
