# Town engine and town graphics documentation

## Scope

This document explains the town gameplay module and its town-specific graphics driver:

- `town.asm`, loaded at `org 6000h`
- `gtmcga.asm`, loaded at `org 3000h`
- `town.inc`
- relevant shared state from `common.inc`

## Big picture

Town mode consists of two cooperating overlays:

| Module | Slot | Responsibility |
|---|---:|---|
| `town.bin` | `6000h` | Gameplay loop, hero movement, NPC logic, dialog, shops/building transitions, town transitions, save/restore UI. |
| `gtmcga.bin` | `3000h` | Town rendering: 28-column tile viewport, NPC sprite composition, shadow VRAM, tile decompression, text buffers, scrolling effects. |

Important `town.asm` procedures:

`town_entry_disabling_edge_scroll`, `hero_spacebar_interaction`, `check_special_npc_conversation`, `start_npc_conversation`, `render_dialog_text`, `wait_for_dialog_input`, `measure_text_to_delimiter`, `count_dialog_lines`, `confirm_purchase_dialog`, `draw_dialog_cursor`, `check_tile_in_special_list`, `find_non_passable_npc_at_x_pos`, `update_npcs_and_render`, `game_loop_with_frame_wait`, `handle_inventory_key`, `swap_a000_c000_buffers`, `clear_6_hero_tiles_in_viewport_buffer`, `prepare_hero_sprite`, `is_hero_close_to_npc`, `find_first_npc_at_x`, `find_first_npc_at_x_after_current`, `load_patterns_and_call_background`, `load_town_background`, `init_c015_obj_if_exists`, `update_npcs`, `npc_ai_look_at_hero_and_bob`, `npc_ai_patrol_1bit_phase`, `npc_ai_patrol_2bit_phase`, `npc_ai_face_hero`, `npc_ai_bob_in_place`, `npc_ai_patrol_bounce_1bit`, `npc_ai_patrol_bounce_2bit`, `npc_ai_static`, `save_head_level_tiles_in_npcs`, `restore_head_level_tiles_from_npcs`, `render_life_almas_gold_place`, `handle_edge_screen_transition`, `load_town_transition_data`, `load_and_decompress_patterns`, `load_hero_town_sprite`, `npcAnimation`, `render_menu_dialog`, `advance_dialog_page`, `scroll_dialog_down`, `draw_next_page_arrow`, `wait_for_dialog_continue`, `measure_single_word`, `count_remaining_dialog_lines`, `convert_ax_to_decimal`, `div_by_sub`, `div_mod`, `select_from_menu`, `houseCursorShow`, `houseCursorUp`, `houseCursorDown`, `show_yes_no_dialog`, `render_menu_string_list`, `render_menu_list_scrolling`, `check_gold_sufficient`, `add_gold_to_hero`, `restore_game`, `choose_game_to_restore`, `check_save_is_restart`, `clear_save_name`, `render_save_game_list`, `save_name_input_handler`, `highlight_save_cursor`, `render_save_name_string`

Important `gtmcga.asm` procedures:

`backup_upper_town_3_tiles`, `render_town_tiles_28_columns`, `hero_column_shadow_blitter_guard`, `special_tile_dispatcher`, `background_tile_render_with_blit_cache`, `tile_render_and_animate`, `unpack_to_shadow_memory_six_tiles`, `unpack_six_tiles`, `unpack_cx_tiles`, `special_multi_tile_column_renderer`, `pre_pass_special_column_initializer`, `sprite_descriptor_table_scanner`, `reset_sprite_table_pointer`, `advance_sprite_table_to_matching_x`, `copy_3_vert_tiles`, `sprite_compositor_dispatcher`, `two_sprite_shadow_compositor`, `single_sprite_shadow_compositor`, `get_sprite_vram_address`, `sprite_x_coordinate_lookup`, `ui_draw_routine_dispatcher`, `draw_second_column`, `draw_two_columns`, `draw_first_column`, `npc_3_tiles_to_shadow_buffer`, `blit_6_tiles_to_shadow_memory`, `blit_tile_to_shadow_buffer`, `scroll_floor_right_8px`, `scroll_ceiling_right_4px`, `scroll_floor_left_8px`, `scroll_ceiling_left_4px`, `draw_tile_to_screen`, `draw_arrow_icon_or_ui_symbol`, `draw_string_buffer_to_screen`, `format_string_to_buffer`, `render_menu_asciiz_to_buffer1`, `render_menu_glyph_to_buffer1`, `render_numeric_score`, `render_dl_ax_to_buffer_as_decimal`, `render_digit_to_buffer`, `dl_ax_to_decimal`, `dl_ax_to_seven_digits`, `high_byte_decimal_digit_extractor`, `divmod24`, `scroll_hud_up`, `scroll_hud_down`, `apply_screen_xor_grid`, `apply_sprite_mask`, `decompress_patterns`, `sprite_plane_decompressor_0`, `sprite_plane_decompressor_b`, `sprite_plane_decompressor_g`, `sprite_plane_decompressor_r`, `build_48_bytes_packed_tile_from_rgb_planes`, `build_48_bits_packed_from_rgb_planes`, `extract_3_bits_from_rgb_planes`, `extract_transparency_byte_from_mask_plane`

