# 07d — Передача статов миньонам и спецэффекты уникальных/сетовых предметов (дамп LE 1.5.0)

Метки: **D** — прочитано из декомпилированного кода; **D?** — прочитано, но интерпретация неоднозначна.
Источники: `dump/decomp/LE.dll/*.c` (Ghidra), `dump/isil/IsilDump/LE/*.txt` (ISIL, где Ghidra не справилась), `dump/cs/DiffableCs/LE/*.cs` (офсеты), ассеты `Resources/UniqueList.asset`, `SetBonusesList.asset`, `PlayerPropertyList.asset`, `AbilityPropertyList.asset`.

Новые файлы:
- `tools/extract/pp_switch.py` → `research/data/game/player_property_fields.json` (PlayerProperty → поле CharacterMutator, по таблице переходов в бинарнике);
- `tools/extract/pp_usage.py` → дополняет тот же файл списком методов-триггеров;
- `tools/extract/extract_unique_effects.py` (+ `tools/extract/unique_component_mechanics.json`, ручная выжимка из классов-компонентов) → `research/data/game/unique_effects.json`.

---

## Часть 1. Миньоны

### 1.1 Главный вывод — снимок статов игрока в момент призыва (**D**)

Общий путь передачи, который не нашёл 06e, находится в компоненте объекта способности **`SummonEntityOnDeath`** (наследник `RequiresTaggedStats`), а не в `Summoned`/`CharacterMutator`.

Цепочка (игрок кастует призыв):
1. `AbilityObjectConstructor.constructAbilityObject` @0x18241ce20:
   - pre-mutation temp stats (`CharacterMutator.ApplyPreMutationTemporaryStats`) и обычные temp stats способности (виртуальный `applyTemporaryStats` @0x18241c320, vtable +0x2A8: `levelScaling × уровень персонажа`, `attributeScaling × атрибут`, статы предметов с `extraTag = ID способности`, статы мутатора/дерева) **добавляются в `Stats.stats` кастера** (`AddRange`, строки ~3644/3724);
   - для каждого `RequiresTaggedStats` на объекте создаётся/берётся компонент `Stats` объекта способности, в его список копируется **весь** список статов кастера (`AddRange(caster.stats.stats)`, строка ~4302), затем вызывается `SetStats(thatStats)`;
   - temp stats снимаются с кастера (строки ~4370–4420).
2. `SummonEntityOnDeath.Summon` @0x181143130 (вызывается при «смерти» объекта способности или на Start при `createOnStartInstead`) спавнит `ActorData` и для **каждого** стата `s` из полученного списка выполняет (ISIL `SummonEntityOnDeath.txt` строки 2436–2600, псевдо-C строки ~2780–2915):

```
idx = AbilityIDIndex(creationReferences.GetPrimaryAbility())   // ID способности-призыва
isTotem = ability.isTotem() || countsAsTotemEvenIfAbilityIsNotTotemAbility
if HandledBySummonerEvenIfMinionTaggedOrAbilitySpecific(s.property): skip      // SP 38,39,40,50,126,127
elif s.extraTag != 0 and s.extraTag != idx:
        minion.addStat(s)                       // без изменений (vtable-слот 0x24)            D?
elif (s.tags & Minion) or (isTotem and s.tags & Totem) or (s.extraTag == idx and idx != 0):
        if summonIsASummoner:                   // поле +0x1B8 «For Minions That Summon»
            minion.AddStatModifier(s.property, s.added,   ADDED,     s.tags | Minion, s.specialTag, extraTag 0)
            minion.AddStatModifier(s.property, s.inc,     INCREASED, s.tags | Minion, ...)
            for m in s.moreValues: minion.AddStatModifier(s.property, m, MORE, s.tags | Minion, ...)
        minion.AddStatModifier(s.property, s.added, ADDED,     s.tags & ~(Minion|Totem), s.specialTag, extraTag 0)
        minion.AddStatModifier(s.property, s.inc,   INCREASED, s.tags & ~(Minion|Totem), ...)
        for m in s.moreValues: minion.AddStatModifier(s.property, m, MORE, s.tags & ~(Minion|Totem), ...)
else: skip                                      // обычные статы без тега Minion НЕ передаются
```
(`minion` = `actor.stats` (+0x50) заспавненного актёра; `AddStatModifier` = интерфейсный вызов `FUN_180186360(0x1c, …)` с аргументами `(SP, value, ModType, AT, specialTag, extraTag)`.)

