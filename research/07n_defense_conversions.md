# 07n. Damage-Taken Conversions, Dodge/Block Conversions, Conditional Defenses, Leech and On-Hit Gains (Client 1.5.0)

Date: 2026-10-07. Sources: Ghidra `dump/decomp/LE.dll/*.c`, `dump/decomp_extra/`, ISIL `dump/isil/IsilDump/LE/*.txt` (where Ghidra dropped float arguments), offsets `dump/cs/DiffableCs/LE/*.cs`, constants via `tools/readconst.py`. Background: 06c (ApplyDamage), 07i, 07d, `player_property_fields.json`.

Machine table: `research/data/game/conditional_defenses.json` (keys: `convertDamageTaken`, `conversions`, `conditions` (42 entries, code order), `delayedDamage`, `leech`, `slotMap`).

Labels: **D** read unambiguously from code, **D?** ambiguous (explained). Slot names f0..f9 follow 06c (return tuple of `IDefensiveConditionalProvider.ApplyConditionalDefenses`).

---

## 1. `ProtectionClass.ConvertDamageTaken` (@0x181124B30) — "damage taken as X"

### 1.1 Formula (D)
Stats SP 31..37 = `DamageTakenAs{Physical,Fire,Cold,Lightning,Necrotic,Void,Poison}` (target type index 0..6 in damage-array order Phys, Fire, Cold, Light, Necro, Void, Poison). **The stat's `tags` is the SOURCE type**: `DamageTakenAsFire + tags=Physical` = "Physical damage taken as Fire" (confirmed by data: affix "Fire Damage Taken As Physical" = SP31 + tags Fire; unique The Ashen Crown = SP32 + tags Physical).

```
out = copy(in[7])                       // in = DamageStats.damage
for s in Actor.stats(BaseStats).stats:  // raw List<Stat>, list order
    if SP31 <= s.property <= SP37:
        t = s.property - 31
        for (i, bit) in [(Phys,1), (Light,2), (Cold,4), (Fire,8), (Void,16), (Necro,32), (Poison,64)]:
            if in[i] != 0 and (s.tags & bit):          // first match only
                m = min(s.addedValue, 1.0) * in[i]
                out[t] += m ; out[i] -= m
                break
```
then ApplyDamage multiplies every `out[k]` by `(1 + damageModifier)`.

Answers to the questions:
- **Added only**: only `Stat.addedValue` (+0x1C) is read. `increasedValue`, `moreValues`, `specialTag`, `extraTag` are ignored. Entries with an identical key (SP, tags, specialTag, extraTag) are summed by `BaseStats.addStat` before this runs, so the cap 1.0 acts on the summed share per (SP, source tag).
- **Scale**: fraction (0.4 = 40%).
- **Normalisation**: none. Each stat is clamped to <= 1.0 individually (not below: negative values move damage backwards). Shares of different stats are NOT normalised: two stats "60% Physical as Fire" and "60% Physical as Cold" leave Phys = -0.2*in, Fire = 0.6*in, Cold = 0.6*in; the negative entry is skipped later by the per-type `M*damage[i] > 0` test, so total taken damage becomes 120% (D).
- **No chaining**: every stat takes its share from the ORIGINAL array (`in`), so A->B plus B->C do not chain; a source type with `in[i]==0` is skipped.
- **Which damage**: all 7 types, hits and DoT alike (no `isHit` test).
- **Tags used for the stat query**: none. The function scans the stat list directly; there is no `GetStatValue` call, no tag filter, no hitEvents. Only AT bits 1,2,4,8,16,32,64 are tested; a stat with several type bits uses the first in the order Phys, Lightning, Cold, Fire, Void, Necrotic, Poison.
- **Gate**: `ProtectionClass.hasDamageTakenConversion` (0x176), set by `updateHasDamageTakenAndLeechBools` @0x181128DA0 whenever ANY stat of SP 31..37 exists (also sets 0x177 for SP6, 0x178 for SP51 HealthLeech, 0x179 for SP129).
- **Order in ApplyDamage** (D): (1) conversion (or plain copy) times `(1+damageModifier)`; (2) `DamageConditionalEffect.apply` (attacker/ability); (3) `ApplyConditionalDefenses` (which may still scale `damageArray[i]`, see section 3 rows "res above cap"); (4) per type: `ApplyResistance` of the NEW type, then `GetStatValueForHitEvents(DamageTaken, tags=(otherTags & ~0xFF)|typeTag(i), base 1)` of the new type, etc. So converted damage is mitigated by the resistance of the target type.

