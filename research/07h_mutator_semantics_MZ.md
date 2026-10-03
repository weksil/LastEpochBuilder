# 07h. Семантика полей мутаторов скиллов M–Z (Last Epoch 1.5.0)

Данные: `research/data/game/mutator_field_semantics_MZ.json` (собираются `dump/work_wave3/mz/merge.py --write` из `mz/out/<Mutator>.json`).
Формат записи: `mutator, field, offset, declaredIn, semantic, formula, affectsNumbers, category, readers, confidence, notes, trees, nodes`.
Здесь `f` в формулах — значение поля, которое пишет дерево навыков (`flat + per_point * p`); `p` — вложенные очки.

## 1. Покрытие

| Показатель | Значение |
|---|---|
| Мутаторов (группы `mz/groups.json`) | 121, у всех есть выходной файл; `merge.py`: bad = [], missing = {}, extra = {} |
| Записей (полей, пишущихся деревьями) | 2581 |
| Достоверность `D` (код прочитан, формула получена) | 2371 |
| Достоверность `D?` (часть выведена из имени/тултипа или не найден читатель) | 210 (список в п. 6) |
| `affectsNumbers = true` | 2490 |
| `affectsNumbers = false` (чисто поведенческие: визуал, флаги без числового эффекта, ability swap, мёртвые поля) | 91 |

Категории (число полей): damage 483, proc 313, buff 226, behaviour 208, conversion 202, defence 188, mana 168, ailment 156, minion 146, area 140, speed 111, projectile 77, duration 69, cooldown 51, debuff 32, other 11.

Самые «тяжёлые» мутаторы: ProfaneVeil 48, RunicInvocation 47, Runebolt Fire/Cold/Lightning 46/45/45, TempestStrike Cold/Phys/Light 41/41/38, Warcry 41, Static 37, StaticOrb 37, Transplant 37.

Метод. Для каждого мутатора: срез Ghidra (`ms/slices/<M>.txt`), чтение методов-читателей, при необходимости ISIL (`ms/fn.py --isil`) и константы `tools/readconst.py`. Правила: без субагентов, без Ghidra/AssetRipper, без UI.

## 2. Что влияет на числа, а что поведенческое

* Числовые (2490): множители/добавки урона, площади, скорости, стоимости, длительности, шансы, resist/penetration, добавленные статы. Большая часть реально влияет через три канала:
  1. прямые поля, копируемые в adapter/компонент (summon, totem, shockwave и т.п.);
  2. `getTempStats` / `addsTempStats` (список `unconditionalTempStats` + «производные» статы: за заряд, за миньона, за Intelligence и т.д.);
  3. условные эффекты `DamageConditionalEffect` (HasAilmentConditional / LowHealthConditional / CursedConditional) с `DamageEffectMoreDamage[PerAilmentStack]`.
* Поведенческие (91): `hourglass`, `shotgun`, `traversalTagRemovedFromTree`, `coldTag`, `visualColdConversion`, `backflipOnUse`, `increasedReturnSpeed`, ability-swap флаги (`convertHuman…OnUse`), мёртвые поля (п. 4) и т.п.
* Поля-списки `List<Stat>` (160 штук: `statList`, `*TempStats`, `*Stats`) — «ёмкости»: их числовой смысл задаётся узлами дерева (в JSON поле `nodes`/`trees`), а мутатор лишь кладёт список в нужный компонент. Для планировщика важно, КУДА список применяется (summon, totem, aura, buff на игрока, следующий каст).

## 3. Заметные механики и закономерности

### 3.1 Скорость: «increased» против «more»
* Аддитивная `getIncreasedCastSpeed()` (складывается с остальным increased): Snap Freeze, Spirit Plague, Tornado (`increasedCastSpeed`), Transplant, Vengeance, Volcanic Orb (`increasedCastSpeed`), Wandering Spirits, Umbral Blades (`increasedAttackSpeed`), Spriggan Healing Totem (`increasedSummonSpeed`).
* Мультипликативная `mutateUseSpeed` (ведёт себя как more/less): Multishot, Shatter Strike, Shadow Cascade, Shield Throw, Multistrike (из первой части), Summon Volatile Zombie (`increasedCastSpeed`, `* (1+f)`), Summon Wraith (`increasedCastSpeed`), Thorn Totem (`increasedSummoningSpeed`), Tornado (`moreCastSpeed`), Volcanic Orb (`moreCastSpeed`), Tempest Strike (`increasedAttackSpeed`: `(1+f)*useSpeed`), Umbral Blades (`lessAttackSpeed`: `(1-f)*useSpeed`), Werebear Charge (`(1-less)*(1+inc)`), Upheaval (`lessAttackSpeedForTotems` и `noAttackSpeedScaling` — деление на stat Attack Speed), Storm Crow (`teleportSummonerToTarget`: use speed ×0.75).
* Практическое следствие: поле с именем `increasedAttackSpeed`/`increasedCastSpeed` НЕ всегда аддитивное. Смотреть на читателя (`getIncreasedCastSpeed` или `mutateUseSpeed`). Тултип «+X% Cast Speed» в двух случаях выше на самом деле «more».
* Multishot: speed стрелы укорачивает время жизни, поэтому дальность не меняется (проверено в первой части).

### 3.2 Площадь и радиус
* Общая форма: `radius = sqrt((1+f)^2 + statArea) - 1` (`Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease`), где `statArea` — аддитивный Increased Area для навыка. Деревья пишут в поле уже `sqrt(1 + k*p) - 1` (Snap Freeze, Surge, Swipe, Tornado, Transplant, Wandering Spirits, Werebear Maul и др.), т.е. 4 очка по «+20% Area» дают `sqrt(1.8)-1`, а не 0.8.
* Исключения (аддитивная «area» без sqrt в поле): Void Cleave `increasedArea` (складывается с `statArea` внутри `GetTotalIncreasedArea`, sqrt берётся уже после), Warpath, Warcry, Wandering Spirits (`increasedRadius` — множитель радиуса, `increasedDamageRadius` — sqrt-форма).
* Рисунок «ровно одно поле читается по ISIL»: у Snap Freeze, Shield Throw, Radiant Lance радиус вызывает функцию без аргументов в Ghidra; аргумент (поле) виден только в ISIL (отмечено `D?` там, где ISIL не открывали).

