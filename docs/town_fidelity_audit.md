# Town Fidelity Audit

Scope: keep the town hero movement anchored to the assembly-backed horizontal state and avoid reintroducing the provisional free 2D actor path.

## Assembly Inspected
- `asm/common.inc`: `hero_x_in_viewport`, `proximity_map_left_col_x`, `facing_direction`, `hero_animation_phase`
- `asm/game.asm`: `DrawDecorationsAroundCanvas` callsite, `render_tears_collected`, `tears_order_coords`, equipment render calls after MOLE
- `asm/gmmcga.asm`: `Render_Icon_16x13`, `byte_2A61`, `byte_2B31`
- `asm/mole.asm`: `DrawDecorationsAroundCanvas`, `mode4_mcga`, `Unpack2bppTo4bit_MCGA`, `DrawTitleFrame`
- `asm/town.asm`: `town_entry_common`, `game_loop_with_frame_wait`, `update_npcs_and_render`, left/right movement handlers, `handle_edge_screen_transition`, `prepare_hero_sprite`, `clear_6_hero_tiles_in_viewport_buffer`, `town_up_pressed`, `is_hero_close_to_npc`, `find_non_passable_npc_at_x_pos`, `npc_ai_look_at_hero_and_bob`, `npc_ai_bob_in_place`
- `asm/stick.asm`: `timer_ISR_int8_chained`, `Int_61_handler`, `frame_timer`, `speed_const`, `____right_left_down_up`
- `asm/gtmcga.asm`: `hero_column_shadow_blitter_guard`, `render_town_tiles_28_columns`, `special_tile_dispatcher`, `sprite_descriptor_table_scanner`, `sprite_compositor_dispatcher`, `get_sprite_vram_address`
- `asm/town.inc`: `NPC STRUC`, `town_tiles`, `town_head_level_tiles`, `viewport_buffer`

