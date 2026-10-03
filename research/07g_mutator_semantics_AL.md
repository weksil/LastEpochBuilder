# 07g. Семантика полей мутаторов навыков A–L (Last Epoch 1.5.0)

Волна 3 reverse-engineering: для каждого навыкового мутатора `<X>Mutator` (буквы A–L, 97 классов) определено, что делает каждое поле заголовка, которое пишет дерево навыков (skill tree), в формуле игры. Источники: срезы Ghidra/ISIL (`dump/work_wave3/ms/slices`), `fn.py`, `readconst.py`; фоновые документы `07c_skill_mutators.md`, `dump_agent_brief.md`. Машиночитаемый результат: `research/data/game/mutator_field_semantics_AL.json` (плоский список, формат как у `mutator_field_semantics_MZ.json`; ключи: mutator, field, offset, type, declaredIn, semantic, formula, category, affectsNumbers, readers, confidence, notes, trees, nodes).

Уровни уверенности: **D** — поведение прочитано непосредственно в коде (Mutate / getTempStats / On* / геттеры). **D?** — поле только копируется в компонент, который не прослежен, значение читается только через ISIL без полного разбора, либо эффект выведен из названия узла/тултипа.

## 1. Итоги

- Мутаторов: **97** (из них 6 сделаны в предыдущей волне: ClawTotem, ColdTempest, DeathSealExit, DetonateDecoy, DivineBolt, DivineFlare; 91 новых).
- Полей всего: **2237**; числовые категории (урон, недуги, защита, скорость, область, стоимость и т.д.): **2005**; поведенческие флаги/режимы (категория behaviour): **209** (из них 132 переключают формулы, `affectsNumbers=true`); мёртвые (unused): **23**.
- Уверенность D: **1989**, D?: **248** (11.1%).
- Все файлы `out/*.json` проходят `validate.py --all` (OK).

## 2. Таблица покрытия

| Мутатор | Полей | D | D? | Числовые | Поведение/unused |
|---|---:|---:|---:|---:|---:|
| AbyssalEchoesMutator | 31 | 28 | 3 | 29 | 2 |
| AcidFlaskMutator | 23 | 18 | 5 | 21 | 2 |
| AerialAssaultMutator | 27 | 26 | 1 | 23 | 4 |
| AnomalyMutator | 27 | 27 | 0 | 24 | 3 |
| ArcaneAscendanceMutator | 23 | 21 | 2 | 22 | 1 |
| AssembleAbominationMutator | 40 | 33 | 7 | 36 | 4 |
| AuraMutator | 3 | 3 | 0 | 2 | 1 |
| AuraOfDecayMutator | 36 | 35 | 1 | 34 | 2 |
| AvalancheMutator | 12 | 10 | 2 | 10 | 2 |
| AvalancheSnowballMutator | 21 | 21 | 0 | 21 | 0 |
| BallistaMutator | 27 | 27 | 0 | 25 | 2 |
| BlackHoleMutator | 28 | 28 | 0 | 20 | 8 |
| BladestormThrowMutator | 33 | 33 | 0 | 27 | 6 |
| BloodSplatterMutator | 5 | 5 | 0 | 5 | 0 |
| BoneArmorMutator | 1 | 1 | 0 | 1 | 0 |
| BoneCurseMutator | 36 | 36 | 0 | 31 | 5 |
| BurningDaggerConeMutator | 1 | 1 | 0 | 1 | 0 |
| BurningDaggerMutator | 1 | 1 | 0 | 1 | 0 |
| BurstOfFlameMutator | 6 | 6 | 0 | 5 | 1 |
| CaltropsMutator | 6 | 6 | 0 | 6 | 0 |
| ChaosBoltsMutator | 41 | 28 | 13 | 40 | 1 |
| CharacterMutator | 30 | 29 | 1 | 30 | 0 |
| ChthonicFissureMutator | 35 | 16 | 19 | 33 | 2 |
| CinderStrikeMutator | 33 | 29 | 4 | 30 | 3 |
| ClawTotemMutator (прошлая волна) | 1 | 1 | 0 | 1 | 0 |
| ColdTempestMutator (прошлая волна) | 6 | 6 | 0 | 6 | 0 |
| DancingStrikesMutator | 33 | 32 | 1 | 32 | 1 |
| DarkBladeMutator | 8 | 8 | 0 | 7 | 1 |
| DarkQuiverBuffMutator | 17 | 17 | 0 | 14 | 3 |
| DarkQuiverMutator | 10 | 10 | 0 | 10 | 0 |
| DeathSealExitMutator (прошлая волна) | 1 | 1 | 0 | 0 | 1 |
| DeathSealMutator | 34 | 34 | 0 | 31 | 3 |
| DecoyMutator | 10 | 8 | 2 | 9 | 1 |
| DetonateDecoyMutator (прошлая волна) | 1 | 1 | 0 | 1 | 0 |
| DetonatingArrowMutator | 39 | 39 | 0 | 36 | 3 |
| DevouringOrbMutator | 31 | 31 | 0 | 28 | 3 |
| DisintegrateMutator | 31 | 31 | 0 | 31 | 0 |
| DiveBombMutator | 29 | 29 | 0 | 27 | 2 |
| DivineBoltMutator (прошлая волна) | 2 | 2 | 0 | 2 | 0 |
| DivineFlareMutator (прошлая волна) | 6 | 5 | 1 | 6 | 0 |
| DrainLifeMutator | 35 | 34 | 1 | 33 | 2 |
| DreadShadeMutator | 35 | 33 | 2 | 31 | 4 |
| DreamslashMutator | 31 | 31 | 0 | 29 | 2 |
| EarthquakeSeekingCrackMutator | 13 | 1 | 12 | 13 | 0 |
| EarthquakeSlamMutator | 33 | 33 | 0 | 30 | 3 |
| EnchantWeaponMutator | 25 | 25 | 0 | 25 | 0 |
| EnchantWeaponPassiveMutator | 2 | 2 | 0 | 2 | 0 |
| EntanglingRootsMutator | 34 | 33 | 1 | 31 | 3 |
| ErasingStrikeMutator | 29 | 29 | 0 | 28 | 1 |
| EterrasBlessingMutator | 26 | 26 | 0 | 23 | 3 |
| ExplosiveTrapMutator | 43 | 43 | 0 | 39 | 4 |
| FalconStrikeMutator | 1 | 1 | 0 | 1 | 0 |
| FalconryMutator | 86 | 20 | 66 | 81 | 5 |
| FinalExplosionMutator | 9 | 9 | 0 | 8 | 1 |
| FireAuraMutator | 4 | 4 | 0 | 4 | 0 |
| FireShieldMutator | 16 | 16 | 0 | 15 | 1 |
| FireballExplosionMutator | 3 | 3 | 0 | 3 | 0 |
| FireballMutator | 25 | 25 | 0 | 20 | 5 |
| FirebrandMutator | 24 | 24 | 0 | 24 | 0 |
| FlameReaveMutator | 30 | 30 | 0 | 27 | 3 |
| FlameRushMutator | 38 | 13 | 25 | 35 | 3 |
| FlameWardMutator | 19 | 19 | 0 | 15 | 4 |
| FlayBloodExplosionMutator | 25 | 25 | 0 | 24 | 1 |
| FlayMutator | 47 | 45 | 2 | 43 | 4 |
| FlurryMutator | 30 | 30 | 0 | 28 | 2 |
| FocusMutator | 25 | 25 | 0 | 23 | 2 |
| ForgeStrikeMutator | 26 | 24 | 2 | 19 | 7 |
| FrenzyTotemMutator | 26 | 18 | 8 | 21 | 5 |
| FrostClawMutator | 29 | 27 | 2 | 22 | 7 |
| FrostWallMutator | 40 | 39 | 1 | 35 | 5 |
| FuryLeapMutator | 26 | 24 | 2 | 23 | 3 |
| GatheringStorm1Mutator | 1 | 1 | 0 | 0 | 1 |
| GatheringStorm2Mutator | 1 | 1 | 0 | 0 | 1 |
| GatheringStormMutator | 35 | 31 | 4 | 34 | 1 |
| GhostflameMutator | 40 | 40 | 0 | 34 | 6 |
| GlacierMutator | 25 | 22 | 3 | 21 | 4 |
| GlyphOfDominionMutator | 38 | 31 | 7 | 34 | 4 |
| HailOfArrowsMutator | 33 | 33 | 0 | 28 | 5 |
| HammerThrowMutator | 30 | 27 | 3 | 22 | 8 |
| HarvestMutator | 27 | 23 | 4 | 26 | 1 |
| HealingHandsMutator | 31 | 28 | 3 | 27 | 4 |
| HeartseekerMutator | 27 | 24 | 3 | 24 | 3 |
| HolyAuraMutator | 10 | 9 | 1 | 7 | 3 |
| HolyFlameBurstMutator | 2 | 2 | 0 | 2 | 0 |
| HungeringSoulsMutator | 23 | 22 | 1 | 22 | 1 |
| IceBarrageMutator | 40 | 24 | 16 | 36 | 4 |
| IceSpiralMutator | 5 | 5 | 0 | 5 | 0 |
| IceThornsMutator | 31 | 29 | 2 | 26 | 5 |
| IceWardMutator | 14 | 14 | 0 | 14 | 0 |
| InfernalShadeMutator | 32 | 30 | 2 | 27 | 5 |
| JavelinMutator | 33 | 31 | 2 | 28 | 5 |
| JudgementMutator | 35 | 33 | 2 | 27 | 8 |
| LethalMirageDamageMutator | 5 | 5 | 0 | 2 | 3 |
| LethalMirageMutator | 31 | 30 | 1 | 25 | 6 |
| LightTempestMutator | 7 | 6 | 1 | 7 | 0 |
| LightningBlastMutator | 33 | 33 | 0 | 27 | 6 |
| LungeMutator | 28 | 21 | 7 | 27 | 1 |
| **Итого** | **2237** | **1989** | **248** | **2005** | **232** |

