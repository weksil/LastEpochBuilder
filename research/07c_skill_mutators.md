# 07c. Skill trees: how nodes change skill (client 1.5.0)

Source: ISIL/Cpp2IL disassembler (`dump/isil/IsilDump/LE/<X>Tree.txt`), constants read directly from `GameAssembly.dll`. Pseudo-C from Ghidra used for manual verification. Tool: `tools/extract/mutator_coeffs.py` + `tools/extract/isil_sym.py`. Result: `research/data/game/skill_node_effects.json`.

## Brief

> Patch (07f): two defects fixed in `isil_sym.py`: `xorps xmm,[sign mask]` now negation (was `x ^ -0.0`), arithmetic `sub/add/and/or/xor` update flags (was stale flags after `sub rcx,1; je`). Recount results: auto 3568, auto_combined 212, auto_formula 29, conditional 2, manual 5, none 4. 7 nodes changed, e.g. Acid Flask Poison Pool base cooldown 6.0 → 2.0 (matches tooltip), Flay Cold/Necrotic/Poison Conversion now has Bleed conversion.

- **Node logic lives in `<Skill>Tree` / `<Skill>SkillTree` classes, not `<Skill>Mutator`.** 141 such classes (plus 6 character class trees, out of scope). Each contains static `updateMutator(LocalTreeData, TreeData)`. Mutator only stores fields reads them on cast (`getTempStats`, `Mutate`, `OnHit`…). **D**
- Coefficients per point — **float literals in code** (`.rdata` section), not ScriptableObject. Exception — 39 nodes with `AutomaticNodeStat` (`nodeStatsData` in Global Tree Data). Applied separately via `UpdateGlobalStatsFromTree` (06a §7.2). **D**
- Node identified **by name** (string `switch`: FNV-1a `ComputeStringHash` + `String.Equals`), points from `NodeData.points` (byte at `+0x11`). Node IDs not used in code, renamed node stops working. **D**
- Automation covered 136 active trees and 3820 nodes. 8 obsolete trees without UI and ability (07b) analyzed but not in stats (§6). Results:

| Status | Nodes | Meaning |
|---|---|---|
| `auto` | 3568 (93.4%) | All effects resolved, linear in p, effects of different nodes simply sum |
| `auto_combined` | 212 (5.5%) | Effect resolved, field computed **non-linear formula of multiple nodes** (formula in `after_loop.formulas`) |
| `auto_formula` | 29 (0.8%) | Value — known non-linear function of p (`sqrt(1+k·p)−1`, `1/(1+k·p)−1`, `pow`) |
| `conditional` | 2 | Different behavior depending on p (e.g. clamp) |
| `manual` | 5 | Needs manual parse (§5) |
| `none` | 4 | No solo effect: 3 dead nodes and 1 flag-node working only in pair (§5) |

- Verification:
  - Numbers from node tooltips (`tree_node_stats.json`) found among code coefficients at **2506** nodes, partly at 606, none at 252. Mismatches mostly explainable: tooltip shows mutator constants ("limit 2 per 4 s"), area-to-radius recalc or tick breakdown.
  - Ghidra constants in node block found in extraction at **2469 of 2565** nodes. Manual sample of remaining 96: either block overlap in my rough Ghidra carving or collapsed products (`0.4·0.25 → 0.1`).
  - Found **one case where Ghidra wrong**: Infernal Shade "More Damage and Reduced Duration". Ghidra shows −0.12 and 0.2. By asm `mulss xmm0,[18471CDECh]` and `[18471DD70h]` values −0.1 and 0.18, matches tooltip (18% / 10%). **Finding: float literals from Ghidra pseudo-C cannot be trusted without binary verify.**

## 1. How tree applies to skill

`LocalTreeData.updateMutator(ability, treeData)` @0x1816c8140:
1. `UpdateGlobalStatsFromTree` — `AutomaticNodeStat` nodes to global stats (06a §7.2).
2. `switch (AbilityManager.GetAbilityID(ability))` → `<X>Tree.updateMutator(localTreeData, tree)`. If no tree, logs "no tree found for …".

Typical `<X>Tree.updateMutator` (verified by ISIL on Fireball, Rive, Summon Skeleton, Rip Blood, Tempest Strike, Flurry, Holy Aura, etc.):
```
mut  = GetComponentInChildren<FireballMutator>()     // or GetComponentsInChildren<T>() → array (combo skills)
listA = new List<Stat>(); ...                        // sometimes list directly into mutator field
locals = 0
foreach (node in tree.nodes) if (node.points > 0):
    switch (GlobalTreeData.getTreeData(id).getNode(node.id).name):    // by name!
        case "Fireball Cast Speed":  castSpeed += p * 0.05
        case "Fireball Ignite Chance": listA.Add(new Stat(AilmentChance, 0, Ignite, p * 0.3))
        case "Fireball Homing": homing = true
        ...
// after loop:
mut.increasedCastSpeed = castSpeed; mut.unconditionalTempStats = listA; ...
mut.SetCooldown(...)/GiveCooldown(...)      // virtual, slots vtable 0xC48/0xC58
resummonCompanions(...)                     // summons
```
Important for engine:
- **Inside node points scaled linearly** (`p·k`). Multiple nodes writing to one local **sum**, then result once written to field. Non-linearity only in after-loop code (`after_loop.formulas`).
- **Fixed effects exist** (`flat`), independent of p, even on nodes with maxPoints > 1 (§4.4).
- `List<Stat>` lists become mutator fields (`unconditionalTempStats`, `statsWhileChannelling`, minion stat list, etc.). Mutator outputs them as cast temp stats (`getTempStats`) or attaches to minions.
- Stat types nodes create:
  - added 725, more 521, increased 191, ailment chance 162, ailment conversion 42, ailment duration 20, etc.;
  - **damage stats: more 429, added 79, increased 38.** Confirms rule 06a §7.3 that "increased" in tree almost always works as more. Exceptions (increased damage) listed individually in JSON.