`EpochExtensions.HandledBySummonerEvenIfMinionTaggedOrAbilitySpecific(SP)` @0x1810e0220 возвращает true для **SP 38 HealthGain, 39 WardGain, 40 ManaGain, 50 HasteOnHitChance, 126 ChanceToCastForAbility, 127 ChanceToCastForTags**. Такие статы с тегом Minion обрабатывает сам призыватель (например, «здоровье при попадании миньона»).

После цикла:
- Добавляются статы **самого компонента** `SummonEntityOnDeath.statList` (+0x148) — **без изменения тегов** (`addStat`). Сюда мутатор призыва (`XxxMutator.Mutate`) кладёт статы из дерева скилла: например `SummonWolfMutator.Mutate` @0x18233a6b0 делает `AddRange(mutator.statList +0x140)` и добавляет `AddedStat(CritChance(4), tags 0, v)`, `AddedStat(SP 56 StunImmunity, 1)` и т. п. Затем `BaseStats.UpdateStats()`, здоровье ставится в максимум (или `maxHealth × healthPercent` создателя при `inheritHealthRatio`).
- Компаньоны (`ability.companion` и есть создатель): PlayerProperty **132 «Increased Companion Size»** (`tags == 0x84`) суммируется и вместе с `increasedMinionSize` (+0x150) через `Maths.combineModifiers` масштабирует `localScale`. Чисто визуально.
- `Summoned.attributeScalingWhenSummoned` ← `CreationReferences.attributeScalingOnCast`. Используется только в `Summoned.OnItemChange` (миньоны с предметами, 06e §4.3).

**Снимок, а не живая связь.** У `Stats` миньона нет ссылки на `Stats` игрока. `AbilityObjectConstructor.initialise` @0x1824217D0 берёт `Stats` самого актёра. В `Summoned.OnUpdateTick`/`initialise` пересчёта от игрока нет. Статический список `Summoned.excludedPlayerPropertiesForSnapShotProtection` создаётся пустым в `.cctor` @0x1812814D0 и больше нигде не используется. Миньон получает актуальные статы игрока только при **перепризыве**:
- дерево скилла: `*Tree.resummonMinions/resummonCompanions`;
- смена сцены: `SummonPersistenceManager.OnPreSceneLoad` → `ResummonCertainMinions` @0x1812747B0 вызывает те же `resummon*` у деревьев Wolf/Bear/Raptor/Sabertooth/Scorpion/Spriggan/Primalist Elemental/Manifest Armor;
- новый каст.

**D** для правила. **D?** — только для ветки «чужой extraTag → addStat без изменений»: аргументы видны в ISIL, но назначение неочевидно; вероятно, это статы под собственные способности миньона.

### 1.2 Что из статов игрока доходит до миньона (следствия, **D**)

| Стат игрока | Что получает миньон |
|---|---|
| `+X% damage` (tags 0), `+X% fire damage` (Fire) | **ничего** |
| `+X% minion damage` (Minion) | `Damage INCREASED X`, tags 0 |
| `+X minion melee physical damage` (Physical\|Melee\|Minion) | `Damage ADDED X`, tags Physical\|Melee → только к melee-физ. способностям миньона |
| `+X% minion health / armour / resist` (Minion) | Health/Armour/Res без тега → идут в `ApplyExternalStats` миньона (06a §4.1) |
| статы с `extraTag = ID способности-призыва` (например «+X% урона Summon Skeleton» с предмета) | переносятся с `extraTag 0` и без тега Minion |
| `levelScaling`/`attributeScaling` способности-призыва (ассет `Ability`) | считаются **на игроке** (уровень персонажа, атрибуты игрока) и переносятся, если стат с тегом Minion (или с extraTag способности) |
| узлы дерева призыва | (а) temp stats мутатора с тегом Minion → по правилу выше; (б) `SummonEntityOnDeath.statList` → как есть, обычно без тегов |
| totem-статы (tag Totem) | только если способность — тотем (`Ability.isTotem` или флаг `countsAsTotem…`) |
| HealthGain/WardGain/ManaGain/Haste on hit/ChanceToCast с тегом Minion | не переносятся (обрабатывает игрок) |
| скрытая база игрока (`CharacterStats.SetInitialValues`, 06a §5.3): Movespeed MORE 0.10 Minion; DamageTaken MORE −0.6 Minion\|PetResisted; Damage MORE n·k Minion и DamageTaken MORE −n·k Minion от уровня | у миньона: Movespeed MORE +10%; DamageTaken MORE −0.6 с тегом **PetResisted** (тег не снимается, маска снимает только 0x6000); Damage MORE и DamageTaken MORE от уровня — без тега |

