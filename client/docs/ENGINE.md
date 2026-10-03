# Движок расчёта (GDScript) — спецификация

Контракт для всех файлов `client/scripts/engine/` и автозагрузок. Формулы взяты из
`research/06a`, `06b`, `06c`, `06d`, `07a`, `07b` (метка D = прочитано из кода игры).
Код: Godot 4.7, GDScript, табы, статическая типизация, `class_name` у каждого файла движка.
Движок не трогает UI. Все числа — float; округление только там, где сказано.

## 1. Константы — `engine/le.gd` (`class_name LE`)

Теги `AT` (битовая маска):
```
PHYSICAL=1 LIGHTNING=2 COLD=4 FIRE=8 VOID=16 NECROTIC=32 POISON=64 ELEMENTAL=128
SPELL=256 MELEE=512 THROWING=1024 BOW=2048 DOT=4096 MINION=8192 TOTEM=16384
PET_RESISTED=32768 POTION=65536 BUFF=131072 CHANNELLING=262144 TRANSFORM=524288
LOW_LIFE=1048576 HIGH_LIFE=2097152 FULL_LIFE=4194304 HIT=8388608 CURSE=16777216 AILMENT=33554432
ELEMENTS = LIGHTNING|COLD|FIRE (14)
```
Имена тегов для разбора строк: `"Physical","Lightning","Cold","Fire","Void","Necrotic","Poison","Elemental","Spell","Melee","Throwing","Bow","DoT","Minion","Totem","PetResisted","Potion","Buff","Channelling","Transform","LowLife","HighLife","FullLife","Hit","Curse","Ailment"`.

Свойства `SP` (id): DAMAGE 0, AILMENT_CHANCE 1, ATTACK_SPEED 2, CAST_SPEED 3, CRIT_CHANCE 4,
CRIT_MULTI 5, DAMAGE_TAKEN 6, HEALTH 7, MANA 8, MOVESPEED 9, ARMOUR 10, DODGE_RATING 11,
STUN_AVOIDANCE 12, FIRE_RES 13, COLD_RES 14, LIGHTNING_RES 15, WARD_RETENTION 16, HEALTH_REGEN 17,
MANA_REGEN 18, STRENGTH 19, VITALITY 20, INTELLIGENCE 21, DEXTERITY 22, ATTUNEMENT 23,
VOID_RES 26, NECROTIC_RES 27, POISON_RES 28, BLOCK_CHANCE 29, ALL_RES 30, ADAPTIVE_SPELL_DAMAGE 41,
ALL_ATTRIBUTES 46, ELEMENTAL_RES 52, BLOCK_EFFECTIVENESS 53, ABILITY_PROPERTY 58, PENETRATION 59,
GLANCING 62, PHYSICAL_RES 64, MANA_COST 66, MANA_EFFICIENCY 69, CDR 70, NEG_PHYSICAL_RES 72,
ENDURANCE 75, ENDURANCE_THRESHOLD 76, NEG_ARMOUR 77, NEG_FIRE_RES 78, NEG_COLD_RES 79,
NEG_LIGHTNING_RES 80, NEG_VOID_RES 81, NEG_NECROTIC_RES 82, NEG_POISON_RES 83, NEG_ELEMENTAL_RES 84,
LEVEL_OF_SKILLS 88, CRIT_AVOIDANCE 89, WARD_REGEN 92, MAX_HEALTH_AS_ET 96, PLAYER_PROPERTY 98,
PHYS_VOID_RES 106, NECRO_POISON_RES 107, DAMAGE_TAKEN_BUFF 108, CHANCE_TO_BE_CRIT 112,
REDUCED_CRIT_BONUS_TAKEN 114, DAMAGE_PER_AILMENT_STACK 115, CONDITIONAL_DAMAGE 117, PARRY 121,
CONDITIONAL_PEN 131, CONDITIONAL_CRIT_CHANCE 132, CONDITIONAL_CRIT_MULTI 133.

Типы урона — индекс 0..6 в порядке **Physical, Fire, Cold, Lightning, Necrotic, Void, Poison**:
```
DT_TAG     = [1, 8, 4, 2, 32, 16, 64]
DT_NAME_RU = ["Физический","Огонь","Холод","Молния","Некротика","Пустота","Яд"]
RES_SP     = [64, 13, 14, 15, 27, 26, 28]
NEG_RES_SP = [72, 78, 79, 80, 82, 81, 83]
RES_GROUP  = [2, 1, 1, 1, 4, 2, 4]   # 1 стихия, 2 Phys/Void, 4 Necrotic/Poison
```
Функции:
- `static func tag_mask(s: String) -> int` — `"Fire|Spell"`, `"Fire | Spell"`, `"None"`, `""` → маска.
- `static func tags_match(mod_tags: int, check: int) -> bool` (06a §3):
  `(mod & check) == mod` ИЛИ (`mod & ELEMENTAL` и `check & ELEMENTS` и `((check | ELEMENTAL) & mod) == mod`).
- `static func round_half_even(x: float) -> int` — банковское округление.
- `static func fmt_pct(x: float) -> String` → `"12.5%"` (x=0.125), `static func fmt_num(x: float) -> String` → до 2 знаков без хвостовых нулей.

## 2. Мод и хранилище

### `engine/stat_mod.gd` (`class_name StatMod extends RefCounted`)
Поля: `property: int`, `special: int = 0`, `tags: int = 0`, `extra: int = 0`, `added: float`,
`increased: float`, `more: Array[float]`, `source: String` (по-русски, для расшифровки:
`"Пассивка «Arcanist» ×3"`, `"Шлем: Added Health T5"`).
- `static func make(property, kind: String, value: float, tags := 0, source := "", special := 0, extra := 0) -> StatMod`
  `kind`: `"added" | "increased" | "more" | "quotient"`; quotient → more `1/(1+x) − 1`.
- `func scaled(n: float) -> StatMod` — копия, где added, increased **и каждое more** умножены на n (линейно, 06a §6.6).
- `func describe() -> String` — `"+12 (источник)"`, `"+30% inc (источник)"`, `"×1.15 more (источник)"`.

### `engine/stat_query.gd` (`class_name StatQuery extends RefCounted`)
Результат запроса: `added: float`, `increased: float`, `more: float = 1.0` (произведение),
`mods: Array[StatMod]` (подошедшие). `func value() -> float` = `added·(1+increased)·more`.
`func breakdown() -> String` — многострочный текст: строка формулы
`"(Σ added) × (1 + Σ inc) × Π more = A × B × C = V"`, затем по строке на каждый мод (`describe()`).

