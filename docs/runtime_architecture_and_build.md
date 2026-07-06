# Runtime architecture and build documentation

## Scope

This document explains how the uploaded Zeliard source tree is built and how the original DOS runtime loads code and data into fixed memory slots.

Primary sources:

- `build_all.sh`
- `exe2bin.py`
- `zeliard.asm`
- `game.asm`
- `common.inc`

## Build model

The project is built as a collection of small DOS executables and then converted into flat binary overlays. The build script compiles each `.asm` file with TASM, links it with TLINK, then calls `exe2bin.py` with a load-base correction.

Representative conversion targets:

| Source | Linked executable | Flat binary | Runtime load address |
|---|---|---|---:|
| `zeliard.asm` | `ZELIARD.EXE` | executable remains EXE | DOS program entry |
| `stick.asm` | `STICK.EXE` | `stick.bin` | `0100h` |
| `game.asm` | `GAME.EXE` | `game.bin` | `0A000h` |
| `gmmcga.asm` | `GMMCGA.EXE` | `gmmcga.bin` | `2000h` |
| `gdmcga.asm` | `GDMCGA.EXE` | `gdmcga.bin` | `3000h` |
| `gtmcga.asm` | `GTMCGA.EXE` | `gtmcga.bin` | `3000h` |
| `gfmcga.asm` | `GFMCGA.EXE` | `gfmcga.bin` | `3000h` |
| `town.asm` | `TOWN.EXE` | `town.bin` | `6000h` |
| `fight.asm` | `FIGHT.EXE` | `fight.bin` | `6000h` |
| shop/building modules | `*.EXE` | `*.bin` | usually `0A000h` |

The repeated `org` values are deliberate. They are not normal executable addresses. They are overlay-slot addresses. Different modules can occupy the same slot at different times.

## Bootstrap sequence in `zeliard.asm`

`zeliard.asm` is the true DOS launcher. Its `start` procedure performs these steps:

1. Clear direction flag with `cld`.
2. Query the DOS version through `INT 21h, AH=30h`.
3. Parse the command line.
4. Open and parse `RESOURCE.CFG`.
5. Choose video, music, sound, and joystick settings.
6. Allocate the large runtime memory block.
7. Optionally run `MTINIT.COM` for MT-32 setup.
8. Save old interrupt vectors.
9. Load resident binaries into the allocated game segment.
10. Install new interrupt handlers.
11. Reprogram the PIT timer.
12. Set the requested graphics mode.
13. Jump into `game.bin` at `0A000h`.

The code stores old interrupt vectors for clean restoration on exit. It hooks keyboard, timer, critical-error, music, and joystick/resource services.

## `RESOURCE.CFG` parsing

`zeliard.asm` tokenizes the config file and then calls dedicated parsers:

| Parser | Purpose |
|---|---|
| `Parse_Config_Token` | Reads the next config token from file input. |
| `Parse_Video_drv` | Converts video config into a driver index and video mode choice. |
| `Parse_Music_Driver` | Selects the music driver and MT-32 flag. |
| `Parse_Sound_FX_Driver` | Selects sound effects driver. |
| `Parse_joystick_yesno` | Enables or disables joystick use. |
| `Find_Colon_In_Token` | Splits key/value token fields. |

The driver filenames are stored into local buffers that are later used by `Load_Resource_File`.

## Resident memory map established by `zeliard.asm`

Near the end of `zeliard.asm`, comments describe the initial memory layout:

```text
game_cseg:
  0000h..00FFh  stdply.bin or savegame.usr
  0100h         stick.bin
  2000h         gmmcga.bin
  0A000h        game.bin

seg1:
  0000h         music driver area, loaded through paragraph adjustment
  1000h         sound effects driver area
```

Later code extends this scheme with `seg2` and `seg3`. The major convention is:

```text
seg1 = game_cseg + 1000h
seg2 = game_cseg + 2000h
seg3 = game_cseg + 3000h
```

This is why the assembly frequently does:

```asm
mov ax, cs
add ax, 1000h ; seg1
mov es, ax
```

or:

```asm
mov ax, cs
add ax, 3000h ; seg3
mov es, ax
```

## Driver slot system

The game uses tables of function pointers at fixed offsets. `common.inc` defines addresses such as:

| Slot | Module | Meaning |
|---:|---|---|
| `0100h` | `stick.bin` | Interrupt entry and service jump table. |
| `2000h` | `gmmcga.bin` | General graphics and UI driver. |
| `3000h` | `gtmcga/gdmcga/gfmcga` | Context-specific graphics driver slot. |
| `6000h` | `town.bin` or `fight.bin` | Main gameplay overlay slot. |
| `0A000h` | `game.bin`, buildings, select, demos | Large overlay slot. |
| `0C000h` | data or overlay depending on segment | Town MDT data, dungeon MDT data, fight/select overlays. |

A call such as:

```asm
call word ptr cs:res_dispatcher_proc
```

invokes `stick.bin`'s resource dispatcher through the resident table.

A call such as:

```asm
call word ptr cs:Draw_Bordered_Rectangle_proc
```

jumps through the exported function pointer in `gmmcga.bin`.

## `game.asm` startup flow

`game.asm` starts at `org 0A000h`. Its entry receives a restoration flag in `AX`:

| AX value | Meaning |
|---:|---|
| `0000h` | Normal entry after opening demo or restart. |
| `FFFFh` | Restored from a save file. |

The common startup actions are:

1. Load `font.grp` into the font pointer area.
2. Read raw joystick calibration.
3. Reset many runtime flags such as `sword_swing_flag`, `spell_active_flag`, `hero_damage_this_frame`, `heartbeat_volume`, and `hero_animation_phase`.
4. Load the initial dungeon graphics driver based on the selected video driver.

For a new game, `game.asm` loads `opdemo.bin` and jumps to the opening story.

For restore or normal gameplay re-entry, `game.asm` loads:

| Resource | Destination | Purpose |
|---|---:|---|
| town graphics driver | `gtmcga_drv_addr = 3000h` | Town graphics. |
| `town.bin` | `town_entry_enabling_edge_scroll_proc = 6000h` | Town gameplay. |
| fight graphics driver | `seg2:9000h` in restore setup | Fight graphics support. |
| `fight.bin` | `seg2:0C000h` in restore setup | Fight code cached for later. |
| `select.bin` | `seg1:0C000h` | Inventory overlay. |
| `itemp.grp` | `seg1:sword_item_gfx` and related icon pointers | Item icons. |
| `magic.grp` | `seg2:0` | Magic sprite group. |
| `sword.grp` | `seg2:sword_grp_sprites` | Sword sprites. |
| `mole.bin` | `seg3:0` | Decorative border/canvas renderer. |

After this, it reads town descriptor data and loads town music, town NPC sprite group, and finally jumps into `town.bin`.

## Overlay philosophy

Zeliard uses manual overlays because conventional DOS memory is scarce. The code treats fixed offsets as slots. A module can be loaded over another module if both are never needed at the same time.

Examples:

- `gtmcga.bin`, `gdmcga.bin`, and `gfmcga.bin` all use `org 3000h` because only the active graphics context needs that slot.
- `town.bin` and `fight.bin` use the same gameplay slot concept.
- Buildings, inventory, sage, king, and demo modules use the large `0A000h` overlay area.

The result is a custom, game-specific overlay engine rather than one monolithic program.

## Exit and cleanup

`Handle_Game_Exit` restores the environment:

- Restores old interrupt vectors.
- Restores timer/PIT behavior.
- Frees allocated memory.
- Prints exit/status messages.
- Returns control to DOS.

This is important because the program temporarily owns hardware-level services like keyboard and timer interrupts.

## Practical consequences for porting

When porting this source, do not translate absolute offsets naively into global C++ pointers. First classify each address:

| Address style | Meaning in original source | Porting equivalent |
|---|---|---|
| `org 3000h` | Overlay slot offset | Module interface table or class instance. |
| `0C000h` | Contextual data/overlay area | Variant-owned buffer or typed structure. |
| `0E000h` | Proximity map / viewport buffer base | Runtime map window array. |
| `0FFxxh` | Shared global runtime variables | Engine state struct. |
| `A000:xxxx` | Video framebuffer | Indexed framebuffer or texture memory. |

The safest modernization path is to preserve the original logical regions first, then gradually replace raw offsets with typed structures.
