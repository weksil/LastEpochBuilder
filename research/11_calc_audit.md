# Calculator vs game code audit (2026-10-09)

Read-only workflow: 11 area auditors, each finding re-checked by a skeptic against the dump (139 confirmed, 9 unverified, 3 refuted). Within a part: high impact first. Findings 0/33 and 1/34 are duplicates reported from two areas. Items marked (both) touch DPS and defence.


# Part 1. Findings that affect DPS (102)

## #0 [stat-model] Affix ranges with min > max (Descending) are rolled in the wrong direction
- impact: High for the affected affixes. The best roll yields the worst value and vice versa, and mid rolls differ by 1 grid step. Wrong 'less damage taken on block', channel cost and evade-cooldown affixes change defences and ability stats.
- calculator: `client/scripts/engine/affix_math.gd roll_value(), lines ~300-306 (if a > b: swap a and b), called from item_mods.gd:202 and build_mods.gd:264` — When the rounded lo > hi the code swaps a and b, then uses the ascending formula min(floor((b-a+1)*roll/255 + a), b). Roll 0 therefore gives the numerically smaller of the two endpoints and roll 255 the larger.
- game: When raw max < min, v = max(ceil-or-trunc((b - a - 1) * roll/255 + a), b) / s with a = round(min * s) and b = round(max * s), where a is the larger endpoint. Roll 0 gives the first number (min as written in the data) and roll 255 gives the second (max as written). The calculator should detect lo > hi on the raw values, before the effect modifier and rounding, and use this descending formula instead of swapping endpoints.
- evidence: dump/decomp/LE.dll/EpochExtensions.c GetValueAfterRounding_1 (~line 17030-17055): "if (param_5 < param_4) { EpochExtensions_DescendingValueAfterPropertyRounding(param_1,param_4,param_5,param_6,0); } else { ...Ascending...". The same dispatch appears at lines ~16978-16985 in the other overload. Descending (EpochExtensions.c:14359+): "FUN_18037c870((double)((float)((iVar2 - iVar1) + -1) * ((float)pa

## #7 [hit-damage] Hammer Throw 'aoeVoidDamage' modelled as 100% Physical->Void conversion; the game adds a separate Void damage zone and converts nothing
- impact: High for builds that take this node: the main hit is computed against Void resistance/modifiers instead of Physical (wrong by the resist/increased-damage difference), and the real extra source (Void aura, 8*(1+inc) per 0.2 s tick as a DoT-tagged zone) is missing. Also no rule exists for the manager flag Phys->Lightning conversion.
- calculator: `research/data/game/skill_conversions.json key HammerThrowMutator.aoeVoidDamage (convert Physical->Void 1, tags_add Void, tags_remove Physical, tags_when active), applied by SkillCalc._apply_conversion` — With the node 'Hammer Throw Tree Void Damage In Aoe' all Physical base damage of every Hammer Throw component is moved to Void, so resistance, increased/more and penetration use the Void cell. The rule's evidence text ('converts physical damage (convertBaseDamage 0->3 per tag)') came from the semantics description, and the field_models note says 'Physical damage becomes Abyss damage; base +8 Abyss aura counted separately', but no such aura compon
- game: With aoeVoidDamage, the Hammer Throw hit stays Physical. The game adds an extra damage zone component of (increasedAoEVoidDamage+1)*8 Void base damage, with added-damage scaling, ticking every 0.2 s, tags 0x1400, and radius (area+1)*2.2. Void is type 5, or Lightning (type 3) if hammerThrowLightningConversion (manager +0x1440) is set. Physical to Lightning conversion (convertBaseDamage 0,3,1.0 on all DamageStatsHolders) is tied to that manager flag, not to aoeVoidDamage.
- evidence: dump/decomp/LE.dll/HammerThrowMutator.c, Mutate, lines ~822-880: "if (*(char*)(param_1+0x155)=='\0') ... else { ... GetOrAddComponent<RepeatedlyDamageEnemiesWithinRadius> ... uVar6 = 3; if (cVar3=='\0') uVar6 = 5; DamageStatsHolder_addBaseDamage(lVar9,uVar6,(*(float*)(param_1+0x2b)+1.0)*8.0,0); DamageStatsHolder_calculateAddedDamageScaling(lVar9,0,0); *(lVar9+0x128)=0x3e4ccccd; *(lVar9+0x98)=0x140

