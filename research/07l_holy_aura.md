# 07l. Holy Aura (Last Epoch 1.5.0): Active Buff and Passive Aura

Skill: `Holy Aura` (AbilityID 187 `holyAura`, tree `ah443` / `HolyAuraTree`, Paladin mastery). Model in machine form: `research/data/game/holy_aura_model.json`.

Sources: `HolyAuraMutator` (ISIL: `.ctor`, `Mutate`, `OnMutatorUpdate`, local function `ApplyStatToAura|40_0`), `AuraMutator` (`.cctor`, `Mutate`), `HolyAuraTree.updateMutator`, `BuffOnAllyHit.Apply/addBuffToList`, `StatBuffs.addBuff(Buff)`, `Buff.generateName`, `AbilityStatsMutatorManager.UpdateAbilityStats` (case 0xBB), `KnightTree.updateMutator` (Paladin passives), type tree prefabs `HolyAura` and `Aura` (UnityPy). Ghidra did not run. Constants verified via `tools/readconst.py` and ISIL.

## 0. Brief Summary

1. These are two different mutations of the same set of buffs, not two different recipients. Recipients are the same: caster and all allies (including minions) in 20 m radius sphere around caster.
2. **Passive aura** (`AuraMutator.Mutate`) is cast automatically every 0.5 s, buff lasts 4.0 s and refreshes. Values: `v * M`.
3. **Active cast** (`HolyAuraMutator.Mutate`) during «boost window» (4 s, 6 s with Concentration) replaces passive casts. Values: default `v * 2 * M`, tree stats `(2v) * M` (tree makes a copy ×2, no second ×2 multiplier).
4. `M = 1 + X`, `X = mgr.holyAuraIncreasedEffect + increasedEffectFromPassives`. Only real source in 1.5.0: Paladin passive «Covenant of Light» (`Paladin Covenant`), +0.04 per point, max +0.20. Field `increasedEffectFromPassives` is effectively always 0.
5. Buff with same name on one actor is replaced, not stacked. So active cast covers passive, not adds to it (result exactly ×2 from passive values, not ×3).

## 1. Pipeline

### 1.1 Constants

| What | Value | Source |
|---|---|---|
| `auraStatsMultiplier` (k, +0x13C) | 2.0 | `HolyAuraMutator..ctor` (0x40000000), prefab 2.0, `HolyAuraTree.updateMutator` writes 2.0 again; no other writers |
| tree copy multiplier | 2.0 (hardcoded) | `HolyAuraTree.updateMutator`: `Stat.multiplyValues(0x40000000)`; does NOT read `auraStatsMultiplier` |
| `castInterval` (+0x1A4) | 0.5 s | `.ctor`, 0x3F000000 (not in prefab fields, serialized only for `auraStatsMultiplier`) |
| `passiveHolyAuraDuration` (+0x158) | 4.0 s | `.ctor`, 0x40800000 (= `basePassiveHolyAuraDuration` = `MAX_BUFF_DURATION`) |
| passive buff duration | 4.0 s | in `AuraMutator.Mutate` each `addBuffToList` gets constant 0x184561DD4 = 4.0 |
| boost window | `(1 + increasedBoostDuration) * 4` = 4 s / 6 s | `get_AuraBoostDuration`, `OnMutatorUpdate` |
| active buff duration | `clamp(window − timeSinceActiveCast + 0.6, 0.6, 4.0)` | `Mutate` (`castInterval + 0.1` = 0.6) |
| radius | 20 m | `SphereCollider` (trigger) on `HolyAura` and `Aura` prefabs (ability 190), scale 1. `AuraMutator.increasedRadius`/`duration` are dead |
| HitDetector | `ignoreCreator = 0`, `canApplyToSameAllyAgain = 0`, object lifetime 1 s | prefabs |
| Cooldown / mana | 10 s (1 charge, 0.1 charge/s) / 30 mana, instant cast | `abilities.json` |
| `HealthGlobe` radius | 30 m (0x41F00000) | `OnActorDeath` |

Cooldown calculated by general formula 06e §2.2: `CD = max(min, 1/regen)`, where `regen = (1 + moreCDR)(1 + incCDR)/((1 + incLength)(base + added))`. Concentration and Faith's Reward each give `addedCooldownLength = +5`, so base 10 → 15 → 20 s.

