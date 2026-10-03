# 07l. Holy Aura (Last Epoch 1.5.0): активный бафф и пассивная аура

Скилл: `Holy Aura` (AbilityID 187 `holyAura`, дерево `ah443` / `HolyAuraTree`, мастерство Paladin). Модель в машинном виде: `research/data/game/holy_aura_model.json`.

Источники: `HolyAuraMutator` (ISIL: `.ctor`, `Mutate`, `OnMutatorUpdate`, локальная функция `ApplyStatToAura|40_0`), `AuraMutator` (`.cctor`, `Mutate`), `HolyAuraTree.updateMutator`, `BuffOnAllyHit.Apply/addBuffToList`, `StatBuffs.addBuff(Buff)`, `Buff.generateName`, `AbilityStatsMutatorManager.UpdateAbilityStats` (case 0xBB), `KnightTree.updateMutator` (пассивки Paladin), типдеревья префабов `HolyAura` и `Aura` (UnityPy). Ghidra не запускалась. Константы проверены через `tools/readconst.py` и ISIL.

## 0. Краткий вывод

1. Это две разные мутации одного и того же набора баффов, а не два разных получателя. Получатели одинаковые: кастер и все союзники (в том числе миньоны) в сфере радиусом 20 м вокруг кастера.
2. **Пассивная аура** (`AuraMutator.Mutate`) кастуется автоматически каждые 0.5 с, бафф живёт 4.0 с и обновляется. Значения: `v * M`.
3. **Активный каст** (`HolyAuraMutator.Mutate`) на время «окна усиления» (4 с, 6 с с Concentration) заменяет пассивные касты. Значения: дефолты `v * 2 * M`, статы дерева `(2v) * M` (копию ×2 делает дерево, второй раз ×2 не умножается).
4. `M = 1 + X`, `X = mgr.holyAuraIncreasedEffect + increasedEffectFromPassives`. Единственный реальный источник в 1.5.0: пассивка Paladin «Covenant of Light» (`Paladin Covenant`), +0.04 за очко, максимум +0.20. Поле `increasedEffectFromPassives` фактически всегда 0.
5. Бафф с одинаковым именем на одном акторе заменяется, а не складывается. Поэтому активный каст перекрывает пассивный, а не добавляется к нему (итог ровно ×2 от пассивных значений, а не ×3).

## 1. Конвейер

### 1.1 Константы

| Что | Значение | Источник |
|---|---|---|
| `auraStatsMultiplier` (k, +0x13C) | 2.0 | `HolyAuraMutator..ctor` (0x40000000), префаб 2.0, `HolyAuraTree.updateMutator` пишет 2.0 снова; других писателей нет |
| множитель копии дерева | 2.0 (зашит) | `HolyAuraTree.updateMutator`: `Stat.multiplyValues(0x40000000)`; НЕ читает `auraStatsMultiplier` |
| `castInterval` (+0x1A4) | 0.5 с | `.ctor`, 0x3F000000 (в префабе поля нет, сериализуется только `auraStatsMultiplier`) |
| `passiveHolyAuraDuration` (+0x158) | 4.0 с | `.ctor`, 0x40800000 (= `basePassiveHolyAuraDuration` = `MAX_BUFF_DURATION`) |
| длительность пассивного баффа | 4.0 с | в `AuraMutator.Mutate` каждый `addBuffToList` получает константу 0x184561DD4 = 4.0 |
| окно усиления | `(1 + increasedBoostDuration) * 4` = 4 с / 6 с | `get_AuraBoostDuration`, `OnMutatorUpdate` |
| длительность активного баффа | `clamp(окно − timeSinceActiveCast + 0.6, 0.6, 4.0)` | `Mutate` (`castInterval + 0.1` = 0.6) |
| радиус | 20 м | `SphereCollider` (trigger) на префабах `HolyAura` и `Aura` (ability 190), scale 1. `AuraMutator.increasedRadius`/`duration` мёртвые |
| HitDetector | `ignoreCreator = 0`, `canApplyToSameAllyAgain = 0`, жизнь объекта 1 с | префабы |
| Откат / мана | 10 с (1 заряд, 0.1 зар/с) / 30 маны, instant cast | `abilities.json` |
| `HealthGlobe` радиус | 30 м (0x41F00000) | `OnActorDeath` |

Откат считается по общей формуле 06e §2.2: `CD = max(min, 1/regen)`, где `regen = (1 + moreCDR)(1 + incCDR)/((1 + incLength)(base + added))`. Концентрация и Faith's Reward дают `addedCooldownLength = +5` каждая, то есть база 10 → 15 → 20 с.