## Town entry flow

`town.asm` has two entry styles:

| Entry | Purpose |
|---|---|
| `town_entry_disabling_edge_scroll` | Primary town initialization after opening intro or after returning from a cavern. It disables edge scrolling for the first frame. |
| `town_entry_enabling_edge_scroll` | Re-entry after transitions such as resurrection or warp. It allows edge scrolling immediately. |

The startup path initializes town rendering, loads current town data, loads patterns and background, prepares the hero sprite, and enters the main town loop.

## Main town loop

The loop follows this conceptual order:

```text
while in town:
  poll frame/input services
  process inventory key
  process spacebar/NPC interaction
  process special NPC conversation triggers
  move hero left/right if passable
  handle edge transitions
  update NPC AI
  prepare hero sprite
  render changed town tiles
  render hero/NPC overlays
  wait for frame timing
```

The frame wait is handled by `game_loop_with_frame_wait`, which also runs global handlers such as exit dialog, pause, speed change, joystick calibration, and restore-game handling. Town NPC AI advances once per town-loop tick, and the movement / bobbing cadence still comes from each NPC's `n_anim_phase` logic inside `asm/town.asm`.

## Town map data

`town.inc` maps the town data block at `0C000h`.

The tile map starts at `town_tiles = 0C017h`. The source comment shows one town map as `0xD7 * 8` bytes, meaning 215 columns by 8 tile rows.

The viewport renderer displays only 28 columns at a time. The engine tracks a larger proximity window and uses `proximity_start_tiles` to point at the left column currently being rendered. In the MCGA path, `render_town_tiles_28_columns` then adds `0x20` bytes, which is 4 tile columns, so the visible viewport begins at `proximity_start_tiles + 0x20` instead of the proximity window's left edge.

Town transition data is also stored in the MDT header block. The 1-based `town_id` byte lives at `+0x06`, `town_transition_table` starts at `+0x07`, and the door table begins at `+0x09`. The transition records are 4 bytes each:

- byte 0: edge flags
- byte 1: destination town id
- byte 2: NPC sprite-group selector
- byte 3: pattern-group selector

The transition table ends where the door table starts. Current startup loads `game/0/cmap.mdt` through `StartingTownId = 0`; its transition table pointer is `C3C6` (`0x03C6`) and its door table pointer is `C3CA` (`0x03CA`), leaving exactly one 4-byte record: `00 01 00 01`. That right-edge town record selects destination town id `1` (`MRMP.MDT`) and pattern group `1` (`mpat.grp`). `MRMP.MDT` has transition pointer `C6E8` (`0x06E8`) and door table pointer `C6EC` (`0x06EC`), leaving exactly one matching left-edge record: `01 00 00 00` back to destination id `0` (`CMAP.MDT`).
The current native edge path rebuilds the destination town NPC runtime records from the loaded map before movement resumes, so CMAP restores its own NPCs after a round-trip from MRMP without carrying blockers forward. MRMP parses 9 NPC records and now uses the same runtime AI table as CMAP. The destination visual reload still needs to accept all town pattern banks (`cpat.grp`, `mpat.grp`, and `dpat.grp`); the `CMAP.MDT -> MRMP.MDT` handoff needs the 242-tile, 11872-byte unpacked `mpat.grp` bank.
Normal startup now opens directly in town gameplay mode (`M`) instead of the font viewer, with the existing debug overlays still behind the explicit `D`, `T`, `O`, and `Y` controls.
Muralla's startup seed uses `HeroXInViewport = 12`, `ProximityMapLeftColumnX = 4`, `FacingDirection = 0` (right), and `HeroAnimationPhase = 0`.
The far-edge transition reloads still force `FacingDirection = 0` and `HeroAnimationPhase = 0`; only the startup seed uses the Muralla entry position above.

## Town NPC structure

Town NPCs are 8-byte records:

```asm
NPC STRUC
  n_x           dw   ?
  n_facing      db   ?
  n_head_tile   db   ?
  n_anim_phase  db   ?
  n_ai_type     db   ?
  n_flags       db   ?
  n_id          db   ?
NPC ENDS
```

The array terminates when `n_x == FFFFh`.

Key behaviors:

