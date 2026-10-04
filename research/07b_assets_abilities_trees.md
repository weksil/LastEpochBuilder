# 07b — Skills and trees (abilities, passives, Weaver) from Last Epoch 1.5.0 assets

Source: client bundles `StreamingAssets/LEAssetBundles` (26,667 files). Read directly via UnityPy: typetrees embedded in bundles. AssetRipper server not used. All scripts re-run after patch (order see §6).

## 0. Brief
- **Abilities.** `PermaLoad.bundle` holds 4349 `Ability` assets. Of them 1044 tied to player (categories described §2.1), rest 3305 in monster index.
- **Where damage.** Base damage, crit, ADE and ailment chances **not stored in `Ability` asset**. They in ability prefab (`Ability.abilityPrefabSoftRef`), components `DamageStatsHolder` (`DamageEnemyOnHit`, etc.) and `ChanceToApplyAilmentsOnHit`. Of 1044 prefabs 989 in `PermaLoad.bundle`.
- **Trees structure.** `Global Tree Data` defines structure of 150 trees: 144 skill, 5 passive and Weaver.
- **Where node values.** Node values stored in `SkillTreeNode` / `WeaverTreeNode` UI-prefab components. These 176 bundles, each skill has own. For passives nodes in 20 mastery-panel prefabs.
- **Verification.** With LE Tools and Maxroll data match nearly complete (§5).

## 1. Where data lives

| What | Where | Class / field |
|---|---|---|
| Ability params (timings, speed, mana, CD, tags, scaling) | `PermaLoad.bundle` | `Ability` (ScriptableObject) |
| Player ability list | `PermaLoad.bundle`, asset "Ability Manager" | `AbilityManager.playerAbilities` (184, 183 non-empty, Focus twice) |
| AbilityID → asset table | there | `AbilityManager.abilities[i]` = AbilityID `i` (enum `AbilityID`, 994 values) |
| Ability key | there | `AbilityManager.keyedArray[{ability, key}]`. Ref by `AbilityRef{key}` in mutators and prefabs |
| Damage, crit, ADE, ailments | ability prefab. Soft ref → `AssetBundle.m_Container` → bundle + pathID. All 1044 prefabs found: 989 PermaLoad, 55 in `assets_*.bundle` | components with field `baseDamageStats` (subclasses `DamageStatsHolder`), `ChanceToApplyAilmentsOnHit.ailments[]` |
| Minions | summon prefab → `SummonEntityOnDeath.ActorReference` → `ActorData` (PermaLoad) → `ActorData.ActorSoftRef` → actor prefab | minion abilities: `AbilityList.abilityRefs[]`, `*Mutator.abilityRef`, `CastSpeedManager.overrides[]`, etc. |
| Player mutator defaults | `assets_d7321f5c187fdc63.bundle` (player prefab: only bundle with `UsingAbilityPlayer`) | 600 components `*Mutator` |
| Trees structure | `PermaLoad.bundle`, "Global Tree Data" | `GlobalTreeData.skillTrees[144] / passiveTrees[5] / weaverTree` |
| Node values | tree UI prefabs (§1.1) | `SkillTreeNode.stats[]` (`NodeTooltipStat`), `SkillTreeNode.nodeStats[]` (`AutomaticNodeStat`) |
| Tooltip category names | "Node Tooltip Property List" (PermaLoad) | `NodeTooltipPropertyList.properties[150]` |
| Which mastery panels actually used | PermaLoad, `PassivePanelData.classResources[].masteryPanels[]` | soft refs to 20 prefabs `PassiveTree<Class>_Mastery<0..3>` |

**Soft ref → bundle.** Field `SoftRef.guid {_0, _1}` (two ulong) turns into bundle `m_Container` key as: `"%016x%016x" % (_0, _1)`. Verified on all 1044 ability prefabs, 20 panels and 59 actor minions. Keys of all bundles collected in `dump/assets/bundle_index.jsonl`.

