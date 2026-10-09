# 09 - Navigation map of the game dump (where to look, how to find things fast)

Client 1.5.0 (Unity 6000.4.8f1, IL2CPP). Everything below is read-only data extracted from the game. `dump/` and `tools/` are not
published (see `.gitignore`). The disk is slow: a repo-wide `grep -r` over `dump/decomp` times out (minutes), so always start from an
index (section 2) and then open or grep ONE file or a small directory. Use the Grep tool with a narrow `path` + `glob`.

## 1. Map of `dump/`

```
dump/
  decomp/LE.dll/<Class>.c            Ghidra pseudo-C of the game code, ONE FILE PER CLASS (6390 files; nested = Outer+Inner.c)
  decomp_extra/                      a few methods that failed or were skipped in the main pass (MageTree__updateMutator.c,
                                     CharacterMutator__applyModifiersBeforeExternalStatsCalculation.c, *Tree__updateMutator.c, ...)
  cs/DiffableCs/LE/<Class>.cs        class layouts: fields with OFFSETS, types, consts, method signatures (no bodies)
  isil/IsilDump/LE/<Class>.txt       ISIL (IR) per class, 7027 files; used by tools/extract/field_tracer.py
  inspector/symbols.tsv              address -> symbol -> "LE.dll/Class :: Signature" (all methods, F = function, C = alias)
  inspector/metadata.json            il2cpp metadata (method infos, signatures); inspector/cpp/appdata/il2cpp-types.h = C types
  assets/                            AssetRipper export: index.tsv, guid_index.tsv, bundle_index.jsonl, json/ (ScriptableObject JSON)
  mini_game/                         the game binaries (GameAssembly.dll, Last Epoch_Data/il2cpp_data/Metadata/global-metadata.dat)
  dummydll/                          dummy assemblies of the game (types only)
  work_wave3/                        first extraction wave: ms/ (mutator-semantics batches, fields_all.json), mz/, pp/ (player
                                     property snippets: pp_<index>.txt + index.json), trees/ (<Class>Tree.json = tree node -> field
                                     writes), ap_readers*.json (readers of AbilityProperty fields), abid.json, probe/lift scripts
  work_wave4/                        second wave: traces/ (per skill-mutator field: <Mutator>__<field>.txt, 459 files + index.json),
                                     traces_uniq/ (per unique-effect property: <ppIndex>__<name>.txt, 203 files), cards/, BRIEF*.md,
                                     TRACER.md (how the tracer works), out_*.json (agent results), cache/ (51 MB, deletable)
tools/extract/                       extraction scripts (field_tracer.py, extract_*.py, save_parser.py, ...), tools/ghidra_*, Cpp2IL
research/data/game/*.json            the DISTILLED game data the planner reads (abilities, trees, affixes, uniques, ...) - section 4
research/07*.md                      write-ups of what was found (index in section 5)
```

## 1a. Global index (SQLite) - use this first

`python tools/dump_index.py build` (about 1-2 minutes) writes `dump/index/dump_index.sqlite`: 6265 classes (bases, nesting), 60240
fields with offsets (from `cs/DiffableCs`), 39515 functions (class, signature, C name, address, file + line range, failed flag), the
field offsets each function dereferences (`derefs`, scaled by the pointer element size: `*(float *)(param_1 + 0x1d5)` with
`longlong *param_1` is byte offset 0xEA8) and the call graph between decompiled functions (`calls`). Queries (instant):

```
python tools/dump_index.py class   CharacterMutator
python tools/dump_index.py func    OnUpdateTick --class CharacterMutator     # by signature or C name substring
python tools/dump_index.py field   CharacterMutator.fireAura                 # name -> offset, type, declaring class
python tools/dump_index.py offset  CharacterMutator 0xEA8                    # offset -> field (walks base classes)
python tools/dump_index.py readers CharacterMutator.fireAuraChanceWhileMovingOrMeleeDoubleUnder3   # [--all]
python tools/dump_index.py callers CharacterMutator__OnUpdateTick_g__CastFireAura_2622_1
python tools/dump_index.py callees CharacterMutator_OnUpdateTick
python tools/dump_index.py show    CharacterMutator_OnUpdateTick --max-lines 400   # prints the pseudo-C by file + line range
python tools/dump_index.py addr    0x18265b470
```

`readers` is a heuristic (offset match restricted to the declaring class, its bases/derived/nested classes; `--all` lifts the
restriction): the pseudo-C does not name the class of an offset. It finds readers AND writers; read the hits. C function names are
`<Class>_<Method>`; compiler-generated lambdas / local functions look like `Class__Method_g__Local_<n>_<m>` (use the `func` search).
Misses: reads through a typed pointer whose declaration the heuristic cannot see are stored as byte offsets (may be wrong); calls
through il2cpp vtables/delegates are not in the call graph.

## 2. Recipes (question -> fastest path)