Почему тег снимается: у способностей миньонов в ассетах **нет** тега Minion (например, `Skeleton Rogue Melee`, `PrimalWolf 01 melee`: `tags 513` = Physical\|Melee; `Summon Skeleton Archer Bow Attack`: `2049` = Physical\|Bow). Тег Minion стоит на способности-призыве игрока (`SummonSKeletonWarrior.asset`: `tags 8192`). `DamageStats.buildDamageStats` @0x18108C090 требует тег Minion у стата, только если он есть у самого урона (`required = damageTags & 0x2000`, через `Tags.Applicable(own, stat, required)` @0x1816A4EF0). Для способностей миньона required = 0, и снятые теги совпадают обычным правилом подмножества.

### 1.3 Уровень и база миньона (**D**)
- `ActorData.spawn` @0x18277BD10 не принимает уровень. Уровень актёра берётся из `ActorData.level` в ассете (у `BloodGolem` = 34), но для игровых миньонов **не масштабируется**: `ActorScaler.scaleToLevel/scaleToZoneLevel` из `SummonEntityOnDeath` не вызываются.
- **`levelScaling` собственных способностей миньона не применяется.** В `applyTemporaryStats` уровень берётся из `CharacterDataTracker` (+0xE0 → +0x20 → +0x88). Если трекера на кастере нет (а у миньонов его нет), блок пропускается целиком. `attributeScaling` способностей миньона использует атрибуты самого миньона (обычно 0, кроме миньонов с предметами).
- Базовые здоровье/броня/резисты миньона — из его префаба (`UnitHealth`, `ActorStats`/`ProtectionClass` в бандле актёра), не из PermaLoad. Итог: `maxHealth = RoundHalfEven((base + ΣA)·(1 + ΣI)·ΠM)` по 06a §4.1, где A/I/M уже содержат перенесённые статы.
- Базовые крит 5%/×2 (`Stats.baseCritChance/baseCritMulti`) — общие для всех `Stats`.

### 1.4 Компаньоны (**D**)
- `CharacterStats.getMaximumCompanions` @0x181698270 = `Round(GetStatValue(SP61 MaximumCompanions, added = 2.0))`, то есть база **2** + added, × (1+inc) × more. Если в `CharacterMutator` (+0x130) выставлен флаг +0xB5C, лимит = **1**.
- `Stats.maxContributionToCompanionLimit` @0x1816A4CD0 = `maxCompanions × 60`. Вклад компаньона по умолчанию `Summoned.defaultContributionToCompanionLimit = 60`, мутаторы могут его менять (`SummonWolfMutator.getContributionModifier`, `setContributionToCompanionLimit`).
- Отдельных множителей силы у компаньонов нет. Отличия: размер (PP 132) и лимит.

### 1.5 Тест-векторы (передача)
Призыв `idx = 50` (не тотем), `summonIsASummoner = false`.
1. Игрок: `Damage INC 0.4 tags 0`, `Damage INC 0.5 Minion`, `Damage INC 0.3 Minion|Melee`, `Health ADD 20 Minion`.
   → Миньон: `Damage INC 0.5 (0)`, `Damage INC 0.3 (Melee)`, `Health ADD 20 (0)`.
   Melee-атака миньона (Physical\|Melee): ΣI = 0.8. Спелл миньона: ΣI = 0.5. Здоровье `(base+20)·…`.
2. Игрок L100 (`first = 26`, `k = 0.008`): `Damage MORE 0.6 Minion`, `DamageTaken MORE −0.6 Minion`, `DamageTaken MORE −0.6 Minion|PetResisted`.
   → Миньон: урон ×1.6; входящий урон ×0.4, урон с тегом PetResisted ×0.4·0.4 = ×0.16.