## 3. Поля, влияющие на числа, и поведенческие поля

| Категория | Всего | из них `affectsNumbers=true` | D? | Что входит |
|---|---:|---:|---:|---|
| damage | 548 | 548 | 68 | урон: more/increased/added, конвертации, крит, проникающий урон, cull |
| trigger | 240 | 240 | 42 | шансы срабатывания, ренкасты, спавн объектов |
| ailment | 226 | 226 | 28 | шансы/длительность/эффект недугов, заморозка, шреды |
| behaviour | 209 | 132 | 11 | флаги режимов (канал, телепорт, наведение, цель и т.д.) |
| defence | 190 | 189 | 14 | здоровье, ward, мана, блок, сопротивления, лиф |
| buff | 181 | 181 | 20 | баффы/статы на игрока и союзников |
| cost_cooldown | 167 | 167 | 17 | мана-стоимость, кулдаун, эффективность маны, сброс КД |
| area | 124 | 122 | 19 | радиус/площадь/ширина конуса |
| speed | 94 | 94 | 6 | скорость каста/атаки, частота, скорость снарядов |
| count | 93 | 93 | 10 | число снарядов/цепей/целей/стаков |
| minion | 72 | 72 | 9 | миньоны |
| duration | 70 | 70 | 4 | длительности |
| unused | 23 | 0 | 0 | поле никогда не читается (мёртвое) |

Поведенческие поля (категория behaviour) — булевы режимы и флаги: канальный режим, телепорт/траверс, смена цели, «не наводится», «не пробивает» и т.п. Сами по себе они числа не добавляют, но переключают формулы: `affectsNumbers=true` стоит там, где режим меняет итоговые числа (стоимость, число снарядов, тип урона); `false` — чисто визуальные/целевые флаги. Остальные категории — прямые числовые модификаторы.

## 4. Системные находки

1. **Слоты `Stats.Stat` ctor.** Порядок аргументов: `(this, SP, AT, added, increased, more, byte, int)`. Float в 6-й позиции — это **MORE**, а не increased. Это приводит к расхождению тултип/код: тултип «+X% increased», а код кладёт значение в more-слот (BurstOfFlame.increasedDamage, ArcaneAscendance mark explosion, AbyssalEchoes и др.; DivineFlare per-sigil, HolyFlameBurst.finalHitDamageMultiplier и Glacier.noCritMulti — тоже MORE).
2. **Копирование в компоненты.** Многие мутаторы почти ничего не считают сами, а копируют поля в компонент на созданном объекте (Adapter / ExplosionMutator / DamageMutator / JudgementAoEMutator / FallingJavelinMutator / LightningBlastMutator и т.п.). Для Falconry, FlameRush, ChthonicFissure, FrenzyTotem, IceBarrage, ChaosBolts, Lunge значительная доля полей помечена D? именно потому, что логика компонента не прослежена.
3. **getTempStats / addsTempStats.** Всё, что приходит как `unconditionalTempStats`, копируется через `EpochExtensions.replaceWith` в `conditionalTempStats`, а дополнительные числовые поля навыка добавляются к списку в `getTempStats` (бонусы «за N», «при условии»). Планировщику достаточно воспроизвести этот список стат.
4. **Базовые AbilityMutator-поля.** `increasedManaCost` (+0xC4) и `addedManaCostDivider` (+0xC0) читаются базовым `AbilityMutator.getManaCost`, а не классом навыка, поэтому у класса они выглядят «нечитаемыми» (readers пуст). Семантика стандартная: множитель стоимости и эффективность маны.
5. **Мёртвые поля (23 шт.).** Записываются деревом, но никогда не читаются ни самим классом, ни другими:
   - `AerialAssaultMutator.aerialProwessStackOnKillChance`
   - `AuraMutator.addedFieryInquisitionStacksOnMeleeHit`
   - `AuraOfDecayMutator.chanceToGainFesterInsteadOfLose`
   - `BladestormThrowMutator.moreRadiusForAcidFlask`
   - `BladestormThrowMutator.moreDamageForAcidFlask`
   - `CinderStrikeMutator.shadowsImitateBurningDaggers`
   - `DarkQuiverBuffMutator.arrowManaConsumption`
   - `DarkQuiverBuffMutator.arrowConsumesShadows`
   - `FalconryMutator.shadowFeatherstormMoreDamage`
   - `FinalExplosionMutator.critMultiFromDodge`
   - `FlameRushMutator.runeEmbersPierce`
   - `FrostWallMutator.explosionChecksFacing`
   - `FrostWallMutator.recastManaGain`
   - `GhostflameMutator.screechAreaIncrease`
   - `GhostflameMutator.canCastStygianBeam`
   - `GhostflameMutator.dodgeRatingConvertedToArmorWhileChanneling`
   - `HailOfArrowsMutator.addedCritChance`
   - `HolyAuraMutator.addedFieryInquisitionStacksOnMeleeHit`
   - `LethalMirageDamageMutator.onlyStrikesAllies`
   - `LethalMirageDamageMutator.mirageFormForSelfDurationPerCrit`
   - `LethalMirageMutator.smokeCloudDuration`
   - `LethalMirageMutator.smokeMakesAlliesUncrittable`
   - `LethalMirageMutator.smokeCloudConvertedToPoison`
   Для части из них эффект тултипа реализован другим путём (например, бонус крита HailOfArrows идёт через `unconditionalTempStats`; `Aura/HolyAura.addedFieryInquisitionStacksOnMeleeHit` дублирует запись в `statsToApply`), для остальных — вероятно, реально не работает в 1.5.0.
6. **Расхождения тултип/код**, найденные при анализе (подробности в поле `notes`):
   - ChaosBolts: поля единичного снаряда `increasedAreaPerProjectile`/`moreDamagePerProjectile` поменяны местами относительно тултипа (0.5 в area, 0.35 в damage).
   - Glacier: `percentManaGainedOnKill` служит только условием (>0), реальная мана = maxMana * `percentManaGainedOnHit` (+0x164) — другое поле, которое дерево не пишет (проверено в ISIL). Эффект «мана за убийство» на деле не масштабируется деревом.
   - Judgement: `noHealConsecratedGround` пишется узлом «Added Critical Strike Multiplier» (побочный эффект «Consecrated Ground не лечит» не отражён в тултипе).
   - Firebrand/CharacterMutator: константа 0.12 в коде против «15%» в тултипе (moreDamageForNextMeleeAttackFromFirebrand).
   - EnchantWeapon: `zapActiveReducedCooldown` пишется 2 при тултипе 50% (формула `1 - f`, предположительно клампится).
   - DreadShade `reducedDecayRate`: знак значения противоположен формулировке тултипа.
   - AbyssalEchoes `chanceToDetonateDevouringOrbs`: тултип 25%, код 0.15 за очко.
   - BurstOfFlame/ArcaneAscendance: increased в тултипе, more в коде (п. 1).
   - Ice Barrage: значение `lessRateOfFire` в узле конуса показано как 1053609152.0 — это битовый образ float 0.4 (артефакт экстрактора).
   - InfernalShade `explosionIncreasedArea` читается только в ChaosBoltsMutator.Mutate; сам InfernalShadeMutator.Mutate его не использует.
7. **Перекрёстные читатели.** Поля мутаторов часто читаются «чужими» классами: Glacier.Mutate читает IceBarrage-поля (Glacier запускает Ice Barrage); LightningBlast.Mutate читает поля GlyphOfDominion; ChaosBolts.Mutate читает InfernalShade; Judgement/RadiantLance, FuryLeap/WerebearMaul и компоненты Hammer/Javelin. В JSON они указаны в `readers`.

## 5. Заметные механики по навыкам

(Краткие технические выводы по каждому мутатору; тексты на английском, как в `out/_notes_AL.json`.)

### AbyssalEchoesMutator

- Механика: Echoed casts (UseType 5) spawn from the rift; echo-only more damage and tripled chains. Ailments are applied via echo-object ChanceToApplyAilmentsOnHit; Abyssal Decay is modified through mutateAilmentInstance (spread, lingering, on-hit portion). Void spell on-hit damage replaces Decay when noDecay.
- Пробелы: Several ActiveAilment fields (+0x98,+0x110,+0x114) not decoded; tempBuffStats duration unknown.

### AcidFlaskMutator

- Механика: Flask hit/explosion/pool are separate objects: pool poison DPS and cluster bombs are separate DPS appliers; fire conversion removes poison chance and pools and turns poison shred/duration into fire ones. Area is additive (increasedArea+statArea) into the explosion radius.
- Пробелы: AcidFlaskExplosionMutator / pool-side effects (Ballista synergy, efficacious toxins, ally stats) not followed.

