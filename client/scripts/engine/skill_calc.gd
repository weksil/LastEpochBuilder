class_name SkillCalc

## Skill numbers with breakdowns (docs/ENGINE.md §8, research/06b).

const ATTACK_TAGS: int = LE.SPELL | LE.MELEE | LE.THROWING | LE.BOW
## Order in which a mod's damage-type bit is resolved (06b §1.2): Physical, Lightning, Cold, Fire, Void, Necrotic, Poison.
const TYPE_RESOLVE_ORDER: Array[int] = [0, 3, 2, 1, 5, 4, 6]


## {title, sections: [{title, rows: [{label, text, breakdown}]}], notes: [String]}
static func compute(build: Node, slot: int) -> Dictionary:
	var result: Dictionary = {"title": "", "sections": [], "notes": []}
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

	var ctx: Dictionary = _context(build, ab, store, s["conversions"], notes)
	var speed: Dictionary = _speed(build, ab, ctx, s)
	var sections: Array = []
	var ail: Dictionary = AilmentCalc.compute(build, ctx, float(speed["uses"]), notes)
	var tooltip_rows: Array = []
	var enemy_rows: Array = []
	var hit_tooltip: float = 0.0
	var hit_enemy: float = 0.0
	if ctx["base"].is_empty():
		notes.push_front("У умения нет урона удара в основном компоненте (урон задаётся кодом или под-умениями) — показаны скорость, мана и айлменты.")
		if not ctx["conversion_rows"].is_empty():
			sections.append({"title": "Конверсии и теги", "rows": ctx["conversion_rows"]})
		sections.append({"title": "Скорость и мана", "rows": speed["rows"]})
	else:
		var ds: Dictionary = _build_damage(ctx)
		sections.append({"title": "Урон за применение (до врага)", "rows": ds["rows"]})
		if not ctx["conversion_rows"].is_empty():
			sections.append({"title": "Конверсии и теги", "rows": ctx["conversion_rows"]})
		sections.append({"title": "Крит", "rows": ds["crit_rows"]})
		sections.append({"title": "Скорость и мана", "rows": speed["rows"]})
		tooltip_rows = _tooltip(ds, speed)
		enemy_rows = _vs_enemy(build, ctx, ds, speed, notes)
		hit_tooltip = float(speed.get("tooltip_dps", 0.0))
		hit_enemy = float(speed.get("enemy_dps", 0.0))
	sections.append_array(ail["sections"])
	if ail["tooltip_dps"] > 0.0:
		tooltip_rows.append({"label": "DPS айлментов", "text": LE.fmt_num(ail["tooltip_dps"]), "breakdown": "Сумма DPS всех айлментов без врага (разделы «Айлмент: …»)."})
	tooltip_rows.append({"label": "DPS", "text": LE.fmt_num(hit_tooltip + ail["tooltip_dps"]), "breakdown":
		"Удар %s + айлменты %s = %s" % [LE.fmt_num(hit_tooltip), LE.fmt_num(ail["tooltip_dps"]), LE.fmt_num(hit_tooltip + ail["tooltip_dps"])]})
	if ail["enemy_dps"] > 0.0:
		enemy_rows.append({"label": "DPS айлментов по врагу", "text": LE.fmt_num(ail["enemy_dps"]), "breakdown": "Сумма DPS всех айлментов по врагу (разделы «Айлмент: …»)."})
	enemy_rows.append({"label": "DPS по врагу", "text": LE.fmt_num(hit_enemy + ail["enemy_dps"]), "breakdown":
		"Удар %s + айлменты %s = %s" % [LE.fmt_num(hit_enemy), LE.fmt_num(ail["enemy_dps"]), LE.fmt_num(hit_enemy + ail["enemy_dps"])]})
	sections.append({"title": "DPS как в подсказке игры", "rows": tooltip_rows})
	sections.append({"title": "Против врага", "rows": enemy_rows})
	result["sections"] = sections
	result["notes"] = notes
	return result


# --- 8.1 context ------------------------------------------------------------------

