# 07g. Semantics of skill mutator fields A–L (Last Epoch 1.5.0)

Wave 3 reverse-engineering: for each skill mutator `<X>Mutator` (letters A–L, 97 classes) determined what each header field does, written by the skill tree (skill tree), in the game formula. Sources: Ghidra/ISIL slices (`dump/work_wave3/ms/slices`), `fn.py`, `readconst.py`; background documents `07c_skill_mutators.md`, `dump_agent_brief.md`. Machine-readable result: `research/data/game/mutator_field_semantics_AL.json` (flat list, format as `mutator_field_semantics_MZ.json`; keys: mutator, field, offset, type, declaredIn, semantic, formula, category, affectsNumbers, readers, confidence, notes, trees, nodes).

Confidence levels: **D** — behavior read directly in code (Mutate / getTempStats / On* / getters). **D?** — field only copied to a component that was not traced, value read via ISIL only without full parsing, or effect inferred from node name/tooltip.

## 1. Summary

- Mutators: **97** (of which 6 made in previous wave: ClawTotem, ColdTempest, DeathSealExit, DetonateDecoy, DivineBolt, DivineFlare; 91 new).
- Total fields: **2237**; numeric categories (damage, ailments, defense, speed, area, cost, etc.): **2005**; behavioral flags/modes (behaviour category): **209** (of which 132 switch formulas, `affectsNumbers=true`); dead (unused): **23**.
- Confidence D: **1989**, D?: **248** (11.1%).
- All files `out/*.json` pass `validate.py --all` (OK).

## 2. Coverage table

| Mutator | Fields | D | D? | Numeric | Behaviour/unused |
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
| ClawTotemMutator (previous wave) | 1 | 1 | 0 | 1 | 0 |
| ColdTempestMutator (previous wave) | 6 | 6 | 0 | 6 | 0 |
| DancingStrikesMutator | 33 | 32 | 1 | 32 | 1 |
| DarkBladeMutator | 8 | 8 | 0 | 7 | 1 |
| DarkQuiverBuffMutator | 17 | 17 | 0 | 14 | 3 |
| DarkQuiverMutator | 10 | 10 | 0 | 10 | 0 |
| DeathSealExitMutator (previous wave) | 1 | 1 | 0 | 0 | 1 |
| DeathSealMutator | 34 | 34 | 0 | 31 | 3 |
| DecoyMutator | 10 | 8 | 2 | 9 | 1 |
| DetonateDecoyMutator (previous wave) | 1 | 1 | 0 | 1 | 0 |
| DetonatingArrowMutator | 39 | 39 | 0 | 36 | 3 |
| DevouringOrbMutator | 31 | 31 | 0 | 28 | 3 |
| DisintegrateMutator | 31 | 31 | 0 | 31 | 0 |
| DiveBombMutator | 29 | 29 | 0 | 27 | 2 |
| DivineBoltMutator (previous wave) | 2 | 2 | 0 | 2 | 0 |
| DivineFlareMutator (previous wave) | 6 | 5 | 1 | 6 | 0 |
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
| **Total** | **2237** | **1989** | **248** | **2005** | **232** |

## 3. Fields affecting numbers and behavioral fields

| Category | Total | with `affectsNumbers=true` | D? | Includes |
|---|---:|---:|---:|---|
| damage | 548 | 548 | 68 | damage: more/increased/added, conversions, crit, penetrating damage, cull |
| trigger | 240 | 240 | 42 | trigger chances, recasts, object spawns |
| ailment | 226 | 226 | 28 | ailment chances/duration/effect, freeze, shreds |
| behaviour | 209 | 132 | 11 | mode flags (channel, teleport, targeting, target type, etc.) |
| defence | 190 | 189 | 14 | health, ward, mana, block, resistances, leech |
| buff | 181 | 181 | 20 | buffs/stats on player and allies |
| cost_cooldown | 167 | 167 | 17 | mana cost, cooldown, mana efficiency, cooldown reset |
| area | 124 | 122 | 19 | radius/area/cone width |
| speed | 94 | 94 | 6 | cast/attack speed, frequency, projectile speed |
| count | 93 | 93 | 10 | number of projectiles/chains/targets/stacks |
| minion | 72 | 72 | 9 | minions |
| duration | 70 | 70 | 4 | durations |
| unused | 23 | 0 | 0 | field never read (dead) |

Behavioral fields (behaviour category) — boolean modes and flags: channelling mode, teleport/traverse, target switching, "not homing", "not piercing", etc. By themselves they add no numbers, but switch formulas: `affectsNumbers=true` where mode changes final numbers (cost, projectile count, damage type); `false` — purely visual/targeting flags. Other categories — direct numeric modifiers.

## 4. System findings

1. **Slots `Stats.Stat` ctor.** Argument order: `(this, SP, AT, added, increased, more, byte, int)`. Float in 6th position is **MORE**, not increased. This causes tooltip/code mismatch: tooltip ""+X% increased"", code puts value in more slot (BurstOfFlame.increasedDamage, ArcaneAscendance mark explosion, AbyssalEchoes, etc.; DivineFlare per-sigil, HolyFlameBurst.finalHitDamageMultiplier, Glacier.noCritMulti — also MORE).
2. **Copying to components.** Many mutators compute almost nothing themselves, copying fields to a component on the spawned object (Adapter / ExplosionMutator / DamageMutator / JudgementAoEMutator / FallingJavelinMutator / LightningBlastMutator, etc.). For Falconry, FlameRush, ChthonicFissure, FrenzyTotem, IceBarrage, ChaosBolts, Lunge a significant portion of fields marked D? because component logic not traced.
3. **getTempStats / addsTempStats.** Everything arriving as `unconditionalTempStats` copied via `EpochExtensions.replaceWith` to `conditionalTempStats`, additional numeric skill fields added to the list in `getTempStats` (bonuses "per N", "if condition"). Planner enough to reproduce this stat list.
4. **Base AbilityMutator fields.** `increasedManaCost` (+0xC4) and `addedManaCostDivider` (+0xC0) read by base `AbilityMutator.getManaCost`, not class, so class reads appear "unread" (readers empty). Semantics standard: cost multiplier and mana efficiency.
5. **Dead fields (23 total).** Written by tree but never read by self or others:
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
   For some, tooltip effect is implemented differently (e.g. HailOfArrows crit bonus goes through `unconditionalTempStats`; `Aura/HolyAura.addedFieryInquisitionStacksOnMeleeHit` duplicates entry in `statsToApply`), for rest probably actually doesn't work in 1.5.0.
6. **Tooltip/code mismatches**, found during analysis (details in `notes` field):
   - ChaosBolts: per-projectile fields `increasedAreaPerProjectile`/`moreDamagePerProjectile` swapped vs tooltip (0.5 in area, 0.35 in damage).
   - Glacier: `percentManaGainedOnKill` only as condition (>0), actual mana = maxMana * `percentManaGainedOnHit` (+0x164) — different field tree doesn't write (verified in ISIL). "Mana on kill" effect not scaled by tree.
   - Judgement: `noHealConsecratedGround` written by "Added Critical Strike Multiplier" node (side effect "Consecrated Ground doesn't heal" not in tooltip).
   - Firebrand/CharacterMutator: code constant 0.12 vs "15%" in tooltip (moreDamageForNextMeleeAttackFromFirebrand).
   - EnchantWeapon: `zapActiveReducedCooldown` writes 2 with tooltip 50% (formula `1 - f`, presumably clamped).
   - DreadShade `reducedDecayRate`: value sign opposite to tooltip wording.
   - AbyssalEchoes `chanceToDetonateDevouringOrbs`: tooltip 25%, code 0.15 per point.
   - BurstOfFlame/ArcaneAscendance: increased in tooltip, more in code (p. 1).
   - Ice Barrage: value `lessRateOfFire` in node shown as 1053609152.0 — this is bit image of float 0.4 (extractor artifact).
   - InfernalShade `explosionIncreasedArea` read only by ChaosBoltsMutator.Mutate; InfernalShadeMutator.Mutate doesn't use it.
