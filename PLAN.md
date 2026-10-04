# Last Epoch Builder — verdict and implementation plan

Date: 2026-10-03. Current game version at the time of the research: **1.5.0 (Season 5)**.
Source research:
- [research/01_pob_architecture.md](research/01_pob_architecture.md) — how PoB / PoB-PoE2 are built
- [research/02_le_formulas.md](research/02_le_formulas.md) — LE formulas with confidence labels (+ `research/02_assets/` — images of the formulas from the in-game guide and data dumps)
- [research/03_le_data_sources.md](research/03_le_data_sources.md) — where to get game data
- [research/04_le_character_import.md](research/04_le_character_import.md) — character import
- [research/05_dump_verification.md](research/05_dump_verification.md) — client dump, checking the method on armor
- `research/06a…06e_dump_*.md` — formulas from the decompiled code: stats, damage, defense, ailments, speed/minions
- `research/data/` — stat and tag enums, the DR-by-level table
- [research/dump_agent_brief.md](research/dump_agent_brief.md) — how to work with the dump

---

## 1. Verdict

**It can be done, and the formulas are now known from the game code itself.** The client was decompiled (Cpp2IL → Il2CppInspector → Ghidra, see `research/05`, `06a–06e`). The armor and dodge formulas matched the official in-game guide down to the last constant, so the method is reliable. All the gaps from `02_le_formulas.md`, except for numbers that live in the assets, have been closed by reading the code (label **D**).

| Layer | Status | Source |
|---|---|---|
| Stat model: `(Σadded)·(1+Σinc)·Π(1+more_i)`, tag-subset matching (Elemental = Fire∨Cold∨Lightning), health states as tags | ✅ D | 06a |
| Hit damage: base, added×ADE (1.0 by default; for skills with a base from code 0.05·Σbase), inc/more by damage type, attributes linearly | ✅ D | 06b |
| Skill tree nodes → **more** (the tree code creates a more stat by hand; points in a node add up, nodes multiply) | ✅ D (verified on Fireball) | 06a |
| Crit: chance → +"chance to be crit" of the target after inc/more; NoCritMulti; super crit and Deadly Strikes (+3.0 to the multiplier) | ✅ D | 06b |
| Damage spread ×U(0.8; 1.2), one roll per hit after the crit, hit only | ✅ D | 06b |
| Target resistance: `1 − min(res,0.75) + pen`, no lower bound; shred down to the cap | ✅ D | 06b/06c |
| Hidden damage reduction by monster level: a table of 101 values, boss/miniboss +0.05·(1−DR), applies to hit and DoT, training dummies have none | ✅ D | `research/data/monster_level_damage_reduction.json` |
| Player defense: the full order of 18 steps (dodge → parry → glancing → block → crit → spread → resist → armor → … → ward → mana → endurance) | ✅ D | 06c |
| Ailments: chance → stacks, damage snapshot on application, 0.5 s tick on enemies, "increased effect" of damaging ailments = **penetration**, not damage | ✅ D (group ailments — D?, check in game) | 06d |
| Speed: `use/(S·mult·1.1)`, a weapon multiplies only Melee (and Bow with a bow), dual wield = average; cooldowns; mana `cost/efficiency` | ✅ D | 06e |
| Minions: strength `(L−25)·0.8%`, the Minion tag rule | ✅ D; the general transfer of player stats to minions — ❓ | 06e |
| Monsters: health, damage, rarity, corruption | ✅ formulas D, coefficients in the assets | 06c/06e |
| Items, idols, blessings, sets: ordinary stats; **affix values are quantized** on the `PropertyRounding` grid from roll 0..255 | ✅ D | 06a |
| Class numbers (health per level, etc.), attributes, MonsterRarity, node coefficients of ~150 trees | ⚠️ live in the assets or are lost by the decompiler → AssetRipper/UnityPy + an ISIL script | — |

**Summary:** all mechanics of the shared layer are known exactly. What remains is engineering work:
1. **Extract the assets** (class, attribute and rarity numbers, AilmentList, trees) via AssetRipper/UnityPy.
2. **Skill tree mechanics.** The logic of each tree lives in the `<Skill>Mutator` code and can now be read. The node coefficients have to be pulled out with an ISIL script, because Ghidra loses float arguments.
3. **Find the transfer of player stats to minions** (xref search in Ghidra).

Testing in the game is needed only for the final cross-check, not for finding formulas.

