# 07f. Passive Trees of Classes, Weaver Tree and Code-Defined Ability Damage (Client 1.5.0)

Results: `research/data/game/passive_node_effects.json`, `weaver_node_effects.json`, `abilities_code_damage.json`. Tool: `tools/extract/passive_tree_effects.py` (on top of `mutator_coeffs.py` and `isil_sym.py`, runtime ~8 s, restarts without edits).

## 1. Brief

- All 5 class trees (Knight, Acolyte, Mage, Primalist, Rogue) analyzed: **541 nodes, 0 nodes without effect**. Of them `auto` 312, `auto_threshold` 226 (bonus at `p >= N`), `auto_formula` 2 (non-linear function of p), `auto_after_loop_rule` 1. No manual analysis left.
- Weaver: 79 nodes with points (80th, `Node_None`, root). Each has effect. Weaver doesn't affect character, it sets echo content parameters (drop chances, spawn etc).
- Found and analyzed another layer: **mastery base bonuses** (`switch(chosenMastery)` after node loop), field `mastery_bonuses` in JSON.
- Fixed two defects of symbol executor along the way (affected skill trees too, see §6).

## 2. How Passive Nodes Are Applied (D)

`LocalTreeData.updateMutator` calls `<Class>Tree.updateMutator(localTreeData, tree)`. Differences from skill trees:
- Not `switch` by hash, but chain `if (gnode.name == "...")` (String.op_Equality). Points taken from `NodeData.points`.
- Stat created directly in needed list: `CharacterMutator.stats`, `statsWithWeaponRequirements`, `totemStats`, `statsPerMastery1Level`; for minions and skills this is `ManifestArmorMutator.statListFromPassiveTree` etc. Fields `CharacterMutator.*` read later by player itself (conditional effects, triggers).
- «At N points» bonuses: `if (p >= N)` inside node block. In JSON such effect has `minPoints` and `when`.
- `AcolyteTree.updateMutator` truncated by Cpp2IL (no `Return`, ~2.6 KB); missing tail decoded from `GameAssembly.dll` (`mini_x64`) and appended to method.
- `dump/decomp_extra/{Knight,Acolyte,Mage,Primalist}Tree__updateMutator.c` used only for verification. `RogueTree.c` in normal decompilation exists.
- Mastery read from `LocalTreeData+0xB0` (`chosenMastery`, byte). Index 0 — no mastery, 1..3 — three masteries of class, as in `masteries[1..3]`.

### Schema of `passive_node_effects.json`
Array of 5 trees:
```
{ tree, treeID, class, kind:"passive", masteries[], mutators[], errors[],
  mastery_bonuses: { "1"|"2"|"3": { mastery, fields{target: value}, stats[{target, stat}], calls[] } },
  after_loop{formulas, baseline_fields, baseline_stats, baseline_calls, loop_carried},
  field_usage_hints, code_node_names_not_in_tree[], tree_nodes_without_code[],
  nodes[ { id, name, displayName, maxPoints, mastery, masteryRequirement, status, review[], manual_note?,
           effects[], asset_noScaling{type, pointThreshold},
           tooltip_stats[], effects_without_tooltip[], tooltip[], tooltip_check{} } ] }
```
Node effect:
- `{target:"CharacterMutator.stats", op:"add_stat", stat:{...}, when?, minPoints?}`. Field `stat.kind`: `added`, `increased`, `more`, `ailment_chance`, `ailment_duration`, `ailment_effect`, `ailment_effect_on_you`, `conditional_more_damage` (`condition`, e.g. `ToBossesAndRareEnemies`), `player_property` / `more_player_property`, `ability_property` / `more_ability_property`, `ailment_conversion`.
- Value: `added|increased|more|value: {per_point, flat}` or `{expr}` (`per_point` multiplied by p).
- `stat.property`, `stat.tags`, `stat.ailment`, `stat.specialTag`.
- `StatWithWeaponRequirement` wrapper (fields `wrapper`, `other`: weapon type, `WeaponRequirementType`) for stats working only with weapon.
- `player_property`: `playerPropertyIndex`, `playerPropertyName`, `playerPropertyField`, `playerPropertyOp` (from `player_property_fields.json` table, 169 of 169 occurrences named).
- `ability_property`: `abilityID`, `abilityPropertyIndex`, `abilityPropertyField`, `abilityPropertyOp` from `ability_property_fields.json`, named only 7 of 67 (rest of pairs not in table).
- Direct field writes in mutators: `{target:"CharacterMutator.<field>", type, value:{per_point, flat}}` (triggers, chances, stacks). Cooldown calls: `op:"cooldown"`.
- Statuses:
  - `auto`: effect linear in p;
  - `auto_threshold`: part of effects only at `p >= minPoints`;
  - `auto_formula`: non-linear function of p (e.g. `1/(1-0.05p)-1`);
  - `auto_after_loop_rule`: rule from method tail, node Rogue Marksman Concentration, see `manual_note`.

