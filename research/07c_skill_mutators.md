# 07c. Деревья скиллов: как узлы меняют скилл (клиент 1.5.0)

Источник: ISIL/дизассемблер Cpp2IL (`dump/isil/IsilDump/LE/<X>Tree.txt`), константы читаются прямо из `GameAssembly.dll`. Псевдо-C из Ghidra использовался для ручной сверки. Инструмент: `tools/extract/mutator_coeffs.py` + `tools/extract/isil_sym.py`. Результат: `research/data/game/skill_node_effects.json`.

## Кратко

> Правка (07f): в `isil_sym.py` исправлены два дефекта: `xorps xmm,[sign mask]` теперь отрицание (раньше `x ^ -0.0`), а арифметика `sub/add/and/or/xor` обновляет флаги (раньше `sub rcx,1; je` читал устаревшие флаги). Итог пересчёта: auto 3568, auto_combined 212, auto_formula 29, conditional 2, manual 5, none 4. Изменились 7 узлов, например у Acid Flask Poison Pool базовый кулдаун 6.0 стал 2.0 (совпадает с тултипом), а у Flay Cold/Necrotic/Poison Conversion появилась конверсия Bleed.

- **Логика узлов лежит в классах `<Skill>Tree` / `<Skill>SkillTree`, а не в `<Skill>Mutator`.** Таких классов 141 (плюс 6 деревьев классов персонажа, они вне задачи). Каждый содержит статический `updateMutator(LocalTreeData, TreeData)`. Мутатор только хранит поля и читает их при касте (`getTempStats`, `Mutate`, `OnHit`…). **D**
- Коэффициенты на очко — это **float-литералы в коде** (секция `.rdata`), а не ScriptableObject. Исключение — 39 узлов с `AutomaticNodeStat` (`nodeStatsData` в Global Tree Data). Они применяются отдельно, через `UpdateGlobalStatsFromTree` (06a §7.2). **D**
- Узел опознаётся **по имени** (строковый `switch`: FNV-1a `ComputeStringHash` + `String.Equals`), очки берутся из `NodeData.points` (байт по `+0x11`). ID узлов в коде не используются, поэтому переименованный узел перестаёт работать. **D**
- Автоматизация покрыла 136 действующих деревьев и 3820 узлов. 8 устаревших деревьев без UI и способности (07b) разобраны, но в статистику не входят (§6). Результаты:

| Статус | Узлов | Смысл |
|---|---|---|
| `auto` | 3568 (93.4%) | Все эффекты разрешены, линейны по p, эффекты разных узлов просто складываются |
| `auto_combined` | 212 (5.5%) | Эффект узла разрешён, но поле мутатора считается **нелинейной формулой от нескольких узлов** (формула приведена в `after_loop.formulas`) |
| `auto_formula` | 29 (0.8%) | Значение — известная нелинейная функция от p (`sqrt(1+k·p)−1`, `1/(1+k·p)−1`, `pow`) |
| `conditional` | 2 | Разное поведение в зависимости от p (например, клэмп) |
| `manual` | 5 | Нужен ручной разбор (§5) |
| `none` | 4 | Нет эффекта в одиночку: 3 мёртвых узла и 1 узел-флаг, работающий только в паре (§5) |

- Проверка:
  - Числа из тултипов узлов (`tree_node_stats.json`) все нашлись среди коэффициентов кода у **2506** узлов, часть — у 606, ни одно — у 252. Расхождения в основном объяснимы: тултип показывает константы мутатора («лимит 2 раза в 4 с»), пересчёт площади в радиус или разбивку на тики.
  - Константы Ghidra в блоке узла все нашлись в извлечении у **2469 из 2565** узлов. Ручная выборка остальных 96 показала: это либо перекрытие блоков в моей грубой нарезке Ghidra-кода, либо свёрнутые произведения (`0.4·0.25 → 0.1`).
  - Найден **один случай, где неверен сам Ghidra**: Infernal Shade «More Damage and Reduced Duration». Ghidra показывает −0.12 и 0.2. По ассемблеру `mulss xmm0,[18471CDECh]` и `[18471DD70h]` значения −0.1 и 0.18, и это совпадает с тултипом (18% / 10%). **Вывод: float-литералы из псевдо-C Ghidra нельзя брать без сверки с бинарём.**

## 1. Как дерево применяется к скиллу

`LocalTreeData.updateMutator(ability, treeData)` @0x1816c8140:
1. `UpdateGlobalStatsFromTree` — `AutomaticNodeStat` узлов в глобальные статы (06a §7.2).
2. `switch (AbilityManager.GetAbilityID(ability))` → `<X>Tree.updateMutator(localTreeData, tree)`. Если дерева нет, пишется лог «no tree found for …».

Типовой `<X>Tree.updateMutator` (проверено по ISIL на Fireball, Rive, Summon Skeleton, Rip Blood, Tempest Strike, Flurry, Holy Aura и др.):
```
mut  = GetComponentInChildren<FireballMutator>()     // или GetComponentsInChildren<T>() → массив (комбо-скиллы)
listA = new List<Stat>(); ...                        // иногда список сразу кладётся в поле мутатора
locals = 0
foreach (node in tree.nodes) if (node.points > 0):
    switch (GlobalTreeData.getTreeData(id).getNode(node.id).name):    // по имени!
        case "Fireball Cast Speed":  castSpeed += p * 0.05
        case "Fireball Ignite Chance": listA.Add(new Stat(AilmentChance, 0, Ignite, p * 0.3))
        case "Fireball Homing": homing = true
        ...
// после цикла:
mut.increasedCastSpeed = castSpeed; mut.unconditionalTempStats = listA; ...
mut.SetCooldown(...)/GiveCooldown(...)      // виртуальные, слоты vtable 0xC48/0xC58
resummonCompanions(...)                     // у призывателей
```
Что важно для движка:
- **Внутри узла очки умножаются линейно** (`p·k`). Несколько узлов, пишущих в один локал, **складываются**, после чего результат один раз записывается в поле. Нелинейность появляется только в коде после цикла (`after_loop.formulas`).
- **Встречаются фиксированные эффекты** (`flat`), не зависящие от p, в том числе у узлов с maxPoints > 1 (§4.4).
- Списки `List<Stat>` становятся полями мутатора (`unconditionalTempStats`, `statsWhileChannelling`, `statList` для миньонов и т. п.). Мутатор выдаёт их как временные статы каста (`getTempStats`) или вешает на миньонов.
- Типы статов, которые создают узлы:
  - added 725, more 521, increased 191, ailment chance 162, ailment conversion 42, ailment duration 20 и др.;
  - **у статов урона: more 429, added 79, increased 38.** Это подтверждает правило 06a §7.3 о том, что «increased» в дереве почти всегда работает как more. Исключения (increased урона) перечислены в JSON поштучно.