7. **Cross-readers.** Mutator fields often read by "foreign" classes: Glacier.Mutate reads IceBarrage fields (Glacier casts Ice Barrage); LightningBlast.Mutate reads GlyphOfDominion fields; ChaosBolts.Mutate reads InfernalShade; Judgement/RadiantLance, FuryLeap/WerebearMaul and Hammer/Javelin components. In JSON listed in `readers`.

## 5. Notable mechanics per skill

(Brief technical conclusions per mutator; texts in English as in `out/_notes_AL.json`.)

### AbyssalEchoesMutator

- Mechanic: Echoed casts (UseType 5) spawn from the rift; echo-only more damage and tripled chains. Ailments applied via echo-object ChanceToApplyAilmentsOnHit; Abyssal Decay modified through mutateAilmentInstance (spread, lingering, on-hit portion). Void spell on-hit damage replaces Decay when noDecay.
- Gaps: Several ActiveAilment fields (+0x98,+0x110,+0x114) not decoded; tempBuffStats duration unknown.

### AcidFlaskMutator

- Mechanic: Flask hit/explosion/pool separate objects: pool poison DPS and cluster bombs separate DPS appliers; fire conversion removes poison chance and pools turns poison shred/duration to fire ones. Area additive (increasedArea+statArea) into explosion radius.
- Gaps: AcidFlaskExplosionMutator / pool-side effects (Ballista synergy, efficacious toxins, ally stats) not followed.

### AerialAssaultMutator

- Mechanic: Aerial Prowess stacks (8 s window after cast, cap 12/pt) gained on hit/crit/kill/dodge consumed on next cast for health/ward, Haste+Frenzy duration and more damage; with cross node also consumed by Ballista/Explosive Trap/Dive Bomb. Many nodes feed other falcon/ballista skills.
- Gaps: Featherstorm and Umbral Blade damage in other mutators.

### AnomalyMutator

- Mechanic: Anomaly teleports enemies forward in time ailments modified on return (speed, reset, Time Rot/Ignite, Future Strike chances via addChance). Optional Time Wave (start and/or end) and Time Bubble / Time Lock modes spawn extra mutators with their own damage.
- Gaps: Time Wave / Time Bubble / Time Lock internals not followed.

### ArcaneAscendanceMutator

- Mechanic: Arcane Ascendance is a buff: statsWhileActive/statsGainedPerSecond/WhenHit are stat lists on buff objects; ManaDrain is a stat inside the list noManaDrain removes reducedManaDrain modifies. Distant-enemy hit effects use manhattan distance threshold; mark explosion damage uses temp stats.
- Gaps: Mark explosion object (ExplodeMarks) and Lightning Blast cost not followed. manaGainWhenHit sign/guard.

### AssembleAbominationMutator

- Mechanic: Assemble Abomination configured entirely through AssembleAbominationAdapter on spawned Abomination: absorbed minion counts (skeleton warriors/rogues/archers capped jointly at 20, wraith/golem/zombie/mage flags and type counts) turn into stat lists, extra abilities and per-count more-damage on those abilities.
- Gaps: Devour-side fields (health restore on devour, temp health, sacrifice, zombie devour, cooldown-ability damage) not followed into RepeatedlyAbsorbMinion.

### AuraMutator

- Mechanic: Generic aura object used by Holy Aura: tree stats multiplied by the aura effect (manager increased effect + passives) handed to allies via BuffOnAllyHit.
- Gaps: Only shared base class; Holy Aura specifics in HolyAuraMutator.

### AuraOfDecayMutator

- Mechanic: Aura object repeatedly applies ailments to enemies in radius (RepeatedlyApplyAilmentsInRadius) and self-poison; conversion flags re-tag poison to cold/physical/fire. Fester stacks give aura damage per stack. Lots of side effects (nova, bombs, bolts, heals) via separate mutators.
- Gaps: Retaliation/bomb/nova/bolt damage in other mutators; aura damage tick itself on aura object.

### AvalancheMutator

- Mechanic: Avalanche drops big and small boulders; conversion flags switch Physical/Cold via tags and which prefab the DPS uses. Channelled mode adds shrinking area and post-channel persistence.
- Gaps: moreDamage application; reducedFallAreaPerSecond law.

### AvalancheSnowballMutator

- Mechanic: Avalanche large/small boulder impacts are AvalancheAoEMutator objects that receive copies of snowball fields. Large boulder chance gates most effects (upheaval, fissure, frozen ground, elemental, earthquake counter).
- Gaps: Per-hit damage slots (increased vs more) inside AvalancheAoEMutator not followed.

### BallistaMutator

- Mechanic: Ballista is placed minion configured through BallistaAdapter. The ballista copies fractions of player Damage/crit/ailment stats (ratio nodes) into its own stat list; Dexterity scales placement speed, attack speed and explosion damage/area.
- Gaps: Adapter-side behaviour of copied flags (double shot, pierce, tripwire) not followed.

### BlackHoleMutator

- Mechanic: Black Hole spawns stationary or drifting object; ailments (chill/ignite/blind) applied every 0.5 s in radius; end shockwave and optional periodic shockwaves are separate abilities; binary star and fire conversion change base damage types. Pull parameters mostly behavioural.
- Gaps: Binary star split ratio; center-distance threshold.

### BladestormThrowMutator

- Mechanic: Bladestorm throws up to 3 (+/- nodes) storm objects whose own BladestormMutator receives copies of these fields. Weapon-dependent bonuses (daggers/swords/2h) computed at cast from WeaponInfoHolder. Umbral Blade consumption gives more damage and area per stack.
- Gaps: Damage numbers of storm hit live in BladestormMutator (not part of this batch).

### BloodSplatterMutator

- Mechanic: Blood Splatter is Rip Blood spawned object; its tree fields live on Rip Blood tree stored here. Area grows with minion count (cap 20); minions hit get 4 s buff; necrotic conversion changes tags and ailments.
- Gaps: Splatter hit damage numbers in Rip Blood mutator.

### BoneArmorMutator

- Mechanic: Only flat +duration for Bone Armor from Transplant tree.

### BoneCurseMutator

- Mechanic: Bone Curse applied as ailment; most nodes mutate ActiveAilment instance (cull, max hits, always crit, damage multiplier, whenHit ailments, death procs). Damage nodes mirrored in tooltipStats purely for tooltip. Aura mode, prison, cursed ground, on-hit recast and minion buffs are separate modes.
- Gaps: Instance field meanings (+0x110/+0x98) inferred from tooltips.

### BurningDaggerConeMutator

- Mechanic: Cinder Strike spawns burning dagger cones; only tree field is temp-stat list (more Damage).

### BurningDaggerMutator

- Mechanic: Single burning dagger; only more Damage temp stat from Cinder Strike tree.

### BurstOfFlameMutator

- Mechanic: Burst of Flame is Flame Ward retaliation. Conversion flags convert all base fire damage and alter ailment stats; damage node applied as more despite its name.

### CaltropsMutator

- Mechanic: Caltrops is ground object triggered by Aerial Assault or Net; its tree fields are temp-stat ailment chances, damage, and area. Crit scales with global slow chance.
- Gaps: Area combination formula partly hidden.