3. `Damage INC 0.25 Totem`: у тотема (isTotem) → `Damage INC 0.25 (0)`; у не-тотемного миньона → ничего.
4. `Damage INC 0.2 extraTag=50 tags 0` → миньону `Damage INC 0.2 (0)`. `extraTag = 77` (другая способность) → миньону как есть, `extraTag 77` (**D?**).
5. `HealthGain ADD 5 Minion` (SP 38) → не переносится.
6. `summonIsASummoner = true`, стат `Damage INC 0.5 Minion` → миньону две записи: `INC 0.5 (Minion)` (для его призывов) и `INC 0.5 (0)`.

### 1.6 Не удалось установить (миньоны)
- Точная семантика интерфейсных слотов `0x1C` (AddStatModifier или ChangeStatModifier) и `0x24` (addStat) у `Stats` миньона: имена восстановлены по аргументам, а не по символам.
- Базовые значения миньонов (health, armour, резисты, базовый урон их способностей) лежат в префабах актёров в отдельных бандлах. Нужен экстрактор UnityPy по `ActorData.ActorSoftRef`.
- Пересобирает ли смена экипировки снимок у уже живых миньонов. Найдены только перепризыв по дереву скилла, при смене сцены и при новом касте. Константа `AbilityManager.falconAgeToSetAfterGearChange = 115` намекает на отдельную логику для сокола.
- Конкретные статы, которые каждый `*SkillTree.updateMutator` кладёт в `statList` мутатора призыва. Это задача на ~25 деревьев призыва, по образцу `SummonWolfMutator.Mutate`.

---

## Часть 2. Спецэффекты уникальных и сетовых предметов

### 2.1 Как устроены «особые» свойства уникальных предметов (**D**)

Уникальный предмет = список `UniqueItemMod` в `UniqueList.uniques[i].mods` + необязательный класс-компонент. «Спецэффекты» (то, что в тултипе описано текстом) реализованы четырьмя способами:

| Способ | Модов (489 уник.) | Где логика |
|---|---|---|
| **PlayerProperty** (SP 98, `tags` = индекс в `PlayerPropertyList`; 371 разный индекс) | 399 | `CharacterMutator`: поле, заполняемое в `applyModifiersBeforeExternalStatsCalculation` @0x182601FE0; его читают обработчики событий |
| **AbilityProperty** (SP 58, `tags` = индекс способности в `Ability Manager.abilities`, `specialTag` = индекс (0-based) в `AbilityPropertyList[ability].properties`) | 385 | мутатор конкретной способности (`Stats.GetAbilityStat(abilityID, idx)`) |
| Условные/особые SP: 117/131/132/133 GlobalConditional*, 115 DamagePerStackOfAilment, 100 AilmentConversion, 130 IdolAltarProperty | ~35 | общий движок урона (06a §6.4) |
| **Класс-компонент** `UniqueItemComponent` (42 шт.; 14 из них пустые маркеры) и `SetItemComponent<T>` (6 сетовых предметов, все без логики) | — | собственный код класса (§2.4) |

Остальные моды — обычные статы (06a), с роллами.

**Значение мода** (`ItemEquipManager.UpdateStats` @0x181436460 → `UniqueItemMod.getValue(byte roll)` @0x18126B510):
```
roll = item.getUniqueRoll(mod.rollID)                 // байт 0..255
if !canRoll || maxValue <= value || roll == 0:  v = GetFixedValueAfterRounding(prop, tags, special, type, value)
else:                                            v = GetValueAfterRounding(prop, tags, special, type, value, maxValue, roll)
v *= 1 + equipEffectModifier                         // параметр UpdateStats, по умолчанию 0          (D?)
ModType: 0 ADDED, 1 INCREASED, 2 MORE (QUOTIENT = снять more)
```
- Квантование такое же, как у аффиксов (06a §7.1): `a = RHE(lo·s)`, `b = RHE(hi·s)`, `v = min(floor((b−a+1)·roll/255 + a), b)/s`. Шаг s — из `PropertyRounding` свойства; для SP 98/58 — из записи PlayerPropertyList/AbilityPropertyList.
- При `maxValue < value` (например, у Snowblind `AilmentChance 0.4/0.2`) мод **не роллится** и всегда даёт `value`. В JSON это поля `rolls`/`rollMax`.
- Несколько модов могут делить один rollID: у Snowblind это PP 454 и PP 455.

**Привязка компонента:**
- `GetComponent(uniqueName.Replace(" ", "_"))` на шаблонном объекте → `AddComponent` этого типа игроку → `EquipUnique()` (vtable +0x268).
- При снятии предмета вызывается `RemoveUnique()` (+0x278).
- Для легендарных и сетовых предметов дополнительно вызывается `CharacterMutator.UniqueSetOrLegendaryEquipped` @0x18266D9A0.
- **D**