- `n_x` is absolute horizontal map position.
- `n_facing` stores facing and sprite selection. Bit 7 is direction, low bits participate in sprite lookup.
- `n_head_tile` saves the original tile under the NPC's head-level row.
- `n_anim_phase` drives bobbing and walking frames.
- `n_ai_type` indexes the town NPC AI table.
- `n_flags` controls passability and special interaction.
- `n_id` selects conversation/person data.
- `npc_patrol_boundaries` is a per-map min/max X pair for the patrol AIs; `CMAP.MDT` parses `33 00 6D 00` and `MRMP.MDT` parses `05 00 96 00`, so the patrol walkers use the range stored in their own MDT header.
- `CMAP.MDT` and `MRMP.MDT` both resolve to `mman.grp` from descriptor byte 1, so Muralla NPC sprites keep using the same bank after the town transition.

## NPC tile marker system

The town tile row `town_head_level_tiles = town_tiles + 5` is special. NPC placement is represented by replacing the original tile with marker `FDh`.

Two procedures manage this:

| Procedure | Role |
|---|---|
| `save_head_level_tiles_in_npcs` | Saves original head-row tiles into each NPC record and writes `FDh` into the map. |
| `restore_head_level_tiles_from_npcs` | Restores original map tiles from NPC records before updating positions. |

This lets the tile renderer detect special multi-tile/NPC columns while still preserving the underlying background tile.

## Town movement and passability

Hero movement checks both tile passability and NPC passability.

Relevant routines:

| Routine | Purpose |
|---|---|
| `check_tile_in_special_list` | Tests whether a tile id appears in the special/non-passable tile list. |
| `find_non_passable_npc_at_x_pos` | Searches the NPC array for a blocking NPC at a target X. |
| left/right edge handlers | Scroll or transition when the hero reaches viewport edges. |
| `handle_edge_screen_transition` | Loads adjacent town data when crossing town boundary. |

The DOS movement handlers probe row `7` before changing any horizontal state:

- left checks `ProximityMapLeftColumnX + HeroXInViewport + 3`
- right checks `ProximityMapLeftColumnX + HeroXInViewport + 6`

Both checks feed `check_tile_in_special_list`, so a tile found in the special list blocks movement before the hero can advance or scroll.
When the viewport is already at the maximum right scroll column, the DOS path falls back to incrementing `hero_x_in_viewport` instead of scrolling further.
The right-edge transition check is `hero_x_in_viewport + 1 == 28`, so `hero_x_in_viewport = 27` belongs to the transition path.
The native path lets Duke reach that sentinel, then reloads the destination town from the parsed transition entry when a right-edge town record is present. Source/data validation for the current `cmap.mdt` startup reaches `HeroXInViewport = 27` at `ProximityMapLeftColumnX = 78`; the right-edge check then selects `00 01 00 01`. The SDL update re-checks the sentinel immediately after movement reaches `27` so the next presented frame uses the destination map. The `hero_x_in_viewport = 0` and `proximity_map_left_col_x = 0` reset is transition-only; normal startup keeps the original town entry state.

The left-edge transition is the mirror path in `handle_edge_screen_transition`: after left movement decrements unsigned `hero_x_in_viewport` from `0` to `0xFF`, the transition test increments it and branches when the result is zero. The transition scan then requires bit `0` set in the 4-byte record. For `MRMP.MDT`, the raw record is `01 00 00 00`, so destination id `0` maps back to `CMAP.MDT` and pattern group `0` maps to `cpat.grp`. After `load_town_transition_data`, the assembly sets `hero_x_in_viewport = 26` and `proximity_map_left_col_x = mapWidth - 36`; returning to `CMAP.MDT` therefore lands at `HeroXInViewport = 26`, `ProximityMapLeftColumnX = 78`.

The passability list comes from `seg1:special_tile_list_ptr`, part of the active pattern/tile group. That means `cpat.grp` blocks `3C 3D`, while `mpat.grp` blocks `96 97`; using the old CMAP list after the MRMP reload falsely blocks walkable MRMP row-7 columns such as `57`, `58`, `61`, and `62` where the map contains tile `3D`.

## Dialog system

Town dialog is handled by several cooperating routines:

| Routine | Purpose |
|---|---|
| `hero_spacebar_interaction` | On spacebar, find NPC in front of hero and begin conversation. |
| `check_special_npc_conversation` | Detects special NPC conversations based on position and flags. |
| `start_npc_conversation` | Captures screen area, opens dialog box, renders text, restores screen. |
| `render_dialog_text` | Word-wrapped dialog renderer with control codes. |
| `wait_for_dialog_input` | Waits for spacebar/Alt/direction events. |
| `measure_text_to_delimiter` | Calculates word width for wrapping. |
| `count_dialog_lines` | Determines how much dialog fits. |
| `confirm_purchase_dialog` | Shows Take/No Take confirmation. |
| `render_menu_dialog` | FF-terminated menu/dialog renderer used by building overlays too. |