Town NPC AI type `0` now matches `npc_ai_look_at_hero_and_bob`: it faces Duke using `hero_x_in_viewport + 4 + proximity_map_left_col_x`, then runs the bob-in-place phase step that `get_sprite_vram_address` consumes through `n_facing` bit 7 and `n_anim_phase` low 2 bits.
Town NPC AI type `3` now mirrors `npc_ai_face_hero`: it uses the same hero absolute X comparison, flips `n_facing` bit 7 only, and leaves bobbing alone.
The parsed `tools/cmap.mdt` town data confirms NPC ID `2` uses AI type `3` with `X = 84`, `NpcSpriteSelector = 0x80`, `NpcAnimationPhase = 0x01`, `NpcFlags = 0x00`, and `NpcId = 2` (the checked-in `game/0/cmap.mdt` copy matches this record).
NPC runtime animation now advances from `TownScene::Update` instead of `Draw`, so rendering stays read-only. The previous logic-tick placement was still too fast because native `Update` is not the DOS `frame_timer` cadence; the town NPC gate now mirrors the assembly-proven standard town interval from PIT reload `0x13B1` and `speed_const = 5`.

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
- `ScrollOffsetPixels` now follows the canonical horizontal state by projecting `ProximityMapLeftColumnX + 4` into the scroll offset, matching the assembly-visible town column instead of the hidden proximity column.
- Town tiles now render in the original MCGA town viewport at `x = 48`, `y = 14 + 8 * 8 = 78`, with row `0` starting there and the row-5 NPC/hero band landing at `y = 118`.
- The NPC sprite compositor was feeding a screen-space row-5 Y into a helper that already adds the viewport origin, so the fix keeps NPC slices viewport-relative and lets the shared draw helper apply the origin once.
- The YMPD outdoor mountain layer is now decoded from `mountains0` at `0x05E7` and `mountains1` at `0x1459` into `88 x 56` byte planes, then drawn behind the town tiles at `x = 48`, `y = 14` with a `224 x 88` rendered footprint. The mountain RLE repeat byte is unsigned, so `0xFF` means 255 repeats.
- The original YMPD mountain pass is a one-shot VRAM background render at `A000:(48,14)`; it does not move with `proximity_map_left_col_x` and it is not redrawn by the town frame loop.
- The floor strip now scrolls horizontally in 8px steps when `proximity_map_left_col_x` changes, while staying anchored at `x = 48`, `y = 142`; the remaining CKPD scenic behavior above the town viewport is still provisional.
- Town pattern tiles now preserve their original mode byte and row mask bytes. The top three tile rows use the replacement cycle from `tile_animation_replacement_table`, while the masked static upper decorations keep their tile ids unless they have an explicit replacement entry. The native port advances that replacement step from `TownScene::Update()` on the DOS town-loop cadence (`TownDosTownLoopIntervalMilliseconds`, about 84.49 ms), so `Draw()` stays render-only.
- The MOLE top piece is semantically the Tears placeholders. Keep the raw labels `title_logo_data` and `title_demo_text_data` as source-label mappings only; do not rename the gameplay UI feature as `TitleLogo`, `TopLogo`, or `DemoText`.
- The MOLE Tears placeholder top bar still renders from those raw labels as a `224 x 13` band at `x = 48`, `y = 0`; the proven source spans are `0x04AE..0x073C` and `0x073D..0x08CC`.
- `mode4_mcga` seeds its unpack helper from the low byte of `cx` for each source byte, so the top bar starts with `bl = 0x0D` and the helper carries that state through the four pixel extractions before the caller restores the next byte seed.
- External guidance from br0x matched the split in broad strokes: `mole.bin` owns the left/right/top frame pieces, and `gmmcga` participates in the lower HUD. Treat that as context only, not primary proof.
- The full top Tears bar is not MOLE-only: after `DrawDecorationsAroundCanvas` returns, `game.asm` calls `render_tears_collected`, and this is the only inspected post-MOLE startup call that overlaps `y = 0..13`.
- `render_tears_collected` uses `Tears_of_Esmesanti_count` as the loop count, returns when it is zero, and draws the first `count` entries from `tears_order_coords`: `x = 60, 244, 84, 220, 108, 196, 132, 172, 152`, all at `y = 0`.
- `gmmcga.asm` `Render_Icon_16x13` is a transparent masked copy, not an OR blend: `0x80` pixels skip the write and all other pixels overwrite VRAM. The first eight Tears use icon `AL = 0`; the ninth center Tear uses icon `AL = 1`.
- `off_2A5D` in `gmmcga.bin` starts at file offset `0x0A5D`; `off_2A5D[0]` points to `byte_2A61` at `0x0A61` and `off_2A5D[1]` points to `byte_2B31` at `0x0B31`. Each icon is `16 x 13` bytes.
- The C++ town scene now reads the project-owned `TearsOfEsmesantiCount` byte. It defaults to `0`, the overlay clamps to `9`, and the optional debug-only override can show all nine Tears for visual testing without changing gameplay state.
- Do not synthesize collected Tears or force a fake filled bar in normal runtime. If `TearsOfEsmesantiCount` stays `0`, the overlay stays hidden.
- The town frame also renders the MOLE decorative side panels from `mole.bin`: the left panel sits at `x = 0`, `y = 0`, the right panel sits at `x = 272`, `y = 0`, and the central `x = 48` town viewport stays unchanged.
- The MOLE bottom/status base panel is separate from the later `game.asm` / `gmmcga.asm` HUD contents: the `title_screen_final_data` span `0x2799..0x2926` is the `224 x 42` MOLE base panel at `x = 48`, `y = 158`, while the equipment icons, numbers, and status overlays remain a later draw layer.
- The collected Tears overlay path is proven: `game.asm` `render_tears_collected` (`game.asm:316..345`, called at `game.asm:148`) loops `Tears_of_Esmesanti_count` times over `tears_order_coords` (`game.asm:348..356`), each `dw` encoding `BH*256+BL` -> screen `x = BH*4`, `y = BL` (all `y = 0`). Icons: `gmmcga.asm` `Render_Icon_16x13` (`gmmcga.asm:1722..1763`) reads `off_2A5D[AL]` -> `byte_2A61` (`AL=0`, small blue, `gmmcga.asm:1768`) or `byte_2B31` (`AL=1`, large red, `gmmcga.asm:1785`), `16 x 13`, `0x80` transparent.
## Collision And Scrolling
- The remaining collision work is deferred.
- Horizontal town movement now mirrors the assembly tile-ahead gate on row `7` before any move or scroll: left probes `ProximityMapLeftColumnX + HeroXInViewport + 3`, right probes `ProximityMapLeftColumnX + HeroXInViewport + 6`, and both still rely on `IsTownMapBlockedTileIndex` for the current native blocked-tile list.
- The NPC blocker path now matches the assembly's X-column scan and only treats `n_flags` bit 6 as non-passable.
- `ActorCollisionBlocked` is retained only as a debug/provisional field and is cleared by the projection sync.
- Edge scrolling is implemented narrowly from the confirmed left/right town thresholds by advancing `ProximityMapLeftColumnX` when the viewport needs to pan; once the map cannot scroll right any further, the native path keeps Duke walking in-viewport up to the provisional clamp instead of freezing at the scroll edge.
- The projection clamps scroll to the current map bounds, so the visible hero stays tied to the canonical horizontal state.
- The exact edge-transition wrap at the far left/right map boundary is still provisional in C++; `hero_x_in_viewport + 1 == 28` is the DOS right-edge transition check, `hero_x_in_viewport = 27` belongs to that transition path, and the native path currently clamps before that sentinel.

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
- The background driver runs before that town-frame pass, so the mountain layer sits behind the tile band and sprite overlays; the lower floor strip is only updated by the separate 8px panning helpers.
- `hero_column_shadow_blitter_guard` and the compositor routines remain rendering-only and were inspected only to confirm they are not part of the movement rewrite.
- `special_tile_dispatcher` only opens the NPC compositor when the row-5 tile is `0xFD`; the intermediate C++ path should treat that marker as opening a two-column special compositor area, then scan `npc_array_addr` by X and keep the current-column / next-column split through `two_sprite_shadow_compositor` and `single_sprite_shadow_compositor`.
- The intermediate SDL renderer must also defer or filter staged special-compositor slices so future-column slices are not overwritten by the later background pass.
- The town viewport projection now matches the proven MCGA origin; the YMPD mountain layer above the town tile band is now implemented, while CKPD scenic behavior and any byte-exact viewport-buffer behavior remain provisional.
- The lower strip scroll is now implemented as the proven 8px cyclic floor-band shift; what remains provisional is the rest of the scenic background driver and any byte-exact VRAM copy ordering outside that strip.
- The provisional free 2D town-movement helpers were removed from `town_scene.cpp`; the remaining town movement stays on the confirmed horizontal hero state.
- The DOS town loop still does not expose a proven held-input repeat cadence in a way that maps cleanly to one exact C++ frame delay, so the new movement cooldown is a small provisional throttle rather than a claimed perfect match.
- The current town NPC timing gate uses the standard DOS town wait threshold of `speed_const * 4 = 20` PIT ticks. With PIT input `1193182 Hz` and reload `0x13B1 = 5041`, the interval is `20.0 / (1193182.0 / 5041.0) ≈ 0.08449 s` per NPC logic update, so the visible bob phase changes about every `0.338 s` at standard speed. Speed controls are still not implemented in the native town view.
