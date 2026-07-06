# Dungeon and fight graphics drivers, `gdmcga.asm` and `gfmcga.asm`

## Scope

This document explains the dungeon/fight graphics modules:

- `gdmcga.asm`
- `gfmcga.asm`
- relevant graphics structures from `dungeon.inc` and `common.inc`

These modules share the `org 3000h` graphics-driver slot at different times or are loaded into auxiliary segment buffers depending on the active phase.

## Difference between `gdmcga` and `gfmcga`

| Module | Main role |
|---|---|
| `gdmcga.bin` | General dungeon graphics support: 3-plane decompression, masked blits, tile grid rendering, scrolling borders, simple text, clearing, animated tile rows. |
| `gfmcga.bin` | Fight/cavern runtime renderer: dirty tiles, animated cavern tiles, hero sprite composition, sword overlay, monsters/entities, boss effects, tile cache, Roca tilemap. |

`gdmcga` is closer to decompression/drawing primitives. `gfmcga` is closer to the real-time renderer used during dungeon gameplay.

## `gdmcga.asm` export table

Important entries include:

| Slot | Routine | Purpose |
|---:|---|---|
| 0 | `NoOp` | Empty placeholder. |
| 1 | `Decompress_3Plane_2Row` | Decode 3-plane graphics, two source rows per destination row. |
| 2 | `Decompress_3Plane_Interleaved` | Interleaved source decode variant. |
| 3 | `Render_With_MaskErase_Callback` | Mask erase render callback. |
| 4 | `GDMCGA_Fade_Palette` | Palette fade. |
| 5 | `Clear_Seg2_Buffer` | Clear auxiliary buffer. |
| 6 | `Render_Text_String` | Render text. |
| 7 | `Blit_Sprite_To_Screen` | Sprite blit. |
| 8 | `Decompress_And_Copy_To_VRAM` | Decode and copy to video memory. |
| 9 | `Animate_Sprites` | Sprite animation support. |
| 10 | `Load_Tiles_From_Big_Block` | Tile load helper. |
| 11 | `Load_Tiles_From_Small_Block` | Tile load helper. |
| 12 | `GDMCGA_Clear_Viewport` | Clear dungeon viewport. |
| 14 | `Render_Tile_Grid` | Draw a tile grid. |
| 15 | `Blit_And_Or_Xor_Masked` | Composite using AND/OR/XOR style masks. |
| 16 | `Render_Scrolling_Border` | Draw animated/scrolled border. |
| 17 | `Render_Animated_Tiles` | Animated tile draw path. |
| 18 | `GDMCGA_Draw_Bordered_Rect` | Bordered rectangle for dungeon context. |
| 19 | `Pack_3Plane_And_Render` | Pack planar data and draw. |
| 24 | `GDMCGA_Font_Glyph_Thunk` | Font glyph bridge. |

Important procedures:

`Decompress_3Plane_2Row`, `Render_8Plane_Loop`, `Render_SetOr_Pixel`, `Render_SetOr_Transparent`, `Render_MaskErase_2bpp`, `Render_Text_String`, `Expand_1bpp_To_2bpp`, `Blit_Sprite_To_Screen`, `Decompress_And_Copy_To_VRAM`, `Animate_Sprites`, `Copy_VRAM_Block_Fwd`, `Copy_VRAM_Block_Rev`, `Blit_Masked_OR_From_Seg1`, `Load_Tiles_From_Big_Block`, `Load_Tiles_From_Small_Block`, `GDMCGA_Clear_Viewport`, `Render_Tile_Grid`, `Render_Font_Glyph_8x8`, `Blit_And_Or_Xor_Masked`, `Render_Scrolling_Border`, `Render_Scrolling_Border_Row`, `Render_Border_Row_Composite`, `Render_Animated_Tiles`, `Render_Anim_Tile_Row`, `GDMCGA_Draw_Bordered_Rect`, `Draw_BorderedRect_TopRow`, `Draw_BorderedRect_SideRows`, `Draw_BorderedRect_Corner`, `Pack_3Plane_And_Render`, `Render_Animated_Tile_Rows`, `Decompress_And_Render_Tile`, `Render_Partial_Width_Tile`, `Setup_HUD_Frame`, `Write_VRAM_HLine`, `Render_Tile_Rows_TopDown`, `Render_TileRow_TopDown`, `Render_Tile_Rows_BottomUp`, `Render_TileRow_BottomUp`, `GDMCGA_Clear_HUD_Bar`, `GDMCGA_Fade_Palette`, `Decompress_3Plane_To_2bpp`, `Generate_AND_Mask_From_2bpp`, `Clear_Seg2_Buffer`, `GDMCGA_Font_Glyph_Thunk`, `Calc_VRAM_Addr`, `NoOp`