The dialog renderer handles control bytes, including shop and quest triggers. `FFh` usually terminates dialog/menu text.

## Town graphics driver export table

`gtmcga.asm` starts with a 20-entry table. Key entries:

| Table slot | Routine | Purpose |
|---:|---|---|
| 0 | `apply_screen_xor_grid` | Applies an XOR visual overlay/grid. |
| 1 | `backup_upper_town_3_tiles` | Saves 28 columns × 3 tiles of upper town area. |
| 2 | `render_town_tiles_28_columns` | Main dirty tile renderer. |
| 3..6 | scroll routines | Floor/ceiling left/right scroll. |
| 7 | `unpack_to_shadow_memory_six_tiles` | Unpack six 8×8 tiles into shadow VRAM. |
| 8 | `ui_draw_routine_dispatcher` | Draw hero/sprite columns into shadow memory. |
| 9 | `blit_6_tiles_to_shadow_memory` | Masked blit of six tiles. |
| 10 | `get_sprite_vram_address` | Compute town NPC sprite frame pointer. |
| 11 | `draw_tile_to_screen` | Draw one 8×8 packed tile/glyph. |
| 13 | `format_string_to_buffer` | Format menu string into offscreen buffer. |
| 14 | `draw_string_buffer_to_screen` | Copy formatted string to VRAM. |
| 17 | `render_numeric_score` | Render decimal number. |
| 18 | `decompress_patterns` | Convert pattern group data into packed tile graphics. |
| 19 | `apply_sprite_mask` | Generate/apply sprite transparency masks. |

## Dirty tile rendering in `render_town_tiles_28_columns`

The town viewport is 28 columns wide. Each column has 8 tile rows. The renderer compares the current proximity map tile byte against `viewport_buffer`.

Conceptually:

```text
for column in 0..27:
  if column intersects hero area:
    restore/prepare shadow background

  for row in 0..7:
    if current_tile != previous_viewport_tile:
      render tile
      update viewport_buffer

  advance screen address by 8 pixels
```

This avoids redrawing unchanged tiles and is essential for speed on 286-era hardware.

## Proven town viewport coordinates

- `render_town_tiles_28_columns` draws the 28-column town tile layer at logical MCGA coordinates `x = 48`, `y = 14 + 8 * 8 = 78`.
- `render_town_tiles_28_columns` seeds `si` from `proximity_start_tiles` and then adds `0x20`, so the visible town columns start 4 tile columns after the proximity map's left column.
- Town tile row `0` starts at that viewport origin. Row `7` ends at `y = 141`, so the full town tile band spans `78..141`.
- The shared NPC and hero sprite band sits on row `5`, which maps to `y = 14 + 13 * 8 = 118` in the same screen space.
- `current_column_screen_addr` starts from `48 + 78 * 320` and advances 8 pixels per column.
- The lower floor strip remains the assembly-backed `x = 48`, `y = 142`, `224 x 16` rectangle from the YMPD/CKPD driver.
- `viewport_top_left_vram_offset = 48 + 14 * 320` belongs to the scenic background driver above the town viewport, not to the town tile layer itself.

## Tile format

Town pattern tiles are 8×8 pixels and stored as 48 bytes per tile:

```text
8 rows × 8 pixels × 6 bits per pixel = 384 bits = 48 bytes
```

Render routines unpack 3 source bytes into 4 destination pixels repeatedly. This is why the tile renderer loops over 16 packed groups per tile.
Pattern tiles also keep their original mode byte and an 8-byte per-row transparency mask. Modes 1-3 use the missing plane as the mask source, mode 0 is fully opaque, and mode 4 uses the fully masked variant.
Transparency is mask-driven only, so palette index 0 still renders as black whenever the mask leaves a pixel opaque.

## Tile animation

`render_town_tiles_28_columns` only routes rows 0, 1, and 2 through `tile_render_and_animate`. Rows 3, 4, 6, and 7 use `background_tile_render_with_blit_cache`, and row 5 uses `special_tile_dispatcher`.

That same row split also controls transparency in the native port: town pattern masks are only applied for the top 3 rows, matching the `tile_render_and_animate` path in `gtmcga.asm`. Lower rows draw solid, so palette index `0` still renders as black when the source tile contains it.

`tile_render_and_animate` checks `tile_anim_count_table`. If a tile has no animation count, it falls back to `background_tile_render_with_blit_cache`. If it is animated, it renders with the per-row transparency mask and then uses `tile_animation_replacement_table` to replace the tile id for the next phase.

The replacement table is a counted or terminated list of `(old_tile, new_tile)` pairs.

