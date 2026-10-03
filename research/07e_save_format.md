# 07e - Last Epoch 1.5.0 offline save format (character JSON + binary item blobs)

Date: 2026-10-03. Client: 1.5.0 (Unity 6000.4.8f1, IL2CPP). Sources: `dump/decomp/LE.dll` (Ghidra pseudo-C),
`dump/cs/DiffableCs` (field offsets, enums, JSON attribute names), `dump/isil` (to check two rounding functions),
`dump/inspector/symbols.tsv` (string literals), AssetRipper YAML (`MasterItemsList`, `MasterAffixesList`,
`UniqueList`, Quest assets). The local saves were opened read-only. Nothing was written to them.

Reference parser: `tools/extract/save_parser.py` (stdlib only). Run `--selftest` for the encode/decode round trip.

Confidence tags: **D** = read from decompiled code. **D?** = read from code, but the meaning is inferred.
**S** = seen in a real save file. **A** = from 1.5.0 assets.

---

## 0. TL;DR for the planner

* File = ASCII `EPOCH` + UTF-8 JSON (Newtonsoft, `CharacterData`). No compression, checksum or encryption. **D+S**
* Build data is plain JSON: `characterClass`, `chosenMastery`, `level`, `savedCharacterTree` (passives),
  `savedSkillTrees` (one per specialised skill; `treeID` = ability key, for example `ws54hm`), `abilityBar`,
  `savedWeaverTree`, `savedQuests`.
* Gear, idols, blessings and weaver-tree items are entries of `savedItems` (`ItemLocationPair`):
  `containerID` + `inventoryPosition` + `data` (a byte array written as a JSON int array).
* `data[0]` is the **item serialisation version**. Current = **6** (`ItemData.currentDataSerialisationVersion`).
  The game upgrades versions 0..5 on load by inserting bytes. After that every item has the same v6 layout (§3).
* An affix is **3 bytes**: `[tier<<4 | idHigh4][idLow8][roll]`. Affix IDs are **12-bit (0..4095)**. The tier nibble
  is 0-based (display tier = nibble + 1). Nibble 7 (T8) = primordial.
* Roll 0..255 → value: `v = floor((b−a+1)·roll/255 + a)`, clamped to b, on the PropertyRounding grid (§5).
  Affixes first scale the tier range by `(1+m)/(1+standardAffixEffectModifier)`. 06a §7.1 does not mention this factor.

---

## 1. Files

| Item | Value | Tag |
|---|---|---|
| Folder | `%USERPROFILE%\AppData\LocalLow\Eleventh Hour Games\Last Epoch\Saves` | S |
| Character slot | `<prefix>CHARACTERSLOT_BETA_<n>`. Regex in `OfflineCharacterService`: `(.*?)CHARACTERSLOT_BETA_(\d*)$`. Local sample: `1CHARACTERSLOT_BETA_0` | D+S |
| Backups | `<file>.bak` (previous write). `BACKUPCHARACTERSLOT…` (LocalCharacterSlots) | D+S |
| Stash / global | `STASH_CYCLE_{0}_{1}`, `…_TAB_n`, `Epoch_Local_Global_Data_Beta` (same `EPOCH` prefix) | D+S |
| Prefix | `SafeTextFile.TryRead` @0x18183b5c0: the content must start with `EPOCH` and have length ≥ 34, then `Substring(5)`. `ConvertFileIfOld` @0x18183abe0 adds the prefix to old JSON-only files | D |
| JSON | `CharacterDataSerializer.Serialize` @0x18285d8a0: `JsonSerializer.CreateDefault()` + `JsonTextWriter`, InvariantCulture. `Deserialize` = `JsonConvert.DeserializeObject<CharacterData>` | D |
| Byte arrays | `ByteArrayConverter.ReadJson`: requires `StartArray`, reads Integer tokens with `Convert.ToByte`, skips comments. So `data` is `[2,4,1,…]`, not base64 (the parser accepts both) | D+S |

