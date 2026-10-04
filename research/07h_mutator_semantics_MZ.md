# 07h. Semantics of Skill Mutator Fields M–Z (Last Epoch 1.5.0)

Data: `research/data/game/mutator_field_semantics_MZ.json` (collected by `dump/work_wave3/mz/merge.py --write` from `mz/out/<Mutator>.json`).
Record format: `mutator, field, offset, declaredIn, semantic, formula, affectsNumbers, category, readers, confidence, notes, trees, nodes`.
Here `f` in formulas — field value written by skill tree (`flat + per_point * p`); `p` — allocated points.

## 1. Coverage

| Metric | Value |
|---|---|
| Mutators (groups from `mz/groups.json`) | 121, all have output file; `merge.py`: bad = [], missing = {}, extra = {} |
| Records (fields written by trees) | 2581 |
| Confidence `D` (code read, formula obtained) | 2371 |
| Confidence `D?` (part inferred from name/tooltip or reader not found) | 210 (list in §6) |
| `affectsNumbers = true` | 2490 |
| `affectsNumbers = false` (pure behavior: visuals, flags without numeric effect, ability swap, dead fields) | 91 |

Categories (field count): damage 483, proc 313, buff 226, behaviour 208, conversion 202, defence 188, mana 168, ailment 156, minion 146, area 140, speed 111, projectile 77, duration 69, cooldown 51, debuff 32, other 11.

Heaviest mutators: ProfaneVeil 48, RunicInvocation 47, Runebolt Fire/Cold/Lightning 46/45/45, TempestStrike Cold/Phys/Light 41/41/38, Warcry 41, Static 37, StaticOrb 37, Transplant 37.

Method. For each mutator: Ghidra slice (`ms/slices/<M>.txt`), reader method analysis, if needed ISIL (`ms/fn.py --isil`) and constants `tools/readconst.py`. Rules: no subagents, no Ghidra/AssetRipper, no UI.

## 2. What Affects Numbers vs. What's Behavioral

* Numeric (2490): damage/area/speed/cost/duration multipliers, chances, resist/penetration, added stats. Most affect through three channels:
  1. direct fields copied to adapter/component (summon, totem, shockwave etc);
  2. `getTempStats` / `addsTempStats` (list `unconditionalTempStats` + «derived» stats: per charge, per minion, per Intelligence etc);
  3. conditional effects `DamageConditionalEffect` (HasAilmentConditional / LowHealthConditional / CursedConditional) with `DamageEffectMoreDamage[PerAilmentStack]`.
* Behavioral (91): `hourglass`, `shotgun`, `traversalTagRemovedFromTree`, `coldTag`, `visualColdConversion`, `backflipOnUse`, `increasedReturnSpeed`, ability-swap flags (`convertHuman…OnUse`), dead fields (§4) etc.
* List fields `List<Stat>` (160: `statList`, `*TempStats`, `*Stats`) — «containers»: numeric meaning set by tree nodes (in JSON field `nodes`/`trees`), mutator just places list in component. For planner matters WHERE list applies (summon, totem, aura, player buff, next cast).

## 3. Notable Mechanics and Patterns

### 3.1 Speed: «Increased» vs. «More»
* Additive `getIncreasedCastSpeed()` (sums with rest of increased): Snap Freeze, Spirit Plague, Tornado (`increasedCastSpeed`), Transplant, Vengeance, Volcanic Orb (`increasedCastSpeed`), Wandering Spirits, Umbral Blades (`increasedAttackSpeed`), Spriggan Healing Totem (`increasedSummonSpeed`).
* Multiplicative `mutateUseSpeed` (behaves as more/less): Multishot, Shatter Strike, Shadow Cascade, Shield Throw, Multistrike (from part 1), Summon Volatile Zombie (`increasedCastSpeed`, `* (1+f)`), Summon Wraith (`increasedCastSpeed`), Thorn Totem (`increasedSummoningSpeed`), Tornado (`moreCastSpeed`), Volcanic Orb (`moreCastSpeed`), Tempest Strike (`increasedAttackSpeed`: `(1+f)*useSpeed`), Umbral Blades (`lessAttackSpeed`: `(1-f)*useSpeed`), Werebear Charge (`(1-less)*(1+inc)`), Upheaval (`lessAttackSpeedForTotems` and `noAttackSpeedScaling` — divide by stat Attack Speed), Storm Crow (`teleportSummonerToTarget`: use speed ×0.75).
* Practical consequence: field named `increasedAttackSpeed`/`increasedCastSpeed` is NOT always additive. Look at reader (`getIncreasedCastSpeed` or `mutateUseSpeed`). Tooltip «+X% Cast Speed» above actually «more» in two cases.
* Multishot: arrow speed shortens lifetime, so range doesn't change (verified in part 1).

