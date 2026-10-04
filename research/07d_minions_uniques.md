# 07d — Stat Transfer to Minions and Special Effects of Unique/Set Items (LE 1.5.0 Dump)

Labels: **D** — read from decompiled code; **D?** — read but interpretation is ambiguous.
Sources: `dump/decomp/LE.dll/*.c` (Ghidra), `dump/isil/IsilDump/LE/*.txt` (ISIL, where Ghidra failed), `dump/cs/DiffableCs/LE/*.cs` (offsets), assets `Resources/UniqueList.asset`, `SetBonusesList.asset`, `PlayerPropertyList.asset`, `AbilityPropertyList.asset`.

New files:
- `tools/extract/pp_switch.py` → `research/data/game/player_property_fields.json` (PlayerProperty → CharacterMutator field, by jump table in binary);
- `tools/extract/pp_usage.py` → supplements the same file with list of trigger methods;
- `tools/extract/extract_unique_effects.py` (+ `tools/extract/unique_component_mechanics.json`, manual extraction from component classes) → `research/data/game/unique_effects.json`.

---

## Part 1. Minions

### 1.1 Key Finding — Snapshot of Player Stats at Summon Time (**D**)

The general path for stat transfer, which 06e did not find, is located in the ability object component **`SummonEntityOnDeath`** (inheritor of `RequiresTaggedStats`), not in `Summoned`/`CharacterMutator`.

Chain (player casts summon):
1. `AbilityObjectConstructor.constructAbilityObject` @0x18241ce20:
   - pre-mutation temp stats (`CharacterMutator.ApplyPreMutationTemporaryStats`) and normal ability temp stats (virtual `applyTemporaryStats` @0x18241c320, vtable +0x2A8: `levelScaling × character level`, `attributeScaling × attribute`, item stats with `extraTag = ability ID`, mutator/tree stats) **are added to `Stats.stats` of the caster** (`AddRange`, lines ~3644/3724);
   - for each `RequiresTaggedStats` on the object, a `Stats` component is created/taken from the object, **entire** caster's stats list is copied into its list (`AddRange(caster.stats.stats)`, line ~4302), then `SetStats(thatStats)` is called;
   - temp stats are removed from caster (lines ~4370–4420).
2. `SummonEntityOnDeath.Summon` @0x181143130 (called on ability object "death" or on Start if `createOnStartInstead`) spawns `ActorData` and for **each** stat `s` from the obtained list performs (ISIL `SummonEntityOnDeath.txt` lines 2436–2600, pseudo-C lines ~2780–2915):

```
idx = AbilityIDIndex(creationReferences.GetPrimaryAbility())   // ID of summon ability
isTotem = ability.isTotem() || countsAsTotemEvenIfAbilityIsNotTotemAbility
if HandledBySummonerEvenIfMinionTaggedOrAbilitySpecific(s.property): skip      // SP 38,39,40,50,126,127
elif s.extraTag != 0 and s.extraTag != idx:
        minion.addStat(s)                       // unchanged (vtable-slot 0x24)            D?
elif (s.tags & Minion) or (isTotem and s.tags & Totem) or (s.extraTag == idx and idx != 0):
        if summonIsASummoner:                   // field +0x1B8 «For Minions That Summon»
            minion.AddStatModifier(s.property, s.added,   ADDED,     s.tags | Minion, s.specialTag, extraTag 0)
            minion.AddStatModifier(s.property, s.inc,     INCREASED, s.tags | Minion, ...)
            for m in s.moreValues: minion.AddStatModifier(s.property, m, MORE, s.tags | Minion, ...)
        minion.AddStatModifier(s.property, s.added, ADDED,     s.tags & ~(Minion|Totem), s.specialTag, extraTag 0)
        minion.AddStatModifier(s.property, s.inc,   INCREASED, s.tags & ~(Minion|Totem), ...)
        for m in s.moreValues: minion.AddStatModifier(s.property, m, MORE, s.tags & ~(Minion|Totem), ...)
else: skip                                      // normal stats without Minion tag are NOT transferred
```
(`minion` = `actor.stats` (+0x50) of spawned actor; `AddStatModifier` = interface call `FUN_180186360(0x1c, …)` with arguments `(SP, value, ModType, AT, specialTag, extraTag)`.)