### `engine/stat_store.gd` (`class_name StatStore extends RefCounted`)
- `var mods: Array[StatMod]`, `var parent: StatStore = null`.
- `add(mod)`, `add_all(arr)`, `all_mods() -> Array[StatMod]` (свои + цепочка parent).
- `query(property, check_tags := 0, special := 0, extra := 0, extra_zero_matches := true) -> StatQuery`.
  Мод подходит: `property` равен; `mod.special == 0 or mod.special == special`;
  `mod.extra == extra or (extra_zero_matches and mod.extra == 0)`; `LE.tags_match(mod.tags, check_tags)`.
  added суммируются, increased суммируются, каждое more → `more *= (1+m)`.
- `query_untagged(property) -> StatQuery` — только моды с `tags == 0 and extra == 0 and special == 0`
  (так игра собирает здоровье, броню и прочие защиты, 06a §4.1).
- `sum_added_untagged(properties: Array) -> float` и `untagged_mods(properties: Array) -> Array[StatMod]`.

## 3. Состояние билда — автозагрузка `Build`

Уже есть: `class_id, mastery, level, passives`, сигнал `changed`, правила очков пассивок.
Добавить (каждый сеттер эмитит `changed`):
```
skills: Array[Dictionary]  # 5 слотов: {ability: String (playerAbilityID) или "", level: int = 20, tree: {node_id:int -> points:int}}
selected_skill: int = 0
items: Dictionary          # slot:String -> {base: int, sub: int, implicit_rolls: Array[int], affixes: Array[{id:int, tier:int, roll:int}]}
enemy: Dictionary          # см. §6.1
player_state: Dictionary   # {health: "full"|"high"|"normal"|"low"}
```
Слоты предметов и допустимые `typeName` баз:
`helmet:HELMET, body:BODY_ARMOR, belt:BELT, boots:BOOTS, gloves:GLOVES, amulet:AMULET, ring1:RING, ring2:RING, relic:RELIC,
weapon: все isWeapon (1H и 2H), offhand: SHIELD|QUIVER|CATALYST и 1H-оружие`.
Лимиты очков (D, research/07e §6 и 06e §6):
- пассивки: `Build.passive_point_cap() = clamp(level − 2 + min(15, quest_passive_points), 0, 255)` (на 100 уровне 113; `quest_passive_points`
  по умолчанию 15 — максимум квестовых очков, редактора в UI нет); `add_point` отказывает при `spent_points() ≥ cap`;
  `Build.passive_cap_override ≥ 0` (только для тестов) заменяет расчёт;
- дерево умения: `Build.skill_point_cap(slot) = skills[slot].level + skill_level_bonus(slot)`; бонус — сумма `added` модов
  `LEVEL_OF_SKILLS` (88) из `BuildMods.global_store`, у которых `LE.tags_match(mod.tags, ability.tags)` и `extra ∈ {0, abilityIDEnum.value}`,
  округлённая (`roundi`, способ округления игры — D?); кэшируется до следующего `changed`. Классовые «+N ко всем умениям класса»
  (`specialTag`) пока не различаются.
Методы: `set_skill(slot, ability_id)` (сбрасывает tree, level=20), `set_skill_level(slot, lvl)`,
`add_skill_point(slot, node_id) -> bool`, `remove_skill_point(slot, node_id) -> bool` (правила как у пассивок:
`requirements` — **«ИЛИ»** (узел открыт, если хоть у одного соседа из списка очков ≥ requirement; пустой список — открыт;
D, `LocalTreeData.ArePassiveNodeRequirementsMet`), `maxPoints`, сумма очков ≤ level; снятие очка запрещено, если какой-то
узел перестаёт быть связан с корнем (`Build.all_connected`); порог `masteryRequirement` у узлов скилла не используется),
`skill_points_spent(slot)`, `set_item(slot, dict)`, `clear_item(slot)`, `set_enemy(key, value)`,
`set_enemy_ailment(ailment_id, stacks)`, `set_player_state(key, value)`.

## 4. Данные — автозагрузка `GameData` (добавить)

Файлы `research/data/game/`: `abilities.json`, `affixes.json` (`data`), `items.json` (`data`),
`ailments.json` (`data`), `attributes.json` (`data`), `passive_node_effects.json`,
`skill_node_effects.json`; из `research/data/`: `sp_enum.json`, `monster_level_damage_reduction.json` (`values`).
`classes.json` верхний ключ `hiddenBaseMods` сохранить в `hidden_base_mods`.
Методы:
- `get_ability(pid: String) -> Dictionary` — запись `abilities.json` с этим `playerAbilityID`, приоритет `category == "player"`.
- `class_skills(class_id, mastery) -> Array[String]` — playerAbilityID из `masteries[0].abilities`,
  `masteries[mastery].abilities` и `masteryAbility` выбранного мастерства, `knownAbilities`, `unlockableAbilities`;
  без `na28` и пустых, без дублей.
- `get_skill_tree(tree_id) -> Dictionary` — `trees.json`, `kind == "skill"`, `treeID == tree_id`.
- `passive_effects(tree_id) -> Dictionary` (node_id → узел из `passive_node_effects`),
  `skill_effects(tree_id) -> Dictionary` (то же из `skill_node_effects`).
- `affix(id) -> Dictionary`, `item_base(base_type_id) -> Dictionary`, `item_sub(base, sub) -> Dictionary`,
  `affixes_for_type(type_id: int) -> Array` — `rollsOn == "Equipment"`, `specialAffixType == "Standard"`, `type_id in canRollOn`.
- `ailment(id) -> Dictionary`, `enemy_ailments() -> Array` — `inList`, `positive == 0`, и (`buffs` не пуст или `dealsDamage`), сортировка по имени.
- `attributes: Array`, `sp_name(id) -> String`, `sp_id(name) -> int` (−1 если нет), `damage_reduction(level) -> float` (0 при level > 100).
- `affixes_for_type(type_id, class_filter := "")` для идолов (типы 25–33) берёт `rollsOn == "Idols"` и фильтрует
  `classSpecificity` (пусто, `NonSpecific` или имя класса); `is_idol_type(type_id)`; `idol_grid()` — `idols.json`
  `containerGrids.defaultData` (5×5, 99 — закрытая клетка); `conversion_rule("Mutator.field")` — правило из `skill_conversions.json`.
- `enum_value(enum_name: String, name: String) -> int` по `research/data/stat_tag_enums.json`
  (`{enum_name: {values: [{id, name}]}}`), −1 если нет. Используется для `AilmentID` и `ConditionalDamageProperty`.

## 5. Источники модов — `engine/build_mods.gd` (`class_name BuildMods`)

`static func global_store(build) -> Dictionary` → `{store: StatStore, notes: Array[String]}`.
`notes` — человекочитаемые строки «что не учтено» (показываются в UI честно).

### 5.1 База класса
- `classes.json data[class].levelMods`: значение `base + L·perLevel`, тип `modType`, теги `tags`. Источник «База класса».
- `hidden_base_mods`: `value`, `modType`, `tags`. Источник «Скрытая база».