### AerialAssaultMutator

- Механика: Aerial Prowess stacks (8 s window after cast, cap 12/pt) are gained on hit/crit/kill/dodge and consumed on the next cast for health/ward, Haste+Frenzy duration and more damage; with the cross node they are also consumed by Ballista/Explosive Trap/Dive Bomb. Many nodes feed other falcon/ballista skills.
- Пробелы: Featherstorm and Umbral Blade damage are in other mutators.

### AnomalyMutator

- Механика: Anomaly teleports enemies forward in time and ailments are modified when they return (speed, reset, Time Rot/Ignite, Future Strike chances via addChance). Optional Time Wave (start and/or end) and Time Bubble / Time Lock modes spawn extra mutators with their own damage.
- Пробелы: Time Wave / Time Bubble / Time Lock internals not followed.

### ArcaneAscendanceMutator

- Механика: Arcane Ascendance is a buff: statsWhileActive/statsGainedPerSecond/WhenHit are stat lists on the buff objects; ManaDrain is a stat inside the list that noManaDrain removes and reducedManaDrain modifies. Distant-enemy hit effects use a manhattan distance threshold; mark explosion damage uses temp stats.
- Пробелы: Mark explosion object (ExplodeMarks) and Lightning Blast cost not followed. manaGainWhenHit sign/guard.

### AssembleAbominationMutator

- Механика: Assemble Abomination is configured entirely through the AssembleAbominationAdapter on the spawned Abomination: absorbed minion counts (skeleton warriors/rogues/archers capped jointly at 20, wraith/golem/zombie/mage flags and type counts) turn into stat lists, extra abilities and per-count more-damage on those abilities.
- Пробелы: Devour-side fields (health restore on devour, temp health, sacrifice, zombie devour, cooldown-ability damage) not followed into RepeatedlyAbsorbMinion.

### AuraMutator

- Механика: Generic aura object used by Holy Aura: tree stats are multiplied by the aura effect (manager increased effect + passives) and handed to allies via BuffOnAllyHit.
- Пробелы: Only the shared base class; Holy Aura specifics are in HolyAuraMutator.

### AuraOfDecayMutator

- Механика: Aura object that repeatedly applies ailments to enemies in a radius (RepeatedlyApplyAilmentsInRadius) and a self-poison; conversion flags re-tag poison to cold/physical/fire. Fester stacks give aura damage per stack. Lots of side effects (nova, bombs, bolts, heals) via separate mutators.
- Пробелы: Retaliation/bomb/nova/bolt damage in other mutators; aura damage tick itself is on the aura object.

### AvalancheMutator

- Механика: Avalanche drops big and small boulders; conversion flags switch Physical/Cold via tags and which prefab the DPS uses. Channelled mode adds shrinking area and post-channel persistence.
- Пробелы: moreDamage application; reducedFallAreaPerSecond law.

### AvalancheSnowballMutator

- Механика: Avalanche large/small boulder impacts are AvalancheAoEMutator objects that receive copies of the snowball fields. Large boulder chance gates most effects (upheaval, fissure, frozen ground, elemental, earthquake counter).
- Пробелы: Per-hit damage slots (increased vs more) inside AvalancheAoEMutator not followed.

### BallistaMutator

- Механика: Ballista is a placed minion configured through BallistaAdapter. The ballista copies fractions of the player Damage/crit/ailment stats (ratio nodes) into its own stat list; Dexterity scales placement speed, attack speed and explosion damage/area.
- Пробелы: Adapter-side behaviour of copied flags (double shot, pierce, tripwire) not followed.

### BlackHoleMutator

- Механика: Black Hole spawns a stationary or drifting object; ailments (chill/ignite/blind) are applied every 0.5 s in the radius; end shockwave and optional periodic shockwaves are separate abilities; binary star and fire conversion change the base damage types. Pull parameters are mostly behavioural.
- Пробелы: Binary star split ratio; center-distance threshold.

### BladestormThrowMutator

- Механика: Bladestorm throws up to 3 (+/- nodes) storm objects whose own BladestormMutator receives copies of these fields. Weapon-dependent bonuses (daggers/swords/2h) are computed at cast from WeaponInfoHolder. Umbral Blade consumption gives more damage and area per stack.
- Пробелы: Damage numbers of the storm hit live in BladestormMutator (not part of this batch).

### BloodSplatterMutator

- Механика: Blood Splatter is a Rip Blood spawned object; its tree fields live on the Rip Blood tree but are stored here. Area grows with minion count (cap 20); minions hit get a 4 s buff; necrotic conversion changes tags and ailments.
- Пробелы: Splatter hit damage numbers are in the Rip Blood mutator.

### BoneArmorMutator

- Механика: Only a flat +duration for Bone Armor from the Transplant tree.

### BoneCurseMutator

- Механика: Bone Curse is applied as an ailment; most nodes mutate the ActiveAilment instance (cull, max hits, always crit, damage multiplier, whenHit ailments, death procs). Damage nodes are mirrored in tooltipStats purely for the tooltip. Aura mode, prison, cursed ground, on-hit recast and minion buffs are separate modes.
- Пробелы: Instance field meanings (+0x110/+0x98) inferred from tooltips.

### BurningDaggerConeMutator

- Механика: Cinder Strike spawns burning dagger cones; the only tree field is a temp-stat list (more Damage).

### BurningDaggerMutator

- Механика: Single burning dagger; only the more Damage temp stat from the Cinder Strike tree.

### BurstOfFlameMutator

- Механика: Burst of Flame is the Flame Ward retaliation. Conversion flags convert all base fire damage and alter ailment stats; the damage node is applied as more despite its name.

### CaltropsMutator

- Механика: Caltrops is a ground object triggered by Aerial Assault or Net; its tree fields are temp-stat ailment chances, damage, and area. Crit scales with the global slow chance.
- Пробелы: Area combination formula partly hidden.

### ChaosBoltsMutator

- Механика: Chaos Bolts spawns bolts whose damage/secondary missiles are governed by ChaosBoltsDamageMutator/SecondaryMissilesMutator copies of these fields; conversion flags re-tag Necrotic->Physical and Fire->Cold. Many conditional damage nodes (vs Bleeding/Damned/Ignited/Frostbitten/Cursed) are stored on the bolt, not in temp stats. Single-projectile mode multiplies damage by (projectiles+5).
- Пробелы: Bolt-side consumers (ChaosBoltsDamageMutator, SecondaryMissiles) not followed, so several conditional damage fields are D?.

### CharacterMutator

- Механика: Player-side synergy fields: one-shot "next skill" buffs (activated by OnAbilityUse/OnHit, consumed in ApplyConditionalTemporaryStats / PopulateActorTempStatsForCast), echo-chance modifiers for the Void Knight, retaliation casts and Healing Hands extras. Each field is implemented as a temp stat added to the next cast of the target ability.
- Пробелы: Application sites of "next damage" buffs on the target skill side (ErasingStrike, VoidCleave, Judgement, ForgeStrike) not followed; moreHealthRegenWithABear has no reader.

### ChthonicFissureMutator

- Механика: Chthonic Fissure spawns a fissure object plus Tormenting Spirits; most spirit/torment nodes are copied into TormentingSpiritMutator, ChthonicFissureHitMutator or applied via mutateAilmentInstance on the Torment ailment. Conversion flags (Fire->Physical/Poison) re-tag the damage and convert ignite chance to bleed/poison chance.
- Пробелы: Spirit and hit mutator consumers not followed (hence many D?).

### CinderStrikeMutator

- Механика: Cinder Strike is a 3-strike combo (melee and bow variants); the base class holds tree fields and each strike mutator builds its own conditional temp stats. First-strike bonuses are added only to strike 1 (more damage, ignite duration, crit multi, doubled added fire). Incendiary Ammo stack system gives scaling buffs to the player.
- Пробелы: Flask/trap/explosion objects not followed; shadowsImitateBurningDaggers consumer not found.

### ClawTotemMutator

Сделан в предыдущей волне; см. `dump/work_wave3/ms/out/ClawTotemMutator.json`.

### ColdTempestMutator

Сделан в предыдущей волне; см. `dump/work_wave3/ms/out/ColdTempestMutator.json`.

### DancingStrikesMutator

- Механика: Dancing Strikes is a 4-strike combo (separate DancingStrikes1/2/4 mutators read the base fields). Many nodes give timed buffs on use of any other strike; Rhythm stacks and the third-strike Arena are additional systems. Conditional damage components are built per cast as DamageConditionalEffect entries.
- Пробелы: Strike-specific consumers partly followed; Puncture synergy not.

### DarkBladeMutator

- Механика: Iron Blade (Vengeance): ricocheting projectile; weapon-conditional temp stats (sword crit, polearm bleed duration), recent block/parry doubling, and per-ignite fire damage conditional effect.

### DarkQuiverBuffMutator

- Механика: Dark Quiver Buff is the pickup effect object of a black arrow: pickup effects (health, mana, shrouds, frenzy, shadow, ballista buffs) are applied in Mutate; black arrow stats are applied to skills via DarkQuiverMutator. arrowManaConsumption and arrowConsumesShadows on this class are dead copies.

### DarkQuiverMutator

