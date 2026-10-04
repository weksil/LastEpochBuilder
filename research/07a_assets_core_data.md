# 07a — Game data from Last Epoch 1.5.0 assets: classes, attributes, properties, monsters, ailments, items

Date: 2026-10-03. Source: AssetRipper export `dump/assets/ar2/ExportedProject/Assets/` (YAML), plus `global-metadata.dat` for ActorScaler tables. Code (addresses, formulas) — from `dump/decomp`, `dump/isil`, `dump/cs`, as in 06a–06e.

Labels: **A** — value read from asset; **D** — from code; **D?** — from code, but interpretation ambiguous; **X** — confirmed by external data (Maxroll / LETools).

---

## 0. Main points

1. **Conflicts 02/06a closed by data (A, X).** All five `CharacterClass` records store `healthPerLevel = 10` (int) and `healthRegenPerLevel = 0.14`. Guide (8 and 0.125) outdated. With formula 06a gives `Health(L) = 100 + 10·L` and `HealthRegen(L) = 6 + 0.14·L`. `manaPerLevel = 0.50506`, `baseMana = 50`, `manaRegen = 8`. Minion strength: `26 / 0.008 / 0.008` (A, confirms 06e). All classes same `baseEndurance = 0.2`, `enduranceThresholdPerHealth = 0.2`, `baseMoreDoTDamageTaken = −0.15`, `baseStunAvoidance = 250 + 5·L`. Classes differ only in starting attributes.
2. **Serialized `GlobalPlayerProperties` diverges from constructor defaults (A).** `bossEffectiveHealthModifierVsStun` and `bossEffectiveHealthModifierVsFreeze` equal **0.5**, not 0.25, as 06c §4 assumed. So for bosses `EH × 1.5`, matches guide and 02 §5.4. Ward decay constants match defaults: `q = 5e−5`, `l = 0.2`, min 0.5/s.
3. **Affixes: effect modifier computed vs "standard" base (D, correction to 06a §7.1).** `AffixList+Affix.getModifier` @0x1811B13C0 returns `m = (1+itemAEM)/(1+affix.standardAffixEffectModifier) − 1`, equals 0 if equal. Tier values in `AffixList` stored for base with `standardAffixEffectModifier`. Formula 06a §7.1 should use `m`, not raw `affixEffectModifier` of item. Example: Added Melee Physical Damage T8 [85, 100] with standard 0.75 on 2H axe (AEM 2.2) gives `m = 3.2/1.75 − 1 = 0.8286` and range [155, 183].
4. **Monster rarity goes via `MonsterRarityManager.setActorRarity` @0x1827FE1B0 (D, ISIL).** Both `ChangeStatModifier` calls use ModType 2 = **MORE**:
   - magic: Health MORE +1.15 (×2.15), Damage MORE +0.6;
   - rare: Health MORE +1.6 + 0.02·L′, Damage MORE +0.9;
   - L′ = L / (1 + 0.5·effHM), if `UnitHealth.healthSerialisation == 1`.

   Tunklab's "×2.15" confirmed for magic.
5. **Corruption mod (A).** `Monster Power From Corruption Mod`: Health MORE 0.01, Damage(Hit) MORE 0.01, **Damage(DoT) MORE 0.005**, plus increasedItemRarity 0.01 per effect unit. Effect equals `f(c) − 1` (06c). Monsters' DoT grows from corruption **twice as slow** as hits and health.
6. **ActorScaler tables (D/A).** All four float[101] arrays (`damageReduction`, `effectiveHealthModifier`, `damageModifier`, `originalDamageApproximation`) extracted from `global-metadata.dat` match reference points 06c.
7. **Ailments: gaps 06d closed (A).**
   - Blind = `CriticalChance MORE −1`, i.e. "cannot crit".
   - Frenzy = +20% increased attack and cast speed.
   - VoidResShred = −5% void res per stack.
   - PhysicalResShred has id 73.
   - ExposedFlesh: −15% cold res and +30% chance to be frozen, `mutationType = AbilityMutator`.
   - `addedDamageScaling`, `penetration`, replacement flags and `mutationType` present for all 149 assets.
8. **Verification (X).** Compared all:
   - vs Maxroll: 1156 affixes, 781 bases and subtypes, 486 uniques, 24 sets, 128 ailments, 113 rounding rules, 712 player properties, 63 blessing lists, 5 classes;
   - vs LETools: 234 monster mods, 5 attributes.

   **Zero** value discrepancies. Only differences in completeness (§9).