## `gfmcga.asm` export table

The `gfmcga` table is defined in `dungeon.inc` as procedure offsets `3000h..302Ah`.

| Offset | Routine | Purpose |
|---:|---|---|
| `3000h` | `Refresh_Dirty_Tiles` | Main dirty tile renderer. |
| `3002h` | `Sample_Neighborhood_Attributes` | Attribute sampling around viewport. |
| `3004h` | `Flush_Ui_Element_If_Dirty` | Flush dirty UI element. |
| `3006h` | `Render_Sword_Overlay` | Draw active sword overlay. |
| `3008h` | `Uncompress_And_Render_Tile` | Decode and draw a tile. |
| `300Ah` | `Viewport_Coords_To_Screen_Addr` | Convert viewport tile coordinates to VRAM offset. |
| `300Eh` | `Dungeon_Static_Tile_Cached_Drawer` | Draw cached static tile. |
| `3010h` | `Boss_Explosions_Renderer` | Draw boss explosion rings. |
| `3012h` | `Render_Viewport_Tiles` | Render full viewport tile set. |
| `3014h` | `Copy_Hero_Frame_To_VRAM` | Copy composed hero frame. |
| `3016h` | `Update_Local_Attribute_Cache` | Update local tile attributes. |
| `3018h` | `Render_Viewport_Border_Walls` | Draw border walls. |
| `301Ah` | `Load_Magic_Spell_Sprite_Group` | Load spell sprite group. |
| `301Ch` | `Render_Animated_Tile_Strip` | Draw animated tile strip. |
| `301Eh` | `Render_Roca_Tilemap` | Render Roca tilemap with palette transforms. |
| `3020h` | `Calculate_Tile_VRAM_Address` | Compute tile screen address. |
| `3022h` | `Render_16x16_Sprite` | Draw 16×16 sprite. |
| `3024h` | `Render_Status_Indicator` | Draw status indicator. |
| `3026h` | `Render_Entity_Sprite` | Draw monster/entity sprite. |
| `3028h` | `Decompress_Tile_Data` | Decompress tile data and masks. |
| `302Ah` | `NoOperation` | Empty placeholder. |

Important procedures:

`Refresh_Dirty_Tiles`, `Process_Dirty_Tile_With_Animation`, `Animate_Water_Cavern5`, `Animate_Gold_Magma_Cavern6`, `Animate_Hot_Cavern7`, `Animate_Thorn_Cavern8`, `Dungeon_Static_Tile_Cached_Drawer`, `Render_Top_Left_Corner_Entity`, `Render_Tile_With_Attribute_Cache`, `Render_Top_Right_Corner_Entity`, `Render_Tile_With_Dual_Cache`, `Render_Tile_With_Border_Check`, `Render_Tile_And_Update_Cache`, `Render_Tile_Neighborhood_Cell`, `Decode_And_Render_MonsterEntity_Tile_With_Blit`, `decode_and_render_tile_with_blitting`, `four_pixels_or_blit`, `render_nibble_compressed_tile`, `draw_4_pix_from_table_by_ax`, `get_pixel_from_table_by_ax_hi_nibble`, `Copy_Tile_To_VRAM`, `render_48bytes_packed_tile`, `Clear_Tile_Buffer`, `get_from_layer2`, `Lookup_Monster_Tile_Attributes`, `Spawn_Boss_Explosion_Ring`, `Boss_Explosions_Renderer`, `Update_Local_Attribute_Cache`, `hero_background_continue`, `Render_Hero_Sprite_To_Buf9`, `get_player_shield_category`, `Render_Empty_Or_Cached_Tile`, `Render_Tile_With_Palette`, `load_3x3_tiles`, `render_hero_sword`, `Render_Sword_Overlay`, `Flush_Ui_Element_If_Dirty`, `Copy4x4TilesFromScreenToShadowBuffer`, `Blit32x32SpriteToVram`, `Clear_Tile_Cache_Around_Hero`, `CalculateSpriteBitmask`, `Calculate_Tile_VRAM_Address`, `Copy_Hero_Frame_To_VRAM`, `Uncompress_And_Render_Tile`, `Render_Viewport_Tiles`, `render_tile`, `RenderTileRowWithMask`, `ClearTileRowWithMask`, `CalculateTileOffset`, `Render_Viewport_Border_Walls`, `RenderBorderRings`, `RenderBorderSegment`, `RenderOrthogonalSegments`, `DrawVerticalLine`, `DrawHorizontalLine`, `CalculateRowVRAMAddress`, `WaitForVBlankAndDelay`, `DrawDitheredPattern`, `Viewport_Coords_To_Screen_Addr`, `Load_Magic_Spell_Sprite_Group`, `wrap_e900_from_above`, `wrap_e000_from_below`, `Render_Animated_Tile_Strip`, `Render_Roca_Tilemap`, `RenderTileFrom_seg1`, `Render8pxWithPaletteTransform`, `PaletteTransform_0`, `PaletteTransform_1`, `PaletteTransform_2`, `PaletteTransform_3`, `PaletteTransform_4`, `Render_16x16_Sprite`, `Unpack_4MaskBytes`, `Render_Status_Indicator`, `Render_Entity_Sprite`, `Decompress_Tile_Data`, `build_16_bits_from_2_planes`, `extract_transparency_byte_from_mask_plane_f`, `nullsub_1`

## `gdmcga` planar decompression

`gdmcga` contains routines such as:

- `Decompress_3Plane_2Row`,
- `Decompress_3Plane_Interleaved`,
- `Decompress_3Plane_To_2bpp`,
- `Generate_AND_Mask_From_2bpp`.

These routines convert planar graphics into packed pixel representations and masks suitable for MCGA drawing.

The common pattern is:

```text
read one or more plane words
rotate/shift bits into packed pixel values
emit rows to seg3 or VRAM
optionally build AND masks for transparency
```

## `gfmcga` dirty tile renderer

`Refresh_Dirty_Tiles` is the main cavern tile refresh routine. It clears tile cache state, increments a render counter, samples the proximity map near the viewport, checks high-bit entity markers, and renders only tiles that changed or require animation.

Conceptual flow:

```text
clear tile_vram_cache
set viewport row VRAM offset
sample top-left corner entity marker
process row/column tile attributes
for rows in viewport:
  render hero sword overlay if needed
  compare proximity tile with viewport buffer
  render dirty or animated tiles
  update cache and viewport buffer
handle border/corner cases
```

The viewport is 28×19 tiles. The code uses the 36×64 proximity map as the source and the 28×19 viewport buffer as the previous-frame cache.

## Cavern animated tiles

`gfmcga` contains special animation procedures by cavern type:

| Routine | Likely cavern/effect |
|---|---|
| `Animate_Water_Cavern5` | Water animation. |
| `Animate_Gold_Magma_Cavern6` | Gold/magma animation. |
| `Animate_Hot_Cavern7` | Heat/lava animation. |
| `Animate_Thorn_Cavern8` | Thorn animation. |

