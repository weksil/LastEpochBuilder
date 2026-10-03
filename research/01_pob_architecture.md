# Path of Building: Architecture Study for a Last Epoch Build Planner

Source: shallow clones of
- `PathOfBuildingCommunity/PathOfBuilding` (PoE1), commit `16de4b8` (2026-09-08)
- `PathOfBuildingCommunity/PathOfBuilding-PoE2` (PoE2), commit `bb52d6b` (2026-10-01)

Everything below comes from reading the source. Paths are relative to the repo root (`src/...`). Line counts are for the PoE1 repo unless marked otherwise.

---

## 0. TL;DR

PoB is a **Lua 5.1 / LuaJIT application** running inside a small custom C++ host (**SimpleGraphic**) that provides drawing, input, file and network calls. The program has three parts:

1. **Data layer**: game data exported from the PoE client (GGPK `.dat` tables plus stat-description files) into large generated **Lua table files** under `src/Data` and `src/TreeData`. A few hand-written template files are mixed in.
2. **Mod engine**: every source of power (passive node, item affix, gem stat, config checkbox, buff) becomes a **mod object**: `{name, type, value, flags, keywordFlags, source, [tags...]}`. Mods live in a **ModDB / ModList** with a parent chain. Calculations ask the store questions like `Sum("INC", cfg, "Damage", "FireDamage")`. Tags are conditional predicates (`Condition`, `Multiplier`, `PerStat`, `SkillType`, `ActorCondition`, `GlobalEffect`, ...), checked lazily at query time against the current skill context (`cfg`).
3. **Calc pipeline**: `Calcs.lua` runs `initEnv` (collect mods from tree, items, skills and config), then `perform` (attributes, life and mana, reservation, charges, buffs, auras, curses, ailments), then `defence`, `triggers` and `offence`. Every number goes into a flat `output` table. Where the calc has a UI, it also fills a parallel `breakdown` table of human-readable derivation lines. The Calcs tab (`CalcSections.lua`) declares which outputs to show, which breakdown lines go with each, and which mod names to tabulate in the "where did this come from" table.

The biggest transferable ideas are the **uniform mod object + lazily evaluated tag predicates**, the **actor/ModDB parent chain**, **declarative config options that inject mods**, **"conditionsUsed" tracking so the UI only shows relevant config options**, **override-driven what-if recalcs** (node power, item comparison), and **golden-build regression tests run headless**.

The biggest things to avoid:
- breakdown strings hand-written next to the math, so they can drift from it
- English-text parsing as the main way mods get in (~7k-line regex table)
- untyped variadic query APIs
- 32-bit flag bitmasks (PoE2 had to move to 64-bit emulation)
- the Lua + custom-host stack
- a copy-paste hard fork for the second game

---

## 1. Module layout

### 1.1 Top-level