### 1.1 Bundles with trees
Full list: `research/data/game/tree_ui_sources.json` (field `bundles`).
- **Skill trees: 136 bundles, one per tree.** Component `<Skill>Tree` / `<Skill>SkillTree : SkillTree` with fields `treeID`, `version`, `ability`, `nodeList`. Examples:
  - Fireball `fi9` → `assets_66d2336bd98608aa.bundle`;
  - Flame Reave → `assets_66f3ad81937aecba.bundle`;
  - Swarmblade → `assets_4b3ca2487b37f89c.bundle`.
  Another Dreamslash copy in test scene `scene_Testing_Funtimes_Zone_unity.bundle`; discarded.
- **Passives.** Root components `KnightTree` / `AcolyteTree` / `MageTree` / `PrimalistTree` / `RogueTree : CharacterTree` stored in `assets_6e80c7b01b3ea527` (kn-1), `assets_ece0c7bdeb7dd87f` (ac-1), `assets_0e889347fa33eb0a` (mg-1), `assets_8db0c9701e1ffc53` (pr-1) and `assets_a5a8b4de4c31ccfe` (rg-1). Their `nodeList` empty.
  - Nodes in 40 bundles `PassiveTree<Class>_Mastery<N>`, 2 copies each panel. Ref `SkillTreeNode.tree` on these nodes is null.
  - `PassivePanelData` picks right copy: uses `masteryPanels`, `masteryNodes` — preview with old values (e.g. mg-1:93 has 1% there vs 1.5% real).
  - Empty copies `*Tree` in PermaLoad no nodes ignored.
- **Weaver.** `LE.Factions.WeaverTree` + 80 `LE.Factions.WeaverTreeNode` in `assets_39f854b235462baf` and same copy `assets_73fcfbbb45576562`. UI version 10, GTD version 9.
- **Obsolete trees.** 8 from GTD no UI, all version 0: Fire Shield `fs11`, Thorn Burst `tb47`, Ice Ward `is58`, Mark For Death `md26kh`, Manifest Weapon `mw26fp`, Ephemeral Stance `of28ur`, Abyssal Echoes (empty treeID; real `ab0lh`), Bladestorm `bs6d9` (real `bl5st`). Old trees.
- **UI-only nodes.** In 43 trees 62 nodes in UI `nodeList` but absent GTD (e.g. `ah443` 73–75 and `srk21` 14/26/32). Probably disabled. In output listed in `uiOnlyNodes`.

### 1.2 How tree nodes turn into stats (link to 06a §7.2–7.3)
1. **`AutomaticNodeStat` (`nodeStats`).** Real stats `LocalTreeData.UpdateGlobalStatsFromTree` applies.
   - Only **31 UI nodes** and **32 GTD `nodeStatsData` nodes**. All skill trees.
   - Passives and Weaver **have none**.
2. **Rest from code.** `<Skill>Tree.updateMutator` and `<Class>Tree.updateMutator` (KnightTree.updateMutator Ghidra timed out, huge function). Assets contain only **hint** `NodeTooltipStat`:
   - `statName`;
   - `value` — string **per point**, if not `noScaling`;
   - `property`, `tags`, `downside`, `noScaling`.
3. **Hint matches code.** For Fireball (constants 06a §7.3) hint values match code constants:
   - Winged Fire "+7%" Damage = more 0.07·p;
   - Mana Sphere +3% = 0.03·p;
   - Immolated Core +10% pen;
   - Conflagration +30% ignite;
   - Magma Shell +15% fire res;
   - Plasma Ball +35% crit multi.

   So `tooltipStats` — reliable source of **magnitudes**. **Type** (added / increased / more, global or skill-only) from code only. `tools/extract/mutator_coeffs.py` of another agent, output `skill_node_effects.json` handles this.
4. **`NodeTooltipStat.property` encoding (ushort)**, derived from `NodeTooltipPropertyList.GetStatPropertyName` @ `NodeTooltipPropertyList.c`, **D**:
   - `< 5000` — SP;
   - `5000..9999` — `NodeTooltipPropertyList.properties[p−5000]`, e.g. 5000 "Extra Projectiles";
   - `≥ 10000` — `AilmentID` (`p−10000`), e.g. 10001 Ignite. This branch confirmed by data; hint code not traced.

   `property = 54` (SP.None) means display string only.

