# 03 — Last Epoch Game Data Sources

*Research date: 2026-10-03. Live game: **1.5.x, Season 5 "Rage of the Frostborn"** (hotfix 1.5.1.1). Local client: Unity **6000.4.8f1**, IL2CPP x64.*

## TL;DR

- **Two public sites already serve the full structured game data as plain JSON/JS.** Plain `curl` can fetch both, with no login and no captcha:
  - **lastepochtools.com (LETools)** splits it into versioned JS files: `window.LEAbilities`, `LESkillTrees`, `LECharTrees`, `itemDB`, `coreDB` and others. It also serves i18n JSON in 10 languages.
  - **Maxroll** serves one file of about 10 MB, `https://assets-ng.maxroll.gg/leplanner/game/data.json?<hash>`, with English text inline and `Access-Control-Allow-Origin: *`.
- **Both datasets are game ScriptableObjects serialized almost 1:1.** The field names match the game's C# fields, for example `addedDamageScaling`, `standardAffixEffectModifier` and `specialAffixType`. Both sites clearly run their own extractor on the client.
- **Items, affixes, uniques, implicits, blessings, idols and ailments are fully structured.** Each stat comes as `property` + `tags` + `specialTag` + `modifierType` + `min/max`, so these need no text parsing.
- **Skill-tree nodes are only semi-structured.** Each stat gives `property` + `tags` + a display string such as `"+25%"`. 43% of skill-node stats use ability-specific property IDs (5000 and up, or 10000 and up for ailment chance). Those effects live in game code, so we must write a hand-curated mapping per node (a "SkillStatMap"). We do **not** need a full PoB-style English ModParser for affixes.
- **The game's ToS forbids reverse engineering and data mining (§3 f, g).** All the big fan tools do it anyway, and EHG tolerates it. That is precedent, not a licence. LETools also claims copyright on its site content.
- **Recommendation:**
  - **Primary:** our own extractor run on the locally installed client. A MelonLoader runtime dump is the most robust option; a static Cpp2IL → AssetRipper/UnityPy pipeline is the alternative. Normalize the output to our own schema.
  - **Fallback and cross-check:** adapters for the LETools and Maxroll JSON. Their schema is nearly the same as the game's, so these adapters are cheap to write. Use them for bootstrapping, for diff validation, and for coverage when our extractor breaks after a Unity upgrade.

---

## 1. lastepochtools.com (LETools)

### 1.1 What the planner loads

Inspected with the browser's network panel at `https://www.lastepochtools.com/planner/`. Every page embeds `window['dataVersion']='version150'`.

| URL | Decoded size | Global it sets | Contents |
|---|---|---|---|
| `/data/version150/planner/js/517be1eca36fc17ea39ea512e30f4499.js` | 5.8 MB | `LEAbilities`, `LESkillTrees`, `LESkillTreesUI`, `LECharTrees`, `LECharTreesUI`, `LEWeaverTree(UI)`, `LEHUD`, `LETooltipIcons` | All abilities (1227 total, 183 player abilities), 136 skill trees, 5 class trees, Weaver tree, 148 ailments, entities/minions, invocations, quest passive and attribute points |
| `/data/version150/db/js/08266c841e3045b3cb400be73fd0f879.js` | 3.1 MB | `itemDB` | Item bases and subtypes with implicits (`itemList.equippable` / `nonEquippable`), `affixList` (616 single + 540 multi), `uniqueList.uniques` (486), `setBonusList`, triggered abilities, fractured uniques, idol altar grids, champion data, scene list |
| `/data/version150/db/js/e3e0b655a8f4f31d04f48451cb59f5cd.js` | 1.0 MB | `coreDB` | `propertyList` (stat definitions and display rules), `playerPropertyList`, `abilityPropertyList`, `idolAltarPropertyList`, `coreAttributes`, `extraStatData`, corruption config |
| `/data/version150/endgame/js/20a1543c654528a9d66a0cdc8b0ee786.js` | 0.6 MB | `monsterMods`, `timelineData`, `dungeonData`, `arenaData`, `wovenEchoList`, `prophecyData` | Monolith timelines, including the blessing IDs available per slot and difficulty |
| `/data/version150/{factions,checklist,loot-filters}/js/<hash>.js` | small | `factionList`, `checklist`, `lootFilter*` | Not needed |
| `/data/version150/i18n/full/en.json?17` | 3.1 MB | — | About 35,000 flat keys, e.g. `"Skills.Skill_fi9_2_Name": "Piercing Heat"`. Also `de`, `es`, `fr`, `ja`, `ko`, `pl`, `pt`, `ru`, `zh` |
| `/data/version150/{planner,db}/res/<hash>.webp` + `.css` | 1.9 MB / 3.9 MB | — | Sprite atlases for icons |
| `/planner/js/planner.js?<ts>` | 0.7 MB | — | Planner app code (Closure-minified) |

