# 07a — Игровые данные из ассетов Last Epoch 1.5.0: классы, атрибуты, свойства, монстры, ailments, предметы

Дата: 2026-10-03. Источник: экспорт AssetRipper `dump/assets/ar2/ExportedProject/Assets/` (YAML), плюс `global-metadata.dat` для таблиц ActorScaler. Код (адреса, формулы) — из `dump/decomp`, `dump/isil`, `dump/cs`, как в 06a–06e.

Метки: **A** — значение прочитано из ассета; **D** — из кода; **D?** — из кода, но трактовка неоднозначна; **X** — подтверждено внешними данными (Maxroll / LETools).

---

## 0. Главное

1. **Конфликты 02/06a закрыты данными (A, X).** Во всех пяти `CharacterClass` записано `healthPerLevel = 10` (int) и `healthRegenPerLevel = 0.14`. Гайд (8 и 0.125) устарел. С формулой 06a это даёт `Health(L) = 100 + 10·L` и `HealthRegen(L) = 6 + 0.14·L`. `manaPerLevel = 0.50506`, `baseMana = 50`, `manaRegen = 8`. Сила миньонов: `26 / 0.008 / 0.008` (A, подтверждает 06e). У всех классов одинаково `baseEndurance = 0.2`, `enduranceThresholdPerHealth = 0.2`, `baseMoreDoTDamageTaken = −0.15`, `baseStunAvoidance = 250 + 5·L`. Классы различаются только стартовыми атрибутами.
2. **Сериализованный `GlobalPlayerProperties` расходится с дефолтами конструктора (A).** `bossEffectiveHealthModifierVsStun` и `bossEffectiveHealthModifierVsFreeze` равны **0.5**, а не 0.25, как предполагал 06c §4. Значит, для боссов `EH × 1.5`, и это совпадает с гайдом и 02 §5.4. Константы распада варда совпадают с дефолтами: `q = 5e−5`, `l = 0.2`, минимум 0.5/с.
3. **Аффиксы: модификатор эффекта считается относительно «эталонной» базы (D, поправка к 06a §7.1).** `AffixList+Affix.getModifier` @0x1811B13C0 возвращает `m = (1+itemAEM)/(1+affix.standardAffixEffectModifier) − 1`, а при равенстве 0. Значения тиров в `AffixList` хранятся для базы с `standardAffixEffectModifier`. В формулу 06a §7.1 нужно подставлять `m`, а не сырой `affixEffectModifier` предмета. Пример: Added Melee Physical Damage T8 [85, 100] со standard 0.75 на 2H-топоре (AEM 2.2) даёт `m = 3.2/1.75 − 1 = 0.8286` и диапазон [155, 183].
4. **Редкость монстров идёт через `MonsterRarityManager.setActorRarity` @0x1827FE1B0 (D, ISIL).** Оба вызова `ChangeStatModifier` используют ModType 2 = **MORE**:
   - magic: Health MORE +1.15 (×2.15), Damage MORE +0.6;
   - rare: Health MORE +1.6 + 0.02·L′, Damage MORE +0.9;
   - L′ = L / (1 + 0.5·effHM), если `UnitHealth.healthSerialisation == 1`.

   Цифры Tunklab «×2.15» подтверждаются для magic.
5. **Мод порчи (A).** `Monster Power From Corruption Mod`: Health MORE 0.01, Damage(Hit) MORE 0.01, **Damage(DoT) MORE 0.005**, плюс increasedItemRarity 0.01 за единицу эффекта. Эффект равен `f(c) − 1` (06c). DoT монстров растёт от порчи **вдвое медленнее**, чем хиты и здоровье.
6. **Таблицы ActorScaler (D/A).** Все четыре массива float[101] (`damageReduction`, `effectiveHealthModifier`, `damageModifier`, `originalDamageApproximation`) извлечены из `global-metadata.dat` и совпадают с опорными точками 06c.
7. **Ailments: пробелы 06d закрыты (A).**
   - Blind = `CriticalChance MORE −1`, то есть «не может критовать».
   - Frenzy = +20% increased attack и cast speed.
   - VoidResShred = −5% void res за стак.
   - PhysicalResShred имеет id 73.
   - ExposedFlesh: −15% cold res и +30% chance to be frozen, `mutationType = AbilityMutator`.
   - `addedDamageScaling`, `penetration`, флаги замещения и `mutationType` есть для всех 149 ассетов.