### 1.2 Inert stats (D)
Stats whose tags have no damage-type bit never convert: **Knight "Abyssal Fluctuation"** (kn-1 id 64: `DamageTakenAsVoid`, tags = Elemental 0x80, 10%/pt) and **Acolyte "Decaying Form"** (ac-1, >=6 pts: `DamageTakenAsPoison`, tags = DoT 0x1000, 0.5) match none of the tested bits. SP31-37 have no other reader in the dll (all `Stats.Get*` call sites grepped), so these two tooltips ("Elemental Damage Taken As Void 10%", "Damage Over Time Taken As Poison 50%") have no effect in this code. Whether this is a shipped bug cannot be told from code (D for the code, D? for in-game).

### 1.3 Test vectors (all executed with a reference implementation, in the JSON)
| Case | in [Phys,Fire,Cold,Light,Necro,Void,Poison] | stats (SP target, tags, value) | out |
|---|---|---|---|
| 40% Phys as Fire | [1000,0,0,0,0,0,0] | Fire, Phys, 0.4 | [600,400,0,0,0,0,0] |
| clamp | same | Fire, Phys, 1.5 | [0,1000,...] |
| no normalisation | same | Fire,Phys,0.6 + Cold,Phys,0.6 | [-200,600,600,...] |
| no chaining | [1000,500,0,..] | Fire,Phys,1.0 + Cold,Fire,1.0 | [0,1000,500,...] |
| source empty | [1000,0,...] | Fire,Phys,1.0 + Cold,Fire,1.0 | [0,1000,0,...] |
| multi-bit tags | [1000,1000,0..] | Void, Phys\|Fire(9), 0.5 | [500,1000,0,0,0,500,0] |
| negative | [1000,0..] | Fire, Phys, -0.2 | [1200,-200,...] |
| inert tags | [1000,500,500,500,..] | Void,Elemental,0.1 + Poison,DoT,0.5 | unchanged |

Sources of the stats: idol/sentinel affixes (2-3%, 8-20%, 18-19%), uniques (The Ashen Crown, Orians Eye, Bane of Winter, Blossom of Immortal Stone, Ravenous Void), skill node Shatterhide (Sabertooth).

---

## 2. Writers of dodge/block/endurance/ward flags (all inlined; the setters have no callers)

`PrecalculatedStatsHolder.setDodgeConversion` @0x1804EE5F0, `setBlockConversion` @0x1805EBE20, `SetMaximumBlockChance` @0x1805E1950 are never called by name: the writes are inlined into `CharacterMutator.applyModifiersBeforeExternalStatsCalculation` @0x182601FE0 and executed on every stats update against `CharacterMutator.protection` (+0x20A0). (D)