- **File discovery is scriptable.** `curl https://www.lastepochtools.com/planner/` returns HTML containing every `data/versionNNN/<section>/js/<md5>.js` path. A plain `curl` with a browser User-Agent got 200 on all data files. Cloudflare is present, but no challenge fired on static data. (WebFetch got a 403 on the HTML page.)
- **Older versions stay online.** These folders still exist: `version100 101 110 111 112 120 121 122 123 130 131 132 140 141 142 145 150`. The folder is bumped only for patches that change data (for example, there is no `version147`). This gives us a free history for diffing.

### 1.2 Sample structures (verbatim, trimmed)

**Ability (Fireball, `LEAbilities.abilityList.fi9`):**
```json
{"internalName":"fireball","id":"fi9","nameKey":"Abilities.Ability_Fireball_Name",
 "tags":264,"skillTreeConversionDamageTags":2,"manaCost":3,"channelCost":0,"minimumManaCost":0,
 "as":1.46667,"useDelay":0.27,"useDuration":0.75,"speedScaler":3,"speedMultiplier":1,
 "maxCharges":0,"chargesGainedPerSecond":0,
 "attributeScaling":{"2":[{"property":0,"specialTag":0,"tags":0,"addedValue":0,"increasedValue":0.04,"moreValues":[]}]},
 "levelScaling":[],"channelled":false,"transform":false,"companion":false,
 "prefab":{"components":[
   {"type":"DamageEnemyOnHit","baseDamageStats":{"damage":[0,25,0,0,0,0,0],"critChance":0.05,"critMultiplier":2,
     "critType":0,"hit":true,"addedDamageScaling":1.25,"freezeRate":0,"convertAllAddedDamage":false,"penetration":[]},
    "damageTags":256,"damageModifier":0,"canDamageSameEnemyAgain":false},
   {"type":"DestroyAfterDuration","duration":0.875},
   {"type":"ChanceToApplyAilmentsOnHit","ailments":[{"ailment":1,"chance":0.4,"rolledSeparately":false}]}]},
 "comboAbilities":[],"sharedCooldownAbilities":[]}
```
- `damage[]` is indexed by damage type: `[Physical, Fire, Cold, Lightning, Necrotic, Void, Poison]`.
- `addedDamageScaling` is the added-damage effectiveness (125%).
- `attributeScaling` keys are attribute IDs (2 = Intelligence): +4% increased damage per point.
- Cooldown, when a skill has one, sits in the ability record or the prefab components (needs verifying per skill).

**Skill-tree node (`LESkillTrees.fi9.nodes[2]`):**
```json
{"id":2,"maxPoints":4,"mastery":0,"masteryRequirement":0,
 "nodeNameKey":"Skills.Skill_fi9_2_Name","descriptionKey":"Skills.Skill_fi9_2_Description",
 "stats":[{"statNameKey":"Skills.Skill_fi9_2_0_Stat","value":"+25%","noScaling":false,"downside":false,"property":5002,"tags":0},
          {"statNameKey":"Skills.Skill_fi9_2_1_Stat","value":"+33%","noScaling":false,"downside":true,"property":66,"tags":0}],
 "requirements":[{"nodeId":0,"requirement":0}],"noScalingType":false,"noScalingPointThreshold":0,
 "relatedAbilities":[],"relatedAilments":[],"triggeredAbilities":{},"triggeredAilments":{}}
```
The i18n keys resolve to: "Piercing Heat" / "Pierce Chance" / "Mana Cost". The node layout (x/y positions) lives in `LESkillTreesUI`.

**Passive node (`LECharTrees.trees[1].characterTree`, tree `mg-1`, node 5):**
```json
{"id":5,"maxPoints":5,"masteryRequirement":10,"nodeNameKey":"Skills.Skill_mg-1_5_Name",
 "stats":[{"value":"3%","property":2,"tags":0,"noScaling":false},
          {"value":"3%","property":3,"tags":0,"noScaling":false},
          {"value":"9%","property":70,"tags":0,"noScaling":true}, ...],
 "noScalingType":true,"noScalingPointThreshold":3,"relatedAbilities":["te44","sw31a"]}
```

**Affix (`itemDB.affixList.multiAffixes`, affix 14):**
```json
{"affixId":14,"levelRequirement":15,"type":0,"standardAffixEffectModifier":0,"weighting":1,"group":4,
 "canRollOn":[21,22,20,4],"rollsOn":0,"classSpecificity":0,"specialAffixType":0,"affixMorphology":2,
 "tiers":[{"rolls":[{"min":0.2,"max":0.4},{"min":0.05,"max":0.05}]}, ... 8 tiers ...,
          {"rolls":[{"min":5.6,"max":7},{"min":0.29,"max":0.36}]}],
 "affixProperties":[{"property":67,"specialTag":0,"tags":0,"modifierType":0},
                    {"property":14,"specialTag":0,"tags":0,"modifierType":0}],
 "affixDisplayNameKey":"Item_Affixes.Item_Affix_14_DisplayName","id":"AAwRgLEA"}
```
- `type` is 0 for a prefix and 1 for a suffix.
- `specialAffixType` values, as decoded by the LEB project: 0 normal, 1 experimental, 2 personal/champion, 3 set/reforged, 4/5 idol-only dual-stat sealed suffix/prefix, 6 corrupted, 7 new in 1.5.
- Idol affixes are ordinary affixes whose `canRollOn` lists base types 25–33. They also carry `specificRerollChances`.