### ChaosBoltsMutator

- Mechanic: Chaos Bolts spawns bolts whose damage/secondary missiles governed by ChaosBoltsDamageMutator/SecondaryMissilesMutator copies of these fields; conversion flags re-tag Necrotic->Physical and Fire->Cold. Many conditional damage nodes (vs Bleeding/Damned/Ignited/Frostbitten/Cursed) stored on bolt, not in temp stats. Single-projectile mode multiplies damage by (projectiles+5).
- Gaps: Bolt-side consumers (ChaosBoltsDamageMutator, SecondaryMissiles) not followed, so several conditional damage fields are D?.

### CharacterMutator

- Mechanic: Player-side synergy fields: one-shot "next skill" buffs (activated by OnAbilityUse/OnHit, consumed in ApplyConditionalTemporaryStats / PopulateActorTempStatsForCast), echo-chance modifiers for Void Knight, retaliation casts and Healing Hands extras. Each field implemented as temp stat added to next cast of target ability.
- Gaps: Application sites of "next damage" buffs on target skill side (ErasingStrike, VoidCleave, Judgement, ForgeStrike) not followed; moreHealthRegenWithABear has no reader.

### ChthonicFissureMutator

- Mechanic: Chthonic Fissure spawns fissure object plus Tormenting Spirits; most spirit/torment nodes copied into TormentingSpiritMutator, ChthonicFissureHitMutator or applied via mutateAilmentInstance on Torment ailment. Conversion flags (Fire->Physical/Poison) re-tag damage convert ignite chance to bleed/poison chance.
- Gaps: Spirit and hit mutator consumers not followed (hence many D?).

### CinderStrikeMutator

- Mechanic: Cinder Strike is 3-strike combo (melee and bow variants); base class holds tree fields each strike mutator builds its own conditional temp stats. First-strike bonuses added only to strike 1 (more damage, ignite duration, crit multi, doubled added fire). Incendiary Ammo stack system gives scaling buffs to player.
- Gaps: Flask/trap/explosion objects not followed; shadowsImitateBurningDaggers consumer not found.

### ClawTotemMutator

Done in previous wave; see `dump/work_wave3/ms/out/ClawTotemMutator.json`.

### ColdTempestMutator

Done in previous wave; see `dump/work_wave3/ms/out/ColdTempestMutator.json`.

### DancingStrikesMutator

- Mechanic: Dancing Strikes is 4-strike combo (separate DancingStrikes1/2/4 mutators read base fields). Many nodes give timed buffs on use of any other strike; Rhythm stacks and third-strike Arena are additional systems. Conditional damage components built per cast as DamageConditionalEffect entries.
- Gaps: Strike-specific consumers partly followed; Puncture synergy not.

### DarkBladeMutator

- Mechanic: Iron Blade (Vengeance): ricocheting projectile; weapon-conditional temp stats (sword crit, polearm bleed duration), recent block/parry doubling, and per-ignite fire damage conditional effect.

### DarkQuiverBuffMutator

- Mechanic: Dark Quiver Buff is pickup effect object of black arrow: pickup effects (health, mana, shrouds, frenzy, shadow, ballista buffs) applied in Mutate; black arrow stats applied to skills via DarkQuiverMutator. arrowManaConsumption and arrowConsumesShadows on this class are dead copies.

### DarkQuiverMutator

- Mechanic: Dark Quiver drops black arrows over duration; arrow count and drop rate set interval. Picking up arrow empowers next ability via applyStatsFromBlackArrow (mana cost, shadow consumption, elemental ailment chances).

### DeathSealExitMutator

Done in previous wave; see `dump/work_wave3/ms/out/DeathSealExitMutator.json`.

### DeathSealMutator

- Mechanic: Death Seal is buff on player (or minion): current-health drain / delayed damage mechanics with release effects. Wave of Death fields copied into DeathSealWaveMutator in SetupWaveMutator; cast every second with wave-interval node. Conversion flags convert wave necrotic damage to physical/cold convert resistance/shred lists.
- Gaps: Wave mutator consumers (DeathSealWaveMutator) not followed; hence wave damage fields are D by field name only.

### DecoyMutator

- Mechanic: Decoy throws one (or more) decoys that explode; damage nodes collected in finalExplosionUnconditionalTempStats used by explosion/DPS. Remote-detonate mode makes it two-step combo. Cooldown/charge fields partially unresolved.
- Gaps: addedManaCost and treeAddedCharges readers not found.

### DetonateDecoyMutator

Done in previous wave; see `dump/work_wave3/ms/out/DetonateDecoyMutator.json`.

### DetonatingArrowMutator

- Mechanic: Detonating Arrow places arming charge; explosion parameters written onto explosion/charge object. Charge-up mode (channelled) adds pierce and damage per second charged. Arming time scales explosion hit damage per second armed.
- Gaps: Explosion-side consumers not followed in detail; field-to-offset mapping done by name.

### DevouringOrbMutator

- Mechanic: Devouring Orb is slow orb (or orbiting orb) that creates Void Rifts (own mutator); rift growth, abyssal orbs and void eruption are separate spawned objects. Per-second ailments applied via RepeatedlyApplyAilmentsInRadius with interval 0.25 s.
- Gaps: Void Rift/Abyssal Orb internals not followed.

### DisintegrateMutator

- Mechanic: Disintegrate is channelled beam with tier power-up system (tier 2/3 nodes, powerUpInterval) and Lucomancer stacks; ailments applied per second of channelling (chance*0.5 per tick style via addChance). Many side casts (lightning blast, fire aura, orbs, fireballs) use CastAfterDuration and ability mana cost.

### DiveBombMutator

- Mechanic: Dive Bomb is falcon skill; Falcon adapter copies most fields. Talon Blades stacks (creator buff), Crimson Shroud, shadow falcons per rogue shadow (capped by umbral blades), feather rain side casts and decoy/trap detonation.

### DivineBoltMutator

Done in previous wave; see `dump/work_wave3/ms/out/DivineBoltMutator.json`.

### DivineFlareMutator

Done in previous wave; see `dump/work_wave3/ms/out/DivineFlareMutator.json`.

### DrainLifeMutator

- Mechanic: Drain Life is channelled beam (or casted version); many fields copied into beam component (+0xa0.. offsets). Mana-to-health conversion node adds AcceleratingHealthDrain. Damned/contempt systems give conditional damage and defensive stacks.
- Gaps: Beam component internals not followed.

### DreadShadeMutator

- Mechanic: Dread Shade is shade attached to minion that drains its health gives it and nearby minions aura (stats lists). Many nodes only toggle ailments/behaviours on parent minion; InfernalShadeMutator reads addedMaxShades, auraStats and markedForDeath fields from this mutator.
- Gaps: Doom Brand and decay-rate sign conventions unclear.

### DreamslashMutator

- Mechanic: Dreamslash is Rogue shadow-synergy skill: casts repeated by Rogue Shadows (UseType 6) with their own temp stats and area bonuses; Dream stacks (time, kill, elite, consumed shadows) give damage/crit; shroud ailments scale ailment chance and ward.
- Gaps: Shadow-side behaviour (RogueShadow) not followed.

### EarthquakeSeekingCrackMutator

- Mechanic: Earthquake aftershocks are EarthquakeAftershockMutator objects fed with copies of these fields (also copied to Bear minion via CopyVariablesToMinionMutator).
- Gaps: EarthquakeAftershockMutator consumers not followed.

### EarthquakeSlamMutator