---

## 1. How to run

```
tools/venv/Scripts/python tools/extract/extract_classes.py    # classes, attributes, global_player_properties
tools/venv/Scripts/python tools/extract/extract_monsters.py   # monster_rarity, monster_mods, actor_scaler
tools/venv/Scripts/python tools/extract/extract_ailments.py   # ailments
tools/venv/Scripts/python tools/extract/extract_items.py      # affixes, items, uniques, sets, idols, blessings
tools/extract/crosscheck_maxroll.py <maxroll data.json> [letools coreDB.js] [letools endgame.js]
```

`tools/extract/le_assets.py` — common loader. What's handled:
- PyYAML (CSafeLoader) with extended float resolver: Unity writes `5E-05`, YAML 1.1 reads as string.
- AssetRipper writes primitive arrays (`List<int>`, `List<byte>`) as one hex-string little-endian (`canRollOn: 15000000160000001400000004000000` = [21, 22, 20, 4]). Loader quotes such scalars so YAML doesn't turn them into octal int, `hex_ints()` decodes them.
- guid → path from `.meta` (cache `dump/assets/guid_index.tsv`).

PyYAML installed in `tools/venv`. Full run ~12 s. After patch only new AssetRipper export needed. ActorScaler signatures searched by reference values (§4.3); if EHG changes tables, search reports it.

Common envelope of each file: `{gameVersion, source, schema, ...extra fields, data: [...]}`.

### 1.1 How values map to stat model (06a §11)

Each mod in all files normalized same way (`le_assets.norm_stat` / `extract_items.stat_key`):

| Field | Meaning |
|---|---|
| `property` / `propertyName` | SP (0–133), name from `sp_enum.json` |
| `specialTag` | subtype: AilmentID, HitEventTag, CDP, AbilityProperty index; 0 — wildcard |
| `tags` / `tagNames` | AT mask (subset semantics + Elemental rule). `tagNames` **not output** if `tags` — index: SP 58 (AbilityID), 98 (PlayerProperty index), 100 (AilmentID), 104/105 (drop category: when `specialTag = 0` this is EquipmentType, see `dropRateItemType`), 123 (Tracker), 130 (IdolAltar) |
| `extraTag` | AbilityID (mod tied to skill) |
| `added` / `increased` / `more[]` | for Stat-like records (attributes, buffs, monster mods) |
| `modType` | ADDED / INCREASED / MORE / QUOTIENT. For affixes, implicits, uniques and sets type explicit, one value (`value`, `[min, max]`); for Stat records computed by `Stat.GetModType` |
| `rounding` | quantization grid for this mod (§3.2) |

---

## 2. classes.json, attributes.json

### 2.1 classes.json (A; formulas D from 06a §5.3)

`data[]` contains 5 records by `classID`: Primalist 0, Mage 1, Sentinel 2, Acolyte 3, Rogue 4.