### 1.2 Расчёт X и M

```
X = mgr.holyAuraIncreasedEffect (+0x114C)  +  increasedEffectFromPassives
M = 1 + X
```

- `mgr.holyAuraIncreasedEffect` = сумма added-значений всех `AbilityPropertyStat(holyAura, index 0)` у кастера. `UpdateAbilityStats` case 0xBB, specialTag 0: `field += stat.added`. Глобальный текст: «increased Effect of Holy Aura».
  - Единственный источник в данных 1.5.0: пассивка Paladin `Paladin Covenant` («Covenant of Light», id 119, макс. 5): `+0.04` за очко (то же очко даёт Sigils of Hope index 1). Диапазон X: 0..0.20.
  - В `affixes.json`, `uniques.json`, `idols`, `blessings`, `weaver_node_effects` ни одного модификатора с ability 187 нет (единственная запись: аффикс 601 «Level of Holy Aura», `LevelOfSkills`; на число баффов не влияет, у скилла нет `levelScaling` статов).
- `increasedEffectFromPassives` (`HolyAuraMutator +0x140`, `AuraMutator +0x134`): пишет только `KnightTree.updateMutator`, значение `0.1 * очки` узла с именем `Paladin Increased Holy Aura Effectiveness`. Такого узла в данных дерева нет (`code_node_names_not_in_tree`), т.е. поле = 0. Дерево самого Holy Aura это поле не трогает.
- Общего «increased aura effect» / «increased buff effect» стата, который бы влиял на Holy Aura, нет. `frenzyTotemIncreasedEffectOfBuffs`, `dreadShadeIncreasedBuffEffect` относятся к другим скиллам. На стороне получателя `StatBuffs.addBuff` никакого эффект-множителя не применяет: стат из баффа добавляется в `Stats` получателя как обычный.
- X и M аддитивны внутри (`1 + a + b`), M умножает значение стата.

### 1.3 Пассивная аура (`AuraMutator.Mutate`)

Когда: `HolyAuraMutator.OnMutatorUpdate` накапливает `t += dt`; при `t > 0.5` (и если Holy Aura есть у актора в `AbilityList`) и не идёт окно усиления создаёт объект абилки 190 (`Aura`) в позиции кастера и обнуляет `t`. Если стоит `inactiveWhileOnCooldown` (Concentration) и Holy Aura на откате, пассивный каст пропускается.

Каждый объект применяет баффы всем союзникам в сфере 20 м (в том числе кастеру) один раз (`canApplyToSameAllyAgain = 0`); раз в 0.5 с создаётся новый объект, поэтому бафф постоянно обновляется (заменой по имени, остаток 4.0 с).

Список баффов (в порядке добавления; идентификатор имени в скобках):

| Бафф | Значение | Условие |
|---|---|---|
| ElementalResistance added | `0.15 * M` («default aura mutator») | `!disableDefaultStats` |
| Damage increased (tags 0) | `0.30 * M` («default aura mutator») | `!disableDefaultStats` |
| каждый стат из `AuraMutator.statsToApply` | `v * M` («aura mutator») | список непуст |
| ManaRegen increased | `mgr.holyAuraIncManaRegen * M` («extra aura mutator») | `holyAuraIncManaRegen != 0` |
| BlockEffectiveness added | `Strength * mgr.holyAuraBlockEffectivenessPerStrength * M` | `perStr > 0` и `stats` валиден |
| Movespeed increased | `mgr.holyAuraIncreasedMovespeed * M` | `> 0` |
| StunAvoidance increased | `mgr.holyAuraIncreasedStunAvoidance * M` | `> 0` |

Флаг `holyAuraPersonalMinionsOnly` (+0x1165) → `BuffOnAllyHit.onlyApplyToCreatorsMinions = 1`: баф получают только миньоны кастера (сам кастер исключён, `IsMinionOf`).

Только для кастера (его `StatBuffs`, без M): при `canFlameBurst` бафф `AilmentChanceStat(HolyAuraStackForFlameBurst, Melee) = 9 + addedFieryInquisitionStacksOnMeleeHit`, 4 с (имя «Aura Personal Flame Burst»). Дополнительно `holyAuraElectrifyChancePerSecondPerAttunement > 0` добавляет `RepeatedlyApplyAilmentsInRadius` (r = 10 м) с шансом `Attunement * value * castInterval` по врагам.

### 1.4 Активный каст (`HolyAuraMutator.Mutate`)