- Mutator field name doesn't say modifier type. Fields `increased*` for damage in 13 cases mutator turns to **more** (`getTempStats: Damage more`), in 11 — increased. Use `field_usage_hints`, not name.
- Cooldown. AbilityMutator fields:
  - `+0xC8 addedCharges`, `+0xF8 increasedCooldownRecoverySpeed`, `+0xFC moreCooldownRecoverySpeed`, `+0x100 increasedCooldownLength`, `+0x104 addedCooldownLength`, `+0x108 overriddenBaseCooldownLength`.
  - `SetCooldown(addedCharges, moreCDR, incCooldownLength[, addedCooldownLength, incCDR])` @0x1823fb2a0/0x1823fb2d0.
  - `GiveCooldown(charges, baseCooldownLength, moreCDR, incCooldownLength, incCDR)` @0x1823fa5c0 sets `addedCharges = charges − ability.maxCharges` overrides base cooldown.
  - In JSON these effects `op:"cooldown"` (108 nodes, 45 via `GiveCooldown`, node gives skill cooldown). **D**

## 2. Tool `tools/extract/mutator_coeffs.py`

Symbolic executor ISIL (`isil_sym.py`): registers, stack, memory, symbolic values.
1. **Prologue** runs before `MoveNext` gives state at loop entry: which slots hold mutators (type from `MethodInfo` at `GetComponentInChildren<T>`) and lists.
2. **Loop body** runs **per tree node** with real name. FNV-1a hash computed, `String.Equals` evaluated concrete, `switch` traversed deterministic, points stay symbol `p ∈ [1, maxPoints]`.
3. **Tail after loop:**
   - (a) with symbolic accumulators — get formulas `field = f(acc…)`;
   - (b) after single node pass — get effect "in isolation" vs baseline without nodes.
4. Manually handled:
   - null checks (branches throwing exceptions discarded), `op_Implicit` (Unity object considered existing), inline `List.Clear`;
   - `foreach` over lists assembled in method (iterate real elements);
   - arrays `GetComponentsInChildren` (simulated as two instances `T` and `T#2`), `SzArrayNew`, copy ctor `Stat(Stat)`, `Stat.multiplyValues`, field writes on Stat after ctor, `moreValues.Add`;
   - virtual calls: vtable slot resolved via `il2cpp-types.h`, base vtable `Il2CppClass+0x138` (verified: 0xC48 → `SetCooldown`, 0xC58 → `GiveCooldown`);
   - `powf`, `sqrtf`, `Math.Round`;
   - constants Cpp2IL prints as `typeof(C)`, and operands `lea r,[idx*k]` printed as `[]`: recovered via binary alignment.
5. Hints per mutator field: straight pass over all methods `<X>Mutator`. Tracked what `this.field` goes into Stat constructors (`feeds_stat`) and which methods read field (`read_in`). Hints exist for 3012 of 4372 written fields, `feeds_stat` for 349.

Time ~20 s. Script re-runs after patch without changes (names and offsets from dump).

### Schema `skill_node_effects.json`
Array of trees:
```
{ tree, treeID, class, orphan?, mutators[], errors[],
  nodes: [ { id, name, displayName, maxPoints, status, review[],
             effects: [ ... ],                 // node effect alone (exact)
             accumulators: [ {acc, op:add|set|expr, per_point, flat, feeds[]} ],  // loop local contribution
             combined_formula_fields?, tooltip[], tooltip_check{tooltip_numbers, matched, unmatched},
             unimplemented?, manual_note? } ],
  after_loop: { formulas{ field|"LIST …"|"CALL …": [{expr, when?}] },   // field = f(acc[...])
                baseline_fields, baseline_stats, baseline_calls, loop_carried[] },
  field_usage_hints{ "Mutator.field": {feeds_stat[], read_in[]} },
  code_node_names_not_in_tree[] }
```
Effect types:
- `{target:"XMutator.field", type, value:{per_point, flat} | {expr}}` — field value after `updateMutator`, equals `flat + per_point·p`. For bool: `flat 1` = flag on.
- `{op:"add_stat", target:"XMutator.list", stat:{property, tags, specialTag/ailment, extraTag, kind: added|increased|more|ailment_chance|…, added|increased|more|value:{per_point,flat}, more_values[], multiplied_by?}}`.
- `{op:"cooldown", target, method, args{…}}`, `{op:"proc_limit"}` (`ProcTimeTracker.ChangeLimit`), `{op:"automatic_node_stat", property, tags, modType, value, scaling, threshold}`, `{op:"list_add"}`, `{op:"call"}` (unmodeled call, manual only).
- `when` — variant condition (branch by p, etc.).
- `acc[reg:xmm13]` / `acc[stk:0x8C]` — loop local (register or stack). To get multi-node result:
  1. sum `accumulators` contributions of chosen nodes into each `acc`;
  2. plug sums into `after_loop.formulas`.

  For `auto` nodes formula is `acc` itself or its linear combo, so just sum `effects`.

