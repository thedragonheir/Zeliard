# GRP assets and graphics formats

## Scope

This document consolidates the GRP-related information from the uploaded analysis note and the assembly source references.

Primary sources:

- `grp_analysis.md`
- `stick.asm`
- `gmmcga.asm`
- `gtmcga.asm`
- `gdmcga.asm`
- `gfmcga.asm`
- `fight.asm`
- `common.inc`
- `dungeon.inc`

## GRP files are not raw bitmaps

A `.grp` file is generally a small Zeliard container:

1. Zeliard-specific header.
2. Compressed payload.
3. Unpacked data that may be:
   - a multi-group offset table,
   - pattern/tile bank data,
   - sprite frame tables,
   - planar image data,
   - transparency masks or inputs for mask generation.

The payload is decompressed through the custom method table implemented in `stick.asm` and mirrored by the Python viewer tooling.

## Header behavior

The uploaded GRP analysis describes this high-level Python behavior:

```text
if raw[0] == 0:
    payload = raw[1:]
    expected_length = len(raw) - 1
else:
    skip = u16le(raw[1:3])
    expected_length = u16le(raw[3:5])
    payload = raw[5 + skip:]

unpacked = unpack(payload, expected_length)
```

A C++ or modern decoder should not just ignore `expected_length`. It should use it as a validation check.

## Unpack methods

The original source implements methods 0 through 7 through `stick.asm`'s `unpack_dispatcher`.

| Method | Source routine | Summary |
|---:|---|---|
| 0 | `fn0_raw_copy` | Raw copy. |
| 1 | `fn1_RLE_with_lookup_table_hi_nib` | High-nibble RLE with lookup table. |
| 2 | `fn2_RLE_with_inline_marker_hi_nib` | High-nibble RLE with inline marker. |
| 3 | `fn3_RLE_with_lookup_table_lo_nib` | Low-nibble RLE with lookup table. |
| 4 | `fn4_RLE_with_inline_marker_lo_nib` | Low-nibble RLE with inline marker. |
| 5 | `fn5_byte_pair_RLE` | Byte-pair run-length encoding. |
| 6 | `fn6_RLE_with_word_sentinel_table` | Word/sentinel-table encoding. |
| 7 | `fn7_three_byte_run_encoding` | Three-byte run encoding. |

## Major GRP render modes

The uploaded analysis maps known GRPs to these render modes:

| Mode | Format |
|---:|---|
| 0 | 20×18 MCGA sprites, 3 bit-planes, 15-byte row stride. |
| 1 | 16×16 MCGA sprites, 3 bit-planes, 12-byte row stride. |
| 2 | 8×8 font glyphs, 1bpp, 8 bytes per tile. |
| 3 | 16×16 magic sprites, 3 planes, 48-byte block reassembly. |
| 4 | 32×32 sword macro tiles, 2bpp bit-plane assembly. |
| 5 | 16×24 town NPC sprites, `mman.grp` / `cman.grp`. |
| 6 | 16×24 town hero sprites, `tman.grp`. |
| 7 | 8×8 pattern/background tiles, `mpat.grp` / `dpat.grp` / `cpat.grp`. |
| 8 | 24×24 dungeon hero sprites, `fman.grp`. |
| 9 | `roka.grp`, 28×18 tile map with 5 palette modes. |
| 10 | 8×8 static dungeon tiles, `dchr.grp` / `mpp*.grp`. |
| 11 | 16×16 monster/item sprites, `enp*.grp`. |
| 12 | boss sprites, for example `crab.grp`. |
| 13 | `dman.grp`, rokademo sprites. |

## Important GRP files by subsystem

| File | Subsystem | Notes |
|---|---|---|
| `font.grp` | UI/common graphics | First visible render test, 8×8 1bpp glyphs. |
| `itemp.grp` | UI/inventory | Item icon pointer groups. |
| `magic.grp` | dungeon/fight | Magic spell sprite groups. |
| `sword.grp` | dungeon/fight | Sword sprites and macro tiles. |
| `cpat.grp` | town/tile pattern | Town pattern/background tile bank. |
| `mpat.grp` | town/tile pattern | Pattern tile bank. |
| `dpat.grp` | town/tile pattern | Pattern tile bank. |
| `mman.grp` / `cman.grp` | town NPCs | 16×24 NPC sprite sets. |
| `tman.grp` | town hero | 16×24 hero town sprite set. |
| `fman.grp` | dungeon hero | 24×24 hero frames, 3×3 tiles. |
| `dchr.grp` | dungeon objects | Doors, platforms, special 8×8 tiles. |
| `mpp*.grp` | dungeon tile sets | Cavern static tile banks. |
| `enp*.grp` | monsters/items | 16×16 monster/entity sprites. |
| `crab.grp` | boss | Boss sprite composition. |
| `roka.grp` | special/demo | 28×18 tilemap with palette transforms. |

## Pattern/tile bank format

Town and dungeon background tiles commonly use 8×8 tiles with 48 bytes per tile:

```text
8 rows × 8 pixels × 6 bits = 384 bits = 48 bytes
```

`gtmcga.asm` and `gfmcga.asm` contain routines that decode this packed form into pixel bytes.

For `cpat.grp`, the analysis notes:

```text
unpacked size 7792 bytes
= 256-byte control/header region + 157 tiles × 48 bytes
```

The first region contains metadata/pointers and per-tile function selectors. Tile data starts at byte 256.

## Town pattern pipeline

```text
res_dispatcher AL=2 loads cpat/mpat/dpat-style GRP
  -> pattern data appears around seg1:8000h
  -> offsets in first words are adjusted
  -> gtmcga.decompress_patterns converts plane/pattern data
  -> 48-byte packed tiles become available at seg1:8100h
  -> gtmcga.render_town_tiles_28_columns draws the viewport
```

`common.inc` defines:

| Offset | Meaning |
|---:|---|
| `seg1:8000h` | `tile_anim_count_table` / pattern descriptor base. |
| `seg1:8002h` | `special_tile_list_ptr`. |
| `seg1:8004h` | `tile_animation_replacement_table`. |
| `seg1:8100h` | 48-byte packed tile graphics. |

## Town sprite masks

Town sprites use masks to preserve transparent background. `gtmcga.asm` contains:

- `apply_sprite_mask`,
- `sprite_plane_decompressor_0`,
- `sprite_plane_decompressor_b`,
- `sprite_plane_decompressor_g`,
- `sprite_plane_decompressor_r`,
- `extract_transparency_byte_from_mask_plane`.

The resulting draw path is:

```text
background tile in shadow VRAM
AND mask clears pixels where sprite is opaque
OR sprite pixels draw colored pixels
copy composed block to visible screen
```

## Common MCGA reassembly

`gmmcga.asm` has `Reassemble_3_Planes_To_Packed_Bitmap`, used by building overlays after loading their portrait/background GRPs.

This path converts three bitplanes into a packed indexed representation suitable for direct UI drawing.

## Dungeon hero and monster graphics

`fight.asm` comments describe:

```text
fman.grp  = hero in dungeon, 3×3 grid of 8×8 tiles, 24×24 per frame
enp?.grp  = monsters/items, 2×2 grid of 8×8 tiles, 16×16 per frame
crab.grp  = boss sprite, multi-part composition
```

`gfmcga.asm` renders these through specialized sprite, mask, palette, and cache routines.

## Palette information

The uploaded analysis states:

- The Python viewer builds a 64-color MCGA/Zeliard palette fragment.
- `PAL_DECODE_TABLES` contains 16-entry tables used by hero/dungeon sprite decoding.
- `SWORD_COLORS` defines sword color pairs.
- `roca_transform()` models palette substitutions for `roka.grp`.

Assembly references include:

- `gfmcga.asm` `Render8pxWithPaletteTransform` and `PaletteTransform_0..4`.
- `snippet.asm` with `pal_decode_tbl` and decode data.

## Validation strategy

The safest validation path is staged:

1. Implement GRP header parsing.
2. Implement the eight unpack methods.
3. Byte-compare `cpat.grp` unpack output against `cpat.grp.unp` if available.
4. Render `font.grp` glyphs as the first visible test.
5. Decode static 8×8 tiles such as `dchr.grp` or `mpp1.grp`.
6. Add town pattern decoding for `cpat.grp`.
7. Add town NPC/hero sprites with masks.
8. Add dungeon hero and monster sprites.
9. Add boss and Roca special cases.

## Recommended modern file split

A clean C++ or modern implementation can start with:

```text
src/resources/BinaryReader.h/.cpp
src/grp/GrpArchive.h/.cpp
src/grp/GrpUnpacker.h/.cpp
src/grp/GrpFontDecoder.h/.cpp
src/graphics/IndexedBitmap.h/.cpp
src/graphics/Palette.h/.cpp
```

Do not begin with a large engine framework. First prove byte-exact resource loading and one simple visible renderer.

## Source note

The following was used as a source-style reference while building this document:

```text
# GRP analysis

## Scope

Sources inspected:

- `AGENTS.md`
- `tools.zip`, extracted as `tools/`
- `game.zip`, extracted as `game/`
- `asm.zip`, extracted as `asm/`

No folders were moved. No files were deleted. No C++ code was generated.

`src/` and `assets/` were not included in the uploaded source bundle for this analysis. The entry point and folder rules therefore come from `AGENTS.md`.

## Relevant GRP files

Example GRP files are available in two useful places:

- `tools/grpviewer/`, curated viewer/test set
- `game/0/`, larger extracted game data set

Useful first files:

| File | Location | Why useful |
|---|---|---|
| `font.grp` | `tools/grpviewer/font.grp`, `game/0/font.grp` | Best first visible render test. 8x8 1bpp glyphs, simpler than sprite/tile GRPs. |
| `cpat.grp` | `tools/grpviewer/cpat.grp`, `game/0/cpat.grp` | Good decompression sanity test. Matching `.unp` exists in `t
...
```
