# Dungeon gameplay engine, `fight.asm`

## Scope

This document explains the main dungeon/cavern gameplay engine:

- `fight.asm`, loaded at `org 6000h`
- `dungeon.inc`
- fight exports defined in `common.inc`

## Role of `fight.bin`

`fight.bin` is the largest gameplay module in the source tree. It implements the real-time dungeon/cavern mode.

High-level responsibilities:

- dungeon initialization,
- MDT map unpacking,
- hero walking, jumping, sliding, rope climbing, squatting,
- sword attacks,
- magic projectile firing,
- collision and passability checks,
- monster proximity culling,
- monster AI interface,
- monster and projectile damage,
- collectible item pickup,
- door and platform logic,
- boss setup and boss HUD,
- dungeon-to-town and dungeon-to-dungeon transitions.

Important procedures:

`Cavern_Game_Init`, `state_machine_dispatcher`, `hero_interaction_check`, `hero_knockback_handler`, `sliding_physics_step`, `init_horizontal_sliding`, `jump_press_handler`, `try_climb_rope`, `move_hero_up`, `left_up_pressed`, `move_hero_left_if_no_obstacles`, `is_right_airflow`, `right_up_pressed`, `flip_facing_direction`, `init_on_ground`, `move_hero_right_if_no_obstacles`, `is_left_airflow`, `airborne_movement`, `slope_assist_on_landing`, `down_pressed`, `hero_scroll_down`, `land_after_jump`, `check_floor_for_landing`, `is_over_rope`, `get_slope_direction_by_tile_under_feet`, `remove_accomplished_items`, `render_place_and_gold_labels`, `render_hud_bars_with_enemy`, `unpack_map`, `unpack_step_forward`, `unpack_step_backward`, `unpack_forward_case0`, `unpack_backward_case0`, `unpack_case1`, `unpack_case2`, `unpack_case3`, `unpack_column`, `coords_in_ax_to_proximity_map_addr_in_di`, `wrap_map_from_above`, `wrap_map_from_below`, `set_zero_flag_if_slippery`, `hero_coords_to_addr_in_proximity`, `get_dst_monster_flags`, `is_blocking_tile`, `is_blocking_tile_extended`, `is_blocking_tile_simple`, `input_handling`, `apply_sword_hit_to_map_tiles`, `main_update_render`, `game_loop_render_and_timing`, `screen_flash_overlay`, `bring_inventory_window`, `swap_eai_and_inventory_code_regions`, `load_place_and_reinit`, `clear_viewport_buffer`, `is_tile_safe_to_stay`, `render_notification_string`, `render_cavern_signs`, `clear_hero_in_viewport`, `step_on_aggressive_ground`, `check_hero_contact_damage`, `apply_hit_from_left`, `apply_hit_from_right`, `destroy_shield`, `get_monster_in_row_or_above`, `get_monster_one_row_above`, `damage_hero`, `check_airflows_on_hero`, `dispatch_airflows`, `get_airflow_direction`, `update_boss_heartbeat_volume`, `restore_game`, `process_doors`, `move_if_dst_high_bit_zero`, `calc_object_viewport_x_offset`, `prepare_dungeon`, `try_door_interaction`, `hero_left_16_down_1`, `edge_locking_scrolling_window`, `open_door`, `reset_dungeon_state_vars`, `process_mdt_descriptor`, `load_cavern_sprites_ai_music`, `sleep_loop_handle_system_keys`, `render_vertical_platforms_to_proximity`, `move_platform_down_damage_monster`, `try_move_platform_down`, `try_move_platform_up`, `find_platform_under_hero`, `identify_platform_tile`, `process_visible_collapsing_platforms`, `hero_collapse_platform`, `update_and_render_horiz_platforms`, `update_slow_horiz_platform_coords`, `update_horiz_platform_coords`, `hero_on_horiz_platform`, `abs_x_to_proximity_rel`, `horiz_platform_proximity_x_offset`, `put_dl_to_proximity_layered`, `update_and_render_projectile_row_pair`, `Browse_Projectiles`, `flush_dirty_projectile`, `restore_bg_tile_at_given_position`, `projectiles_collision_processing`, `sub_846F`, `projectile_y_vs_hero_row_dispatch`, `check_y_eq_projectile_row`, `check_prev_y_eq_projectile_row`, `check_next_y_eq_projectile_row`, `projectile_advance_position`, `decY`, `incX`, `incX_incY`, `decY_`, `decX`, `decX_incY`, `incY`, `decY__`, `projectile_read_curved_path_step`, `Add_Projectile_To_Array`, ... (180 total)

## Export table

The start of `fight.asm` declares an export table. Other modules call into these slots by using `fight.bin` base address plus slot×2.

Important entries:

| Slot | Routine | Purpose |
|---:|---|---|
| 0 | `Cavern_Game_Init` | Main dungeon entry/init. |
| 1 | `prepare_dungeon` | Prepare dungeon after town transition. |
| 2 | `monster_move_in_direction` | Move monster by directional angle. |
| 3 | `Check_collision_in_direction` | Directional collision check. |
| 4..11 | `move_monster_*` | Direction-specific monster movement. |
| 12..19 | `check_collision_*2` | Direction-specific collision helpers. |
| 20 | `coords_in_ax_to_proximity_map_addr_in_di` | Convert X/Y to proximity map pointer. |
| 21 | `wrap_map_from_above` | Wrap proximity pointer downward. |
| 22 | `wrap_map_from_below` | Wrap proximity pointer upward. |
| 23 | `is_blocking` | Tile blocking test. |
| 24 | `check_monster_on_aggressive_ground` | Ground damage/behavior for monsters. |
| 25 | `Check_Vertical_Distance_Between_Hero_And_Monster` | Monster/hero vertical relation. |
| 26 | `Hero_Hits_monster` | Sword/magic hit application. |
| 27 | `is_in_proximity_window` | Tests whether map X is inside 36-column window. |
| 28 | `Get_Stats` | Returns derived hero/combat values. |
| 29 | `Add_Projectile_To_Array` | Spawn enemy projectile. |
| 30 | `Browse_Projectiles` | Iterate/update projectile list. |
| 31 | `Find_Monsters_Near_Hero` | Proximity-cull monsters. |

## Coordinate system

The dungeon map is always 64 tile rows high and `map_width` columns wide.

The engine maintains:

```text
proximity_map         36 × 64 tiles at 0E000h..0E8FFh
viewport_buffer_28x19 28 × 19 tiles at 0E900h
```

The proximity map is a sliding horizontal window centered around the hero. It wraps circularly. The viewport buffer is the visible tile region used by the graphics driver.

The procedure `coords_in_ax_to_proximity_map_addr_in_di` expects:

```text
AL = y
AH = x
y &= 3Fh
DI = y * 36 + x + 0E000h
```

## MDT map format

The top comments in `fight.asm` describe the MDT file structure:

```text
[mdt_descriptor] 7 bytes
[cavern data] name strings, monsters, doors, platforms
[packed map] column-run-length encoded tile map, 64 rows × mapWidth columns
```

The packed map uses four encoding cases based on the high two bits of each byte. The unpacking path includes:

| Routine | Purpose |
|---|---|
| `unpack_map` | Top-level map unpacker. |
| `unpack_step_forward` | Decode forward step. |
| `unpack_step_backward` | Decode backward step. |
| `unpack_forward_case0` | Forward case 0. |
| `unpack_backward_case0` | Backward case 0. |
| `unpack_case1` | Encoding case 1. |
| `unpack_case2` | Encoding case 2. |
| `unpack_case3` | Encoding case 3. |
| `unpack_column` | Decode one packed column. |

## Dungeon initialization

`Cavern_Game_Init` begins by resetting the stack pointer and clearing runtime state:

- slide counters,
- projectile arrays,
- magic projectile state,
- boss flags,
- sprite flash flags,
- heartbeat flags.

Then it chooses one of three paths:

| Path | Condition | Behavior |
|---|---|---|
| Boss cavern | `is_boss_cavern != 0` | Draw enemy HUD, load boss music and encounter graphics, animate intro, load boss group, draw boss HP/name. |
| Jashiin cavern | `is_jashiin_cavern != 0` | Uses special shifted viewport and MDT behavior. |
| Regular cavern | otherwise | Draw place name, gold label, hero HP bars, initialize cavern. |

After common setup, the main dungeon loop begins.

## Main frame loop

The main loop inside `Cavern_Game_Init` is tightly coupled. It performs:

```text
rope state check
input_handling
sliding_physics_step
main_update_render
magic_spell_fire_handler
hero_interaction_check
hero_knockback_handler
state_machine_dispatcher
```

The state machine routes left/right/up/down/squat/jump conditions to the correct movement handler.

## Hero movement

Major movement routines include:

| Routine | Role |
|---|---|
| `jump_press_handler` | Starts or continues jump logic. |
| `try_climb_rope` | Enter rope-climb movement. |
| `move_hero_up` | Vertical rope/up movement. |
| `move_hero_left_if_no_obstacles` | Horizontal left with collision checks. |
| `move_hero_right_if_no_obstacles` | Horizontal right with collision checks. |
| `airborne_movement` | Air movement while jumping/falling. |
| `sliding_physics_step` | Ice/slope sliding. |
| `slope_assist_on_landing` | Adjusts movement after landing on slopes. |
| `down_pressed` | Squat/down handling. |
| `hero_scroll_down` | Viewport scroll when hero descends. |
| `land_after_jump` | Landing state transition. |
| `check_floor_for_landing` | Detects floor under hero. |