Когда: игрок кастует Holy Aura (30 маны, instant). При первом касте `isRecastOfActive = false` и `timeSinceHolyAuraActiveCast := 0`. Далее `OnMutatorUpdate` каждые 0.5 с, пока `timeSince <= (1 + increasedBoostDuration) * 4`, повторно кастует активный объект (`isRecastOfActive = true`) вместо пассивного. После окна возвращается пассивный каст; его бафф с теми же именами перезаписывает активный (удвоение заканчивается через ≤ 0.5 с после окна).

Длительность: `D = clamp(окно − timeSince + 0.6, 0.6, 4.0)`.

| Бафф | Значение | Условие |
|---|---|---|
| ElementalResistance added | `0.15 * k * M` = `0.30 * M` | `!disableDefaultStats` |
| Damage increased | `0.30 * k * M` = `0.60 * M` | то же |
| каждый стат из `HolyAuraMutator.statsToApply` | `(2v) * M`, где `2v` уже посчитано деревом; повторно на k не умножается | список непуст |
| ManaRegen increased | `holyAuraIncManaRegen * k * M` | `!= 0` |
| BlockEffectiveness | `Strength * perStr * k * M` | `perStr > 0` |
| Movespeed | `holyAuraIncreasedMovespeed * k * M` | `> 0` |
| StunAvoidance | `holyAuraIncreasedStunAvoidance * k * M` | `> 0` |
| HealthRegen added | `holyAuraHealthRegenInActiveMode * M` (БЕЗ k) | `> 0`, только в активе |
| PlayerProperty 450 (slow/chill immunity) | `1.0 * M` (булев по смыслу) | `holyAuraActiveSlowImmune` или `holyAuraActiveChillImmune` |

Только кастеру, без M: при `canFlameBurst` `AilmentChanceStat(HolyAuraStackForFlameBurst, Melee) = k*9 + addedStacks` (то есть 18 + добавленные), длительность `D`.

Только при первом касте (не при повторных): `wardGainedOnActivation` (GiveResourcesOnHit.wardOnHit), `activeCleanse` (CleanseAilmentsOnHit: все негативные, союзники), `mgr.holyAuraMoreIgniteDamageOnActivation` (`AmplifyDamageOfAilmentOfType(Ignite, value, onlyFromSpecificActor = кастер)` по врагам с Ignite в манхэттенской дистанции < 20 м от кастера).

На каждый тик (0.5 с): `chanceToSlowEnemiesEverySecond * castInterval` шанс замедления на врагов, попавших в объект; флаги fear (r = 10 м), blind, сброс откатов Evade/Traversal берутся из менеджера (`holyAura*`).

### 1.5 Как бафф попадает в статы

`BuffOnAllyHit.Apply(actor)`: для каждого `Buff` из списка делает копию и вызывает `StatBuffs.addBuff(Buff)`. Тот сначала `removeBuffsWithName(name)`, потом добавляет бафф и вызывает добавление стата в `Stats` актора. Имя: `Buff.generateName(identifier, stat)` = формат из семи полей: `identifier`, `SP`, `AT`, `specialTag`, `extraTag`, `added>0`, `increased>0`.

Следствия:
- Активный и пассивный бафф одного стата имеют одно имя, поэтому активный заменяет пассивный (не складывается).
- Дефолтные («default aura mutator») и стат дерева («aura mutator») имеют разные идентификаторы: ER 0.15*M и ER +5%/очко дерева суммируются как два разных added.
- Краевой случай: «Block Effectiveness per Strength» (`AddedStat(BlockEffectiveness, tags 0)`) имеет то же имя, что стат узла Mighty Shield, и добавляется в список позже, поэтому ЗАМЕНЯЕТ значение узла, а не прибавляется. Источника такого свойства среди предметов 1.5.0 в данных нет.

## 2. Числовые примеры

Обозначения: p = очки узла, M = 1 + X, значения «increased»/«added» даны в долях (0.15 = 15%).

**Пример A: только дефолты, X = 0**

| | Пассив | Актив |
|---|---|---|
| ElementalResistance added | 0.15 | 0.30 |
| Damage increased | 0.30 | 0.60 |

**Пример B: Covenant of Light 5/5 (X = 0.20, M = 1.2), Fanaticism 3/3, Shelter from the Storm 5/5, Firestorm 5/5**

