# NPC Sprite Analysis

This note records the repo-local evidence for town NPC sprite selection and why the town debug overlay can now render them without guessing at `NpcId`.

## What The Repo Confirms

- `asm/town.asm` shows that town NPC records are 8 bytes long.
- `asm/town.asm` uses byte 7 (`n_id`) only for the conversation lookup path.
- `asm/gtmcga.asm` shows the sprite selector in byte 2, with bit 7 used for facing and byte 4 used for the animation phase.
- The sprite selector maps directly to `mman.grp` / `cman.grp` frame blocks by low nibble, with `n_anim_phase & 3` selecting the phase inside each 8-frame block.
- `asm/game.asm` and `asm/town.asm` route town NPC sprites through the descriptor byte at `town_descriptor_addr[1]`.
- `tools/mdtviewer/core/decoder.py` mirrors that rule and selects `mman.grp` when the descriptor byte is `0`, `cman.grp` when it is `1`.
- `tools/cmap.mdt` and `game/0/cmap.mdt` currently decode to `mman.grp` from the checked-in descriptor bytes.
- `tools/mdtviewer/rendering/map_renderer.py` follows the same sprite-selection rule for its town NPC preview.
- The checked `cmap.mdt` sample uses selector bytes `0x80` and `0x81`, which resolve to family 1 frames `8` and `9` with the same facing/phase arithmetic as the other confirmed town blocks.

## What That Means For The Town Debug Pass

- `NpcId` should stay as the dialogue key.
- Town NPC sprites should be rendered from the parsed sprite-selector byte and animation phase, not from `NpcId`.
- `mman.grp` and `cman.grp` are the descriptor-selected town NPC banks.
- Town selector families `0` through `4` are confirmed and should render as sprite frames when their bank frame loads cleanly.
- `tman.grp` is the town player/debug actor source and stays independent from NPC-bank selection.
- `fman.grp` is for future dungeon/cavern hero rendering, not the current town view.
- Actor and NPC frames that load but contain only transparent pixels should be treated as empty and drawn with fallback markers instead of disappearing.
- The first pass should stay narrow: render confirmed 8-frame family mappings as sprites, but keep every parsed NPC visible.
- Unconfirmed families, missing frames, or failed frame loads should render as debug markers at the parsed X/Y position instead of disappearing.
- `NPCSPR` should count only actual NPC sprites drawn; `NPCMISS` should count NPCs drawn as fallback markers.

## What Remains Uncertain

- The exact narrative meaning of each sprite family inside the town NPC bank.
- Whether any selector families beyond `0` through `4` are actually used in towns.
- Whether the current debug anchor should stay on the head-level row or move by one tile after a live visual comparison.
