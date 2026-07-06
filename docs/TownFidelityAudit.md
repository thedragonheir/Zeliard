# Town Fidelity Audit

Scope: compare the current town-mode C++ behavior against the original Zeliard assembly before gameplay changes.

Assembly inspected:
- `asm/town.inc`: `NPC STRUC`, `npc_array_addr`, `town_head_level_tiles`, `viewport_buffer`
- `asm/town.asm`: `update_npcs_and_render`, `save_head_level_tiles_in_npcs`, `restore_head_level_tiles_from_npcs`, `find_first_npc_at_x`, `find_first_npc_at_x_after_current`
- `asm/gtmcga.asm`: `sprite_descriptor_table_scanner`, `sprite_x_coordinate_lookup`, `sprite_compositor_dispatcher`, `npc_3_tiles_to_shadow_buffer`, `single_sprite_shadow_compositor`, `two_sprite_shadow_compositor`

Key conclusion:
- Town rendering is marker-driven. `town_head_level_tiles` is the row-5 overlay, NPCs are marked with `0xFD`, and the visible town pass walks the column buffer instead of a generic Y-sorted sprite list.

Confirmed NPC layout:
- `NPC STRUC` is 8 bytes: `n_x` at offset 0, `n_facing` at offset 2, `n_head_tile` at offset 3, `n_anim_phase` at offset 4, `n_ai_type` at offset 5, `n_flags` at offset 6, and `n_id` at offset 7.
- `npc_array_addr` points at the first NPC entry in a zero-terminated array. The terminator is `n_x == 0xFFFF`.
- `save_head_level_tiles_in_npcs` reads `town_head_level_tiles[x * 8]`, stores the original byte in `NPC.n_head_tile`, and writes `0xFD` back into the head-level row.
- `restore_head_level_tiles_from_npcs` restores the saved tile byte unless the saved byte itself is `0xFD`.

Live npc_array mirror:
- `TownNpcRuntimeRecord` now mirrors the confirmed `NPC STRUC` bytes in C++: `X` from `n_x`, `Facing` from `n_facing`, `HeadTile` from `n_head_tile`, `AnimPhase` from `n_anim_phase`, `AiType` from `n_ai_type`, `Flags` from `n_flags`, and `Id` from `n_id`.
- `TownNpcRuntimeView` is projected from that mirror before compositor dispatch, so the SDL path no longer reads the parsed MDT markers directly.
- `AiType` and `Flags` are represented in the mirror but remain zero-filled for now because the live AI-owned update path is still deferred.

Confirmed viewport buffer role:
- `viewport_buffer` is the town-pass staging buffer at `0xE000`.
- `render_town_tiles_28_columns` sets `DI` to `viewport_buffer` before the column walk, and `clear_6_hero_tiles_in_viewport_buffer` writes `0xFF` into the hero-adjacent cells to force redraw.
- The assembly uses the buffer as a dirty/comparison surface for the town pass; it is not the final screen surface.

Confirmed shadow-memory compositor flow:
- `render_town_tiles_28_columns` initializes `blit_cache`, walks each column, and routes row 5 through `special_tile_dispatcher`.
- `special_tile_dispatcher` checks the previous tile byte for `0xFD` and jumps to `special_multi_tile_column_renderer` for NPC columns.
- `special_multi_tile_column_renderer` and `pre_pass_special_column_initializer` both scan `npc_array_addr` with `sprite_descriptor_table_scanner` and `sprite_x_coordinate_lookup`.
- `sprite_x_coordinate_lookup` returns `BL=2` for the current column, `BL=1` for the next column, and `BL=0` otherwise.
- `sprite_compositor_dispatcher` subtracts 1 from `BL` and indexes `funcs_34D2`, which selects `single_sprite_shadow_compositor` or `two_sprite_shadow_compositor`.
- `two_sprite_shadow_compositor` starts at `vram_shadow_addr + 192*2`, calls `npc_3_tiles_to_shadow_buffer`, then immediately falls through into the same routine again so both 3-tile slices are composited.
- `single_sprite_shadow_compositor` adds 3 to `SI` to skip the first slice, starts at `vram_shadow_addr + 192*3`, and then jumps into `npc_3_tiles_to_shadow_buffer`.
- `npc_3_tiles_to_shadow_buffer` is the 3-tile blitter. It marks each staging slot with `0xFF`, derives the packed tile and mask offsets, and calls `blit_tile_to_shadow_buffer` for each of the three tiles.
- `hero_column_shadow_blitter_guard` is the separate hero-column copy that pulls 3 vertical tiles from shadow memory into the screen buffer when the current column matches the hero.