### 5.2 Пассивки (`passive_effects(treeID)`)
Для узла с `p > 0` очков, для каждого `effect` с `op == "add_stat"`:
- `target == "CharacterMutator.stats"` и `stat.kind` ∈ `added|increased|more` → `StatMod`:
  property = id по имени `stat.property` (через `sp_enum`), tags = `LE.tag_mask(stat.tags)`,
  значение = `v(stat.added | stat.increased | stat.more | stat.value)`.
- `kind == "ailment_chance"` → property 1, special = AilmentID по имени `stat.ailment` (`stat_tag_enums.json` → `AilmentID`), added.
- `kind == "ailment_duration"` → 42, `ailment_effect` → 43 (special = AilmentID, added).
- `kind == "conditional_more_damage"` → property 117, special = индекс ConditionalDamageProperty по имени `stat.condition`, more.
- Остальное (другие target, `player_property`, `ability_property`, `stat` без kind…) → `notes`: `"Узел «displayName»: <target или kind> — не учитывается"`.
Значение `v(x)`: `x.per_point·p + x.flat`; если есть `x.expr` — вычислить `Expression` с переменной `p`.

### 5.3 Атрибуты (после всех остальных источников)
`N = round_half_even(Σadded SP_attr + Σadded SP 46)` по **всем** модам (теги не проверяются).
Для каждого `attributes[i].perPoint` добавить мод × N (`scaled(N)`), источник `"Сила ×N"`.
Испорченные атрибуты не поддерживаются (note, если встретится SP 98 tags 650–654).

### 5.4 Предметы — `engine/item_mods.gd` (`class_name ItemMods`)
`static func item_mods(slot: String, item: Dictionary) -> Array[StatMod]`.
- Импликиты `item_sub(base, sub).implicits[j]`: значение `AffixMath.roll_value(value, maxValue, rounding, modType, implicit_rolls[j], 0.0)`.
- Аффиксы: `a = affix(id)`, `tier = a.tiers[t-1]`, для каждого `properties[j]` + `tier.rolls[j] = [min,max]`:
  `m = AffixMath.effect_modifier(base.affixEffectModifier, a.standardAffixEffectModifier)`,
  значение `AffixMath.roll_value(min, max, rounding, modType, roll, m)`.
- Мод: `property, special = specialTag, tags, extra = extraTag`, kind по `modType` (ADDED/INCREASED/MORE/QUOTIENT).
- Источник: `"<Слот>: <имя аффикса> T<t>"`.

`engine/affix_math.gd` (`class_name AffixMath`), 07a §6:
```
scale(rounding) = {"Hundredth":100, "Integer":1, "Tenth":10, "Thousandth":1000}; INCREASED всегда Hundredth
effect_modifier(item_aem, std) = 0 if is_equal_approx(item_aem, std) else (1+item_aem)/(1+std) − 1
roll_value(lo, hi, rounding, mod_type, roll, m):
   lo2 = lo·(1+m); hi2 = hi·(1+m); s = scale
   a = round_half_even(lo2·s); b = round_half_even(hi2·s)
   если a > b: поменять местами
   v = min(floor((b − a + 1)·roll/255.0 + a), b) / s
```
Тест-векторы: Integer [5,10] roll 0→5, 128→8, 255→10; Hundredth [0.10,0.20] roll 200→0.18;
[0.10,0.20] m=0.5 roll 255→0.30; [61,90] m=0.5 roll 0→92, 255→135.

### 5.4.1 Идолы — `engine/idol_grid.gd` (`class_name IdolGrid`)
Идол хранится в `Build.items` под ключом `idol_<row>_<col>` (левая верхняя клетка) с той же структурой, что предмет
(`affixes` — 1 префикс и 1 суффикс). `gridSize` базы — `[ширина, высота]`. Идол помещается, если все его клетки открыты
(`!= 99`) и не заняты другими идолами. Моды идолов собираются как у предметов (`ItemMods`), с модификатором эффекта базы
(Small −0.83, Grand −0.33 и т. д.). Награды за открытие слотов считаются полученными.
Алтарь (`Build.items["altar"]`, база 41, `engine/altar_mods.gd` `AltarMods.apply`): сетка `idols.json data[sub]`, клетки
`+100` — преломлённые; свойства SP 130 (`tags` = IdolAltarPropertyID): 1–4 — эффект аффиксов/зачарований идолов в
преломлённых клетках ×(1 + x) (`ItemMods.item_mods(..., effect_scale)`), 9–19 и 22–30 — статы × число подходящих идолов
(осквернённые — флаг `corrupted`, еретические/знамения/ткача — по имени подтипа), 20 — SP 117 против боссов за
уникальный/легендарный идол, 21 — CDR при условии порядка размеров, лимиты — заметки.

### 5.4.2 Уникальные предметы и сеты (07d §2.1–2.3)
Предмет с `unique: uniqueID` и `unique_rolls[rollID]` (байт ролла, по умолчанию 255): импликиты базы + моды уникального.
Значение мода — `AffixMath.unique_value`: роллится, только если `canRoll`, `maxValue > value` и ролл ≠ 0, иначе
фиксированное значение на сетке округления. Моды SP 98 (PlayerProperty) и SP 58 (AbilityProperty) и компоненты —
особые эффекты (§5.4.3). SP 88 (+уровень умений) — note. SP 100 (конверсия айлмента: specialTag = из, tags = в) — §8.6,
SP 115 (more за стак айлмента на цели, без лимита) — вместе с SP 117 в `_condition_factor`.
Сеты: `count` = число **разных** uniqueID сета в экипировке + число Legends Entwined (423); бонусы `sets.json` с
`setRequirement ≤ count` добавляются фиксированными значениями, источник «Сет «…» (N предм.)».
`BuildMods.set_counts(build)` и `complete_sets(build)` (сет полный, если count ≥ числа предметов сета).

### 5.4.3 Особые эффекты уникальных — `engine/unique_effects.gd` (`class_name UniqueEffects`)
Модели — рукописная таблица `client/data/unique_effect_models.json` (не выгрузка игры; схема в самом файле), построена по
формулам `unique_effects.json` (07i). `player[ppIndex]` для PlayerProperty, `ability["abilityIndex:propertyIndex"]` для
AbilityProperty. Значение `pp` — ролл мода-носителя: SP 98 с `tags = ppIndex` или SP 58 с `tags = AbilityID`,
`specialTag = index` (`AffixMath.unique_value`).
- Модель → StatMod: `x = pp · (источник − offset) · factor` (без `per`: `pp · factor`), затем `min`/`max`; `stat` — имя SP,
  `mod`, `tags`, `ailment` → specialTag. Источники: атрибуты, сумма атрибутов, added/value/increased SP, сопротивления без
  капа, макс. здоровье/мана, порог выносливости, стаки айлмента на враге, числа игрока (`Build.player_state`), полные сеты.
