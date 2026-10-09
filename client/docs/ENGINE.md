# Calculation engine (GDScript) — specification

Contract for all files in `client/scripts/engine/` and the autoloads. Formulas come from
`research/06a`, `06b`, `06c`, `06d`, `07a`, `07b` (label D = read from the game's code).
Code: Godot 4.7, GDScript, tabs, static typing, every engine file has a `class_name`.
The engine does not touch the UI. All numbers are float; rounding only where stated.

## 1. Constants — `engine/le.gd` (`class_name LE`)

`AT` tags (bit mask):
```
PHYSICAL=1 LIGHTNING=2 COLD=4 FIRE=8 VOID=16 NECROTIC=32 POISON=64 ELEMENTAL=128
SPELL=256 MELEE=512 THROWING=1024 BOW=2048 DOT=4096 MINION=8192 TOTEM=16384
PET_RESISTED=32768 POTION=65536 BUFF=131072 CHANNELLING=262144 TRANSFORM=524288
LOW_LIFE=1048576 HIGH_LIFE=2097152 FULL_LIFE=4194304 HIT=8388608 CURSE=16777216 AILMENT=33554432
ELEMENTS = LIGHTNING|COLD|FIRE (14)
```
Tag names for string parsing: `"Physical","Lightning","Cold","Fire","Void","Necrotic","Poison","Elemental","Spell","Melee","Throwing","Bow","DoT","Minion","Totem","PetResisted","Potion","Buff","Channelling","Transform","LowLife","HighLife","FullLife","Hit","Curse","Ailment"`.

`SP` properties (id): DAMAGE 0, AILMENT_CHANCE 1, ATTACK_SPEED 2, CAST_SPEED 3, CRIT_CHANCE 4,
CRIT_MULTI 5, DAMAGE_TAKEN 6, HEALTH 7, MANA 8, MOVESPEED 9, ARMOUR 10, DODGE_RATING 11,
STUN_AVOIDANCE 12, FIRE_RES 13, COLD_RES 14, LIGHTNING_RES 15, WARD_RETENTION 16, HEALTH_REGEN 17,
MANA_REGEN 18, STRENGTH 19, VITALITY 20, INTELLIGENCE 21, DEXTERITY 22, ATTUNEMENT 23,
VOID_RES 26, NECROTIC_RES 27, POISON_RES 28, BLOCK_CHANCE 29, ALL_RES 30, ADAPTIVE_SPELL_DAMAGE 41,
ALL_ATTRIBUTES 46, ELEMENTAL_RES 52, BLOCK_EFFECTIVENESS 53, ABILITY_PROPERTY 58, PENETRATION 59,
GLANCING 62, PHYSICAL_RES 64, MANA_COST 66, MANA_EFFICIENCY 69, CDR 70, NEG_PHYSICAL_RES 72,
ENDURANCE 75, ENDURANCE_THRESHOLD 76, NEG_ARMOUR 77, NEG_FIRE_RES 78, NEG_COLD_RES 79,
NEG_LIGHTNING_RES 80, NEG_VOID_RES 81, NEG_NECROTIC_RES 82, NEG_POISON_RES 83, NEG_ELEMENTAL_RES 84,
LEVEL_OF_SKILLS 88, CRIT_AVOIDANCE 89, WARD_REGEN 92, MAX_HEALTH_AS_ET 96, PLAYER_PROPERTY 98,
PHYS_VOID_RES 106, NECRO_POISON_RES 107, DAMAGE_TAKEN_BUFF 108, CHANCE_TO_BE_CRIT 112,
REDUCED_CRIT_BONUS_TAKEN 114, DAMAGE_PER_AILMENT_STACK 115, CONDITIONAL_DAMAGE 117, PARRY 121,
CONDITIONAL_PEN 131, CONDITIONAL_CRIT_CHANCE 132, CONDITIONAL_CRIT_MULTI 133.

Damage types — index 0..6 in the order **Physical, Fire, Cold, Lightning, Necrotic, Void, Poison**:
```
DT_TAG     = [1, 8, 4, 2, 32, 16, 64]
DT_NAME = ["Physical","Fire","Cold","Lightning","Necrotic","Void","Poison"]   # display names (the identifier keeps its old name)
RES_SP     = [64, 13, 14, 15, 27, 26, 28]
NEG_RES_SP = [72, 78, 79, 80, 82, 81, 83]
RES_GROUP  = [2, 1, 1, 1, 4, 2, 4]   # 1 elements, 2 Phys/Void, 4 Necrotic/Poison
```
Functions:
- `static func tag_mask(s: String) -> int` — `"Fire|Spell"`, `"Fire | Spell"`, `"None"`, `""` → mask.
- `static func tags_match(mod_tags: int, check: int) -> bool` (06a §3):
  `(mod & check) == mod` OR (`mod & ELEMENTAL` and `check & ELEMENTS` and `((check | ELEMENTAL) & mod) == mod`).
- `static func round_half_even(x: float) -> int` — banker's rounding.
- `static func fmt_pct(x: float) -> String` → `"12.5%"` (x=0.125), `static func fmt_num(x: float) -> String` → up to 2 decimals without trailing zeros.

## 2. Mod and store

### `engine/stat_mod.gd` (`class_name StatMod extends RefCounted`)
Fields: `property: int`, `special: int = 0`, `tags: int = 0`, `extra: int = 0`, `added: float`,
`increased: float`, `more: Array[float]`, `source: String` (display text for the breakdown:
`Passive "Arcanist" ×3`, `Helmet: Added Health T5`).
- `static func make(property, kind: String, value: float, tags := 0, source := "", special := 0, extra := 0) -> StatMod`
  `kind`: `"added" | "increased" | "more" | "quotient"`; quotient → more `1/(1+x) − 1`.
- `func scaled(n: float) -> StatMod` — a copy where added, increased **and every more** are multiplied by n (linearly, 06a §6.6).
- `func describe() -> String` — `"+12 (source)"`, `"+30% inc (source)"`, `"×1.15 more (source)"`.

### `engine/stat_query.gd` (`class_name StatQuery extends RefCounted`)
Query result: `added: float`, `increased: float`, `more: float = 1.0` (product),
`mods: Array[StatMod]` (the matching ones). `func value() -> float` = `added·(1+increased)·more`.
`func breakdown() -> String` — multi-line text: the formula line
`"(Σ added) × (1 + Σ inc) × Π more = A × B × C = V"`, then one line per mod (`describe()`).

### `engine/stat_store.gd` (`class_name StatStore extends RefCounted`)
- `var mods: Array[StatMod]`, `var parent: StatStore = null`.
- `add(mod)`, `add_all(arr)`, `all_mods() -> Array[StatMod]` (own + the parent chain).
- `query(property, check_tags := 0, special := 0, extra := 0, extra_zero_matches := true) -> StatQuery`.
  A mod matches if: `property` is equal; `mod.special == 0 or mod.special == special`;
  `mod.extra == extra or (extra_zero_matches and mod.extra == 0)`; `LE.tags_match(mod.tags, check_tags)`.
  added are summed, increased are summed, each more → `more *= (1+m)`.
- `query_untagged(property) -> StatQuery` — only mods with `tags == 0 and extra == 0 and special == 0`
  (this is how the game collects health, armor and other defenses, 06a §4.1).
- `sum_added_untagged(properties: Array) -> float` and `untagged_mods(properties: Array) -> Array[StatMod]`.

## 3. Build state — autoload `Build`

Already present: `class_id, mastery, level, passives`, the `changed` signal, the passive point rules.
To add (every setter emits `changed`):
```
skills: Array[Dictionary]  # 5 slots: {ability: String (playerAbilityID) or "", level: int = 20, tree: {node_id:int -> points:int}}
selected_skill: int = 0
items: Dictionary          # slot:String -> {base: int, sub: int, implicit_rolls: Array[int], affixes: Array[{id:int, tier:int, roll:int}]}
enemy: Dictionary          # see §6.1
player_state: Dictionary   # {health: "full"|"high"|"normal"|"low"}
defense: Dictionary        # the Defense tab settings, see §10
```
Item slots and the allowed base `typeName` values:
`helmet:HELMET, body:BODY_ARMOR, belt:BELT, boots:BOOTS, gloves:GLOVES, amulet:AMULET, ring1:RING, ring2:RING, relic:RELIC,
weapon: all isWeapon (1H and 2H), offhand: SHIELD|QUIVER|CATALYST and 1H weapons`.
Point limits (D, research/07e §6 and 06e §6):
- passives: `Build.passive_point_cap() = clamp(level − 2 + min(15, quest_passive_points), 0, 255)` (113 at level 100; `quest_passive_points`
  defaults to 15 — the maximum of quest points, there is no editor for it in the UI); `add_point` refuses when `spent_points() ≥ cap`;
  `Build.passive_cap_override ≥ 0` (tests only) replaces the calculation;
- skill tree: `Build.skill_point_cap(slot) = skills[slot].level + skill_level_bonus(slot)`; the bonus is the sum of `added` of the
  `LEVEL_OF_SKILLS` (88) mods from `BuildMods.global_store` for which `LE.tags_match(mod.tags, ability.tags)` and `extra ∈ {0, abilityIDEnum.value}`,
  rounded (`roundi`, the game's rounding method — D?); cached until the next `changed`. Class-wide "+N to all skills of the class"
  (`specialTag`) are not distinguished yet.
Methods: `set_skill(slot, ability_id)` (resets tree, level=20), `set_skill_level(slot, lvl)`,
`add_skill_point(slot, node_id) -> bool`, `remove_skill_point(slot, node_id) -> bool` (the rules are the same as for passives:
`requirements` is **"OR"** (a node is open if at least one neighbor from the list has points ≥ requirement; an empty list means open;
D, `LocalTreeData.ArePassiveNodeRequirementsMet`), `maxPoints`, the sum of points ≤ level; removing a point is forbidden if some
node would stop being connected to the root (`Build.all_connected`); the `masteryRequirement` threshold is not used for skill nodes),
`skill_points_spent(slot)`, `set_item(slot, dict)`, `clear_item(slot)`, `set_enemy(key, value)`,
`set_enemy_ailment(ailment_id, stacks)`, `set_player_state(key, value)`, `set_defense(key, value)`.

## 4. Data — autoload `GameData` (to add)

Files in `research/data/game/`: `abilities.json`, `affixes.json` (`data`), `items.json` (`data`),
`ailments.json` (`data`), `attributes.json` (`data`), `passive_node_effects.json`,
`skill_node_effects.json`; from `research/data/`: `sp_enum.json`, `monster_level_damage_reduction.json` (`values`).
The top-level key `hiddenBaseMods` of `classes.json` is stored in `hidden_base_mods`.
Methods:
- `get_ability(pid: String) -> Dictionary` — the `abilities.json` entry with this `playerAbilityID`, `category == "player"` has priority.
- `class_skills(class_id, mastery) -> Array[String]` — playerAbilityIDs from `masteries[0].abilities`,
  `masteries[mastery].abilities` and the `masteryAbility` of the selected mastery, `knownAbilities`, `unlockableAbilities`;
  without `na28` and empty ones, without duplicates.
- `get_skill_tree(tree_id) -> Dictionary` — `trees.json`, `kind == "skill"`, `treeID == tree_id`.
- `passive_effects(tree_id) -> Dictionary` (node_id → node from `passive_node_effects`),
  `skill_effects(tree_id) -> Dictionary` (the same from `skill_node_effects`).
- `mastery_bonus(tree_id, mastery) -> Dictionary` — the base bonus of a mastery (`mastery_bonuses` of `passive_node_effects`,
  research/07f §2) as a node-like `{displayName, effects[]}`: stats become `{target, op: "add_stat", stat}`, mutator fields
  `{target, value: {flat}}`; `{}` for no mastery.
- `affix(id) -> Dictionary`, `item_base(base_type_id) -> Dictionary`, `item_sub(base, sub) -> Dictionary`,
  `affixes_for_type(type_id: int) -> Array` — `rollsOn == "Equipment"`, `specialAffixType == "Standard"`, `type_id in canRollOn`.
- `ailment(id) -> Dictionary`, `enemy_ailments() -> Array` — `inList`, `positive == 0`, and (`buffs` is not empty or `dealsDamage`), sorted by name.
- `attributes: Array`, `sp_name(id) -> String`, `sp_id(name) -> int` (−1 if none), `damage_reduction(level) -> float` (0 for level > 100).
- `affixes_for_type(type_id, class_filter := "")` for idols (types 25–33) takes `rollsOn == "Idols"` and filters by
  `classSpecificity` (empty, `NonSpecific` or the class name); `is_idol_type(type_id)`; `idol_grid()` — `idols.json`
  `containerGrids.defaultData` (5×5, 99 is a closed cell); `conversion_rule("Mutator.field")` — a rule from `skill_conversions.json`.
- `enum_value(enum_name: String, name: String) -> int` from `research/data/stat_tag_enums.json`
  (`{enum_name: {values: [{id, name}]}}`), −1 if none. Used for `AilmentID` and `ConditionalDamageProperty`.

## 5. Mod sources — `engine/build_mods.gd` (`class_name BuildMods`)

`static func global_store(build) -> Dictionary` → `{store: StatStore, notes: Array[String]}`.
`notes` — human-readable "not counted" lines (shown honestly in the UI).

### 5.1 Class base
- `classes.json data[class].levelMods`: value `base + L·perLevel`, type `modType`, tags `tags`. Source "Class base".
- `hidden_base_mods`: `value`, `modType`, `tags`. Source "Hidden base".

### 5.2 Passives (`passive_effects(treeID)`)
For a node with `p > 0` points, for every `effect` with `op == "add_stat"`:
- `target == "CharacterMutator.stats"` and `stat.kind` ∈ `added|increased|more` → `StatMod`:
  property = id by the name `stat.property` (via `sp_enum`), tags = `LE.tag_mask(stat.tags)`,
  value = `v(stat.added | stat.increased | stat.more | stat.value)`.
- `specialTag` of `added|increased|more`: a number (or numeric text) is the special id as is (AilmentChance "3" = Chill), a name is
  its AilmentID; an unknown name drops the mod (it must not become special 0 = every ailment; the same for the `ailment` of a model).
- `kind == "ailment_chance"` → property 1, special = AilmentID by the name `stat.ailment` (`stat_tag_enums.json` → `AilmentID`), added.
- `kind == "ailment_duration"` → 42, `ailment_effect` → 43 (special = AilmentID, added).
- `kind == "conditional_more_damage"` → property 117, special = the index of ConditionalDamageProperty by the name `stat.condition`, more.
- Everything else (other targets, `player_property`, `ability_property`, `stat` without kind…) → `notes`: `Node "displayName": <target or kind> — not counted`.
- A field model of scope `skill` on the mutator of another skill (not `CharacterMutator.*`) never reaches the character: with its
  skill on the bar it is applied in `skill_store` (§9.7), without it the effect is a "not counted" note.
- `automatic_node_stat.extraTag` (an ability name such as "entanglingRoots", "none" = 0) limits the stat to that ability
  (`mod.extra` = its abilityIDEnum value, `BuildMods.ability_index_of`); an unknown name drops the mod.
An expression that does not parse or run (game code the client does not have) counts as 0 and logs a warning once per text.
Value `v(x)`: `x.per_point·p + x.flat`; if `x.expr` is present, evaluate an `Expression` with the variable `p`.
The base bonus of the chosen mastery (`GameData.mastery_bonus`, e.g. Falconer +12 Dexterity, Forge Guard +35% Fire and
Physical Resistance) is applied as one more node with `p = 1`, source "<Mastery> mastery bonus" (**D**, 07f §2).

### 5.3 Attributes (after all other sources)
`N = round_half_even(Σadded SP_attr + Σadded SP 46)` over **all** mods (tags are not checked, 06a §5.1): `BuildMods.attribute_value`,
also used by the `attr:` / `total_attr` sources of the effect models (§9.2).
Attributes given after this step (models of the "post" phase, Haste / Frenzy, the buffs of the equipped skills) are converted by
their delta: `_add_attributes(..., done)` adds the per-point stats × (N now − N converted before), as the game does on every
change of the value (nothing if the attribute was converted or un-converted meanwhile).
Haste / Frenzy of the Conditions tab count once: the flag is skipped while the same ailment has "Buffs on me" stacks.
For every `attributes[i].perPoint` add the mod × N (`scaled(N)`), source `Strength ×N`.
Corrupted attributes (07a §2.2): when the store holds SP 98 with the tags of `corruptedFlag` (650–654, e.g. the corrupted
amulet affix "Vitality converted to Rampancy"), the attribute gives `corruptedPerPoint` instead of `perPoint`, the source and
the Stats row are named after the new attribute (`BuildMods.converted_attribute`: "Rampancy ×N"). Its PlayerProperty
entries go through `player[ppIndex]` of `unique_effect_models.json` (§5.4.3) with `pp = per point × N` (Rampancy: PP 638,
more damage taken without Frenzy); entries without a model and the AbilityProperty ones go to `notes`.

### 5.4 Items — `engine/item_mods.gd` (`class_name ItemMods`)
`static func item_mods(slot: String, item: Dictionary) -> Array[StatMod]`.
- Implicits `item_sub(base, sub).implicits[j]`: value `AffixMath.roll_value(value, maxValue, rounding, modType, implicit_rolls[j], 0.0)`.
- Affixes: `a = affix(id)`, `tier = a.tiers[t-1]`, for every `properties[j]` + `tier.rolls[j] = [min,max]`:
  `m = AffixMath.effect_modifier(base.affixEffectModifier, a.standardAffixEffectModifier)` (for a subtype with
  `affixEffectiveness == "OmenIdol"` the base's value is replaced by `items.json globals.omenIdolAffixEffectModifier` = 0,
  `ItemMods.OMEN_IDOL_AEM`, 07a §6),
  value `AffixMath.roll_value(min, max, rounding, modType, roll, m)`.
- Mod: `property, special = specialTag, tags, extra = extraTag`, kind by `modType` (ADDED/INCREASED/MORE/QUOTIENT).
- Source: `"<Slot>: <affix name> T<t>"`.

`engine/affix_math.gd` (`class_name AffixMath`), 07a §6:
```
scale(rounding) = {"Hundredth":100, "Integer":1, "Tenth":10, "Thousandth":1000}; INCREASED is always Hundredth
effect_modifier(item_aem, std) = 0 if is_equal_approx(item_aem, std) else (1+item_aem)/(1+std) − 1
roll_value(lo, hi, rounding, mod_type, roll, m):
   lo2 = lo·(1+m); hi2 = hi·(1+m); s = scale
   a = round_half_even(lo2·s); b = round_half_even(hi2·s)    // in float32 like the game (AffixMath.f32): lo·(1+m)·s
   if a > b: swap them
   v = min(floor((b − a + 1)·roll/255.0 + a), b) / s
```
Test vectors: Integer [5,10] roll 0→5, 128→8, 255→10; Hundredth [0.10,0.20] roll 200→0.18;
[0.10,0.20] m=0.5 roll 255→0.30; [61,90] m=0.5 roll 0→92, 255→135.

### 5.4.1 Idols — `engine/idol_grid.gd` (`class_name IdolGrid`)
An idol is stored in `Build.items` under the key `idol_<row>_<col>` (the top-left cell) with the same structure as an item
(`affixes` — 1 prefix and 1 suffix). The base's `gridSize` is `[width, height]`. An idol fits if all its cells are open
(`!= 99`) and not occupied by other idols. Idol mods are collected like item mods (`ItemMods`), with the base's effect modifier
(Small −0.83, Grand −0.33, etc.). Rewards for opening slots are considered received.
Altar (`Build.items["altar"]`, base 41, `engine/altar_mods.gd` `AltarMods.apply`): the grid `idols.json data[sub]`, cells
`+100` are refracted; properties SP 130 (`tags` = IdolAltarPropertyID): 1–4 — the effect of idol affixes/enchantments in
refracted cells ×(1 + x) (`ItemMods.item_mods(..., effect_scale)`; prefixes/suffixes scale standard and Weaver affixes,
enchantments scale IdolEnchantment ones, other special types — corrupted etc. — are not scaled: `ItemEquipManager.UpdateStats`,
`EpochExtensions.IsAffectedByAffectOfStandardPrefixesOrSuffixes`), 9–19 and 22–30 — stats × the number of suitable idols
(corrupted ones — the `corrupted` flag, heretical/omen/weaver ones — by the subtype name), 20 — SP 117 against bosses per
unique/legendary idol, 21 — CDR under the size-order condition, limits — notes. Weaver idols (subtypes "… Weaver Idol" of
bases 25–28; the only ones IdolWeaver affixes roll on, the second affix may be a standard one): property 5 caps their number
(`AltarMods.weaver_limit`, `IdolsItemContainer.CanPlaceNewWeaverIdol`; no cap when the rounded value is below 1, i.e. without
the property); above the cap the calculation keeps them and adds a note, the Idols tab shows a warning.

### 5.4.2 Unique items and sets (07d §2.1–2.3)
An item with `unique: uniqueID` and `unique_rolls[rollID]` (roll byte, 255 by default): the base's implicits + the unique's mods.
The mod value is `AffixMath.unique_value`: it is rolled only if `canRoll`, `maxValue > value` and the roll ≠ 0, otherwise
a fixed value on the rounding grid. Mods SP 98 (PlayerProperty) and SP 58 (AbilityProperty) and components are
special effects (§5.4.3). SP 88 (+skill level) — a note. SP 100 (ailment conversion: specialTag = from, tags = to) — §8.6,
SP 115 (more per ailment stack on the target, no limit) — together with SP 117 in `_condition_factor`.
Sets: `count` = the number of **different** set uniqueIDs in the equipment + the number of Legends Entwined (423); the `sets.json` bonuses with
`setRequirement ≤ count` are added with fixed values, source `Set "…" (N items)`.
`BuildMods.set_counts(build)` and `complete_sets(build)` (a set is complete if count ≥ the number of the set's items).

### 5.4.3 Special effects of uniques — `engine/unique_effects.gd` (`class_name UniqueEffects`)
The models are a handwritten table `client/data/unique_effect_models.json` (not a game export; the schema is in the file itself), built from the
formulas of `unique_effects.json` (07i). `player[ppIndex]` for PlayerProperty, `ability["abilityIndex:propertyIndex"]` for
AbilityProperty. The value `pp` is the roll of the carrier mod: SP 98 with `tags = ppIndex` or SP 58 with `tags = AbilityID`,
`specialTag = index` (`AffixMath.unique_value`).
- Model → StatMod: `x = pp · (source − offset) · factor` (without `per`: `pp · factor`), then `min`/`max`; `stat` is the SP name,
  `mod`, `tags`, `ailment` → specialTag. Sources: attributes, the sum of attributes, added/value/increased SP, uncapped
  resistances, max health/mana, endurance threshold, ailment stacks on the enemy, player numbers (`Build.player_state`), complete sets,
  `converted_attr:<str|vit|int|dex|att>` — the hidden attribute of a corrupted attribute (Brutality, Rampancy, Madness, Guile,
  Apathy; Exulis "per 10 Rampancy"): the attribute value while it is converted (§5.3), otherwise 0.
- Conditions (`when`, `at_least`, `below`): enemy ailments and flags, enemy type, player flags, two weapons / a two-handed melee
  weapon (by the bases in the slots), item slot. An unmet condition → the note "counted when: …".
- Order in `global_store`: sets → `apply_global("pre")` (sources that do not read the store) → the "transformed" copies
  (player flag `transformed`: every mod with the Transform tag is added once more without that tag, research/06a §6.2;
  the Conditions checkbox is shown when a bar skill has `isTransform` or a mod carries the tag) → attributes → the player's Haste/Frenzy
  (`ailments.json` buffs × (1 + increased SP 120)) → `apply_global("post")` → `add_notes`.
- `apply_skill` in `skill_store`: AbilityProperty only for the skill with `abilityIDEnum.value = abilityIndex`, models with
  `skill_any` — for skills with one of the tags; `kind: mana_added` → `mana_added` and `mana_sources`.
- Special: `overcap_taken` (Null Portent: per damage type, more damage taken `max(−cap, (res−0.75)/0.02·pp)`).
- No model → a note with the reason: "does not affect damage or defenses" (flag/util), "trigger or a separate mechanic" (proc,
  components), "not modeled" (with the formula from the code); idol altars are not supported.

**Item triggers.** "Chance to cast X" affixes of items and idols (`_affix_triggers`) join `entries` with trigger models
only: SP 98 (`player[ppIndex]` of `unique_effect_models.json`), SP 58 (`ability["AbilityID:index"]`) and SP 127
ChanceToCastForTags (specialTag 1 = hit, 2 = crit; `tags` = the skill tags it needs → model `skill_mask`; `extraTag` =
AbilityID of the cast skill, `GameData.ability_by_index`). A trigger becomes a damage component (§9.3) of every bar skill
that matches (`skill_any` / `skill_mask`), so its DPS is part of that skill's "DPS vs enemy" and of the total on the stats
panel. Triggers on character events (`second`, `hit_taken`, `block`, `dodge`, `potion`) are attached to the first filled
slot only, so the total does not count them once per skill.

### 5.5 Skill tree — `BuildMods.skill_store(build, slot, global) -> Dictionary`
→ `{store: StatStore (parent = global), notes, use_speed_inc: float, use_speed_more: float, mana_inc: float, mana_added: float}`.
For a node with `p > 0` from `skill_effects(treeID)`:
- `op == "add_stat"` and the target contains `.unconditionalTempStats` (exactly this field) → a mod into the local store (`extra = 0`).
- `op == "add_stat"` and the target is `CharacterMutator.stats` → a mod into the local store (it is a global stat, but for the skill calculation it is the same thing).
- `op == "automatic_node_stat"` → a mod into the local store.
- A mutator field (there is a `target` of the form `XMutator.field`, no `op`):
  `increasedCastSpeed`, `increasedAttackSpeed` → `use_speed_inc += v`; `moreCastSpeed`, `moreAttackSpeed` → `use_speed_more *= (1+v)`;
  `increasedManaCost` → `mana_inc += v`; `addedManaCost` → `mana_added += v`.
- A field that has a rule in `skill_conversions.json` (`kind` ≠ none) → `conversions.append({rule, value, node})`.
- Everything else → `notes`: `Node "name": field <field> — a skill mechanic, not calculated`.

**Conversion rules** (`research/data/game/skill_conversions.json`, collected from the descriptions in the mutator code, level D?):
`{key "Mutator.field", kind conversion|tags|ailment_conversion, convert[{from, to, fraction: "value"|number}], tags_add[],
tags_remove[], tags_when active|full_conversion, ailment_convert[{from,to}], note}`. `fraction: "value"` — the value of the field
set by the node (clamped to 0..1). If the tags are not given in the markup, the source type is replaced by the target type
(`tags_derived`), and for a partial conversion — only at 100%.
Plus skill mods: `attributeScaling[]` — each Stat × the attribute value (int), `levelScaling` × character level.

## 6. Enemy — `engine/enemy.gd` (`class_name Enemy`)

### 6.1 Config `Build.enemy`
```
{level: 100, kind: "dummy",           # default; "dummy" | "normal" | "magic" | "rare" | "miniboss" | "boss"
 res: [0,0,0,0,0,0,0],                # percents by damage type (order §1)
 armour: 0,
 ailments: {ailment_id: stacks},      # shreds, shock, chill, curses, ignite, etc.
 flags: {moving: false, stunned: false, low_health: false, full_health: true}}
```
### 6.2 Functions
- `static func store(enemy: Dictionary) -> StatStore` — base mods: `res[i]/100` added into `RES_SP[i]`,
  `armour` added into SP 10; then for every ailment with n > 0 stacks:
  `n_eff = min(n, maxInstances)` if `maxInstances > 0`; for `buffScalingType == 2` also `min(n_eff, maxStacksThatApplyBuffs)`;
  `penalty = moreBuffEffectAgainstBosses` if the enemy is boss/miniboss, otherwise 0;
  every `buffs[k]` → `StatMod` (added/increased/more as in the data) `.scaled(n_eff·(1+penalty))`, source `"<name> ×n"`.
- `static func resistance(store, i: int) -> StatQuery` — only **added**:
  `RES_SP[i] + ALL_RES(30) + (ELEMENTAL_RES 52 if group 1) + (106 if group 2) + (107 if group 4)
   − (NEG_RES_SP[i] + NEG_ELEMENTAL_RES 84 if group 1)`; increased/more are ignored.
- `static func armour(store) -> float` = `query_untagged(10).value() − sum_added_untagged([77])`.
- `static func armour_mitigation(x: float, area_level: int, non_phys: bool) -> float` (06c §2.2):
  `L = area_level + 5`; `x<0 → −f(−x)`; `f = 0.55·0.0015x²/(0.0015x² + 180L) + 0.30·1.2x/(0.05L² + 80 + 1.2x)`; ×0.7 if non_phys.
- `static func level_dr(enemy) -> float`: `dummy → 0`; otherwise `dr = GameData.damage_reduction(level)`;
  boss/miniboss → `dr + 0.05·(1 − dr)`.
- `static func has_condition(enemy, cdp: int) -> float` — a multiplier/counter for ConditionalDamageProperty
  (06b §5): 0 Stunned → flag; 1 LowHealth; 3 FullHealth; 4 Bosses&Rares (rare/boss/miniboss); 5 Ignited (Ignite stacks > 0);
  6 PerPoisonStack (min(stacks,30)); 7 PerBleedStack (min(stacks,30)); 8 Chilled; 9 Slowed; 10 Shocked; 13 Cursed (any isCurse);
  16 Moving; 17 Bosses; 18 PerArmourShred (min(stacks,14)); 19 Bleeding; 20 Frozen (the `frozen` flag: freeze is a state,
  not an AilmentID); 21 PerNegAilment (the number of different ailments); 25 Damned; 26 PerNegAilment≤8; 32 Frozen (flag)|Chilled; 33 Ignited|Shocked; 36 Electrified; 44 Poisoned; 46 Blinded; 47 Frostbitten.
  Returns 1/0 for booleans and a counter for "Per…"; for unknown ones — 0 and the caller writes a note.
  Ailments are looked up by `ailmentIDName` (`Ignite, Bleed, Poison, Chill, Shock, Slow, ArmourShred, Damned, Electrify, Blind, Frostbite`).

## 7. Character — `engine/character_calc.gd` (`class_name CharacterCalc`)

`static func compute(store: StatStore, build) -> Array[Dictionary]` — rows
`{group, label, value: float, text: String, breakdown: String}`. Groups and formulas (06a §4.1, 06c):
- "Attributes": Str/Vit/Int/Dex/Att = `round_half_even(Σadded attr + Σadded 46)`.
- "Resources": Health = `round_half_even(query_untagged(7).value())`; Mana (8) likewise; Health regen (17), mana regen (18) `value()`.
- "Defense": Armor (`query_untagged(10).value() − Σadded 77`), physical damage reduction from armor
  `armour_mitigation(armor, level, false)` (area level = character level); Dodge rating (11), dodge chance
  `0.6·0.001x²/(0.001x² + 32L) + 0.25x/(0.05L² + 80 + x)` (L = level+5, x ≤ 0 → 0); Block chance (29), block effectiveness (53, the rating is shown as a number) and damage reduction on block
  `0.6·(0.0006x² + 1.2x)/(0.0006x² + 1.2x + 60L) + 0.25·3x/(0.03L² + 40 + 3x)` (`CharacterCalc.block_mitigation`, research/06c §2.3);
  Parry chance min(0.75, 121); Endurance min(0.6, Σadded 75); Endurance threshold
  `I76·((maxMore96 + A96)·maxHealth + A76)·M76` (maxMore96 is the largest more of SP 96, otherwise 0);
  Stun avoidance (12); Resistances: 7 rows, only added by groups as for the enemy (`Enemy.resistance`),
  text `"min(res,75)% (uncapped X%)"`.
  "Damage taken from hits" / "… from DoT": per type `(1+added)(1+inc)·Πmore` for `query(6, HIT|DOT | type)`
  (the text is a value or a range across types); Ward per second (92), ward decay threshold (119).
- "Other": Movement speed `query(9).more − 1` as %, Ward retention (16), damage reflection (85), Crit avoidance (89).
Each row: `breakdown` — from `StatQuery.breakdown()` plus a formula explanation.

## 8. Skill — `engine/skill_calc.gd` (`class_name SkillCalc`)

`static func compute(build, slot: int) -> Dictionary` →
`{title, sections: Array[{title, rows: Array[{label, text, breakdown}]}], notes: Array[String]}`.

### 8.1 Input data
`ab = GameData.get_ability(skill.ability)`; `base = ab.primaryDamage` (none → the note "damage is set by code/sub-skills", only speed and mana).
`g = BuildMods.global_store(build)`; `s = BuildMods.skill_store(build, slot, g.store)`; `store = s.store`.
`tags = ab.tags`, then the tree conversions (§5.5): base damage `dmg[to] += f·dmg[from]; dmg[from] −= …` **before** all
modifiers (like `convertBaseDamage`, 06b §1.7), tag change `tags = (tags & ~remove) | add`. Rules with the same field
on different skill mutators (Fireball / FireballExplosion) are applied once. The new tags are used for mod matching,
speed and cooldown; ailment conversions carry over the chance (§8.6).
`hit = base.isHit == 1`; `src = hit ? (tags & ~DOT) | HIT : (tags & ~HIT) | DOT`; add the health tag from `player_state.health`:
full → `HIGH_LIFE|FULL_LIFE`, high → `HIGH_LIFE`, low → `LOW_LIFE`.
`ADE = base.addedDamageScaling`; `dmg[7] = base.damage`; `typeBits` = OR of `DT_TAG[i]` for `dmg[i] > 0`.
`minionMask = tags & MINION`.

### 8.2 buildDamageStats (06b §1)
Iterate over `store.all_mods()` with `extra == 0` (mods with `extra ≠ 0` — only if `extra == ab.abilityIDEnum.value`, then as with 0).
1. **Untyped flat** (only if ADE ≠ 0 and `src & (SPELL|MELEE|THROWING|BOW)`):
   `flat = Σ added` of mods where (`property == 41` and src has SPELL) or (`property == 0` and `(mod.tags & 0xFF) == 0` and `(mod.tags & src & 0xF00) != 0`),
   and `applicable(mod.tags)`. `total = Σ dmg`; if `total > 0`: `dmg[i] += flat·ADE·dmg[i]/total`.
   `applicable(t) = (t & minionMask) == minionMask and LE.tags_match(t, src | typeBits)`.
2. **Damage (property 0)**: parse the mod's tags: `elem = t & ELEMENTAL`; type = the first in the order
   Physical, Lightning, Cold, Fire, Void, Necrotic, Poison whose bit is in t; `other = t` without ELEMENTAL and without this type's bit.
   The mod applies if `(t & minionMask) == minionMask` and `(other & src) == other`.
   - added (only if there is a type and ADE ≠ 0): `dmg[type] += ADE·added`.
   - increased: there is a type → `inc[type] += v`; otherwise ELEMENTAL → inc Fire, Cold, Lightning; otherwise → all 7.
   - more: addressed the same way, `more[...] *= (1+m)` for every m.
3. **Crit** (`critType` from base; 0 Normal): `cc = (1+ccInc)·(base.critChance + ccAdd)·ccMore` over mods 4 with `applicable`;
   `cm = max(1, (1+cmInc)·(base.critMultiplier + cmAdd)·cmMore)` over mods 5; critType 2 → cm = 1; critType 1 → cc = 0, cm = 1.
4. **Penetration** (59): like Damage by addressing, only added → `pen[type / F,C,L / all]`.
5. Result: `dmg[i] = max(0, (1+inc[i])·dmg[i]·more[i])`.
Breakdown for each type: base, added (list of mods), Σinc (list), Πmore (list).

### 8.3 Speed and cost (06b §6.2, 06e)
- `scaler = ab.speedScaler` (2 AttackSpeed, 3 CastSpeed, 54 None).
  `None → S = 1 + use_speed_inc`; otherwise `q = store.query(scaler, tags)`; `S = q.added·(1 + q.increased + use_speed_inc)·q.more`;
  for AttackSpeed and the MELEE tag (or BOW with a bow) `S *= attackRate` of the weapon (`item_sub(weapon).attackRate`, with two weapons — the average).
  `speedScalerAppliedAsIncrease` → `S = max(S − 1, 0)·speedScalerEffectiveness + 1` (06e §1.1; `S·eff + 1` is only the tooltip's bug). `maximumUseSpeed > 0 → S = min(S, max)`.
  `S *= use_speed_more`. `speedScale = S·speedMultiplier·1.1` (≤ 0 → 0.1), `uses/s = speedScale / useDuration` (`instantCastForPlayer` → no division).
- Mana: `cost = (ab.manaCost + mana_added)·(1 + mana_inc)` (mana stats are not counted — a note).
- Cooldown: `ab.cooldown` (if present) / (1 + query(70).increased) — shown.
  The speed and CDR queries pass the ability index (`abilityIDEnum`; extra 0 matches all); a cooldown ≤ 0 caps nothing.

### 8.4 Removed
The model "DPS as in the game's tooltip" (without an enemy) has been removed: the only source of DPS is "Against enemy" (§8.5). The hit numbers match
what the training dummy shows (without damage variance).

### 8.5 Against enemy (06b §7)
`e = Enemy.store(build.enemy)`; for every type i with `dmg[i] > 0`:
`D_i = dmg[i]`; the player's conditional mods (SP 117 by `Enemy.has_condition`): `D_i *= Π(1 + m·count)` for those matching by type
(mod tags → type; no type — all; requiredTags = `mod.tags & ~0xFF` ⊆ src);
`res_mult = (res > 0.75 ? 0.25 : 1 − res) + pen[i]` (res from `Enemy.resistance(e, i)`, no floor);
`DT = e.query(6, src_other | DT_TAG[i]) ` → `(1 + added)·(1+inc)·more` (base 1);
`dr = Enemy.level_dr(enemy)`; `arm = hit ? (1 − armour_mitigation(Enemy.armour(e), level, i != 0)) : 1`.
`Hit_i = D_i·res_mult·DT·(1 − dr)·arm`. Crit against the enemy: `cc_eff = min(1, cc + e.query(112).added)` (if cc > 0);
`E_crit = 1 + cc_eff·(cm − 1)`. `avg_hit = Σ Hit_i·E_crit`; `DPS_enemy = avg_hit·uses/s`.
Breakdown: a table by type with every multiplier.
Hit rows (per single hit, as on the training dummy): "Hit without crit" = `Σ Hit_i`; "Hit with crit" = `Σ Hit_i·cm`
(only for a hit that can crit: `cc_eff > 0`). Hit damage in the game usually varies ×0.8–1.2 on every hit (06b §3.1);
the dummy does not show the variance; "Average hit vs enemy" is averaged over the crit chance and also does not account for the variance.

### 8.6 Ailments — `engine/ailment_calc.gd` (`class_name AilmentCalc`, research/06d)
- **Chance** by AilmentID: the prefab's base chance (`ailmentsOnHit[]`, class `ChanceToApplyAilmentsOnHit`, the same `go` as
  `primaryDamage`) + SP 1 mods (`special` = AilmentID, added, tags ⊆ skill tags + health). Ailment conversions from the rules of
  `skill_conversions.json` carry over the whole chance. One hit on the target per use.
  For curse hits (the `curse_hit` component, §9.3) — only mods with `StatMod.on_curse_hit` ("when a cursed enemy is hit",
  a model with `"on_curse_hit": true`), events/s = hits on the target per second; the general "on hit" chances and `ailmentsOnHit`
  do not apply to them, and `on_curse_hit` mods do not act on ordinary hits.
- **Duration** `T = duration·(1 + Σ SP42)`, **effect** `Σ SP43` (only added, `special` = AilmentID).
- **Stack damage**: `SkillCalc._build_damage` over the ailment's `baseDamage` with tags `(ailment.tags | Ailment | DoT) & ~Hit` + health
  (Spell/Melee/Hit mods do not match), the ailment's ADE; then `× (1+effMore)(1+durMore)(1+damageModifier)`, where
  `effMore = effect` when `effectOfIncreasedEffectiveness == 0`, otherwise the effect goes into penetration `additionalPenetrationDamageType`;
  `durMore = incDur` if the damage is not dealt at the end / on hit.
- **DPS**: `λ = uses/s × chance`; without a limit `DPS = λ·D`, stacks `λ·T`. With a limit `maxInstances`, if `λ·T > max`:
  `a = max/λ`, `DPS = λ·D·(a + 0.4)/(T + 0.4)` (k = 0.4 for enemies).
- **Against enemy**: by type — conditional SP 117 mods, `(res > 0.75 ? 0.25 : 1 − res) + pen`, damage taken SP 6 with tags
  DoT|Ailment, `(1 − DR by level)`, armor only with SP 118 (× the fraction). No crit, variance, dodge or block.
- Non-damaging ailments (shock, shreds, chill) are shown as a number of stacks; their effect on the enemy is set in the "Conditions" tab.

### 8.7 Result sections
For every damage component (§9.3; the first one without a prefix, the others with the prefix "<name>: "): "Damage per use (before enemy)"
(by type, total; for non-first components and when events ≠ uses — the row "Damage events per second"), "Conversions and tags",
"Crit", "Ailment: …". Once after the crit of the first component — "Speed and mana" (uses/s, mana, CD).
Component events/s: `rate` if given, otherwise uses/s × `per_use` × `hits` (`hits` is `Build.skills[slot].hits`,
only for primary and sub; for `curse_hit` always `rate`, `hits` is not used, §9.3). Then "Skill parameters" (one row per `s.params`), "Against enemy" (by type, "Hit without crit", "Hit with crit", "Average hit vs enemy", "Hit DPS vs enemy",
ailments, with >1 component "DPS vs enemy: <name>", the total "DPS vs enemy" = Σ of all components; the details of the
other components are the sections "<name>: Against enemy"), "Not counted" (notes). If none of the components has damage —
only speed, mana and the skill's ailments.

**Sustain** (after "Against enemy", only non-empty rows; `SkillCalc._sustain_rows`, research/06c §3, §5):
- Health leech/s = Σ over components and damage types of `Hit_i(vs enemy) × E_crit × events/s × fraction`, where
  `fraction = (Σ added SP 51 + 10·baseDamage.additionalLeech) × (1+inc) × Πmore × 0.1` (SP 51 is queried with the tags
  `src | type tag`; 06c §5.2, the ×0.1 scale — **D?**, confirmed on skill tree nodes: tooltip = stat×10). The payout of each
  hit is linear over `3 / (1 + Σ added SP 102)` s (06c §5.1), it does not affect the average flow — a separate row. There is no cap;
  stopping at full health and the cap by the target's remaining health are not accounted for (**D?**). Ailments do not heal in the calculation (**D?**).
- Health/Mana/Ward per hit = Σ added SP 38 / 40 / 39 (skill tags + health) × hits/s (hit components only).
  Bonuses to received sustain and "more ward generated" are not accounted for (**D?**); `wardGainModifier` is not from SP 39 (06c §3.3).
- Ward from mana/s = mana cost × uses/s × Σ added SP 99 (the scale is **D?**).
- Health/mana/ward regen (SP 17/18/92) are character stats and are not duplicated in the skill.

## 9. Effect models and skill components (full mechanics coverage)

### 9.1 Effect model — common format (`client/data/*_models.json`)
One schema for the special effects of uniques (§5.4.3), the skill tree mutator fields (`field_models.json`, key
`"Mutator.field"`), the special stat lists of the tree and passives (`list_models.json`, key `"Mutator.list"` /
`"CharacterMutator.list"`), and blessings. The base value `v`: the roll of the mod (uniques) or the field value
`per_point·p + flat` (tree nodes). The `kind` field:
- `stat` (default): StatMod `{stat (SP name), mod: added|increased|more, tags, ailment}`;
  `x = v·(source − offset)·factor` with `per`, otherwise `v·factor`; then `min`/`max`.
- `speed`: `{speed: increased|more}` → the skill's use speed.
- `mana`: `{mana: added|increased}` → the skill's mana cost.
- `cooldown`: `{cooldown: recovery_increased|recovery_more|length_added|length_increased|charges}`.
- `param`: `{param, mod: added|increased|more|set}` — a skill parameter for the "Skill parameters" section
  (`projectiles, chains, pierce, area, duration, radius, count, hits, …`; `hits` — hits on the target per use,
  multiplies the DPS of all the skill's components).
- `trigger`: `{ability (name in abilities.json), on: use|hit|crit|kill|second|end|block|hit_taken|evade|movement|minion_use|totem_summon, chance, count, icd}` —
  a new damage component (§9.3); `chance`/`count` — a number or `"v"` (the effect value). With `per` the chance is the model value
  (`v × source × factor`: Chaos Rip 1% per 1 max mana, Chaos Bolts → Harvest 1% per Dexterity); `single_projectile` — one
  projectile per triggered use (Chaos Rip: one bolt). Events other than use/cast/end/hit/crit/second come from the input `events_<on>` (0 by default).
  An item trigger on use / cast / end does not fire from a triggered use (`use:triggered`).
- Scope `triggered`: the mod goes to `triggered_mods`, given to the skills this skill's tree triggers, not to the skill itself
  (Flay's Deadly Plot: more damage per 100 max mana for the triggered Chaos Bolts and Marrow Shards).
- `base_cooldown`: the effect gives the skill a cooldown of its own (Executioner's Tithe: Great Harvest, 5 s, `use:direct`).
- `v_caps_source`: the effect value caps the `per` source instead of multiplying it: `min(source, v) × factor`
  (Chronostasis: up to v ward consumed per attack, +1 melee damage per 10).
- `component`: `{ability, count}` — the node enables a sub-skill that triggers on every use.
- `minion_stat`: like `stat`, but for the minions of this skill.
- `stat_list`: for `add_stat` into a special list — the stat is taken from the effect itself, the model sets `scope`/`when`/`per`.
- `resource`: `{resource: mana|health|ward, on: hit|kill|use|second}` — only a row in "Skill parameters".
- `flag`: `{text}` — changes behavior, does not affect numbers.
- `conversion`: a rule from `skill_conversions.json` (already counted by §5.5).
- `scope`: `skill` (default) | `component:<sub-skill name>` | `global` (onto the character) | `minion`.

Common fields: `per` (source, §5.4.3, plus `input:<key>`, `player:shadows` and `buff:<AilmentID name>` — stacks of a buff
on the player, §9.10), `when` (conditions, §5.4.3, plus `input:<key>` — a boolean input, and `use:direct|shadow|echo` —
who uses the skill, §9.10), `at_least`/`below` (`{per, value}` or `{per, value_per_v}`: the threshold is the effect value
× `value_per_v`, Careful Assault), `offset`, `factor`, `min`, `max`, `src_max`, `inverse` (x → 1/(1 + x) − 1, a «more»
that cancels another one), `note`, `on_curse_hit` (an ailment chance only when a cursed target is hit, §9.3), `confidence` (D / D?).
`input`: `{key, label, default, max, bool}` — the declaration of a skill input parameter (stacks, number of totems,
"while channelling" …); the values are `Build.skills[slot].inputs[key]`, `default` by default.

### 9.2 `engine/effect_models.gd` (`class_name EffectModels`)
`ctx = {build, store: StatStore, slot: int (skill slot or -1), item_slot: String (item slot or "")}`.
- `blocked(model, ctx) -> String` — "" if the conditions are met, otherwise the text of the condition (in English).
- `value(model, v, ctx) -> Dictionary {x: float, text: String}` — the final value and the explanation of the source.
- `make_mod(model, v, ctx, label) -> StatMod` (null if the SP is unknown).
- `source(per, ctx) -> float`, `source_name(per, ctx) -> String`, `holds(cond, ctx) -> bool`, `phase(model) -> String`.
- `inputs(model) -> Array[Dictionary]` — the inputs declared by the model.

### 9.3 Damage components — `engine/skill_components.gd` (`class_name SkillComponents`)
`collect(build, slot, ab, s) -> Array[Dictionary]`: `{name, kind: primary|sub|trigger|minion|curse_hit|dot, ab, base (damage record),
per_use (times per use), rate (events/s, if not from uses), chance, icd, mods: Array[StatMod]}`.
- `primary`: `ab.primaryDamage`; if empty — sub-skills with the reason `prefab:CreateAbilityObjectOnDeath|OnStart|
  CastAfterDuration` (linked via `parents`), otherwise the damage from `abilities_code_damage.json`. Not per use, so skipped:
  `CastAfterDuration.alternateAbility` (the combo's other strike, Flay 2 Damage instead of Flay 1 Damage) and a sub-skill
  linked through another record cast by `ChanceToCastOnKill` (Flay Blood Explosion through its on-kill delayer).
- `sub`: the prefab's sub-skills (the same reasons) for skills with their own damage; `component` models of nodes. The same sub-skill from
  several sources (prefab + node) is one component with the sum of `per_use`, not a duplicate: for Transplant the prefab gives one
  detonation (DetonateBody), the node "Reign of Blood" (`TransplantMutator.explodesAtEnd`) another one on arrival (in the game
  "detonations = 1 + additional", research/07h), so on a build with the node `per_use = 2`, the row "Damage events per second"
  = 2 × uses/s, one section (without "DetonateBody: …"); without the node — one detonation per use.
- `dot` (Spirit Plague): a code component without a hit (`isHit` false / no crit block), with `duration` and `maxInstances = 1`.
  The base damage of the record is the **whole** damage over the base duration (90 necrotic over 3 s at ADE 4.5 = 1.5 × 3 s, not damage per
  second). One instance lives on the target, it is maintained by reapplying (uptime 100%), so damage events per
  second `rate = 1 / duration` (not uses/s), damage per second = instance damage / `duration`. There is no crit or variance
  (`critType` without crit; the sections "Crit", "Hit with crit", "Average crit multiplier" are not shown, "Penetration" remains).
  Rows: "Damage over full duration (3 s)", "Damage per second" (in the component section), "Damage over full duration vs enemy (3 s)",
  "Damage per second vs enemy" (in "Against enemy" instead of "Hit without crit"…"Hit DPS vs enemy"). Against the enemy as with ailments
  (§8.6): resistance and penetration, damage taken, target level; armor only with SP 118; no crit, block or variance.
  Increased duration (the tree's `param duration`) stretches the instance and raises its damage in the same proportion — damage per
  second does not depend on it (shown in the breakdown). Tree mods (`moreSpiritPlagueDamage`, damage per Intelligence, etc.)
  are applied to `base` through the regular pipeline of §8.2. The skill's ailment chances (poison, etc.) are counted per uses/s, not per
  damage events; leech — per damage events (D?: a DoT may have no leech). The rule is general: it applies to any
  code component with `isHit` false, `duration` and `maxInstances = 1` (Spirit Plague, Abyssal Echoes `abyssal_decay_dot`);
  stacking DoTs (`maxInstances` ≠ 1: Aura of Decay, Anomaly `time_rot`) are still counted as `sub` per use.
- `trigger`: `trigger` models (nodes, uniques, passives): frequency = event frequency × chance, no more often than 1/icd.
- `skill`: a trigger of a skill that is on the bar (specialized): computed through that slot as a triggered use
  (`SkillCalc._triggered_skill`: `skill_store(…, "triggered")` + the parent's `triggered_mods`, uses/s = the trigger rate, its own
  triggers — a chain, at most `TRIGGER_DEPTH` = 3 levels, a slot already on the chain is not counted again). Only its hits count:
  curse damage, a maintained DoT and minions of the triggered skill stay in its own slot. Flay → Chaos Bolts → Harvest / Rip Blood.
  The ailments of a triggered use are part of its DPS but do not feed the automatic enemy ailments (EnemyAilments) yet.
- `curse_hit` (Bone Curse): a code component with `moreDamageWhenHitByCreator` (the curse hits the target on every hit on it;
  applying it deals no damage itself, reapplying only refreshes the single curse, uptime 100%). The damage of a single
  hit is calculated by the regular pipeline (ADE, crit, the skill's increased/more; it is a hit, so armor and the target's
  level apply). The frequency is not from uses but from two skill inputs (`Build.skills[slot].inputs`, declared in `s["inputs"]`):
  `curse_own_hits` — your hits on the cursed target per second (the default estimate: the sum of uses/s of the other skills
  on the bar that have hit damage — `SkillComponents.deals_hit_damage`, speed from `SkillCalc.uses_per_second`; this is
  only the speed pipeline without recursion into `compute`; the number of hits per use is not accounted for; if set manually, it is used)
  and `curse_other_hits` — hits by minions and allies (0 by default). Damage events/s
  `rate = own·(1 + moreDamageWhenHitByCreator) + other` (your hits ×3), hits/s `hit_rate = own + other`. The skill's `hits`
  multiplier is not used. The curse's damage is calculated over the same weighted events in "Against enemy". Ailment chances are not from
  use: the general "on hit" chances do not apply, the "when a cursed enemy is hit" nodes (`on_curse_hit`) use `hit_rate`.
  Per-hit rewards (SP 38/39/40) are counted per `hit_rate`, leech — per weighted events.
- `minion`: §9.4.
`SkillCalc.compute` calculates every component with the same pipeline (§8.2–8.6) and adds the DPS up in the "Total" section.

### 9.4 Minions — `engine/minion_calc.gd` (`class_name MinionCalc`, research 07d §1, 07j §4)
Data: `minion_base_stats.json` (`summonedBy`, `health`, `innateStats`, `protection`, `abilityList`, `castSpeedOverrides`,
`summonSettings[{numberToSummon, limit, duration…}]`, `mutators`). For a summoning skill (`summonedBy` contains the skill name):
- Minion stats = a snapshot of the player's stats by the `SummonEntityOnDeath` rule (07d §1.1): skip SP 38/39/40/50/126/127;
  a stat with `extraTag` = the ID of the summoning skill or with the Minion tag (Totem — if the skill is a totem) passes over with the tags
  `tags & ~(Minion|Totem)` and `extraTag 0`; other player stats do not pass over. Plus the actor's `innateStats`, plus
  `minion_mods` from the tree (§9.1, `minion_stat` / `stat_list scope minion`, as is), plus the player's hidden base for minions
  (Movespeed MORE 0.10, DamageTaken MORE −0.6 PetResisted — already in the player's stats with the Minion tag).
- Damage: every ability from `abilityList` with damage is a `kind: minion` component (§9.3), the pipeline of §8.2–8.6 on the minion's stats
  (the minion's level does not scale damage; the `levelScaling` of minion abilities is not applied). Attack frequency: the minion's attack/cast
  speed (SP 2/3, base 1) × 1.1 / `useDuration` from `castSpeedOverrides` (or the ability).
- Number of minions (`engine/minion_count.gd`, `class_name MinionCount`): one global count per minion type summoned by
  the bar skills — the card «Active minions» of the Conditions tab (`Build.player_state.minions`, keyed by actor name), by
  default the summon limit `MinionCount.limit_of`: the base (the `limit` of the summoning skill's `summonSettings` entry,
  `numberToSummon` when unlimited; `GROUPS` for summons whose minions the tree chooses — Summon Skeleton 3, Summon Skeletal
  Mage 2, the constants of `getSkeletonLimit` / `getSkeletonMageLimit`), then the skill's «Max …» parameters
  (`LIMIT_LABELS`: tree nodes and passives aimed at the summon's mutator, e.g. `additionalSkeletonsFromPassives`; set,
  added, increased, more), the AbilityProperties of passives, items and uniques (`LIMIT_PROPERTIES`, the
  AbilityStatsMutatorManager fields `addedSkeletonSummonCap`, `additionalMaxSkeletalMages`, `boneGolemAdditionalMaxGolem`,
  `additionalMaxWraiths`, `extraAddedMaxForgedWeapons`, `addedMaximumThornTotem`, `addedMaximumBallistae`,
  `stormTotemAdditionalTotem`, `extraNonCompanionCapSpriggans`, `maxLocusts`; `doubledMaxSkeletons` ×2; wolves / raptors
  «up to your maximum number of companions» = Round((2 + SP MaximumCompanions) …), research 07d §1.4), rounded. Not read:
  the shared companion cap across companion skills, Bone Golem's extra golems per skeleton and its tree flag (D?).
  Summon Skeleton and Summon Skeletal Mage (`GROUPS`) have no minion records of their own: their count is split evenly
  between the members of the rotation the tree flags allow (`MinionCount.rotation` / `members`: warriors and archers,
  rogues with «Adds rogues», at most one warrior with «Max one warrior»; mages, cryomancers, pyromancers, death knights),
  and every member is a minion component with its own record (`MinionCalc.minion_by_actor`). The per-type stat lists
  (`warriorStatList`, `archerStatList`, `rogueStatList`) have the scope `minion:<actor>` (`minion_actor_mods` of the skill
  store), so they reach only that type. DPS = DPS of one × the number.
- Ability choice (`MinionCalc.components`): MADStateController gives a minion with two or more ability ranges
  `UsingMultipleAbilitiesAI`, whose `chooseAbility` takes the first ability of the list that is not on cooldown and has a
  charge. So an ability with a cooldown or charges (`_use_cap`: the minion record's cooldown / maxCharges /
  chargesGainedPerSecond plus `addedCharges` / `addedChargeRegen` of the minion's mutators, × the minion's cooldown
  recovery) is used whenever ready, the first one without takes the rest of the time and the abilities after it are never
  used; abilities without damage take their time too. Ranges and health thresholds of the prefab's AbilityRangeList are
  not extracted: the target is assumed within range of every ability (D?).
- Summon AbilityProperties that are minion stats (`MinionCalc.MINION_PROPERTIES`: Summon Skeleton crit chance,
  increased damage, physical / poison penetration, armour, attack / cast speed, cooldown recovery; Summon Skeletal Mage
  crit chance and increased damage) are added to every minion of the summon (`property_mods`); `handles_effect` keeps
  their passives (and the summon limit properties) out of the «not counted» notes. The models that scale with a minion count
  (`per: input:<key>` of `MinionCount.COUNT_KEYS`: `minions` = all minions but totems, `totems`, `wolves`, `raptors`,
  `crows` = `storm_crows`) read the same card: a number set by hand, else the sum of the summoned types it covers. These
  keys are never per-skill fields (`EffectModels.inputs` drops them), so passives and uniques («per minion you control»,
  «per active totem», Spriggan auras per wolf / raptor / crow) follow them too. The card lists the summoned types and only
  the counts a model of the build reads (ConfigRelevance group `minions`; the global store is recorded as well). The rows "Minion health", "Armor" and the resistances are in the section "Minion: <name>".

### 9.5 Blessings — `BuildMods._add_blessings` (`blessings.json`, 07a §8.2)
`Build.blessings: {timelineID: {id: blessingId, roll: 0..255}}`, one per timeline (normal or grand — from
`timelines[].difficulties[].otherSlotBlessings/anySlotBlessings`). A blessing's implicits → StatMod like an item's implicits
(`AffixMath.roll_value(value, maxValue, rounding, modType, roll, 0)`), source `Blessing "…"`.

### 9.6 Trigger frequency and cooldown
- The `on` event of a `trigger` model: `use` / `cast` = uses/s; `hit` = uses/s × hits (`hits`); `crit` = hit frequency
  × crit chance; `kill` = the input `kills_per_second`; `second` = 1; `end` = uses/s; `hit_taken`, `block`,
  `dodge`, `potion`, `minion_hit`, `minion_death`, `stun`, `death` — skill inputs with the number of events per second (0 by
  default, the label is in English). Frequency = event × `chance` × `count`, no more than `count / icd`.
- Skill cooldown: base `ab.cooldown` or `cooldown_base.baseCooldownLength`; length `(base + length_added) ×
  (1 + length_increased)`; recovery `(1 + Σincreased CDR (SP 70) + recovery_increased) × (1 + recovery_more)`;
  result `length / recovery`. `charges` (base 1) only affect a burst; in the steady state
  uses/s = min(frequency by cast speed, 1 / cooldown).
- Granted skills (`engine/granted_calc.gd`, `class_name GrantedCalc`): an ability that a trigger casts (character-mutator passive,
  unique or affix, skill tree node) and that is not on the bar is a "virtual slot" of the Calculations tab. `SkillCalc` tags the
  sections of such a component (`granted`) and lists them in `result.granted` / `granted_names`; `GrantedCalc.skills(build)` is
  the list (id = ability `name`, owner = the first bar slot whose triggers cast it), `GrantedCalc.compute(build, id, details)`
  a `SkillCalc.compute`-shaped view built from the owner's result: the same rate (event × chance × count, icd cap), the same
  numbers, level 1 (no level of its own), and no new damage — the owner keeps counting the component, so nothing is counted
  twice. The selection is kept by the tab (never in `Build.selected_skill`, which stays a bar slot). Character events (`second`,
  `hit_taken`, …) of passives are counted in the first slot whose skill deals damage by itself only (`UniqueEffects.first_skill_slot`;
  a skill's own events `use` / `hit` / `crit` count in every skill). The rate is `event × min(1, chance) × count`; the limit is either a
  ProcTimeTracker window (default: at most `count / icd` per second) or, with `cooldown: true`, a cooldown field that starts after a
  SUCCESSFUL roll (`count / (icd + count / rate)`); `stochastic: true` (StochasticRound fields) lets a chance above 100% give several
  casts, otherwise it is one guaranteed cast. `skill_any` limits a trigger to skills with a tag. Casts of the character (passive of
  the character mutator, player property of an item/affix: `character` on the trigger) are built with the player's own stats (global
  store), not the stats of the skill in use (game code: the player constructor with no mutator). Sources: research/10_trigger_audit.md.
- Flame Walker (`CharacterMutator.OnUpdateTick`): `on: second`, one roll per 1 s tick, chance 10% per point doubled while fewer than 3
  (`double_below`) Fire Auras are active (input `fire_auras`, 0 = estimate: casts per second × `stack_duration` 4 s), cast only while the
  character moves (Conditions) or a Melee skill is in use (`moving_or_melee`; the skill is assumed to be used all the time).
- The basic attack (`BasicPlayerAttack`, ba1; `BasicPlayerBowAttack` with a bow) is always the first virtual slot: a full
  calculation on a temporary slot after the bar (`GrantedCalc.with_basic_slot`, removed afterwards; level 1, default hits and
  event rates). It is not part of any bar skill's DPS; skills it triggers (Flame Walker casts on a melee attack) are listed as
  granted skills owned by the basic attack when no bar skill casts them.

### 9.7 Skill buffs on the character and passives on skill mutators
- **Scope `global`** (§9.1; `stat`, `stat_list`, buffs on use, `statsInForm`, `statsWhileActive` …): `_add_scoped` puts the
  mod into `result["global_mods"]` of the `skill_store` result, not into the skill's local store. At the end (after the
  post-phase of passives and uniques) `BuildMods.global_store` calls `skill_store(build, slot, store)` for every equipped skill (`skill_store`
  itself does not call `global_store` — no recursion), collects the `global_mods` of all slots and adds them as one batch
  (slot order does not matter; a mod reads the store at the moment of collection, attributes from buff stats to Strength/Intelligence are not recalculated).
  Source: `Skill "<name>" (buff): <original source>`. One skill is counted once (duplicates on the bar are ignored).
  A buff applies only with the skill input `buff_active` (`Build.skills[slot].inputs`, enabled by default; declared in
  `result["inputs"]` as "Skill buff active" if the skill has a scope-global model — even with an unmet condition).
  The skill itself and all the others see the buff through the parent (`store.parent = global`), so there is no duplicate in its own store.
  The model's own input with `default: true` (`when: input:<key>`) is considered enabled when not set (`EffectModels.blocked`).
- **Buffs from mutator code** — `engine/buff_skills.gd` (`class_name BuffSkills`, connected in `build_mods.gd` via `preload`),
  `client/data/buff_skill_models.json`: `{"<abilityName>": {stats: [{stat, mod, tags, value, label, source, …}], note, uptime,
  confidence, source, ability_id, effect_index, active_input, active_multiplier, mode_passive, mode_active, tree_lists:
  {passive, active}, ability_properties: [{index, stat, mod, active_k, …}]}}`; the key is the skill's `abilityName`; keys with `_`
  are skipped. Only numbers read from the code (Ghidra, ISIL, `tools/readconst.py`), nothing is invented. Entry keys (in
  `stats` and `ability_properties`): `active_only` / `passive_only` (the model's `active_input` mode), `active_value` (the value in
  active mode instead of `value × active_multiplier`), `when_input` (the entry only with the input enabled), `per_input`
  (value × the input, e.g. the number of sigils or stacks), `no_m` (without the multiplier `M = 1 + the effect_index property`). Inputs
  are declared in `result["inputs"]` once per key. The tree list (`tree_lists`) replaces the field models of these lists
  (`BuffSkills.owns_list`): in passive mode the passive list is used, in active mode the active one (it is already ×2 there).
  Currently in the model:
  - **Holy Aura** (07l, `holy_aura_model.json`): `M = 1 + Σ AbilityPropertyStat(holyAura #0)` from passives (Covenant of
    Light 0.04/point); passive: ER +0.15 and Damage increased +0.30, `AuraMutator.statsToApply` — `v·M`; the empowered cast (input
    `holy_aura_active_cast`, off by default): base `2·v·M`, `HolyAuraMutator.statsToApply` (already ×2 there) `v·M` —
    replaces the passive; properties #1 (ManaRegen increased), #9 (Movespeed), #10 (StunAvoidance) `v·M` (active ×2), #6 (HealthRegen
    added, active only, without ×2).
  - **Symbols of Hope** (`SigilsOfHopeMutator..cctor`, `AddStatToAura`): per sigil (input `sigils`, 3 by default) ×
    `M = 1 + AbilityProperty(sigilsOfHope #1)` (Covenant of Light): HealthRegen increased +0.2 and Damage added +3 (Fire × Melee /
    Spell / Throwing / Bow); property #2 (HealthRegen added, Covenant of Protection ≥ 5 points, +5). The input `sigils_active_use`
    (off by default, activation 3 s): the sigils are spent, the passive stats disappear, DamageTaken more −0.05 per sigil (without M;
    +100 barrier per sigil is not modeled).
  - **Enchant Weapon** (`EnchantWeaponPassiveMutator..ctor`, `EnchantWeaponMutator..ctor`): the passive Damage more +0.15
    (Elemental|Melee) always; the input `enchant_weapon_active_cast` (off by default, 5 s out of a 15 s cooldown): the same more stat
    +0.5 replaces the passive (one buff name). The tree lists `EnchantWeaponPassiveMutator.statsToApply` / `EnchantWeaponMutator.statsToApply`
    go through `tree_lists` (previously both were added: passive + active).
  - **Firebrand** (`ModifyFirebrandStacks`): Damage added +5 (Melee|Fire) per stack, the input `firebrand_stacks` (4 by default;
    a stack lasts 4 s, maximum 4 + extra); the conversion to lightning (node) is not counted.
  - **Aura Of Decay** (`AuraOfDecayMutator.Mutate`): while the aura is on DamageTaken more −0.3 with the tags DoT|Poison.
  - **Dark Quiver** (`applyStatsFromBlackArrow`): Damage increased +1.0 (tag Bow) for the next bow attack; the input
    `black_arrow_ready` (off by default), a conditional stat of a single attack.
  Checked and found no numeric buff in the code (it all comes from tree fields, AbilityProperty or prefab data): Warcry (Berserk 4.0 —
  a tree node), Rebuke, Arcane Ascendance, Flame Ward, Ice Ward (not a bar skill), Death Seal, Eterra's Blessing, Healing Hands,
  Ring of Shields, Manifest Armor, Smoke Bomb, Fury Leap, Focus, Dread Shade, Sacrifice, Transplant, Teleport, forms (Spriggan,
  Swarmblade, Werebear, Reaper). Their tree buff goes through the scope global models above.
- **Passives targeting a skill mutator** (`LungeMutator.increasedCooldownRecoverySpeedFromPassiveTree`,
  `TeleportMutator.increasedCastSpeedFromPassives`, `DivineBoltMutator.extraProjectiles`, `…statListFromPassiveTree` …):
  `BuildMods._add_skill_passives` in `skill_store` takes the effects of passive nodes (`points ≥ minPoints`) whose target is not
  `CharacterMutator.*`, keeps the parts of the target that belong to the skill (`BuffSkills.owns_mutator`: the `mutators` list of the skill tree in
  `skill_node_effects.json`, the skill's mutator class, or the skill name + "Mutator"), and applies them with the same `_apply_field_models`
  / `_apply_list_effect` / conversion rules as tree nodes (source `Passive "…" ×N`). In `global_store` such an
  effect no longer produces a note if the skill with this mutator is on the bar; otherwise the "not counted" note remains.

### 9.8 Which conditions a build needs — `engine/config_relevance.gd` (`class_name ConfigRelevance`)
The "Conditions" tab shows (like Path of Building) only those checkboxes and fields that have a source in the build.
`ConfigRelevance.compute(build) -> {player_flags: {key: reason}, player_values: {key: reason}, player_buffs: {AilmentID: reason},
ailments: {AilmentID: reason}, enemy: {flag: reason}}`; a key is present — the control is needed, the reason is the English text of the source (up to three lines joined by `\n`, for the tooltip).
Sources:
- the `when` conditions and the `per` / `at_least.per` / `below.per` sources of all effect models (uniques, passives, skill trees):
  `EffectModels.blocked` calls `ConfigRelevance.note_model` while `compute` rebuilds `global_store` and the `skill_store` of every
  slot with recording enabled (outside `compute` recording is off);
- conditional damage SP 117: which enemy flags and ailments `Enemy.has_condition(cdp)` reads is found by probing — an enemy with
  only one key set; a condition that triggers from any of more than 8 keys ("per ailment") is not shown by key;
  damage per stack SP 115 — the ailment `special`;
- ailments that the build applies: the skill prefab's chances (`ailmentsOnHit`), the chance stats SP 1 (`special` > 0), ailment
  conversions (SP 100 and `ailment_convert` of tree rules);
- Haste / Frenzy on the player: `HasteOnHitChance` and the ailment effect on you SP 120 with `special` = 33 / 34;
  a chance to apply a positive ailment (Void Essence, Dusk Shroud …) goes to `player_buffs`, not to the enemy;
- shadows and buffs on the player (§9.10): a bar skill imitated by shadows; texts of the taken passive and skill nodes, of
  the bar skills and of the equipped uniques that name `{Shadow}`, a buff's display name or "any Shroud".
Cost is ~12 ms, called only while the tab is visible. Check — `tests/relevance_test.tscn`.

### 9.9 Projectiles and shotgun — `SkillCalc.projectile_hits`
Data: `research/data/game/ability_projectiles.json` (local script `tools/extract/extract_projectiles.py`, from the
AssetRipper prefabs and Ability assets): ability record name → `{abilityName, projectiles, shotgun, confidence, evidence}`.
`projectiles` = 1 + `ExtraProjectiles.numberOfExtraProjectiles` of the projectile object (the root prefab, or a damaging
sub-ability with ExtraProjectiles: Hungering Souls); Chaos Bolts is code-driven (5 bolts, D?).
`shotgun` — several projectiles of one use can damage the same target. Game logic (ISIL):
- `Ability.sharedHitDetector` (overridable by `AbilityMutator.useSharedHitDetector`: Multishot `canShotgun`, Shurikens
  `shotgun`) gives the first object of a use a `SharedHitDetector`; `HitDetector.hitActor` then checks the shared
  "enemies hit" list instead of its own unless `bypassSharedHitDetection`.
- `AbilityObjectConstructor.constructAbilityObject(..., InheritSharedHitDetector = true)`: a new object takes its creator's
  shared detector; without one it gets a new detector if its own ability uses one. `ExtraProjectiles`,
  `CreateAbilityObjectOnDeath` and `CastAfterDuration` all pass `true`, so extra projectiles **and the explosions they
  spawn** share one hit list per use: with a shared detector the explosions of one use cannot stack on one target either.
  `HitDetector.cannotHaveSharedhitDetector` skips the assignment (the object hits independently).
- Without a shared detector on the skill (Umbral Blades, Chaos Bolts, Volcanic Orb, Detonating Arrow, Static Orb) every
  projectile and every explosion hits on its own.
Tree params: `projectiles` (added extra projectiles), `projectile_limit` (cap of extra projectiles), `shotgun` (set 1 by
the nodes above). `Build.skills[slot].projectile_mode` = `one | average | all` (default `average`): the number of
projectiles hitting one target is 1 / (1 + N) / 2 / N with shotgun, always 1 without. The factor multiplies the hits per
use of every component (with the "Hits on the target per use" input); row "Projectiles hitting the target" in
"Against enemy", `result.projectiles = {count, shotgun, mode, factor, row}`.
Minions (§9.4) whose ability is in the file (Thorn Totem thorns, Skeleton Rogue shurikens, Cryomancer Woven Ice …): the
rate of their `minion` component is multiplied by the same factor, with the summoning skill's mode and tree params; one
row per minion ability ("<minion>: Projectiles hitting the target"). Without own projectiles `result.projectiles` is the
minion's (a shotgun one preferred), so the selector is shown for such summons too. Check — `tests/engine_test.tscn` (`_projectiles`).

### 9.10 Repeated uses (shadows, echoes), buffs on the player, combo parts
**Shadows** — `engine/shadow_calc.gd` (`class_name ShadowCalc`). A shadow (CreateShadow, AbilityID 469) imitates your next
direct use of Shadow Cascade, Shurikens, Umbral Blades, Dreamslash or Acid Flask (ability descriptions); up to 3 + the
CreateShadow property 0 are active. `Build.player_state.shadows` (Conditions, "Active shadows", clamped to the limit) is
the number of shadows that repeat each use: every hit component (primary / sub) of an imitated skill gets a copy
"Shadows: <name>" with `per_use × shadows` (the node "Shadows do not execute Dreamslash" turns it off). The copy runs
on `BuildMods.skill_store(build, slot, global, "shadow")`: models with `use:shadow` apply only there, `use:direct` only to
your own use (a model of the other user is skipped without a note). Extra mods of a shadow use: increased damage =
CreateShadow property 2, crit chance = property 4 (passives and the mastery bonus, item and idol affixes, unique effects;
their «not counted» notes are dropped); Umbral Blades shadows throw one blade with 300% more damage and do not get the
single-blade bonus of your throws (`BaseUmbralBladesMutator.getTempStats`: MoreStat 3 when usedByShadow, then
1 / (1 + singleBladeDamageBonus) − 1; the player's +250% comes from the node's temp stats). Per-shadow node values
(Shadow Torrent, Figments of Annihilation, Lethal Mirage, Dark Quiver, Careful Assault's minimum) read `player:shadows`.
A shadow is consumed by the use it imitates and lasts up to 5 s, so keeping N shadows takes N × max(uses/s, 1/5)
creations per second; health (property 1) and ward (property 3) gained per creation (`CreateShadowMutator.Mutate`:
`BaseHealth.restoreHealth` / `ProtectionClass.GainWard`) become the skill's sustain rows (`ShadowCalc.sustain_rows`, read
by the Defense tab). Property 5 is the chance that a used shadow comes back (`RogueShadow.RollResummonChance`, plus the
Umbral Blades bonus): it only helps keep the Conditions number and is named in the shadow component's note.

**Void Knight echoes** — `engine/echo_calc.gd` (`class_name EchoCalc`, `CharacterMutator.TryToEchoAbility`, pseudo-C):
chance = Σ `chanceToRepeatMeleeThrowingAttacksAndVoidSpells` (the Void Knight mastery 10%, passives); Rive ×
(1 + `echoChanceModifierWithRive`); Vengeance + `additionalEchoChanceWithVengeance` and Abyssal Echoes +
`abyssalEchoesAdditionalEchoChance` when the chance is already above 0; the tree param `echo_chance`. A skill echoes if its
tags have Melee, Throwing or Void + Spell, it is not a movement skill (Void Cleave is allowed), not Anomaly and not
channelled (`AbilityInfo.isChanneled`, interface slot 27 — checked against slots 8 `getUseDelay`, 32
`getAbilityAnimation`, 80 `GetCastingVFXIndex` of the same call). Components "Echo: <name>" with `per_use × chance` on the
store of `use:echo`, plus increased damage PlayerProperty 57 (items, idols, uniques), Rive's `moreEchoDamageWithRive`
(more) and `echoTimeRotChance` (Time Rot chance). The 1 s delay does not change DPS.
Warpath echoes only with its node «Warpath can echo» and by its own rule (`WarpathHitMutator.OnMutatorUpdate`): once per
second, when you moved at least 4 units over the last 2 s, it rolls (1 + `WarpathMutator.echoChanceModifier`) × the echo
chance and casts Warpath with the echo use type where you were. A channelled skill's echo components therefore get a fixed
`rate = per_use × chance / 1 s` instead of uses/s × chance; the length of an echoed channel is taken as one use (D?).
Mechanic checks read `skill_store().flag_keys` (the untranslated flag model texts); `flags` holds the shown texts.

**Buffs on the player** — `Build.player_state.buffs: {AilmentID: stacks}` ("Buffs on me" on Conditions:
`GameData.player_buffs()` = positive ailments with stats plus Silver Shroud, without Haste / Frenzy which are checkboxes).
`BuildMods._add_player_ailments` adds the buff stats × stacks (at most `maxInstances`) × (1 + effect of the ailment on you
SP 120); AbilityProperty / PlayerProperty buff stats are skipped. Models read the stacks as `per: "buff:DuskShroud"`
(`BuildMods.buff_stacks`). The build code stores the keys as strings.

**Combo parts and sub-ability mutators** (`BuildMods._add_skill_node`). A node often writes one field into the mutators
of every part of a skill (Umbral Blades: UmbralBladesMutator / UmbralBlades2Mutator / UmbralBladesRecallMutator; Flay and
its blood explosion; Volatile Reversal and its return). The parts share the skill's store, so a field the node also
writes into the skill's own mutator (`ability.mutator.class`) is counted once, except `component` / `trigger` models
(Volatile Reversal casts void bolts on the jump and on the return within one cooldown). A target only in the mutator of a
combo part (`reasons` has `Ability.comboAbilities`) or of another player skill (`GameData.ability_by_mutator_class`)
puts its stats into that ability's damage component (`scope_override`), with a note; they are dropped when the skill has
no such component. Other sub-ability mutators keep the old behavior (into the skill's store).
The other way round, `BuildMods._add_other_skill_nodes` gives a skill the parts of node targets aimed at its own mutator
from the trees of the other bar skills (Summon Bear → Swipe damage, Multistrike → Void Cleave damage, Firebrand → Flame
Reave, Umbral Blades → Shift mana per recalled blade); the source names the other skill.

### 9.11 Automatic enemy ailments — `engine/enemy_ailments.gd` (`class_name EnemyAilments`)
An ailment, shred or curse of the enemy takes the number set on the Conditions tab when there is one
(`Build.enemy.ailments` holds only those, an explicit 0 included; `Build.clear_enemy_ailment` returns one to automatic).
Every other ailment takes the average kept on the target.

**Applications.** `AilmentCalc.compute` returns `applied` (id, applications/s = hits/s × chance, duration × (1 + increased
duration), maxInstances) for every damage component, `SkillCalc` tags them with the component kind and name
(`_tag_applied`) and returns `ailments_applied`, `cooldown` (the skill has a cooldown) and `flag_keys`. Sources:
- hits of the skill's components: primary, sub-skills, triggers, minions, shadow and echo copies;
- **zones** (`AilmentCalc.zones`, prefab `RepeatedlyApplyAilmentsInRadius`: every `applicationInterval` s to the enemies in
  the radius, no hit; game code `OnUpdateTick`) of the skill, of its components' abilities and of the abilities its tree
  grants as components or triggers, damage included (`SkillCalc._zone_results`, sections «Zone "…"»). The target is
  assumed to stay in the zone (D?). Chances of the zone: its own ailments plus, for the skill's own zone, the AilmentChance
  stats of the skill store (tree nodes; «on hit» chances of items and passives do not apply). Aura of Decay is such a zone
  (poison every 0.25 s); its old code component (`abilities_code_damage.json`, one poison per use) is skipped;
- **threshold strikes** (`THRESHOLDS`): Shadow Daggers strike at 4 stacks («Upon reaching 4 stacks», ShadowDaggersFinisher:
  68 physical, added damage ×3.4, always crits): a `trigger` component of the skill with rate = applications/s / 4
  (× load / 4 when the stacks expire first, D?), plus property 0 of AbilityID 508 (more damage against rares and bosses).

**Average.** `EnemyAilments.auto(build, slot)` reads one pass of every bar skill against the Conditions values only
(`_raw`, cached by the build state) and sums the applications of the skill itself and the parallel sources of the other
bar skills: their minions and zones always, everything of a skill with a cooldown (used on cooldown).
- load = Σ applications/s × duration; stacks = min(load, maxInstances), a single-instance ailment counts its uptime;
  uptime = 1 − e^(−load);
- threshold ailments: (N − 1) / 2 × min(1, load / N) stacks, uptime × (N − 1) / N;
- consumption (`CONSUMERS`: flags of nodes whose hits spend Bleed / Ignite / Poison — Dive Bomb, Abyssal Echoes, Puncture,
  Enchant Weapon, Flame Rush, Rive, Soul Feast) by the skill itself or a cooldown skill: wiped every P = 1 / Σ uses s,
  `consumed_load` = rate × P / 2 (rate × (T − T² / 2P) when the duration T < P).
`EnemyAilments.effective` gives a copy of the enemy with the stacks in `ailments` and the uptimes in `uptime`
(`APPLIED_KEY` marks it, nested calculations add nothing). `SkillCalc.compute` uses the averages of that skill;
`DefenseCalc.compute` and the Conditions tab use the selected skill's. Readers: `Enemy.store` (ailment buffs × fractional
stacks), `Enemy.has_condition` (a «vs X» condition is the presence: the uptime of an automatic value, 1 for a number set by
hand, so `1 + more × presence` is the expected factor; «per stack» reads the stacks; «per ailment» sums the presences),
`EffectModels` (`enemy_stacks:` per-stack sources; on/off `enemy:` conditions hold from a presence of
`PRESENT_SHARE` = 0.5, D?). `EnemyAilments.enabled = false` turns it off for tests that compare with in-game measurements
on a dummy.

**Buffs on you** («Buffs on me»: `Build.player_state.buffs`, an explicit 0 included; `Build.clear_player_buff` returns one
to automatic) work the same way through `EnemyAilments.buffs(build, slot)`. Gains:
- positive ailments among the chances of the skill's hits (`AilmentCalc` marks them `self`: section «Buffs on you», never
  an enemy ailment) — tree models such as Hail of Arrows' Dusk Shroud chance;
- «on you» prefab ailments per use (`ApplyAilmentToCreator`);
- PlayerProperty chances (`PP_BUFFS`, summed by `player_property` over passives, the mastery bonus, affixes and unique
  effects): 102 Dusk Shroud and 107 Crimson Shroud once per use of a melee or throwing attack that hits
  (`CharacterMutator.OnFirstMeleeOrThrowingHit`), 27 Critical Effluence per spell cast, 316 / 317 / 318 Runeword
  Hurricane / Avalanche / Inferno per direct use of a lightning / cold / fire skill and 315 Runeword Cataclysm per crit
  (hits × crit chance; 319 = increased Runeword duration), 680 Aspect of the Grole per use of a companion skill (a flag),
  97 Dusk Shroud per enemy hit taken, 470 per dodge (the attack, interval and dodge chance of the Defense tab);
- timed PlayerProperties (`_timed_sources`, a fixed timer: uptime = its share of the time, not 1 − e^(−load)): 80
  Apocalypse for 3 s every 3 s while the Health select is full or high; 217 Damage Immunity for `value` s after a hit, once
  per 15 s cooldown + 1 / landed enemy hits per second;
- Dusk Shroud per consumed shadow (CreateShadow property 6; shadows consumed per second as in `ShadowCalc.sustain_rows`);
- unique AbilityProperty chances (`ABILITY_PROPERTY_BUFFS`, item_procs.json): Lament of the Lost Refuge — Corrupted
  Heraldry per Volcanic Orb cast (property 7) and per hit of the skill (8, its shrapnel);
- skill parameters (`PARAM_BUFFS`, `SkillCalc` result `params`): Smoke Bomb «Moonlight Bomb» `silver_shroud_stacks` per
  use — Silver Shroud dodges your next hit, so the k-th stack of a burst lives min(10 s, k / landed enemy hits per second)
  (the Defense tab attack, PlayerProperty 534 = chance not to spend it); «Smoke Blades» `smoke_blades_stacks` per second
  while you stand in the cloud (4 s per bomb: min(1, uses × 4) of the time); Smoke Bomb Dusk Shroud on you every
  `dusk_shroud_interval` / (1 + `dusk_shroud_frequency`) s in the cloud (a RepeatedlyApplyAilmentsInRadius added in
  `SmokeBombMutator`); Dusk Shroud chance per use (Umbral Blades, Shadow Rend's shadow hit); Synchronized Strikes Crimson
  Shroud stacks per use; Void Essence chance per use (Rebuke, Volatile Reversal, Devouring Orb expiry, Vengeance) or per
  crit (Erasing Strike); Void Cleave Molten Infusion stacks per hit (none with «only on hit vs own minion»); Drain Life
  Contempt, a stack every `contempt_interval` s of channel.
- events a single-target calculation has no rate for come from player numbers of the Conditions tab (`EVENT_INPUTS`,
  per second, `Build.player_state`; shown only when the build has a source — `EnemyAilments.input_reasons` feeds
  `ConfigRelevance`): kills/s — PP 50 Void Essence, PP 60 Inspiration (kills of the selected skill when it is a void
  skill), Smoke Bomb Crimson Shroud on kill in the cloud (× the share of time in it); stuns/s — PP 8 Inspiration; arrows
  picked up/s — Dark Quiver `dusk_shroud_stacks`; drops below high health/s — PP 104 Silver Shroud stacks (spent by enemy
  hits like Moonlight Bomb's); the Moving checkbox — PP 139 Ancient Flight (always on while moving after attacking).
Not modelled: Swiftness (its stacks follow the distance moved; set them by hand), buffs given to minions only.
Stacks = min(Σ gains/s × duration, maxInstances) with the same parallel sources as the enemy ailments.
`EnemyAilments.apply(build, slot)` / `restore` put both the enemy ailments and the buffs into the build around
`SkillCalc.compute`, `DefenseCalc.compute` and the character stats panel (the selected skill).

The ailment sections explain the hits per second that roll the chances (`SkillCalc._hit_events_text`): uses/s × per use ×
hits per use × projectiles hitting the target by the slot's projectile mode (one / average / all).

## 10. Effective health — `engine/defense_calc.gd` (`class_name DefenseCalc`)

The "Defense" tab, in the spirit of Path of Building's "Maximum hit taken" / "Total EHP": one enemy attack is run through
the player side of `ProtectionClass.ApplyDamage` (research/06c §1). There is no EHP in the game client (06c §6).

Settings: `Build.defense = {attack, area_level, interval, recovery, custom_damage[7], custom_crit_chance, custom_crit_multi}`
(`default_settings()`, saved in the build code; `settings_of(build)` / `normalized()` merge the defaults and fix the types).
The enemy corruption is the Conditions value `Build.enemy.corruption`, the current ward is `Build.player_state.ward`.

### 10.1 Attacks

`groups()` — the first dropdown: the average monster, every boss, the custom hit (last); `presets()` — every attack,
`key = "<group>|…"`, `group_of(key)`. Labels repeat words shared by every attack of a boss less (`_strip_common_prefix`).
The cache is rebuilt after a language switch.
- **Average monster** (`average|all|melee|ranged|spell|dot`): `research/data/game/monster_damage.json` (local
  `tools/extract/extract_monster_damage.py`): 261 ordinary monsters with `spawnsInMonolith`, 1137 damaging components, base
  damage × `(1 + damageModifier)` × the monster's own Damage MORE × `originalDamageApproximation[100] / originalDamageApproximation[L0]`.
  Per category (melee, ranged, spell, DoT per second) the 10% trimmed mean of the total, split by the share of each damage
  type; "every damage type" holds each type at the average value of the hit attacks that deal it. Treated as authored at
  level 100. **D?** (monsters are weighted equally, spawn weights are ignored).
- **Bosses**: `research/data/game/boss_attacks.json` (local `tools/extract/extract_boss_attacks.py`): the 10 monolith
  timeline end bosses and the pinnacle bosses — Aberroth, Herald of Oblivion (Uber Aberroth), Morditas, Majasa, Vision of
  the Observer, The Observer, the Uber Aberroth Harbingers. A preset is one damage component with non-zero damage;
  abilities of actors the boss spawns (`viaActor`) are skipped. `every` — seconds between uses: `useDuration`, or
  `1 / chargesGainedPerSecond` for abilities with charges.
- **Custom hit**: the final damage, no level or corruption scaling.

Damage at area level L (the monster level), **D?** for the whole chain: base × `(1 + damageModifier)` × the boss's Damage
MORE stats (matched with `LE.tags_match` against the component tags + Hit/DoT + type) × `(damageModifier[L] + 1)·1.06` ×
`originalDamageApproximation[L] / originalDamageApproximation[L0]` (ActorScaler, 06c §7) × `1 + 0.01·f(c)` for hits,
`1 + 0.005·f(c)` for damage over time (`Enemy.corruption_more`); a repeating damage area (`timing.damageInterval`) is shown
per second.

### 10.2 Layers

**Per type** (`type_multiplier`, 06c §1 step 7): `1 − min(res, 0.75) + zonePen + pen` with `zonePen = min(0.01·L, 0.75)`,
× damage taken SP 6 (`HIT|DOT | type | health tags`), × more damage taken while moving SP 113 (only with "moving"),
× `1 − armour_mitigation(armor, L, type ≠ Physical)` (DoT: × min(SP 118, 1)), × `1 + damageTakenBuff` SP 108.
Conditional defenses of uniques that reduce to stats (DamageTaken / Armour / BlockChance … with conditions from the
Conditions tab) are already in the store.
**Avoidance** (hits only): average factor `(1 − dodge)(1 − parry)(1 − 0.35·glancing)(1 − block·blockDR)(1 + critChance·(critMulti − 1))`
at area level L; enemy crit `(attack crit + SP 112)·(1 − SP 89)` (an attack with crit chance 0 never crits), multiplier `max(1, 1 + (1 − SP 114)(cm − 1))` (06c §2.8).
**Conversions and conditional defenses** (`engine/defense_conversions.gd`, `DefenseConversions.collect(build, store, attack)`,
research/07n, `research/data/game/conditional_defenses.json`). PlayerProperty values (`pp_values`) are summed from uniques
(only effects whose model is not already a stat / overcap_taken in the store), item and idol affixes (SP 98), passives and
skill tree nodes (`PlayerPropertyStat`). Then:
- dodge → endurance threshold (PP 425) / glancing blow at 2 × dodge chance (PP 194) / armor (PP 177), in that priority;
  block → parry without a shield (PP 531) / glancing blow `min(maxBlock, block) + f1·mult` (PP 392); maximum block chance
  (PP 614); converted dodge adds to the armor before its more: `(armour + dodgeRating)·(1 + f2)`; endurance mode
  "everything" (PP 310) or "…and mana" (PP 309). Converted dodge or block no longer dodges or blocks.
- `ApplyConditionalDefenses` (the conditions not modelled as unique stats): within 4 m (PP 257/258; melee attacks count as
  near — D?), ≥ 400 current mana (262), DoT per 8% over-capped cold resistance (677), attacker Slowed / Time Rotted /
  Shocked (252, crit avoidance 321, armor per Shock stack 323) / Ignited (251, threshold per Ignite 322 and per Shock 549) /
  Ignited·Damned·Bleeding (346) / Chilled·Bleeding (711) / Cursed (347, per curse 356, armor per curse 354) / Withering (373),
  damage redirected to minions (496 passive part, 562, 670 — the minion is assumed alive), block effectiveness against DoT
  (524), the delayed share f7 = `1 − (1 − pp564)·(rare/boss ? 1 − pp498 : 1)·(Spirit Plague ? 1 − pp671 : 1)` for hits,
  extra endurance f8 (525) while hits are delayed, fire damage per 10% over-capped fire resistance (436/437) and Knight
  "Battle Hardened" (physical per 5% over-capped physical resistance, tree field). The attacker's ailments are the enemy of
  the Conditions tab; the attacker is a boss for boss presets, a normal monster for the average monster, the Conditions
  enemy for the custom hit. Trackers the planner cannot see (Hail of Arrows, Drain Life: PP 619, 650) go to "Not counted".
- **Damage taken as another type** (SP 31–37, `convert_damage`, 07n §1): SP = target type, stat tags = source type;
  the first source type in the order Phys, Lightning, Cold, Fire, Void, Necrotic, Poison with damage; share = min(Σ added
  per (SP, tags), 1), no normalisation, no chaining (each share reads the original damage); applied to the attack before
  every per-type layer, hits and DoT.
Slot values: f0 → `hit_more` / `dot_more` (per type × `type_more`), f1 → block chance (× the block chance multiplier),
f2 → armor × (1 + f2), f3/f4 → endurance threshold, f5 → crit avoidance.
**Pool** (`take_damage`, 06c §1 steps 3, 10–16, 18): the delayed share f7 (queued from the final damage `D/(1 − f7)·f7`,
after mana before ward and endurance mode 2; taken over 4 s as direct damage that only ward absorbs), mana before ward SP 94, endurance on the whole hit in the mode "everything", ward, mana before health SP 24
(1 mana = 5 damage; × (1 − e) in the mode "…and mana"), endurance below the threshold;
`e = 1 − (1 − f8)(1 − min(SP 75, 0.6))`, in modes 0/1 only with base endurance above 0 (`endurance_of`).

### 10.3 Recovery between hits — `engine/defense_recovery.gd` (`class_name DefenseRecovery`)

`collect(build, layers, avoid, interval)` → sources `{resource: health|ward, timing: rate|enemy_hit, base: flat|max|missing|current, k}`:
health regen SP 17, ward regen SP 92; the selected skill (`Build.selected_skill`, `SkillCalc.compute`: `rates` = uses/s,
hits/s, crit chance, mana cost; the "Sustain" rows tagged `sustain` — leech, health / ward on hit, ward from mana spent);
resource models of the skill tree, uniques (`result.resources`, recorded by `BuildMods._apply_model`) and character
passives (`passive_resources`). A resource model counts when it has `amount` (`flat`, `max_health`, `missing_health`,
`current_health`, `max_mana`, `current_mana` (full mana), `mana_cost`, `damage` (× DPS vs enemy); `none` = not counted,
listed in "Not counted"), optional `amount_factor`, `amount_chance`, `per_second_cap`, `costs_health` (never counted).
Own events: `use` × uses/s, `hit` × hits/s, `crit` × hits/s × crit, `second`; enemy events per enemy hit: `dodge`, `block`,
`hit_taken` (not dodged or parried). `kill` and other events are not counted (one target).
Interval between enemy hits: the "Seconds between hits" parameter, else the attack's `every`, else 1 s.
`hits_to_die` simulates average hits every `interval` seconds with recovery in 0.05 s steps (ward decay 06c §3.2, health
capped at its maximum, delayed damage ticks; the minimum ward decay depends on the ward regeneration SP 92 only); ∞ when a
full cycle leaves health, ward and mana no lower and no more delayed damage queued; after 2000 hits (100000 without
recovery) the result is an estimate `n + pool / loss of the last cycle` (pool = health + ward + 5 per mana − queued delayed damage).
`seconds_to_die` does the same for damage over time (ward, mana before health and endurance apply to it; steps are counted as
integers, after 600 s the estimate is extrapolated like above).

### 10.4 Results

`lethal_damage` — the smallest post-layer damage that kills from full health (binary search; the delayed share f7 that lands
within 4 s counts, no recovery in between); "Maximum hit taken" =
lethal / (post-layer share of the attack mix), "Maximum crit taken" = that / crit multiplier; "Hits to die" (with recovery
when it is on); "Effective health" = hits to die × raw damage per hit (∞ for an attack without damage); "Worst hit" = post-layer damage × crit multiplier ×
1.2 (variance) — the tab warns when it kills from full health. DoT attacks show damage taken per second and seconds to
die. "Maximum hit taken by damage type" divides the lethal damage by the hit multiplier of each type without attack
penetration. Not counted (`notes`): boss mechanics without damage numbers, resource models without an amount.
Check — `tests/defense_test.tscn` (06c §2.7/§2.9 vectors, endurance modes, delayed damage, recovery, scaling, presets,
the average monster, an imported build, the build code).

## 11. Caching and lean results — `engine/calc_cache.gd` (`class_name CalcCache`)

One edit in the UI recomputes every bar skill (the stats panel), the enemy ailments and buffs kept on the target
(EnemyAilments computes the whole bar once more), the Defense tab, the Conditions filter and, on an item hover, the build
with that item. Most of it is the same work on the same build state, so pure results are memoized:
- `CalcCache.build_key(build)` — `var_to_bytes` of every Build field the engine reads (class, mastery, level, quest points,
  passives, skills with trees and inputs, items, blessings, enemy, player state, defense settings) and the locale (mod
  sources are translated). It is exact (no hash collisions) and a temporary change of the build (EnemyAilments.apply,
  ItemCompare snapshots, a skill input switched for a moment) is a different key, so an edit never sees a stale value.
- Buckets (`lookup` / `put`, at most 64 entries each, a full bucket is emptied): `global_store` (key + `MinionCount._busy`;
  not cached while ConfigRelevance records, it needs the models to run), `skill_calc` (key, slot, `EnemyAilments.enabled`
  and `_busy`, `MinionCount._busy`, details; every call gets a deep copy), `item_mods` (slot, item, effect scale, locale;
  1024 entries), `unique_entries` (items, locale), `passive_entries` (class, mastery, passives, locale).
  `EnemyAilments._raw` and `MinionCount.types` keep their own caches keyed the same way.
- Cached values are shared: callers never change a returned store, StatMod or entry (StatMods are not changed after they
  are put into a store). Game data is assumed fixed; code that changes it at run time (tests) calls `CalcCache.clear()`.
  `CalcCache.enabled = false` turns the cache off (`tests/perf_bench.tscn -- --nocache`).
- `StatStore` keeps an index property → own mods (extended lazily as mods are appended); `query` and `mods_of(property)`
  walk the parent chain through it in the order of `all_mods()`, so sums are added in the same order as before.

**Lean results.** `SkillCalc.compute(build, slot, details := true)`: with `details = false` the static flag `LE.details`
is off while the skill is computed and the per-mod breakdown lines are not built (`_build_damage`); every section row gets
`breakdown = ""` and `lazy = true`, the result `lean = true`. Numbers, row texts, notes and the projectile row (with its
breakdown) are the same as with details (`engine_test` `_lean_and_cache`). A lean result is also made from a cached result
with details. Lean callers: EnemyAilments (the bar pass), ItemCompare snapshots, the stats panel, the Calculations tab while no
row is expanded (the breakdowns are computed when a row is expanded, the headline tile tooltips on hover).

`tests/perf_bench.tscn` (not part of the suite) times what the UI recomputes after an edit on every fixture build and writes
every row of the results with `--golden=<path>`, to diff two engine versions.