| Field | Value / example |
|---|---|
| `className`, `treeID` | `Acolyte`, `ac-1`. Trees: pr-1, mg-1, kn-1, ac-1, rg-1 |
| `passiveTree` | `{name, treeID, version, nodeCount, nodesPerMastery}` from Global Tree Data, e.g. Acolyte {0: 15, 1: 29, 2: 34, 3: 31} |
| `base` | all numeric fields CharacterClass (see §0 p. 1) |
| `minionScaling` | `{firstLevelForMinionScaling: 26, moreMinionDamagePerLevel: 0.008, lessMinionDamageTakenPerLevel: 0.008}` |
| `levelMods[]` | stat model SetInitialValues: `{property, modType, base, perLevel, tags?}` (Health, Mana, HealthRegen, ManaRegen, StunAvoidance, Endurance, EnduranceThreshold, SP96, DamageTaken DoT MORE, 5 attributes). Value = base + L·perLevel |
| `masteries[]` | `masteryIndex` 0–3 (0 — base class; node trees' `requiredMastery` value), `name`, `masteryAbility {asset, name, playerAbilityID}`, `abilities[{…, level}]`, `passiveNodes` |
| `defaultAbilities`, `knownAbilities`, `unlockableAbilities`, `basicAttackReplacer`, `startingItems` | Ability refs, resolved to `{asset, name, playerAbilityID}` |
| `specialTagForClassSpecificLevelOfSkillsStats` | specialTag for "+N to class skills" |

File-level also `hiddenBaseMods` (code constants, 06a §5.3: AttackSpeed/CastSpeed BASE 1, Movespeed MORE 0.05, minion Movespeed MORE 0.10, IncreasedStunChance INC 1.0 Melee|Bow, minion DamageTaken MORE −0.6) and `formulas`.

Starting attributes: Primalist Str 2 / Att 1; Mage Int 3; Sentinel Str 2 / Vit 1; Acolyte Int 2 / Vit 1; Rogue Dex 3.

### 2.2 attributes.json (A, X)

`data[]` contains 5 records: `{attribute, name, statProperty (19–23), perPoint[], corruptedPerPoint[], corruptedFlag{property 98, tags 650–654, playerPropertyName}}`.

| Attribute | Per point | Corrupted (replaces perPoint) |
|---|---|---|
| Strength | Armour INC +4% | PlayerProperty 636 ("Damage for Melee Attacks per 1 Mana Cost (up to 20)") MORE 0.0002; HealthLeech INC −0.5% |
| Vitality | Health +6; Necrotic Res +1%; Poison Res +1% | EffectOfAilmentOnYou INC +3%; PlayerProperty 638 ("Damage Taken while you don't have Frenzy") MORE 0.001 |
| Intelligence | WardRetention +2% | CritMultiplier (Spell) +1%; ReducedBonusDamageTakenFromCrits −1% |
| Dexterity | DodgeRating +4 | AbilityProperty (acolyteEvade, idx 9 "Increased Cooldown Recovery Speed for Movement Skills") +0.3%; Armour INC −1% |
| Attunement | Mana +2 | ManaRegen INC +2%; PlayerProperty 637 ("Current Health lost when you directly use a Skill") +0.2% |

Corruption flag: SP98 with tags 650 (Str, "Strength Converted to Brutality"), 651 (Int), 652 (Dex), 653 (Att), 654 (Vit). These indices match 06a §5.1 and PlayerPropertyList names.

---

## 3. global_player_properties.json

### 3.1 GlobalPlayerProperties (A)

`data.globalPlayerProperties` contains all asset fields. Important for formulas:

| Field | Asset | Constructor default (06c) |
|---|---|---|
| quadraticWardDecay | 5e−5 | 5e−5 |
| linearWardDecay | 0.2 | 0.2 |
| minimumWardDecayWithoutRegen | 0.5 | 0.5 |
| **bossEffectiveHealthModifierVsStun** | **0.5** | 0.25 |
| **bossEffectiveHealthModifierVsFreeze** | **0.5** | 0.25 |
| bossWardGainModifier | −0.25 | — |
| bossWardPercentDecay / …PerSecond / …PerSquareSecond | 0.04 / 0.005 / 3e−5 | — |
| baseBossWardDecayEffectiveTimeDivisor / …PerEffectiveHealthMultiplier | 0.75 / 0.0075 | — |

Comparison in `data.assetVsConstructorDefaults`. Boss ward fields relate to **bosses' ward**; formulas in code not parsed (§10).

### 3.2 Properties, display and quantization grid (A, X)

| Key | Source | Schema |
|---|---|---|
| `statProperties[113]` | MasterPropertyList | `{property, name, spName, roundingForAdded, roundingForMore, roundingForIncreased: "Hundredth", moreRoundingOverrides[{specialTag, roundingForMore}], display{…flags ≠ 0}, altText}` |
| `conditionalDamageProperties[48]` | same | CDP texts by index |
| `playerProperties[713]` | PlayerPropertyList | `{index, name, rounding…, display}`. Index = `tags` at SP98 |
| `abilityProperties[177]` | AbilityPropertyList | `{abilityID, abilityIDName, properties[{index, name, rounding…}]}`. `index` = specialTag at SP58 |
| `trackerProperties[2]`, `idolAltarProperties[31]` | TrackerPropertyList, IdolAltarPropertyList | same |
| `propertyRoundingEnum`, `propertyRoundingScale` | `PropertyRounding` | Hundredth 0 → ×100, Integer 1 → ×1, Tenth 2 → ×10, Thousandth 3 → ×1000 |

How rounding picked for mod (`extract_items.Rounding.get`; repeats `BasePropertyInfo.GetRounding`, 06a §7.1):
- ADDED → `roundingForAdded`;
- INCREASED → always Hundredth;
- MORE → `moreRoundingOverrides[specialTag]`, else `roundingForMore`.

For SP98, SP58, SP123 and SP130 PropertyInfo taken from its own list by index.

Distribution across affixes: Hundredth/ADDED 779, Integer/ADDED 503, Hundredth/INCREASED 373, Thousandth/MORE 18, Hundredth/MORE 10, Tenth/ADDED 7, Thousandth/ADDED 6.

---

## 4. Monsters

### 4.1 monster_rarity.json (A + D)

`data = {magic, rare}`, fields `MonsterRarityManager+MonsterRarity`:

| | increasedHealth | …PerLevel | additionalEffectiveHealthModifier | increasedDamage | increasedExperience | …PerLevel | increasedItemDrops | increasedSize | prefix/suffix |
|---|---|---|---|---|---|---|---|---|---|
| magic | 1.15 | 0 | 1 | 0.6 | 0.5 | 0 | 2.05 | 0.2 | 0 / 1 |
| rare | 1.6 | 0.02 | 2.5 | 0.9 | 2.0 | 0.04 | 5.2 | 0.5 | 1 / 1 (guaranteedRareItemDrop) |

Order in `setActorRarity` (D, ISIL @0x1827FE1B0):
1. `UnitHealth.effectiveHealthModifier += additionalEffectiveHealthModifier`.
2. `hpl = increasedHealthPerLevel`; if `healthSerialisation == 1` and effHM > 0, then `hpl /= (1 + 0.5·effHM)`.
3. `ChangeStatModifier(Health, increasedHealth + level·hpl, MORE)`.
4. `ChangeStatModifier(Damage, increasedDamage, MORE)`, no tags.
5. Experience `×(1 + inc + level·incPerLevel)`; drop chance `×(1 + increasedItemDrops)` with overflow carry into count; size `×(1 + increasedSize)`.

Example: rare at level 100 with effHM = 2.5 → hpl = 0.02/2.25 = 0.00889 → Health MORE +2.489 (×3.489), Damage ×1.9.

### 4.2 monster_mods.json (A, X)

`data[239]` (StatsMonsterMod):
```
{key, name, modType(Prefix|Suffix|Monolith|Dungeon|EventActor|TimeBeast), title, description, minilithDescription,
 inRarePrefixPool, inSuffixPool, monolith{timelineIDs[], differentForEmpowered, empoweredTimelineIDs[]},
 minimumLevel, rarityRequirement, increasedItemRarity, increasedExperience,
 stats[normalized Stat], rareModifier, scalingType(None|Level|Health), flatScaling, perUnit, perUnitSquared,
 onlyScaleSomeStats, numberOfStatsToScale, effectModifierEffect(Full|None|Capped|Partial|CappedPartial),
 effectModifierCap, statsWithoutEffectModifier, incompatibleETags, necessaryETags, soulGambler…}
```

Additional:
- `otherMonsterMods[51]` — Component/PseudoComponent/CastsAbility/ContractsAilments mods, name, key and description only;
- `timelines[]` — per timeline: `difficulties[{level, modFromCorruption, minimumCorruption, maximumCorruption, additionalCorruptionEffect(None|Level|RewardRarity), corruptionRequiredPerLevel}]`, `mods`/`empoweredMods` with names and depth, `modEffectivenessFormulae`.

Mod stat scale (06e §5.2): `k = (isRare ? 1 + rareModifier : 1)·(1 + effect)·(flatScaling + perUnit·x + perUnitSquared·x²)`. Examples:
- "Increased Health": Level, flat 1, perUnit 0.01;
- "Increased Damage": Level, 1 / 0.0025, rareModifier 0.1;
- monolith mods: Capped, cap 0.75–3.

Timelines (normal): level 62/66/70/74/78/82/85/90/90/90, corruption 0–50, `Level`. Every 5 corruption (10 for T7–T10) +1 zone level. Empowered: level 100, corruption ≥ 100, `RewardRarity`.

### 4.3 actor_scaler.json (D/A)

`data.tables` contains four float[101] arrays (index — monster level), `metadataOffsets` (DR 18405528, effHM 18406016, dmgMod 19215768, origDmg 19216256), `constants` from ActorScaler.cs and `formulas`.

| | L0 | L50 | L100 |
|---|---|---|---|
| damageReduction | 0 | 0.54 | 0.87 |
| effectiveHealthModifier | −0.09 | 0.24 | 0.95 |
| damageModifier | −0.05 | −0.13 | 0.157 |
| originalDamageApproximation | 1.30 | 9.36 | 15.25 |

`research/data/monster_level_damage_reduction.json` (06c) matches `tables.damageReduction` byte-for-byte. Search by signature values (§10 p. 6).

---

## 5. ailments.json (A, X)

`data[149]` — all `LE:Ailment` assets. 148 in `AilmentList`; `Morditas Gauntlet Enemy Buff` (id 60, duplicate ShrineHaste) not in list, so `inList = false`. `AilmentList.list` has 150 refs, 2 duplicates (indices 111 and 118).

Schema: all serialized numeric and bool fields of Ailment (UI, icons and VFX dropped), plus:
- `id`, `ailmentIDName`, `name`, `inList`, `listIndex`;
- `duration`, `maxInstances`, `positive`, `tags` and `tagNames`;
- `baseDamage{damage[7], damageByType, critChance, critMultiplier, critType(+Name), isHit, addedDamageScaling, penetration[], freezeRate, cull…, additionalLeech, leechVsPlayers, convertAllAddedDamage, damageTypeToConvertTo, conditionalEffects}`;
- `effectOfIncreasedEffectiveness(+Name)`, `additionalPenetrationDamageType(+Name)`, `buffScalingType(+Name)`, `maxStacksThatApplyBuffs`, `buffs[normalized Stat]`, `moreBuffEffectAgainstBosses`, `moreBuffEffectAgainstPlayers`;
- `dealsDamage`, `dealsAllDamageAtEnd`, `dealsDamageWhenHit`, `moreDamageWhenHitByCreator`, `dealsDamageWhenAffectedHitsOthers`, `dealsDamageOnAnguish`, `damageScalesWithTargetHealth`, `moreDamageAtFullHealth`, `moreDamageAtHealthThreshold`, `moreDamageHealthThreshold`;
- `spreads`, `spreadRange`, `spreadDelay`, `maxSpreadPerInstance`, `heals`, `totalHealingOverDuration`;
- `effectOfEffectivenessOnProc`, `procsAbilityWhenStacksReached`, `abilityToProcWhenStacksReached` (name), `stacksRequiredForProc`, `procsAbilityOnExpiration`;
- `dontReplaceHigherDurationStacks`, `prioritiseStrongestStacks`, `replaceLowestDamageStacksInsteadOfOldest`, `stopsWhenHit`, `hitsRequiredToStop`;
- `blinds`, `roots`, `isCurse`, `isBrand`, `uncleansable`, `mutationType(+Name)`, `abilityForMutation`, `receiverMutationType(+Name)`, `expiresWithCreatorDeath`, `movementAilment*`.

File-level: `shrineBuffs` (6) and `integrity`.

Damage type order: `damageTypeOrder = [Physical, Fire, Cold, Lightning, Necrotic, Void, Poison]`.

Answers to 06d §7 questions:

| Ailment | Answer |
|---|---|
| Blind (14) | buffs: CriticalChance MORE −1 → crit impossible (06d p. 6) |
| VoidResShred (30) | NegativeVoidResistance +0.05, Grouped, boss −0.6 |
| Frenzy (34) | AttackSpeed INC +0.2, CastSpeed INC +0.2 |
| ExposedFlesh (137) | ColdResistance −0.15, IncreasedChanceToBeFrozen +0.3; addedDamageScaling 4; mutationType AbilityMutator |
| PhysicalResShred | id **73** |
| addedDamageScaling | Ignite, Bleed, Poison: 0; shreds: 1; Laceration 3; AbyssalDecay 5; Decrepify 10; Torment 6; SpiritPlague 4.5 |
| baseDamage.penetration | all 149 empty list; penetration set via `additionalPenetrationDamageType` |

---

## 6. affixes.json (A, X)

`data[1156]`, key `affixId` (shared for single and multi, no collisions):
```
{affixId, kind(single|multi), name, displayName, title, type(PREFIX|SUFFIX|SPECIAL),
 rollsOn(Equipment|Idols), specialAffixType(Standard|Experimental|Personal|Set|IdolEnchantment|IdolWeaver|Corrupted|FakeUniqueMod),
 isIdolAffix, isExperimental, isPersonal, isSetAffix, isCorrupted, classSpecificity[classes],
 levelRequirement, group, weighting, standardAffixEffectModifier, canRollOn[EquipmentType], canRollOnNames,
 specificRerollChances[], convertOnIncompatibleItemType, affixIDToConvertTo, t6Compatibility,
 maximumAffixEffectModifierForT6, displayCategory, uniqueId, weaponEffect,
 properties[{property, propertyName, specialTag, tags, tagNames, extraTag, modType, rounding, setProperty, displayName?}],
 tiers[{tier 1..N, rolls[[min,max] per properties[j]]}]}
```

Composition:
- single: 470 prefix and 146 suffix; multi: 414 prefix and 126 suffix;
- by type: Standard 770, Corrupted 134, IdolWeaver 66, Set 61, IdolEnchantment 49, FakeUniqueMod 38, Personal 26, Experimental 12;
- idol affixes 472;
- tiers: 8 on 684 affixes, 1 on 423, 7 on 49.

**Sealed** — affix state on item (ItemData), not affix property. No such flag in data.

**Value model (D):**
```
m  = (itemAEM == std) ? 0 : (1+itemAEM)/(1+std) − 1          // Affix.getModifier @0x1811B13C0
itemAEM = items.json baseTypes[].affixEffectModifier (for OmenIdol subtypes — ItemList.omenIdolAffixEffectModifier)
lo = min·(1+m);  hi = max·(1+m);  s = scale(rounding)
a = RoundHalfEven(lo·s); b = RoundHalfEven(hi·s)
v = min(floor((b−a+1)·roll/255 + a), b) / s                    // roll — byte 0..255
```

Values `standardAffixEffectModifier`: 0 (821), 0.5 (82, armor), 0.75 (59, 1H), 0.17 (48), −0.83/−0.62/−0.33/−0.05 (idols), 2.2 (14, 2H).

Test vectors (Python `round` = half-even; game float32):

| Affix, tier, base | m | roll | → |
|---|---|---|---|
| Added Health (25) T5 [61, 90], helmet | 0 | 0 / 128 / 255 | 61 / 76 / 90 |
| same, chest (AEM 0.5) | 0.5 | 0 / 255 | 92 / 135 |
| Fire Resistance (13) T7 [0.61, 0.75], helmet | 0 | 200 | 0.72 |
| Increased Health (52) T6 [0.15, 0.20], chest | 0.5 | 100 | 0.25 |
| Added Melee Phys (63) T8 [85, 100], std 0.75, 2H axe (2.2) | 0.8286 | 255 | 183 |
| same, 1H axe (0.75) | 0 | 0 | 85 |

Binding to stat model: `properties[j]` + `tiers[t].rolls[j]` → `Mod{stat: property, sub: specialTag, tags, abilityId: extraTag, type: modType, value: v}`. For SP58 and SP98 tags — index (§1.1).

---

## 7. items.json, uniques.json, sets.json

### 7.1 items.json (A, X)

`data[41]` — EquippableItems without Blessing (34), by `baseTypeID`:
```
{baseTypeID, name, displayName, type, typeName, isWeapon, isIdol, maximumAffixes, maxSockets,
 affixEffectModifier, gridSize[w,h], classAffinity[], subTypeClassSpecificity, minimumDropLevel, obsoleteItemType,
 subItems[{subTypeID, name, displayName, levelRequirement, classRequirement[], subClassRequirement, cannotDrop,
           isCorruptedSubtype, isLegacySubType, obsoleteItem, affixEffectiveness(Default|OmenIdol),
           implicits[{property…, modType, rounding, value, maxValue}], attackRate?, addedWeaponRange?}]}
```

Total 699 subtypes. Additional: `nonEquippable` (9 bases, counters only), `equipmentTypeEnum`, `globals` (ice/blood forging, globalIdolRerollChance 0.1, omenIdolAffixEffectModifier 0), `disabledBaseTypesToRoll` [24 Crossbow, 11 1H Fist].

`attackRate` on weapons, e.g. Hatchet 1.05, Poignard 1.14, Gladius 1.12. This is `CharacterStats.getPropertyMultiplier` multiplier for AttackSpeed (06a §3). Implicits roll in `[value, maxValue]` like uniques.

AEM bases: body armor 0.5; 1H weapon and bows 0.75; 2H 2.2; shield, catalyst and amulet 0.17; idols −0.83 to 0.

### 7.2 uniques.json (A, X)

`data[489]`, key `uniqueID`:
```
{uniqueID, name, displayName, baseType, baseTypeName, subTypes[], levelRequirement(if override), isSetItem, setID,
 isPrimordialItem, isCocoonedItem, unifiedType, legendaryType(LegendaryPotential|WeaversWill), canDropAsLegendary,
 canDropRandomly, hideFromPlayers, overrideEffectiveLevelForLegendaryPotential, effectiveLevelForLegendaryPotential,
 dropsSpecificLegendaryAffixes, droppableLegendaryAffixCount, droppableLegendaryAffixes[affixId],
 excludeSpecificAffixesFromPrefixSuffixLimits, convertPotentialToLegendaryAffixes, additionalRandomLegendaryAffixes,
 isPreCorrupted, preCorruptPositiveChance, validPreCorrupts[], primordialCosts{},
 mods[{property…, modType, rounding, rollID, canRoll, value, maxValue, hideInTooltip}],
 tooltipDescriptions[{description, altText, setRequirement}], loreText}
```

Composition: 61 set items; 471 with LegendaryPotential and 18 with WeaversWill.

Value mod (D, `UniqueItemMod.getValue` @0x18126B510): if `canRoll && maxValue > value && roll ≠ 0`, then `GetValueAfterRounding(prop, tags, special, type, value, maxValue, roll)` — same grid as affixes, no AEM; else `GetFixedValueAfterRounding(value)`. `rollID` picks byte of item roll. Multiple mods with one rollID roll synchronously. Text descriptions (`tooltipDescriptions`) don't encode mechanics. Their effects besides stats in `unique_effects.json` (another agent's work).