## 3. Verified examples (manually, ISIL ↔ Ghidra ↔ tooltip)
| Node | Code | Tooltip |
|---|---|---|
| Fireball Projectile Speed And Damage | `increasedSpeed += 0.07p`; `Stat(Damage, more 0.07p)` → unconditionalTempStats (Fireball + FireballExplosion) | +7% / +7% |
| Fireball Mana Cost And Damage | `addedManaCost −= 1·p`; `Stat(Damage, more 0.03p)` | +3% damage, −1 mana |
| Fireball Protection While Channelling | `statsWhileChannelling += FireRes added 0.15p, Armour added 30p` (06a knew only FireRes) | +30 armor, +15% |
| Fireball Crit Chance Reduced Cast Speed | `Stat(CritChance, added 0.04p)` created in tail; `moreCastSpeed` = −0.05p, enters formula `((extra·k_seq + 1)·(1 + Σ)) − 1` with Projectiles In Sequence | +4% / −5% |
| Rive Bleed Chance And Duration | `AilmentChance(Bleed, 0.25p)` + `AilmentDuration(Bleed, 0.1p)` to all 3 strike mutators | |
| Summon Skeleton Health and Damage | `Stat(Health, more [0.15p])` → warriorStatList, `Stat(Damage, more [0.15p])` → archer/rogue | "+15%" (code more) |
| Rip Blood Area | `increasedRadius = sqrt(1+0.25p)−1` (`EpochExtensions.AreaToRadius`) | +25% area |
| Storm Totem Added Crit Multi | `new Stat(CritMulti)`, then `stat.addedValue = 0.3p` | +30% |
| Holy Aura (Attack and Cast Speed, etc.) | stat goes to `AuraMutator.statsToApply`, its copy after `multiplyValues(2.0)` — to `HolyAuraMutator.statsToApply` | |
| Disintegrate Chance to Slow | `chanceToSlow += p·0.4·0.25` (= 0.1p per 0.25 s tick) | +40% per second |

## 4. Non-trivial mechanics (what engine must implement)

### 4.1 Area → radius (88 nodes)
`EpochExtensions.AreaToRadius(x)` @0x1810dbca0 = `sqrt(1 + x) − 1`. Code sums "increased area" all nodes in local **after loop** once converts to `increasedRadius`. So area-nodes can't sum by radius: area sums first, then `sqrt`. This is `auto_combined`. Formula in `after_loop.formulas`, e.g. `NovaMutator.increasedRadius = sqrt(acc+1)−1`. **D**

### 4.2 "Non-X damage" via compensating more (11 nodes)
Scheme:
- general `Stat(Damage, more k·p)`;
- for excluded part separate `Stat(Damage, tags X, more 1/(1+k·p) − 1)`, cancels bonus.

Examples:
- Meteor "Non Fire Damage": Fire excluded;
- Volcanic Orb (Orb Damage, etc.): orb bonus canceled in `shrapnelTempStats` / `fireCircleTempStats`;
- Spirit Plague More Damage: excluded `Necrotic|DoT`;
- Rip Blood Upfront Damage. **D**

### 4.3 "Doubled when condition" (8 nodes)
Base part goes normal stat `Stat(Damage, more k·p)`. In mutator field (e.g. `VengeanceMutator.moreDamageToLowHealth`) written `Maths.GetDifferenceModifierForMultiplyingModifier(k·p, 2)` = `(1 + 2kp)/(1 + kp) − 1`. This extra more applied by mutator only when condition (low or high health, 2h, recent block…). Together exactly `1 + 2kp`. Nodes:
- Nova Base Elemental Damage;
- Vengeance ×2;
- Erasing Strike Damage And Mana Cost;
- Shurikens Chakram;
- Javelin High Health;
- Upheaval No Attack Speed Scaling;
- Flay Doubled Against Low. **D** (helper formula from Ghidra @0x1812be7a0).

### 4.4 Effect doesn't grow with points
7 nodes with maxPoints > 1 value independent of p:

| Node | maxPoints | Value |
|---|---|---|
| Fireball Increased Duration | 4 | `+0.1` |
| Tornado Casts Lightning Faster | 4 | 2.0 |
| Fury Leap Casts Lightning Faster | 5 | 0.25 |
| Aura of Decay Poison Nova On Activation | 3 | 0.02 |
| Summon Skeleton Mage Frenzy On Hit | 3 | 0.1 |
| Death Seal Culling | 2 | 0.08 |
| Smoke Bomb Shadow Dagger On Slow | 2 | 0.35 |

For Fireball confirmed by Ghidra (`fVar18 + 0.1` no point multiplier). Probably bug: tooltip ""+10% per point"". Engine reproduces code. **D**

### 4.5 Scaling by ticks and hit frequency
- Disintegrate: `p·0.4·0.25` — chance per sec × 0.25 s tick.
- Warpath / Bladestorm: `p·k/0.6` — ailment chance divided by 0.6.
- Value in JSON already folded (0.1p, 0.5p, etc.). **D**

### 4.6 Stat clones with multiplier
Holy Aura puts each node stat in `AuraMutator.statsToApply` (allies), its copy after `Stat.multiplyValues(2.0)` — to `HolyAuraMutator.statsToApply` (probably self, verify in mutator). 19 nodes, field `multiplied_by`. **D?**

### 4.7 Nodes working only in combination
Node just places value in local, after loop used only if condition dependent on other nodes. Alone such nodes nothing. Visible in `accumulators[].feeds` and `after_loop.formulas`:
- Nova Extra Charge / Cooldown Recovery: `GiveCooldown(charges, …)` called only if cooldown given other node (`0 < fVar18`);
- Infernal Shade Cooldown Recovery, Detonating Arrow Plus Charges, Shadow Rend Added Charges, Runic Invocation Cooldown Recovery.