### 2.2 PlayerProperty → поле CharacterMutator (**D**, автоматически)
В `applyModifiersBeforeExternalStatsCalculation` (Ghidra упала по таймауту, логика прочитана по ISIL):
```
foreach s in stats.stats:
    if s.property == 98 and (uint)s.tags <= 999:  goto jumptable[s.tags]   // таблица @0x182616398, 1000 int32 RVA
```
`pp_switch.py` читает таблицу из GameAssembly.dll и распознаёт тело каждого case по байтам. Всего 692 case:

| op | Кол-во | Смысл |
|---|---|---|
| `add` | 534 | `field += s.added` (все источники суммируются) |
| `flag=(added>eps)` / `flag\|=(added>eps)` | 45 / 33 | bool-поле включается, если added > ε (иммунитеты, «You have Haste» и т. п.) |
| `more-combine` | 42 | `field = (1+field)·Π(1+mᵢ) − 1`, через `Stat.ApplyMoreModifier` @0x18169DB90 или инлайн `getMoreMultiplier`. Это все «X% less/more damage taken from …» |
| `assign` | 2 | `field = s.added` |
| `complex` / `unknown` / `local` | 32 / 3 / 1 | нестандартные тела. Поле угадано по первому `[rdi+disp]` (**D?**); в нескольких случаях имя поля явно не совпадает с именем свойства |

Затем `pp_usage.py` находит методы, обращающиеся к этому полю:
- где ищет: `CharacterMutator`, а для офсетов ≥ 0x1000 и другие классы;
- в чём ищет: в псевдо-C, а если там не нашлось — в ISIL.

Имя метода и есть триггер. Примеры:
- `ApplyConditionalDefenses` — входящий урон;
- `ApplyConditionalTemporaryStats` — статы на каст;
- `OnHit`, `OnKill`, `HitDamageTaken`, `OnUpdateTick`, `onPotionUse`, `IsImmuneToAilment` и т. д.

Покрытие для 399 PlayerProperty-модов уникальных предметов:
- триггер найден у 356;
- у 43 обращение к полю текстом не найдено;
- 8 свойств вне этого switch (126, 127, 190, 507, 528, 551, 630, 665 — зелья и компаньоны).

Пример цепочки: Snowblind, PP 454 «Armor against Chilled Enemies», MORE 0.16–0.24, rollID 2.
- Switch: `moreArmourAgainstChilledAttackers = (1+f)(1+m) − 1`.
- Читает поле `ApplyConditionalDefenses`.

Пример чтения: PP 250 «Damage Taken from Chilled Enemies». В `ApplyConditionalDefenses` @0x18261D5C0 `mult *= (1 + moreDamageTakenFromChilledEnemies)`, если у атакующего есть Chill (AilmentID 3). **D**

### 2.3 Сетовые бонусы (**D**, `ItemEquipManager.UpdateStats`, строки ~4190–4470)
```
count[setID] = число РАЗНЫХ uniqueID предметов этого сета в экипировке (RecyclingListList.addUnique)
             + число надетых uniqueID 423 «Legends Entwined» («Counts as a part of every equipped item set»)
для каждого mod сета: если mod.setRequirement <= count → Stat(property, specialTag, tags, extraTag, value по type) в статы игрока
```
- Учитываются и «сет-ифицированные» уникальные предметы (`ItemData.grantsSetBonus` / `getSetItemUniqueId`).
- Значения сетовых модов фиксированные, роллов нет.
- `SetItemComponent<T>` только добавляет `IsadoraSetBuffs`/`ElementalistSetBuffs`; колбэки `OnSetItemEquipped/Unequipped` пустые. Логика «N предметов» живёт только в `SetBonusesList`.

Тест: Isadora (setID 1) — `+100% Damned chance` (req 2), `+30% mana efficiency` (req 3), `+30% Damned effect` (req 3).
- 2 разных предмета → активен 1 мод.
- 2 предмета + Legends Entwined → count = 3 → активны все три.
- Два одинаковых предмета → count = 1.

### 2.4 Классы-компоненты (полные детали и адреса — в `unique_effects.json` → `effects[source = Component:*]`)
Ни один компонент не читает роллы уникального предмета или PlayerProperty: все константы зашиты в код. Роллящиеся строки тултипа — это обычные моды.