### 3.2 Area and Radius
* General form: `radius = sqrt((1+f)^2 + statArea) - 1` (`Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease`), where `statArea` — additive Increased Area for skill. Trees write into field already `sqrt(1 + k*p) - 1` (Snap Freeze, Surge, Swipe, Tornado, Transplant, Wandering Spirits, Werebear Maul etc), i.e. 4 points of «+20% Area» give `sqrt(1.8)-1`, not 0.8.
* Exceptions (additive «area» no sqrt in field): Void Cleave `increasedArea` (sums with `statArea` inside `GetTotalIncreasedArea`, sqrt after), Warpath, Warcry, Wandering Spirits (`increasedRadius` — radius multiplier, `increasedDamageRadius` — sqrt-form).
* Picture «exactly one field read per ISIL»: Snap Freeze, Shield Throw, Radiant Lance radius call function without args in Ghidra; argument (field) visible only in ISIL (marked `D?` where ISIL not opened).

### 3.3 Cooldown: «Field Plus Field»
`increasedCooldownRecoverySpeedFromMutator` in many mutators (Transplant, Teleport base, Volatile Reversal base, Void Cleave, Wandering Spirits, Shurikens) prints in Ghidra as `field + field + …`. Second addend — field of base `AbilityMutator` (+0xF8), not double-count (verified ISIL on Reap, pattern matches).

### 3.4 Values «Raw Bits» in Tree
Storm Orbs node in Tornado writes `moreCastSpeed = 3192704256.0`. This is `0xBE4CCCCD` — bit representation of float `-0.2`, i.e. -20% (exporter output int-bits). Account when reading tree `value`: numbers like 31927…, 1.17965e+06 — artifacts, not real values.

### 3.5 Tooltip ↔ Code Divergences
* Rune Ember: Cold conversion converts Fire→Cold (source type 1), tooltip says Lightning→Cold.
* Soul Feast: result `increasedWardGenerated` after loop is -0.35 instead of -50% in tooltip.
* Sacrifice: DoT bonus in code `more`, not `increased` as tooltip; Rip Blood: cap damage-per-minion — 20 minions (effective cap `f*20`).
* Marrow Shards: base health cost 0.09 (ISIL verified).
* Tornado: channel cost in code 6.0 (0x40c00000), tooltip 5/s (unreconciled).
* Sonic Wave, Snap Freeze, Soul Feast: some numbers (buff duration 4 s etc) from tooltip, not code (marked).
* Swarmblade Spin: added damage per locust = `N * (15 + f)`, 15.0 — constant 0x41700000 (Ghidra shows only 15; ISIL confirms field +0x138). Slicer reported `readers=[]` due to lost float-arg.

### 3.6 Readers in Base Classes (Slicer Reports `readers=[]`)
Field declared in base class, read there: Rive (BaseRive), Runebolt Fire/Cold/Lightning (RuneboltMutator), Swarmblade Armblade Slash 1/2/3 (SwarmbladeArmbladeSlashMutator), Umbral Blades 1/2/3 (BaseUmbralBladesMutator), Tempest Strike Cold/Light/Phys (TempestStrikeMutator, 35 of 41 fields), Teleport/TeleportReturn (TeleportBaseMutator), Volatile Reversal/Return (VolatileReversalBaseMutator), plus `addedManaCostDivider` (+0xC0) and `increasedManaCost` (+0xC4) in nearly all mutators — these are `AbilityMutator` fields, read by base `getAddedManaCostDivider`/`getIncreasedManaCost`.

### 3.7 Trees Writing to Foreign Mutators
* Multistrike → Void Cleave: «Void Cleave Consumes Stacks For More Damage» writes to `VoidCleaveMutator` fields (`moreDamagePerMultistrikeStack`, `increasedAreaMultistrikeStackPerStack`); live reader — Void Cleave, `MultistrikeMutator.voidCleaveConsumesStacks` is dead (Void Cleave on cast consumes ALL Multistrike stacks: `multistrikeMut+0x198`).
* Teleport → Transplant: all `Teleport*` fields read by `TransplantMutator.Mutate` (cross-class), form and numbers same as `TeleportBaseMutator`.
* Static → Lightning Blast: Static fields copied to `LightningBlastMutator` (charge, arc range, shock per charge).
* Warpath ↔ Void Cleave (`moreDamageWithVoidCleaveAfterWarpath`, `minDurationOfWarpathForVoidCleaveBuff`), Swipe → Werebear Swipe/Bear, Warcry → Werebear Roar, Thorn Totem tree → Spriggan Healing Totem / Swarmblade Hive (`castsThorns`), Spriggan Form → Spirit Thorns, Storm Bolt ↔ Scorpion (`scorpionStormBoltSoak`: live reader StormBolt).