| Стат | Формула пассив | Пассив | Актив |
|---|---|---|---|
| ER (default) | `0.15 * 1.2` / `0.30 * 1.2` | 0.18 | 0.36 |
| Damage increased (default) | `0.30 * 1.2` / `0.60 * 1.2` | 0.36 | 0.72 |
| AttackSpeed / CastSpeed increased | `0.03*3 * 1.2` / `0.18 * 1.2` | 0.108 каждый | 0.216 каждый |
| ER (узел) | `0.05*5 * 1.2` / `0.50 * 1.2` | 0.30 | 0.60 |
| Endurance added | `0.03*5 * 1.2` / `0.30 * 1.2` | 0.18 | 0.36 |
| Damage increased, Fire | `0.10*5 * 1.2` / `1.00 * 1.2` | 0.60 | 1.20 |
| Damage increased, Lightning | то же | 0.60 | 1.20 |

Суммарный ER для получателя: пассив 0.18 + 0.30 = 0.48, актив 0.36 + 0.60 = 0.96 (до капа сопротивлений).

**Пример C: B + Flame Burst 1/1, Inner Flame 2/2, Purification 1/1, passive Covenant of Dominion (holyAuraIncManaRegen = 0.25)**

| Стат | Пассив | Актив |
|---|---|---|
| ManaRegen increased | `0.25 * 1.2` = 0.30 | `0.25 * 2 * 1.2` = 0.60 |
| PoisonResistance added | `0.2 * 1.2` = 0.24 | `0.4 * 1.2` = 0.48 |
| HolyAuraStackForFlameBurst chance (союзникам) | `1 * 1.2` = 1.2 | `2 * 1.2` = 2.4 |
| личный бафф кастера (без M) | 9 + 2 = 11 | 18 + 2 = 20 |

## 3. Какой из прежних отчётов прав

- **07j** (`HolyAuraMutator.statsToApply` + `defaultStats × 2.0`, копия дерева ×2 не умножается повторно; ER +0.15, Damage +0.30): верно для активного пути. Неполно: нет множителя `(1+X)`, нет пассивного `AuraMutator.Mutate` (не разбирался), нет extras и таймингов.
- **07h** (`ApplyStatToAura`: клон, ×`auraStatsMultiplier` если флаг, всегда ×`(1+X)`): верно. Флаг true для дефолтов и extras (mana regen, block/Str, movespeed, stun avoidance), false для списка дерева, health regen и иммунитета. Уточнение: `X` формируется в `Mutate` как `mgr +0x114C + increasedEffectFromPassives`, поэтому фраза «`increasedEffectFromPassives` в этой функции не читается» верна только для самой локальной функции (она получает готовый X).
- **07c** (узел кладёт стат в `AuraMutator.statsToApply`, копию ×2 в `HolyAuraMutator.statsToApply`): верно. Открытый вопрос «кому уходит копия ×2» закрыт: получатели одинаковы (кастер и союзники в 20 м); отличается только момент (пассив постоянно, актив в окне усиления).
- **Черновик Haiku** (`dump/work_wave4/holy_aura.md`): в основном неверен.
  - Активный бафф «только игроку», пассивная аура «только союзникам»: неверно, `ignoreCreator = 0`, оба пути бьют всех в сфере.
  - Поле `increasedEffectFromPassives` названо «increased aura effect» из дерева: неверно, оно всегда 0; настоящий X идёт из `mgr.holyAuraIncreasedEffect` (Covenant of Light).
  - Три «пути» на самом деле два (пассив ×1, актив ×2), дефолты «×2 только в активе» верно, но то же самое относится и к extras.
  - Не учтены 0.5 с / 4.0 с, замена баффа по имени, окно усиления, особые баффы кастера.
  - Смещения: `AuraMutator +0x134/+0x120/+0x158` названы верно; `HolyAuraMutator +0x158` на самом деле `passiveHolyAuraDuration` (float 4.0), а не ссылка на `StatBuffs`; `+0x1A4` это `castInterval` (0.5), а не «дополнительный модификатор».
  - Верно в черновике: формулы `v * (1 + X)` для пассива, «дефолты ×2 только в активе», `(2v) * (1+X)` для статов дерева в активе.

## 4. Узлы дерева Holy Aura (финальные формулы)

`p` = очки узла. Для статовых узлов: пассив = `raw * p * M`, актив = `2 * raw * p * M` (флоат `raw` ниже за одно очко). Все 27 статовых записей проверены автоматически: значение в `HolyAuraMutator.statsToApply` ровно вдвое больше значения в `AuraMutator.statsToApply`.