static func _context(build: Node, ab: Dictionary, store: StatStore, conversions: Array, notes: Array[String]) -> Dictionary:
	var base: Dictionary = ab.get("primaryDamage", {}) if ab.get("primaryDamage") is Dictionary else {}
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
			rows.append({"label": "%s → %s" % [LE.DT_NAME_RU[from], LE.DT_NAME_RU[to]], "text": LE.fmt_pct(f),
				"breakdown": "Узел «%s»: %s базового урона типа «%s» переходит в «%s» до всех модификаторов (перенесено %s).\nПравило: %s" % [
					c["node"], LE.fmt_pct(f), LE.DT_NAME_RU[from], LE.DT_NAME_RU[to], LE.fmt_num(moved), rule["key"]]})
			if moved <= 0.0:
				continue
			dmg[to] += moved
			dmg[from] -= moved
			lines[to].append("  +%s из «%s» (конверсия %s, узел «%s»)" % [LE.fmt_num(moved), LE.DT_NAME_RU[from], LE.fmt_pct(f), c["node"]])
			lines[from].append("  −%s в «%s» (конверсия %s, узел «%s»)" % [LE.fmt_num(moved), LE.DT_NAME_RU[to], LE.fmt_pct(f), c["node"]])
		var change_tags: bool = str(rule.get("tags_when", "active")) == "active" or full
		var add_mask: int = LE.tag_mask("|".join(PackedStringArray(rule.get("tags_add", []))))
		var remove_mask: int = LE.tag_mask("|".join(PackedStringArray(rule.get("tags_remove", []))))
		if change_tags and (add_mask != 0 or remove_mask != 0) and not seen.has("tags:" + field):
			seen["tags:" + field] = true
			tags = (tags & ~remove_mask) | add_mask
			rows.append({"label": "Теги: узел «%s»" % c["node"], "text": _tag_text(add_mask, remove_mask),
				"breakdown": "Правило %s меняет теги умения; от тегов зависит, какие моды подходят к умению." % rule["key"]})
		for ac: Dictionary in rule.get("ailment_convert", []):
			var key: String = "ail:%s:%s" % [ac.get("from", "?"), ac.get("to", "?")]
			if seen.has(key):
				continue
			seen[key] = true
			ailment_conversions.append({"from": str(ac.get("from", "")), "to": str(ac.get("to", "")), "node": c["node"]})
			rows.append({"label": "Айлмент: %s → %s" % [ac.get("from", "?"), ac.get("to", "?")], "text": "100%",
				"breakdown": "Узел «%s»: шанс наложения %s переходит в %s (правило %s)." % [c["node"], ac.get("from", "?"), ac.get("to", "?"), rule["key"]]})
		if str(rule.get("note", "")) != "":
			var note: String = "Узел «%s»: %s" % [c["node"], rule["note"]]
			if not notes.has(note):
				notes.append(note)
	if tags != tags_before:
		rows.append({"label": "Итоговые теги умения", "text": _tag_names(tags),
			"breakdown": "Было: %s\nСтало: %s" % [_tag_names(tags_before), _tag_names(tags)]})
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
					lines_added[i].append("  +%s × %s × доля %s = %s  (%s, без типа)" % [
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
					if mod.added != 0.0:
						lines_pen[i].append("  +%s  (%s)" % [LE.fmt_pct(mod.added), mod.source])
				continue
			if mod.added != 0.0 and split[0] >= 0 and ade != 0.0:
				var i_add: int = split[0]
				flat_added[i_add] += ade * mod.added
				lines_added[i_add].append("  +%s × %s = %s  (%s)" % [LE.fmt_num(mod.added), LE.fmt_num(ade), LE.fmt_num(ade * mod.added), mod.source])
			for i: int in targets:
				if mod.increased != 0.0:
					inc[i] += mod.increased
					lines_inc[i].append("  %s%s  (%s)" % ["+" if mod.increased > 0 else "", LE.fmt_pct(mod.increased), mod.source])
				for m: float in mod.more:
					more[i] *= 1.0 + m
					lines_more[i].append("  ×%s  (%s)" % [LE.fmt_num(1.0 + m), mod.source])
		elif mod.property == LE.CRIT_CHANCE and _applicable(ctx, mod.tags):
			cc_add += mod.added
			cc_inc += mod.increased
			for m: float in mod.more:
				cc_more *= 1.0 + m
			crit_lines.append("  " + mod.describe())
		elif mod.property == LE.CRIT_MULTI and _applicable(ctx, mod.tags):
			cm_add += mod.added
			cm_inc += mod.increased
			for m: float in mod.more:
				cm_more *= 1.0 + m
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
		var b: PackedStringArray = []
		if not ctx["conversion_lines"][i].is_empty():
			b.append("База до конверсии: %s" % LE.fmt_num(ctx["base_before"][i]))
			b.append_array(ctx["conversion_lines"][i])
		b.append("База: %s (эффективность добавленного урона %s)" % [LE.fmt_num(base_dmg[i]), LE.fmt_num(ade)])
		if not lines_added[i].is_empty():
			b.append("Добавленный урон:")
			b.append_array(lines_added[i])
		b.append("Сумма до множителей: %s" % LE.fmt_num(pre))
		b.append("Increased: +%s" % LE.fmt_pct(inc[i]))
		b.append_array(lines_inc[i])
		b.append("More: ×%s" % LE.fmt_num(more[i]))
		b.append_array(lines_more[i])
		b.append("Итог: %s × %s × %s = %s" % [LE.fmt_num(pre), LE.fmt_num(1.0 + inc[i]), LE.fmt_num(more[i]), LE.fmt_num(final[i])])
		rows.append({"label": LE.DT_NAME_RU[i], "text": LE.fmt_num(final[i]), "breakdown": "\n".join(b)})
	rows.append({"label": "Всего за удар (без крита)", "text": LE.fmt_num(total),
		"breakdown": "Сумма по типам урона. Разброс ±20% в среднем даёт ×1." if bool(ctx["hit"]) else "Урон периодического компонента."})

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
	var cc_text: PackedStringArray = ["(база %s + added %s) × (1 + %s) × %s = %s" % [
		LE.fmt_pct(base_cc), LE.fmt_pct(cc_add), LE.fmt_pct(cc_inc), LE.fmt_num(cc_more), LE.fmt_pct(cc)]]
	cc_text.append_array(crit_lines)
	var cm_text: PackedStringArray = ["(база %s + added %s) × (1 + %s) × %s = %s" % [
		LE.fmt_num(base_cm), LE.fmt_num(cm_add), LE.fmt_pct(cm_inc), LE.fmt_num(cm_more), LE.fmt_num(cm)]]
	cm_text.append_array(multi_lines)
	if crit_type == 1:
		cc_text = ["Умение не может критовать (critType NoCritChance)."]
	if crit_type != 0:
		cm_text = ["Множитель крита не используется (critType %d)." % crit_type]
	var crit_rows: Array = [
		{"label": "Шанс крита", "text": LE.fmt_pct(cc), "breakdown": "\n".join(cc_text)},
		{"label": "Множитель крита", "text": "×" + LE.fmt_num(cm), "breakdown": "\n".join(cm_text)},
	]
	var pen_rows: Array = []
	for i in range(7):
		if final[i] > 0.0 and pen[i] != 0.0:
			pen_rows.append({"label": "Пробивание: " + LE.DT_NAME_RU[i], "text": LE.fmt_pct(pen[i]), "breakdown": "\n".join(lines_pen[i])})
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
		b.append("Скорость не масштабируется статами: 1 + %s (дерево)" % LE.fmt_pct(use_inc))
	else:
		var q: StatQuery = store.query(scaler, int(ctx["tags"]))
		speed = q.added * (1.0 + q.increased + use_inc) * q.more
		b.append("%s: (Σ added %s) × (1 + %s + %s дерево) × %s = %s" % [
			"Скорость атаки" if scaler == LE.ATTACK_SPEED else "Скорость каста",
			LE.fmt_num(q.added), LE.fmt_pct(q.increased), LE.fmt_pct(use_inc), LE.fmt_num(q.more), LE.fmt_num(speed)])
		for mod: StatMod in q.mods:
			b.append("  " + mod.describe())
		if scaler == LE.ATTACK_SPEED:
			var rate: float = _weapon_rate(build, int(ctx["tags"]))
			if rate > 0.0:
				speed *= rate
				b.append("× скорость атаки оружия %s = %s" % [LE.fmt_num(rate), LE.fmt_num(speed)])
		if int(ab.get("speedScalerAppliedAsIncrease", 0)) == 1:
			speed = speed * float(ab.get("speedScalerEffectiveness", 1.0)) + 1.0
			b.append("Скорость как increased: × %s + 1 = %s" % [LE.fmt_num(float(ab.get("speedScalerEffectiveness", 1.0))), LE.fmt_num(speed)])
	var max_speed: float = float(ab.get("maximumUseSpeed", 0.0))
	if max_speed > 0.0 and speed > max_speed:
		speed = max_speed
		b.append("Ограничение maximumUseSpeed: %s" % LE.fmt_num(max_speed))
	if use_more != 1.0:
		speed *= use_more
		b.append("× more от дерева %s = %s" % [LE.fmt_num(use_more), LE.fmt_num(speed)])
	var duration: float = float(ab.get("useDuration", 1.0))
	var mult: float = float(ab.get("speedMultiplier", 1.0))
	var instant: bool = int(ab.get("instantCastForPlayer", 0)) == 1
	var uses: float = speed * mult * 1.1 / (1.0 if instant or duration <= 0.0 else duration)
	b.append("Применений/с = %s × speedMultiplier %s × 1.1 / useDuration %s = %s" % [
		LE.fmt_num(speed), LE.fmt_num(mult), "—" if instant else LE.fmt_num(duration), LE.fmt_num(uses)])

	var rows: Array = [{"label": "Применений в секунду", "text": LE.fmt_num(uses), "breakdown": "\n".join(b)}]
	var mana_base: float = float(ab.get("manaCost", 0.0))
	var mana: float = (mana_base + float(s["mana_added"])) * (1.0 + float(s["mana_inc"]))
	var mana_lines: PackedStringArray = ["(база %s + добавлено %s) × (1 + %s) = %s" % [
		LE.fmt_num(mana_base), LE.fmt_num(float(s["mana_added"])), LE.fmt_pct(float(s["mana_inc"])), LE.fmt_num(mana)]]
	for line: String in s.get("mana_sources", []):
		mana_lines.append("  " + line)
	mana_lines.append("Добавлено — узлы дерева и свойства уникальных предметов; статы маны с аффиксов и пассивок пока не учитываются.")
	rows.append({"label": "Стоимость маны", "text": LE.fmt_num(mana), "breakdown": "
".join(mana_lines)})
	if ab.get("cooldown") != null and float(ab["cooldown"]) > 0.0:
		var cdr: StatQuery = store.query(LE.CDR, int(ctx["tags"]))
		var cd: float = float(ab["cooldown"]) / (1.0 + cdr.increased)
		rows.append({"label": "Перезарядка, с", "text": LE.fmt_num(cd), "breakdown":
			"%s / (1 + %s скорости восстановления) = %s" % [LE.fmt_num(float(ab["cooldown"])), LE.fmt_pct(cdr.increased), LE.fmt_num(cd)]})
	return {"uses": uses, "rows": rows}


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


# --- 8.4 tooltip DPS --------------------------------------------------------------

static func _tooltip(ds: Dictionary, speed: Dictionary) -> Array:
	var cc: float = ds["cc"]
	var cm: float = ds["cm"]
	var crit_f: float = maxf(1.0, 1.0 + minf(1.0, cc) * (cm - 1.0))
	var per_use: float = 0.0
	var b: PackedStringArray = ["Средний множитель крита: 1 + min(1, %s) × (%s − 1) = %s" % [LE.fmt_pct(cc), LE.fmt_num(cm), LE.fmt_num(crit_f)]]
	for i in range(7):
		var d: float = ds["final"][i]
		if d <= 0.0:
			continue
		var part: float = (1.0 + float(ds["pen"][i])) * crit_f * d
		per_use += part
		b.append("%s: %s × (1 + пробивание %s) × %s = %s" % [LE.DT_NAME_RU[i], LE.fmt_num(d), LE.fmt_pct(ds["pen"][i]), LE.fmt_num(crit_f), LE.fmt_num(part)])
	var dps: float = per_use * float(speed["uses"])
	speed["tooltip_dps"] = dps
	return [
		{"label": "Урон за применение", "text": LE.fmt_num(per_use), "breakdown": "\n".join(b) +
			"\nПодсказка игры не учитывает сопротивления, броню, скрытое снижение урона и условные модификаторы."},
		{"label": "DPS удара", "text": LE.fmt_num(dps), "breakdown": "%s × %s применений/с = %s" % [LE.fmt_num(per_use), LE.fmt_num(speed["uses"]), LE.fmt_num(dps)]},
	]


# --- 8.5 against the enemy ----------------------------------------------------------

static func _vs_enemy(build: Node, ctx: Dictionary, ds: Dictionary, speed: Dictionary, notes: Array[String]) -> Array:
	var enemy: Dictionary = build.enemy
	var e: StatStore = Enemy.store(enemy)
	var hit: bool = ctx["hit"]
	var src: int = ctx["src"]
	var area_level: int = int(enemy.get("level", 100))
	var dr: float = Enemy.level_dr(enemy)
	var armour: float = Enemy.armour(e)
	var rows: Array = []
	var total: float = 0.0

	var cond_mods: Array[StatMod] = []
	for mod: StatMod in ctx["mods"]:
		if mod.property == LE.CONDITIONAL_DAMAGE or mod.property == LE.DAMAGE_PER_AILMENT_STACK:
			cond_mods.append(mod)

	for i in range(7):
		var d: float = ds["final"][i]
		if d <= 0.0:
			continue
		var b: PackedStringArray = ["Урон до врага: %s" % LE.fmt_num(d)]
		var cond: float = _condition_factor(cond_mods, enemy, src, i, b)
		# resistance with penetration (06b §4.2)
		var res_q: StatQuery = Enemy.resistance(e, i)
		var res: float = res_q.added
		var pen: float = ds["pen"][i]
		var res_mult: float = (0.25 if res > 0.75 else 1.0 - res) + pen
		b.append("Сопротивление %s (кап 75%%, без нижнего предела), пробивание %s → ×%s" % [LE.fmt_pct(res), LE.fmt_pct(pen), LE.fmt_num(res_mult)])
		for mod: StatMod in res_q.mods:
			if mod.added != 0.0:
				b.append("  " + mod.describe())
		# damage taken (SP 6, base 1)
		var dt_q: StatQuery = e.query(LE.DAMAGE_TAKEN, (src & ~0xFF) | LE.DT_TAG[i])
		var dt: float = (1.0 + dt_q.added) * (1.0 + dt_q.increased) * dt_q.more
		if dt != 1.0:
			b.append("Получаемый урон врага: ×%s" % LE.fmt_num(dt))
			for mod: StatMod in dt_q.mods:
				b.append("  " + mod.describe())
		# armour (06c §2.2), hits only
		var arm: float = 1.0
		if hit and armour != 0.0:
			var mit: float = Enemy.armour_mitigation(armour, area_level, i != 0)
			arm = 1.0 - mit
			b.append("Броня %s при уровне зоны %d: снижение %s%s → ×%s" % [
				LE.fmt_num(armour), area_level, LE.fmt_pct(mit), "" if i == 0 else " (×0.7 для нефизического)", LE.fmt_num(arm)])
		b.append("Скрытое снижение урона по уровню: %s → ×%s" % [LE.fmt_pct(dr), LE.fmt_num(1.0 - dr)])
		var hit_i: float = d * cond * res_mult * dt * (1.0 - dr) * arm
		b.append("Итог: %s × %s × %s × %s × %s × %s = %s" % [LE.fmt_num(d), LE.fmt_num(cond), LE.fmt_num(res_mult), LE.fmt_num(dt), LE.fmt_num(1.0 - dr), LE.fmt_num(arm), LE.fmt_num(hit_i)])
		total += hit_i
		rows.append({"label": LE.DT_NAME_RU[i], "text": LE.fmt_num(hit_i), "breakdown": "\n".join(b)})

	# crit against the target (06b §2.2)
	var cc: float = ds["cc"]
	var cm: float = ds["cm"]
	var ctbc: float = e.query(LE.CHANCE_TO_BE_CRIT).added
	var p: float = minf(1.0, cc + ctbc) if cc > 0.0 else 0.0
	var e_crit: float = 1.0 + p * (cm - 1.0)
	rows.append({"label": "Средний множитель крита", "text": "×" + LE.fmt_num(e_crit), "breakdown":
		"Шанс %s + уязвимость цели %s = %s; 1 + %s × (%s − 1) = %s" % [
			LE.fmt_pct(cc), LE.fmt_pct(ctbc), LE.fmt_pct(p), LE.fmt_pct(p), LE.fmt_num(cm), LE.fmt_num(e_crit)]})
	var avg: float = total * e_crit
	var dps: float = avg * float(speed["uses"])
	rows.append({"label": "Средний удар по врагу", "text": LE.fmt_num(avg), "breakdown":
		"%s × %s = %s" % [LE.fmt_num(total), LE.fmt_num(e_crit), LE.fmt_num(avg)]})
	speed["enemy_dps"] = dps
	rows.append({"label": "DPS удара по врагу", "text": LE.fmt_num(dps), "breakdown":
		"%s × %s применений/с = %s" % [LE.fmt_num(avg), LE.fmt_num(speed["uses"]), LE.fmt_num(dps)]})
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
				var what: String = "за стак %s ×%d" % [str(GameData.ailment(mod.special).get("name", mod.special)), int(count)] if per_stack else _cdp_name(mod.special)
				lines.append("Условие «%s»: ×%s  (%s)" % [what, LE.fmt_num(f), mod.source])
	return cond


static func _cdp_name(cdp: int) -> String:
	const NAMES: Dictionary = {
		0: "оглушён", 1: "низкое здоровье", 3: "полное здоровье", 4: "боссы и редкие", 5: "подожжён",
		6: "за стак яда", 7: "за стак кровотечения", 8: "охлаждён", 9: "замедлен", 10: "шокирован",
		13: "проклят", 16: "двигается", 17: "боссы", 18: "за стак шреда брони", 19: "кровоточит",
		20: "заморожен", 21: "за айлмент", 25: "проклят (Damned)", 26: "за айлмент (до 8)",
		32: "заморожен или охлаждён", 33: "подожжён или шокирован", 36: "наэлектризован", 44: "отравлен",
		46: "ослеплён", 47: "обморожен",
	}
	return str(NAMES.get(cdp, "условие %d" % cdp))