**Import in a couple of clicks:**
- **Offline characters — yes.** A save is the prefix `EPOCH` and plain JSON. Items, idols and blessings are stored inside in binary form and need to be decoded.
- **Online characters — only through the developer's (EHG) partner API.** There is no public API; LE Tools and Maxroll apparently have partner access. Until we get it, the fallback is importing an LE Tools or Maxroll build link.

---

## 2. Architecture (following PoB's lessons, but modern)

```
le-builder/                      (monorepo, pnpm + TypeScript)
├─ packages/
│  ├─ data-schema/     Zod schemas of normalized data (Skill, SkillTreeNode, PassiveNode, Affix, BaseItem, Unique, Set, Idol, Blessing, Ailment, StatDef)
│  ├─ data-pipeline/   extractors → normalization → data/<gameVersion>/*.json
│  │   ├─ adapters/letools.ts, adapters/maxroll.ts   (for development and cross-checking, NOT for shipping without permission)
│  │   └─ extractor/   our own extraction from the client (Cpp2IL + UnityPy / MelonLoader dumper)
│  ├─ engine/          pure calculation engine, no UI and no global state, runs in a Web Worker
│  │   ├─ mods/        Mod, ModStore (parent chain), tags/conditions, queries
│  │   ├─ setup/       mod collection: class/mastery tree, items, idols, blessings, skill trees, config
│  │   ├─ calc/        phases: attributes → resources → buffs/auras → defence → offence (hit, crit, speed, DoT/ailments, minions)
│  │   ├─ trace/       Traced<number> — every number keeps the tree of its derivation (breakdown)
│  │   ├─ skills/      hand-written implementations of skill tree mechanics (one file per skill)
│  │   └─ uniques/     hand-written implementations of special effects of unique and set items
│  ├─ import/          save-file parser, item decoder, adapters for LE Tools / Maxroll links, build codes
│  └─ app/             React UI (+ PixiJS for trees), optionally Tauri for desktop
└─ data/<gameVersion>/  versioned JSON data + hand-written tables (skill-node-effects.yaml)
```

### 2.1 The mod system (taken from PoB with improvements)

```ts
type ModType = 'BASE' | 'INC' | 'MORE' | 'FLAG' | 'OVERRIDE' | 'LIST';
interface Mod {
  stat: StatId;                // a typed enum, not a string
  type: ModType;
  value: number;
  tags: Set<Tag>;              // damage types, Spell/Melee/Bow/Throwing/Minion/DoT/Hit, ailment ids — a set instead of bit masks
  conditions: Condition[];     // { kind: 'Condition', name: 'LowLife' } | { kind: 'Multiplier', var: 'ShredStacks', per: 1 } |
                               // { kind: 'PerStat', stat: 'Strength', per: 1 } | { kind: 'SkillId', id } | { kind: 'Actor', actor: 'enemy', name: 'Chilled' }
  source: SourceRef;           // { kind: 'item', slot, affixId, tier } | { kind: 'passive', nodeId, points } | { kind: 'skillNode', skillId, nodeId } | { kind: 'config', optionId } ...
}
```
- Separate stores for the player, the enemy and each minion. Each skill has its own store on top of the player's store (parent chain). Skill trees change the skill's tags (for example, turn fire into cold or a hit into DoT), so tags are defined **in the skill's context**.
- The LE rule for trees: a damage modifier in a skill tree is `MORE`, even if it is labeled "increased". The exceptions are attack speed and crit. This is done during data normalization, not in the engine.
- Conditions are checked at query time against the skill context (like `ModStore:EvalMod` in PoB).

**Clarifications from the game code (06a–06e), mandatory for the engine:**
- The stat key mirrors the game's: `SP` (134 properties) + `AT` tags (bit mask) + `specialTag` + `extraTag` (usually the skill ID). A mod matches if its tags are a **subset** of the skill's tags (AND logic). The only exception is `Elemental` (matches Fire, Cold and Lightning). LowLife/HighLife/FullLife are tag bits, not separate conditions.
- Aggregation in **float32**: `(Σadded)·(1+Σinc)·Π(1+m_i)`. AttackSpeed is additionally multiplied by weapon speed, only for Melee (and Bow with a bow). `QUOTIENT` → more `1/(1+x)−1` during normalization.
- "Per X" (attributes, etc.) scales linearly, **including more** (`1+N·m`).
- Add a `group` field to `Mod`: several tree nodes writing to the same mutator field give one shared more.
- Conditional damage stats (SP 117, 48 `ConditionalDamageProperty` conditions) are more, and they are exactly what become the enemy-state checkboxes.
- Affix values are quantized on the `PropertyRounding` grid (roll 0..255) **before** being turned into stats. Max health, mana and attributes use banker's rounding, everything else is not rounded.
- "Increased effect" of damaging ailments = + penetration of its own type (except Witchfire and Penance). For group ailments the effect is not read (D?, check in game).
- The defense order is an 18-step pipeline (06c); the DPS in the game tooltip follows the `getApproximateDPS` formula (06b), so that our "dummy" mode matches the number in the game.