- Имя поля мутатора не говорит о типе модификатора. Поля `increased*` для урона в 13 случаях мутатор превращает в **more** (`getTempStats: Damage more`), в 11 — в increased. Брать нужно подсказку `field_usage_hints`, а не имя.
- Кулдаун. Поля `AbilityMutator`:
  - `+0xC8 addedCharges`, `+0xF8 increasedCooldownRecoverySpeed`, `+0xFC moreCooldownRecoverySpeed`, `+0x100 increasedCooldownLength`, `+0x104 addedCooldownLength`, `+0x108 overriddenBaseCooldownLength`.
  - `SetCooldown(addedCharges, moreCDR, incCooldownLength[, addedCooldownLength, incCDR])` @0x1823fb2a0/0x1823fb2d0.
  - `GiveCooldown(charges, baseCooldownLength, moreCDR, incCooldownLength, incCDR)` @0x1823fa5c0 задаёт `addedCharges = charges − ability.maxCharges` и переопределяет базовый кулдаун.
  - В JSON это эффекты `op:"cooldown"` (108 узлов, из них 45 через `GiveCooldown`, то есть узел даёт скиллу кулдаун). **D**

## 2. Инструмент `tools/extract/mutator_coeffs.py`

Символьный исполнитель ISIL (`isil_sym.py`): регистры, стек, память, символьные значения.
1. **Пролог** выполняется до `MoveNext` и даёт состояние на входе в цикл: в каких слотах лежат мутаторы (тип берётся из `MethodInfo` у `GetComponentInChildren<T>`) и списки.
2. **Тело цикла** прогоняется **для каждого узла дерева** с настоящим именем. Хеш FNV-1a считается, `String.Equals` вычисляется конкретно, поэтому `switch` проходится детерминированно, а очки остаются символом `p ∈ [1, maxPoints]`.
3. **Хвост после цикла:**
   - (a) с символьными аккумуляторами — получаются формулы `поле = f(acc…)`;
   - (b) после одиночного прохода узла — получается эффект узла «в изоляции» в сравнении с базовой линией без узлов.
4. Обработано вручную:
   - null-проверки (ветки с бросанием исключения отбрасываются), `op_Implicit` (объект Unity считается существующим), inline `List.Clear`;
   - `foreach` по спискам, собранным в методе (итерация по реальным элементам);
   - массивы `GetComponentsInChildren` (моделируются двумя экземплярами `T` и `T#2`), `SzArrayNew`, копирующий конструктор `Stat(Stat)`, `Stat.multiplyValues`, запись в поля Stat после конструктора, `moreValues.Add`;
   - виртуальные вызовы: слот vtable резолвится через `il2cpp-types.h`, база vtable `Il2CppClass+0x138` (проверено: 0xC48 → `SetCooldown`, 0xC58 → `GiveCooldown`);
   - `powf`, `sqrtf`, `Math.Round`;
   - константы, которые Cpp2IL печатает как `typeof(C)`, и операнды `lea r,[idx*k]`, напечатанные как `[]`: их восстанавливает выравнивание по ассемблеру.
5. Подсказки по полям мутатора: прямолинейный проход по всем методам `<X>Mutator`. Фиксируется, в какие конструкторы Stat попадает `this.field` (`feeds_stat`) и в каких методах поле читается (`read_in`). Подсказки есть для 3012 из 4372 записываемых полей, а `feeds_stat` — для 349.

Время работы ~20 с. Скрипт перезапускается после патча без правок (имена и офсеты берутся из дампа).

### Схема `skill_node_effects.json`
Массив деревьев:
```
{ tree, treeID, class, orphan?, mutators[], errors[],
  nodes: [ { id, name, displayName, maxPoints, status, review[],
             effects: [ ... ],                 // эффект узла, взятого в одиночку (точный)
             accumulators: [ {acc, op:add|set|expr, per_point, flat, feeds[]} ],  // вклад в локалы цикла
             combined_formula_fields?, tooltip[], tooltip_check{tooltip_numbers, matched, unmatched},
             unimplemented?, manual_note? } ],
  after_loop: { formulas{ поле|"LIST …"|"CALL …": [{expr, when?}] },   // поле = f(acc[...])
                baseline_fields, baseline_stats, baseline_calls, loop_carried[] },
  field_usage_hints{ "Mutator.field": {feeds_stat[], read_in[]} },
  code_node_names_not_in_tree[] }
```
Виды `effects`:
- `{target:"XMutator.field", type, value:{per_point, flat} | {expr}}` — значение поля после `updateMutator`, равно `flat + per_point·p`. Для bool: `flat 1` = флаг включён.
- `{op:"add_stat", target:"XMutator.list", stat:{property, tags, specialTag/ailment, extraTag, kind: added|increased|more|ailment_chance|…, added|increased|more|value:{per_point,flat}, more_values[], multiplied_by?}}`.
- `{op:"cooldown", target, method, args{…}}`, `{op:"proc_limit"}` (`ProcTimeTracker.ChangeLimit`), `{op:"automatic_node_stat", property, tags, modType, value, scaling, threshold}`, `{op:"list_add"}`, `{op:"call"}` (не смоделированный вызов, только у `manual`).
- `when` — условие варианта (ветвление по p и т. п.).
- `acc[reg:xmm13]` / `acc[stk:0x8C]` — локальная переменная цикла (регистр или слот стека). Чтобы получить итог нескольких узлов, нужно:
  1. сложить вклады `accumulators` выбранных узлов в каждый `acc`;
  2. подставить суммы в `after_loop.formulas`.

  Для `auto`-узлов формула поля — это сам `acc` или его линейная комбинация, поэтому достаточно просто сложить `effects`.

