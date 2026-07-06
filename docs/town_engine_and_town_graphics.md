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

The frame wait is handled by `game_loop_with_frame_wait`, which also runs global handlers such as exit dialog, pause, speed change, joystick calibration, and restore-game handling.

## Town map data

`town.inc` maps the town data block at `0C000h`.

The tile map starts at `town_tiles = 0C017h`. The source comment shows one town map as `0xD7 * 8` bytes, meaning 215 columns by 8 tile rows.

The viewport renderer displays only 28 columns at a time. The engine tracks a larger proximity window and uses `proximity_start_tiles` to point at the left column currently being rendered.

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

The passability list comes from `seg1:special_tile_list_ptr`, part of the active pattern/tile group.

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

## Tile animation

`tile_render_and_animate` checks `tile_anim_count_table`. If a tile has no animation count, it falls back to `background_tile_render_with_blit_cache`. If it is animated, it renders with animation handling and then uses `tile_animation_replacement_table` to replace the tile id for the next phase.

The replacement table is a counted or terminated list of `(old_tile, new_tile)` pairs.

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

## Lower strip path

The current town scene now also mirrors the floor strip from the background driver instead of leaving the lower area black.

- `town_descriptor_addr[3]` selects `ympd.bin` or `ckpd.bin` from `game/0`.
- YMPD uses the proven `ground` and `ground1` streams at `0x229e` and `0x23f1`, then applies the MCGA `render_ground` bitplane-to-pixel conversion.
- CKPD uses the MCGA `mode4_mcga` raw tables at `0x1c25` and `0x1de5`.
- The strip is drawn at logical MCGA coordinates `x = 48`, `y = 14 + 16 * 8 = 142` and occupies a `224 x 16` rectangle.
- The decoded strip stays at that fixed screen position, but its pixels are sampled with a cyclic 8-pixel horizontal phase that advances only when the viewport pans one town column, matching `scroll_floor_right_8px` and `scroll_floor_left_8px`.
- No separate background-driver offset was found in the inspected assembly; the proven driver behavior is the in-place 8px scroll step, not a new scenic background system.

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