### 3.8 Specific Numeric Findings
* Static: movement gives `(1+f)*5` charges/s (×2 with double); discharge: range `×(1 + f + charges*perCharge/10)`, shock/Haste = `floor(charges/50)*k`, auto-zap >80 charges; Static Orb: `addedManaCostMaxManaPercentage` = `min(100, maxMana*f)`.
* Spriggan/Thorn Totem: Freeze `15*(1+0.05*Attunement)`; totem ring radius 2.3 (0x40133333); `thornAddedDuration` — plus seconds after multiplier.
* Storm Bolt: mana cost `min(10, mana*f)`, damage bonus `min(3.0, mana*f/10)`; Storm Totem: spell lightning per shock-chance `((chance+retaliation)/0.1)*f`.
* Skeleton: limit = `3 + passives + f` (halfSkeletons halves); Wraith: max `6 + f + mgr`, interval `0.5*(1-f)`.
* Void Cleave: `moreMeleeDamagePerBleed` capped `maxMoreMeleeDamagePerBleed`; Ravaging Aura +duration per enemy up to 10 s.
* Smite: conversions fire→lightning (+electrify) and fire→void (+time rot), mode `freeAtZeroMana` (zero mana cost 0, no heal/Fissure); Surge: Dormant Energy via `getTempStats`.
* Umbral Blades: crit multi `min(20, blades)*f`, Dusk Shroud damage `min(20,stacks)*f`.

## 4. Dead / Probably Unused Fields (No Reader)

| Mutator.Field | Comment |
|---|---|
| MultistrikeMutator.voidCleaveConsumesStacks | effect in VoidCleave (see 3.7) |
| NetMutator.moreFalconDamageToNetted | no readers in mutator or 8 related files |
| PrimalistSummonElementalMutator.noCooldown | no reader in slice |
| ProfaneVeilMutator.increasedDurationUsingSceptre | doesn't use `GetTotalDurationModifier` |
| RadiantLanceMutator.increasedAreaWith3DivineEssences | radius call with lost args (possibly live, unconfirmed) |
| RingOfShieldsMutator.potionsHealShieldsToo | not traced outside class |
| ShatterStrikeMutator.recastChanceWith2h | possibly read via computed offset |
| ShurikensMutator.pierceConvertedToCritMulti | flag without reader, behavior via `ricochetAmount>0` |
| SigilsOfHopeMutator.divineFlare* (4 fields) | copies; real effect in DivineFlareMutator |
| SmokeBombMutator.increasedSmokeBladesEffectiveness | not read in mutator |
| SparkChargeExplosionMutator.coldConversion | effect if any in ManaStrike |
| SprigganHealingTotemMutator / SwarmbladeSummonHiveMutator.increasedSummoningSpeed | live — ThornTotem.mutateUseSpeed |
| SummonScorpionMutator.scorpionStormBoltSoak | live — StormBoltMutator |
| SummonSkeletonMutator.chanceToResummonOnDeath | no reader |
| SynchronizedStrikesMutator.extraTemporaryMaxShadows | no reader |

## 5. ISIL Notes by Coordinator Request

### 5.1 Manifest Armor — «Non-Functioning» Nodes
In `ManifestArmorMutator.Mutate` (ISIL) fields `useShield` (+0x145), `useWeapon` (+0x144), `whirlwindMode` (+0x18C), `canCharge` (+0x18D), `tauntChance` (+0x190) only COPIED to `ManifestedArmorAdapter` (bytes +0x5C…+0x5F and float +0x60: shieldMode, swordMode, whirlwind, canCharge, taunt) — no numeric logic in mutator itself. Additionally: `canCharge` adds ExtraAbility Charge (reference +0x1E0, cooldown 8.0 s by constant 0x184561FFC), `useShield`/`useWeapon` only in `baseTypeMatch` (copy equipment stats). `addsMinionFireTag` (+0x146) read only in `getMinionDisplayTags` (adds Fire tag to minion; +2 fire damage itself via `statList`). I.e. «empty» nodes — nodes where effect entirely in `ManifestedArmorAdapter`/`ManifestArmor01MeleeMutator`; another agent should parse adapter, not mutator.