8. **Сверка (X).** Сравнено всё:
   - с Maxroll: 1156 аффиксов, 781 база и подтип, 486 уников, 24 сета, 128 ailments, 113 правил округления, 712 player properties, 63 списка благословений, 5 классов;
   - с LETools: 234 монстр-мода, 5 атрибутов.

   Расхождений в значениях **0**. Есть только различия в полноте (§9).

---

## 1. Как запускать

```
tools/venv/Scripts/python tools/extract/extract_classes.py    # classes, attributes, global_player_properties
tools/venv/Scripts/python tools/extract/extract_monsters.py   # monster_rarity, monster_mods, actor_scaler
tools/venv/Scripts/python tools/extract/extract_ailments.py   # ailments
tools/venv/Scripts/python tools/extract/extract_items.py      # affixes, items, uniques, sets, idols, blessings
tools/venv/Scripts/python tools/extract/crosscheck_maxroll.py <maxroll data.json> [letools coreDB.js] [letools endgame.js]
```

`tools/extract/le_assets.py` — общий загрузчик. Что в нём учтено:
- PyYAML (CSafeLoader) с расширенным float-резолвером: Unity пишет `5E-05`, а YAML 1.1 считает такое строкой.
- AssetRipper пишет примитивные массивы (`List<int>`, `List<byte>`) одной hex-строкой little-endian (`canRollOn: 15000000160000001400000004000000` = [21, 22, 20, 4]). Загрузчик закавычивает такие скаляры, чтобы YAML не превратил их в восьмеричные int, а `hex_ints()` их декодирует.
- guid → путь берётся из `.meta` (кэш `dump/assets/guid_index.tsv`).

PyYAML установлен в `tools/venv`. Время полного прогона около 12 с. После патча нужен только новый экспорт AssetRipper. Сигнатуры ActorScaler ищутся по опорным значениям (§4.3); если EHG поменяет таблицы, поиск об этом сообщит.

Общий конверт каждого файла: `{gameVersion, source, schema, ...доп. поля, data: [...]}`.

### 1.1 Как значения ложатся на стат-модель (06a §11)

Каждый мод во всех файлах нормализован одинаково (`le_assets.norm_stat` / `extract_items.stat_key`):

| Поле | Смысл |
|---|---|
| `property` / `propertyName` | SP (0–133), имя из `sp_enum.json` |
| `specialTag` | подтип: AilmentID, HitEventTag, CDP, индекс AbilityProperty; 0 — подстановочный знак |
| `tags` / `tagNames` | маска AT (семантика подмножества + правило Elemental). `tagNames` **не выводится**, если `tags` — индекс: SP 58 (AbilityID), 98 (индекс PlayerProperty), 100 (AilmentID), 104/105 (категория дропа: при `specialTag = 0` это EquipmentType, см. `dropRateItemType`), 123 (Tracker), 130 (IdolAltar) |
| `extraTag` | AbilityID (мод привязан к скиллу) |
| `added` / `increased` / `more[]` | для Stat-подобных записей (атрибуты, баффы, монстр-моды) |
| `modType` | ADDED / INCREASED / MORE / QUOTIENT. У аффиксов, импликитов, уников и сетов тип задан явно, значение одно (`value`, `[min, max]`); у Stat-записей вычисляется по `Stat.GetModType` |
| `rounding` | сетка квантования для этого мода (§3.2) |

---

## 2. classes.json, attributes.json

### 2.1 classes.json (A; формулы D из 06a §5.3)

`data[]` содержит 5 записей по `classID`: Primalist 0, Mage 1, Sentinel 2, Acolyte 3, Rogue 4.

| Поле | Значение / пример |
|---|---|
| `className`, `treeID` | `Acolyte`, `ac-1`. Деревья: pr-1, mg-1, kn-1, ac-1, rg-1 |
| `passiveTree` | `{name, treeID, version, nodeCount, nodesPerMastery}` из Global Tree Data, например Acolyte {0: 15, 1: 29, 2: 34, 3: 31} |
| `base` | все числовые поля CharacterClass (см. §0 п. 1) |
| `minionScaling` | `{firstLevelForMinionScaling: 26, moreMinionDamagePerLevel: 0.008, lessMinionDamageTakenPerLevel: 0.008}` |
| `levelMods[]` | стат-модель SetInitialValues: `{property, modType, base, perLevel, tags?}` (Health, Mana, HealthRegen, ManaRegen, StunAvoidance, Endurance, EnduranceThreshold, SP96, DamageTaken DoT MORE, 5 атрибутов). Значение = base + L·perLevel |
| `masteries[]` | `masteryIndex` 0–3 (0 — базовый класс; это значение `requiredMastery` узлов дерева), `name`, `masteryAbility {asset, name, playerAbilityID}`, `abilities[{…, level}]`, `passiveNodes` |
| `defaultAbilities`, `knownAbilities`, `unlockableAbilities`, `basicAttackReplacer`, `startingItems` | ссылки на Ability, разрешённые в `{asset, name, playerAbilityID}` |
| `specialTagForClassSpecificLevelOfSkillsStats` | specialTag для «+N к скиллам класса» |