- Mechanic: Earthquake slam (Bear/Primalist): initial slam plus aftershock objects (EarthquakeMutator) fed by copies; triple hit recasts slam via CreateAbilityObjectOnDeath (extra slams cost mana); noAftershocks folds aftershock damage into slam.
- Gaps: Aftershock consumers in EarthquakeMutator/EarthquakeAftershockMutator not followed.

### EnchantWeaponMutator

- Mechanic: Enchant Weapon is timed buff; its tree stats are player stat list while active plus proc effects on melee hits (zap, fire burst, ice shards) limited by ProcTimeTrackers that change while active.
- Gaps: zapActiveReducedCooldown sign.

### EnchantWeaponPassiveMutator

- Mechanic: Enchant Weapon passive part: list of player stats plus player property granting Frostbite chance from Chill chance.
- Gaps: Property 0x274 identity inferred from tooltip.

### EntanglingRootsMutator

- Mechanic: Entangling Roots creates root wave object (EntanglingRootsWrapMutator) plus seeds (EntanglingRootsSeedMutator) with copied fields; many ally/minion buffs are BuffOnAllyHit components (8 s) with stat lists for specific minion abilities. UpheavalMutator reads several fields for Upheaval interaction.
- Gaps: Wrap/Seed mutator consumers not followed.

### ErasingStrikeMutator

- Mechanic: Erasing Strike (Void Knight) applies Time Rot via temp stats creates Void Rifts / void beams. Weapon-type conditionals (2h mace/sword/axe) use WeaponInfoHolder. AbyssalEchoesMutator.Mutate reads many of these fields to run Erasing Strike through Abyssal Echoes.

### EterrasBlessingMutator

- Mechanic: Eterra's Blessing is heal spell that creates Sacred Plant (heal buff area); synergy nodes grant effects depending on type of companion healed. Healing amount scales with IncreasedHealing stat plus tree increased healing.
- Gaps: Base heal amount and HoT details not decoded.

### ExplosiveTrapMutator

- Mechanic: Explosive Trap throws traps that detonate through ExplosiveTrapDamageMutator / ExplosiveTrapOnGroundMutator with copied fields. Arming time, trigger radius, per-second growth and conversion-of-each-type determine effective hit damage and area; max traps matter for Mine Field.
- Gaps: Trap-side consumers partly followed.

### FalconStrikeMutator

- Mechanic: Only flat mana cost increase for Falcon Strike.

### FalconryMutator

- Mechanic: Falconry is falcon companion mutator holding falcon-related trees (Falconry, Aerial Assault feather skills, Dive Bomb, Net synergies). Mutate copies most fields into FalconAdapter / falcon abilities; ratio fields convert player stats into falcon stats.
- Gaps: Almost all fields are D? by name/tooltip; falcon-side consumers (FalconAdapter, feather burst, featherstorm, falcon strikes) not followed.

### FinalExplosionMutator

- Mechanic: Decoy final explosion: area, damage nodes via temp stats, cold conversion converts base fire damage to cold and ignite to chill, ignite stacks.

### FireAuraMutator

- Mechanic: Fire Aura spawned by Flame Ward; Flame Ward writes conversion flags and duration here.

### FireShieldMutator

- Mechanic: Fire Shield is timed shield buff with retaliation fireballs (FireballMutator on retaliation object) and optional AoE damage aura. Resistances and granted damage are stats in shield BuffParent.

### FireballExplosionMutator

- Mechanic: Explosion part of Fireball: penetration/crit temp stats, partial base damage conversion to lightning, crit bonus vs ignited.

### FireballMutator

- Mechanic: Fireball: projectile stats copied to spawned FireballMutator; extra projectile count with halving/sequence nodes, conversion to lightning as fraction, flamethrower channelled mode.

### FirebrandMutator

- Mechanic: Firebrand builds up to 4+ stacks (4 s each, duration scaled) that give per-stack stats and per-stack melee damage/crit through getTempStats; consumption by other melee attacks configured in CharacterMutator. LightningBlastMutator reuses most of these fields for lightning variant.

### FlameReaveMutator

- Mechanic: Flame Reave sends fire wave (FireWaveMutator) that can return and cycle; Rhythm of Fire stacks (max 12) empower cast at max; conditional damage/crit vs ignited; Firebrand stack consumption adds ignite chance.

### FlameRushMutator

- Mechanic: Flame Rush is channelled dash through enemies with Rune Embers; many nodes trigger side effects (ward, ignite consumption, glyph/orbs). Damage scales with current mana (1% per 40). Conversion modes alter ailments through temp-stat conversion entries.
- Gaps: Mutate body of Flame Rush not read; many side-effect fields D?.

### FlameWardMutator

- Mechanic: Flame Ward is ward buff: ward amount = (base + additional)*(1+increased)+missing health part, optionally split over 6 ticks; its retaliation is BurstOfFlameMutator (fed by copies of retaliation fields).

### FlayBloodExplosionMutator

- Mechanic: Blood Eruption part of Flay (also used by Rip Blood): area grows with curses, conditional more damage vs low life/chilled/frozen, converted ailment chance/duration (bleed -> frostbite/damned/poison) through temp stats, and Blood Revelry stacks for Harvest/Rip Blood.

### FlayMutator

- Mechanic: Flay alternates melee hits (copied into hit component) and Blood Eruption; Spirit Step traversal can be removed or turned into traversal skill. Many on-hit effects use onDetailedHit.

### FlurryMutator

- Mechanic: Flurry is 3-strike melee combo (bow variant BowFlurryMutator): per-strike damage/ailment modifiers written into separate hit components (strike 1, 2, 3); Onslaught (Adrenaline Rush) stacks give +5% more damage and other bonuses.

### FocusMutator

- Mechanic: Focus is channelled mana skill: it converts mana gain into lightning damage (during channel waves and at end), ward and haste; ailments applied per second in radius of 5.

### ForgeStrikeMutator

- Mechanic: Forge Strike: mode flags sword/spear/anvil change forged weapon (sword 35% more attack speed, no crit; spear 100% crit multi, -35% area; anvil 20% less attack speed, stun chance and phys damage). Detonating Ground eruption added through castDetonateGround.

### FrenzyTotemMutator

- Mechanic: Frenzy Totem is mostly data hand-off: Mutate copies almost every field into FrenzyTotemAdapter (aura radius, tether, damage storage, companion bonuses); adapter logic not followed so those are D?.
- Gaps: FrenzyTotemAdapter behaviour not analysed.

### FrostClawMutator

- Mechanic: Frost Claw (Nova derived): mana cost/ward/freeze rate mechanics in Mutate; projectile behaviour flags (five projectiles, second/third cast, no explosion, projectile speed) copied to claw component; Frozen Sleeper stacks accumulate in OnMutatorUpdate.
- Gaps: Claw component flags not followed.

### FrostWallMutator

- Mechanic: Frost Wall (also used by Abyssal Echoes): wall + two pylons; ally pass-through grants ward/mana/haste/frenzy, buffs next Glyph of Dominion/Runic Invocation, casts Flame Ward; enemy pass-through grants ward, increases pylon blast frequency; idle >= 15 s gives free cast with more damage; Fire/Lightning conversion variants.
- Gaps: recastManaGain and explosionChecksFacing never read (dead fields).

### FuryLeapMutator

- Mechanic: Fury Leap: landing buffs (added melee/spell damage 3 s, frenzy, heal, cleanse), Storm Bolts while leaping, cooldown resets on kill, Upheaval at end; shares data with companion version (CopyVariablesToMinionMutator) and WerebearMaulMutator.
- Gaps: getTempStats read via ISIL only.

### GatheringStorm1Mutator

- Mechanic: Gathering Storm 1/2 are cast-variant subclasses of GatheringStormMutator; only scorpion soak flag added.
- Gaps: All other behaviour documented under GatheringStormMutator.

