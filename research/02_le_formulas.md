# 02 — Last Epoch damage and defense formulas (research report)

Researched 2026-10-03. Game version is **1.5.0** (Season 5, "Rage of the Frostborn"). The version comes from `window.gameVersion="Version 1.5.0"` in LE Tools' current data bundle (`/data/version150/`).

## Confidence tags

- **A, officially confirmed.** The source is Eleventh Hour Games (EHG): the in-game Game Guide text or formula images, patch notes, or a developer forum post. The in-game guide ships inside the game client. Its full English text is mirrored in the localization file LE Tools serves:
  - Text: `https://www.lastepochtools.com/data/version150/i18n/full/en.json`, keys `GameGuide.*`.
  - Formula images: `https://www.lastepochtools.com/data/version150/guide/res/r-NN.webp`.

  Both the text and the images are copied into `research/02_assets/`. The official support site (support.lastepoch.com) hosts the same articles but returned HTTP 403 to automated fetches.
- **B, community-verified or datamined.** Values read from extracted game data, or formulas used by established tools:
  - LE Tools data bundles and planner code.
  - Tunklab's datamined calculator library.
  - Maxroll resource pages.
  - Community tests posted on forums.
- **C, speculative or unknown.** Inferred, contradictory, or not found.

Where an official guide paragraph contradicts the shipped game data or a later patch note, the conflict is flagged ⚠.

### Primary sources (keep for re-checking each patch)

| ID | Source | Notes |
|---|---|---|
| S1 | In-game Game Guide (EHG), via `https://www.lastepochtools.com/guide/section/<id>` (JS-rendered) and the localization JSON above | Official text (A) |
| S2 | Guide formula images r-29…r-36 (`/data/version150/guide/res/r-30.webp` armor, `r-31` ward, `r-32` dodge, `r-33` block, `r-34` stun, `r-35` freeze) | Official formulas (A). Transcribed below, PNG copies in `02_assets/` |
| S3 | LE Tools game-data bundle: `https://www.lastepochtools.com/data/version150/planner/js/629e1f484b0a39776110dcc951d0d7f8.js` (`LEAbilities.abilityList`, `LEAbilities.ailmentList`, `coreDB`) | Raw extracted game data (B, but very strong) |
| S4 | LE Tools planner bundle: `/data/version150/planner/js/517be1eca36fc17ea39ea512e30f4499.js` (`skillBonuses` = per-node skill-tree stats, `passiveBonuses`, `LECharTrees`) | Raw data (B) |
| S5 | LE Tools planner code: `https://www.lastepochtools.com/planner/js/planner.js` (stat aggregation, tag matching, DPS "calc tab") | Community implementation (B) |
| S6 | Tunklab library (Next.js chunk `https://lastepoch.tunklab.com/_next/static/chunks/1gel_y8w0p4dx.js`, module `673465`). Pages: https://lastepoch.tunklab.com/mobdr, /armor, /dodge, /block, /ehp | Datamined formulas (B) |
| S7 | Maxroll: https://maxroll.gg/last-epoch/resources/damage-explained, …/defenses-explained, …/ailments-explained | Community (B). Partly outdated, see notes |
| S8 | Patch notes: https://lastepoch.com/1-5/patchnotes/, https://maxroll.gg/last-epoch/news/season-5-patch-notes, …/last-epoch-season-4-patch-notes, …/minion-changes-and-quality-of-life-in-season-3 | Official (A) |

The hash filenames in the data URLs change every patch. Re-resolve them from the `<script src>` tags of `https://www.lastepochtools.com/planner/` or `/ailments/`.

---

## 1. Hit damage

### 1.1 Core pipeline — **A** (S1 `BaseDamage`, `DamageEffectiveness`, `IncreasedAddedAndMore`)

```
TotalBase  = SkillBaseDamage[type] + Σ(AddedFlat[type]) × AddedDamageEffectiveness
Hit        = TotalBase × (1 + Σ increased − Σ reduced) × Π(1 + more_i) × Π(1 − less_j)
```

- **Base damage** is "the base amount of damage [a skill] would deal without any stats … Base damage can only be modified by a skill's tree." Melee skills typically have 2 base damage total, because most of their damage comes from weapons (S1).
- **Added damage effectiveness (ADE)** multiplies only flat added damage (for example "+5 melee fire damage"), never base damage. The guide's examples are Elemental Nova at 100% and Meteor at 900%. ADE is shown by holding ALT on a skill (S1).
- **Increased/reduced** are summed into one multiplier. **More/less** each multiply separately. The official worked example: (5+2+3)=10; inc (1+0.05+0.3+0.1)=1.45; 10×1.45=14.5; then ×1.05×1.3×1.1 = 21.77, not 21.03 (S1).
- **Untyped added damage** such as "+5 Melee Damage" takes the skill's base damage type. It is 5 melee physical on a physical melee attack, or 5 melee fire on a fire melee attack (S1).
- **Data fields** (S3). Each damaging prefab component has:
  - `baseDamageStats.damage[7]`, indexed **[Physical, Fire, Cold, Lightning, Necrotic, Void, Poison]**.
  - `addedDamageScaling` (ADE as a fraction).
  - `critChance` (usually 0.05), `critMultiplier` (usually 2), `critType`.
  - `hit` (bool), `freezeRate`, `penetration[]`, `damageTags`.

  ADE is per damage component, not per skill: a skill with several components can have several ADE values. Observed ADE values range from 0 to 6+, most often 1, 2, 1.5, 3, 4, 1.25 or 2.5 (S3, tallied).