### 2.2 A breakdown of every number (the main value of the product)

In PoB the breakdown texts are written by hand next to the formulas and drift away from the real math. Here:
```ts
const hit = T.mul('Hit damage (fire)',
  T.add('Base', skillBase, T.mul('Added × effectiveness', addedFlat, effectiveness)),
  T.inc('Increased', modsInc),      // sum → (1 + Σ)
  T.more('More', modsMore));        // each separately
```
Every `Traced` value stores the operation, the operands and the list of mods with their sources. The UI (the "Calcs" tab) builds an expandable tree from it: **number → formula → contributions → the specific item / node / checkbox**. Breakdowns cannot diverge from the calculation, because they are generated by it.

### 2.3 Config: checkboxes "like in PoB"

Declarative options: `{ id, label, type: 'check'|'count'|'list'|'number', actor: 'player'|'enemy', apply(value, env) }`. An option is shown only if some mod in the build refers to its condition (the same as in PoB).

**Player** (starter set): Low Life / Full Health, ward > 0 / ward value, "was hit recently", "killed recently", "crit recently", "used a potion recently", "moving / standing still", "channelling for N sec", number of active minions, buff stacks (Haste, Frenzy, Lightning Aegis…), active auras and totems, "used a movement skill recently", mana percentage.

**Enemy:** type (normal / magic / rare / boss / dummy), area level, resistances and armor (with presets), Chilled / Frozen / Shocked (stacks), Slowed, Blinded, Frailty, Stunned, Shred per type and armor (stacks, accounting for the limit against bosses), Critical Vulnerability (stacks), Marked for Death, Ignite / Bleed / Poison / Electrify / Damned / Time Rot / Doom (stacks), "near / far", "on low health", corruption level.

### 2.4 What the calculation accounts for (user requirements)

| Requirement | Implementation |
|---|---|
| Items | base type and implicits; affixes by ID and tier with the exact roll value (a min–max slider); uniques with LP and Weaver's Will; sets with bonuses by item count; experimental, personal and sealed affixes. All affix stats are global (per the guide) |
| Idols | the idol grid (sizes, class-specific, "Enchanted / Omen / Grand / Large" depending on the season), affixes by ID |
| Blessings | Monolith timeline slots (from endgame data) → list of allowed blessings → a value in the range (normal / Grand) |
| Leveled skills | 5 specialization slots, skill level (with + levels from items), the specialization tree with points per node |
| Leveled passives | the class and mastery tree with points per node, mastery restrictions; the Weaver tree, if applicable |
| Statuses on the character and the enemy | section 2.3 |

---

## 3. Data

1. **First week:** adapters for the LE Tools JSON (`/data/version150/planner/js/*.js`, `/data/version150/db/js/*.js`, i18n) and Maxroll (`assets-ng.maxroll.gg/leplanner/game/data.json`) → normalization into our schema by game ID. For internal development and cross-checking only. Distributing their files without written permission is not allowed.
2. **Main path for release:** our own extractor from the installed client. **The code is already parsed** (`tools/`, `dump/`): Cpp2IL supports metadata v39, Il2CppInspector provides addresses, types and static arrays, Ghidra decompiles the whole LE.dll in about 10 minutes. The pipeline after a patch: `Cpp2IL (cs + isil) → Il2CppInspector (metadata.json) → Ghidra import + ApplySymbols → DecompileMethods`, about 40 minutes including the import. What remains to be done:
   - **assets** (class, attribute, MonsterRarity numbers, AilmentList, trees, affixes, uniques): AssetRipper or UnityPy, the type structures are taken from the dump;
   - **tree node coefficients**: an ISIL script over `<Skill>Mutator` (Ghidra loses float arguments);
   - **static tables** (DR by level, ActorScaler, etc.): from the `fields` section of `metadata.json`.