### GatheringStorm2Mutator

- Mechanic: Gathering Storm 1/2 are cast-variant subclasses of GatheringStormMutator; only scorpion soak flag added.
- Gaps: All other behaviour documented under GatheringStormMutator.

### GatheringStormMutator

- Mechanic: Gathering Storm builds Storm Stacks and expends them to cast Storm Bolts (most logic in GatheringStorm1Mutator); conversions (cold/physical), melee bonuses and attunement-scaled stats go through getTempStats.
- Gaps: Several on-hit effects (repeat on boss, 3-enemy stack, mana for stacks) read via ISIL only.

### GhostflameMutator

- Mechanic: Ghostflame: channelled skull; per-second ailment chances added to ChanceToApplyAilmentsOnHit component; channel cost = (base+added)*(1+increased)*(1+more)*(1+less); skull can detach, move, screech and fire Marrow Shards.
- Gaps: screechAreaIncrease, canCastStygianBeam and dodgeRatingConvertedToArmorWhileChanneling never read.

### GlacierMutator

- Mechanic: Glacier casts three explosions (smallest/middle/largest) through Glacier1/2/3Mutator components; per-explosion stat lists and shared fields copied to those components. Rime is player buff (DoT increased + freeze rate multiplier).
- Gaps: percentManaGainedOnKill is only >0 gate; mana gained uses percentManaGainedOnHit (another field) - verified in ISIL (+0x160 gate, +0x164 multiplier).

### GlyphOfDominionMutator

- Mechanic: Glyph of Dominion places zone (up to 1 + additionalMaxGlyphs glyphs) that grants buffs to allies through BuffOnAllyHit afflicts enemies through RepeatedlyApplyAilmentsInRadius; runes of Runic Invocation can be consumed (Rah/Heo/Gon). LightningBlastMutator.Mutate reads many same fields when Lightning Blast cast on glyph.
- Gaps: Explosion component, static charge and ward-per-resistance details not followed.

### HailOfArrowsMutator

- Mechanic: Hail of Arrows creates area object with RepeatedlyApplyAilmentsInRadius (0.2 s interval; chance per tick = f*0.2). Conversion flags change damage type, ailment and VFX; channelled mode changes delay/cost; advancing rectangle moves area.
- Gaps: addedCritChance never read (crit bonus goes through unconditionalTempStats).

### HammerThrowMutator

- Mechanic: Hammer Throw: same class acts as skill mutator and as component of each thrown hammer (many fields copied there). Zeal stacking buff stats applied through StatBuffs on cast; spiral/nova/chain flags control projectile layout.
- Gaps: increasedAttackSpeed/freeWhenOutOfMana read only via ISIL. centreOnCaster/spiralMovement/ignoreTerrainCollision have no tooltip writers.

### HarvestMutator

- Mechanic: Harvest: weapon-attack skill converting necrotic base damage (physical/cold options); curse-gated bonuses (more damage, ward, heal per Int); on-kill/on-hit triggers (Wandering Spirits, Volatile Zombie, Blood Wraith); CopyToMinionMutator copies whole state to Rip Blood version.
- Gaps: Zombie/Wraith/Spirit chance in OnKill (ISIL only).

### HealingHandsMutator

- Mechanic: Healing Hands copies its numbers into adapter on cast object (+0x138..+0x190) applies healing/ward as ailment instances (mutateAilmentInstance); upfront healing base 100 + f, channelled base cost 10; traversal mode reuses Shield Rush ability.
- Gaps: Adapter-side use of copied fields not followed.

### HeartseekerMutator

- Mechanic: Heartseeker: recurve mechanic (chance + dex bonus with minimum) with many OnRecurve triggers (Dark Arrow, Burning Dagger, Crimson/Dusk Shroud, Hail of Arrows extension, Dragonfang stacks); conversions to cold/fire via convertBaseDamage.
- Gaps: Arrow component fields (+0x38, +0x3c, minimum chance) not followed.

### HolyAuraMutator

- Mechanic: Holy Aura: passive aura plus active boost; most bonuses are entries of statsToApply (including HolyAuraStack ailment chances), so few dedicated fields exist.
- Gaps: addedFieryInquisitionStacksOnMeleeHit never read; finalHitDamageMultiplier read only by DPS calculation.

### HolyFlameBurstMutator

- Mechanic: Holy Flame Burst (released by Holy Aura): small mutator with one MORE-damage stat and area increase.

### HungeringSoulsMutator

- Mechanic: Hungering Souls: CopyVariablesToMinionMutator copies full state into spawned soul (offsets +0x130..+0x19c); damage bonuses per minion go through getTempStats; kill/hit triggers (mana, ward, cast when hit) in OnKill/whenHit.

### IceBarrageMutator

- Mechanic: Ice Barrage launches frostbolts with fire interval = 1/((1-less)*(1/base)) / (1+increased); Mutate copies many numbers into barrage component (+0x128..+0x188). GlacierMutator.Mutate also reads several Ice Barrage fields (Glacier launches Ice Barrage). Ice Shield is separate mutator receiving iceShield* fields.
- Gaps: Barrage component use of copied fields not followed (D?).

### IceSpiralMutator

- Mechanic: Ice Spiral fields come from Frost Claw tree: per-spiral buffs for Glacier / Snap Freeze are Stats.AbilityPropertyStat entries; double cast is roll in onCast.
- Gaps: Property ids 0x2f / 0xa6 (Glacier / Snap Freeze) identified from tooltips, not enum.

### IceThornsMutator

- Mechanic: Ice Thorns (Thorn Burst): projectile volley or Thorn Shield barrier (thornShieldMode); shield numbers copied to component (+0x130..+0x1a4); proc-based extras (Sundering Thorns, Thorn Trail/Totem) in OnHit/OnKill.
- Gaps: Tree entries have no tooltip text for this skill; semantics from code and node names. delayWindow and damageAndFreezeBuffStacks marked D?.

### IceWardMutator

- Mechanic: Ice Ward builds ward buff from stat entries (block, armour, ward retention/regen, mana regen); Frost Nova cast periodically via CastAfterDuration with numbers written into FrostNovaMutator.
- Gaps: Stat ids (0x35, 0x39, 0x27, 0x12, 0x10) inferred from node names.

### InfernalShadeMutator

- Mechanic: Infernal Shade: shades attach to enemies/minions (or wait on ground) apply per-second ailment chances through RepeatedlyApplyAilmentsInRadius (chance = f * interval). Chaos Bolts (ChaosBoltsMutator.Mutate) reads same fields to build its shade variant.
- Gaps: explosionIncreasedArea read only by ChaosBoltsMutator.Mutate.

### JavelinMutator

- Mechanic: Javelin: base throw with distance/pierce scaling, optional lightning conversion; modes Javelin Rain (falling javelins, optionally flag with healing aura and smite) and lunge combo; fields copied into JavelinSpearBurstMutator, FallingJavelinMutator and FlameTrailMutator.
- Gaps: moreAttackSpeed/addedManaCost read via ISIL only.

### JudgementMutator

- Mechanic: Judgement hits via JudgementAoEMutator creates Consecrated Ground (or Holy Eruption/aura); most tree numbers written into ConsecratedGroundMutator through mutatorManager at fixed offsets.
- Gaps: Tooltip/code mismatch: noHealConsecratedGround written by crit-multiplier node. eruptionMoreDamage read only by DPS calculation.

### LethalMirageDamageMutator

- Mechanic: Damage-side component of Lethal Mirage; only ally-buff fields used here, other two consumed through LethalMirageMutator.