### Base Mastery Bonuses (`mastery_bonuses`, D)
Result of running method tail with `chosenMastery = 1,2,3` minus result for 0. Examples:
- Void Knight: field `chanceToRepeatMeleeThrowingAttacksAndVoidSpells = 0.1` and PlayerProperty 440 +0.01.
- Forge Guard: `stalwartWhenHitAndOnHit`, +35% Fire and Physical Resistance.
- Paladin: `moreDamagePerPercentHealth 0.15`, `increasedHealingPerAttunement 0.01`.
- Bladedancer: `createShadow` +1, +15 Physical Melee Damage, DodgeRating more 0.15.
- Falconer: +12 Dexterity, `falconry` property +1.
Rest of masteries see in JSON.

## 3. Hypothesis «Increased-strings = INC, +N = ADDED» (Verified by Code)

Matched 1259 tooltip lines with code effects (628 of them reliable: match by SP property and tags).

| Tooltip | Type in Code | Lines |
|---|---|---|
| «Increased X», «Reduced X» | `increased`, or `added` in special SP `Increased*` (IncreasedStunChance, IncreasedHealing, IncreasedLeechRate, IncreasedCooldownRecoverySpeed, IncreasedAreaForAreaSkills, ReducedBonusDamageTakenFromCrits), i.e. INC-pool | 179 of 180 |
| «More / Less X» | `more` | 15 of 15 |
| «+N» (signed number) | `added` | 284 |
| «+N%» for speeds and costs (AttackSpeed, CastSpeed, Movespeed, Minion Health, ManaCost, ReceivedStunDuration) | `increased` | 21 |
| «±N%» «Damage Taken ...» (from melee enemies, while moving, with dual wield, DoT) | `more` | 11 |
| «N%» without sign (resistances, crit multiplier, block chance) | mostly `added` (38), rarely `increased` (4: AttackSpeed, ManaRegen) | 42 |
| ailment chances «+N%» (Bleed, Chill, ...) | `ailment_chance` (additive chance, separate type) | 49 |

**Conclusion.** Hypothesis true for «Increased/Reduced» strings. Only exception, FG Strength and Damage: «Increased Melee Attack Speed With Sword» coded as `added` in AttackSpeed Melee; base added for AttackSpeed/CastSpeed is 1, so this is base addition, not INC. For «+N» hypothesis **incorrect**: type cannot be determined from text, must take `stat.kind` from JSON. Damage Taken always `more`. Passive node damage has `increased` much more often than skill trees (which are mostly `more`, 07c).

## 4. Verification Against `tree_node_stats.json` (tooltipStats)

- Matched by count and type 1259 lines (`match: matched`), 81 lines have no effect (`display_only`: line for display only, `property = None`), 100 lines no «own» effect (`no_code_effect`).
- `no_code_effect` — not lost effects: mostly conditional triggers and `CharacterMutator.*` fields («per 5 Strength», «Cast Holy Symbol On Block», «Can Equip Swords in Offhand», limits and durations). They are in `effects`, but not auto-matched by value.
- Value count mismatch (`value_ok: false`) remained in **9** lines. Leech (leech): percent in tooltip = stat value ×10 (stat `HealthLeech` weighs 0.1, 06c §5.2). Confirmed on 14 lines and accounted (`value_note`).
  Real code/tooltip divergences (code authoritative):
  - Knight VK Health And Void Protection: Health tooltip +8, code 10 per point;
  - Mage SB Armor And Ward Per Second: Ward/s tooltip +3, code 4;
  - Primalist Shaman Totem Stun Immunity: Armor tooltip +10, code 30 per point (totem also 30);
  - Rogue BD Parry And Crit: Increased Crit tooltip 8%, code 10%;
  - Rogue BD Poison And Bleed: Increased DoT tooltip 7%, code 8%;
  - Rogue Falconer Throwing Damage And Speed: tooltip 7%, code 5%;
  - Rogue Falconer Spear Buffs: tooltip 6%, code 5%;
  - Rogue Falconer Damage And Slow Duration: tooltip 6%, code 5%.
  Ninth line (BD Leech, DoT) — false effect match (tooltip 0.5% = 0.05×10, code correct).