| id | Узел (отображаемое имя) | max | Стат / поле | пассив за очко | актив за очко |
|---|---|---|---|---|---|
| 2 | Flame Burst | 1 | `canFlameBurst`; AilmentChance HolyAuraStackForFlameBurst (Melee) | 1.0*M | 2.0*M; личный бафф 9+stacks / 18+stacks |
| 3 | Improved Flame Burst | 4 | `finalHitDamageMultiplier` | +50% more на Holy Flame Burst за очко (не баф) | то же |
| 4 | Fanaticism | 3 | AttackSpeed inc, CastSpeed inc | 0.03*M | 0.06*M |
| 5 | True Strike | 4 | CriticalChance inc | 0.10*M | 0.20*M |
| 6 | Extreme Zeal | 3 | CriticalMultiplier added | 0.05*M | 0.10*M |
| 7 | Firestorm | 5 | Damage inc (Fire), Damage inc (Lightning) | 0.10*M | 0.20*M |
| 8 | Rahyeh's Devotion | 3 | AilmentChance Ignite, Electrify | 0.05*M | 0.10*M |
| 9 | Rahyeh's Fury | 2 | Penetration added (Fire), (Lightning) | 0.05*M | 0.10*M |
| 10 | Call To Arms | 5 | Damage inc (Physical) | 0.10*M | 0.20*M |
| 11 | Strength From Afar | 4 | Damage inc (Throwing), IncreasedStunChance (Throwing) | 0.12*M | 0.24*M |
| 12 | Shelter from the Storm | 5 | ElementalResistance added; Endurance added | 0.05*M; 0.03*M | 0.10*M; 0.06*M |
| 13 | Swiftness | 3 | DodgeRating added | 20*M | 40*M |
| 14 | Redemption | 4 | IncreasedHealing added | 0.10*M | 0.20*M |
| 15 | Concentration | 1 | `increasedBoostDuration` +0.5, `inactiveWhileOnCooldown`, +5 с откат | окно 6 с; пассив отключён на откате | без M и k |
| 16 | Purification | 1 | `activeCleanse`; PoisonResistance added | 0.2*M | 0.4*M (+ очистка при первом касте) |
| 17 | Demoralizing Aura | 2 | `chanceToSlowEnemiesEverySecond` | только актив | 0.25*p шанс slow на объект (0.5*p за секунду), без M и k |
| 18 | Expedite | 3 | AttackSpeed inc (Throwing); HasteOnHitChance added | 0.03*M | 0.06*M |
| 19 | Vital Boon | 4 | HealthRegen increased | 0.10*M | 0.20*M |
| 20 | Faith | 5 | WardRegen added | 3*M | 6*M |
| 21 | Shielded By Faith | 4 | WardRetention added | 0.05*M | 0.10*M |
| 22 | Faith's Reward | 1 | `wardGainedOnActivation` +400, +5 с откат | не работает | 400 ward при первом касте, без M и k |
| 23 | Mighty Shield | 4 | BlockEffectiveness added; HealthGain on block (specialTag 6) | 30*M; 2*M | 60*M; 4*M |
| 24 | Against The Odds | 3 | WardGain on block (specialTag 6) added | 7*M | 14*M |
| 26 | Hope | 1 | `healthGlobeOnNearbyEnemyDeathChance` | 12% шанс globe при смерти врага в 30 м | не зависит от каста |
| 28 | Inner Flame | 2 | `HolyFlameBurstMutator.increasedArea` +25%/очко; `addedFieryInquisitionStacksOnMeleeHit` +1/очко | личный бафф 9+p | 18+p |

Полный список с SP-именами, тегами и видом значения в `research/data/game/holy_aura_model.json`, ключ `nodes`.

## 5. Что осталось неизвестным

- Масштаб/доставка `GiveResourcesOnHit` (400 ward): компонент добавляется на объект абилки, кому именно (только кастеру или всем союзникам) определяется флагами префаба `GiveResourcesOnHit` (поведение по умолчанию не прослежено).
- Реальные источники `mgr.holyAuraIncManaRegen`, `holyAuraIncreasedMovespeed`, `holyAuraIncreasedStunAvoidance`, `holyAuraBlockEffectivenessPerStrength` и флагов (slow/chill immune, fear, blind, minions-only и т.д.): среди 1.5.0 данных есть только пассивки Paladin для индексов 0, 1 (Covenant of Dominion, ≥ 5 очков, 0.25) и 2 (Sword of Rahyeh, ≥ 5 очков, 0.5); остальные индексы в данных аффиксов/уникальных не найдены.
- Что именно делает виртуальный вызов `AbilityList +0x208` (по сигнатуре `hasAbilityEquipped(Ability)`/`hasAbility`): считаем условием «Holy Aura присутствует в списке умений».
