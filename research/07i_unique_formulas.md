# 07i. Formulas of Special Effects of Unique and Set Items (Client 1.5.0)

Continuation of 07d (part 2). Closes section 2.7 «Could Not Determine»: what exactly PlayerProperty handlers do, how skills read AbilityProperty and which AbilityIDs items call.

Results:
- `research/data/game/unique_effects.json` (updated in place): for each PlayerProperty/AbilityProperty effect added `formula`, `plannerModel`, `plannerConstants`, `confidence`. Old lines preserved in `formulaGeneric` / `confidenceStructure`. Top-level `ppFormulas` — reference by ppIndex (359 entries), `apCoverage` — AbilityProperty coverage.
- `research/data/game/item_procs.json` — item → AbilityID (38 PlayerProperty/Component entries + 52 ability-scoped chances).
- `research/data/game/abilities.json` — abilities with added `itemProcs` and `resolution` (field for all `abilityIdOnly`).
- `research/data/game/ability_property_fields_c.json` — new map (AbilityID, specialTag) → `AbilityStatsMutatorManager` field (2242 entries vs 490).
- Tools: `tools/extract/ap_switch_c.py`, `merge_unique_formulas.py`, `build_item_procs.py`. Work directories: `dump/work_wave3/{notes,pp,pp_c,*.py}` (`notes/A..F.py` — hand formulas, `ctx.py`/`hint.py`/`lift2.py`/`statctor.py`/`auto.py` — ISIL readers).

## 1. Coverage

| Class | Total | Done |
|---|---|---|
| PlayerProperty (unique fields) | 359 indices (399 effects) | each has formula. Of 399 effects: **D** (read and verified in code) 141, **D(const)** (constants from code, trigger semantics from tooltip) 33, **D?** (structure and name; some constants unresolved) 225 |
| AbilityProperty | 385 effects (366 skill+property pairs) | `AbilityStatsMutatorManager` field found for 374 (97%), operation, reader classes for 350. Semantics — by tooltip (**D?**) |
| Item proc abilities | 38 item → AbilityID bindings | `item_procs.json` |
| `abilityIdOnly` in abilities.json | 433 | 20 bound to items, rest marked `resolution` (mostly skill/Weaver/tree procsand monsters) |