- **Adaptive spell damage** (property 41) is split across the skill's base damage types in proportion to their share of base damage: `adaptive × base_of_type / total_base`. This is LE Tools' implementation (S5) — **B**.

### 1.2 Damage-type and scaling tags — **A** (rules), **B** (bitmask)

Tag bitmask (`window.AT`, S3):

| Tag | Value | Tag | Value | Tag | Value |
|---|---|---|---|---|---|
| Physical | 1 | Lightning | 2 | Cold | 4 |
| Fire | 8 | Void | 16 | Necrotic | 32 |
| Poison | 64 | Elemental | 128 | Spell | 256 |
| Melee | 512 | Throwing | 1024 | Bow | 2048 |
| DoT | 4096 | Minion | 8192 | Totem | 16384 |
| Buff | 131072 | Channelling | 262144 | Transform | 524288 |
| LowLife | 1048576 | HighLife | 2097152 | FullLife | 4194304 |
| Hit | 8388608 | Curse | 16777216 | Ailment | 33554432 |

**Modifier applicability** (LE Tools `pvm5m`, S5) — **B**:

- A modifier applies when **all of its tags are present** on the damage source: `(mod.tags & src.tags) == mod.tags`.
- **Elemental** special case: a mod tagged Elemental also applies to a source tagged Fire, Cold or Lightning, if the mod's other tags are a subset of the source's tags.
- Untyped flat added damage is matched separately (see 1.1).
- Example: "increased melee fire damage" (Melee|Fire) does not apply to Ignite (DoT|Fire). "Increased fire damage over time" (Fire|DoT) does.
- The official phrasing of the same rule: "Even when an ailment is applied by a melee skill or a hit, that does not make it count as melee damage or hit damage" (S1 `AilmentMechanics`) — **A**.

**Specials** (property `specialTag`, S3) restrict a modifier to a particular ailment or skill. The ailment IDs are in `window.AilmentID`.

### 1.3 Conversion — **A** (S1 `DamageConversion`)

- Base damage conversion changes the skill's base damage type. It does **not** change typed flat added damage ("+5 Melee Fire Damage" stays fire). It **does** change untyped flat damage ("+5 Melee Damage").
- Conversion doesn't affect ailments (ignite and so on) or other effects applied by the skill, unless stated otherwise.
- In practice the converted skill also loses the old type tag and gains the new one. LE Tools models conversion as `tags &= ~Old; tags |= New`, with partial conversions using a converted fraction — **B** (S5).
- Developer statement (Kain, forum bug-report thread "Scaling Tags … Added Flat/Base Damage from skill trees", forum.lastepoch.com/t/57409, now 404; quoted in search snippets): flat or base damage added by skill trees should **not** change a skill's scaling tags — **A** (secondary citation).

### 1.4 Damage variance — **B/C**

Maxroll (S7) and forum posts say hits vary by ±20% (DoT does not). EHG does not document this. It doesn't change the average if it is symmetric. **C** for exact distribution.

### 1.5 Skill-tree "more" — **A** (rule), **B** (per-point stacking)