| Holder field | Value semantics | Writer (D) | Source |
|---|---|---|---|
| `dodgeConversion` (+0x58) | 0 none, 1 dodgeRating added to armour, 2 glancing += 2*dodgeChance (no dodge roll), 3 dodgeRating added to endurance threshold | `mode = 0xF18 ? 3 : 0x11D9 ? 2 : 0x11D8 ? 1 : 0` (priority 3>2>1) | PP 425 `dodgeConvertedToEnduranceThreshold` (holder not found in extracted data, D?), PP 194 `dodgeConvertedToGlancingBlow` (Rogue passive rg-1 "Apostasy"), PP 177 `dodgeConvertedToArmor` (Knight passive "Iron Reflexes" >=5 pts; skill node). All flags `added>0.1`. |
| `blockConversion` (+0x6C) | 0 none, 1 glancing (block roll off), 2 parry (block roll off) | `mode = (0x1BD0 && weaponInfoHolder exists && !hasShield) ? 2 : (0x1668 ? 1 : 0)`; parry wins | PP 531 `blockChanceConvertedToParryWithoutShield` (unique Clothos Needle), PP 392 `blockChanceConvertedToGlancingBlow` (Rogue passive "Deflect and Weave" >=5 pts) |
| `maximumBlockChance` (+0x68) | 0 = no cap, else fraction cap | `*(prot+0x68) = CharacterMutator.maximumBlockChanceFromTheSlab (0x1F14)` | PP 614 (op add), unique The Monolith 0.75 |
| `enduranceMode` (+0xC8) | 0 HealthBelowThreshold, 1 ...AndMana, 2 Everything | local `iStack_4c8`: PP 310 (>0.1) -> 2; PP 309 (>0.1, only if still 0) -> 1; then `*(prot+0xC8)=local` | PP 309 (unique Seed of Ekkidrasil; the PlayerPropertyList name is "Endurance applies to all damage dealt to mana"), PP 310 "Endurance applies to All Damage" (holder not found) |
| `dotsBypassWard` (+0x1A0) | DoT skips ward | `= CharacterMutator.dotsBypassWard (0x675)` | tree field: Acolyte passive ac-1 node 44 "Impact Ward" at >=3 pts (AcolyteTree.updateMutator); no PP |
| `hitsBypassWard` (+0x1A1) | hits skip ward | `= CharacterMutator.hitsBypassWard (0xDF4)` | PP 685 (unique Vestige of Imprisonment) |
| `maxHealthCapForWard` (+0x19C) | ward <= maxHealth*x (GainWard clamp), 0 = none; `GainWard` re-called when it changes | min of the non-zero of `maxHealthCapForWardFromAcolyteTree (0x670)` and `maxHealthCapForWardFromArchitectsOfAncestralBlood (0x1EE8)` | tree: Acolyte "Corrupted Form" (ac-1 node 115, >=2 pts, 0.5; same node also sets `maxHealthCapForCurrentHealth` 0x66C=0.5 and `alwaysLowLife`); PP 609 (unique Architects of Astral Blood 2.0-2.4) |
| `canBeUnableToBlock` (+0x1A2) / `unableToBlockSources` (+0x1A8) | block flag (0x20) suppressed if any source `unableToBlock()` | `addUnableToBlockSource`; only caller is `ShieldThrowMutator` (registers itself; `unableToBlock()` = `noBlockDuringThrow`(0x179, tree flag) and thrown shields alive) | Shield Throw skill-tree flag. **D?**: nothing in the dll writes `canBeUnableToBlock` (0x1A2) (serialised prefab field) |
| `sourcesOfNoWardGain` (+0x198) | >=1: no ward gain | `UpdateSourcesOfNoWardGain` @0x18266E7B0 (+1 while `noWard` 0x1AE8) and `...FromBeingInCombat` @0x18266E6E0 (+1 while `noWardGainInCombat` 0x1AF0 and in combat) | PP 471 "No Ward" |

---

## 3. `CharacterMutator.ApplyConditionalDefenses` (@0x18261D5C0)

Signature `(DamageStats, float[] damageArray, Actor attacker, bool attackerExists)` -> 10 floats. `isHit` = `DamageStats.isHit` (+0x20), `DoT` = `otherTags & 0x1000`. Slots (D): f0 damage multiplier (start 1.0), f1 block chance add, f2 armour increase, f3/f4 endurance threshold adds (f3 ignite/shock stacks, f4 missing mana), f5 crit avoidance add, f6 parry (constant 0), f7 delayed fraction, f8 extra endurance, f9 thorns increase. The tuple order was read from the `ValueTuple8` constructor call (args f0, f1, f2, ignite/shock threshold, missing-mana threshold, critAvoidanceVsShocked, 0, nested(f7, f8, f9)).

The function never reads `damageStats.damage`; the conditions that touch `damageArray[i]` (no slot) modify `ProtectionClass.damageArray` in place before the per-type mitigation. All hit/DoT/attacker tests are listed per row. Condition order = code order (JSON `conditions[].order`).

