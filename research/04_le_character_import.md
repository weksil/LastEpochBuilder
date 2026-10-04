# 04 - Last Epoch character import: options and feasibility

Date of research: 2026-10-03. Game client on this machine: 1.3.6 (`version.txt`).
Method: web research, inspection of lastepochtools.com public HTML/JS, read-only inspection of the local save folder and Player.log on this machine.
Confidence tags: [verified] = observed directly here, [sourced] = from a cited page, [inferred] = my deduction, [unverified].

## TL;DR

* There is **no public official API**. EHG has a REST "Game Data API" that is "limited access to partners" and used by the official website. [sourced]
* **Online characters live only on EHG servers.** They are not cached locally. [sourced + verified]
* lastepochtools.com (LE Tools) and Maxroll import online characters by **account name + character name** through a partner/privileged server-side API. A third party cannot replicate this without EHG partnership. LE Tools' own backend (`import_character.php`) is not a documented public endpoint.
* **Offline characters** are plain JSON on disk (5-byte `EPOCH` prefix, no encryption or compression). Items are compact binary byte arrays that need a game-database mapping to decode.
* Best realistic strategy: (1) offline save file drag-and-drop parser, (2) import from an LE Tools build link, (3) manual recreate. Pursue a partnership/API access with EHG (or LE Tools' Dammitt) for true account import. Never memory-read or reimplement the game's login.

---

## 1. Official API / ladder / armory

| Item | Finding |
|---|---|
| Public API | None. EHG staff (Kain, Discord, ~Jan 2025): "The API is not publicly available and is currently limited access to partners during development." [sourced: forum.lastepoch.com/t/api-for-developers/74843] |
| Official docs | Support page "The Game Data API Is Not Yet Available" (support.lastepoch.com). Planned: REST + JSON, tree node names/descriptions/connections etc. Already used by the official website. [sourced via search snippet; page itself returned 403 to my fetch] |
| Staff confirmation of partner use | EHG staff `Dammitt` (same handle as the LE Tools author) said there was "maintenance for API service on LE servers ... inability to import online characters in LE Tools". [sourced: forum thread "LE Planner import not working after update"] |
| Official ladder web | lastepoch.com/arena-ladder (Nuxt SPA) - arena ladder only; no gear/build pages found. [verified shell only] |
| Backend hosts the client talks to | From this machine's Player.log: `login.prod.api.lastepoch.com` (Steam-ticket login `/auth/loginwithsteam`, TOS accept), `game-data.prod.api.lastepoch.com/Character/CharacterList` (flag `useBackendCharacterList: true`), `player-storage.prod.api.lastepoch.com` (diagnostics), Azure Cosmos DB `lastepoch-data-*.documents.azure.com`. [verified] |
| Unauthenticated call to CharacterList | HTTP 401. [verified] Needs the player's game session token (Steam/PlayFab auth). |

**Implication.** The endpoints exist but are for the authorised client (and partners). Calling them with a player's Steam/PlayFab token from our own app = "connecting to servers through software other than the authorised client" -> ToS violation and account risk. Do not do this.

## 2. How LE Tools and Maxroll do it

### LE Tools (lastepochtools.com)
* Announcement 2023-09-22 by Dammitt: "Online character import and Character Profiles". Import button in the planner's left toolbar, two modes: **online** (account name + character name) or **offline** (upload save file). [sourced + verified in planner.js]
* Mechanics, read from the public `/planner/js/planner.js` [verified]:
  * Online: `POST {host}/import_character.php` with form data `{accountName, charName}`. Server returns `{buildInfo: {data, data_version}, buildId}`. If the data version equals the planner's version it loads directly, else it redirects to `/planner/?char_build=<buildId>`.
  * Offline: multipart `POST {host}/upload_save.php` with the save file; the server parses it and returns `{data}` (a planner build object). **Parsing is server-side**, so the item-decoding logic is not public.
  * Planner data can be re-read from `/api/internal/planner_data/<id>` (internal, undocumented; do not depend on it).
* The account name (forum display name / login account) is the key. The partner API returns equipment, idols, blessings, passive tree, skill trees, quest progress. [sourced]
* Imported online characters get a **green "verified" checkmark** (gear untampered because server-held). Quest data is imported so passive/attribute points and idol slots are correct. [sourced]
* Character Profiles: `https://www.lastepochtools.com/profile/<account>` and `/profile/<account>/character/<name>`; reachable from Ladders. Shows basic info, cycle, HC/Solo, last fetch time, equipment, idols, blessings, stats, skill trees, passive trees. Refreshed lazily when opened, **no more often than every 2 hours**. [sourced]
* LE Tools states it is "not affiliated with Eleventh Hour Games"; its data comes from partner API access.
* LE Tools has its own **ladders page** (`/ladders/`) served from its own backend, not from a public EHG ladder endpoint. [verified shell; not reverse engineered further]
* No browser extension, overlay or companion app is involved: type names, or drag a save file. [verified]

### Maxroll (maxroll.gg/last-epoch/planner)
* Same two modes: online by Account Name ("Search" lists all online characters of that account), offline by dropping the save file from `AppData\LocalLow\...\Saves`. Imports Equipment, Passives, Skill Specializations, Blessings, Idols. Maxroll states "The character import API is public, so you're able to import anyone's build". [sourced: maxroll.gg/last-epoch/news/last-epoch-planner-feature-update-1]
* "Public" means any account can be looked up (like PoE profiles), not that EHG offers a public API. Maxroll very likely uses the same partner access. [inferred]
* Forum reports: Maxroll's import stayed broken longer than LE Tools' after an update, implying a separate integration. [sourced]

### Other planners
* Musholic/PathOfBuildingForLastEpoch (lastepochplanner.com): imports **offline characters** and **LE Tools planner builds**; only ~43% of mods recognised by its parser. [sourced]
* JLC827/last-epoch-build-as-plaintext: scrapes LE Tools planner page state through headless Chrome (`window.buildInfo`, `window.itemDB`) - fragile and ToS-grey. [sourced]

## 3. Local save files

### Location and files [verified on this machine]
`%USERPROFILE%\AppData\LocalLow\Eleventh Hour Games\Last Epoch\Saves` contains only stale Feb-2024 beta files:

```
1CHARACTERSLOT_BETA_0 (+ .bak)         10,226 B  one hardcore level-12 offline char (2024-02-23)
Epoch_Local_Global_Data_Beta (+ .bak)     174 B  list of stash names
STASH_CYCLE_2_0 / _1 (+ _TAB_0)      0.2-1.1 KB  stash tabs, gold, shards
steam_autocloud.vdf
```
`D:\` exists but holds no Last Epoch data. No 1.x-era offline character is present, so I could not inspect a current-format file with a real build.
Other files in the parent folder: `Player.log`, `Player-prev.log`, `Filters\*.xml` (loot filters), `owned_cosmetics.json`, `online_cosmetic_data_equips.json` (cosmetics only, no gear), `temp` (a loot filter XML), `version.txt` = `1.3.6`.

### Format [verified]
* `EPOCH` (5 ASCII bytes `45 50 4f 43 48`) immediately followed by **plain UTF-8 JSON**. No encryption, compression or checksum observed. Parse with `JSON.parse(text.slice(5))`.
* File name pattern: `1CHARACTERSLOT_<BETA|...>_<slot>`; `.bak` is the previous write.
* Community save editors exist (FearLess Cheat Engine thread). Game updates (1.0.3+) changed internals and broke third-party tools. [sourced]

### Schema (redacted real sample, top-level keys)
```jsonc
// file = "EPOCH" + JSON
{
  "characterName": "<REDACTED>", "level": 12, "slot": 0, "currentExp": 1905,
  "hardcore": true, "died": false, "deaths": 0, "masochist": false,
  "characterClass": 3,              // numeric class id; mastery in "chosenMastery"
  "chosenMastery": 0,
  "cycle": 2, "competitiveCharacterVersion": 17, "version": 0, "seqNo": 568,
  "savedItems": [                   // ALL items: equipped, bag, idols, blessings...
    { "itemData": null,
      "data": [2,4,1,4,0,61,20,192,20,4,17,247,41,16,8,181,17,248,110,0,13,151,0],
      "inventoryPosition": {"x":0,"y":4},
      "quantity": 1,
      "containerID": 1,             // 1 = bag; other ids = equipment slots / idol grid / etc. (mapping needed)
      "formatVersion": 2 } ],
  "savedCharacterTree": {           // passive tree
      "treeID": "", "version": 2,
      "nodeIDs": [1,2,55], "nodePoints": [2,5,2], "unspentPoints": 0 },
  "savedSkillTrees": [              // one per skill used
      { "treeID": "ws54hm", "slotNumber": 1, "xp": 16551, "version": 2,
        "nodeIDs": [30,9,8], "nodePoints": [2,1,1], "unspentPoints": 0, "abilityXP": 0.0 } ],
  "abilityBar": ["ts50pl","ss37kl","bg36nl"],   // equipped skill ids (5 slots)
  "savedQuests": [ { "questID":127, "questStepID":678, "state":0, "completeObjectives":[623,624] } ],
  "blessingsDiscovered": [], "monolithRuns": [], "factions": {}, "respecs": 0,
  "unlockedWaypointScenes": ["Z22"], "sceneProgresses": [],   // plus many progression fields
}
```
### Data completeness from a save

| Data | In save? | Notes |
|---|---|---|
| Class / mastery / level | Yes | numeric ids, need enum map |
| Passive tree allocation | Yes | `nodeIDs` + `nodePoints` (node id -> points) |
| Skill selection | Yes | `abilityBar` string ids (e.g. `ts50pl`) |
| Skill specialisation trees | Yes | per `treeID`, node ids + points |
| Equipment, idols, blessings | Yes, as items in `savedItems` | by `containerID`; encoded in `data` bytes (container mapping [inferred]) |
| Affix IDs / tiers / rolls | Yes, **inside `data` bytes** | see below |
| Unique/set roll values | Yes (bytes) | unique rolls are 0-255 bytes mapped to ranges |
| Quest progress | Yes | needed for point / idol-slot totals |
| Blessings | Items; `blessingsDiscovered` is only discovery | |

### Item byte-array format
Community docs (FearLess save-editor thread) for older formats [sourced]: `data[0]` format flag (0 = instability, 1 = forging potential), `[1]` base type, `[2]` base id, `[3]` rarity/quality, `[4-6]` implicit rolls, `[7]` instability/forging potential, `[8]` affix count (or unique/set id), then 3 bytes per affix `(tier, affix id, roll)` at offsets 9-11, 12-14, ... Roll is 0-255 (255 = max) mapped to the real stat range through game data.

**Caveat:** my sample has `data[0] = 2` and `formatVersion: 2`, and 23-byte items, so the current layout differs from the documented v0/v1 layout. The exact v2+ layout is [unverified] and must be reverse-engineered or taken from an existing parser (needs a current-version save with known gear to validate). Affix id -> name/range tables come from game data; LE Tools serves such a DB as `/data/<ver>/db/js/*.js` (the site's data - ask permission before reusing), or it can be extracted from the client with Unity asset tools (legal review needed).

### Online characters cached locally?
No. Forum: online saves "are fully online, on EHG servers". Verified here: no online-character JSON anywhere in LocalLow (only cosmetics JSON). [sourced + verified]

## 4. Player.log

* Location `...\LocalLow\Eleventh Hour Games\Last Epoch\Player.log` (+ `Player-prev.log`; only the last two sessions are kept). [verified]
* Content: Unity startup, backend config JSON, region mapping, errors/stack traces, crafting-attempt debug lines (affix shard names), loot-filter messages. **No gear or character snapshot.** Searches for `characterName`, `savedItems`, `profile` gave 0 hits. [verified]
* It does contain backend endpoint URLs and some "token" strings (28 lines; not printed). Treat logs as sensitive; never upload them.
* Useful at most as a weak signal (game version), not for import.

## 5. Other approaches

| Approach | Verdict |
|---|---|
| In-game build codes | None exist; only loot-filter import/export in-game. Feature request thread exists. [sourced] |
| Import from LE Tools build link | Feasible, depends on LE Tools' undocumented endpoints; ask Dammitt. Musholic's PoB fork already imports LE Tools builds. |
| Screenshot / OCR | Works outside the game process; low fidelity (exact rolls only visible with detail tooltips), heavy effort. EHG treats OCR as undefined. Not primary. |
| Memory reading / DLL injection / packet sniffing | **Not recommended - bannable.** ToS prohibits modifying the client or its data and connecting through non-authorised software; EHG explicitly prohibits automation reacting to game state. [sourced] |
| Reusing the game's auth / CharacterList endpoint | **Not recommended** - needs the player's session token; breaks ToS and is a credential-handling risk. |
| Companion app reading the save and opening a URL | Offline only, low risk (user's own file). But browser drag-and-drop gives the same result with zero install; the File System Access API (Chromium) can remember the Saves folder handle for one-click re-import. |
| Headless-scrape LE Tools | Fragile, probably against its terms; avoid. |

## Comparison matrix

| Option | Items+rolls | Idols | Blessings | Skill trees | Passives | Online chars | Offline chars | ToS risk | Effort |
|---|---|---|---|---|---|---|---|---|---|
| Official API (partner) | full | yes | yes | yes | yes | yes | no | none (as partner) | low technically, **gated by EHG** |
| Save file parser (drag/drop) | full once item decoder done | yes | yes | yes | yes | **no** | yes | none (own file) | medium-high (item decode + id maps) |
| LE Tools link import | full | yes | yes | yes | yes | yes (via their import) | yes | low; relies on their goodwill | medium |
| Player.log | none | no | no | no | no | - | - | none | n/a |
| OCR / screenshot | partial | partial | partial | partial | partial | yes | yes | grey | high |
| Memory reading / injection | full | yes | yes | yes | yes | yes | yes | **high (bannable)** | high |
| Manual recreate | by user | by user | by user | by user | by user | yes | yes | none | none |

## Recommended strategy

**Primary (ship first): offline save-file import, fully client-side.**
* Drag-and-drop `1CHARACTERSLOT_*` (or pick the Saves folder) in the browser; parse `EPOCH` + JSON locally, nothing uploaded.
* Milestone 1 (cheap): class/mastery, level, passive tree, skill selection, skill trees (all plain JSON).
* Milestone 2: item decoding (`savedItems` -> gear/idols/blessings by `containerID`) using our own game database (see other research docs), validated against a current-version save with known gear.

**Fallback 1: import from an LE Tools planner link** (covers online characters without an EHG relationship, but dependent on LE Tools formats and good faith). Contact Dammitt first.

**Fallback 2: guided manual build** (class, mastery, trees, item picker) plus pasting an LE Tools / Maxroll link for the static parts.

**Strategic ask (in parallel, low cost):** apply to EHG for Game Data API partner access (Discord/email per the forum thread). Account-name import is then a one-field UX identical to LE Tools/Maxroll. Until approved, do not call EHG endpoints directly.

**Do not do:** memory reading, injection, packet capture, replaying Steam/PlayFab tokens, headless-scraping LE Tools.

### Minimum-click UX flow
1. User clicks **Import** in the planner.
2. Tab "From save file": button "Pick Saves folder" (handle remembered via File System Access API) or drag-and-drop; hint with the path `%USERPROFILE%\AppData\LocalLow\Eleventh Hour Games\Last Epoch\Saves` and a copy button.
3. Character list appears (name, class, level, HC/Solo tag). One click on a character imports it and opens the planner populated. About **2-3 clicks** the first time, 1-2 afterwards.
4. Tab "From account name" (enabled only after partner API access): account + character -> import.
5. Tab "From link": paste an LE Tools URL.
6. Show warnings for anything not decoded (unknown affix id) instead of failing; mark save-imported builds "unverified" (offline saves are editable), as LE Tools does.

## Sources
* https://forum.lastepoch.com/t/api-for-developers/74843
* https://forum.lastepoch.com/t/character-files-for-online-characters/60191
* https://forum.lastepoch.com/t/le-planner-import-not-working-after-update/75746
* https://forum.lastepoch.com/t/third-party-software-tos/59916
* https://www.lastepochtools.com/news/article/site-update-online-character-import-and-character-profiles
* https://maxroll.gg/last-epoch/news/last-epoch-planner-feature-update-1
* https://support.lastepoch.com/hc/en-us/articles/1260805256609-The-Game-Data-API-Is-Not-Yet-Available
* https://fearlessrevolution.com/viewtopic.php?t=17089 (save editor thread)
* https://github.com/Musholic/PathOfBuildingForLastEpoch ; https://github.com/JLC827/last-epoch-build-as-plaintext
* https://lastepoch.com/policy/tos/
* Local inspection: `%USERPROFILE%\AppData\LocalLow\Eleventh Hour Games\Last Epoch\` (Saves, Player.log) and lastepochtools.com `planner.js` (read-only).