### 7.3 sets.json (A, X)

`data[24]`: `{setID, setName, bonuses[{property…, modType, rounding, value, setRequirement, hideInTooltip}], tooltipDescriptions[], items[{uniqueID, name}]}`. `setRequirement` — how many set items needed.

---

## 8. idols.json, blessings.json

### 8.1 idols.json (A)

- `data[10]`: idol bases 25–33 and altar 41 in items.json schema. Sizes: Small 1×1 (−0.83), Small Lagonian 1×1, Humble 2×1 and Stout 1×2 (−0.62), Grand 3×1 and Large 1×3 (−0.33), Ornate 4×1 and Huge 1×4 (0), Adorned 2×2 (−0.05). Idols have `maximumAffixes = 2`, altar 4 (13 subtypes).
- `containerGrids`: `IdolsContainerGridDataList` serialized Odin (`SerializedBytes`). Parsed by `odin_decode()`. `defaultData` and `data[13]` (by altar subtype) — 5×5 matrices `unlockMatrix`:
  - 99 — locked cell;
  - 1–8 — reward slot open number;
  - +100 — refracted slot.

  Index order (D): `int[,] unlockMatrix` indexed `[x, y]`. `IdolsContainerGridData.get_BlockedCellsPositions` loops `[i, j]`
  and for 99 adds tuple `(x: i, y: j)`. So inner JSON list — column, screen cell (row y, col x) = `m[x][y]`.
  Client transposes on load (`GameData._grid_rows`). Verified on subtype 4 altar vs game screenshot (LE Tools build ApbrXYvx).

  Example default: `[[99,7,6,5,99],[8,4,3,2,1],[8,4,99,1,1],[8,4,3,2,1],[99,7,6,5,99]]`.