## 2. File schemas (`research/data/game/`)

### 2.1 `abilities.json`
1044 records, sorted by category then name.

**Categories** (`category`):
- `player` (182) — `AbilityManager.playerAbilities`, class abilities (known, default, unlockable, masteries), tree roots.
- `nodeGranted` (189) — `SkillTreeNode.abilityGrantedByNode`. Abilities node casts or refs: Flame Burst, Spreading Flames, etc.
- `sub` (177) — closure by refs:
  - `Ability` fields (`replacementAbility`, `comboAbilities`, `sharedCooldownAbilities`…);
  - PPtr and `AbilityRef{key}` in prefab components and nested prefabs (soft ref);
  - player mutators.
- `minion` (56) and `minionSub` (7) — abilities of 59 actor minion prefabs summoned by player abilities.
- `abilityIdOnly` (433) — in enum `AbilityID` (`AbilityManager.abilities`), unreached from assets. Code calls via AbilityID: unique item procs, passives, Weaver. But some are monster abilities (e.g. `Majasa Boss 07p3 …`).
  - By `itemDB.triggeredAbilities` from LE Tools: 85 AbilityID fire from items. 29 in `abilityIdOnly`, rest in player/sub/nodeGranted.
  - Label `abilityIdOnly` means "used by code", not "monster".

**Fields:**
- **ID:**
  - `pathID` — PermaLoad asset PathID, stable inside build;
  - `key` — `keyedArray.key`;
  - `name` — m_Name, Maxroll key;
  - `abilityName`;
  - `playerAbilityID` — tree ID and LE Tools key, e.g. `fi9`;
  - `abilityIDEnum {value, name}`;
  - `reasons[]`, `parents[]`, `minionActors[]`, `classes[]`;
  - `skillTree` — treeID or `treeID:nodeID` for nodeGranted.
- **Tags:**
  - `tags` (AT mask) + `tagNames`;
  - `fakeTags`;
  - `skillTreeConversionDamageTags` + `…Names`.
- **Speed** (06e §1):
  - `useDelay`, `useDuration`, `hasMinimumUseDuration`, `minimumUseDuration`;
  - `speedScaler` (SP: 2 AttackSpeed, 3 CastSpeed, 54 None) + `speedScalerName`. No separate "throw speed": throws use AttackSpeed no weapon speed multiplier (06e §1.2);
  - `speedMultiplier`, `maximumUseSpeed`, `speedScalerAppliedAsIncrease`, `speedScalerEffectiveness`, `instantCastForPlayer`.
- **Mana and channel:**
  - `manaCost`, `minimumManaCost`, `freeWhenOutOfMana`, `manaCostPerDistance`;
  - `channelled`, `channelCost`, `noManaRegenWhileChanneling`, `channelTimeLimit`.
- **Cooldown:**
  - `maxCharges`, `chargesGainedPerSecond`;
  - `cooldown` — derived: `1/chargesGainedPerSecond`, no stats;
  - `sharedCooldown`.
- **Flags:**
  - `companion`, `minionsUseAbility`, `isTransform`, `traversalSkill`, `evadeSkill`, `countsAsMovementAbility`;
  - weapon requirements: `requireWeaponType`, `permittedWeaponTypes`, `requiresSheild`, `requiresDualWielding`.
  - Minion/totem from `tagNames` (Minion / Totem) and category.
- **Scaling:**
  - `attributeScaling [{attribute, stats:[Stat]}]` and `levelScaling [{stats}]` — game `Stats.Stat` format: property, specialTag, tags, extraTag, addedValue, increasedValue, moreValues;
  - `statsDuringUse`, `statsSource`.
