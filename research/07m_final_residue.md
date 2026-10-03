# 07m. Финальный остаток: 46 значений (33 поля мутаторов + 13 эффектов уников)

Итог: **все 46 переведены в D** (`dump/work_wave4/out_final_residue.json`). Неразрешённых и мёртвых полей не осталось.
Способ: глубокие трассы (`traces_deep/`), ISIL/Ghidra конкретных методов, `readconst` для констант, поиск потребителей по имени метода и по смещению.

## Что нашли по мутаторам

Прямой эффект (читатель найден до конца):
- **AssembleAbomination.percentMaxHealthGainedAsTempHealthOnDevour** — при поглощении миньона (`AbominationConsumeMinionsMutator.OnMutatorUpdate`): `MoreStat(Health, f)` на 8 с, лимит `ProcTimeTracker(5, 8.0)`.
- **ChaosBolts.moreHitDamageToIgnited** — `DamageConditionalEffect(HasAilmentConditional(Ignite=1), DamageEffectMoreDamage(f))`, множитель `(1+f)`.
- **CharacterMutator.moreHealthRegenWithABear** — MORE HealthRegen `+f`, пока жив медведь (`HasLivingMinionOfType(summonBear=56)`).
- **ChthonicFissure.spiritFireResShredStacks** — `AilmentChance(Shred, added=f)` у духов; шанс > 1 даёт гарантированные стаки (`AilmentApplication.Apply`). Ailment: Fire 42 / Poison 28 при `poisonConversion` / Physical 73 при `physicalConversion`.
- **ChthonicFissure.moreDamageToBossAndRareEnemies** — условные MORE: boss/rare `(1+f)`; если актор «cursed» — `2f` и без доп. условия, иначе дополнительно `CursedConditional` (цель проклята) `(1+f)`.
- **DreadShade.increasedDoomBrandEffect**, **SmokeBomb.increasedSmokeBladesEffectiveness** — аргумент `increasedEffect` в `RepeatedlyApplyAilmentsInRadius.addChance` (Ghidra теряет float-аргументы, брали из ISIL). У SmokeBomb значение = очки−1, то есть эффект = базовый × очки.
- **Falconry**: ailmentChance…Ratio (копия шансов игрока на 11 ailment-ов × f), extraHitsFromRareBossHit (до f доп. ударов, шанс 10% на удар по rare/boss), manaPerTotal…(мана = сумма атрибутов × f за убийство и за удар по rare/boss, лимит 10 за 3 с), moreShadowFalconDamagePerUmbralBlade (`min(лезвия,25)·f`).
- **FlameRush**: wardAtEnd (флэт вард при смерти объекта), frenzyAtEndDuration (длительность Frenzy ровно f секунд: `increasedDuration=(f-base)/base`), chanceToGainRuneEmberOnFlameRushKill (шанс +1 Rune Ember за убийство).
- **GlyphOfDominion.glyphsExplodeAtSameTime** — флаг связывания двух глифов (`DestroyObjectOnDeath`) и расчёта расстояния между ними.
- **HammerThrow.increasedAttackSpeed** (аддитивный increased, `getIncreasedCastSpeed`), **Javelin.moreAttackSpeed** (`mutateUseSpeed = (1+f)·S`, f=-0.2).
- **HealingHands.moreDamageToUndeadEnemies** — `ActorConditional(EType=Undead)`.
- **ManaStrike.leechWhileNotFullMana** — `additionalLeech += f`, если мана < макс. на момент каста.
- **PrimalistSummonElemental.wellspringIncreasedCastSpeed** — аура: радиус 18 м, интервал 1 с, бафф 2 с, increased CastSpeed `f`.
- **RadiantLance…Per1PercentIgniteElectrifyChance** — `GetAilmentDamageModifier` для Scathing Light (144): `f·100·(ignite+electrify+…)`, множитель `ActiveAilment.damageModifier`.
- **Riposte.physPenWithBleedPerOvercappedPhysRes** — на самом деле **AilmentEffectStat** (increased effect), а не пенетрация: `(uncappedRes−0.75)·f`. Подмеченная странность игры: при Fire-конверсии ailment id = 9 (TimeRot), а не Ignite.
- **ShadowCascade.daggerShadowDaggerChance** — шанс «Shadow Dagger» на попадании Dagger Throw; для UseType=Shadow(6) берётся соседнее поле 0.2/очко.
- **ShatterStrike.recastChanceWith2h** — при двуручном оружии и оригинальном касте: шанс `f` на +2 бесплатных рекаста.
- **SprigganForm.maxValeSpirits** — только лимит для проки «Vale Spirit при смерти тотема».
- **SprigganVines.increasedSize** — `SizeManager.increaseSize(f)` (f=0.88 в дереве) и `addedMeleeRange=f·0.75`.
- **SummonMage.increasedNecroticMorterRadius** — радиус в «sqrt-пространстве»: `R=sqrt((1+f)²+A)−1`, то есть +20% area за очко аддитивно с area мага.
- **TeleportReturn.statsAtEnd** — список статов как баффы на `4.0·(1+increasedBuffDuration)` с (`BuffCreatorOnDeath`).
- **Tornado.increasedBuffDuration** — длительность `2.0·(1+f)` (в Ghidra «дважды» — это база 2 с, а не двойное применение).
- **DancingStrikes.morePunctureDamageOnNextUse** — только гейт (`f>0` ставит флаг); величина из `PunctureMutator.moreDamageAfterDancingStrikes`.

