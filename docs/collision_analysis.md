# Collision Analysis

## Scope

This note summarizes repository-local evidence for how Zeliard decides whether a town tile is walkable or blocked. It is analysis-only and does not change C++ code.

## Short answer

Town collision appears to be tile-index based, but the movement check is triggered by hero position first.

- The code samples one tile at the hero's leading edge.
- That tile ID is compared against a `special_tile_list`.
- If the tile is not in that list, movement is allowed.
- NPCs add a separate blocking rule through the `non-passable` NPC flag.

For the checked `cmap.mdt` sample, the strongest evidence points to tile IDs `0x3C` and `0x3D` as blocked. Everything else in the town pattern bank is passable unless an NPC blocks that x position.

## Best evidence

### Town movement code

`asm/town.asm` shows the town walk check directly:

- left and right movement read one tile from `proximity_start_tiles`
- `check_tile_in_special_list` treats the `special_tile_list` as a non-passable tile set
- `find_non_passable_npc_at_x_pos` adds a second blocker based on NPC state

That makes the town rule:

1. choose the tile at the edge of the hero
2. check whether the tile ID is in the blocked list
3. check whether a non-passable NPC occupies the same x position

### Pattern-bank loading

`asm/town.asm`, `asm/gtmcga.asm`, and `asm/common.inc` show that town pattern banks load a relocated pointer table at `seg1:8000h`.

- `tile_anim_count_table` lives at `8000h`
- `special_tile_list_ptr` lives at `8002h`
- `tile_animation_replacement_table` lives at `8004h`

`load_and_decompress_patterns` relocates those pointers, so the blocked-tile list comes from the loaded pattern bank, not from the MDT map file itself.

### GRP sample evidence

The unpacked `cpat.grp` sample in `tools/grpviewer/cpat.grp.unp` exposes a counted special-tile list:

- pointer at `0x8002` resolves to a list with count `2`
- the two blocked tile IDs are `0x3C` and `0x3D`

That is the clearest repository-local evidence for town walkability in the `cmap.mdt` case.

### MDT sample evidence

Both checked-in samples are identical:

- `tools/cmap.mdt`
- `game/0/cmap.mdt`

They decode to the same map:

- width `114`
- height `8`
- same file hash

The decoded grid contains tile IDs `0x3C` and `0x3D`, which line up with the blocked list above. The rest of the observed tile IDs in the sample are not present in that blocked list.

## Walkable vs blocked

### Confirmed blocked town tiles for `cmap.mdt`

- `0x3C`
- `0x3D`

### Confirmed walkable rule

Any town tile not in the special blocked list is walkable, subject to NPC blocking on the same x position.

### What the map sample suggests

The `cmap.mdt` grid uses many tile IDs, but only `0x3C` and `0x3D` have direct evidence here as blocked. The sample's remaining tile IDs should be treated as walkable by the town rule unless another file-specific list says otherwise.

## Town vs dungeon

The collision model is different for town and dungeon maps.

### Town

- tile-index based blocked list
- coordinate-driven sampling of the edge tile
- separate non-passable NPC check

### Dungeon

`asm/fight.asm` shows a different passability system:

- `is_blocking` treats `AL >= 0x80` as non-passable monster/item markers
- `0x49..0x7F` is treated as passable door range
- `AL < 0x49` is checked against a 24-byte passable-tile list at `seg1:8000h`

That is code-driven passability with a shared passable list, not the same town `special_tile_list` rule.

`asm/dungeon.inc` also shows dungeon door metadata using tile-type bits in the door flags, which supports the idea that dungeon traversal uses separate runtime rules from town maps.

## Strongest files

- `asm/town.asm`
- `asm/gtmcga.asm`
- `asm/common.inc`
- `asm/fight.asm`
- `tools/mdtviewer/core/decoder.py`
- `tools/mdtviewer/rendering/map_renderer.py`
- `tools/mdtviewer/core/constants.py`
- `tools/grpviewer/cpat.grp.unp`
- `tools/cmap.mdt`
- `game/0/cmap.mdt`

## Uncertain

- I have not yet traced whether every town pattern bank (`mpat.grp`, `dpat.grp`, `cpat.grp`) has its own special blocked list, though the code strongly suggests it does.
- I have not yet mapped every visible `cmap.mdt` tile graphic to a semantic name, so only the blocked IDs are confirmed here.
- I have not yet confirmed whether any town-specific exceptions exist beyond the special-tile list and NPC blocking.

## Next minimal C++ step

After this analysis, the smallest useful C++ change would be:

1. parse the town tile grid
2. expose the loaded special-tile list
3. add a read-only helper that asks whether a tile ID is blocked
4. keep NPC blocking separate

That keeps collision work small and avoids building a large gameplay layer too early.
