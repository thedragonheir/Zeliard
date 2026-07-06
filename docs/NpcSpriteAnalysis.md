# NPC Sprite Analysis

This note records the repo-local evidence for town NPC sprite selection and why the town debug overlay can now render them without guessing at `NpcId`.

## What The Repo Confirms

- `asm/town.asm` shows that town NPC records are 8 bytes long.
- `asm/town.asm` uses byte 7 (`n_id`) only for the conversation lookup path.
- `asm/gtmcga.asm` shows the sprite selector in byte 2, with bit 7 used for facing and byte 4 used for the animation phase.
- `asm/game.asm` and `asm/town.asm` route town NPC sprites through the descriptor byte at `town_descriptor_addr[1]`.
- `tools/mdtviewer/core/decoder.py` mirrors that rule and selects `mman.grp` when the descriptor byte is `0`, `cman.grp` when it is `1`.
- `tools/cmap.mdt` and `game/0/cmap.mdt` currently decode to `mman.grp` from the checked-in descriptor bytes.
- `tools/mdtviewer/rendering/map_renderer.py` follows the same sprite-selection rule for its town NPC preview.

## What That Means For The Town Debug Pass

- `NpcId` should stay as the dialogue key.
- Town NPC sprites should be rendered from the parsed sprite-selector byte and animation phase, not from `NpcId`.
- `mman.grp` and `cman.grp` are the descriptor-selected town NPC banks.
- `tman.grp` is the town player/debug actor source and stays independent from NPC-bank selection.
- `fman.grp` is for future dungeon/cavern hero rendering, not the current town view.
- The town actor mapping uses the first confirmed non-empty `tman.grp` frame in each left/right set as the provisional idle frame.
- Actor and NPC frames that load but contain only transparent pixels should be treated as empty and drawn with fallback markers instead of disappearing.
- The first pass should stay narrow: render confirmed 8-frame family mappings as sprites, but keep every parsed NPC visible.
- Unconfirmed families, missing frames, or failed frame loads should render as debug markers at the parsed X/Y position instead of disappearing.
- `NPCSPR` should count only actual NPC sprites drawn; `NPCMISS` should count NPCs drawn as fallback markers.

## What Remains Uncertain

- The exact narrative meaning of each sprite family inside the town NPC bank.
- Whether all descriptor-selected NPC banks use the same family mapping.
- Whether the current debug anchor should stay on the head-level row or move by one tile after a live visual comparison.