Current C++ structural matches:
- `SaveHeadLevelTilesInNpcs` / `RestoreHeadLevelTilesFromNpcs` match the head-tile save/restore pass.
- `BuildTownNpcRuntimeRecords` and `BuildTownNpcRuntimeViews` now project the live town npc_array mirror into the compositor-facing view layer.
- `GetTownNpcRuntimeViewSpriteColumnMatch`, `FindFirstTownNpcRuntimeViewForColumn`, and `FindFirstTownNpcRuntimeViewForColumnAfterCurrent` mirror the X-based NPC scan and current/next column matching.
- `GetTownNpcSpriteFrameIndex` matches `get_sprite_vram_address` for selector, facing, and animation phase math.
- `DispatchTownSpecialTile` is the current stand-in for the `special_tile_dispatcher` branch into the compositor helpers.
- `DrawTownNpcRuntimeViewCurrentColumnSliceOnTownMap` and `DrawTownNpcRuntimeViewNextColumnSliceOnTownMap` are the SDL-only stand-ins for the two compositor branches.
- `RenderTownColumn` is the closest structural match to the per-column walk in `render_town_tiles_28_columns`, but it still draws directly instead of writing the shadow-memory path.

Still provisional:
- `TownNpcRuntimeRecord` is a minimal mirror, not a live NPC simulation. `AiType` and `Flags` are present but inert, and `Id` is carried only as assembly-facing metadata.
- `prepare_hero_sprite`, `clear_6_hero_tiles_in_viewport_buffer`, and `hero_column_shadow_blitter_guard` do not have a byte-faithful C++ counterpart yet.
- The SDL slice helpers remain the visible path, so `viewport_buffer` and the shadow-memory compositor are not yet reproduced exactly.

Next smallest safe implementation step:
- Thread the live `npc_array` mirror into the byte-exact shadow-memory compositor once the real viewport buffer path is rebuilt, keeping NPC AI, movement, and draw mode unchanged until those assembly routines are matched.