**Base item subtype with implicits (Hide Boots):**
```json
{"subTypeId":1,"levelRequirement":8,"displayNameKey":"Item_Names.Item_SubType_Name_3_1",
 "implicits":[{"property":10,"tags":0,"type":0,"implicitValue":15,"implicitMaxValue":15},
              {"property":9,"tags":0,"type":1,"implicitValue":0.08,"implicitMaxValue":0.1}],
 "affixEffectiveness":0,"attackRate":1,"classRequirement":0,"id":"IIwBhGYykg"}
```

**Base types** (`itemDB.itemList.equippable`, 39 of them):
- 0–23: gear
- 25–33: idols — Small 1x1, Minor Lagonian 1x1, Humble 2x1, Stout 1x2, Grand 3x1, Large 1x3, Ornate 4x1, Huge 1x4, Adorned 2x2
- **34: Blessing** — 224 subtypes. Each subtype's implicit range is the blessing roll, e.g. `{"property":104,"tags":29,"implicitValue":0.3,"implicitMaxValue":0.5}`
- 35–39: lenses
- 41: Idol Altar

The blessing IDs allowed per timeline and difficulty are in `timelineData[n].difficulties[].otherSlotBlessings/anySlotBlessings`.

**Unique (`itemDB.uniqueList.uniques`):**
```json
{"uniqueId":51,"baseTypeId":18,"subTypeIds":[0],"levelRequirement":3,"legendaryType":0,
 "mods":[{"value":-0.5,"maxValue":-0.5,"property":53,"tags":0,"type":2,"canRoll":0},
         {"value":80,"maxValue":180,"property":11,"tags":0,"type":0,"canRoll":1,"rollId":0},
         {"value":4,"maxValue":5,"property":98,"tags":118,"type":0,"canRoll":0}],
 "tooltipDescriptions":[{"descriptionKey":"Item_Names.Unique_Tooltip_0_51","altText":"Recently refers to the last 4 seconds"}],
 "effectiveLevelForLegendaryPotential":0,"canDropAsLegendary":0,"droppableLegendaryAffixCount":1,
 "convertPotentialToLegendaryAffixes":0,"isPrimordialItem":0,"isSetItem":0,"setId":0,"id":"UAw4VgRiA"}
```
`mods[].type` is the modifier type: 0 added, 1 increased, 2 more. `tooltipDescriptions` hold the free-text special effects; those need hand-coded logic.

**Ailment (`LEAbilities.ailmentList`, Ignite):**
```json
{"internalName":"Ignite","id":1,"duration":2.5,"maxInstances":0,"dealsDamage":true,
 "baseDamage":{"damage":[0,40,0,0,0,0,0],"critChance":0,"hit":false},"tags":4096,
 "effectOfIncreasedEffectiveness":1,"spreads":false,"buffs":[],"curse":false}
```
Bleed in the Maxroll data shows `damage:[53,0,...]`.

### 1.3 How builds are encoded

LETools builds are **not encoded in the URL**. They are short server-side IDs: `https://www.lastepochtools.com/planner/AL0rXWDz`.

- **Public JSON endpoint:** `GET https://www.lastepochtools.com/api/public/build_data/<id>`. It returned 200 to plain curl.
- The planner itself uses `/api/internal/planner_data/<id>`.

Response shape:
```json
{"data":{"bio":{"level":100,"characterClass":3,"chosenMastery":1},
  "equipment":{"ring1":{"id":"IIwBgTKIOwrQ","affixes":[{"id":"AAwJgbEA","tier":5},...],"sealedAffix":{"id":"AOwNgnEA","tier":5}},
               "weapon2":{"id":"UAzBMEYDZKA","affixes":[...],"corruptedAffix":{...}}, "idol_altar":{...}},
  "idols":[{"x":1,"y":1,"id":"IIwBgzATC7SQ","affixes":[...],"corruptedAffix":{...}}],
  "blessings":{"1":{"id":"IIwBgzALMwSdA"}, ...},
  "charTree":{"selected":{"1":8,"4":7,...},"version":3},
  "skillTrees":[{"treeID":"svz81","selected":{"3":3,...},"level":31,"slotNumber":0}],
  "weaverTree":{...}, "charTreeProgression":[...], "skillTreesProgression":{...},
  "dataVersion":"Version 1.5.0"},
 "created_for_build":"Version 1.5.0","data_version":"Version 1.5.0","class":3,"mastery":1}
```
- Item and affix IDs are LETools' own compact IDs (the `id` field on every item, affix and unique record).
- `uniqueMinLP` and the `tier` fields complete the data.
- **Affix roll values are not stored.** Only the tier is kept, so a build always uses fixed or maximum rolls. Keep this in mind for importing.