- Механика: Dark Quiver drops black arrows over a duration; the arrow count and drop rate set the interval. Picking up an arrow empowers the next ability via applyStatsFromBlackArrow (mana cost, shadow consumption, elemental ailment chances).

### DeathSealExitMutator

Сделан в предыдущей волне; см. `dump/work_wave3/ms/out/DeathSealExitMutator.json`.

### DeathSealMutator

- Механика: Death Seal is a buff on the player (or a minion): current-health drain / delayed damage mechanics with release effects. The Wave of Death fields are copied into DeathSealWaveMutator in SetupWaveMutator; cast every second with the wave-interval node. Conversion flags convert wave necrotic damage to physical/cold and convert resistance/shred lists.
- Пробелы: Wave mutator consumers (DeathSealWaveMutator) not followed; hence the wave damage fields are D by field name only.

### DecoyMutator

- Механика: Decoy throws one (or more) decoys that explode; damage nodes are collected in finalExplosionUnconditionalTempStats and used by the explosion/DPS. Remote-detonate mode makes it a two-step combo. Cooldown/charge fields partially unresolved.
- Пробелы: addedManaCost and treeAddedCharges readers not found.

### DetonateDecoyMutator

Сделан в предыдущей волне; см. `dump/work_wave3/ms/out/DetonateDecoyMutator.json`.

### DetonatingArrowMutator

- Механика: Detonating Arrow places an arming charge; explosion parameters are written onto the explosion/charge object. Charge-up mode (channelled) adds pierce and damage per second charged. Arming time scales explosion hit damage per second armed.
- Пробелы: Explosion-side consumers not followed in detail; field-to-offset mapping done by name.

### DevouringOrbMutator

- Механика: Devouring Orb is a slow orb (or orbiting orb) that creates Void Rifts (own mutator); rift growth, abyssal orbs and void eruption are separate spawned objects. Per-second ailments are applied via RepeatedlyApplyAilmentsInRadius with interval 0.25 s.
- Пробелы: Void Rift/Abyssal Orb internals not followed.

### DisintegrateMutator

- Механика: Disintegrate is a channelled beam with a tier power-up system (tier 2/3 nodes, powerUpInterval) and Lucomancer stacks; ailments are applied per second of channelling (chance*0.5 per tick style via addChance). Many side casts (lightning blast, fire aura, orbs, fireballs) use CastAfterDuration and the ability mana cost.

### DiveBombMutator

- Механика: Dive Bomb is a falcon skill; the Falcon adapter copies most fields. Talon Blades stacks (creator buff), Crimson Shroud, shadow falcons per rogue shadow (capped by umbral blades), feather rain side casts and decoy/trap detonation.

### DivineBoltMutator

Сделан в предыдущей волне; см. `dump/work_wave3/ms/out/DivineBoltMutator.json`.

### DivineFlareMutator

Сделан в предыдущей волне; см. `dump/work_wave3/ms/out/DivineFlareMutator.json`.

### DrainLifeMutator

- Механика: Drain Life is a channelled beam (or a casted version); many fields are copied into the beam component (+0xa0.. offsets). Mana-to-health conversion node adds AcceleratingHealthDrain. Damned/contempt systems give conditional damage and defensive stacks.
- Пробелы: Beam component internals not followed.

### DreadShadeMutator

- Механика: Dread Shade is a shade attached to a minion that drains its health and gives it and nearby minions an aura (stats lists). Many nodes only toggle ailments/behaviours on the parent minion; InfernalShadeMutator reads addedMaxShades, auraStats and markedForDeath fields from this mutator.
- Пробелы: Doom Brand and decay-rate sign conventions unclear.

### DreamslashMutator

- Механика: Dreamslash is a Rogue shadow-synergy skill: casts are repeated by Rogue Shadows (UseType 6) with their own temp stats and area bonuses; Dream stacks (time, kill, elite, consumed shadows) give damage/crit; shroud ailments scale ailment chance and ward.
- Пробелы: Shadow-side behaviour (RogueShadow) not followed.

### EarthquakeSeekingCrackMutator

- Механика: Earthquake aftershocks are EarthquakeAftershockMutator objects fed with copies of these fields (also copied to the Bear minion via CopyVariablesToMinionMutator).
- Пробелы: EarthquakeAftershockMutator consumers not followed.

### EarthquakeSlamMutator

- Механика: Earthquake slam (Bear/Primalist): initial slam plus aftershock objects (EarthquakeMutator) fed by copies; triple hit recasts the slam via CreateAbilityObjectOnDeath (extra slams cost mana); noAftershocks folds aftershock damage into the slam.
- Пробелы: Aftershock consumers in EarthquakeMutator/EarthquakeAftershockMutator not followed.

### EnchantWeaponMutator

- Механика: Enchant Weapon is a timed buff; its tree stats are a player stat list while active plus proc effects on melee hits (zap, fire burst, ice shards) limited by ProcTimeTrackers that change while active.
- Пробелы: zapActiveReducedCooldown sign.

### EnchantWeaponPassiveMutator

- Механика: Enchant Weapon passive part: a list of player stats plus a player property granting Frostbite chance from Chill chance.
- Пробелы: Property 0x274 identity inferred from tooltip.

### EntanglingRootsMutator

- Механика: Entangling Roots creates a root wave object (EntanglingRootsWrapMutator) plus seeds (EntanglingRootsSeedMutator) with copied fields; many ally/minion buffs are BuffOnAllyHit components (8 s) with stat lists for specific minion abilities. UpheavalMutator reads several fields for the Upheaval interaction.
- Пробелы: Wrap/Seed mutator consumers not followed.

### ErasingStrikeMutator

- Механика: Erasing Strike (Void Knight) applies Time Rot via temp stats and creates Void Rifts / void beams. Weapon-type conditionals (2h mace/sword/axe) use WeaponInfoHolder. AbyssalEchoesMutator.Mutate reads many of these fields to run Erasing Strike through Abyssal Echoes.

### EterrasBlessingMutator

- Механика: Eterra's Blessing is a heal spell that creates a Sacred Plant (heal buff area); synergy nodes grant effects depending on the type of companion healed. Healing amount scales with the IncreasedHealing stat plus the tree increased healing.
- Пробелы: Base heal amount and HoT details not decoded.

### ExplosiveTrapMutator

- Механика: Explosive Trap throws traps that detonate through ExplosiveTrapDamageMutator / ExplosiveTrapOnGroundMutator with copied fields. Arming time, trigger radius, per-second growth and conversion-of-each-type determine the effective hit damage and area; max traps matter for Mine Field.
- Пробелы: Trap-side consumers partly followed.

### FalconStrikeMutator

- Механика: Only a flat mana cost increase for Falcon Strike.

### FalconryMutator

- Механика: Falconry is the falcon companion mutator holding the falcon-related trees (Falconry, Aerial Assault feather skills, Dive Bomb, Net synergies). Mutate copies most fields into FalconAdapter / falcon abilities; ratio fields convert player stats into falcon stats.
- Пробелы: Almost all fields are D? by name/tooltip; falcon-side consumers (FalconAdapter, feather burst, featherstorm, falcon strikes) not followed.

### FinalExplosionMutator

- Механика: Decoy final explosion: area, damage nodes via temp stats, cold conversion converts base fire damage to cold and ignite to chill, ignite stacks.

### FireAuraMutator

- Механика: Fire Aura spawned by Flame Ward; Flame Ward writes conversion flags and duration here.

### FireShieldMutator

- Механика: Fire Shield is a timed shield buff with retaliation fireballs (FireballMutator on the retaliation object) and an optional AoE damage aura. Resistances and granted damage are stats in the shield BuffParent.

### FireballExplosionMutator

- Механика: Explosion part of Fireball: penetration/crit temp stats, partial base damage conversion to lightning, crit bonus vs ignited.

### FireballMutator

- Механика: Fireball: projectile stats copied to the spawned FireballMutator; extra projectile count with halving/sequence nodes, conversion to lightning as a fraction, flamethrower channelled mode.

### FirebrandMutator

- Механика: Firebrand builds up to 4+ stacks (4 s each, duration scaled) that give per-stack stats and per-stack melee damage/crit through getTempStats; consumption by other melee attacks is configured in CharacterMutator. LightningBlastMutator reuses most of these fields for the lightning variant.

### FlameReaveMutator

- Механика: Flame Reave sends a fire wave (FireWaveMutator) that can return and cycle; Rhythm of Fire stacks (max 12) empower the cast at max; conditional damage/crit vs ignited; Firebrand stack consumption adds ignite chance.

### FlameRushMutator

- Механика: Flame Rush is a channelled dash through enemies with Rune Embers; many nodes trigger side effects (ward, ignite consumption, glyph/orbs). Damage scales with current mana (1% per 40). Conversion modes alter ailments through temp-stat conversion entries.
- Пробелы: Mutate body of Flame Rush not read; many side-effect fields D?.

### FlameWardMutator

- Механика: Flame Ward is a ward buff: ward amount = (base + additional)*(1+increased)+missing health part, optionally split over 6 ticks; its retaliation is BurstOfFlameMutator (fed by copies of retaliation fields).

### FlayBloodExplosionMutator

- Механика: Blood Eruption part of Flay (also used by Rip Blood): area grows with curses, conditional more damage vs low life/chilled/frozen, converted ailment chance/duration (bleed -> frostbite/damned/poison) through temp stats, and Blood Revelry stacks for Harvest/Rip Blood.