- **Prefab:** `abilityPrefab {key, bundle, root, error}`. `key` — m_Container key (soft ref).
- **`damage[]`** — each damage component in prefab, including children:
  - `class`, `go` (object path);
  - `damage[7]` order Phys, Fire, Cold, Lightning, Necrotic, Void, Poison, plus `damageByType`;
  - `critChance`, `critMultiplier`, `critType`, `isHit`, `addedDamageScaling` (ADE);
  - `cullPercent`, `increasedStunChance`, `freezeRate`, `additionalLeech`;
  - `convertAllAddedDamage`, `damageTypeToConvertTo`, `penetration[]`, `conditionalEffects[]`;
  - `damageTags` + `damageTagNames`, `damageModifier`, `distanceScaling`;
  - `other` — component scalars, e.g. interval at `Repeatedly…`;
  - `nestedPrefab` — if component in nested prefab.
- **`primaryDamage`** — first damage component (convenience).
- **`ailmentsOnHit[]`:** `{class, go, ailments:[{ailment(Ailment name), chance, rolledSeparately, damageModifier, increasedDuration, increasedEffect}], other}`. All components with field `ailments` (ailment PPtr), aura / radius appliers too.
- **`summons[]`:** `{actor, actorName, field, go}`.
- **`subAbilities[]`.**
- **`mutator`:** `{class, bundle, matchedBy?, nonZeroDefaults, statLists}`.
  - Serialized mutator defaults on player prefab, most fields zero: trees set them.
  - Mutator → ability: by `abilityRef.key` (50 cases) or class name (`FireballMutator` → `Fireball`, `matchedBy:"className"`). Total 150.
- **Text:** `description`, `altText`.

### 2.2 `monster_abilities_index.json`
3305 records `{pathID, key, name, abilityName, playerAbilityID|null}`. Some monster copies have `playerAbilityID`: monsters re-use player IDs.

### 2.3 `minion_actors.json`
59 records `{actorData, actorName, id, actorBundle, summonedBy[], abilities[]}`, e.g. `PrimalWolf ← SummonWolf | [PrimalWolf 01 melee, BasicEnemyMelee]`.

### 2.4 `trees.json`
150 trees: `{kind: skill|passive|weaver, name, treeID, version, uiBundle, uiClass, panelBundles[] (passives), ability{name, playerAbilityID, pathID} (skill), classes[{className, classID, masteries[]}] (passives), uiOnlyNodes[], nodes[]}`.

Node fields:
- `id`, `name` (internal from GTD, `updateMutator` switches on it), `displayName`;
- `maxPoints`, `requiredMastery`, `masteryRequirement`, `requirements[{nodeID, requirement}]`;
- `description`;
- `position` — `RectTransform.anchoredPosition` in panel. Matches Maxroll `transform`; Maxroll root offset (0.23, −0.80);
- `panel` (parent GameObject), `mastery` (from UI), `noScalingType` (0 SinglePoint, 1 PointThreshold), `noScalingPointThreshold`;
- `abilityGrantedByNode` (for Weaver `nodeEffect`), `hasUI`, `notInUINodeList`, `uiMismatch` (now 0).

Structure (maxPoints, requirements, mastery) from GTD, authoritative: `LocalTreeData` uses it. UI fields added on top.

### 2.5 `tree_node_stats.json`
Object key `"<treeID>:<nodeID>"`, 4725 nodes. Hints at 4423 nodes, 8038 stat lines total.

Record fields:
- `treeID`, `treeKind`, `nodeID`, `nodeName`, `displayName`, `maxPoints`;
- `noScalingType`, `noScalingPointThreshold`;
- `description`, `nodeDescription` (old, values may be stale), `pointBonusDescription`, `altText`;
- `automaticStats[]` — `AutomaticNodeStat` from UI: `{property, specialTag, tags, extraTag, modType, value, scaling, threshold}`;
- `globalTreeDataStats[]` — same from GTD `nodeStatsData`;
- `tooltipStats[]` — `{statName, value, noScaling, downside, property, tags, tagNames, overrideSprite, icon, propertyKind: SP|TooltipList|Ailment, propertyName, num, unit (%, #, s, x, m or null), explicitSign}`. `num` — per-point number;
- `propertiesForAltText[]`.

### 2.6 Service files
- `tree_ui_sources.json`: picked bundles, dupes, discarded copies.
- `dump/assets/bundle_index.jsonl`: **all** 26,665 bundles. Line: `{bundle, size, files:[{cab, externals, classes{}, scripts{class: count}, container[{key, pathID, class, name}]}]}`.
  - Index builds in **63 s** (20 processes): headers and `script_types` only, object data not parsed.
  - Worth re-use by other agents for any class search in bundles.