- Условия (`when`, `at_least`, `below`): айлменты и флаги врага, тип врага, флаги игрока, два оружия / двуручное ближнего
  боя (по базам в слотах), слот предмета. Невыполненное условие → note «учитывается при условии: …».
- Порядок в `global_store`: сеты → `apply_global("pre")` (источники, не читающие хранилище) → атрибуты → Haste/Frenzy игрока
  (баффы `ailments.json` × (1 + increased SP 120)) → `apply_global("post")` → `add_notes`.
- `apply_skill` в `skill_store`: AbilityProperty только для умения с `abilityIDEnum.value = abilityIndex`, модели со
  `skill_any` — для умений с одним из тегов; `kind: mana_added` → `mana_added` и `mana_sources`.
- Особые: `overcap_taken` (Null Portent: по типу урона more получаемого `max(−cap, (res−0.75)/0.02·pp)`).
- Без модели → note с причиной: «не влияет на урон и защиту» (flag/util), «срабатывание или отдельная механика» (proc,
  компоненты), «не моделируется» (с формулой из кода); алтари идолов не поддерживаются.

### 5.5 Дерево скилла — `BuildMods.skill_store(build, slot, global) -> Dictionary`
→ `{store: StatStore (parent = global), notes, use_speed_inc: float, use_speed_more: float, mana_inc: float, mana_added: float}`.
Для узла с `p > 0` из `skill_effects(treeID)`:
- `op == "add_stat"` и цель содержит `.unconditionalTempStats` (ровно это поле) → мод в локальный store (`extra = 0`).
- `op == "add_stat"` и цель `CharacterMutator.stats` → мод в локальный store (это глобальный стат, но для расчёта умения то же самое).
- `op == "automatic_node_stat"` → мод в локальный store.
- Поле мутатора (есть `target` вида `XMutator.field`, нет `op`):
  `increasedCastSpeed`, `increasedAttackSpeed` → `use_speed_inc += v`; `moreCastSpeed`, `moreAttackSpeed` → `use_speed_more *= (1+v)`;
  `increasedManaCost` → `mana_inc += v`; `addedManaCost` → `mana_added += v`.
- Поле, для которого есть правило в `skill_conversions.json` (`kind` ≠ none) → `conversions.append({rule, value, node})`.
- Всё остальное → `notes`: `"Узел «name»: поле <field> — механика скилла, не считается"`.

**Правила конверсий** (`research/data/game/skill_conversions.json`, собраны из описаний кода мутаторов, уровень D?):
`{key "Mutator.field", kind conversion|tags|ailment_conversion, convert[{from, to, fraction: "value"|число}], tags_add[],
tags_remove[], tags_when active|full_conversion, ailment_convert[{from,to}], note}`. `fraction: "value"` — значение поля,
выставленное узлом (обрезается до 0..1). Если теги в разметке не указаны, тип-источник заменяется типом-целью
(`tags_derived`), при частичной конверсии — только при 100%.
Плюс моды умения: `attributeScaling[]` — каждый Stat × значение атрибута (int), `levelScaling` × уровень персонажа.

## 6. Враг — `engine/enemy.gd` (`class_name Enemy`)

### 6.1 Конфиг `Build.enemy`
```
{level: 100, kind: "boss",            # "dummy" | "normal" | "magic" | "rare" | "miniboss" | "boss"
 res: [0,0,0,0,0,0,0],                # проценты по типам урона (порядок §1)
 armour: 0,
 ailments: {ailment_id: stacks},      # шреды, шок, холод, проклятия, игнайт и т. д.
 flags: {moving: false, stunned: false, low_health: false, full_health: true}}
```
### 6.2 Функции
- `static func store(enemy: Dictionary) -> StatStore` — базовые моды: `res[i]/100` added в `RES_SP[i]`,
  `armour` added в SP 10; затем для каждого айлмента со стаками n > 0:
  `n_eff = min(n, maxInstances)` если `maxInstances > 0`; для `buffScalingType == 2` ещё `min(n_eff, maxStacksThatApplyBuffs)`;
  `penalty = moreBuffEffectAgainstBosses` если враг boss/miniboss, иначе 0;
  каждый `buffs[k]` → `StatMod` (added/increased/more как в данных) `.scaled(n_eff·(1+penalty))`, источник `"<name> ×n"`.
- `static func resistance(store, i: int) -> StatQuery` — только **added**:
  `RES_SP[i] + ALL_RES(30) + (ELEMENTAL_RES 52 если group 1) + (106 если group 2) + (107 если group 4)
   − (NEG_RES_SP[i] + NEG_ELEMENTAL_RES 84 если group 1)`; increased/more игнорируются.
- `static func armour(store) -> float` = `query_untagged(10).value() − sum_added_untagged([77])`.
- `static func armour_mitigation(x: float, area_level: int, non_phys: bool) -> float` (06c §2.2):
  `L = area_level + 5`; `x<0 → −f(−x)`; `f = 0.55·0.0015x²/(0.0015x² + 180L) + 0.30·1.2x/(0.05L² + 80 + 1.2x)`; ×0.7 если non_phys.
- `static func level_dr(enemy) -> float`: `dummy → 0`; иначе `dr = GameData.damage_reduction(level)`;
  boss/miniboss → `dr + 0.05·(1 − dr)`.
- `static func has_condition(enemy, cdp: int) -> float` — множитель/счётчик для ConditionalDamageProperty
  (06b §5): 0 Stunned → flag; 1 LowHealth; 3 FullHealth; 4 Bosses&Rares (rare/boss/miniboss); 5 Ignited (стаки Ignite > 0);
  6 PerPoisonStack (min(стаки,30)); 7 PerBleedStack (min(стаки,30)); 8 Chilled; 9 Slowed; 10 Shocked; 13 Cursed (любое isCurse);
  16 Moving; 17 Bosses; 18 PerArmourShred (min(стаки,14)); 19 Bleeding; 20 Frozen (флаг `frozen`: заморозка — состояние,
  не AilmentID); 21 PerNegAilment (число разных айлментов); 25 Damned; 26 PerNegAilment≤8; 32 Frozen (флаг)|Chilled; 33 Ignited|Shocked; 36 Electrified; 44 Poisoned; 46 Blinded; 47 Frostbitten.
  Возвращает 1/0 для булевых и счётчик для «Per…»; для неизвестных — 0 и вызывающий пишет note.
  Айлменты ищутся по `ailmentIDName` (`Ignite, Bleed, Poison, Chill, Shock, Slow, ArmourShred, Damned, Electrify, Blind, Frostbite`).

## 7. Персонаж — `engine/character_calc.gd` (`class_name CharacterCalc`)