| # | Field (offset) | Slot | Formula | Condition | Applies | Source |
|---|---|---|---|---|---|---|
| 1 | chanceToTakeNoDamageWhenHitPer10Guile 0x1FF4 | f0 | `roll(attr3/10*pp)` -> f0=0 | attribute 3 corrupted (Dexterity->Guile, PP 652) and isHit | hit | PP 657 (Exulis) |
| 2 | takesLessHitDamageFromEnemiesInHailOfArrows 0x1798 | f0 | `*= 1 - tracker(attacker,3)` | flag, attacker, isHit | hit | PP 619 (no holder found) |
| 3 | takesLessDamageFromEnemiesDamagedByDrainLife 0x17C4 | f0 | `*= 1 - tracker(attacker,7)` | flag, attacker | both | PP 650 (**D?**: PlayerPropertyList name "Strength Converted to Brutality"; code name is the Drain Life one) |
| 4 | moreDamageTakenWhileLeeching 0x15A8 | f0 | `*= 1+pp` | player's `LeechTracker.getTotalCurrentLeech()>0` | both | PP 340 |
| 5 | moreHitDamageTakenFromRareBoss 0xE34 | f0 | `*= 1+pp` | attacker rare/boss, isHit | hit | PP 682 |
| 6 | moreDamageTakenWithoutFrenzy 0x1F84 | f0 | `*= 1+pp` | no Frenzy (34) | both | PP 638 |
| 7 | moreDamageTakenPerRecentMeteorCast 0x1328 | f0 | `n=min(18,recentCasts); f0=max(0,f0*(1+n*pp))` | Meteor mutator present, n>0 | both | PP 246 |
| 8 | moreReflectDamageToBossesAndRares 0x1D60 | f9 | `f9 = combine(0,pp)` (=pp) | attacker rare/boss | both | PP 575 |
| 9 | bonusDamageReduction...DelayedDamage 0x17DC | f8 | `f8 = pp` | `slowDamageRemaining > 0.1*maxHealth` | both | PP 525 |
| 10 | moreDamageTakenFromEnemiesWithin4m 0x1380 / blockChanceAgainstEnemiesWithin4m 0x1384 | f0 / f1 | `f0*=1+pp257; f1=pp258` | attacker closer than 4.0 | both | PP 257 / 258 |
| 11 | blockChanceWhileMoving 0x1F48 | f1 | `+= pp` | player moving | both | PP 625 |
| 12 | moreDamageTakenWithAtLeast1000Ward 0x138C | f0 | `*= 1+pp` | ward >= 1000 | both | PP 259 |
| 13 | moreDamageTakenWithAtLeast400CurrentMana 0x139C | f0 | `*= 1+pp` | mana >= 400 | both | PP 262 |
| 14 | moreDamageOverTimeTakenWhileYouHaveHaste 0x13FC | f0 | `x=max(-0.75,(1+TotalIncreased(SP120,spec 33))*pp); *=1+x` | DoT, player has Haste | dot | PP 275 |
| 15 | moreDamageOverTimeTakenPer8OvercappedCold 0xE70 | f0 | `over=min(2,cold-0.75); *= 1+over*pp*12.5` | DoT, cold res > 0.75 | dot | PP 677 |
| 16 | morePhysDamageTakenPer5Overcapped...UpTo10Percent 0xCD8 | damageArray[Phys] | `*= 1+max(-0.1,(res-0.75)/0.05*field)` | phys res > 0.75 | both | **tree**: Knight "Battle Hardened" kn-1 node 28, -0.01 at >=7 pts |
| 17 | moreDamageTakenPerActiveShadow1in6Chance 0x1420 | f0 | `n=shadows; f0=max(0,f0*(1+n*pp))` | roll(1/6) and shadow mutator and n>0 | both | PP 281 |
| 18 | effectiveBonusEnduranceThresholdPer10MissingMana 0x1410 | f4 | `missingMana*pp*0.1` | mana component | both | PP 278 |
| 19a | moreDamageTakenFromChilledEnemies 0x133C | f0 | `*=1+pp` | attacker Chill | both | PP 250 |
| 19b | ...SlowedEnemies 0x1350 | f0 | `*=1+pp` | attacker Slow | both | PP 561 |
| 19c | ...TimeRottedEnemies 0x1358 | f0 | `*=1+pp` | attacker TimeRot | both | PP 490 |
| 19d | ...ShockedEnemies 0x1344 + critAvoidanceVsShocked 0x1524 | f0 / f5 | `*=1+pp252; f5=pp321` | attacker Shock | both | PP 252 / 321 |
| 19e | ...IgnitedEnemies 0x1340 + enduranceThresholdPerIgniteOnTarget 0x1528 + enduranceThresholdPerShockOnTarget 0x1C30 | f0 / f3 | `*=1+pp251; f3=igniteStacks*pp322 (+shockStacks*pp549, only inside this block)` | attacker Ignite | both | PP 251 / 322 / 549 |
| 19f | ...IgnitedShockedOrChilledEnemies 0x1474 | f0 | `*=1+pp` | attacker Ignite or Shock or Chill | both | PP 291 |
| 19g | ...IgnitedDamnedOrBleedingEnemies 0x1348 | f0 | `*=1+pp` | attacker Ignite or Damned or Bleed | both | PP 346 |
| 19h | moreDamageTakenFromChilledOrBleeding 0xE44 | f0 | `*=1+pp` | attacker Chill or Bleed | both | PP 711 |
| 19i | cursed attacker: moreDamageTakenFromCursedEnemies 0x134C, ...PerCurseOnAttacker 0x16C8, moreArmorPerCurseOnAttacker 0x16B8 | f0, f0, f2 | `*=1+pp347; *=1+curses*pp356; f2=curses*pp354` | attacker cursed | both | PP 347 / 356 / 354 |
| 20 | moreDamageOverTimeTakenFromSlowedEnemies 0x1424 | f0 | `*=1+pp` | DoT, attacker Slow | dot | PP 282 |
| 21 | moreDamageTakenFromWitheringEnemies 0x16E4 | f0 | `*=1+pp` | attacker Withering (115) | both | PP 373 |
| 22 | moreArmourAgainstShockedEnemies 0x1444, moreArmourPerShockOnAttacker 0x152C, blockChancePerShockOnAttacker 0x1448 | f2, f2, f1 | `f2=(1+pp)(1+f2)-1` twice; `f1+=stacks*pp287` | attacker Shock | both | PP 286 / 323 / 287 |
| 23 | moreArmourAgainstChilledAttackers 0x1AA8 | f2 | `(1+pp)(1+f2)-1` | attacker Chill | both | PP 454 |
| 24 | moreArmourAgainstBlindedAttackers 0x1AAC | f2 | same | attacker Blind | both | PP 455 |
| 25 | moreDamageTakenPer2pResAboveCap 0x1360 / max 0x1364 | damageArray[i] x7 | `*= 1+max(-pp255,(res_i-0.75)/0.02*pp254)` | res_i > 0.75 | both | PP 254 / 255 |
| 26 | moreFireDamageTakenPer10PercentFireResAboveCap 0x19AC / min 0x19B0 | damageArray[Fire] | `*= 1+max(pp437,(res-0.75)/0.1*pp436)` | fire res > 0.75 | both | PP 436 / 437 |
| 27 | percentDamageRedirectedToHighest/LowestHealthMinion 0x1B88 / 0x1B9C | f0 | `h=min(pp,0.75); l=min(pp2,0.75-h); *= 1-h-l` | a living minion exists | both | PP 496 / 562 |
| 28 | percentageOfDamageRedirectedToBearWhileBearAboveHalfHealth 0xB10 | f0 | `*= 1-pp` | bear minion (AbilityID 56) above 50% health | both | PP 670 |
| 29 | slowDamagePercent{FromRareAndBossHits 0x1B34, FromHits 0x1B38, FromSpiritPlaguedHits 0x1B3C} | f7 | `x=(rare/boss?1-pp498:1)*(plague?1-pp671:1); f7=1-(1-pp564)*x` | isHit, attacker, any nonzero | hit | PP 498 / 564 / 671 |
| 30 | chanceToTake0DamageFromHits 0x1AC4 | f0 | `roll(pp)` -> f0=0 | isHit | hit | PP 462 |
| 31 | moreDamageTakenFromFirstHitFromEnemies 0x1E08 | f0 | `*=1+pp` (once per attacker, list pruned every 3 s) | isHit, attacker, f0>0 | hit | PP 587 |
| 32 | moreDamageTakenFromBossesAndRareEnemiesWhileBelowHalfMana 0x1EB0 | f0 | `*=1+pp` | attacker rare/boss, mana <= 50% (no isHit test) | both | PP 598 |
| 33 | blockEffectivenessAppliedToDoT 0x1CF8 | f0 | `*= 1 - blockMitigation(blockProtection)*pp` | DoT | dot | PP 524 |
| 34 | AbilityStatsMutatorManager.lessHitDamageTakenFromEnemiesOutsideRingOfShields 0xECC (radius 0xED0) | f0 | `*= 1 - field` | attacker farther than radius, no isHit test | both | **tree/skill**: AbilityID 172 ringOfShields AbilityProperty idx 12/13 (exact node D?) |