- Developer Reimerh, 2021-06-30 (https://forum.lastepoch.com/t/increases-inside-skill-trees/41334): "All damage modifiers inside skill trees are multiplicative now". A tree node that says "increased damage" "will function as a 'more' multiplier". This "has always only been with % damage modifiers. Not attack speed, crit etc."
- Data (S4 `skillBonuses[skillId].stats[nodeId]`): entries look like `{value, type, property, tags, conditions?, per?}`, where `type` 0=added, 1=increased, 2=more.
  - Example: Fireball node 6 `{value:.07,type:2,property:0}` = 7% more damage per point.
  - LE Tools multiplies the value by points allocated, giving **one** more-multiplier of value×points. Within a node, points therefore stack additively; separate nodes multiply — **B**.
- Most skill-tree behaviour is **not** in stat form. It sits in `skillBonuses[...].mods` as skill-specific flags and values (for example `conflagrateDamage:.5`, `extraChainsPerRecentCast:2`). These are hand-coded per skill in the game's C#. LE Tools re-implements each skill as a JS class.
- **A calculator therefore needs per-skill logic.** This is the biggest effort item.

---

## 2. Attributes

### 2.1 Core attribute bonuses — **A** (S1 `Attributes`), matched by data **B** (S3 `coreDB.coreAttributes`)

| Attribute | Per point |
|---|---|
| Strength | +4% increased Armor (`property 10, increasedValue .04`) |
| Dexterity | +4 Dodge Rating |
| Intelligence | +2% Ward Retention |
| Attunement | +2 Mana |
| Vitality | +6 Health, +1% Poison Resistance, +1% Necrotic Resistance |

`coreAttributes` also contains a `corruptedStats` list per attribute. Examples:
- Strength: "more" property 98 with tags 636, and −0.5% increased armor.
- Intelligence: +1% spell crit multiplier, −1% "reduced bonus damage taken from crits".

These look like a newer corruption-related mechanic, and their trigger is not documented — **C**.

### 2.2 Skill attribute scaling — **A** (concept, S1), **B** (values, S3 `attributeScaling`)

Each skill lists the attributes that scale it (ALT tooltip). The tally of `attributeScaling` entries across all abilities (S3):

| Count | Effect per point |
|---|---|
| 397 | **+4% increased damage**, generic (property 0, tags 0, `increasedValue .04`). This is "increased", so it adds to the other increased sources. |
| 46 | +4% increased **minion** damage (tags 8192) |
| 49 | Mana efficiency, +2–3% (property 69) |
| 50+ | Minion health +3…+25 flat (property 7, Minion tag) |
| 11 | +4% freeze rate multiplier (added) |
| 10 | +2 added spell void damage (property 0, tags 272), +1 added damage to some tag combinations |
| others | Healing effectiveness, attack speed, and so on |

- Because attribute scaling is generic increased damage, it **also applies to ailments the skill applies**. Officially, damaging ailments are "affected by damage modifiers from the skill tree and attribute scaling of the skill that applies it" (S1) — **A**.
- Attributes are integers: `roundAddedToInt=1` for properties 19–23 (S3). Whether the game floors or rounds "increased attributes" is unknown — **C**.

### 2.3 Class base stats — **B** (S3/S4 `LECharTrees`)

| Stat | Value |
|---|---|
| baseHealth | 100 |
| healthPerLevel | 10 |
| baseMana | 50 |
| manaPerLevel | 0.50506 |
| healthRegen | 6 |
| healthRegenPerLevel | 0.14 |
| manaRegen | 8 |
| baseStunAvoidance | 250 |
| baseEndurance | 0.20 |
| firstLevelForMinionScaling | 26 |
| moreMinionDamagePerLevel | 0.008 |
| lessMinionDamageTakenPerLevel | 0.008 |

Base attributes per class: Mage Int 2 Vit 1; Rogue Dex 3; Sentinel Str 2 Att 1; and so on.

⚠ Conflicts with the guide:
- `HealthAndRegen` says +8 health/level, while `Levels` says +10 health/level.
- The guide says +0.125 regen/level; the data says 0.14.
- Stun avoidance: guide says 250 + 5/level.

Use the data values and verify on the character sheet.

---

## 3. Critical strikes — **A** (S1 `CriticalStrikes`), **B** (data)

```
CritChance  = min(1, (BaseCrit_skill + Σ added crit chance) × (1 + Σ increased crit chance))
CritMulti   = 2.00 + Σ added crit multiplier      (default 200%)
AvgHitMult  = (1 − c) + c × CritMulti            (LE Tools calc tab, S5 — B)
```

- Base crit chance is 5% for all hits (S1). Data: 559 damage components use `critChance .05`, `critMultiplier 2`. A few use 0.06, 0.1, 0.5 or 1.0 (guaranteed crit).
- Official example: +1% added and 1% increased → (5+1)×1.01 = 6.06%.
- `critType` (S3/S5): 0 = normal; 1 = cannot crit (all ailments); 2 = has crit chance but crit multiplier is ignored.
- Item affixes for crit multiplier exist only as added (`modifierType 0`). Crit chance has both added and increased (item DB tally, S3). Whether tree or uniques add "more crit multiplier" is skill-specific — **B**.
- **DoT cannot crit** (S1).
- **Crit avoidance** (defender) rolls after the attacker's crit roll. 30% enemy crit chance against 50% avoidance gives an effective 15% (S1).
- Enemy hits have a 200% multiplier. "Less bonus damage taken from crits" is capped at 100% (S1).
- **Critical Vulnerability** (debuff, S3 ailment 85): +2% "Chance to Receive a Critical Strike" (property 112, added) and −10% crit avoidance per stack. Max 10 stacks, 4 s duration. Maxroll agrees.
  - Whether the +2% is added before or after the attacker's "increased crit chance" multiplier is **C**. Most likely it is added to final chance.
- **Blind**: blinded enemies cannot crit (S1).

---

## 4. Speed, cooldowns, mana, channelling

| Item | Formula | Conf. / Source |
|---|---|---|
| Base use rate | Data per skill: `as` (uses/sec), `useDuration`, `useDelay`, `speedMultiplier`, `speedScaler` (which stat scales it: AttackSpeed, CastSpeed, or none). LE Tools computes `baseRate = speedMultiplier × 0.75 / useDuration × 1.46667`. Example: useDuration 0.75 → 1.46667/s, matching `as`. | B (S3, S5) |
| Spells | `APS = baseRate × (1 + Σ inc cast speed) × Π more` | B (S5, S7) |
| Attacks | `APS = baseRate × weaponAttackRate × (1 + Σ inc attack speed) × Π more`. Dual wield averages weapon rates. Weapons have `attackRate` in item data (S3). | B (S7) |
| Chill on enemies | Each stack is 12% less attack, cast and move speed, multiplicative per stack, max 3. 50% less effect on bosses and players (6% per stack). | A (S1) + data `moreBuffEffectAgainstBosses -0.5` |
| Cooldown | `CD_eff = baseCD / (1 + Σ increased cooldown recovery speed)` | B (S5) |
| Evade | 4 s CD, +0.5% CDR per character level (2.7 s at level 100) | A (S1) |
| Mana cost | `cost = (base + Σadded) × (1 + Σinc) × Πmore / (1 + manaEfficiency)`, floored at 0 | B (S5) |
| Channel cost/sec | `(perSec + addedPerSec) × (1 + inc) / (1 + manaEff) × (1 + channelCost%/100)` | B (S5) |
| Negative mana | A skill can be cast whenever mana > 0, even if it costs more than the remaining mana (mana goes negative). Skills that cost ≥1 mana cannot be cast at negative mana. | A (S1) |
| Mana regen | 8 base, not scaled by level | A (S1) |
| Channelled DPS | LE Tools: `APS = 1 / channelInterval × (1 + speed) × dpsMod` | B (S5) |

---

## 5. Damage over time and ailments

### 5.1 General rules — **A** (S1 `AilmentMechanics`, `AilmentDurationandEffectiveness`, `HitvsDamageoverTime`)

- **Ailment chance above 100%** applies floor(chance) stacks, plus one more with probability equal to the fractional part. Example: 235% gives 2 stacks plus a 35% chance of a third.
- **Base damage** of damaging ailments is fixed and cannot be raised with added damage. It *is* scaled by the applying skill's tree modifiers and attribute scaling. Maxroll: "There is currently no way of increasing Base Damage for Ailments."
- **Applicable modifiers.** The ailment's own tags are DoT plus its damage type (curses also have Curse and Spell). So these apply:
  - generic increased damage;
  - increased [type] damage;
  - increased elemental (for fire, cold or lightning);
  - increased damage over time;
  - increased [type] DoT;
  - skill-tree more;
  - generic or DoT more.

  These do not apply: spell damage, melee damage, throwing damage, or hit-only modifiers.
- **Duration.** Increased duration lengthens each stack. It raises total damage per stack but not DPS per stack. Example: a 120-damage bleed over 3 s becomes 180 over 4.5 s with +50% duration.
- **Max stacks.** At the cap, a new stack replaces the oldest.
- **Ailment effectiveness** ("increased X effect") scales the stat modifiers an ailment grants. Example: +50% armor shred effect gives 150 armor per stack.
  - Data field `effectOfIncreasedEffectiveness` is 1 for damaging ailments, and LE Tools multiplies tick damage by `(1 + increased effect)`. So effect probably also scales DoT damage — **B/C**.
- **Season 5 change.** "When an ailment's duration resets, it also resets its remaining total damage to its original value when it was applied" — **A** (S8).
- **Season 5 change.** Ailments cannot apply other ailments — B (S7).
- **Penetration.** Ailments use the penetration of their damage type (`additionalPenetrationDamageType`, S3) — B.
- **No crit, no on-hit effects** (S1). Endurance and resistances mitigate DoT. Armor, dodge, block, glancing blow and parry do not (except via "armor mitigation applies to DoT", property 118).

### 5.2 Ailment DPS model (LE Tools calc tab, S5) — **B**

```
perStackDPS        = BaseDamage / BaseDuration × (1 + Σinc) × Π(1+more) × (1 + incEffect) × PenMult
stacksPerSecond    = chanceToApply × APS            (multi-stack rule above)
steadyStateStacks  = min(stacksPerSecond × BaseDuration × (1 + incDuration), maxStacks or ∞)
AilmentDPS         = perStackDPS × steadyStateStacks
```

### 5.3 Ailment table (game data 1.5.0, S3 `ailmentList`; text from S1 where it exists)

`max=0` means unlimited. "Boss/Player" is the `moreBuffEffectAgainstBosses/Players` multiplier on the **debuff** part.

| Ailment | Base dmg (type) / duration | Max stacks | Debuff per stack | vs Boss/Player | Conf. |
|---|---|---|---|---|---|
| Ignite | 40 fire / 2.5 s | ∞ | — | — | A+B |
| Bleed | 53 phys / 3 s | ∞ | — | — | A+B |
| Poison | 28 poison / 3 s | ∞ | −5% poison res (first 30 stacks) | 60% less → −2% (cap 60%) | A+B |
| Electrify | 44 lightning / 2.5 s | ∞ | — | — | A+B |
| Frostbite | 50 cold / 3 s | ∞ | +20% chance to be frozen, first 15 stacks (≤ +300%) | none | A+B |
| Damned | 35 necrotic / 2.5 s | ∞ | 20% reduced health regen | — | A+B |
| Time Rot | 60 void / 3 s | 12 | +5% increased stun duration received | — | A+B |
| Doom | 400 void / 4 s | 4 | +4% increased **melee** damage taken | — | B |
| Spreading Flames | 200 fire / 4 s | 1 | — | — | B |
| Abyssal Decay | 100 void / 5 s | 1 | — | — | B |
| Hemorrhage | 300 phys / 3 s | ∞ | ("based on target's current health", per description) | — | B/C |
| Plague | 150 poison / 4 s | 1 (spreads within 6 m every 0.6 s) | — | — | A+B |
| Serpent Venom | 400 poison / 3 s | 1 | −100% crit chance (prevents crits) | — | B |
| Witchfire | 600 fire + 600 necrotic / 12 s | 1 | — | — | B |
| Shock | — / 4 s | 10 | −5% lightning res, +20% increased chance to be stunned | 60% less (−2%, +8%) | A+B |
| Chill | — / 4 s | 3 | 12% less attack, cast and move speed | 50% less | A+B |
| Slow | — / 4 s | 3 | 20% less move speed | 50% less | A+B |
| Frailty | — / 4 s | 3 | 6% less damage dealt | none in data | A+B |
| Armor Shred | — / 4 s | ∞ | −100 armor | none | A+B |
| [Type] Resistance Shred (7 types) | — / 4 s | 10 | −5% res | 60% less → −2% | A+B |
| Critical Vulnerability | — / 4 s | 10 | +2% chance to receive crit, −10% crit avoidance | none | B |
| Marked for Death (curse) | — / 8 s | 1 | −25% all res | none | A+B |
| Decrepify (curse) | 200 phys / 10 s | 1 | 15% more DoT taken | — | A+B |
| Spirit Plague (curse) | 90 necrotic / 3 s | 1 | — | — | A+B |
| Torment (curse) | 120 necrotic / 3 s | 1 | 18% less move speed | — | A+B |
| Acid Skin (curse) | 80 poison / 5 s (guide says 50) ⚠ | 1 | +20% chance to receive crit (guide says +25%) ⚠ | — | B |
| Anguish (curse) | 40 necrotic on kill / 10 s | 1 | 15% less DoT dealt | — | A+B |
| Bone Curse | 4 phys per hit / 8 s (×3 if you made the hit) | 1 | — | — | A+B |
| Penance | 20 fire per hit / 15 s, +5% more per 1% reflect | 1 | — | — | A+B |
| Withering | — / 3 s | 10 | +10% increased curse damage taken | 60% less | A+B |
| Exposed Flesh | 80 poison / 8 s | 1 | −15% cold res, −15 armor per inflicter Dex, +30% chance to be frozen | — | A |
| Efficacious Toxin | — / 4 s | 1 | +12% increased DoT taken | — | B |
| Blind | — / 4 s | 1 | cannot crit | — | A |
| Laceration | 1 phys (melee-scaled) / 3 s | 1 | — | — | B |

Maxroll's ailment page is **outdated** for Frostbite (36), Poison (20) and Time Rot (55). Use the data values.

### 5.4 Stun and freeze — **A** (S2 r-34, r-35; S1 `Stun`, `Freeze`)

```
StunChance  = [2 × Damage × (1 + inc stun chance)] / (MaxHealth + CurrentWard)  −  (500 + StunAvoidance) / 5000
   Player hits: melee damage additionally ×3, other damage ×2 (guide paragraph).
   Bosses: MaxHealth ×1.5.  Shock: chance × (1 + 0.20 per stack; 0.08 vs bosses/players).
   Players' stun avoidance = 250 + 5 × level.  Base stun duration 0.4 s.

FreezeChance = (FreezeRate × (1 + FreezeRatePerChill × ChillStacks) × FreezeRateMultiplier) / (MaxHealth + CurrentWard)
               × (1 + 0.20 × min(FrostbiteStacks,15))   ;  bosses MaxHealth ×1.5 ; base freeze 1.2 s
```

The guide's own examples check out:
- (40 × 6) / 10000 = 2.4%.
- With 3 chill stacks at 50% per stack: 40 × 2.5 × 6 / 10000 = 6%.
- Adding 15 frostbite stacks: ×4 = 24%.
- Against a boss: ÷1.5 = 16%.

⚠ Tunklab's older `freezeChance` uses `min(o,30)` frostbite stacks. The current guide says 15.

---

## 6. Enemy debuffs, penetration and enemy stats

### 6.1 Resistances and penetration — **A** (S1 `Resistances`, `Penetrations`, `ResistanceShred`, `Terminology`)

- Resistance caps at 75% (players). Negative resistance raises damage taken 1:1.
- **Shred, Shock, Marked for Death and Poison** reduce *uncapped* resistance, before the cap. **Penetration** subtracts *after* the cap.
- Example: 30% lightning penetration against 20% resistance gives −10%.
- Most enemies have **0% resistance and 0 armor** by default. Mods, monolith modifiers and champions add resistance.

Enemy effective resistance:

```
EnemyRes_eff = min(75%, BaseRes − Σshred − shock − MfD − poisonShred) − Penetration
DamageMult_res = 1 − EnemyRes_eff          (−50% res → ×1.5)
```

- Shred is −5% per stack against normal enemies and −2% against bosses (and players), max 10 stacks, 4 s.
- Penetration has no boss penalty in any source — **B**.
- No lower floor for negative enemy resistance is documented — **C**.
- **Enemies penetrate players.** Enemies get 1% penetration per area level, capped at 75% at area level 75+. Overcapping resistance doesn't help against it (S1) — **A**.

### 6.2 Armor shred / negative armor — **A** (base), **B** (formula on enemies)

- Armor Shred is −100 armor per stack (×(1 + increased shred effect)), 4 s, unlimited stacks (S1).
- Developer Tunk (forum, 2020-11-02, https://forum.lastepoch.com/t/negative-armor-formula/26045): you cannot plug negative armor into the mitigation formula. "Use positive armor value and reverse it, so shred graph is identical to mitigation graph."
- Tunklab code (S6) implements this as `armorMitigation(a, x<0) = −f(a, −x)`, where f is the armor formula in 7.2.
- Result: a damage *increase* of f(a, |x|). It is capped at 85% for physical hits and 0.7× that (≈59.5%) for non-physical hits. Area level is used as `a`.
- Armor shred affects **hits only**.

### 6.3 Other enemy debuffs

See the 5.3 table: Shock, Chill, Slow, Frailty, Critical Vulnerability, Doom, Withering, Efficacious Toxin, Decrepify, Marked for Death.
- "Damage taken" modifiers (property 6) exist as **increased** (type 1, additive with each other) and **more** (type 2, multiplicative), per the item and ailment data (S3).
- Maxroll: "Increased Damage Taken" sources add together and form a separate multiplier, independent of penetration and shred — **B**.

### 6.4 Hidden enemy damage reduction by level — **B** (datamined, S6), not in official docs

Every monster has an unpenetrable % damage reduction that depends on its level. Tunklab table `damageReduction[level]` (index 0–100):

| Level | 1–6 | 10 | 20 | 26 | 30 | 40 | 50 | 56 | 60 | 70 | 75 | 80 | 90 | 100 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DR | 0 | 6% | 21% | 30% | 34% | 44% | 54% | 60% | 63.2% | 71.2% | 75% | 78% | 83% | **87%** |

The shape:
- +1.5% per level from level 7 to 26;
- +1% per level from 27 to 56;
- +0.8% per level to about 74;
- tapering to 0.4% per level near 100.

The full array is in S6, module 673465, variable `_`.

- `getDamageReductionForLevel(level, flagA, flagB)` returns `DR + 0.05 × (1 − DR)` if either flag is set. Probably boss or rare/champion — **C** for the meaning.
- Forum users independently report about 87–90% at level 100. Training dummies have **no** DR, so dummy damage is about 7.7× real damage at level 100. See https://forum.lastepoch.com/t/hidden-damage-reduction-at-higher-levels/66560 and Maxroll S7.
- Assumed to apply to both hits and DoT — **C**.

### 6.5 Monster health and damage scaling — **B/C** (S6)

Tunklab functions, likely datamined:

```
addedDamageScaling(L) = 0.0075·max(0, L'−40) + sqrt((3L'+10)·0.035) − 0.6
    with L' = L−1, and L' = (L'−100)·5 + 100 above 100.
addedHealthScaling(L) uses the same shape with 0.006.

getHealth: base(L) = 0.5L² + 5L + 60, × (1 − DR(L)), times a per-level table and rarity factors
    (rare 2.15, boss 2.6 + …).

corruptionModScaling(c) = 0.6·c            for c ≤ 100
                        = 0.002·c^1.52 + 1.055·c − 47.69   above
```

The last function is probably the % increased monster health and damage from corruption (the guide confirms corruption raises monster health and damage) — **C**.

Not needed for player DPS. Needed only for "time-to-kill" or EHP-versus-content features.

---

## 7. Defensive formulas

### 7.1 Order of player mitigation (from guide statements plus Tunklab EHP model) — **A** (each layer), **B** (combined)

All layers multiply together. Tunklab `getAverageEhp` (S6):

```
DamageTaken_hit = Raw × (1 − ArmorDR) × (1 − ResEff) × Π(1 + damageTakenMods)
                  × (1 − BlockDR × BlockChance) × (1 − DodgeChance) × (1 − 0.35 × GlancingChance)
                  × [ (1 − Endurance) for the part below the Endurance threshold ]
DoT             = Raw × (1 − ResEff) × Π(damageTaken) × [Endurance]       (no armor/dodge/block/glancing)
ResEff          = min(Res, 75%) − min(AreaLevel, 75)%                      (enemy penetration)
```

Parry (cap 75%) negates a hit completely. It still counts as being hit.

### 7.2 Armor — **A** (S2 r-30, transcribed)

```
ArmorDR_phys(x, a) = [1.2x / (80 + 0.05(a+5)² + 1.2x)] × 0.30  +  [0.0015x² / (180(a+5) + 0.0015x²)] × 0.55
ArmorDR_nonphys     = 0.7 × ArmorDR_phys          ("Armor is 70% as effective against non-physical damage")
x = armor, a = AREA level; max 85% (phys) / 59.5% (non-phys); hits only.
```

Tunklab's code is identical (its key "082"; versions "080" and "081" are older formulas), and LE Tools' `pvm7m` is identical too. Sample values:

| Armor | a=20 | a=50 | a=75 | a=100 |
|---|---|---|---|---|
| 1000 | 41.2% | 32.4% | 27.7% | 23.7% |
| 3000 | 70.4% | 59.9% | 53.6% | 48.4% |
| 6000 | 80.3% | 75.5% | 71.8% | 68.3% |

### 7.3 Dodge — **A** (S2 r-32)

```
DodgeChance(x, a) = [x / (80 + 0.05(a+5)² + x)] × 0.25  +  [0.001x² / (32(a+5) + 0.001x²)] × 0.60     (cap 85%)
```

LE Tools additionally multiplies by `(1 + "dodge chance" modifiers)` — B.

⚠ The guide's text rule of thumb ("dodge rating = 10× area level ≈ 50%") does **not** match the shipped formula. 10× area level gives 19% at a=20, 25% at a=50 and 29% at a=100; 20× gives 30% / 42% / 52%. The Steam thread "Game Guide provides a wrong conclusion / shorthand for the Dodge formula" (https://steamcommunity.com/app/899770/discussions/0/4338725867372381093/) reports the same. **Trust the formula, and verify against the character-sheet dodge %.**

### 7.4 Block — **A** (S2 r-33)

```
BlockDR(x, a) = [3x / (40 + 0.03(a+5)² + 3x)] × 0.25 + [(1.2x + 0.0006x²) / (60(a+5) + 1.2x + 0.0006x²)] × 0.60   (cap 85%)
```

- x is block effectiveness. Block chance is additive and rolled per hit.
- It works against spells too, but not DoT. "Less damage taken from block" multiplies with it (Maxroll).

### 7.5 Endurance — **A** (S1)

- Base 20% endurance, cap 60%. The endurance threshold is 20% of max health (base) and has no cap.
- It applies only to the portion of a hit below the threshold. It applies to health, not to ward. It covers hits and DoT.

### 7.6 Ward — **A** (S2 r-31)

```
WardLostPerSecond = [0.00005 × (W − T)² + 0.2 × (W − T)] / (1 + 0.5 × WardRetention)
W = current ward, T = ward decay threshold (no decay below T), WardRetention as a fraction (100% = 1)
```

- Tunklab `wardDecay` is identical. The old formula (pre-1.x) was 0.4·W / (1 + 0.5R) — superseded.
- Steady-state ward for a ward/sec generation G: solve `G = decay(W)` (quadratic).
- Intelligence gives 2% retention per point.

### 7.7 Glancing blow, parry, crit avoidance, damage taken from mana — **A** (S1)

- **Glancing blow:** 35% less damage from a hit. Chance above 100% does nothing.
- **Parry:** negates all damage from a hit, cap 75%, still counts as hit.
- **Crit avoidance:** see §3.
- **Damage taken from mana before health:** the share p (cap 100%) goes to mana at **1 mana per 5 damage**. It is applied after all other reductions, doesn't protect ward, and doesn't work at 0 or negative mana.

### 7.8 Leech, regeneration — **A** (S1), **B**

- **Leech** = final damage dealt (after the enemy's mitigation, capped at the enemy's remaining health) × Σ applicable leech%. It is paid out evenly over 3 s per instance, with no cap. "Increased leech rate" exists (property 102) — B.
- **Health regen:** `(6 + 0.14·level + Σadded) × (1 + Σinc)`. Base value from Maxroll; per-level value from data. ⚠ The guide says 0.125/level.
- **Mana regen** 8 base.

---

## 8. Minions — **A** (rules), **B** (data)

- Player modifiers **do not** apply to minions unless they carry the minion tag ("increased minion physical damage") or say "for you and your minions" (S1). Minion skill trees give minion stats.
- Attribute scaling on minion skills gives "+4% increased minion damage" or "+N minion health" per point (S3).
- **Minion power:** from character level 26, **+0.8% more damage and 0.8% less damage taken per level**, reaching 60%/60% at level 100. Season 3 patch note: "you now gain 0.8% minion power per character level (from 0.6%)" — **A** (S8). Data agrees (`moreMinionDamagePerLevel .008`).
  - ⚠ The in-game guide text still says 0.6%/45% in `Levels` and 0.6% damage/0.8% DR in `Minions`. Treat it as stale.
- Minions take 60% less damage from "dangerous enemy abilities" (Season 3) — A.
- Hidden per-minion modifiers exist. Season 4 "Removed the hidden 14% less damage modifier that was on Skeletal Mages, Pyromancers, and Cryomancers" (S8) — **A**. Each minion's base damage, attack rate, crit and ADE come from its own ability entry in `LEAbilities` (S3).
- Companions and totems are minions; all minion stats apply to them (S1).
- Maxroll lists exceptions that scale from the player: Manifest Armor (scales from equipped items), Ballista (shared enhancements), Julra's Obsession — B.

---

## 9. Added damage effectiveness and how skill trees modify it

- ADE is per component (`addedDamageScaling`, S3). Tooltip: hold ALT (S1). It never multiplies base damage (S1) — **A**.
- Skill-tree nodes can change it through custom `mods` keys (S4), and can add base damage, added damage with "per" scaling (example: `per:[{stat:0,value:5,tags:512,perPoint:true}]`), conversions, and so on. Each one needs per-skill implementation — **B**.
- ADE does **not** apply to ailment base damage, because ailments have `addedDamageScaling 0` (S3) — **B**.

---

## 10. Order of operations and rounding

Generic stat formula (official for damage; LE Tools uses it for every stat):

```
Stat = (Base + Σadded) × (1 + Σincreased − Σreduced) × Π(1 + more_i)
```

Full hit chain against an enemy:

```
DamagePerHit = Hit(§1) × AvgCritMult(§3)
             × (1 − EnemyRes_eff)              (§6.1, per damage type)
             × (1 + NegArmorIncrease)           (§6.2, hits only)
             × Π(1 + enemy damage-taken more) × (1 + Σ enemy increased damage taken)
             × (1 − LevelDR(level))             (§6.4, hidden)
DPS          = Σ_types DamagePerHit × APS × repeats/projectiles/hits-per-use
```

- **Rounding.** `coreDB.propertyList` flags properties with `roundAddedToInt` and `roundingForMore` (for example Damage `roundAddedToInt=1`; DamageTaken `roundingForMore=3`). These look like display or format rules.
- Whether the engine rounds intermediate damage values (for example integer flat added damage after ADE) is **unknown — C**. LE Tools rounds only for display.
- "Increased damage per X" (for example per attribute, or per stack via the `per[]` field in S4) enters the **increased** pool unless it says "more".
  - Data: `per:[{stat, value, perPoint, uncapped, overcapped}]`, so per-point-of-*uncapped* or *overcapped* stat variants exist.
  - Season 5 added uncapped-block-chance scaling — A (S8).
- Mitigation layers (§7.1) are all multiplicative. Endurance uses a split-hit rule (§7.5).

---

## 11. Blessings, idols, sets, legendary potential, Weaver's Will, experimental and sealed affixes — **A**

The guide states "All stats granted by affixes are global". An increased physical damage affix on a ring counts the same as one on a weapon implicit or a passive (S1 `Affixes`). Each item type is just a stat source:

- **Blessings:** permanent stat increases.
- **Idols:** 1 prefix + 1 suffix.
- **Sets:** extra bonuses when 2–4 pieces are worn. Reforged set items count.
- **Legendary items:** unique + 1–4 exalted affixes.
- **Weaver's Will:** a unique gains affix tiers up to 4×T7.
- **Experimental affixes:** boots, belts and gloves only.
- **Sealed affixes:** like normal affixes.
- **Primordial items:** T8 affixes, one at a time.
- **Corrupted items, champion affixes:** also ordinary stat sources.

There are no special formulas. The catch is the **content** of many uniques, set bonuses and experimental affixes. These are bespoke mechanics ("chance to cast X", "X per Y", conversions, triggers) that need individual implementation. In the item data they appear as `mods` with `property/tags/specialTag` plus `tooltipDescriptions` (S3). Item affix tier and roll ranges are fully present in the LE Tools item DB (`itemDB.affixList`, S3).

---

## 12. Hidden mechanics and gotchas

1. **Monster level DR (up to 87%)** is invisible in game and missing from tooltips and dummies (§6.4). Any "DPS vs enemy" figure must apply it or be clearly labelled "vs dummy".
2. **Tooltip damage/DPS is untrustworthy for real content.** It ignores level DR, enemy resistances and shred, conditionals (low life, ailment present and so on), and uptime. A developer stream is quoted as "We have no intention of giving you a perfect DPS calculation" (https://forum.lastepoch.com/t/skill-tooltip-dps-is-5-times-higher-than-damage-enemies-take/60017; https://forum.lastepoch.com/t/how-accurate-are-the-tooltips/74120) — B. It is still useful as a **calibration target** for the "vs dummy" number.
3. **Hidden per-skill and per-minion multipliers** have existed (the Season 4 removal of 14% less damage on skeletal mages, pyromancers and cryomancers). Expect others. Calibrate per skill against in-game tooltips and dummies.
4. **Skill-tree "increased" behaves as "more"** (developer statement, §1.5). Attack speed and crit in trees do **not** follow that rule.
5. **Boss and player penalties differ by debuff** (§5.3):
   - Shred, Shock, Poison shred and Withering: 60% less.
   - Chill and Slow: 50% less.
   - Frailty, Armor Shred, Critical Vulnerability and Marked for Death: no penalty in data.
   - Boss max health is ×1.5 for stun and freeze.
6. **Ailments ignore conversion and hit tags.** Melee, spell or throwing increases never scale Ignite or Bleed (§5.1).
7. **Ailment base values change between patches.** Maxroll and other guides lag (Frostbite 36→50, Poison 20→28, Time Rot 55→60). Read values from data every patch.
8. **Guide text versus data conflicts:**
   - minion power 0.6 vs 0.8;
   - health per level 8 vs 10;
   - regen per level 0.125 vs 0.14;
   - dodge rule of thumb;
   - Acid Skin 50/25% vs 80/20%.

   Data and patch notes win, but verify in game.
9. **Season 5 ailment refresh:** a duration reset also resets remaining damage (S8).
10. **Enemy penetration against players** (1% per area level, max 75) makes "75% capped" resistance effectively 0% at level 75+ in EHP calculations.

---

## Gaps (no exact public formula found)

1. **Damage variance distribution** for hits (±20% claimed, uniform?) — not official.
2. **Internal rounding** of damage, attributes and stats (floor vs round, and at which steps).
3. **Meaning of the two flags** in the monster level-DR function (`+0.05·(1−DR)`), and whether level DR applies to DoT. The DR table itself is datamined, not official.
4. **Lower bound on negative enemy resistance**, and whether enemy resistance is capped at 75% like players'.
5. **Critical Vulnerability / "chance to receive crit"** application order relative to the attacker's increased crit chance.
6. **Whether "increased ailment effect" scales DoT damage** (LE Tools assumes yes; officially it only says "all stat modifiers").
7. **Exact weapon attack rate × skill speed interaction** for every skill. The `speedScaler` and `useDuration` model comes from LE Tools, not EHG. Same for dual-wield averaging and channelled tick intervals.
8. **Mana efficiency and channel cost** formulas (LE Tools implementation only).
9. **Per-skill custom mechanics:** `skillBonuses[...].mods` keys (thousands across all trees) have no generic formula. Each needs code that mirrors the game's C#. Same for unique/set/experimental special effects.
10. **Monster base damage, health and crit chance**, and corruption scaling semantics (only Tunklab code, partly undocumented).
11. **`corruptedStats` on attributes** (newer mechanic) — trigger and semantics undocumented.
12. **Enemy crit chance** against players (only the 200% multiplier is documented).
13. Whether **hits from minions or totems** use the player's area-level formulas identically (assumed).

## Verdict on feasibility

**An exact calculator is feasible for the generic layer.** The official in-game guide gives exact formulas for:
- added/increased/more stacking, ADE, conversion and crit;
- armor, dodge, block, ward decay, endurance, glancing blow, parry, resistances and penetration;
- stun and freeze;
- ailment rules.

The shipped game data (via LE Tools bundles) gives every skill's base damage, ADE, crit, speed fields and attribute scaling. It gives every ailment's base damage, duration, stacks, debuffs and boss penalties, and every passive or skill-tree node's per-point stat values. These cover defense, character-sheet stats and "DPS vs training dummy" to a high degree of precision.

**Parts that need in-game testing or calibration:**

1. **Per-skill tree mechanics (`mods`) and unique/set special effects.** Code is needed for every skill. Calibrate by comparing against the in-game skill tooltip (ALT) and dummy DPS for each implemented skill. This is the largest workload, and it is how LE Tools' planner handles it.
2. **Hidden multipliers** on specific skills and minions — detect by tooltip/dummy mismatch.
3. **Real-enemy DPS:** the level-DR table, boss flags and negative-resistance floor are only datamined. Validate with combat-log or dummy tests at several area levels.
4. **Speed model** (weapon rate × skill rate, channel intervals) and **rounding**. Validate against the character sheet and skill tooltips.
5. **Guide-versus-data conflicts** (dodge rule of thumb, health and regen per level). Check against the character sheet; it is cheap to verify.

**Data pipeline recommendation.** Ingest these per patch from LE Tools' `/data/versionNNN/` bundles:
- `LEAbilities` (abilities plus ailments);
- `coreDB` (property list, attributes);
- `skillBonuses` / `passiveBonuses` (tree stats);
- `itemDB` (items and affixes);
- `en.json` (localization, including the GameGuide text).

Re-check the guide formula images (r-29…r-36) for changes each season.