## 3. Проверенные примеры (вручную, ISIL ↔ Ghidra ↔ тултип)
| Узел | Код | Тултип |
|---|---|---|
| Fireball Projectile Speed And Damage | `increasedSpeed += 0.07p`; `Stat(Damage, more 0.07p)` → unconditionalTempStats (Fireball + FireballExplosion) | +7% / +7% |
| Fireball Mana Cost And Damage | `addedManaCost −= 1·p`; `Stat(Damage, more 0.03p)` | +3% урона, −1 маны |
| Fireball Protection While Channelling | `statsWhileChannelling += FireRes added 0.15p, Armour added 30p` (06a знал только о FireRes) | +30 брони, +15% |
| Fireball Crit Chance Reduced Cast Speed | `Stat(CritChance, added 0.04p)` создаётся в хвосте; `moreCastSpeed` = −0.05p, но входит в формулу `((extra·k_seq + 1)·(1 + Σ)) − 1` вместе с Projectiles In Sequence | +4% / −5% |
| Rive Bleed Chance And Duration | `AilmentChance(Bleed, 0.25p)` + `AilmentDuration(Bleed, 0.1p)` во все 3 мутатора ударов | |
| Summon Skeleton Health and Damage | `Stat(Health, more [0.15p])` → warriorStatList, `Stat(Damage, more [0.15p])` → archer/rogue | «+15%» (в коде more) |
| Rip Blood Area | `increasedRadius = sqrt(1+0.25p)−1` (`EpochExtensions.AreaToRadius`) | +25% площади |
| Storm Totem Added Crit Multi | `new Stat(CritMulti)`, затем `stat.addedValue = 0.3p` | +30% |
| Holy Aura (Attack and Cast Speed и др.) | стат идёт в `AuraMutator.statsToApply`, его копия с `multiplyValues(2.0)` — в `HolyAuraMutator.statsToApply` | |
| Disintegrate Chance to Slow | `chanceToSlow += p·0.4·0.25` (= 0.1p за тик 0.25 с) | +40% в секунду |

## 4. Нетривиальные механики (что нужно реализовать в движке)

### 4.1 Площадь → радиус (88 узлов)
`EpochExtensions.AreaToRadius(x)` @0x1810dbca0 = `sqrt(1 + x) − 1`. Код складывает «increased area» всех узлов в локал и **после цикла** один раз превращает его в `increasedRadius`. Поэтому area-узлы нельзя складывать по радиусу: сначала суммируется площадь, потом берётся `sqrt`. Это `auto_combined`. Формула лежит в `after_loop.formulas`, например `NovaMutator.increasedRadius = sqrt(acc+1)−1`. **D**

### 4.2 «Урон кроме X» через компенсирующий more (11 узлов)
Схема:
- общий `Stat(Damage, more k·p)`;
- для исключаемой части отдельный `Stat(Damage, tags X, more 1/(1+k·p) − 1)`, который отменяет бонус.

Примеры:
- Meteor «Non Fire Damage»: исключён Fire;
- Volcanic Orb (Orb Damage и др.): бонус орба отменяется в `shrapnelTempStats` / `fireCircleTempStats`;
- Spirit Plague More Damage: исключён `Necrotic|DoT`;
- Rip Blood Upfront Damage. **D**

### 4.3 «Удваивается при условии» (8 узлов)
Базовая часть идёт обычным статом `Stat(Damage, more k·p)`. В поле мутатора (например, `VengeanceMutator.moreDamageToLowHealth`) пишется `Maths.GetDifferenceModifierForMultiplyingModifier(k·p, 2)` = `(1 + 2kp)/(1 + kp) − 1`. Это дополнительный more, который мутатор применяет только при условии (низкое или высокое здоровье врага, 2h, недавний блок…). Вместе они дают ровно `1 + 2kp`. Узлы:
- Nova Base Elemental Damage;
- Vengeance ×2;
- Erasing Strike Damage And Mana Cost;
- Shurikens Chakram;
- Javelin High Health;
- Upheaval No Attack Speed Scaling;
- Flay Doubled Against Low. **D** (формула хелпера из Ghidra @0x1812be7a0).

### 4.4 Эффект не растёт с очками
У 7 узлов с maxPoints > 1 значение не зависит от p:

| Узел | maxPoints | Значение |
|---|---|---|
| Fireball Increased Duration | 4 | `+0.1` |
| Tornado Casts Lightning Faster | 4 | 2.0 |
| Fury Leap Casts Lightning Faster | 5 | 0.25 |
| Aura of Decay Poison Nova On Activation | 3 | 0.02 |
| Summon Skeleton Mage Frenzy On Hit | 3 | 0.1 |
| Death Seal Culling | 2 | 0.08 |
| Smoke Bomb Shadow Dagger On Slow | 2 | 0.35 |

Для Fireball подтверждено и по Ghidra (`fVar18 + 0.1` без множителя очков). Вероятно, это баг: тултип пишет «+10% за очко». Движок должен воспроизводить код. **D**

### 4.5 Масштабирование под тики и частоту ударов
- Disintegrate: `p·0.4·0.25` — шанс в секунду × тик 0.25 с.
- Warpath / Bladestorm: `p·k/0.6` — шанс айлмента делится на 0.6.
- Значение в JSON уже свёрнуто (0.1p, 0.5p и т. д.). **D**