- `idolAffixIds` — 472 idol affix ids (affixes themselves in affixes.json).

### 8.2 blessings.json (A, X)

`data[224]` (base 34 subtypes; 112 normal and 112 Grand):
```
{blessingId, name, displayName, levelRequirement, cannotDrop, implicits[{property…, modType, rounding, value, maxValue}],
 isGrand, grandVariantId | normalVariantId,
 timelines[{timelineID, timeline, difficultyIndex(0 normal / 1 empowered), slot(first|other|any)}]}
```

Plus `timelines[]`: `{timelineID, displayName, pairs[{name, normal, grand}], difficulties[{level, firstSlotBlessings[], otherSlotBlessings[], anySlotBlessings[]}]}`. Example: Cruelty of Formosus (14) gives IncreasedDropRate 0.30–0.45 on WAND (`specialTag 0`, `tags 10` = EquipmentType). Grand variant (127) gives 0.50–0.90 offered only in empowered.

---

## 9. Verification against external data

Script: `tools/extract/crosscheck_maxroll.py`. Compared **all** records, so sample ≥ 10 met with margin.

| Entity | Compared | Value discrepancies | Completeness differences |
|---|---|---|---|
| Classes (all base and minion fields) | 110 | 0 | — |
| Affixes (name, levelReq, canRollOn, tiers and extraRolls, property/tags/modType) | 1156 | 0 | — |
| Bases and subtypes (AEM, maxAffixes, implicits, levelReq, attackRate) | 781 | 0 | — |
| Uniques (all mods with rollID, LP level) | 486 | 0 | ours 3 extra: Sharktooth Saw (46) and Heirloom of Light (69) with `hideFromPlayers`, FleshofStone (248) |
| Sets | 24 | 0 | — |
| Ailments (duration, maxInstances, damage, addedDamageScaling, buffs…) | 128 | 0 | Maxroll missing ids 129–150 (Aterroth*, Silk, Spiders, **ExposedFlesh**, **Hemorrhage**, Bulwark, Disemboweled, etc.) — incomplete export |
| Property rounding and PlayerProperty names | 825 | 0 | ours 713 PlayerProperty, Maxroll 712; last — "Monstrous Rage minion explosion on death" |
| Blessing lists by timeline | 63 | 0 | — |
| Attributes (LETools coreDB) | 10 | 0 | — |
| StatsMonsterMod (LETools endgame, matched by name in loc key) | 234 of 239 | 0 | — |

