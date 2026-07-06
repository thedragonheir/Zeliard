# Overlays, buildings, inventory, demos, and AI modules

## Scope

This document explains the non-core overlays and support modules:

- building/shop modules: `kingpro.asm`, `kenjpro.asm`, `armrpro.asm`, `drugpro.asm`, `bankpro.asm`, `churpro.asm`, `innapro.asm`, `omoypro.asm`
- inventory: `select.asm`
- demos and decoration: `opdemo.asm`, `rokademo.asm`, `mole.asm`, `ympd.asm`, `ckpd.asm`
- monster/boss AI: `eai1.asm`, `crab.asm`

These modules are loaded only when needed. Most of them use `org 0A000h` and therefore occupy a large overlay slot.

## Common building overlay pattern

Most building modules follow the same setup pattern:

```text
load building .grp portrait/background into seg1:8000h
call Reassemble_3_Planes_To_Packed_Bitmap
reset dialog cursor/scroll state
clear viewport
clear place/enemy bar
render building/place name
render portrait or building scene
open dialog rectangle
set dialog_string_ptr
loop render_menu_dialog until FFh means exit
fade to black
```

A typical code pattern appears in king, sage, armor, drug, bank, church, and inn modules:

```asm
mov es, word ptr ds:seg1
mov di, 8000h
mov si, offset vfs_..._grp
mov al, 2
call word ptr cs:res_dispatcher_proc

push ds
mov ds, word ptr cs:seg1
mov si, 8000h
mov cx, 100h
call word ptr cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
pop ds
```

This gives all buildings a consistent graphics-loading path.

## Building modules summary

| Module | Likely role | Entry table shape | Notable behavior |
|---|---|---|---|
| `kingpro.asm` | King / throne room dialog | two entries | Can grant 1000 gold and story/state effects. |
| `kenjpro.asm` | Sage / resurrection / level up | three entries | Handles resurrection path, sage names by town, level-up logic. |
| `armrpro.asm` | Armor/sword/shield shop | two entries | Loads prices by town, checks crest/story flags, sells equipment. |
| `drugpro.asm` | Item/magic/potion shop | two entries | Purchase menus and inventory/gold updates. |
| `bankpro.asm` | Bank | two entries | Updates 24-bit values, deposits/withdraws gold. |
| `churpro.asm` | Church | two entries | Dialog and likely healing/resurrection/save-adjacent logic. |
| `innapro.asm` | Inn | two entries | Dialog, payment/rest flow, HP recovery. |
| `omoypro.asm` | Hut/end-demo path | two entries | Loads hut graphics and can branch into `enddemo.bin`. |

Procedure lists:

| File | Procedures |
|---|---|
| `kingpro.asm` | `sub_A004`, `sub_A06D`, `sub_A114`, `sub_A302`, `sub_A315`, `sub_A3E8` |
| `kenjpro.asm` | `sage_resurrect`, `sub_A05A`, `on_dialog_result`, `on_go_outside`, `on_see_power`, `on_listen_knowledge`, `sub_A1D1`, `sub_A200`, `checkLevelUp`, `level_up`, `sub_A410`, `sub_A427`, `sub_A528`, `sub_A559`, `sub_A790`, `sub_A7FD`, `sub_A914`, `sub_A93B`, `sub_A983`, `sub_A990`, `sub_AA16`, `sub_AB47`, `sub_AC07` |
| `armrpro.asm` | `sub_A004`, `sub_A0B6`, `sub_A0E2`, `sub_A10E`, `sub_A47B`, `sub_A706`, `sub_A870`, `sub_A8E0`, `sub_A902`, `sub_A90F`, `sub_A9CF` |
| `drugpro.asm` | `sub_A004`, `sub_A08C`, `sub_A0B8`, `sub_A49C`, `sub_A5B2`, `sub_A5BF`, `sub_A644`, `sub_A708` |
| `bankpro.asm` | `sub_A004`, `sub_A0AD`, `sub_A61F`, `update_24bit_value_according_to_al_flags`, `sub_A6A3`, `sub_A728`, `sub_A813` |
| `churpro.asm` | `sub_A004`, `sub_A06D`, `sub_A089`, `sub_A152`, `sub_A1D7`, `sub_A1FA`, `sub_A288` |
| `innapro.asm` | `sub_A004`, `sub_A05F`, `sub_A075`, `sub_A15F`, `sub_A16F`, `sub_A17F`, `sub_A1AA`, `sub_A22F` |
| `omoypro.asm` | - |

## Dialog integration

The building modules do not implement a completely separate dialog renderer. They call back into `town.bin` through:

```text
render_menu_dialog_proc
select_from_menu_proc
show_yes_no_dialog_proc
check_gold_sufficient_proc
add_gold_to_hero_proc
```

This makes building-specific code mostly about:

- choosing text strings,
- choosing menu actions,
- changing savegame/inventory/gold variables,
- loading the correct portrait/background GRP.

## Inventory overlay, `select.asm`

`select.asm` is loaded at `org 0A000h` and exports:

```text
0A000h Inventory_Screen
0A002h Inventory_Screen_Full
```

Important procedures:

`Inventory_Screen`, `Render_Selected_Magic_Detail`, `Draw_Magic_Status_Frame`, `Render_Selected_Accessory_Detail`, `Draw_Accessory_Status_Frame`, `Render_Selected_Item_Detail`, `Draw_Item_Status_Frame`, `Clear_Item_Panel`, `Render_Item_Usage_Text`, `Capture_Screen_Backup`, `Restore_Screen_From_Backup`, `Collect_Active_Items`, `Render_Items_Panel`, `Render_Wearables_Panel`, `Render_Selected_Accessory`, `Render_Equipment_Panel`, `Render_Shield_HP_Detail`, `Render_Enchantment_Count`, `Render_Magics_Panel`, `Render_Magic_Counts_Panel`, `Render_Decimal_Number`, `Render_Menu_Labels`, `Render_String_At_Position`, `Check_Menu_Exit`, `Check_Enter_Pressed`

The inventory screen:

1. Draws four framed panels.
2. Collects active spells from `espada_active..guerra_active`.
3. Collects wearable equipment from shoe/cape flags.
4. Collects active item slots.
5. Renders magic, wearables, items, and equipment panels.
6. Handles cursor navigation and Enter/exit.
7. Renders selected item details.

The inventory overlay uses `gmmcga` icon renderers and decimal display helpers.

## Demo modules

### `opdemo.asm`

Opening demo/story module loaded at `6000h`. It contains animation and RLE decompression helpers.

Procedures:

`sub_6002`, `sub_62D1`, `sub_62FD`, `sub_6358`, `sub_63AB`, `sub_63CC`, `sub_6456`, `sub_6497`, `sub_6A07`, `sub_6A18`, `sub_6A75`, `sub_6CC4`, `sub_6D04`, `sub_6D5E`, `sub_6D63`, `RLE_decompress`, `sub_6E0F`, `sub_6E4F`, `sub_6E5E`, `sub_6E6D`, `sub_6E8F`, `sub_6EB0`, `sub_6ED8`, `sub_6F41`, `sub_6FAC`

It uses `RLE_decompress` and several rendering subroutines to present the initial story sequence before normal gameplay.

### `rokademo.asm`

Roka demo/special sequence module loaded around `0A000h`.

Procedures:

`sub_A002`, `sub_A407`, `sub_A48F`, `sub_A4A3`, `sub_A50A`

It cooperates with graphics routines such as `Render_Roca_Tilemap` in `gfmcga.asm`.

## Decorative canvas modules

### `mole.asm`

`mole.bin` is loaded into `seg3:0` by `game.asm` and called through `DrawDecorationsAroundCanvas_proc`. It handles decorative frame/canvas rendering and video-mode-specific unpacking.

Procedures:

`DrawDecorationsAroundCanvas`, `SetGraphicsMode`, `DecompressToVRAM`, `Unpack2bppTo4bit_MCGA`, `UnpackPixels_CGA_Alt`, `DrawTitleFrame`, `CopyFrameBytes_EGA`, `RenderFrameRows_MCGA`, `ExpandByteToPixels_MCGA`, `RenderFrameRows_CGA_Alt`, `ProcessPixel_CGA_Alt`, `DecompressRLE`

Key roles:

- set graphics mode,
- decompress to VRAM,
- draw title/frame rows,
- handle MCGA/CGA/EGA variants,
- expand packed pixels.

### `ympd.asm` and `ckpd.asm`

These appear to be town/background decoration modules loaded around `3300h`, matching `town_background_decorations` in `common.inc`.

| Module | Procedures |
|---|---|
| `ympd.asm` | - |
| `ckpd.asm` | - |

They include mountain/ground/background rendering and RLE-style decode helpers.

## Monster AI module, `eai1.asm`

`eai1.asm` is a monster AI overlay loaded at `0A000h`.

Procedures:

`Monster_AI`, `bat_step_throttle`, `frog_hero_proximity_and_direction`, `rat_hero_proximity_and_direction`

It exports `Monster_AI` and contains behavior helpers for bats, frogs, and rats. Rather than owning all movement logic, it calls fight engine movement and collision functions through the `fight.bin` export table.

This split is important:

```text
AI overlay decides intention
fight.bin performs movement/collision/proximity services
```

## Boss module, `crab.asm`

`crab.asm` implements the Cangrejo/crab boss logic and rendering helpers.

Procedures:

`Cangrejo_AI_proc`, `boss_move_left`, `boss_move_right`, `trigger_acid_drop`, `begin_recoil`, `death_sequence_handler`, `render_body_sprites`, `apply_damage_to_boss`

Key responsibilities:

- boss movement left/right,
- acid drop trigger,
- recoil begin,
- death sequence,
- body sprite rendering,
- damage application.

It uses the boss state structure and shares rendering services with `gfmcga.bin`.

## Overlay slot consequences

Because many overlays share `org 0A000h`, they cannot all be resident at the same time. The game loads them on demand:

```text
enter building -> load building overlay -> run dialog/shop -> fade out -> return to town
open inventory -> load/select overlay or use cached select -> render inventory -> return
start boss AI -> load AI/boss overlay -> call exported AI routine
```

This pattern is a central design choice in the original codebase.

## Porting notes

For a modern port, treat overlays as separate scene/controller classes:

| Original overlay | Modern class idea |
|---|---|
| `kingpro.bin` | `KingScene` |
| `kenjpro.bin` | `SageScene` |
| `armrpro.bin` | `ArmorShopScene` |
| `drugpro.bin` | `ItemShopScene` |
| `bankpro.bin` | `BankScene` |
| `churpro.bin` | `ChurchScene` |
| `innapro.bin` | `InnScene` |
| `select.bin` | `InventoryScreen` |
| `eai1.bin` | `MonsterAiPack1` |
| `crab.bin` | `CrabBossController` |

Keep their shared dependencies explicit: dialog renderer, resource loader, save state, gold/inventory functions, and graphics UI driver.