На уровне файла лежат ещё `hiddenBaseMods` (константы из кода, 06a §5.3: AttackSpeed/CastSpeed BASE 1, Movespeed MORE 0.05, minion Movespeed MORE 0.10, IncreasedStunChance INC 1.0 Melee|Bow, minion DamageTaken MORE −0.6) и `formulas`.

Стартовые атрибуты: Primalist Str 2 / Att 1; Mage Int 3; Sentinel Str 2 / Vit 1; Acolyte Int 2 / Vit 1; Rogue Dex 3.

### 2.2 attributes.json (A, X)

`data[]` содержит 5 записей: `{attribute, name, statProperty (19–23), perPoint[], corruptedPerPoint[], corruptedFlag{property 98, tags 650–654, playerPropertyName}}`.

| Атрибут | За очко | Испорченный (заменяет perPoint) |
|---|---|---|
| Strength | Armour INC +4% | PlayerProperty 636 («Damage for Melee Attacks per 1 Mana Cost (up to 20)») MORE 0.0002; HealthLeech INC −0.5% |
| Vitality | Health +6; Necrotic Res +1%; Poison Res +1% | EffectOfAilmentOnYou INC +3%; PlayerProperty 638 («Damage Taken while you don't have Frenzy») MORE 0.001 |
| Intelligence | WardRetention +2% | CritMultiplier (Spell) +1%; ReducedBonusDamageTakenFromCrits −1% |
| Dexterity | DodgeRating +4 | AbilityProperty (acolyteEvade, idx 9 «Increased Cooldown Recovery Speed for Movement Skills») +0.3%; Armour INC −1% |
| Attunement | Mana +2 | ManaRegen INC +2%; PlayerProperty 637 («Current Health lost when you directly use a Skill») +0.2% |

Флаг порчи: SP98 с tags 650 (Str, «Strength Converted to Brutality»), 651 (Int), 652 (Dex), 653 (Att), 654 (Vit). Эти индексы совпадают с 06a §5.1 и с именами в PlayerPropertyList.

---

## 3. global_player_properties.json

### 3.1 GlobalPlayerProperties (A)

`data.globalPlayerProperties` содержит все поля ассета. Для формул важны:

| Поле | Ассет | Дефолт конструктора (06c) |
|---|---|---|
| quadraticWardDecay | 5e−5 | 5e−5 |
| linearWardDecay | 0.2 | 0.2 |
| minimumWardDecayWithoutRegen | 0.5 | 0.5 |
| **bossEffectiveHealthModifierVsStun** | **0.5** | 0.25 |
| **bossEffectiveHealthModifierVsFreeze** | **0.5** | 0.25 |
| bossWardGainModifier | −0.25 | — |
| bossWardPercentDecay / …PerSecond / …PerSquareSecond | 0.04 / 0.005 / 3e−5 | — |
| baseBossWardDecayEffectiveTimeDivisor / …PerEffectiveHealthMultiplier | 0.75 / 0.0075 | — |

Сравнение лежит в `data.assetVsConstructorDefaults`. Поля boss ward относятся к варду **боссов**; формулы в коде не разбирались (§10).

### 3.2 Свойства, отображение и сетка квантования (A, X)

| Ключ | Источник | Схема |
|---|---|---|
| `statProperties[113]` | MasterPropertyList | `{property, name, spName, roundingForAdded, roundingForMore, roundingForIncreased: "Hundredth", moreRoundingOverrides[{specialTag, roundingForMore}], display{…флаги ≠ 0}, altText}` |
| `conditionalDamageProperties[48]` | то же | тексты CDP по индексу |
| `playerProperties[713]` | PlayerPropertyList | `{index, name, rounding…, display}`. Индекс = `tags` у SP98 |
| `abilityProperties[177]` | AbilityPropertyList | `{abilityID, abilityIDName, properties[{index, name, rounding…}]}`. `index` = specialTag у SP58 |
| `trackerProperties[2]`, `idolAltarProperties[31]` | TrackerPropertyList, IdolAltarPropertyList | аналогично |
| `propertyRoundingEnum`, `propertyRoundingScale` | `PropertyRounding` | Hundredth 0 → ×100, Integer 1 → ×1, Tenth 2 → ×10, Thousandth 3 → ×1000 |

Как выбирается сетка для мода (`extract_items.Rounding.get`; повторяет `BasePropertyInfo.GetRounding`, 06a §7.1):
- ADDED → `roundingForAdded`;
- INCREASED → всегда Hundredth;
- MORE → `moreRoundingOverrides[specialTag]`, иначе `roundingForMore`.

Для SP98, SP58, SP123 и SP130 PropertyInfo берётся из своего списка по индексу.

Распределение по аффиксам: Hundredth/ADDED 779, Integer/ADDED 503, Hundredth/INCREASED 373, Thousandth/MORE 18, Hundredth/MORE 10, Tenth/ADDED 7, Thousandth/ADDED 6.

---

## 4. Монстры

### 4.1 monster_rarity.json (A + D)

`data = {magic, rare}`, поля `MonsterRarityManager+MonsterRarity`:

| | increasedHealth | …PerLevel | additionalEffectiveHealthModifier | increasedDamage | increasedExperience | …PerLevel | increasedItemDrops | increasedSize | префикс/суффикс |
|---|---|---|---|---|---|---|---|---|---|
| magic | 1.15 | 0 | 1 | 0.6 | 0.5 | 0 | 2.05 | 0.2 | 0 / 1 |
| rare | 1.6 | 0.02 | 2.5 | 0.9 | 2.0 | 0.04 | 5.2 | 0.5 | 1 / 1 (guaranteedRareItemDrop) |

Порядок в `setActorRarity` (D, ISIL @0x1827FE1B0):
1. `UnitHealth.effectiveHealthModifier += additionalEffectiveHealthModifier`.
2. `hpl = increasedHealthPerLevel`; если `healthSerialisation == 1` и effHM > 0, то `hpl /= (1 + 0.5·effHM)`.
3. `ChangeStatModifier(Health, increasedHealth + level·hpl, MORE)`.
4. `ChangeStatModifier(Damage, increasedDamage, MORE)`, без тегов.
5. Опыт `×(1 + inc + level·incPerLevel)`; шанс дропа `×(1 + increasedItemDrops)` с переносом излишка в количество; размер `×(1 + increasedSize)`.

Пример: rare на уровне 100 с effHM = 2.5 → hpl = 0.02/2.25 = 0.00889 → Health MORE +2.489 (×3.489), Damage ×1.9.

### 4.2 monster_mods.json (A, X)

`data[239]` (StatsMonsterMod):
```
{key, name, modType(Prefix|Suffix|Monolith|Dungeon|EventActor|TimeBeast), title, description, minilithDescription,
 inRarePrefixPool, inSuffixPool, monolith{timelineIDs[], differentForEmpowered, empoweredTimelineIDs[]},
 minimumLevel, rarityRequirement, increasedItemRarity, increasedExperience,
 stats[норм. Stat], rareModifier, scalingType(None|Level|Health), flatScaling, perUnit, perUnitSquared,
 onlyScaleSomeStats, numberOfStatsToScale, effectModifierEffect(Full|None|Capped|Partial|CappedPartial),
 effectModifierCap, statsWithoutEffectModifier, incompatibleETags, necessaryETags, soulGambler…}
```

Дополнительно:
- `otherMonsterMods[51]` — Component/PseudoComponent/CastsAbility/ContractsAilments моды, только имя, ключ и описание;
- `timelines[]` — по таймлайну: `difficulties[{level, modFromCorruption, minimumCorruption, maximumCorruption, additionalCorruptionEffect(None|Level|RewardRarity), corruptionRequiredPerLevel}]`, `mods`/`empoweredMods` с именами и глубиной, `modEffectivenessFormulae`.

Масштаб стата мода (06e §5.2): `k = (isRare ? 1 + rareModifier : 1)·(1 + effect)·(flatScaling + perUnit·x + perUnitSquared·x²)`. Примеры:
- «Increased Health»: Level, flat 1, perUnit 0.01;
- «Increased Damage»: Level, 1 / 0.0025, rareModifier 0.1;
- монолитные моды: Capped, cap 0.75–3.

Таймлайны (normal): уровень 62/66/70/74/78/82/85/90/90/90, порча 0–50, `Level`. Каждые 5 порчи (10 для T7–T10) дают +1 к уровню зоны. Empowered: уровень 100, порча ≥ 100, `RewardRarity`.

### 4.3 actor_scaler.json (D/A)

`data.tables` содержит четыре массива float[101] (индекс — уровень монстра), `metadataOffsets` (DR 18405528, effHM 18406016, dmgMod 19215768, origDmg 19216256), `constants` из ActorScaler.cs и `formulas`.

| | L0 | L50 | L100 |
|---|---|---|---|
| damageReduction | 0 | 0.54 | 0.87 |
| effectiveHealthModifier | −0.09 | 0.24 | 0.95 |
| damageModifier | −0.05 | −0.13 | 0.157 |
| originalDamageApproximation | 1.30 | 9.36 | 15.25 |

`research/data/monster_level_damage_reduction.json` (06c) совпадает с `tables.damageReduction` побайтно. Поиск идёт по значениям-сигнатурам (§10 п. 6).

---

## 5. ailments.json (A, X)

`data[149]` — все ассеты `LE:Ailment`. 148 из них в `AilmentList`; `Morditas Gauntlet Enemy Buff` (id 60, дубль ShrineHaste) в список не входит, поэтому `inList = false`. В `AilmentList.list` 150 ссылок, из них 2 дубля (индексы 111 и 118).

Схема: все сериализованные числовые и bool-поля Ailment (UI, иконки и VFX выброшены), плюс:
- `id`, `ailmentIDName`, `name`, `inList`, `listIndex`;
- `duration`, `maxInstances`, `positive`, `tags` и `tagNames`;
- `baseDamage{damage[7], damageByType, critChance, critMultiplier, critType(+Name), isHit, addedDamageScaling, penetration[], freezeRate, cull…, additionalLeech, leechVsPlayers, convertAllAddedDamage, damageTypeToConvertTo, conditionalEffects}`;
- `effectOfIncreasedEffectiveness(+Name)`, `additionalPenetrationDamageType(+Name)`, `buffScalingType(+Name)`, `maxStacksThatApplyBuffs`, `buffs[норм. Stat]`, `moreBuffEffectAgainstBosses`, `moreBuffEffectAgainstPlayers`;
- `dealsDamage`, `dealsAllDamageAtEnd`, `dealsDamageWhenHit`, `moreDamageWhenHitByCreator`, `dealsDamageWhenAffectedHitsOthers`, `dealsDamageOnAnguish`, `damageScalesWithTargetHealth`, `moreDamageAtFullHealth`, `moreDamageAtHealthThreshold`, `moreDamageHealthThreshold`;
- `spreads`, `spreadRange`, `spreadDelay`, `maxSpreadPerInstance`, `heals`, `totalHealingOverDuration`;
- `effectOfEffectivenessOnProc`, `procsAbilityWhenStacksReached`, `abilityToProcWhenStacksReached` (имя), `stacksRequiredForProc`, `procsAbilityOnExpiration`;
- `dontReplaceHigherDurationStacks`, `prioritiseStrongestStacks`, `replaceLowestDamageStacksInsteadOfOldest`, `stopsWhenHit`, `hitsRequiredToStop`;
- `blinds`, `roots`, `isCurse`, `isBrand`, `uncleansable`, `mutationType(+Name)`, `abilityForMutation`, `receiverMutationType(+Name)`, `expiresWithCreatorDeath`, `movementAilment*`.

На уровне файла: `shrineBuffs` (6) и `integrity`.

Порядок урона: `damageTypeOrder = [Physical, Fire, Cold, Lightning, Necrotic, Void, Poison]`.

Ответы на вопросы 06d §7:

| Ailment | Ответ |
|---|---|
| Blind (14) | buffs: CriticalChance MORE −1 → крит невозможен (06d п. 6) |
| VoidResShred (30) | NegativeVoidResistance +0.05, Grouped, boss −0.6 |
| Frenzy (34) | AttackSpeed INC +0.2, CastSpeed INC +0.2 |
| ExposedFlesh (137) | ColdResistance −0.15, IncreasedChanceToBeFrozen +0.3; addedDamageScaling 4; mutationType AbilityMutator |
| PhysicalResShred | id **73** |
| addedDamageScaling | Ignite, Bleed, Poison: 0; shred-ы: 1; Laceration 3; AbyssalDecay 5; Decrepify 10; Torment 6; SpiritPlague 4.5 |
| baseDamage.penetration | у всех 149 пустой список; пробитие задаётся через `additionalPenetrationDamageType` |

---

## 6. affixes.json (A, X)

`data[1156]`, ключ `affixId` (общий для single и multi, коллизий нет):
```
{affixId, kind(single|multi), name, displayName, title, type(PREFIX|SUFFIX|SPECIAL),
 rollsOn(Equipment|Idols), specialAffixType(Standard|Experimental|Personal|Set|IdolEnchantment|IdolWeaver|Corrupted|FakeUniqueMod),
 isIdolAffix, isExperimental, isPersonal, isSetAffix, isCorrupted, classSpecificity[классы],
 levelRequirement, group, weighting, standardAffixEffectModifier, canRollOn[EquipmentType], canRollOnNames,
 specificRerollChances[], convertOnIncompatibleItemType, affixIDToConvertTo, t6Compatibility,
 maximumAffixEffectModifierForT6, displayCategory, uniqueId, weaponEffect,
 properties[{property, propertyName, specialTag, tags, tagNames, extraTag, modType, rounding, setProperty, displayName?}],
 tiers[{tier 1..N, rolls[[min,max] по каждому properties[j]]}]}
```

Состав:
- single: 470 prefix и 146 suffix; multi: 414 prefix и 126 suffix;
- по типу: Standard 770, Corrupted 134, IdolWeaver 66, Set 61, IdolEnchantment 49, FakeUniqueMod 38, Personal 26, Experimental 12;
- аффиксов идолов 472;
- тиров: 8 у 684 аффиксов, 1 у 423, 7 у 49.

**Sealed** — это состояние аффикса на предмете (ItemData), а не свойство аффикса. В данных такого флага нет.

**Модель значения (D):**
```
m  = (itemAEM == std) ? 0 : (1+itemAEM)/(1+std) − 1          // Affix.getModifier @0x1811B13C0
itemAEM = items.json baseTypes[].affixEffectModifier (для OmenIdol-подтипов — ItemList.omenIdolAffixEffectModifier)
lo = min·(1+m);  hi = max·(1+m);  s = scale(rounding)
a = RoundHalfEven(lo·s); b = RoundHalfEven(hi·s)
v = min(floor((b−a+1)·roll/255 + a), b) / s                    // roll — байт 0..255
```

Значения `standardAffixEffectModifier`: 0 (821 шт.), 0.5 (82, броня), 0.75 (59, 1H), 0.17 (48), −0.83/−0.62/−0.33/−0.05 (идолы), 2.2 (14, 2H).

Тест-векторы (Python `round` = half-even; в игре float32):

| Аффикс, тир, база | m | roll | → |
|---|---|---|---|
| Added Health (25) T5 [61, 90], шлем | 0 | 0 / 128 / 255 | 61 / 76 / 90 |
| то же, нагрудник (AEM 0.5) | 0.5 | 0 / 255 | 92 / 135 |
| Fire Resistance (13) T7 [0.61, 0.75], шлем | 0 | 200 | 0.72 |
| Increased Health (52) T6 [0.15, 0.20], нагрудник | 0.5 | 100 | 0.25 |
| Added Melee Phys (63) T8 [85, 100], std 0.75, 2H-топор (2.2) | 0.8286 | 255 | 183 |
| то же, 1H-топор (0.75) | 0 | 0 | 85 |

Привязка к стат-модели: `properties[j]` + `tiers[t].rolls[j]` → `Mod{stat: property, sub: specialTag, tags, abilityId: extraTag, type: modType, value: v}`. Для SP58 и SP98 tags — это индекс (§1.1).

---

## 7. items.json, uniques.json, sets.json

### 7.1 items.json (A, X)

`data[41]` — EquippableItems без Blessing (34), по `baseTypeID`:
```
{baseTypeID, name, displayName, type, typeName, isWeapon, isIdol, maximumAffixes, maxSockets,
 affixEffectModifier, gridSize[w,h], classAffinity[], subTypeClassSpecificity, minimumDropLevel, obsoleteItemType,
 subItems[{subTypeID, name, displayName, levelRequirement, classRequirement[], subClassRequirement, cannotDrop,
           isCorruptedSubtype, isLegacySubType, obsoleteItem, affixEffectiveness(Default|OmenIdol),
           implicits[{property…, modType, rounding, value, maxValue}], attackRate?, addedWeaponRange?}]}
```

Всего 699 подтипов. Дополнительно: `nonEquippable` (9 баз, только счётчики), `equipmentTypeEnum`, `globals` (ice/blood forging, globalIdolRerollChance 0.1, omenIdolAffixEffectModifier 0), `disabledBaseTypesToRoll` [24 Crossbow, 11 1H Fist].

`attackRate` есть у оружия, например Hatchet 1.05, Poignard 1.14, Gladius 1.12. Это множитель `CharacterStats.getPropertyMultiplier` для AttackSpeed (06a §3). Импликиты ролятся в `[value, maxValue]` так же, как уники.

AEM баз: броня тела 0.5; 1H-оружие и луки 0.75; 2H 2.2; щит, катализатор и амулет 0.17; идолы от −0.83 до 0.

### 7.2 uniques.json (A, X)

`data[489]`, ключ `uniqueID`:
```
{uniqueID, name, displayName, baseType, baseTypeName, subTypes[], levelRequirement(если override), isSetItem, setID,
 isPrimordialItem, isCocoonedItem, unifiedType, legendaryType(LegendaryPotential|WeaversWill), canDropAsLegendary,
 canDropRandomly, hideFromPlayers, overrideEffectiveLevelForLegendaryPotential, effectiveLevelForLegendaryPotential,
 dropsSpecificLegendaryAffixes, droppableLegendaryAffixCount, droppableLegendaryAffixes[affixId],
 excludeSpecificAffixesFromPrefixSuffixLimits, convertPotentialToLegendaryAffixes, additionalRandomLegendaryAffixes,
 isPreCorrupted, preCorruptPositiveChance, validPreCorrupts[], primordialCosts{},
 mods[{property…, modType, rounding, rollID, canRoll, value, maxValue, hideInTooltip}],
 tooltipDescriptions[{description, altText, setRequirement}], loreText}
```

Состав: 61 сетовый предмет; 471 с LegendaryPotential и 18 с WeaversWill.

Значение мода (D, `UniqueItemMod.getValue` @0x18126B510): если `canRoll && maxValue > value && roll ≠ 0`, то `GetValueAfterRounding(prop, tags, special, type, value, maxValue, roll)` — та же сетка, что у аффиксов, без AEM; иначе `GetFixedValueAfterRounding(value)`. `rollID` выбирает байт ролла предмета. Несколько модов с одним rollID ролятся синхронно. Текстовые описания (`tooltipDescriptions`) механику не кодируют. Их эффекты, кроме статов, в `unique_effects.json` (это работа другого агента).

### 7.3 sets.json (A, X)

`data[24]`: `{setID, setName, bonuses[{property…, modType, rounding, value, setRequirement, hideInTooltip}], tooltipDescriptions[], items[{uniqueID, name}]}`. `setRequirement` — сколько предметов сета нужно.

---

## 8. idols.json, blessings.json

### 8.1 idols.json (A)

- `data[10]`: базы идолов 25–33 и алтарь 41 в схеме items.json. Размеры: Small 1×1 (−0.83), Small Lagonian 1×1, Humble 2×1 и Stout 1×2 (−0.62), Grand 3×1 и Large 1×3 (−0.33), Ornate 4×1 и Huge 1×4 (0), Adorned 2×2 (−0.05). У идолов `maximumAffixes = 2`, у алтаря 4 (13 подтипов).
- `containerGrids`: `IdolsContainerGridDataList` сериализован Odin (`SerializedBytes`). Его разбирает `odin_decode()`. `defaultData` и `data[13]` (по подтипу алтаря) — матрицы 5×5 `unlockMatrix`:
  - 99 — заблокированная клетка;
  - 1–8 — номер награды открытия слота;
  - +100 — refracted-слот.

  Порядок индексов (D): `int[,] unlockMatrix` индексируется `[x, y]`. `IdolsContainerGridData.get_BlockedCellsPositions` проходит `[i, j]`
  и для 99 добавляет кортеж `(x: i, y: j)`. Поэтому внутренний список JSON — это столбец, и клетка на экране (строка y, столбец x) = `m[x][y]`.
  Клиент транспонирует матрицы при загрузке (`GameData._grid_rows`). Проверено на алтаре подтипа 4 по скриншоту из игры (билд LE Tools ApbrXYvx).

  Пример по умолчанию: `[[99,7,6,5,99],[8,4,3,2,1],[8,4,99,1,1],[8,4,3,2,1],[99,7,6,5,99]]`.
- `idolAffixIds` — 472 id аффиксов идолов (сами аффиксы в affixes.json).

### 8.2 blessings.json (A, X)

`data[224]` (подтипы базы 34; 112 обычных и 112 Grand):
```
{blessingId, name, displayName, levelRequirement, cannotDrop, implicits[{property…, modType, rounding, value, maxValue}],
 isGrand, grandVariantId | normalVariantId,
 timelines[{timelineID, timeline, difficultyIndex(0 normal / 1 empowered), slot(first|other|any)}]}
```

Плюс `timelines[]`: `{timelineID, displayName, pairs[{name, normal, grand}], difficulties[{level, firstSlotBlessings[], otherSlotBlessings[], anySlotBlessings[]}]}`. Пример: Cruelty of Formosus (14) даёт IncreasedDropRate 0.30–0.45 на WAND (`specialTag 0`, `tags 10` = EquipmentType). Grand-вариант (127) даёт 0.50–0.90 и предлагается только в empowered.

---

## 9. Сверка с внешними данными

Скрипт: `tools/extract/crosscheck_maxroll.py`. Сравнивались **все** записи, так что выборка ≥ 10 соблюдена с запасом.

| Сущность | Сравнено | Расхождений в значениях | Различия в полноте |
|---|---|---|---|
| Классы (все поля base и minion) | 110 | 0 | — |
| Аффиксы (имя, levelReq, canRollOn, тиры и extraRolls, property/tags/modType) | 1156 | 0 | — |
| Базы и подтипы (AEM, maxAffixes, импликиты, levelReq, attackRate) | 781 | 0 | — |
| Уники (все моды с rollID, уровень LP) | 486 | 0 | у нас ещё 3: Sharktooth Saw (46) и Heirloom of Light (69) с `hideFromPlayers`, FleshofStone (248) |
| Сеты | 24 | 0 | — |
| Ailments (duration, maxInstances, damage, addedDamageScaling, buffs…) | 128 | 0 | у Maxroll нет id 129–150 (Aterroth*, Silk, Spiders, **ExposedFlesh**, **Hemorrhage**, Bulwark, Disemboweled и др.) — их выгрузка неполная |
| Округление свойств и имена PlayerProperty | 825 | 0 | у нас 713 PlayerProperty, у Maxroll 712; последний — «Monstrous Rage minion explosion on death» |
| Списки благословений по таймлайнам | 63 | 0 | — |
| Атрибуты (LETools coreDB) | 10 | 0 | — |
| StatsMonsterMod (LETools endgame, сопоставление по имени в loc-ключе) | 234 из 239 | 0 | — |

Вывод: Maxroll и LETools получены из той же сериализации. Наш экстрактор воспроизводит её точно и при этом полнее (новые ailments, скрытые уники). Числа, которые независимо от нас вывел только Tunklab (редкость, порча), сходятся с ассетами: magic ×2.15 здоровья; f(c) — 06c.

---

## 10. Не удалось установить

1. **Ward боссов.** `bossWardGainModifier`, `bossWardPercentDecay*`, `baseBossWardDecayEffectiveTimeDivisor*` прочитаны, формула не разобрана. Искать в `ProtectionClass.Update` / `GlobalPlayerProperties.GetWardDecayRate` ветку для боссов.
2. **Компонент `MonsterRarity` на префабах против `MonsterRarityManager`.** В коде два пути: `setActorRarity` (данные менеджера, подтверждено ISIL) и `MonsterRarity.makeMonsterMemberOfRarity` (поля компонента `baseHealthMultiplier` и др., 06e §5.1). Префабы монстров не экспортировались, поэтому неясно, какой путь активен для обычного спавна и какие числа в компоненте. Нужен xref `setActorRarity` ← `Spawner`/`MonsterGenerator` и, при необходимости, префабы через UnityPy.
3. **`statsWithoutEffectModifier`** (int у монстр-модов): битовая маска индексов статов или счётчик — не проверено. Везде, кроме Partial-модов, значение 0.
4. **Семантика SP104/105** (`specialTag` 1–4). При `specialTag = 0` `tags` = EquipmentType (проверено на Cruelty of Formosus = WAND, Pride of Rebellion = Grand Idol). Для 1–4 (не-экипировка, шарды, …) нужен разбор `ItemDrop`/`DropRateType`.
5. **Аргумент `setProperty`** (`SingleAffix+0xC8`) передаётся в `GetValueAfterRounding_2` и, вероятно, меняет квантование «set»-аффиксов. Не разобрано, затрагивает 61 Set-аффикс.
6. **Устойчивость поиска ActorScaler.** Таблицы найдены по значениям-сигнатурам, а не через разбор `fieldDefaultValues` метаданных. Если патч изменит опорные значения, скрипт вернёт `null`. Тогда нужен парсер `Il2CppFieldDefaultValue` (handles `DAT_185347330`, `DAT_185347ee8`, `DAT_185351338`, `DAT_185351b08` в `ActorScaler..cctor`).
7. **PlayerProperty 636–638** (эффекты испорченных атрибутов) — это идентификаторы из списка. Как они работают (например, «per 1 Mana Cost up to 20»), решает код CharacterMutator; см. `player_property_fields.json` и `pp_switch.py` другого агента.
8. **Float32.** Тест-векторы посчитаны в double. Игра считает `min·(1+m)·s` во float32, и на границах .5 результат RoundHalfEven может отличаться. Движку нужен `Math.fround`.