In the native C++ port, that replacement step is advanced from `TownScene::Update()` instead of `Draw()`, and it is gated to the DOS town-loop cadence (`TownDosTownLoopIntervalMilliseconds`, about 84.49 ms at standard speed). Only rows 0, 1, and 2 advance through the replacement table; masked tiles in other rows still render with their masks but stay fixed unless they have an explicit replacement entry.

## Blit cache

`background_tile_render_with_blit_cache` uses `blit_cache` to avoid unpacking identical tiles repeatedly in the same render pass. If a tile has already been rendered, later instances can be copied from the cached screen area rather than decoded again from packed graphics.

## Shadow VRAM and sprite composition

The town renderer uses `A000:FA00` and above as shadow VRAM. It composes background and sprites there before copying to the visible screen.

Typical flow:

```text
unpack background tiles into shadow VRAM
apply NPC or hero masked sprite over those tiles
copy final 8×24 or 16×24 region to visible framebuffer
```

Important routines:

| Routine | Role |
|---|---|
| `unpack_to_shadow_memory_six_tiles` | Draws six background tiles into shadow buffer. |
| `npc_3_tiles_to_shadow_buffer` | Draws three sprite tiles with masks. |
| `blit_tile_to_shadow_buffer` | AND mask then OR sprite pixels. |
| `copy_3_vert_tiles` | Copies 8×24 pixels from shadow to screen. |
| `sprite_compositor_dispatcher` | Chooses one-column or two-column sprite composition. |

This is how the engine avoids square sprite boxes and preserves transparent background pixels.

## Town sprite addressing

`get_sprite_vram_address` reads an NPC record and computes the sprite frame address from:

- low bits of `n_facing`,
- bit 7 of `n_facing` for direction,
- low bits of `n_anim_phase` for frame,
- sprite graphics base at `seg1:4000h`.

The hero town sprite group is loaded into `seg1:6000h` and has masks generated into `seg2:8000h`.

## Scrolling effects

Four routines scroll decorative parts of the town scene:

| Routine | Effect |
|---|---|
| `scroll_floor_right_8px` | Moves floor band right by 8 pixels. |
| `scroll_floor_left_8px` | Moves floor band left by 8 pixels. |
| `scroll_ceiling_right_4px` | Moves top/ceiling band right by 4 pixels. |
| `scroll_ceiling_left_4px` | Moves top/ceiling band left by 4 pixels. |

Right scroll uses `std` so copy operations proceed backward and avoid overwriting source pixels before they are copied.
The floor routines are called only when `proximity_map_left_col_x` advances or retreats during horizontal town panning; `hero_x_in_viewport` only decides whether the hero moves within the viewport or the viewport itself scrolls.

## Mountain layer path

- `town.asm` loads `YMPD.BIN` when `town_has_middle_layer` bit 0 is clear.
- `sub_3300` expands `mountains0` from `ympd.bin` offset `0x05E7` to `seg1:0000` and `mountains1` from offset `0x1459` to `seg1:1340h`, decoding each stream to exactly 4928 bytes into an 88 x 56 plane buffer before `render_mountains` combines the two planes into the final `224 x 88` MCGA layer.
- The mountain RLE stream uses `0x06, value, count`, and `count` is an unsigned 8-bit repeat byte, so `0xFF` means 255 repeats.
- The mountain layer is rendered once by the background driver during town setup. `load_town_background` loads `ympd.bin`, `call_background_code` runs `sub_3300`, and `mode4_mcga` writes the final `224 x 88` mountain footprint directly to VRAM at `viewport_top_left_vram_offset` (`A000:(48,14)`), which is a final screen position rather than a viewport-relative one.
- Each source byte pair from the two mountain planes produces 4 MCGA pixels through the `sub_34F9` bit-combine logic.
- The mountain layer stays static during town panning. The town frame loop later draws the tile band and sprite overlays on top of it, while the floor strip is handled by the separate scroll helpers.

## Lower strip path

The current town scene now also mirrors the floor strip from the background driver instead of leaving the lower area black.

- `town_descriptor_addr[3]` selects `ympd.bin` or `ckpd.bin` from `game/0`.
- YMPD uses the proven `ground` and `ground1` streams at `0x229e` and `0x23f1`, then applies the MCGA `render_ground` bitplane-to-pixel conversion.
- CKPD uses the MCGA `mode4_mcga` raw tables at `0x1c25` and `0x1de5`.
- The strip is drawn at logical MCGA coordinates `x = 48`, `y = 14 + 16 * 8 = 142` and occupies a `224 x 16` rectangle.
- The decoded strip stays at that fixed screen position, but its pixels are sampled with a cyclic 8-pixel horizontal phase that advances only when the viewport pans one town column, matching `scroll_floor_right_8px` and `scroll_floor_left_8px`.
- No separate background-driver offset was found in the inspected assembly; the proven driver behavior is the in-place 8px scroll step, not a new scenic background system.