### 1.2 Computing X and M

```
X = mgr.holyAuraIncreasedEffect (+0x114C)  +  increasedEffectFromPassives
M = 1 + X
```

- `mgr.holyAuraIncreasedEffect` = sum of added-values of all `AbilityPropertyStat(holyAura, index 0)` from caster. `UpdateAbilityStats` case 0xBB, specialTag 0: `field += stat.added`. Global text: «increased Effect of Holy Aura».
  - Only source in 1.5.0 data: Paladin passive `Paladin Covenant` («Covenant of Light», id 119, max 5): `+0.04` per point (same point gives Sigils of Hope index 1). Range of X: 0..0.20.
  - In `affixes.json`, `uniques.json`, `idols`, `blessings`, `weaver_node_effects` — no modifier with ability 187 (only record: affix 601 «Level of Holy Aura», `LevelOfSkills`; doesn't affect buff count, skill has no `levelScaling` stats).
- `increasedEffectFromPassives` (`HolyAuraMutator +0x140`, `AuraMutator +0x134`): only `KnightTree.updateMutator` writes to it, value `0.1 * points` of node named `Paladin Increased Holy Aura Effectiveness`. Such node doesn't exist in tree data (`code_node_names_not_in_tree`), i.e. field = 0. Holy Aura's own tree doesn't touch this field.
- No generic «increased aura effect» / «increased buff effect» stat that affects Holy Aura. `frenzyTotemIncreasedEffectOfBuffs`, `dreadShadeIncreasedBuffEffect` belong to other skills. On recipient side `StatBuffs.addBuff` doesn't apply effect multiplier: stat from buff is added to recipient's `Stats` as normal.
- X and M are additive internally (`1 + a + b`), M multiplies stat value.

### 1.3 Passive Aura (`AuraMutator.Mutate`)

When: `HolyAuraMutator.OnMutatorUpdate` accumulates `t += dt`; when `t > 0.5` (and Holy Aura exists in actor's `AbilityList`) and boost window is not active, creates ability object 190 (`Aura`) at caster's position and resets `t`. If `inactiveWhileOnCooldown` (Concentration) is set and Holy Aura is on cooldown, passive cast skips.

Each object applies buffs to all allies in 20 m sphere (including caster) once (`canApplyToSameAllyAgain = 0`); new object created every 0.5 s, so buff constantly refreshes (replace by name, remainder 4.0 s).

Buff list (in order added; name identifier in parentheses):

| Buff | Value | Condition |
|---|---|---|
| ElementalResistance added | `0.15 * M` («default aura mutator») | `!disableDefaultStats` |
| Damage increased (tags 0) | `0.30 * M` («default aura mutator») | `!disableDefaultStats` |
| each stat from `AuraMutator.statsToApply` | `v * M` («aura mutator») | list not empty |
| ManaRegen increased | `mgr.holyAuraIncManaRegen * M` («extra aura mutator») | `holyAuraIncManaRegen != 0` |
| BlockEffectiveness added | `Strength * mgr.holyAuraBlockEffectivenessPerStrength * M` | `perStr > 0` and `stats` valid |
| Movespeed increased | `mgr.holyAuraIncreasedMovespeed * M` | `> 0` |
| StunAvoidance increased | `mgr.holyAuraIncreasedStunAvoidance * M` | `> 0` |

Flag `holyAuraPersonalMinionsOnly` (+0x1165) → `BuffOnAllyHit.onlyApplyToCreatorsMinions = 1`: buff received only by caster's minions (caster excluded, `IsMinionOf`).

For caster only (its `StatBuffs`, without M): if `canFlameBurst`, buff `AilmentChanceStat(HolyAuraStackForFlameBurst, Melee) = 9 + addedFieryInquisitionStacksOnMeleeHit`, 4 s (name «Aura Personal Flame Burst»). Additionally `holyAuraElectrifyChancePerSecondPerAttunement > 0` adds `RepeatedlyApplyAilmentsInRadius` (r = 10 m) with chance `Attunement * value * castInterval` to enemies.

### 1.4 Active Cast (`HolyAuraMutator.Mutate`)

When: player casts Holy Aura (30 mana, instant). On first cast `isRecastOfActive = false` and `timeSinceHolyAuraActiveCast := 0`. Then `OnMutatorUpdate` every 0.5 s, while `timeSince <= (1 + increasedBoostDuration) * 4`, recast active object (`isRecastOfActive = true`) instead of passive. After window return to passive cast; its buff with same names overwrites active (doubling ends within ≤ 0.5 s after window).

Duration: `D = clamp(window − timeSince + 0.6, 0.6, 4.0)`.

| Buff | Value | Condition |
|---|---|---|
| ElementalResistance added | `0.15 * k * M` = `0.30 * M` | `!disableDefaultStats` |
| Damage increased | `0.30 * k * M` = `0.60 * M` | same |
| each stat from `HolyAuraMutator.statsToApply` | `(2v) * M`, where `2v` already counted by tree; no second k multiplier | list not empty |
| ManaRegen increased | `holyAuraIncManaRegen * k * M` | `!= 0` |
| BlockEffectiveness | `Strength * perStr * k * M` | `perStr > 0` |
| Movespeed | `holyAuraIncreasedMovespeed * k * M` | `> 0` |
| StunAvoidance | `holyAuraIncreasedStunAvoidance * k * M` | `> 0` |
| HealthRegen added | `holyAuraHealthRegenInActiveMode * M` (WITHOUT k) | `> 0`, active only |
| PlayerProperty 450 (slow/chill immunity) | `1.0 * M` (boolean by meaning) | `holyAuraActiveSlowImmune` or `holyAuraActiveChillImmune` |

For caster only, without M: if `canFlameBurst` `AilmentChanceStat(HolyAuraStackForFlameBurst, Melee) = k*9 + addedStacks` (i.e. 18 + added), duration `D`.

Only on first cast (not on recasts): `wardGainedOnActivation` (GiveResourcesOnHit.wardOnHit), `activeCleanse` (CleanseAilmentsOnHit: all negative, allies), `mgr.holyAuraMoreIgniteDamageOnActivation` (`AmplifyDamageOfAilmentOfType(Ignite, value, onlyFromSpecificActor = caster)` to enemies with Ignite in Manhattan distance < 20 m from caster).

Each tick (0.5 s): `chanceToSlowEnemiesEverySecond * castInterval` chance to slow enemies hit by object; flags fear (r = 10 m), blind, reset of Evade/Traversal cooldowns taken from manager (`holyAura*`).

### 1.5 How Buff Goes Into Stats

`BuffOnAllyHit.Apply(actor)`: for each `Buff` from list makes copy and calls `StatBuffs.addBuff(Buff)`. That first `removeBuffsWithName(name)`, then adds buff and calls stat addition to actor's `Stats`. Name: `Buff.generateName(identifier, stat)` = format from seven fields: `identifier`, `SP`, `AT`, `specialTag`, `extraTag`, `added>0`, `increased>0`.

Consequences:
- Active and passive buff of same stat have same name, so active replaces passive (not stacked).
- Default («default aura mutator») and tree stat («aura mutator») have different identifiers: ER 0.15*M and ER +5%/point sum as two different addeds.
- Edge case: «Block Effectiveness per Strength» (`AddedStat(BlockEffectiveness, tags 0)`) has same name as Mighty Shield node, added later, so REPLACES node value, not adds. No such property source in 1.5.0 data.

## 2. Numerical Examples

Notation: p = node points, M = 1 + X, values «increased»/«added» as fractions (0.15 = 15%).

**Example A: Defaults only, X = 0**

| | Passive | Active |
|---|---|---|
| ElementalResistance added | 0.15 | 0.30 |
| Damage increased | 0.30 | 0.60 |

**Example B: Covenant of Light 5/5 (X = 0.20, M = 1.2), Fanaticism 3/3, Shelter from the Storm 5/5, Firestorm 5/5**

| Stat | Formula passive | Passive | Active |
|---|---|---|---|
| ER (default) | `0.15 * 1.2` / `0.30 * 1.2` | 0.18 | 0.36 |
| Damage increased (default) | `0.30 * 1.2` / `0.60 * 1.2` | 0.36 | 0.72 |
| AttackSpeed / CastSpeed increased | `0.03*3 * 1.2` / `0.18 * 1.2` | 0.108 each | 0.216 each |
| ER (node) | `0.05*5 * 1.2` / `0.50 * 1.2` | 0.30 | 0.60 |
| Endurance added | `0.03*5 * 1.2` / `0.30 * 1.2` | 0.18 | 0.36 |
| Damage increased, Fire | `0.10*5 * 1.2` / `1.00 * 1.2` | 0.60 | 1.20 |
| Damage increased, Lightning | same | 0.60 | 1.20 |

Total ER for recipient: passive 0.18 + 0.30 = 0.48, active 0.36 + 0.60 = 0.96 (before resistance cap).

**Example C: B + Flame Burst 1/1, Inner Flame 2/2, Purification 1/1, passive Covenant of Dominion (holyAuraIncManaRegen = 0.25)**

| Stat | Passive | Active |
|---|---|---|
| ManaRegen increased | `0.25 * 1.2` = 0.30 | `0.25 * 2 * 1.2` = 0.60 |
| PoisonResistance added | `0.2 * 1.2` = 0.24 | `0.4 * 1.2` = 0.48 |
| HolyAuraStackForFlameBurst chance (allies) | `1 * 1.2` = 1.2 | `2 * 1.2` = 2.4 |
| caster personal buff (without M) | 9 + 2 = 11 | 18 + 2 = 20 |

## 3. Which of Previous Reports Is Correct

- **07j** (`HolyAuraMutator.statsToApply` + `defaultStats × 2.0`, tree copy ×2 not multiplied again; ER +0.15, Damage +0.30): correct for active path. Incomplete: no multiplier `(1+X)`, no passive `AuraMutator.Mutate` (not analyzed), no extras and timings.
- **07h** (`ApplyStatToAura`: clone, ×`auraStatsMultiplier` if flag, always ×`(1+X)`): correct. Flag true for defaults and extras (mana regen, block/Str, movespeed, stun avoidance), false for tree list, health regen and immunity. Clarification: `X` formed in `Mutate` as `mgr +0x114C + increasedEffectFromPassives`, so phrase «`increasedEffectFromPassives` not read in this function» is true only for the local function itself (it receives ready X).
- **07c** (node puts stat in `AuraMutator.statsToApply`, copy ×2 in `HolyAuraMutator.statsToApply`): correct. Open question «where copy ×2 goes» closed: recipients are same (caster and allies in 20 m); differs only in timing (passive constantly, active in boost window).
- **Haiku Draft** (`dump/work_wave4/holy_aura.md`): mostly incorrect.
  - Active buff «player only», passive aura «allies only»: wrong, `ignoreCreator = 0`, both paths hit all in sphere.
  - Field `increasedEffectFromPassives` called «increased aura effect» from tree: wrong, always 0; real X from `mgr.holyAuraIncreasedEffect` (Covenant of Light).
  - Three «paths» actually two (passive ×1, active ×2), defaults «×2 in active only» correct, but same applies to extras.
  - 0.5 s / 4.0 s, buff replace by name, boost window, special caster buffs not accounted.
  - Offsets: `AuraMutator +0x134/+0x120/+0x158` named correctly; `HolyAuraMutator +0x158` is actually `passiveHolyAuraDuration` (float 4.0), not `StatBuffs` reference; `+0x1A4` is `castInterval` (0.5), not «extra modifier».
  - Correct in draft: formulas `v * (1 + X)` for passive, «defaults ×2 in active only», `(2v) * (1+X)` for tree stats in active.

## 4. Holy Aura Tree Nodes (Final Formulas)

`p` = node points. For stat nodes: passive = `raw * p * M`, active = `2 * raw * p * M` (float `raw` below per point). All 27 stat entries verified automatically: value in `HolyAuraMutator.statsToApply` is exactly double of value in `AuraMutator.statsToApply`.

| id | Node (Display Name) | max | Stat / Field | passive per point | active per point |
|---|---|---|---|---|---|
| 2 | Flame Burst | 1 | `canFlameBurst`; AilmentChance HolyAuraStackForFlameBurst (Melee) | 1.0*M | 2.0*M; personal buff 9+stacks / 18+stacks |
| 3 | Improved Flame Burst | 4 | `finalHitDamageMultiplier` | +50% more on Holy Flame Burst per point (not buff) | same |
| 4 | Fanaticism | 3 | AttackSpeed inc, CastSpeed inc | 0.03*M | 0.06*M |
| 5 | True Strike | 4 | CriticalChance inc | 0.10*M | 0.20*M |
| 6 | Extreme Zeal | 3 | CriticalMultiplier added | 0.05*M | 0.10*M |
| 7 | Firestorm | 5 | Damage inc (Fire), Damage inc (Lightning) | 0.10*M | 0.20*M |
| 8 | Rahyeh's Devotion | 3 | AilmentChance Ignite, Electrify | 0.05*M | 0.10*M |
| 9 | Rahyeh's Fury | 2 | Penetration added (Fire), (Lightning) | 0.05*M | 0.10*M |
| 10 | Call To Arms | 5 | Damage inc (Physical) | 0.10*M | 0.20*M |
| 11 | Strength From Afar | 4 | Damage inc (Throwing), IncreasedStunChance (Throwing) | 0.12*M | 0.24*M |
| 12 | Shelter from the Storm | 5 | ElementalResistance added; Endurance added | 0.05*M; 0.03*M | 0.10*M; 0.06*M |
| 13 | Swiftness | 3 | DodgeRating added | 20*M | 40*M |
| 14 | Redemption | 4 | IncreasedHealing added | 0.10*M | 0.20*M |
| 15 | Concentration | 1 | `increasedBoostDuration` +0.5, `inactiveWhileOnCooldown`, +5 s cooldown | window 6 s; passive disabled on cooldown | without M and k |
| 16 | Purification | 1 | `activeCleanse`; PoisonResistance added | 0.2*M | 0.4*M (+ cleanse on first cast) |
| 17 | Demoralizing Aura | 2 | `chanceToSlowEnemiesEverySecond` | passive only | 0.25*p slow chance on object (0.5*p per second), without M and k |
| 18 | Expedite | 3 | AttackSpeed inc (Throwing); HasteOnHitChance added | 0.03*M | 0.06*M |
| 19 | Vital Boon | 4 | HealthRegen increased | 0.10*M | 0.20*M |
| 20 | Faith | 5 | WardRegen added | 3*M | 6*M |
| 21 | Shielded By Faith | 4 | WardRetention added | 0.05*M | 0.10*M |
| 22 | Faith's Reward | 1 | `wardGainedOnActivation` +400, +5 s cooldown | doesn't work | 400 ward on first cast, without M and k |
| 23 | Mighty Shield | 4 | BlockEffectiveness added; HealthGain on block (specialTag 6) | 30*M; 2*M | 60*M; 4*M |
| 24 | Against The Odds | 3 | WardGain on block (specialTag 6) added | 7*M | 14*M |
| 26 | Hope | 1 | `healthGlobeOnNearbyEnemyDeathChance` | 12% chance globe on enemy death in 30 m | doesn't depend on cast |
| 28 | Inner Flame | 2 | `HolyFlameBurstMutator.increasedArea` +25%/point; `addedFieryInquisitionStacksOnMeleeHit` +1/point | personal buff 9+p | 18+p |

Full list with SP-names, tags and value type in `research/data/game/holy_aura_model.json`, key `nodes`.

## 5. Unknown

- Scale/delivery of `GiveResourcesOnHit` (400 ward): component added to ability object, exactly who (caster only or all allies) determined by prefab `GiveResourcesOnHit` flags (default behavior not traced).
- Real sources of `mgr.holyAuraIncManaRegen`, `holyAuraIncreasedMovespeed`, `holyAuraIncreasedStunAvoidance`, `holyAuraBlockEffectivenessPerStrength` and flags (slow/chill immune, fear, blind, minions-only etc): in 1.5.0 data only Paladin passives for indices 0, 1 (Covenant of Dominion, ≥ 5 points, 0.25) and 2 (Sword of Rahyeh, ≥ 5 points, 0.5); other indices not found in affix/unique data.
- What virtual call `AbilityList +0x208` (signature `hasAbilityEquipped(Ability)`/`hasAbility`) does exactly: treat as condition «Holy Aura present in ability list».