### 5.2 Holy Aura — Stat Cloning ×2
`HolyAuraMutator.<Mutate>g__ApplyStatToAura|40_0` (ISIL): clones `Stat` (copy constructor 0x18169E4A0), then (1) if `useAuraStatsMultiplier` — multiplies value by `auraStatsMultiplier` (+0x13C), (2) ALWAYS multiplies by `(X + 1.0)`, where `X` from local display-class (3rd parameter), adds to aura buff. I.e. two sequential multiplicative steps, not «each stat twice»; result `value * [auraStatsMultiplier] * (1 + X)`. Neighbor field `increasedEffectFromPassives` (+0x140) not read in this function (used in other methods).

## 6. D? List (210 Entries: Mutator.Field — Reason)

Auto-generated from JSON; reasons shortened.

* **MaelstromMutator** (9)
  * `statList` — Per-stack scaling implicit in BuffParent, not traced.
  * `chanceToAutoCastOnHit` — Boss/rare restriction from tooltip.
  * `maxStacksOfLagonsSlumber` — Stack-gain timing only partly visible.
  * `moreDamageToFrozen` — Attachment block elided in Ghidra; semantics from name and Tsunami copy.
  * `moreDamageToChilled` — As moreDamageToFrozen.
  * `chanceToCastTornadoOnStackGained` — No rolling reader visible in slice, only copies.
  * `convertsEarthArmorIntoMaelstrom`
  * `scorpionMaelstromChance` — Field on MaelstromMutator but written by Summon Scorpion tree; downstream cast only partly …
  * `elementalMaelstromChance`
* **ManaStrikeMutator** (7)
  * `increasedSpellDamageOnHit` — Buff duration/stack cap not visible (args dropped by Ghidra). Tooltip: doubled on bosses/rares via increas…
  * `increasedSpellDamageOnEliteHit` — Same as increasedSpellDamageOnHit.
  * `removesCritMultiplier` — Stats_MoreStat(5,0,0xbf800000) = more CriticalMultiplier -100%; exact multiplier effect depends on crit-mu…
  * `chanceToKnockBack` — Knockback buff stat details elided.
  * `leechWhileNotFullMana` — Condition (mana below max) in elided lines; offset 0x40 interpreted as leech.
  * `coldConversion` — Tag change in getTags of base chain.
  * `staticOrbChance` — 80% doubling from tooltip and BaseMana.percentCurrentMana call.
* **ManifestArmorMutator** (7)
  * `useWeapon` — Numbers depend on weapon in gear.
  * `useShield` — Numbers depend on shield in player gear; planner needs shield item stats.
  * `flamethrowerIgniteChance` — Adapter consumer not followed.
  * `flamethrowerIncreasedDamage` — Consumer of adapter+0x54 in adapter class (not followed).
  * `whirlwindMode`
  * `canCharge`
  * `tauntChance` — Adapter consumer not followed.
* **ManifestWeaponMutator** (1)
  * `moreDamageAgainstBleedStunned` — two independent effects: target both stunned and bleeding likely gets (1+field)^2
* **MarkForDeathMutator** (1)
  * `enemiesToProliferatePoisonAndDamn` — written by Profane Veil tree node; 5.0 verified (18456202C); remainingDurationModifier arg = 0 (xmm6 zero) - e…
* **MarrowShardsMutator** (2)
  * `physLeechOnCast` — Unit scale of leech (0.3 vs +3% tooltip) suggests percent*10 or leech in different units; verify.
  * `physLeechOnKill` — Same leech unit question as physLeechOnCast.
* **MeteorMutator** (2)
  * `increasedMeteorFrequency` — Frequency only changes shower duration unless count fixed.
  * `increasedFallSpeed` — Affects only fall time (delay before damage), not damage numbers.
* **MultishotMutator** (6)
  * `increasedSlowDurationPerDexRatio` — Which attribute index 3 is (assumed Dexterity from tooltip).
  * `increasedDamageIfStationary` — increaseAllDamage adds to damageModifier (assumed additive with increasedDamage field of this mutator).
  * `maxDamageFalloffFromDistance` — Exact base of modifier (start at max) interpreted from SetMinMax(-f,0).
  * `armorShredChancePerArrow` — Constant 5 = base arrow count of Multishot assumed; Ghidra literal 5.0 not ISIL-verified.
  * `projectileUpperLimit` — Field 2 vs tooltip 3 arrows: probably limit counted as extras excluding base arrow.
  * `increasedBleedDurationPerDexRatio` — As slow.
* **MultistrikeMutator** (5)
  * `critMultiWithSpear` — Weapon check body truncated in Ghidra.
  * `voidCleaveConsumesStacks` — Grep of decomp shows only ForgeStrike/Smelters/VoidCleave referencing MultistrikeMutator; none touch +0x175 by…
  * `swordsReplacedWithSmite` — Damage of Smite (not sword) applies; planner needs Smite base data.
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
  * `channelled` — Nova cadence while channelling from channelled nova prefab, not visible in this class.
