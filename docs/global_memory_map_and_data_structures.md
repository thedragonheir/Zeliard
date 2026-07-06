# Global memory map and data structures

## Scope

This document explains the shared constants and structures defined in:

- `common.inc`
- `town.inc`
- `dungeon.inc`

These include the savegame/runtime state, overlay call gates, town records, NPC records, dungeon records, monster records, projectile records, and graphics memory layout.

## Core segment model

The original game uses one main allocated runtime segment and then derives nearby logical segments by adding paragraphs:

```text
game_cseg = primary game segment
seg1      = game_cseg + 1000h
seg2      = game_cseg + 2000h
seg3      = game_cseg + 3000h
```

The same numeric offset can mean different things depending on the active segment. For example, `0C000h` can be a town descriptor in the code segment, select overlay data in `seg1`, or fight code/data in `seg2`.

## Screen and VRAM constants

`common.inc` defines:

```asm
viewport_top_left_vram_offset equ (48+14*320)
vram_shadow_addr              equ (320*200)
```

The visible MCGA/VGA framebuffer is assumed to be 320 bytes per scanline. The visible screen is 320×200 bytes, so it occupies offsets `0000h..F9FFh` in segment `A000h`.

The shadow VRAM buffer begins at:

```text
320 * 200 = 64000 = FA00h
```

This gives the renderer a hidden composition area immediately after the visible framebuffer. Town sprite routines use this region to combine background tiles and masked sprites before copying the final pixels to the visible screen.

## Savegame and persistent state area

The savegame area begins at offset `0`. Many offsets in `common.inc` represent permanent player progress, item flags, boss defeats, and inventory data.

Important examples:

| Offset | Symbol | Meaning |
|---:|---|---|
| `0000h` | `Cangrejo_Defeated` | Boss defeated flag. |
| `0005h` | `spoke_to_king` | Story progress flag. |
| `0049h` | `is_death_already_processed` | Death/end-state handling flag. |
| `0080h` | `proximity_map_left_col_x` | Current world X of the left edge of the proximity map. |
| `0083h` | `hero_x_in_viewport` | Hero tile X inside the town/dungeon viewport. |
| `0085h` | `hero_gold_hi` | High byte of 24-bit gold. |
| `0086h` | `hero_gold_lo` | Low word of 24-bit gold. |
| `008Bh` | `hero_almas` | Almas count. |
| `008Dh` | `hero_level` | Hero level. |
| `0090h` | `hero_HP` | Current HP. |
| `0092h` | `sword_type` | Equipped sword. |
| `0093h` | `shield_type` | Equipped shield. |
| `0094h` | `shield_HP` | Current shield HP. |
| `0098h` | `keys_amount` | Ordinary key count. |
| `009Dh` | `current_magic_spell` | Current selected magic row. |
| `00A0h` | `Tears_of_Esmesanti_count` | Tear count. |
| `00A1h..00A5h` | shoe/cape flags | Equipment/accessory flags. |
| `00ABh..00BAh` | spell counts | Remaining magic uses. |
| `00BBh..00C1h` | active spell flags | Whether each spell can be selected. |
| `00C2h` | `facing_direction` | Bit 0: 0 right, 1 left. |
| `00C4h` | `place_map_id` | Current map/town/cavern identifier. |

The project uses byte flags heavily. `00h` usually means false/unowned/inactive. `FFh` often means true/owned/active. Some flags are bitfields where individual bits represent chests, doors, events, or inventory availability.

## Resident service exports

`common.inc` maps resident services into call-table offsets.

### `stick.bin` exports at `0100h`

| Offset | Symbol | Service |
|---:|---|---|
| `0100h` | `int9_new_proc` | Keyboard ISR entry. |
| `0103h` | `int8_new_proc` | Timer ISR entry. |
| `0106h` | `int24_new_proc` | Critical error handler. |
| `0109h` | `int61_new_proc` | Joystick/input service. |
| `010Ch` | `res_dispatcher_proc` | Virtual file/resource dispatcher. |
| `0110h..0120h` | assorted handlers | Exit dialog, pause, speed, calibration, restore, random. |

### `gmmcga.bin` exports at `2000h`

The general graphics driver exposes UI and HUD operations such as rectangle drawing, viewport clear, HP bars, string rendering, decimal rendering, icons, palette fade, screen clear, and plane reassembly.

### `gtmcga.bin`, `gdmcga.bin`, `gfmcga.bin` exports at `3000h`