### 4.8 Combos and multiple mutators
Many skills write same to multiple mutators:
- Rive: 3 hits, `Rive/Rive2/Rive3Mutator`;
- Tempest Strike: 6 mutators;
- Fireball + FireballExplosion;
- Flurry, Dive Bomb, Swipe: arrays `GetComponentsInChildren<T>`.

Stat lists often shared (`target` contains `A & B`). Total 214 different mutator classes involved.

### 4.9 Cooldowns and charges
108 nodes give `op:"cooldown"` effect. 45 call `GiveCooldown` thus **add cooldown to skill**. Examples:
- Javelin Rain Is Flag: 1 charge, 6 s;
- Shield Rush Adds Charges: p charges, 10 s.

`RemoveCooldown` removes cooldown (Focus No Cooldown, Werebear, etc.). Arguments — linear expressions of p, in general formulas from multiple nodes (`CALL …` in `after_loop.formulas`).

### 4.10 Other
- `pow(p, 0.6)`: Flame Reave Crit Narrow, `moreGrowth = −0.16·p^0.6`.
- Clamp: Tornado Double Cast, `pullMultiplier = max(0, 1 − 0.25p)` (status `conditional`).
- `toInt(18/p)`: Infernal Shade Scaling Minion Stats.
- Integer `lea`/`shl`: Reaper Form "Grant Ward on Transform to Reaper" = `40·p` (`(p + 4p) << 3`).

## 5. Need manual parse (7 manual, 2 conditional, 4 none)
Clarifications from this table in JSON field `manual_note` (`MANUAL_NOTES` in script)
| Tree / node | What code does | Why not auto |
|---|---|---|
| Elemental Nova / Lightning Nova | `canLightningNova = (condition via setcc)`, Damage more 0.07p | `sete` not modeled |
| Rip Blood / Bleed Chance | `AilmentChance(Bleed)` in two lists, one value depends on other accumulator | stat after loop with formula |
| Flame Reave / Lightning Conversion | `lightningConversion = true` and local function `AddMirroredLightningStats`: mirrors fire tree stats to lightning | local function not traced; list functions for manual decompile below |
| Summon Bone Golem / Twins | `twins`, `increasedSize −0.35p`, Damage more −0.45p, Health more −0.25p; recount reconstructs live golems (`constructAbilityObject`, `unsummon`) | side effects; stats determined correctly |
| Rebuke / Elemental Protection | `DamageTaken` (Elemental) more: formula from multiple accumulators | formula in `after_loop` |
| Frost Wall / Casts Runebolts Matching Wall Type | `firesRunebolts = true`, `RuneboltMutator.frostWallBolt = Ability.getAbility(693)` | ability ref, not number |
| Runebolt / Reversed Combo | `reversedComboOrder = true` in 3 mutators, plus `ResetComboIndex()` | side call; flag determined correctly |
| Tornado / Double Cast (cond) | `doubleCastChance += 0.25p`; `pullMultiplier = max(0, 1−0.25p)` | clamp |
| Smoke Bomb / Smoke Blades (cond) | `smokeBladesStacksPerSecondToAllies = 1`; `increasedSmokeBladesEffectiveness = p−1` when p > 1 | branch by p |
| Manifest Armor / Reflects Damage Per Attunement, Chance To Slow When Hit (none) | `String.Equals` present, result discarded (Ghidra confirms) | **nodes do nothing in `updateMutator`**; search in `ManifestArmorMutator` / minion |
| Devouring Orb / Rift AoE Growth (none) | node name not in code | **node dead** (tooltip: "+20% Hit Damage To Time Rotting") |
| Reaper Form / Grant Ward on Transform to Human (none) | flag only; after loop `ReaperFormMutator+0x144 = flag ? (ward of "…to Reaper" node) : 0` | works only together with "Grant Ward on Transform to Reaper" (40·p); flag didn't make accumulators |

Bladestorm: Global Tree Data has **two** "Bladestorm" trees. Working — `bl5st`. Obsolete `bs6d9` 15 nodes "Bladestorm Small Node (N)": code logs "is allocated but has no implementation" (status `unimplemented`).

## 6. Data and link to trees
- Tree matched to class via `uiClass` from `trees.json`, or if missing — intersection of node names with class literals. All `*Tree.updateMutator` classes matched. Not covered: Acolyte/Knight/Mage/Primalist/RogueTree (passive class trees, also have `updateMutator` for "special" passives) and empty `EphemeralStanceTree` (one-root tree).
- Obsolete trees (`orphan: true`; in 07b these 8 GTD with version 0 no UI): Fire Shield, Thorn Burst, Ice Ward, Mark For Death, Manifest Weapon, Ephemeral Stance, "Abyssal Echoes" empty treeID (Frost Wall copy) and "Bladestorm" `bs6d9`.
  - Code for some still exists: FireShieldSkillTree, IceThornsTree, IceWardSkillTree, MarkForDeathTree, ManifestWeaponTree.
  - Analyzed and in JSON, not in stats and §7 table.
- 39 nodes with `AutomaticNodeStat` come as `automatic_node_stat` effect (modType, scaling `PerPoint|None|Threshold`). Applied globally via `UpdateGlobalStatsFromTree`, not via mutator. `extraTag` — AbilityID (name from `AbilityID.cs`).

## 7. Skill summary
`auto_combined` = field depends on multiple nodes non-linearly; "Fields with non-additive formula" — which fields (formulas in `after_loop.formulas`).