## #8 [hit-damage] Dancing Strikes 'bleedConvertedToPoison' modelled as 100% Physical->Poison base-damage conversion; the game only sets the Poison tag, hit-VFX theme and Bleed->Poison ailment conversion
- impact: High for that node: hit damage keeps Physical typing in the game, the calculator evaluates it as Poison. The ailment side (Bleed->Poison) is the real effect.
- calculator: `research/data/game/skill_conversions.json key DancingStrikesMutator.bleedConvertedToPoison (convert Physical->Poison 1, tags_remove Physical); SkillCalc._apply_conversions (skill_calc.gd:792-848)` — All Physical base damage of Dancing Strikes becomes Poison with the node allocated (Poison resistance, poison increased/more, poison penetration). The rule is named by the node text 'Bleed to Poison' and the evidence text says 'tags |= Poison ... Physical -> Poison penetration'.
- game: With the node allocated, hit base damage stays Physical, so Physical scaling and Physical resistance still apply to the hit. The skill gains the Poison tag (0x40), so Poison-tagged modifiers can apply. The hit VFX theme becomes Poison, and Bleed is converted to Poison as an ailment. Only the separate manager flag 0x1c18 converts Physical base damage, and that converts it to Fire, not Poison.
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\DancingStrikesMutator.c:
- GetConversionType, lines 233-235: `if (*(char *)(alStackX_18[0] + 0x1c18) != '\0') { return 2; } ... return (ulonglong)(*(char *)(param_1 + 0x148) != '\0');`
- Mutate consumer, lines 878-890: `*(undefined1 *)(lVar9 + 0xf8) = 1; if (iVar6 == 1) { uVar11 = uVar11 + 1; *(undefined1 *)(lVar9 + 0xf9) = 6; } else { if (iVar6 == 2) { Damag

## #9 [hit-damage] Swipe Storm Claw (stormClawEvery3Seconds) applied to every Swipe as a permanent 100% Physical->Lightning conversion; the game converts only the Swipe that finds the Storm Claw cooldown ready
- impact: High for builds with the node at high attack speed: only about one Swipe per ~3 s (cooldown, reducible) is fully Lightning; the calculator gives all Swipes 100% Lightning (wrong resistance and damage-type multipliers; the same cooldown also gates increasedAreaWithStormClaw). The 'full_conversion'/tag handling also differs for partial conversion: th
- calculator: `research/data/game/skill_conversions.json key SwipeMutator.stormClawEvery3Seconds (convert Physical->Lightning fraction 1.0, tags_when full_conversion) with SkillCalc._apply_conversions (skill_calc.gd` — Whenever the node is allocated, 100% of Swipe base damage is Lightning on every use, in addition to the partial baseDamageConvertedToLightning rule (also applied, dedupe key differs). The evidence text itself says 'every 3 s the next Swipe is converted' but the rule treats it as unconditional.
- game: Only the Swipe that finds the Storm Claw timer at 0 or below is fully (100%) converted Physical->Lightning. That Swipe starts a cooldown of (1 - reduction) * stormClawCooldown, counted down in real time, and Swipes during the cooldown get only the normal partial conversion fraction. Totem summon can reset the cooldown. The correct model is an uptime-weighted average, roughly one fully converted Swipe per cooldown period, not 100% Lightning on every Swipe.
- evidence: SwipeMutator.c:933-938: `if ((*(float *)(param_1 + 0x1c0) <= 0.0) && (SwipeMutator_StormClawLightningConversionEvery3Seconds(param_1,0) != 0)) { uStackX_8 = 1; fVar16 = 1.0; *(undefined1 *)(param_1 + 0x1c4) = 1; }`. Only a Swipe that finds the timer at 0 or below gets fraction 1.0.
SwipeMutator.c:1229-1243: `if (0.0 < fVar16) { ... fVar15 = min(fVar16, 1.0); DamageStatsHolder_convertBaseDamage(lVa

## #17 [speed-mana-cooldown] Cooldown recovery from items/affixes (ADDED SP70) is ignored by the cooldown formula
- impact: High for cooldown-limited skills: cooldown recovery from gear affixes/uniques does not reduce the displayed cooldown or the cooldown cap on uses/s (cap = 1/cd). The Minion/Totem tag exclusion (0x6000) is also not applied, so Minion-tagged CDR can leak into a summon skill's own cooldown.
- calculator: `client/scripts/engine/skill_calc.gd:1163-1166 (cooldown_info: cdr.increased only); client/scripts/engine/build_mods.gd:474-475 and altar_mods.gd:239 create CDR as 'increased'` — cooldown_info queries LE.CDR (SP70) and uses only StatQuery.increased (rec_inc = cdr.increased + tree values). Mods with modType ADDED land in StatQuery.added and are dropped. Passive/idol sources are wrapped as 'increased' CDR, item sources stay ADDED.
- game: Cooldown = 1 / (chargesGainedPerSecond * (1 + sum of ADDED SP70 for the ability, excluding Minion/Totem-tagged stats)). The calculator's recovery term must use cdr.added together with (or instead of) cdr.increased, and must exclude stats with tags & 0x6000 for the player's own skills.
- evidence: dump/decomp/LE.dll/Ability.c:1169-1195 (Ability_GetCooldownWithStats: Stats_GetTotalAddedForAbility(...,0x46,...); fVar3=1/((fVar2+1.0)*chargesPerSec)). dump/decomp/LE.dll/PlayerChargeManager.c:289-297 ('F' check, (tags & 0x6000)==0, fVar11 += *(float*)(stat+0x1c)). dump/decomp/LE.dll/ChargeManager.c:349-362 (base function returns +0xD8). research/data/game/affixes.json data/27, data/893 (untagged

## #20 [speed-mana-cooldown] Rate of channelled skills: uses/s = speed*mult*1.1/useDuration contradicts the game's own channel model (and beam tick interval)
- impact: High for Disintegrate / Drain Life / Ghostflame / Runebolt-channel style builds: calc rate is 5.5*S vs the game model 4.4*S (or 4/s fixed) for Disintegrate (x1.25), and for Drain Life 16.5*S vs 3.3*S x (1/interval); the true rate is UNKNOWN but the calc number rests on useDuration, not on any game channel code.
- calculator: `client/scripts/engine/skill_calc.gd:1081-1090 (uses = speed_scale / useDuration, no channel branch); client/data/field_models.json DisintegrateMutator.addedUseDelay = display-only param 'delay'` — A channelled skill is treated like any other: every 'use' (useDuration/speedScale: Disintegrate 0.2 s, Drain Life 0.2 s with speedMultiplier 3, Ghostflame 0.2 s x3) deals the listed damage once. Disintegrate = 5.5*S hits/s, Drain Life = 16.5*S, Ghostflame = 16.5*S. Disintegrate's 'Kamehameha' node (addedUseDelay) does not change useDuration.
- game: Disintegrate's beam applies damage once per damageInterval (0.25 s = 4 applications/s), via a timer in DamageEnemiesWithBeam.OnUpdateTick that reads no cast speed. The game's tooltip DPS is S*speedMultiplier*1.1/1.0 (channelled) times 1/damageInterval, which is 4.4*S for Disintegrate. Whether the real tick rate scales with cast speed is UNKNOWN: the channel repeat loop is not traced. The calculator's 5.5*S (useDuration 0.2) is not supported by any of this code. For Drain Life and Ghostflame the interval comes from prefab values that are not in 
- evidence: - client/scripts/engine/skill_calc.gd:1081-1090: `var uses: float = speed_scale / (1.0 if instant or duration <= 0.0 else duration)`, no channelled branch.
- dump/decomp/LE.dll/AbilityMutatorManager.c:2568-2573: `cVar6 = FUN_18000e8c0(5,_AbilityTooltipTagInfoProvider__TypeInfo,plVar23); if (cVar6 == '\0') fVar26 = FUN_1800141b0(9,_AbilityInfo__TypeInfo,...); else fVar26 = 1.0; fVar26 = (fVar25 * f

## #21 [speed-mana-cooldown] Minion attack/cast rate ignores Ability.speedMultiplier
- impact: High for minion builds: minion damage/s is off by the multiplier (up to x1.5, or x0.67-0.85) for every one of those minions.
- calculator: `client/scripts/engine/minion_calc.gd:272-276 (per_second = speed * 1.1 / duration)` — Minion uses/s = (1+added)(1+inc)*more * 1.1 / useDuration; ability.speedMultiplier and maximumUseSpeed are not read.
- game: The use rate of any actor, including minions, is scaled by ability.speedMultiplier. Minion uses/s should be speed * speedMultiplier * 1.1 / useDuration, and the maximumUseSpeed cap should be applied the same way as for the player.
- evidence: 1) client/scripts/engine/minion_calc.gd:274-275 reads `var speed = (1+added)*(1+inc)*more` and `var per_second = speed * 1.1 / duration`. _use_duration (168-181) takes only the useDuration or castSpeedOverrides duration. The only speedMultiplier / maximumUseSpeed references in client/scripts/engine are in skill_calc.gd (1074, 1082, 1089).
2) dump/decomp/LE.dll/UsingAbility.c, UsingAbility_getSpeed

## #32 [character-attrs] Cooldown recovery (SP 70) from gear, uniques and passive nodes is ignored: the calculator reads only the increased part, the game sums the added part
- impact: HIGH for skills with a cooldown: any CDR on gear/uniques/passives is dropped, so cooldown-capped uses per second and everything derived (trigger limits, DPS caps) are overstated in cooldown. Fix is to read q.added + q.increased as minion_calc does.
- calculator: `client/scripts/engine/skill_calc.gd:1163-1164 (cooldown_info: cdr.increased); fed by item_mods.gd:117-119 and 217-219 (ADDED -> mod.added), build_mods.gd:1181-1219 (kind added -> added), altar_mods.gd` — cooldown_info does rec_inc = store.query(LE.CDR).increased + field models. Every affix, unique mod and passive/skill-node stat of IncreasedCooldownRecoverySpeed is stored in .added, so none of them reaches the recovery speed. Only the altar prop 21 and the 'recovery_increased' field models are written as increased. minion_calc.gd:208-212 correctly uses q.added + q.increased.
- game: Cooldown recovery speed from SP 70 is the sum of ADDED values (gear, uniques, passives, altar). The calculator should use cdr.added + cdr.increased when computing recovery in cooldown_info, as minion_calc.gd does.
- evidence: dump/decomp/LE.dll/Ability.c:3894-3896 `uVar3 = Stats_GetTotalAdded(*(longlong *)(param_2 + 0x50),0x46,0,0,0,0,0); ... fVar4 = (float)uVar3 + 0.0;`. research/data/game/affixes.json: property 70, propertyName IncreasedCooldownRecoverySpeed, modType 'ADDED' (5 entries, none INCREASED). client/scripts/engine/skill_calc.gd:1164 `var rec_inc: float = cdr.increased + ...`. client/scripts/engine/item_mod

## #55 [enemy-side] Armour against enemy DoT/ailments uses the PLAYER's SP118 share; the game reads the victim's own SP118
- impact: HIGH for builds with an 'armor applies to DoT' affix/unique when the target has armour: the calculator reduces DoT/ailment DPS by armour mitigation x share, while the game applies none. It is a systematic underestimate of ignite, bleed, poison and similar DoT DPS vs armoured targets, proportional to the share and the target's armour.
- calculator: `client/scripts/engine/skill_calc.gd:1211 and 1251-1254; client/scripts/engine/ailment_calc.gd:265 and ~285 (armour_share = minf(1.0, ctx["store"].query(118).added))` — For DoT and ailment damage against the target, the enemy's armour mitigation is multiplied by the attacker's own stat 118 (ArmourMitigationAppliesToDamageOverTime, from the player's gear/passives), as 1 - mit*share. The share is read from the attacker's skill store, not from the enemy store.
- game: The proportion is taken from the damage receiver's own SP118 (`PrecalculatedStatsHolder +0xCC`). The attacker's SP118 does not affect DoT dealt to an enemy. An enemy with no SP118 gets 0 armour mitigation on DoT and ailment damage. The player's SP118 only reduces DoT that the player takes.
- evidence: dump/decomp/LE.dll/ProtectionClass.c, ProtectionClass_ApplyDamage, near lines 916-927: `if ((uStack_294 & 1) == 0) { if (*(float *)(param_2 + 0xcc) != 0.0) { fVar35 = PrecalculatedStatsHolder_mitigationFromArmour(param_2); fVar34 = *(float *)(param_2 + 0xcc); if (1.0 < fVar34) fVar34 = 1.0; fVar43 = (1.0 - fVar35 * fVar34) * fVar43;`
The same function reads `param_2+0xf8` (the actor) and writes `p

## #82 [minions-shadows] Minion use rate uses the player's 1.1 constant; minions use 1.0
- impact: HIGH. Every minion DPS (all summon skills) is overstated by 10% from the speed term. It also distorts the cooldown and charge share split, because per_second sets how much of the time a cooldown ability occupies.
- calculator: `client/scripts/engine/minion_calc.gd:275 (per_second = speed * 1.1 / duration)` — Every minion ability's uses per second is multiplied by 1.1, copied from the player's baseUseSpeedMultiplier.
- game: Minion uses per second = speed * baseUseSpeedMultiplier / useDuration, with baseUseSpeedMultiplier = the prefab's serialized UsingAbility.baseUseSpeedMultiplier (default 1.0). The 1.1 applies only to the player. In minion_calc.gd:275 the multiplier should be the minion's own value, 1.0 unless a prefab says otherwise.
- evidence: 1. Calculator: client/scripts/engine/minion_calc.gd:275 reads `var per_second: float = speed * 1.1 / duration`.

2. Player-only constant: dump/decomp/LE.dll/UsingAbilityPlayer.c lines 5629-5639, `UsingAbilityPlayer_getBaseUseSpeedMultiplier(void) { return 0x3f8ccccd; }`. That is 1.1f. The method exists only in UsingAbilityPlayer (dump/cs/DiffableCs/LE/UsingAbilityPlayer.cs:211).

3. Base class use

## #83 [minions-shadows] Ability.speedMultiplier is ignored for minion abilities
- impact: HIGH for the affected minions. Attack rate is off by up to +/-50%, and by x3 for Hive. This hits Skeletal Mage, Death Knight, Cryomancer, Pyromancer, Ballista, Bear, Golems, Sabertooth, Rogue, Falcon, Hive and Wisp.
- calculator: `client/scripts/engine/minion_calc.gd:273-275 (speed, per_second); skill_calc.gd:1082 applies it only for the player's skills` — uses/s = (1+added)(1+inc)more * 1.1 / useDuration. The ability asset's speedMultiplier is never read for minions.
- game: Minion uses/s = speedScale / castDuration, where speedScale = mutated stat speed * Ability.speedMultiplier * baseUseSpeedMultiplier. The calculator should multiply the minion per_second formula by the ability's speedMultiplier (default 1.0), as skill_calc.gd does for player skills.
- evidence: dump/decomp/LE.dll/UsingAbility.c:5464-5526 (UsingAbility_getSpeedMultiplier): "fVar1 = *(float *)(lVar4 + 0x60); ... fVar7 = (float)uVar9 * fVar1 * fVar7; if (fVar7 <= 0.0) fVar7 = 0.1". UsingAbility.c:690-728 (InitialiseAbilityUse): "fVar15 = *(float *)(lVar7 + 0x60); ... fVar14 = fVar14 * fVar15 * fVar12; ... *(float *)((longlong)param_1 + 0x11c) = fVar14" (speedScale). dump/cs/DiffableCs/LE/Ab

## #84 [minions-shadows] halfSkeletons (and noSummonSkeletons) are not applied to the skeleton limit
- impact: HIGH when that node is taken. The calc counts twice as many skeletons, and the node's statList damage bonus also applies, so DPS is overstated by roughly x2. The ordering of 4 (add) then 21 (double) in LIMIT_PROPERTIES matches the code.
- calculator: `client/scripts/engine/minion_count.gd:130-179 (limit_of) and GROUPS['SummonSkeleton']; client/data/field_models.json SummonSkeletonMutator.halfSkeletons (kind flag only)` — The limit is 3 + added params + AbilityProperty 4, then doubled by AbilityProperty 21. The tree node 'Skeletons halved' is only a text flag, so the count stays full.
- game: limit = sum+3 (sum = param fields at +0x120 and +0x124, plus manager addedSkeletonSummonCap). With halfSkeletons set and doubledMaxSkeletons clear, the limit is rounded(limit * ~0.5). With both set, the limit is sum+3 (cancel). With only doubledMaxSkeletons set, the limit is 2*sum+6. With noSummonSkeletons set and no ignoreLockout, the limit is 0.
- evidence: dump/isil/IsilDump/LE/SummonSkeletonMutator.txt, getSkeletonLimit: lines 16-18 read [rax+6228]=0x1854 noSummonSkeletons, [rax+6208]=0x1840 added cap, [rax+6229]=0x1855 doubledMax. Lines 26-29 compute eax = [rbx+292]+[rbx+288]+rdx+3. Line 30 'Compare [rbx+472], rcx' jumps to the plain return (cancel). Lines 32-36 'Compare [rbx+472], 0' then 'LoadAddress rax,[6]' (2*sum+6 path). Line 46 'Multiply xm

## #102 [buffs-and-skillbuffs] Per-second / per-tick ailment chances of channels, auras and areas without a prefab zone are rolled per hit event
- impact: Potentially high for these skills. The application rate is either understated (one roll per cast instead of f per second over the lifetime) or absent, e.g. for buff-only channels.
- calculator: `client/data/field_models.json stat=AilmentChance fields described as chance per second: BlackHoleMutator.chanceToBlind/Chill/IgnitePerUncappedFireRes, DevouringOrbMutator.frailtyChancePerSecond/timeRo` — The field value f is added as a per-hit AilmentChance. The hit-event rate is uses/s * per_use * hits (skill_calc.gd ~595). Only AuraOfDecay (and Smoke Bomb, Blizzard, ...) have a prefab zone with a tick interval; research/data/game/abilities.json has no RepeatedlyApplyAilmentsInRadius entry for BlackHole, DevouringOrb, Focus, HailOfArrows, InfernalShade, Ghostflame, DrainLife or Disintegrate.
- game: While the Black Hole, orb or channel exists, enemies in its radius get f chance per second of the ailment, rolled on a tick (Black Hole 0.5 s, each tick adding f*0.5). That chance is independent of any hit event. The calculator should model it as a zone with interval and chance f*interval, the way it does for prefab zones, rather than as a per-hit chance.
- evidence: dump/decomp/LE.dll/BlackHoleMutator.c, Mutate, lines ~611-646: "if ((0.0 < *(float *)(param_1 + 0x28)) || (0.0 < *(float *)(param_1 + 0x27)) || (0.0 < *(float *)(param_1 + 0x2d)))" then "Comp_1_System_Object__GetOrAdd_1(param_2, ...RepeatedlyApplyAilmentsInRadius...GetOrAdd...)". Next come three calls "RepeatedlyApplyAilmentsInRadius_addChance(lVar9, Ailment_getAilment(3,0), *(float *)(param_1 + 0

## #109 [uniques] All 52 'component' models (Component:* special effects) are never applied
- impact: High. The effects of about 40 uniques are absent from the numbers although models exist and were audited. Cold/Fire damage per Dexterity or level (Mourningfrost, Frozen Ire, Hammer of Lorent) and the trigger casts are lost; the user only sees a note.
- calculator: `client/scripts/engine/unique_effects.gd:_entries (lines 36-44) looks up a model only for source PlayerProperty (line 41) and AbilityProperty (line 42). client/scripts/autoload/game_data.gd:453 unique_` — Component effects get model = {} and UniqueEffects.add_notes prints 'trigger or a separate mechanic, not modelled'. All 52 hand-written entries are dead data (about 26 stat, trigger and resource models): Keepers Gloves 22:0, Frozen Ire 32:0 and 32:1, Volcanus 48:0, Bone Harvester 40:0, Pontifex 42:0, Soul Bastion 52:0, Strong Mind 54:x, Arboreal Circuit 65:0, Ignivar Head 74:1 and 74:2, Urzils Pride 10:0, Preparation 12:x, Mourningfrost 19:0, Ham
- game: Component:* unique effects should be resolved through unique_component_model(unique_id, effect_index) in UniqueEffects._entries. The result should then flow through apply_global and apply_skill, which already list 'component' in SKILL_KINDS.
- evidence: D:\LastEpochBuilder\client\scripts\engine\unique_effects.gd lines 40-44: 'if src == "PlayerProperty": model = GameData.unique_player_model(...)' and 'elif src == "AbilityProperty": ... model = GameData.unique_ability_model(...)'. There is no Component branch, so model stays {}.
unique_effects.gd line 266: 'src.begins_with("Component")' returns the 'trigger or a separate mechanic, not modelled' not

## #110 [uniques] Eternal Eclipse (pp161-164) applied to every melee skill on every hit; the game gives it to one Void+Melee (or Fire+Melee) use per 2 s
- impact: High for Eternal Eclipse: +200-240 added damage on every hit of every melee skill instead of about one use per (2 s x attack rate), and on skills that are not Void+Melee.
- calculator: `unique_effect_models.json player 161, 162, 163, 164 (kind stat, global scope, input default true, no skill_any), applied by UniqueEffects.apply_global into the global store` — Added Fire|Melee damage and +Ignite chance (161/162), or added Void|Melee damage and +Time Rot chance (163/164), as permanent global StatMods. They apply to every skill carrying the Melee tag at 100% of uses.
- game: Eternal Eclipse effects apply only to a use whose ability tags contain both Void and Melee (pp161/162, mask 0x210) or both Fire and Melee (pp163/164, mask 0x208). They apply only while the 2.0 s cooldown field is <= 0, and a real use resets it to 2.0 s. So there is at most one enhanced use per 2 s, not every hit of every melee skill.
- evidence: dump/work_wave3/pp/pp_161.txt, CharacterMutator.ApplyConditionalTemporaryStats: `if ((meleeFireDamageWithNextVoidMeleeAttackEvery2Seconds != 0 || igniteChanceWithNextVoidMeleeAttackEvery2Seconds != 0) && remainingCooldownOfDamageAndIgniteChanceOnNextVoidMeleeAttack <= 0.0 && (uVar11 & 0x210) == 0x210) { if (param_5 != 0) { cooldown = 0x40000000; ...} Stats_AddedStat(0,0x208); Stats_AilmentChanceSt

## #111 [uniques] Vaion's Chariot (pp228): MORE damage applied to every skill permanently; the game gives it to the next movement skill every 3 s
- impact: High: 24-40% more damage on every skill on the bar instead of a short buff on movement skills.
- calculator: `unique_effect_models.json player 228 (stat Damage more, scope global, input next_move_skill default true, note 'movement abilities only, every 3 sec', confidence D?)` — A permanent global MORE Damage of pp (24-40%) for all skills.
- game: Vaion's Chariot grants MORE Damage (pp 24-40%) only to a movement-skill use (countsAsMovementAbility) when its internal 3.0 s cooldown has expired. The cooldown starts when the use is applied, so the bonus is at most one movement-skill use per 3 s. It does not affect non-movement skills. The calculator should either restrict the bonus to movement skills or make the toggle default to off.
- evidence: dump/work_wave3/pp/pp_228.txt, CharacterMutator.ApplyConditionalTemporaryStats: `if ((moreDamageWithNextMovementSkillEvery3Seconds != 0.0) && (...RemainingCooldown <= 0.0)) { cVar6 = EpochExtensions_countsAsMovementAbility(...); if (cVar6 != '\0') { ... Stats_MoreStat(0,0) ... List.Add ...; if (param_5 != 0) { ...RemainingCooldown = 0x40400000 (3.0) ...`. The same file's ISIL for OnUpdateTick show

## #115 [uniques] Downfall of the Righteous (pp521) scales from the wrong stat
- impact: High for this unique: the model multiplies by generic increased damage (often hundreds of percent) instead of curse-damage increases.
- calculator: `unique_effect_models.json player 521 (Damage more, tags Ailment, per increased:Damage, note 'counted from all damage increase (approximation)'); EffectModels.source 'increased' = StatStore.query_untag` — MORE damage = v x (untagged increased Damage total) on ailment damage.
- game: Witchfire more damage = moreWitchfireDamagePerIncreasedCurseDamage × (sum of increased Damage stats whose tag is exactly Curse, from the ailment source actor's stats). This is then combined with the ignite-chance and damned-chance terms as (curseTerm+1)×(igniteTerm+1)−1.
- evidence: dump/work_wave3/pp/pp_521.txt, CharacterAilmentMutator.GetAilmentDamageModifier, lines 36-41:
`uVar7 = Stats_GetTotalIncreasedExactMatch(lVar1,0,0x1000000,0,0,0);`
`fVar8 = (float)uVar7 * *(float *)(param_2 + 0x1780/*moreWitchfireDamagePerIncreasedCurseDamage*/);`
`fVar8 = (fVar8 + 1.0) * (fVar10 + 1.0) - 1.0;`

dump/decomp/LE.dll/Stats.c, lines 2825-2829: GetTotalIncreasedExactMatch(SP, AT, Byte,

## #121 [uniques] Runic Invocation 'chance per Intelligence' (689:24-26): the reader rolls with the raw field, no Intelligence multiplication found
- impact: Potentially high: with 100 Int the model gives 100% of the bonus, the code as read gives 1-3%. If an Intelligence factor is applied somewhere not found in the traced code, the model is right; needs a check that does not depend on the tooltip.
- calculator: `unique_effect_models.json ability 689:24, 689:25, 689:26 (Damage more / Penetration / Damage increased, per attr:int, max 11% / 22% / 33%, note 'chance per Intelligence x ... (average)')` — Average bonus = min(1, v x Intelligence) x 11% / 22% / 33%, i.e. 1% x Int chance per invocation.
- game: When the number of runes in the invocation is 1, 2 or 3, the code rolls RngElement.Roll(summed mod value). A hit grants one flat stat: MoreStat(0,0x80), AddedStat(0x3b,0x80) or IncreasedStat(0,0x80). The chance does not scale with Intelligence in the code read. Expected bonus is therefore (mod value) x 11% / 22% / 33%, not min(1, value x Int) x those amounts.
- evidence: dump/decomp/LE.dll/RunicInvocationMutator.c:2607, 2620 and 2636: "cVar5 = RngElement_Roll(lVar9,*(undefined4 *)(alStack_68[0] + 0x808),0" (and 0x80c, 0x810). After a successful roll the code goes straight to Stats_MoreStat(0,0x80) / Stats_AddedStat(0x3b,0x80) / Stats_IncreasedStat(0,0x80) and adds the stat to the list. There is no Intelligence read in between. In the same function, the 0x994 field

## #128 [passives-and-sets] Passive Stats.PlayerPropertyStat / MorePlayerPropertyStat / AbilityPropertyStat effects are not applied at all (about 168 PlayerProperty and 67 AbilityProperty node effects)
- impact: High for builds that rely on these nodes (the numbers are silently low; the Notes list says 'not counted'). Affects speed, crit, ailment chance, more-damage multipliers of many mastery nodes.
- calculator: `client/scripts/engine/build_mods.gd _add_passives (L289-317) -> stat_from_effect (L1181-1215) returns null for kind player_property / more_player_property / ability_property / more_ability_property / ` — Only a handful of passive PPs are consumed by dedicated code (enemy_ailments.player_property for shroud/essence buffs, defense_conversions, ShadowCalc/MinionCalc for summon properties). Everything else is dropped with a note. Damage- or speed-relevant examples dropped: PP 93 damage per 100% movespeed (Agility), 94/95 crit chance per Sword/Dagger, 98/99 bleed/poison chance per Sword/Dagger, 106 more bow damage per mana cost, 113 added damage per E
- game: Passive Stats.PlayerPropertyStat, MorePlayerPropertyStat and AbilityPropertyStat effects are applied by the CharacterMutator. The calculator should map each property index to its game effect. For example, PP 171 adds increased attack speed and cast speed while a sword, axe or the 0x10 weapon type is held, or weaponRequirementFulfilled(3,0xc) holds.
- evidence: client/scripts/engine/build_mods.gd: `_add_passives` L289-317 calls `stat_from_effect` and then `_passive_unmodelled` (L412). `stat_from_effect` (L1181-1215) ends the kind match with `_: return null`. `_passive_unmodelled` appends "Passive \"%s\": %s — not counted".
research/data/game/passive_node_effects.json: kind counts under CharacterMutator.stats are player_property 157, more_player_property 

## #10 [hit-damage] Per-stack conditional more damage (SP 115 and SP 117 with per-stack conditions) multiplies (1 + m*n) per more-value; the game combines the stat's more values first and then scales by stacks
- impact: Medium/low: overestimates when two or more identical-key per-stack more modifiers (items, idols, passives) are stacked; exact when a single source exists.
- calculator: `client/scripts/engine/skill_calc.gd:1331-1352 (_condition_factor: for m in mod.more: f = 1 + m*count; cond *= f)` — For a per-stack condition with several 'more' values on the same stat key the factor is Prod(1 + m_i * stacks).
- game: For per-stack conditional more damage, the game combines all more values of the merged same-key Stat first: per = Prod(1+m_i) - 1. The damage factor is then 1 + stacks*per (stacks capped by the per-condition limit), not Prod(1 + m_i*stacks).
- evidence: dump/decomp/LE.dll/Stats+Stat.c getMoreMultiplier (lines ~1377-1415): fVar5 = 1.0; loop over the list at +0x28: fVar5 = fVar5 * (item + 1.0). HasNonZeroMoreValue (lines 434-445): *param_2 = getMoreMultiplier - 1.0. dump/decomp/LE.dll/BaseStats.c AddStatModifier (lines ~130-165): for the more mod type (param_4 == 2) the value is added with List<float>.Add on the existing exact-match Stat at +0x28, 

## #22 [speed-mana-cooldown] Minion base use-speed constant 1.1 is applied to minions without support
- impact: Medium-high: if prefab values are 1.0, every minion attack rate is overstated by 10%; if prefabs differ per minion the error is minion-specific. Needs a prefab read of UsingAbility.baseUseSpeedMultiplier.
- calculator: `client/scripts/engine/minion_calc.gd:275 ('speed * 1.1 / duration')` — Minions get the player's constant 1.1 baseUseSpeedMultiplier.
- game: For player actors the factor is the constant 1.1. For monsters and minions it is the serialized UsingAbility.baseUseSpeedMultiplier, which defaults to 1.0 and can differ per prefab. The calculator should use that prefab value, or 1.0 where unknown, instead of the player's 1.1. The prefab values have not been extracted.
- evidence: client/scripts/engine/minion_calc.gd:275 `var per_second: float = speed * 1.1 / duration`.
dump/decomp/LE.dll/UsingAbilityPlayer.c:5629-5636: UsingAbilityPlayer_getBaseUseSpeedMultiplier returns 0x3f8ccccd (1.1).
dump/decomp/LE.dll/UsingAbility.c:3729 and UsingAbilityAI.c:140 both have `*(undefined4 *)(param_1 + 0x154) = 0x3f800000;` (1.0f default).
dump/cs/DiffableCs/LE/UsingAbility.cs:68 `public

## #25 [speed-mana-cooldown] Mutator overrides of getUseDuration / getUseDelay are ignored (node-selected modes change cast time)
- impact: Medium for the affected node choices: attack/cast rate wrong by the ratio of the durations (Detonating Arrow melee conversion x1.2, Earthquake slam as bear x0.67, Disintegrate Kamehameha etc.); NOTE: which of these modes the calc enables through other models was not traced, only that the duration is never read.
- calculator: `client/scripts/engine/skill_calc.gd:1081 (duration = ab.useDuration only); field models DetonatingArrow convertedToMelee, Avalanche traversalMode, EarthquakeSlam usedByBear, FrostClaw isLeapingAtStart` — Cast time always comes from the ability asset (and the minion castSpeedOverrides).
- game: Use duration = AbilityInfo.getUseDuration(useType), unless a CastSpeedManager override exists. For a mutated skill this goes through the mutator. For example, Avalanche in traversalMode gives 0.75 (0x3f400000), Earthquake Slam with usedByBear gives 1.5 (0x3fc00000) and Detonating Arrow converted to melee gives 0.75; otherwise the mutator returns the asset value. The cast duration is then useDuration / speedScale, and the same applies to useDelay.
- evidence: 1. Calculator: client/scripts/engine/skill_calc.gd:1081 has `var duration: float = float(ab.get("useDuration", 1.0))`. A grep of client/scripts/engine for useDuration/useDelay finds only the ability asset value there, plus the minion castSpeedOverrides path in minion_calc.gd:168-178 and defense_calc.gd:167. No mutator duration is read.

2. Runtime path: dump/decomp/LE.dll/UsingAbility.c:618-622 ge

## #26 [speed-mana-cooldown] Stat-kind speed models are dropped on skills with speedScaler 54 (Shield Bash, Ballista)
- impact: Medium for Shield Bash builds (the node's attack speed is lost); low for Ballista placement.
- calculator: `client/scripts/engine/skill_calc.gd:1053-1055 (scaler==54 reads only use_speed_inc); client/data/field_models.json ShieldBashMutator.attackSpeedPerBlockChance (kind stat, AttackSpeed increased, per va` — These nodes add AttackSpeed/CastSpeed StatMods to the skill store; Shield Bash and Summon Ballista have speedScaler 54, so _speed never queries the store and the bonus has no effect.
- game: ShieldBashMutator.getIncreasedCastSpeed returns f*uncapped block chance, i.e. it feeds S = 1 + increasedCastSpeed directly; BallistaMutator.mutateUseSpeed multiplies use speed by (1 + Dexterity*f) (a MORE).
- evidence: 1) dump/decomp/LE.dll/UsingAbility.c, UsingAbility_getSpeedMultiplierStat (line 5379 onward): "if (cVar2 == '6') { fVar8 = (float)param_4 + 1.0; goto LAB_181672d53;" (return before any Stats_GetStatValue call). Stats_GetStatValue is only reached in the non-54 branch.
2) UsingAbility.c, UsingAbility_getSpeedMultiplier (around line 5470): the result of the getSpeedMultiplierStat virtual call (+0x528

## #33 [character-attrs] Affix/implicit ranges whose first number is larger than the second (descending ranges) are rolled in the reverse direction
- impact: MEDIUM-HIGH for the 15 affixes and 14 implicit subtypes: at a stored roll r the calculator gives the value of roll 255-r. Example: Oracle Amulet at max roll -6% DoT taken instead of -20%.
- calculator: `client/scripts/engine/affix_math.gd:36-43 (roll_value swaps a and b when a > b), used by item_mods.gd:102 and 202, build_mods.gd:264` — After rounding, if a > b the two ends are swapped and the ascending formula min(floor((b-a+1)*roll/255+a), b) is applied. For a range like [-0.06, -0.20] roll 0 gives -0.20 and roll 255 gives -0.06. A missing implicit roll defaults to 255 (item_mods.gd:94), so the weakest end is used.
- game: When max < min (first number larger than second), the game uses the Descending variant. In it roll 0 gives the first number as listed (value) and roll 255 gives the last (maxValue), via max(round((b-a-1)*roll/255 + a), b)/s. The calculator should mirror the roll (use roll 255-r on the swapped ascending formula) or implement the Descending formula directly, instead of just swapping the endpoints.
- evidence: dump/decomp/LE.dll/EpochExtensions.c:16978-16986 and 17044-17052: `if (param_6 < param_5) { EpochExtensions_DescendingValueAfterPropertyRounding(...,param_5,param_6,param_7,0); } else { EpochExtensions_AscendingValueAfterPropertyRounding(...) }`. dump/decomp/LE.dll/EpochExtensions.c:14359-14405 Descending: `FUN_18037c870((double)((float)((iVar2 - iVar1) + -1) * ((float)param_4 / 255.0) + (float)iV

## #35 [character-attrs] Items with a Reforged Set affix do not count as set members
- impact: MEDIUM: builds that use Reforged Set affixes to reach 2/3-piece set bonuses lose those bonuses in the calculator; wrong in the other direction is not possible. The affix values themselves are applied.
- calculator: `client/scripts/engine/build_mods.gd:525-543 (set_counts counts only items that have a 'unique' key with isSetItem); complete_sets 547-553` — Only unique-list items flagged isSetItem (plus Legends Entwined 423) add to a set count. A rare/exalted item carrying a 'Reforged' Set affix is treated as a plain item and adds nothing to the set count; set bonuses stay inactive.
- game: An item counts toward a set if its rarity is Set, or any of its affixes has specialAffixType Set (3), or it is a unique/legendary with id 0x1A7. A Reforged-Set item counts as the set piece named by the affix's uniqueId. Each distinct uniqueId is counted once per set, so a reforged item whose affix points to a piece the player already wears adds nothing.
- evidence: dump/decomp/LE.dll/ItemData+__c.c, `<isReforgedSet>b__292_0`: `return *(int *)(param_2 + 0x18) == 3;`. dump/cs/DiffableCs/LE/ItemAffix.cs: `public SpecialAffixType specialAffixType; //Field offset: 0x18`, and the enum has `Set = 3`. dump/decomp/LE.dll/ItemData.c `ItemData_grantsSetBonus` (~28841-28870): `Item_1_rarityIsSet` false, then `ItemData_isReforgedSet` false, then the unique/legendary bran

## #45 [ailments-player] Stacks that displace others at the cap get no 0.1 s first tick; the (life+0.4)/(T+0.4) share is wrong, and badly so at high apply rates
- impact: Medium. Capped damaging ailments are TimeRot (max 12), Doom (4), Pestilence (2) and every max-1 ailment (SpreadingFlames, Plague, Witchfire, Torment, Spirit Plague, AbyssalDecay, ScathingLight, Brands, ...). DPS is overstated 15% to over 100% depending on apply rate. Ignite, Bleed and Poison (max 0) are not affected.
- calculator: `client/scripts/engine/ailment_calc.gd:8 (ENEMY_TICK_K = 0.4) and 223-228 (share = (life+k)/(duration+k), life = max(max_inst/rate, 0.1))` — For capped ailments (maxInstances>0 and rate*duration > max) every stack is assumed to get its first tick at 0.1 s and then ticks every 0.5 s, so a stack evicted at age `life` has delivered (life+0.4)/(T+0.4) of its damage. The comment cites research/06d 4.3.
- game: A damaging ailment stack created while the existing stack count equals maxInstances gets firstTickApplied = 1, so it has no early tick at age 0.1 s. It ticks only on the shared global tick, every baseTickInterval (0.5 s on enemies), with a phase unrelated to its creation time. A stack evicted before its first global tick delivers 0. Otherwise, after its first global tick at age u in (0, I], it has delivered (age-u+I)/(T-u+I) of its damage. The calculator should average this over u, uniform in (0, I], for capped stacks instead of using (life+0.4
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\AilmentReceiver.c, AilmentReceiver_ApplyAilmentWithDamageStats (0x182828F90), lines 707-712: `fVar16 = *(float *)(param_2 + 0x20); } if ((*(char *)(param_2 + 0x83) != '\0') && (fStack_b4 == fVar16)) { ... *(undefined1 *)(*(longlong *)(lVar9 + 0x18) + 0x28) = 1; }`. Before that, line 629 compares maxInstances with the existing count plus one, and line 635 remo

## #47 [ailments-player] Abyssal Decay is consumed by the first hit on the target; the calculator models it as a DoT with displacement loss
- impact: Medium for Abyssal Echoes builds. DPS from Abyssal Decay is undercounted at high use rates; it is correct only when uses*5 <= 1.
- calculator: `client/scripts/engine/ailment_calc.gd:220-228 (generic cap/displacement model), no handling of stopsWhenHit` — AbyssalDecay (id 12, maxInstances 1, duration 5, replaceLowestDamage...) goes through the generic path. If uses*chance*5 > 1, the cap formula applies and a stack evicted early loses most of its damage: (life+0.4)/(5.4) with life = 1/uses.
- game: On the first hit the holder takes (HitEvents.Hit bit, any attacker), the Abyssal Decay stack's remaining duration is zeroed and OnUpdateTick pays out its entire unpaid damage at once (f clamped to 1 - paid fraction). It does not lose damage to displacement. The total damage per stack stays the same, but it is delivered when the target is next hit, not spread over the duration.
- evidence: research/data/game/ailments.json data[] id 12 and id 13: stopsWhenHit=1, hitsRequiredToStop=1, requireSpecificActorHit=0. dump/cs/DiffableCs/LE/Ailment.cs:186-189 (stopsWhenHit +0x13B, hitsRequiredToStop +0x13C). dump/cs/DiffableCs/LE/AilmentReceiver.cs, ActiveAilment fields: remainingDuration +0x1C, stopsWhenHit +0x98, hitsRemainingBeforeStopping +0x9C, requireSpecificActorHit +0xA0. dump/decomp/

## #49 [ailments-player] Witchfire unique effect (ppIndex 521) is applied to ALL ailments and scaled by total increased Damage
- impact: Medium for the few builds with this unique: the bonus is wrongly applied to other ailments and uses the wrong source stat. Witchfire itself is under- or over-counted depending on the build.
- calculator: `client/data/unique_effect_models.json:2163-2170 ("521": stat Damage, more, tags Ailment, per increased:Damage)` — more Damage with tag Ailment = v * (all increased Damage). It multiplies every damaging ailment of every skill (Ignite, Bleed, Poison, ...), and the source is the total of all increased damage (the model's own note calls it an approximation).
- game: The bonus affects only the Witchfire ailment stack (ailment id 122). It is a multiplier on that stack's damage: (1 + curse-tagged increased Damage * v) * (1 + ignite chance with fire skills * f2 + damned chance with necrotic skills * f3), minus 1. The increased-damage source is only the exact Curse tag (0x1000000). All other ailments get nothing from it.
- evidence: dump/decomp/LE.dll/CharacterAilmentMutator.c lines 63-90 (GetAilmentDamageModifier, branch `else if (cVar3 == 'z')`): `if (*(float *)(param_2 + 0x1780) != 0.0) { ... uVar7 = Stats_GetTotalIncreasedExactMatch(lVar1,0,0x1000000,0,0,0); fVar8 = (float)uVar7 * *(float *)(param_2 + 0x1780); } fVar8 = (fVar8 + 1.0) * (fVar10 + 1.0) - 1.0;`. The same branch reads 0x1768 (`CharacterMutator_GetIgniteChance

## #50 [ailments-player] Ailment-instance-only 'more damage' of skill mutators is modelled as skill-wide Damage more with a manual chance input (Scathing Light, Brand of Subjugation)
- impact: Medium for those skills: the hit damage of Radiant Lance / Flame Rush (and other ailments) is boosted by a bonus that only applies to one ailment instance, while the chance input (default 100) is not derived from the build's real Ignite/Electrify/Chill chance, which the calculator already knows from AilmentCalc._chances.
- calculator: `client/data/field_models.json:22075-22087 (RadiantLanceMutator.moreScathingLightDamagePer1PercentIgniteElectrifyChance) and 11720-11733 (FlameRushMutator.brandOfSubjugationMoreDamagePerChillChance); r` — A normal `Damage` more modifier (no tags, scope skill) whose value is (user input % of chance) * factor. It multiplies the hit damage and every ailment of the skill, not just one ailment. Defaults: 100% input for Radiant Lance. The note 'Scathing Light damage' is only text.
- game: Radiant Lance: when the ailment being applied is Scathing Light (id 144), mod = f * 100 * (IgniteChance + ElectrifyChance + E + S), using the caster's real chances. That mod is folded into that ailment instance as (old+1)*(mod+1)-1. Flame Rush: the modifier is Stats_GetAilmentChance(stats, 3 = Chill) * field, taken from the caster's real chill chance and applied to the ailment instance, not to hit damage. The calculator should apply these only to the relevant ailment's damage and derive the chance from AilmentCalc's computed chances, not from a
- evidence: 1. dump/decomp/LE.dll/RadiantLanceMutator.c, RadiantLanceMutator_GetAilmentDamageModifier (0x1822414e0): `uVar5 = EpochExtensions_GetAilment(0x90,0); cVar3 = Object_1_op_Equality(param_2,uVar5,0); fVar9 = 0.0; if (cVar3 != '\0') {...}`. The modifier is non-zero only for ailment 0x90 = 144. The returned value is `((float)uVar5 + fVar8 + fVar9 + fVar6) * *(float *)(param_1 + 0x168) * 100.0`, where t

## #57 [enemy-side] Puncture 'Large hit absorbs bleeds' is modelled as consuming bleed on every use; the game consumes only on the every-third big hit
- impact: MEDIUM for Puncture bleed builds: average bleed stacks and the bleed-dependent multipliers (per-bleed-stack, 'bleeding' uptime) are computed with a wipe 3x too often. When duration >= period the average is rate*P/2, so about 3x too low; when the duration is shorter the error is smaller.
- calculator: `client/scripts/engine/enemy_ailments.gd:32-40 (CONSUMERS) and 159-163 (consume_rate += r["uses"]), consumed_load at 196-199` — Any skill whose flag_keys contain 'Large hit absorbs bleeds and deals their damage instantly' wipes all Bleed stacks once per use (period P = 1/uses), so the average bleed is rate*P/2 with P = 1/uses.
- game: With everyThirdBigger on, the counter rises by 1 per Puncture use. On the use where it exceeds 2, the use gets the big-hit damage bonus, the counter resets to 0, and (if bigHitConsumesBleed is set) a CleanseAilmentsOnHit is added for Bleed. The id is Poison if bleedConvertedToPoison, or Frostbite in the stats-mutator case. The wipe period is therefore about 3/uses, not 1/uses. If everyThirdBigger is off, there is no wipe.
- evidence: dump/decomp/LE.dll/PunctureMutator.c, the damage-computation function: lines 965-968 read 'if ((*(char *)((longlong)param_1 + 0x13c) != 0) && (2 < (int)param_1[0x36])) { fVar18 = fVar18 + *(float *)(param_1 + 0x35); *(undefined4 *)(param_1 + 0x36) = 0; if (*(char *)((longlong)param_1 + 0x161) != 0) { ... AddComponent<CleanseAilmentsOnHit> ...'. param_1 is a longlong*, so index 0x36 is offset 0x1b0

## #58 [enemy-side] Increased effect of an ailment (SP 43) is ignored for debuffs on the target (Armour Shred, Chill, Slow, ...)
- impact: MEDIUM for armour-shred builds with the increased-effect affix; an under-count of NegativeArmour (and of Chill/Slow-type debuffs). Per stack, shred should be 100 x (1+increasedEffect).
- calculator: `client/scripts/engine/enemy.gd:53-66 (store: scaled(n_eff*(1+penalty)) only); effect is only used for the damage of the player's own damaging ailments in ailment_calc.gd:211 (eff_more)` — Buffs/debuffs of ailments on the enemy scale with stacks and the boss penalty only. No 'increased effect of <ailment>' from the player's stats is applied, so e.g. 'increased Armour Shred effect' does nothing.
- game: For Individual ailments with effectOfIncreasedEffectiveness == 0 (Chill, Slow, Armour Shred, Frailty, Blind, Stagger, etc.), the buff multiplier per stack is (1 + bossPenalty) * stacks * (1 + increasedEffect) * (1 + max(-1, target's EffectOfAilmentOnYou)). Armour Shred NegativeArmour is therefore 100 * stacks * (1 + increasedEffect) * (1 + effectOnYou) * (1 + penalty). Grouped ailments (Shock, resistance shreds, Poison, Frostbite, and so on) ignore increasedEffect.
- evidence: dump/decomp/LE.dll/AilmentReceiver+IndividualActiveBuffsForStackingAilment.c, addBuffFromActiveAilment, lines 109-113: 'if (*(int *)(lVar2 + 0xb0) == 0) { fVar11 = *(float *)(param_2 + 0x94); } else { fVar11 = 0.0; }'. Line 124: 'fVar13 = fVar13 * (fVar11 + 1.0);' where fVar13 starts as stacksRepresented (+0x8c). Line 149: 'fVar11 = (fVar10 + 1.0) * fVar11 * fVar12;' (fVar10 is the boss penalty, f

## #85 [minions-shadows] Minion abilities whose damage is in sub-abilities deal 0 or partial damage; they still consume their time share
- impact: MEDIUM-HIGH. Storm Totem, Forged Weapons, Abomination, Falcon, Hive and Bone Golem DPS is understated or zero.
- calculator: `client/scripts/engine/minion_calc.gd:219-224 (_first_damage) and 282-283; no subAbilities handling anywhere in engine/*.gd` — Only abilities[name].damage[0] is used. If the ability has no own damage entry it is skipped after free -= share, so it eats time and deals nothing. Sub-ability hits are never added.
- game: The damaging hit comes from the sub-ability that the ability's prefab spawns. For the Storm Totem, the LightningStorm prefab spawns StormLightning through CastAtRandomPointAfterDuration. That sub-ability deals Lightning 11.0 per hit with `addedDamageScaling` 0.55 and uses the same cast speed. The calculator should add sub-ability damage entries, as SkillComponents does for player skills, instead of reading only `ability.damage[0]`.
- evidence: client/scripts/engine/minion_calc.gd:219-224 (`_first_damage` returns only `rec.damage[0]`) and :281-283 (`free -= share`, then `if entry.is_empty() or rate <= 0.0: continue`). No sub-ability handling in that file.
research/data/game/abilities.json:
- LightningStorm: damage=[], subAbilities=["StormLightning"], minionActors=["StormTotem"].
- StormLightning: category "minionSub", parents ["Lightning

## #86 [minions-shadows] Minion mutator damage and speed fields are not applied
- impact: MEDIUM. Wolf is understated by 15%, Raptor by 65% (multiplicative), Sabertooth by up to 65% on its hit, Rogue Shurikens speed by +20%.
- calculator: `client/scripts/engine/minion_calc.gd:193-200 reads only addedCharges and addedChargeRegen from minion.mutators; the rest of minion_base_stats.json mutators[*].nonZero is unused` — Per-minion mutator multipliers are ignored.
- game: When a minion ability is used, its mutator multiplies all damage on the ability's DamageStatsHolder by (1 + increasedDamage). Wolf melee gets x1.15 and Primal Serpent's BasicMeleeMutator x2.0. Corpse Parasite's LightningBlastMutator carries -0.6, but I did not verify that class reads it. The Skeleton Vanguard 0.4, Primal Raptor 0.65 and Sabertooth moreHitDamage 0.65 depend on the unverified points above. BasicMeleeMutator also scales the ability's use speed by (1 + increasedAttackSpeed). The calculator should apply these data-driven multipliers
- evidence: client/scripts/engine/minion_calc.gd:193-200 reads only addedCharges and addedChargeRegen. dump/decomp/LE.dll/WolfMeleeMutator.c:209-211: 'if (*(float *)(param_1 + 0x27) != 0.0) { ... DamageStatsHolder_increaseAllDamage(lVar8);'. dump/decomp/LE.dll/BasicMeleeMutator.c:255-257: 'if (*(float *)(param_1 + 0x27) != 0.0) ... DamageStatsHolder_increaseAllDamage(lVar8,*(float *)(param_1 + 0x27),0);'. Bas

## #87 [minions-shadows] Companion limit is not shared between companion types; wolf contribution modifiers and the 1-companion flags are ignored
- impact: MEDIUM. With two or more companion skills on the bar, total companions and minion DPS are overstated. Wolf and squirrel counts and damage are wrong with those nodes. 'Limited to one companion' sets are not applied at all.
- calculator: `client/scripts/engine/minion_count.gd:175-177 ('companions' kind: value = max(value, companions)), 222-229 (max_companions; the header comment mentions 'Limited to one companion' but it is not impleme` — Each companion type (wolf, raptor, ...) independently gets up to the full maximumCompanions, 2 by default. The wolf count ignores AbilityProperty summonWolf 2 'convertWolvesTo2Squirrels' (0x1c3) and summonWolf 8 'summonWolfCountAsTwoForLimit' (0x1c5). PlayerProperty 85 (maxOneCompanion) and 553 (one of each type) are flag text only.
- game: All companions share one budget of maximumCompanions*60. Each companion contributes 60, or its own contribution value. A wolf contributes 60 * (0.5 if mgr+0x1c3) * (2 if mgr+0x1c5). Oldest companions are evicted until the total is at or below the budget. If SummonTracker+0x81 is set, only one of each companion type is kept. SummonWolfMutator.getMaximum is 900 with mgr+0x1c4, and 1 with this+0x134.
- evidence: dump/decomp/LE.dll/SummonTracker.c:8372 SummonTracker_unsummonExtraCompanions: `iVar3 = Stats_maxContributionToCompanionLimit(...)`, `lVar5 = SummonTracker_getCompanions_1(param_1,&iStackX_18,0)`, `if (*(char*)(param_1+0x81)!='\0') SummonTracker_EnforceLimitOfOneOfEachCompanionType_1(...)`, then `while(true){ if (iVar9<0 || iVar8<=iVar3) return; ... iVar4=0x3c; if (*(char*)(lVar7+0xd4)!='\0') iVar

## #88 [minions-shadows] Minion shared cooldown/charge cap ignores mutators without an abilityRef, and treats CDR as added+increased
- impact: MEDIUM for the Death Knight (melee never used, Harvest uncapped). LOW for Skeleton CDR.
- calculator: `client/scripts/engine/minion_calc.gd:193-200 (m.get('abilityRef') == ability.name) and 208-211 (cap *= 1 + q.added + q.increased)` — Mutator charges apply only to a mutator whose abilityRef equals the ability name. Cooldown recovery is applied as (1 + added + increased).
- game: Death Knight Harvest gets +1 charge and +0.333 charge regen from DeathKnightHarvestMutator, so it is capped at about 0.333 uses per second (about a 3 s cooldown) before CDR. The calculator should match mutators to abilities by the mutator's hardcoded target as well as by abilityRef (here the Awake() ID 295 = DeathKnightHarvest). The melee attack then gets the remaining time. Cooldown recovery is not established as added+increased: the code shows added SP70 (id 0x46) when there is no ChargeManager, and the ChargeManager path is UNKNOWN.
- evidence: 1) minion_base_stats.json, Death Knight: mutators.DeathKnightHarvestMutator[0].nonZero = {addedCharges 1.0, addedChargeRegen 0.333} with no abilityRef. abilities.json gives DeathKnightHarvest cooldown None, maxCharges 0, chargesGainedPerSecond 0. minion_calc.gd:197 is `m.get("abilityRef") == ability.get("name")`, so this mutator is skipped.
2) dump/decomp/LE.dll/DeathKnightHarvestMutator.c, Awake(

## #90 [minions-shadows] Shadow imitation list (IMITATED) is incomplete relative to the code
- impact: MEDIUM-LOW. Net, Heartseeker, Explosive Trap (bow) and Bladestorm shadow repeats are not counted, so DPS is understated for those skills.
- calculator: `client/scripts/engine/shadow_calc.gd:17 (IMITATED = ShadowCascade, Shurikens, Umbral Blades 1, Dreamslash, AcidFlask); the header cites the ability description` — Only those five skills get 'Shadows: ...' components.
- game: In startedUsingAbility, active shadows repeat the used skill when it is: ShadowCascade (0x158, via a separate branch with the last flag = 1), Shurikens (0x160), AcidFlask (0x168), Umbral Blades 1/2/3 (0x170/0x178/0x180), Explosive Trap (0x190, only when ExplosiveTrapMutator.castingBowVersion is false), Net (0x198, unconditional), and Heartseeker (0x1a0, gated by RngElement.Roll on the field at +0x19c of the mutator held at +0x1e0). Separately, an AbilityInfo-type check followed by Ability_CastAfterDelay spawns extra casts spread along the cast 
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\CreateShadowMutator.c. Awake (about lines 70-110): Ability_getAbility(0xd6/0x1ea/0x107/0x32/0x232/0x233/0x243/0x240/0x2de/0x2df/0x327/0x154/0x39a/0x36f) stored at +0x158..+0x1c0. startedUsingAbility (lines 2729-3086). Line 2791: `Object_1_op_Equality(param_3, *(param_1+0x158))`. Line 2797: 0x160. Line 2836: 0x168. Line 2842: 0x170. Line 2848: 0x178. Line 2854

## #94 [buffs-and-skillbuffs] Event-based 'recover X% of remaining cooldown' fields modelled as permanent cooldown recovery speed
- impact: Medium. Cooldown-limited uses are overstated because skill_calc caps uses by 1/cd; the 75% Healing Hands field is the largest case. The real effect is an event-driven reduction, not a rate.
- calculator: `client/data/field_models.json kind=cooldown, cooldown=recovery_increased (about 13 entries: AerialAssaultMutator.percentRemainingCDRecoveredOnFalconHit, ...missingCDpercentDiveBombAndStrikesRecoveredO` — The field value f is added to the skill's increased cooldown recovery speed, so f = 0.75 gives +75% recovery speed and 0.06 gives +6%. This is permanent and independent of how often the event happens.
- game: Each triggering event (falcon hit, first throw/bow hit, heal of another ally, freeze, detonation, Reap/Reaper Form hit) calls ChargeManager.recoverPercentRemainingCooldown(ability, f) once. It sets elapsed = elapsed + clamp(total - elapsed, 0, 1) * f, capped at the total. The result is a discrete jump of f times the remaining cooldown per event. It is limited by the event rate and any per-use or per-window limits, and it is not a permanent increase to recovery speed.
- evidence: dump/decomp/LE.dll/ChargeManager.c:2696-2800, recoverPercentRemainingCooldown(Ability, Single): `fVar5 = fStack_5c - fStack_58; if (0.0 <= fVar5) { if (1.0 < fVar5) fVar5 = 1.0; } else fVar5 = 0.0; afStack_68[0] = fVar5 * param_3 + fStack_54; List<float>.set_Item(...)`, followed by `if (fStack_4c < fStack_50)` which caps the value at the total. research/data/game/mutator_field_semantics_AL.json:27

## #95 [buffs-and-skillbuffs] Serpent Strike 'Serpent Venom more damage' fields modelled as Increased Ailment Effect (poison penetration) and without their 'enemy not at high health' condition
- impact: Medium for Serpent Strike builds. A more-damage multiplier on the venom becomes poison penetration, and the not-high-health condition is ignored (overcount against full-health enemies).
- calculator: `client/data/field_models.json: SerpentStrikeMutator.moreSerpentVenomDamagePerVitality / ...PerMeleeCritChance / ...PerPoison / ...PerFrostbite (stat=IncreasedAilmentEffect, ailment=SerpentVenom, no wh` — The values are added as IncreasedAilmentEffect to SerpentVenom. ailments.json gives SerpentVenom effectOfIncreasedEffectiveness=1 (AdditionalPenetration, Poison), so the engine adds +x poison penetration. The crit-chance field reads the untagged CriticalChance value. The per-poison and per-frostbite fields apply at all enemy health levels.
- game: Vitality and melee crit: the venom instance's moreDamage becomes (moreDamage+1) * (1 + meleeCrit*f_crit) * (1 + Vitality*f_vit) - 1. The crit value is Stats.GetStatValue(stat 4, tag 0x200). Poison and frostbite: a DamageConditionalEffect with InverterConditional(HighHealthConditional) wraps DamageEffectMoreDamagePerAilmentStack (ailment 7 for poison, 0x17 for frostbite, hasLimit=1, cap f*100). It applies only when the enemy is not on high health.
- evidence: dump/decomp/LE.dll/SerpentStrikeMutator.c, mutateAilmentInstance:
- Lines 3750-3776: fVar9 = Stats_GetStatValue(..., 4, 0x200, ...), fVar10 = fVar9 * f1f8 + 1.0, then fVar10 *= (float)iVar5 * f1fc + 1.0, then '*(float *)(param_3 + 0x110) = (*(float *)(param_3 + 0x110) + 1.0) * fVar10 - 1.0;'.
- Lines 3782-3794: DamageConditionalEffect with InverterConditional(HighHealthConditional) wrapping 'Damag

## #96 [buffs-and-skillbuffs] Chance-based Haste/Frenzy gains use the ailment's default duration; the code's own durations are ignored, and about 45 tree fields that give Haste/Frenzy for f seconds never reach 'Buffs on me'
- impact: Medium for Haste uptime and the movespeed buff derived from it. Haste uptime = 1-exp(-rate*duration), so a 2 s Haste counted as 4 s inflates it, and a 1 s Haste counted as 4 s inflates it much more. Timed gains from the other ~45 fields are omitted, which undercounts.
- calculator: `enemy_ailments.gd:574 _gain (duration = ailment.duration*(1+inc)), ailment_calc.gd:49 (self applications use ail.duration); field_models.json AcidFlaskMutator.hasteChanceOnUse, CharacterMutator.chance` — Haste is always counted as 4 s and Frenzy as 1 s (ailments.json) plus ailment duration increases. The node's own duration field is not used. Timed Haste/Frenzy granted by tree nodes (Earthquake Slam, Shurikens, Warcry, Lunge, ...) is not added to the auto Buffs-on-me, only shown as parameter rows.
- game: Chance-based Haste gains use the duration given by the node field. AcidFlask gives Haste for 2 s, not 4 s. Rune bolts give Haste for hasteOnCastDuration seconds, and increased duration is derived as (dur - base)/base. The calculator should take that duration from the field and apply increased duration on top.
- evidence: dump/decomp/LE.dll/AcidFlaskMutator.c lines 1265-1268: 'uVar14 = Ailment_getAilment(0x21,0); AilmentReceiver_ApplyStackOfAilmentForDuration_1(lVar13,uVar14,0x40000000,...)'. The float bit pattern 0x40000000 is 2.0, and the third argument is the duration. dump/decomp/LE.dll/RuneboltMutator.c lines 1233-1246: 'if (0.0 < *(float*)(param_1+0x134)) { AddComponent<ApplyAilmentToCreator>; Ailment_getAilm

## #98 [buffs-and-skillbuffs] Hit-only conditional 'more damage' nodes are modelled as tag-less More Damage and therefore also boost the skill's ailment/DoT damage
- impact: Medium for ailment/DoT skills with such nodes: the DoT part is overcounted by the node's full multiplier. None for pure hit skills.
- calculator: `client/data/field_models.json, about 60 entries with stat=Damage, mod=more and no 'Hit' tag, whose code is a DamageConditionalEffect/DamageEffectMoreDamage(PerAilmentStack): e.g. JudgementMutator.more` — A tag-less More Damage mod matches the ailment damage source too, so the 'vs ignited/shocked/...' multiplier also multiplies the DPS of the Ignite/Bleed/Poison stacks the skill applies.
- game: 'Hit damage vs ignited/shocked/etc.' conditional more-damage from skill mutators applies only to the skill's own hit DamageStats (its holder's conditionalEffects). The ailment's DamageStats is built from the ailment's baseDamage plus the attacker's Stats, so these multipliers should not scale ailment/DoT stack damage. The calculator should give these mods a Hit tag, as it already does for the ChaosBolts and Javelin entries.
- evidence: dump/decomp/LE.dll/AilmentReceiver.c, AilmentReceiver_ApplyAilment, ~line 1497: `uVar13 = DamageStats_buildDamageStats(param_2[0x11],uVar15 | 0x2000000,param_7,0,...)`; lines ~1500-1516 then add only a `DamageEffectMoreDamagerPerCurrentHealth` conditional to `uVar13+0x50`.
dump/decomp/LE.dll/DamageStats.c, DamageStats_buildDamageStats, near line 1241: `List.AddRange(*(lVar17+0x50), *(param_1+0x50)

## #99 [buffs-and-skillbuffs] Missing or wrong stack caps on 'more damage per ailment stack' and per-resource fields
- impact: Medium on poison/armour-shred stacking builds (Serpent Strike: several times the real bonus with many stacks; Runebolt: over 7% above 14 shred stacks). The Glyph model undercounts above 7 stacks.
- calculator: `client/data/field_models.json: SerpentStrikeMutator.moreMeleeDamagePerPoisonOnTarget (no cap); ShurikensMutator.moreHitDamagePerPoisonOrBleedOnTarget (input max 30, no cap); DrainLifeMutator.moreDamag` — The effect grows linearly with the stack or input value; the cap fields are not applied. The Glyph entry is capped at 7 stacks.
- game: Caps from the game data: Serpent poison 0.12 per point vs 0.01 per stack (12 stacks); Shurikens 0.3 vs 0.02 (15 stacks, input max is 30); Drain Life maxTotalDamageToDamned 0.21 vs 0.03 per stack (7 stacks); Flay meleePerHealthCap and spellPerWardCap 12 per point vs health/30 (reached at 360); Cinder 9 per point vs 3 per target (3 targets, input max 10). Runebolt and Glyph use ConditionalDamageProperty.PerStackOfArmourShredUpTo14: cap = 14 stacks * f, so the Glyph cap is 14 stacks (28% at f=0.02), not 7, and Runebolt caps at 14 stacks (7%).
- evidence: - dump/decomp/LE.dll/DamageEffectMoreDamagePerAilmentStack.c, apply: fVar8 = stacks * *(param_1+0x18); if (*(char*)(param_1+0x1c) != 0 && limit(+0x20) < fVar8) fVar8 = limit. The cap is on the total bonus.
- dump/decomp/LE.dll/SerpentStrikeMutator.c lines ~1346-1362: ctor(7, field 0x150, hasLimit 1, limit field 0x154).
- dump/decomp/LE.dll/GlobalDamageConditionals.c case 0x12: GetPerAilmentStackEf

## #103 [buffs-and-skillbuffs] AuraOfDecay increasedAilmentFrequency (and other rate fields) are parameter rows only; the poison zone interval is not changed
- impact: Medium for Aura of Decay poison DPS (the frequency nodes are ignored); low for the Flame Burst counts.
- calculator: `client/data/field_models.json AuraOfDecayMutator.increasedAilmentFrequency (param=frequency), FireShieldMutator.increasedIgniteFrequency, GlyphOfDominionMutator.increasedIgniteFrequencyPerIgniteChance` — Only projectiles, projectile_limit, shotgun, duration, echo_chance and the PARAM_BUFFS names are consumed. The Aura of Decay poison zone always ticks every 0.25 s. The Flame Burst trigger chance stays 1/8 (Disintegrate) and 1/5 (Fireball) whatever 'reduced hits' says.
- game: Aura interval = base/(1+f); poison ticks per second scale by (1+f).
- evidence: AuraOfDecayMutator.c OnAbilityUse: fVar18 = field at param_1+0x31 (offset 0x188); *(lVar10+0x98) = *(lVar10+0x98)/(fVar18+1.0). getDPSAppliersForDPSCalculation: DPSApplier__ctor(..., fVar2+1.0). RepeatedlyApplyAilmentsInRadius.c seedIncreasedAilmentApplicationFrequency: 1.0/((1.0/interval)*(f+1.0)). Calculator: ailment_calc.gd line 27 uses = 1.0/zone["interval"]; field_models.json line 1409 param=

## #105 [buffs-and-skillbuffs] 'More damage vs state' conditions are all-or-nothing at 50% presence
- impact: Medium: a 40% uptime gives 0% of the bonus and 60% gives 100%. The error is large for conditionals near the threshold.
- calculator: `client/scripts/engine/effect_models.gd:233-248 (PRESENT_SHARE = 0.5, holds() for enemy:<Ailment> and enemy_any); about 102 field_models.json entries plus 16 unique-effect entries use when: enemy:*` — The conditional bonus is fully on when the ailment's computed uptime is at least 50% and fully off below that, regardless of the actual uptime (the source comment itself says D?).
- game: The effect is a per-hit conditional: each hit multiplies damage by (1 + f) only if the target has the ailment at that moment. The expected multiplier over a fight is therefore about 1 + f*uptime, not a 0/1 switch at 50% uptime. The correct way to model this is to scale f by the ailment's uptime (or its probability of being present).
- evidence: D:\LastEpochBuilder\client\scripts\engine\effect_models.gd lines 233-248: "const PRESENT_SHARE: float = 0.5", "...(automatic averages, EnemyAilments; D?)", "return Enemy.presence_id(build.enemy, GameData.enum_value("AilmentID", arg)) >= PRESENT_SHARE". D:\LastEpochBuilder\client\scripts\engine\enemy.gd lines 291-296: presence_id returns uptime[id] as a float, else 1.0 or 0.0. D:\LastEpochBuilder\r

## #106 [buffs-and-skillbuffs] 'Current mana' effects are evaluated at max mana
- impact: Medium. An upper bound for the mana-scaling nodes of Mana Strike and Gathering Storm.
- calculator: `client/data/field_models.json ManaStrikeMutator.addedLightningPerMana and critChancePerMana (per=max_mana, note 'assumed equal to max'), GatheringStormMutator.stormBoltMoreDamagePer10CurrentMana (per=` — The source value is the maximum mana.
- game: Mana Strike adds Lightning (or Cold) base damage of f*currentMana and crit chance of f*currentMana at hit time. Gathering Storm's Storm Bolt gets more damage of min(3.0, currentMana*f/10) from the mana consumed. The game does not use max mana. The true average depends on the mana level at each cast, and the data does not give it, so it is UNKNOWN.
- evidence: client/data/field_models.json: 14488-14496 (GatheringStormMutator.stormBoltMoreDamagePer10CurrentMana: per max_mana, factor 0.1, note "Per every 10 current mana (approximately max)", confidence D?); 19227-19235 (ManaStrikeMutator.addedLightningPerMana: per max_mana, note "From current mana (assumed equal to max)"); 19257-19264 (ManaStrikeMutator.critChancePerMana: same note). client/scripts/engine

## #112 [uniques] Gathering Fury (pp236) attack speed and Crystalwind (pp506) damage are global; the game restricts them to Bow skills (506 also to direct use)
- impact: Medium to high for non-bow skills with these uniques (up to +50% attack speed, up to +60% more damage). The fix is a skill_any Bow filter.
- calculator: `unique_effect_models.json player 236 (AttackSpeed increased, scope global, no tags) and player 506 (Damage more, note 'ranged abilities', no skill_any or tags)` — 236: +pp x stacks (default 10) increased attack speed for all skills. 506: MORE Damage = consumed stacks (default 4) x pp (8-15%) for all skills.
- game: Gathering Fury's increased attack speed carries the Bow tag (0x800), so it applies only to Bow skills. Crystalwind's more damage applies only to a skill with the Bow tag, and only on a Direct use (UseType 1). It consumes min(4, stacks) and adds MORE Damage equal to consumed times the per-stack value. The calculator should add a Bow skill_any filter to both entries, plus a direct-use restriction on pp 506.
- evidence: dump/work_wave3/pp/pp_236.txt, CharacterMutator.OnFirstBowHit: the stat-add interface call passes (plVar6, 2, gatheringFuryBowAttackSpeed @0x860, 1, 0x800, ...). dump/cs/DiffableCs/LE/AT.cs line 18: Bow = 2048. dump/decomp/LE.dll/CharacterMutator.c line 5395: if (((0 < *(int *)(param_1 + 0x1bc8)) && ((uVar11 >> 0xb & 1) != 0)) && (uStackX_20 == 1)) { uVar19 = 4; if (stacks < 4) uVar19 = stacks; ..

## #113 [uniques] Frenzy-linked unique effects are not multiplied by (1 + increased effect of Frenzy); same for pp275 and Haste
- impact: Medium to high for Fangs of the Berserker, Sword Catcher, Gift of the Eidolon and Advent of the Erased, whose own mods raise Frenzy or Haste effect (per Strength, per highest attribute, per Rampancy). Damage and damage taken are understated.
- calculator: `unique_effect_models.json player 411, 601, 602, 603, 669 and 275; EffectModels.value()` — The models use the raw pp: 411 flat added Melee damage v, 601 HealthLeech v, 602 MORE Melee damage v, 603 increased DamageTaken v, 669 added area v, 275 DamageTaken x v with note 'without accounting for increased Haste effect'. The calculator models increased effect of Frenzy (pp605/606/667) and applies it only to the generic Frenzy buff in BuildMods._add_player_ailments. The pp669 note says 'Multiplied by (Frenzy effect + 1)' but the model does 
- game: Each affected value is scaled by (1 + total increased effect of the ailment on you). For Frenzy (id 34) this applies to pp411, 601, 602, 603 and 669. For Haste (id 33), pp275 uses x = max(-0.75, (1 + increased Haste effect) * pp275) and then multiplies damage taken by (1 + x).
- evidence: dump/decomp/LE.dll/CharacterAilmentMutator.c, MutateReceivedAilment, lines ~268-313: Stats_GetTotalIncreased(stats,0x78,0,0x22) then Stats_AddedStat(0x33,0x200,(fVar5+1.0)*fVar1), Stats_MoreStat(0,0x200,(fVar5+1.0)*fVar1), Stats_IncreasedStat(6,0,(fVar5+1.0)*fVar1). The same function handles ailment 0x21 (Haste) with (fVar5+1.0)*0.1.
dump/work_wave4/traces_uniq/411__meleeDamageWhileYouHaveFrenzy.t

## #114 [uniques] Salt the Wound and sibling (pp141/pp142): the crit multiplier lost by the conversion is not modelled
- impact: Medium to high for crit builds: crit multiplier overstated by 40-50% of the added crit multi while the ailment bonus is kept in full.
- calculator: `unique_effect_models.json player 141 and 142 (IncreasedAilmentEffect Bleed / Poison added, per added:CriticalMultiplier, note 'conversion coefficient not allowed in code, taken as 1')` — Adds ailment effect = pp x added crit multiplier and leaves the crit multiplier unchanged.
- game: For PP 141 and 142, effectiveness = pp * (GetTotalAdded(SP5 CriticalMultiplier) + previously removed amount). Bleed and Poison effectiveness are added to IncreasedAilmentEffect (SP 43). The sum of both converted amounts is then removed from CriticalMultiplier as a negated ADDED mod (SP 5, mod type 0). The calculator should reduce added crit multiplier by the same amount it grants as ailment effect, using coefficient = pp rather than 1.
- evidence: dump/work_wave3/pp_c/pp_141.txt, percentOfCritMultiConvertedToBleedEffectiveness at ISIL idx 13331-13345:
- 13313 'Call Stats.GetTotalAdded ... rdx=5' (SP 5 = CriticalMultiplier)
- 13331-13333 'Move xmm0,[percentOfCritMultiConvertedToBleedEffectiveness]; Multiply xmm0,xmm0,xmm2; Move [currentBleedEffectivenessFromCritMulti],xmm0'
- 13336-13338 the same multiplication for poison
- 13341-13344 'curr

## #116 [uniques] Deicide (pp77) is a MORE buff of 20% damage (plus 20% move speed), modelled as increased
- impact: Medium: the 20% is applied in the wrong pool (increased instead of more).
- calculator: `unique_effect_models.json player 77 (Damage increased, factor 0.2, note 'modifier type not confirmed', confidence D?; input deicide default false)` — Increased Damage +20% (additive with other increased), and only if the input is enabled (see the inputs finding).
- game: On killing a rare or boss, the game adds two Buffs named 'Deicide Damage' through StatBuffs.addBuff. One is a Damage stat with MORE 0.2, and the other is a MoveSpeed stat with MORE 0.2. Added and increased are 0 on both. The calculator should model this as a more multiplier (x1.2) in the more pool, not as +20% increased.
- evidence: dump/isil/IsilDump/LE/CharacterMutator.txt lines 118334-118351 (idx 1618-1635):
1618 Call Actor.isRareOrBoss; 1620 JumpIfEqual {1722}
1628 Move xmm6, [0x184561C00]
1629 Move stack:0x28, xmm6 (sixth argument, _moreValue)
1630 Move stack:0x20, xmm10 (xmm10 was zeroed at idx 1594, so _increasedValue = 0)
1631 Move xmm3, xmm10 (_addedValue = 0)
1633 Move rdx, 0 (SP Damage)
1635 Call Stat..ctor
Lines 1

## #117 [uniques] Poison damage 'applies to Skeleton Rogues / Falcon' (120:6, 727:17) copies the wrong player stats
- impact: Medium for poison minion builds (Lethal Concentration): the set of copied stats is inverted compared with the model.
- calculator: `unique_effect_models.json ability 120:6 and 727:17 (minion_stat Damage increased, tags Poison, per increased:Damage, note 'all % increased damage is counted')` — The minion gets increased Poison damage = v x (player's UNTAGGED increased Damage).
- game: Each minion gets clones of the player's Damage stats whose tags include Poison (0x40), each scaled by the unique's value v through Stat(Stat, multiplier). The player's untagged increased-damage stats are not used.
- evidence: 1. SummonSkeletonMutator.c:1937 `if (*(float *)(lStack_1c8 + 0x1848) != 0.0)`. The dump index confirms offset 0x1848 is AbilityStatsMutatorManager.percentOfPlayerPoisonDamageForSkeletonRogues.
2. SummonSkeletonMutator.c, around lines 1955-1975: `if (((char)plStack_198[2] == '\0') && ((*(byte *)((longlong)plStack_198 + 0x14) & 0x40) != 0)) { uVar23 = *(undefined4 *)(lStack_1c8 + 0x1848); Stats_Stat

## #119 [uniques] Two GlobalConditionalDamage conditions are never evaluated: 117:35 (Feared) and 117:40 (bosses and rares while mana above 50%)
- impact: Medium for the two uniques (silent 0%, no note). Other ConditionalDamageProperty ids without a has_condition case (11, 12, 14, 15, 22-24, 27-31, 34, 37-39, 41-43, 45) would drop silently the same way.
- calculator: `Enemy.has_condition (enemy.gd:196-279) returns 0.0 for ids without a case; UniqueEffects.DERIVED_SOURCES skips the note for GlobalConditionalDamage(more); used by Fingers of the Phantom Mire (117:35) ` — The bonus (+10-15% more damage to feared enemies; +10-20% more to bosses and rares above half mana) contributes factor 1.0 silently, with no note and no Conditions checkbox.
- game: Fingers of the Phantom Mire (SP 117, special 35, MORE 0.10) applies more damage when the target is feared. Spirit Xylem (SP 117, special 40, MORE 0.10) applies more damage via a CompoundConditional of CasterAboveManaThresholdConditional(0.5) and BossConditional(true), meaning the caster has more than 50% mana and the target is a boss. The ids in the claim's text for the Xylem condition ('bosses and rares') are not established by the code I read. The ctor is BossConditional(true), and I did not open that class to see whether it covers rares. The
- evidence: dump/decomp/LE.dll/GlobalDamageConditionals.c: 'case 0x23: uVar11 = _FearedConditional__TypeInfo; ... AbilityEvent__ctor(lVar7,0);' (line 344). 'case 0x28: ... CasterAboveManaThresholdConditional__ctor(uVar11,0x3f000000,0); ... BossConditional__ctor(uVar9,1,0); ... CompoundConditional__ctor(lVar7,uVar11,uVar9,0,0);' (lines 385-392). 0x3f000000 is the float 0.5. client/scripts/engine/enemy.gd has_c

## #120 [uniques] Inputs of global-scope unique stat models can never be changed; they always use the declared default
- impact: Medium: effects are fixed on or off for every skill with no way to enable them, and per-mana-cost effects use 10 mana for all skills.
- calculator: `UniqueEffects.apply_global builds ctx with slot -1 (unique_effects.gd:117); EffectModels.blocked/source read build.skills[slot].inputs only when slot >= 0 (effect_models.gd:43). Only routed models cal` — Values like cw_stacks, gf_stacks, meteors, ward_consumed, mana_cost, target_dist use the default and no input row exists. Models whose input default is false (pp77 Deicide, pp587 Wings of Discord first hit) are never active.
- game: Per-1-mana-cost effects (PP 476, 477, 683) use the mana cost of the skill being cast, so the value differs per skill. Run-time conditions such as Deicide, first hit, Gathering Fury stacks, meteors and Crystalwind stacks depend on combat state. The calculator should offer an input for them, or take the cost from the skill, rather than a hidden default.
- evidence: D:\LastEpochBuilder\client\scripts\engine\effect_models.gd:41-44 and 177-180 (slot >= 0 gate, otherwise default). D:\LastEpochBuilder\client\scripts\engine\unique_effects.gd:109, 161 (ctx slot -1). D:\LastEpochBuilder\client\scripts\engine\build_mods.gd:932 (_apply_model is the only place that registers the model's inputs, besides 1057). D:\LastEpochBuilder\client\data\unique_effect_models.json pl

## #122 [uniques] Flag-only effects whose numbers affect damage (Truesight Glass pp590, Singularity pp206, Bane of Winter pp445, Scissor of Atropos pp529, Thicket pp574, Primal Cadence pp588, Jasper pp148)
- impact: Medium for those uniques: the formulas are known but omitted, and the label suggests no numeric effect (for example pp590 changes how crit chance above 100% is used and pp206 removes crits).
- calculator: `unique_effect_models.json player 590, 206, 445, 529, 574, 588, 148 (kind flag; UniqueEffects.add_notes prints the text, no StatMod)` — Only a note; the damage numbers are unchanged.
- game: pp590: if the hit is a crit and the attacker is a player with canSuperCrit, then when crit chance c > 1.0 a super crit rolls with chance min(c - 1, 0.5). On success critMulti becomes (critMulti + 3.0) * (1 + moreCritMulti). The calculator should apply an expected critMulti + 3P instead of just printing a note. The other pps (445, 574, 206, 529) have numeric effects that the calculator omits, but those formulas rest on lower-confidence traces.
- evidence: dump/isil/IsilDump/LE/ProtectionClass.txt lines 5058-5150 (ApplyDamage): "cmp [rax+1E44h],dil; subss xmm6,xmm15; movss xmm0,[184561C04h]; comiss xmm0,xmm6" (the cap at 0.5), "call 0000000180F68ED0h" (the roll), "movss xmm11,[184561C3Ch]; or [rsp+84h],102h; addss xmm0,xmm11; movss [rsi+1CCh],xmm0" (+3.0), then "movss xmm2,[rsi+1D0h]; addss xmm2,xmm15; mulss xmm0,xmm2" (multiply by 1 + moreCritMulti

## #126 [passives-and-sets] Archmage: adaptive spell damage is a constant 1x per point, game scales it 0 / 1 / 2 by max mana
- impact: Medium. Archmage builds are undercounted by 33% of the node's flat spell damage at >= 1000 max mana (3x vs 2x) and overcounted at < 300 max mana (1x vs 2x). The 7%/pt mana-refund PP 460 is also not modelled (see passive PlayerProperty finding).
- calculator: `client/data/field_models.json CharacterMutator.adaptiveSpellDamageFromMaxMana (kind stat, added AdaptiveSpellDamage, note 'x2 at 300 max mana, x3 at 1000'); fed by passive 'Archmage' (passive_node_eff` — The note is never evaluated. The field adds points x 1 AdaptiveSpellDamage regardless of max mana, so total flat Spell damage is always 2 x points (1 base + 1 adaptive).
- game: In CharacterMutator.applyModifiersBeforeExternalStatsCalculation, if the Archmage accumulator (+0x234) is non-zero and the mana object exists: max mana < 300 gives adaptive multiplier 0 (skipped); 300 to 999 gives 1.0; >= 1000 gives 2.0. The result is multiplied by +0x234 and applied as added Damage with the Spell tag (0x100). On top of that, the separate base add_stat gives 1 x points of added Spell damage. The total is 1x points below 300 max mana, 2x from 300 to 999, and 3x at 1000 or more.
- evidence: dump/decomp_extra/CharacterMutator__applyModifiersBeforeExternalStatsCalculation.c, around lines 6108-6133: `if (*(int *)(lVar15 + 0x88) < 300) goto LAB_18260e8a2; ... if (*(int *)(lVar15 + 0x88) < 1000) { fVar22 = 1.0; } else { fVar22 = 2.0; } *(float *)(lStack_4d8 + 0x238) = fVar22 * *(float *)(param_1 + 0x234);`. ISIL dump/isil/IsilDump/LE/CharacterMutator.txt, around lines 17520-17548: `cmp dw

## #129 [passives-and-sets] Set bonuses with PlayerProperty / AbilityProperty (27 of 54 bonuses) are never applied
- impact: Medium. Set builds lose the 2-/3-piece special bonuses (some are large multipliers, e.g. Jormun 632, Shattered Lance 196, Weaver 623). Only visible as a note.
- calculator: `client/scripts/engine/build_mods.gd _add_set_bonuses L557-572: `if prop_id == LE.PLAYER_PROPERTY or prop_id == LE.ABILITY_PROPERTY: notes.append('special bonus ... not counted'); continue`` — Only plain-stat set bonuses become StatMods. All 12 PlayerProperty and 15 AbilityProperty set bonuses are skipped, and unique_effect_models.json has no model for any of their indices.
- game: All set bonuses with setRequirement <= the number of equipped set pieces (including entwined pieces) become active Stats, whatever their property. That includes the 12 PlayerProperty and 15 AbilityProperty bonuses. The calculator should apply those bonuses through its player and ability effect models instead of only noting them as "not counted".
- evidence: dump/decomp/LE.dll/ItemEquipManager.c lines ~4435-4470: `if (*(int *)(lStack_200 + 0x24) <= iVar9) { ... Stats_Stat__ctor(uVar21,uVar7,uVar1,uVar24,lVar27,uVar26,...); List_1_..._Add(*(longlong *)(param_1 + 0x70),uVar21,...)`, with no property check. client/scripts/engine/build_mods.gd L564-568: `if prop_id == LE.PLAYER_PROPERTY or prop_id == LE.ABILITY_PROPERTY: notes.append(... "special bonus ..

## #130 [passives-and-sets] Reforged set items (non-unique items with a Set affix) do not count towards set bonuses
- impact: Medium for builds using reforged set pieces: set bonus thresholds are under-counted (also affects complete_sets used by Legends Entwined).
- calculator: `client/scripts/engine/build_mods.gd set_counts L525-541 (counts only item['unique'] with GameData.unique(...).isSetItem and setID); the item editor offers 'Set' kind affixes (affixes.json specialAffix` — A rare/magic item carrying a Set ('... Reforged') affix contributes 0 pieces.
- game: An equipped item with a Set-type affix (specialAffixType 3, a "Reforged" affix) counts as one piece of the set whose uniqueId is stored in that affix. It also counts toward complete_sets and Legends Entwined. set_counts should add these items to the member list for their setID, alongside real set uniques.
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\ItemData.c lines 28841-28882, ItemData_grantsSetBonus: `cVar2 = Item_1_rarityIsSet(uVar1,0); if (cVar2 == '\0') { cVar2 = ItemData_isReforgedSet(param_1,0); if (cVar2 == '\0') { ... return *(short *)(param_1 + 0x32) == 0x1a7; } } return true;`
ItemData.c line 28435, ItemData_getSetItemUniqueId: `cVar5 = ItemData_isReforgedSet(param_1,0); if (cVar5 != '\0') { 

## #2 [stat-model] Health tags (LowLife/HighLife/FullLife) are not added to the attack and cast speed query
- impact: Low to medium. Only affects 'attack speed while low life' sources (Nightbringer), and only when the 'low' health state is selected.
- calculator: `client/scripts/engine/skill_calc.gd:_speed ~line 1058, store.query(scaler, int(ctx["tags"]), ...). Health tags are added only to ctx["src"] (line 761). Also CDR (line 1163), leech-rate (1427) and ward` — Only the damage, crit, penetration, ailment and defence paths OR the health tags (from _health_tags) into the check tags. A mod such as Bow|LowLife INCREASED AttackSpeed never matches in the speed query, even when player_state.health is 'low'.
- game: Stats.GetStatValue and the other Stats query functions add LowLife (0x100000), HighLife (0x200000) or FullLife plus HighLife (0x600000) to the check tags, depending on the current health state. This applies to every query, including attack speed and cast speed. A mod tagged Bow|LowLife INCREASED AttackSpeed therefore applies while the player is at low life.
- evidence: 1) dump/decomp/LE.dll/Stats.c, Stats_GetStatValue (starts at line 2099); the health-tag block is at lines ~2166-2178. The code is: if ((char)param_1[0x12]=='\0') { if (*(char*)(param_1+0x91)=='\0') { if (*(char*)(param_1+0x92)!='\0') param_3 |= 0x100000; } else param_3 |= 0x200000; } else param_3 |= 0x600000;. The same block repeats for other Stats query functions at lines 830, 1014, 1815, 1988, 2

## #3 [stat-model] Player ailment/buff stacks are scaled linearly and always get 'effect on you'
- impact: Low to medium. It only affects 'Buffs on me' stack counts above 1 with MORE-type buff stats, for example 4 stacks of Totem Armor: ×1.749 in the game against ×1.60 in the calculator. It also affects the effect multiplier on grouped buffs.
- calculator: `client/scripts/engine/build_mods.gd:577-604 (_add_player_ailments: mod.scaled(effect) and mod.scaled(effect * stacks), effect = 1 + query(EFFECT_OF_AILMENT_ON_YOU).increased)` — N stacks of a buff become one StatMod scaled by N, so a 'more' value m becomes 1 + N*m. Every buff, whatever its scaling type, is multiplied by (1 + Σ inc of SP 120). The multiplier has no floor at -1.
- game: For buffScalingType 0 (Individual, max stacks above 1), each stack is its own Stat whose value is multiplied by (1 + clamp(effOnYou, >= -1)), so "more" values multiply across stacks as (1+m)^N. For Grouped* ailments (Swiftness, Stalwart and similar), value = stacks * base with no effect-on-you applied. Non-stacking ailments (+0x20 == 1) use the NonStacking class. I did not open its code, so whether it applies effect-on-you is UNKNOWN.
- evidence: dump/decomp/LE.dll/AilmentReceiver.c lines ~7513-7538 (class selection by ailment+0xb8 and +0x20). dump/decomp/LE.dll/AilmentReceiver+IndividualActiveBuffsForStackingAilment.c lines 117-149: effect-on-you clamped at -1.0, `fVar11 = (fVar10 + 1.0) * fVar11 * fVar12`, and lines 170-184: a `Stats_Stat__ctor_12` call and vtable (+0x378) add per Stat. dump/decomp/LE.dll/AilmentReceiver+CollectedActiveA

## #11 [hit-damage] Penetration stats are filtered by the minion mask in the calculator, the game's Penetration branch has no minion-mask check
- impact: Low/uncertain: only matters when a minion ability is built from a Stats list that contains player penetration stats without the Minion tag (the minion stat snapshot semantics are not verified here); worth checking against how MinionCalc builds its store.
- calculator: `client/scripts/engine/skill_calc.gd:939-950 (shared check '(mod.tags & ctx["minion"]) != ctx["minion"] -> continue' for both LE.DAMAGE and LE.PENETRATION)` — For minion abilities (ctx.minion = tags & MINION) a Penetration (SP 59) stat is applied only if it carries the Minion tag.
- game: Per DamageStats.buildDamageStats, penetration stats (property 0x3B) are not filtered by the minion mask. They apply whenever their other-tags are a subset of the ability's source tags. Only Damage-type stats (property 0) require (stat.tags & minionMask) == minionMask. The calculator should skip the minion-tag requirement for LE.PENETRATION. Whether non-minion-tagged player penetration is present in a minion ability's stat list is not established here.
- evidence: dump/decomp/LE.dll/DamageStats.c: line 389 'uStack_254 = param_2;' and line 612 'uStack_254 = uStack_254 & 0x2000;'. Line 729 (Damage, bVar10==0): 'if ((*(uint *)(lStack_e8 + 0x14) & uStack_254) == uStack_254)'. Lines 930-935 (Penetration): 'if (bVar10 == 0x3b) { ... Stats_getDamageTypeAndOtherTags(...); if ((uStack_220 & (uint)fStack_250) == uStack_220) {', with no uStack_254 anywhere in lines 93

## #12 [hit-damage] Super crit / Deadly Strikes (Truesight Glass) and conditional crit/penetration stats SP 131/132/133 are not modelled
- impact: Low to medium: only affects builds that use those base items / Truesight Glass; crit-multiplier and penetration are understated for them.
- calculator: `SkillCalc._vs_enemy (skill_calc.gd:1267-1295) and _condition_factor; no consumer of LE.CONDITIONAL_PEN/CONDITIONAL_CRIT_CHANCE/CONDITIONAL_CRIT_MULTI (defined in le.gd:138-140, never read); grep of cl` — Average crit multiplier is 1 + P*(cm-1) only. Base-item implicits GlobalConditionalPenetration (items.json: cold pen vs Frozen|Chilled 0.10/0.12), GlobalConditionalCritChance (more crit chance vs Bleeding), GlobalConditionalCritMulti (added vs Bleeding/Chilled) are ignored; unique Truesight Glass (canSuperCrit, deadlyStrikesChancesOnCrit) is ignored.
- game: When the attacker is a player, a crit has been rolled, and canSuperCrit is set with cc>1, there is a Roll(min(cc-1,0.5)) chance of a super crit. A separate Roll(deadlyStrikesChancesOnCrit) can also trigger it. A super crit adds 3.0 to the crit multiplier before it is multiplied by (1+moreCritMulti). The average crit factor should therefore include a q-weighted extra +3.0 on the crit multiplier. Conditional stats SP131/132/133 modify penetration, crit chance and crit multi for the hit when their conditions hold.
- evidence: dump/decomp/LE.dll/ProtectionClass.c lines ~740-800 (ApplyDamage: mutator+0x1e44 test and RngElement_Roll, mutator+0x1c4c read and RngElement_Roll, then "*(float *)(param_2 + 0x1cc) = *(float *)(param_2 + 0x1cc) + 3.0" and "uStack_294 | 0x102"); dump/cs/DiffableCs/LE/CharacterMutator.cs:2341 (deadlyStrikesChancesOnCrit, offset 0x1C4C) and :2439 (canSuperCrit, offset 0x1E44); research/06b_dump_hit_

## #13 [hit-damage] Code-damage components with a textual ADE get ADE 0 (added damage lost), e.g. Healing Hands
- impact: Low (one skill); additionally the base value 40 for Healing Hands is itself marked D? (constant not re-read).
- calculator: `client/scripts/engine/skill_components.gd:171-179 ('addedDamageScaling': float(ade_v) if (ade_v is float or ade_v is int) else 0.0)` — When abilities_code_damage.json stores ADE as a descriptive string, the component is still built with a numeric base but addedDamageScaling = 0, so no added/flat damage reaches it.
- game: For code-set non-weapon base damage, ADE = 0.05 * sum(base damage), which is 2.0 for Healing Hands if its base Fire is 40. For weapon attacks ADE = 1.0. Added damage to the Healing Hands hit should be scaled by that ADE, not by 0. The calculator should either compute 0.05 * sum(damage) when the ADE string indicates calcADE=true and isWeapon=false, or store the numeric ADE in the data.
- evidence: client/scripts/engine/skill_components.gd:171-177 ("addedDamageScaling": float(ade_v) if (ade_v is float or ade_v is int) else 0.0). research/data/game/abilities_code_damage.json, HealingHands: "ADE": "0.05 * 40 = 2.0 (calcADE=true, isWeapon=false)", "conf": "D? (constant at 0x184561E0C not re-read, taken as 40.0)". dump/decomp/LE.dll/DamageStatsHolder.c:1846-1873: if (param_2 != 0) { *(lVar1+0x3c

## #14 [hit-damage] Sacrifice 'addedFireDamage' is claimed as counted 'by rule' but the rule only changes tags
- impact: Low: Sacrifice added fire spell damage is dropped (affects the hit only if Sacrifice has its own damage or is used as a damage source).
- calculator: `research/data/game/skill_conversions.json SacrificeMutator.addedFireDamage (kind tags, tags_add Fire|Spell, no damage); client/data/field_models.json SacrificeMutator.addedFireDamage note '+6 added fi` — Node adds the Fire and Spell tags to Sacrifice; no added damage is created anywhere in the engine.
- game: SacrificeMutator.getTempStats adds an AddedStat on Damage with tag mask 0x108 (Fire|Spell) equal to addedFireDamage (field 0x164) to the ability's temp stats. getTags separately ORs the Fire tag (8) into the ability tags when the field is greater than 0. The calculator should add an added-Damage mod carrying that value (Fire|Spell mask) in addition to the tag change.
- evidence: dump/decomp/LE.dll/SacrificeMutator.c SacrificeMutator_getTempStats: "fVar9 = *(float *)(param_1 + 0x164); if (fVar9 != 0.0) { ... uVar7 = Stats_AddedStat(0,0x108,fVar9,0,0,0); ... List.Add(...)". SacrificeMutator_getTags: "if (0.0 < *(float *)(param_1 + 0x164)) { uVar3 = AbilityMutator_getTags(0,0); return (uVar3 | 8); }". dump/cs/DiffableCs/LE/SacrificeMutator.cs:61 "public float addedFireDamage

## #15 [hit-damage] Partial (fraction < 1) conversions also strip the source damage tag in 'active' rules
- impact: Low for damage numbers (typeBits come from the remaining base damage), but tag-gated mods (e.g. ailment chance / crit mods keyed on the Physical tag) can be wrongly excluded.
- calculator: `skill_calc.gd:826-832 (change_tags = tags_when == 'active' or full) with rules such as SwipeMutator.baseDamageConvertedToLightning, ShurikensMutator.percentBaseDamageConvertedToLightning, VoidCleaveMu` — For rules tagged tags_when 'active' the ability's tags are changed (source type removed, target added) even when only part of the base damage is converted.
- game: The Physical tag is removed only when the conversion fraction is at least 1.0. For a partial conversion (0 < f < 1), the game keeps the source tag and adds the target tag (tags | 2). Tags_remove should apply only when the conversion is full.
- evidence: dump/decomp/LE.dll/SwipeMutator.c (SwipeMutator_getTags): `fVar1 = *(float*)(param_1+300); if (1.0 <= fVar1) { uVar4 = AbilityMutator_getTags(...); return uVar4 & 0xfffffffe | 2; } ... uVar4 = AbilityMutator_getTags(param_1,0); return uVar4 | 2;`. dump/decomp/LE.dll/ShurikensMutator.c (ShurikensMutator_getTags) has the same structure: `if (1.0 <= fVar4) return tags & 0xfffffffe | 2; ... return tag

## #16 [hit-damage] Per-condition 'has_condition' only knows ~28 of the 48 ConditionalDamageProperty values; the rest silently evaluate to 'not present'
- impact: Low to medium: affects only builds using affixes/uniques with the unmodelled conditions; the omission is silent (no note), so the user sees damage too low.
- calculator: `client/scripts/engine/enemy.gd:196-280 (has_condition match; default branch returns 0.0)` — Conditions 11,12,14,15,22,23,24,27,28,29,30,31,34,35,37-43,45 contribute no damage (factor 1) even when a mod uses them, with no note to the user. Condition 2 (HighHealth) is also made true by the full_health flag, and 20/32 'Frozen' use an enemy flag.
- game: Each ConditionalDamageProperty value maps to a real game conditional that the calculator should evaluate. Examples: 22 is true if the enemy has ailment 0x15 or ailment 6; 30 PerSlow gives one effect per stack of ailment 6 with no cap; 23 PerCurse gives a per-curse effect; 14 and 15 are Branded and Branded Boss/Rare; 40 is caster mana above 50% AND a Boss/Rare target. The calculator should model these conditions, or at least warn the user that the mod was not counted.
- evidence: client/scripts/engine/enemy.gd:196-280: has_condition match with default `_: return 0.0`; there are no arms for 11,12,14,15,22,23,24,27-31,34,35,37-43,45. client/scripts/engine/skill_calc.gd:1339-1346: count = Enemy.has_condition(...); f = 1.0 + m*count, so an unmodelled condition gives factor 1; no note is added. client/scripts/engine/build_mods.gd:1205: the mod is created via enum_value("Conditi

## #23 [speed-mana-cooldown] Minion speed stat selection ignores Ability.speedScaler
- impact: Low-medium: affected abilities scale with the wrong speed stat; leap/dive abilities should not scale at all.
- calculator: `client/scripts/engine/minion_calc.gd:272-273 (is_cast = Spell tag or speedScaler==3; else AttackSpeed)` — Minion abilities scale with CastSpeed if they have the Spell tag or speedScaler 3, otherwise AttackSpeed, including speedScaler 54.
- game: The speed stat for a minion ability comes only from its speedScaler. 54 means speed = 1 + increasedCastSpeed, with no attack or cast speed stat applied. Any other value is the stat id to query (2 = AttackSpeed, 3 = CastSpeed), whatever tags the ability has. minion_calc.gd should use the same logic as skill_calc._speed.
- evidence: dump/decomp/LE.dll/UsingAbility.c lines 5404-5408: "cVar2 = FUN_18000e8c0(0x61,_AbilityInfo__TypeInfo,param_2); if (cVar2 == '6') { fVar8 = (float)param_4 + 1.0; goto LAB_181672d53;" ('6' is ASCII 54). Lines 5420-5422: the same property is passed to Stats_GetStatValue as the stat id. The function has no tag check. client/scripts/engine/minion_calc.gd:272: "var is_cast: bool = (tags & LE.SPELL) != 

## #24 [speed-mana-cooldown] hasMinimumUseDuration / minimumUseDuration not applied
- impact: Low (both are cooldown-limited); real above ~+30% cast speed for Teleport (cap 2.86 uses/s) where the calc keeps growing.
- calculator: `client/scripts/engine/skill_calc.gd:1081-1088 (no minimum on cast duration)` — uses/s = speedScale/useDuration without a lower bound on the cast duration.
- game: castDuration = useDuration / speedScale, where speedScale is the product of the ability's speed multiplier and the player's speed stat (floored at 0.1). If Ability.hasMinimumUseDuration then castDuration = max(castDuration, minimumUseDuration). If castDuration is at or below castDelay it becomes castDelay + 0.01. Uses/s is therefore capped at 1/minimumUseDuration for Teleport and Transplant, which is 2.857/s with minimum 0.35.
- evidence: dump/decomp/LE.dll/UsingAbility.c, UsingAbility_InitialiseAbilityUse_1, lines 744-759: 'lVar7 = param_1[0x20]; if (*(char *)(lVar7 + 0x4c) != 0) { if (*(float *)(param_1+0xe4) <= *(float *)(lVar7 + 0x50) && *(float *)(lVar7 + 0x50) != *(float *)(param_1+0xe4)) { *(param_1+0xe4) = *(float *)(lVar7 + 0x50); } ... if (fVar15 < *(float*)(lVar7+0x50)) *(param_1+0xec) = *(lVar7+0x50); }'; then 'if (cast

## #27 [speed-mana-cooldown] Weapon attack-rate tag test differs from CharacterStats.getPropertyMultiplier
- impact: Low (edge case: Melee-tagged skills used with a bow; crossbow type 24 is not weapon-flagged in items.json).
- calculator: `client/scripts/engine/skill_calc.gd:1177-1198 (_weapon_rate: Melee OR (Bow AND bow equipped))` — The weapon rate multiplies a skill that has the Melee tag, or the Bow tag when a bow is in the main hand; is_bow only from typeName 'BOW'.
- game: When the main-hand base type is 23 or 24 (ranged), the weapon attack rate multiplies a skill's AttackSpeed only if the skill has the Bow tag (bit 11). Otherwise it multiplies only if the skill has the Melee tag (bit 9). The two cases are mutually exclusive, and the rate is also skipped when it is 0.
- evidence: dump/decomp/LE.dll/CharacterStats.c, getPropertyMultiplier (about lines 3298-3315): "if (*(float*)(this+0x184) != 0.0 && param_2 == 2) { if (*(char*)(this+0x180) == 0) tags >>= 9; else tags >>= 0xb; if (tags & 1) return *(float*)(this+0x184); } return 1.0". The same file, setMainHandAttackRate (about line 3815): "*(undefined1*)(this+0x180) = param_4". dump/decomp/LE.dll/ItemEquipManager.c lines 30

## #28 [speed-mana-cooldown] 'Recover X% of the remaining cooldown' effects are modelled as +X% cooldown recovery speed
- impact: Unknown/medium: the conversion to a recovery-speed percent has no code basis (labels are D?); it can over- or understate cooldown depending on the event rate.
- calculator: `client/data/field_models.json kind cooldown / recovery_increased with notes 'remaining cooldown': HealingHandsCooldownRecoveryOnOtherAllyHealed (0.75), DiveBomb remainingCooldownRecoveryOnThrowOrBowTh` — The fraction f is added to recovery_increased (a permanent speed bonus), independent of how often the event happens.
- game: ChargeManager.recoverPercentRemainingCooldown(ability, pct) instantly sets charge[i] = clamp(maxCharge[i] - charge[i], 0, 1) * pct + charge[i] for the matching ability, then clamps charge to max if it overshoots. Each trigger is a one-off refund of pct of the missing charge fraction. It is not a standing speed bonus, and the effective cooldown reduction depends on how often the triggering event occurs (and on any per-use or per-3 s caps on the node).
- evidence: dump/decomp/LE.dll/ChargeManager.c lines ~2696-2790, function ChargeManager_recoverPercentRemainingCooldown(Ability, Single): for each charge slot i whose ability matches param_2 and charges[i] < max[i], fVar5 = max[i] - charges[i], clamped to [0,1]; then `afStack_68[0] = fVar5 * param_3 + fStack_54;` is stored back into charges[i], and if the new value exceeds the max it is set to the max. client

## #29 [speed-mana-cooldown] Smoke Bomb minimumCooldown and the general cooldown floor are not applied
- impact: Low (Smoke Bomb with heavy cooldown recovery under that node).
- calculator: `client/scripts/engine/skill_calc.gd:1153-1174 (cooldown_info: cd = length/recovery, no minimum); client/data/field_models.json SmokeBombMutator.minimumCooldown (kind param, param min_cooldown, never r` — Silver Shroud's 6 s minimum is shown as a parameter only; cooldown can fall below it.
- game: When a minimum cooldown is above 0, the cooldown is max(minimumCooldown, 1/regen), where regen is the combined cooldown recovery term. With Silver Shroud, Smoke Bomb's cooldown cannot fall below 6 s. Teleport and BlackHole also have GetMinimumCooldown getters, so the same floor probably applies to them.
- evidence: dump/decomp/LE.dll/AbilityMutator.c:1008 (AbilityMutator_GetCooldown), tail of the function: "if (0.0 < fVar9) { if (fVar11 <= 0.0) return fVar9; if (1.0 / fVar11 < fVar9) return fVar9; return 1.0 / fVar11; }". Here fVar9 comes from the virtual call at +0xda8 and 1/fVar11 is the regen-derived cooldown. dump/decomp/LE.dll/SmokeBombMutator.c:482 SmokeBombMutator_GetMinimumCooldown: "if (*(float *)(p

## #30 [speed-mana-cooldown] Dive Bomb 'reduced delay' modelled as +use speed
- impact: Low-medium for Dive Bomb (cooldown-limited anyway).
- calculator: `client/data/field_models.json DiveBombMutator.reducedDelay and FalconryMutator.reducedDelayWithDiveBomb (kind speed, increased, 1/(1-f)-1, D?)` — The node raises the skill's use speed by 1/(1-f)-1.
- game: Dive Bomb reducedDelay multiplies the dive ability object's own delay timers (DestroyAfterDuration and CastAfterDuration) by (1-f), and speeds up the indicator animation by 1/(1-f)-1. It also shortens the movement duration in spear traversal mode. It is not a player use-speed or cast-rate modifier. It makes the dive land or hit sooner, and it does not raise attack rate or lower the cooldown. Treating it as +use speed is unsupported. The calculator should either drop the speed contribution or mark it as a hit-latency effect with no DPS impact.
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\DiveBombMutator.c lines 1291-1340: "if (fVar1 != 0.0) { ... GetComponent<DestroyAfterDuration>, GetComponent<CastAfterDuration> ... *(float *)(lStack_88 + 0x88) = (1.0 - fVar1) * *(float *)(lStack_88 + 0x88); *(float *)(lVar10 + 0xd4) = (1.0 - fVar1) * *(float *)(lVar10 + 0xd4); ... AbilityObjectIndicator_setIncreasedAnimationSpeed(lVar10,1.0 / fVar18 - 1.0,0

## #39 [character-attrs] Set-property affix values are not multiplied by the number of equipped items carrying the same affix
- impact: LOW: only the Boardman's Fallacy Reforged penetration when the affix sits on two or more equipped items. The count semantics beyond this are from reading UpdateStats without a run, so the exact total (the other copies are also re-applied with the new count) should be confirmed in game.
- calculator: `client/scripts/engine/item_mods.gd:182-230 (affix loop ignores the property's setProperty flag and any equipped-affix count)` — Each affix property is rolled once and added; setProperty is not read.
- game: For an affix property whose setProperty flag is true, the rounded value is multiplied by the number of equipped ItemAffix entries sharing that affix id, whenever that number is not 1. Only affix 780 in affixes.json has this flag.
- evidence: dump/decomp/LE.dll/EpochExtensions.c:17063-17083, EpochExtensions_GetValueAfterRounding_2: `if ((param_8 != '\0') && (param_9 != 1)) { uVar1 = (ulonglong)(uint)((float)param_9 * (float)uVar1); }`. dump/decomp/LE.dll/AffixList.c:2989-2995: `uVar3 = *(undefined1 *)(lStackX_10 + 0x28); ... EpochExtensions_GetValueAfterRounding_2(uVar1,uVar4,uVar2,uVar5,...,param_5,uVar3,param_7,0)`. dump/cs/DiffableC

## #44 [character-attrs] Set bonuses of type PlayerProperty/AbilityProperty are not counted (27 of the set bonuses)
- impact: LOW-MEDIUM: known gap, flagged to the user in the notes; the value of each bonus would need a model per index.
- calculator: `client/scripts/engine/build_mods.gd:566-569 (notes 'special bonus ... not counted')` — Bonuses with property 98 or 58 are only listed in the notes (e.g. Apiarist's 3, Halvar's 3, Boardman's 1/2/3, Zerrick's 2, Corsair's 2, Weaver 2, Jormun's 2, Caretaker's 2, Keplahan's 2 ...).
- game: The game creates a Stat for every set bonus whose setRequirement is at or below the equipped piece count, including property 98 (PlayerProperty) and 58 (AbilityProperty) bonuses. Those effects are active whenever the threshold is met. The calculator should model each PlayerProperty/AbilityProperty index used by set bonuses, not drop all 27.
- evidence: dump/decomp/LE.dll/ItemEquipManager.c lines 4406-4466. Line 4406 calls SetBonusesList_getEntry and iterates its SetBonus list (field 0x20) with a List<SetBonus> enumerator. Line 4435 is the only gate: `if (*(int *)(lStack_200 + 0x24) <= iVar9)`, which is setRequirement <= piece count. The following lines read the modType at +0x20 and the value at +0x10. Line 4460 then calls `Stats_Stat__ctor(uVar2

## #46 [ailments-player] max-1 ailments with application chance above 100% are still counted at uses*chance applications per second
- impact: Low to medium. It only matters for max-1 damaging ailments whose chance exceeds 100% (stacked chance nodes on Spreading Flames, Witchfire, Torment, Spirit Plague, Abyssal Decay, ...). In that case DPS and uptime are overstated roughly in proportion to chance/1.
- calculator: `client/scripts/engine/ailment_calc.gd:44 (rate = uses * chance), 47, 223-226` — rate = uses * chance with no limit on chance. For a maxInstances == 1 ailment with chance 1.5 or 2.0 the cap formula uses life = 1/rate and dps = rate * stack_damage * share. DPS keeps growing with chance above 100%.
- game: For an ailment with maxInstances == 1, a single application event creates at most one stack no matter how far the chance exceeds 100%. The effective rate is uses * min(chance, 1). For maxInstances > 1, a chance above 1 gives floor(chance) guaranteed stacks plus a roll for the fractional part. Each of these stacks is applied individually, up to maxInstances.
- evidence: dump/decomp/LE.dll/AilmentReceiver.c, AilmentReceiver_ApplyAilment (0x18282a870), lines 1384-1412: `if (param_9 <= 1.0) {...} else { ... if ((int)param_2[4] == 1) { param_9 = 1.0; } else if ((1 < (int)param_2[4]) || (*(char *)((longlong)param_2 + 0x12d) != '\0')) { ... AilmentReceiver_ApplyAilment(..., 0x3f800000, ...) loop while (float)(int)uVar15 < param_9 ...`.

dump/cs/DiffableCs/LE/Ailment.cs

## #48 [ailments-player] "Armour Mitigation Applies to DoT" (SP 118) of the PLAYER is used as the share of the ENEMY's armour that mitigates the player's DoT
- impact: Low to medium. Builds with the 118 stat vs an armoured enemy get DoT reduced by armour although the game takes the enemy's value (probably 0, UNKNOWN). Builds without the stat are correct if the monster field is 0.
- calculator: `client/scripts/engine/ailment_calc.gd:265 and 283-285; client/scripts/engine/skill_calc.gd:1211 and 1250-1255 (armour_share = min(1, ctx["store"].query(118).added))` — The player's own stat 118 is read from the attacker's skill store and multiplies the enemy's armour mitigation (1 - mitigation*share) for periodic damage.
- game: DoT armour mitigation on a target is (1 - mitigationFromArmour(target armour) * min(1, target.proportionOfArmourMitigationAppliesToDoTs [0xCC])), using the damaged actor's own 0xCC. The attacker's SP118 only affects DoT that the attacker themself takes. Against an enemy, the share is the monster's 0xCC, which is UNKNOWN in the data (likely 0, so armour would not mitigate the player's DoT).
- evidence: dump/decomp/LE.dll/ProtectionClass.c, ProtectionClass_ApplyDamage, around lines 905-925: `if ((uStack_294 & 1) == 0) { if (*(float *)(param_2 + 0xcc) != 0.0) { fVar35 = PrecalculatedStatsHolder_mitigationFromArmour(param_2); fVar34 = *(float *)(param_2 + 0xcc); if (1.0 < fVar34) fVar34 = 1.0; fVar43 = (1.0 - fVar35 * fVar34) * fVar43; } } else { ... fVar43 = (1.0 - fVar34) * fVar43; }`. The same f

## #51 [ailments-player] Individual (non-grouped) buff ailments: effect multiplier and per-stack multiplication of 'more' values are not modelled
- impact: Low for Chill/Slow/Frailty (the player's DPS barely depends on them), medium for Armour Shred builds (shred scales with +% effect; the calculator gives 100 armour per stack without effect) and for Marked for Death resistance reduction.
- calculator: `client/scripts/engine/enemy.gd:36-66 (mod.scaled(n_eff * (1 + penalty))); ailment effect never reaches the enemy store (ailment_calc.gd inc_eff is used only for damage, EnemyAilments._gain carries onl` — (a) Every buff is scaled linearly by the stack count: scaled() multiplies added, increased AND each `more` by n. Chill (-12% more speed per stack) at 3 stacks gives -36% (x0.64), Slow and Frailty likewise. (b) The player's increased ailment effect (SP 43) is ignored for Armour Shred (NegativeArmour 100/stack) and Marked for Death (all resistances -25%) and for Chill/Slow/Frailty, because the effect never gets into Enemy.store.
- game: For Individual-scaling stacking ailments (Chill, Slow, Frailty, ArmourShred), each ActiveAilment instance adds its own Stat(stat, m). Here m = stacksRepresented * (1 + increasedEffect, when effectOfIncreasedEffectiveness == 0) * (1 + effOnYou) * (1 + boss or penalty factor). The more-values of separate stacks multiply, so Chill 3 stacks gives 0.88^3 = x0.681 speed, not x0.64, and increased ailment effect scales the more value and the added value. ArmourShred is 100 * (1 + effect) NegativeArmour per stack. MarkedForDeath (maxInstances 1) takes t
- evidence: dump/decomp/LE.dll/AilmentReceiver+IndividualActiveBuffsForStackingAilment.c lines 109-114 (increasedEffect read only if ailment+0xb0 == 0), 132-133 (fVar13 = stacks * (inc+1); fVar12 = effOnYou + 1), 149 (fVar11 = (fVar10+1)*fVar11*fVar12), 170-177 (new Stat per buff with that multiplier), 190-193 (stored per ActiveAilment in the dictionary).
dump/decomp/LE.dll/Stats+Stat.c Stats_Stat__ctor_12 li

## #52 [ailments-player] Mutator 'more damage' for TimeRot / Brand of Deception / Witchfire from CharacterMutator passives (fields 0x1A20, 0x1A24, 0x1A28, 0x14E4, 0x1768, 0x176C) not modelled
- impact: Low to medium (omission, listed in the notes). Matters for Time Rot / Brand of Deception / Witchfire builds using those nodes.
- calculator: `No model for CharacterMutator.moreTimeRotDamagePerGlobalSlowChance, ...PerGlobalTimeRotChanceWithVoidSkills, ...PerLowestAttackCastOrThrowSpeed, moreBrandOfDeceptionDamagePerShockChance, moreWitchfire` — Passive nodes with these player properties (passive_node_effects.json playerPropertyField entries) produce no damage effect in AilmentCalc; they appear at most as 'not counted' notes (build_mods._passive_unmodelled).
- game: GetAilmentDamageModifier returns a modifier that is folded into ActiveAilment.moreDamage as a separate more multiplier. For AilmentID 9 (Time Rot): (lowestAttackCastOrThrowSpeed*f_0x1A28+1) * (timeRotWithVoidSkillsChance*f_0x1A24+1) * (slowChanceWithVoidSkills*f_0x1A20+1) - 1. For AilmentID 107 (Brand of Deception): shockChance*f_0x14E4. For AilmentID 122 (Witchfire): ((term from field 0x1780)+1) * (igniteChanceWithFireSkills*f_0x1768 + damnedChanceWithNecroticSkills*f_0x176C + 1) - 1. The calculator should apply these as more factors on that a
- evidence: 1. `python tools/dump_index.py offset CharacterMutator <off>` gave: 0x1A20=moreTimeRotDamagePerGlobalSlowChance, 0x1A24=moreTimeRotDamagePerGlobalTimeRotChanceWithVoidSkills, 0x1A28=moreTimeRotDamagePerLowestAttackCastOrThrowSpeed, 0x14E4=moreBrandOfDeceptionDamagePerShockChance, 0x1768=moreWitchfireDamagePerIgniteChanceWithFireSkills, 0x176C=moreWitchfireDamagePerDamnedChanceWithNecroticSkills.
2

## #53 [ailments-player] Ailments with replaceLowestDamageStacksInsteadOfOldest are modelled as 'oldest stack is replaced'
- impact: Low.
- calculator: `client/scripts/engine/ailment_calc.gd:225-228 and the cap_text 'a new stack displaces the stack with the least time left'` — TimeRot (9), AbyssalDecay (12), Doom (90), ScathingLight (144) are treated like the default mode: the new stack always replaces the stack with the least remaining time and the loss is the share formula.
- game: For ailments with replaceLowestDamageStacksInsteadOfOldest = 1 (e.g. ids 9, 12, 90, 144), once the stack cap is exceeded a new stack replaces an existing stack only if the lowest-remaining-damage existing stack has approximate remaining damage <= (new stack's approximate remaining damage * (1 + mutator damage modifier)). Otherwise the new stack is rejected (the apply function returns 0). For ailments with the flag = 0, the oldest stack is removed (or the weakest-by-relevant-duration stack in the special sub-case when max stacks is 1).
- evidence: dump/decomp/LE.dll/AilmentReceiver.c lines 630-703, ApplyAilmentWithDamageStats: `if (*(char *)(param_2 + 0x13a) == '\0') { ... AilmentReceiver_removeOldestAilment ... } else { for (...) { fStack_b0 = GetApproximateRemainingDamage(...); fStack_b0 = (fVar6 + 1.0) * fStack_b0; ... cVar4 = AilmentReceiver_RemoveLowestRemainingDamage(param_1,uVar2,acStack_c8,uVar17 & 0xff,lStack_a8,0); if (cVar4 == '\

## #54 [ailments-player] Hidden level DR for bosses above level 100
- impact: Low (edge case: enemy level above 100; the effect is a 5% DPS reduction applied to hits and DoT that the game does not apply).
- calculator: `client/scripts/engine/enemy.gd:179-191 (level_dr), used by ailment_calc.gd:263 and skill_calc.gd:1210` — dr = damage_reduction(level) (0 for level > 100) and then, for boss/miniboss, dr = dr + 0.05*(1-dr), so a boss with level above 100 gets 5% DR.
- game: For level > 100 the game returns DR 0 for all enemies, bosses and minibosses included. The 5% boss/miniboss bonus applies only when level <= 100. The calculator should return 0 when level > 100 before applying the boss/miniboss bonus.
- evidence: dump/decomp/LE.dll/ActorScaler.c lines 221-283, ActorScaler_getDamageReductionForLevel (0x1827837E0): line 234 `if (100 < param_1) { return 0; }` comes first. After it, line 237 `if (param_2 == '\0')` has two paths. With param_3 == '\0' it returns the plain table value. With param_3 set (lines 261-263) it returns `(1.0 - t) * 0.05 + t`. The else branch for param_2 set (lines 274-276) returns the s

## #56 [enemy-side] 'Stunned' condition is also true for frozen (and time-locked/petrified) enemies
- impact: LOW-MEDIUM: 'more damage to stunned enemies' sources (SP117 cdp 0, 1 affix + 1 unique + 2 item implicits) are missed when the user marks the target frozen but not stunned; freeze-based builds undercount that multiplier.
- calculator: `client/scripts/engine/enemy.gd:200-202 (has_condition cdp 0) and config_relevance.gd probing of 'stunned'` — ToStunnedEnemies is 1 only if the separate flag 'stunned' is set; 'frozen' is an independent flag that does not satisfy it.
- game: Untyped ToStunnedEnemies (GlobalDamageConditionals case 0) is true for any target whose state controller is in the Stunned state, which includes frozen targets (and, per the typed sub-flags, time-locked and petrified ones). Only the typed conditionals separate plain stun from frozen, time lock and petrify. The calculator should count frozen as satisfying ToStunnedEnemies.
- evidence: dump/decomp/LE.dll/GlobalDamageConditionals.c ~line 97-100: 'case 0: lVar7 = ...StunnedConditional__TypeInfo; AbilityEvent__ctor(lVar7,0); *(undefined1 *)(lVar7 + 0x14) = 0;'. Case 0x25 (line ~356) is the typed one: '+0x14 = 1; +0x10 = 3'.
dump/decomp/LE.dll/StunnedConditional.c Check: 'cVar4 = (**(code **)(*plVar2 + 0x308))(plVar2,...); if (cVar4 != 0) { if (*(char *)(param_1 + 0x14) == 0) { retu

## #59 [enemy-side] Conditional penetration / crit chance / crit multiplier (SP 131, 132, 133) are never consumed
- impact: LOW (5 cannotDrop item bases), but those items lose their signature stat entirely.
- calculator: `client/scripts/engine/le.gd:138-140 (CONDITIONAL_PEN/CRIT_CHANCE/CRIT_MULTI defined, no reader anywhere in client/scripts); skill_calc.gd:1217 only collects CONDITIONAL_DAMAGE and DAMAGE_PER_AILMENT_S` — Mods with property 131/132/133 enter the store but nothing evaluates their ConditionalDamageProperty, so they have no effect.
- game: GlobalDamageConditionals.AddDamageConditionalEffectFromStat accepts stat byte 0x75 (117) and 0x83-0x85 (131-133) and builds DamageConditionalEffects with the same condition switch (penetration, more crit chance, crit multi).
- evidence: client/scripts/engine/le.gd:138-140 defines the three constants, and a grep of client/scripts finds no other use of CONDITIONAL_PEN, CONDITIONAL_CRIT_CHANCE, CONDITIONAL_CRIT_MULTI or the literals 131-133. skill_calc.gd:1218 and ailment_calc.gd:268 check only `mod.property == LE.CONDITIONAL_DAMAGE or ... DAMAGE_PER_AILMENT_STACK`.

dump/decomp/LE.dll/BaseStats.c, around line 102: `else if ((bVar1 

## #60 [enemy-side] ConditionalDamageProperty values with no handler silently count as 0 (Feared, Boss/Rare above half mana, PerDistance, PerCurse, ...)
- impact: LOW-MEDIUM: those uniques/affix contribute 0 instead of their multiplier even when the condition holds (needs a Feared flag, a mana-above-50% flag and a distance input).
- calculator: `client/scripts/engine/enemy.gd:279-280 (default branch of has_condition returns 0.0)` — Ids 11, 12, 14, 15, 22, 23, 24, 27-31, 34, 35, 37-43, 45 are never active. 3 are used by real data: 35 ToFearedEnemies (one unique, more 10-15%), 40 ToBossesAndRaresWhenAboveHalfMana (one unique, more 10-20%), 43 PerDistance (one corrupted Bow affix, more 0.5-1% per unit); the others are in no extracted affix/unique.
- game: When the condition holds, the game applies the more-damage value on the hit: Feared target for id 35, Boss or Rare target with the caster above 50% mana for id 40, and a per-distance scaling for id 43. The calculator would need a Feared flag, a mana-above-half flag and a distance input to model these.
- evidence: client/scripts/engine/enemy.gd:279-280 `_: return 0.0`. dump/cs/DiffableCs/LE/ConditionalDamageProperty.cs: ToFearedEnemies = 35, ToBossesAndRaresWhenAboveHalfMana = 40, PerDistance = 43. dump/decomp/LE.dll/GlobalDamageConditionals.c line 96 `switch(*(undefined1 *)(lStack_58 + 0x11))`, line 344 `case 0x23: uVar11 = _FearedConditional__TypeInfo;`, lines 385-391 `case 0x28:` CasterAboveManaThreshold

## #62 [enemy-side] Several 'more' values under one conditional/per-stack key are combined as a product of separate factors; the game folds them into one value first
- impact: LOW-MEDIUM only when 2+ sources share the exact same condition/tags and uptime < 100% or SP115 stacks > 1 (e.g. two 'more vs ignited' sources at 60% uptime: 1.5x1.5 gives 1.5625 in the calculator vs 1.625 exact).
- calculator: `client/scripts/engine/skill_calc.gd:1344-1346 (for m in values: cond *= 1 + m*count), same in ailment_calc via _condition_factor` — Each SP117/SP115 more entry gets its own factor (1 + m_i*count), where count is the uptime fraction (conditions) or the stack count (SP115).
- game: Entries under one key (same property, tags and special) are combined into one multiplier P = prod(1+m_i) first. For N stacks (SP115) the damage factor is 1 + N*(P-1). For a binary condition (SP117) the factor is P when the condition is true and 1 otherwise, so the expectation at uptime p is 1 - p + p*P. The calculator's prod(1 + m_i*count) underestimates both when a key has two or more entries and count is above 1 or uptime is below 100%.
- evidence: dump/decomp/LE.dll/Stats+Stat.c, getMoreMultiplier: 'fVar5 = fVar5 * (afStackX_8[0] + 1.0)' over the list at +0x28, starting at 1.0. dump/decomp/LE.dll/Stats+Stat.c, HasNonZeroMoreValue: '*param_2 = fVar1 - 1.0'. dump/decomp/LE.dll/BaseStats.c, AddStatModifier: 'lVar2 = Stats_GetExactStatMatch(...)', then 'if (param_4 == 2) ... List<float>.Add(*(lVar2+0x28), param_3)'. dump/decomp/LE.dll/BaseStats

## #63 [enemy-side] Rive third-strike ignite consumption is treated like a per-use wipe
- impact: UNKNOWN to LOW-MEDIUM: ignite uptime/stacks could be wiped up to 3x too often for Rive-ignite builds.
- calculator: `client/scripts/engine/enemy_ailments.gd:37 ('Absorbs Ignite stacks (up to 20) and grants Flame Drinker: Phys penetration per stack') + 159-163` — The ignite stacks on the target are wiped once per use of the skill carrying that flag.
- game: Only hits of the Rive third-strike ability consume ignite. Each such hit fully cleanses the target's ignite and grants min(consumed stacks, 20) Flame Drinker stacks. The consumption rate should therefore be the third-strike hit rate, about one third of Rive strikes if each use is one strike, not the full uses/s of the skill.
- evidence: dump/decomp/LE.dll/Rive3Mutator.c, Rive3Mutator_OnHit (line 676 onward): it calls BaseRiveMutator_OnHit(param_1,...), then `if (Object_1_op_Equality(param_2, *(param_1+0x88)) ...)`, which is the ability-is-own-ability gate. Inside the gate, when `*(float*)(param_1+0x1b8) > 0` and the target has ignite, `AilmentReceiver_hasAilment_1(target+0xb0, 1)` is true. It then runs `fVar8 = AilmentReceiver_cl

## #64 [enemy-side] Soul Feast 'Hits absorb poison stacks' modelled as a plain wipe; trace says the effect is unverified and also gives enemy shred
- impact: UNKNOWN; poison stacks and poison-resistance shred for Soul Feast builds may be off.
- calculator: `client/scripts/engine/enemy_ailments.gd:38-39 (CONSUMERS: 'Hits absorb poison stacks from target')` — Poison on the target is wiped once per use, no other effect on the enemy.
- game: UNKNOWN. The code shows that OnHit is gated on the target having ailment 7 (poison) and calls cleanseAilment, but the consumption amount and frequency are not traced. The armour and poison-resistance buff per stack, with its 60 limit, is also not traced.
- evidence: dump/work_wave4/traces/SoulFeastMutator__consumePoisonStacks.txt: line 3 has the node text "Consumes Poison Stacks | +1% Armor Per Stack | +6% Poison Resistance Per Stack | 60 Buff Limit". Line 5 has "previous (UNVERIFIED, D?) semantic". Line 6 has "Consumption effect inside elided branch." Line 10 has "[gate h0] ... GATES ... in SoulFeastMutator.OnHit ISIL#277..323 -> calls: AilmentReceiver.Sprea

## #65 [enemy-side] Enemy armour mitigation uses the enemy's level as the area level
- impact: LOW: only a mismatch when monster level != area level.
- calculator: `client/scripts/engine/skill_calc.gd:1208 and 1247/1253; ailment_calc.gd:285 (area_level = enemy.level)` — armour_mitigation(armour, enemy.level, ...) with a single 'level' that also selects the DR table row.
- game: Armour mitigation in the hit path uses L = ZoneInfoManager.areaLevel (static), with the formula's L+5 term. The game's damage-reduction table is keyed by the monster level passed to setHealthAndDamageResistanceForLevel. The calculator should keep these as separate inputs, or document that it assumes monster level equals area level.
- evidence: dump/decomp/LE.dll/PrecalculatedStatsHolder.c:346-376, mitigationFromArmour(float, bool nonPhys, bool overrideLevel, int levelOverride): 'if (param_4 == 0) { ... param_5 = **(int **)(_ZoneInfoManager__TypeInfo + 0xb8); } fVar2 = (float)(param_5 + 5);'. When the override flag is 0, the level is read from the ZoneInfoManager static. The flag is only set to 1 by CharacterSheet.c:1327/1344, which are 

## #92 [minions-shadows] Echo: guaranteedEcho (Volatile Reversal) and echo-triggered buffs are not modelled; eligibility uses base ability tags
- impact: LOW-MEDIUM. The guaranteed echo raises the chance for the next cast to 100%. The echo buffs are missing damage for idol/gear properties 58 and 59.
- calculator: `client/scripts/engine/echo_calc.gd:60-71 (eligible), 75-99 (chance), 103-128 (echo_mods); field_models.json VolatileReversal*.guaranteedEchoAfterLongJump is flag-only` — Echo chance is Rive/Vengeance/Abyssal-adjusted base chance clamped to [0,1]. guaranteedEchoAfterLongJump is a text flag only. The buffs given when an echo is created (PlayerProperty 58 'increased void damage if echoed recently', 59 melee, and the Frenzy-on-echo property) are not modelled. Eligibility reads the ability's asset tags (ab.tags).
- game: After a jump longer than 4 m with the Volatile Reversal node, the game sets CharacterMutator.guaranteedEcho (+0xCE0). The next eligible cast then echoes with certainty whenever its chance is above 0 and no override chance was passed. The flag is cleared when that echo is created from a normal cast. Creating an echo also applies applyOnEchoBuffs: 4 s Stat(Damage, void tag, increased) and melee-tag buffs from PlayerProperty 58 and 59, plus a further buff gated on field +0x1a10. The calculator models none of these.
- evidence: dump/decomp/LE.dll/CharacterMutator.c line ~45960-45975, CharacterMutator_TryToEchoAbility: 'cVar11 = RngElement_Roll(..., fVar24, 0); if (((cVar11 != 0) || (((0.0 < fVar24 && (*(char *)(param_1 + 0xce0) != 0)) && (param_6 == 0.0)))) && ((uVar14 & 0x110) == 0x110 || ((uVar14 >> 10 & 1) != 0 || (uVar14 >> 9 & 1) != 0)))'. A few lines further on, '*(undefined1 *)(param_1 + 0xce0) = 0' is set when pa

## #93 [minions-shadows] Minion AI priority model: range, health-threshold and other gates are assumed open; companion/rounding details
- impact: LOW-MEDIUM. It affects which of a minion's abilities contribute for golems, abominations and totems.
- calculator: `client/scripts/engine/minion_calc.gd:258-293 (priority loop) and minion_count.gd:178, 229 (roundi)` — The first ability in the minion's abilityList that is not on cooldown gets its share, the first one without a cooldown takes all the remaining time, and abilities after it are never used. 'The target is assumed within range of every ability (D?)'. Counts and companions are rounded with Godot roundi (half away from zero).
- game: The first ability in list order that passes all of the following gates is used: skip flag, cooldown, health threshold, zone compatibility, summon-count cap, creator distance, and a target within pursuit range. If none passes, the minion uses the best-scoring fallback ability. The calculator's list-order and cooldown model is therefore a simplification. Whether a given ability is range-gated or health-gated depends on that minion's AbilityRangeList data, which the model does not read.
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\UsingMultipleAbilitiesAI.c, function UsingMultipleAbilitiesAI_chooseAbility (lines 986-1575):
- 1196: "if (iVar8 <= iVar17) goto LAB_18168d2f4;" (loop over the ability list in order)
- 1200-1202: "(**(code **)(*plVar3 + 0x198))(plVar3,iVar17,...)" skip flag, then "UsingMultipleAbilitiesAI_abilityOnCooldown(param_1,iVar17,0)"; a hit goes to LAB_18168d2ec, whic

## #97 [buffs-and-skillbuffs] Buff-on-me scaling omits the per-instance increased effect and the per-stack separation of 'Individual' buffs
- impact: Low to medium. Individual compounding: Contempt 5 stacks of +10% more armour give x1.61 in the game vs x1.50 in the calc; Totem Armor 4x15% more damage give x1.75 vs x1.60; Crimson Shroud 3 stacks give 0.857 vs 0.85. Instance increased effect: Smoke Blades 'effectiveness' x1 to x5 is not applied to the player's own SmokeBlades stacks.
- calculator: `client/scripts/engine/build_mods.gd:575-604 (_add_player_ailments: store.add(mod.scaled(effect * stacks)), effect = 1 + EFFECT_OF_AILMENT_ON_YOU.increased); ailment_calc.gd self branch (inc_eff of a p` — Every stack's buff stats are multiplied linearly by stacks * (1 + SP120 effect on you). The effect gained from the applying ability (IncreasedAilmentEffect of the application) is never used for buffs on the player. 'more' buff stats scale linearly, 1 + n*m.
- game: For an Individual-scaling stacking ailment (53 positive ailments have effectOfIncreasedEffectiveness 0 and are Individual, plus 3 with effect 1), each ActiveAilment instance contributes its own scaled Stat to the actor. Scale = (1 + moreBuffEffectAgainstBosses or Players) * stacksRepresented * (1 + instance increasedEffect, only when effectOfIncreasedEffectiveness == 0) * (1 + effectOnYou[ailment]). Several stacks of a "more" buff therefore compound multiplicatively as (1+m*scale)^n, and the application's increased effect (e.g. Smoke Blades eff
- evidence: dump/decomp/LE.dll/AilmentReceiver.c, addBuffsModifiedByStacksAndIncreasedEffect (line 6262-6303): 'if (*(int *)(lVar2 + 0xb0) == 0) { fVar14 = *(float *)(param_2 + 0x94); } else { fVar14 = 0.0; }' and 'fVar14 = (fVar13 + 1.0) * fVar1 * (fVar14 + 1.0) * (fVar12 + 1.0);' with fVar1 = *(param_2+0x8c). Offset 0xB0 is effectOfIncreasedEffectiveness (dump/cs/DiffableCs/LE/Ailment.cs line 126).

dump/de

## #101 [buffs-and-skillbuffs] Tempest Strike 'more damage per mana cost' reads the ManaCost stat instead of the skill's mana cost
- impact: Low to medium for Tempest Strike builds: the node's damage bonus is lost.
- calculator: `client/data/field_models.json TempestStrikeCold/Light/PhysMutator.moreDamagePerManaCost (per='value:ManaCost'); effect_models.gd:133-134 source 'value' = store.query_untagged(SP).value()` — The source is the aggregate of the ManaCost STAT mods in the store (normally about 0), not the ability's mana cost, so the node adds roughly +0% damage.
- game: more damage = f * BaseMana.getManaCost(ability), with f = 0.015 per node point. The source should be the ability's full computed mana cost, not the aggregate of ManaCost stat mods.
- evidence: dump/decomp/LE.dll/TempestStrikeMutator.c, TempestStrikeMutator_getTempStats (~line 2269): "if (*(float *)(param_1 + 0x130) != 0.0) { ... BaseMana_getManaCost_2(*(longlong *)(param_1 + 0x1e0), ...); uVar8 = Stats_MoreStat(0,0); List.Add(*(param_1+0x270), uVar8) }". research/data/game/mutator_field_semantics_MZ.json (~line 46839) gives the semantic "Temp stat: more damage = f * mana cost of the abi

## #104 [buffs-and-skillbuffs] Sacrifice 'more DoT damage on cast' modelled as increased
- impact: Low. Wrong stacking bucket for the DoT damage of Sacrifice builds.
- calculator: `client/data/field_models.json SacrificeMutator.moreDotDamageOnCast (mod=increased, stat=Damage, tags=DoT, input sacrifice_buff)` — Adds the value into the 'increased' bucket of DoT damage.
- game: When the player casts Sacrifice with at least one minion, a 6 s buff is applied that is a separate multiplicative 'more' Damage modifier restricted to the DoT attack type. It should use mod="more", not "increased".
- evidence: dump/decomp/LE.dll/SacrificeMutator.c lines 453-474: inside `if (0 < SummonTracker_numberOfMinions_3(...))` and `if (*(float*)(param_1+0x28) != 0.0)`, the code calls `uVar11 = Stats_MoreStat(0,0x1000,(int)lVar14,0,...)`, then `Buff__ctor_2(uVar12,uVar11,0x40c00000,_StringLiteral_sacrifice_dot_on_cast_bug,0)`, then `StatBuffs_addBuff_2`. 0x40c00000 is 6.0f, matching the 6 s duration. dump/decomp/LE

## #107 [buffs-and-skillbuffs] Untagged 'value:' sources where the code reads a tag-filtered stat value
- impact: Low to medium. Undercount of tag-specific mods feeding these scaling nodes.
- calculator: `effect_models.gd:133-138 (value/increased/added sources use query_untagged = mods with tags==0 only; stat_store.gd:99); field_models.json per='value:CriticalChance' (SerpentStrike ...PerMeleeCritChanc` — Only mods without tags are counted, so crit chance, attack speed, ailment chance etc. that carry Melee/Fire/Spell/Throwing tags are excluded from the source.
- game: The game calls Stats.GetStatValue(stat, tags) with the relevant tag mask, for example CriticalChance with melee (0x200). That includes every mod whose tags are a subset of the mask, so melee-tagged crit chance counts. The calculator should query with the same tag mask instead of tags=0.
- evidence: 1. dump/decomp/LE.dll/SerpentStrikeMutator.c, SerpentStrikeMutator_mutateAilmentInstance, line 3755: "fVar9 = (float)Stats_GetStatValue(*(longlong *)(param_1 + 0x2a0),4,0x200,0,0,0,0,0,...". The stat argument is 4 and the tags argument is 0x200.
2. client/scripts/engine/le.gd line 72: "const CRIT_CHANCE: int = 4", so stat 4 is crit chance.
3. client/scripts/engine/effect_models.gd lines 133-138: t

## #108 [buffs-and-skillbuffs] buff_skill_models.json: Dark Quiver tag assumption and Symbols of Hope activation without the Divine Flare exception
- impact: Low.
- calculator: `client/data/buff_skill_models.json 'Dark Quiver' (confidence D?, tags 'Bow', when_input black_arrow_ready) and 'Symbols of Hope' entry DamageTaken -0.05 per symbol (active_only, no condition for Sigil` — Dark Quiver: +100% increased damage with the Bow tag for the whole evaluation while the input is on. Symbols of Hope activation: -5% damage taken per symbol applied whenever the activation input is on.
- game: Symbols of Hope activation applies MoreStat(DamageTaken, -0.05 * symbols * (1 - AbilityProperty#9)) only when damageReductionDisabled is false. With the Divine Flare node (canCastDivineFlare) allocated, no damage reduction is applied. Dark Quiver adds a tag-less +100% increased Damage stat to the attack that spends a black arrow; the Bow restriction is an assumption.
- evidence: dump/decomp/LE.dll/SigilsOfHopeActiveMutator.c, SigilsOfHopeActiveMutator_Mutate: "if (*(char *)(param_1 + 300) == '\0') { ... uVar6 = Stats_MoreStat(6,0,(float)iVar1 * -0.05 * fVar9,0,0,0); ... List.Add }". research/data/game/mutator_field_semantics_MZ.json line 26848: "Active.damageReductionDisabled = field (removes MoreStat(DamageTaken, -0.05*sigils))". client/data/field_models.json:27221 Sigil

## #118 [uniques] 'value:' / 'increased:' sources use untagged-only queries where the game reads totals by ailment or by tag
- impact: Low to medium: the Falcon bleed chance is probably near 0 in the calculator, and the Warpath axe-throw frequency is understated.
- calculator: `EffectModels.source() kinds 'value' and 'increased' use StatStore.query_untagged (tags 0, special 0); used by ability 727:3 (per value:AilmentChance, Falcon gets your Bleed chance) and ability 97:3 (W` — 727:3 counts only ailment-agnostic chance mods (special == 0), excluding Bleed-specific chance. 97:3 counts only untagged increased Damage.
- game: 727:3: Falcon bleed chance = Stats.GetAilmentChance(playerStats, ailment 2 = Bleed) × field. This includes Bleed-specific chance mods and ailment-agnostic ones. 97:3: Axe Throw interval = 1/((GetTotalModifier(Damage, tags=Physical, special 0) × field)/0.1 + 1). This counts untagged and Physical-tagged Damage modifiers, and GetTotalModifier is (1+Σinc)·Πmore − 1.
- evidence: dump/decomp/LE.dll/FalconryMutator.c ~796-806: Stats_GetAilmentChance(lVar11,2,0,0,...); Stats_AilmentChanceStat(2,0).
dump/decomp/LE.dll/Stats.c 750-757: Stats_GetAilmentChance(p1,p2,p3,p4,p5) calls Stats_GetStatValue(0,1,p3,p4,0,0,p2,p5,0,1,0), so the ailment id lands in the special slot.
dump/decomp/LE.dll/Stats.c 51-62: Stats_AilmentChanceStat(ailment,...) builds a Stat with property 1 and the

## #124 [uniques] 'param' kind unique effects with damage impact are displayed but not calculated (pp235, pp571, ability 881:0, 263:4, 216:6, 731:0, 689:12/13, 402, 12:2)
- impact: Low to medium. The '784 of 866 modelled' coverage includes a number of display-only models; their real contribution (extra casts) is missing from DPS. This is not a contradiction by itself, but the models should be labelled 'not computed'.
- calculator: `BuildMods._apply_model case 'param' / 'resource' (build_mods.gd:977-993) stores values in result['params']. The only readers are projectiles, projectile_limit, shotgun (SkillCalc.projectile_hits, skil` — Rows like 'Bow ability repeat (chance)' (pp235), 'Fire spirit ability repeat' (pp571), 'Additional shadow attack' (881:0), 'Additional Smite targets' (216:6), 'Additional shuriken ricochet' (263:4) are listed but change no damage number.
- game: pp235 rolls chanceToRepeatBowAbility and requires repeatBowAbilityCooldownIndex >= repeatBowAbilityCooldown (1.0 s). The trace suggests a matching ability is then cast again, which would add extra damage events at most once per second. The calculator currently applies no damage from this effect and shows only an informational row.
- evidence: client/scripts/engine/build_mods.gd:977-993 ('param'/'resource' store into result['params'] and nothing more). Consumers of p.get("param"): skill_calc.gd:436, skill_components.gd:206, echo_calc.gd:93, enemy_ailments.gd:352-355 (PARAM_BUFFS, lines 96-108, no 'hits' key), minion_count.gd:139. client/data/unique_effect_models.json:1410-1418 (pp235, param 'hits', confidence 'D?'). dump/work_wave3/pp/p

## #125 [uniques] Recency windows of Gambler's Fallacy, Lightning Bow/Throwing chain and 'next attack' uniques depend on manual toggles and omit code gates (pp419, pp89, pp229/230)
- impact: Low. Uptime follows from crit chance and attack rate in the game, while the planner takes a fixed toggle; channelled skills wrongly receive the pp419 bonus.
- calculator: `unique_effect_models.json player 419 and 89 (crit chance without a recent crit / less crit chance after a crit), 229 and 230 (2 s lightning penetration window)` — Binary toggles (Conditions flag crit_recently, input defaults true). pp419 does not exclude channelled skills (only a note), 229/230 are always on.
- game: pp419 (Gambler's Fallacy): non-channelled-skill crit chance applies only while now > timeLastCrit + 4 s, so it depends on the crit rate. pp89: each crit starts a 4 s timed buff that applies the crit-chance penalty. pp229/230 (Zeurial's Hunt): using a lightning bow attack opens a 2 s window that boosts only the next throwing attack with lightning penetration, and the reverse holds for throwing then bow. It is not a permanent bonus.
- evidence: dump/work_wave3/pp_c/pp_419.txt, CharacterMutator.ApplyConditionalTemporaryStats: `if ((F.critChanceWithNonChannelledSkillsIfYouHaveNotDealtACriticalStrikeRecently != 0.0) && (fVar26 = F.timeLastCrit, fVar23 = (float)Time_1_get_time(0), fVar26 + 4.0 < fVar23)) { cVar6 = FUN_18000e8c0(0x1b,_AbilityInfo__TypeInfo); if (cVar6 == '\0') { ... Stats_AddedStat(4,0)`.
dump/work_wave3/pp_c/pp_89.txt, Chara

## #131 [passives-and-sets] moreVoidDamageDoubledWithUnder30Block: doubling below 30% block is not modelled
- impact: Low-medium: players with < 30% block (most non-block builds) get half of the intended bonus.
- calculator: `client/data/field_models.json CharacterMutator.moreVoidDamageDoubledWithUnder30Block (kind stat, more Damage tag Void, note 'Doubles when block chance below 30%', no condition); passive_node_effects.j` — Always adds 2% (x points) more Void damage; the note is text only.
- game: more Void damage applied = field x (below-30% factor, apparently 2.0, if BlockChance < 0.3, else 1.0). The calculator needs a block-chance condition, or a doubling when block chance is under 30%. The game also needs the player's own PrecalculatedStatsHolder, so a missing object means no doubling.
- evidence: dump/decomp_extra/CharacterMutator__applyModifiersBeforeExternalStatsCalculation.c lines ~6414-6429: `fVar22 = *(float *)(param_1 + 0x1a14); ... cVar5 = Object_1_op_Implicit(uVar16,0); if (cVar5 == '\0') { LAB_18260f1d3: fVar20 = 1.0; } else { ... fVar23 = PrecalculatedStatsHolder_GetBlockChance(); if (0.3 <= fVar23) goto LAB_18260f1d3; } *(float *)(param_1 + 0x1a18) = fVar20 * fVar22;`. dump/isil

## #132 [passives-and-sets] Flame Drinker (moreDamageWithHighCostMeleeAttacks): planner restricts the More to Elemental damage, code adds untagged More Damage for Melee skills costing >= 10 mana
- impact: Low-medium: physical/void/poison portions of a high-cost melee skill are wrongly excluded from the bonus; the 10-mana threshold and Melee tag are not enforced against the real skill cost.
- calculator: `client/data/field_models.json CharacterMutator.moreDamageWithHighCostMeleeAttacks (more Damage, tags 'Elemental', boolean input 'Expensive melee attack' default true)` — 3% x points More damage applied only to damage with the Elemental tag; the 'high cost' condition is a user checkbox, the Melee/cost>=10 check is not derived from the skill.
- game: When the used ability has bit 9 (Melee) set and BaseMana.getManaCost >= 10.0, the game adds a MORE Damage stat (property Damage, tags None) of value field+0xC2C. It applies to all damage types of that skill, not only Elemental.
- evidence: dump/decomp/LE.dll/CharacterMutator.c lines 7313-7328: `if ((*(float *)(param_1 + 0xc2c) != 0.0) && ((uVar11 >> 9 & 1) != 0)) {... fVar24 = BaseMana_getManaCost(...); ... if (10.0 <= fVar24) {... uVar13 = Stats_MoreStat(0,0); ... List_Add`. dump/isil/IsilDump/LE/CharacterMutator.txt around lines 188396-188410: `bt r15d,9`, `comiss xmm0,xmm8`, `movss xmm6,[rdi+0C2Ch]`, `xor r9d,r9d`, `movaps xmm2,x

## #133 [passives-and-sets] Minion penetration from overcapped resistance: planner uses necrotic overcap for one 'Necrotic|Elemental' stat, game makes four per-type stats
- impact: Low-medium: elemental minion builds lose the penetration; non-necrotic skills get nothing; a mod tagged Necrotic|Elemental also does not match an elemental-only skill.
- calculator: `client/data/field_models.json CharacterMutator.minionPenetrationPer5PercentOvercappedResistanceForNecroticOrEle (kind minion_stat, Penetration, tags 'Necrotic|Elemental', per res:4, offset 0.75, facto` — One Penetration mod with tags Necrotic|Elemental whose size comes only from the (uncapped) NECROTIC resistance; Fire/Cold/Lightning minion penetration from their own resistances is not produced.
- game: Four independent Penetration stats on the player, each tagged Minion plus one damage type. Each stat is max(0, protection(type) - 0.75) x field(+0x6a8) x 20. Fire, cold and lightning each come from their own resistance, and necrotic comes from necrotic resistance. A fire minion skill therefore gets penetration from fire resistance only, and the necrotic stat does not feed it.
- evidence: dump/decomp_extra/CharacterMutator__applyModifiersBeforeExternalStatsCalculation.c:
- Lines 5296-5316 (Necrotic): `afStack_518[0] = Stats_GetProtectionValue(*(param_1+0x98),0x1b,0); afStack_518[0] = afStack_518[0] - 0.75; if (<0) =0; afStack_518[0] = afStack_518[0] * fVar22 * 20.0;` with fVar22 = *(float*)(param_1+0x6a8). Then UpdateDynamicStat(..., param_1+0x6b8, ...) and `CONCAT44(..,0x2020)` fo

## #134 [passives-and-sets] Shift bleed buff: only the duration half of the bonus is modelled, the bleed effect half is dropped
- impact: Low: bleed effect per point (0.25/pt in tree data) of the next attack missing.
- calculator: `client/data/field_models.json CharacterMutator.bleedEffectAndDurationForNextAttackFromShift (stat IncreasedAilmentDuration only; note 'Same value also gives bleed effect')` — Adds only IncreasedAilmentDuration (Bleed) when 'Attack right after Shift' is on.
- game: After Shift, the next attack gets both IncreasedAilmentDuration (SP 0x2a) and IncreasedAilmentEffect (SP 0x2b), each equal to the field value (0.25 per point), applied for Bleed. The calculator should add both stats, not only the duration.
- evidence: dump/decomp/LE.dll/CharacterMutator.c lines 7147-7164: `if (*(float *)(param_1 + 0xa88) != 0.0) { ... Stats_Stat__ctor_3(uVar13,0x2b,0,2,uVar15,0); ... Stats_Stat__ctor_3(uVar13,0x2a,0,2,in_stack_fffffffffffffcb8,0);`. Both stats are added to the same list. tools/dump_index.py field: `CharacterMutator.bleedEffectAndDurationForNextAttackFromShift float offset 0xA88`. dump/cs/DiffableCs/LE/SP.cs lin

## #135 [passives-and-sets] Event-based self-buff chances are modelled as AilmentChance per hit of the skill; game rolls them on other events
- impact: Low-medium: Haste/Divine Essence/Void Essence/Marked-for-Death uptime derived from skill use rate instead of minion kills, 1/s ticks, totem summons; affects only buffs on you / enemy debuffs, not directly the hit damage.
- calculator: `client/data/field_models.json CharacterMutator.chanceToGainHasteFor2SecondsOnMinionKillOrDeath, chanceToGainHasteWhenYouSummonATotemFromPassives, divineEssenceEverySecondChance, voidEssenceOnKillChanc` — A per-hit chance for every skill use, so the buff stacks scale with the skill's use rate.
- game: Haste (minion kill or death): one roll per minion kill or death event. Divine Essence: one roll per second while health is above the threshold, independent of skill use rate. Both buffs are better modelled from the minion-kill rate and a fixed 1/s tick respectively, or exposed as a user-set uptime or stack count.
- evidence: 1) dump_index offset CharacterMutator 0x694 gives chanceToGainHasteFor2SecondsOnMinionKillOrDeath. dump/decomp/LE.dll/CharacterMutator.c, OnMinionKill (about lines 35395-35418): `RngElement_Roll(**(TypeInfo+0xb8), *(param_1+0x694), 0)` and on success `AilmentReceiver_ApplyStackOfAilmentForDuration(owner+0xb0, 0x21, 0x40000000, ...)`, which applies ailment 0x21 to self. I did not decode 0x21 as Has

## #136 [passives-and-sets] Void Corruption (Void Knight): statsPerMastery1Level is not counted
- impact: Low-medium: up to roughly 1% crit multiplier per point spent in the mastery (tens of percent) missing for Void Knight. The planner already has Build.points_in_mastery for the formula.
- calculator: `client/data/field_models.json CharacterMutator.statsPerMastery1Level (kind stat_list, per 'points'); build_mods.gd _apply_passive_model L486-489: `if str(model['per']) == 'points': _passive_unmodelled` — Not counted (note only).
- game: While the node has at least 5 points, the build gets +0.01 CriticalMultiplier for each point spent in mastery index 1, i.e. value = 0.01 * masteryLevels[1] (the sum of points allocated to nodes of mastery 1). The calculator should add this using Build.points_in_mastery instead of treating per="points" as unmodelled.
- evidence: dump/decomp/LE.dll/CharacterMutator.c, CharacterMutator_updateStatsPerMastery1Level (L56881):
- L57050-57060: `lVar6 = *(longlong *)(param_1 + 0x2108); if (*(longlong *)(lVar6 + 0xa8) != 0) { ... EpochExtensions_safeGet_2(uVar7,1,afStackX_20,...); fVar12 = (float)((uint)afStackX_20[0] & 0xff);`
- L57088-57098: `(**(code **)(*plVar5 + 0x2f8))(plVar5, *(undefined1 *)(alStack_88[0] + 0x10), fVar12 * 

## #137 [passives-and-sets] Stack-count inputs of passive buffs have hard-coded maxima instead of the game's max-stack fields
- impact: Low: manual input can exceed the achievable stacks (cast speed +5%/stack, damage taken -4%/stack).
- calculator: `client/data/field_models.json CharacterMutator.arcaneMomentumStatsPerStack (input max 10), arcaneShieldStats (max 10), blade conduit (max 10); corresponding fields maxArcaneMomentumStacks, maxArcaneSh` — The user may enter up to 10 stacks regardless of the points in the node.
- game: Arcane Momentum stacks cannot exceed maxArcaneMomentumStacks, which is 1 per point in the node (5 points, so at most 5). Arcane Shield stacks cap at maxArcaneShieldStacks, a flat 4 from the node. The calculator input should be clamped to these values rather than a fixed 10.
- evidence: dump/decomp/LE.dll/CharacterMutator.c line 12336, in CharacterMutator_GainArcaneMomentumStack: `if (*(int *)(param_1 + 0x128) < *(int *)(param_1 + 0x124)) {`. `python tools/dump_index.py offset CharacterMutator 0x124` returns maxArcaneMomentumStacks and `... 0x128` returns currentArcaneMomentumStacks. research/data/game/passive_node_effects.json (around lines 33401 and 36122): maxArcaneMomentumSta

## #138 [passives-and-sets] 'More damage per attack mana cost' passives use a typed input, not the used skill's mana cost
- impact: Low: the planner already knows the skill's mana cost, so the result can diverge if the input is not kept in sync.
- calculator: `client/data/field_models.json CharacterMutator.moreDamagePerMeleeAttackCost / moreDamagePerThrowingAttackCost (input attack_cost default 10, tags Melee / Throwing)` — x = field x typed 'Attack mana cost' (default 10), independent of the skill's computed cost.
- game: More Damage (untagged) = field value x BaseMana.getManaCost(AbilityInfo, ...) of the ability being used, applied only when the ability has the Melee (bit 9) or Throwing (bit 0xA) tag. The calculator should derive attack_cost from the skill's computed mana cost instead of a free input.
- evidence: dump/isil/IsilDump/LE/CharacterMutator.txt lines ~188303-188340: `movss xmm0,[rdi+0CD0h]; bt r15d,9; call 18128E110h; movss xmm6,[rdi+0CD0h]; mulss xmm6,xmm7; xor edx,edx; xor ecx,ecx; call 1816A3F60h`. The 0xCD4 block uses `bt r15d,0Ah` and the same call sequence. `python tools/dump_index.py func getManaCost` returns `0x18128E110 BaseMana_getManaCost Single getManaCost(AbilityInfo, Single) (decom


# Part 2. Findings that affect defence (22)

## #68 [defense] DamageTaken stats with a hit-event specialTag (damage taken on block) are never applied
- impact: high for block builds: damage taken on a blocked hit is overestimated, and for The Monolith blocked hits would deal 0. Low for The Confluence of Fate (a small penalty is missed).
- calculator: `defense_calc.gd _taken / player_layers (store.query(DAMAGE_TAKEN, tags) with special = 0); stat_store.gd query skips mods with special != 0` — DamageTaken mods with specialTag 6 (Block) or 1 (Hit) are excluded from every query. The block layer is only 1 - block*blockDR.
- game: On a blocked hit, ApplyDamage ORs 0x20 into the hit-event mask. DamageTaken mods with specialTag 6 (damage taken on block) then apply in the per-type damage-taken step. Mods with specialTag 1 apply on hits (mask bit 0x1). The calculator should query DamageTaken with the hit-event mask (block bit set for the blocked-hit branch), not special = 0.
- evidence: dump/decomp/LE.dll/Stats.c lines 183-190: `if (*(char *)(param_2 + 0x11) != '\0') { bVar1 = ...; in_RAX = Maths_integerPower(2,bVar1 - 1,0); if (((uint)in_RAX & param_5) != (uint)in_RAX) goto LAB_18169f261; }` (param_2+0x11 is the mod's specialTag; param_5 is the hit-event mask). dump/decomp/LE.dll/ProtectionClass.c line 717: `uStack_294 = uStack_294 | 0x20;` inside the successful block roll (RngE

## #67 [defense] Passive/skill-node PlayerProperty effects of kind more_player_property are dropped by the defense calc
- impact: medium. Less damage taken from these nodes is silently missing, so taken damage is overestimated and EHP underestimated for builds using them. No note is shown to the user.
- calculator: `defense_conversions.gd _add_node_pps (line 58) feeding pp_values` — Only effects with stat.kind == 'player_property' are collected. MorePlayerPropertyStat effects are skipped, and stat_from_effect returns null for them, so nothing else applies them.
- game: PlayerProperty stats created by MorePlayerPropertyStat (Stat type 0x62 with a "more" value) are folded into the CharacterMutator PP field as field = (1+field)*(1+m) - 1. ApplyConditionalDefenses then applies them when the condition holds, for example damage *= 1 + field for a Slowed attacker (PP 561, field 0x1350). The calculator should collect more_player_property node effects into pp_values, combining them multiplicatively, so that PP 561, 490, 291, 252, 251, 250, 436 and 437 take effect.
- evidence: client/scripts/engine/defense_conversions.gd:58 (kind != "player_property" skips the effect). client/scripts/engine/build_mods.gd:1181-1208 (stat_from_effect returns null for other kinds). research/data/game/passive_node_effects.json (nodes with kind "more_player_property", e.g. PP 561 value -0.05, PP 291 per_point -0.01, PP 252 per_point -0.01, PP 436 -0.01, PP 437 -0.4). research/data/game/skill

## #69 [defense] Endurance +30% from PP 525 (Immortal Vise) modelled as permanent added Endurance
- impact: medium for that unique. Endurance is overstated when no delayed damage is pending, and the cap and combination are wrong.
- calculator: `client/data/unique_effect_models.json player/525 {kind stat, stat Endurance, added}; defense_conversions.gd pp_values skips kind 'stat' so the endurance_extra path (line 211) is not used` — Flat +30% base endurance at all times, capped together with other endurance at 0.6. This also satisfies the 'endurance > 0' gate of the threshold step.
- game: While LeechTracker delayed damage remaining exceeds 10% of max health, f8 = PP 525 is combined as e = 1-(1-f8)(1-min(endurance,0.6)). It sits outside the 0.6 cap, so the result can exceed 0.6. Without pending delayed damage, e = min(endurance,0.6). In the modes that need it, the threshold block requires base endurance above 0.
- evidence: dump/decomp/LE.dll/ProtectionClass.c lines ~1046-1053: fVar38 = min(*(param_2+0xc0), 0.6); fVar38 = 1.0 - (1.0 - f8) * (1.0 - fVar38). Here f8 is the slot held in uStack_278, and ProtectionClass+0xC0 is the player's endurance. In mode (param_2+200)==2 the result is applied as damage *= (1 - fVar38). research/data/game/unique_effects.json ppIndex 525: 'E_eff = 1 - (1 - pp) * (1 - min(endurance, 0.6

## #73 [defense] Boss Damage 'increased' ignored (Heorot, Volcanic Shaman)
- impact: medium for those two bosses: damage is overestimated by about 11-16%. Possibly the same in the average-monster extraction, which says it uses MORE only.
- calculator: `defense_calc.gd _load_presets line 107 (keeps only Damage stats with a non-empty 'more') and the monster_damage.json extraction` — Only Damage MORE entries of the boss's ActorStats are applied. Heorot has increased -0.135 and no more, so it gets no modifier. Volcanic Shaman gets only its more -0.1425 and not its increased -0.10.
- game: The boss's own Damage stats feed the same (1 + Σincreased) * Π(1 + more) pipeline as any attacker. defense_calc.gd should keep every Damage stat with a non-zero increased OR a non-empty more. It should then add the increased to a per-damage-type inc sum (after the same tag matching as for 'more') and compute base * (1 + inc) * Π(1 + more) * the attack's damageModifier. Heorot gets x0.865. Volcanic Shaman gets x0.90 * x0.8575 = x0.77175.
- evidence: 1) Calculator: D:\LastEpochBuilder\client\scripts\engine\defense_calc.gd:107 `if int(stat.get("property", -1)) == LE.DAMAGE and not (stat.get("more", []) as Array).is_empty(): damage_stats.append(stat)`; lines 140-143 `for v in stat["more"]: m *= 1.0 + float(v)` with no use of stat["increased"].
2) Data: research/data/game/boss_attacks.json, actorStats. Heorot (actorData "Heorot Boss"): {"property

## #74 [defense] Average monster ignores rarity damage and the non-boss health-serialisation condition
- impact: medium. Most monolith monsters are magic or rare, so the 'average monster' damage is understated by up to 60-90%, and the rare/boss conditionals never fire for it.
- calculator: `defense_calc.gd _average_presets and enemy_attack (attacker_kind 'normal', level scaling)` — The average monolith monster is a normal-rarity monster that always gets the (damageModifier+1)*1.06 factor. Spawn weights are ignored.
- game: Per hit, a monster's damage is scaled by oda[L]/oda[L0] always. The (damageModifier[L]+1)*1.06 MORE applies only when its UnitHealth.healthSerialisation == 1. Magic monsters then get an extra Damage MORE +0.6 and rares +0.9 (MORE). The average-monster preset should be a weighted mix of normal, magic and rare monsters, or at least expose a rarity selector. Whether ordinary monsters use mode 1 still needs checking in the monster prefabs.
- evidence: research/data/game/monster_rarity.json: data.magic.increasedDamage = 0.6, data.rare.increasedDamage = 0.9, formulas.Damage = "ChangeStatModifier(SP0 Damage, increasedDamage, MORE)". dump/decomp/LE.dll/ActorScaler.c ActorScaler_scaleToLevel, lines 477-488: "if ((int)plVar7[0x1d] != 1) goto LAB_182783e0d; ... BaseStats_setHealthAndDamageResistanceForLevel(...)". The goto skips the call. Lines 496-51

## #75 [defense] Block and hit-taken gain events use wrong probabilities (glancing, low-health condition)
- impact: medium for those uniques. Recovery is overestimated, and for PP 33 it is granted even at full health.
- calculator: `client/data/unique_effect_models.json player/96 and player/33; defense_recovery.gd _add_resource (lines 122-126) with avoid = {dodge, block, land}` — PP 96 'Health gained when you receive a Glancing Blow' fires on every landed hit. PP 33 ('ward when a hit leaves you at low health', 5 s cooldown) fires on every landed hit, capped only by 0.2/s.
- game: PP 96 fires only on a glancing blow, with probability equal to the glancing chance. PP 33 fires only when the damage leaves you at low health (valueWouldBeLowHealth), at most once per 5 s.
- evidence: dump/decomp/LE.dll/CharacterMutator.c line 14007: `if (((param_4 != '\0') && (*(float *)(param_1 + 0x102c) != 0.0)) && (0.0 < afStack_204[0])) { ... BaseHealth_restoreHealth(); }`. Lines 14087-14095: `if ((0.0 < *(float *)(param_1 + 0xb88)) && (*(float *)(param_1 + 0xb8c) <= *(float *)(param_1 + 0xb90))) { ... cVar5 = BaseHealth_valueWouldBeLowHealth(*(longlong *)(param_1 + 0x2088),afStack_204,0);

## #77 [defense] HealthGain/WardGain with hit-event specialTags (on block, on kill, crit, melee hit) not counted as recovery
- impact: medium for block builds: health/ward on block from gear and trees is not part of recovery. The special-0 query may double-count or miscount.
- calculator: `skill_calc.gd _sustain_rows line 1419 (store.query(prop, tags, special=0, ...)) feeding defense_recovery.gd` — Only HealthGain/WardGain mods with special == 0 are summed as 'per hit'. Mods with specialTag 1-7 are filtered out by StatStore.query. No block, kill or crit event source is built from them.
- game: HealthGain, WardGain and ManaGain only produce resource on the event named by their specialTag: 1 hit, 2 crit, 3 kill, 4 freeze, 5 stun, 6 block, 7 melee hit. Block (6) is honoured only for untagged stats, in UpdateResourceGainTotals. Tagged or ability-specific stats go through GainResourcesFromTaggedOrAbilitySpecificStats, which handles 1, 2, 3, 4, 5 and 7 and skips everything else. A stat with special 0 contributes nothing in either path. The calculator should therefore treat special 1 (and 7 on melee hits) as per-hit gain. Gains on kill, cri
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\ResourceGainEvents.c lines 1828-1885: switch(bVar1) case 0x26/0x27/0x28 { if tags(+0x14)==0 && extra(+0x18)==0: switch(special byte at +0x11) { case 1..7 only; no case 0 } }. Special 1 and 7 go to the +0x68 / +0x70 / +0x6c accumulators, 2 to +0x2c, 3 to +0x44, 4 to +0x50, 5 to +0x5c, and 6 (block) to +0x38 / +0x40 / +0x3c.
Same file, lines 204-449 (GainResour

## #78 [defense] Ward bypass flags and health caps not applied
- impact: medium for those builds. EHP is overstated when current health is capped at 50%, and ward is wrongly counted against bypassed damage.
- calculator: `defense_calc.gd take_damage / full_pool; field_models.json CharacterMutator.dotsBypassWard, maxHealthCapForCurrentHealth, maxHealthCapForWardFromAcolyteTree (flags only); unique_effect_models player/6` — Ward always absorbs hits and DoT. The pool starts at 100% of max health. Ward is not capped by max health.
- game: When hitsBypassWard is set (PP 685) hits skip ward, and when dotsBypassWard is set (Acolyte Impact Ward at 3 or more points) DoT skips ward. Bypassed damage goes to the next layer in full and ward is untouched. Current health is capped at maxHealth * maxHealthCapForCurrentHealth (Corrupted Form 0.5) whenever health is restored. Ward gained is capped at maxHealth * maxHealthCapForWard when that value is above 0.
- evidence: dump/decomp/LE.dll/ProtectionClass.c lines 1075-1101: `if (((ward <= D && D != ward) || (*(char*)(param_2+0x1a0) != 0 && (uStack_294&1)==0)) || (*(char*)(param_2+0x1a1) != 0 && (uStack_294&1)!=0))`, then `if (flag == 0) { fStack_288 = fVar45 - ward; ward -> 0 or reduced }`. Flags set means no ward subtraction.
dump/decomp/LE.dll/ProtectionClass.c lines 3202-3217: `if (0.0 < *(float*)(param_1+0x19c

## #127 [passives-and-sets] Illusory Combatant: dodge per Intelligence counted twice (uncapped + capped), game has one capped value
- impact: Medium. With Int 50 the planner gives 200 dodge vs 100 in game; for Int >= 50 it gives 2*Int+100 vs 100. Inflates dodge for that mastery node.
- calculator: `client/data/field_models.json CharacterMutator.addedDodgeRatingPerInt (per attr:int, no cap) and CharacterMutator.addedDodgePerIntCap (per attr:int, factor 0.02, src_max 50); passive 'Illusory Combata` — Each field is its own stat model, nothing dedupes them: DodgeRating +2 x Int (uncapped) AND a second DodgeRating +100 x 0.02 x min(Int,50) = 2 x min(Int,50). Total = 2*Int + 2*min(Int,50).
- game: DodgeRating from Illusory Combatant = min(addedDodgeRatingPerInt x Int, addedDodgePerIntCap), i.e. min(2*Int, 100) when the cap field is above 0. The cap field must not add its own bonus. In the calculator, addedDodgePerIntCap should be modelled as a cap on addedDodgeRatingPerInt, not as a separate per-Int stat.
- evidence: 1) dump/decomp_extra/CharacterMutator__applyModifiersBeforeExternalStatsCalculation.c lines 4998-5010: `fVar22 = *(float *)(param_1 + 0x6dc); iVar8 = func_0x0001800120a0(0x16,*(longlong *)(param_1 + 0x98),2); afStack_518[0] = (float)iVar8 * fVar22; ... cVar5 = CharacterMutator_UpdateDynamicStat(afStack_518,param_1 + 0x6e0,param_1 + 0x6e4,0);`.
2) Field offsets from `tools/dump_index.py field`: add

## #40 [character-attrs] Altar prop 29 (healing effectiveness per heretical idol) is stored as 'increased'; the game adds it as an added stat
- impact: LOW now: no calculator code reads SP 44 (no healing model), so it only matters if healing effectiveness is added later.
- calculator: `client/scripts/engine/altar_mods.gd:31 (29: sp 44, kind 'increased')` — StatMod(SP 44) with the increased part set.
- game: Altar property 29 adds count * value to SP 44 as an added stat, so kind should be 'added'. Consumers would read .added.
- evidence: dump/decomp/LE.dll/IdolsItemContainer.c (UpdateStatsFromAltarMods): `fVar13 = (float)Stats_GetIdolAltarStatValue(plVar4,0x1d,0,0); ... fVar13 = (float)*(int *)(... + 0x18) * fVar13; ... uVar10 = Stats_AddedStat(0x2c,0,fVar13,0,0,0);`. Property 0x1d is 29 and the stat is 0x2c, which is 44. The count multiplier is the field at +0x18. client/scripts/engine/altar_mods.gd:31 has `29: {... "sp": 44, "ki

## #41 [character-attrs] Character sheet defence percentages use the character level; the game uses the zone area level (character level only in hubs)
- impact: LOW-MEDIUM: percentages on the sheet at area level 100 differ from character-level values for characters below level 100; the formulas themselves are correct.
- calculator: `client/scripts/engine/character_calc.gd:14, 134, 155, 187 (level = build.level; L = level + 5)` — Armor %, dodge % and block mitigation % are computed with L = character level + 5. The Defense tab has a separate area_level setting (defense_calc.gd:46), but the Character sheet does not use it.
- game: CharacterSheet.UpdateSheet takes the level from the current scene. If SceneDetails.ShowPlayerLevelInUI is false (normal zones), it uses ZoneInfoManager.areaLevel. If it is true (hubs and towns), it uses the character level. It passes that level as the override into CalculateDodgeChance, mitigationFromArmour and blockMitigation, which compute with L = level + 5. The sheet's defence percentages should use an area level setting, defaulting to the character level only when modelling a hub.
- evidence: dump/decomp/LE.dll/PrecalculatedStatsHolder.c:78-86: `if (param_4 == '\0') { ... param_5 = **(int **)(_ZoneInfoManager__TypeInfo + 0xb8); } fVar1 = (float)(param_5 + 5);`

dump/decomp/LE.dll/CharacterSheet.c, UpdateSheet @0x182874E20 (around lines 1190-1220 of the file, found via `dump_index.py show CharacterSheet_UpdateSheet`): `lVar10 = SceneList_GetCurrentSceneDetails(0); if (*(char *)(lVar10 +

## #42 [character-attrs] Sheet rows for Thorns, Crit avoidance, Block chance, Armor and Endurance threshold use generic I*A*M or ignore conversions that the game applies
- impact: LOW: wrong only when such mods/conversions exist; the combat model in defense_calc.gd is not affected.
- calculator: `client/scripts/engine/character_calc.gd:164-173 (block), 122-131 (armor), 219-227 and 366-388 (ET), 281-300 (thorns, crit avoidance)` — Thorns and Crit avoidance use query.value() = added*(1+inc)*more. Block chance is shown without maximumBlockChance and regardless of block->glancing/parry conversion. Armor and ET omit the dodge-rating conversions.
- game: Thorns = (sum of increased + 1) * sum of added, with no "more" applied. Crit avoidance = product of "more" multipliers * sum of added, with no increased applied. Sheet block chance = 0 when the block conversion is non-zero, otherwise min(added block chance, maximumBlockChance) when that cap is non-zero. Armor sheet value = armour + dodge rating when the dodge conversion == 1. Endurance threshold sheet value = ET + dodge rating when the conversion == 3. Dodge rating on the sheet = 0 when any conversion is active.
- evidence: dump/decomp/LE.dll/BaseStats.c lines 979-981: case 'U': fStack_25c += +0x1c; fStack_208 += +0x20. Line 1261: *(0x8c) = (fStack_208 + 1.0) * fStack_25c. Lines 989-991: case 'Y': fStack_1b4 += +0x1c; fStack_26c *= Stats_Stat_getMoreMultiplier. Line 1244: *(0xdc) = fStack_26c * fStack_1b4. Initial values at lines 718-729: fStack_26c = 1.0, the others 0.0. client/scripts/engine/le.gd:120-121: CRIT_AVO

## #70 [defense] Delayed (slow) damage is queued from D before the endurance-threshold reduction
- impact: low-medium. Delayed damage is overestimated whenever the hit lands in the below-threshold health range, for example with a high threshold or at low health.
- calculator: `defense_calc.gd take_damage lines 575-577` — queued = d/(1-f7)*f7, with d taken after mana-before-ward and mode-2 endurance, but before the threshold step.
- game: The queued delayed damage should be (D_after_threshold / (1 - f7)) * f7. D_after_threshold is D after mode-2 endurance and after subtracting the threshold absorption (R - R'). The calculator's threshold block would need to be applied to a damage value before the queue step, or the absorbed amount subtracted from d before the queue.
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\ProtectionClass.c line 1159: `fVar45 = fVar45 - (fVar33 - fStack_288);` inside the threshold branch (lines 1144-1161: `if (0.0 < *(float *)(param_2 + 0xc0)) && (mode == 0 || mode == 1)` ... `fStack_288 = (health_or_cap - fVar46) + (1.0 - fVar38) * (...)`). Line 1560: `fVar33 = (fVar45 / (1.0 - (float)uVar36)) * (float)uVar36;` followed by creation of the Slow

## #71 [defense] Crit bonus reduction floors the whole hit multiplier at 1, not only the crit factor
- impact: low, only for crits with SP114 together with f0 < 1 or delayed damage. In those cases the calculator underestimates crit damage.
- calculator: `defense_calc.gd crit_against (line 537) and type_multiplier / take_damage, which apply f0 and (1-f7) separately` — factor = max(1, 1+(1-r)(cm-1)) is multiplied with the f0 'less damage taken' multipliers and the (1-f7) delayed share.
- game: When r != 0 on a crit, M = max(1, (1 + (1-r)(cm-1)) * M), where M already holds f0 and (1-f7). The floor applies to the whole running multiplier, not just the crit factor. When r == 0, M = cm * M with no floor.
- evidence: D:\LastEpochBuilder\dump\decomp\LE.dll\ProtectionClass.c lines 576-618: "fVar45 = *pfVar19;" and "if ((0.0 < fStack_20c) && (fVar45 = (1.0 - fStack_20c) * fVar45, fVar45 < 0.0)) fVar45 = 0.0;". Lines 799-808: "if (*(float *)(param_2 + 0xe4) == 0.0) { fVar45 = fVar46 * fVar43 * fVar45; } else { fVar45 = ((1.0 - *(float *)(param_2 + 0xe4)) * (fVar46 * fVar43 - 1.0) + 1.0) * fVar45; if (fVar45 < 1.0)

## #72 [defense] Converted block (to parry) includes the conditional block add f1
- impact: low. Only affects shieldless block-to-parry builds with conditional block.
- calculator: `defense_calc.gd player_layers lines 465-466 (parry = min(0.75, parry + block), where block includes block_f1)` — Parry = parry + (blockChance + f1*mult), capped by max block.
- game: With blockConversion == 2, parry = min(0.75, baseParry (field 0xD4) + min(maxBlock if nonzero, blockChance (0x5C)) + 0). The conditional block add f1 is not included. The calculator should use block_q.value() capped at max_block, without block_f1, when adding to parry.
- evidence: dump/decomp/LE.dll/PrecalculatedStatsHolder.c, GetParryChance (line ~119) and parryChanceForCharacterSheet (line ~285): `if (*(int*)(p+0x6c)==2) { fVar1 = *(float*)(p+0x5c) + 0.0; ... min with *(p+0x68) ...}`, then `+ param_2` (base parry), capped at 0.75. The block-chance field is only written by SetBlockChance (line 23).

dump/isil/IsilDump/LE/ProtectionClass.txt lines 4828-4846 (the combat roll

## #76 [defense] Ward-on-hit chance (SP97) not modelled
- impact: low-medium. Ward per enemy hit of 30*chance is missing from recovery.
- calculator: `defense_recovery.gd / defense_calc.gd (no reference to SP 97 anywhere in client/scripts)` — Ignored.
- game: On each enemy hit that reaches the ward step, the game rolls the SP97 chance (chanceToGain30WardWhenHit). If it succeeds and no no-ward-gain source is active, the player gains 30 ward. This happens before the damage is applied when ward + health is below D, and after the damage otherwise. The expected recovery is about 30 x chance ward per enemy hit.
- evidence: dump/decomp/LE.dll/ProtectionClass.c:1030-1046 (`cVar10 = RngElement_Roll(); if (cVar10 != 0 && *(int*)(param_2+0x198) < 1) { ... if (*(float*)(param_2+0x170) + *(float*)(lVar25+0x94) < fVar45) ProtectionClass_GainWard(param_2); else bVar7 = true; }`); ProtectionClass.c:1462-1465 (`LAB_18112290d: if (bVar7) ProtectionClass_GainWard(param_2);`). dump_index field/readers: PrecalculatedStatsHolder.ch

## #79 [defense] CurrentHealthDrain (SP60) not applied
- impact: low-medium. Net recovery and survival time are overstated for builds that carry the drain.
- calculator: `defense_recovery.gd and defense_calc.gd (the stat is added to the store but never read)` — No health loss over time.
- game: Every frame the game subtracts currentHealthDrain * currentHealth * dt directly from health, bypassing ward. This is a continuous loss proportional to current health, so net recovery and survival time should be reduced by it.
- evidence: dump/decomp/LE.dll/ProtectionClass.c lines 4303-4318: "if (0.0 < *(float *)(param_1 + 0xbc)) {... fVar13 = *(float *)(*(longlong *)(lVar5 + 0x38) + 0x94); fVar11 = *(float *)(param_1 + 0xbc); fVar9 = Time_1_get_deltaTime(0); BaseHealth_HealthDamage(uVar3, fVar11 * fVar13 * fVar9, 0);". dump/cs/DiffableCs/LE/PrecalculatedStatsHolder.cs:74 "public float currentHealthDrain; //Field offset: 0xBC". dum

## #80 [defense] Affix PP 275 (less DoT taken during Haste) not applied; PP 262 and 257/258 use proxies
- impact: low. The proxies are labelled D? by the author.
- calculator: `defense_conversions.gd _conditional (no 275 branch; PP 262 uses max mana; PP 257/258 use 'melee attack' as the 4 m test)` — Affix-sourced PP 275 is collected into pps but never used. PP 262 compares max mana with 400. 'Within 4 m' is true for every melee attack.
- game: While the player has Haste, DoT taken is multiplied by 1 + max(-0.75, (1 + increased SP120 effect-of-Haste-on-you) * PP275). The 4 m bonuses (PP 257/258) apply only when the attacker is within 4.0 units of the player. PP 262 applies when current mana is at least 400.
- evidence: dump/decomp/LE.dll/CharacterMutator.c, ApplyConditionalDefenses (starts at line 3770). Lines 4011-4030: `if (*(float *)(param_2 + 0x13fc) != 0.0) {... if ((*(uint *)(param_3 + 0x34) & 0x1000) != 0) {... AilmentReceiver_hasAilment_1(lVar9,0x21,0) ... fVar15 = Stats_GetTotalIncreased(lVar9,0x78,0,0x21,...); fVar15 = (fVar15 + 1.0) * *(float *)(param_2 + 0x13fc); if (fVar15 <= -0.75) fVar15 = -0.75; 

## #81 [defense] Boss attack timing ignores the boss's Attack/Cast speed stats
- impact: low-medium. The recovery interval and the DPS of repeating attacks are affected.
- calculator: `defense_calc.gd _ability_every and _load_presets (every/tick)` — Seconds between hits come from useDuration or charge time, unscaled.
- game: For each boss ability whose speedScaler is AttackSpeed or CastSpeed, the effective use time is useDuration / (S × ability.speedMultiplier × baseUseSpeedMultiplier), and the effective use delay is useDelay / the same factor. S is the boss's total stat for that property: (1 + sum of added) × (1 + sum of increased) × the product of (1 + more), with tag and extra-tag matching. This includes the prefab modifiers, for example Lagon's AttackSpeed more -0.30. If S × speedMultiplier × baseUseSpeedMultiplier is 0 or below it is clamped to 0.1, and if the
- evidence: 1) D:\LastEpochBuilder\client\scripts\engine\defense_calc.gd lines 166-173 (`_ability_every`): uses `useDuration` and charge time only, and never the boss's AttackSpeed or CastSpeed stats.
2) D:\LastEpochBuilder\dump\decomp\LE.dll\UsingAbility.c, `InitialiseAbilityUse` (line 580 on): `fVar14 = fVar14 * fVar15 * fVar12; if (fVar14 <= 0.0) fVar14 = 0.1; *(float*)(param_1+0x11c) = fVar14; ... fVar12 

## #89 [minions-shadows] Minion base armour is taken from the prefab's serialized 'armour' (70.05 / 56.9), which 07j says is garbage
- impact: LOW. It adds about +70 and +57 base armour to Bear and Serpent.
- calculator: `client/scripts/engine/minion_calc.gd:309-312 (protection.get('armour'))` — Primal Bear base armour 70.05 and Primal Serpent 56.9 are used as the base in (base + added)(1+inc)more.
- game: Minion armour = (1 + increased) × (sum of Armour ADDED from the minion's stats list, starting at 0) × Π more − armour shred. The prefab-serialized `armour` is not part of that sum.
- evidence: 1) dump/cs/DiffableCs/LE/PrecalculatedStatsHolder.cs:63 declares `public float armour; //Field offset: 0xA0`, and ProtectionClass.cs:5 declares `class ProtectionClass : PrecalculatedStatsHolder`. 2) dump/decomp/LE.dll/BaseStats.c, `BaseStats_ApplyExternalStats`:
- Line 654 sets `fStack_1ec = 0.0;`.
- Line 832 accumulates `fStack_1ec = fStack_1ec + *(float *)(lVar1 + 0x1c);` (the Added value per st

## #91 [minions-shadows] Shadow sustain model (shadows created per second, health/ward per creation) rests on assumptions
- impact: LOW-MEDIUM. Only affects the Defense-tab sustain rows and the assumption that max shadows are always up.
- calculator: `client/scripts/engine/shadow_calc.gd:158-179 (created = n * max(uses, 1/LIFETIME)) and the Conditions-tab shadow count` — Assumes that keeping n shadows needs n * max(uses/s, 1/5) creations per second and applies health/ward 'on creation' to that rate. The shadow count is a user input, not derived.
- game: The max shadow count is a base of 3 plus modifiers, and a shadow lasts 5 s. Health (stats manager +0x1b58) and ward (+0x1c28) are granted once per CreateShadowMutator.Mutate call, which is once per created shadow. The creation rate is not fixed by a single formula in the code. Whether that rate equals n * max(uses/s, 1/5) depends on the creation sources, and the data I checked does not establish it. The calculator's assumption of keeping n shadows up is a user-input choice.
- evidence: client/scripts/engine/shadow_calc.gd:20 sets LIFETIME = 5.0, and lines 165-168 compute created = n * maxf(uses, 1.0 / LIFETIME). dump/cs/DiffableCs/LE/CreateShadowMutator.cs:13 has 'private const int baseMaximumShadows = 3'. dump/cs/DiffableCs/LE/RogueShadow.cs:21 has 'private const float baseDuration = 5'. dump/decomp/LE.dll/CreateShadowMutator.c, function Mutate (starts at line 1015), lines 1135

## #123 [uniques] Immortal Vise (pp525) is modelled as additive Endurance although an exact path exists in DefenseConversions that the model bypasses
- impact: Low to medium (defence only): the pp is lost against the 60% cap, and the planner applies it even at 0 endurance.
- calculator: `unique_effect_models.json player 525 (kind stat, Endurance added, input delayed_dmg default true). DefenseConversions.pp_values skips kind stat / overcap_taken (defense_conversions.gd:24-29), so its e` — The pp is added to the Endurance sum, which is then capped at ENDURANCE_CAP 0.6 (defense_calc.gd:402). With endurance 0.5 and pp 0.3 the result is min(0.8, 0.6) = 0.6.
- game: E_eff = 1 - (1 - pp525) * (1 - min(endurance, 0.6)) while slow damage remaining exceeds 10% of max health. In EnduranceMode 0 and 1 the endurance block applies only if player endurance > 0, so with 0 endurance pp525 has no effect. In mode 2 the whole hit is multiplied by (1 - E_eff).
- evidence: dump/decomp/LE.dll/ProtectionClass.c, ApplyDamage, lines 1048-1055: "fVar38 = 0.6; if (*(float *)(param_2 + 0xc0) <= 0.6) fVar38 = *(float *)(param_2 + 0xc0); fVar38 = 1.0 - (1.0 - (<f8 slot>)) * (1.0 - fVar38); if (*(int *)(param_2 + 200) == 2) fVar45 = fVar45 * (1.0 - fVar38);".
ProtectionClass.c line 1144: "if ((0.0 < *(float *)(param_2 + 0xc0)) && (mode(+200) == 0 || mode == 1))" opens the thr


# Part 3. Other (UI, mana, movement, idols, latent) (15)

## #18 [speed-mana-cooldown] Mana cost row omits ManaEfficiency, global ManaCost stats, minimumManaCost, attribute/level scaling; addedManaCostDivider modelled with the wrong formula
- impact: High for any build with mana cost reduction/efficiency gear, mana-efficiency attribute scaling or the divider nodes: the displayed mana cost, 'Ward from mana spent per second' (mana*uses*SP99) and Defense-tab mana rates are wrong; error grows with efficiency (divider nodes off by up to ~15-20% of cost at f=0.4-0.5).
- calculator: `client/scripts/engine/skill_calc.gd:1093-1100 (mana = (manaCost + mana_added)*(1+mana_inc)); client/scripts/engine/build_mods.gd:849-853 and 965-970 (only increasedManaCost/addedManaCost); client/data` — Cost = (base + added)*(1 + increased) only. Stats SP66 ManaCost (affixes, passives, items), SP69 ManaEfficiency (including attributeScaling of 30+ skills such as Teleport, Shift, Warcry, DarkQuiver, Spriggan/Wolf Ability), mutator moreManaCost, minimumManaCost are not read (LE.MANA_COST / LE.MANA_EFFICIENCY are never queried in the engine). The skill's own 'Mana efficiency' tree divider is approximated as increased -f (cost*(1-f)) and is also sto
- game: Mana cost = max(minimumManaCost, GetStatValue(SP66 ManaCost; added = base + Σadded + attribute and level scaling + mutator added, increased = Σ + mutator increased, more = mutator more, ability-id tag) / GetStatValue(SP69 ManaEfficiency; added = 1 + addedManaCostDivider + attribute and level scaling + mutator divider)). The skill's own divider f is added into the efficiency divisor, so cost scales by 1/(1+f), not (1-f). Gear, passive and affix ManaCost and ManaEfficiency stats also apply.
- evidence: dump/isil/IsilDump/LE/BaseMana.txt, getManaCost(Ability,...), around lines 2830-3070:
- 462-463: "Move rdx, 69 / Call Stats.GetStatValue" (efficiency), result "Move xmm7, xmm0".
- 486-488: "Move rdx, 66 / Call Stats.GetStatValue / Divide xmm0, xmm0, xmm7".
- 489-491: "Compare xmm9, xmm0 / JumpIfGreater / Move xmm9, xmm0" (minimum clamp).
- 501-502: the channel-cost branch also does "Divide xmm9, x

## #19 [speed-mana-cooldown] Channel cost per second is never modelled (and mutator-made channelled variants are not detected)
- impact: High for channel builds: mana per second is understated by 18-48 mana/s per skill at base; whether the build can sustain the channel is not shown, and mana-derived rows (ward from mana spent, mana-based unique effects) use manaCost*uses/s which is not what the game spends.
- calculator: `client/scripts/engine/skill_calc.gd:1093-1113 (mana row shows ability.manaCost only); no use of Ability.channelCost / SP25 ChannelCost / ab.channelled anywhere in skill_calc.gd or build_mods.gd except` — Channelled skills (Disintegrate 18/s, Drain Life 23/s, Ghostflame 48/s, Warpath 18/s, Healing Hands/Fireball/Nova/Flurry/Hail of Arrows/Avalanche/Shadow Cascade when their channel node is taken) show only the one-off manaCost (e.g. 5); mana per second and the mana-based sustain rows ignore channel drain. ab.channelled (asset flag) is the only channel notion; nodes that set a mutator isChanneled flag are flags only.
- game: Channelled abilities pay manaCost once on cast. After that, mana is also drained continuously at a rate of currentChannelCost per second (mana -= rate*dt each frame), with the rate recomputed every 0.25 s. The calculator should model that per-second drain in the mana-per-second and sustain rows.
- evidence: dump/decomp/LE.dll/UsingAbilityPlayer.c lines 7012-7026: `if (... UsingAbility_isUsingChannelledAbility(param_1,0) ... ) { if (fVar26 + 0.25 < Time) { BaseMana_setChannelCost(param_1[0x2b],param_1[0x20],0,0,0,0); ...} BaseMana_consumeManaFromChannel(param_1[0x2b],0); }`.
dump/decomp/LE.dll/UsingAbility.c lines 2396-2406: `BaseMana_getManaCost_2(...)`, then `BaseMana_spendManaOnAbility(...)`, then 

## #1 [stat-model] Movement speed sheet row uses only the 'more' component
- impact: Medium for the displayed stat. It shows +5% regardless of gear, Haste or 40% increased movespeed. Anything built on top of it (a Vaion's-style 'per movement speed' effect) would also be wrong. Damage is not affected unless such a source is modelled.
- calculator: `client/scripts/engine/character_calc.gd:259-268 (_compute_other, movespeed_query.more - 1.0); client/docs/ENGINE.md:325` — Movement speed is shown as (Π(1+more) - 1). Increased movement speed is ignored. The UI states 'Only the more component is used'.
- game: The game reads Movespeed through Stats_GetTotalIncreased (SP 9), which is the increased total, floored at 0. The calculator should include increased movement speed in the row. The full formula, including how more is combined, is not established in the dump.
- evidence: D:\LastEpochBuilder\client\scripts\engine\character_calc.gd:259-268: `var movespeed_more: float = movespeed_query.more - 1.0` with the breakdown note "Only the more component is used: more - 1".
D:\LastEpochBuilder\dump\decomp\LE.dll\EvadeMutator.c:238, in GetEffectiveMovementSpeedForScaling: `fVar5 = (float)Stats_GetTotalIncreased(lVar2,9,0,0,0,0);`, followed at lines 244-246 by `if (fVar5 <= 0.0

## #34 [character-attrs] Character-sheet 'Movement speed' shows only the more component; the game uses (1+sum increased) * product of more - 1
- impact: MEDIUM: a build with +50% movement speed on boots shows 5%. It only affects the displayed value unless other code reads this row; related unique formulas (e.g. Vaion's Chariot via TotalIncreased(MoveSpeed)) are handled separately.
- calculator: `client/scripts/engine/character_calc.gd:259-268 (_compute_other: movespeed_more = movespeed_query.more - 1.0)` — Row value = Π(1+more) - 1 only; the comment says 'Only the more component is used: more - 1' with no code citation. 'Increased Movement Speed' affixes and increased from any other source are not shown or used.
- game: Movement speed modifier = (1 + sum of increased) * product of (1 + more) - 1. This matches StatQuery.value() with added excluded.
- evidence: dump/decomp/LE.dll/Stats.c, Stats_GetTotalModifier: the accumulator is initialised with `fVar7 = 0.0; fVar6 = 1.0;`. Each matching stat does `fVar7 = fVar7 + *(float *)(lVar3 + 0x20);`, and the more factors are multiplied into fVar6 in a nested loop. It returns `(fVar7 + 1.0) * fVar6 - 1.0`. dump/decomp/LE.dll/UsingAbility.c, UsingAbility_getAnimationSpeedScale: `fVar12 = (float)Stats_GetTotalModi

## #4 [stat-model] Quotient handling differs and is inconsistent between code paths
- impact: Latent and low. grep finds no QUOTIENT modType in research/data/game/*.json, and no 'quotient' kind in client/data, so nothing currently reaches this path.
- calculator: `client/scripts/engine/stat_mod.gd:34-37 (floor of the divisor at 0.01); client/scripts/engine/item_mods.gd:125-126 and 225-226 (1/(1+rolled)-1 with no guard)` — StatMod.make('quotient', -1) gives more = 1/0.01 - 1 = +99. item_mods divides by (1+rolled) directly, which is a division by zero or an inf at x = -1.
- game: QuotientStat gives more = 0 when x == -1.0 exactly. Otherwise it gives more = 1/(x+1) - 1. For example, x = -0.5 gives +1, and x = -1.5 gives -3.
- evidence: dump/decomp/LE.dll/Stats.c lines 3830-3835, in Stats_QuotientStat: "if (param_3 == -1.0) { fVar2 = 0.0; } else { fVar2 = 1.0 / (param_3 + 1.0) - 1.0; }". Stats.c line 3893 has a second "param_4 == -1.0" check, inside StatOfType. I did not read past line 3893, so I did not confirm it is the QUOTIENT case. Calculator: client/scripts/engine/stat_mod.gd:37 "mod.more.append(1.0 / maxf(1.0 + value, 0.01

## #5 [stat-model] Scaled 'more' is clamped at -1 and some floors/caps differ from game code
- impact: Low. It only matters for strongly negative more values × large N, or net-negative endurance or parry. Those are edge cases that real builds rarely reach.
- calculator: `stat_mod.gd:59 (scaled: maxf(more*n, -1.0)); defense_calc.gd:402-403 (maxf(endurance, 0.0)), defense_calc.gd:425 parry clampf(...,0,PARRY_CAP); character_calc.gd lines 209-211 endurance min only` — Scaling a more value by n (stacks, attribute points) floors it at -1, which gives a multiplier of 0. Endurance and parry are also floored at 0.
- game: Scaling a stat multiplies added, increased and every more value by N with no clamp, so the more factor 1+m*N can be negative. Endurance is min(endurance, 0.6) and parry is min(parry, 0.75), with no lower floor at 0.
- evidence: dump/decomp/LE.dll/Stats+Stat.c:1487-1522 Stats_Stat_multiplyValues: `afStackX_8[0] = afStackX_10[0] * param_2;` and `(float)*(undefined8*)(param_1+0x1c) * param_2`, with no min/max. Stats+Stat.c:1409 getMoreMultiplier: `fVar5 = fVar5 * (afStackX_8[0] + 1.0);`. Stats+Stat.c:21 ApplyMoreModifier: `*param_2 = fVar2 * (fVar1 + 1.0) - 1.0;`. dump/decomp/LE.dll/PrecalculatedStatsHolder.c:303-313 get_Ca

## #6 [stat-model] Untagged queries drop mods with a specialTag, and the sheet attribute row uses untagged only
- impact: Low, a latent mismatch. The sheet and the effect path could disagree for a tagged attribute mod, and a special-tagged defence mod would be dropped. No current data triggers it.
- calculator: `stat_store.gd:189-190 query_untagged() calls query(property, 0, 0, 0, false). It is used for Health, Mana, Armour, Dodge, Block, Resistances (Enemy.resistance) and so on. character_calc.gd:_compute_at` — Mods with tags != 0, extra != 0 or special != 0 are excluded from the base-defence aggregation. The attribute sheet counts untagged mods only, but the attribute effects (build_mods) count mods of any tag.
- game: ApplyExternalStats includes a stat when tags == 0 and extraTag == 0, whatever its specialTag. The calculator should therefore not exclude special != 0 mods in the base-defence and health aggregation. ApplyCoreAttributeModifiers sums added of SP 19-23 and 46 with no tag, extraTag or special filter, so the attribute sheet should sum all mods like build_mods does.
- evidence: dump/cs/DiffableCs/LE/Stats.cs, Stats.Stat: 'property 0x10; byte specialTag 0x11; AT tags 0x14; int extraTag 0x18; addedValue 0x1C'.
dump/decomp/LE.dll/BaseStats.c line 359, ApplyExternalStats loop: 'if ((*(int *)(lVar1 + 0x14) == 0) && (*(int *)(lVar1 + 0x18) == 0)) { bVar6 = *(byte *)(lVar1 + 0x10);'. Line 762 repeats the same test. Offset 0x11 is not tested.
dump/decomp/LE.dll/CharacterStats.c 

## #31 [speed-mana-cooldown] Lunge manaCostPerDistance not modelled
- impact: Low (distance dependent, needs an input).
- calculator: `client/scripts/engine/skill_calc.gd:1093 (ab.manaCost only)` — Lunge costs its flat 8 mana.
- game: Lunge's mana cost is 8 plus 1.0 per unit of lunge distance, with the distance reduced by the stop range and floored at 0. It is passed through BaseMana.getManaCost as the added cost. The calculator charges only the flat 8.
- evidence: research/data/game/abilities.json ~11379-11382: Lunge "manaCost": 8.0, "manaCostPerDistance": 1.0. dump/decomp/LE.dll/UsingAbility.c lines 2356-2400: "if (*(float *)((longlong)param_2 + 0xc4) == 0.0) {... fVar35 = 0.0;} else {... fVar35 = distance(...); [stop-range subtraction: fVar35 = fVar35 - *(float *)(param_1[0x20] + 0x174); clamp 0] ... fVar35 = fVar35 * fVar37;}" followed by "BaseMana_getMa

## #36 [character-attrs] Refracted-slot idol effect is applied before value rounding; the game multiplies the already-rounded value
- impact: LOW-MEDIUM: only idols in refracted slots; differences up to half a grid step per affix (Integer-rounded health/armor/attribute idol affixes, Hundredth-rounded percents).
- calculator: `client/scripts/engine/item_mods.gd:174-180 (m = (1+m)*effect_scale - 1 fed into AffixMath.roll_value); altar_mods.gd:155-180 (_scale_deltas)` — The refracted multiplier (altar props 1-4) is folded into the effect modifier, so lo/hi are scaled and then rounded to the property grid (Integer/Hundredth) before the roll is taken. The result stays on the grid.
- game: The base-item effect modifier is applied before rounding (min*(1+m'), max*(1+m')), but the refracted extra is applied after: value = GetValueAfterRounding_2(...) and then value = value * (extra + 1.0). The result is not re-rounded.
- evidence: 1. dump/decomp/LE.dll/AffixList.c, AffixList_ChangeAffixModifier, around lines 1806-1812. fVar8 starts as AffixList_Affix_getModifier(...), and the rounding call is `fVar8 = (float)EpochExtensions_GetValueAfterRounding_2(..., fVar9 * (fVar8 + 1.0), (fVar8 + 1.0) * *(float *)((longlong)param_5 + 0x14), ...)`. The result of that call is not rounded again.
2. The next statement is `fVar8 = fVar8 * (p

## #37 [character-attrs] Blessings with two implicits use one roll for both; the game keeps an independent roll byte per implicit
- impact: LOW-MEDIUM: only the second implicit of those 10 blessings (e.g. Dodge rating, Block effectiveness, Ward decay threshold, flat health regen) is wrong when the two roll bytes differ.
- calculator: `client/scripts/engine/build_mods.gd:243-270 (_add_blessings: one 'roll' for all implicits); importers letools_import.gd:411 and maxroll_import.gd:369 keep only the first implicit roll` — roll = blessing_data['roll'] is passed to AffixMath.roll_value for every implicit of the blessing; a missing roll defaults to 0.
- game: Each implicit of a blessing has its own roll byte (implicitRolls[j]). The value of implicit j comes from EquipmentImplicit.GetValue(getImplictRoll(item, j)). The calculator should hold one roll per implicit instead of one roll per blessing.
- evidence: dump/decomp/LE.dll/ItemList.c lines ~3532-3533, inside the per-implicit while loop of GetItemImplicits: `uVar5 = ItemData_getImplictRoll(param_2,uVar9,0); uVar11 = ItemList_EquipmentImplicit_GetValue(plVar7,uVar5,0);`. dump/decomp/LE.dll/ItemData.c lines 31298-31330, ItemData_randomiseImplicitRolls: the loop runs while index < array length, calls RngElement_RandomByte, and stores `*(undefined1 *)(

## #38 [character-attrs] 'No larger idol above a smaller one' test (altar prop 21) is stricter than the game's test
- impact: LOW-MEDIUM: for altars with prop 21 the calculator can grant the cooldown-recovery bonus when the game would not (e.g. a 2x2 idol at the top of one column and a 1x1 idol lower in another column).
- calculator: `client/scripts/engine/altar_mods.gd:137-152 (larger_above_smaller) and 234-240` — Reports a violation only if an idol lies strictly above another (upper bottom edge <= lower top edge), overlaps it in columns, and has a larger area. Otherwise the ICRS bonus is added.
- game: Prop 21 (ICRS) is granted only if no pair of placed idols (A, B) exists with (A.pos.y + A.size.y) > (B.pos.y + B.size.y) and area(A) > area(B). Columns and overlap are irrelevant, the y axis goes up, and the comparison is on top edges.
- evidence: dump/decomp/LE.dll/IdolsItemContainer.c lines 3375-3460, in UpdateStatsFromAltarMods:
- Stat 0x15 = prop 21: `fStackX_20 = (float)Stats_GetIdolAltarStatValue(plVar4,0x15,0,0);`
- Outer loop: `iVar9 = iStack_124 * iStack_128; iVar2 = iStack_12c + iStack_124;`
- Inner loop, line 3419: `if (((float)iVar2 < (float)(iStack_12c + iStack_124)) && ((float)iVar9 < (float)(iStack_124 * iStack_128))) { ... b

## #43 [character-attrs] Idol classification by name, idol limits not enforced, slot unlock assumed complete, missing-roll defaults
- impact: LOW: no wrong number with the current data, but an extra omen idol (or an altar-less grid with 2 omen idols) is counted although the game does not allow it, and any new idol subtype whose name does not follow the pattern would be misclassified.
- calculator: `client/scripts/engine/altar_mods.gd:56-69 (heretical/omen/weaver by sub name), 35-42 and 206-214 (limits as notes only); idol_grid.gd:47-53 (is_open: != 99); item_mods.gd:94 (missing implicit roll = 2` — Heretical = name contains 'Heretical', weaver = name contains 'Weaver', omen = name contains 'Omen' or affixEffectiveness OmenIdol. Altar limits for omen/heretical/adorned/corrupted idols are only shown as notes (no cap), and there is no default omen limit. All 8 idol slot rewards are assumed unlocked. Missing rolls take fixed defaults.
- game: Heretical: IsHereticalIdol looks up ItemList's static dictionary by base type and tests whether the subtype is among its values. Weaver: base 25 with sub 2, or bases 26, 27, 28 with sub 1. Omen idols: CanPlaceNewOmenIdol allows altar value + 1, so the limit is 1 without an altar. Idol limits are enforced when placing, not just reported.
- evidence: dump/decomp/LE.dll/ItemData.c, ItemData_IsHereticalIdol (line 13249): reads base byte at +0x2c and subtype short at +0x2e, then calls Dictionary TryGetValue on the ItemList static at +0x68 and Enumerable_Contains(get_Values, subtype). ItemData_isWeaverIdol (line 30579): `if (cVar3 != '\x19') { if (((cVar3 != '\x1a') && (cVar3 != '\x1b')) && (cVar3 != '\x1c')) return false; return sVar2 == 1; } ret

## #61 [enemy-side] Corruption monster-power mod effect is f(c) - 1 in the game, calculator uses f(c)
- impact: LOW: constant offset of 1 percentage point (0.01 / 0.005) in monster health/damage more. It does not touch the player's DPS; it only feeds the defence summary and the 'Corruption' info row.
- calculator: `client/scripts/engine/enemy.gd:169-174 (corruption_more: 0.01*f, 0.005*f)` — Health and Hit-damage MORE = 0.01 * f(c), DoT MORE = 0.005 * f(c).
- game: Health and Hit-damage MORE = 0.01*(f(c)-1). DoT MORE = 0.005*(f(c)-1). Here f(c) is EchoWeb.GetMonsterPowerMultiplierFromCorruption(corruption), because the mod's effect is f(c)-1.
- evidence: dump/decomp/LE.dll/MonolithRun.c, MonolithRun_updateCorruptionMod (around line 3730): 'fVar7 = (float)EchoWeb_GetMonsterPowerMultiplierFromCorruption(); uVar6 = ActiveMonolithMonsterMod_NewPersistentMod(uVar6,fVar7 - 1.0,0);'. dump/decomp/LE.dll/ActiveMonolithMonsterMod.c, NewPersistentMod: the second argument is stored at +0x1c, which I take to be the mod's effect. research/data/game/monster_mods

## #66 [enemy-side] ConfigRelevance decides buff/shadow controls from tooltip text regexes
- impact: LOW (UI only), but a hidden control makes a relevant input impossible to set.
- calculator: `client/scripts/engine/config_relevance.gd:62-106 (_scan_buff_sources: SHADOW_TEXT, SHROUD_TEXT and ailment displayName regexes over node/skill/unique descriptions)` — A Conditions control ('Buffs on me', shadows) is shown only if a taken node's description/unique tooltip text mentions the name.
- game: Not derived from code or mutator data; a mechanic that grants a buff without naming it in the text (or the name appearing in unrelated text) hides or wrongly shows the control. This affects UI visibility only, not any number.
- evidence: D:\LastEpochBuilder\client\scripts\engine\config_relevance.gd lines 62-106. SHADOW_TEXT = "(?i)\\{shadows?\\}|\\bshadows\\b" (line 62) and SHROUD_TEXT = "(?i)\\{shroud\\}|any shroud" (line 63). Lines 72, 80, 85 and 90 append str(node.get("description")), str(ab.get("description")) and JSON.stringify(u.get("tooltip")) + JSON.stringify(unique_effects) to texts. Lines 93-98 build patterns from GameDa

## #100 [buffs-and-skillbuffs] Mana efficiency fields are inert and 'mana increased -f' models use -f instead of the game's division
- impact: Low to medium. The displayed mana cost and anything derived from it (ward/mana per spend, sustain) are wrong for builds with these nodes. The cost is not used for DPS.
- calculator: `client/data/field_models.json: 41 AbilityMutator.addedManaCostDivider entries as stat ManaEfficiency (21 mod=added, 20 mod=increased) and 6 entries (EntanglingRoots, Glacier, Meteor, ThornTotem, Torna` — ManaEfficiency (SP 69) is never read when computing the mana cost, so 41 entries change nothing. The 6 'mana' entries multiply the cost by (1 - f).
- game: cost = max(SP66 ManaCost(base+added, inc, more) / SP69 ME(added = 1 + divider + attr/level scaling, inc, more), minimumManaCost). A divider of f divides the cost by (1+f+...), not multiplies by (1-f).
- evidence: Calculator side. skill_calc.gd:1094 computes mana = (mana_base + mana_added) * (1 + mana_inc) with no ME term. grep of client/scripts finds MANA_EFFICIENCY only at le.gd:106. field_models.json has 47 addedManaCostDivider keys. Visible ones are kind=stat, stat=ManaEfficiency, with mod 'added' (AbyssalEchoes, AcidFlask, BoneCurse) or 'increased' (Avalanche, CinderStrike). MeteorMutator.addedManaCost


# Unverified (9)

- [hit-damage] ~35 skill_conversions rules rest on description text; the field is read only by getTags/VFX/DPS code in the mutator itself, the actual base-damage change happens in child objects or prefab variants that were not traced
- [speed-mana-cooldown] Cooldown regeneration pausing while the ability is in use is not modelled
- [ailments-player] Ailment chance is rolled per hit event in the calculator, but the game rolls it only on the FIRST hit of each ability object on each enemy (unless canApplyToSameEnemyAgain)
- [enemy-side] Training dummy / 'dummy' kind assumed to have zero DR, armour and resistances (forum-sourced)
- [enemy-side] Ailment uptime assumes independent Poisson applications; the game applies deterministic refreshes
- [minions-shadows] Granted skills: cast stats come from the owner's store, and the 'skill level 1 / base' claim is not tied to the mutator that actually exists
- [buffs-and-skillbuffs] Per-use 'component' entries for minion or timed behaviours
- [buffs-and-skillbuffs] Steady-state stack count at a cap uses min(mean, max) for random applications
- [uniques] Trinity of Flames (pp170): 'every 3rd fire spell is a guaranteed crit' modelled as +33.3% additive crit chance

# Refuted (3)

- [stat-model] Open item left unverified: Ward Gain modifier is computed from WardDecayThreshold stats in the game: The claim says no reader of PrecalculatedStatsHolder.wardGainModifier (+0x44) was found and that the effect on ward gain is UNKNOWN. That is wrong. The reader is ProtectionClass.GainWard, and the game
- [minions-shadows] Skeleton and mage rotation split is an assumption (D?): The claim says the code does not show an equal split and that the steady-state mix is UNKNOWN. I read SummonSkeletonMutator.Mutate myself, and the selection rule is a least-count balancing rule, which
- [minions-shadows] Umbral Blades shadow bonus '300% more' comes from altText; the value is not confirmed by code: The claim says the 300% value is not confirmed by code. I was able to confirm it from the game binary, so the model entry is not merely a tooltip guess.

The mechanism is real. In BaseUmbralBladesMuta

# Fix status

Status after waves 1 and 2 (working tree, not committed). FIXED = calculator matches the game code re-read in this wave; PARTIAL = main part done, remainder named; SKIPPED = no change, missing data named. Test vectors live in client/tests/engine_test.gd and minion_test.gd (suite passes after one repair round of test expectations).

## Wave 1

| # | Status | Note |
|---|---|---|
| 0, 33, 17, 32, 8, 9, 82, 22, 83, 21, 23, 84, 19, 55, 48, 54, 111, 112, 115, 116 | FIXED | Wave-1 fixes. |
| 29, 7, 86, 110 | PARTIAL | #7 zone part and #110 averaging remain; #86 finished in wave 2 (see below). |
| 20, 28, 94 | SKIPPED | Undeterminable from extracted data. |

## Wave 2: hit damage

| # | Status | Note / unblocker |
|---|---|---|
| 10, 11, 13, 14 | FIXED | Already in tree, re-verified. |
| 12 | PARTIAL | Conditional-penetration tag mask added; super-crit/crit ProtectionClass numbers not re-verified. |
| 15 | FIXED | Fireball, Fireball Explosion, Flame Reave keep Fire when converting (skill_conversions.json, merge.py OVERRIDES). Flame Reave cold branch has no rule; thresholds approximated. |
| 16 | PARTIAL | Condition arms and 40 done. Skipped 11 (needs enemy absolute health), 28 (enemy type data), 37 (petrified toggle), 41/42 (ailment-instance path, arg semantics), 43 (distance input). None used by extracted data except 43 on one corrupted bow affix. |
| 2, 3 | FIXED | Health tags and stacked buff effect match game code (per-instance multipliers assumed 1 and 0). |
| 39 | SKIPPED | Formula known but inert: only setProperty affix (780) rolls on body armor, one slot, N is always 1. Revisit if another affix gains setProperty 1. |

## Wave 2: speed

| # | Status | Note / unblocker |
|---|---|---|
| 24, 26, 27, 30 | FIXED | minimumUseDuration floor and delay clamp, scaler-54 stat models, weapon rate tag test, Dive Bomb/Falconry reducedDelay demoted to flag. |
| 25 | PARTIAL | Detonating Arrow, Lethal Mirage quick attack, Radiant Lance done. Other overrides are unreachable (no extracted source grants the switch) or do not change uses/s. Unblocker: a source granting the AP fields; exported prefab refs shieldRush/netTrap. |

## Wave 2: ailments

| # | Status | Note / unblocker |
|---|---|---|
| 45, 46, 49, 50a, 51a, 51b, 52 | FIXED | Early tick on cap, chance cap per max instances, exact-match increased, ability-scoped stats excluded, per-stack more values, ailment effect on stacks, lowest-speed modifier. |
| 50b | SKIPPED | Scathing Light ailment-instance-only more damage; not settled. |
| 53 | SKIPPED | replaceLowestDamageStacksInsteadOfOldest modelled as oldest-replaced; equal stacks make it equivalent for Time Rot, Doom, Scathing Light. |
| 47 | SKIPPED | Abyssal Decay payout depends on per-hit chance; needs a probability model the data does not settle. Spec premise contradicted by code (whenDamaged pays nothing). |

## Wave 2: enemy

| # | Status | Note / unblocker |
|---|---|---|
| 56, 59, 62 | FIXED | Stunned true for frozen (isCurrentState vcall identity inferred), mana toggle reaches conditional crit/pen, one fold per condition key. |
| 58 | FIXED | Ailment increased effect on target debuffs already implemented (via #51b). |
| 60 | PARTIAL | Handled arms confirmed. Remaining 43 (distance input + GetPerDistanceEffect trace), 41/42, 11, 28, 37 (see #16). |
| 57 | SKIPPED | Puncture bleed wipe period 3 vs 4 depends on onAbilityUse vs Mutate ordering; needs UsingAbility.UseAbility event-vs-ability-object order or a usesSinceLarge trace. |
| 63 | SKIPPED | Rive3 consume rate needs Rive1 prefab comboBehaviour / comboAbilities / comboTimeLimit. |
| 64 | SKIPPED | Soul Feast cleanse count and per-stack buff not traced (consumePoisonStacks body). |
| 65 | SKIPPED | Product decision: separate area-level input and default needed (skill_calc.gd:1357, ailment_calc.gd:285). |

## Wave 2: minions

| # | Status | Note / unblocker |
|---|---|---|
| 87 | PARTIAL | Companion limit flags, half-even rounding (inferred from structure), per-type cap done. Skipped: shared budget between companion types (depends on cast order), wolf squirrel (no record), wolf special 8, Spriggan/Falconry caps. |
| 88 | PARTIAL | Death Knight Harvest mutator target fixed. Cooldown recovery of minions UNKNOWN: ChargeManager.increasedRecoverySpeed is a prefab-serialised field not exported. |
| 90 | PARTIAL | Net imitated by shadows. Explosive Trap needs prefab component presence; Heartseeker already modelled as trigger; Bladestorm/Dreamslash do not fit; shurikensDirectNoShadowUse has no source. |
| 86 | PARTIAL | Increased damage (BasicMelee, Sabertooth moreHitDamage) and Skeleton Rogue cast speed done; Raptor not scaled. Remaining WolfMelee 0.15, Serpent/Vanguard BasicMelee: mutator-to-ability mapping not traced. Corpse Parasite inert. |
| 85 | SKIPPED | Sub-ability hit counts live in prefab components (CastAtRandomPointAfterDuration, CreateAbilityObjectOnDeath), not exported. |
| 92 | SKIPPED | Echo guaranteedEcho, PP 58/59 buffs, tag eligibility: need jump rate, echo-rate/uptime rule, AbilityTooltipTagInfoProvider tags. |
| 93 | SKIPPED | AbilityRangeList component values not exported. |

## Wave 2: buffs

| # | Status | Note / unblocker |
|---|---|---|
| 95 | PARTIAL | Serpent Venom vitality/poison/frostbite fields done. Crit field: unknown whether SerpentStrikeMutator.stats holds character stats only (skill store vs global store). Speed doubling at crit >= 0.5 not modelled. |
| 97 | PARTIAL | Stacked buff scaling verified, tests only. Per-instance increased effect source (ActiveAilment+0x94) is a design choice. |
| 98 | FIXED | holder_only on 74 field-model keys, skipped for ailment stack damage. Dark Quiver, Glyph/Runebolt/ChthonicFissure keys not changed. |
| 99 | PARTIAL | src_max in stack units for Serpent, Dancing, Shurikens, Cinder; Flay; Glyph and Runebolt 14. Drain Life skipped: cap grows with node points, value() cannot see points. |
| 103, 104, 105, 108 | FIXED | Aura of Decay frequency, Sacrifice DoT more, presence scaling (expected-value convention, changes stat models with enemy conditions), Symbols of Hope activation. |
| 96 | SKIPPED | Per-source Haste/Frenzy duration and ~45 timed-gain fields need new extraction plus a per-source duration design. |
| 101 | SKIPPED | Tempest Strike needs an exact port of BaseMana.getManaCost (mutator virtuals 0xBE8/0xBF8/0xC08/0x10A8, efficiency order). |
| 102 | SKIPPED | Per-tick ailment zones need prefab applicationInterval/radius/lifetime and RepeatedlyApplyAilmentsInRadius.addChance. |
| 106 | SKIPPED | Current-mana effects: average mana level is not a function of any extracted input. |
| 107 | SKIPPED | value:SP:mask source; only user is the skipped #95 crit field. |

## Wave 2: uniques

| # | Status | Note / unblocker |
|---|---|---|
| 109 | PARTIAL | Component plumbing and 12 component models done. 30:0 (Undisputed) and 52:0 (Soul Bastion) stay notes: need a bleed-uptime/hit-rate stack rule and a kill-time distribution decision. |
| 113, 114, 117, 118, 120, 121 | FIXED | Frenzy/Haste scaling, Salt the Wound conversion, Poison copies, untagged-only sources, input slot, invocation chance. |
| 122 | PARTIAL | Bane of Winter and Truesight Glass (super crit) done. Singularity inert for one item. Skipped: pp529 Kismet (ConsumeKismetStacks not extracted), pp574 reflection chain, pp588 overkill, pp148 needs multi-mod model schema. |
| 119 | FIXED | Conditions 117:35 and 117:40 already evaluated (see #16/#60). |
| 124 | SKIPPED | Param-kind unique effects: re-cast code for pp235 and consumers for pp571, 881:0, 263:4, 216:6, 731:0, 689:12/13, 12:2 not extracted. |
| 125 | SKIPPED | Recency windows (pp419, pp89, pp229/230): need a crit/use rate model decision and identity of unnamed thunk FUN_18000e8c0 (0x1b). Manual toggles kept. |

## Wave 2: passives and sets

| # | Status | Note / unblocker |
|---|---|---|
| 126, 131, 132, 133, 134, 136, 137, 138 | FIXED | Max-mana steps, block steps, mana-cost scaling, minion penetration, Shift bleed buff, mastery points, stack caps. |
| 128 | PARTIAL | Passive PP/AP plumbing and 29 PP models done. Left unmodelled: PP 312, 359-361, 563 (undecoded consumers), PP 691 predicate, traversal window, negative ailments on you, Stalwart/Elemental Arrow counters, AP fields without extracted mutator readers. |
| 129, 44 | PARTIAL | Set PP/AP bonuses routed through models. Unmodelled: ability 210 -> 211 relation (PP 68), PP 623 weapon legendary re-scaling. |
| 130, 35 | FIXED | Reforged set items counted by Set-affix uniqueId. |
| 135 | SKIPPED | Event-based self-buff chances need event rates (minion kill/death, totem summon) and a formula choice. |

## Follow-ups
- tools/models/out/batch_033.json still holds the old input:chill_chance model; do not re-run merge.py over field_models.json without redoing the #50a edit.
- tools/models/validate.py does not cover the merged field_models.json / unique_effect_models.json and rejects converted_attr:*, buff:*, weapon_added:*.
- Unique 187 label "Converted to Physical Penetration with Bleed" does not match the Bleed-effectiveness model; check on the next audit pass.
- #105 presence scaling changes results for every stat model with an automatic enemy condition; list it in the changelog.

# Fix status (defence)

Status after the defence wave (working tree, not committed). Part 2 findings, grouped. FIXED = calculator matches game code re-read in this wave; PARTIAL = main part done, remainder named; SKIPPED = no change, missing data named. Full headless suite (15 tests) passes with these changes; no test expectations were repaired. Test vectors: client/tests/defense_test.gd (`_review_fixes`, `_presets`, `_sheet_vectors`), engine_test.gd (`_gain_events`, `_dodge_per_int_cap`, `_idol_altar`), minion_test.gd (`_prefab_armour`).

| # | Status | Note / unblocker |
|---|---|---|
| 68 | FIXED | Hit-event damage taken: specialTag 1 on every hit, 6 only on a blocked hit, none on DoT. The sheet row "Damage taken from hits" in character_calc.gd still queries special 0 (same gap, not changed). |
| 67 | FIXED | more_player_property node effects collected and folded; Chill branch for PP 250. |
| 69, 123 | FIXED | PP 525 Immortal Vise is a flag; extra endurance applies per hit only while pending slow damage > 10% max health (strict). Only the f7 delayed share feeds the pending queue; other SlowDamageInstance sources not modelled. |
| 73 | FIXED | Boss Damage "increased" applied per damage type (Heorot, Volcanic Shaman). |
| 74a | FIXED | Rarity variants `average\|<type>\|magic` / `\|rare` (x1.6 / x1.9); default stays normal. |
| 74b | FIXED (no change) | healthSerialisation == 1 for all 261 monsters and all 19 boss presets; always-apply is already correct for every extracted preset. |
| 74c | SKIPPED | Spawn share of magic/rare monsters is not in extracted data. Needs MonsterRarityManager rarity roll chances per spawner/monolith difficulty. |
| 75a | FIXED | PP 96 fires per glancing roll on a landed hit. Model label still "Health on sliding hit" (game field: Glancing Blow); wording only. |
| 75b | FIXED | PP 33 ward requires health after the hit strictly below 35% of max. Ward amount still ignores the GainWard multiplier (see 76). |
| 76 | SKIPPED | Ward on hit (SP 97, 30 per proc) goes through ProtectionClass.GainWard, which applies the +0x1E0 list and wardGainModifier; calculator has no ward-gain multiplier. Needs that multiplier modelled first. Also open: before-damage timing (per-hit damage distribution), sourcesOfNoWardGain writers, tagged SP 97 reader. |
| 77a | FIXED | Health/Ward on hit count only specials the game reads (1 every hit, 7 melee, 2 per crit; 0 counts nothing). Side effect: SynchronizedStrikes `healthGainedFromShadowsCreatedWithin4Seconds` (SP 38 special 0) no longer counts; its real effect is AbilityProperty 469 and is not modelled. |
| 77b | PARTIAL | Health on block / kill / stun added to recovery sources. Ward on block/kill/stun not added: GainWard multiplier gap, and ward on block may be granted twice (blockEvent and afterBlockEvent); needs full control-flow proof of ApplyDamage ordering or an in-game observation. |
| 77c | SKIPPED | Freeze events (4), tagged kill/stun gains. Needs a freeze-events-per-second input/rule and the ability tags used for tagged gains (no extracted data uses them). |
| 78 | FIXED | Ward bypass flags, health and ward caps applied in take_damage, recovery, full pool, ward equilibrium. The ProtectionClass cap block at 1067-1072 (pre-ward D) is the same item and is covered by the caps. |
| 79 | FIXED | SP 60 current-health drain: exponential decay in recover, recovery row, ehp via timed simulation. |
| 80a | FIXED | Affix PP "more" folded; PP 275 less DoT taken during Haste as max(-0.75, (1+inc)*pp) on DoT only. |
| 80b | SKIPPED | PP 262 needs current mana (planner has only max mana and the low_mana flag; a user input is a design choice). PP 257/258 need attacker distance; boss_attacks.json and monster_damage.json hold no engagement distance. |
| 81 | SKIPPED | Formula confirmed (UsingAbility.InitialiseAbilityUse) but inputs are not extracted for boss abilities: speedScaler SP, speedMultiplier, scaler effectiveness, cap at Ability+0x64, minimumUseDuration, prefab baseUseSpeedMultiplier, CastSpeedManager overrides. Needs a new per-boss-prefab extraction of these fields. |
| 70 | FIXED | Slow queue taken from D after the endurance-threshold step; ward does not reduce it. Gate is d_slow > 0 (f7 = 1 queues nothing). |
| 71 | FIXED | Crit floor applied to the whole hit multiplier. Limit: when f0*(1-f7) = 0 the game yields M = 1 and the multiplicative factor gives 0; the +3.0 on 0x1cc in the crit branch is not analysed. |
| 72 | FIXED | Block converted to parry = min(0.75, parry + uncapped + min(maxBlock, block)), no f1. |
| 127 | FIXED | Dodge per Int cap applied to the whole per-Int value (max_field), uncapped duplicate removed. |
| 40 | FIXED | Altar property 29 is an added stat (SP 44), not increased. |
| 41 | FIXED | Sheet defence percentages use the area level setting as ZoneLevel. The sheet is now a zone view, not a hub view (modelling choice per audit). |
| 42 | FIXED | Thorns, crit avoidance, armour, dodge rating/chance, endurance threshold, block chance and parry follow the game's conversions. Block effectiveness input (holder +0x60) not re-verified. |
| 89 | FIXED | Minion base armour from the prefab ignored; BaseStats overwrites the field after the stat loop. |
| 91 | SKIPPED | Shadow creation rate model is an assumption: needs per-skill creation sources and rates, which uses consume shadows, resummon interaction, and a writer of CreateShadowMutator.additionalMaximumShadows (+0x130). ShadowCalc / ENGINE.md 9.10 should call "N x max(uses/s, 1/5)" an assumption (baseDuration 5 s is confirmed, RogueShadow.cs:21). |

## Follow-ups (defence)
- Ward gain multiplier (GainWard: +0x1E0 list, wardGainModifier +0x44) is unmodelled; it affects 75b, 76, 77a, 77b ward parts. Modelling it unblocks the ward half of those findings.
- character_calc.gd "Damage taken from hits" row ignores the specialTag mask (see #68).
- #71 limit and #69 residual (only the f7 queue feeds pending slow damage) are documented, not data-settled.
- Wording: PP 96 label "Health on sliding hit" should read Glancing Blow.