Group gate for rows 19a-19i (D): `attackerExists` and attacker has an AilmentReceiver and at least one of the 13 group fields is nonzero; 0x1C30 is not part of the gate and is only evaluated inside the "attacker ignited" block (D? whether intended).

Counts: **42 JSON entries (34 code blocks; 55 distinct fields)**. PlayerProperty-sourced: 40 entries (53 fields, each with a `player_property_fields.json` index), tree-sourced only: 2 (row 16 Battle Hardened, row 34 Ring of Shields), unknown source: 0. 11 entries have at least one PP with no holder found in the extracted item/passive data (PP 619, 638, 257, 258, 262, 321, 322, 711, 347, 323, 670, 564, 671; also not found for 310 and 425 in section 2): the PP exists and is read; the item/node that grants it was not located (D?).

Remarks: (a) rows 27/28 only remove damage from the player; no redirect to a minion is applied in this function (D?, may be done elsewhere or not at all). (b) Hits only for rows 1, 2, 5, 29-31; DoT only for 14, 15, 20, 33; the rest both. (c) f6 is never set (always 0).

### 3.1 Delayed damage f7 (D, one D? inside)
- f7 formula in row 29. In ApplyDamage: `M = f0; if f7>0: M = max(0,(1-f7)*M)`.
- After the health step, if f7>0 and D>0 and the target survived (currentHealth>0) and has a LeechTracker: `SlowDamageInstance{total=remaining=D/(1-f7)*f7, duration 4.0 s}`. D is the damage at the ward stage (after armour, resist, block, damageTakenBuff, mana-before-ward, Endurance Everything, minimumHealth; minus the endurance-threshold absorption when it applies; NOT minus ward or mana-before-health absorption). Which exact Ghidra variable this is: D?.
- Tick (`LeechTracker.OnUpdateTick` @0x18111C3F0): linear, `remaining*dt/remainingDuration` per frame, applied through `SurvivesDirectDamage_1(amount, false, out, false)`: not scaled by the untagged DamageTaken modifier (only used for the invulnerability test), minimumHealth caps it, ward absorbs first (consumed), remainder to health (boss-ward step in between). `dotsBypassWard` is not consulted.
- Not mitigated again: armour, resistances, block, endurance, mana are applied once at hit time; the delayed share is just the other part of the same mitigated damage. Ward still absorbs the ticks.
- PP 525 (f8) uses `GetSlowDamageRemaining() > 10% maxHealth`.