### FlayMutator

- Механика: Flay alternates melee hits (copied into a hit component) and a Blood Eruption; Spirit Step traversal can be removed or turned into a traversal skill. Many on-hit effects use onDetailedHit.

### FlurryMutator

- Механика: Flurry is a 3-strike melee combo (bow variant BowFlurryMutator): per-strike damage/ailment modifiers are written into separate hit components (strike 1, 2, 3); Onslaught (Adrenaline Rush) stacks give +5% more damage and other bonuses.

### FocusMutator

- Механика: Focus is a channelled mana skill: it converts mana gain into lightning damage (during channel waves and at the end), ward and haste; ailments are applied per second in a radius of 5.

### ForgeStrikeMutator

- Механика: Forge Strike: mode flags sword/spear/anvil change the forged weapon (sword 35% more attack speed, no crit; spear 100% crit multi, -35% area; anvil 20% less attack speed, stun chance and phys damage). Detonating Ground eruption added through castDetonateGround.

### FrenzyTotemMutator

- Механика: Frenzy Totem is mostly a data hand-off: Mutate copies almost every field into FrenzyTotemAdapter (aura radius, tether, damage storage, companion bonuses); the adapter logic was not followed so those are D?.
- Пробелы: FrenzyTotemAdapter behaviour not analysed.

### FrostClawMutator

- Механика: Frost Claw (Nova derived): mana cost/ward/freeze rate mechanics are in Mutate; the projectile behaviour flags (five projectiles, second/third cast, no explosion, projectile speed) are copied to the claw component; Frozen Sleeper stacks accumulate in OnMutatorUpdate.
- Пробелы: Claw component flags are not followed.

### FrostWallMutator

- Механика: Frost Wall (also used by Abyssal Echoes): wall + two pylons; ally pass-through grants ward/mana/haste/frenzy, buffs next Glyph of Dominion/Runic Invocation, casts Flame Ward; enemy pass-through grants ward, increases pylon blast frequency; idle >= 15 s gives free cast with more damage; Fire/Lightning conversion variants.
- Пробелы: recastManaGain and explosionChecksFacing are never read (dead fields).

### FuryLeapMutator

- Механика: Fury Leap: landing buffs (added melee/spell damage 3 s, frenzy, heal, cleanse), Storm Bolts while leaping, cooldown resets on kill, Upheaval at the end; shares data with the companion version (CopyVariablesToMinionMutator) and WerebearMaulMutator.
- Пробелы: getTempStats read via ISIL only.

### GatheringStorm1Mutator

- Механика: Gathering Storm 1/2 are cast-variant subclasses of GatheringStormMutator; only the scorpion soak flag is added.
- Пробелы: All other behaviour is documented under GatheringStormMutator.

### GatheringStorm2Mutator

- Механика: Gathering Storm 1/2 are cast-variant subclasses of GatheringStormMutator; only the scorpion soak flag is added.
- Пробелы: All other behaviour is documented under GatheringStormMutator.

### GatheringStormMutator

- Механика: Gathering Storm builds Storm Stacks and expends them to cast Storm Bolts (most of the logic is in GatheringStorm1Mutator); conversions (cold/physical), melee bonuses and attunement-scaled stats go through getTempStats.
- Пробелы: Several on-hit effects (repeat on boss, 3-enemy stack, mana for stacks) read via ISIL only.

### GhostflameMutator

- Механика: Ghostflame: channelled skull; per-second ailment chances are added to a ChanceToApplyAilmentsOnHit component; channel cost = (base+added)*(1+increased)*(1+more)*(1+less); the skull can detach, move, screech and fire Marrow Shards.
- Пробелы: screechAreaIncrease, canCastStygianBeam and dodgeRatingConvertedToArmorWhileChanneling are never read.

### GlacierMutator

- Механика: Glacier casts three explosions (smallest/middle/largest) through Glacier1/2/3Mutator components; per-explosion stat lists and shared fields are copied to those components. Rime is a player buff (DoT increased + freeze rate multiplier).
- Пробелы: percentManaGainedOnKill is only a >0 gate; the mana gained uses percentManaGainedOnHit (another field) - verified in ISIL (+0x160 gate, +0x164 multiplier).

### GlyphOfDominionMutator

- Механика: Glyph of Dominion places a zone (up to 1 + additionalMaxGlyphs glyphs) that grants buffs to allies through BuffOnAllyHit and afflicts enemies through RepeatedlyApplyAilmentsInRadius; runes of Runic Invocation can be consumed (Rah/Heo/Gon). LightningBlastMutator.Mutate reads many of the same fields when Lightning Blast is cast on the glyph.
- Пробелы: Explosion component, static charge and ward-per-resistance details not followed.

### HailOfArrowsMutator

- Механика: Hail of Arrows creates an area object with RepeatedlyApplyAilmentsInRadius (0.2 s interval; chance per tick = f*0.2). Conversion flags change damage type, ailment and VFX; channelled mode changes delay/cost; advancing rectangle moves the area.
- Пробелы: addedCritChance never read (crit bonus goes through unconditionalTempStats).

### HammerThrowMutator

- Механика: Hammer Throw: the same class acts as skill mutator and as a component of each thrown hammer (many fields copied there). Zeal stacking buff stats are applied through StatBuffs on cast; spiral/nova/chain flags control projectile layout.
- Пробелы: increasedAttackSpeed/freeWhenOutOfMana read only via ISIL. centreOnCaster/spiralMovement/ignoreTerrainCollision have no tooltip writers.

### HarvestMutator

- Механика: Harvest: weapon-attack skill converting necrotic base damage (physical/cold options); curse-gated bonuses (more damage, ward, heal per Int); on-kill/on-hit triggers (Wandering Spirits, Volatile Zombie, Blood Wraith); CopyToMinionMutator copies the whole state to the Rip Blood version.
- Пробелы: Zombie/Wraith/Spirit chance are in OnKill (ISIL only).

### HealingHandsMutator

- Механика: Healing Hands copies its numbers into an adapter on the cast object (+0x138..+0x190) and applies healing/ward as ailment instances (mutateAilmentInstance); upfront healing base 100 + f, channelled base cost 10; traversal mode reuses the Shield Rush ability.
- Пробелы: Adapter-side use of the copied fields not followed.

### HeartseekerMutator

- Механика: Heartseeker: recurve mechanic (chance + dex bonus with minimum) with many OnRecurve triggers (Dark Arrow, Burning Dagger, Crimson/Dusk Shroud, Hail of Arrows extension, Dragonfang stacks); conversions to cold/fire via convertBaseDamage.
- Пробелы: Arrow component fields (+0x38, +0x3c, minimum chance) not followed.

### HolyAuraMutator

- Механика: Holy Aura: passive aura plus active boost; most bonuses are entries of statsToApply (including HolyAuraStack ailment chances), so few dedicated fields exist.
- Пробелы: addedFieryInquisitionStacksOnMeleeHit never read; finalHitDamageMultiplier read only by DPS calculation.

### HolyFlameBurstMutator

- Механика: Holy Flame Burst (released by Holy Aura): small mutator with one MORE-damage stat and an area increase.

### HungeringSoulsMutator

- Механика: Hungering Souls: CopyVariablesToMinionMutator copies the full state into the spawned soul (offsets +0x130..+0x19c); damage bonuses per minion go through getTempStats; kill/hit triggers (mana, ward, cast when hit) in OnKill/whenHit.

### IceBarrageMutator

- Механика: Ice Barrage launches frostbolts with fire interval = 1/((1-less)*(1/base)) / (1+increased); Mutate copies many numbers into the barrage component (+0x128..+0x188). GlacierMutator.Mutate also reads several Ice Barrage fields (Glacier launches Ice Barrage). Ice Shield is a separate mutator receiving iceShield* fields.
- Пробелы: Barrage component use of copied fields not followed (D?).

### IceSpiralMutator

- Механика: Ice Spiral fields come from the Frost Claw tree: per-spiral buffs for Glacier / Snap Freeze are Stats.AbilityPropertyStat entries; double cast is a roll in onCast.
- Пробелы: Property ids 0x2f / 0xa6 (Glacier / Snap Freeze) identified from tooltips, not enum.

### IceThornsMutator

- Механика: Ice Thorns (Thorn Burst): projectile volley or Thorn Shield barrier (thornShieldMode); shield numbers copied to a component (+0x130..+0x1a4); proc-based extras (Sundering Thorns, Thorn Trail/Totem) in OnHit/OnKill.
- Пробелы: Tree entries have no tooltip text for this skill; semantics from code and node names. delayWindow and damageAndFreezeBuffStacks marked D?.

### IceWardMutator

- Механика: Ice Ward builds a ward buff from stat entries (block, armour, ward retention/regen, mana regen); Frost Nova is cast periodically via CastAfterDuration with numbers written into FrostNovaMutator.
- Пробелы: Stat ids (0x35, 0x39, 0x27, 0x12, 0x10) inferred from node names.

### InfernalShadeMutator

- Механика: Infernal Shade: shades attach to enemies/minions (or wait on the ground) and apply per-second ailment chances through RepeatedlyApplyAilmentsInRadius (chance = f * interval). Chaos Bolts (ChaosBoltsMutator.Mutate) reads the same fields to build its shade variant.
- Пробелы: explosionIncreasedArea is read only by ChaosBoltsMutator.Mutate.