## MOLE side panels

`mole.bin` is loaded at `seg3:0` and `DrawDecorationsAroundCanvas` selects the MCGA path with `al = 4`. For the town frame we now use only the two decorative side-panel passes:

- left panel: `title_border1_data` + `title_border2_data`
- right panel: `title_frame1_data` + `title_frame2_data`

The confirmed source spans in `game/0/mole.bin` are:

- `title_border1_data`: `0x08CD..0x10DA`
- `title_border2_data`: `0x10DB..0x1860`
- `title_frame1_data`: `0x1861..0x2087`
- `title_frame2_data`: `0x2088..0x2798`

Each source plane decodes to `12 x 200` bytes, and the MCGA unpack path combines two planes into a `48 x 200` pixel panel. The left panel renders at `x = 0`, `y = 0`; the right panel renders at `x = 272`, `y = 0`. The center town viewport still stays anchored at `x = 48`.

The MOLE MCGA unpack table is the exact one from `Unpack2bppTo4bit_MCGA`:

`0,1,5,3,8,9,0D,0B,28,29,2D,2B,18,19,1D,1B`

## MOLE bottom/status base panel

`DrawDecorationsAroundCanvas` then renders the lower MOLE base art from `title_screen_final_data` with `rle_marker_high = 0x50` and `rle_flag = 0xFF`. The source span in `game/0/mole.bin` is `0x2799..0x2926`, which consumes `397` bytes and decodes to `2352` bytes before the MCGA unpack pass combines it with the zero-filled second plane.

The exact assembly path is:

- `mov ds:rle_flag, 0FFh`
- `mov ds:rle_marker_high, 50h`
- `mov si, offset title_screen_final_data`
- `mov di, buf1`
- `call DecompressRLE`
- `mov di, buf2`
- `mov cx, 4B0h`
- `xor ax, ax`
- `rep stosw`
- `mov bp, 960h`
- `mov bx, 0C9Eh`
- `mov cx, 382Ah`
- `call DecompressToVRAM`

In MCGA terms that means:

- `x = BH * 4 = 48`
- `y = BL = 158`
- source bytes per row = `CH = 56`
- row count = `CL = 42`

The lower base panel is therefore `224 x 42` pixels at `x = 48`, `y = 158`. It is MOLE base art only; the later HUD contents are drawn separately by `game.asm` and `gmmcga.asm`.

## Bottom HUD bars and text

After the MOLE bottom/status base panel, town startup calls `gmmcga.asm` `Clear_HUD_Bar` from `town.asm` with these parameters:

- `bx = 0204h`, `ch = 21h` for the LIFE strip.
- `bx = 021Ch`, `ch = 42h` for the GOLD strip.
- `bx = 481Ch`, `ch = 42h` for the ALMAS strip.
- `Clear_Place_Enemy_Bar`, which uses `bx = 0210h`, `ch = 88h` for the PLACE/name strip.

`Clear_HUD_Bar` maps those bytes to `x = 48 + BH`, `y = 158 + BL`, writes a black lead column, then writes `CH` columns with a black top row, palette index `5` body rows, and palette index `0x2D` bottom row.

`town.asm` `render_life_almas_gold_place` renders the fixed labels through `gmmcga.asm` `Render_Pascal_String_0`, which uses `font.grp` `thin_font`, primary color `0x1B`, shadow color `0x12`, four pixel columns per glyph, and five pixels of glyph advance. The proven label positions are:

- LIFE: `0E A3 00 04`, so `x = 56`, `y = 163`.
- ALMAS: `1E BB 03 05`, so `x = 123`, `y = 187`.
- GOLD: `0D BB 01 04`, so `x = 53`, `y = 187`.
- PLACE: `0D AF 01 05`, so `x = 53`, `y = 175`.

The current C++ path renders Gold and Almas as zero only. The zero display matches the `gmmcga.asm` digit path for the proven positions: Gold uses `Print_Gold_Decimal` at `x = 78`, `y = 187`, six digits, and Almas uses `Print_Almas_Decimal` at `x = 154`, `y = 187`, five digits. Full live gold/almas state and the full 24-bit decimal conversion path are not wired yet.

The place name comes from the MDT/runtime `town_name_rendering_info` pointer at offset `0x04` / runtime `0C004h`, then renders through `Render_Pascal_String_1` with `thin_font`, primary color `9`, and shadow color `0x2D`.

Remaining unresolved lower-HUD work:

- Training Sword rendering is proven and implemented from unpacked `itemp.grp`. The file starts with 7 little-endian group offsets; group 0 starts at `0x000E` and ends at `0x0662`, giving six sword item sprites. Each sword sprite is `18 * 15 = 270` source bytes and decodes to `20 x 18` pixels. `SWORD_TRAINING = 1`, and `gmmcga.asm` `Render_Sword_Item_Sprite_20x18` does `dec al` before multiplying by `270`, so Training Sword uses group 0 sprite index `0`: `0x000E + (SwordType - 1) * 270`.
- Startup HP/max HP are not implemented. The assembly calls `Draw_Hero_Max_Health` and `Draw_Hero_Health`, but the C++ startup values are not proven from the runtime/save-state source yet.

## Full top Tears bar render order

`DrawDecorationsAroundCanvas` first decodes the MOLE Tears placeholder top bar from the raw assembly labels `title_logo_data` and `title_demo_text_data`, then calls `DecompressToVRAM` with `bp = 0x960`, `bx = 0x0C00`, and `cx = 0x380D`. In the MCGA path that means:

- `x = BH * 4 = 48`
- `y = BL = 0`
- source bytes per row = `CH = 56`
- row count = `CL = 13`

The proven source spans in `game/0/mole.bin` are:

- `title_logo_data`: `0x04AE..0x073C`
- `title_demo_text_data`: `0x073D..0x08CC`

The full `title_logo_data` stream decodes to `1202` bytes, while `title_demo_text_data` decodes to `728` bytes. The MCGA unpack path consumes the first `728` decoded bytes from each plane, starting at offset `0` in both decoded buffers, and combines them into a `224 x 13` pixel strip. The strip renders at `x = 48`, `y = 0`, between the two side panels. The central town viewport still stays anchored at `x = 48`.

`mode4_mcga` seeds the unpack helper from the low byte of `cx` for each source byte (`bl = 0x0D` for the top bar), and the helper keeps that `bl` state across the four pixel extractions for the byte before the caller restores the next source-byte seed.

The complete startup render order is:

1. `mole.asm` `DrawDecorationsAroundCanvas` draws the center top base strip at `x = 48`, `y = 0`, size `224 x 13`.
2. The same MOLE routine draws the left and right side panels at `x = 0` and `x = 272`. These touch `y = 0..199`, but they do not modify the center top strip.
3. The same MOLE routine later draws the bottom/status base art at `x = 48`, `y = 158`, size `224 x 42`, then `DrawTitleFrame` writes small frame rows around `y = 47`. Neither overlaps `y = 0..13`.
4. After the far call returns, `game.asm` immediately calls `render_tears_collected`. This is the only post-MOLE call in the inspected startup path that writes into the center top bar.
5. The following equipment calls render into the bottom HUD contents: sword at `bx = 0x18AB`, shield at `bx = 0x3EA4`, and magic at `bx = 0x37A4`; their `BL` values place them below the top bar and they are separate from the MOLE bottom/status base art. The sword routine scales `BH` by 8, so the town HUD Training Sword position is `x = 192`, `y = 171`.

`render_tears_collected` returns without drawing when `Tears_of_Esmesanti_count == 0`. Otherwise it loops through the first `count` entries in `tears_order_coords`, passes each coordinate in `BX`, and calls `Render_Icon_16x13`. The first eight collected tears use `AL = 0`; the ninth uses `AL = 1`.

| Field | Proof |
|---:|---|
| `Tears_of_Esmesanti_count` address | `common.inc:250` defines it as `equ 0a0h`; `docs/global_memory_map_and_data_structures.md:68` lists `00A0h` as the global "Tear count" byte. |
| State class | Global save/global-state byte, not town-local and not hero-local. |
| Written where | Only `rokademo.asm` writes it: `inc byte ptr ds:Tears_of_Esmesanti_count` then clamps to `9` (`rokademo.asm:32..36`). That routine is the intro/demo/test path, confirming the byte is seeded by global/demo state rather than town state. |
| Read where | `game.asm` `render_tears_collected` tests and loads it (`game.asm:317`, `game.asm:323`) but never writes it; `rokademo.asm` also reads it at `:99` and `:285`. |
| C++ source today | `src/town/town.cpp` reads the project-owned `TearsOfEsmesantiCount` byte. It defaults to `0`, the overlay clamps to `9`, and the optional debug-only override can display all nine collected Tears for visual testing without changing gameplay state. |

| Order | `tears_order_coords` | Screen position |
|---:|---:|---|
| 0 | `0x0F00` | `x = 60`, `y = 0` |
| 1 | `0x3D00` | `x = 244`, `y = 0` |
| 2 | `0x1500` | `x = 84`, `y = 0` |
| 3 | `0x3700` | `x = 220`, `y = 0` |
| 4 | `0x1B00` | `x = 108`, `y = 0` |
| 5 | `0x3100` | `x = 196`, `y = 0` |
| 6 | `0x2100` | `x = 132`, `y = 0` |
| 7 | `0x2B00` | `x = 172`, `y = 0` |
| 8 | `0x2600` | `x = 152`, `y = 0` |