### 4.6 Клоны статов с множителем
Holy Aura кладёт каждый стат узла в `AuraMutator.statsToApply` (союзникам), а его копию после `Stat.multiplyValues(2.0)` — в `HolyAuraMutator.statsToApply` (вероятно, на себя, это надо подтвердить в мутаторе). 19 узлов, поле `multiplied_by`. **D?**

### 4.7 Узлы, которые работают только в сочетании
Узел только кладёт значение в локал, а после цикла оно используется лишь при условии, которое зависит от других узлов. Поодиночке такие узлы ничего не дают. Это видно по `accumulators[].feeds` и `after_loop.formulas`:
- Nova Extra Charge / Cooldown Recovery: `GiveCooldown(charges, …)` вызывается, только если кулдаун дал другой узел (`0 < fVar18`);
- Infernal Shade Cooldown Recovery, Detonating Arrow Plus Charges, Shadow Rend Added Charges, Runic Invocation Cooldown Recovery.

### 4.8 Комбо и несколько мутаторов
Много скиллов пишут одно и то же в несколько мутаторов:
- Rive: 3 удара, `Rive/Rive2/Rive3Mutator`;
- Tempest Strike: 6 мутаторов;
- Fireball + FireballExplosion;
- Flurry, Dive Bomb, Swipe: массивы `GetComponentsInChildren<T>`.

Списки статов часто общие (`target` содержит `A & B`). Всего задействовано 214 разных классов мутаторов.

### 4.9 Кулдауны и заряды
108 узлов дают эффект `op:"cooldown"`. 45 из них вызывают `GiveCooldown` и тем самым **добавляют скиллу кулдаун**. Примеры:
- Javelin Rain Is Flag: 1 заряд, 6 с;
- Shield Rush Adds Charges: p зарядов, 10 с.

`RemoveCooldown` снимает кулдаун (Focus No Cooldown, Werebear и др.). Аргументы — линейные выражения от p, а в общем случае формулы от нескольких узлов (`CALL …` в `after_loop.formulas`).

### 4.10 Прочее
- `pow(p, 0.6)`: Flame Reave Crit Narrow, `moreGrowth = −0.16·p^0.6`.
- Клэмп: Tornado Double Cast, `pullMultiplier = max(0, 1 − 0.25p)` (статус `conditional`).
- `toInt(18/p)`: Infernal Shade Scaling Minion Stats.
- Целочисленные `lea`/`shl`: Reaper Form «Grant Ward on Transform to Reaper» = `40·p` (`(p + 4p) << 3`).

## 5. Требуют ручного разбора (7 manual, 2 conditional, 4 none)
Пояснения из этой таблицы записаны в JSON в поле `manual_note` (`MANUAL_NOTES` в скрипте).
| Дерево / узел | Что делает код | Почему не автомат |
|---|---|---|
| Elemental Nova / Lightning Nova | `canLightningNova = (условие через setcc)`, Damage more 0.07p | `sete` не смоделирован |
| Rip Blood / Bleed Chance | `AilmentChance(Bleed)` в двух списках, одно значение зависит от другого аккумулятора | стат после цикла с формулой |
| Flame Reave / Lightning Conversion | `lightningConversion = true` и локальная функция `AddMirroredLightningStats`: зеркалит огненные статы дерева в молнию | локальная функция не прослежена; список функций для ручной декомпиляции ниже |
| Summon Bone Golem / Twins | `twins`, `increasedSize −0.35p`, Damage more −0.45p, Health more −0.25p; при перерасчёте пересоздаёт живых големов (`constructAbilityObject`, `unsummon`) | побочные эффекты; статы определены верно |
| Rebuke / Elemental Protection | `DamageTaken` (Elemental) more: формула от нескольких аккумуляторов | формула в `after_loop` |
| Frost Wall / Casts Runebolts Matching Wall Type | `firesRunebolts = true`, `RuneboltMutator.frostWallBolt = Ability.getAbility(693)` | ссылка на способность, не число |
| Runebolt / Reversed Combo | `reversedComboOrder = true` в 3 мутаторах, плюс `ResetComboIndex()` | побочный вызов; флаг определён верно |
| Tornado / Double Cast (cond) | `doubleCastChance += 0.25p`; `pullMultiplier = max(0, 1−0.25p)` | клэмп |
| Smoke Bomb / Smoke Blades (cond) | `smokeBladesStacksPerSecondToAllies = 1`; `increasedSmokeBladesEffectiveness = p−1` при p > 1 | ветвление по p |
| Manifest Armor / Reflects Damage Per Attunement, Chance To Slow When Hit (none) | `String.Equals` есть, результат выбрасывается (подтверждено Ghidra) | **узлы ничего не делают в `updateMutator`**; искать в `ManifestArmorMutator` / миньоне |
| Devouring Orb / Rift AoE Growth (none) | имени узла нет в коде | **узел мёртвый** (тултип: «+20% Hit Damage To Time Rotting») |
| Reaper Form / Grant Ward on Transform to Human (none) | только флаг; после цикла `ReaperFormMutator+0x144 = flag ? (ward узла «…to Reaper») : 0` | работает только вместе с «Grant Ward on Transform to Reaper» (40·p); флаг не попал в аккумуляторы |

Bladestorm: в Global Tree Data есть **два** дерева «Bladestorm». Рабочее — `bl5st`. У устаревшего `bs6d9` 15 узлов «Bladestorm Small Node (N)»: код для них пишет лог «is allocated but has no implementation» (статус `unimplemented`).

## 6. Данные и связь с деревьями
- Дерево сопоставляется классу через `uiClass` из `trees.json`, а если его нет — по пересечению имён узлов с литералами класса. Все классы `*Tree.updateMutator` сопоставлены. Не охвачены только Acolyte/Knight/Mage/Primalist/RogueTree (пассивные деревья классов, у них тоже есть `updateMutator` для «особых» пассивок) и пустой `EphemeralStanceTree` (дерево из одного корня).
- Устаревшие деревья (`orphan: true`; в 07b это 8 деревьев GTD с version 0 без UI): Fire Shield, Thorn Burst, Ice Ward, Mark For Death, Manifest Weapon, Ephemeral Stance, «Abyssal Echoes» с пустым treeID (копия Frost Wall) и «Bladestorm» `bs6d9`.
  - Код для части из них ещё есть: FireShieldSkillTree, IceThornsTree, IceWardSkillTree, MarkForDeathTree, ManifestWeaponTree.
  - Они разобраны и лежат в JSON, но в статистике и таблице §7 их нет.
