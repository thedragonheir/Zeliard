# NPC Sprite Analysis

This note records the repo-local evidence for town NPC sprite selection and why the town debug overlay can now render them without guessing at `NpcId`.

## What The Repo Confirms

- `asm/town.asm` shows that town NPC records are 8 bytes long.
- `asm/town.asm` uses byte 7 (`n_id`) only for the conversation lookup path.
- `asm/gtmcga.asm` shows the sprite selector in byte 2, with bit 7 used for facing and byte 4 used for the animation phase.
- `tools/mdtviewer/rendering/map_renderer.py` follows the same sprite-selection rule for its town NPC preview.
- `tools/cmap.mdt` and `game/0/cmap.mdt` contain NPC records whose byte 2 values match that selector layout.

## What That Means For The Town Debug Pass

- `NpcId` should stay as the dialogue key.
- Town NPC sprites should be rendered from the parsed sprite-selector byte and animation phase, not from `NpcId`.
- The first pass can stay narrow and render only the confirmed town NPC sprite families already present in `mman.grp` / `cman.grp`.

## What Remains Uncertain

- The exact narrative meaning of each sprite family inside the town NPC bank.
- Whether every town uses the same NPC sprite bank, or whether some towns should switch between `mman.grp` and `cman.grp` at runtime.
- Whether the current debug anchor should stay on the head-level row or move by one tile after a live visual comparison.