`EpochExtensions.HandledBySummonerEvenIfMinionTaggedOrAbilitySpecific(SP)` @0x1810e0220 returns true for **SP 38 HealthGain, 39 WardGain, 40 ManaGain, 50 HasteOnHitChance, 126 ChanceToCastForAbility, 127 ChanceToCastForTags**. Such stats with Minion tag are handled by the summoner themselves (e.g., "health on minion hit").

After the loop:
- Stats of the **component itself** `SummonEntityOnDeath.statList` (+0x148) are added — **without changing tags** (`addStat`). Here the summon mutator (`XxxMutator.Mutate`) places stats from the skill tree: for example `SummonWolfMutator.Mutate` @0x18233a6b0 does `AddRange(mutator.statList +0x140)` and adds `AddedStat(CritChance(4), tags 0, v)`, `AddedStat(SP 56 StunImmunity, 1)` etc. Then `BaseStats.UpdateStats()`, health is set to maximum (or `maxHealth × healthPercent` of creator if `inheritHealthRatio`).
- Companions (`ability.companion` is the creator): PlayerProperty **132 «Increased Companion Size»** (`tags == 0x84`) is summed and together with `increasedMinionSize` (+0x150) via `Maths.combineModifiers` scales `localScale`. Purely visual.
- `Summoned.attributeScalingWhenSummoned` ← `CreationReferences.attributeScalingOnCast`. Used only in `Summoned.OnItemChange` (minions with items, 06e §4.3).

**Snapshot, not live link.** Minion's `Stats` has no reference to player's `Stats`. `AbilityObjectConstructor.initialise` @0x1824217D0 takes `Stats` of the actor itself. In `Summoned.OnUpdateTick`/`initialise` there is no recalculation from the player. Static list `Summoned.excludedPlayerPropertiesForSnapShotProtection` is created empty in `.cctor` @0x1812814D0 and is not used anywhere else. Minion receives actual player stats only on **resummon**:
- skill tree: `*Tree.resummonMinions/resummonCompanions`;
- scene change: `SummonPersistenceManager.OnPreSceneLoad` → `ResummonCertainMinions` @0x1812747B0 calls the same `resummon*` for Wolf/Bear/Raptor/Sabertooth/Scorpion/Spriggan/Primalist Elemental/Manifest Armor trees;
- new cast.

**D** for the rule. **D?** — only for the branch "foreign extraTag → addStat unchanged": arguments are visible in ISIL, but purpose is unclear; probably these are stats for minion's own abilities.

### 1.2 What Player Stats Reach the Minion (Consequences, **D**)

| Player Stat | What Minion Gets |
|---|---|
| `+X% damage` (tags 0), `+X% fire damage` (Fire) | **nothing** |
| `+X% minion damage` (Minion) | `Damage INCREASED X`, tags 0 |
| `+X minion melee physical damage` (Physical\|Melee\|Minion) | `Damage ADDED X`, tags Physical\|Melee → only to minion's melee-phys abilities |
| `+X% minion health / armour / resist` (Minion) | Health/Armour/Res without tag → go to minion's `ApplyExternalStats` (06a §4.1) |
| stats with `extraTag = ID of summon ability` (e.g. «+X% Summon Skeleton damage» from item) | transferred with `extraTag 0` and without Minion tag |
| `levelScaling`/`attributeScaling` of summon ability (asset `Ability`) | calculated **on player** (character level, player attributes) and transferred if stat has Minion tag (or extraTag of ability) |
| summon tree nodes | (a) mutator temp stats with Minion tag → by rule above; (b) `SummonEntityOnDeath.statList` → as is, usually without tags |
| totem stats (tag Totem) | only if ability is totem (`Ability.isTotem` or flag `countsAsTotem…`) |
| HealthGain/WardGain/ManaGain/Haste on hit/ChanceToCast with Minion tag | not transferred (handled by player) |
| hidden player base (`CharacterStats.SetInitialValues`, 06a §5.3): Movespeed MORE 0.10 Minion; DamageTaken MORE −0.6 Minion\|PetResisted; Damage MORE n·k Minion and DamageTaken MORE −n·k Minion from level | minion has: Movespeed MORE +10%; DamageTaken MORE −0.6 with **PetResisted** tag (tag not removed, mask removes only 0x6000); Damage MORE and DamageTaken MORE from level — without tag |