## 2. Character JSON schema (`LE.Data.CharacterData`)

Names come from the `[JsonProperty]` attributes in `dump/cs/DiffableCs/LE/LE/Data/CharacterData.cs`. **D**

### 2.1 Fields the planner needs

| JSON key | Type | Meaning |
|---|---|---|
| `characterName` | string | |
| `characterClass` | int | 0 Primalist, 1 Mage, 2 Sentinel, 3 Acolyte, 4 Rogue (`CharacterClassList`, A) |
| `chosenMastery` | byte | 0 = no mastery (base class), 1..3 = masteries in class asset order (Primalist: Beastmaster, Shaman, Druid; Mage: Sorcerer, Spellblade, Runemaster; Sentinel: Void Knight, Forge Guard, Paladin; Acolyte: Necromancer, Lich, Warlock; Rogue: Bladedancer, Marksman, Falconer). `originalMastery` also exists |
| `level`, `currentExp` | int, long | |
| `savedCharacterTree` | `{treeID:string, version:ushort, nodeIDs:[byte], nodePoints:[byte], unspentPoints:int, nodesTaken:[{key,value}]?}` | Passive tree. `nodeIDs[i]` → `nodePoints[i]`. **Node IDs are bytes (0..255).** Class tree IDs (asset): `pr-1`, `mg-1`, `kn-1`, `ac-1`, `rg-1` (`treeID` was `""` in the sample). `nodesTaken` is legacy: nothing in the decompiled code reads it |
| `characterTreeNodeProgression` | [string] | Allocation order (used for respec) |
| `savedSkillTrees` | `[{treeID, slotNumber:int, xp:int, version:ushort, nodeIDs:[byte], nodePoints:[byte], unspentPoints, abilityXP:float, nodesTaken}]` | One per specialised skill. **`treeID` = playerAbilityID** (for example `ws54hm` = Wandering Spirits: `Global Tree Data.asset` and `WanderingSpirits.asset`). `slotNumber` = specialisation slot |
| `abilityBar` | [string] | Ability IDs on the bar (5 entries in the sample) |
| `werebearAbilityBar`, `sprigganFormAbilityBar`, `swarmbladeAbilityBar` | [int] | Transform bars |
| `savedWeaverTree` | `{version, nodeIDs:[byte], nodePoints:[byte]}` | Weaver tree |
| `savedItems` | [ItemLocationPair] | §2.2 |
| `savedQuests` | `[{questID, questStepID, state, questBranch, completeObjectives:[int], failedObjectives, nolongerRelevantObjectives, objectiveProgress, trackStatus}]` | `state`: QuestState NotStarted 0, Active 1, **Completed 2**, Failed 3, NoLongerRelevant 4 |
| `blessingsDiscovered` | [int] | Blessing subtypes discovered (not the equipped ones) |
| `openBlessings` | `[{subtypeId:ushort, implicitRollByte0..2}]` | The blessing **options currently offered** (`populateBlessingOptions` → `SaveUnlockedBlessings`), **not** the equipped blessings |
| `cycle` | byte | Cycle enum (Beta 0, Legacy 1, Release 2, Octo 3 … Tarpon 12) |
| `hardcore`, `soloChallenge`, `soloCharacterChallenge`, `masochist`, `died`, `deaths` | | Flags |
| `factions` | {int: FactionCharacterData} | Faction rank (CoF/MG, relevant for some items) |

Other keys (monolith, arena, dungeons, tutorials, tracking, `_ts`, `id`, `seqNo`, `_etag`, `partitionKey`,
`version`, …) do not affect the build. `CharacterDataVersioning.UpgradeVersion` throws NotImplemented, so there are
no JSON-level migrations. Only the items are versioned. **D**

### 2.2 `ItemLocationPair` (`savedItems[]`)

