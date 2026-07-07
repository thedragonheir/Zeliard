# Common MCGA UI and palette driver, `gmmcga.asm`

## Scope

This document explains the general MCGA graphics module:

- `gmmcga.asm`
- exports at `org 2000h`
- shared UI drawing used by town, dungeon, inventory, buildings, and demos

## Role of `gmmcga.bin`

`gmmcga.bin` is the always-available general graphics driver. It is loaded at offset `2000h` and provides UI services that are not specific to towns or dungeons.

It handles:

- bordered rectangles,
- viewport clearing,
- HUD bars,
- health bar normalization,
- font glyph rendering,
- strings,
- decimal number rendering,
- item icon rendering,
- inventory-style sprites,
- screen scrolling/capture/restore,
- fade to black,
- screen clear,
- 3-plane graphics reassembly.

Important procedures:

`Draw_Bordered_Rectangle`, `draw_one_scanline_of_bordered_horiz_bar`, `clear_rectangular_region`, `Clear_Viewport`, `Fade_To_Black_Dithered`, `Clear_HUD_Bar`, `draw_HUD_column_width_1`, `Draw_Hero_Max_Health`, `Draw_Hero_Health`, `normalize_health_to_100`, `draw_vertical_line`, `Render_Pascal_String_0`, `render_glyph`, `Clear_Place_Enemy_Bar`, `Print_Almas_Decimal`, `Print_Gold_Decimal`, `Print_Magic_Left_Decimal`, `Print_ShieldHP_Decimal`, `Prepare_Decimal_Display_Buffer`, `Convert_32bit_To_Decimal_Digits`, `_Divide_By_Rounding`, `_Divide_16_Get_High_Byte`, `Render_Decimal_Digits`, `_Render_Single_Digit_Glyph`, `Render_Sword_Item_Sprite_20x18`, `Render_Magic_Spell_Item_Sprite_16x16`, `Render_Shield_Item_Sprite_16x16`, `Render_Wearable_Item_Sprite_16x16`, `Render_Magic_Potion_Item_Sprite_16x16`, `Render_Key_Item_Sprite_16x16`, `Render_Crest_Item_Sprite_16x16`, `Render_3plane_16x16_Sprite`, `_Decode_4_Pixels_From_3_Planes`, `Render_Font_Glyph`, `Scroll_Screen_Rect_Down`, `Capture_Screen_Rect_to_seg3`, `Put_Image`, `Render_String_FF_Terminated`, `Copy_Screen_Rect_VRAM`, `Draw_Status_Frame`, `_Draw_Status_Frame_Lines`, `Render_Icon_16x13`, `Clear_Screen`, `Reassemble_3_Planes_To_Packed_Bitmap`, `assemble_48_bytes`, `assemble_48_bits`, `assemble_3_bits`

## Export table

The module begins with a function pointer table. `common.inc` assigns addresses to these table entries.

| Offset | Routine | Purpose |
|---:|---|---|
| `2000h` | `Draw_Bordered_Rectangle` | Draw or clear a rectangle. |
| `2002h` | `Clear_Viewport` | Clear the gameplay viewport. |
| `2004h` | `Clear_HUD_Bar` | Clear HUD area. |
| `2006h` | `Draw_Hero_Max_Health` | Draw max HP bar. |
| `2008h` | `Draw_Hero_Health` | Draw current HP. |
| `200Ah` | `Draw_Boss_Max_Health` | Draw boss max HP. |
| `200Ch` | `Draw_Boss_Health` | Draw boss current HP. |
| `200Eh` | `Render_Pascal_String_0` | Render positioned Pascal-style string. |
| `2010h` | `Render_Pascal_String_1` | Alternative Pascal string render entry. |
| `2012h` | `Clear_Place_Enemy_Bar` | Clear place/enemy label area. |
| `2014h..201Ah` | decimal printers | Almas, gold, magic, shield HP. |
| `201Ch..203Eh` | sprite/icon renderers | Sword, magic, shield, wearables, keys, crests, icon drawing. |
| `2040h` | `Fade_To_Black_Dithered` | Dithered fade effect. |
| `2042h` | `Clear_Screen` | Full screen clear. |
| `2044h` | `Reassemble_3_Planes_To_Packed_Bitmap` | Convert planar data into packed tile/sprite data. |

## Coordinate model

The code assumes a 320-byte row stride. It computes screen addresses as:

```text
address = y * 320 + x
```

Many UI calls encode X in tiles or 4-pixel units, not always raw pixels. For example, rectangle width may be passed as words, which correspond to two pixels per word. Some text routines use left margins in 4-pixel units because the thin font is compact.

## Rectangle drawing

`Draw_Bordered_Rectangle` accepts:

| Register | Meaning |
|---|---|
| `BH` | Left margin. |
| `BL` | Top margin. |
| `CL` | Height in rows. |
| `CH` | Width in words, where one word is two pixels. |
| `AL` | `0` fill black, non-zero draw border. |

When `AL = 0`, it jumps to `clear_rectangular_region`. Otherwise it draws a border using color values that depend on `font_highlight_flag`.

This routine is heavily used by dialogs, shops, inventory windows, and save/restore UI.

## HUD and health bars

The health routines normalize HP values to a display width. `normalize_health_to_100` converts current/max values into a 0..100 display scale. Then the bar routines draw vertical/horizontal segments.

The boss HP paths reuse the same visual logic as the hero HP paths but draw into the enemy/status bar region.

## Text and font rendering

The module supports several string styles:

| Routine | Input style |
|---|---|
| `Render_Pascal_String_0` | Pascal string with position bytes. |
| `Render_Pascal_String_1` | Similar positioned Pascal string entry. |
| `Render_String_FF_Terminated` | String ending in `FFh`. |
| `Render_C_String` | C-style zero-terminated string. |
| `Render_Font_Glyph` | Single glyph render. |

`Render_Font_Glyph` takes:

| Register | Meaning |
|---|---|
| `AL` | ASCII character code. |
| `AH` | Palette/color index. |
| `BX` | X pixel coordinate. |
| `CX` | Y row coordinate. |

The module uses font data loaded from `font.grp` into pointers at `bold_font_8x8`, `digits_font`, and `thin_font`.

## Decimal number conversion

The decimal conversion path is:

```text
Print_*_Decimal
  -> Prepare_Decimal_Display_Buffer
  -> Convert_32bit_To_Decimal_Digits
  -> Render_Decimal_Digits
  -> _Render_Single_Digit_Glyph
```

This allows UI modules to render gold, almas, magic count, and shield HP consistently. Gold is effectively a multi-byte value, so decimal conversion is not just a simple 8-bit print.

## Item and inventory icon rendering

The module renders several fixed-size icon classes:

| Routine | Format |
|---|---|
| `Render_Sword_Item_Sprite_20x18` | 20×18 item sprite. |
| `Render_Magic_Spell_Item_Sprite_16x16` | 16×16 magic spell icon. |
| `Render_Shield_Item_Sprite_16x16` | 16×16 shield icon. |
| `Render_Wearable_Item_Sprite_16x16` | 16×16 accessory icon. |
| `Render_Magic_Potion_Item_Sprite_16x16` | 16×16 potion icon. |
| `Render_Key_Item_Sprite_16x16` | 16×16 key icon. |
| `Render_Crest_Item_Sprite_16x16` | 16×16 crest icon. |

These are used by `select.asm` and by HUD restore/render flows in `game.asm`.

## Collected Tear icons

`Render_Icon_16x13` is also the renderer for the collected Tears overlay. Its source table is `off_2A5D` in `gmmcga.asm`, which sits at file offset `0x0A5D` in `game/gmmcga.bin`.

- `off_2A5D[0]` points to `byte_2A61` at file offset `0x0A61` for the small blue Tear icon.
- `off_2A5D[1]` points to `byte_2B31` at file offset `0x0B31` for the large red Tear icon.
- Each icon is `16 x 13` bytes.
- `0x80` is transparent and all other bytes overwrite the framebuffer.

## 3-plane graphics reassembly

`Reassemble_3_Planes_To_Packed_Bitmap` is one of the most important helper routines. It converts planar graphics into packed bitmap/tile data.

Helper routines:

```text
Reassemble_3_Planes_To_Packed_Bitmap
  -> assemble_48_bytes
  -> assemble_48_bits
  -> assemble_3_bits
```

This is used by many building overlays immediately after loading their `.grp` portrait/background files. The common pattern is:

```asm
mov ds, word ptr cs:seg1
mov si, 8000h
mov cx, 100h
call word ptr cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
```

## Screen capture and restore helpers

`Capture_Screen_Rect_to_seg3` and `Put_Image` copy rectangular screen areas to and from `seg3`. Dialogs and overlays use this to temporarily cover part of the screen and then restore it.

This is a key reason the original game can draw modal menus and dialog boxes without needing to fully redraw the game scene behind them.

## Fade and clear

`Fade_To_Black_Dithered` performs a dithered fade effect rather than simply clearing the screen immediately. It is used when leaving shops, buildings, demos, and other overlays.

## Porting notes

The easiest modern equivalent is an indexed 320×200 framebuffer and a set of draw helpers:

```text
FrameBuffer320x200
  drawRectangle()
  clearViewport()
  drawGlyph()
  drawString()
  drawHealthBar()
  drawIcon16x16()
  fadeToBlackDithered()
```

Keep color indices first. Do not convert everything to RGBA too early, because palette transforms, dithered fade, and old sprite composition depend on indexed behavior.