* **PhysTempestMutator** (1)
  * `penPerTypedMinion` — numberOfMinions args (1,1) likely filter type/alive; exact minion filter not resolved.
* **PrimalistSummonElementalMutator** (18)
  * `maxElementalFuryStacks` — Per-stack bonus in adapter.
  * `elementalBoltConsumesFuryStacks` — Projectile count rule from tooltip.
  * `moreDamagePerSecondSummoned` — Cap 18% from tooltip.
  * `geyserRepeatChanceFromTotems`
  * `geyserIncreasedCooldownRecoverySpeed`
  * `noCooldown` — readers=[] in slice; likely read by AbilityMutator cooldown logic elsewhere or unused. Related numeric …
  * `geyserSummonModeMoreDamage`
  * `geyserSummonModeMoreArea`
  * `geyserElementalBoltCasts`
  * `increasedHealthRegenFromIncreasedManaRegen` — Computation partly elided.
  * `wellspringAddedColdSpellDamage` — Aura application in PrimalistElementalAdapter (not followed).
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
  * `increasedDurationUsingSceptre` — readers=[] in slice and no cross-class reader; GetTotalDurationModifier doesn't use it.
  * `cooldownReductionCharges` — Per-use cooldown effect from tooltip.
  * `damnedBleedPoisonIgniteSlowChanceGainedAsIgniteChancePerSecond` — Sum of six chance terms (fVar18+fVar17+...); exact set elided in Ghidra.
  * `infernalShadeChance` — Roll site in second AoE mutator (not followed).
  * `moreDamagePerBleedChance` — Tooltip says +1% per 10% bleed chance but f=1.0 and bleedChance units unknown (fraction -> 10% chance = +10%?)…
  * `wardPer15UncappedNecroticResFromWanderingSpirit`
* **PunctureMutator** (4)
  * `poisonConvertedToBleed` — Stat(100,2,1.0) interpreted as ailment conversion.
  * `directUseShadowDaggerChance` — Ailment id 0x4F assumed to be Shadow Dagger proc ailment.
  * `moreDamageAfterDancingStrikes` — increaseAllDamage is additive generic damage modifier.
  * `physicalPenetrationPer15Mana` — SP 0x3B penetration tag uses converted type (physical or poison).