### JavelinMutator

- Механика: Javelin: base throw with distance/pierce scaling, optional lightning conversion; modes Javelin Rain (falling javelins, optionally flag with healing aura and smite) and a lunge combo; fields are copied into JavelinSpearBurstMutator, FallingJavelinMutator and FlameTrailMutator.
- Пробелы: moreAttackSpeed/addedManaCost read via ISIL only.

### JudgementMutator

- Механика: Judgement hits via JudgementAoEMutator and creates Consecrated Ground (or Holy Eruption/aura); most tree numbers are written into ConsecratedGroundMutator through the mutatorManager at fixed offsets.
- Пробелы: Tooltip/code mismatch: noHealConsecratedGround is written by a crit-multiplier node. eruptionMoreDamage read only by the DPS calculation.

### LethalMirageDamageMutator

- Механика: Damage-side component of Lethal Mirage; only the ally-buff fields are used here, the other two are consumed through LethalMirageMutator.

### LethalMirageMutator

- Механика: Lethal Mirage: 6 mirages (+additional) are created by CastAfterDuration; per-mirage numbers are copied to LethalMirageDamageMutator; self/ally mirage-form buffs are bleed chance + dodge rating for 4 s.
- Пробелы: smokeCloudDuration, smokeMakesAlliesUncrittable, smokeCloudConvertedToPoison are never read. lightningConversion only enters addsTempStats.

### LightTempestMutator

- Механика: Light Tempest (Tempest Strike lightning variant): small mutator, penetration scales with typed minions and uncapped resistance through getTempStats; area is a collider radius multiplier.
- Пробелы: chanceToGainGladiatorOfLagonStack via ISIL only.

### LightningBlastMutator

- Механика: Lightning Blast: base chains = tree chains + recent-cast chains (min(recent, f+2)); Mutate copies nearly all fields into a LightningBlastMutator component on the cast object. Glyph of Dominion and Firebrand add chains through glyphMut (+0x144) and firebrandMut (+0x158).

### LungeMutator

- Механика: Lunge: path hit with distance scaling (damage/area/cull/haste/smite at up to 10 m); the distance-scaled numbers and conversions are copied into the lunge component (+0x130..+0x160); cooldown recovery via onAbilityUse of other melee abilities.
- Пробелы: Lunge component logic for the copied fields not followed.

## 6. Список D? (поля с пониженной уверенностью)

Всего 248. Причина — копирование в непрослеженный компонент, чтение только через ISIL либо вывод по названию/тултипу.


**AbyssalEchoesMutator**
- `abyssalDecayNotConsumedOnHit` — Meaning of ActiveAilment+0x98 (removeOnHit) inferred from tooltip "Abyssal Decay Lingers" and trigger-on-hit mechanics.
- `damageOnHitPercentageOfDoTDamage` — +0x110 semantics (on-hit portion/DoT portion) not followed. Tooltip: "DoT -> damage on hit, 5% damage portion".
- `tempBuffStats` — Buff duration constant not recovered.

**AcidFlaskMutator**
- `poisonPoolStatsToGiveAllies` — Pool-side application not followed (AcidFlaskExplosionMutator).
- `poisonPenentrationPerPoisonResistance` — Exact stat value computation (uncapped resistance accessor) not shown in Ghidra excerpt.
- `poisonPoolEfficaciousToxinChance` — Pool-side effect not followed.
- `poisonChanceToGiveBallistaOnHit` — Application to Ballista not followed.
- `poisonDamageToGiveBallistaOnHit` — Application to Ballista not followed.

**AerialAssaultMutator**
- `featherstormAtEnd` — Featherstorm damage is in the falcon skills; not followed.

