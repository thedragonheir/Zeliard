# Zeliard documentation

## Scope

This folder contains the Zeliard source and asset documentation in one flat documentation directory.

Naming convention:

- filenames are lowercase
- words are separated with underscores
- there are no numeric prefixes
- all files are Markdown

The numeric prefixes used in the earlier generated pack were only meant to force a reading order in file explorers. This version keeps the order inside this `readme.md` instead, which is cleaner for the existing lowercase source-tree style.

## Recommended reading order

| Order | Document | Main subject |
|---:|---|---|
| 1 | `runtime_architecture_and_build.md` | DOS executable startup, build scripts, binary overlays, and entry points. |
| 2 | `global_memory_map_and_data_structures.md` | Shared memory, savegame offsets, town structs, dungeon structs, and segment conventions. |
| 3 | `resource_input_interrupts_and_audio.md` | Resource loading, input, keyboard/joystick/timer interrupts, music, and SFX. |
| 4 | `common_mcga_ui_and_palette_driver.md` | Shared MCGA UI driver, HUD, fonts, item icons, decimal rendering, and palette helpers. |
| 5 | `town_engine_and_town_graphics.md` | Town gameplay, NPCs, doors, dialog, scrolling, town graphics, shadow VRAM, and `gtmcga`. |
| 6 | `dungeon_gameplay_engine.md` | Dungeon/fight gameplay loop, MDT unpacking, hero movement, collision, monsters, projectiles, and bosses. |
| 7 | `dungeon_and_fight_graphics_drivers.md` | Dungeon/fight graphics drivers, dirty tile rendering, sprites, palette transforms, and Roca tilemaps. |
| 8 | `overlays_buildings_inventory_demos_and_ai.md` | Shops, building overlays, inventory overlay, demo modules, monster AI modules, and boss modules. |
| 9 | `grp_assets_and_graphics_formats.md` | GRP containers, render modes, tile/sprite formats, palette usage, and validation strategy. |

## Focused analysis notes

| Document | Subject |
|---|---|
| `collision_analysis.md` | Town and dungeon collision rules. |
| `grp_analysis.md` | GRP container, decompression, render modes, palettes, and implementation order. |
| `mdt_analysis.md` | MDT map structure and how maps reference GRP pattern banks. |
| `npc_sprite_analysis.md` | Town NPC sprite selection, selector bytes, facing, and animation phase. |
| `sprite_grp_analysis.md` | Sprite-like GRP files, character sheets, monsters, bosses, masks, and palette paths. |
| `town_analysis.md` | Town NPCs, doors, shops, object tables, interactions, and building transitions. |
| `town_fidelity_audit.md` | C++ town movement fidelity notes against the assembly-backed horizontal state. |

## Source file inventory