| JSON key | Type | Notes |
|---|---|---|
| `itemData` | string | Legacy string format (pair formatVersion 0). Converted by `LegacyItemStringConverter.fromStringToSerialisationVersion0` |
| `data` | byte[] | The item blob (§3) |
| `inventoryPosition` | `{x,y}` | Grid position (idols, bag, stash) |
| `quantity` | int | Items with quantity < 1 are rejected on load |
| `containerID` | ushort (omitted when 0) | §2.3 |
| `tabID` | int (omitted when 0) | Stash tab |
| `formatVersion` | byte | **Pair** format, always 2 now (`CURRENT_VERSION = 2`). 0 = legacy `itemData` string. 1 = the container was encoded in the position: (-1,-1) → 30 LEGACY_EQUIPMENT_REDIRECT, (-1,0) → 19 CURSOR, (-4,-4) → 31, (-5,-5) → crafting 23/24/25 by item type, other positions → 1 INVENTORY (`ItemLocationPairExtensions.CheckAndUpdateFormat` @0x181c4f3c0) **D** |

### 2.3 Container IDs (enum `ContainerID`) **D**

| ID | Container | Planner use |
|---|---|---|
| 1 | INVENTORY (bag) | optional |
| 2 helmet, 3 body, 4 weapon, 5 offhand, 6 gloves, 7 belt, 8 boots, 9 right ring, 10 left ring, 11 amulet, 12 relic | equipment | **yes** |
| 29 | IDOLS (idol grid, `inventoryPosition` = top-left cell) | **yes** |
| 123 | IDOLS_INVENTORY | no |
| 33–39, 43–45 | BLESSING_0…6, BLESSING_7…9 (one slot per timeline) | **yes** |
| 40–42, 46, 47, 87–90 | BLESSING_OPTION_n | no |
| 91–96 | WEAVER_TREE_ITEM_NODE_SMALL_1/2, LARGE_1…4 | **yes** (items socketed in the Weaver tree) |
| 21 stash, 32 shop buyback, 82–86 nemesis, 124–128 Rage of Morditas, … | | no |

Loader: `ItemContainersManager.LoadItemsToCharacterContainers` @0x1814000b0 builds an `ItemDataUnpacked(byte[])` for
each pair and drops item types marked obsolete (`ItemList.IsItemTypeObsolete`). **D**

## 3. Item blob layout (current = serialisation version 6)

Reader: `ItemData.setValuesFromSerialisation` @0x18120ff70. Writer: `ItemData.RebuildID` @0x181203610.
Helpers: `EpochExtensions.concatForUshort(a,b) = a<<8|b`, `splitToBytes(u16)` → `[hi][lo]`,
`concatFourBytesForUInt` big-endian. Multi-byte integers are **big-endian**, except gifting targets and the
resonance target, which are little-endian `BitConverter.ToInt64`. **D**

### 3.1 Common header (all item types)

| Byte | Content |
|---|---|
| 0 | serialisation version (6). Versions above 6 throw "Tried to load an item with serialisation version …" |
| 1 | bit7 = `duplicated`. bits0-6 = individualID bits 30..24 |
| 2..4 | individualID bits 23..0 (31-bit unique instance ID. 0 → the game rolls a random ID and rewrites the item) |
| 5 | `itemType` = base type ID (`MasterItemsList.baseTypeID`). **< 101 = equipment-like** (gear, idols 25–33, blessing 34, lenses 35–39, idol altar 41). ≥ 101 = non-equippable |

### 3.2 Equipment-like items (itemType < 101)