- 39 узлов с `AutomaticNodeStat` идут как эффект `automatic_node_stat` (modType, scaling `PerPoint|None|Threshold`). Применяются глобально через `UpdateGlobalStatsFromTree`, а не через мутатор. `extraTag` — это AbilityID (имя из `AbilityID.cs`).

## 7. Сводка по скиллам
`auto_combined` = поле зависит от нескольких узлов нелинейно; «Поля с не-аддитивной формулой» — какие именно поля (формулы в `after_loop.formulas`).

| Дерево | Класс дерева | Мутаторов | Узлов | auto | auto_combined | auto_formula | manual/none/cond | Нелинейные механики | Поля с не-аддитивной формулой |
|---|---|---|---|---|---|---|---|---|---|
| Abyssal Echoes | AbyssalEchoesTree | 1 | 30 | 24 | 6 | 0 | 0 | cooldown x1, area->radius, AutomaticNodeStat | LIST unconditionalTempStats, increasedRadius |
| Acid Flask | AcidFlaskTree | 1 | 28 | 27 | 1 | 0 | 0 | cooldown x1 | CALL GiveCooldown |
| Aerial Assault | AerialAssaultTree | 5 | 31 | 27 | 3 | 1 | 0 | cooldown x1 | moreFeatherBurstDamageToRareAndBoss, moreFeatherstormDamageToRareAndBoss |
| Anomaly | AnomalyTree | 1 | 29 | 27 | 2 | 0 | 0 | cooldown x3, area->radius | increasedRadius, increasedTimeWaveRadius |
| ArcaneAscendance | ArcaneAscendanceTree | 1 | 23 | 23 | 0 | 0 | 0 | cooldown x2 | - |
| Assemble Abomination | AssembleAbominationTree | 1 | 30 | 29 | 1 | 0 | 0 | area->radius | increasedRadiusForMeleeSkills |
| Aura Of Decay | AuraOfDecayTree | 1 | 29 | 25 | 4 | 0 | 0 | area->radius | increasedRadius, timeToGainFester, timeToLoseFester |
| Avalanche | AvalancheTree | 2 | 27 | 24 | 2 | 1 | 0 | cooldown x1, area->radius | increasedDamageRadius |
| Ballista | BallistaTree | 2 | 29 | 29 | 0 | 0 | 0 | - | - |
| Black Hole | BlackHoleTree | 1 | 28 | 27 | 1 | 0 | 0 | cooldown x2, area->radius, AutomaticNodeStat | lessPullRadius |
| Bladestorm | BladestormTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Bone Curse | BoneCurseTree | 1 | 31 | 28 | 3 | 0 | 0 | cooldown x3, area->radius | auraMode, increasedRadius |
| Chaos Bolts | ChaosBoltsSkillTree | 1 | 28 | 23 | 5 | 0 | 0 | - | LIST minionBuffStats |
| Chthonic Fissure | ChthonicFissureTree | 2 | 30 | 30 | 0 | 0 | 0 | cooldown x1 | - |
| Cinder Strike | CinderStrikeTree | 3 | 27 | 27 | 0 | 0 | 0 | - | - |
| Dagger Dance | ShadowCascadeTree | 1 | 27 | 27 | 0 | 0 | 0 | - | - |
| Dancing Strikes | DancingStrikesTree | 2 | 31 | 31 | 0 | 0 | 0 | - | - |
| Dark Quiver | DarkQuiverTree | 2 | 32 | 32 | 0 | 0 | 0 | - | - |
| Death Seal | DeathSealTree | 2 | 30 | 29 | 1 | 0 | 0 | area->radius | increasedDeathWaveRadius |
| Decoy | DecoyTree | 6 | 27 | 27 | 0 | 0 | 0 | cooldown x2 | - |
| Detonating Arrow | DetonatingArrowTree | 1 | 30 | 22 | 8 | 0 | 0 | cooldown x1, area->radius | LIST unconditionalTempStats, moreExplosionHitDamage, moreExplosionRadiusFromChargeAmplify, moreRadiusFromCooldown |
| Devouring Orb | DevouringOrbTree | 1 | 26 | 25 | 0 | 0 | 1 | cooldown x1 | - |
| Disintegrate | DisintegrateTree | 1 | 30 | 28 | 2 | 0 | 0 | - | increasedDamagePerPowerStep |
| Dive Bomb | DiveBombTree | 3 | 27 | 24 | 2 | 1 | 0 | cooldown x2 | CALL SetCooldown |
| Drain Life | DrainLifeTree | 1 | 29 | 23 | 6 | 0 | 0 | cooldown x1, area->radius | addedManaCost, necroticExplosionIncreasedRadius |
| Dread Shade | DreadShadeTree | 1 | 30 | 28 | 2 | 0 | 0 | area->radius | increasedRadius |
| Dreamslash | DreamslashTree | 1 | 28 | 28 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Earthquake | EarthquakeSlamTree | 3 | 31 | 24 | 7 | 0 | 0 | cooldown x2, area->radius | CALL GiveCooldown, aftershockIncreasedRadius, increasedRadius |
| Elemental Nova | NovaSkillTree | 1 | 31 | 24 | 6 | 0 | 1 | cooldown x1, area->radius, doubled-cond more | increasedAreaForDirectUse, increasedRadius |
| Enchant Weapon | EnchantWeaponTree | 2 | 26 | 26 | 0 | 0 | 0 | cooldown x1 | - |
| Entangling Roots | EntanglingRootsTree | 2 | 29 | 28 | 1 | 0 | 0 | cooldown x1, AutomaticNodeStat | - |
| Erasing Strike | ErasingStrikeTree | 2 | 26 | 25 | 0 | 1 | 0 | cooldown x2, doubled-cond more | - |
| Eterra's Blessing | EterrasBlessingTree | 3 | 26 | 26 | 0 | 0 | 0 | cooldown x1 | - |
| Explosive Trap | ExplosiveTrapTree | 2 | 31 | 27 | 4 | 0 | 0 | cooldown x2, area->radius | CALL GiveCooldown, increasedDetonationRadius, increasedTriggerRadius, lessRadius |
| Falconry | FalconryTree | 3 | 29 | 29 | 0 | 0 | 0 | - | - |
| Fireball | FireballSkillTree | 2 | 27 | 19 | 8 | 0 | 0 | - | LIST unconditionalTempStats, moreCastSpeed |
| Firebrand | FirebrandTree | 5 | 29 | 29 | 0 | 0 | 0 | - | - |
| Flame Reave | FlameReaveTree | 1 | 28 | 25 | 2 | 0 | 1 | cooldown x1, pow | moreGrowth |
| Flame Rush | FlameRushSkillTree | 2 | 26 | 23 | 3 | 0 | 0 | cooldown x1, area->radius | increasedRadius, increasedRadiusIfCastFireballInSameDirection, increasedRadiusOnFrostWallHit |
| Flame Ward | FlameWardTree | 3 | 30 | 28 | 2 | 0 | 0 | cooldown x2, area->radius | increasedRadius |
| Flay | FlayTree | 2 | 33 | 32 | 0 | 1 | 0 | cooldown x1, doubled-cond more | - |
| Flurry | FlurryTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Focus | FocusTree | 1 | 28 | 28 | 0 | 0 | 0 | cooldown x4 | - |
| Forge Strike | ForgeStrikeTree | 2 | 28 | 24 | 4 | 0 | 0 | cooldown x1, area->radius | increasedDuration, increasedRadius |
| Frost Claw | FrostClawTree | 4 | 28 | 28 | 0 | 0 | 0 | - | - |
| Frost Wall | FrostWallSkillTree | 3 | 28 | 26 | 1 | 0 | 1 | cooldown x1, area->radius | increasedRadius |
| Fury Leap | FuryLeapSkillTree | 1 | 23 | 21 | 1 | 1 | 0 | area->radius | increasedRadius |
| Gathering Storm | GatheringStormTree | 2 | 27 | 24 | 3 | 0 | 0 | area->radius | increasedMeleeRadius, increasedTargetingRadius |
| Ghostflame | GhostflameTree | 1 | 29 | 28 | 1 | 0 | 0 | area->radius | increasedRadius |
| Glacier | GlacierSkillTree | 1 | 27 | 19 | 8 | 0 | 0 | cooldown x1 | rimeFreezeRateMulti, rimeIncreasedDamage |
| Glyph of Dominion | GlyphOfDominionSkillTree | 2 | 27 | 26 | 1 | 0 | 0 | cooldown x1, area->radius | increasedRadius |
| Hail of Arrows | HailOfArrowsTree | 1 | 30 | 30 | 0 | 0 | 0 | cooldown x2 | - |
| Hammer Throw | HammerThrowTree | 1 | 24 | 16 | 8 | 0 | 0 | cooldown x1 | extraProjectiles |
| Harvest | HarvestTree | 2 | 28 | 27 | 1 | 0 | 0 | area->radius | increasedRadius |
| Healing Hands | HealingHandsTree | 5 | 28 | 27 | 0 | 1 | 0 | cooldown x1 | - |
| Heartseeker | HeartseekerTree | 2 | 31 | 31 | 0 | 0 | 0 | cooldown x2 | - |
| Holy Aura | HolyAuraTree | 3 | 25 | 25 | 0 | 0 | 0 | cooldown x2, Stat.multiplyValues | - |
| Hungering Souls | HungeringSoulsTree | 2 | 27 | 25 | 2 | 0 | 0 | area->radius | increasedRadius |
| Ice Barrage | IceBarrageTree | 1 | 30 | 30 | 0 | 0 | 0 | cooldown x3 | - |
| Infernal Shade | InfernalShadeTree | 1 | 28 | 17 | 10 | 1 | 0 | cooldown x1, area->radius | LIST statsPerSecondWaiting, giantShadeIncreasedRadius, increasedRadius |
| Javelin | JavelinTree | 2 | 31 | 30 | 0 | 1 | 0 | cooldown x3, doubled-cond more | - |
| Judgement | JudgementTree | 1 | 29 | 28 | 1 | 0 | 0 | cooldown x1, area->radius | increasedRadiusConsecratedGround |
| Lethal Mirage | LethalMirageTree | 3 | 29 | 29 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Lightning Blast | LightningBlastSkillTree | 1 | 27 | 23 | 3 | 1 | 0 | 1/(1+x)-1 | wardOnHit |
| Lunge | LungeTree | 1 | 28 | 27 | 1 | 0 | 0 | cooldown x1, area->radius | increasedPathRadius |
| Maelstrom | MaelstromTree | 3 | 25 | 22 | 2 | 1 | 0 | area->radius | increasedRadius |
| Mana Strike | ManaStrikeSkillTree | 2 | 26 | 24 | 2 | 0 | 0 | cooldown x1, area->radius | increasedRadius, moreRadius |
| Manifest Armor | ManifestArmorTree | 1 | 26 | 24 | 0 | 0 | 2 | - | - |
| Marrow Shards | MarrowShardsTree | 1 | 30 | 30 | 0 | 0 | 0 | - | - |
| Meteor | MeteorSkillTree | 1 | 25 | 23 | 1 | 1 | 0 | 1/(1+x)-1 | increasedArea |
| Multishot | MultishotTree | 1 | 26 | 26 | 0 | 0 | 0 | - | - |
| Multistrike | MultistrikeTree | 3 | 27 | 26 | 1 | 0 | 0 | area->radius | increasedTargetFindRadius |
| Net | NetTree | 3 | 30 | 29 | 1 | 0 | 0 | cooldown x3, area->radius | increasedRadius |
| Profane Form | ProfaneVeilTree | 3 | 31 | 29 | 2 | 0 | 0 | area->radius | increasedRadius, wanderingSpiritIncreasedRadius |
| Puncture | PunctureTree | 2 | 26 | 26 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Radiant Lance | RadiantLanceTree | 2 | 31 | 31 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Reaper Form | ReaperFormTree | 3 | 33 | 29 | 3 | 0 | 1 | cooldown x1, area->radius | increasedRadius, scalingSpellDamageInterval |
| Rebuke | RebukeTree | 1 | 23 | 19 | 3 | 0 | 1 | cooldown x2, area->radius | LIST statsAfterChannelling, LIST statsWhileChannelling, increasedRadius |
| Ring Of Shields | RingOfShieldsTree | 2 | 27 | 23 | 4 | 0 | 0 | area->radius | LIST creatorBuffStats, increasedRingRadius |
| Rip Blood | RipBloodTree | 2 | 27 | 22 | 3 | 1 | 1 | area->radius, 1/(1+x)-1 | LIST splatterStats, coagulatedBloodIncreasedRadius, increasedRadius, increasedRadiusPerMinion |
| Rive | RiveTree | 5 | 30 | 24 | 5 | 1 | 0 | area->radius | LIST flameDrinkerStats, increasedRadius |
| Runebolt | RuneBoltSkillTree | 3 | 32 | 30 | 1 | 0 | 1 | area->radius | increasedImbuedRunestoneExplosionRadius |
| Runic Invocation | RunicInvocationSkillTree | 2 | 31 | 27 | 4 | 0 | 0 | cooldown x2 | CALL GiveCooldown |
| Sacrifice | SacrificeTree | 1 | 24 | 24 | 0 | 0 | 0 | - | - |
| Serpent Strike | SerpentStrikeTree | 1 | 29 | 29 | 0 | 0 | 0 | - | - |
| Shadow Rend | ShadowRendTree | 2 | 29 | 27 | 2 | 0 | 0 | cooldown x2 | CALL GiveCooldown |
| Shatter Strike | ShatterStrikeTree | 1 | 27 | 25 | 2 | 0 | 0 | area->radius, AutomaticNodeStat | increasedRadius |
| Shield Bash | ShieldBashTree | 4 | 32 | 28 | 4 | 0 | 0 | cooldown x2 | LIST unconditionalTempStats, nextMeleeOrThrowingAttackBuffsFromShieldBash |
| Shield Rush | ShieldRushTree | 1 | 22 | 21 | 1 | 0 | 0 | cooldown x3, area->radius | increasedRadius |
| Shield Throw | ShieldThrowTree | 1 | 31 | 26 | 5 | 0 | 0 | cooldown x1, area->radius | LIST allyOnHitStats, increasedLavaBurstRadius |
| Shift | ShiftTree | 2 | 30 | 30 | 0 | 0 | 0 | cooldown x1 | - |
| Shurikens | ShurikensTree | 1 | 26 | 25 | 0 | 1 | 0 | cooldown x1, doubled-cond more | - |
| Sigils Of Hope | SigilsOfHopeTree | 2 | 28 | 28 | 0 | 0 | 0 | cooldown x2 | - |
| Smelter's Wrath | SmeltersWrathTree | 1 | 26 | 24 | 2 | 0 | 0 | - | moreChargeSpeed |
| Smite | SmiteTree | 1 | 30 | 27 | 3 | 0 | 0 | cooldown x1 | percentCurrentHealthCost |
| Smoke Bomb | SmokeBombTree | 1 | 31 | 28 | 2 | 0 | 1 | area->radius | increasedRadius |
| Snap Freeze | SnapFreezeTree | 1 | 23 | 23 | 0 | 0 | 0 | cooldown x3 | - |
| Soul Feast | SoulFeastTree | 1 | 28 | 27 | 1 | 0 | 0 | area->radius | increasedRadius |
| Spirit Plauge | SpiritPlagueTree | 1 | 27 | 24 | 0 | 3 | 0 | 1/(1+x)-1 | - |
| Spriggan Form | SprigganFormTree | 8 | 34 | 33 | 1 | 0 | 0 | area->radius | thornBurstIncreasedRadius |
| Static | StaticTree | 1 | 26 | 26 | 0 | 0 | 0 | cooldown x1 | - |
| Static Orb | StaticOrbTree | 1 | 27 | 23 | 4 | 0 | 0 | - | addedManaCost |
| Summon Bear | SummonBearSkillTree | 4 | 26 | 26 | 0 | 0 | 0 | - | - |
| Summon Bone Golem | SummonBoneGolemTree | 1 | 26 | 25 | 0 | 0 | 1 | AutomaticNodeStat | - |
| Summon Elemental | PrimalistSummonElementalTree | 4 | 30 | 30 | 0 | 0 | 0 | cooldown x1, AutomaticNodeStat | - |
| Summon Frenzy Totem | FrenzyTotemTree | 1 | 25 | 24 | 1 | 0 | 0 | area->radius | increasedRadius |
| Summon Raptor | SummonRaptorTree | 2 | 27 | 27 | 0 | 0 | 0 | - | - |
| Summon Sabertooth | SummonSabertoothTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Summon Scorpion | SummonScorpionTree | 6 | 26 | 20 | 6 | 0 | 0 | area->radius | LIST statList, increasedMeleeRadius, increasedRadius |
| Summon Skeleton | SummonSkeletonTree | 1 | 27 | 27 | 0 | 0 | 0 | - | - |
| Summon Skeleton Mage | SummonSkeletonMageTree | 1 | 27 | 26 | 1 | 0 | 0 | cooldown x1, area->radius | increasedNecroticMorterRadius |
| Summon Spriggan | SummonSprigganSkillTree | 1 | 29 | 29 | 0 | 0 | 0 | - | - |
| Summon Storm Crow | SummonStormCrowTree | 2 | 31 | 30 | 1 | 0 | 0 | cooldown x1, area->radius | activeIncreasedRadius |
| Summon Storm Totem | StormTotemTree | 1 | 25 | 25 | 0 | 0 | 0 | - | - |
| Summon Thorn Totem | ThornTotemTree | 3 | 24 | 24 | 0 | 0 | 0 | - | - |
| Summon Volatile Zombie | SummonVolatileZombieTree | 2 | 29 | 28 | 1 | 0 | 0 | cooldown x1, area->radius | moreRadiusForGiantZombie |
| Summon Wolf | SummonWolfSkillTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Summon Wraith | SummonWraithTree | 1 | 28 | 24 | 4 | 0 | 0 | cooldown x1 | delayedWraiths, targetting |
| Surge | SurgeTree | 1 | 29 | 28 | 1 | 0 | 0 | area->radius | increasedRadius |
| Swarmblade Form | SwarmbladeTree | 9 | 33 | 32 | 1 | 0 | 0 | area->radius | increasedMeleeRadius |
| Swipe | SwipeSkillTree | 1 | 23 | 22 | 1 | 0 | 0 | cooldown x2, area->radius | increasedRadius |
| Synchronized Strike | SynchronizedStrikeTree | 1 | 28 | 28 | 0 | 0 | 0 | cooldown x1 | - |
| Teleport | TeleportTree | 2 | 24 | 24 | 0 | 0 | 0 | cooldown x1 | - |
| Tempest Strike | TempestStrikeTree | 6 | 32 | 30 | 0 | 2 | 0 | - | - |
| Tornado | TornadoSkillTree | 1 | 23 | 20 | 1 | 1 | 1 | cooldown x1, area->radius | increasedRadius |
| Transplant | TransplantTree | 2 | 28 | 27 | 1 | 0 | 0 | cooldown x1, area->radius | increasedExplosionRadius |
| Umbral Blades | UmbralBladesTree | 6 | 27 | 27 | 0 | 0 | 0 | - | - |
| Upheaval | UpheavalTree | 3 | 30 | 28 | 1 | 1 | 0 | cooldown x1, area->radius, doubled-cond more | increasedRadius |
| Vengeance | VengeanceTree | 4 | 29 | 27 | 0 | 2 | 0 | doubled-cond more | - |
| Void Cleave | VoidCleaveTree | 3 | 30 | 30 | 0 | 0 | 0 | cooldown x2 | - |
| Volatile Reversal | VolatileReversalTree | 4 | 28 | 28 | 0 | 0 | 0 | cooldown x2 | - |
| Volcanic Orb | VolcanicOrbTree | 1 | 26 | 21 | 0 | 5 | 0 | cooldown x1, 1/(1+x)-1 | - |
| Wandering Spirits | WanderingSpiritsTree | 1 | 27 | 26 | 1 | 0 | 0 | cooldown x2, area->radius | increasedDamageRadius |
| Warcry | WarcryTree | 2 | 31 | 31 | 0 | 0 | 0 | cooldown x2 | - |
| Warpath | WarpathTree | 1 | 27 | 27 | 0 | 0 | 0 | - | - |
| Werebear Form | WerebearFormTree | 4 | 28 | 27 | 1 | 0 | 0 | cooldown x2, area->radius | increasedRadius |