| File | Bytes | Proc count | Main `org` values | Includes |
|---|---:|---:|---|---|
| `adlib.inc` | 174 | 0 | - | - |
| `armrpro.asm` | 78,778 | 11 | 0A000h | common.inc, town.inc |
| `bankpro.asm` | 39,512 | 7 | 0A000h | common.inc, town.inc |
| `build.sh` | 895 | 0 | - | - |
| `build_all.sh` | 7,649 | 0 | - | - |
| `churpro.asm` | 12,682 | 7 | 0A000h | common.inc, town.inc |
| `ckpd.asm` | 79,507 | 10 | 100h, 3300h | common.inc |
| `common.inc` | 38,628 | 0 | - | - |
| `crab.asm` | 32,261 | 8 | 0A000h | common.inc, dungeon.inc |
| `drugpro.asm` | 43,094 | 8 | 0A000h | common.inc, town.inc |
| `dungeon.inc` | 8,036 | 0 | - | - |
| `eai1.asm` | 38,713 | 4 | 0A000h | common.inc, dungeon.inc |
| `exe2bin.py` | 1,115 | 0 | - | - |
| `fight.asm` | 422,484 | 180 | 6000h | common.inc, dungeon.inc |
| `game.asm` | 17,888 | 2 | 0A000h | common.inc, gdmcga.inc, town.inc, dungeon.inc |
| `gdmcga.asm` | 92,988 | 46 | 3000h | common.inc |
| `gdmcga.inc` | 1,197 | 0 | - | - |
| `gfmcga.asm` | 164,421 | 79 | 3000h | common.inc, dungeon.inc |
| `gmmcga.asm` | 63,120 | 47 | 2000h | common.inc |
| `gtmcga.asm` | 72,837 | 57 | 3000h | common.inc, town.inc |
| `innapro.asm` | 13,730 | 8 | 0A000h | common.inc, town.inc |
| `kenjpro.asm` | 64,769 | 23 | 0A000h | common.inc, town.inc |
| `kingpro.asm` | 19,281 | 6 | 0A000h | common.inc, town.inc |
| `mole.asm` | 94,230 | 12 | 100h, 0 | - |
| `mole.inc` | 68 | 0 | - | - |
| `mscadlib.asm` | 55,384 | 30 | 100h | common.inc, adlib.inc |
| `omoypro.asm` | 7,320 | 3 | 0A000h | - |
| `opdemo.asm` | 124,164 | 25 | 6000h | common.inc, gdmcga.inc |
| `rokademo.asm` | 20,275 | 5 | 0A000h | common.inc, gdmcga.inc |
| `select.asm` | 60,443 | 25 | 0A000h | common.inc |
| `sndadlib.asm` | 101,493 | 15 | 1100h, 1100h | common.inc |
| `snippet.asm` | 3,067 | 2 | - | - |
| `stick.asm` | 75,771 | 43 | 100h | common.inc, dungeon.inc |
| `town.asm` | 164,592 | 68 | 6000h | common.inc, town.inc |
| `town.inc` | 5,079 | 0 | - | - |
| `ympd.asm` | 94,569 | 10 | 100h, 3300h | common.inc |
| `zeliard.asm` | 44,942 | 14 | - | common.inc, adlib.inc |

## High-level architecture in one view

```text
ZELIARD.EXE
  |
  |-- Parses RESOURCE.CFG
  |-- Allocates the large runtime segment
  |-- Loads resident modules and drivers
  |     |
  |     |-- stick.bin   at 0100h
  |     |-- gmmcga.bin  at 2000h
  |     |-- music driver and SFX driver through INT 60h/INT 61h
  |
  |-- Loads game.bin at A000h
        |
        |-- Loads context graphics drivers
        |     |
        |     |-- gtmcga.bin for towns, loaded at 3000h
        |     |-- gdmcga.bin for dungeon/decompression support, loaded at 3000h
        |     |-- gfmcga.bin for fight/dungeon rendering, loaded at 3000h or seg2:9000h depending on phase
        |
        |-- Loads gameplay overlays
              |
              |-- town.bin  at 6000h
              |-- fight.bin at 6000h or seg2:C000h
              |-- select.bin, shops, sages, king, inn, church, demos at A000h/C000h-style overlay slots
```

## Main naming convention used in these docs

- **game_cseg** means the primary runtime code segment allocated by `zeliard.asm`.
- **seg1** means `game_cseg + 1000h`.
- **seg2** means `game_cseg + 2000h`.
- **seg3** means `game_cseg + 3000h`.
- **VRAM** means segment `A000h`, the visible MCGA/VGA framebuffer.
- **Shadow VRAM** means the offscreen area beginning at `vram_shadow_addr = 320*200 = FA00h` in the video segment.

## Important caution

Many addresses in `common.inc`, `town.inc`, and `dungeon.inc` are offset constants, not standalone pointers. They only make sense together with the currently selected segment. For example, `0C000h` can mean town data, dungeon data, select overlay data, or fight overlay data depending on which module owns the segment at that moment.