`static func compute(store: StatStore, build) -> Array[Dictionary]` — строки
`{group, label, value: float, text: String, breakdown: String}`. Группы и формулы (06a §4.1, 06c):
- «Атрибуты»: Str/Vit/Int/Dex/Att = `round_half_even(Σadded attr + Σadded 46)`.
- «Ресурсы»: Здоровье = `round_half_even(query_untagged(7).value())`; Мана (8) так же; Реген здоровья (17), реген маны (18) `value()`.
- «Защита»: Броня (`query_untagged(10).value() − Σadded 77`), снижение физ. урона от брони
  `armour_mitigation(броня, level, false)` (уровень зоны = уровень персонажа); Рейтинг уклонения (11), шанс уклонения
  `0.6·0.001x²/(0.001x² + 32L) + 0.25x/(0.05L² + 80 + x)` (L = level+5, x ≤ 0 → 0); Шанс блока (29), эффективность блока (53, рейтинг — выводится числом) и снижение урона при блоке
  `0.6·(0.0006x² + 1.2x)/(0.0006x² + 1.2x + 60L) + 0.25·3x/(0.03L² + 40 + 3x)` (`CharacterCalc.block_mitigation`, research/06c §2.3);
  Шанс парирования min(0.75, 121); Endurance min(0.6, Σadded 75); Порог endurance
  `I76·((maxMore96 + A96)·maxHealth + A76)·M76` (maxMore96 — наибольшее more у SP 96, иначе 0);
  Избежание оглушения (12); Сопротивления: 7 строк, только added по группам как у врага (`Enemy.resistance`),
  текст `"min(res,75)% (без капа X%)"`.
  «Получаемый урон от ударов» / «… от DoT»: по типам `(1+added)(1+inc)·Πmore` для `query(6, HIT|DOT | тип)`
  (текст — значение или диапазон по типам); Ward в секунду (92), порог распада ward (119).
- «Прочее»: Скорость передвижения `query(9).more − 1` как %, Ward retention (16), отражение урона (85), Crit avoidance (89).
Каждая строка: `breakdown` — из `StatQuery.breakdown()` плюс пояснение формулы.

## 8. Умение — `engine/skill_calc.gd` (`class_name SkillCalc`)

`static func compute(build, slot: int) -> Dictionary` →
`{title, sections: Array[{title, rows: Array[{label, text, breakdown}]}], notes: Array[String]}`.

### 8.1 Входные данные
`ab = GameData.get_ability(skill.ability)`; `base = ab.primaryDamage` (нет → note «урон задаётся кодом/подумениями», только скорость и мана).
`g = BuildMods.global_store(build)`; `s = BuildMods.skill_store(build, slot, g.store)`; `store = s.store`.
`tags = ab.tags`, затем конверсии дерева (§5.5): базовый урон `dmg[to] += f·dmg[from]; dmg[from] −= …` **до** всех
модификаторов (как `convertBaseDamage`, 06b §1.7), смена тегов `tags = (tags & ~remove) | add`. Правила с одинаковым полем
у разных мутаторов умения (Fireball / FireballExplosion) применяются один раз. Новые теги используются для подбора модов,
скорости и перезарядки; конверсии айлментов переносят шанс (§8.6).
`hit = base.isHit == 1`; `src = hit ? (tags & ~DOT) | HIT : (tags & ~HIT) | DOT`; добавить health-тег из `player_state.health`:
full → `HIGH_LIFE|FULL_LIFE`, high → `HIGH_LIFE`, low → `LOW_LIFE`.
`ADE = base.addedDamageScaling`; `dmg[7] = base.damage`; `typeBits` = OR `DT_TAG[i]` для `dmg[i] > 0`.
`minionMask = tags & MINION`.

### 8.2 buildDamageStats (06b §1)
Перебираем `store.all_mods()` с `extra == 0` (моды с `extra ≠ 0` — только если `extra == ab.abilityIDEnum.value`, тогда как с 0).
1. **Нетипизированный flat** (только если ADE ≠ 0 и `src & (SPELL|MELEE|THROWING|BOW)`):
   `flat = Σ added` модов, где (`property == 41` и src имеет SPELL) или (`property == 0` и `(mod.tags & 0xFF) == 0` и `(mod.tags & src & 0xF00) != 0`),
   и `applicable(mod.tags)`. `total = Σ dmg`; если `total > 0`: `dmg[i] += flat·ADE·dmg[i]/total`.
   `applicable(t) = (t & minionMask) == minionMask and LE.tags_match(t, src | typeBits)`.
2. **Damage (property 0)**: разобрать теги мода: `elem = t & ELEMENTAL`; тип = первый из порядка
   Physical, Lightning, Cold, Fire, Void, Necrotic, Poison, бит которого есть в t; `other = t` без ELEMENTAL и без бита этого типа.
   Мод применяется, если `(t & minionMask) == minionMask` и `(other & src) == other`.
   - added (только если есть тип и ADE ≠ 0): `dmg[тип] += ADE·added`.
   - increased: тип есть → `inc[тип] += v`; иначе ELEMENTAL → inc Fire, Cold, Lightning; иначе → все 7.
   - more: так же адресуется, `more[...] *= (1+m)` для каждого m.
3. **Крит** (`critType` из base; 0 Normal): `cc = (1+ccInc)·(base.critChance + ccAdd)·ccMore` по модам 4 с `applicable`;
   `cm = max(1, (1+cmInc)·(base.critMultiplier + cmAdd)·cmMore)` по модам 5; critType 2 → cm = 1; critType 1 → cc = 0, cm = 1.
4. **Пробивание** (59): как Damage по адресации, только added → `pen[тип / F,C,L / все]`.
5. Итог: `dmg[i] = max(0, (1+inc[i])·dmg[i]·more[i])`.
Расшифровка по каждому типу: база, added (список модов), Σinc (список), Πmore (список).

### 8.3 Скорость и стоимость (06b §6.2, 06e)
- `scaler = ab.speedScaler` (2 AttackSpeed, 3 CastSpeed, 54 None).
  `None → S = 1 + use_speed_inc`; иначе `q = store.query(scaler, tags)`; `S = q.added·(1 + q.increased + use_speed_inc)·q.more`;
  для AttackSpeed и тега MELEE (или BOW с луком) `S *= attackRate` оружия (`item_sub(weapon).attackRate`, при двух оружиях — среднее).
  `speedScalerAppliedAsIncrease` → `S = S·speedScalerEffectiveness + 1`. `maximumUseSpeed > 0 → S = min(S, max)`.
  `S *= use_speed_more`. `uses/s = S·speedMultiplier·1.1 / useDuration` (`instantCastForPlayer` → без деления).
- Мана: `cost = (ab.manaCost + mana_added)·(1 + mana_inc)` (статы маны не учитываем — note).
- Перезарядка: `ab.cooldown` (если есть) / (1 + query(70).increased) — показать.

