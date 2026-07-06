# Town Fidelity Audit

Scope: confirm the town hero position and movement model before adding hero-relative NPC AI.

## Assembly inspected
- `asm/town.inc`: `NPC STRUC`, `town_tiles`, `town_head_level_tiles`, `viewport_buffer`
- `asm/common.inc`: `hero_x_in_viewport`, `proximity_map_left_col_x`, `facing_direction`, `hero_animation_phase`
- `asm/town.asm`: `game_loop_with_frame_wait`, `update_npcs_and_render`, `prepare_hero_sprite`, `clear_6_hero_tiles_in_viewport_buffer`, left/right movement handlers, `town_up_pressed`, `handle_edge_screen_transition`, `town_entry_common`, `is_hero_close_to_npc`, `find_non_passable_npc_at_x_pos`
- `asm/gtmcga.asm`: `hero_column_shadow_blitter_guard`, `render_town_tiles_28_columns`, `sprite_descriptor_table_scanner`, `sprite_x_coordinate_lookup`, `sprite_compositor_dispatcher`

## Confirmed Town Hero Model
- `hero_x_in_viewport` is the town hero's viewport X byte.
- I found no town hero Y position in the inspected town assembly. The town code uses horizontal state only for walking and interaction.
- When town code needs absolute X, it combines `proximity_map_left_col_x + hero_x_in_viewport + 4`.
- `town_entry_common` sets `hero_animation_phase = 0`, but it does not assign a town X value.
- The only confirmed town-mode X assignments I found are:
  - left-edge transition: `hero_x_in_viewport = 26`
  - right-edge transition: `hero_x_in_viewport = 0`
  - falter warp: `hero_x_in_viewport = 0Dh`
- The initial town X at first entry is still a gap in the inspected assembly.

## Confirmed Movement Model
- Town walking is horizontal only.
- The left and right handlers:
  - test the tile ahead with `check_tile_in_special_list`
  - block movement if `find_non_passable_npc_at_x_pos` finds a non-passable NPC at the destination X
  - increment `hero_animation_phase` and mask it with `3`
  - update `facing_direction` bit 0
  - either move the hero one viewport column or trigger scrolling
- Left movement scrolls once `hero_x_in_viewport < 11`.
- Right movement scrolls once `hero_x_in_viewport >= 16` and the map still has room.
- Scrolling shifts `proximity_map_left_col_x` and `proximity_start_tiles`, then calls the floor and ceiling scroll routines.

## Confirmed Facing And Animation
- `facing_direction` bit 0 is the town-facing bit.
- In town movement, left sets bit 0 and right clears it.
- `hero_animation_phase` is not a frame timer. In town it is:
  - reset to `0` on town entry
  - ORed with `1` on up-arrow, spacebar interaction, and some dialog paths
  - set to `4` for door, falter, and facing-from-viewer transitions
  - advanced by movement with `inc` followed by `and 3`
- `prepare_hero_sprite` uses `facing_direction` bit 0 to choose left/right hero art and uses `hero_animation_phase` as the walking-frame index.

## Interaction And Comparison Rules
- `town_up_pressed` computes absolute hero X from `proximity_map_left_col_x + hero_x_in_viewport + 4` and matches doors by X only.
- `is_hero_close_to_npc` compares the hero's absolute X against `NPC.n_x` only when the hero's 1x3 row buffer contains `0xFD`.
- `find_non_passable_npc_at_x_pos` scans the NPC array for exact X matches with `n_flags` bit 6 set, and movement uses it as the horizontal blocker test.

## Current C++ Mismatches
- `src/town/town_scene.h:125-148` still models the hero as a 2D actor with `ActorMapPixelX`, `ActorMapPixelY`, `TownMapActorInitialMapPixelX/Y`, `CameraFollowEnabled`, `ActorCollisionBlocked`, and `ActorAnimationTickCount`.
- `src/town/town_scene.cpp:592-681` implements free 4-way pixel movement at 2 px per step; town assembly only confirms horizontal left/right movement.
- `src/town/town_scene.cpp:1104-1118` adds manual page-up/page-down camera scrolling; town assembly only confirms automatic edge scroll.
- `src/town/town_scene.cpp:320-323,493-524,606-680` uses hardcoded blocked tiles `0x3C` and `0x3D` plus pixel-probe collision; town assembly uses `check_tile_in_special_list` and `find_non_passable_npc_at_x_pos`.
- `src/town/town_scene.cpp:1189-1209` exposes debug HUD fields that are useful for inspection, but they are not the town assembly's canonical hero state.
- `src/town/town_scene.cpp:825-906` still keeps NPC AI mostly inert; only the bob-in-place phase step for `AiType == 4` is confirmed in C++.

## Debug-Only Or Provisional
- Safe to keep as debug-only:
  - `CameraFollowEnabled`
  - `ActorCollisionBlocked`
  - `BlockedTileOverlayEnabled`
  - `TownEntityMarkersEnabled`
- Provisional and not canonical for town movement:
  - `ActorMapPixelY`
  - `TownMapActorInitialMapPixelY`
  - `ActorAnimationTickCount`
  - `TownMapActorFacingDirection::Up` and `Down`
- `ActorMapPixelX` can remain as a projection or debug field, but it should not be the authoritative town hero state.

## npc_ai_face_hero Gate
- `npc_ai_face_hero` is not safe to implement yet.
- It depends on a corrected horizontal hero model because the current C++ hero state is still pixel-space and 2D, while the assembly town logic is viewport-X plus map-left-column offset.

## Smallest Safe Next Step
- Introduce a canonical town-hero state split with confirmed horizontal fields only: `hero_x_in_viewport`, `proximity_map_left_col_x`, `facing_direction` bit 0, and `hero_animation_phase`.
- Keep the current 2D and camera-related fields read-only or diagnostic until the horizontal movement path is rebuilt from the assembly.
- Do not wire `npc_ai_face_hero` until that split exists.

## Notes
- `game_loop_with_frame_wait` is confirmed to call `prepare_hero_sprite`, then `clear_6_hero_tiles_in_viewport_buffer`, then `render_town_tiles_28_columns`.
- `hero_column_shadow_blitter_guard` and the sprite compositor routines are confirmed in `asm/gtmcga.asm`, but they remain rendering-only and are not part of the hero movement rewrite.