| Класс | Триггер | Механика (константы) |
|---|---|---|
| Calamity | kill огненным скиллом; тик 0.5 с | каждые 0.5 с урон огнём себе `1.0 × (число огненных убийств за последние 2 с)` через ApplyDamage (≈4 за убийство) |
| Frozen_Ire | смена уровня; on hit | за уровень персонажа +0.2 added Cold dmg (только тег Cold, не Spell), +0.02 FreezeRateMultiplier, +0.01 NecroticRes; Tundra Nova с шансом 0.15, против нежити второй ролл 0.176471 → 0.30 |
| Mourningfrost | пересчёт статов | за единицу Dex: +1 added Cold (Melee/Spell/Throwing/Bow), −1% Physical res и др. |
| Hammer_Of_Lorent | смена уровня | +1 added Physical\|Melee dmg и +0.01 increased Melee stun chance за уровень |
| Strong_Mind | пересчёт статов; Stunned.enter | StunAvoidance += 2 × maxMana; при оглушении каст Lightning Explosion (ID 67) |
| Urzils_Pride | пересчёт статов | ManaRegen INCREASED += 0.5 × min(uncapped LightningRes, 40). Кап 40 не действует: резист хранится долей |
| Preparation | поздний тик | HP ≥ 65%: +30 added Cold\|Melee dmg; иначе +0.3 HealthLeech (Melee) |
| Undisputed | on hit | +0.08 inc Physical на 4 с; именованные стаки 0..50 → до 51 стака (4.08) |
| Taste_of_Blood | on hit | у всех текущих Bleed на цели speed = (speed+1)·2 − 1, без капа |
| Close_Call | block | безымянный бафф +0.4 inc Dodge на 4 с; каждый блок — отдельный стак, без капа |
| Ignivar_Head | тик (ченнелинг); equip | Fire Aura (ID 162) раз в 1 с при ченнелинге; Disintegrate MORE dmg = spell crit chance (+0.05 база), без капа |
| IsadoraGravechill | kill | бафф +1.0 Chill chance (Necrotic) на **4 с** (в тултипе 5), с обновлением |
| Death_Rattle | смерть миньона | +30 HP плоско, healing effectiveness не учитывается |
| Bleeding_Heart | каст спелла | 1 стак Bleed на себя (D?) |
| Stormtide | смена состояния (остановка) | Shock на себя, ICD 0.5 с (D?) |
| The_Scavenger | зелье | Haste 3 с |
| Beast_King | kill миньона / kill игрока | игроку DamageTaken MORE −0.08 на 4 с; миньонам −0.25 на 4 с (обновляется, не стакается) |
| Soulfire | kill; опрос 0.5 с | +0.6 inc Fire на 4 с; при Ignite на себе +1.0 inc Armour |
| Soul_Bastion | kill | заряды по 10 с; при 5 зарядах каст Soul Eruption и сброс |
| Culnivars_Claim | тик | при полной мане: мана → 0, Ward += maxMana |
| Rahyehs_Light | тик | Flame Ward с остатком < 1 с при ward > 80: длительность сбрасывается, −80 ward |
| Keepers_Gloves / Arboreal_Circuit | melee hit / when hit | шанс 0.1 (поле summonChance не используется), ICD 8 с / 15 с |
| Volcanus / Bone_Harvester / Torch_Of_The_Pontifex | melee hit / kill / kill | каст способности с шансом 0.3 / 0.2 / 1.0 |
| Plague_Bearer_Staff | when hit | Blind атакующего с шансом 0.2 |
| Artor_Legacy | unequip | unsummonExtraCompanions |
| маркеры без кода | — | Chains_of_Uleros, Chimaeras_Essence, Cinder_Song, Eterras_Path, Eye_of_Reen, Hollow_Finger, Humming_Bee, Ring_of_the_Third_Eye, Riverbend_Grasp, The_Claw, The_Fang, The_Falcon, Valeroot, Ward_Trail, IsadoraRevenge, IsadoraTombbinding, Elementalist* — эффект целиком в модах (PP/AbilityProperty) |