## 3. Scripts (`tools/extract/`)
| Script | What |
|---|---|
| `bundle_index.py` | Bundle index (multiprocessing, one bundle per process in memory) |
| `common.py` | Paths, `load_scripts` (pathID MonoScript → class from monoscripts.bundle), `open_bundle`, `script_class`, `softref_key`, `BundleIndex` |
| `extract_trees.py` | Builds `trees.json`, `tree_node_stats.json`, `tree_ui_sources.json` (≈10 s) |
| `extract_abilities.py` | Builds `abilities.json`, `minion_actors.json`, `monster_abilities_index.json` (≈25 s). Needs `trees.json` |
| `jslit.py` | JS-literal parser LE Tools (verification only) |
| `crosscheck_abilities_trees.py` | Checks Maxroll `data.json` and LE Tools `planner/js/<md5>.js`. File paths passed args, no third-party data in repo |

Order after patch: `bundle_index.py` → `extract_trees.py` → `extract_abilities.py` → (optional) `crosscheck_abilities_trees.py`.

## 4. Subtleties found during extraction
- **`AbilityRef{key}`.** Mutators and many components ref ability not PPtr but via key from `keyedArray`. Unset `AbilityRef` serializes key **Fireball** (AbilityID 1, key −648846322).
  - No filter Fireball "used" 11 minions (`BasicMeleeMutator.abilityRef`) and Ice Rune.
  - Single field with this key on non-Fireball component treated empty (**D?**).
- **Mutators.** 500 of 600 on player prefab `abilityRef.key = 0`: ability tied in code, heuristic by class name. Boss/monster mutators (other bundles) excluded.
- **Damage by code.** Some skills **have no damage in assets**: Anomaly, Snap Freeze, Abyssal Echoes, Bone Curse, Spirit Plague, Aura of Decay. Via ailments or code `setBaseDamage` in mutator, 06b §1.7.
  - Many skills damage in sub-abilities. E.g. Meteor → `MeteorAoe` 240 fire, ADE 12; Glacier → `Glacier1..3`.
  - "Skill → sub" in `subAbilities` and `parents`.
- **`abilityGrantedByNode`** at 805 nodes. More "linked ability for hint" than actual skill grant.
- **Two mastery-panel copies differ in values.** Use `PassivePanelData.masteryPanels` (§1.1).

## 5. Verification vs LE Tools (v150) and Maxroll (data.json 2026-10-02)
All overlapping records compared, not sample.

| Comparison | Volume | Mismatches |
|---|---|---|
| Abilities vs LE Tools (by `playerAbilityID` / `internalName` = AbilityID): tags, manaCost, channelCost, minimumManaCost, useDelay, useDuration, speedScaler, speedMultiplier, maxCharges, chargesGainedPerSecond, skillTreeConversionDamageTags, attributeScaling; root prefab damage (damage[7], crit, critMulti, ADE, isHit) | 555 abilities, 330 with damage | **0** |
| Abilities vs Maxroll (by m_Name): same + ailment chances | 567 abilities, 337 with damage | 42. All 42 — components Maxroll doesn't export: DoT and aura with `isHit=0` (Black Hole 48 cold ADE 2.4, Tornado 9 phys ADE 0.45, Infernal Shade, Devouring Orb DoT 5 void…), and radius appliers (Aura of Decay Poison, Smoke Bomb Blind/Haste…). **No mistakes in shared fields** |
| playerAbilities list vs Maxroll `playerAbilityList` | 183 | 0 |
| Skill and passive trees vs Maxroll: maxPoints, masteryRequirement, displayName, requirements, all hint lines (value, property, tags), positions | 142 trees, 4577 nodes | 1: root `vo54` position (Maxroll offset 0.23 / −0.80) |
| Skill trees vs LE Tools (`LESkillTrees` + UI) | 136 trees, 3956 nodes | 4 positions (≤9 px: LE Tools stores `rect` different anchor) |
| Passives vs LE Tools (`LECharTrees`) | 5 trees, 541 nodes | 0 |
| Weaver vs LE Tools | 80 nodes | 1: node 191, first hint line: ours `''`, LE Tools `'50%'`. LE Tools probably fills value itself |