- `scaling_ok: false` (10 lines): tooltip without `noScaling`, code has constant not of p (e.g. «+1 Intelligence» with `flat 1`); these are threshold or trigger effects, see `flat` and `minPoints`.
- `tooltip_check.unmatched` not empty for 110 nodes: limit numbers, durations and «per N», not stat per point. No single number matched 5 nodes (Mage Sorc Ward On High Mana Use, Primalist BM Slow Melee and BM Shark Stacks, Rogue BD Dodge to Glancing Blow Conversion and BD Leech).
- `code_node_names_not_in_tree`: dead branches of old nodes (e.g. `FG Melee Physical And Fire Damage`, `BD Temp Node`). Tree nodes without code: none (`tree_nodes_without_code` empty).

## 5. Weaver

`TheWeaver.UpdateWeaverTreeNode(effect, points)` @0x1820DDE40 — three jump-tables (effects 0..64, 101..131, 151..191). Cpp2IL truncates method, so decoded from binary fully, each case executed symbolically.
- Result: 79 nodes `auto` (flags `p > 0`, integer ranks, fields `p * k`), 0 errors.
- Schema `weaver_node_effects.json`: array of one object with `nodes[]` (`id, name, maxPoints, nodeEffect, nodeEffectName, effects[{target:"TheWeaver.<field>", type, value, when?}], tooltip, tooltip_check`) and `effects_by_enum[]`.
- Three nodes use `p * TheWeaver.<X>PerPointAllocated`: field `+0x80` initialized by constructor (`0x3e19999a` = 0.15, D), fields `+0x90` and `+0x94` serialized in asset (not found), values taken from tooltip (0.10 and 0.02, **D?**, field `per_point_value`).
- Nodes 6/7/8 (`...RewardWeightRank`) store only rank, group weights read elsewhere (not analyzed). Tooltip (80%, 50%, 50%) matches meaning.
- Node 42: code constant 0.029, tooltip 6% (probably accumulates by `OnCacheOpenedChanceForSimilarItemsAmountWeights` table, not analyzed).

## 6. Tool Fixes (Affected skill_node_effects.json)

1. `isil_sym.py`: `xorps xmm,[0x80000000-mask]` now gives negation (previously `x ^ -0.0`). Defect in 9 expressions (3 in passives, 6 in skills).
2. `isil_sym.py`: `Subtract/Add/And/Or/Xor` now set flags (previously `sub rcx,1; je` took stale flags). Gave correct `switch(chosenMastery)` and fixed 7 skill nodes: Acid Flask Poison Pool (base cooldown 6.0 became 2.0, like tooltip), Flay Cold/Necrotic/Poison Conversion (added Bleed conversion) etc.
3. `passive_tree_effects.py`: `typeof(C)` (float 2.0 @0x184561C38, Cpp2IL name collision) replaced by constant where asm alignment didn't work (3 Knight nodes, 1 Rogue node). `EpochExtensions.safeQuotient(x)` = x (or 0.0001 at x == 0) collapsed to expression.
`skill_node_effects.json` recalculated, 07c updated: auto 3568, auto_combined 212, auto_formula 29, conditional 2, manual 5, none 4.

## 7. Ability Damage Code-Defined (`abilities_code_damage.json`)

Of 182 player abilities 54 have no `damage[]`. «Damage not in asset» is three kinds: ailment damage (in `ailments.json`), hit collected in mutator, and sub-ability damage.