### 8.4 Подсказка игры (DPS без врага, 06b §6.3)
`critF = hit ? max(1, 1 + min(1, cc)·(cm − 1)) : 1`;
`per_use = Σ_i (1 + pen[i])·critF·dmg[i]`; `DPS_tooltip = per_use·uses/s`.

### 8.5 По врагу (06b §7)
`e = Enemy.store(build.enemy)`; для каждого типа i с `dmg[i] > 0`:
`D_i = dmg[i]`; условные моды игрока (SP 117 по `Enemy.has_condition`): `D_i *= Π(1 + m·count)` для подходящих по типу
(теги мода → тип; без типа — все; requiredTags = `mod.tags & ~0xFF` ⊆ src);
`res_mult = (res > 0.75 ? 0.25 : 1 − res) + pen[i]` (res из `Enemy.resistance(e, i)`, пола нет);
`DT = e.query(6, src_other | DT_TAG[i]) ` → `(1 + added)·(1+inc)·more` (base 1);
`dr = Enemy.level_dr(enemy)`; `arm = hit ? (1 − armour_mitigation(Enemy.armour(e), level, i != 0)) : 1`.
`Hit_i = D_i·res_mult·DT·(1 − dr)·arm`. Крит по врагу: `cc_eff = min(1, cc + e.query(112).added)` (если cc > 0);
`E_crit = 1 + cc_eff·(cm − 1)`. `avg_hit = Σ Hit_i·E_crit`; `DPS_enemy = avg_hit·uses/s`.
Расшифровка: таблица по типам с каждым множителем.

### 8.6 Айлменты — `engine/ailment_calc.gd` (`class_name AilmentCalc`, research/06d)
- **Шанс** по AilmentID: базовый шанс префаба (`ailmentsOnHit[]`, класс `ChanceToApplyAilmentsOnHit`, тот же `go`, что у
  `primaryDamage`) + моды SP 1 (`special` = AilmentID, added, теги ⊆ теги умения + health). Конверсии айлментов из правил
  `skill_conversions.json` переносят весь шанс. Одно попадание по цели за применение.
- **Длительность** `T = duration·(1 + Σ SP42)`, **эффект** `Σ SP43` (только added, `special` = AilmentID).
- **Урон стака**: `SkillCalc._build_damage` по `baseDamage` айлмента с тегами `(ailment.tags | Ailment | DoT) & ~Hit` + health
  (Spell/Melee/Hit-моды не подходят), ADE айлмента; затем `× (1+effMore)(1+durMore)(1+damageModifier)`, где
  `effMore = effect` при `effectOfIncreasedEffectiveness == 0`, иначе effect идёт в пробивание `additionalPenetrationDamageType`;
  `durMore = incDur`, если урон не наносится в конце / при ударе.
- **DPS**: `λ = применений/с × шанс`; без лимита `DPS = λ·D`, стаков `λ·T`. С лимитом `maxInstances`, если `λ·T > max`:
  `a = max/λ`, `DPS = λ·D·(a + 0.4)/(T + 0.4)` (k = 0.4 для врагов).
- **По врагу**: по типам — условные моды SP 117, `(res > 0.75 ? 0.25 : 1 − res) + pen`, получаемый урон SP 6 с тегами
  DoT|Ailment, `(1 − DR по уровню)`, броня только при SP 118 (× доля). Без крита, разброса, уклонения и блока.
- Айлменты без урона (шок, шреды, холод) показываются числом стаков; их эффект на враге задаётся во вкладке «Условия».

### 8.7 Секции результата
Для каждого компонента урона (§9.3; первый — без префикса, остальные с префиксом «<имя>: »): «Урон за применение (до врага)»
(по типам, итог; у не-первых и при событиях ≠ применений — строка «Событий урона в секунду»), «Конверсии и теги»,
«Крит», «Айлмент: …». Один раз после крита первого компонента — «Скорость и мана» (применений/с, мана, CD).
События/с компонента: `rate`, если задан, иначе применений/с × `per_use` × `hits` (`hits` — `Build.skills[slot].hits`,
только для primary и sub). Затем «Параметры умения» (по строке на `s.params`), «DPS как в подсказке игры» (удар, айлменты,
при >1 компонента «DPS: <имя>», итог «DPS» = Σ всех компонентов), «Против врага» (то же, итог «DPS по врагу»; детали
остальных компонентов — разделы «<имя>: Против врага»), «Не учтено» (notes). Если урона нет ни у одного компонента —
только скорость, мана и айлменты умения.

**Восполнение** (после «Против врага», только непустые строки; `SkillCalc._sustain_rows`, research/06c §3, §5):
- Вампиризм здоровья/с = Σ по компонентам и типам урона `Hit_i(по врагу) × E_crit × событий/с × доля`, где
  `доля = (Σ added SP 51 + 10·baseDamage.additionalLeech) × (1+inc) × Πmore × 0.1` (SP 51 запрашивается с тегами
  `src | тег типа`; 06c §5.2, масштаб ×0.1 — **D?**, подтверждён на узлах дерева: подсказка = стат×10). Выплата каждого
  удара линейно за `3 / (1 + Σ added SP 102)` с (06c §5.1), на средний поток не влияет — отдельная строка. Капа нет;
  прекращение на полном здоровье и кап остатком здоровья цели не учтены (**D?**). Айлменты не лечат в расчёте (**D?**).
- Здоровье/Мана/Ward за удар = Σ added SP 38 / 40 / 39 (теги умения + health) × ударов/с (только hit-компоненты).
  Бонусы к получаемому восполнению и «more ward generated» не учтены (**D?**); `wardGainModifier` не от SP 39 (06c §3.3).
- Ward от маны/с = стоимость маны × применений/с × Σ added SP 99 (масштаб — **D?**).
- Реген здоровья/маны/ward (SP 17/18/92) — характеристики персонажа, в умении не дублируются.

## 9. Модели эффектов и компоненты умения (полный учёт механик)

### 9.1 Модель эффекта — общий формат (`client/data/*_models.json`)
Одна схема для особых эффектов уникальных (§5.4.3), полей мутаторов дерева умения (`field_models.json`, ключ
`"Mutator.field"`), особых списков статов дерева и пассивок (`list_models.json`, ключ `"Mutator.list"` /
`"CharacterMutator.list"`), благословений. Базовое значение `v`: ролл мода (уникальные) или значение поля
`per_point·p + flat` (узлы дерева). Поле `kind`:
- `stat` (по умолчанию): StatMod `{stat (имя SP), mod: added|increased|more, tags, ailment}`;
  `x = v·(источник − offset)·factor` при `per`, иначе `v·factor`; затем `min`/`max`.