### LethalMirageMutator

- Mechanic: Lethal Mirage: 6 mirages (+additional) created by CastAfterDuration; per-mirage numbers copied to LethalMirageDamageMutator; self/ally mirage-form buffs are bleed chance + dodge rating for 4 s.
- Gaps: smokeCloudDuration, smokeMakesAlliesUncrittable, smokeCloudConvertedToPoison never read. lightningConversion only enters addsTempStats.

### LightTempestMutator

- Mechanic: Light Tempest (Tempest Strike lightning variant): small mutator, penetration scales with typed minions and uncapped resistance through getTempStats; area is collider radius multiplier.
- Gaps: chanceToGainGladiatorOfLagonStack via ISIL only.

### LightningBlastMutator

- Mechanic: Lightning Blast: base chains = tree chains + recent-cast chains (min(recent, f+2)); Mutate copies nearly all fields into LightningBlastMutator component on cast object. Glyph of Dominion and Firebrand add chains through glyphMut (+0x144) and firebrandMut (+0x158).

### LungeMutator

- Mechanic: Lunge: path hit with distance scaling (damage/area/cull/haste/smite at up to 10 m); distance-scaled numbers and conversions copied into lunge component (+0x130..+0x160); cooldown recovery via onAbilityUse of other melee abilities.
- Gaps: Lunge component logic for copied fields not followed.

## 6. List of D? (fields with reduced confidence)

Total 248. Reason — copying to untracted component, reading only via ISIL, or inference from name/tooltip.


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
- `featherstormAtEnd` — Featherstorm damage in falcon skills; not followed.