| Byte | Content |
|---|---|
| 6 | `subType` (one byte. For uniques the reader replaces it with `UniqueList.Entry.GetSubType(…)`) |
| 7 | bits0-5 = `rarity`. bits6-7 = number of gifting targets (0..3) |
| 8 | bits0-3 = faction rank requirement. bit4 = **corrupted** (also always true for itemType 41 Idol Altar). bit5 = ruined. bit6 = required faction (0 Circle of Fortune, 1 Merchant's Guild). bit7 = alwaysUntradeable |
| 9..11 | implicit rolls 0..2 (bytes 0..255) |

Rarity byte values: 0 normal, 1–2 magic, 3–6 rare (**exalted is not a rarity**: `isExaltedItem` checks for an
affix with tier ≥ 6, i.e. nibble ≥ 5), 7 unique, 8 set, 9 legendary. **D**

#### (a) rarity < 7: normal / magic / rare / exalted, idols, blessings, lenses

| Byte | Content |
|---|---|
| 12 | non-idol: bits0-5 = **forging potential** (stored clamped to 63), bits6-7 = forging potential type (0 default, 1 Blood, 2 Ice; 3 is read as default). Idol (types 25–33): **weaver's touch** (whole byte), forging potential = 0 |
| 13 | bits0-5 = affix count n. bit6 = has corruption-sealed affix. bit7 = has regular sealed affix |
| 14 + 3i | affix i (§3.4) |
| 14 + 3n … | gifting targets: 8 bytes each, little-endian int64 (account/character IDs; trade-related only) |

Sealed affixes are identified by **position**: if bit7 is set, affix 0 is the regular sealed affix. If bit6 is set,
the next affix (index 1 when bit7 is set, else 0) is the corruption-sealed affix. Any other affix with tier nibble 7
is **primordial** (sealed, T8). After loading, the reader **recomputes the rarity** as
`clamp(n − regularSealed − hasPrimordial − corruptionSealed, 0, 4)`. Only rarity < 5 loads affixes. **D**

The writer always writes this layout for rarity < 7. Blessings (type 34) normally have n = 0. A blessing's value
lives in its subType and its 3 implicit rolls (compare `BlessingData`). **D?** (no blessing in the local sample)

#### (b) rarity 7 unique / 8 set

| Byte | Content |
|---|---|
| 12..13 | `uniqueID` (big-endian ushort) → `UniqueList.uniqueID` |
| 14..21 | 8 unique rolls (`MaxUniqueRolls = 8`). Mod k uses `uniqueRolls[mod.rollID]` |
| 22 | non-idol: bits0-4 = **legendary potential OR weaver's will**. Which one depends on the unique entry's `legendaryType` (0 LegendaryPotential, 1 WeaversWill). bits5-7 = affix count n. Idol uniques: bits5-7 = n only |
| 23 + 3i | affix i (reforged set affixes, corruption affixes, etc.; the kind comes from the affix data) |
| 23 + 3n … | gifting targets |

The writer stores `weaversWill` if it is non-zero, else `legendaryPotential` (LP 0..4, WW 5..28). The real game
loads these affixes only when the unique ID exists in `UniqueList`. **D**

#### (c) rarity 9 legendary

| Byte | Content |
|---|---|
| 12..21 | uniqueID + 8 unique rolls (as in b) |
| 22 | not corrupted: bits0-2 = legendary affix count n, bits3-7 = **weaver's will**. Corrupted: bits0-2 = n, bit7 = the **last** affix is corruption-sealed |
| 23 + 3i | affix i (the affixes that were added to the unique) |
| 23 + 3n … | gifting targets |

Legendary potential is not stored on legendaries. Version-4 data fix: items saved in v4 with LP 4 or more than 3
legendary affixes are clamped for some uniques in the Trout cycle. Not relevant for current saves. **D**

### 3.3 Non-equippable items (itemType ≥ 101)

| itemType | Name (asset) | Layout after the header |
|---|---|---|
| 101 'e' | Affix Shard | [6..7] subType ushort (= affix ID) |
| 102 'f' | Crafting Modifier Item (runes, glyphs) | [6] subType (102/7 → 0) |
| 103 'g' | Crafting Support Item | [6] subType (103/4 → 0) |
| 104 'h' | Key Items | [6] subType |
| 105 'i' | Lost Memory | [6..7] subType, [8] memory affix 1 ID, [9] roll, [10] affix 2 ID, [11] roll, [12] bits6-7 gift count, gifting targets from 13 |
| 106 'j' | Resonance | [6] subType, [7..14] resonanceTarget (int64 LE). The writer allocates 100 bytes |
| 107 'k' | Woven Echo | [6..7] subType ushort |
| 108 'l' | Bags | [6] subType (100-byte allocation) |
| 109 'm' | Lens | [6] subType |

### 3.4 Affix triplet (`loadAffixFromSerialisation` @0x18120eb10) **D**

```
byte0 = tier<<4 | (affixId >> 8)     tier = 0-based nibble; display tier = tier+1 (ItemAffix.DisplayTier)
byte1 = affixId & 0xFF               affixId: 12 bits (0..4095). "2-byte IDs" = IDs ≥ 256
byte2 = roll                         0..255
```
`ItemAffix` constructor @0x181213660 adjusts the stored values:
1. An unknown affix ID becomes **affix 25**.
2. If `convertOnIncompatibleItemType` is set and the item type is not in `canRollOn`, the ID is replaced by
   `affixIDToConvertTo` (up to 100 hops). Class/base-specific affix variants work this way.
3. On **idols** (types 25–33) the tier is forced to 0 unless the affix is an IdolEnchantment
   (`specialAffixType 4`).
4. Experimental, personal, set, idol-enchantment, idol-weaver and corrupted affixes are **not flagged in the bytes**.
   They come from `AffixList.Affix.specialAffixType` (Standard 0, Experimental 1, Personal 2, Set 3,
   IdolEnchantment 4, IdolWeaver 5, Corrupted 6, FakeUniqueMod 7). Prefix/suffix comes from `type`
   (0 prefix, 1 suffix, 2 special).
5. `IsExalted` = display tier > 5. **Sealed types**: Regular 1 (header bit), Primordial 2 (nibble 7),
   FromCorruption 3 (header bit).

### 3.5 Version history (upgrade performed by the reader) **D**

| From | Change made by the reader on load |
|---|---|
| 0, 1 | If `data[1] < 101`: insert byte **0x80** at index 4 (this becomes the flag byte: alwaysUntradeable). Version → 2. v0 also: forging potential = `calculateForgingPotentialFromVersion0Serialisation(instability = byte10, rarity, type, subType)` = `((u%9)−4+base)·(60−instability)/60` clamped to 0..63, with u = 2·subType + type and base 22/12/10 for rare/normal/magic; 0 for idols or instability ≥ 60 |
| 2 | Insert a 2-byte random individualID (16..32767) after the version byte |
| 3, 4, 5 | Widen the 2-byte ID to 4 bytes (bit7 of byte 1 = duplicated is kept) |
| 1..3 | byte 12 = forging potential only (no type). From v4 on, bits 6-7 = type and idols store weaver's touch |
| < 6 or ID 0 | The item is re-serialised as v6 (`RebuildID`) |

Equivalent positions: v2 index k ≥ 1 → v6 index k + 4. The Feb-2024 beta sample is v2, so its bytes 1..9 are
type, subType, rarity, flags, implicits×3, FP, count. **S**

## 4. Worked examples

**v2 sample (gloves, S)**: `[2, 4,1,4,0, 61,20,192, 20, 4, 17,247,41, 16,8,181, 17,248,110, 0,13,151, 0]`
→ v6 `[6,0,0,0,0, 4,1,4,0, 61,20,192, 20, 4, …]`: Gloves (type 4) subType 1, rarity 4 (rare), FP 20, 4 affixes:
503 T2 roll 41, 8 T2 roll 181, 504 T2 roll 110, 13 T1 roll 151. Every v2 equipment blob in the sample has **one
trailing 0 byte** after the affixes. The reader ignores it, so it is probably a leftover field of the 2024 writer.

**v2 unique**: `[2, 22,2,7,0, 145,155,180, 0,68, 160,194,179,131,55,154,98,152, 0]` → Relic subType 2, unique 68
(Grimoire of Necrotic Elixirs), rolls [160,194,…], LP 0, 0 affixes.

**v6 synthetic** (from `encode_item`, the RebuildID port; round-trips with the decoder):
`[6, 7,91,205,21, 0,9,4,0, 10,200,255, 87, 133, 97,245,77, 64,13,3, 52,0,255, 16,2,0, 15,255,128]` =
helmet, individualID 123456789, rare, FP 23 Blood (`87 = 1<<6 | 23`), 5 affixes with header bit7 set:
affix 0 = 501 T7 roll 77 regular-sealed, then 13 T5, 1024 T4, 2 T2, 4095 T1.

## 5. Roll byte → value **D**

### 5.1 Rounding core
`EpochExtensions.GetValueAfterRounding(PropertyRounding added, PropertyRounding more, ModType, min, max, roll)`
@0x1810dfff0:

* `ModType` (BaseStats): ADDED 0 → property `roundingForAdded`. INCREASED 1 → **Hundredth**. MORE 2 / QUOTIENT 3 →
  property `roundingForMore` (virtual, may depend on specialTag). The SP overload @0x1810dff00 looks up
  `PropertyList.GetPropertyInfo(property, tags, specialTag)` first.
* `PropertyRounding`: Hundredth 0 (×100), Integer 1 (×1), Tenth 2 (×10), Thousandth 3 (×1000).
  `research/02_assets/property_ids_v1.5.0.txt` lists `rInt` (added) and `rMore` per property as these enum values.
* Ascending (min ≤ max), `AscendingValueAfterPropertyRounding` @0x1810dbce0:
  `a = RoundHalfEven(min·s); b = RoundHalfEven(max·s); v = min(floor((b−a+1)·roll/255 + a), b); value = v/s`
* Descending (min > max), @0x1810dc920 (checked in ISIL):
  `v = max(ceil((b−a−1)·roll/255 + a), b)`. Example [10→5]: roll 0 → 10, 128 → 7, 255 → 5.
* Arithmetic is float32 (`(float)roll/255f`). The parser emulates float32.

### 5.2 Affixes (`AffixList.GetSingleAffixValue` @0x18119c0d0, `GetMultiAffixPropertyValue` @0x18119b9a0)
```
m   = ItemList.getAffixEffectModifier(baseType, subType)
        = baseType.affixEffectModifier, or ItemList.omenIdolAffixEffectModifier if subItem.affixEffectiveness == 1
m'  = (m == affix.standardAffixEffectModifier) ? 0 : (1+m)/(1+standardAffixEffectModifier) − 1   // Affix.getModifier
tier = tiers[tierNibble] (out of range → tiers[0])
lo, hi = tier.minRoll·(1+m'), tier.maxRoll·(1+m')        // multi-affix property k>0: tier.extraRolls[k−1]
value  = GetValueAfterRounding(property, tags, specialTag, modifierType, lo, hi, roll [, setProperty, affixCountForSetProps])
```
All properties of a multi-affix use the **same roll byte**. Set properties (`setProperty`) also scale with the
number of equipped items that have the affix (`affixCountForSetProps`). The exact scaling is still to be checked
(see §8). **Correction to 06a §7.1**: 06a writes `tier·(1+affixEffectModifier)`. The real factor is
`(1+m)/(1+standardAffixEffectModifier)`.

### 5.3 Implicits
`ItemList.GetItemImplicits` @0x181223b80 → `EquipmentImplicit.GetValue(implicitRolls[i])` @0x181230ec0 = the same
`GetValueAfterRounding(property, tags, specialTag, type, implicitValue, implicitMaxValue, roll)`. The affix effect
modifier does not apply. Implicit i ↔ `subItems[sub].implicits[i]`.

### 5.4 Unique / set / legendary mods
`UniqueItemMod.getValue(roll)` @0x18126b510 with `roll = uniqueRolls[mod.rollID]` (`ItemData.getUniqueRoll`):
if `!canRoll || maxValue ≤ value || roll == 0`, the value is the **fixed** `GetFixedValueAfterRounding(value)`.
Otherwise it is `GetValueAfterRounding(value, maxValue, roll)`. **Descending unique ranges never roll.**

### 5.5 Test vectors (also in `--selftest`)
| rounding | range | roll | value |
|---|---|---|---|
| Integer | 5..10 | 0 / 128 / 255 | 5 / 8 / 10 |
| Hundredth | 0.10..0.20 | 200 | 0.18 |
| Hundredth | 0.15..0.30 | 255 | 0.30 |
| Integer | 10..5 (desc) | 0 / 128 / 255 | 10 / 7 / 5 |
| Unique 68 mod 0 (MORE, Thousandth) | −0.4..−0.3 | 160 | −0.337 |
| Unique 68 (ADDED, Integer) | 30..40 | 179 | 37 |

## 6. Points and slots that come from quests **D**

* Passive points earned = `level − 2 + min(15, Σ passivePointsReward of quests with state == Completed)`, clamped to
  0..255 (`LocalTreeData.calculatePassivePointsEarnt` @0x1816bd1b0; the level is `CharacterData.Level`;
  `StatefulQuestList.getPassivePointsFromQuestRewards` @0x1814cab40 caps at 15). At level 100 this gives 113.
* Idol slot unlocks: quests with `idolUnlockReward` (always 1 = one more grid block). Maximum 8 blocks
  (`IdolsContainerGridData.MaxIdolSlotUnlockRewards`). Which cells each block opens is in `IdolsContainerGridDataList`
  (`dump/assets/json`).
* All attributes: quest 169 "Knowledge of Orobyss" +2.
* Reward table (A, from the Quest assets `passivePointsReward / idolUnlockReward / allAttributesReward`). The asset
  sum is 31 passive points against the cap of 15, so some of these quests are probably obsolete. The cap makes this
  harmless.

| questID: (pp, idol, attr) |
|---|
| 1:(0,1,0) 3:(1,0,0) 9:(2,0,0) 11:(1,0,0) 12:(1,0,0) 20:(0,1,0) 24:(1,0,0) 30:(1,0,0) 32:(1,0,0) 33:(1,0,0) 35:(0,1,0) 36:(1,1,0) 37:(1,1,0) 39:(1,0,0) 45:(0,1,0) 46:(0,1,0) 47:(0,1,0) 49:(1,0,0) 57:(1,0,0) 58:(1,1,0) 93:(1,0,0) 94:(1,0,0) 97:(1,0,0) 117:(0,1,0) 119:(1,1,0) 120:(1,0,0) 121:(0,1,0) 122:(0,1,0) 124:(1,0,0) 128:(1,0,0) 129:(1,0,0) 131:(1,0,0) 151:(1,0,0) 158:(2,1,0) 159:(2,1,0) 160:(2,1,0) 169:(0,0,2) |

Skill points are not stored in the save. A skill's level follows from its `xp`. The planner can use the allocated
`nodePoints` directly.

## 7. Reference parser `tools/extract/save_parser.py`

```
python tools/extract/save_parser.py <save>                     # IDs only, stdlib
python tools/extract/save_parser.py <save> --gamedata          # + names, LP/WW split, redirects, values
python tools/extract/save_parser.py --item "2,4,1,4,0,..."     # decode one blob
python tools/extract/save_parser.py --selftest                 # encode/decode round trip + value vectors
```
Output (normalized): `class{id,name,passiveTreeId}`, `mastery{id,name}`, `level`, `passives{nodeId:points}`,
`passiveTree{version,unspentPoints,allocationOrder}`, `skills[{abilityKey,treeId,slot,xp,nodes}]`, `abilityBar`,
`weaverTree`, `questRewards{passivePoints,idolSlotUnlocks,allAttributes,totalPassivePoints}`,
`equipment[{slot,baseType,subType,rarity,implicitRolls,forgingPotential,forgingPotentialType,corrupted,
uniqueId,uniqueRolls,legendaryPotential|weaversWill,weaversTouch,affixes[{id,tier(1-based),tierRaw,roll,sealed,
(name,values)}],giftingTargets,trailingBytes}]`, `idols[...+position,gridSize]`, `blessings[...+blessingSlot]`,
`weaverTreeItems`, and `otherItems` with `--all-items`. `encode_item()` ports `RebuildID` (useful for writing
test vectors, or exporting from the planner later).

Validation done: both local saves (`1CHARACTERSLOT_BETA_0` and `.bak`, item v2, Feb 2024) parse with no
warnings: Acolyte level 12, 10 equipped items (9 rares/magics + unique relic 68), 2 skill trees. Names and values
resolve with `--gamedata`. The v6 layout is checked by a reader/writer round trip over 10 synthetic items (rare with
regular-sealed + 2-byte IDs, corrupted rare with corruption-sealed + primordial + 2 gifting targets, unique LP,
legendary WW, corrupted legendary, idol with weaver's touch, blessing, set, shard, rune). **No real v6 blob was
available.**

## 8. Open points / not established

1. **No current-format save on this machine.** The v6 layout comes from code only (reader and writer agree).
2. QuestState in the 2024 beta sample: all 9 quests had `state 0` on a level-12 character. Either the old enum
   ordering was different or completion is stored differently. Check against a fresh save.
3. The set-property scaling (`GetValueAfterRounding_2(…, setProperty, affixCountForSetProps)`) was not decompiled
   in detail.
4. `roundingForMore` may depend on specialTag, and `GetPropertyInfo(property, tags, specialTag)` may return
   overrides. The parser uses the per-property table only.
5. `GetFixedValueAfterRounding` is assumed to be `RoundHalfEven(value·s)/s` (not read line by line). **D?**
6. Blessing items: containers 33–45 per code. The 1.x global migration `MoveCharacterBlessingsToStash` moved some
   blessings to the stash. Verify that equipped blessings really appear in the character file.
7. The idol-altar (type 41) and lens (35–39) slot containers were not identified.
8. Meaning of the trailing 0 byte in v2 blobs: the current reader ignores it.

## 9. Test cases the user should provide (fresh 1.5.x offline saves, plus in-game screenshots with Alt tooltips)

1. **Basic**: a new character of each class at level 1, and one with a mastery chosen. Confirms the class/mastery
   IDs, an empty tree and `data[0] == 6`.
2. **Mid-campaign character** with passives and 3+ specialised skills, and a list of completed quests (or a
   screenshot of the passive point counter). Confirms node IDs, quest `state`, and the formula `level−2+quest pts`.
3. **Rare items**: one each with T1, T5 and T6/T7 (exalted) affixes. An affix with ID ≥ 256 (any attribute affix
   such as 501–504). Write down the tooltip ranges and values. Confirms the triplet and the roll→value maths
   including `affixEffectModifier`.
4. **Sealed affixes**: an item with a regular sealed affix (Glyph of Despair), a primordial (T8) affix, and a
   corrupted item with a corruption-sealed affix.
5. **Forging potential**: Blood and Ice forging potential items. A normal item with FP > 63, if possible.
6. **Uniques**: a unique with LP 1–4, a Weaver's Will unique (WW value visible), a set item, a reforged set item
   (has an affix).
7. **Legendaries**: one with 1–4 legendary affixes, one corrupted legendary, one Weaver's Will legendary.
8. **Corruption / faction**: a corrupted rare, an item with a Merchant's Guild or Circle of Fortune rank
   requirement, a gifted/traded item (gifting targets).
9. **Idols**: one of each shape (small, humble, stout, grand, large, ornate, huge, adorned), an enchanted idol,
   a weaver idol (weaver's touch), a corrupted idol, and the grid positions.
10. **Blessings**: blessings equipped in several timelines (expect containers 33–45). Note whether they show up in
    `savedItems` or only in the stash files.
11. **Weaver tree**: weaver tree points plus items socketed in weaver nodes (containers 91–96).
12. **Idol altar and lenses** equipped, to find their containers.
13. For each case: the save file plus Alt-tooltip screenshots, so the expected values are known.
