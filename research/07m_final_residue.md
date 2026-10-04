# 07m. Final Residue: 46 Values (33 Mutator Fields + 13 Unique Effects)

Result: **all 46 translated to D** (`dump/work_wave4/out_final_residue.json`). No unresolved or dead fields remain.
Method: deep traces (`traces_deep/`), ISIL/Ghidra of specific methods, `readconst` for constants, consumer search by method name and by offset.

## What We Found in Mutators

Direct effect (reader found to end):
- **AssembleAbomination.percentMaxHealthGainedAsTempHealthOnDevour** — on minion consumption (`AbominationConsumeMinionsMutator.OnMutatorUpdate`): `MoreStat(Health, f)` for 8 s, limit `ProcTimeTracker(5, 8.0)`.
- **ChaosBolts.moreHitDamageToIgnited** — `DamageConditionalEffect(HasAilmentConditional(Ignite=1), DamageEffectMoreDamage(f))`, multiplier `(1+f)`.
- **CharacterMutator.moreHealthRegenWithABear** — MORE HealthRegen `+f`, while bear alive (`HasLivingMinionOfType(summonBear=56)`).
- **ChthonicFissure.spiritFireResShredStacks** — `AilmentChance(Shred, added=f)` on spirits; chance > 1 gives guaranteed stacks (`AilmentApplication.Apply`). Ailment: Fire 42 / Poison 28 on `poisonConversion` / Physical 73 on `physicalConversion`.
- **ChthonicFissure.moreDamageToBossAndRareEnemies** — conditional MORE: boss/rare `(1+f)`; if actor «cursed» — `2f` without extra condition, else additionally `CursedConditional` (target cursed) `(1+f)`.
- **DreadShade.increasedDoomBrandEffect**, **SmokeBomb.increasedSmokeBladesEffectiveness** — argument `increasedEffect` in `RepeatedlyApplyAilmentsInRadius.addChance` (Ghidra loses float-args, taken from ISIL). SmokeBomb value = points−1, so effect = base × points.
- **Falconry**: ailmentChance…Ratio (copy of player chances for 11 ailments × f), extraHitsFromRareBossHit (up to f extra hits, 10% chance on rare/boss hit), manaPerTotal… (mana = sum of attributes × f on kill and on rare/boss hit, limit 10 per 3 s), moreShadowFalconDamagePerUmbralBlade (`min(blades,25)·f`).
- **FlameRush**: wardAtEnd (flat ward on object death), frenzyAtEndDuration (Frenzy duration exactly f seconds: `increasedDuration=(f-base)/base`), chanceToGainRuneEmberOnFlameRushKill (chance +1 Rune Ember on kill).
- **GlyphOfDominion.glyphsExplodeAtSameTime** — flag binding two glyphs (`DestroyObjectOnDeath`) and distance calc.
- **HammerThrow.increasedAttackSpeed** (additive increased, `getIncreasedCastSpeed`), **Javelin.moreAttackSpeed** (`mutateUseSpeed = (1+f)·S`, f=-0.2).
- **HealingHands.moreDamageToUndeadEnemies** — `ActorConditional(EType=Undead)`.
- **ManaStrike.leechWhileNotFullMana** — `additionalLeech += f` if mana < max at cast time.
- **PrimalistSummonElemental.wellspringIncreasedCastSpeed** — aura: 18 m radius, 1 s interval, 2 s buff, increased CastSpeed `f`.
- **RadiantLance…Per1PercentIgniteElectrifyChance** — `GetAilmentDamageModifier` for Scathing Light (144): `f·100·(ignite+electrify+…)`, multiplier `ActiveAilment.damageModifier`.
- **Riposte.physPenWithBleedPerOvercappedPhysRes** — actually **AilmentEffectStat** (increased effect), not penetration: `(uncappedRes−0.75)·f`. Odd detail: Fire-conversion ailment id = 9 (TimeRot), not Ignite.
- **ShadowCascade.daggerShadowDaggerChance** — «Shadow Dagger» chance on Dagger Throw hit; for UseType=Shadow(6) take neighbor field 0.2/point.
- **ShatterStrike.recastChanceWith2h** — with two-handed weapon on original cast: chance `f` for +2 free recasts.
- **SprigganForm.maxValeSpirits** — only limit for «Vale Spirit on totem death» procs.
- **SprigganVines.increasedSize** — `SizeManager.increaseSize(f)` (f=0.88 in tree) and `addedMeleeRange=f·0.75`.
- **SummonMage.increasedNecroticMorterRadius** — radius in «sqrt-space»: `R=sqrt((1+f)²+A)−1`, so +20% area per point additive with mage's area.
- **TeleportReturn.statsAtEnd** — list of stats as buffs for `4.0·(1+increasedBuffDuration)` with (`BuffCreatorOnDeath`).
- **Tornado.increasedBuffDuration** — duration `2.0·(1+f)` (in Ghidra «twice» — this is base 2 s, not double apply).
- **DancingStrikes.morePunctureDamageOnNextUse** — only gate (`f>0` sets flag); magnitude from `PunctureMutator.moreDamageAfterDancingStrikes`.

Mirror fields (planner-only, `affectsNumbers=false`, not to double-count):
- **HolyAura.finalHitDamageMultiplier** (real effect: `HolyFlameBurstMutator.getTempStats`, MORE Damage `f`),
- **Judgement.eruptionMoreDamage** (real: `eruptionStats`),
- **ShieldRush.delayedEndRushMoreDamage** (real: `delayedEndRushStats`).

## Uniques (13)

- **Via `CharacterMutator.onPotionUse`**: pp248 (mana = `min(meteors in 4 s · pp, 200)`).
- **Via `ApplyConditionalDefenses`/`ProtectionClass.ApplyDamage`**: pp525 — slot f8 «extra endurance» on delayed damage > 10% max HP; important detail: in modes 0/1 block only works if base endurance > 0. pp590 — `canSuperCrit`: at crit chance > 100% super crit chance `min(c−1, 0.5)`, +3.0 to crit multi before (1+moreCritMulti) multiply. pp660 — three MORE DamageTaken (Necrotic/Void/Poison), `pp·Attunement/10` («Apathy» = corrupted Attunement; code reads attribute 4 without corruption check).
- **pp309** — contrary to prior note, **in switch**: sets `enduranceMode=1`; mana cost in «mana before health» becomes `(1−e)/5` per damage unit.
- **HealthPotion** (not `CharacterMutator`): pp190 (heal = lost HP · pp · crit), pp507 (flag if value > 0.1; potion crit chance = global crit chance + 5%), pp528 (`critMult = 2 + critMultiStat·pp`), pp551 (`min(Σpp, 0.75)` don't spend charge), pp630 (second roll if potion restored ≥ 20% max HP), pp665 (`currentHP −= currentHP·pp·N`, N — potions in last 4 s).
- **Downed** (companions): pp126 (resurrection radius `2.5·(1+pp)` m), pp127 (speed `0.167·(1+pp)` per s).

## What Remains Unresolved and Why

Nothing critical. Caveats:
- Numeric ailment asset effects (Doom Brand, Smoke Blades, Shadow Dagger, Scathing Light-tick) in assets, not code; code only confirms value path (`increasedEffect`, chance).
- `GetSumOfAttributeValues` (virtual slot +0x2d8 in Falconry) defined by override name of `Stats`, not direct Ghidra label.
- Ghidra drops float-args in places; all such places re-checked against ISIL.