### 3.3 Кулдаун: «поле плюс поле»
`increasedCooldownRecoverySpeedFromMutator` у многих мутаторов (Transplant, Teleport base, Volatile Reversal base, Void Cleave, Wandering Spirits, Shurikens) в Ghidra печатается как `field + field + …`. Второе слагаемое — поле базового `AbilityMutator` (+0xF8), а не двойной учёт (проверено ISIL на Reap, паттерн совпадает).

### 3.4 Значения «сырых битов» в дереве
Узел Storm Orbs у Tornado пишет `moreCastSpeed = 3192704256.0`. Это `0xBE4CCCCD` — битовое представление float `-0.2`, т.е. -20% (экспортёр вывел int-биты). Учитывать при чтении `value` деревьев: числа вида 31927…, 1.17965e+06 — артефакты, не реальные значения.

### 3.5 Расхождения тултип ↔ код
* Rune Ember: Cold conversion конвертирует Fire→Cold (source type 1), а тултип пишет Lightning→Cold.
* Soul Feast: итог `increasedWardGenerated` после цикла даёт -0.35 вместо -50% в тултипе.
* Sacrifice: DoT-бонус в коде `more`, а не `increased` как в тултипе; Rip Blood: потолок damage-per-minion — 20 миньонов (эффективный потолок `f*20`).
* Marrow Shards: базовая стоимость здоровья 0.09 (подтверждено ISIL).
* Tornado: стоимость канала в коде 6.0 (0x40c00000), тултип 5/с (не примирено).
* Sonic Wave, Snap Freeze, Soul Feast: часть чисел (длительность баффа 4 с и т. п.) взята из тултипа, не из кода (отмечено).
* Swarmblade Spin: добавленный урон за локуста = `N * (15 + f)`, 15.0 — константа 0x41700000 (в Ghidra виден только 15; ISIL подтверждает поле +0x138). Слайсер показал `readers=[]` из-за потерянного float-аргумента.

### 3.6 Читатели в базовых классах (слайсер показывает `readers=[]`)
Поле объявлено в базовом классе и читается там: Rive (BaseRive), Runebolt Fire/Cold/Lightning (RuneboltMutator), Swarmblade Armblade Slash 1/2/3 (SwarmbladeArmbladeSlashMutator), Umbral Blades 1/2/3 (BaseUmbralBladesMutator), Tempest Strike Cold/Light/Phys (TempestStrikeMutator, 35 из 41 полей), Teleport/TeleportReturn (TeleportBaseMutator), Volatile Reversal/Return (VolatileReversalBaseMutator), а также `addedManaCostDivider` (+0xC0) и `increasedManaCost` (+0xC4) практически у всех мутаторов — это поля `AbilityMutator`, читаются базовыми `getAddedManaCostDivider`/`getIncreasedManaCost`.

### 3.7 Деревья, пишущие в чужие мутаторы
* Multistrike → Void Cleave: «Void Cleave Consumes Stacks For More Damage» пишет в поля `VoidCleaveMutator` (`moreDamagePerMultistrikeStack`, `increasedAreaMultistrikeStackPerStack`); живой читатель — Void Cleave, а `MultistrikeMutator.voidCleaveConsumesStacks` мёртвое (Void Cleave при касте списывает ВСЕ стаки Multistrike: `multistrikeMut+0x198`).
* Teleport → Transplant: все `Teleport*` поля читает `TransplantMutator.Mutate` (cross-class), форма и числа те же, что у `TeleportBaseMutator`.
* Static → Lightning Blast: поля Static копируются в `LightningBlastMutator` (дозаряд, дальность дугой, шок за заряды).
* Warpath ↔ Void Cleave (`moreDamageWithVoidCleaveAfterWarpath`, `minDurationOfWarpathForVoidCleaveBuff`), Swipe → Werebear Swipe/Bear, Warcry → Werebear Roar, Thorn Totem tree → Spriggan Healing Totem / Swarmblade Hive (`castsThorns`), Spriggan Form → Spirit Thorns, Storm Bolt ↔ Scorpion (`scorpionStormBoltSoak`: живой читатель StormBolt).

### 3.8 Конкретные числовые находки
* Static: движение даёт `(1+f)*5` зарядов/с (×2 с double); разряд: дальность `×(1 + f + charges*perCharge/10)`, шок/Haste = `floor(charges/50)*k`, авто-zap при >80 зарядов; Static Orb: `addedManaCostMaxManaPercentage` = `min(100, maxMana*f)`.
* Spriggan/Thorn Totem: заморозка `15*(1+0.05*Attunement)`; кольцо тотемов радиус 2.3 (0x40133333); `thornAddedDuration` — плюс секунды после мультипликатора.
* Storm Bolt: расход маны `min(10, mana*f)`, бонус урона `min(3.0, mana*f/10)`; Storm Totem: spell lightning за шок-шанс `((chance+retaliation)/0.1)*f`.
* Skeleton: лимит = `3 + passives + f` (halfSkeletons делит пополам); Wraith: максимум `6 + f + mgr`, интервал `0.5*(1-f)`.
* Void Cleave: `moreMeleeDamagePerBleed` ограничен `maxMoreMeleeDamagePerBleed`; Ravaging Aura +duration за каждого врага до 10 с.
* Smite: конверсии fire→lightning (+electrify) и fire→void (+time rot), режим `freeAtZeroMana` (при нуле маны стоимость 0, но нет хила/Fissure); Surge: Dormant Energy через `getTempStats`.
* Umbral Blades: критмульти `min(20, blades)*f`, урон за Dusk Shroud `min(20,stacks)*f`.

## 4. Мёртвые / вероятно неиспользуемые поля (нет читателя)