---

## 4. Leech and on-hit gains

### 4.1 Leech formula (D; scale confirmed)
In `ProtectionClass.ApplyDamage` per damage type i after its full mitigation (d):

```
if attacker.protection.hasLeechStats(0x178) == false:
    leech += d * additionalLeech
else:
    leech += d * 0.1 * GetStatValueForHitEvents(attacker.stats, HealthLeech(SP51),
              tags = otherTags with low byte = type tag i, hitEvents,
              added = 10*additionalLeech, increased = 0, more = 0,
              extraTag = attacker primary AbilityID index, treatExtraTagZeroAsMatching = true)
     = d * 0.1 * (10*additionalLeech + SumAdded) * (1+SumInc) * Prod(1+more)
```
- `additionalLeech` (0x1D4) = `DamageStats.additionalLeech` + (victim is a player ? `leechVsPlayers` : 0).
- **x0.1 is confirmed**: constants `0x184561DB8 = 0.1` and `0x184561DDC = 10.0` (ISIL), and data agree: unique tooltip "3% of melee damage leeched" has HealthLeech 0.3; Immortal Vise 0.1-0.2 = 1-2%; affix "Melee Health Leech" T1 0.23-0.29. So a HealthLeech stat v leeches `v*10` percent... of d; ability `additionalLeech` is 1:1.
- Afterwards: `leech *= D_after/D_before` when block/damageTakenBuff changed D; after `BaseHealth.HealthDamage` returns the overkill: `leech *= (D - overkill)/D` (D includes ward-absorbed damage, so ward damage still leeches; **capped by the target's remaining health via the overkill**); overkill leech `+= overkill*attacker.overkillLeech(SP93)*0.1` (isHit only). Attacker must be alive and != victim. Then `attacker.LeechTracker.AddLifeLeech(leech)`.
- Payout: instance paid linearly over `3/(1+IncreasedLeechRate(SP102))` s; ignored while the leech-disabled timer runs; no cap; plain addition to health (caps at max health / health caps). `PlayerLeechTracker` can turn leech into damage to the nearest enemy (<=6 m) instead (`leechDamagesEnemiesInstead` 0x658, tree) or additionally (`percentLeechAlsoDealtAsDamage` 0x1EB4, PP 599).

### 4.2 IncreasedHealing (SP44) (D)
Does NOT affect leech, on-hit/on-kill/on-block/crit/stun/freeze HealthGain (`ResourceGainEvents` calls `BaseHealth.restoreHealth` directly), nor regeneration (`BaseHealth.OnUpdateTick`). It scales heals computed as `heal*(1+SP44)` in: ability components (GiveSelfResourcesOnKill/OnAbilityUse, GiveCreatorResources*, GiveNearbyAlliesResourcesOnDeath, HealAlliesOnHit, HealParent, RepeatedlyHealAlliesWithinRadius, RepeatedlyGiveCreatorResources, CreateResourceReturnAbilityObject*), skill mutators (Judgement via `HealWithIncreasedHealingEffectiveness`, ConsecratedGround, FlameTrail, EterrasBlessing, FuryLeap, RadiantLance, RingOfShields, RipBlood, Warcry, SummonRaptor, SummonVolatileZombie) and three `CharacterMutator` sites (one adds +0.04 per point of attribute 4).

### 4.3 HealthGain (SP38) / WardGain (SP39) on hit (D)
- `ResourceGainEvents.UpdateResourceGainTotals` @0x18115B3A0 (on every `updateStatsEvent`) sums **added values only** of untagged stats (tags==0 and extraTag==0) per specialTag: 1 OnHit (adds to both the hit slot and the melee-hit slot), 2 OnCrit, 3 OnKill, 4 OnFreeze, 5 OnStun, 6 OnBlock, 7 OnMeleeHit only. Tagged or ability-specific stats go through `GainResourcesFromTaggedOrAbilitySpecificStats` (tag filter, ICD via `CanProc`/ProcTimeTracker, summed once per event).
- Applied per detailed hit event (`onHitEventDetailed`, i.e. per hit instance per target; no splitting by hits): non-melee hit -> `restoreHealth(healthOnHit)`, `gainMana`, `GainWard(wardOnHit)`; melee hit (`dae tags & 0x200`) -> the melee-hit slots. No IncreasedHealing scaling.
- Ward goes through `GainWard` only: skipped if `sourcesOfNoWardGain>=1`; `(1+t)` of the quirky "more ward generated" list; `wardGainModifier` (06c D?); clamp `maxHealth*maxHealthCapForWard`. SP39 itself has no extra multiplier. Block gains use `GainWardOnBlock` (a replica of GainWard).
- Health: `restoreHealth` adds the amount, caps at maxHealth, health caps (0xCA/0xCC) and `maxHealth*0xA4` (e.g. Corrupted Form 50%).

---

## 5. Unresolved
- Holders of PP 425, 310, 619, 638, 257, 258, 262, 321, 322, 711, 347, 323, 670, 564, 671 not found in the extracted item/node data (field readers are known).
- PP 650: code name (Drain Life tracker) vs PlayerPropertyList name (Strength->Brutality corruption flag) disagree; the 1.5 effect of the flag is as coded in row 3 (D) but its purpose is D?.
- Who sets `ProtectionClass.canBeUnableToBlock` (0x1A2); exact skill-tree node for the Ring of Shields distance reduction; whether the 0x1C30 shock-threshold nesting and the two inert conversion nodes (section 1.2) are intended.
- Vtable identity of the two `Stats` calls in condition 1 (`AttributeIsCorrupted` / `GetAttributeValue`) is inferred from signatures and the PP names (PP 652 "Dexterity Converted to Guile").
- Which Ghidra variable equals D at the SlowDamageInstance site (section 3.1).
