# Town Fidelity Audit

Scope: keep the town hero movement anchored to the assembly-backed horizontal state and avoid reintroducing the provisional free 2D actor path.

## Assembly Inspected
- `asm/common.inc`: `hero_x_in_viewport`, `proximity_map_left_col_x`, `facing_direction`, `hero_animation_phase`
- `asm/town.asm`: `town_entry_common`, `game_loop_with_frame_wait`, `update_npcs_and_render`, left/right movement handlers, `handle_edge_screen_transition`, `prepare_hero_sprite`, `clear_6_hero_tiles_in_viewport_buffer`, `town_up_pressed`, `is_hero_close_to_npc`, `find_non_passable_npc_at_x_pos`
- `asm/stick.asm`: `timer_ISR_int8_chained`, `Int_61_handler`, `frame_timer`, `speed_const`, `____right_left_down_up`
- `asm/gtmcga.asm`: `hero_column_shadow_blitter_guard`, `render_town_tiles_28_columns`, `sprite_descriptor_table_scanner`, `sprite_compositor_dispatcher`
- `asm/town.inc`: `NPC STRUC`, `town_tiles`, `town_head_level_tiles`, `viewport_buffer`

## Canonical Horizontal Model
- `TownHeroRuntimeState.HeroXInViewport` maps to `hero_x_in_viewport`.
- `TownHeroRuntimeState.ProximityMapLeftColumnX` maps to `proximity_map_left_col_x`.
- `TownHeroRuntimeState.FacingDirection` maps to `facing_direction`, and bit 0 still means `0=right, 1=left`.
- `TownHeroRuntimeState.HeroAnimationPhase` maps to `hero_animation_phase`.
- `GetTownHeroAbsoluteX()` remains the canonical absolute X helper: `ProximityMapLeftColumnX + HeroXInViewport + 4`.
- The initial state is still the conservative mirror:
  - `HeroXInViewport = 12`
  - `ProximityMapLeftColumnX = 4`
  - `FacingDirection = 0`
  - `HeroAnimationPhase = 0`

## Movement Mapping
- Normal town updates now read the canonical horizontal state instead of the provisional free 2D actor movement.
- Left and right are the only movement inputs that change town position in normal mode.
- Up and down no longer move Duke vertically in normal town mode.
- Left updates `FacingDirection` bit 0 to `1` and right clears it back to `0`.
- Each successful horizontal step increments `HeroAnimationPhase` and masks it with `3`.
- C++ now gates horizontal repeat with `TownMovementFrameCountdown` and `TownMovementFrameDelay` instead of advancing every render/update frame.
- `ActorMapPixelX`, `ActorMapPixelY`, `ActorFacingDirection`, `ActorAnimationPhase`, and `ScrollOffsetPixels` are now projections of `TownHeroState`, not the source of truth.

## Rendering Projection
- Visible hero X is derived from `TownHeroState` and projected into `ActorMapPixelX`.
- Visible hero Y stays fixed at `TownMapActorInitialMapPixelY` for now.
- `ScrollOffsetPixels` now follows the canonical horizontal state by projecting `ProximityMapLeftColumnX` into the scroll offset.
- `CameraFollowEnabled` is no longer part of the normal town movement path.

## Collision And Scrolling
- Collision is deferred.
- I did not implement the full assembly-backed blocker path from `check_tile_in_special_list` plus `find_non_passable_npc_at_x_pos`.
- `ActorCollisionBlocked` is retained only as a debug/provisional field and is cleared by the projection sync.
- Edge scrolling is implemented narrowly from the confirmed left/right town thresholds by advancing `ProximityMapLeftColumnX` when the viewport needs to pan.
- The projection clamps scroll to the current map bounds, so the visible hero stays tied to the canonical horizontal state.

## Removed From Normal Town Mode
- The free 4-way pixel movement path no longer drives normal town updates.
- The manual page-up/page-down camera scroll path is disconnected from town movement.
- The old pixel-probe collision path is no longer canonical.
- `TownMapActorFacingDirection::Up` and `Down` remain provisional and are not part of normal town walking.

## Provisional Fields That Remain
- `TownMovementFrameCountdown`
- `TownMovementFrameDelay`
- `ActorAnimationTickCount`
- `ActorCollisionBlocked`
- `CameraFollowEnabled`
- `BlockedTileOverlayEnabled`
- `TownEntityMarkersEnabled`
- `ActorMapPixelY`
- `TownMapActorInitialMapPixelY`
- `ActorMapPixelX` remains a projection only

## Next Smallest Safe Gameplay Step
- Implement the exact assembly-backed collision test for left/right movement, including the NPC blocker scan, then wire `town_up_pressed` only after that horizontal gate is stable.

## Notes
- `game_loop_with_frame_wait` still matches the assembly order: `prepare_hero_sprite`, `clear_6_hero_tiles_in_viewport_buffer`, then `render_town_tiles_28_columns`.
- `hero_column_shadow_blitter_guard` and the compositor routines remain rendering-only and were inspected only to confirm they are not part of the movement rewrite.
- The DOS town loop still does not expose a proven held-input repeat cadence in a way that maps cleanly to one exact C++ frame delay, so the new movement cooldown is a small provisional throttle rather than a claimed perfect match.