Planner models (`plannerModel`): `conv` (stats from attribute/stat), `cond` (conditional multiplier/bonus), `buff` (buff for N s, model by uptime), `proc` (chance + ICD + AbilityID), `stat` (flat stat/resource), `flag`, `util` (doesn't affect DPS/EHP).

## 2. How to Read PlayerProperty Handler

Field `CharacterMutator` filled by `applyModifiersBeforeExternalStatsCalculation` (see 07d 2.2), read by trigger methods. Typical schemes (all **D**):

1. **Stat from Attribute** («X per N Y»). Block in `applyModifiersBeforeExternalStatsCalculation` after switch:
   `current = pp · f(source) · k`, then `AddStatModifier(SP, value = current − previous, ModType, AT, specialTag, extra)` (Stats vtable +0x1c, arguments in `r8`=SP, `xmm3`=value, stack `0x20`=ModType, `0x28`=AT, `0x30`=specialTag). **No floor**: «per 2 Int» is `pp·Int·0.5`.
   - ModType: 0 ADDED, 1 INCREASED, 2 MORE.
   - Attribute IDs in `Stats.GetAttribute`: 0 Str, 1 Vit, 2 Int, 3 Dex, 4 Att.
   - Divisor constants: `0.5` (per 2), `0.2` (per 5), `0.1` (per 10), `/3`, `/40`, `/120`; resistances read as fraction, «per 1%» = `·100`.
2. **Incoming Damage** — `ApplyConditionalDefenses`: multiplier `M` starts at 1, each condition `M *= (1+x)`; returns tuple (M, +block chance, more armor, crit avoidance, +endurance threshold, fraction of delayed damage).
3. **Outgoing Temp Stats** — `ApplyConditionalTemporaryStats`/`ApplyPreMutationTemporaryStats`: stats added to list of specific cast; condition — ability tags (`uVar11 & mask`), «every N seconds» — field `remainingCooldown…` (reset only on actual use `param_5`).
4. **Procs** — `OnHit`/`OnKill`/`OnCrit`/`OnBlock`/`HitDamageTaken`/`OnAbilityUse`…: `RngElement.Roll(pp)` (chance = mod value), ICD — field `…Cooldown` (value from `.ctor`, see `character_mutator_init.json`) or `ProcTimeTracker` («N times per T s»), then `Ability.getAbility(ID)` + `AbilityObjectConstructor.constructAbilityObject`. Buff on event: `Buff(stat, duration)`, duration 4 s for all «recently» (register `xmm13` = 4.0).

## 3. Notable Formulas (Full List — in `ppFormulas`)

Notation: `pp` — mod roll; M — incoming damage multiplier.

### 3.1 Conditional Damage and Defense Multipliers
| PP | Item | Formula |
|---|---|---|
| 254/255 | Null Portent | for each damage type: if resistance > 0.75: `x = max(−pp255, (res−0.75)/0.02·pp254)`, `dmg_i *= 1+x` |
| 246 | Harbinger of Stars | `M *= 1 + min(18, recent Meteors)·pp` |
| 259 | Aergon Refuge | `M *= 1+pp` if Ward ≥ 1000 |
| 275 | Advent of the Erased | DoT only when Haste: `x = (1+TotalIncreased)·pp ≥ −0.75` |
| 281 | Gambit of an Erased Rogue | `Roll(1/6)`, `M *= 1 + n_shadows·pp` |
| 462 / 657 | Wall of Nothing / Exulis | chance `pp` (or `pp·Guile/10`) to nullify hit |
| 587 | Wings of Discord | first hit from each enemy: `M *= 1+pp` |
| 598 / 682 | Spirit Xylem / Effusive Oath | boss/rare: `M *= 1+pp` (at mana ≤ 50% / for hits) |
| 496 | Mantle of the Pale Ox | redirect `r_h = min(0.75,pp)` to healthiest minion, `M *= 1−r_h−r_l` |
| 498 | Immortal Vise/Effusive Oath | fraction of rare/boss hit stretched over 4 s (`LeechTracker.slow`) |
| 524 | Countenance of Majasa | DoT: `M *= 1 − blockMitigation·pp` |
| 454/455/286 | Snowblind/Static Shell | `armorMore = (1+pp)(1+armorMore)−1` against attacker with Chill/Blind/Shock |
| 129 | Titan Heart | `DamageTaken MORE = −pp` with two-handed melee weapon |
| 240 | Red Ring of Atlaria | `DamageTaken MORE = pp` if attribute sum ≥ 180 |

### 3.2 Outgoing Damage
| PP | Item | Formula |
|---|---|---|
| 161–164 | Eternal Eclipse | every 2 s next void-melee attack: +pp added Fire\|Melee (and Ignite); next fire-melee: +pp Void\|Melee (and Time Rot) |
| 228 | Vaions Chariot | every 3 s next movement skill: MORE Damage +pp |
| 234 | Humming Bee | Elemental Melee: INCREASED Damage `pp·Ward/200` |
| 222 | Immolators Oblation | Spell added Damage `pp·min(Ignite stacks, 40)` |
| 419 | Gambler Fallacy | +pp crit chance if no crit ≥ 4 s and skill not channelled |
| 89 | Gambler Fallacy | after crit 4 s: crit chance MORE −pp |
| 93 | Vaions Chariot | INCREASED Damage = `pp·TotalIncreased(MoveSpeed)` (pp=1: +100% per +100% MS) |
| 154, 196 | Darkstride, Shattered Lance | MS inc `pp·addedMeleeVoid·0.1`; Melee Cold inc `min(20, pp·HealthRegen·0.1)` |
| 506 | Crystalwind | cost ≤ 4 stacks: MORE Damage `consumed·pp` |
| 631 | Jormuns Feast | crit multi `pp` per 10 Bleed on target, max 200 stacks |
| 180 | Longshot | +40 added Physical\|Bow at Dex ≥ 40 |

### 3.3 Stats from Attributes (ADDSTAT)
All «per N» from 3.3 have form `pp · source / N` without floor, examples: `146` Lightning\|Spell added `pp·Int/2`; `185` Physical\|Spell added `pp·Att/3`; `413/414` Penetration `pp·Dex/5`; `431` crit multi `pp·Str/2`; `285` Health `pp·Vit`; `183` MS inc `min(0.2, pp·Dex/2)`; `220` Block `max(0,pp·(Endurance−0.6)/0.02)`; `474` WardRegen `pp·maxHealth`; `325` EnduranceThreshold `pp·maxMana`; `569` Ignite chance `pp·res·10` (res — uncapped fraction); `686` Fire pen minions `pp·(res−0.75)·100/3`.

### 3.4 Procs (chance = mod roll unless stated; ICD/PTT from code)
| PP | Item | Event → AbilityID | ICD / PTT |
|---|---|---|---|
| 4 | Apiarists* | every `10/pp` s → summonBee (353) | — |
| 28 | Ucenui Sphere | hit rare/boss → waterOrb (92) | 3 s |
| 30 | Arek Bones | hit left < 50% HP → summonAreksFlesh (367) | 20 s |
| 32 | Dark Shroud of Cinders | hit received → fireAura (162) | 3 per s |
| 37 | Sunforged Cuirass | hit received → summonWeapon (220) | 2 s |
| 40 | Locket of the Forgotten Knight | hit → voidRift (87) | 3 s in code (2 s in tooltip, **D?**) |
| 42 | Fiery Dragon Shoes | crit you → fireTrail (378) | 5 s |
| 68 | Halvar's | spell-crit → avalancheSnowball (210) | 1 s |
| 76 | Alluvion | melee attack → alluvionWave (426) | 1 s |
| 81 | Trident of the Last Abyss | melee-kill/hit rare/boss → abyssalEchoes (118) | 3 s |
| 83 | Dragonflame Edict | minion skill → dragonfireNova (427) | 3/s |
| 134 | Reign of Winter | bow hit → heorotUniqueBowIcicle (518) | — |
| 138 | Aurora Time Glass | below 30% HP → auroraAmuletSpell (530), Haste | 20 s |
| 155, 166, 184, 186, 203, 264, 265, 508 | see `item_procs.json` | — | PTT/ICD there |

Components (constants from code, 07d 2.4): Keepers Gloves swarmOfBees(63) 0.1/8 s; Arboreal Circuit summonIllusoryTree(62) 0.1/15 s; Volcanus flameShards(117) 0.3; Bone Harvester(122) 0.2 on kill; Torch of the Pontifex pontifexCremate(121) 1.0 on kill; Frozen Ire tundraNova(315) 0.15 (0.30 vs undead); Soul Bastion soulEruption(233) on 5 charges; Strong Mind lightningExplosion(67) on stun; Ignivar Head fireAura(162) once per 1 s during channelling.

## 4. AbilityProperty

New map built by parsing full `UpdateAbilityStats` decompile (`ap_switch_c.py`): `if (abilityID == X)` / `switch(abilityID)` and inner branches by `specialTag` (`stat+0x11`). Record `+= stat.added` — `add`, `ApplyMoreModifier` — `more-combine`, `0.1 < value` — bool flag. Verification: 483 pairs matched with old byte walk, match perfectly (0 diverges); 11 unresolved effects — Swipe(19), SummonBee(353), Rebuke(173), Focus(175).

For each effect in JSON: `field`, `fieldOffset`, `fieldOp` (add/more-combine/flag/set), `readers` (mutator classes reading this field in ISIL; selection by name token match with skill: possible false matches like Thorn/Shield-skill classes for ThornShield; starting point, not proof) and `plannerModel`:

| plannerModel | Effects | How to Model |
|---|---|---|
| skillDamage | 68 | `+value` to skill field (added/increased/more — by tooltip and `fieldOp`); mutator adds field to tree values |
| skillProc/chance | 52 | chance to cast linked ability (name in tooltip); ICD — in tooltip |
| skillMisc / skillConversion/mechanic | 39 / 38 | element conversion, skill replacement, bool toggle — on at `value > 0.1` |
| skillCount/charges, skillArea/range, skillCooldown, skillCost, skillDuration, skillCrit, skillSpeed, skillPenetration, skillDefence | 29/28/21/13/8/7/15/14/27 | summed in field; reader applies as addend to skill parameter |
| skillMechanicFlag | 26 | flag `\|=`, no magnitude |

General mechanism: all `AbilityProperty` stats with one (AbilityID, index) summed in `AbilityStatsMutatorManager` field; skill-mutator (`<Skill>Mutator.Mutate`) reads field at cast time. 07c describes fields written by trees; unique fields (`fireballPierceChance`, …) read by same methods.

## 5. Test Vectors

1. PP 146 (Vilatria's): Int 200 → added Lightning\|Spell Damage = 1.0·200·0.5 = 100.
2. PP 183 (Snowdrift): pp=0.01, Dex 300 → `min(0.2, 0.01·300·0.5)` = 0.15 → +15% MS.
3. PP 254/255 (Null Portent): pp254=−0.01, cap=0.3, Fire res 0.95 → `(0.95−0.75)/0.02 = 10` → x = −0.10 for fire damage.
4. PP 220 (Face of the Mountain): pp=0.01, Endurance 0.80 → `(0.80−0.6)/0.02·0.01` = +0.10 Block.
5. PP 69: maxHP 1000, HP 400, pp 0.2: Ward/s = (1000−400)·0.2 = 120.
6. PP 70: HP drops by `HP·(1−0.2·dt)`: ×0.8 in 1 s (at HP > 1).
7. PP 28: hit boss, `rand < 1.0`, ≥ 3 s since last cast → waterOrb; else no.
8. PP 161: cast void-melee skill at `cooldown ≤ 0` → +pp added Fire\|Melee, cooldown = 2 s; repeat void-melee in 1 s no bonus.
9. PP 462 (pp = 0.1): each hit independently 10% chance to nullify (M=0).

## 6. Unresolved / Where to Look Next

- **225 of 399 PlayerProperty effects marked D?**: formula from property name + code constants (ability ID, ICD, PTT, durations); exact chance/ICD/stat type check by `dump/work_wave3/pp_c/pp_<ppIndex>.txt` and `ctx.py CharacterMutator <method> <field>`.
- Temp stats from `ApplyConditionalTemporaryStats` (Stats.AddedStat/MoreStat): Ghidra loses float-args; for 161–164, 170, 173, 222–231, 234, 411, 419, 445, 506 type (added/inc/more) and tags from `statctor.py` (ISIL), `x2` values — field expressions, part unverified.
- PP outside switch: 126, 127, 190, 507, 528, 551, 630, 665 (potions/companions) — by name only; 309 «Endurance applies to all damage dealt to mana» read outside CharacterMutator.
- 28 etc. «chance» in tooltip on `flag` (30 Arek's Flesh): value 1.0 — flag, 100% chance.
- Tooltip/code divergence: PP 40 (ICD 2 s in text, 3 s in `.ctor`) — code taken.
- 215, 193, 141/142/149, 339, 566–568 (set count source), 621 (floor or not) — **D?**.
- AbilityProperty: 11 effects field unresolved (Swipe, SummonBee, Rebuke, Focus); rest semantics — by tooltip, line-by-line readers not analyzed (list `readers` — starting point).
- «Item → AbilityID» covers 31 abilities; rest `abilityIdOnly` (≈410) not bound to uniques: skill/Weaver/tree procs and monsters. LE Tools `itemDB.triggeredAbilities` (85 ID) wider: can cross-check by taking list from there.
- Components Chains_of_Uleros, Hollow_Finger etc without code — effect entirely in mods (see 07d).
