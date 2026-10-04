# 07k — Wave 4: verification of ambiguous ("D?") records

Date: 2026-10-03. Agent model: Haiku (by user request), tools — Sonnet.

## What was done
1. **First attempt: Haiku searches code.** 5 batches mutators (458 fields) and 3 batches uniques (211 formulas). Result rejected. Haiku marked "D" finding field offset in code or prior base, but didn't trace actual use. Honestly verified 7 fields. Drafts in `dump/work_wave4/out_mut_*.json` and `out_uniq_*.json`.
2. **Tracer** `tools/extract/field_tracer.py` (Sonnet, ~25 s full run). Per mutator field builds copy chain (mutator → component or adapter, up to 2 hops) and cuts code all readers (Ghidra ±12 lines and ISIL with constants). On 80 fields with known answer 94% accuracy. Result: 432 fields traced, 18 dead, 8 no reader. Described in `dump/work_wave4/TRACER.md`.
3. **Haiku on fragments** (11 agents, `dump/work_wave4/BRIEF_TRACES.md`): one field per file, answer must contain literal quote of use.
4. **Auto-check** `tools/extract/validate_traces.py`. Answer accepted if quote found verbatim in code part of fragment, not copy line, formula not stub.

## Result per mutator fields (`mutator_field_semantics_{AL,MZ}.json`, merged `tools/extract/merge_wave4.py`)
| Label | Fields | Meaning |
|---|---|---|
| D | 4360 | verified earlier (07g/07h) |
| D(w4b) | 107 | field use confirmed by literal code quote; formula partly inferred beyond quote |
| dead(w4b) | 21 | field written by tree, never read (planner returns 0) |
| D? | 330 | unconfirmed; each has fragment `dump/work_wave4/traces/<Mutator>__<field>.txt` and note `w4b` |

Haiku claimed "D" on 208 more fields, checker rejected: 147 no quote in fragment, 61 quote — copy or stub formula.

## Uniques (wave 4c)
Tracer works for `CharacterMutator` fields too (script `tools/extract/trace_uniques.py` → `dump/work_wave4/traces_uniq/`). 211 unconfirmed formulas got 190 fragments; 12 fields no reader, 9 effects (potions, companions) no field in `CharacterMutator`. Haiku (7 agents, `BRIEF_UNIQ_TRACES.md`) analyzed fragments, checker ran `validate_traces.py traces_uniq ...`, merged via `merge_wave4_uniq.py` (backup: `dump/work_wave4/unique_effects.before_w4c.json`).

| Label (PlayerProperty indices, 359 total) | Count |
|---|---|
| D (07i) | 116 |
| D(const) (07i: code constants, tooltip condition) | 32 |
| D(w4c) (use confirmed by code quote) | 147 |
| D? | 64 |

## Did not change
- **Holy Aura:** Haiku's preview (`dump/work_wave4/holy_aura.md`): active buff = value × 2.0 × (1 + effect), passive aura no ×2. Needs verify.

## Finding on models
Haiku fits only for interpreting pre-cut fragments under mandatory quote verification. Solo code search — doesn't perform: claims verify without doing it.


## Cleanup (waves 4d, 4e, final) — all values closed
- **4d, cards** (`tools/extract/make_cards.py`, `merge_cards.py`). Script picks numbered-use lines from fragment, Haiku picks numbers and writes formula, quote programmed in. Stub formulas ("v", "acc[...]", bare tree formula) not accepted. Result: +218 mutator fields, +35 unique formulas.
- **4e, deep cards** (`TRACE_DEPTH=4`, `trace_remaining_deep.py`, `make_cards_deep.py`). +77 fields, +16 formulas. One Haiku batch (all formulas "v") rejected, redone.
- **Final, Sonnet** (`dump/work_wave4/out_final_residue.json`, report `07m_final_residue.md`). Last 46 values Haiku thrice couldn't do. Merged `merge_final_residue.py`: quotes checked via files, 7 values manually verified by orchestrator. Potion and companion effects read in `HealthPotion` and `Downed`, not `CharacterMutator`.
- **Holy Aura (Sonnet):** `07l_holy_aura.md`, `data/game/holy_aura_model.json`. Passive aura and active cast buff player and allies; effect ×(1+X), X only Covenant of Light; active buff replaces passive (result ×2, not ×3).

### Total
| | Total | Confirmed | Dead | D? |
|---|---|---|---|---|
| Mutator fields | 4818 | 4795 (D 4360, D(w4b) 107, D(w4d) 218, D(w4e) 77, D(final) 33) | 23 | **0** |
| Unique formulas (PlayerProperty indices) | 359 | 359 (D 116, D(const) 32, D(w4c) 147, D(w4d) 35, D(w4e) 16, D(final) 13) | — | **0** |

Caveat on labels w4b/w4c/w4d/w4e: literal code quote proves value really used at named place, but formula partly inferred by model. When implementing specific skill or item verify formula vs quote (fields `w4*` in JSON).