- `speed`: `{speed: increased|more}` → скорость применения умения.
- `mana`: `{mana: added|increased}` → стоимость маны умения.
- `cooldown`: `{cooldown: recovery_increased|recovery_more|length_added|length_increased|charges}`.
- `param`: `{param, mod: added|increased|more|set}` — параметр умения для раздела «Параметры умения»
  (`projectiles, chains, pierce, area, duration, radius, count, hits, …`; `hits` — попаданий по цели за применение,
  умножает DPS всех компонентов умения).
- `trigger`: `{ability (имя в abilities.json), on: use|hit|crit|kill|second|end|block|hit_taken, chance, count, icd}` —
  новый компонент урона (§9.3); `chance`/`count` — число или `"v"` (значение эффекта).
- `component`: `{ability, count}` — узел включает подумение, срабатывающее за каждое применение.
- `minion_stat`: как `stat`, но для миньонов этого умения.
- `stat_list`: для `add_stat` в особый список — стат берётся из самого эффекта, модель задаёт `scope`/`when`/`per`.
- `resource`: `{resource: mana|health|ward, on: hit|kill|use|second}` — только строка в «Параметрах умения».
- `flag`: `{text}` — меняет поведение, на числа не влияет.
- `conversion`: правило из `skill_conversions.json` (уже учтено §5.5).
- `scope`: `skill` (по умолчанию) | `component:<имя подумения>` | `global` (на персонажа) | `minion`.

Общие поля: `per` (источник, §5.4.3, плюс `input:<ключ>`), `when` (условия, §5.4.3, плюс `input:<ключ>` —
логический вход), `at_least`/`below`, `offset`, `factor`, `min`, `max`, `src_max`, `note`, `confidence` (D / D?).
`input`: `{key, label, default, max, bool}` — объявление входного параметра умения (стаки, число тотемов,
«пока канализирует» …); значения — `Build.skills[slot].inputs[key]`, по умолчанию `default`.

### 9.2 `engine/effect_models.gd` (`class_name EffectModels`)
`ctx = {build, store: StatStore, slot: int (слот умения или -1), item_slot: String (слот предмета или "")}`.
- `blocked(model, ctx) -> String` — "" если условия выполнены, иначе текст условия по-русски.
- `value(model, v, ctx) -> Dictionary {x: float, text: String}` — итоговое значение и пояснение источника.
- `make_mod(model, v, ctx, label) -> StatMod` (null, если SP неизвестен).
- `source(per, ctx) -> float`, `source_name(per, ctx) -> String`, `holds(cond, ctx) -> bool`, `phase(model) -> String`.
- `inputs(model) -> Array[Dictionary]` — объявленные входы модели.

### 9.3 Компоненты урона — `engine/skill_components.gd` (`class_name SkillComponents`)
`collect(build, slot, ab, s) -> Array[Dictionary]`: `{name, kind: primary|sub|trigger|minion, ab, base (запись урона),
per_use (раз за применение), rate (событий/с, если не от применений), chance, icd, mods: Array[StatMod]}`.
- `primary`: `ab.primaryDamage`; если пусто — подумения с причиной `prefab:CreateAbilityObjectOnDeath|OnStart|
  CastAfterDuration` (связь через `parents`), иначе урон из `abilities_code_damage.json`.
- `sub`: подумения префаба (те же причины) у умений с собственным уроном; `component`-модели узлов.
- `trigger`: модели `trigger` (узлы, уникальные, пассивки): частота = частота события × шанс, не чаще 1/icd.
- `minion`: §9.4.
`SkillCalc.compute` считает каждый компонент тем же конвейером (§8.2–8.6) и складывает DPS в раздел «Итог».

### 9.4 Миньоны — `engine/minion_calc.gd` (`class_name MinionCalc`, research 07d §1, 07j §4)
Данные: `minion_base_stats.json` (`summonedBy`, `health`, `innateStats`, `protection`, `abilityList`, `castSpeedOverrides`,
`summonSettings[{numberToSummon, limit, duration…}]`, `mutators`). Для умения-призыва (`summonedBy` содержит имя умения):
- Статы миньона = снимок статов игрока по правилу `SummonEntityOnDeath` (07d §1.1): пропустить SP 38/39/40/50/126/127;
  стат с `extraTag` = ID умения-призыва или с тегом Minion (Totem — если умение тотем) переходит с тегами
  `tags & ~(Minion|Totem)` и `extraTag 0`; остальные статы игрока не переходят. Плюс `innateStats` актёра, плюс
  `minion_mods` из дерева (§9.1, `minion_stat` / `stat_list scope minion`, как есть), плюс скрытая база игрока для миньонов
  (Movespeed MORE 0.10, DamageTaken MORE −0.6 PetResisted — уже в статах игрока с тегом Minion).
- Урон: каждая способность из `abilityList` с уроном — компонент `kind: minion` (§9.3), конвейер §8.2–8.6 на статах миньона
  (уровень миньона не масштабирует урон; `levelScaling` способностей миньона не применяется). Частота атак: скорость
  атаки/каста миньона (SP 2/3, база 1) × 1.1 / `useDuration` из `castSpeedOverrides` (или способности).
- Число миньонов: вход умения `minions` (по умолчанию `limit` из `summonSettings`, с параметрами дерева `count`);
  DPS = DPS одного × число. Строки «Здоровье миньона», «Броня», сопротивления — в разделе «Миньон: <имя>».

### 9.5 Благословения — `BuildMods._add_blessings` (`blessings.json`, 07a §8.2)
`Build.blessings: {timelineID: {id: blessingId, roll: 0..255}}`, по одному на таймлайн (обычное или великое — из
`timelines[].difficulties[].otherSlotBlessings/anySlotBlessings`). Импликиты благословения → StatMod как импликиты
предмета (`AffixMath.roll_value(value, maxValue, rounding, modType, roll, 0)`), источник «Благословение «…»».

### 9.6 Частота срабатываний и перезарядка
- Событие `on` модели `trigger`: `use` / `cast` = применений/с; `hit` = применений/с × попаданий (`hits`); `crit` = частота
  попаданий × шанс крита; `kill` = вход `kills_per_second`; `second` = 1; `end` = применений/с; `hit_taken`, `block`,
  `dodge`, `potion`, `minion_hit`, `minion_death`, `stun`, `death` — входы умения с числом событий в секунду (по
  умолчанию 0, ярлык по-русски). Частота = событие × `chance` × `count`, не больше `count / icd`.
- Перезарядка умения: база `ab.cooldown` или `cooldown_base.baseCooldownLength`; длина `(база + length_added) ×
  (1 + length_increased)`; восстановление `(1 + Σincreased CDR (SP 70) + recovery_increased) × (1 + recovery_more)`;
  итог `длина / восстановление`. Заряды `charges` (база 1) влияют только на серию; в установившемся режиме
  применений/с = min(частота по скорости каста, 1 / перезарядка).

