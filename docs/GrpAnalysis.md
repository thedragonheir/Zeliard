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
| `cpat.grp` | `tools/grpviewer/cpat.grp`, `game/0/cpat.grp` | Good decompression sanity test. Matching `.unp` exists in `tools/grpviewer/`. |
| `dchr.grp` | `tools/grpviewer/dchr.grp`, `game/0/dchr.grp` | Good first 8x8 dungeon/tile test after planar tile decoding works. |
| `mpp1.grp` | `tools/grpviewer/mpp1.grp`, `game/0/mpp1.grp` | Dungeon tile set, same general static tile path as mode 10. |
| `fman.grp` | `tools/grpviewer/fman.grp`, `game/0/fman.grp` | Hero dungeon sprite sheet, useful later, not first. |
| `sword.grp` | `tools/grpviewer/sword.grp`, `game/0/sword.grp` | Sword macro tiles, useful later for hero composition. |
| `enp1.grp` | `tools/grpviewer/enp1.grp`, `game/0/enp1.grp` | Monster/item sprites, useful after 16x16 composition works. |
| `crab.grp` | `tools/grpviewer/crab.grp`, `game/0/crab.grp` | Boss sprite composition, later stage. |

Counts found in uploaded sources:

- `tools/`: 56 `.grp` files
- `game/`: 83 `.grp` files
- `asm/`: no `.grp` files, but many references and decode routines

## Most relevant code

### Primary Python reference

`tools/grpviewer/grp_viewer_13_1.py` is the best high-level reference.

It contains:

- `GRP_DESCRIPTOR`, mapping known `.grp` files to render modes.
- `MODE_CFG`, defining width, height, stride, bytes per tile, and type per mode.
- `unpack()`, the custom GRP decompression routine.
- palette data and palette lookup tables.
- render paths for font, item, magic, sword, town NPCs, hero, dungeon tiles, monsters, bosses, and `roka.grp`.

`tools/grpviewer/grp_viewer.py` is also useful, but `grp_viewer_13_1.py` has a richer descriptor set for `enp2` through `enp8` and improved `dchr.grp` metadata.

### Decompression helper

`tools/grpviewer/unpack.py` contains the smallest standalone Python version of the GRP unpacker. It is the best reference for the first C++ decompressor.

Header handling used there:

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

The current Python implementation reads `expected_length`, but does not strictly enforce it. The C++ implementation should use it as validation.

### Assembly references

Important assembly files:

| File | Relevance |
|---|---|
| `asm/game.asm` | Loads early GRPs such as `font.grp`, `itemp.grp`, `magic.grp`, and `sword.grp`. |
| `asm/fight.asm` | Strong documentation comments for dungeon GRPs, hero sprites, monster sprites, boss sprites, and runtime loading. |
| `asm/gmmcga.asm` | Contains `Reassemble_3_Planes_To_Packed_Bitmap`, the MCGA 3-plane to packed bitmap conversion. |
| `asm/gtmcga.asm` | Contains `decompress_patterns`, `sprite_plane_decompressor_*`, and `build_48_bits_packed_from_rgb_planes`. Relevant for `mpat.grp`, `dpat.grp`, `cpat.grp`, `dchr.grp`, and `mpp*.grp`. |
| `asm/gfmcga.asm` | Contains tile rendering, blitting, palette transforms, and `roca_tile_indices_28x18`. Relevant for dungeon/tile display and palette animation. |
| `asm/common.inc` | Defines important segment offsets and data locations, for example `packed_tile_ptr`, `packed_tile_graphics`, and sprite/tile buffers. |
| `asm/dungeon.inc` | Defines dungeon graphics offsets, including `magic_grp_sprites` and `sword_grp_sprites`. |

## GRP container notes

A `.grp` file is not just raw image data. It usually has:

1. A small Zeliard header.
2. A compressed payload using a custom method selected by the low 3 bits of the first payload byte.
3. After unpacking, either:
   - a multi-group offset table, or
   - raw tile/sprite data interpreted by a file-specific mode.

The custom `unpack()` supports methods `0` through `7`.

Known unpacked size examples from the uploaded files:

| File | Raw size | Unpacked size |
|---|---:|---:|
| `font.grp` | 3225 | 1623 |
| `cpat.grp` | 6096 | 7792 |
| `dpat.grp` | 8157 | 9424 |
| `mpat.grp` | 9895 | 11872 |
| `dchr.grp` | 1665 | 1872 |
| `mpp1.grp` | 1167 | 1248 |
| `fman.grp` | 5459 | 8176 |
| `sword.grp` | 4328 | 6702 |
| `enp1.grp` | 6258 | 8128 |
| `crab.grp` | 5320 | 7296 |