| Мутатор.поле | Комментарий |
|---|---|
| MultistrikeMutator.voidCleaveConsumesStacks | эффект реализован в VoidCleave (см. 3.7) |
| NetMutator.moreFalconDamageToNetted | читателей нет ни в мутаторе, ни в 8 связанных файлах |
| PrimalistSummonElementalMutator.noCooldown | читателя нет в слайсе |
| ProfaneVeilMutator.increasedDurationUsingSceptre | не используется `GetTotalDurationModifier` |
| RadiantLanceMutator.increasedAreaWith3DivineEssences | вызов радиуса с потерянными аргументами (возможно живое, не подтверждено) |
| RingOfShieldsMutator.potionsHealShieldsToo | вне класса не прослежено |
| ShatterStrikeMutator.recastChanceWith2h | возможно чтение по вычисленному смещению |
| ShurikensMutator.pierceConvertedToCritMulti | флаг без читателя, поведение через `ricochetAmount>0` |
| SigilsOfHopeMutator.divineFlare* (4 поля) | копии; реальный эффект в DivineFlareMutator |
| SmokeBombMutator.increasedSmokeBladesEffectiveness | не читается в мутаторе |
| SparkChargeExplosionMutator.coldConversion | эффект, если есть, в ManaStrike |
| SprigganHealingTotemMutator / SwarmbladeSummonHiveMutator.increasedSummoningSpeed | живое — ThornTotem.mutateUseSpeed |
| SummonScorpionMutator.scorpionStormBoltSoak | живое — StormBoltMutator |
| SummonSkeletonMutator.chanceToResummonOnDeath | читателя нет |
| SynchronizedStrikesMutator.extraTemporaryMaxShadows | читателя нет |

## 5. ISIL-заметки по запросу координатора

### 5.1 Manifest Armor — «ничего не делающие» узлы
В `ManifestArmorMutator.Mutate` (ISIL) поля `useShield` (+0x145), `useWeapon` (+0x144), `whirlwindMode` (+0x18C), `canCharge` (+0x18D), `tauntChance` (+0x190) только КОПИРУЮТСЯ в `ManifestedArmorAdapter` (байты +0x5C…+0x5F и float +0x60: shieldMode, swordMode, whirlwind, canCharge, taunt) — никакой численной логики в самом мутаторе нет. Дополнительно: `canCharge` добавляет ExtraAbility Charge (ссылка +0x1E0, кулдаун 8.0 с по константе 0x184561FFC), а `useShield`/`useWeapon` участвуют лишь в `baseTypeMatch` (копирование статов экипировки). `addsMinionFireTag` (+0x146) читается только в `getMinionDisplayTags` (добавляет тег Fire к миньону; сами +2 fire damage приходят через `statList`). Т.е. «пустые» узлы — узлы, эффект которых целиком в `ManifestedArmorAdapter`/`ManifestArmor01MeleeMutator`; другой агент должен разбирать адаптер, а не мутатор.

### 5.2 Holy Aura — клонирование статов ×2
`HolyAuraMutator.<Mutate>g__ApplyStatToAura|40_0` (ISIL): клонирует `Stat` (конструктор копии 0x18169E4A0), затем (1) если `useAuraStatsMultiplier` — умножает значение на `auraStatsMultiplier` (+0x13C), (2) ВСЕГДА умножает на `(X + 1.0)`, где `X` берётся из локального display-class (3-й параметр), и добавляет в баф ауры. То есть два последовательных мультипликативных шага, а не «каждый стат дважды»; итог `value * [auraStatsMultiplier] * (1 + X)`. Соседнее поле `increasedEffectFromPassives` (+0x140) в этой функции не читается (используется в других методах).

## 6. Список D? (210 записей: мутатор.поле — причина)

Автоматически сгенерирован из JSON; причины сокращены.

* **MaelstromMutator** (9)
  * `statList` — Per-stack scaling is implicit in BuffParent, not traced.
  * `chanceToAutoCastOnHit` — Boss/rare restriction from tooltip.
  * `maxStacksOfLagonsSlumber` — Stack-gain timing only partly visible.
  * `moreDamageToFrozen` — Attachment block elided in Ghidra; semantics from name and Tsunami copy.
  * `moreDamageToChilled` — As moreDamageToFrozen.
  * `chanceToCastTornadoOnStackGained` — No rolling reader visible in the slice, only copies.
  * `convertsEarthArmorIntoMaelstrom`
  * `scorpionMaelstromChance` — Field lives on MaelstromMutator but written by Summon Scorpion tree node; the downstream cast was only partly …
  * `elementalMaelstromChance`
* **ManaStrikeMutator** (7)
  * `increasedSpellDamageOnHit` — Buff duration/stack cap not visible (args dropped by Ghidra). Tooltip: doubled on bosses and rares via increas…
  * `increasedSpellDamageOnEliteHit` — Same as increasedSpellDamageOnHit.
  * `removesCritMultiplier` — Stats_MoreStat(5,0,0xbf800000) = more CriticalMultiplier -100%; the exact multiplier effect depends on crit-mu…
  * `chanceToKnockBack` — Knockback buff stat details elided.
  * `leechWhileNotFullMana` — Condition (mana below max) is in elided lines; offset 0x40 interpreted as leech.
  * `coldConversion` — Tag change itself is in getTags of base chain.
  * `staticOrbChance` — 80% doubling from tooltip and BaseMana.percentCurrentMana call.
* **ManifestArmorMutator** (7)
  * `useWeapon` — Numbers depend on the weapon in the gear.
  * `useShield` — Numbers depend on the shield in the player gear; planner needs the shield item stats.
  * `flamethrowerIgniteChance` — Adapter consumer not followed.
  * `flamethrowerIncreasedDamage` — Consumer of adapter+0x54 is in the adapter class (not followed).
  * `whirlwindMode`
  * `canCharge`
  * `tauntChance` — Adapter consumer not followed.
* **ManifestWeaponMutator** (1)
  * `moreDamageAgainstBleedStunned` — two independent effects: a target both stunned and bleeding likely gets (1+field)^2
* **MarkForDeathMutator** (1)
  * `enemiesToProliferatePoisonAndDamn` — written by Profane Veil tree node; 5.0 verified (18456202C); remainingDurationModifier arg = 0 (xmm6 zero) - e…