* **RadiantLanceMutator** (7)
  * `lightningPenetrationDoubledForAilments` — Tag values partly elided (uVar13=2, uVar7=0x10).
  * `lightningPenPerElectrifyStackUpTo10` — Conditional effect class elided.
  * `moreScathingLightDamagePer1PercentIgniteElectrifyChance` — Which ailment ids sum: Stats.GetAilmentChance(0x5D) + electrify + (shock) + extra fVar6 (ignite).
  * `increasedAreaWith3DivineEssences` — readers=[] ; Mutate calls GetIncreasedRadiusAfterAdditiveAreaIncrease with dropped args (xmm) - check ISIL for…
  * `reliquaryMoreHealth` — Tooltip says duration; code adds a more Health stat.
  * `electrifyChance` — Only read in ailment damage modifier; actual electrify application chance from tree stats on hits (…
  * `shockChance` — Actual shock application chance from tree stats.
* **ReapMutator** (1)
  * `moreDamagePerPercentMissingHealth` — Unit of getMissingHealthPercent (0-100 vs 0-1) not verified; tooltip says 1% per 1% missing.
* **ReaperFormMutator** (3)
  * `coldConversion` — Reap's own damage conversion (tooltip) not done here; only tag/ailment swap + AbilityObjectIndicator visuals s…
  * `poisonConversion` — tooltip '+100% poison chance / no crit' not implemented in this class
  * `physicalConversion` — cold overrides physical overrides poison
* **RingOfShieldsMutator** (4)
  * `creatorBuffStats` — Per-shield scaling in adapter (not followed).
  * `consumeForShieldThrow`
  * `fireDamageOverTimeNearby` — Damage formula in adapter/forgeFlames ability.
  * `potionsHealShieldsToo` — Not followed outside mutator class.
* **RipBloodMutator** (3)
  * `increasedDamagePerMinion` — Tooltip cap +20% damage max; code cap is 20 minions - effective cap = f*20 (0.4 at p=1).
  * `increasedHealthGained` — Combination across nodes computed in tree after-loop expression.
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
  * `consumeCooldownReducedPerRuneInvocated` — readers=[]; field only inferred from name and 20 s constant.
  * `moreElemenetalDamagePerRuneweaveStackPerArmorShredOnTarget` — Property 0x12 meaning inferred from name.
  * `increasedExplosionAreaPerUncappedRes` — Unit of resistance (fraction vs percent) not verified.
  * `physicalSpellDamagePerStrengthOfNearbyPartyMember` — Stat construction partly elided.
* **RuneboltFireMutator** (4)
  * `consumeCooldownReducedPerRuneInvocated` — readers=[]; field only inferred from name and 20 s constant.
  * `moreElemenetalDamagePerRuneweaveStackPerArmorShredOnTarget` — Property 0x12 meaning inferred from name.
  * `increasedExplosionAreaPerUncappedRes` — Unit of resistance (fraction vs percent) not verified.
  * `physicalSpellDamagePerStrengthOfNearbyPartyMember` — Stat construction partly elided.
* **RuneboltLightningMutator** (4)
  * `consumeCooldownReducedPerRuneInvocated` — readers=[]; field only inferred from name and 20 s constant.
  * `moreElemenetalDamagePerRuneweaveStackPerArmorShredOnTarget` — Property 0x12 meaning inferred from name.
  * `increasedExplosionAreaPerUncappedRes` — Unit of resistance (fraction vs percent) not verified.
  * `physicalSpellDamagePerStrengthOfNearbyPartyMember` — Stat construction partly elided.
* **RunicInvocationMutator** (2)
  * `chanceToCastCorrespondingInvocationWhenConsumedByOtherSkill` — Only visible in ISIL fragment.
  * `penetrationPer3Intelligence` — Division by 3 from tooltip; details elided.
* **SacrificeMutator** (2)
  * `moreDotDamageOnCast` — Tooltip says increased but code applies a more stat.
  * `infernalShadeNewDurationOnCast` — Duration cast to int, so 2.1 -> 2 s.
* **ScorpionCompanionAbilityMutator** (1)
  * `poolDuration` — Tooltip says Creates Poison Pool; f-1 used as increased duration of pool object base.
* **SerpentStrikeMutator** (3)
  * `lifeOnCrit` — Ghidra shows Roll() argument as this field too; probably argument-tracking artifact, actual roll chance is…
  * `slitherDodgeRatingPerOnePercentColdRes`
  * `constrictorStats` — Per-stack scaling inside elided loop.
* **ShadowCascadeMutator** (5)
  * `moreDamagePerAttackSpeed` — Stat used for S read via Stats.GetStatValue (ability tags) elided.
  * `increasedPhysicalDamageIfHitAtLeast4EnemiesRecently` — Buff duration 4 s from tooltip.
  * `daggerShadowDaggerChance` — Slice reported readers=[] because read uses base+offset arithmetic.
  * `daggerShadowDaggerChanceFromShadows` — As above.
  * `daggersPerSecond` — Interval constant 0x3ea8f5c3 = 0.33 s hard-coded; field only gates branch.
* **ShatterStrikeMutator** (3)
  * `moreDamageToHighHealth` — Doubling vs high health from tooltip.
  * `firebrandStacksToConsume`
  * `recastChanceWith2h` — readers=[]; not found in decomp slice; may read through computed offset in strike mutator.
* **ShieldBashMutator** (2)
  * `shieldWallWithRingOfShieldsActive` — Width computation partly elided.
  * `moreFireDamagePerBlockChance` — Unit: blockForDamageScaling is block chance fraction (cap 1); f=0.25 per point means +25% max with 100% block.
* **ShieldRushMutator** (2)
  * `delayedEndRushMoreDamage` — Only read by DPS tooltip; actual damage uses delayedEndRushStats (more Damage 0.45 per point).
  * `addedVoidReducedByAttackSpeed` — Attack-speed reduction not visible in slice (f added directly).
* **ShieldThrowMutator** (2)
  * `increasedLavaBurstRadius` — readers=[]; Ghidra shows call without args; assumed from Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease…
  * `colossusStacksOnHit` — Per-stack stats in elided StatBuffs.AddBuff call.
* **ShiftMutator** (1)
  * `addedTravelDamage` — Effective damage uses equipped melee weapon (itemContainersManager) - see DamageStatsHolder.calculateAdded…
* **ShurikensMutator** (3)
  * `increasedCooldownRecoverySpeed` — Name collision between derived and base field; verified by ISIL only for ReapMutator.
  * `shotgun` — No numeric effect in Mutate; tooltip-only flag.
  * `pierceConvertedToCritMulti` — Flag unused by name; behavior via ricochetAmount>0.
* **SigilsOfHopeMutator** (4)
  * `divineFlareChanceToCleanseAilmentsPerSigil` — dead copy on this mutator; effect in DivineFlareMutator (not analyzed here)
  * `divineFlareChanceToBlindPerSigil` — dead copy; real effect in DivineFlareMutator
  * `divineFlareDamagePerSigil` — dead copy; planner must model on Divine Flare
  * `divineFlareIncAreaPerSigil` — dead copy; real effect in DivineFlareMutator
* **SmeltersWrathMutator** (3)
  * `statsPerSecondCharged` — Per-second scaling inside SmeltersWrathEndMutator (not read in this slice).
  * `attackSpeedToCritChanceConversion` — Conversion body elided in Ghidra.
  * `areaStatsGiveFireDoTInstadOfChargeSpeed` — The 0.03 constant from tooltip; value argument elided in Ghidra.
* **SmokeBombMutator** (1)
  * `increasedSmokeBladesEffectiveness` — Not read in slice; likely consumed via Smoke Blades ailment instance offset (0x168) elsewhere or d…
* **SnapFreezeMutator** (2)
  * `increasedRadius` — readers=[]: argument loss in Ghidra; assumed from Maths.GetIncreasedRadiusAfterAdditiveAreaIncrease call.
  * `hourglass`
* **SonicWaveMutator** (1)
  * `coldConversion` — Conversion body read from names/tooltip; Mutate not expanded.
* **SoulFeastMutator** (3)
  * `increasedWardGenerated` — Tree after-loop value (1-x)-1 gives -0.35 whereas tooltip says -50%.
  * `consumePoisonStacks` — Consumption effect inside elided branch.
  * `increasedCastSpeed` — mutateUseSpeed body not shown in slice; assumed analogous to others.
* **SparkChargeExplosionMutator** (1)
  * `coldConversion` — Mana Strike cold conversion of spark-charge explosion, if any, must come from ManaStrikeMutator, not here;…
* **SpiritPlagueMutator** (2)
  * `moreSpiritPlagueDamage` — Is modifier «more» multiplicative with other more sources? Returned value summed across nodes.
  * `reactivateToSpread` — 0x40000000 as undefined4 raw -> float 2.0 s; Ghidra shows as integer.
* **SprigganFormMutator** (1)
  * `maxValeSpirits` — Only reader in all decomp. Tooltip '1 Vale Spirit every 5 Spirit Thorn casts / +1 max Vale Spirits' not imp…
* **SprigganHealingTotemMutator** (2)
  * `convertToCold` — Tooltip claims 30 base freeze rate and +25% freeze rate multiplier; constants in code are 15 (0x41700000); 30 …
  * `increasedSummoningSpeed` — readers=[]; see ThornTotemMutator for live reader.
* **SprigganVinesMutator** (1)
  * `increasedSize` — Tooltip says +200% size; code constant 0.88 compounding with other nodes unresolved.
* **StaticMutator** (2)
  * `unconditionalTempStats` — The 0.04*charges MoreStat (ISIL const 0.04) is built-in Static bonus; unclear whether value is fractio…
  * `addedLightningDamagePerCharge` — Tags of this added Damage stat not read from asm (edx=0, r8d=0).
* **StaticOrbMutator** (2)
  * `moreDamagePer25MaxMana` — Exact division (/25) inferred from tooltip; Ghidra elides arithmetic.
  * `chargedGroundMoreDamagePer10CritMulti` — Division by 10% inferred from tooltip.
* **StormBoltMutator** (3)
  * `lightningPenetration` — Tag of penetration (lightning vs converted type) from asm branches (uVar5=0x17 for cold conv. path), not …
  * `addedSpellDamagePer3MeleeDamageOnAxeOrMace` — Divisor 3 inferred from tooltip (divss by constant in xmm9).
  * `scorpionStormBoltSoak` — Scorpion-side effect (stacks, shock nova) in scorpion classes.
* **StormTotemMutator** (2)
  * `spellLightningDamagePer10percentShockChance` — The fVar14 term (player shock chance) elided in slice; only 0x57 ShockRetaliationChance vis…
  * `consumesOtherTotems` — Per-totem 20% bonus applied in elided consumption branch.
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
  * `healthGainedFromShadowsCreatedWithin4Seconds` — Which SP stat uses was not resolved.
  * `extraTemporaryMaxShadows` — Tree writes flat 2.0 with twoMoreShadows node.
* **TeleportMutator** (1)
  * `statsAtEnd` — Base buff duration constant at +0x164 not resolved here (base field).
* **TeleportReturnMutator** (1)
  * `statsAtEnd` — Base buff duration constant at +0x164 not resolved here (base field).
* **TempestStrikeColdMutator** (3)
  * `physPenPer5UncappedPhysRes` — Exact scaling (per 5% = division by 0.05) inferred from tooltip; arithmetic elided.
  * `coldPenPer5UncappedColdRes` — Same caveat.
  * `lightPenPer5UncappedLightRes` — Same caveat.
* **TempestStrikeLightMutator** (3)
  * `physPenPer5UncappedPhysRes` — Exact scaling (per 5% = division by 0.05) inferred from tooltip; arithmetic elided.
  * `coldPenPer5UncappedColdRes` — Same caveat.
  * `lightPenPer5UncappedLightRes` — Same caveat.
* **TempestStrikePhysMutator** (3)
  * `physPenPer5UncappedPhysRes` — Exact scaling (per 5% = division by 0.05) inferred from tooltip; arithmetic elided.
  * `coldPenPer5UncappedColdRes` — Same caveat.
  * `lightPenPer5UncappedLightRes` — Same caveat.
* **ThornTotemMutator** (1)
  * `addedManaCost` — Semantics of r12 in after-loop expression not fully certain.
* **TornadoMutator** (2)
  * `increasedBuffDuration` — Ghidra shows "fVar28 + 1.0 + fVar28 + 1.0" for actor buff duration; likely 2*(1+f) from base 2.
  * `channelledWhenDirectlyCast` — Channel cost constant 6.0 vs tooltip 5 mana per second not reconciled.
* **UmbralBlades2Mutator** (1)
  * `singleBladeDamageBonus` — Which instance gets which inferred from usedByShadow branch.
* **UmbralBlades3Mutator** (1)
  * `singleBladeDamageBonus` — Which instance gets which inferred from usedByShadow branch.
* **UmbralBladesMutator** (1)
  * `singleBladeDamageBonus` — Which instance gets which inferred from usedByShadow branch.
* **VolatileReversalMutator** (5)
  * `increasedArea` — Reader not found by slicer.
  * `moreHitDamagePerSlow` — Reader not found.
  * `increasedAttackArea` — Reader not found by slicer (declared in base).
  * `arrivalVoidBoltsReplacedByAbyssalEchoes` — Reader not found.
  * `guaranteedEchoAfterLongJump` — Reader not found.
* **VolatileReversalReturnMutator** (5)
  * `increasedArea` — Reader not found by slicer.
  * `moreHitDamagePerSlow` — Reader not found.
  * `increasedAttackArea` — Reader not found by slicer (declared in base).
  * `arrivalVoidBoltsReplacedByAbyssalEchoes` — Reader not found.
  * `guaranteedEchoAfterLongJump` — Reader not found.
* **VolcanicOrbMutator** (1)
  * `moreCastSpeed` — Ghidra shows addition of fVar1; likely decompiler artifact of multiply.

## 7. Coverage by Mutators (Fields / of them D?)

| Mutator | Fields | D? |
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

## 8. Gaps and Limitations

1. Adapter objects (`*Adapter`, e.g. `ManifestedArmorAdapter`, `HealingTotemAdapter`, `RaptorAdapter`, `SabertoothAdapter`, `ScorpionAdapter`, `SprigganAdapter`, `StormCrowAdapter`, `TempestTotemAdapter`, `UpheavalTotemAdapter`, `DecoyAdapter`, `HiveAdapter`) NOT analyzed: for fields where mutator only copies to adapter, `semantic` built on name, tooltip and copy destination (confidence `D` if destination clear, `D?` if reader not found). Numeric formula inside adapter not obtained.
2. Units: for fraction/percent (`getMissingHealthPercent`, uncapped resistance, dodge chance, leech x10) units not everywhere verified — marked `D?`. Particularly «per 5% uncapped resistance» for Tempest Strike and Rune Bolt (division by 0.05 inferred from tooltip).
3. Tooltip-only values: buff durations (3–4 s), caps («max 20 minions/stacks») sometimes from tooltip if Ghidra lost float-arg; marked in `notes`.
4. Attribute indices: 0 Strength, 1 Vitality, 2 Intelligence, 3 Dexterity, 4 Attunement — confirmed by tooltips (except marked `D?`).
5. Cross-class readers (`*Mutator.Mutate` of neighbor skills) verified by «CROSS-CLASS READS» section of slice; reading via computed offset (`base + offset`) slicer doesn't see (Shadow Cascade, Shatter Strike `recastChanceWith2h`).
6. Base AbilityMutator-fields (`addedManaCostDivider`, `increasedManaCost`, `increasedCooldownRecoverySpeed` +0xF8) considered known from block A–L/06e; here only reference to base reader.
7. Tree after-loop (`after_loop`) execution not verified for complex expressions (`acc[...]`) except marked in text (Tornado moreCastSpeed, Thorn Totem addedManaCost, Soul Feast ward).
8. Images, VFX, sound, UI not covered.