| Ability | Damage Source | Base | ADE |
|---|---|---|---|
| Snap Freeze | `DamageEnemyOnHit` created in `Mutate`, only if `addedColdDamage > 0` | Cold = 5 (node) + 6 per point (node, up to 5 points), no node = no damage; crit 5%, multiplier 2.0, Spell | 1.0 (constant) |
| Abyssal Echoes | ailment `AbyssalDecay` (id 12) and hit when node `addedVoidSpellDamage = 60` | DoT Void 100 (Spell DoT, 5 s, max 1); hit Void 60 (Fire on conversion) | DoT 5.0; hit 0.05·damage |
| Bone Curse | ailment `BoneCurse` (id 58): hit cursed enemy | Physical 4, crit 5% ×2, Spell Curse, 8 s; ×(1+2) if caster hits (D?) | 0.2 |
| Spirit Plague | ailment `SpiritPlague` (id 59) | Necrotic 90, 3 s, Spell DoT Curse, spread 9 m; Intelligence × (node) as added Spell Necrotic; `moreSpiritPlagueDamage` — ailment multiplier | 4.5 |
| Aura of Decay | `Poison` (id 7) every 0.25 s in 4 m radius | Poison 28 per stack, 3 s, added damage ineffective | 0 |
| Anomaly | `TimeWave` (AbilityID 368) and ailments `TimeRot` (id 9), `FutureAttack` (id 10) | Void 100 / Void 60 per stack / Void 60 | 2.5 / 0 / 0 |
| Focus | `FocusMutator` and `FocusEndMutator` | Lightning = 12% max mana per point; end: mana × 0.25 per point | 0.05·damage |
| Warcry | `addedPhysicalSpellDamage` | Physical 40 per point (Cold on conversion) | 0.05·damage |
| Shift | damage along rush path | Physical `addedTravelDamage = 2` with melee weapon | 1.0 |
| Healing Hands | `setBaseDamage` when `dealsDamage` | Fire 40 (D?) plus added from 20% healing | 0.05·damage = 2.0 |

Formulas `addBaseDamage`, `setStandardVariables`, `calculateAddedDamageScaling` (06b §1.7) confirmed: ADE = `isWeapon ? 1.0 : 0.05 × Σ base damage`; hit gets crit 5% and ×2.0, non-hit gets DoT tag. Other no-damage abilities — buffs, traversals and summon (minion damage, 07d); list in JSON (`noDirectDamage`).

## 8. Default Value of `AbilityRef` (D)

`AbilityRef` — struct `{long key @0x0; Ability ability @0x8}` without field initializers. For `default(AbilityRef)` key is 0, and `GetAbility()` calls `AbilityManager.GetAbilityFromKey(0)`: `Dictionary.TryGetValue` doesn't find key, returns null. Among 1044 abilities none has key 0. Constructors: `AbilityRef(long)` and `AbilityRef(Ability)` (key from `GetKeyForAbility`). **Fireball key (−648846322) in serialized data doesn't follow from code**: this is value written to prefab at authoring. So 07b conclusion (treat Fireball key in unrelated component as empty) correct, but reason not code default.

## 9. Could Not Determine

1. Fields `TheWeaver.WeaversWillLuckyRollChancePerPointAllocated` (+0x90) and `RareEnemiesChanceToWeaversWillItemPerPointAllocated` (+0x94): serialized in asset (not found), values from tooltip.
2. Weaver reward rank weights (nodes 6/7/8) and node 42 table.
3. 60 of 67 `ability_property`-effects of passives have no field name in `ability_property_fields.json` (pairs not in table).
4. Conditional and trigger effects in `CharacterMutator.*` fields (chances, thresholds, «per N attribute»): values present, semantics in `CharacterMutator` methods (`usedIn` in `player_property_fields.json`).
5. Snap Freeze: «Lightning Damage Per Second Of Freeze» requires Freeze duration from `FreezeEnemyOnHit` prefab (not extracted); Focus interval unspecified (`increasedChannellingLightningDamageFrequency`).
6. Healing Hands: constant 40.0 (@0x184561E0C) taken without re-read, moreDamage conditions not traced.
7. Extra damage code adds to damage-having abilities (Meteor, Flay, Disintegrate, Black Hole etc): not extracted (list in JSON).
8. For 8 nodes (§4) tooltip and code diverge; code authoritative for engine, but what game shows at this, not verified.