Why tag is removed: minion abilities in assets **have no** Minion tag (e.g. `Skeleton Rogue Melee`, `PrimalWolf 01 melee`: `tags 513` = Physical\|Melee; `Summon Skeleton Archer Bow Attack`: `2049` = Physical\|Bow). Minion tag is on player's summon ability (`SummonSKeletonWarrior.asset`: `tags 8192`). `DamageStats.buildDamageStats` @0x18108C090 requires Minion tag in stat only if it's in the damage itself (`required = damageTags & 0x2000`, via `Tags.Applicable(own, stat, required)` @0x1816A4EF0). For minion abilities required = 0, and removed tags match normal subset rule.

### 1.3 Minion Level and Base (**D**)
- `ActorData.spawn` @0x18277BD10 does not take level. Actor level is taken from `ActorData.level` in asset (for `BloodGolem` = 34), but for game minions **is not scaled**: `ActorScaler.scaleToLevel/scaleToZoneLevel` from `SummonEntityOnDeath` are not called.
- **`levelScaling` of minion's own abilities is not applied.** In `applyTemporaryStats` level is taken from `CharacterDataTracker` (+0xE0 → +0x20 → +0x88). If tracker doesn't exist on caster (and minions don't have it), block is skipped entirely. `attributeScaling` of minion abilities uses minion's own attributes (usually 0, except minions with items).
- Minion's base health/armour/resistances — from its prefab (`UnitHealth`, `ActorStats`/`ProtectionClass` in actor bundle), not from PermaLoad. Result: `maxHealth = RoundHalfEven((base + ΣA)·(1 + ΣI)·ΠM)` per 06a §4.1, where A/I/M already contain transferred stats.
- Base crit 5%/×2 (`Stats.baseCritChance/baseCritMulti`) — common for all `Stats`.

### 1.4 Companions (**D**)
- `CharacterStats.getMaximumCompanions` @0x181698270 = `Round(GetStatValue(SP61 MaximumCompanions, added = 2.0))`, i.e. base **2** + added, × (1+inc) × more. If flag +0xB5C in `CharacterMutator` (+0x130) is set, limit = **1**.
- `Stats.maxContributionToCompanionLimit` @0x1816A4CD0 = `maxCompanions × 60`. Companion's default contribution `Summoned.defaultContributionToCompanionLimit = 60`, mutators can change it (`SummonWolfMutator.getContributionModifier`, `setContributionToCompanionLimit`).
- Companions have no separate power multipliers. Differences: size (PP 132) and limit.

### 1.5 Test Vectors (Transfer)
Summon `idx = 50` (not totem), `summonIsASummoner = false`.
1. Player: `Damage INC 0.4 tags 0`, `Damage INC 0.5 Minion`, `Damage INC 0.3 Minion|Melee`, `Health ADD 20 Minion`.
   → Minion: `Damage INC 0.5 (0)`, `Damage INC 0.3 (Melee)`, `Health ADD 20 (0)`.
   Minion's melee attack (Physical\|Melee): ΣI = 0.8. Minion spell: ΣI = 0.5. Health `(base+20)·…`.
2. Player L100 (`first = 26`, `k = 0.008`): `Damage MORE 0.6 Minion`, `DamageTaken MORE −0.6 Minion`, `DamageTaken MORE −0.6 Minion|PetResisted`.
   → Minion: damage ×1.6; incoming damage ×0.4, damage with PetResisted tag ×0.4·0.4 = ×0.16.
3. `Damage INC 0.25 Totem`: for totem (isTotem) → `Damage INC 0.25 (0)`; for non-totem minion → nothing.
4. `Damage INC 0.2 extraTag=50 tags 0` → minion gets `Damage INC 0.2 (0)`. `extraTag = 77` (other ability) → minion gets as is, `extraTag 77` (**D?**).
5. `HealthGain ADD 5 Minion` (SP 38) → not transferred.
6. `summonIsASummoner = true`, stat `Damage INC 0.5 Minion` → minion gets two records: `INC 0.5 (Minion)` (for its summons) and `INC 0.5 (0)`.

### 1.6 Could Not Determine (Minions)
- Exact semantics of interface slots `0x1C` (AddStatModifier or ChangeStatModifier) and `0x24` (addStat) for minion's `Stats`: names recovered from arguments, not symbols.
- Minion base values (health, armour, resistances, base damage of their abilities) lie in actor prefabs in separate bundles. Need UnityPy extractor via `ActorData.ActorSoftRef`.
- Whether equipment change rebuilds snapshot for already-living minions. Found only resummon by skill tree, scene change and new cast. Constant `AbilityManager.falconAgeToSetAfterGearChange = 115` hints at separate falcon logic.
- Specific stats that each `*SkillTree.updateMutator` puts into `statList` of summon mutator. Task for ~25 summon trees, per pattern of `SummonWolfMutator.Mutate`.

---

## Part 2. Special Effects of Unique and Set Items

### 2.1 How «Special» Properties of Unique Items Are Implemented (**D**)

Unique item = list `UniqueItemMod` in `UniqueList.uniques[i].mods` + optional component class. «Special effects» (described as text in tooltip) are implemented four ways:

| Method | Mods (489 unique) | Logic Location |
|---|---|---|
| **PlayerProperty** (SP 98, `tags` = index in `PlayerPropertyList`; 371 different indices) | 399 | `CharacterMutator`: field filled in `applyModifiersBeforeExternalStatsCalculation` @0x182601FE0; event handlers read it |
| **AbilityProperty** (SP 58, `tags` = ability index in `AbilityManager.abilities`, `specialTag` = index (0-based) in `AbilityPropertyList[ability].properties`) | 385 | specific ability mutator (`Stats.GetAbilityStat(abilityID, idx)`) |
| Conditional/special SP: 117/131/132/133 GlobalConditional*, 115 DamagePerStackOfAilment, 100 AilmentConversion, 130 IdolAltarProperty | ~35 | general damage engine (06a §6.4) |
| **Component class** `UniqueItemComponent` (42 total; 14 are empty markers) and `SetItemComponent<T>` (6 set items, all without logic) | — | class's own code (§2.4) |

Remaining mods — normal stats (06a), with rolls.

**Mod value** (`ItemEquipManager.UpdateStats` @0x181436460 → `UniqueItemMod.getValue(byte roll)` @0x18126B510):
```
roll = item.getUniqueRoll(mod.rollID)                 // byte 0..255
if !canRoll || maxValue <= value || roll == 0:  v = GetFixedValueAfterRounding(prop, tags, special, type, value)
else:                                            v = GetValueAfterRounding(prop, tags, special, type, value, maxValue, roll)
v *= 1 + equipEffectModifier                         // UpdateStats parameter, default 0          (D?)
ModType: 0 ADDED, 1 INCREASED, 2 MORE (QUOTIENT = remove more)
```
- Quantization same as affixes (06a §7.1): `a = RHE(lo·s)`, `b = RHE(hi·s)`, `v = min(floor((b−a+1)·roll/255 + a), b)/s`. Step s — from `PropertyRounding` of property; for SP 98/58 — from PlayerPropertyList/AbilityPropertyList record.
- If `maxValue < value` (e.g. Snowblind `AilmentChance 0.4/0.2`), mod **does not roll** and always gives `value`. In JSON these are `rolls`/`rollMax` fields.
- Multiple mods can share one rollID: for Snowblind these are PP 454 and PP 455.

**Component binding:**
- `GetComponent(uniqueName.Replace(" ", "_"))` on template object → `AddComponent` of this type to player → `EquipUnique()` (vtable +0x268).
- When item is removed, `RemoveUnique()` (+0x278) is called.
- For legendaries and set items additionally `CharacterMutator.UniqueSetOrLegendaryEquipped` @0x18266D9A0 is called.
- **D**

### 2.2 PlayerProperty → CharacterMutator Field (**D**, Automatically)
In `applyModifiersBeforeExternalStatsCalculation` (Ghidra timed out, logic read from ISIL):
```
foreach s in stats.stats:
    if s.property == 98 and (uint)s.tags <= 999:  goto jumptable[s.tags]   // table @0x182616398, 1000 int32 RVA
```
`pp_switch.py` reads the table from GameAssembly.dll and recognizes each case body by bytes. Total 692 cases:

| op | Count | Meaning |
|---|---|---|
| `add` | 534 | `field += s.added` (all sources summed) |
| `flag=(added>eps)` / `flag\|=(added>eps)` | 45 / 33 | bool-field enabled if added > ε (immunities, «You have Haste» etc) |
| `more-combine` | 42 | `field = (1+field)·Π(1+mᵢ) − 1`, via `Stat.ApplyMoreModifier` @0x18169DB90 or inline `getMoreMultiplier`. These are all «X% less/more damage taken from …» |
| `assign` | 2 | `field = s.added` |
| `complex` / `unknown` / `local` | 32 / 3 / 1 | non-standard bodies. Field guessed from first `[rdi+disp]` (**D?**); in several cases field name doesn't explicitly match property name |

Then `pp_usage.py` finds methods accessing this field:
- where it searches: `CharacterMutator`, and for offsets ≥ 0x1000 other classes;
- what it searches in: pseudo-C, and if not found there — in ISIL.

Method name is the trigger. Examples:
- `ApplyConditionalDefenses` — incoming damage;
- `ApplyConditionalTemporaryStats` — cast stats;
- `OnHit`, `OnKill`, `HitDamageTaken`, `OnUpdateTick`, `onPotionUse`, `IsImmuneToAilment` etc.

Coverage for 399 PlayerProperty mods of unique items:
- trigger found for 356;
- for 43 field access not found textually;
- 8 properties outside this switch (126, 127, 190, 507, 528, 551, 630, 665 — potions and companions).

Example chain: Snowblind, PP 454 «Armor against Chilled Enemies», MORE 0.16–0.24, rollID 2.
- Switch: `moreArmourAgainstChilledAttackers = (1+f)(1+m) − 1`.
- Field read in `ApplyConditionalDefenses`.

Example read: PP 250 «Damage Taken from Chilled Enemies». In `ApplyConditionalDefenses` @0x18261D5C0 `mult *= (1 + moreDamageTakenFromChilledEnemies)`, if attacker has Chill (AilmentID 3). **D**

### 2.3 Set Bonuses (**D**, `ItemEquipManager.UpdateStats`, lines ~4190–4470)
```
count[setID] = number of DIFFERENT uniqueID items of this set in equipment (RecyclingListList.addUnique)
             + number of equipped uniqueID 423 «Legends Entwined» («Counts as a part of every equipped item set»)
for each set mod: if mod.setRequirement <= count → Stat(property, specialTag, tags, extraTag, value by type) into player's stats
```
- Accounts for «set-ified» unique items (`ItemData.grantsSetBonus` / `getSetItemUniqueId`).
- Set mod values are fixed, no rolls.
- `SetItemComponent<T>` only adds `IsadoraSetBuffs`/`ElementalistSetBuffs`; callbacks `OnSetItemEquipped/Unequipped` are empty. Logic of «N items» lives only in `SetBonusesList`.

Test: Isadora (setID 1) — `+100% Damned chance` (req 2), `+30% mana efficiency` (req 3), `+30% Damned effect` (req 3).
- 2 different items → 1 mod active.
- 2 items + Legends Entwined → count = 3 → all three active.
- Two identical items → count = 1.

### 2.4 Component Classes (Full Details and Addresses — in `unique_effects.json` → `effects[source = Component:*]`)
No component reads unique item rolls or PlayerProperty: all constants are hardcoded. Rolling tooltip strings — these are normal mods.

| Class | Trigger | Mechanics (Constants) |
|---|---|---|
| Calamity | kill with fire skill; tick 0.5 s | every 0.5 s fire damage to self `1.0 × (number of fire kills in last 2 s)` via ApplyDamage (≈4 per kill) |
| Frozen_Ire | level change; on hit | per character level +0.2 added Cold dmg (Cold tag only, not Spell), +0.02 FreezeRateMultiplier, +0.01 NecroticRes; Tundra Nova with 0.15 chance, against undead second roll 0.176471 → 0.30 |
| Mourningfrost | stat recalc | per unit Dex: +1 added Cold (Melee/Spell/Throwing/Bow), −1% Physical res etc |
| Hammer_Of_Lorent | level change | +1 added Physical\|Melee dmg and +0.01 increased Melee stun chance per level |
| Strong_Mind | stat recalc; Stunned.enter | StunAvoidance += 2 × maxMana; on stun cast Lightning Explosion (ID 67) |
| Urzils_Pride | stat recalc | ManaRegen INCREASED += 0.5 × min(uncapped LightningRes, 40). Cap 40 does not apply: resistance stored as fraction |
| Preparation | late tick | HP ≥ 65%: +30 added Cold\|Melee dmg; else +0.3 HealthLeech (Melee) |
| Undisputed | on hit | +0.08 inc Physical for 4 s; named stacks 0..50 → up to 51 stacks (4.08) |
| Taste_of_Blood | on hit | for all current Bleed on target speed = (speed+1)·2 − 1, no cap |
| Close_Call | block | unnamed buff +0.4 inc Dodge for 4 s; each block — separate stack, no cap |
| Ignivar_Head | tick (channelling); equip | Fire Aura (ID 162) once per 1 s during channelling; Disintegrate MORE dmg = spell crit chance (+0.05 base), no cap |
| IsadoraGravechill | kill | buff +1.0 Chill chance (Necrotic) for **4 s** (tooltip says 5), with refresh |
| Death_Rattle | minion death | +30 HP flat, healing effectiveness not accounted |
| Bleeding_Heart | spell cast | 1 stack of Bleed on self (D?) |
| Stormtide | state change (stop) | Shock on self, ICD 0.5 s (D?) |
| The_Scavenger | potion | Haste 3 s |
| Beast_King | minion kill / player kill | player DamageTaken MORE −0.08 for 4 s; minions −0.25 for 4 s (refreshes, not stacks) |
| Soulfire | kill; poll 0.5 s | +0.6 inc Fire for 4 s; on Ignite on self +1.0 inc Armour |
| Soul_Bastion | kill | charges per 10 s; at 5 charges cast Soul Eruption and reset |
| Culnivars_Claim | tick | at full mana: mana → 0, Ward += maxMana |
| Rahyehs_Light | tick | Flame Ward with remainder < 1 s at ward > 80: duration reset, −80 ward |
| Keepers_Gloves / Arboreal_Circuit | melee hit / when hit | chance 0.1 (summonChance field not used), ICD 8 s / 15 s |
| Volcanus / Bone_Harvester / Torch_Of_The_Pontifex | melee hit / kill / kill | cast ability with chance 0.3 / 0.2 / 1.0 |
| Plague_Bearer_Staff | when hit | Blind attacker with 0.2 chance |
| Artor_Legacy | unequip | unsummonExtraCompanions |
| markers without code | — | Chains_of_Uleros, Chimaeras_Essence, Cinder_Song, Eterras_Path, Eye_of_Reen, Hollow_Finger, Humming_Bee, Ring_of_the_Third_Eye, Riverbend_Grasp, The_Claw, The_Fang, The_Falcon, Valeroot, Ward_Trail, IsadoraRevenge, IsadoraTombbinding, Elementalist* — effect entirely in mods (PP/AbilityProperty) |

### 2.5 Schema of `research/data/game/unique_effects.json`
```
{gameVersion, source, schema, setCountRule,
 data: [ {uniqueName, displayName, uniqueID, isSetItem, setID, legendaryType, baseType, subTypes[], levelRequirement,
          class (UniqueItemComponent subclass | null), classKind ("code"|"marker"|null), tooltip[],
          mods: [{rollID, canRoll, rolls, value(min), maxValue, rollMax, property, propertyName, specialTag, tags, tagNames?,
                  extraTag, abilitySpecific?, ailment?, modType, hideInTooltip}],
          effects: [{source: "PlayerProperty"|"AbilityProperty"|"GlobalConditional*"|"DamagePerStackOfAilment"|
                             "AilmentConversion"|"IdolAltarProperty"|"Component:<class>",
                     trigger[], formula, constants{}?, rollIDs[], value{min,max}?, confidence,
                     // PlayerProperty: ppIndex, name, codeField, codeOp, methods[{method,address}]
                     // AbilityProperty: abilityIndex, ability, propertyIndex, name
                     // Component: condition, creates, playerProperties, notes}],
          componentMethods?: [{name,address}] } ],
 sets: [ {setID, setName, items[{uniqueName, uniqueID}], tooltip[{setRequirement, description}], mods[... + setRequirement], effects[]} ] }
```
Helper file `player_property_fields.json`: `[{index, propertyName, caseVA, op, fieldOffset, field, fieldType, usedIn[{method, address|null, fromIsil?, outsideCharacterMutator?}]}]`.

Restart after patch (switch table address is hardcoded and will change):
```
pp_switch.py → pp_usage.py → extract_unique_effects.py
```

**Verification with Maxroll** (`data.json`): for all 486 common unique items `mods` match completely (rollID, property, specialTag, tags, value, maxValue, type). We have 3 more hidden items: 46 Sharktooth Saw, 69 Heirloom of Light, 248 FleshofStone.

### 2.6 Test Vectors (Unique Items)
1. Calamity, rollID 1 (`Damage INC Fire 0.2–0.8`, step Hundredth): roll 0 → 0.20; roll 255 → 0.80; roll 128 → `floor(61·128/255 + 20)/100` = 0.50.
2. Calamity, 3 fire kills in 1 s: in next tick 3 fire damage before mitigation, then 1 per kill still in 2-second window.
3. Frozen Ire, L80: +16 added Cold, +1.6 FreezeRateMultiplier, +0.8 Necrotic res. Tundra Nova against undead: 0.15 + 0.85·0.176471 = 0.30.
4. Hammer of Lorent, L100: +100 added Physical\|Melee, +1.0 increased Melee stun chance.
5. Strong Mind, maxMana 600: StunAvoidance +1200.
6. Undisputed, 60 hits in 4 s: 51 stacks → +4.08 increased Physical.
7. Taste of Blood: Bleed stack with speed 0 after 3 melee hits has speed 7 (×8).
8. Snowblind, roll PP 454 = 0.2 MORE: `moreArmourAgainstChilledAttackers = 0.2` (same rollID 2 sets PP 455).

### 2.7 Could Not Determine (Unique Items)
- **Formulas inside handlers of most PlayerProperty.** Field, aggregation and trigger method are known, but not chance, ICD or proc damage. Manual analysis needed for ~350 fields.
  - Priority — fields that read `ApplyConditionalDefenses`/`ApplyConditionalTemporaryStats`: they affect DPS and EHP.
  - Where to look: `CharacterMutator.c` by `fieldOffset` (account for indexing like `param_1[off/8]`) and ISIL `CharacterMutator.txt`.
- **AbilityProperty (385 mods):** how ability mutators use property index was not traced. Only property name and ability known.
- **32 `complex` + 3 `unknown` cases** (D?): field guessed by heuristic. E.g. PP 494 «Haste gives block chance…» shows `maxTolmatMinions` — this is heuristic error.
- **`equipEffectModifier`** (UpdateStats parameter): source of non-zero value not found.
- **PlayerProperty outside switch:** 190, 507, 528, 551, 630, 665 (potions), 126, 127 (companions). Presumably `HealthPotion`/`Downed`, not analyzed.
- **Component `The_Falcon`:** no «The Falcon» name in UniqueList, binding unconfirmed.