| Tree | Tree class | Mutators | Nodes | auto | auto_combined | auto_formula | manual/none/cond | Non-linear mechanics | Fields with non-additive formula |
|---|---|---|---|---|---|---|---|---|---|
| Abyssal Echoes | AbyssalEchoesTree | 1 | 30 | 24 | 6 | 0 | 0 | cooldown x1, area->radius, AutomaticNodeStat | LIST unconditionalTempStats, increasedRadius |
| Acid Flask | AcidFlaskTree | 1 | 28 | 27 | 1 | 0 | 0 | cooldown x1 | CALL GiveCooldown |
| Aerial Assault | AerialAssaultTree | 5 | 31 | 27 | 3 | 1 | 0 | cooldown x1 | moreFeatherBurstDamageToRareAndBoss, moreFeatherstormDamageToRareAndBoss |
| Anomaly | AnomalyTree | 1 | 29 | 27 | 2 | 0 | 0 | cooldown x3, area->radius | increasedRadius, increasedTimeWaveRadius |
| ArcaneAscendance | ArcaneAscendanceTree | 1 | 23 | 23 | 0 | 0 | 0 | cooldown x2 | - |
| Assemble Abomination | AssembleAbominationTree | 1 | 30 | 29 | 1 | 0 | 0 | area->radius | increasedRadiusForMeleeSkills |
| Aura Of Decay | AuraOfDecayTree | 1 | 29 | 25 | 4 | 0 | 0 | area->radius | increasedRadius, timeToGainFester, timeToLoseFester |
| Avalanche | AvalancheTree | 2 | 27 | 24 | 2 | 1 | 0 | cooldown x1, area->radius | increasedDamageRadius |
| Ballista | BallistaTree | 2 | 29 | 29 | 0 | 0 | 0 | - | - |
| Black Hole | BlackHoleTree | 1 | 28 | 27 | 1 | 0 | 0 | cooldown x2, area->radius, AutomaticNodeStat | lessPullRadius |
| Bladestorm | BladestormTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Bone Curse | BoneCurseTree | 1 | 31 | 28 | 3 | 0 | 0 | cooldown x3, area->radius | auraMode, increasedRadius |
| Chaos Bolts | ChaosBoltsSkillTree | 1 | 28 | 23 | 5 | 0 | 0 | - | LIST minionBuffStats |
| Chthonic Fissure | ChthonicFissureTree | 2 | 30 | 30 | 0 | 0 | 0 | cooldown x1 | - |
| Cinder Strike | CinderStrikeTree | 3 | 27 | 27 | 0 | 0 | 0 | - | - |
| Dagger Dance | ShadowCascadeTree | 1 | 27 | 27 | 0 | 0 | 0 | - | - |
| Dancing Strikes | DancingStrikesTree | 2 | 31 | 31 | 0 | 0 | 0 | - | - |
| Dark Quiver | DarkQuiverTree | 2 | 32 | 32 | 0 | 0 | 0 | - | - |
| Death Seal | DeathSealTree | 2 | 30 | 29 | 1 | 0 | 0 | area->radius | increasedDeathWaveRadius |
| Decoy | DecoyTree | 6 | 27 | 27 | 0 | 0 | 0 | cooldown x2 | - |
| Detonating Arrow | DetonatingArrowTree | 1 | 30 | 22 | 8 | 0 | 0 | cooldown x1, area->radius | LIST unconditionalTempStats, moreExplosionHitDamage, moreExplosionRadiusFromChargeAmplify, moreRadiusFromCooldown |
| Devouring Orb | DevouringOrbTree | 1 | 26 | 25 | 0 | 0 | 1 | cooldown x1 | - |
| Disintegrate | DisintegrateTree | 1 | 30 | 28 | 2 | 0 | 0 | - | increasedDamagePerPowerStep |
| Dive Bomb | DiveBombTree | 3 | 27 | 24 | 2 | 1 | 0 | cooldown x2 | CALL SetCooldown |
| Drain Life | DrainLifeTree | 1 | 29 | 23 | 6 | 0 | 0 | cooldown x1, area->radius | addedManaCost, necroticExplosionIncreasedRadius |
| Dread Shade | DreadShadeTree | 1 | 30 | 28 | 2 | 0 | 0 | area->radius | increasedRadius |
| Dreamslash | DreamslashTree | 1 | 28 | 28 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Earthquake | EarthquakeSlamTree | 3 | 31 | 24 | 7 | 0 | 0 | cooldown x2, area->radius | CALL GiveCooldown, aftershockIncreasedRadius, increasedRadius |
| Elemental Nova | NovaSkillTree | 1 | 31 | 24 | 6 | 0 | 1 | cooldown x1, area->radius, doubled-cond more | increasedAreaForDirectUse, increasedRadius |
| Enchant Weapon | EnchantWeaponTree | 2 | 26 | 26 | 0 | 0 | 0 | cooldown x1 | - |
| Entangling Roots | EntanglingRootsTree | 2 | 29 | 28 | 1 | 0 | 0 | cooldown x1, AutomaticNodeStat | - |
| Erasing Strike | ErasingStrikeTree | 2 | 26 | 25 | 0 | 1 | 0 | cooldown x2, doubled-cond more | - |
| Eterra's Blessing | EterrasBlessingTree | 3 | 26 | 26 | 0 | 0 | 0 | cooldown x1 | - |
| Explosive Trap | ExplosiveTrapTree | 2 | 31 | 27 | 4 | 0 | 0 | cooldown x2, area->radius | CALL GiveCooldown, increasedDetonationRadius, increasedTriggerRadius, lessRadius |
| Falconry | FalconryTree | 3 | 29 | 29 | 0 | 0 | 0 | - | - |
| Fireball | FireballSkillTree | 2 | 27 | 19 | 8 | 0 | 0 | - | LIST unconditionalTempStats, moreCastSpeed |
| Firebrand | FirebrandTree | 5 | 29 | 29 | 0 | 0 | 0 | - | - |
| Flame Reave | FlameReaveTree | 1 | 28 | 25 | 2 | 0 | 1 | cooldown x1, pow | moreGrowth |
| Flame Rush | FlameRushSkillTree | 2 | 26 | 23 | 3 | 0 | 0 | cooldown x1, area->radius | increasedRadius, increasedRadiusIfCastFireballInSameDirection, increasedRadiusOnFrostWallHit |
| Flame Ward | FlameWardTree | 3 | 30 | 28 | 2 | 0 | 0 | cooldown x2, area->radius | increasedRadius |
| Flay | FlayTree | 2 | 33 | 32 | 0 | 1 | 0 | cooldown x1, doubled-cond more | - |
| Flurry | FlurryTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Focus | FocusTree | 1 | 28 | 28 | 0 | 0 | 0 | cooldown x4 | - |
| Forge Strike | ForgeStrikeTree | 2 | 28 | 24 | 4 | 0 | 0 | cooldown x1, area->radius | increasedDuration, increasedRadius |
| Frost Claw | FrostClawTree | 4 | 28 | 28 | 0 | 0 | 0 | - | - |
| Frost Wall | FrostWallSkillTree | 3 | 28 | 26 | 1 | 0 | 1 | cooldown x1, area->radius | increasedRadius |
| Fury Leap | FuryLeapSkillTree | 1 | 23 | 21 | 1 | 1 | 0 | area->radius | increasedRadius |
| Gathering Storm | GatheringStormTree | 2 | 27 | 24 | 3 | 0 | 0 | area->radius | increasedMeleeRadius, increasedTargetingRadius |
| Ghostflame | GhostflameTree | 1 | 29 | 28 | 1 | 0 | 0 | area->radius | increasedRadius |
| Glacier | GlacierSkillTree | 1 | 27 | 19 | 8 | 0 | 0 | cooldown x1 | rimeFreezeRateMulti, rimeIncreasedDamage |
| Glyph of Dominion | GlyphOfDominionSkillTree | 2 | 27 | 26 | 1 | 0 | 0 | cooldown x1, area->radius | increasedRadius |
| Hail of Arrows | HailOfArrowsTree | 1 | 30 | 30 | 0 | 0 | 0 | cooldown x2 | - |
| Hammer Throw | HammerThrowTree | 1 | 24 | 16 | 8 | 0 | 0 | cooldown x1 | extraProjectiles |
| Harvest | HarvestTree | 2 | 28 | 27 | 1 | 0 | 0 | area->radius | increasedRadius |
| Healing Hands | HealingHandsTree | 5 | 28 | 27 | 0 | 1 | 0 | cooldown x1 | - |
| Heartseeker | HeartseekerTree | 2 | 31 | 31 | 0 | 0 | 0 | cooldown x2 | - |
| Holy Aura | HolyAuraTree | 3 | 25 | 25 | 0 | 0 | 0 | cooldown x2, Stat.multiplyValues | - |
| Hungering Souls | HungeringSoulsTree | 2 | 27 | 25 | 2 | 0 | 0 | area->radius | increasedRadius |
| Ice Barrage | IceBarrageTree | 1 | 30 | 30 | 0 | 0 | 0 | cooldown x3 | - |
| Infernal Shade | InfernalShadeTree | 1 | 28 | 17 | 10 | 1 | 0 | cooldown x1, area->radius | LIST statsPerSecondWaiting, giantShadeIncreasedRadius, increasedRadius |
| Javelin | JavelinTree | 2 | 31 | 30 | 0 | 1 | 0 | cooldown x3, doubled-cond more | - |
| Judgement | JudgementTree | 1 | 29 | 28 | 1 | 0 | 0 | cooldown x1, area->radius | increasedRadiusConsecratedGround |
| Lethal Mirage | LethalMirageTree | 3 | 29 | 29 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Lightning Blast | LightningBlastSkillTree | 1 | 27 | 23 | 3 | 1 | 0 | 1/(1+x)-1 | wardOnHit |
| Lunge | LungeTree | 1 | 28 | 27 | 1 | 0 | 0 | cooldown x1, area->radius | increasedPathRadius |
| Maelstrom | MaelstromTree | 3 | 25 | 22 | 2 | 1 | 0 | area->radius | increasedRadius |
| Mana Strike | ManaStrikeSkillTree | 2 | 26 | 24 | 2 | 0 | 0 | cooldown x1, area->radius | increasedRadius, moreRadius |
| Manifest Armor | ManifestArmorTree | 1 | 26 | 24 | 0 | 0 | 2 | - | - |
| Marrow Shards | MarrowShardsTree | 1 | 30 | 30 | 0 | 0 | 0 | - | - |
| Meteor | MeteorSkillTree | 1 | 25 | 23 | 1 | 1 | 0 | 1/(1+x)-1 | increasedArea |
| Multishot | MultishotTree | 1 | 26 | 26 | 0 | 0 | 0 | - | - |
| Multistrike | MultistrikeTree | 3 | 27 | 26 | 1 | 0 | 0 | area->radius | increasedTargetFindRadius |
| Net | NetTree | 3 | 30 | 29 | 1 | 0 | 0 | cooldown x3, area->radius | increasedRadius |
| Profane Form | ProfaneVeilTree | 3 | 31 | 29 | 2 | 0 | 0 | area->radius | increasedRadius, wanderingSpiritIncreasedRadius |
| Puncture | PunctureTree | 2 | 26 | 26 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Radiant Lance | RadiantLanceTree | 2 | 31 | 31 | 0 | 0 | 0 | AutomaticNodeStat | - |
| Reaper Form | ReaperFormTree | 3 | 33 | 29 | 3 | 0 | 1 | cooldown x1, area->radius | increasedRadius, scalingSpellDamageInterval |
| Rebuke | RebukeTree | 1 | 23 | 19 | 3 | 0 | 1 | cooldown x2, area->radius | LIST statsAfterChannelling, LIST statsWhileChannelling, increasedRadius |
| Ring Of Shields | RingOfShieldsTree | 2 | 27 | 23 | 4 | 0 | 0 | area->radius | LIST creatorBuffStats, increasedRingRadius |
| Rip Blood | RipBloodTree | 2 | 27 | 22 | 3 | 1 | 1 | area->radius, 1/(1+x)-1 | LIST splatterStats, coagulatedBloodIncreasedRadius, increasedRadius, increasedRadiusPerMinion |
| Rive | RiveTree | 5 | 30 | 24 | 5 | 1 | 0 | area->radius | LIST flameDrinkerStats, increasedRadius |
| Runebolt | RuneBoltSkillTree | 3 | 32 | 30 | 1 | 0 | 1 | area->radius | increasedImbuedRunestoneExplosionRadius |
| Runic Invocation | RunicInvocationSkillTree | 2 | 31 | 27 | 4 | 0 | 0 | cooldown x2 | CALL GiveCooldown |
| Sacrifice | SacrificeTree | 1 | 24 | 24 | 0 | 0 | 0 | - | - |
| Serpent Strike | SerpentStrikeTree | 1 | 29 | 29 | 0 | 0 | 0 | - | - |
| Shadow Rend | ShadowRendTree | 2 | 29 | 27 | 2 | 0 | 0 | cooldown x2 | CALL GiveCooldown |
| Shatter Strike | ShatterStrikeTree | 1 | 27 | 25 | 2 | 0 | 0 | area->radius, AutomaticNodeStat | increasedRadius |
| Shield Bash | ShieldBashTree | 4 | 32 | 28 | 4 | 0 | 0 | cooldown x2 | LIST unconditionalTempStats, nextMeleeOrThrowingAttackBuffsFromShieldBash |
| Shield Rush | ShieldRushTree | 1 | 22 | 21 | 1 | 0 | 0 | cooldown x3, area->radius | increasedRadius |
| Shield Throw | ShieldThrowTree | 1 | 31 | 26 | 5 | 0 | 0 | cooldown x1, area->radius | LIST allyOnHitStats, increasedLavaBurstRadius |
| Shift | ShiftTree | 2 | 30 | 30 | 0 | 0 | 0 | cooldown x1 | - |
| Shurikens | ShurikensTree | 1 | 26 | 25 | 0 | 1 | 0 | cooldown x1, doubled-cond more | - |
| Sigils Of Hope | SigilsOfHopeTree | 2 | 28 | 28 | 0 | 0 | 0 | cooldown x2 | - |
| Smelter's Wrath | SmeltersWrathTree | 1 | 26 | 24 | 2 | 0 | 0 | - | moreChargeSpeed |
| Smite | SmiteTree | 1 | 30 | 27 | 3 | 0 | 0 | cooldown x1 | percentCurrentHealthCost |
| Smoke Bomb | SmokeBombTree | 1 | 31 | 28 | 2 | 0 | 1 | area->radius | increasedRadius |
| Snap Freeze | SnapFreezeTree | 1 | 23 | 23 | 0 | 0 | 0 | cooldown x3 | - |
| Soul Feast | SoulFeastTree | 1 | 28 | 27 | 1 | 0 | 0 | area->radius | increasedRadius |
| Spirit Plauge | SpiritPlagueTree | 1 | 27 | 24 | 0 | 3 | 0 | 1/(1+x)-1 | - |
| Spriggan Form | SprigganFormTree | 8 | 34 | 33 | 1 | 0 | 0 | area->radius | thornBurstIncreasedRadius |
| Static | StaticTree | 1 | 26 | 26 | 0 | 0 | 0 | cooldown x1 | - |
| Static Orb | StaticOrbTree | 1 | 27 | 23 | 4 | 0 | 0 | - | addedManaCost |
| Summon Bear | SummonBearSkillTree | 4 | 26 | 26 | 0 | 0 | 0 | - | - |
| Summon Bone Golem | SummonBoneGolemTree | 1 | 26 | 25 | 0 | 0 | 1 | AutomaticNodeStat | - |
| Summon Elemental | PrimalistSummonElementalTree | 4 | 30 | 30 | 0 | 0 | 0 | cooldown x1, AutomaticNodeStat | - |
| Summon Frenzy Totem | FrenzyTotemTree | 1 | 25 | 24 | 1 | 0 | 0 | area->radius | increasedRadius |
| Summon Raptor | SummonRaptorTree | 2 | 27 | 27 | 0 | 0 | 0 | - | - |
| Summon Sabertooth | SummonSabertoothTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Summon Scorpion | SummonScorpionTree | 6 | 26 | 20 | 6 | 0 | 0 | area->radius | LIST statList, increasedMeleeRadius, increasedRadius |
| Summon Skeleton | SummonSkeletonTree | 1 | 27 | 27 | 0 | 0 | 0 | - | - |
| Summon Skeleton Mage | SummonSkeletonMageTree | 1 | 27 | 26 | 1 | 0 | 0 | cooldown x1, area->radius | increasedNecroticMorterRadius |
| Summon Spriggan | SummonSprigganSkillTree | 1 | 29 | 29 | 0 | 0 | 0 | - | - |
| Summon Storm Crow | SummonStormCrowTree | 2 | 31 | 30 | 1 | 0 | 0 | cooldown x1, area->radius | activeIncreasedRadius |
| Summon Storm Totem | StormTotemTree | 1 | 25 | 25 | 0 | 0 | 0 | - | - |
| Summon Thorn Totem | ThornTotemTree | 3 | 24 | 24 | 0 | 0 | 0 | - | - |
| Summon Volatile Zombie | SummonVolatileZombieTree | 2 | 29 | 28 | 1 | 0 | 0 | cooldown x1, area->radius | moreRadiusForGiantZombie |
| Summon Wolf | SummonWolfSkillTree | 1 | 28 | 28 | 0 | 0 | 0 | - | - |
| Summon Wraith | SummonWraithTree | 1 | 28 | 24 | 4 | 0 | 0 | cooldown x1 | delayedWraiths, targetting |
| Surge | SurgeTree | 1 | 29 | 28 | 1 | 0 | 0 | area->radius | increasedRadius |
| Swarmblade Form | SwarmbladeTree | 9 | 33 | 32 | 1 | 0 | 0 | area->radius | increasedMeleeRadius |
| Swipe | SwipeSkillTree | 1 | 23 | 22 | 1 | 0 | 0 | cooldown x2, area->radius | increasedRadius |
| Synchronized Strike | SynchronizedStrikeTree | 1 | 28 | 28 | 0 | 0 | 0 | cooldown x1 | - |
| Teleport | TeleportTree | 2 | 24 | 24 | 0 | 0 | 0 | cooldown x1 | - |
| Tempest Strike | TempestStrikeTree | 6 | 32 | 30 | 0 | 2 | 0 | - | - |
| Tornado | TornadoSkillTree | 1 | 23 | 20 | 1 | 1 | 1 | cooldown x1, area->radius | increasedRadius |
| Transplant | TransplantTree | 2 | 28 | 27 | 1 | 0 | 0 | cooldown x1, area->radius | increasedExplosionRadius |
| Umbral Blades | UmbralBladesTree | 6 | 27 | 27 | 0 | 0 | 0 | - | - |
| Upheaval | UpheavalTree | 3 | 30 | 28 | 1 | 1 | 0 | cooldown x1, area->radius, doubled-cond more | increasedRadius |
| Vengeance | VengeanceTree | 4 | 29 | 27 | 0 | 2 | 0 | doubled-cond more | - |
| Void Cleave | VoidCleaveTree | 3 | 30 | 30 | 0 | 0 | 0 | cooldown x2 | - |
| Volatile Reversal | VolatileReversalTree | 4 | 28 | 28 | 0 | 0 | 0 | cooldown x2 | - |
| Volcanic Orb | VolcanicOrbTree | 1 | 26 | 21 | 0 | 5 | 0 | cooldown x1, 1/(1+x)-1 | - |
| Wandering Spirits | WanderingSpiritsTree | 1 | 27 | 26 | 1 | 0 | 0 | cooldown x2, area->radius | increasedDamageRadius |
| Warcry | WarcryTree | 2 | 31 | 31 | 0 | 0 | 0 | cooldown x2 | - |
| Warpath | WarpathTree | 1 | 27 | 27 | 0 | 0 | 0 | - | - |
| Werebear Form | WerebearFormTree | 4 | 28 | 27 | 1 | 0 | 0 | cooldown x2, area->radius | increasedRadius |