3. **Hand-written tables in git:** `skill-node-effects.yaml` (the meaning of custom skill node stats), `unique-effects/*.ts`. On every patch, CI compares the data and highlights changed nodes and items.
4. **Versions:** `data/<gameVersion>/`, a build keeps the game version (LE is often rebalanced). Seasons come out every 4–6 months, data changes — roughly every 2 months.
5. **Legal:** the EHG user agreement (§3) formally forbids datamining. The community does it openly and EHG tolerates it. We reduce the risk: only numbers and IDs without art and sounds, credit EHG, and in parallel ask EHG for partner status (it is also needed for the online character API).

---

### 3.1 Extraction status (2026-10-03)
The data is extracted into `research/data/game/` by the `tools/extract/` scripts (rerunning after a patch takes minutes). Cross-check with Maxroll and LE Tools: **0 value mismatches** across all overlapping records.

| Entity | File | Source |
|---|---|---|
| Classes, attributes, global constants, monster rarity and mods, ActorScaler | classes, attributes, global_player_properties, monster_rarity, monster_mods, actor_scaler | 07a |
| Ailments (149), affixes (1156), bases (781), uniques (489), sets, idols, blessings | ailments, affixes, items, uniques, sets, idols, blessings | 07a |
| Abilities (1044, with base damage from prefabs), trees (150), node stats (4725) | abilities, trees, tree_node_stats | 07b |
| Skill tree node effects from code: 99.7% of nodes covered (93.5% fully automatically) | skill_node_effects | 07c |
| Transfer of stats to minions, special effects of uniques (CharacterMutator fields) | unique_effects, player_property_fields | 07d |
| Save format v6 + a reference parser | tools/extract/save_parser.py | 07e |
| Passive nodes (541) and Weaver (79), base mastery bonuses, ability damage set by code (10) | passive_node_effects, weaver_node_effects, abilities_code_damage | 07f |
| Semantics of mutator fields on cast: 218 mutators, 4818 fields, 4360 D / 458 D? | mutator_field_semantics_AL, mutator_field_semantics_MZ | 07g, 07h |
| Formulas of unique special effects: 399 effects (174 checked against code, 225 D?), ability properties 374/385, item procs | unique_effects, item_procs, ability_property_fields_c | 07i |
| Base minion stats (59), boss ward, dead nodes, RoundToInt, the active rarity path | minion_base_stats, boss_ward | 07j |

**Status after 07k–07m:** all mutator fields (4795 confirmed + 23 dead out of 4818) and all 359 unique formulas are closed; Holy Aura is worked out (07l). Only these remain open: checking the save parser on fresh 1.5 saves (deferred), ward from Faith's Reward, the sources of some Holy Aura manager bonuses.

## 4. Character import

| Path | Clicks | Coverage | When |
|---|---|---|---|
| **A. Offline save** (`%USERPROFILE%\AppData\LocalLow\Eleventh Hour Games\Last Epoch\Saves`): "Import" → pick the folder (the File System Access API remembers it) → pick a character | 2–3 the first time, then 1–2 | class, mastery, passives, skill trees, skill bar — right away (JSON); items, idols, blessings — after decoding the `savedItems` bytes | phase 1 (JSON), phase 3 (items) |
| **B. An LE Tools or Maxroll build link** → paste into a field | 1 | everything except exact rolls (LE Tools stores only tiers; the default roll is the maximum or the middle, adjustable with a slider) | phase 2; after talking to the LE Tools author (Dammitt) |
| **C. An online character by account and character name** | 1–2 | full | only after getting the EHG partner API |
| **D. Our own build code** (compressed JSON + base64url) and links | 1 | full | phase 1 |

**Forbidden and not done:** the player's session token, memory reading, packet interception. This violates the user agreement and risks a ban.

**Needed from the user:** a fresh offline save of the current version. The machine has only beta saves from February 2024, and the item byte format (format v2) has to be reverse-engineered on current data.

---

## 5. Phases