Conclusion: Maxroll and LETools sourced from same serialization. Our extractor reproduces it exactly and more complete (new ailments, hidden uniques). Numbers independently output by Tunklab only (rarity, corruption) match assets: magic ×2.15 health; f(c) — 06c.

---

## 10. Could not establish

1. **Boss ward.** `bossWardGainModifier`, `bossWardPercentDecay*`, `baseBossWardDecayEffectiveTimeDivisor*` read, formula not parsed. Search in `ProtectionClass.Update` / `GlobalPlayerProperties.GetWardDecayRate` boss branch.
2. **`MonsterRarity` component on prefabs vs `MonsterRarityManager`.** Code has two paths: `setActorRarity` (manager data, ISIL confirmed) and `MonsterRarity.makeMonsterMemberOfRarity` (component fields `baseHealthMultiplier` etc., 06e §5.1). Monster prefabs not exported, unclear which path active for normal spawn and what numbers in component. Need xref `setActorRarity` ← `Spawner`/`MonsterGenerator` and if needed prefabs via UnityPy.
3. **`statsWithoutEffectModifier`** (int on monster mods): bit mask of stat indices or count — unchecked. Everywhere except Partial-mods value 0.
4. **SP104/105 semantics** (`specialTag` 1–4). When `specialTag = 0` `tags` = EquipmentType (verified on Cruelty of Formosus = WAND, Pride of Rebellion = Grand Idol). For 1–4 (non-equip, shards, …) need `ItemDrop`/`DropRateType` parse.
5. **`setProperty` argument** (`SingleAffix+0xC8`) passed to `GetValueAfterRounding_2` probably changes "set" affix quantization. Not parsed, affects 61 Set affixes.
6. **ActorScaler search robustness.** Tables found by signature values, not via `fieldDefaultValues` metadata parse. If patch changes reference values script returns `null`. Then need `Il2CppFieldDefaultValue` parser (handles `DAT_185347330`, `DAT_185347ee8`, `DAT_185351338`, `DAT_185351b08` in `ActorScaler..cctor`).
7. **PlayerProperty 636–638** (corrupted attribute effects) — indices from list. How they work (e.g. "per 1 Mana Cost up to 20") solved by CharacterMutator code; see `player_property_fields.json` and `pp_switch.py` of another agent.
8. **Float32.** Test vectors computed in double. Game computes `min·(1+m)·s` in float32, at .5 boundaries RoundHalfEven may differ. Engine needs `Math.fround`.