| Path | Role |
|---|---|
| `runtime/` | Prebuilt Windows host: `Path of Building.exe`, `SimpleGraphic.dll` (C++ renderer, GLFW/D3D), `lcurl.dll`, `lua51.dll` (LuaJIT), and pure-Lua libraries in `runtime/lua/` (`dkjson`, `xml`, `base64`, `sha2`, `socket`). |
| `src/Launch.lua` | Entry point (`#@ SimpleGraphic` header). Creates a `launch` object, calls `SetMainObject(launch)`, runs the update check, loads `Modules/Main`. Handles `OnFrame` / `OnKeyDown` callbacks from the host, `DownloadPage`, and sub-scripts (threads) via `LaunchSubScript`. |
| `src/_SimpleGraphic.def.lua` | Stub and EmmyLua definition of the host API (`DrawImage`, `DrawString`, `NewImageHandle`, `SetDrawLayer`, `LaunchSubScript`, `Inflate/Deflate`...). Used by the headless wrapper. |
| `src/HeadlessWrapper.lua` | Runs PoB with no graphics under plain LuaJIT. Loads the stubs, calls `OnInit`/`OnFrame`, and exposes `newBuild()`, `loadBuildFromXML()` and `loadBuildFromJSON()`. Used by tests and CI. |
| `src/GameVersions.lua` | Tree versions, `latestTreeVersion`, legacy version mapping. |
| `src/Modules/` | "Modules": singletons or function libraries (calc engine, parser, data loader, main UI shell, build mode). |
| `src/Classes/` | "Classes" made with the home-grown `newClass(name, parent...)` OOP (in `Modules/Common.lua`). UI controls, tabs, and model objects (`Item`, `PassiveSpec`, `PassiveTree`, `ModDB`, `ModList`, `ModStore`). |
| `src/Data/` | Generated plus hand-curated game data as Lua tables (skills, bases, mods, uniques, stat descriptions, minions, bosses, `ModCache.lua`). |
| `src/TreeData/<ver>/` | One folder per tree version (`3_10`...`3_27`, PoE2 `0_1`...`0_5`): `tree.lua` (converted from GGG's tree JSON), sprites and images. |
| `src/Export/` | A **separate GUI app** ("Dat View") with its own `Main.lua`, run in the same host, for browsing `.dat` files and running export scripts that regenerate `src/Data`. |
| `spec/` | Busted tests (`spec/System/*_spec.lua`) plus golden builds (`spec/TestBuilds/<ver>/*.xml` + `.lua` expected outputs). `.busted` config at repo root. |

### 1.2 Key `src/Modules` files

| File (lines) | Role |
|---|---|
| `Main.lua` (1.8k) | App shell: mode switching (LIST/BUILD), settings, loads `ModCache`, writes it back (`SaveModCache`). |
| `Build.lua` (2.3k) | "Build mode": owns all tabs (`configTab`, `treeTab`, `skillsTab`, `itemsTab`, `calcsTab`, `importTab`, `notesTab`, `partyTab`). Save/load XML (`self.savers = {Config=..., Tree=..., Items=..., Skills=..., Calcs=...}`), the sidebar stat list, rebuild triggers. |
| `BuildDisplayStats.lua` | Declarative list of sidebar stats (which `output` keys to show and how to format them). |
| `Data.lua` (1.5k) | Loads all `Data/*` files into the global `data` table. Builds `data.skills`, `data.itemBases`, `data.uniques`, and wraps skill `statMap`s with the global `SkillStatMap`. |
| `Common.lua` | `newClass`, `copyTable`, `round`, `common.base64`, etc. |
| `ModParser.lua` (7.0k) | Text to mod list. See section 2.1. |
| `ModTools.lua` | `modLib.createMod`, `compareModParams`, `formatMod`, `parseMod` (cached wrapper). |
| `Calcs.lua` | Calc entry points: `buildOutput`, `getMiscCalculator` (what-if calculator), `calcFullDPS`. |
| `CalcBase.lua` / `CalcTools.lua` | `calcLib.mod` (`(1+INC/100)*MORE`), `calcLib.val`, gem/support matching (`canGrantedEffectSupportActiveSkill`), `buildSkillInstanceStats` (level/quality interpolation). |
| `CalcSetup.lua` (2.0k) | `calcs.initModDB`, `calcs.initEnv`, `buildModListForNode(List)`. Collects mods from every source. |
| `CalcActiveSkill.lua` | `createActiveSkill`, `buildActiveSkillModList` (skill flags, weapon flags, `skillCfg`, splitting `GlobalEffect` mods into buffs), `createMinionSkills`. |
| `CalcPerform.lua` (4.0k) | `calcs.perform`: the orchestration pass (attributes, pools, reservations, charges, flasks, buffs, auras, curses, exposure, non-damaging ailments), then calls defence, triggers, offence. |
| `CalcOffence.lua` (6.3k) | `calcs.offence`: damage, speed, crit, hit chance, DPS, leech, ailments (bleed, poison, ignite), impale, DoTs, combined DPS. |
| `CalcDefence.lua` (3.9k) | Resistances, armour/evasion/ES/ward, block, suppression, EHP and max-hit simulation (`buildDefenceEstimations`, `reducePoolsByDamage`). |
| `CalcTriggers.lua` (1.6k) | Trigger-rate math for CoC, CWC, Mjolner, Cospri's, etc. A `configTable` keyed by skill or trigger name, plus `defaultTriggerHandler`. |
| `CalcMirages.lua` | Mirage Archer / General's Cry and similar "copy of skill" mechanics. |
| `CalcBreakdown.lua` | Helper factory for breakdown line generators (`simple`, `mod`, `multiChain`, `effMult`, `area`, `slot`, ...). |
| `CalcSections.lua` (2.6k) | **Declarative layout of the Calcs tab**: sections, rows, format strings, which breakdown key and which mod names to tabulate. |
| `ConfigOptions.lua` (2.4k) | **Declarative list of config tab options**, each with an `apply` function that injects mods. |
| `ConfigVisibility.lua` | Decides which config options to show from what the build actually uses. |
| `StatDescriber.lua` | Turns raw game stats into display text using `Data/StatDescriptions` (reverse direction: stat to text). |
| `ItemTools.lua` | `itemLib.applyRange`, `formatModLine`, value scaling helpers. |
| `BuildSiteTools.lua` | Build-code host list (pobb.in, pob.codes, poe.ninja, Maxroll, pastebin, rentry, poedb), upload/download. |

### 1.3 Key `src/Classes`

- `ModStore.lua` (abstract base), `ModDB.lua` (hash by mod name), `ModList.lua` (flat array).
- `Item.lua` (2.7k): parse and serialize item text, variants, influences, crafting, `BuildModList` (local mod resolution, per-slot lists).
- `PassiveTree.lua` (tree geometry and node stat parsing via `ProcessStats`), `PassiveSpec.lua` (allocation, pathing, URL encode/decode, jewels, masteries), `PassiveTreeView.lua` (rendering and hover tooltips with stat deltas).
- Tabs: `TreeTab`, `SkillsTab`, `ItemsTab` (5k: slots, item DB, crafting UI, trade query), `CalcsTab`, `ConfigTab`, `ImportTab`, `NotesTab`, `PartyTab`, `CompareTab`.
- `CalcBreakdownControl.lua`: renders breakdown popups and the modifier source tables.
- `PoEAPI.lua`: OAuth2 PKCE client for `api.pathofexile.com` (character list, character data).
- `TradeQuery*.lua`: trade site integration with stat weights.
- About 40 generic UI controls (`ButtonControl`, `EditControl`, `DropDownControl`, `ListControl`, ...). This is a hand-rolled immediate-mode-ish widget toolkit on top of SimpleGraphic.

---

## 2. The mod system

### 2.1 The mod object

`src/Modules/ModTools.lua`:

```lua
function modLib.createMod(modName, modType, modVal, ...)
	-- optional: source (string), flags (number), keywordFlags (number), then tag tables
	return {
		name = modName, type = modType, value = modVal,
		flags = flags, keywordFlags = keywordFlags, source = source,
		select(tagStart, ...)          -- tags stored in the array part: mod[1], mod[2], ...
	}
end
```

A real parsed mod (from `Data/ModCache.lua`, for "chance to deal Double Damage"):

```lua
{ name="Damage", type="MORE", value=100, flags=0, keywordFlags=0,
  [1]={ type="Multiplier", var="DamageDoubled", globalLimit=100, globalLimitKey="DamageDoubledLimit" } }
```

Typical engine-constructed mods (`CalcSetup.lua: calcs.initModDB`):

```lua
modDB:NewMod("Life", "BASE", data.characterConstants["life_per_level"], "Base", { type = "Multiplier", var = "Level", base = 38 })
modDB:NewMod("DamageTaken", "INC", 10, "Base", ModFlag.Attack, { type = "Condition", var = "Intimidated"})
modDB:NewMod("Damage", "MORE", -10, "Base", { type = "Condition", var = "Debilitated"}, { type = "GlobalEffect", effectName = "Debilitated", effectType = "Debuff"})
```

Fields:
- **name**: the stat ID string (`"Life"`, `"FireDamage"`, `"CritChance"`, `"Condition:LowLife"`, `"Multiplier:PowerCharge"`, `"PhysicalDamageConvertToFire"`, `"ExtraAura"`, `"MinionModifier"`...). There are ~thousands of names, all ad hoc strings and not centrally declared.
- **type**:
  - `BASE`: additive flat value.
  - `INC`: additive percent (reduced = negative INC).
  - `MORE`: multiplicative percent (less = negative MORE).
  - `FLAG`: boolean.
  - `OVERRIDE`: first match wins.
  - `LIST`: collects arbitrary payload tables.
  - `MAX`, `MIN`.
  - Also `DUMMY` / `CHANCE`.
- **flags** (`ModFlag`, `Data/Global.lua`): bitmask the *query* must contain: `Attack`, `Spell`, `Hit`, `Dot`, `Melee`, `Area`, `Projectile`, `Ailment`, weapon types, `Weapon1H`... A mod matches if `band(cfg.flags, mod.flags) == mod.flags` (all of the mod's flags present in the query).
- **keywordFlags** (`KeywordFlag`): `Aura`, `Curse`, `Fire`, `Cold`, `Trap`, `Totem`, `Minion`, `Attack`, `Spell`, `Poison`, `Bleed`, `Ignite`, `FireDot`... Matches **any** by default. Add `KeywordFlag.MatchAll` to require all (`MatchKeywordFlags`, with a two-level cache).
- **source**: `"Tree:12345"`, `"Item:7:Kaom's Heart"`, `"Skill:Fireball"`, `"Config"`, `"EnemyConfig"`, `"Base"`, `"Custom:<title>"`, `"Pantheon:..."`. The UI uses the prefix before `:` to group and attribute (`cfg.source = "Tree"` lets you ask "how much INC life comes from the tree").
- **tags** (array part): conditional or scaling predicates, evaluated lazily.

### 2.2 Tag types (`Classes/ModStore.lua: ModStoreClass:EvalMod`)

`EvalMod(mod, cfg, globalLimits)` walks the tags in order. Each tag either **scales** the value or **gates** it (returns `nil`, so the mod contributes nothing):

| Tag | Effect |
|---|---|
| `Multiplier` `{var|varList, div, limit, limitVar, limitTotal, base, actor, noFloor, invert}` | `value = value * floor(GetMultiplier(var)/div) + base`. Multipliers are `Multiplier:<var>` BASE mods or `modDB.multipliers[var]`. `actor = "enemy"/"parent"/"player"` reads another actor's DB. |
| `MultiplierThreshold` `{var, threshold|thresholdVar, upper, equals}` | Gate on a multiplier value. |
| `PerStat` `{stat|statList, div, limit, base, actor}` | Scale by a computed **output** stat (`actor.output[stat]`, e.g. "per 10 Strength", "per 1% block"). This is why order matters in the pipeline: the stat must already be computed. |
| `PercentStat` `{stat, percent}` | Value = percent of a stat (e.g. "gain 10% of life as ES"). |
| `StatThreshold` | Gate on an output stat. |
| `Condition` `{var|varList, neg}` | Gate on `GetCondition(var)`: `modDB.conditions[var]`, a `Condition:<var>` FLAG mod, or `cfg.skillCond[var]` (per-skill conditions such as `MainHandAttack`). |
| `ActorCondition` `{actor="enemy"/"parent", var, neg}` | Condition on another actor (e.g. enemy is Shocked). |
| `ItemCondition`, `SocketedIn`, `SlotName`, `SlotNumber`, `InSlot` | Item and slot gates. |
| `SkillName`, `SkillId`, `SkillPart`, `SkillType` `{skillType|skillTypeList, neg}`, `BaseFlag` | Gate on the skill context in `cfg` (`cfg.skillTypes`, `cfg.skillName`, ...). |
| `ModFlagOr`, `KeywordFlagAnd` | Override the default AND/OR semantics of flags. |
| `DistanceRamp`, `MeleeProximity` | Distance-based scaling (`cfg.skillDist`). |
| `Limit` | Clamp the value. |
| `GlobalEffect` `{effectType="Buff"/"Aura"/"Curse"/"Debuff"/"Warcry"..., effectName, ...}` | Not checked in `EvalMod`. `CalcActiveSkill.buildActiveSkillModList` uses it to **move** mods out of the skill's own list into a `buffList`, which `CalcPerform` later applies to player, minion, enemy or party (with aura effect, curse effect and so on). |
| `MonsterTag` | Minion monster tags. |
| `globalLimit` / `globalLimitKey` (field on any tag) | Cross-mod cap applied after evaluation. The query passes a shared `globalLimits` table so "max 100% double damage" holds across all sources. |

**Wrapper mods** (`LIST` payload containing a mod) give indirection:
- `ExtraAura {mod=...}`, `ExtraAuraEffect`
- `MinionModifier {mod=...}` (applied to minions)
- `EnemyModifier {mod=...}` (applied to the enemy DB)
- `ExtraSkillMod`
- `SkillData {key, value}` (sets `skillData` fields)
- `JewelFunc` (radius jewels: code executed over nearby nodes)

### 2.3 Stores and queries (`ModStore`, `ModDB`, `ModList`)

```lua
-- ModStore (base): parent chain + per-store conditions/multipliers + actor link
function ModStoreClass:ModStore(parent)
	self.parent = parent or false
	self.actor = parent and parent.actor or { }
	self.multipliers = { }
	self.conditions = { }
end
```

- **`ModDB`**: `self.mods[name] = {mod, mod, ...}`. O(mods with that name) lookup. Used for actor-level DBs (`env.modDB`, `env.enemyDB`, `env.itemModDB`, minion DB).
- **`ModList`**: flat array. Used for small or temporary lists (a node's mods, an item's mods, config mods, the skill mod list). `MergeMod` collapses identical BASE/INC/MORE mods.
- **Parent chain**: `skillModList = new("ModList"):ModList(activeSkill.actor.modDB)`. A skill's own mods sit on top of the actor's DB. Every query walks `self` and then `self.parent`. That gives per-skill views without copying the player's mods.

Public query API (`ModStore.lua`):

```lua
modDB:Sum("BASE"|"INC"|..., cfg, name1, name2, ...)  -- additive total
modDB:More(cfg, name1, ...)                           -- product of (1+v/100), rounded per mod name to 2dp (game-accurate)
modDB:Flag(cfg, name...)       -- any true
modDB:Override(cfg, name...)   -- first value
modDB:List(cfg, name...)       -- collected payloads
modDB:Tabulate(type|nil, cfg, name...)  -- {value, mod} rows: used for UI attribution
modDB:Max / :Min / :HasMod / :GetCondition / :GetMultiplier / :GetStat
```

`cfg` is the skill context created in `CalcActiveSkill.lua`:

```lua
activeSkill.skillCfg = {
	flags = bor(skillModFlags, activeSkill.weapon1Flags or activeSkill.weapon2Flags or 0),
	keywordFlags = skillKeywordFlags,
	skillName = ..., skillGem = ..., skillGrantedEffect = ..., skillPart = ...,
	skillTypes = activeSkill.skillTypes, skillCond = { }, skillDist = ...,
	slotName = ..., socketColor = ..., socketNum = ...
}
```

with derived contexts such as `weapon1Cfg` / `weapon2Cfg` (adding `skillCond.MainHandAttack`), `dotCfg`, `bleedCfg`, `poisonCfg`, `igniteCfg`.

### 2.4 How "increased" and "more" are aggregated

`Modules/CalcTools.lua`:

```lua
function calcLib.mod(modStore, cfg, ...)
	return (1 + (modStore:Sum("INC", cfg, ...)) / 100) * modStore:More(cfg, ...)
end
function calcLib.val(modStore, name, cfg)
	local baseVal = modStore:Sum("BASE", cfg, name)
	return baseVal ~= 0 and baseVal * calcLib.mod(modStore, cfg, name) or 0
end
```

- All INC for the queried names are **summed into one bucket**. A query passes several names at once, e.g. `"Damage", "FireDamage", "ElementalDamage"`, so generic and specific increases stack additively.
- MORE mods multiply individually. `MoreInternal` rounds each mod name's product to 2 decimals (or to a configured `data.highPrecisionMods` precision) to match game rounding.
- **Damage-type mod name sets** (`CalcOffence.lua: damageStatsForTypes`) come from a type bitmask. Converted damage carries the flags of every type it passed through, so Physical converted to Fire benefits from both Physical and Fire INC/MORE (correct PoE behaviour). This is an elegant design detail:

```lua
local function calcDamage(activeSkill, output, cfg, breakdown, damageType, typeFlags, convDst)
	typeFlags = bor(typeFlags, dmgTypeFlags.flags[damageType])
	-- recursively pull converted damage from earlier types in conversion order
	for _, otherType in ipairs(dmgTypeList) do
		if otherType == damageType then break end
		local convMult = conversionTable[otherType][damageType]
		if convMult > 0 then
			local min, max = calcDamage(activeSkill, output, cfg, breakdown, otherType, typeFlags, damageType)
			addMin = addMin + min * convMult ...
	local modNames = damageStatsForTypes[typeFlags]          -- e.g. {"Damage","PhysicalDamage","FireDamage","ElementalDamage"}
	local inc  = 1 + skillModList:Sum("INC", cfg, unpack(modNames)) / 100
	local more = skillModList:More(cfg, unpack(modNames))
```

### 2.5 ModParser: text to mods (`Modules/ModParser.lua`, 7k lines)

PoB's canonical **input format for mods is English text**: item affixes, uniques, passive node `stats`, cluster jewel lines, and the user's custom mods all go through it. The parser is a cascade of Lua-pattern tables:

1. `jewelFuncList`, `clusterJewelSkills`, `unsupportedModList`.
2. **`specialModList`** (~3,800 lines, 2130 to 5949): full-line patterns mapping to hand-written mod lists or functions, e.g. `["enemies you kill have a (%d+)%% chance to explode, ..."] = function(...) return explodeFunc(...) end`.
3. Otherwise a **compositional parse** (`parseMod(line, order)`). Each `scan()` finds the earliest and longest match in a table and removes it from the line:
   - `preFlagList` (`"^axe attacks deal "` → `{flags=ModFlag.Axe}`)
   - `preSkillNameList`
   - **`formList`** (`"^(%d+)%% increased"` → `INC`, `"less"` → `LESS` (negative MORE), `"^([%+%-][%d%.]+)%%? to"` → `BASE`, `"DMG"` for "adds X to Y", `PEN`, `FLAG`, `OVERRIDE`, `DOUBLED`...)
   - `modTagList` (`"per power charge"` → `{tag={type="Multiplier", var="PowerCharge"}}`, `"on critical strike"` → `Condition:CriticalStrike`, `"for you and nearby allies"` → `newAura`)
   - **`modNameList`** (`"maximum life"` → `"Life"`, `"strength and dexterity"` → `{"Str","Dex","StrDex"}`)
   - `skillNameList`
   - **`modFlagList`** (`"with bows"` → `{flags = bor(ModFlag.Bow, ModFlag.Hit)}`)
   - `suffixTypes` (`"ConvertToFire"`, `"GainAsCold"`...)
4. Combine flags, keywordFlags and tags. Then wrap according to `misc` hints: `addToAura` → `ExtraAuraEffect`, `newAura` → `ExtraAura`, `addToMinion` → `MinionModifier`, `applyToEnemy` → `EnemyModifier`, `addToSkill` → `ExtraSkillMod`.
5. Returns `modList, unparsedRemainder`. A non-nil remainder means "unsupported/partially supported". The UI shows those lines in red/grey. Item and tree code then tries **combining multi-line mods** (`PassiveTree:ProcessStats`).

Results are memoized (`cache[line]`) and **pre-baked into `Data/ModCache.lua`** (`c["<line>"] = {modList, remainder}`), which is loaded at startup. CI regenerates ModCache headless and fails if the diff is non-empty (`.github/workflows/test.yml` → `check_modcache`).

---

## 3. Calc pipeline

### 3.1 Entry points (`Modules/Calcs.lua`)

```lua
function calcs.buildOutput(build, mode)          -- mode = "MAIN" (sidebar) or "CALCS" (calcs tab, honours buff-mode selector)
	local env, cachedPlayerDB, cachedEnemyDB, cachedMinionDB = calcs.initEnv(build, mode)
	calcs.perform(env)
	local fullDPS = calcs.calcFullDPS(build, "CALCULATOR", {}, {...cached DBs...})
	...  -- then records env.conditionsUsed / multipliersUsed / modsUsed / skillsUsed for the config UI
end

function calcs.getMiscCalculator(build)          -- returns a closure for what-if calcs
	return function(override, useFullDPS)
		local env = calcs.initEnv(build, "CALCULATOR", override); calcs.perform(env); return env.player.output
	end, baseOutput
end
```

`CalcsTab:BuildOutput()` runs `buildOutput` twice (MAIN and CALCS) on every change. `CalcsTab:PowerBuilder()` (a coroutine, so the UI doesn't freeze) uses the misc calculator with `override = { addNodes = {...} }` / `{ removeNodes = ... }` / `{ repSlotName, repItem }` / `{ toggleFlask }` / `{ conditions = {...} }` to compute **per-node power heatmaps**, item swap deltas and tooltip "+X DPS" comparisons. The `override` table is threaded through `initEnv`, which changes what gets collected.

**Modes**: `env.mode_buffs`, `mode_combat` and `mode_effective` come from the Calcs-tab selector ("Unbuffed / Buffed / In Combat / Effective DPS"). Base mods carry `{type="Condition", var="Combat"}` / `"Effective"` tags (e.g. config enemy conditions use `var = "Effective"`), so one engine produces sheet-DPS vs effective-DPS views.

### 3.2 `calcs.initEnv` (CalcSetup.lua): gathering mods

1. Creates `env` with three actors, each owning a ModDB:
   ```lua
   env.player = { modDB = env.modDB, level = build.characterLevel }
   env.enemy  = { modDB = env.enemyDB, level = env.enemyLevel }
   env.player.enemy = env.enemy; env.enemy.enemy = env.player
   ```
   Minion actors are created later with their own DB.
2. Base mods: class base attributes, `calcs.initModDB` (resist caps, charge maxima, leech caps, shrine/condition FLAG→effect mods, life/mana per level as `Multiplier:Level`).
3. **Config**: `env.modDB:AddList(build.configTab.modList)`, `env.enemyDB:AddList(build.configTab.enemyModList)`, plus the party tab.
4. **Passive tree**: `calcs.buildModListForNodeList(env, env.allocNodes, true)`. This handles override add/remove nodes, radius jewels (`JewelFunc` mutating node mod lists), tattoos, masteries, timeless jewels, cluster subgraphs.
5. **Items**: per slot, `item.modList` or `item.slotModList[slotNum]`, with scale factors (e.g. "+X% effect of socketed jewels"), into `env.itemModDB`, which is then added to modDB. Flasks and tinctures go to separate lists (applied in perform if active).
6. **Skills**: walks socket groups and expands gems into `activeEffect` + applicable supports (`calcLib.canGrantedEffectSupportActiveSkill`, `addBestSupport`). Then `calcs.createActiveSkill` → `buildActiveSkillModList` builds each skill's `skillModList`: level stats via `statMap` → mods, `baseMods`, support mods, skill flags and weapon flags.
7. Can **re-enter itself** (`return calcs.initEnv(build, mode, override, specEnv)`) when a later discovery changes earlier inputs (extra jewel funcs, Energy Blade condition). Cheap fixpoint by restart.
8. Caching: `cachedPlayerDB` etc. are reused across FullDPS passes so the per-skill calc doesn't rebuild the item/tree DB. `GlobalCache.cachedData[mode][uuid]` stores per-skill outputs for cross-skill lookups (e.g. cost warnings, trigger sources).

### 3.3 `calcs.perform` (CalcPerform.lua): global state and buffs

Rough order (from the section comments in `calcs.perform`):
1. Merge keystones. Build minion skills and init minion ModDBs.
2. Banners, curses/hexes classification, minion counts.
3. Init breakdown module: `env.player.breakdown = require(calcs.breakdownModule)(modDB, output, actor)` (only when `env.buildBreakdown`).
4. Flasks and tinctures (effect scaling), Mageblood.
5. `doActorAttribsConditions`, `doActorLifeMana` (life = `calcLib.val(modDB,"Life")` etc. with breakdowns), `doActorLifeManaReservation`, attribute requirements.
6. Count auras/heralds, `doActorCharges`, `doActorMisc`.
7. **Combine buffs/debuffs**: iterate all active skills' `buffList`s. By `buff.type` (`Buff`, `Aura`, `Curse`, `Debuff`, `Guard`, `Warcry`...), compute effect multipliers (aura effect, curse effect, buff effect on self) and `ScaleAddList` the buff's mods into player, minion, party or **enemy** DBs. Curse slots and priority (`determineCursePriority`), marks, exposure, consecrated ground.
8. Non-damaging ailments (chill, shock, scorch, brittle, sap): max strength, guaranteed sources.
9. Then: `calcs.defence(env, player)`, `buildDefenceEstimations` (EHP), `calcs.triggers`, `calcs.mirages` or `calcs.offence(env, player, mainSkill)`. Then the same for the minion.

The ordering is **implicit and hand-tuned**. Comments like "needs to be after main auras but before extra auras" and "Merge keystones again to catch any that were added by buffs" show it is fragile.

### 3.4 `calcs.offence` (CalcOffence.lua)

Section order in the function:
1. Update `skillData`, add stat bonuses, skill-type stats (area, projectile count, duration, cooldown, trap/mine/totem specifics).
2. **Costs** (two passes for cost conversion).
3. Explosions. **Conversion table** (`activeSkill.conversionTable` from `SkillXConvertToY`, `XConvertToY`, `XGainAsY`, scaled down if over 100%).
4. **Damage passes** (`passList`): one per weapon for attacks (`Main Hand` / `Off Hand` with `weapon1Cfg`/`weapon2Cfg`, own `output.MainHand` and `breakdown.MainHand`), or a single `Skill` pass for spells. Then `combineStat(stat, "OR"/"ADD"/"AVERAGE"/"DPS"...)` merges the hands.
5. Per pass:
   - **hit chance** (accuracy vs evasion → `calcs.hitChance`)
   - **attack/cast speed** (`Speed` INC/MORE with `ModFlag.Cast` / `Attack`, action speed, attack-rate caps)
   - **crit** (base + `CritChance` BASE, INC, MORE, lucky, bifurcate, cap, × hit chance)
   - double/triple damage, culling
   - **base damage** (weapon or skill base × `baseMultiplier` / damage effectiveness + added damage)
   - **per-type `calcDamage`** (conversion → INC/MORE)
   - enemy mitigation (`effMult`: resist, penetration, damage taken, armour for physical)
   - leech, on-hit/on-kill gains
   - average hit → **AverageDamage → TotalDPS** (× speed × hit chance × crit effect × quantity multipliers)
6. **Ailments**: bleed, poison, ignite as "chance to apply × stacks × per-stack DPS" with weighted-average crit/non-crit source damage. Separate DoT configs. Non-damaging ailment magnitudes, stun, knockback, impale.
7. **Skill DoT components** (`skillData.dot`), self-hit, then **CombinedDPS** (hit + DoT + ailments + impale + culling).

### 3.5 `calcs.defence` (CalcDefence.lua)

Resistances (capped, overcapped), armour/evasion/ES/ward via `calcLib.val`, block and spell suppression, damage-taken conversion, `takenHitFromDamage`, and **max hit / EHP estimation** by simulating hits through pools (`reducePoolsByDamage` handles ES before life, MoM, guard, life-loss prevention). Everything writes `output.*` plus `breakdown.*`.

### 3.6 CalcTriggers.lua

`calcs.triggers(env, actor)` looks up a config factory by skill id, skill name, trigger name or unique-item name in `configTable`. It runs `defaultTriggerHandler` (or a custom handler) to compute the trigger rate: source skill rate × chance, cooldown with server-tick rounding, multi-skill rotation (`calcMultiSpellRotationImpact`). The result is written into the triggered skill's `skillData` so offence uses it as the speed. It finds the source skill by running the full calc for other skills (`GlobalCache`). Lots of special cases. This is the area most likely to be needed in Last Epoch (LE has many "on hit/on kill/on cast" triggers).

### 3.7 Breakdowns: how the UI explains every number

There are **three cooperating layers**:

**(a) Breakdown lines produced inside the calc**, only when `breakdown` is non-nil (MAIN/CALCS mode, not during power calcs). They are *hand-written next to the math*:

```lua
-- CalcPerform.lua, doActorLifeMana
breakdown.Life = { }
breakdown.Life[1] = s_format("%g ^8(base)", base)
if inc ~= 0 then  t_insert(breakdown.Life, s_format("x %.2f ^8(increased/reduced)", 1 + inc/100)) end
if more ~= 1 then t_insert(breakdown.Life, s_format("x %.2f ^8(more/less)", more)) end
t_insert(breakdown.Life, s_format("= %g", output.Life))
```

Breakdown entries can also be structured tables, e.g. the per-damage-type table from `calcDamage`:

```lua
t_insert(breakdown.damageTypes, {
	source = damageType, base = baseMin .. " to " .. baseMax,
	inc = (inc ~= 1 and "x "..inc), more = (more ~= 1 and "x "..more),
	convSrc = ..., total = ..., convDst = "50% to Fire", gainDst = ...,
})
```

`CalcBreakdown.lua` gives reusable generators: `breakdown.simple(extraBase, cfg, total, ...)` (base × inc × more = total, by querying the modDB again), `breakdown.mod`, `breakdown.multiChain(out, {label, base, {fmt, mult}...})`, `breakdown.effMult` (resist/pen/taken), `breakdown.area`, `breakdown.slot` (per-item-slot armour contributions).

**(b) Declarative section layout** (`CalcSections.lua`). Each row names the output to display, the breakdown key(s) and the **mod names to tabulate**:

```lua
{ label = "Crit Chance", notFlag = "attack", { format = "{2:output:CritChance}%",
	{ breakdown = "CritChance" },
	{ label = "Player modifiers", modName = {"CritChance", ...}, cfg = "skill" },
	{ label = "Enemy modifiers", modName = "SelfCritChance", enemy = true },
}, },
{ label = "Total Increased", notFlag = "attack",
	{ format = "{0:mod:1}%", { modName = "Damage", modType = "INC", cfg = "skill" }, }, ... }
```

Format strings like `{2:output:CritChance}` (2 decimals of `output.CritChance`) or `{0:mod:1}` (live mod query) are interpreted by `CalcSectionControl`. `flag` / `notFlag` / `haveOutput` show or hide rows by skill flags.

**(c) Mod attribution tables** (`CalcBreakdownControl:AddModSection`). For each `modName` row it **re-queries** `modStore:Tabulate(modType, cfg, names...)` using the *same skill cfg*. It renders a table with columns Value / Stat / Skill types (decoded flags) / Notes (decoded tags such as "Condition: Not LowLife", "per 10 Strength", "Skill type: Spell") / Source ("Tree", "Item", "Skill"...) / Source Name (node name, item name with rarity colour and hover tooltip). It also computes **per-source-type totals** via `Combine(modType, cfg)` with `cfg.source = sourceType`.

The result: hovering a number shows the arithmetic chain *and* every contributing mod with its origin. **Weakness**: layer (a) is free-form strings written by hand next to every formula. It is easy to forget, easy to get out of sync with the real computation, and hard to localize. Layer (c) is generic and robust because it reuses the query engine.

---

## 4. Config tab (`Modules/ConfigOptions.lua`, `Classes/ConfigTab.lua`)

`ConfigOptions.lua` returns an ordered array. Section headers are `{ section = "General", col = 1 }`. Options look like:

```lua
{ var = "conditionLowLife", type = "check", label = "Are you always on Low ^xE05030Life?",
  ifCond = "LowLife", tooltip = LowLifeTooltip,
  apply = function(val, modList, enemyModList)
	modList:NewMod("Condition:LowLife", "FLAG", true, "Config")
  end },

{ var = "conditionEnemyShocked", type = "check", label = "Is the enemy ^xADAA47Shocked?",
  apply = function(val, modList, enemyModList)
	enemyModList:NewMod("Condition:Shocked", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
  end },
{ var = "conditionShockEffect", type = "count", label = "Effect of ^xADAA47Shock:", ifOption = "conditionEnemyShocked",
  apply = function(val, modList, enemyModList)
	enemyModList:NewMod("ShockVal", "BASE", val, "Shock", { type = "Condition", var = "ShockedConfig" })
  end },

{ var = "usePowerCharges", type = "check", label = "Do you use Power Charges?", apply = function(val, modList)
	modList:NewMod("UsePowerCharges", "FLAG", true, "Config", { type = "Condition", var = "Combat" }) end },
{ var = "overridePowerCharges", type = "count", label = "# of Power Charges (if not maximum):", ifOption = "usePowerCharges", ... },

{ var = "enemyFireResist", type = "countAllowZero", label = "Enemy Fire Resistance:", apply = function(val, modList, enemyModList)
	enemyModList:NewMod("FireResist", "BASE", val, "EnemyConfig") end },
```

- **Types**: `check`, `count`, `integer`, `countAllowZero`, `float`, `list` (dropdown with `{val,label}`), `text`. Also `defaultState`, `defaultIndex`, and **placeholders**: computed defaults shown greyed out (e.g. boss presets set `enemySpeed`, `enemyCritChance`), applied if no user input.
- **Visibility predicates**: `ifCond`, `ifEnemyCond`, `ifMinionCond`, `ifMult`, `ifEnemyMult`, `ifEnemyStat`, `ifTagType`, `ifMod`, `ifSkill`, `ifSkillData`, `ifFlag`, `ifOption` (dependent option), `implyCond` (`ConfigVisibility.lua`). They check `mainEnv.conditionsUsed[...]` etc. Those sets are filled by `calcs.buildOutput`, which scans **every mod in the DBs for tags it references** (`addTo(env.conditionsUsed, tag.var, mod)`). So **the config tab only shows "Are you on Low Life?" if some mod in the build actually has a `Condition: LowLife` tag**, and the tooltip can list which mods use it. This is a great UX pattern to copy.
- `ConfigTab:BuildModList()` turns inputs into two `ModList`s (`modList` for the player, `enemyModList` for the enemy) by calling each option's `apply`. It also parses **free-text custom mods** through `modLib.parseMod` with source `"Custom:<block>"`. These lists are added in `initEnv`.
- Multiple **config sets** per build (PoE2 adds a `ConfigSetService`).

---

## 5. Data pipeline

### 5.1 The exporter (`src/Export`)

- A separate app run in the same SimpleGraphic host (`Export/Launch.lua`, `Export/Main.lua`). It is a GUI to point at a GGPK / Steam install, browse tables, edit column specs, and run scripts.
- **GGPK extraction**: `Export/ggpk/` uses an external `bun_extract_file.exe` (from the community "ooz/bun" tools) to unpack `Data/*.dat64` and `Metadata/StatDescriptions/*.txt|.csd` (`Classes/GGPKData.lua`).
- **Binary table schema**: `Export/spec.lua` (14k lines) is a hand-maintained schema of every `.dat` table (`{name, type = "Int"/"String"/"Key"/"ShortKey"/"Enum"/..., refTo, list, width}`). `Classes/DatFile.lua` / `Dat64File.lua` read rows with typed accessors and foreign keys (`dat("Mods"):Rows()`, `mod.SpawnTags[1].Id`). The in-app editor (`SpecColListControl`) lets maintainers reverse-engineer new columns after each patch.
- **Scripts** (`Export/Scripts/*.lua`): `skills.lua`, `mods.lua`, `bases.lua`, `minions.lua`, `statdesc.lua`, `miscdata.lua`, `bossData.lua`, `essence.lua`, `pantheons.lua`, `legionPassives.lua`, `skillGemList.lua`, ... Each writes a `-- This file is automatically generated, do not edit!` Lua file into `src/Data`.
- **Template files with directives**: `processTemplateFile(name, inDir, outDir, directiveTable)` reads `Export/Skills/act_str.txt` etc. Lines starting with `#` are directives (`#skill <Id>`, `#flags spell area`, `#baseMod skill("radius", 25)`, `#mods`, PoE2 adds `#set` and `#skillEnd`). Everything else (notably the hand-written `statMap` overrides) is copied verbatim. So **hand-curated mechanics live next to generated data in the same source file**, and the output is regenerated without losing them:

```
#skill Cleave
#flags attack melee area
	statMap = {
		["cleave_+1_base_radius_per_nearby_enemy_up_to_10"] = {
			mod("AreaOfEffect", "BASE", nil, 0, 0, { type = "Multiplier", var = "NearbyEnemies", limit = 10, limitTotal = true })
		},
	},
#baseMod skill("radius", 20)
#mods
```

- The passive tree is **not** taken from GGPK in PoE1. It comes from GGG's published tree JSON, converted to `TreeData/<ver>/tree.lua`. Node `stats` are English lines, parsed at load by `PassiveTree:ProcessStats` → `modLib.parseMod`. PoE2 has `Export/Scripts/passivetree.lua` (from game files + texture packing via `gimpbatch` / `nvtt`) and `passivetree_ggg.lua` (from `grindinggear/poe2-skilltree-export`).

### 5.2 Output formats (all Lua tables)

- **Skills** (`Data/Skills/act_str.lua` ...):
  ```lua
  skills["Cleave"] = {
  	name = "Cleave", color = 1, skillTypes = { [SkillType.Attack] = true, [SkillType.Area] = true, ... },
  	weaponTypes = { ["One Handed Axe"] = true, ... }, castTime = 1,
  	statMap = { [...] = { mod(...) } },          -- skill-specific stat→mod overrides
  	baseFlags = { attack = true, melee = true, area = true },
  	baseMods = { skill("radius", 20) },
  	qualityStats = { { "cleave_+1_base_radius_per_nearby_enemy_up_to_10", 0.05 } },
  	constantStats = { { "active_skill_merged_damage_+%_final_while_dual_wielding", -40 } },
  	stats = { "active_skill_base_radius_+", "is_area_damage", ... },   -- column order for levels[]
  	levels = { [1] = { 0, attackSpeedMultiplier = -20, baseMultiplier = 1.794, damageEffectiveness = 1.794,
  	                   levelRequirement = 1, statInterpolation = { 1, }, cost = { Mana = 7, }, }, ... },
  }
  ```
- **Item mods** (`Data/ModItem.lua`, `ModJewel.lua`, `ModFlask.lua` ...) are stored **as rendered English text** plus metadata:
  ```lua
  ["Strength1"] = { type = "Suffix", affix = "of the Brute", "+(8-12) to Strength", statOrder = { 1204 }, level = 1,
                    group = "Strength", weightKey = { "ring", "amulet", ..., "default" }, weightVal = { 1000, 1000, ..., 0 },
                    modTags = { "attribute" }, tradeHashes = { [4080418644] = { "+(8-12) to Strength" } } },
  ```
  The exporter renders raw stats to text using the stat-description engine (`describeMod`). The app then **parses the text back into mods** with ModParser. One text pipeline serves items pasted from the game, imported from the API, crafted in-app, and uniques.
- **Uniques** (`Data/Uniques/*.lua`): long-bracket strings in **the in-game Ctrl+C item text format**, with PoB extensions (`Variant:`, `{variant:2,3}`, `{tags:...}`, `Implicits: N`, `LevelReq:`).
- **Bases** (`Data/Bases/*.lua`): `itemBases["Amber Amulet"] = { type, subType, tags, implicit = "...", req = {...}, weapon/armour = {...} }`.
- **Stat descriptions** (`Data/StatDescriptions/*.lua`): parsed GGG description files (`stats`, `limit` ranges, `text` templates, value handlers). Used by `StatDescriber.lua` for gem tooltips and by the exporter.
- **`Data/SkillStatMap.lua`** (2.4k): the **global game stat ID → PoB mod mapping**, used for all gem stats (per-skill `statMap` overrides via metatable fallback, `Data.lua` line ~1066):
  ```lua
  ["base_skill_effect_duration"] = { skill("duration", nil), div = 1000 },
  ["critical_strike_chance_+%"]  = { mod("CritChance", "INC", nil) },
  ["base_cast_speed_+%"]         = { mod("Speed", "INC", nil, ModFlag.Cast) },
  ["active_skill_merged_damage_+%_final_while_dual_wielding"] = { mod("Damage", "MORE", nil, 0, 0, { type = "Condition", var = "DualWielding" }) },
  ["infinite_minion_duration"]   = { skillFlag = "permanentMinion" },
  ```
  `calcs.mergeSkillInstanceMods` (CalcActiveSkill.lua) evaluates level/quality stats (`calcLib.buildSkillInstanceStats` with `statInterpolation` 1 = constant, 2 = linear, 3 = effectiveness-scaled). For each stat with a map entry it clones the template mod with `value = statValue * mult / div + base` (cached per value in `mergeLevelCache`).
- `Data/Global.lua`: `ModFlag`, `KeywordFlag`, `SkillType` enums (names from `ActiveSkillType.dat`), colour codes.
- `Data/Misc.lua`, `Data/Bosses.lua`, `Data/Minions.lua`, `Data/Spectres.lua`, `Data/Costs.lua` ...: constants (`data.characterConstants`, `data.monsterLifeTable`) used by the calcs.

---

## 6. Build import / export

- **Native build format**: XML. `<PathOfBuilding><Build level= className= ascendClassName= mainSocketGroup= ...><PlayerStat .../></Build><Tree>...<Spec treeVersion= nodes="..." masteryEffects=.../></Tree><Items>...</Items><Skills>...</Skills><Config>...</Config><Calcs/><Notes/></PathOfBuilding>`. Each tab implements `Load(xml)` / `Save(xml)`, registered in `Build.lua: self.savers`. Items are stored as raw item text inside `<Item>` elements. PlayerStats are cached outputs, which the golden tests use.
- **Build code**: `ImportTab.lua` line 505:
  ```lua
  common.base64.encode(Deflate(self.build:SaveDB("code"))):gsub("+","-"):gsub("/","_")
  -- import:
  local xmlText = Inflate(common.base64.decode(buf:gsub("-","+"):gsub("_","/")))
  ```
  That is zlib/deflate (host-provided `Deflate/Inflate`) + URL-safe base64 of the full XML.
- **Paste sites**: `Modules/BuildSiteTools.lua` has a table of `{label, id, matchURL, regexURL, downloadURL, postUrl, postFields, codeOut}` for Maxroll, pob.codes, pobb.in, poe.ninja, pastebin, rentry, poedb. Upload/download go through `LaunchSubScript` + lcurl in a background thread. There is also a `pob://<siteId>/<buildId>` protocol handler.
- **Character import from PoE**:
  - Legacy public endpoints: `character-window/get-characters`, `get-passive-skills`, `get-items?accountName=&character=&realm=` (`ImportTab:DownloadPassiveTree`, `DownloadItems`).
  - OAuth: `Classes/PoEAPI.lua` does OAuth2 PKCE against `pathofexile.com/oauth`, scopes `account:profile/leagues/characters`, `DownloadCharacterList`, `DownloadCharacter`, with a rate limiter. PoE2 uses only the OAuth path.
  - `ImportPassiveTreeAndJewels(charData)` maps node hashes / mastery effects / jewels into a `PassiveSpec`. `ImportItemsAndSkills` → `ImportItem(itemData, slotName)` turns the JSON item (`frameType` → rarity, `typeLine` → base lookup, `implicitMods`/`explicitMods`/`craftedMods`/`enchantMods` text arrays, sockets, socketed gems) into PoB item text, then `Item:ParseRaw`. Gems become socket groups. `GuessMainSocketGroup()` picks the main skill.
  - Tree URLs: `PassiveSpec:EncodeURL/DecodeURL` (GGG's base64 binary tree format), `DecodePoePlannerURL`.
- PoE2 also has `Modules/BuildExportPoE2.lua`: exports a loadout to the **in-game BuildPlanner `.build` JSON**.

---

## 7. Items (`Classes/Item.lua`, `Classes/ItemsTab.lua`)

- **The model is text-first.** `Item:ParseRaw(raw)` (~1,200 lines) parses the in-game copy format line by line:
  - Rarity / name / base.
  - Properties (Quality, Sockets, LevelReq, Item Level).
  - Influence and special flags (Corrupted, Fractured, Synthesised, Mirrored).
  - `Implicits: N`.
  - Mod lines with PoB annotations `{crafted}`, `{fractured}`, `{range:0.5}`, `{variant:..}`, `{tags:..}`, `{custom}`.
  - "Prefix:/Suffix:" lines with mod IDs for crafted rares.

  Each mod line becomes `{line, range, modList = parseMod(line), extra = unparsed, crafted, implicit, ...}`. Ranged lines `(8-12)` store a `range` 0..1, resolved by `itemLib.applyRange` before parsing.
- `Item:BuildRaw()` serializes back. `BuildAndParseRaw()` is the canonical "rebuild after edit".
- **Local vs global**: ModParser produces local-flavoured names for weapon/armour local stats. `Item:BuildModListForSlotNum` uses `calcLocal(modList, name, type, flags)` to *consume* local mods (e.g. local phys INC, added phys, local attack speed, local armour INC) into `weaponData` / `armourData` (min/max damage, APS, crit, armour/evasion/ES). The rest pass through as global mods with `source = "Item:<id>:<name>"`. Per-slot lists handle "in slot N"-style mods.
- **Affix representation for crafting**: `item.prefixes = { {modId="Strength3", range=0.5}, ... }` / `item.suffixes`, `affixLimit`. `Item:Craft()` rebuilds `explicitModLines` from `data.itemMods` entries, merging same-`statOrder` lines numerically. It also sets the name prefix/suffix and level requirement = `floor(mod.level*0.8)`. `GetModSpawnWeight` / `CanHaveMod` filter the affix pool using `weightKey/weightVal` against base tags + influence tags. The ItemsTab "Craft item" UI is dropdowns of eligible affixes with tier sliders. Crafting-bench mods (`ModMaster`), essences, enchants, corruptions, anointments, cluster jewels and timeless jewels have their own data and popups.
- **ItemsTab**: slot controls (`ItemSlotControl`), item sets (swap loadouts), unique/rare DB browser (`ItemDBControl`) with sort-by-DPS-delta (uses the misc calculator with `repSlotName/repItem`), shared items across builds, trade query generator (`TradeQueryGenerator` builds weighted-sum searches from stat deltas).

---

## 8. Testing

- **Framework**: busted, run headless via `src/HeadlessWrapper.lua` (`.busted`: `directory="src"`, `helper="HeadlessWrapper.lua"`, `ROOT={"../spec"}`, `exclude-tags="builds"`). CI (`.github/workflows/test.yml`) runs `busted --lua=luajit` in a Docker image and separately **regenerates ModCache and fails on diff**.
- **Unit/system specs** (`spec/System/*_spec.lua`, 44 in PoE1, 52 in PoE2): build a scenario through the real UI-model API, run a frame, assert on outputs:
  ```lua
  it("no armour max hits", function()
  	build.configTab.input.enemyIsBoss = "None"
  	build.configTab:BuildModList()
  	runCallback("OnFrame")
  	assert.are.equals(60, build.calcsTab.calcsOutput.PhysicalMaximumHitTaken)
  	build.configTab.input.customMods = "+200 to all resistances\n200% additional Physical Damage Reduction\n"
  	build.configTab:BuildModList(); runCallback("OnFrame")
  	assert.are.equals(600, build.calcsTab.calcsOutput.PhysicalMaximumHitTaken)
  end)
  ```
  Patterns:
  - `build.skillsTab:PasteSocketGroup("Fireball 20/0  1\nCommunion 3/0  1")` to add skills
  - **custom mods as test fixtures** (any mechanic can be injected as text)
  - item text pasted into the items tab
  - direct `modDB:Sum(...)` probes
  - `assertNearRelative` tolerances

  Files: `TestOffence`, `TestDefence`, `TestAilments`, `TestAttacks`, `TestImpale`, `TestTriggers`, `TestItemParse`, `TestItemMods`, `TestImport` (with `SampleCharacter.json`), `TestSkills`, `TestBuilds`.
- **Golden builds** (`spec/TestBuilds/3.13/*.xml` + `.lua`): `spec/GenerateBuilds.lua` (busted profile `generate`) loads each XML and dumps `build.calcsTab.mainOutput` into a `.lua` file with `xml = [[...]]` and `output = {...}`. `TestBuilds_spec.lua` (tag `#builds`) reloads each one and asserts every output key to 4 decimals. These are **regression snapshots, not ground truth**. They are excluded from the default run (and only cover ancient 3.13 builds), so they are effectively unmaintained.
- **What validates "correctness" vs the game?** Nothing automated. Correctness comes from community testing in game, wiki/datamined formulas, and PR review. Tests guard against regressions and parser coverage.

---

## 9. PoE2 fork vs PoE1

**Architecture**: the **same** (same host, same Lua module/class layout, same mod engine, same calc pipeline shape, same Export app, same XML/build-code format). It is a **hard fork**: the files were copied and then edited independently. There is no shared library. Diff stats per file (lines changed / total):

| File | PoE1 | PoE2 | changed lines |
|---|---|---|---|
| ModParser.lua | 7021 | 7454 | ~4.7k |
| CalcOffence.lua | 6263 | 6471 | ~4.5k |
| CalcPerform.lua | 3990 | 3724 | ~2.8k |
| CalcDefence.lua | 3874 | 4391 | ~2.6k |
| CalcSetup.lua | 1975 | 2604 | ~1.9k |
| Item.lua | 2736 | 2908 | ~1.9k |
| ModStore.lua | 971 | 1084 | ~330 |
| CalcBreakdown.lua | 255 | 266 | 65 |

What PoE2 changed or generalized:
- **64-bit flags**: `ModFlag` overflowed 32 bits (new weapon types: Crossbow, Flail, Spear, Warstaff, Talisman; Thorns). Since LuaJIT `bit` is 32-bit, PoE2 adds `OR64/AND64/XOR64` helpers in `Data/Global.lua`, and `ModDB` uses `local band = AND64`. A direct consequence of the bitmask design.
- **Perf work in ModDB/ModList**: `SumInternalMulti` with fixed arity (`nameAt(i, n1..n8)`) to avoid `select('#', ...)` aborting JIT traces. ModDB grew from 370 to 568 lines. Mod queries are the hot path.
- **Skills**: gems are no longer socketed in items. Skills have multiple **stat sets** (`#set` directive, `grantedEffect.statSets`, `mergeSkillInstanceMods(env, modList, skillEffect, statSet, ...)`). New `GemTag` tag type. Spirit reservation. Weapon-set-specific passives (`Condition: WeaponSet1/2`, node `allocMode`), handled by rewriting tags in `CalcSetup`.
- **Services layer** for loadouts: `BuildSetService`, `ConfigSetService`, `ItemSetService`, `SkillsSetService` (a small step toward separating model ops from UI controls).
- **Data**: new tables (runes `ModRunes`, charms, soul cores, `WorldAreas`, `QuestRewards`, `InventorySlots`, `LiquidEmotions`, `VerisiumCrafts`). Tree exported from game files plus texture atlases (`.dds.zst` gem icons, `Assets.lua`). Tree versions `0_1`...`0_5`.
- **Import**: OAuth API only. Plus export to the in-game planner (`BuildExportPoE2.lua`).
- Removed PoE1-only systems (pantheon, delve, synthesis, cluster jewels, foulborn, tattoos ...).

What was **copied** (with bugs): e.g. this line exists in both repos:

```lua
-- CalcOffence.lua (PoE1 line 2194, PoE2 line 2712)
local more = skillModList:More("MORE", cfg, "Accuracy")   -- signature is More(cfg, ...): "MORE" is taken as cfg,
                                                          -- the real cfg becomes a *mod name*; skill flags are ignored
```

It works only by accident: string-indexing returns nil, so flags=0. This is a textbook example of the untyped variadic API hazard, spread by a copy-paste fork.

---

## 10. Lessons / transferable architecture for a Last Epoch planner

### 10.1 Patterns to copy

1. **One uniform modifier record**: `{ stat, kind: BASE|INC|MORE|FLAG|OVERRIDE|LIST|MAX|MIN, value, scope/flags, tags[], source }`. Every input becomes this record:
   - passive nodes (LE class + mastery trees)
   - **skill specialization tree nodes** (LE's per-skill trees are the analogue of PoB support gems + `statMap`)
   - item affixes (T1 to T7 + sealed/exalted), implicits
   - uniques + **legendary potential / weaver's will**, set bonuses, idols, blessings
   - config toggles, buffs/auras, enemy debuffs (shred, armour shred, etc.)
2. **Lazy tag predicates evaluated against a query context**: `Condition`, `Multiplier` (per X stacks, e.g. per stack of Ignite / Bleed / Poison, per active minion, per Ward), `PerStat` (per attribute, LE has many "+X per point of Strength/Int/..."), `ActorCondition(enemy, ...)`, `SkillTag` (LE skill tags: Spell, Melee, Bow, Minion, Fire, DoT, Channel, Throwing, Totem, Buff, Movement, Transform...), `GlobalEffect` (buff extraction), `globalLimit`. Keeping mods "unevaluated" until queried is what makes per-skill, per-hand and per-ailment contexts cheap.
3. **Actors with stores and a parent chain**: player, enemy, each minion/totem, plus `skillStore(parent = player)`. Wrapper mods `MinionModifier` / `EnemyModifier` / `ExtraAura` for "minions gain X" / "enemies take X" / "nearby allies gain X". This fits LE's minion-heavy classes (Necromancer, Beastmaster, Forge Guard) directly.
4. **Increased are additive per query (summed over a name set), More multiply individually**, with damage-type name sets built from type flags so converted damage keeps all of its types' modifiers. LE uses the same additive-increased / multiplicative-more structure. Its conversion rules ("converted damage benefits from both" vs not) must be confirmed for LE; encode them in one function, not scattered through the code.
5. **Declarative config options** (`{id, type, label, visibleIf, apply(value) => mods}`) plus **"conditionsUsed" tracking** so the config UI only shows conditions that some mod in the build references, with "used by: <mod list>" tooltips. A very high-value UX feature.
6. **Declarative calcs-tab layout** (sections → rows → output key + breakdown key + mod names to tabulate) and **generic mod attribution tables** built by re-querying the store with the same context (`Tabulate`), grouped by source type, with per-source totals.
7. **What-if calculation via an `override` input** (add/remove nodes, replace item in slot, toggle condition), run in a background worker. This powers node-power heatmaps, "+X% DPS" tooltips on every tree node, affix and item, upgrade search, and trade weightings.
8. **Calc modes** (unbuffed / buffed / in-combat / effective vs enemy) as conditions on mods rather than code branches.
9. **Data versioned per game patch** (`TreeData/<ver>`), with builds remembering their version and offering conversion.
10. **Headless engine + system tests that drive the real model**, custom-mod text as test fixtures, golden-build snapshots, and CI that regenerates generated data and fails on diff.
11. **Template + directive data files** that keep hand-written mechanics overrides next to generated data and survive regeneration. Better still: generated JSON plus a separate, *keyed* overrides file merged at build time.
12. A short, shareable **build code** (deflate + base64url of the canonical build document) and a list of paste-site adapters (`matchURL` / `downloadURL` / `postUrl`).

### 10.2 Patterns to avoid or improve

1. **Hand-written breakdown strings parallel to the math.** In PoB every formula is coded twice: once to compute, once as `s_format` strings. They drift, and many outputs have no breakdown at all. **Do instead**: compute with a tiny **traced-value / expression-graph** layer. Each calc step creates nodes like `mul(label("base", sum(BASE mods)), label("increased", 1+sum(INC)/100), label("more", prod(MORE)))` that *evaluate and record themselves*. The UI renders the tree (collapsible, with each leaf linking to its contributing mods and sources). Disable tracing during bulk what-if calcs for speed (PoB does the same with `breakdown == nil`). This is the single most important improvement for the "show users exactly how each number is derived" goal.
2. **English-text parsing as the primary mod ingestion path.** PoB ships a ~7k-line regex cascade plus a ~4 MB pre-baked ModCache, because PoE data and items flow as text. For LE, **key affixes, nodes and uniques by game IDs and structured stat properties** taken from the extracted game data (property + modifier type + tags + value range), and map game-property → engine-mod in a single table (the `SkillStatMap` equivalent). Keep a *small* text parser only for user-typed custom mods and maybe pasted tooltips. Unsupported mods should then be an explicit list of unmapped IDs, not unparsed strings.
3. **Untyped variadic APIs** (`Sum(type, cfg, ...names)`; the `More("MORE", cfg, ...)` bug shipped in both forks). Use a typed language and object parameters: `store.sum({ kind: "INC", stats: [...], ctx })`. Make stat IDs and tag kinds **enums / discriminated unions** checked at compile time. PoB's thousands of free-form stat name strings are a constant source of typos.
4. **Fixed-width bitmask flags.** PoE2 overflowed 32 bits and had to emulate 64-bit ops. Use tag **sets** (bitsets of arbitrary width, or interned small-int sets) generated from the game's tag list.
5. **Implicit, hand-ordered pipeline with restarts** (`initEnv` recursion, "merge keystones again", comments about ordering). **Do instead**: explicit phases with declared dependencies (e.g. attributes → pools → reservations → buffs → defences → offence). A `PerStat` read of a stat not yet computed should raise a dev-time error, not silently read 0. Consider a small dependency graph or at least assertions.
6. **Global mutable state** (`data`, `GlobalCache`, `main`, `build` globals) and UI-coupled model code (tabs own model state; `ConfigOptions.apply` pokes `build.configTab.varControls`). Keep the **engine pure**: `calculate(buildDocument, gameData, options) → {outputs, traces}`, no UI imports. That makes it runnable in a web worker, in Node tests, and on a server for sharing previews.
7. **Hard fork per game.** If you ever support multiple LE seasons or major mechanic versions, version the **data** and keep **one engine** with feature switches, rather than copying the codebase.
8. **Golden tests excluded from CI and pinned to ancient versions.** Run snapshot tests by default and regenerate them deliberately on patch updates (with a diff review). Add **in-game verified fixtures** (screenshots / character-sheet numbers) as a separate "ground truth" suite. LE's in-game character sheet shows many final stats, so this is feasible.
9. **Lua + SimpleGraphic host** is legacy. It means a custom C++ renderer, a hand-built widget toolkit (~40 control classes), Windows-first distribution, no web version, and a niche language for contributors.

### 10.3 Suggested modern stack for a Last Epoch planner

- **Language**: **TypeScript** end to end (largest contributor pool, runs in browser + Node). Optionally a Rust core compiled to WASM later if what-if calcs get heavy; profile first. The JS engine should handle thousands of full recalcs per second if the store is indexed by stat ID like PoB's `ModDB`.
- **Engine package** (`packages/engine`): pure functions, zero DOM. Contents:
  - typed `Mod`, `Tag`, `StatId` enums generated from data
  - `ModStore` with parent chain and `sum` / `more` / `flag` / `override` / `list` / `tabulate`
  - traced-value math
  - phase pipeline
  - `override`/what-if API
  - Runs in a **Web Worker** pool for node-power / affix-power sweeps.
- **Data package** (`packages/data`): an extraction pipeline in Python or TS (LE is a Unity/IL2CPP game; data comes from asset extraction, e.g. AssetRipper/UABE-style tools and community datamines). It produces **versioned JSON** (`data/<patch>/skills.json`, `affixes.json`, `uniques.json`, `passives/<class>.json`, `skilltrees/<skill>.json`, `idols.json`, `blessings.json`) validated by **zod/JSON Schema**, plus a hand-curated `overrides/` (keyed by game ID) for mechanics the raw data doesn't express. Generated files are committed, and CI checks regeneration is deterministic.
- **UI**: React (or Svelte/Solid) + a canvas/WebGL renderer (**PixiJS**) for the passive and skill trees. Breakdown popovers render the trace tree. **Tauri** wrapper if a desktop app is wanted (offline use, local save-file import).
- **Build document**: versioned JSON (`{schemaVersion, gameVersion, class, mastery, passives, skills:[{id, specTree}], equipment, idols, blessings, config}`). **Build code** = brotli/deflate + base64url. Optional short-link service.
- **Import**: LE has no public character API comparable to GGG's. Plan on importing from **local save files**, from community planner links (if their formats are documented/permitted), and manual entry. Treat any import format as an adapter that produces the build document. The save format should be verified before committing to this (offline character saves are reportedly JSON-like local files).
- **Tests**: Vitest. Engine unit tests per mechanic, custom-mod text fixtures, golden build snapshots run on every PR, and an "in-game verified" suite.

### 10.4 LE-specific pitfalls to plan for

- **Per-skill specialization trees** behave like PoB's support gems + per-skill `statMap`. Their nodes often *change skill behaviour* (convert damage type, add tags, change base damage, add a triggered sub-skill). Model nodes as mods on a **skill-scoped store** and support **tag mutation** (adding/removing skill tags changes which global mods apply). PoB handles analogous things with `SkillType` tags and `ExtraSkillMod`, but ad hoc.
- **Added damage effectiveness**: LE skills scale flat added damage by a per-skill effectiveness value (same idea as PoB's `damageEffectiveness` / `baseMultiplier` on gem levels).
- **Damaging ailments as stacking DoTs** (Ignite, Bleed, Poison, plus damage-over-time skills), "chance to apply" above 100% giving multiple stacks, and **shred** debuffs (armour/resistance shred stacks on the enemy). Model these as enemy-actor multipliers and conditions (PoB's `enemyDB` + `Multiplier:*Stack` pattern, the config "# of stacks" options).
- **Triggers** ("cast X on hit / on kill / when you use Y") are common in LE item and node design. Budget early for a general trigger-rate subsystem; PoB's `CalcTriggers` became a 1.6k-line special-case list.
- **Minions and companions** need full actor calcs (own stores, own skills, "minions gain X" wrappers), as PoB does.
- **Affix tiers, sealed and exalted affixes, Forging Potential, legendary potential transfer, set items, idol grid shapes, and blessings**: represent them as item-structure data (affix ID + tier + roll fraction), not text. Render text from data for display.
- **Patch churn**: LE rebalances often. Keep data versioned, make builds remember `gameVersion`, and give the engine a hook for per-version mechanics changes, so old builds stay viewable.
- **Breakdown explosion**: if every number is traced, keep traces lazy (build the trace only for the stat the user is inspecting, by rerunning the calc with tracing on for that stat), as PoB only builds breakdowns in MAIN/CALCS mode.