The `3000h` region is a graphics-driver slot. Town, dungeon, and fight graphics modules all declare `org 3000h`, but only the currently relevant one is active in that slot.

### `fight.bin` exports at `6000h`

The fight/dungeon gameplay module exposes collision, movement, monster, projectile, and proximity services through a table starting at `6000h`.

## Shared volatile runtime variables at `0FFxxh`

The `0FFxxh` area acts like a global engine state block.

Important fields:

| Offset | Symbol | Purpose |
|---:|---|---|
| `FF00h` | `fn_exit_far_ptr` | Exit callback pointer. |
| `FF08h` | `heartbeat_volume` | Dynamic heartbeat SFX volume. |
| `FF09h` | `exit_pending_flag` | Exit requested flag. |
| `FF0Ah` | `joystick_enabled_flag` | Joystick enabled. |
| `FF0Ch` | `fn_per_tick_callback` | Timer callback. |
| `FF14h` | `video_drv_id` | Selected graphics driver index. |
| `FF16h` | `____Alt_Space` | Alt/space key bits. |
| `FF17h` | `____right_left_down_up` | Directional input bits. |
| `FF18h` | `F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter` | Packed keyboard state. |
| `FF1Ah` | `frame_timer` | Frame pacing counter. |
| `FF1Bh` | `anim_timer` | Animation timer. |
| `FF1Dh` | `spacebar_latch` | Edge-detected spacebar. |
| `FF1Eh` | `altkey_latch` | Edge-detected alt key. |
| `FF2Ah` | `proximity_start_tiles` | Town tile pointer for visible left column. |
| `FF2Ch` | `seg1` | Stored segment value for `game_cseg + 1000h`. |
| `FF31h` | `viewport_left_top_addr` | Pointer inside proximity map. |
| `FF33h` | `speed_const` | Game speed/timing divisor. |
| `FF35h` | `hero_y_absolute` | Hero Y coordinate in dungeon. |
| `FF36h` | `hero_damage_this_frame` | Damage accumulator/flag. |
| `FF3Ch` | `spell_active_flag` | Magic active state. |
| `FF43h` | `sword_swing_flag` | Sword action state. |
| `FF44h` | `ui_element_dirty` | UI update required. |
| `FF45h` | `sword_hit_type` | Forward, overhead, or down-thrust. |
| `FF4Ch` | `dialog_string_ptr` | Active dialog string pointer. |
| `FF52h` | `menu_item_count` | Menu row count. |
| `FF54h` | `menu_base_addr` | Menu rendering base. |
| `FF57h` | `menu_digits_render_flag` | Whether menu text includes numbers. |
| `FF6Ch` | `save_name` | Save name buffer. |
| `FF75h` | `soundFX_request` | SFX request byte. |
| `FF77h` | `font_highlight_flag` | Font/highlight rendering state. |

## Common graphics data offsets in `seg1`

`seg1` contains many active graphics resources:

| Offset | Symbol | Meaning |
|---:|---|---|
| `3000h` | `town_msd_music` | Town music data. |
| `4000h` | `mman_cman_gfx` | Town NPC graphics. |
| `6000h` | `tman_gfx` | Town hero graphics. |
| `8000h` | `packed_tile_ptr` | Pattern/tile descriptor base. |
| `8000h` | `tile_anim_count_table` | Pointer to per-tile animation counts. |
| `8002h` | `special_tile_list_ptr` | Pointer to non-passable/special tile list. |
| `8004h` | `tile_animation_replacement_table` | Counted list of animation replacement pairs. |
| `8100h` | `packed_tile_graphics` | 48-byte packed 8×8 tiles. |
| `0D000h` | `hero_transparency_masks` | Sprite row transparency masks. |
| `0E200h..` | item icon pointer table | Sword, shield, crest, magic, key, potion, wearable icons. |

## Common graphics data offsets in `seg2`

| Offset | Symbol | Meaning |
|---:|---|---|
| `3300h` | `town_background_decorations` | Town decoration code/data. |
| `6000h` | `or_blit_buffer` | OR data for masked blits. |
| `8000h` | `and_blit_buffer` | AND masks for masked blits. |
| `9000h` | `mcga_driver_buffer` | Secondary graphics driver buffer. |

## Town structures

`town.inc` defines the town runtime layout at `0C000h`.