**ArcaneAscendanceMutator**
- `manaGainWhenHit` — Applied only when 0 < f in the guard ("0.0 < f"), so the negative tree values never reach it; guard likely makes the node tooltip incorrect (-1 mana drained when hit has 
- `frozenKillsProliferationDuration` — Target selection geometry (cone test) partially visible only.

**AssembleAbominationMutator**
- `auraStats` — Aura application code (adapter Start/aura) not followed.
- `increasedRadiusForMeleeSkills` — Application path (Maths call) dropped by Ghidra; presumably Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease.
- `additionalPercentHealthRestoredOnDevour` — Consumer (RepeatedlyAbsorbMinion/adapter) not followed.
- `percentMaxHealthGainedAsTempHealthOnDevour` — Consumer not followed.
- `dontDevourZombies` — Consumer in RepeatedlyAbsorbMinion not followed.
- `moreDamageForAbilitiesWithCooldowns` — Application site not located.
- `sacrificeInsteadOfDevour` — Consumer not followed.

**AuraOfDecayMutator**
- `coldRetaliationChanceWhenHit` — Retaliation ability details not followed.

**AvalancheMutator**
- `reducedFallAreaPerSecond` — Exact shrink law lives in the spawned object (CastAtRandomLocation..); only the constants are visible.
- `moreDamage` — Real hit damage application not located; the tree node probably also adds a Damage more Stat (not a header field).

**ChaosBoltsMutator**
- `chanceToFearOnHit` — Consumer not followed.
- `increasedSpread` — Consumer not followed; behaviour mostly area of impact.
- `moreHitDamageToBleeding` — Consumer not followed.
- `moreHitDamageToDamned` — Consumer not followed.
- `moreHitDamageToIgnited` — Consumer not followed.
- `moreHitDamageToFrostbitten` — Consumer not followed.
- `chanceForDoubleDamageToChilled` — Consumer not followed.
- `chanceForGreatlyIncreasedArea` — Consumer not followed.
- `chanceToConsumeMana` — Consumer not followed.
- `zombieIncreasedArea` — Consumer not followed.
- `zombieTempStats` — Consumer not followed.
- `moreDamageToCursed` — Consumer not followed.
- `recastChanceOnHitCursed` — Recast cost (80% mana per tooltip) not decoded.

**CharacterMutator**
- `moreHealthRegenWithABear` — No reader located; written by the Summon Bear tree.

**ChthonicFissureMutator**
- `percentManaRefundedIfCursedEntityNearBy` — Refund computation partly dropped.
- `igniteStackSpreadOnTormentToEnemiesCount` — Spirit-side mechanics not followed.
- `chaosBoltCastInsteadOfSpiritChance` — Chaos Bolt side not followed.
- `tormentChainOnDeathChance` — Chance that a dying tormented enemy releases a Spirit (mutateAilmentInstance on the Torment ailment).
- `spiritFireResShredStacks` — Fire/physical/poison resistance shred stacks applied by spirits (copied to TormentingSpiritMutator).
- `consumesInfernalShades` — Spirit/Shade interaction not followed.
- `moreDamageToTormentPer3PercentUncappedNecroticResistance` — Torment damage increases with uncapped Necrotic resistance (mutateAilmentInstance).
- `moreDamageToBossAndRareEnemies` — More damage to bosses and rare enemies (doubled if cursed); applied to the fissure/torment/spirit (copied to TormentingSpiritMutator, read by FlameWhipMutator and mutateA
- `spiritTargetsPlayer` — Buff values (3, 15) are constants in TormentingSpiritMutator.
- `castVolatileZombie` — Zombie side not followed.
- `appliesDamageOnHit` — Amount in the hit mutator.
- `spellDamageGainedPer2PercentOfIgniteBleedOrPoisonChance` — Fissure hit mutator adds Added Spell Damage = f per 2% of the player Ignite/Bleed/Poison chance (matching the converted ailment).
- `increasedStunChancePer2PercentOfIgniteBleedOrPoisonChance` — Increased stun chance per 2% of the ailment chance (5% per 2%).
- `applyAcidSkin` — Fissure hit applies Acid Skin to the player (+20% crit chance from Acid Skin per tooltip).
- `ailmentStackSpreadOnImpactToEnemiesCount` — Number of enemies Ignite/Bleed/Poison stacks spread to on fissure impact.
- `igniteChanceOnHitAsIgniteChancePerSecond` — Player ignite chance on hit is converted into ignite chance per second on the fissure (fraction f).
- `igniteChancePerSecond` — Flat ignite chance per second applied by the fissure.
- `increasedTormentDuration` — Increased Torment duration (copied to the Torment ailment application).
- `tormentMoreDamageToIgnitedPoisonedOrBleedingEnemies` — Torment deals more damage to enemies that are ignited, poisoned or bleeding (mutateAilmentInstance).

**CinderStrikeMutator**
- `firstStrikeFlaskChance` — Flask damage not followed.
- `flasksReplacedWithTraps` — The Volatile Flask is replaced with an Explosive Trap (AddFlaskChanceToObject, OnKill).
- `firstStrikeMoreCritChancePerIgnite` — Application on explosion object not followed.
- `maxFirstStrikeMoreCritChancePerIgnite` — Cap of the crit chance bonus (0.09 per point).

**DancingStrikesMutator**
- `morePunctureDamageOnNextUse` — Application is in the Puncture mutator (not followed).

**DecoyMutator**
- `addedManaCost` — Reader not found in this slice.
- `treeAddedCharges` — Probably consumed through getAddedCharges of base AbilityMutator via a different field; 07c В§1 covers cooldown fields.

**DivineFlareMutator**
- `divineFlareChanceToCleanseAilmentsPerSigil` — CleanseAilmentsOnHit field meanings (+0x38 count, +0x58 flag) inferred from names; utility only.

**DrainLifeMutator**
- `noMana` — Header has no writer line for this field; value from after_loop acc[r12].

**DreadShadeMutator**
- `markNearbyMinionsWithDoomBrand` — Doom Brand effect application not followed.
- `increasedDoomBrandEffect` — Doom Brand application not followed.

**EarthquakeSeekingCrackMutator**
- `aftershockChanceToSlow` — Application inside EarthquakeAftershockMutator not followed.
- `aftershockIncreasedRadius` — Aftershock-side formula not followed (probably Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease).
- `aftershockChanceToRepeat` — Chain rules not followed.
- `aftershockChanceToDropSnowball` — Chance that an aftershock hit casts a Boulder (snowball), 5 mana consumption.
- `aftershockIncreasedSlowDuration` — Increased slow duration of aftershocks.
- `aftershockIncreasedStunChance` — Increased stun chance of aftershocks.
- `aftershockConvertToDoT` — Aftershock hits become damage over time (convertToDoT).
- `aftershockIncreasedDuration` — Aftershock duration (also read by BearAdapter.adapt).
- `aftershockChanceToBlind` — Chance to blind enemies with aftershocks.
- `igniteInsteadOfArmorShred` — Fire mode: base damage -> Fire, Armour Shred -> Ignite chance in the aftershock.
- `spellConversion` — Melee attack becomes a spell with physical -> lightning conversion; +80 initial slam spell damage and +20 aftershock spell damage (the +20 is in aftershock_unconditionalT
- `frostbiteInsteadOfArmorShred` — Cold mode: base damage -> Cold, Armour Shred -> Frostbite chance in the aftershock.

**EntanglingRootsMutator**
- `increasedArea` — Reader not located.

**FalconryMutator**
- `acidFlaskManaCostRatio` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `chanceFalconGainFlaskChargeOnPlayerFlaskUse` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `prioritiseTargetsCloseToPlayer` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `prioritiseSummonerTargetLocation` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `ailmentChanceFromPlayerEffectivenessRatio` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `throwsFeatherKnives` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `featherKnivesCooldownFromPlayerThrowingAttackSpeedRatio` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `highestIncreasedDamageTypeFromPlayerRatio` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `falconTypedCritMultiOnCrit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `reducedFalconStrikeCooldownPercentageOnHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `secondHitScreeches` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `slowStacksWithScreech` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `frailtyStacksWithScreech` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `protectiveScreechOnPlayerLowLife` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `screechFears` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `addedHits` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `cullPercentage` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `razorWingsMode` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `increasedWidthPerIncreasedAreaRatio` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreDamageIfUsedAreaSkillRecently` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `extraHitsFromKills` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `extraHitsFromRareBossHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `chanceToAddHitFromRareBossHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `healthPerTotalAttributesOnKillOrRareBossHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `manaPerTotalAttributesOnKillOrRareBossHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `falconWakeDurationOnMarkConsume` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `consumingFalconMarkRecoversFalconStrikeCooldown` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `slowChancePerSecondInFeatherstorm` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `shadowFeatherstormBossOrRare` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreDamagePerSecondFeatherstormActive` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `increasedFeatherstormDuration` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `blackArrowPerSecondInFeatherstormChance` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `poisonConversionForFeatherstorm` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreDamagePerAerialProwessStackConsumed` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreDiveBombDamageFromAerialProwess` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreFeatherBurstDamageToHighHealth` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreFeatherstormDamageToHighHealth` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `throwingDamageFeatherBurstStatsRatio` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `throwingDamageFeatherstormStatsRatio` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreFeatherBurstDamageToRareAndBoss` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreFeatherstormDamageToRareAndBoss` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `featherRainTargets` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `increasedDiveBombRadius` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `diveBombStats` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `giveCreatorTalonBladesOnDiveBombOrFeatherRainHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `increasedMoveSpeedWith5TalonBladeStacks` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `detonateExplosiveTraps` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `increasedAreaForTriggeredExplosiveTraps` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `maxCrimsonShroudStacksPerUseOfDiveBomb` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `consumeBleedStacksWithDiveBomb` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreDamagePerBleed` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `reducedDelayWithDiveBomb` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `shadowFalconCount` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `duskShroudChanceIfShadowFalconHits` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `shadowFalconsBounceInSmokeBombChance` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreShadowFalconDamagePerUmbralBlade` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `dualWieldingWeaponStatPercentage` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `moreAilmentDamagePer10PercentStunChance` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `manaRestoreOnRareOrBossFirstHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `traversalRemainingCooldownRestoreOnRareOrBossFirstHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `detonateDecoys` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `decoyMoreDamageOnHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `decoyIncreasedAreaOnHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `diveBombAddedManaCost` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `increasedSmokeBombDurationOnHit` — Consumed in the falcon adapter/spawned falcon objects (not followed).
- `featherRainArmorShredChance` — Consumed in the falcon adapter/spawned falcon objects (not followed).

**FlameRushMutator**
- `castGlyphOfDominionAtTargetLocation` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `volcanicOrbTravelsWithYou` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `buffOverflowDurationPercentage` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `wardAtEnd` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `castStaticOrbBackwards` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `applyBrandOfSubjugationWhileTravelling` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `brandOfSubjugationMoreDamagePerChillChance` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `frenzyAtEndDuration` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `castRunicInvocationAtEnd` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `moreDamageIfCastFireballInSameDirection` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `increasedRadiusIfCastFireballInSameDirection` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `manaRefundIfCastFireballInSameDirection` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `runicBurstOnFireballHitDuringFlameRush` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `fireResShredStacksOnHitWhileChannelling` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `wardPerIgnitedEnemyYouTravelThrough` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `consumeYourIgnitesOnEnemiesYouTravelThrough` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `wardGainedPerIgniteConsumed` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `consumedIgnitesDealDamageImmediately` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `moreIgniteDamagePerInt` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `increasedRadiusOnFrostWallHit` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `moreCritChanceOnFrostWallHit` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `maxRuneEmberCount` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `additionalRuneEmbersOnFlameRushUse` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `increasedRuneEmberGenerationSpeed` — Mutate body not followed in detail; semantics from the node tooltips and field name.
- `chanceToGainRuneEmberOnFlameRushKill` — Mutate body not followed in detail; semantics from the node tooltips and field name.

**FlayMutator**
- `chanceEveryOtherMeleeExplodeOnElite` — ISIL-only read; effect inferred from tooltip.
- `chanceToMarrowShardsOnDirectCrit` — ISIL-only read; effect inferred from tooltip.

**ForgeStrikeMutator**
- `increasedCooldownRecoverySpeed` — Increased cooldown recovery speed read in increasedCooldownRecoverySpeedFromMutator (ISIL only).
- `stunChanceFromTree` — Stun chance read in getTempStats via ISIL only (added as increased stun chance temp stat).

**FrenzyTotemMutator**
- `chanceToCastEterrasBlessingPerSecond` — Copied to FrenzyTotemAdapter; adapter rolls each second to cast Eterra's Blessing for allies in range (adapter not followed).
- `damageStoredByTotem` — Fraction of damage taken by the totem stored (copied to adapter).
- `totemDamageTakenThresholdToRelease` — Threshold of max health in damage taken at which the totem releases the stored damage (adapter).
- `playerDamageTakenStoredByTotem` — Fraction of damage taken by the player stored by the totem (adapter).
- `AoEHealOnCompanionRevival` — Healing nova of f when a companion is revived (adapter).
- `addedSabertoothSwipes` — Extra Sabertooth swipe(s) per cast (adapter).
- `wolfHowlIncreasedCritChance` — Wolf Howl grants increased crit chance to the player (adapter.wolfHowlIncreasePlayerCritChance).
- `scorpionNovaIncreasedArea` — Increased area of the scorpion venom nova (adapter).

**FrostClawMutator**
- `addedManaCost` — Added mana cost read in getAddedManaCost via ISIL only (tree: -2 per point, +4/+2 for extra casts).
- `elementalNovaAtTargetChance` — Chance for an Elemental Nova at the target, copied to the claw component (+0x14c).

**FrostWallMutator**
- `fireballChanceOnhit` — Chance for a Fireball when an enemy passes through (OnHit via ISIL only; Fireball mana cost evaluated).

**FuryLeapMutator**
- `unconditionalTempStats` — Temp stats of Fury Leap (crit multi, stun chance/duration, ...), returned by getTempStats (ISIL); copied to the companion mutator.
- `moreDamagePerDistance` — Damage more per meter travelled: distance-scaled value (max distance = (range bonus + 1) * 8) multiplied by f; applied through the AoE hit (branch details not followed).

**GatheringStormMutator**
- `stormBoltRepeatChanceOnBossOrRare` — Chance for the Storm Bolt to be cast again against a boss or rare (OnHit via ISIL only).
- `addedManaCost` — Flat mana cost added (+6 for ranged staff bolt), read in getAddedManaCost via ISIL only.
- `manaConsumptionForAdditionalStacks` — Mana consumed when the chance roll for additional stacks succeeds (OnHit via ISIL).
- `chanceForAdditionalStormStackWith3EnemiesHit` — Chance for an additional Storm Stack when 3+ enemies are hit (OnHit via ISIL).

**GlacierMutator**
- `chanceForSuperIceVortex` — Greater Ice Vortex chance, copied to each Glacier component (OnHit via ISIL) and counted in the DPS applier.
- `moreDamageToBosses` — More damage vs rares/bosses copied to each Glacier component (component not followed).
- `moreDamageAgainstChilled` — More hit damage vs chilled copied to each Glacier component (Double Chill node).

**GlyphOfDominionMutator**
- `moreExplosionDamagePerSlow` — Copied to GlyphOfDominionExplosionMutator.moreDamagePerSlow (explosion component not followed); LightningBlastMutator.Mutate also reads it.
- `glyphsExplodeAtSameTime` — Glyphs explode at the same time when two glyphs exist (checked with glyph count == 1).
- `moreDoTPerArmorShredUpTo14Buff` — Conditional more DoT per armour shred stack (cap 14%) added to the BuffOnAllyHit buffs (Stats.ConditionalMoreDamageStat 0x12, DoT).
- `wardPerSecondPerUncappedResistance` — Ward per second granted to allies on the glyph, scaled with uncapped resistances (BuffOnAllyHit buff built from f; formula details not followed).
- `grantsAcceleratingStaticCharges` — Static charges gained at an accelerating rate (gainingStaticCharges, totalChargesGainedPerInterval).
- `grantedLightningBlastChains` — Lightning Blast cast on the glyph gets +f chains (read by LightningBlastMutator.Mutate, getChannelCost).
- `manaConsumedByLightningBlast` — Mana added to the Lightning Blast channel cost on the glyph (LightningBlastMutator.getChannelCost).

**HammerThrowMutator**
- `increasedAttackSpeed` — Added in getIncreasedCastSpeed (read via ISIL only).
- `freeWhenOutOfMana` — noManaCost and getIncreasedManaCost: hammer throw costs no mana when out of mana (actor mana check via ISIL).
- `noPierce` — Hammers do not pierce; with no chains and no chain history the pierce is removed; copied to the hammer component.

**HarvestMutator**
- `necroticShred` — getTempStats / addsTempStats adds a Necrotic resistance shred chance stat (read via ISIL in CopyToMinionMutator).
- `increasedBleedEffect` — Read in getTempStats (adds a temp stat; tooltip: +50% physical penetration with bleed with Self Bleed node; exact stat not decoded).
- `zombieChanceOnKillOrRareBossHit` — Chance for a Volatile Zombie on kill or rare/boss hit (OnKill read via ISIL).
- `chanceToSummonBloodWraith` — Chance for a Blood Wraith on kill (OnKill via ISIL); bloodWraithStats applied.

**HealingHandsMutator**
- `moreDamageToVoidEnemies` — Conditional more damage vs Void enemies, built into ChanceToApplyAilmentsOnHit.ConditionalAilment/condition (ISIL-level detail).
- `moreDamageToUndeadEnemies` — Conditional more damage vs undead (Fear Undead node).
- `moreCastSpeed` — Copied to the adapter and applied in mutateUseSpeed (ISIL).

**HeartseekerMutator**
- `punctureOnRecurveChance` — Copied to the arrow component (+0x3c): chance for a Puncture per recurve after the arrow dies.
- `moreAilmentDamageOnRecurve` — Copied to the arrow component (+0x38): DoT more damage per recurve (8 stacks max per tooltip).
- `minimumRecurveChance` — Minimum recurve chance written to the arrow component (Mutate).

**HolyAuraMutator**
- `finalHitDamageMultiplier` — Only read by getDPSAppliersForDPSCalculation (final hit of the Flame Burst); the in-game hit multiplier is applied elsewhere.

**HungeringSoulsMutator**
- `increasedDamageWith3Minions` — getTempStats via ISIL: more damage when exactly three minions are present.

**IceBarrageMutator**
- `freezeRateMultiplierPerCastOfFrostbolt` — Copied to the barrage component (+0x148): freeze rate multiplier per Frostbolt cast (ice shard), up to freezeRateMultiplierPerCastMaxStacks.
- `freezeRateMultiplierPerCastMaxStacks` — Copied to the barrage component (+0x14c): cap of the per-cast freeze rate stacks.
- `chanceToCastFrostNovaOnHit` — Copied to the barrage component (+0x154): chance to cast Frost Nova on hit (nova radius from increasedFrostNovaRadius).
- `moreDamagePerCastOfFrostbolt` — Copied to the barrage component (+0x140): more damage per frostbolt cast, cap moreDamagePerCastMaxStacks.
- `moreDamagePerCastMaxStacks` — Copied to the barrage component (+0x144): cap of the per-cast damage stacks.
- `noHoming` — Copied to the barrage component (+0x164): shards do not home.
- `chanceToMakePiercingProjectile` — Copied to the barrage component (+0x138): pierce chance.
- `chanceToApplyForstbiteIfPiercingProjectile` — Copied to the barrage component (+0x13c): frostbite chance on piercing shards.
- `increasedDelayBeforeFire` — Copied to the barrage component (+0x130): delay before each shard fires.
- `increasedProjectilSize` — Copied to the barrage component (+0x168): projectile size.
- `extraProjectiles` — Copied to the barrage component (+0x184): extra frostbolts per volley.
- `addedMaxAngle` — Copied to the barrage component (+0x180): cone width in degrees.
- `splinterOnHit` — Copied to the barrage component (+0x188): ice shards shatter on hit.
- `moreCritToFrozenTargets` — Copied to the barrage component (+0x12c): crit chance more vs frozen.
- `moreDamageToFrozen` — Copied to the barrage component (+0x128): more damage vs frozen.
- `moreFreezeRateToNoDelayBolts` — Copied to the barrage component (+0x170): Ice Burst freeze rate more.

**IceThornsMutator**
- `delayWindow` — Enum DelayWindow (0/1/2) selecting the projectile delay/pattern in Mutate and OnHit (value 2 used for the re-cast on hit).
- `damageAndFreezeBuffStacks` — Stacking buff on cast: stack index cycles up to f (byte), a 4 s buff with stacks is added to the player (damage and freeze rate per tree text).

**InfernalShadeMutator**
- `increasedCastSpeed` — mutateUseSpeed (read via ISIL) and ChaosBoltsMutator.Mutate (Chaos Bolts casting the shade).
- `explosionIncreasedArea` — Read only by ChaosBoltsMutator.Mutate; InfernalShadeMutator.Mutate does not read it (area may be applied in ShadeExplosionMutator via ISIL, not followed).

**JavelinMutator**
- `moreAttackSpeed` — mutateUseSpeed (read via ISIL only).
- `addedManaCost` — Added mana cost, read in getAddedManaCost via ISIL (tree +2 per point, -3, +10 for rain).

**JudgementMutator**
- `increasedRadiusConsecratedGround` — Consecrated Ground radius increase (read in Mutate via ISIL only).
- `eruptionMoreDamage` — Read only by getDPSAppliersForDPSCalculation (Holy Eruption more damage); the in-game effect is carried by eruptionStats (same tree node writes both).

**LethalMirageMutator**
- `lightningConversion` — Flag read only in addsTempStats; the conversion amount comes from percentBaseDamageConvertedToLightning.

**LightTempestMutator**
- `chanceToGainGladiatorOfLagonStack` — Chance for a Gladiator of Lagon stack when the tempest is cast (Mutate read via ISIL only).

**LungeMutator**
- `immobilizeOnHitDuration` — Copied to the lunge component (+0x134): immobilize duration on the final hit.
- `increasedHitAreaPerDistanceTraveled` — Copied to the lunge component (+0x148): max area bonus reached at 10 m distance.
- `moreDamagePerDistanceTraveled` — Copied to the lunge component (+0x14c): max damage bonus at 10 m distance.
- `cullEnemiesBelowHealthThresholdAtMaxDistanceTraveled` — Copied to the lunge component (+0x150): cull threshold at max distance.
- `physicalPenPerEnemyHit` — Copied to the lunge component (+0x158): physical penetration per enemy hit.
- `chanceToCast3SmitesOnArrivalAtMaxDistanceTraveled` — Copied to the lunge component (+0x160): chance for 3 Smites on arrival at max distance.
- `shieldBashAtEnd` — Copied to the lunge component (+0x138): Shield Bash after the lunge (shieldBashMut; written by the Shield Bash tree).

## 7. Пробелы и ограничения

- Логика компонентов, в которые копируются поля, не разбиралась: FrenzyTotemAdapter, компоненты FlameRush, Ice Barrage component, Lunge component, HealingHands adapter и др. (см. D?).
- Поля, читаемые только через ISIL (например, `getAddedManaCost`, `mutateUseSpeed`, части `OnHit/OnKill`), помечены D?, если константы/ветви не удалось подтвердить прямым чтением.
- Значения `per_point`/`flat` берутся из `trees`/`tree_node_stats` как есть; в `formula` они приведены лишь как справка и не заменяют данные из `skill_node_effects.json`.
- Идентификаторы Stat/AT/SP в части мест (ward per second 0x5c, block 0x1d/0x35, mana drain 0x39 и т.п.) выведены из названий узлов; сверка с enum выполнялась там, где enum известен (`sp_enum.json`).
- Список пробелов по каждому мутатору — в `out/_notes_AL.json` (поле `gaps`), он продублирован в разделе 5.
