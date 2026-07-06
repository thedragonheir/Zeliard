# Sprite GRP analysis

## Scope

Sources inspected:

- `tools/grpviewer/grp_viewer.py`
- `tools/grpviewer/grp_viewer_13_1.py`
- `tools/grpviewer/v15/DATA.json`
- `tools/grpviewer/`
- `game/0/`
- `asm/town.asm`
- `asm/game.asm`
- `asm/fight.asm`
- `asm/gmmcga.asm`
- `asm/gtmcga.asm`
- `asm/gfmcga.asm`

This note is about sprite-like GRP files only. `cpat.grp` is still a pattern bank, not a sprite sheet, and the current `M` path already covers it.

## High-confidence sprite GRP files

The strongest repository-local evidence splits the sprite GRPs into a few families.

| File(s) | Likely role | Known or likely layout | Evidence strength |
|---|---|---|---|
| `mman.grp`, `cman.grp` | Town NPC sprites | 16x24 frames, 2x3 grid of 8x8 tiles, 6 indices per sprite, 48 bytes per tile | Strong |
| `tman.grp` | Town hero sprite sheet | 16x24 frames, 2x3 grid of 8x8 tiles, 10 poses in the viewer, no index table | Strong |
| `fman.grp` | Dungeon hero sprite sheet | 24x24 frames, 3x3 grid of 8x8 tiles, frame groups stored as 9-byte headers | Strong |
| `enp1.grp` | Monster / item sprites | 16x16 frames, 2x2 grid of 8x8 tiles, palette index stored per frame | Strong |
| `crab.grp` | Boss sprite | Multi-part composite built from many 16x16 frames | Strong |
| `itemp.grp` | Item sprites | Special sprite format, not the first test candidate | Medium |
| `magic.grp` | Magic / effect sprites | Special sprite format with plane assembly | Medium |
| `sword.grp` | Sword macro tiles | 32x32 macro-tiles with color-pair logic | Medium |
| `king.grp`, `kenjya.grp` | Large character / special sprites | Viewer dev-mode sheets only; likely sprite composites | Medium / viewer-only |
| `tako.grp`, `tori.grp`, `zela.grp`, `meda.grp`, `lega.grp`, `drgn.grp`, `akma.grp`, `mao1.grp`, `mao2.grp` | Boss sprite sheets | Mentioned by `asm/fight.asm`; exact viewer layout not confirmed here | Likely |

## Best first sprite test

`mman.grp` is the best first sprite-rendering test.

Why this one first:

- `asm/town.asm` loads `mman.grp` / `cman.grp` directly for town NPC rendering.
- The format is the simplest confirmed character-sheet path: a shared 16x24 layout with a 256-byte header/index area followed by 48-byte tiles.
- `tman.grp` is also simple, but it uses a hardcoded hero layout (`HERO_INDICES`) rather than a data-driven index table, so it is a slightly worse first test.

If the goal is a hero-only check after that, `tman.grp` is the next easiest sheet.

## Expected layout

### `mman.grp` / `cman.grp`

- 16x24 sprites.
- Each sprite is a 2x3 arrangement of 8x8 tiles.
- The viewer slices the first 256 bytes as the NPC header/index area; the visible layout is 40 NPCs x 6 indices.
- Each sprite uses 6 tile indices, laid out as two columns by three rows.
- The tile bank is 48 bytes per 8x8 tile.

### `mman.grp` frame grouping

- Total frames: 40.
- Confirmed frame size: 16x24 pixels, made from 6 tile indices and 48-byte tiles.
- The raw table falls into five 8-frame blocks: `0-7`, `8-15`, `16-23`, `24-31`, and `32-39`.
- Blocks `0`, `2`, `3`, and `4` look like 4-phase left/right walk families.
- Block `1` is now confirmed by the town selector evidence as a real idle/special family, and it still uses the same 8-frame block arithmetic.
- The assembly render path in `asm/gtmcga.asm` uses `n_anim_phase & 3` plus a facing offset of `4`, which matches a 4-phase cycle per facing inside each 8-frame block.
- `asm/town.asm` advances `n_anim_phase` in the patrol and bobbing AI paths, so the frame motion is driven by state code rather than by separate turn rows in the file.
- What remains uncertain: the exact narrative meaning of each confirmed family, and whether any selector families beyond `0` through `4` are actually used in towns.

### `tman.grp`

- 16x24 sprites.
- Same 2x3 tile shape as `mman.grp` / `cman.grp`.
- No per-file index table in the viewer.
- The layout comes from the hardcoded `HERO_INDICES` table in `grp_viewer.py`.
- The unpacked file length is 2208 bytes, which is exactly 46 tiles x 48 bytes, so this sheet appears to be a plain tile bank.

### `fman.grp`

- 24x24 sprites.
- 3x3 arrangement of 8x8 tiles.
- The viewer uses a small frame header table before the tile bank.
- This is a later step, not the first sprite test, because it adds frame slicing and palette lookups.

### `enp1.grp` and the `enp2`-`enp8` family

- 16x16 sprites.
- 2x2 arrangement of 8x8 tiles.
- Each frame begins with a palette selector byte.
- `tools/grpviewer/v15/DATA.json` extends this family with detailed frame maps for `enp2` through `enp8`.

### `crab.grp`

- Boss sheets are composited from many small parts rather than rendered as a simple sprite grid.
- The viewer renders named body parts and special frames separately.

