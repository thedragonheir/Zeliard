# MDT analysis

This note summarizes the repository-local evidence for MDT map structure and how MDT cells point at GRP pattern tiles. It is based on the MDT viewer, the assembly comments, and the GRP analysis notes.

I did find checked-in `.mdt` sample files under `tools/` and `game/0/` (for example `tools/cmap.mdt`, `tools/mp10.mdt`, and `game/0/cmap.mdt`), but none directly under `game/`, so the test file names below still come from the viewer tables and assembly comments rather than from local sample dumps.

## What MDT files appear to contain

The MDT viewer treats MDT files as two related formats:

- Dungeon / outdoor MDTs have a header, entity tables, and a packed tile grid.
- Town MDTs have a smaller header, town-specific tables, and an unpacked tile grid.

From `tools/mdtviewer/core/decoder.py` and `asm/dungeon.inc`, the runtime layout is:

- `0x00` descriptor pointer
- `0x02` map width
- Dungeon-only tables:
  - `0x04` vertical platforms
  - `0x06` collapsing platforms
  - `0x08` horizontal platforms
  - `0x0A` doors
  - `0x0C` accomplished items
  - `0x0E` cavern name renderer info
  - `0x10` monsters
  - `0x12` cavern level
  - `0x13` tear X
  - `0x15` tear Y
  - `0x17` signs
  - `0x19` packed map end pointer
  - `0x1B` packed map data
- Town-only tables:
  - `0x04` town name info
  - `0x09` town doors
  - `0x0D` NPC text pointer array
  - `0x0F` NPC array
  - `0x17` unpacked map data

The descriptor bytes also matter:

- Dungeon and town descriptor byte `+4` selects the pattern bank family.
- Town descriptor byte `+1` selects `mman.grp` or `cman.grp` for NPCs.
- Town descriptor byte `+3` stores the middle-layer flag.

## Map dimensions known from the code

- Town maps are always 8 tiles high.
- Dungeon maps are always 64 tiles high.
- Map width is stored in the file header at `0x02`; the code validates it but does not hardcode a single width.
- Town grids are `map_width * 8` bytes, column-major.
- Dungeon grids expand to `map_width * 64` tiles, column-major, through a packed RLE stream.

## How map cells reference GRP pattern tiles

The MDT grid does not store pixels. It stores tile indices.

- For towns, the unpacked bytes at `0x17` are direct tile IDs.
- For dungeons, the packed stream at `0x1B` expands to tile IDs with a 2-bit opcode RLE format.
- The renderer then uses those tile IDs to look up 8x8 tiles in the selected GRP pattern bank.

The viewer picks the pattern bank in two layers:

1. Filename / table selection in `tools/mdtviewer/core/constants.py`
2. Descriptor fallback in `tools/mdtviewer/core/decoder.py`

The current viewer logic uses these pattern sources:

- `cpat.grp` for Felishika Castle / common castle-style maps
- `mpat.grp` for surface town maps
- `dpat.grp` for underground town maps and several dungeon-style maps
- `mpp*.grp` for the world-indexed outdoor / dungeon banks when the filename rule or explicit table says to use them

The map renderer in `tools/mdtviewer/rendering/map_renderer.py` passes the raw `tile_idx` directly to the tile graphics layer. `tools/mdtviewer/rendering/tile_graphics.py` then tries the selected GRP, and falls back to MDT-embedded graphics if present.

## Which MDT file is the best first test

Best first test: `CMAP.MDT`.

Reason:

- It is explicitly identified in the repo as Felishika Castle.
- It is the clearest confirmed `cpat.grp` case.
- It exercises the town-style 8-row layout without adding the packed dungeon RLE path yet.

If the next test is needed after that, `MP10.MDT` is the canonical first gameplay map (`map_id 0 => mp10.mdt`) and is the best packed-grid check.

## Which pattern bank belongs with which map type

Best evidence from `tools/mdtviewer/core/constants.py` and `asm/town.asm`:

- `CMAP.MDT` -> `cpat.grp`
- `MRMP.MDT`, `BSMP.MDT`, `LLMP.MDT`, `ESMP.MDT` -> `mpat.grp`
- `STMP.MDT`, `HLMP.MDT`, `TMMP.MDT`, `DRMP.MDT`, `PRMP.MDT` -> `dpat.grp`
- `MP10.MDT` -> `mpp1.grp`
- `MP20.MDT`, `MP21.MDT` -> `mpp2.grp`
- `MP30.MDT`, `MP31.MDT` -> `mpp3.grp`
- `MP40.MDT` through `MP84.MDT` -> `mpat.grp` in the explicit table
- `MP1D.MDT` -> `mpp1.grp`
- `MP2D.MDT` through `MP8D.MDT`, `MP90.MDT`, `MPA0.MDT` -> `dpat.grp`

The filename rule in `get_mdt_tileset()` can also derive `mpp1` through `mppb` for MP* names, but the explicit association table is the stronger evidence whenever both exist.

## Strongest evidence

- `tools/mdtviewer/core/decoder.py`
- `tools/mdtviewer/core/constants.py`
- `tools/mdtviewer/rendering/map_renderer.py`
- `tools/mdtviewer/rendering/tile_graphics.py`
- `asm/town.asm`
- `asm/dungeon.inc`
- `docs/GrpAnalysis.md`

## Next minimal C++ implementation step

Add a small MDT parser that:

- reads the header fields
- detects town vs dungeon MDTs
- decodes the column-major tile grid
- exposes the selected pattern-bank name
- keeps tile IDs as raw indices

Do not render the map yet. That keeps the first C++ step focused on format validation instead of the full drawing pipeline.