The engine uses many small flags: `squat_flag`, `on_rope_flags`, `jump_phase_flags`, `slope_direction`, and `hero_y_absolute`.

## Collision and blocking

The collision system is tile-based and proximity-map-based. Important routines:

| Routine | Role |
|---|---|
| `is_blocking_tile` | Tests blocking semantics for a tile. |
| `is_blocking_tile_extended` | Extended blocking variant. |
| `is_blocking_tile_simple` | Simple blocking variant. |
| `hero_coords_to_addr_in_proximity` | Converts hero coordinates to proximity map location. |
| `get_dst_monster_flags` | Reads monster/object flags at destination. |
| `is_tile_safe_to_stay` | Tests if hero can remain at current tile. |
| `set_zero_flag_if_slippery` | Slope/ice physics helper. |

The map is not just collision geometry. Tile values can imply doors, aggressive ground, items, ropes, slopes, and special interaction zones.

## Sword attacks

The sword system tracks:

| Symbol | Meaning |
|---|---|
| `sword_swing_flag` | Whether a swing is active. |
| `sword_hit_type` | 0 forward, 1 overhead, 2 downward thrust. |
| `sword_movement_phase` | Frame/phase of sword motion. |
| `down_thrust_held_flag` | Down-thrust state. |

Important routines include `apply_sword_hit_to_map_tiles`, `Hero_Hits_monster`, and graphics-driver calls such as `Render_Sword_Overlay_proc`.

## Magic projectiles

Hero magic projectiles use the `magic_projectile` structure from `dungeon.inc`. The fight module manages firing, movement, collision, and life timers. The graphics driver loads the current spell sprite group through `Load_Magic_Spell_Sprite_Group_proc`.

Spells referenced by save/inventory flags include:

```text
Espada, Saeta, Fuego, Lanzar, Rascar, Agua, Guerra
```

## Monsters

Monster entries are 16 bytes. `Find_Monsters_Near_Hero` culls active monsters into the proximity window. External AI modules can call fight movement/collision services through the fight export table.

Important monster-related routines:

| Routine | Role |
|---|---|
| `Find_Monsters_Near_Hero` | Find nearby monsters. |
| `move_monster_*` | Directional movement. |
| `Move_Monster_NWE_Depending_On_Whats_Below` | AI movement helper. |
| `get_monster_in_row_or_above` | Lookup monsters near hero's row. |
| `damage_hero` | Apply monster/projectile contact damage. |
| `check_hero_contact_damage` | Detect contact damage. |
| `step_on_aggressive_ground` | Ground/tile damage. |

Some table flags distinguish live AI monsters from static item-like entries such as keys, potions, chests, almas, signs, and shoes.

## Projectiles

Enemy projectiles use the `projectile` structure. The fight module supports:

- spawning projectiles,
- directional or curved trajectories,
- damage values,
- cached VRAM addresses,
- dirty redraw integration.

`Browse_Projectiles` iterates active projectiles and updates their state.

## Doors and transitions

Dungeon doors are described by `door` structures. `process_doors`, `try_door_interaction`, `open_door`, and transition routines manage movement between caverns or back to town.

Special fields include:

- Lion Key requirement,
- destination map id,
- destination X/Y,
- town transition marker,
- achievement flag address and mask.

## Boss flow

Boss caverns use `boss_state` from `dungeon.inc` and special branches in `Cavern_Game_Init`.

The boss path:

1. Draws enemy HUD.
2. Stops regular music.
3. Loads boss/encounter music.
4. Loads `ENCNT.GRP` for encounter intro.
5. Animates flashing encounter intervals.
6. Loads actual boss sprite group.
7. Decompresses boss graphics.
8. Renders boss name and HP bars.

Boss-specific logic can also be delegated to overlay modules such as `crab.bin`.

## Save/restore and death

`restore_game`, `remove_accomplished_items`, death flags, and transition code connect dungeon state back to the persistent save area. The code removes already-collected items from dungeon tables based on save flags.

## Porting notes

A faithful port should split `fight.asm` into these systems:

1. `DungeonMap`, for MDT descriptors, map unpacking, proximity window, and viewport buffer.
2. `HeroController`, for movement, rope, jump, slide, squat, sword phases.
3. `CollisionSystem`, for blocking, aggressive ground, doors, slopes, and ropes.
4. `MonsterSystem`, for monster tables, proximity culling, and AI service calls.
5. `ProjectileSystem`, for enemy and magic projectiles.
6. `DungeonTransitionSystem`, for doors, town return, boss/Jashiin special cases.
7. `DungeonRendererBridge`, for calls into `gfmcga.bin` and `gdmcga.bin` behavior.

Do not start by rewriting this as one giant update function. Preserve the old timing and state-machine behavior first, then refactor.