## 8. Could not establish

1. **What mutator does with each field.** Here extracted precisely which field, what value, how depends on points. How field affects skill determined by code `<X>Mutator`.
   - Hints `field_usage_hints` exist for 3012 of 4372 written fields. For 349 known specific Stat: SP, type and slot, e.g. `FireballMutator.hypotheticalExtraProjectiles → getTempStats: Damage more`.
   - Other fields mechanical: projectile count, duration, flags, trigger chances. Semantics parse by methods from `read_in` (`Mutate`, `getTempStats`, `OnHit`…) separate task by mutators.
   - For engine priority fields read in `getTempStats`/`Mutate`. Listed in `read_in`.
2. Holy Aura: where goes `HolyAuraMutator.statsToApply` (copy ×2), self or allies.
3. Nodes Manifest Armor "Reflects Damage" and "Chance To Slow When Hit" and node Devouring Orb "Rift AoE Growth" give no effect in `updateMutator`. Check if anyone else reads them (`LocalTreeData.getNodePoints`, etc.). Search by literals in LE.dll found no other places.
4. Helpers without symbols in `symbols.tsv`, identified by context: `0x18037F680 = powf(x, y)`, `0x18037C870 = Math.Round(double)`, `0x1803ECF60 = float→int` (RoundToInt or CeilToInt — **D?**).
5. 252 nodes where no tooltip number matched code. Mostly constants live in mutator (limits, durations, "per X"). Code/tooltip mismatches individually not verified except §4.4 and Ghidra case.

**Functions for manual decompile (Ghidra didn't run):**
- `FlameReaveTree.<updateMutator>g__AddMirroredLightningStats|1_0`;
- `HolyAuraMutator.getTempStats` / `AuraMutator` (where `statsToApply`);
- `ManifestArmorMutator` (Reflects and Slow When Hit nodes);
- `0x1803ECF60`;
- methods `Mutate`/`getTempStats` of mutators from `read_in` for fields without `feeds_stat` (by planner skill priority).

**Re-run:** `tools/venv/Scripts/python tools/extract/mutator_coeffs.py` (~20 s). With tree name filter (`... Fireball Rive`) result writes to `%TEMP%/skill_node_effects_partial.json`, whole file not overwritten.