| I want to know | Do this |
|---|---|
| What a mutator field does, who reads it | `research/data/game/mutator_field_semantics_AL.json` (fields A-L) / `_MZ.json` (M-Z): entry per `{mutator, field}` with `semantic`, `formula`, `readers`, `confidence`. CharacterMutator fields are often NOT there (see next rows) |
| Trace of one skill-mutator field | `dump/work_wave4/traces/<Mutator>__<field>.txt` (header, copy chain, pseudo-C windows around each use, annotated ISIL). Any other field: `python tools/extract/field_tracer.py one <Mutator> <field>` (needs `build` once, ~12 s) |
| Trace of one unique-item property | `dump/work_wave4/traces_uniq/<ppIndex>__<name>.txt` (`index.json` maps them); PlayerProperty snippets: `dump/work_wave3/pp/pp_<index>.txt` |
| Offset / type of a field of class X | `dump/cs/DiffableCs/LE/X.cs` - grep `FieldName` in that one file; the line ends with `//Field offset: 0x...`. Pseudo-C reads it as `*(T *)(param_1 + 0x...)` |
| Where the code of method M of class X is | `dump/decomp/LE.dll/X.c`: every function is preceded by `// <address>  LE.dll/X :: <ReturnType> M(<args>)`. Grep `":: .* M("` in that file. A failed decompile is marked `/* decompile failed: ... */` (try `decomp_extra/`, or the ISIL file `isil/IsilDump/LE/X.txt`) |
| Who reads field F at offset 0x... | grep the offset (`+ 0xea8`, lowercase hex) in the candidate class files (the mutator itself, `CharacterMutator.c`, `AbilityStatsMutatorManager`, `Ability`, `PlayerHealth`...). Better: the tracer (`field_tracer.py one`) or the `readers` list of the semantics JSON |
| Address -> function name | `inspector/symbols.tsv` (TSV: kind, address, short name, signature) |
| What a constant is (`DAT_...`, float literals) | `tools/readconst.py` (reads GameAssembly.dll); the tracer prints `{=0.05}` constants |
| An ability's data (damage, tags, speed, subabilities) | `research/data/game/abilities.json` (`name`, `playerAbilityID`, `category`: player / nodeGranted / sub / minion / abilityIdOnly) |
| Skill tree node -> field writes | `research/data/game/skill_node_effects.json`, passive nodes: `passive_node_effects.json`, weaver: `weaver_node_effects.json`; raw tree code: `dump/work_wave3/trees/<Class>Tree.json`, `decomp_extra/*Tree__updateMutator.c` |
| Unique item effects | `research/data/game/unique_effects.json`, `uniques.json`; formulas `research/07i_unique_formulas.md` |
| Affix / idol / set / blessing / item procs | `affixes.json`, `idols.json`, `sets.json`, `blessings.json`, `item_procs.json` |
| Save-file format | `research/07e_save_format.md`, `tools/extract/save_parser.py` |
| An asset by name or GUID | `dump/assets/index.tsv`, `guid_index.tsv`; ScriptableObject JSON in `dump/assets/json/<Type>__<Name>__<id>.json` |

## 3. Code patterns worth knowing (seen in the dump)

- Mutator fields of passives/skill trees are written by `<Class>Tree.updateMutator` (`decomp_extra/*Tree__updateMutator.c`,
  `work_wave3/trees/*.json`) and consumed at cast time by `<Skill>Mutator.Mutate` / `mutateAbilityObject` / other readers.
- `CharacterMutator` carries the passive "character" fields: `public float <name>; //Field offset: 0x...` followed, for rate-limited
  effects, by `private float <name>CooldownIndex;` and (in the constant block) `private const float <name>Cooldown = <n>;`
  (example: `fireAuraChanceWhileMovingOrMeleeDoubleUnder3`, offset 0xEA8, `...Cooldown = 1`). What these do is established by
  reading the readers, not from the names.
- Player properties (`playerProperty*` consts in `CharacterMutator.cs`) are the PlayerProperty index used by uniques/affixes (SP 98).
- File naming in `traces/`: `<Mutator>__<field>.txt`; `index.json` has `status` (traced / dead / no_reader), `chain`, `readerMethods`.

## 4. Distilled data the planner reads (`research/data/game/`)

abilities, abilities_code_damage, ability_projectiles, ability_property_fields(_c), actor_scaler, affixes, ailments, attributes,
blessings, boss_attacks, boss_ward, character_mutator_init, classes (`data[...]` with defaultAbilities / knownAbilities /
basicAttackReplacer), conditional_defenses, global_player_properties, holy_aura_model, idols, item_procs, items, minion_actors,
minion_base_stats, monster_*, mutator_field_semantics_AL / _MZ, passive_node_effects, player_property_fields, sets,
skill_conversions, skill_node_effects, tree_art, tree_node_stats, trees, unique_effects, uniques, weaver_node_effects.

## 5. Write-ups (`research/`)

01 PoB architecture; 02 formulas; 03 data sources; 04 character import; 05 dump verification; 06a stat system, 06b hit damage,
06c defence, 06d ailments, 06e speed and minions; 07a assets/core data, 07b abilities/trees, 07c skill mutators,
07d minions/uniques, 07e save format, 07f passive/weaver trees, 07g/07h mutator semantics A-L / M-Z, 07i unique formulas,
07j Ghidra deep dives (minions), 07k wave-4 verification, 07l Holy Aura, 07m final residue, 07n defence conversions,
08 build optimization. `dump/work_wave4/TRACER.md` explains the tracer in detail.

## 6. Rules for conclusions

Claims about game behaviour must quote the evidence (file + function/field + lines) and be tagged FACT or UNKNOWN. Tooltips,
node names and field names are not evidence of semantics (a name such as `...WhileMovingOrMelee...` only says where to look).