### 1.4 Terms

- **Site copyright:** the About page says, "All original work on this site is copyright Last Epoch Tools… may not be copied or reprinted without express written approval." The site is run by "Dammitt" and is not affiliated with EHG.
- **robots.txt:**
  - `Disallow: /planner/` (only the bare planner page is allowed) and `/db/search`.
  - The Cloudflare content signal is `ai-train=no`.
  - `/data/` is **not** disallowed.
- There is no published API licence. Only the build-data endpoint is called "public".
- **Bottom line:** fetching the data is technically trivial. Redistributing it inside our product without permission is legally grey. Ask Dammitt (Discord: discord.gg/8uEhMAkxHc, or the Contact page) if we want to rely on it.

---

## 2. Maxroll.gg Last Epoch planner

- **Planner app:** `https://assets-ng.maxroll.gg/leplanner/static/js/planner.js?ver=run-<ci-run-id>`. It is a 5.8 MB React bundle.
- **Game data:** a single file, `https://assets-ng.maxroll.gg/leplanner/game/data.json?7eb3d4fa`. Details:
  - Size is 10.09 MB. The response headers include `ETag: "7eb3d4fa3e67…"`, `Last-Modified: Fri, 02 Oct 2026` (it tracked the 1.5.1.1 hotfix within hours), `Access-Control-Allow-Origin: *` and `Cache-Control: max-age=31536000`.
  - The `?hash` is the first 8 characters of the ETag. It is listed in a manifest inside `planner.js` (`{"data.json":"7eb3d4fa","icons/1h_axes.webp":"ac048e67",...}`).
  - There is also a staging copy at `/staging/data.json`, which needs an `x-maxroll-token` header.
- **Top-level keys:** `abilities` (1054), `abilityList`, `playerAbilityList` (184), `ailments` (128), `skillTrees` (142, keyed by tree ID, with node `transform{x,y,scale}` and `ornaments`), `treeAtlas`, `classes` (5), `abilityProperties`, `affixes` (1156, flattened), `affixCategoryHeaders`, `affixDisplayCategories`, `itemTypes` (51), `itemCategories`, `properties`, `conditionalProperties`, `uniques` (486), `playerProperties` (712), `idolAltarProperties`, `setBonuses` (25), `timelines` (11), `quests`, `stats`, `lootFilterData`, and `default*Property`.
- **Differences from LETools:**
  - English strings are inline (`nodeName`, `statName`, `description`).
  - Sprite references are md5 hashes.
  - `classes[]` includes **base character stats**: `baseHealth`, `healthPerLevel`, `baseMana`, `manaPerLevel`, `manaRegen`, base attributes, `baseEndurance`, `enduranceThresholdPerLevel`, minion per-level scaling, and so on.
  - Affix tiers are flattened as `{"minRoll":58,"maxRoll":156,"extraRolls":[]}` with a single `property`/`tags`/`modifierType` per affix.
- Fireball in the Maxroll data is the same as in LETools (`"components":[{"type":"damageOnHit","baseDamageStats":{"damage":[0,25,0,0,0,0,0],"critChance":0.05,"addedDamageScaling":1.25,...}}]`). This confirms both sites come from the same game source.
- **Build storage:** server-side profiles. `GET https://planners.maxroll.gg/profiles/le/<id>`, or `profiles/load/le/<id>` for the cached copy. Builds are saved with a POST to `profiles/le`.
- **Terms:** Maxroll belongs to Ziff Davis (IGN). Its footer links the Ziff Davis Terms of Use, which I could not fetch. Assume the usual corporate ban on scraping and reuse. Use this data only for development and validation, not for redistribution, unless Maxroll gives permission.

---

## 3. Other planners, tools and open-source projects