Зеркальные поля (planner-only, `affectsNumbers=false`, чтобы не считать дважды):
- **HolyAura.finalHitDamageMultiplier** (реальный эффект: `HolyFlameBurstMutator.getTempStats`, MORE Damage `f`),
- **Judgement.eruptionMoreDamage** (реальный: `eruptionStats`),
- **ShieldRush.delayedEndRushMoreDamage** (реальный: `delayedEndRushStats`).

## Уники (13)

- **Через `CharacterMutator.onPotionUse`**: pp248 (мана = `min(метеоры за 4 с · pp, 200)`).
- **Через `ApplyConditionalDefenses`/`ProtectionClass.ApplyDamage`**: pp525 — слот f8 «extra endurance» при задержанном уроне > 10% макс. HP; важная деталь: в режимах 0/1 блок работает только при базовом endurance > 0. pp590 — `canSuperCrit`: при шансе крита > 100% шанс суперкрита `min(c−1, 0.5)`, +3.0 к crit multi до умножения на (1+moreCritMulti). pp660 — три MORE DamageTaken (Necrotic/Void/Poison), `pp·Attunement/10` («Apathy» = испорченный Attunement; код читает атрибут 4 без проверки порчи).
- **pp309** — вопреки прежней заметке, **находится в switch**: ставит `enduranceMode=1`; стоимость маны в «mana before health» становится `(1−e)/5` на единицу урона.
- **HealthPotion** (не `CharacterMutator`): pp190 (heal = потерянное HP · pp · крит), pp507 (флаг, если значение > 0.1; шанс крита зелья = глобальный crit chance + 5%), pp528 (`critMult = 2 + critMultiStat·pp`), pp551 (`min(Σpp, 0.75)` не потратить заряд), pp630 (второй ролл, если зелье восстановило ≥ 20% макс. HP), pp665 (`currentHP −= currentHP·pp·N`, N — зелья за последние 4 с).
- **Downed** (компаньоны): pp126 (радиус воскрешения `2.5·(1+pp)` м), pp127 (скорость `0.167·(1+pp)`/с).

## Что остаётся неразрешённым и почему

Ничего критичного. Оговорки:
- Численные эффекты ailment-ассетов (Doom Brand, Smoke Blades, Shadow Dagger, Scathing Light-тик) лежат в ассетах, не в коде; в коде подтверждён только путь значения (`increasedEffect`, шанс).
- `GetSumOfAttributeValues` (виртуальный слот +0x2d8 в Falconry) определён по имени переопределения `Stats`, а не по прямой метке в Ghidra.
- Ghidra местами роняет float-аргументы; все такие места перепроверены по ISIL.