| Offset | Symbol | Meaning |
|---:|---|---|
| `0C000h` | `town_descriptor_addr` | Town descriptor pointer/data. |
| `0C002h` | `town_map_width` | Town width in tile columns. |
| `0C004h` | `town_name_rendering_info` | Pascal-style name display info. |
| `0C006h` | `town_id` | 1-based town id. |
| `0C007h` | `town_transition_table` | Edge transition table. |
| `0C009h` | `doors_array_addr` | Door table pointer. |
| `0C00Bh` | `dungeon_entrance_table` | Dungeon entrance table pointer. |
| `0C00Dh` | `npc_conversations_addr` | NPC dialog pointer table. |
| `0C00Fh` | `npc_array_addr` | NPC array pointer. |
| `0C011h` | `npc_patrol_boundaries` | Patrol boundary table. |
| `0C015h` | `word_C015` | Object/init table pointer. |
| `0C017h` | `town_tiles` | Unpacked town tile map. |

The comment in `town.inc` states that Muralla's unpacked town map region is `0x6B8` bytes, equal to `0xD7 * 8`. So the town map is stored as 8 vertical tile rows across a variable-width horizontal map.

### `NPC` structure

```asm
NPC STRUC
  n_x           dw   ? ; 0
  n_facing      db   ? ; 2
  n_head_tile   db   ? ; 3
  n_anim_phase  db   ? ; 4
  n_ai_type     db   ? ; 5
  n_flags       db   ? ; 6
  n_id          db   ? ; 7
NPC ENDS
```

| Field | Meaning |
|---|---|
| `n_x` | Absolute world tile X. `FFFFh` terminates the array. |
| `n_facing` | Packed sprite/facing byte. Bit 7 is direction, low 7 bits are sprite group/index. |
| `n_head_tile` | Original tile under the NPC head row or `FDh` marker. |
| `n_anim_phase` | Animation counter/frame bits. |
| `n_ai_type` | Index into town NPC AI table. |
| `n_flags` | Interaction/collision flags. Bit 6 is used for non-passable NPCs. |
| `n_id` | Dialog/person identifier. |

Town NPCs modify the tile row `town_head_level_tiles`, defined as `town_tiles + 5`. This is the row where NPC presence markers live.

## Dungeon structures

`dungeon.inc` defines runtime structures for caverns.

### `monster`

Each monster table entry is 16 bytes and the table ends with `currX = FFFFh`.

| Field | Meaning |
|---|---|
| `currX` | Absolute map X. |
| `currY` | Y row, usually 0..63. |
| `m_x_rel` | X relative to proximity left, 0..35. |
| `flags` | Monster/item behavior flags. |
| `ai_flags` | AI behavior bitfield. |
| `anim_counter` | Animation counter. |
| `state_flags` | State machine flags. |
| `hp` | Hit points. |
| `ai_state` | AI state. |
| `ai_timer` | Timer for AI logic. |
| `spwnX`, `spwnY` | Spawn coordinates. |
| `type_` | Monster type/sprite index. |
| `counter` | Generic per-monster counter. |

### `door`

Dungeon doors contain source coordinates, destination map id, destination coordinates, flags, key requirements, and achievement/save flag metadata.

### Platforms

- `vert_platform` contains `x` and `y`.
- `horiz_platform` contains encoded speed/direction flags, min X, and max X.

### Projectiles

`projectile` describes enemy shots, including relative coordinates, tile decomposition index, trajectory counters, direction, damage, cached VRAM address, and optional curved-path data.

`magic_projectile` describes hero magic projectiles and stores four cached VRAM addresses for a 2×2 tile footprint.

### Spirits

`spirit` stores orbit phase, speed, active shots, VRAM dirty address, and screen coordinates.

## Proximity and viewport buffers

The dungeon code uses:

```text
proximity_map         = 0E000h, 900h bytes
viewport_buffer_28x19 = 0E900h, 28*19 bytes
```

The proximity map is 36×64 tiles. The viewport buffer is 28×19 tiles. The proximity map wraps circularly, which allows horizontal movement across a larger map while keeping a fixed-size working window around the hero.

## Porting recommendation

Convert the memory map into typed runtime structs in this order:

1. `EngineState`, covering `0FFxxh` variables.
2. `SaveState`, covering `0000h..00E8h` player/event data.
3. `TownState`, covering `0C000h` town descriptor and NPC tables.
4. `DungeonState`, covering MDT descriptors, monsters, doors, platforms, projectiles, and proximity buffers.
5. `GraphicsBank`, covering `seg1`, `seg2`, and shadow framebuffer regions.

Do not flatten all addresses into a single global byte array forever. That helps initial compatibility, but it hides the actual design.