| Project | Stars | Last push | Licence | Data held / approach |
|---|---|---|---|---|
| [Musholic/LastEpochPlanner](https://github.com/Musholic/LastEpochPlanner) (web: [lastepochplanner.com](https://lastepochplanner.com)) | 83 | 2026-04-29 (v0.12.0) | MIT (PoB fork) | Lua PoB fork. **Its own game extracts**, but the extractor is not public. `src/Data/skills.json`, `ModItem.json` (affix tiers rendered as **text**), `uniques.json`, `bases.json`, and `src/TreeData/1_2..1_4/tree_*.json` (passive and skill trees with English stat strings). It uses PoB's text ModParser, and the README says **"6,646 of 15,506 mods (43%) are recognized."** Importer uses the LETools API. |
| [uta666XYZ/LastEpochBuilding](https://github.com/uta666XYZ/LastEpochBuilding) (LEB) | 12 | 2026-07-20 (v0.14.0, LE 1.4.7) | MIT | Builds on Musholic's work. Much further along on DPS (triggers, minions, conversion, ailments). Data comes from `ModItem_1_4.json`, `property_list_1_4.json`, `set_1_4.json`, `ModIdol_1_4.json`, and `src/Data/LEToolsImport/*`, which was **scraped from LETools** through DevTools scripts (`EXTRACTION_SCRIPTS.md`; it uses `itemDB.affixList`, `/data/version142/i18n/full/en.json`). Imports from Maxroll. A good reference for how LE mechanics work. |
| [prowner/last-epoch-data](https://github.com/prowner/last-epoch-data) (ArreatSummit.gg) | 0 | 2024-03-19 | none | `datamined/skillTrees.ts` plus a **hand-converted** `manuallyProcessed/skillTreeNodes.ts` mapping `{property, modifierType, specialTags, tags, value}`, most entries marked `TODO`. Confirms that skill nodes need manual structuring. |
| [RCInet/LastEpoch_DatabaseGenerator](https://github.com/RCInet/LastEpoch_DatabaseGenerator) | 4 | 2024-02 | none | **MelonLoader mod** that dumps classes, items, affixes, blessings and skill trees to JSON at runtime (`UniverseLib.RuntimeHelper.FindObjectsOfTypeAll(typeof(SkillTree))`, `Tree.nodeList`). A template for our extractor. |
| [RCInet/LastEpoch_Mods](https://github.com/RCInet/LastEpoch_Mods) | 137 | 2026-04 | none | Large MelonLoader mod collection. Useful for learning the class names (`Ability`, `SkillTree`, `SkillTreeNode`, `UniqueList`, `AffixList`, …). |
| [chaoscode/LEParser](https://github.com/chaoscode/LEParser) | 0 | 2026-04 | Apache-2.0 | Schema-driven C# parser for raw MonoBehaviour `.dat` dumps (UniqueList and others) exported from `resources.assets`. See the companion blog post [haxerlab: LE database extraction](https://www.haxerlab.com/2025/10/23/last-epoch-database-extraction-using-reverse-engineering-part-1/), which uses UABE on `Last Epoch_Data/resources.assets`. |
| [JLC827/last-epoch-build-as-plaintext](https://github.com/JLC827/last-epoch-build-as-plaintext) | 1 | 2026-04 | Unlicense | Converts a LETools build to text. |
| [medick51o/LEBuildConverter](https://github.com/medick51o/LEBuildConverter) | 0 | 2026-06 | MIT | Converts LETools builds to Maxroll format. Contains the mapping between the two ID spaces. |
| [Helyos96/Repoch](https://github.com/Helyos96/Repoch) | 1 | 2021-06 | none | Old (0.8.2) per-ability JSON dumps. Out of date. |
| [lledinh/LastEpochItemDb](https://github.com/lledinh/LastEpochItemDb) | 5 | 2020 | none | Old Java asset parser. Out of date. |
| [lastepoch.tunklab.com](https://lastepoch.tunklab.com/) | — | live | site | Database of uniques, affixes and bestiary, plus EHP/ward/armor and crafting calculators. Datamined. No public data files were investigated. |
| ArreatSummit.gg | — | ? | site | Older planner with DPS breakdown ([forum post](https://forum.lastepoch.com/t/updated-build-planner-with-dps-calculation-arreatsummit-gg/62789)). |

**Official API:** EHG's support article "[The Game Data API Is Not Yet Available](https://support.lastepoch.com/hc/en-us/articles/1260805256609-The-Game-Data-API-Is-Not-Yet-Available)" says a REST/JSON API is planned and is used internally for lastepoch.com. As of today it is still not public. Save files are JSON (with a prefix) in `%USERPROFILE%\AppData\LocalLow\Eleventh Hour Games\Last Epoch\Saves`; see `04_le_character_import.md`.

---

## 4. Datamining the game client directly

**What I verified on the local install** (`<Last Epoch install dir>\`). I only read files; I ran no tools.

- **IL2CPP:** `GameAssembly.dll` (97 MB) and `Last Epoch_Data/il2cpp_data/Metadata/global-metadata.dat` (36 MB).
  - The header is `AF 1B B1 FA`, so it is not encrypted.
  - The **metadata version is 0x27 = 39**.
  - There is also a `metadata-cert.cer`.
- **Unity version:** `6000.4.8f1`, read from the `resources.assets` header. The build hash is in `build_hash.txt`.
- **Data containers:**
  - `resources.assets` (102 MB) contains the `UniqueList`, `AffixList` and `PropertyList` MonoBehaviours, plus unique names such as "Aurelis".
  - `globalgamemanagers.assets` has the script/type references (`SkillTree`, `CharacterTree`, `AbilityList`, `AilmentList`).
  - Skill trees, abilities and localization tables are most likely in the **Addressables**:
    - `StreamingAssets/aa/` (`catalog.bin`, `StandaloneWindows64/`)
    - `StreamingAssets/LEAssetBundles/` (**26,667** `assets_<hash>.bundle` files plus `Catalog.bin`, with hashed keys)
  - Skill-node display strings such as "Piercing Heat" are not in `resources.assets`.

**Tool options:**

| Tool | Role | Status for LE (Unity 6000.4, metadata v39) |
|---|---|---|
| **MelonLoader** + Il2CppInterop | Runtime: load the game, enumerate ScriptableObjects (`Resources.FindObjectsOfTypeAll`), serialize to JSON | The approach most fan tools use (proven by RCInet). **Risk:** [MelonLoader #1218](https://github.com/LavaGang/MelonLoader/issues/1218), opened 2026-10-03, reports that the IL2CPP support module fails on the newest LE build (Unity 6000.4.8f1). Fixes usually land within days to weeks. |
| **Cpp2IL** (2022.1 dev builds) / **Il2CppDumper** | Static: rebuild dummy DLLs or type trees from `GameAssembly.dll` + `global-metadata.dat` | Il2CppDumper's official support ends around metadata v29/31 and Unity 2022. **v39 is probably unsupported.** Cpp2IL is the better bet; check its support for v39 / Unity 6. |
| **AssetRipper** | Export assets and MonoBehaviours to YAML/JSON using recovered type trees (it runs Cpp2IL internally) | Needs IL2CPP structure recovery to deserialize MonoBehaviours. Unity 6 support is ongoing. |
| **AssetStudio / AssetStudioMod** | Browse and export; MonoBehaviours need dummy DLLs from Il2CppDumper | Raw export gives `.dat` blobs (what LEParser consumes). |
| **UnityPy** (Python) | Scriptable extraction from `.assets` and bundles | Needs a type tree, generated with `TypeTreeGenerator` from dummy DLLs. Best for a headless CI pipeline once the type tree is available. |

**Key game classes** (from mod sources and site field names): `Ability` (with prefab components such as `DamageEnemyOnHit`, `ChanceToApplyAilmentsOnHit`, `DestroyAfterDuration`), `SkillTree : Tree` (`treeID`, `nodeList` of `SkillTreeNode`), `CharacterTree`, `AbilityList`, `AilmentList`, `AffixList` (singleAffixes / multiAffixes), `UniqueList`, `ItemList`, `PropertyList`, `SetBonusList`, and `Timeline`/`MonolithTimeline` lists. Localization uses Unity Localization string tables in the addressables.

**Community scripts:** there is no public end-to-end extractor. LETools and Maxroll keep theirs private, and so does Musholic. RCInet's DatabaseGenerator is the closest open template, but it is old (2024) and covers only part of the data.

**Tooltip formulas:** the rules for display rounding and percentages are data (`coreDB.propertyList[*]`: `roundAddedToInt`, `displayAddedAsPercentage`, `displayAsPercentageOf`, `altTextOverrides`, `moreRoundingOverrides`). The **actual stat math**, though, is in C# code (`StatsHolder`, mutators) and is not data. It has to be reimplemented and checked against in-game tooltips.

### 4.1 Legal: EHG Terms of Service ([lastepoch.com/policy/tos](https://lastepoch.com/policy/tos), §3 "Prohibited Uses")

- **§3(f):** prohibits accessing the game "using any engine, software, tool… (including spiders, robots, crawlers, **data mining tools**, or similar)".
- **§3(g):** prohibits "**reverse engineer, derive source code, modify, decompile, disassemble, or create derivative works**". There is a carve-out for uses "expressly permitted… under any of our applicable guidelines… or under applicable law".
- **§3(a):** forbids non-personal commercial use unless allowed by written agreement or the **Fan Content Creation Guidelines**.
- **§3(u):** bans unauthorized programs "that collect or modify game data by reading the game memory". That is exactly what a MelonLoader dumper does; we would run it offline, never online.
- **Precedent:** LETools, Maxroll, tunklab, Musholic, LEB and many MelonLoader mods all datamine openly. EHG has never acted against data-only fan tools, and Maxroll and LETools are widely promoted. This is tolerance, not a licence.
- **EU/other law:** some jurisdictions allow decompilation for interoperability (e.g. EU Software Directive art. 6), but that does not clearly cover extracting game content.
- **Mitigations:**
  - Never ship game assets such as sprites or audio without permission.
  - Ship only facts: numbers and IDs.
  - Credit EHG and follow their Fan Content Guidelines.
  - Ideally, email EHG (community/partnerships) for written permission.

---

## 5. Are node stats machine-readable, or text only?

| Data | Structure | Do we need a text ModParser? |
|---|---|---|
| Affixes (all kinds: normal, idol, experimental, personal, sealed, corrupted, set) | `affixProperties[]{property, specialTag, tags, extraTag, modifierType, setProperty}` + `tiers[].rolls[]{min,max}` | **No.** Map `property`/`tags`/`modifierType` straight to our mod model. |
| Implicits and blessings | `{property, tags, type(=modType), implicitValue, implicitMaxValue}` | **No.** |
| Unique mods | `mods[]{property, tags, specialTag, type, value, maxValue, canRoll, rollId}` | **No**, apart from `tooltipDescriptions` (free text: about 1–3 special effects per unique), which need hand-written handlers. |
| Set bonuses | Structured property lists, plus some text | Mostly no. |
| Passive-tree nodes | `stats[]{property, tags, value:"+3%"/"3%"/"+1", noScaling}` + `noScalingType/Threshold` | **A light parser only.** `property`/`tags` are given, and the modifier type comes from the value format (`"+N"` added flat, `"+N%"` added %, `"N%"` increased, `"xN%"` more). The `noScaling` flags tell whether the value multiplies by points. Formats in the data: `N%` 583, `+N%` 337, `+N` 297, `N` 112, `null` 87 (text-only "description" stats). |
| **Skill-tree nodes** | Same shape, but **2,828 of 6,528 stats (43%) use ability-specific property IDs ≥ 5000** (for example `5000` Extra Projectiles, `5002` Pierce Chance, `5063` Base Damage → Lightning). IDs ≥ 10000 mean ailment chance with ailment ID = property − 10000 (e.g. `10001` Ignite Chance). Another **1,335 stats have `value: null`**, meaning the effect exists only as description text ("Fireball now pierces…"). | **Yes, per node.** The game applies these through per-skill C# mutator code, so this is not data. Build a curated table `treeId/nodeId → [{target, op, valuePerPoint, condition}]`, generated from the data where `property < 1000`, and hand-filled for ≥ 5000 and null values. This is like PoB's `SkillStatMap.lua` plus per-skill special cases. It is the single largest manual cost: 136 trees × ~20 nodes. |

**Lesson from Musholic:** turning structured data back into English and then parsing it with a PoB ModParser got only 43% coverage. **Keep the structured `property`/`tags`/`modifierType` triples end to end.** Use text only as a display and fallback, and also for display, a template renderer driven by `coreDB.propertyList` display rules and i18n.

Enumerations we need are the `property` IDs, the `tags` bitmask (damage type, skill type, and so on), `specialTag`, attribute IDs and base type IDs. Get them from `coreDB.propertyList` + i18n `Properties.*` keys. The enum maps at the end of the `itemDB` JS (e.g. `DodgeChance:1009`, `ExtraProjectile:1100`) and Maxroll's `properties`/`playerProperties`/`abilityProperties` help too. The game's `SP`/`AT` enums would come from a Cpp2IL dump.

---

## 6. Patch cadence and how tools keep up

- **Major seasons** have come every 4–6 months:
  - 1.0 (Feb 21, 2024)
  - 1.1 Harbingers of Ruin (Aug 2024)
  - 1.2 Tombs of the Erased (Apr 2025)
  - 1.3 Beneath Ancient Skies (2025)
  - 1.4 Shattered Omens (early 2026)
  - 1.5 Rage of the Frostborn (Sep 2026)

  Dates for 1.3–1.5 are approximate.
- **Data-changing patches** happen about every 2 months. LETools has published **17 data folders since 1.0**: `version100, 101, 110, 111, 112, 120–123, 130–132, 140–142, 145, 150`.
- **Hotfixes** come weekly after a season starts, and most are bug fixes. 1.5.1.1 changed drop levels for 3 uniques, and 1.5.1 changed Lens of Tyranny.
- **How the tools keep up:**
  - LETools and Maxroll re-run private extractors and publish within hours to a day. Maxroll's `data.json` was updated Oct 2, the same day as the hotfix. LETools bumps the `versionNNN` folder.
  - Musholic and LEB commit regenerated `*_1_N.json` per season (versioned files: `ModItem_1_2.json`, `_1_3`, `_1_4`) and keep older versions for legacy builds.
  - LEB re-scrapes LETools through DevTools scripts.
  - Pre-season, both big sites usually have planner data **before launch**, because EHG reveals the patch notes and the sites may get early access. That is something we cannot match without an EHG relationship.

---

## 7. Recommendation: data pipeline

### Primary: our own extractor, run against the local client, normalized to our schema

1. **Extractor A (runtime, preferred).** A small MelonLoader mod, based on RCInet's DatabaseGenerator approach:
   - At the main menu, enumerate `AbilityList`, `SkillTree`, `CharacterTree`, `AffixList`, `UniqueList`, `ItemList`, `AilmentList`, `PropertyList`, `SetBonusList`, timelines and Localization tables.
   - Reflect every serialized field to JSON, generically, so new fields appear automatically.
   - Run it offline, never online, to limit ToS §3(u) exposure and avoid anti-cheat issues.
2. **Extractor B (static, headless CI alternative).** Cpp2IL → dummy assemblies or type trees, then UnityPy (or AssetRipper CLI) to read `resources.assets` plus the Addressables bundles. It is harder to start (Unity 6, metadata v39) but needs no game launch.
3. **Normalizer** (Python/TS) from the raw dump to our schema:
   - `skills[]`, `skillTrees[]`, `passiveTrees[]`, `bases[]`, `affixes[]`, `uniques[]`, `sets[]`, `blessings[]`, `idols[]`, `ailments[]`, `properties[]`, `classes[]`.
   - Use stable game IDs (treeId/nodeId, affixId, uniqueId, baseTypeId/subTypeId).
   - Version files by game version, and keep N-1 versions for old builds.
4. **Curated overlay** (in git, hand-maintained): the skill-node effect map (≥ 5000 / null stats), unique special-effect handlers, and set-bonus text effects. CI flags nodes whose raw data changed since the overlay was last reviewed (diff on `treeId/nodeId/stats`).
5. **Diff report** per patch: added, removed and changed numbers. This doubles as patch notes for users.

### Fallback and validation: LETools and Maxroll adapters

- Write `letools_adapter` and `maxroll_adapter` that map their JSON into the same raw shape. The structures are about 95% the same as the game's own fields, so this is roughly 1–2 days of work.
- Use them to:
  - **bootstrap development now**, before our extractor exists;
  - **cross-validate** each extraction (three-way diff on numbers);
  - **cover outages** when a Unity upgrade breaks MelonLoader or Cpp2IL, which is happening right now with #1218.
- Discovery:
  - LETools: parse `https://www.lastepochtools.com/planner/` for `data/versionNNN/*/js/<md5>.js`. Evaluate the files in a JS sandbox (they are `window.X = {...}` literals), or regex-strip the `window.X=` prefix and parse them as JS objects (they are not strict JSON: `!0`/`!1` booleans and unquoted keys).
  - Maxroll: read the manifest hash from `planner.js`, then fetch `game/data.json?<hash>`.
- **Do not ship their data in releases** without written permission from Dammitt (LETools) or Maxroll (Ziff Davis).

### Risks

| Risk | Severity | Mitigation |
|---|---|---|
| EHG ToS §3(f)(g)(u) forbids datamining and RE; C&D possible | Medium (low likelihood given the precedent, high impact) | Ship only numbers and IDs, no assets. Seek written EHG permission. Credit EHG. Non-commercial, or follow the Fan Content Guidelines. |
| LETools/Maxroll copyright or ToS if we redistribute their files | Medium | Use them for development and validation only, or get permission. Their JSON is derived from the game, but their compilation is still theirs. |
| Unity upgrades breaking extraction (Unity 6000.4, metadata v39; MelonLoader #1218 open today) | High (recurs every season) | Keep both extractor A and B. Keep the site adapters as the third path. Pin tool versions. |
| Skill-node semantics live in code (43% custom properties, 1,335 text-only stats) | High (largest ongoing effort) | Curated overlay with review CI. Prioritise popular skills (LETools/Maxroll build stats). Use LEB/Musholic code as a reference for mechanics (MIT). |
| Hidden formulas (cast-time derivation from `useDuration`/`speedScaler`, minion per-level scaling, ward, armor curves) | Medium | Validate against in-game tooltips and the LEB regression corpus. Maxroll's `classes[]` gives base stats. |
| Site schema or URL changes (hashed filenames, minified globals; LEB notes "variable name changes on letools") | Low–Medium | Treat the adapters as best-effort. Discover files dynamically. |
| Patch cadence: big seasons every 4–6 months, data patches about every 2 months, top sites update the same day | Medium | Automate extract → normalize → diff → PR. Keep versioned data. Target a turnaround under 48 hours. |

---

## Appendix: quick reference URLs

```
# LETools (data version folder from window.dataVersion or page HTML)
https://www.lastepochtools.com/planner/                                   # HTML lists the current data JS hashes
https://www.lastepochtools.com/data/version150/planner/js/517be1eca36fc17ea39ea512e30f4499.js   # LEAbilities, LESkillTrees, LECharTrees
https://www.lastepochtools.com/data/version150/db/js/08266c841e3045b3cb400be73fd0f879.js        # itemDB
https://www.lastepochtools.com/data/version150/db/js/e3e0b655a8f4f31d04f48451cb59f5cd.js        # coreDB
https://www.lastepochtools.com/data/version150/endgame/js/20a1543c654528a9d66a0cdc8b0ee786.js   # monsterMods, timelineData, ...
https://www.lastepochtools.com/data/version150/i18n/full/en.json          # strings (de, es, fr, ja, ko, pl, pt, ru, zh)
https://www.lastepochtools.com/api/public/build_data/<buildId>            # build JSON

# Maxroll
https://assets-ng.maxroll.gg/leplanner/static/js/planner.js?ver=...       # contains {"data.json":"<hash>"} manifest
https://assets-ng.maxroll.gg/leplanner/game/data.json?<hash>              # full game data, CORS *
https://planners.maxroll.gg/profiles/le/<id>                              # build JSON

# Local client
<Last Epoch install dir>\GameAssembly.dll
<Last Epoch install dir>\Last Epoch_Data\il2cpp_data\Metadata\global-metadata.dat   (v39)
<Last Epoch install dir>\Last Epoch_Data\resources.assets      (UniqueList, AffixList, PropertyList)
<Last Epoch install dir>\Last Epoch_Data\StreamingAssets\aa\ and \LEAssetBundles\ (26,667 bundles)
```