## How sprite bytes map to pixels

### Town NPC and town hero sheets

The `mman.grp` / `cman.grp` / `tman.grp` family uses 48-byte tiles.

Each tile is:

- 8 rows
- 6 bytes per row
- 3 big-endian 16-bit plane words per row

The viewer's `decode_npc_tile()` and `decode_8()` paths show the mapping:

- read three plane words
- rotate through the plane bits in lockstep
- combine them into a 6-bit palette index per pixel
- keep the ASM transparency byte too, because opaque zero-index pixels are the black-mask clears and not true transparency

For town rendering, the earlier full black-silhouette approach was rejected because it filled the whole sprite rectangle instead of honoring the real mask. The ASM path in `asm\gtmcga.asm` keeps a separate transparency byte per row, so the C++ decode now needs three states instead of two: true transparent pixels skip, normal color pixels draw from the palette, and opaque zero-index pixels draw black.

The current rule is ASM-derived and matches the checked town data: the mask byte is considered transparent only when the extracted 2-bit slot is `11`; when that slot is not `11` and the decoded palette index is `0`, the pixel is treated as the black-mask clear pixel.

That matches the assembly helpers in `asm/gtmcga.asm`:

- `apply_sprite_mask`
- `build_48_bits_packed_from_rgb_planes`
- `extract_transparency_byte_from_mask_plane`

The important point for C++ is that this family does not need a special palette remap table. It draws directly into the base 64-color MCGA palette, and the exact faithful AND/OR mask emulation can be revisited later if we decide to model the original composite blit more closely.

### Dungeon hero, monsters, and boss sheets

`fman.grp`, `enp1.grp`, and `crab.grp` use the palette-decode-table path instead.

The viewer and assembly show:

- 32-byte 8x8 tiles for these sheets
- 8 rows per tile
- palette selection through `PAL_DECODE_TABLES` / `pal_decode_tbl`
- frame-specific palette bytes for the `enp` sheets

The low-level assembly evidence is in:

- `asm/gfmcga.asm` `pal_decode_tbl`
- `asm/gfmcga.asm` `Decompress_Tile_Data`
- `tools/grpviewer/enp_snippet.asm`

### Special object sheets

`itemp.grp`, `magic.grp`, and `sword.grp` are sprite-like but not a good first rendering target.

- `itemp.grp` and `magic.grp` use the sprite-plane decompression helpers in `asm/gtmcga.asm`.
- `sword.grp` uses the 32x32 macro-tile / color-pair path.

## Palette data needed

### For `mman.grp` / `cman.grp` / `tman.grp`

Use the normal 64-color MCGA palette from the viewer's `build_palette()` helper and the matching game palette data in `asm/gfmcga.asm`.

These sheets do not need `pal_decode_tbl`.

### For `fman.grp` / `enp1.grp` / `crab.grp`

Use `PAL_DECODE_TABLES` / `pal_decode_tbl` from:

- `asm/gfmcga.asm`
- `tools/grpviewer/grp_viewer.py`
- `tools/grpviewer/grp_viewer_13_1.py`

The `enp` and `crab` sheets also rely on the palette selector byte stored with each frame.

### For `magic.grp` / `sword.grp`

These need their own special color logic and should stay out of the first sprite test.

## Strongest repository-local evidence

The most useful evidence chain is:

- `asm/town.asm`
  - `load_town_transition_data` loads `mman.grp` or `cman.grp` for towns.
  - `load_and_decompress_patterns` loads `cpat.grp` / `mpat.grp` / `dpat.grp`.
  - `load_hero_town_sprite` loads `tman.grp` and applies the sprite mask.
- `asm/game.asm`
  - loads the town NPC sprite bank via `mman_cman_gfx`.
  - loads `font.grp`, `itemp.grp`, `magic.grp`, and `sword.grp`.
- `asm/fight.asm`
  - contains the broad sprite summary for dungeon assets.
  - explicitly calls out `fman.grp`, `mman.grp`, `cman.grp`, `enp1.grp`-`enp8.grp`, and `crab.grp`.
- `asm/gmmcga.asm`
  - `Reassemble_3_Planes_To_Packed_Bitmap`.
- `asm/gtmcga.asm`
  - `apply_sprite_mask`
  - `build_48_bits_packed_from_rgb_planes`
  - `sprite_plane_decompressor_*`
- `asm/gfmcga.asm`
  - `Decompress_Tile_Data`
  - `pal_decode_tbl`
- `tools/grpviewer/grp_viewer.py`
  - confirms the shared `mman` / `cman` / `tman` / `fman` / `enp1` / `crab` decoding paths.
- `tools/grpviewer/grp_viewer_13_1.py`
  - adds the richer `enp2`-`enp8`, `king.grp`, and `kenjya.grp` evidence.
- `tools/grpviewer/v15/DATA.json`
  - mirrors the viewer descriptors and extends the `enp` and special-character sheets.

## Next minimal C++ step

Do not wire SDL rendering yet.

The smallest safe next step is to add a tiny sprite-bank decoder for `mman.grp` / `cman.grp` that:

- reads the GRP container header
- unpacks the payload
- validates the 256-byte NPC index table
- slices the 48-byte tile bank
- decodes one 16x24 sprite into an in-memory test buffer
- selects an 8-frame block by NPC type, then indexes it with facing plus `n_anim_phase & 3`

That would prove the town NPC format before any on-screen sprite work starts.