These update tile IDs or palette/attribute behavior in the viewport render path.

## Static tile cache

`Dungeon_Static_Tile_Cached_Drawer`, `Render_Tile_With_Attribute_Cache`, `Render_Tile_With_Dual_Cache`, and related helpers reduce redraw cost. The renderer often stores or compares local attributes so it can avoid recomputing packed tile output.

## Tile format

Dungeon static tiles use packed 8×8 formats similar to the town format, but there are multiple source modes:

- `mpp?.grp` for cavern static tile sets,
- `dchr.grp` for doors/platforms and special objects,
- monster/entity GRPs for 16×16 sprites,
- hero `fman.grp` for 24×24 frames.

The renderer has both 48-byte packed tile paths and nibble/plane decode paths.

## Hero rendering

The dungeon hero is not a single flat sprite. The source comments in `fight.asm` describe `fman.grp` as a 3×3 grid of 8×8 tiles, 24×24 pixels per frame.

`gfmcga` composes:

- body,
- right hand,
- optional shield,
- sword overlay,
- possible flashing/damage states.

Relevant routines:

| Routine | Role |
|---|---|
| `Render_Hero_Sprite_To_Buf9` | Compose hero sprite into a buffer. |
| `get_player_shield_category` | Select shield drawing variant. |
| `render_hero_sword` | Integrate sword phase. |
| `Render_Sword_Overlay` | Draw sword overlay. |
| `Copy4x4TilesFromScreenToShadowBuffer` | Save background area. |
| `Copy_Hero_Frame_To_VRAM` | Copy final hero frame to screen. |
| `Clear_Tile_Cache_Around_Hero` | Force redraw around hero. |

## Monster/entity rendering

Entity graphics use routines such as:

| Routine | Role |
|---|---|
| `Lookup_Monster_Tile_Attributes` | Get tile/sprite attributes for monster. |
| `Decode_And_Render_MonsterEntity_Tile_With_Blit` | Decode monster tile and composite. |
| `Render_16x16_Sprite` | Draw standard 16×16 sprite. |
| `Render_Entity_Sprite` | Main monster/entity sprite routine. |
| `Unpack_4MaskBytes` | Decode sprite mask bytes. |

The monster/entity path uses palette decode tables and masks rather than simple opaque tile copying.

## Boss explosions

`Boss_Explosions_Renderer` and `Spawn_Boss_Explosion_Ring` render special explosion effects. These use cached ring data and dirty VRAM markers so the fight engine can update boss death/hit effects efficiently.

## Roca tilemap and palette transforms

`Render_Roca_Tilemap` renders the `roka.grp` special tilemap. The code includes:

- `roca_tile_indices_28x18`,
- `RenderTileFrom_seg1`,
- `Render8pxWithPaletteTransform`,
- `PaletteTransform_0` through `PaletteTransform_4`.

This supports animated or remapped palette modes without needing to duplicate tile graphics.

## Viewport coordinate conversion

`Viewport_Coords_To_Screen_Addr` and `Calculate_Tile_VRAM_Address` map tile positions to `A000h` offsets. The base viewport starts at `viewport_top_left_vram_offset = 48 + 14*320`.

The game uses a 28×19 tile viewport in dungeon mode, which corresponds to 224×152 pixels inside the 320×200 screen.

## Porting notes

Suggested implementation order:

1. Implement a 320×200 indexed framebuffer.
2. Implement 8×8 packed tile decoding for `mpp?.grp` and `dchr.grp`.
3. Implement the 36×64 proximity map and 28×19 viewport buffer.
4. Implement dirty tile comparison.
5. Implement hero 24×24 frame composition.
6. Implement entity 16×16 sprite rendering and masks.
7. Add palette transforms and Roca rendering.
8. Add boss explosion effects.

Do not begin with boss or hero composition. Start with static tiles and dirty redraw, then layer sprites.