* **MarrowShardsMutator** (2)
  * `physLeechOnCast` — Unit scale of leech (0.3 vs +3% tooltip) suggests percent*10 or leech stored in different units; verify.
  * `physLeechOnKill` — Same leech unit question as physLeechOnCast.
* **MeteorMutator** (2)
  * `increasedMeteorFrequency` — Frequency only changes shower duration unless count is fixed.
  * `increasedFallSpeed` — Affects only fall time (delay before damage), not damage numbers.
* **MultishotMutator** (6)
  * `increasedSlowDurationPerDexRatio` — Which attribute index 3 is (assumed Dexterity from tooltip).
  * `increasedDamageIfStationary` — increaseAllDamage adds to damageModifier (assumed additive with increasedDamage field of this mutator).
  * `maxDamageFalloffFromDistance` — Exact base of the modifier (start at max) interpreted from SetMinMax(-f,0).
  * `armorShredChancePerArrow` — Constant 5 = base arrow count of Multishot assumed; Ghidra literal 5.0 not ISIL-verified.
  * `projectileUpperLimit` — Field 2 vs tooltip 3 arrows: probably limit counted as extras excluding the base arrow.
  * `increasedBleedDurationPerDexRatio` — As slow.
* **MultistrikeMutator** (5)
  * `critMultiWithSpear` — Weapon check body truncated in Ghidra.
  * `voidCleaveConsumesStacks` — Grep of decomp shows only ForgeStrike/Smelters/VoidCleave referencing MultistrikeMutator; none touch +0x175 by…
  * `swordsReplacedWithSmite` — Damage of Smite (not the sword) applies; planner needs Smite base data.
  * `consumesManaToShotgun`
  * `spearConversion`
* **NetMutator** (8)
  * `increasedThrowingSpeedWithHuntress` — SP 2 = attack/cast speed family; verify against sp_enum.
  * `moreDamagePerDodgeChance` — Unit of dodgeChance (fraction vs percent) not verified.
  * `moreFalconDamageToNetted` — Searched 8 decomp files referencing NetMutator; treat as dead/unimplemented unless other evidence.
  * `increasedJumpDistancePerDex` — Attribute index 3 assumed Dexterity from tooltip.
  * `lessPhysDamageDealtWhileNetted`
  * `dropsCaltropsAtTarget`
  * `hasPhysDot`
  * `huntressMaxDuration` — Conditional property 0x1B value elided; see stat_tag_enums ConditionalDamageProperty.
* **NovaMutator** (1)
  * `channelled` — Nova cadence while channelling comes from the channelled nova prefab, not visible in this class.
* **PhysTempestMutator** (1)
  * `penPerTypedMinion` — numberOfMinions args (1,1) likely filter type/alive; exact minion filter not resolved.
* **PrimalistSummonElementalMutator** (18)
  * `maxElementalFuryStacks` — Per-stack bonus lives in the adapter.
  * `elementalBoltConsumesFuryStacks` — Projectile count rule from tooltip.
  * `moreDamagePerSecondSummoned` — Cap 18% from tooltip.
  * `geyserRepeatChanceFromTotems`
  * `geyserIncreasedCooldownRecoverySpeed`
  * `noCooldown` — readers=[] in slice; likely read by AbilityMutator cooldown logic via another path or unused. Related numeric …
  * `geyserSummonModeMoreDamage`
  * `geyserSummonModeMoreArea`
  * `geyserElementalBoltCasts`
  * `increasedHealthRegenFromIncreasedManaRegen` — Computation partly elided.
  * `wellspringAddedColdSpellDamage` — Aura application is in PrimalistElementalAdapter (not followed).
  * `wellspringIncreasedCastSpeed`
  * `wellspringIncreasedEffectPerAttunement`
  * `wellspringDoubledForTotems`
  * `wellspringDoesNotAffectPlayers`
  * `wellspringStormCrowChainChance`
  * `movesTotemsWhenSummoned`
  * `castsMaelstrom`
* **ProfaneVeilMutator** (8)
  * `statsAfterProfaneForm`
  * `wardGainOnDodgePerDexWhileInProfaneForm`
  * `increasedDurationUsingSceptre` — readers=[] in slice and no cross-class reader; GetTotalDurationModifier does not use it.
  * `cooldownReductionCharges` — Per-use cooldown effect from tooltip.
  * `damnedBleedPoisonIgniteSlowChanceGainedAsIgniteChancePerSecond` — Sum of six chance terms (fVar18+fVar17+...); the exact set is elided in Ghidra.
  * `infernalShadeChance` — Roll site in the second AoE mutator (not followed).
  * `moreDamagePerBleedChance` — Tooltip says +1% per 10% bleed chance but f=1.0 and bleedChance units unknown (fraction -> 10% chance = +10%?)…
  * `wardPer15UncappedNecroticResFromWanderingSpirit`
* **PunctureMutator** (4)
  * `poisonConvertedToBleed` — Stat(100,2,1.0) interpreted as ailment conversion.
  * `directUseShadowDaggerChance` — Ailment id 0x4F assumed to be the Shadow Dagger proc ailment.
  * `moreDamageAfterDancingStrikes` — increaseAllDamage is additive generic damage modifier.
  * `physicalPenetrationPer15Mana` — SP 0x3B penetration tag uses converted type (physical or poison).