Manually verified examples (match LE Tools, damage order Phys, Fire, Cold, Light, Necr, Void, Poison):

| Ability | Damage | Crit | ADE | Duration / speed | Mana / CD |
|---|---|---|---|---|---|
| Fireball | Fire 25 | 5% | 1.25 | 0.75 Cast | 3 |
| Lightning Blast | Light 21 | | 1.0 | | |
| Smite | Fire 30 | | 1.5 | | 3 |
| Volcanic Orb | Fire 40 | | 2.0 | | 50 mana, CD 3.03 |
| Static | Light 50 | | 2.5 | | CD 4 |
| Javelin | Phys 50 | | 2.5 | 1.2 | 9 |
| Shurikens | Phys 25 | | 1.25 | | |
| Shield Throw | Phys 45 | | 2.25 | | |
| Hammer Throw | Phys 22 | | 1.1 | | |
| Heartseeker | Phys 20 | | 1.0 | | |
| Multishot | Phys 6 | | 1.2 | | |
| Rip Blood | Phys 20 | | 1.0 | | |
| Marrow Shards | Phys 25 | | 1.25 | | |
| Disintegrate | Fire 12 + Light 12 | 50% | 1.2 | 0.2 | CD 0.8 |
| Ghostflame | Fire 17.5 + Necr 17.5 | 50% | 1.75 | | |
| Forge Strike | Phys 2 | | 6.0 | | CD 4 |
| Erasing Strike hit | Void 2 | | 6.0 | | |
| Shadow Cascade | Phys 2 | 10% | 3.0 | | |
| Meteor (MeteorAoe) | Fire 240 | | 12 | | |
| Frost Claw main | Cold 20 | | 1.0 | | |
| Runebolt | Fire 25 | | 1.25 | | |
| Swipe | Phys 2 | | 1.0 | 0.7 | |
| Rive | Phys 2 | | 1.25 | | |
| Warpath hit | Phys 1 | | 0.6 | | |

## 6. Could not establish
1. **Node stat type and scope in skill trees.**
   - Hint gives magnitude and SP / category only. Added, increased or more, where written (mutator field or stat) from code `*Tree.updateMutator`.
   - This `mutator_coeffs.py` / 07c zone, output `skill_node_effects.json`.
   - For verification LE Tools `skillBonuses` / `passiveBonuses` useful (same planner.js): structured `{value, type 0/1/2, property, tags, per}` per node.
2. **Passive node stats in code.** Applied in `<Class>Tree.updateMutator`, KnightTree.updateMutator didn't decompile (Ghidra timeout). Assets hint only. Work hypothesis: "increased" lines — INC, "+N" — ADDED; verify via ISIL.
3. **Ability damage by code** (Anomaly, Snap Freeze, Abyssal Echoes, Bone Curse…). Search `setBaseDamage` and `BaseDamageStats` in `*Mutator` (ISIL).
4. **Full item-proc list.** "Unique → AbilityID" in code (PlayerProperty handlers) or item data. From ability assets not derive. Category `abilityIdOnly` merges such procs with monster AbilityID. Split via item data (`uniques.json` of another agent) or LE Tools `triggeredAbilities`.
5. **Node icons.** `SkillTreeNode.icon` refs Sprite in external bundle (saved as `iconImage {cab, pathID}`), sprite name not resolved. Hint stat lines have icon name (`icon` = `subPath` soft ref).
6. **Minion stats** (health, armor, base melee damage from `ActorData` and actor prefabs) not extracted. Gathered minion abilities and prefab bundles only (`minion_actors.json`).
7. **Default `AbilityRef` value** (Fireball key) derived empirically (**D?**). Verify via `AbilityRef` ctor in dump.
8. **`nodeDescription`** — old hint, values stale (Knight Vitality: "[10%]" vs hint 5%). Use `tooltipStats` only.