| Phase | Content | Done criterion | Estimate (1 developer) |
|---|---|---|---|
| **0. Foundation** | monorepo, Zod schema, an adapter LE Tools/Maxroll data → normalized 1.5.0 JSON, a data viewer | all entities load and validate | 1 wk |
| **0.5 Client extractor** | asset extraction (AssetRipper/UnityPy), an ISIL script for node coefficients, xref search for the transfer of stats to minions, automation of the dump pipeline | data from the client matches LE Tools/Maxroll by entity; class and attribute numbers obtained | 1–2 wk |
| **1. Engine core** | Mod/ModStore/tag-subset, `Traced`, calculation phases, attributes, base class stats, defense by the 06c pipeline, hit/crit/spread/penetration/DR by level (06b), speed/cooldowns/mana (06e), ailments (06d), config checkboxes from `ConditionalDamageProperty`, build code, import of passives and skills from a save (the JSON part) | unit tests on all test vectors from 05/06a–06e; the character sheet matches the game on 3 reference characters | 3–4 wk |
| **2. UI MVP** | class and skill trees (PixiJS), items (choosing a base and affixes, roll sliders), idols, blessings, stats panel, a Calcs tab with a breakdown tree, a Config tab, LE Tools/Maxroll link import | a full build is assembled by hand and by import | 3–4 wk |
| **3. Save item decoder** | the `savedItems` format is read from the item serialization code in the dump (not guessed), then checked on fresh saves; mapping of affix IDs and rolls (roll byte 0..255 → `PropertyRounding`) | import of an offline character in 2–3 clicks with items, idols and blessings | 1–2 wk |
| **4. Skill mechanics (the long tail)** | porting the `<Skill>Mutator` logic from the decompiled code (not guessing from node text): first 1 class fully (5 masteries ~ 25–30 skills), then the rest; special effects of uniques | for every skill, the in-game DPS tooltip matches our number on the dummy (±0.5%) | ~0.3–0.5 day per skill (the code is known) → 1.5–3 months for all trees, parallelized by agents |
| **5. In-game cross-check** | only the open D? items: group ailments and increased effect, wardGainModifier (a possible bug), leech scale, channel ticks, rounding in the UI | documented test cases in `calibration/` | 2–3 days, in parallel with 4 |
| **6. Own extractor and release** | the client extractor, data diff on patch, "what if" (node highlighting, item comparison), a Tauri build | data update after a patch < 1 day | 2–3 wk |

**MVP** (phases 0–3, one class fully): about 2–2.5 months. Full coverage of all skills: another 1.5–3 months, greatly sped up by parallel work of subagents on different skills.

> ⛔ **Before phase 2 (UI) — stop and agree with the user.**

### Parallelization (agent orchestration)
- Opus: the engine (mods, trace, calc), the save decoder, complex skills (minions, triggers, transformations).
- Sonnet: implementing tree nodes from a template (one skill per agent, in an isolated worktree), UI components, data adapters.
- Haiku: generating test fixtures, checking node texts against implemented mods, i18n.
- A test gate for each skill: a table "nodes → expected tooltip numbers" that the user captures in the game (screenshot), and an automated test.

---

## 6. Accuracy checks

1. **Unit tests** for every formula: test vectors from `research/05`, `06a–06e` (derived from the game code) and the guide numbers from `02_assets`.
2. **Reference characters:** a character sheet snapshot from the game (health, armor, resists, crit, speed) → a snapshot test. Tests are mandatory in CI (in PoB they are off by default — we do not repeat that).
3. **DPS per skill:** the in-game skill tooltip and a measurement on the dummy → a test for each skill.
4. **Cross-checking** with the LE Tools calculator and the Musholic/LastEpochPlanner fork, to find discrepancies.
5. **The UI honestly shows where the calculation is inexact:** if a node's mechanic is not implemented or a formula has level B/C, there is an icon next to the number with an explanatory tooltip.

---

## 7. Risks

| Risk | Mitigation |
|---|---|
| Skill tree nodes with logic in code (43%) | the logic is read from `<Skill>Mutator` in the dump; priority to popular skills, explicit "not implemented" marking, parallelization |
| A patch changes code/formulas | the dump pipeline is ~40 min + a decompilation diff between versions highlights changed functions |
| Distribution of decompiled code | `dump/` and `tools/` are not published (local only); only formulas and numbers go into the product |
| Legal (EHG ToS, LE Tools and Maxroll terms) | our own extractor, no art, letters to EHG and the LE Tools author in advance |
| A Unity update breaks the extractor | fallback: cross-checking and the LE Tools/Maxroll adapters |
| The item byte format in the save changes | a versioned decoder, tests on the saves of every patch |
| No API for online characters | LE Tools/Maxroll links as a fallback, an application for partner access |
| Inexact DPS against real enemies | DR by level, boss flags and the resistance formula are now known from code (D); both the "dummy" and "real enemy" modes are exact |

---

## 8. What I need from you to start

1. Confirm the stack: TypeScript + React + Web Worker, optionally Tauri. Or name another (for example, a desktop app in C#/Godot).
2. A fresh offline save of the current version (for the item decoder) and 2–3 reference characters with character sheet screenshots.
3. A decision on the legal side: whether to write to EHG and the LE Tools author (Dammitt) before the public release.
4. Which class to do first for full skill coverage.