The MOLE top art should be described as Tears placeholders. Keep the raw labels (`title_logo_data`, `title_demo_text_data`) as source-label mappings only.

Do not synthesize collected Tears or force a fake filled bar in normal runtime. If `TearsOfEsmesantiCount` stays `0`, the overlay stays hidden.

`Render_Icon_16x13` computes `x = BH * 4` and `y = BL`, then copies a `16 x 13` glyph into VRAM. Pixel value `0x80` is transparent; every other value, including `0`, overwrites the existing MOLE pixel. This path is a masked copy, not an OR blend.

The icon glyph bytes come from the `gmmcga.asm` table `off_2A5D` (`gmmcga.asm:1766`), which lives at file offset `0x0A5D` in `game/gmmcga.bin`: `off_2A5D[0]` points to `byte_2A61` at `0x0A61` (icon `AL = 0`, small blue Tear, `gmmcga.asm:1768`) and `off_2A5D[1]` points to `byte_2B31` at `0x0B31` (icon `AL = 1`, large red Tear, `gmmcga.asm:1785`). Each glyph is `16 x 13` bytes; `0x80` is the transparent skip value (`gmmcga.asm:1750`).

The proven split is:

- MOLE base frame: the center `224 x 13` strip plus the side panels.
- MOLE top part: Tears placeholders.
- MOLE bottom/status base panel: the base art behind the lower HUD, rendered as a `224 x 42` strip at `x = 48`, `y = 158`.
- Empty Tears placeholders and any static center background: part of the MOLE base strip.
- Collected/filled Tears overlay: `game.asm` `render_tears_collected` plus `gmmcga.asm` `Render_Icon_16x13`.
- Bottom HUD contents: `game.asm` and `gmmcga.asm` draw the equipment icons, numbers, and status overlays on top of the MOLE base panel.
- Center icon overlay: no separate routine was found. The only center-changing post-MOLE draw is the ninth collected Tear at `x = 152`, `y = 0` using icon `AL = 1`.

The current C++ town scene now draws the collected Tears overlay from the real `TearsOfEsmesantiCount` value. The optional debug-only override can show all nine collected Tears for visual testing, but normal runtime must never fake the gameplay state.

## Collected Tears overlay path (proven)

- Driver: `game.asm` `render_tears_collected` (`game.asm:316..345`), called once right after `DrawDecorationsAroundCanvas` returns (`game.asm:148`).
- Loop count: `cl = Tears_of_Esmesanti_count`; returns immediately when the byte is `0`.
- Coordinate table: `tears_order_coords` (`game.asm:348..356`), nine `dw` words. Each word encodes `BH` in the high byte and `BL` in the low byte; `Render_Icon_16x13` maps `BH -> x * 4` and `BL -> y`.
  - `0x0F00 -> x=60`, `0x3D00 -> x=244`, `0x1500 -> x=84`, `0x3700 -> x=220`, `0x1B00 -> x=108`, `0x3100 -> x=196`, `0x2100 -> x=132`, `0x2B00 -> x=172`, `0x2600 -> x=152`; all `y = 0`.
- Icon selection: for loop index `dx < 8` `AL = 0` (small blue), for `dx == 8` `AL = 1` (large red) (`game.asm:333..336`).
- Pixel copy: `gmmcga.asm` `Render_Icon_16x13` (`gmmcga.asm:1722..1763`); `0x80` skips, all other bytes overwrite VRAM.
- C++ status: implemented in `src/town/town.cpp` from the real `TearsOfEsmesantiCount` value. Keep the debug-only override off by default and never synthesize collected Tears in normal runtime.

## Town pattern loading

`town.asm` loads pattern groups through:

```text
load_and_decompress_patterns
  -> res_dispatcher_proc AL=2
  -> adjust pattern offsets
  -> decompress_patterns_proc in gtmcga.bin
```

Pattern groups include `cpat.grp`, `mpat.grp`, and `dpat.grp` style files. They contain metadata, animation tables, special tile lists, and packed tile graphics.

## Building transitions

When the hero enters doors or buildings, town code swaps buffers and loads building overlays such as:

- king,
- sage,
- armor shop,
- item/drug shop,
- bank,
- church,
- inn,
- hut/end-demo path.

The building overlays reuse town dialog rendering and common MCGA UI functions.

## Porting notes

Implement town mode in layers:

1. Decode town map and NPC table.
2. Implement a 28×8 tile viewport and dirty comparison buffer.
3. Implement 48-byte tile decoding to indexed pixels.
4. Implement shadow composition for 2×3-tile sprites.
5. Implement NPC marker `FDh` restoration and insertion.
6. Implement dialog/menu control flow.
7. Only then implement decorative scrolling and animation replacement.