### 9.7 Баффы умений на персонажа и пассивки на мутаторы умений
- **Scope `global`** (§9.1; `stat`, `stat_list`, баффы при применении, `statsInForm`, `statsWhileActive` …): `_add_scoped` кладёт
  мод в `result["global_mods"]` результата `skill_store`, не в локальный store умения. `BuildMods.global_store` в конце (после
  пост-фазы пассивок и уникальных) вызывает `skill_store(build, slot, store)` для каждого экипированного умения (сам
  `skill_store` `global_store` не вызывает — рекурсии нет), собирает `global_mods` всех слотов и добавляет их одним пакетом
  (порядок слотов не важен; мод читает хранилище на момент сбора, атрибуты от бафф-статов в Силу/Интеллект не пересчитываются).
  Источник: «Умение «<имя>» (бафф): <исходный источник>». Одно умение считается один раз (дубли на панели игнорируются).
  Бафф идёт только при входе умения `buff_active` (`Build.skills[slot].inputs`, по умолчанию включён; объявляется в
  `result["inputs"]` как «Бафф умения активен», если у умения есть scope-global модель — даже с невыполненным условием).
  Своё умение и все остальные видят бафф через родителя (`store.parent = global`), поэтому дубля в собственном store нет.
  Вход самой модели с `default: true` (`when: input:<key>`) при незаданном значении считается включённым (`EffectModels.blocked`).
- **Баффы из кода мутатора** — `engine/buff_skills.gd` (`class_name BuffSkills`, в `build_mods.gd` подключён через `preload`),
  `client/data/buff_skill_models.json`: `{"<abilityName>": {stats: [{stat, mod, tags, value, label, source, …}], note, uptime,
  confidence, source, ability_id, effect_index, active_input, active_multiplier, mode_passive, mode_active, tree_lists:
  {passive, active}, ability_properties: [{index, stat, mod, active_k, …}]}}`; ключ — `abilityName` умения; ключи с `_`
  пропускаются. Только числа, прочитанные из кода (Ghidra, ISIL, `tools/readconst.py`), придуманных нет. Ключи записи (в
  `stats` и `ability_properties`): `active_only` / `passive_only` (режим `active_input` модели), `active_value` (значение в
  активном режиме вместо `value × active_multiplier`), `when_input` (запись только при включённом входе), `per_input`
  (значение × вход, напр. число символов или стаков), `no_m` (без множителя `M = 1 + свойство effect_index`). Входы
  объявляются в `result["inputs"]` один раз на ключ. Список дерева (`tree_lists`) заменяет полевые модели этих списков
  (`BuffSkills.owns_list`): в пассивном режиме идёт список passive, в активном — active (там уже ×2).
  Сейчас в модели:
  - **Holy Aura** (07l, `holy_aura_model.json`): `M = 1 + Σ AbilityPropertyStat(holyAura #0)` из пассивок (Covenant of
    Light 0.04/очко); пассив: ER +0.15 и Damage increased +0.30, `AuraMutator.statsToApply` — `v·M`; усиленный каст (вход
    `holy_aura_active_cast`, по умолчанию выкл.): базовые `2·v·M`, `HolyAuraMutator.statsToApply` (там уже ×2) `v·M` —
    заменяет пассив; свойства #1 (ManaRegen increased), #9 (Movespeed), #10 (StunAvoidance) `v·M` (актив ×2), #6 (HealthRegen
    added, только актив, без ×2).
  - **Symbols of Hope** (`SigilsOfHopeMutator..cctor`, `AddStatToAura`): на каждый символ (вход `sigils`, по умолчанию 3) ×
    `M = 1 + AbilityProperty(sigilsOfHope #1)` (Covenant of Light): HealthRegen increased +0.2 и Damage added +3 (Fire × Melee /
    Spell / Throwing / Bow); свойство #2 (HealthRegen added, Covenant of Protection ≥ 5 очков, +5). Вход `sigils_active_use`
    (по умолчанию выкл., активация 3 с): символы потрачены, пассивные статы пропадают, DamageTaken more −0.05 за символ (без M;
    +100 барьера за символ не моделируется).
  - **Enchant Weapon** (`EnchantWeaponPassiveMutator..ctor`, `EnchantWeaponMutator..ctor`): пассив Damage more +0.15
    (Elemental|Melee) всегда; вход `enchant_weapon_active_cast` (по умолчанию выкл., 5 с из отката 15 с): тот же стат more
    +0.5 заменяет пассив (одно имя баффа). Списки дерева `EnchantWeaponPassiveMutator.statsToApply` / `EnchantWeaponMutator.statsToApply`
    идут через `tree_lists` (раньше складывались оба: пассив + актив).
  - **Firebrand** (`ModifyFirebrandStacks`): Damage added +5 (Melee|Fire) за стак, вход `firebrand_stacks` (по умолчанию 4;
    стак 4 с, максимум 4 + доп.); конверсия в молнию (узел) не учитывается.
  - **Aura Of Decay** (`AuraOfDecayMutator.Mutate`): пока аура включена DamageTaken more −0.3 с тегами DoT|Poison.
  - **Dark Quiver** (`applyStatsFromBlackArrow`): Damage increased +1.0 (тег Bow) для следующей атаки луком; вход
    `black_arrow_ready` (по умолчанию выкл.), условный стат одной атаки.
  Проверено без числового баффа в коде (всё идёт из полей дерева, AbilityProperty или данных префабов): Warcry (Berserk 4.0 —
  узел дерева), Rebuke, Arcane Ascendance, Flame Ward, Ice Ward (не умение панели), Death Seal, Eterra's Blessing, Healing Hands,
  Ring of Shields, Manifest Armor, Smoke Bomb, Fury Leap, Focus, Dread Shade, Sacrifice, Transplant, Teleport, формы (Spriggan,
  Swarmblade, Werebear, Reaper). Их бафф дерева — через модели scope global выше.
- **Пассивки, нацеленные на мутатор умения** (`LungeMutator.increasedCooldownRecoverySpeedFromPassiveTree`,
  `TeleportMutator.increasedCastSpeedFromPassives`, `DivineBoltMutator.extraProjectiles`, `…statListFromPassiveTree` …):
  `BuildMods._add_skill_passives` в `skill_store` берёт эффекты узлов пассивок (`points ≥ minPoints`) с целью не
  `CharacterMutator.*`, оставляет части цели, принадлежащие умению (`BuffSkills.owns_mutator`: список `mutators` дерева умения в
  `skill_node_effects.json`, класс мутатора умения, либо имя умения + «Mutator»), и применяет их теми же `_apply_field_models`
  / `_apply_list_effect` / правилами конверсий, что и узлы дерева (источник «Пассивка «…» ×N»). В `global_store` такой
  эффект больше не даёт заметку, если умение с этим мутатором на панели; иначе заметка «не учитывается» остаётся.
