# Town Analysis

This note collects the repository-local evidence for town NPCs, doors, shops, and other interactive town objects. It stays analysis-only and does not change C++ code.

## Main Evidence

- `asm/town.asm`
- `asm/town.inc`
- `asm/game.asm`
- `tools/mdtviewer/decoder.py`
- `tools/mdtviewer/models.py`
- `tools/mdtviewer/viewer.py`
- `tools/mdtviewer/archives/sar_reader.py`
- `docs/mdt_analysis.md`
- `docs/Spritegrp_analysis.md`
- `docs/collision_analysis.md`
- `game/0/mman.grp`
- `game/0/cman.grp`
- `game/0/tman.grp`
- `game/0/kingpro.bin`
- `game/0/omoypro.bin`
- `game/0/armrpro.bin`
- `game/0/bankpro.bin`
- `game/0/churpro.bin`
- `game/0/drugpro.bin`
- `game/0/innapro.bin`
- `game/0/town.bin`

## Which Files Define Town NPCs Or Objects

- `asm/town.inc` defines the town runtime layout:
  - `town_descriptor_addr`
  - `town_map_width`
  - `town_name_rendering_info`
  - `town_transition_table`
  - `doors_array_addr`
  - `npc_conversations_addr`
  - `npc_array_addr`
  - `npc_patrol_boundaries`
  - `word_C015`
  - `town_tiles`
- `asm/town.asm` uses those pointers at runtime and contains the logic for NPC animation, NPC collision, conversations, door activation, and town indoor transitions.
- `tools/mdtviewer/decoder.py` and `tools/mdtviewer/models.py` mirror the same town structures in Python:
  - town doors are `3` bytes each
  - town NPCs are `8` bytes each
  - NPC text pointers are a separate pointer array
- `tools/mdtviewer/viewer.py` confirms the same model by exposing the town doors, NPCs, and per-NPC dialogue strings; the confirmed placement row still comes from the assembly evidence below.

## Where NPC And Door Positions Come From

- Town map tiles themselves live at `+0x17` in the MDT runtime layout.
- The town door table lives at `+0x09`.
- The NPC text pointer array lives at `+0x0D`.
- The NPC array lives at `+0x0F`.
- The town descriptor lives at `+0x00`.
- The code treats NPC and door placement as absolute town columns, not as tile graphics hidden inside the map.
- The confirmed town Y anchor is the head-level row at `town_tiles + 5` (`row 5` in the 8-row town grid).
- Both the NPC and door tables are X-only; their markers should be drawn on that shared head-level row rather than on the provisional bottom row.
- `save_head_level_tiles_in_npcs` and `restore_head_level_tiles_from_npcs` show the runtime placement model clearly:
  - the visible map row under an NPC is replaced with `0xFD`
  - the original tile is stored in the NPC record
  - the tile is restored later when the NPC moves or the scene changes
- `town.inc` says `town_head_level_tiles` is `town_tiles + 5`, which matches the row that holds the NPC markers and the shared debug placement row.

## Which GRP Files Are Likely Used For Town Characters

- `mman.grp` and `cman.grp` are the town NPC sprite banks.
- `town_descriptor_addr[1]` selects between those two NPC banks.
- `tman.grp` is the town hero sprite bank.
- `asm/town.asm` loads `TMAN.GRP` in `load_hero_town_sprite`.
- `asm/game.asm` also loads `mman.grp` or `cman.grp` through the town transition path.
- The `tools/grpviewer` notes agree with that split:
  - `mman.grp` and `cman.grp` are 16x24 NPC sheets
  - `tman.grp` is the 16x24 town hero sheet
- `game/0` also contains the likely indoor scene assets for town buildings:
  - `king.grp`
  - `omoya.grp`
  - `armor.grp`
  - `bank.grp`
  - `church.grp`
  - `drug.grp`
  - `inn.grp`

## How Shops, Doors, And Interactions Appear To Be Triggered

- Town doors are checked in `town_up_pressed`.
- The hero's absolute X position is compared against the door table.
- If the X coordinate matches, the destination type in `td_dest_id` decides what happens.
- `td_dest_id` values `0` through `7` load an indoor town scene from the `kingpro.bin` family:
  - king
  - princess
  - sage
  - weapon shop
  - magic shop
  - church
  - bank
  - inn
- `td_dest_id` `8` branches to dungeon transition logic.
- `td_dest_id` `FF` is treated as the Falter special-building warp path.
- Town conversations start from NPC contact:
  - `hero_spacebar_interaction` starts a nearby NPC conversation when the hero is next to a valid NPC
  - `check_special_npc_conversation` starts a special dialogue when the hero is two tiles ahead of a flagged NPC
- `start_npc_conversation` uses `NPC.n_id` to index the pointer array at `npc_conversations_addr`.
- `render_dialog_text` treats control codes `0x81` through `0x8B` as shop or quest triggers.
- The confirmed control-code behavior is:
  - `0x81` shows a yes/no dialog
  - `0x83` updates quest state and calls `init_c015_obj_if_exists`
  - `0x89` opens a purchase confirmation dialog
  - `0x8B` also calls `init_c015_obj_if_exists`
- `init_c015_obj_if_exists` consumes the `word_C015` object table and copies data blocks into memory when the current state allows it.

## What Appears To Be An Object Table

- `word_C015` is the strongest candidate for a scripted town object table.
- The routine that uses it is not tile-based placement; it is a memory-patch/copy loop with a `FFFF` terminator.
- That makes it look more like a town state/object script table than a plain world-map entity list.
- The current Python MDT decoder does not parse this table yet.
- `town.inc` shows `word_C015` as a town runtime pointer, and the Muralla town comment points it at `c705` with a `FFFF` terminator.

## What Is Confirmed By Repo-Local Evidence

- Town maps are 8 tiles tall.
- Town NPCs and town doors come from explicit MDT pointer tables.
- Town NPCs are not embedded as map graphics.
- NPC and door X positions are stored as town columns.
- Their Y placement is derived from the town head-level row, not from a stored per-entity Y field.
- NPC text is separate from NPC placement.
- NPC collision uses the non-passable NPC flag.
- Town NPC sprites are `mman.grp` and `cman.grp`.
- Town hero sprites are `tman.grp`.
- Town indoor building transitions are selected by door type and load the `*pro.bin` building resources.
- Dialog control codes drive at least some shop and quest behavior.

## What Remains Uncertain

- The exact contents and semantics of `word_C015`.
- Whether every town uses the same object patch table layout.
- Whether every shop or special building is fully driven by the same control-code path, or whether some towns have extra overrides.
- The exact meaning of every NPC ID beyond being a dialogue lookup key.
- The full relationship between indoor `*.bin` building resources and the `*.grp` files listed in the archive tables.

## Next Minimal C++ Implementation Step

- Add a read-only town scene data loader in C++ that parses:
  - the MDT town header
  - the town door table
  - the NPC text pointer array
  - the NPC array
  - the `word_C015` pointer
  - the selected town NPC GRP family
- Keep it data-only.
- Do not spawn NPCs.
- Do not add shop logic.
- Do not add dialog UI.
- Do not add gameplay behavior yet.
- The goal is to surface the town entities and script pointers in a structured way before any interactive implementation starts.