**ArcaneAscendanceMutator**
- `manaGainWhenHit` — Applied only when 0 < f in guard ("0.0 < f"), so negative tree values never reach it; guard likely makes node tooltip incorrect (-1 mana drained when hit has
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
- `reducedFallAreaPerSecond` — Exact shrink law lives in spawned object (CastAtRandomLocation..); only constants visible.
- `moreDamage` — Real hit damage application not located; tree node probably also adds Damage more Stat (not header field).

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
- `moreHealthRegenWithABear` — No reader located; written by Summon Bear tree.

**ChthonicFissureMutator**
- `percentManaRefundedIfCursedEntityNearBy` — Refund computation partly dropped.
- `igniteStackSpreadOnTormentToEnemiesCount` — Spirit-side mechanics not followed.
- `chaosBoltCastInsteadOfSpiritChance` — Chaos Bolt side not followed.
- `tormentChainOnDeathChance` — Chance that dying tormented enemy releases Spirit (mutateAilmentInstance on Torment ailment).
- `spiritFireResShredStacks` — Fire/physical/poison resistance shred stacks applied by spirits (copied to TormentingSpiritMutator).
- `consumesInfernalShades` — Spirit/Shade interaction not followed.
- `moreDamageToTormentPer3PercentUncappedNecroticResistance` — Torment damage increases with uncapped Necrotic resistance (mutateAilmentInstance).
- `moreDamageToBossAndRareEnemies` — More damage to bosses and rare enemies (doubled if cursed); applied to fissure/torment/spirit (copied to TormentingSpiritMutator, read by FlameWhipMutator and mutateA
- `spiritTargetsPlayer` — Buff values (3, 15) are constants in TormentingSpiritMutator.
- `castVolatileZombie` — Zombie side not followed.
- `appliesDamageOnHit` — Amount in hit mutator.
- `spellDamageGainedPer2PercentOfIgniteBleedOrPoisonChance` — Fissure hit mutator adds Added Spell Damage = f per 2% of player Ignite/Bleed/Poison chance (matching converted ailment).
- `increasedStunChancePer2PercentOfIgniteBleedOrPoisonChance` — Increased stun chance per 2% of ailment chance (5% per 2%).
- `applyAcidSkin` — Fissure hit applies Acid Skin to player (+20% crit chance from Acid Skin per tooltip).
- `ailmentStackSpreadOnImpactToEnemiesCount` — Number of enemies Ignite/Bleed/Poison stacks spread to on fissure impact.
- `igniteChanceOnHitAsIgniteChancePerSecond` — Player ignite chance on hit converted into ignite chance per second on fissure (fraction f).
- `igniteChancePerSecond` — Flat ignite chance per second applied by fissure.
- `increasedTormentDuration` — Increased Torment duration (copied to Torment ailment application).
- `tormentMoreDamageToIgnitedPoisonedOrBleedingEnemies` — Torment deals more damage to enemies that are ignited, poisoned or bleeding (mutateAilmentInstance).

**CinderStrikeMutator**
- `firstStrikeFlaskChance` — Flask damage not followed.
- `flasksReplacedWithTraps` — Volatile Flask replaced with Explosive Trap (AddFlaskChanceToObject, OnKill).
- `firstStrikeMoreCritChancePerIgnite` — Application on explosion object not followed.
- `maxFirstStrikeMoreCritChancePerIgnite` — Cap of crit chance bonus (0.09 per point).

**DancingStrikesMutator**
- `morePunctureDamageOnNextUse` — Application in Puncture mutator (not followed).

**DecoyMutator**
- `addedManaCost` — Reader not found in this slice.
- `treeAddedCharges` — Probably consumed through getAddedCharges of base AbilityMutator via different field; 07c §1 covers cooldown fields.

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
- `aftershockChanceToDropSnowball` — Chance that aftershock hit casts Boulder (snowball), 5 mana consumption.
- `aftershockIncreasedSlowDuration` — Increased slow duration of aftershocks.
- `aftershockIncreasedStunChance` — Increased stun chance of aftershocks.
- `aftershockConvertToDoT` — Aftershock hits become damage over time (convertToDoT).
- `aftershockIncreasedDuration` — Aftershock duration (also read by BearAdapter.adapt).
- `aftershockChanceToBlind` — Chance to blind enemies with aftershocks.
- `igniteInsteadOfArmorShred` — Fire mode: base damage -> Fire, Armour Shred -> Ignite chance in aftershock.
- `spellConversion` — Melee attack becomes spell with physical -> lightning conversion; +80 initial slam spell damage and +20 aftershock spell damage (the +20 is in aftershock_unconditionalT
- `frostbiteInsteadOfArmorShred` — Cold mode: base damage -> Cold, Armour Shred -> Frostbite chance in aftershock.

**EntanglingRootsMutator**
- `increasedArea` — Reader not located.

**FalconryMutator**
- `acidFlaskManaCostRatio` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `chanceFalconGainFlaskChargeOnPlayerFlaskUse` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `prioritiseTargetsCloseToPlayer` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `prioritiseSummonerTargetLocation` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `ailmentChanceFromPlayerEffectivenessRatio` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `throwsFeatherKnives` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `featherKnivesCooldownFromPlayerThrowingAttackSpeedRatio` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `highestIncreasedDamageTypeFromPlayerRatio` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `falconTypedCritMultiOnCrit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `reducedFalconStrikeCooldownPercentageOnHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `secondHitScreeches` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `slowStacksWithScreech` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `frailtyStacksWithScreech` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `protectiveScreechOnPlayerLowLife` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `screechFears` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `addedHits` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `cullPercentage` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `razorWingsMode` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `increasedWidthPerIncreasedAreaRatio` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreDamageIfUsedAreaSkillRecently` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `extraHitsFromKills` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `extraHitsFromRareBossHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `chanceToAddHitFromRareBossHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `healthPerTotalAttributesOnKillOrRareBossHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `manaPerTotalAttributesOnKillOrRareBossHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `falconWakeDurationOnMarkConsume` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `consumingFalconMarkRecoversFalconStrikeCooldown` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `slowChancePerSecondInFeatherstorm` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `shadowFeatherstormBossOrRare` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreDamagePerSecondFeatherstormActive` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `increasedFeatherstormDuration` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `blackArrowPerSecondInFeatherstormChance` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `poisonConversionForFeatherstorm` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreDamagePerAerialProwessStackConsumed` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreDiveBombDamageFromAerialProwess` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreFeatherBurstDamageToHighHealth` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreFeatherstormDamageToHighHealth` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `throwingDamageFeatherBurstStatsRatio` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `throwingDamageFeatherstormStatsRatio` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreFeatherBurstDamageToRareAndBoss` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreFeatherstormDamageToRareAndBoss` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `featherRainTargets` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `increasedDiveBombRadius` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `diveBombStats` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `giveCreatorTalonBladesOnDiveBombOrFeatherRainHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `increasedMoveSpeedWith5TalonBladeStacks` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `detonateExplosiveTraps` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `increasedAreaForTriggeredExplosiveTraps` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `maxCrimsonShroudStacksPerUseOfDiveBomb` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `consumeBleedStacksWithDiveBomb` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreDamagePerBleed` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `reducedDelayWithDiveBomb` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `shadowFalconCount` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `duskShroudChanceIfShadowFalconHits` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `shadowFalconsBounceInSmokeBombChance` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreShadowFalconDamagePerUmbralBlade` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `dualWieldingWeaponStatPercentage` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `moreAilmentDamagePer10PercentStunChance` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `manaRestoreOnRareOrBossFirstHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `traversalRemainingCooldownRestoreOnRareOrBossFirstHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `detonateDecoys` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `decoyMoreDamageOnHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `decoyIncreasedAreaOnHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `diveBombAddedManaCost` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `increasedSmokeBombDurationOnHit` — Consumed in falcon adapter/spawned falcon objects (not followed).
- `featherRainArmorShredChance` — Consumed in falcon adapter/spawned falcon objects (not followed).

**FlameRushMutator**
- `castGlyphOfDominionAtTargetLocation` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `volcanicOrbTravelsWithYou` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `buffOverflowDurationPercentage` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `wardAtEnd` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `castStaticOrbBackwards` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `applyBrandOfSubjugationWhileTravelling` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `brandOfSubjugationMoreDamagePerChillChance` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `frenzyAtEndDuration` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `castRunicInvocationAtEnd` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `moreDamageIfCastFireballInSameDirection` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `increasedRadiusIfCastFireballInSameDirection` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `manaRefundIfCastFireballInSameDirection` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `runicBurstOnFireballHitDuringFlameRush` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `fireResShredStacksOnHitWhileChannelling` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `wardPerIgnitedEnemyYouTravelThrough` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `consumeYourIgnitesOnEnemiesYouTravelThrough` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `wardGainedPerIgniteConsumed` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `consumedIgnitesDealDamageImmediately` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `moreIgniteDamagePerInt` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `increasedRadiusOnFrostWallHit` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `moreCritChanceOnFrostWallHit` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `maxRuneEmberCount` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `additionalRuneEmbersOnFlameRushUse` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `increasedRuneEmberGenerationSpeed` — Mutate body not followed in detail; semantics from node tooltips and field name.
- `chanceToGainRuneEmberOnFlameRushKill` — Mutate body not followed in detail; semantics from node tooltips and field name.

**FlayMutator**
- `chanceEveryOtherMeleeExplodeOnElite` — ISIL-only read; effect inferred from tooltip.
- `chanceToMarrowShardsOnDirectCrit` — ISIL-only read; effect inferred from tooltip.

**ForgeStrikeMutator**
- `increasedCooldownRecoverySpeed` — Increased cooldown recovery speed read in increasedCooldownRecoverySpeedFromMutator (ISIL only).
- `stunChanceFromTree` — Stun chance read in getTempStats via ISIL only (added as increased stun chance temp stat).

**FrenzyTotemMutator**
- `chanceToCastEterrasBlessingPerSecond` — Copied to FrenzyTotemAdapter; adapter rolls each second to cast Eterra's Blessing for allies in range (adapter not followed).
- `damageStoredByTotem` — Fraction of damage taken by totem stored (copied to adapter).
- `totemDamageTakenThresholdToRelease` — Threshold of max health in damage taken at which totem releases stored damage (adapter).
- `playerDamageTakenStoredByTotem` — Fraction of damage taken by player stored by totem (adapter).
- `AoEHealOnCompanionRevival` — Healing nova of f when companion revived (adapter).
- `addedSabertoothSwipes` — Extra Sabertooth swipe(s) per cast (adapter).
- `wolfHowlIncreasedCritChance` — Wolf Howl grants increased crit chance to player (adapter.wolfHowlIncreasePlayerCritChance).
- `scorpionNovaIncreasedArea` — Increased area of scorpion venom nova (adapter).

**FrostClawMutator**
- `addedManaCost` — Added mana cost read in getAddedManaCost via ISIL only (tree: -2 per point, +4/+2 for extra casts).
- `elementalNovaAtTargetChance` — Chance for Elemental Nova at target, copied to claw component (+0x14c).

**FrostWallMutator**
- `fireballChanceOnhit` — Chance for Fireball when enemy passes through (OnHit via ISIL only; Fireball mana cost evaluated).

**FuryLeapMutator**
- `unconditionalTempStats` — Temp stats of Fury Leap (crit multi, stun chance/duration, ...), returned by getTempStats (ISIL); copied to companion mutator.
- `moreDamagePerDistance` — Damage more per meter travelled: distance-scaled value (max distance = (range bonus + 1) * 8) multiplied by f; applied through AoE hit (branch details not followed).

**GatheringStormMutator**
- `stormBoltRepeatChanceOnBossOrRare` — Chance for Storm Bolt to be cast again against boss or rare (OnHit via ISIL only).
- `addedManaCost` — Flat mana cost added (+6 for ranged staff bolt), read in getAddedManaCost via ISIL only.
- `manaConsumptionForAdditionalStacks` — Mana consumed when chance roll for additional stacks succeeds (OnHit via ISIL).
- `chanceForAdditionalStormStackWith3EnemiesHit` — Chance for additional Storm Stack when 3+ enemies hit (OnHit via ISIL).

**GlacierMutator**
- `chanceForSuperIceVortex` — Greater Ice Vortex chance, copied to each Glacier component (OnHit via ISIL) counted in DPS applier.
- `moreDamageToBosses` — More damage vs rares/bosses copied to each Glacier component (component not followed).
- `moreDamageAgainstChilled` — More hit damage vs chilled copied to each Glacier component (Double Chill node).

**GlyphOfDominionMutator**
- `moreExplosionDamagePerSlow` — Copied to GlyphOfDominionExplosionMutator.moreDamagePerSlow (explosion component not followed); LightningBlastMutator.Mutate also reads it.
- `glyphsExplodeAtSameTime` — Glyphs explode at same time when two glyphs exist (checked with glyph count == 1).
- `moreDoTPerArmorShredUpTo14Buff` — Conditional more DoT per armour shred stack (cap 14%) added to BuffOnAllyHit buffs (Stats.ConditionalMoreDamageStat 0x12, DoT).
- `wardPerSecondPerUncappedResistance` — Ward per second granted to allies on glyph, scaled with uncapped resistances (BuffOnAllyHit buff built from f; formula details not followed).
- `grantsAcceleratingStaticCharges` — Static charges gained at accelerating rate (gainingStaticCharges, totalChargesGainedPerInterval).
- `grantedLightningBlastChains` — Lightning Blast cast on glyph gets +f chains (read by LightningBlastMutator.Mutate, getChannelCost).
- `manaConsumedByLightningBlast` — Mana added to Lightning Blast channel cost on glyph (LightningBlastMutator.getChannelCost).

**HammerThrowMutator**
- `increasedAttackSpeed` — Added in getIncreasedCastSpeed (read via ISIL only).
- `freeWhenOutOfMana` — noManaCost and getIncreasedManaCost: hammer throw costs no mana when out of mana (actor mana check via ISIL).
- `noPierce` — Hammers do not pierce; with no chains and no chain history pierce removed; copied to hammer component.

**HarvestMutator**
- `necroticShred` — getTempStats / addsTempStats adds Necrotic resistance shred chance stat (read via ISIL in CopyToMinionMutator).
- `increasedBleedEffect` — Read in getTempStats (adds temp stat; tooltip: +50% physical penetration with bleed with Self Bleed node; exact stat not decoded).
- `zombieChanceOnKillOrRareBossHit` — Chance for Volatile Zombie on kill or rare/boss hit (OnKill read via ISIL).
- `chanceToSummonBloodWraith` — Chance for Blood Wraith on kill (OnKill via ISIL); bloodWraithStats applied.

**HealingHandsMutator**
- `moreDamageToVoidEnemies` — Conditional more damage vs Void enemies, built into ChanceToApplyAilmentsOnHit.ConditionalAilment/condition (ISIL-level detail).
- `moreDamageToUndeadEnemies` — Conditional more damage vs undead (Fear Undead node).
- `moreCastSpeed` — Copied to adapter applied in mutateUseSpeed (ISIL).

**HeartseekerMutator**
- `punctureOnRecurveChance` — Copied to arrow component (+0x3c): chance for Puncture per recurve after arrow dies.
- `moreAilmentDamageOnRecurve` — Copied to arrow component (+0x38): DoT more damage per recurve (8 stacks max per tooltip).
- `minimumRecurveChance` — Minimum recurve chance written to arrow component (Mutate).

**HolyAuraMutator**
- `finalHitDamageMultiplier` — Only read by getDPSAppliersForDPSCalculation (final hit of Flame Burst); in-game hit multiplier applied elsewhere.

**HungeringSoulsMutator**
- `increasedDamageWith3Minions` — getTempStats via ISIL: more damage when exactly three minions present.

**IceBarrageMutator**
- `freezeRateMultiplierPerCastOfFrostbolt` — Copied to barrage component (+0x148): freeze rate multiplier per Frostbolt cast (ice shard), up to freezeRateMultiplierPerCastMaxStacks.
- `freezeRateMultiplierPerCastMaxStacks` — Copied to barrage component (+0x14c): cap of per-cast freeze rate stacks.
- `chanceToCastFrostNovaOnHit` — Copied to barrage component (+0x154): chance to cast Frost Nova on hit (nova radius from increasedFrostNovaRadius).
- `moreDamagePerCastOfFrostbolt` — Copied to barrage component (+0x140): more damage per frostbolt cast, cap moreDamagePerCastMaxStacks.
- `moreDamagePerCastMaxStacks` — Copied to barrage component (+0x144): cap of per-cast damage stacks.
- `noHoming` — Copied to barrage component (+0x164): shards do not home.
- `chanceToMakePiercingProjectile` — Copied to barrage component (+0x138): pierce chance.
- `chanceToApplyForstbiteIfPiercingProjectile` — Copied to barrage component (+0x13c): frostbite chance on piercing shards.
- `increasedDelayBeforeFire` — Copied to barrage component (+0x130): delay before each shard fires.
- `increasedProjectilSize` — Copied to barrage component (+0x168): projectile size.
- `extraProjectiles` — Copied to barrage component (+0x184): extra frostbolts per volley.
- `addedMaxAngle` — Copied to barrage component (+0x180): cone width in degrees.
- `splinterOnHit` — Copied to barrage component (+0x188): ice shards shatter on hit.
- `moreCritToFrozenTargets` — Copied to barrage component (+0x12c): crit chance more vs frozen.
- `moreDamageToFrozen` — Copied to barrage component (+0x128): more damage vs frozen.
- `moreFreezeRateToNoDelayBolts` — Copied to barrage component (+0x170): Ice Burst freeze rate more.

**IceThornsMutator**
- `delayWindow` — Enum DelayWindow (0/1/2) selecting projectile delay/pattern in Mutate and OnHit (value 2 used for re-cast on hit).
- `damageAndFreezeBuffStacks` — Stacking buff on cast: stack index cycles up to f (byte), 4 s buff with stacks added to player (damage and freeze rate per tree text).

**InfernalShadeMutator**
- `increasedCastSpeed` — mutateUseSpeed (read via ISIL) and ChaosBoltsMutator.Mutate (Chaos Bolts casting shade).
- `explosionIncreasedArea` — Read only by ChaosBoltsMutator.Mutate; InfernalShadeMutator.Mutate does not read it (area may be applied in ShadeExplosionMutator via ISIL, not followed).

**JavelinMutator**
- `moreAttackSpeed` — mutateUseSpeed (read via ISIL only).
- `addedManaCost` — Added mana cost, read in getAddedManaCost via ISIL (tree +2 per point, -3, +10 for rain).

**JudgementMutator**
- `increasedRadiusConsecratedGround` — Consecrated Ground radius increase (read in Mutate via ISIL only).
- `eruptionMoreDamage` — Read only by getDPSAppliersForDPSCalculation (Holy Eruption more damage); in-game effect carried by eruptionStats (same tree node writes both).

**LethalMirageMutator**
- `lightningConversion` — Flag read only in addsTempStats; conversion amount comes from percentBaseDamageConvertedToLightning.

**LightTempestMutator**
- `chanceToGainGladiatorOfLagonStack` — Chance for Gladiator of Lagon stack when tempest cast (Mutate read via ISIL only).

**LungeMutator**
- `immobilizeOnHitDuration` — Copied to lunge component (+0x134): immobilize duration on final hit.
- `increasedHitAreaPerDistanceTraveled` — Copied to lunge component (+0x148): max area bonus reached at 10 m distance.
- `moreDamagePerDistanceTraveled` — Copied to lunge component (+0x14c): max damage bonus at 10 m distance.
- `cullEnemiesBelowHealthThresholdAtMaxDistanceTraveled` — Copied to lunge component (+0x150): cull threshold at max distance.
- `physicalPenPerEnemyHit` — Copied to lunge component (+0x158): physical penetration per enemy hit.
- `chanceToCast3SmitesOnArrivalAtMaxDistanceTraveled` — Copied to lunge component (+0x160): chance for 3 Smites on arrival at max distance.
- `shieldBashAtEnd` — Copied to lunge component (+0x138): Shield Bash after lunge (shieldBashMut; written by Shield Bash tree).

## 7. Gaps and limitations

- Component logic where fields copied not parsed: FrenzyTotemAdapter, FlameRush, Ice Barrage component, Lunge component, HealingHands adapter, etc. (see D?).
- Fields read via ISIL only (e.g., `getAddedManaCost`, `mutateUseSpeed`, parts of `OnHit/OnKill`) marked D? if constants/branches couldn't be confirmed by direct read.
- Values `per_point`/`flat` taken from `trees`/`tree_node_stats` as-is; in `formula` provided only as reference do not replace data from `skill_node_effects.json`.
- Stat/AT/SP identifiers in some places (ward per second 0x5c, block 0x1d/0x35, mana drain 0x39, etc.) derived from node names; enum verification done where enum known (`sp_enum.json`).
- List of gaps per mutator — in `out/_notes_AL.json` (field `gaps`), duplicated in section 5.