### 2.5 Схема `research/data/game/unique_effects.json`
```
{gameVersion, source, schema, setCountRule,
 data: [ {uniqueName, displayName, uniqueID, isSetItem, setID, legendaryType, baseType, subTypes[], levelRequirement,
          class (UniqueItemComponent subclass | null), classKind ("code"|"marker"|null), tooltip[],
          mods: [{rollID, canRoll, rolls, value(min), maxValue, rollMax, property, propertyName, specialTag, tags, tagNames?,
                  extraTag, abilitySpecific?, ailment?, modType, hideInTooltip}],
          effects: [{source: "PlayerProperty"|"AbilityProperty"|"GlobalConditional*"|"DamagePerStackOfAilment"|
                             "AilmentConversion"|"IdolAltarProperty"|"Component:<class>",
                     trigger[], formula, constants{}?, rollIDs[], value{min,max}?, confidence,
                     // PlayerProperty: ppIndex, name, codeField, codeOp, methods[{method,address}]
                     // AbilityProperty: abilityIndex, ability, propertyIndex, name
                     // Component: condition, creates, playerProperties, notes}],
          componentMethods?: [{name,address}] } ],
 sets: [ {setID, setName, items[{uniqueName, uniqueID}], tooltip[{setRequirement, description}], mods[... + setRequirement], effects[]} ] }
```
Вспомогательный файл `player_property_fields.json`: `[{index, propertyName, caseVA, op, fieldOffset, field, fieldType, usedIn[{method, address|null, fromIsil?, outsideCharacterMutator?}]}]`.

Перезапуск после патча (адрес таблицы switch захардкожен и изменится):
```
pp_switch.py → pp_usage.py → extract_unique_effects.py
```

**Сверка с Maxroll** (`data.json`): у всех 486 общих уникальных предметов `mods` совпадают полностью (rollID, property, specialTag, tags, value, maxValue, type). У нас есть ещё 3 скрытых предмета: 46 Sharktooth Saw, 69 Heirloom of Light, 248 FleshofStone.

### 2.6 Тест-векторы (уникальные предметы)
1. Calamity, rollID 1 (`Damage INC Fire 0.2–0.8`, шаг Hundredth): roll 0 → 0.20; roll 255 → 0.80; roll 128 → `floor(61·128/255 + 20)/100` = 0.50.
2. Calamity, 3 огненных убийства за 1 с: в ближайший тик 3 урона огнём до митигации, дальше по 1 за каждое убийство, которое ещё в 2-секундном окне.
3. Frozen Ire, L80: +16 added Cold, +1.6 FreezeRateMultiplier, +0.8 Necrotic res. Tundra Nova против нежити: 0.15 + 0.85·0.176471 = 0.30.
4. Hammer of Lorent, L100: +100 added Physical\|Melee, +1.0 increased Melee stun chance.
5. Strong Mind, maxMana 600: StunAvoidance +1200.
6. Undisputed, 60 попаданий за 4 с: 51 стак → +4.08 increased Physical.
7. Taste of Blood: стак Bleed со speed 0 после 3 melee-попаданий имеет speed 7 (×8).
8. Snowblind, ролл PP 454 = 0.2 MORE: `moreArmourAgainstChilledAttackers = 0.2` (тот же rollID 2 задаёт и PP 455).

### 2.7 Не удалось установить (уникальные предметы)
- **Формулы внутри обработчиков большинства PlayerProperty.** Известны поле, агрегация и метод-триггер, но не шанс, ICD или урон прока. Ручной разбор нужен примерно для 350 полей.
  - Приоритет — поля, которые читают `ApplyConditionalDefenses`/`ApplyConditionalTemporaryStats`: они влияют на DPS и EHP.
  - Где искать: `CharacterMutator.c` по `fieldOffset` (учитывать индексацию вида `param_1[off/8]`) и ISIL `CharacterMutator.txt`.
- **AbilityProperty (385 модов):** как мутаторы способностей используют индекс свойства, не трассировалось. Есть только имя свойства и способность.
- **32 `complex` + 3 `unknown` case** (D?): поле угадано эвристикой. Например, у PP 494 «Haste gives block chance…» показано `maxTolmatMinions` — это ошибка эвристики.
- **`equipEffectModifier`** (параметр `UpdateStats`): источник ненулевого значения не найден.
- **PlayerProperty вне switch:** 190, 507, 528, 551, 630, 665 (зелья), 126, 127 (компаньоны). Предположительно `HealthPotion`/`Downed`, не разбирались.
- **Компонент `The_Falcon`:** имени «The Falcon» в UniqueList нет, привязка не подтверждена.