## Render modes from the viewer

The viewer maps files to these modes:

| Mode | Format |
|---:|---|
| 0 | 20x18 MCGA sprites, 3 bit-planes, 15-byte row stride |
| 1 | 16x16 MCGA sprites, 3 bit-planes, 12-byte row stride |
| 2 | 8x8 font glyphs, 1bpp, 8 bytes per tile |
| 3 | 16x16 magic sprites, 3 planes, 48-byte block reassembly |
| 4 | 32x32 sword macro tiles, 2bpp bit-plane assembly |
| 5 | 16x24 NPC sprites, `mman.grp` / `cman.grp` |
| 6 | 16x24 hero town sprites, `tman.grp` |
| 7 | 8x8 pattern/background tiles, `mpat.grp` / `dpat.grp` / `cpat.grp` |
| 8 | 24x24 hero dungeon sprites, `fman.grp` |
| 9 | `roka.grp`, 28x18 tile map with 5 palette modes |
| 10 | 8x8 static dungeon tiles, `dchr.grp` / `mpp*.grp` |
| 11 | 16x16 monster/item sprites, `enp*.grp` |
| 12 | boss sprites, for example `crab.grp` |
| 13 | `dman.grp`, rokademo sprites |

## Palette information

Palette data is currently hardcoded in the Python viewer:

- `build_palette()` builds a 64-color MCGA/Zeliard palette fragment from 0..63 RGB-like values scaled by 4.
- `PAL_DECODE_TABLES` contains 16-entry lookup tables used by hero/dungeon sprite decoding.
- `SWORD_COLORS` defines sword color pairs.
- `roca_transform()` models the animated palette substitutions used by `roka.grp`.

Assembly palette references:

- `asm/gfmcga.asm` contains `Render8pxWithPaletteTransform` and `PaletteTransform_0` through `PaletteTransform_4`.
- `tools/grpviewer/enp_snippet.asm` contains `pal_decode_tbl` and `pal_decode_data0` through `pal_decode_data4`, matching the Python `PAL_DECODE_TABLES`.

## Recommended first test

Use `font.grp` as the first visible C++ renderer test.

Reason:

- It is small.
- It uses simple 8x8 1bpp glyph rendering after unpacking.
- It exercises the non-zero GRP header path, because `font.grp` uses `raw[0] != 0` with `skip` and `expected_length`.
- It also exercises the multi-group offset table used by several GRPs.

Use `cpat.grp` as a decompression-only sanity test before rendering.

Reason:

- `tools/grpviewer/cpat.grp.unp` already exists.
- The C++ unpacker output can be byte-compared against it.

## Next project-owned C++ files

Create only these when implementation starts:

```text
src/resources/BinaryReader.h
src/resources/BinaryReader.cpp
src/grp/GrpArchive.h
src/grp/GrpArchive.cpp
src/grp/GrpUnpacker.h
src/grp/GrpUnpacker.cpp
src/grp/GrpFontDecoder.h
src/grp/GrpFontDecoder.cpp
```

Possible later files:

```text
src/graphics/Palette.h
src/graphics/Palette.cpp
src/graphics/IndexedBitmap.h
src/graphics/IndexedBitmap.cpp
```

Do not create a large engine layer yet.

## Suggested implementation order

1. Add `BinaryReader` for safe byte/vector reading.
2. Add `GrpArchive` or `GrpFile` to parse the GRP header and expose the compressed payload.
3. Add `GrpUnpacker` with methods `0` through `7` ported from `tools/grpviewer/unpack.py`.
4. Validate `cpat.grp` unpacking against `tools/grpviewer/cpat.grp.unp`.
5. Decode and render `font.grp` as 8x8 1bpp glyph tiles.
6. Upload the rendered output to SDL3 as a texture or draw it inside the existing 320x200 logical presentation.
7. Only then add planar tile decoding for `dchr.grp` or `cpat.grp`.

## Validation notes

C++ validation should follow `AGENTS.md`:

```text
cmake --preset x64-debug
cmake --build --preset x64-debug
out\build\x64-debug\Zeliard.exe
```

For the unpacker, add a temporary manual validation path:

```text
Load tools/grpviewer/cpat.grp
Unpack it in C++
Compare the byte output to tools/grpviewer/cpat.grp.unp
Print match/mismatch to std::cout
```

Keep this as a debug-only step until a proper test harness exists.

## Open questions

- The uploaded sources did not include `assets/`, so this analysis cannot confirm extra asset-side palette files.
- The Python viewer contains some exploratory hardcoded frame maps. Treat those as reference, not as final architecture.
- Before implementing mode 7, 8, 10, 11, 12, or 13 in C++, confirm behavior against both the Python viewer and original game footage/screens.