* **RadiantLanceMutator** (7)
  * `lightningPenetrationDoubledForAilments` — Tag values partially elided (uVar13=2, uVar7=0x10).
  * `lightningPenPerElectrifyStackUpTo10` — Conditional effect class elided.
  * `moreScathingLightDamagePer1PercentIgniteElectrifyChance` — Which ailment ids sum: Stats.GetAilmentChance(0x5D) + electrify + (shock) + extra fVar6 (ignite).
  * `increasedAreaWith3DivineEssences` — readers=[] ; Mutate calls GetIncreasedRadiusAfterAdditiveAreaIncrease with dropped args (xmm) - check ISIL for…
  * `reliquaryMoreHealth` — Tooltip says duration; code adds a more Health stat.
  * `electrifyChance` — Only read in the ailment damage modifier; the actual chance to apply electrify comes from tree stats on hits (…
  * `shockChance` — Actual shock application chance comes from tree stats.
* **ReapMutator** (1)
  * `moreDamagePerPercentMissingHealth` — Unit of getMissingHealthPercent (0-100 vs 0-1) not verified; tooltip says 1% per 1% missing.
* **ReaperFormMutator** (3)
  * `coldConversion` — Reap's own damage conversion (tooltip) not done here; only tag/ailment swap + AbilityObjectIndicator visuals s…
  * `poisonConversion` — tooltip '+100% poison chance / no crit' not implemented in this class
  * `physicalConversion` — cold overrides physical overrides poison
* **RingOfShieldsMutator** (4)
  * `creatorBuffStats` — Per-shield scaling implemented in the adapter (not followed).
  * `consumeForShieldThrow`
  * `fireDamageOverTimeNearby` — Damage formula in adapter/forgeFlames ability.
  * `potionsHealShieldsToo` — Not followed outside the mutator class.
* **RipBloodMutator** (3)
  * `increasedDamagePerMinion` — Tooltip cap +20% damage max; code cap is 20 minions - effective cap = f*20 (0.4 at p=1).
  * `increasedHealthGained` — Combination across nodes is computed in the tree after-loop expression.
  * `increasedHealthGainedPerIntelligence` — Index 2 assumed Intelligence from tooltip.
* **RiposteMutator** (1)
  * `physPenWithBleedPerOvercappedPhysRes` — Ghidra literal 0.75 not ISIL-verified; exact ailment id depends on vengeance conversion (1 or 2).
* **Rive2Mutator** (1)
  * `twoHandedWeaponStatModifier` — Per-affix details (PropertyMatch) not enumerated.
* **Rive3Mutator** (2)
  * `twoHandedWeaponStatModifier` — Per-affix details (PropertyMatch) not enumerated.
  * `addedLifeLeechOnHit` — Unit: tree 0.3 vs tooltip 3% suggests leech stored x10 scale.
* **RiveMutator** (3)
  * `twoHandedWeaponStatModifier` — Per-affix details (PropertyMatch) not enumerated.
  * `critChanceOnHit` — Buff details elided.
  * `shootEnergyWave`
* **RuneEmberMutator** (1)
  * `coldConversion` — Tooltip says Lightning -> Cold but code source type is 1 (Fire).
* **RuneboltColdMutator** (4)
  * `consumeCooldownReducedPerRuneInvocated` — readers=[]; field only inferred from the name and the 20 s constant.
  * `moreElemenetalDamagePerRuneweaveStackPerArmorShredOnTarget` — Property 0x12 meaning inferred from the name.
  * `increasedExplosionAreaPerUncappedRes` — Unit of resistance (fraction vs percent) not verified.
  * `physicalSpellDamagePerStrengthOfNearbyPartyMember` — Stat construction partly elided.
* **RuneboltFireMutator** (4)
  * `consumeCooldownReducedPerRuneInvocated` — readers=[]; field only inferred from the name and the 20 s constant.
  * `moreElemenetalDamagePerRuneweaveStackPerArmorShredOnTarget` — Property 0x12 meaning inferred from the name.
  * `increasedExplosionAreaPerUncappedRes` — Unit of resistance (fraction vs percent) not verified.
  * `physicalSpellDamagePerStrengthOfNearbyPartyMember` — Stat construction partly elided.
* **RuneboltLightningMutator** (4)
  * `consumeCooldownReducedPerRuneInvocated` — readers=[]; field only inferred from the name and the 20 s constant.
  * `moreElemenetalDamagePerRuneweaveStackPerArmorShredOnTarget` — Property 0x12 meaning inferred from the name.
  * `increasedExplosionAreaPerUncappedRes` — Unit of resistance (fraction vs percent) not verified.
  * `physicalSpellDamagePerStrengthOfNearbyPartyMember` — Stat construction partly elided.
* **RunicInvocationMutator** (2)
  * `chanceToCastCorrespondingInvocationWhenConsumedByOtherSkill` — Only visible in ISIL fragment.
  * `penetrationPer3Intelligence` — Division by 3 from tooltip; details elided.
* **SacrificeMutator** (2)
  * `moreDotDamageOnCast` — Tooltip says increased but code applies a more stat.
  * `infernalShadeNewDurationOnCast` — Duration cast to int, so 2.1 -> 2 s.
* **ScorpionCompanionAbilityMutator** (1)
  * `poolDuration` — Tooltip says Creates Poison Pool; f-1 used as increased duration of the pool object base.
* **SerpentStrikeMutator** (3)
  * `lifeOnCrit` — Ghidra shows the Roll() argument as this field too; probably an argument-tracking artefact, the roll chance is…
  * `slitherDodgeRatingPerOnePercentColdRes`
  * `constrictorStats` — Per-stack scaling inside elided loop.
* **ShadowCascadeMutator** (5)
  * `moreDamagePerAttackSpeed` — Stat used for S read via Stats.GetStatValue (ability tags) elided.
  * `increasedPhysicalDamageIfHitAtLeast4EnemiesRecently` — Buff duration 4 s from tooltip.
  * `daggerShadowDaggerChance` — Slice reported readers=[] because the read uses base+offset arithmetic.
  * `daggerShadowDaggerChanceFromShadows` — As above.
  * `daggersPerSecond` — Interval constant 0x3ea8f5c3 = 0.33 s hard-coded; field only gates the branch.
* **ShatterStrikeMutator** (3)
  * `moreDamageToHighHealth` — Doubling vs high health from tooltip.
  * `firebrandStacksToConsume`
  * `recastChanceWith2h` — readers=[]; not found in decomp slice; may be read through computed offset in the strike mutator.
* **ShieldBashMutator** (2)
  * `shieldWallWithRingOfShieldsActive` — Width computation partly elided.
  * `moreFireDamagePerBlockChance` — Unit: blockForDamageScaling is block chance fraction (cap 1); f=0.25 per point means +25% max with 100% block.
* **ShieldRushMutator** (2)
  * `delayedEndRushMoreDamage` — Only read by the DPS tooltip; the actual damage uses delayedEndRushStats (more Damage 0.45 per point).
  * `addedVoidReducedByAttackSpeed` — The attack-speed reduction is not visible in the slice (f is added directly).
* **ShieldThrowMutator** (2)
  * `increasedLavaBurstRadius` — readers=[]; Ghidra shows the call without args; assumed from Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease…
  * `colossusStacksOnHit` — Per-stack stats in elided StatBuffs.AddBuff call.
* **ShiftMutator** (1)
  * `addedTravelDamage` — Effective damage uses the equipped melee weapon (itemContainersManager) - see DamageStatsHolder.calculateAdded…
* **ShurikensMutator** (3)
  * `increasedCooldownRecoverySpeed` — Name collision between derived and base field; verified by ISIL only for ReapMutator.
  * `shotgun` — No numeric effect in Mutate; tooltip-only flag.
  * `pierceConvertedToCritMulti` — Flag unused by name; behaviour implemented through ricochetAmount>0.
* **SigilsOfHopeMutator** (4)
  * `divineFlareChanceToCleanseAilmentsPerSigil` — dead copy on this mutator; effect lives in DivineFlareMutator (not analysed here)
  * `divineFlareChanceToBlindPerSigil` — dead copy; real effect in DivineFlareMutator
  * `divineFlareDamagePerSigil` — dead copy; planner must model it on Divine Flare
  * `divineFlareIncAreaPerSigil` — dead copy; real effect in DivineFlareMutator
* **SmeltersWrathMutator** (3)
  * `statsPerSecondCharged` — Per-second scaling is inside SmeltersWrathEndMutator (not read in this slice).
  * `attackSpeedToCritChanceConversion` — Conversion body elided in Ghidra.
  * `areaStatsGiveFireDoTInstadOfChargeSpeed` — The 0.03 constant from tooltip; value argument elided in Ghidra.
* **SmokeBombMutator** (1)
  * `increasedSmokeBladesEffectiveness` — Not read in the slice; likely consumed through the Smoke Blades ailment instance offset (0x168) elsewhere or d…
* **SnapFreezeMutator** (2)
  * `increasedRadius` — readers=[]: argument loss in Ghidra; assumed from the Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease call.
  * `hourglass`
* **SonicWaveMutator** (1)
  * `coldConversion` — Conversion body read from names/tooltip; Mutate not expanded.
* **SoulFeastMutator** (3)
  * `increasedWardGenerated` — Tree after-loop value (1-x)-1 gives -0.35 whereas tooltip says -50%.
  * `consumePoisonStacks` — Consumption effect inside elided branch.
  * `increasedCastSpeed` — mutateUseSpeed body not shown in the slice; assumed analogous to others.
* **SparkChargeExplosionMutator** (1)
  * `coldConversion` — Mana Strike cold conversion of the spark-charge explosion, if any, must come from ManaStrikeMutator, not here;…
* **SpiritPlagueMutator** (2)
  * `moreSpiritPlagueDamage` — Is modifier "more" multiplicative with the other more sources? The returned value is summed over nodes.
  * `reactivateToSpread` — 0x40000000 as undefined4 raw -> float 2.0 s; Ghidra shows as integer.
* **SprigganFormMutator** (1)
  * `maxValeSpirits` — Only reader in all decomp. Tooltip '1 Vale Spirit every 5 Spirit Thorn casts / +1 max Vale Spirits' is not imp…
* **SprigganHealingTotemMutator** (2)
  * `convertToCold` — Tooltip claims 30 base freeze rate and +25% freeze rate multiplier; constants in code are 15 (0x41700000); 30 …
  * `increasedSummoningSpeed` — readers=[]; see ThornTotemMutator for the live reader.
* **SprigganVinesMutator** (1)
  * `increasedSize` — Tooltip says +200% size; code constant 0.88 compounding with other nodes unresolved.
* **StaticMutator** (2)
  * `unconditionalTempStats` — The 0.04*charges MoreStat (ISIL const 0.04) is a built-in Static bonus; unclear whether the value is a fractio…
  * `addedLightningDamagePerCharge` — Tags of this added Damage stat not read from asm (edx=0, r8d=0).
* **StaticOrbMutator** (2)
  * `moreDamagePer25MaxMana` — Exact division (/25) inferred from tooltip; Ghidra elides the arithmetic.
  * `chargedGroundMoreDamagePer10CritMulti` — Division by 10% inferred from tooltip.
* **StormBoltMutator** (3)
  * `lightningPenetration` — Tag of penetration (lightning vs converted type) read from asm branches (uVar5=0x17 for cold conv. path), not …
  * `addedSpellDamagePer3MeleeDamageOnAxeOrMace` — Divisor 3 inferred from tooltip (divss by a constant held in xmm9).
  * `scorpionStormBoltSoak` — Scorpion-side effect (stacks, shock nova) lives in the scorpion classes.
* **StormTotemMutator** (2)
  * `spellLightningDamagePer10percentShockChance` — The fVar14 term (player shock chance) is elided in the slice; only the 0x57 ShockRetaliationChance term is vis…
  * `consumesOtherTotems` — Per-totem 20% bonus is applied in the elided consumption branch.
* **SummonMageMutator** (1)
  * `increasedNecroticMorterRadius` — tree value already sqrt(1+0.2p)-1. Code only sets adapter usesFireMortar (pyro) / usesColdMortar (cryo); adapt…
* **SummonScorpionMutator** (1)
  * `scorpionStormBoltSoak` — See StormBoltMutator.mutateTargetLocation.
* **SummonSkeletonMutator** (1)
  * `chanceToResummonOnDeath` — Tooltip says 10% resummon chance per point; not verified.
* **SummonWolfMutator** (2)
  * `iceBite` — WolfIceBiteMutator internals not traced.
  * `alwaysHowlWithBonusWolf` — Forced ability = howl via CompanionMutator base logic (not traced).
* **SwarmbladeSummonHiveMutator** (1)
  * `increasedSummoningSpeed` — readers=[]; live in ThornTotemMutator.
* **SynchronizedStrikesMutator** (2)
  * `healthGainedFromShadowsCreatedWithin4Seconds` — Which SP the stat uses was not resolved.
  * `extraTemporaryMaxShadows` — Tree writes flat 2.0 with the twoMoreShadows node.
* **TeleportMutator** (1)
  * `statsAtEnd` — Base buff duration constant at +0x164 not resolved here (base field).
* **TeleportReturnMutator** (1)
  * `statsAtEnd` — Base buff duration constant at +0x164 not resolved here (base field).
* **TempestStrikeColdMutator** (3)
  * `physPenPer5UncappedPhysRes` — Exact scaling (per 5% = division by 0.05) inferred from the tooltip; arithmetic elided.
  * `coldPenPer5UncappedColdRes` — Same caveat.
  * `lightPenPer5UncappedLightRes` — Same caveat.
* **TempestStrikeLightMutator** (3)
  * `physPenPer5UncappedPhysRes` — Exact scaling (per 5% = division by 0.05) inferred from the tooltip; arithmetic elided.
  * `coldPenPer5UncappedColdRes` — Same caveat.
  * `lightPenPer5UncappedLightRes` — Same caveat.
* **TempestStrikePhysMutator** (3)
  * `physPenPer5UncappedPhysRes` — Exact scaling (per 5% = division by 0.05) inferred from the tooltip; arithmetic elided.
  * `coldPenPer5UncappedColdRes` — Same caveat.
  * `lightPenPer5UncappedLightRes` — Same caveat.
* **ThornTotemMutator** (1)
  * `addedManaCost` — Semantics of r12 in the after-loop expression not fully certain.
* **TornadoMutator** (2)
  * `increasedBuffDuration` — Ghidra shows "fVar28 + 1.0 + fVar28 + 1.0" for the actor buff duration; likely 2*(1+f) from a base 2.
  * `channelledWhenDirectlyCast` — Channel cost constant 6.0 vs tooltip 5 mana per second not reconciled.
* **UmbralBlades2Mutator** (1)
  * `singleBladeDamageBonus` — Which instance gets which is inferred from usedByShadow branch.
* **UmbralBlades3Mutator** (1)
  * `singleBladeDamageBonus` — Which instance gets which is inferred from usedByShadow branch.
* **UmbralBladesMutator** (1)
  * `singleBladeDamageBonus` — Which instance gets which is inferred from usedByShadow branch.
* **VolatileReversalMutator** (5)
  * `increasedArea` — Reader not found by the slicer.
  * `moreHitDamagePerSlow` — Reader not found.
  * `increasedAttackArea` — Reader not found by the slicer (declared in base).
  * `arrivalVoidBoltsReplacedByAbyssalEchoes` — Reader not found.
  * `guaranteedEchoAfterLongJump` — Reader not found.
* **VolatileReversalReturnMutator** (5)
  * `increasedArea` — Reader not found by the slicer.
  * `moreHitDamagePerSlow` — Reader not found.
  * `increasedAttackArea` — Reader not found by the slicer (declared in base).
  * `arrivalVoidBoltsReplacedByAbyssalEchoes` — Reader not found.
  * `guaranteedEchoAfterLongJump` — Reader not found.
* **VolcanicOrbMutator** (1)
  * `moreCastSpeed` — Ghidra shows addition of fVar1; likely a decompiler artefact of a multiply.

## 7. Покрытие по мутаторам (полей / из них D?)

| Мутатор | полей | D? |
|---|---|---|
| MaelstromMutator | 31 | 9 |
| ManaStrikeMutator | 25 | 7 |
| ManifestArmorMutator | 18 | 7 |
| ManifestWeaponMutator | 9 | 1 |
| MarkForDeathMutator | 12 | 1 |
| MarrowShardsMutator | 24 | 2 |
| MeteorMutator | 26 | 2 |
| MirageSmokeMutator | 4 | 0 |
| MultishotMutator | 25 | 6 |
| MultistrikeMutator | 28 | 5 |
| NetMutator | 31 | 8 |
| NovaMutator | 30 | 1 |
| PhysTempestMutator | 10 | 1 |
| PrimalistSummonElementalMutator | 31 | 18 |
| ProfaneVeilMutator | 48 | 8 |
| PunctureMutator | 29 | 4 |
| RadiantLanceMutator | 36 | 7 |
| RampageMutator | 1 | 0 |
| ReapMutator | 19 | 1 |
| ReaperFormMutator | 18 | 3 |
| RebukeMutator | 20 | 0 |
| RingOfShieldsMutator | 24 | 4 |
| RipBloodMutator | 27 | 3 |
| RiposteMutator | 9 | 1 |
| Rive2Mutator | 11 | 1 |
| Rive3Mutator | 14 | 2 |
| RiveMutator | 13 | 3 |
| RuneEmberMutator | 4 | 1 |
| RuneboltColdMutator | 45 | 4 |
| RuneboltFireMutator | 46 | 4 |
| RuneboltLightningMutator | 45 | 4 |
| RuneboltMutator | 1 | 0 |
| RunicInvocationMutator | 47 | 2 |
| SacrificeMutator | 24 | 2 |
| ScorpionCompanionAbilityMutator | 5 | 1 |
| SerpentStrikeMutator | 31 | 3 |
| ShadowCascadeMutator | 29 | 5 |
| ShadowRendBowMutator | 31 | 0 |
| ShadowRendMeleeMutator | 31 | 0 |
| ShatterStrikeMutator | 33 | 3 |
| ShieldBashMutator | 27 | 2 |
| ShieldRushMutator | 24 | 2 |
| ShieldThrowMutator | 33 | 2 |
| ShiftMutator | 29 | 1 |
| ShurikensMutator | 26 | 3 |
| SigilsOfHopeMutator | 21 | 4 |
| SkyBeamMutator | 3 | 0 |
| SmallExplosionMutator | 4 | 0 |
| SmeltersWrathMutator | 23 | 3 |
| SmiteMutator | 25 | 0 |
| SmokeBombMutator | 35 | 1 |
| SnapFreezeMutator | 20 | 2 |
| SonicWaveMutator | 7 | 1 |
| SoulFeastMutator | 32 | 3 |
| SparkChargeExplosionMutator | 1 | 1 |
| SpiritPlagueMutator | 30 | 2 |
| SpiritThornsMutator | 11 | 0 |
| SprigganFormMutator | 6 | 1 |
| SprigganHealingTotemMutator | 28 | 2 |
| SprigganVinesMutator | 10 | 1 |
| StaticMutator | 37 | 2 |
| StaticOrbMutator | 37 | 2 |
| StormBoltMutator | 13 | 3 |
| StormCrowAbilityMutator | 1 | 0 |
| StormTotemMutator | 19 | 2 |
| SummonBearMutator | 16 | 0 |
| SummonBoneGolemMutator | 29 | 0 |
| SummonCorpseParasiteMutator | 2 | 0 |
| SummonDecoyMutator | 16 | 0 |
| SummonLocustMutator | 9 | 0 |
| SummonMageMutator | 22 | 1 |
| SummonRaptorMutator | 24 | 0 |
| SummonSabertoothMutator | 17 | 0 |
| SummonScorpionMutator | 18 | 1 |
| SummonSkeletonMutator | 28 | 1 |
| SummonSprigganMutator | 33 | 0 |
| SummonStormCrowMutator | 34 | 0 |
| SummonVolatileZombieMutator | 35 | 0 |
| SummonWeaponMutator | 11 | 0 |
| SummonWolfMutator | 19 | 2 |
| SummonWraithMutator | 22 | 0 |
| SurgeMutator | 28 | 0 |
| SwarmbladeArmbladeSlash1Mutator | 8 | 0 |
| SwarmbladeArmbladeSlash2Mutator | 4 | 0 |
| SwarmbladeArmbladeSlash3Mutator | 4 | 0 |
| SwarmbladeFormMutator | 6 | 0 |
| SwarmbladeShiftMutator | 7 | 0 |
| SwarmbladeSpinMutator | 18 | 0 |
| SwarmbladeSummonHiveMutator | 24 | 1 |
| SwipeMutator | 27 | 0 |
| SynchronizedStrikesMutator | 28 | 2 |
| TeleportMutator | 17 | 1 |
| TeleportReturnMutator | 17 | 1 |
| TempestStrikeColdMutator | 41 | 3 |
| TempestStrikeLightMutator | 38 | 3 |
| TempestStrikePhysMutator | 41 | 3 |
| ThornShieldMutator | 12 | 0 |
| ThornTotemMutator | 21 | 1 |
| TornadoMutator | 29 | 2 |
| TransplantMutator | 37 | 0 |
| UmbralBlades2Mutator | 21 | 1 |
| UmbralBlades3Mutator | 20 | 1 |
| UmbralBladesBackflipMutator | 1 | 0 |
| UmbralBladesMutator | 24 | 1 |
| UmbralBladesRecallMutator | 19 | 0 |
| UpheavalMutator | 34 | 0 |
| ValeSpiritMutator | 2 | 0 |
| VengeanceMutator | 19 | 0 |
| VoidBoltMutator | 6 | 0 |
| VoidCleaveMutator | 29 | 0 |
| VolatileReversalMutator | 30 | 5 |
| VolatileReversalReturnMutator | 28 | 5 |
| VolcanicOrbMutator | 21 | 1 |
| WanderingSpiritsMutator | 29 | 0 |
| WarcryMutator | 41 | 0 |
| WarpathMutator | 34 | 0 |
| WerebearChargeMutator | 9 | 0 |
| WerebearFormMutator | 7 | 0 |
| WerebearMaulMutator | 10 | 0 |
| WerebearRoarMutator | 5 | 0 |
| WerebearSwipeMutator | 3 | 0 |

## 8. Пробелы и ограничения

1. Объекты-адаптеры (`*Adapter`, например `ManifestedArmorAdapter`, `HealingTotemAdapter`, `RaptorAdapter`, `SabertoothAdapter`, `ScorpionAdapter`, `SprigganAdapter`, `StormCrowAdapter`, `TempestTotemAdapter`, `UpheavalTotemAdapter`, `DecoyAdapter`, `HiveAdapter`) НЕ разбирались: для полей, которые мутатор только копирует в адаптер, `semantic` построен на имени, тултипе и месте копирования (confidence `D`, если куда копируется видно однозначно, `D?` если читатель не найден). Числовая формула внутри адаптера не получена.
2. Единицы: для доли/процента (`getMissingHealthPercent`, uncapped resistance, dodge chance, leech x10) единицы не везде проверены — помечено `D?`. Особенно «per 5% uncapped resistance» у Tempest Strike и Rune Bolt (деление на 0.05 выведено из тултипа).
3. Tooltip-only значения: длительности баффов (3–4 с), капы («max 20 minions/stacks») иногда взяты из тултипа, если Ghidra потерял float-аргумент; в `notes` указано.
4. Индексы атрибутов: 0 Strength, 1 Vitality, 2 Intelligence, 3 Dexterity, 4 Attunement — подтверждены тултипами (кроме отмеченных `D?`).
5. Cross-class читатели (`*Mutator.Mutate` соседних скиллов) проверены по разделу «CROSS-CLASS READS» слайса; чтение через вычисляемое смещение (`base + offset`) слайсер не видит (Shadow Cascade, Shatter Strike `recastChanceWith2h`).
6. Базовые AbilityMutator-поля (`addedManaCostDivider`, `increasedManaCost`, `increasedCooldownRecoverySpeed` +0xF8) считаются известными из блока A–L/06e; здесь только ссылка на базовый читатель.
7. Не проверялась работа деревьев после-цикла (`after_loop`) для сложных выражений (`acc[...]`) кроме тех, что отмечены в тексте (Tornado moreCastSpeed, Thorn Totem addedManaCost, Soul Feast ward).
8. Изображения, VFX, звук, UI не затрагивались.