## 8. Не удалось установить

1. **Что делает мутатор с каждым полем.** Здесь извлечено точно, какое поле, какое значение и как оно зависит от очков. Как поле влияет на скилл, определяет код `<X>Mutator`.
   - Подсказки `field_usage_hints` есть для 3012 из 4372 записываемых полей. У 349 из них известен конкретный Stat: SP, тип и слот, например `FireballMutator.hypotheticalExtraProjectiles → getTempStats: Damage more`.
   - Остальные поля механические: число снарядов, длительность, флаги, шансы срабатывания. Их смысл надо разбирать по методам из `read_in` (`Mutate`, `getTempStats`, `OnHit`…) отдельной задачей по мутаторам.
   - Для движка приоритетны поля, читаемые в `getTempStats`/`Mutate`. Они перечислены в `read_in`.
2. Holy Aura: кому уходит `HolyAuraMutator.statsToApply` (копия ×2), себе или союзникам.
3. Узлы Manifest Armor «Reflects Damage» и «Chance To Slow When Hit» и узел Devouring Orb «Rift AoE Growth» не дают эффекта в `updateMutator`. Надо проверить, не читает ли их кто-то ещё (`LocalTreeData.getNodePoints` и т. п.). Поиск по литералам в LE.dll других мест не нашёл.
4. Хелперы без символов в `symbols.tsv`, идентифицированы по контексту: `0x18037F680 = powf(x, y)`, `0x18037C870 = Math.Round(double)`, `0x1803ECF60 = float→int` (RoundToInt или CeilToInt — **D?**).
5. 252 узла, где ни одно число тултипа не совпало с кодом. В основном это константы, которые живут в мутаторе (лимиты, длительности, «per X»). Расхождения кода и тултипа поштучно не проверялись, кроме §4.4 и случая с Ghidra.

**Функции для ручной декомпиляции (Ghidra не запускалась):**
- `FlameReaveTree.<updateMutator>g__AddMirroredLightningStats|1_0`;
- `HolyAuraMutator.getTempStats` / `AuraMutator` (куда идут `statsToApply`);
- `ManifestArmorMutator` (узлы Reflects и Slow When Hit);
- `0x1803ECF60`;
- методы `Mutate`/`getTempStats` мутаторов из `read_in` для полей без `feeds_stat` (по приоритету скиллов планировщика).

**Повторный запуск:** `tools/venv/Scripts/python tools/extract/mutator_coeffs.py` (~20 с). С фильтром по имени дерева (`... Fireball Rive`) результат пишется в `%TEMP%/skill_node_effects_partial.json`, общий файл не перезаписывается.
