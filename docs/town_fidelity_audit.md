# Town Fidelity Audit

Scope: keep the town hero movement anchored to the assembly-backed horizontal state and avoid reintroducing the provisional free 2D actor path.

## Assembly Inspected
- `asm/common.inc`: `hero_x_in_viewport`, `proximity_map_left_col_x`, `facing_direction`, `hero_animation_phase`
- `asm/town.asm`: `town_entry_common`, `game_loop_with_frame_wait`, `update_npcs_and_render`, left/right movement handlers, `handle_edge_screen_transition`, `prepare_hero_sprite`, `clear_6_hero_tiles_in_viewport_buffer`, `town_up_pressed`, `is_hero_close_to_npc`, `find_non_passable_npc_at_x_pos`
- `asm/stick.asm`: `timer_ISR_int8_chained`, `Int_61_handler`, `frame_timer`, `speed_const`, `____right_left_down_up`
- `asm/gtmcga.asm`: `hero_column_shadow_blitter_guard`, `render_town_tiles_28_columns`, `special_tile_dispatcher`, `sprite_descriptor_table_scanner`, `sprite_compositor_dispatcher`
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
- The old town camera-follow toggle was removed; the town view now projects from the canonical horizontal hero state only.

## Movement Mapping
- Normal town updates now read the canonical horizontal state instead of the provisional free 2D actor movement.
- Left and right are the only movement inputs that change town position in normal mode.
- Up and down no longer move Duke vertically in normal town mode.
- Left updates `FacingDirection` bit 0 to `1` and right clears it back to `0`.
- Each successful horizontal step increments `HeroAnimationPhase` and masks it with `3`.
- The main input dispatch also forces `HeroAnimationPhase` bit 0 on when no horizontal move occurs, which keeps the standing pose aligned with the assembly path.
- `TownMovementFrameCountdown` and `TownMovementFrameDelay` remain provisional. The assembly does not show a town-local fixed repeat cadence, so the C++ throttle is still only a stopgap.
- `ActorMapPixelX`, `ActorMapPixelY`, `ActorFacingDirection`, `ActorAnimationPhase`, and `ScrollOffsetPixels` are now projections of `TownHeroState`, not the source of truth.

## Rendering Projection
- Visible hero X is derived from `TownHeroState` and projected into `ActorMapPixelX`.
- Visible hero Y stays fixed at `TownMapActorInitialMapPixelY` for now, and the renderer adds the proven town viewport origin when drawing.
- `ScrollOffsetPixels` now follows the canonical horizontal state by projecting `ProximityMapLeftColumnX` into the scroll offset.
- Town tiles now render in the original MCGA town viewport at `x = 48`, `y = 14 + 8 * 8 = 78`, with row `0` starting there and the row-5 NPC/hero band landing at `y = 118`.
- The NPC sprite compositor was feeding a screen-space row-5 Y into a helper that already adds the viewport origin, so the fix keeps NPC slices viewport-relative and lets the shared draw helper apply the origin once.
- The YMPD outdoor mountain layer is now decoded from `mountains0` at `0x05E7` and `mountains1` at `0x1459` into `88 x 56` byte planes, then drawn behind the town tiles at `x = 48`, `y = 14` with a `224 x 88` rendered footprint. The mountain RLE repeat byte is unsigned, so `0xFF` means 255 repeats.
- The floor strip now scrolls horizontally in 8px steps when `proximity_map_left_col_x` changes, while staying anchored at `x = 48`, `y = 142`; the remaining CKPD scenic behavior above the town viewport is still provisional.
## Collision And Scrolling
- The remaining collision work is deferred.
- The NPC blocker path now matches the assembly's X-column scan and only treats `n_flags` bit 6 as non-passable.
- `ActorCollisionBlocked` is retained only as a debug/provisional field and is cleared by the projection sync.
- Edge scrolling is implemented narrowly from the confirmed left/right town thresholds by advancing `ProximityMapLeftColumnX` when the viewport needs to pan.
- The projection clamps scroll to the current map bounds, so the visible hero stays tied to the canonical horizontal state.
- The exact edge-transition wrap at the far left/right map boundary is still provisional in C++; the right-edge sentinel now matches the assembly (`hero_x_in_viewport = 28`), but the destination loader path is intentionally out of scope here.

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
- `special_tile_dispatcher` only opens the NPC compositor when the row-5 tile is `0xFD`; the intermediate C++ path should treat that marker as opening a two-column special compositor area, then scan `npc_array_addr` by X and keep the current-column / next-column split through `two_sprite_shadow_compositor` and `single_sprite_shadow_compositor`.
- The intermediate SDL renderer must also defer or filter staged special-compositor slices so future-column slices are not overwritten by the later background pass.
- The town viewport projection now matches the proven MCGA origin; the YMPD mountain layer above the town tile band is now implemented, while CKPD scenic behavior and any byte-exact viewport-buffer behavior remain provisional.
- The lower strip scroll is now implemented as the proven 8px cyclic floor-band shift; what remains provisional is the rest of the scenic background driver and any byte-exact VRAM copy ordering outside that strip.
- The provisional free 2D town-movement helpers were removed from `town_scene.cpp`; the remaining town movement stays on the confirmed horizontal hero state.
- The DOS town loop still does not expose a proven held-input repeat cadence in a way that maps cleanly to one exact C++ frame delay, so the new movement cooldown is a small provisional throttle rather than a claimed perfect match.