| Behavior | C++ location | Assembly evidence | Status | Recommendation |
| --- | --- | --- | --- | --- |
| Live npc_array mirror | `src/town/town_scene.h:65-110`, `src/town/town_scene.cpp:823-885`, `src/town/town_scene.cpp:1132-1133` | `npc_array_addr` is a zero-terminated NPC list, and the new C++ mirror now copies the confirmed `NPC STRUC` bytes into `TownNpcRuntimeRecord` before projecting them into `TownNpcRuntimeView` for compositor use (`asm/town.inc:1-8`, `asm/town.asm:1244-1251`, `asm/town.asm:1958-1977`, `asm/gtmcga.asm:714-855`). | Confirmed by assembly | Keep |
| Town actor starting position | `src/town/town_scene.h:76`, `src/town/town_scene.h:90` | Town entry sets `hero_x_in_viewport` from transition data or special cases (`asm/town.asm:2088-2129`, `asm/town.asm:2380-2415`) and only initializes `hero_animation_phase` at entry (`asm/town.asm:33-97`). No fixed `160,40` town start appears in the assembly. | Contradicted by assembly | Replace later with assembly-equivalent behavior |
| Town actor movement speed | `src/town/town_scene.cpp:642-727` | Assembly town movement changes the hero one column at a time and scrolls the map in 1-column steps (`asm/town.asm:1070-1179`). | Contradicted by assembly | Replace later with assembly-equivalent behavior |
| Town actor free X/Y movement | `src/town/town_scene.cpp:642-727` | Assembly town mode only tracks horizontal hero movement with `hero_x_in_viewport`; up is used for interaction, not vertical walking (`asm/town.asm:2256-2295`, `asm/town.asm:1070-1179`). | Contradicted by assembly | Keep isolated until exact replacement is implemented |
| Town actor facing and animation frame mapping | `src/town/town_scene.cpp:58-83`, `src/town/town_scene.cpp:935-997`, `src/grp/grp_sprite_sheet.cpp:509-528` | Assembly uses `facing_direction` plus `hero_animation_phase`, and `prepare_hero_sprite` picks `hero_faced_left` or `hero_faced_right` before blitting 6 tiles (`asm/town.asm:1477-1490`). `TMAN.GRP` is the town hero sheet (`asm/town.asm:2231-2248`). | Provisional | Keep temporarily but label provisional |
| Town actor collision probing | `src/town/town_scene.cpp:537-576`, `src/town/town_scene.cpp:642-727` | Assembly checks passability with `check_tile_in_special_list` and NPC blocking with `find_non_passable_npc_at_x_pos`, not a single-point pixel probe (`asm/town.asm:1074-1093`, `asm/town.asm:1185-1236`). | Contradicted by assembly | Replace later with assembly-equivalent behavior |
| Blocked tiles `0x3C` and `0x3D` | `src/town/town_scene.cpp:32-33`, `src/town/town_scene.cpp:900-911` | Assembly town passability is driven by a special tile list pointer (`asm/town.asm:1185-1208`); no fixed `0x3C` / `0x3D` town collision rule was found in the town assembly. | Not confirmed | Keep temporarily as debug/provisional |
| Camera follow | `src/town/town_scene.cpp:284-292`, `src/town/town_scene.cpp:946-958`, `src/town/town_scene.h:98` | Assembly uses automatic edge-scroll handlers tied to hero position and facing (`asm/town.asm:205-225`, `asm/town.asm:1070-1179`, `asm/town.asm:2062-2130`). There is no camera-follow toggle or page-scroll mode in the assembly. | Contradicted by assembly | Replace later with assembly-equivalent behavior |
| NPC parsing from MDT | `src/mdt/mdt_map.cpp:47-83`, `src/mdt/mdt_map.h:16-30` | Town MDT layout and NPC array location are fixed in `asm/town.inc:76-100`, and `load_town_transition_data` loads town MDT data before town rendering (`asm/town.asm:2142-2178`). | Confirmed by assembly | Keep |
| Door parsing from MDT | `src/mdt/mdt_map.cpp:47-66`, `src/mdt/mdt_map.h:16-30` | Town doors are a 3-byte array in the MDT (`asm/town.inc:78-100`), and `town_up_pressed` iterates `doors_array_addr` during interaction (`asm/town.asm:2256-2295`). | Confirmed by assembly | Keep |
| Derived head-level row | `src/mdt/mdt_map.cpp:13-45`, `src/town/town_scene.cpp:30` | `town_head_level_tiles = town_tiles + 5` in `asm/town.inc:84-85`, and the assembly saves/restores NPC head tiles at that row (`asm/town.asm:1951-2012`). | Confirmed by assembly | Keep |
| NPC head-level marker save/restore | `src/town/town_scene.cpp:766-818` | `save_head_level_tiles_in_npcs` saves `town_head_level_tiles[x * 8]`, writes `0xFD`, and stores the old value in `NPC.n_head_tile`; `restore_head_level_tiles_from_npcs` restores non-`0xFD` saved values (`asm/town.asm:1951-2012`). | Confirmed equivalent | Implemented locally |
| Column render dispatch | `src/town/town_scene.cpp:915-983`, `src/town/town_scene.cpp:1058-1080` | `render_town_tiles_28_columns` renders columns and calls `special_tile_dispatcher` on row 5; `special_tile_dispatcher` branches on `0xFD` (`asm/gtmcga.asm:79-156`, `asm/gtmcga.asm:212-216`). | Structurally similar, now split into explicit current/next branches | Keep the branch split; shadow-memory behavior is still deferred |
| Sprite descriptor scanning | `src/town/town_scene.cpp:688-933`, `src/town/town_scene.cpp:1068-1076` | `sprite_descriptor_table_scanner` and `sprite_x_coordinate_lookup` scan the runtime NPC table by X and by the 2-column sprite span (`asm/gtmcga.asm:714-855`). | Runtime view threaded into compositor scan | The C++ path now uses the runtime view x-match helper and passes the matched view into the compositor draw helper; `HeadTile` is still cached context rather than shadow-memory state |
| NPC sprite selector frame calculation | `src/town/town_scene.cpp:87-98`, `src/town/town_scene.cpp:873-906` | `get_sprite_vram_address` uses `n_facing` bit 7 plus `n_anim_phase & 3`, with a 4-frame facing offset and 6 tiles per phase (`asm/gtmcga.asm:812-833`). | Confirmed equivalent | Keep |
| NPC animation phase handling | `src/mdt/mdt_map.cpp:68-83`, `src/town/town_scene.cpp:85-92` | Assembly updates `n_anim_phase` every frame through NPC AI routines, and the AI jump table drives those updates (`asm/town.asm:1681-1902`). The current C++ stores the parsed phase and never advances NPC AI. | Contradicted by assembly | Do not change until NPC AI is reconstructed |
| MMAN.GRP / CMAN.GRP selection | `src/zeliard.cpp:542-595`, `src/town/town_scene.h:28-30`, `src/town/town_scene.cpp:931-935` | Assembly selects the town NPC sheet from town descriptor byte 1 and loads either `MMAN.GRP` or `CMAN.GRP` (`asm/game.asm:193-201`, `asm/town.asm:2142-2186`). | Confirmed by assembly | Keep |
| TMAN.GRP town hero frame loading | `src/zeliard.cpp:867-899`, `src/town/town_scene.cpp:1089-1121`, `src/grp/grp_sprite_sheet.cpp:509-528` | Assembly hardcodes `TMAN.GRP` in `load_hero_town_sprite` and applies the sprite mask before town rendering (`asm/town.asm:2231-2248`, `asm/town.asm:2251-2253`). | Confirmed by assembly | Keep |
| Sprite draw modes | `src/grp/grp_sprite_sheet.cpp:100-106`, `src/town/town_scene.cpp:109-115`, `src/town/town_scene.cpp:189-234` | Assembly uses masked sprite composition paths (`asm/town.asm:52`, `asm/gtmcga.asm:553-708`, `asm/gtmcga.asm:774-833`). | Derived from data | Keep |
| Hero/NPC compositing | `src/town/town_scene.cpp:873-988` | `prepare_hero_sprite` handles NPC markers around the hero, calls `get_sprite_vram_address`, and uses `ui_draw_routine_dispatcher`; `gtmcga.asm` composites NPC columns through the special tile path (`asm/town.asm:1384-1492`, `asm/gtmcga.asm:553-870`). | Provisional | The SDL path now has explicit current-column and next-column helpers, but exact shadow-memory compositing is still not implemented |
| NPC fallback markers | `src/town/town_scene.cpp:909-940` | No assembly fallback marker exists; the fallback only preserves debug visibility when descriptor mapping or frame loading is incomplete, and only when the debug overlay is enabled. | Debug-overlay only | Keep clearly provisional; debug overlay only |
| Collision tile overlay | `src/town/town_scene.cpp:904-915` | No town-assembly equivalent was found; the assembly uses special-tile passability checks and NPC blocking (`asm/town.asm:1074-1093`, `asm/town.asm:1185-1236`). | Debug-only | Keep but mark debug-only |
| Debug HUD | `src/town/town_scene.cpp:1038-1054` | Assembly town HUD work is the real `LIFE / ALMAS / GOLD / PLACE` bar (`asm/town.asm:2018-2033`, `asm/town.asm:2325-2330`) and dialog cursor work (`asm/town.asm:1022-1067`), not the current ACT/CAM/POS debug text. | Debug-only | Keep but mark debug-only |
| Proximity radius and nearest NPC/door detection | `src/town/town_scene.cpp:342-386` | Assembly uses direct x-coordinate matching and adjacent-tile checks for NPC and door interaction, including `is_hero_close_to_npc`, `find_first_npc_at_x`, and `find_first_npc_at_x_after_current` (`asm/town.asm:1515-1571`, `asm/town.asm:2256-2295`, `asm/town.asm:377-442`). | Contradicted by assembly | Replace later with assembly-equivalent behavior |
| Former Y-sorted dynamic sprite draw list | Removed from `src/town/town_scene.h` and `src/town/town_scene.cpp` | Assembly renders town columns with `0xFD` markers, `sprite_descriptor_table_scanner`, and sprite compositing; it does not build a global Y-sorted sprite list (`asm/gtmcga.asm:79-156`, `asm/gtmcga.asm:553-855`, `asm/town.asm:1384-1492`). | Contradicted by assembly | Removed |
| Current town frame order | `src/town/town_scene.cpp:1054-1080` | Assembly frame order is `update_npcs`, `prepare_hero_sprite`, `clear_6_hero_tiles_in_viewport_buffer`, then `render_town_tiles_28_columns` (`asm/town.asm:1242-1283`, `asm/town.asm:1384-1492`, `asm/gtmcga.asm:79-156`). | Provisional | Column foundation started; exact frame/update order remains incomplete |

Deliberately not implemented because evidence or local support is incomplete:
- No movement or collision rewrite. The current free X/Y movement, fixed speed, single-point collision probe, blocked-tile IDs, proximity radius, and camera follow remain isolated and documented.
- No full NPC AI reconstruction. The assembly AI routines were inspected, but the current C++ does not yet maintain live NPC structs with `n_ai_type`, `n_flags`, patrol boundaries, and per-frame phase updates.
- No byte-exact `viewport_buffer`, shadow-memory, or `blit_cache` implementation. The C++ renderer now dispatches by columns with explicit current-column and next-column SDL helpers, but it does not yet reproduce the original shadow-memory compositor.
- No guessed descriptor format beyond fields already parsed from MDT and supported by `NPC STRUC`.
- No GRP loading changes for `TMAN.GRP`, `MMAN.GRP`, `CMAN.GRP`, or `FMAN.GRP`.
