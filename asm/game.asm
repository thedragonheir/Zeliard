include common.inc
include gdmcga.inc
include town.inc
include dungeon.inc
                .286
                .model small
game            segment byte public 'CODE' use16
                assume cs:game, ds:game
                org 0A000h
start:
; Input:
; AX = 0: game entry after opening demo or restart
; AX = 0ffffh: restored from save file
                mov     cs:is_restore_game, ax
                mov     ax, cs
                mov     ds, ax
                push    cs
                pop     es
                mov     di, bold_font_8x8
                mov     si, offset vfs_font_grp
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                add     es:[di], di
                add     es:[di+2], di
                add     es:[di+4], di
                call    word ptr cs:raw_joystick_calibration_read_proc
                xor     al, al
                mov     byte ptr ds:on_rope_flags, al
                mov     byte ptr ds:hero_hidden_flag, al
                mov     byte ptr ds:sword_swing_flag, al
                mov     byte ptr ds:ui_element_dirty, al
                mov     byte ptr ds:spell_active_flag, al
                mov     byte ptr ds:jump_phase_flags, al
                mov     byte ptr ds:squat_flag, al
                mov     byte ptr ds:hero_damage_this_frame, al
                mov     byte ptr ds:byte_FF3E, al
                mov     byte ptr ds:byte_FF4B, al
                mov     byte ptr ds:heartbeat_volume, al
                mov     byte ptr ds:hero_animation_phase, al
                mov     byte ptr ds:keyboard_alt_mode_flag, al
                mov     byte ptr ds:font_highlight_flag, al
                mov     byte ptr ds:shield_anim_active, al
                mov     byte ptr ds:slope_direction, al
                mov     ax, cs
                mov     es, ax
                xor     bx, bx
                mov     bl, byte ptr ds:video_drv_id
                add     bx, bx
                mov     si, ds:gd_video_drivers[bx]
                mov     di, 3000h
                mov     al, 3       ; fn3_read_virtual_file
                call    word ptr cs:res_dispatcher_proc
                call    word ptr cs:NoOp_proc
                cmp     cs:is_restore_game, 0FFFFh
                jz      short on_restore
                ; restart game
                mov     byte ptr cs:font_highlight_flag, 0FFh
                mov     si, offset vfs_opdemo_bin
                mov     di, opdemo_proc
                mov     al, 3       ; fn3_read_virtual_file
                call    word ptr cs:res_dispatcher_proc
                jmp     word ptr ds:opdemo_proc  ; go to initial story
; ---------------------------------------------------------------------------

on_restore:
                call    set_palette
                mov     ax, cs
                mov     es, ax
                xor     bx, bx
                mov     bl, byte ptr ds:video_drv_id
                add     bx, bx
                mov     si, ds:gt_video_drivers[bx]
                mov     di, gtmcga_drv_addr  ; load gtmcga.bin into seg0:3000h
                mov     al, 3
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     si, offset vfs_town_bin
                mov     di, town_entry_enabling_edge_scroll_proc ; start of town code
                mov     al, 3
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax    ; seg2
                xor     bx, bx
                mov     bl, byte ptr ds:video_drv_id
                add     bx, bx
                mov     si, ds:gf_video_drivers[bx]
                mov     di, 9000h   ; load gfmcga.bin into seg2:9000h
                mov     al, 3
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     si, offset vfs_fight_bin
                mov     di, 0C000h  ; load fight.bin into seg2:0C000h
                mov     al, 3
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     ax, cs
                add     ax, 1000h   ; seg1
                mov     es, ax
                mov     si, offset vfs_select_bin
                mov     di, 0C000h  ; load select.bin into seg1:0C000h
                mov     al, 3
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     ax, cs
                add     ax, 1000h
                mov     es, ax          ; seg1
                mov     si, offset vfs_itemp_grp
                mov     di, sword_item_gfx
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                add     es:[di], di
                add     es:[di+2], di
                add     es:[di+4], di
                add     es:[di+6], di
                add     es:[di+8], di
                add     es:[di+0Ah], di
                add     es:[di+0Ch], di
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax          ; seg2
                mov     di, 0           ; due to dst=0 there is no need to relocate sprite offsets
                mov     si, offset vfs_magic_grp
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax  ; seg2
                mov     si, offset vfs_sword_grp
                mov     di, sword_grp_sprites   ; load to seg2:1800h
                mov     al, 2 ; fn2_segmented_load
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                add     es:[di], di     ; seg2:[1800h]+=1800h
                add     es:[di+2], di   ; seg2:[1802h]+=1800h
                add     es:[di+4], di   ; seg2:[1804h]+=1800h
                mov     ah, ds:sword_type
                mov     al, 4 ; fn4_load_sword_graphics ; AH: sword id (0..6)
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     ax, cs
                mov     ds, ax
                add     ax, 3000h
                mov     ds:DrawDecorationsAroundCanvas_seg, ax ; seg3
                mov     es, ax
                mov     di, 0
                mov     si, offset vfs_mole_bin
                mov     al, 3
                call    word ptr cs:res_dispatcher_proc
                mov     al, byte ptr ds:video_drv_id
                push    ds
                call    dword ptr ds:DrawDecorationsAroundCanvas_proc ; calls mole.bin at seg3:0
                pop     ds
                call    render_tears_collected
                mov     ax, cs
                mov     ds, ax
                test    byte ptr ds:sword_type, 0FFh
                jz      short no_sword_skip_render
                mov     al, ds:sword_type
                mov     bx, 18ABh
                call    word ptr cs:Render_Sword_Item_Sprite_20x18_proc

no_sword_skip_render:
                test    byte ptr ds:shield_type, 0FFh
                jz      short no_shield_skip_render
                mov     al, ds:shield_type
                mov     bx, 3EA4h
                call    word ptr cs:Render_Shield_Item_Sprite_16x16_proc

no_shield_skip_render:
                test    byte ptr ds:current_magic_spell, 0FFh
                jz      short no_magic_skip_render
                mov     al, ds:current_magic_spell
                mov     bx, 37A4h
                call    word ptr cs:Render_Magic_Spell_Item_Sprite_16x16_proc

no_magic_skip_render:
                mov     ah, cs:place_map_id
                mov     al, 1           ; fn1_load_mdt_idx_ah
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                mov     ax, cs
                mov     ds, ax
                add     ax, 1000h
                mov     es, ax          ; seg1
                mov     si, cs:town_descriptor_addr
                lodsb                   ; town descriptor 0: bits 5..1 - msd index
                push    si
                shr     al, 1
                and     al, 1Fh
                mov     cs:msd_index, al
                mov     cl, 11
                mul     cl
                mov     si, ax
                add     si, offset vfs_4_types_of_town_musics
                mov     di, town_msd_music    ; to seg1:3000h
                mov     al, 5           ; fn5_load_music
                call    word ptr cs:res_dispatcher_proc ; res_dispatcher_proc
                pop     si
                lodsb                   ; town descriptor 1: type of town NPCs
                mov     cl, 11
                mul     cl
                mov     si, ax
                add     si, offset vfs_2_types_of_town_npcs
                mov     di, mman_cman_gfx   ; to seg1:4000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                jmp     word ptr ds:town_entry_disabling_edge_scroll_proc

; ---------------------------------------------------------------------------
vfs_font_grp    db 0
                db 0Dh
aFontGrp        db 'font.grp',0
vfs_mole_bin    db 1
                db 8
aMoleBin        db 'mole.bin',0
vfs_itemp_grp   db 1
                db 1Ch
aItempGrp       db 'itemp.grp',0
vfs_select_bin  db 1
                db 2
aSelectBin      db 'select.bin',0
vfs_magic_grp   db 1
                db 1Dh
aMagicGrp       db 'magic.grp',0
vfs_sword_grp   db 1
                db 1Bh
aSwordGrp       db 'sword.grp',0
vfs_fight_bin   db 1
                db 1
aFightBin       db 'fight.bin',0
vfs_town_bin    db 0
                db 7
aTownBin        db 'town.bin',0
vfs_opdemo_bin  db 0
                db 1
aOpdemoBin      db 'opdemo.bin',0
gf_video_drivers dw offset vfs_gfega_bin
                dw offset vfs_gfcga_bin
                dw offset vfs_gfcga_bin
                dw offset vfs_gfhgc_bin
                dw offset vfs_gfmcga_bin
                dw offset vfs_gftga_bin
vfs_gfega_bin   db 1
                db 3
aGfegaBin       db 'gfega.bin',0
vfs_gfcga_bin   db 1
                db 4
aGfcgaBin       db 'gfcga.bin',0
vfs_gfhgc_bin   db 1
                db 5
aGfhgcBin       db 'gfhgc.bin',0
vfs_gfmcga_bin  db 1
                db 7
aGfmcgaBin      db 'gfmcga.bin',0
vfs_gftga_bin   db 1
                db 6
aGftgaBin       db 'gftga.bin',0
gt_video_drivers dw offset vfs_gtega_bin
                dw offset vfs_gtcga_bin
                dw offset vfs_gtcga_bin
                dw offset vfs_gthgc_bin
                dw offset vfs_gtmcga_bin
                dw offset vfs_gttga_bin
vfs_gtega_bin   db 0
                db 8
aGtegaBin       db 'gtega.bin',0
vfs_gtcga_bin   db 0
                db 9
aGtcgaBin       db 'gtcga.bin',0
vfs_gthgc_bin   db 0
                db 0Ah
aGthgcBin       db 'gthgc.bin',0
vfs_gtmcga_bin  db 0
                db 0Ch
aGtmcgaBin      db 'gtmcga.bin',0
vfs_gttga_bin   db 0
                db 0Bh
aGttgaBin       db 'gttga.bin',0
gd_video_drivers dw offset vfs_gdega_bin
                dw offset vfs_gdcga_bin
                dw offset vfs_gdcga_bin
                dw offset vfs_gdhgc_bin
                dw offset vfs_gdmcga_bin
                dw offset vfs_gdtga_bin
vfs_gdega_bin   db 0
                db 2
aGdegaBin       db 'gdega.bin',0
vfs_gdcga_bin   db 0
                db 3
aGdcgaBin       db 'gdcga.bin',0
vfs_gdhgc_bin   db 0
                db 4
aGdhgcBin       db 'gdhgc.bin',0
vfs_gdmcga_bin  db 0
                db 6
aGdmcgaBin      db 'gdmcga.bin',0
vfs_gdtga_bin   db 0
                db 5
aGdtgaBin       db 'gdtga.bin',0
vfs_4_types_of_town_musics db 1
                db 2Fh
aMgt1Msd        db 'MGT1.MSD',0
                db 1
                db 31h
aUgm1Msd        db 'UGM1.MSD',0
                db 1
                db 30h
aMgt2Msd        db 'MGT2.MSD',0
                db 1
                db 32h
aUgm2Msd        db 'UGM2.MSD',0
vfs_2_types_of_town_npcs db 1
                db 1Eh
aMmanGrp        db 'MMAN.GRP',0
                db 1
                db 1Fh
aCmanGrp        db 'CMAN.GRP',0

; =============== S U B R O U T I N E =======================================


render_tears_collected proc near
                test    byte ptr ds:Tears_of_Esmesanti_count, 0FFh
                jnz     short loc_A3AD
                retn
; ---------------------------------------------------------------------------

loc_A3AD:
                mov     cl, ds:Tears_of_Esmesanti_count
                xor     ch, ch
                xor     bx, bx

loc_A3B5:
                push    cx
                push    bx
                mov     dx, bx
                add     bx, bx
                mov     bx, ds:tears_order_coords[bx]
                xor     al, al
                cmp     dx, 8
                jnz     short loc_A3C8
                mov     al, 1

loc_A3C8:
                call    word ptr cs:Render_Icon_16x13_proc
                pop     bx
                inc     bx
                pop     cx
                loop    loc_A3B5
                retn
render_tears_collected endp

; ---------------------------------------------------------------------------
tears_order_coords dw 0F00h
                dw 3D00h
                dw 1500h
                dw 3700h
                dw 1B00h
                dw 3100h
                dw 2100h
                dw 2B00h
                dw 2600h

; =============== S U B R O U T I N E =======================================


set_palette     proc near

                mov     bl, ds:video_drv_id
                xor     bh, bh
                add     bx, bx          ; switch 6 cases
                jmp     cs:jpt_A3ED[bx] ; switch jump
set_palette     endp

; ---------------------------------------------------------------------------
jpt_A3ED        dw offset set_ega_palette ; jump table for switch statement
                dw offset locret_A41A
                dw offset locret_A41A
                dw offset locret_A46F
                dw offset set_mcga_palette
                dw offset locret_A46E
; ---------------------------------------------------------------------------

set_ega_palette:                        ; jumptable 0000A3ED case 0
                push    cs
                pop     es
                mov     dx, offset byte_A409
                mov     ax, 1002h
                int     10h             ; - VIDEO - SET ALL PALETTE REGISTERS (Jr, PS, TANDY 1000, EGA, VGA)
                                        ; ES:DX -> 17-byte palette register list
                retn
; ---------------------------------------------------------------------------
byte_A409       db 0, 3Fh, 24h, 12h, 1Bh, 9, 36h, 2Dh, 38h, 7, 4, 2, 3, 1, 6, 5, 0
; ---------------------------------------------------------------------------

locret_A41A:                            ; jumptable 0000A3ED cases 1,2
                retn
; ---------------------------------------------------------------------------

set_mcga_palette:                       ; jumptable 0000A3ED case 4
                push    cs
                pop     ds
                mov     si, offset byte_A456
                xor     bx, bx
                mov     cx, 8

loc_A425:
                push    cx
                lodsb
                mov     dh, al
                lodsb
                mov     dl, al
                lodsb
                mov     ah, al
                push    si
                mov     si, offset byte_A456
                mov     cx, 8

loc_A436:
                push    cx
                push    ax
                push    dx
                lodsb
                add     dh, al
                lodsb
                add     al, dl
                mov     ch, al
                lodsb
                add     al, ah
                mov     cl, al
                mov     ax, 1010h
                int     10h             ; - VIDEO - SET INDIVIDUAL DAC REGISTER (EGA, VGA/MCGA)
                                        ; BX = register number, CH = new value for green (0-63)
                                        ; CL = new value for blue (0-63), DH = new value for red (0-63)
                inc     bx
                pop     dx
                pop     ax
                pop     cx
                loop    loc_A436
                pop     si
                pop     cx
                loop    loc_A425
                retn
; ---------------------------------------------------------------------------
byte_A456       db 0, 0, 0
                db 1Fh, 1Fh, 1Fh
                db 1Fh, 0, 0
                db 0, 1Fh, 0
                db 0, 1Fh, 1Fh
                db 0, 0, 1Fh
                db 1Fh, 1Fh, 0
                db 1Fh, 0, 1Fh
; ---------------------------------------------------------------------------

locret_A46E:                            ; jumptable 0000A3ED case 5
                retn
; ---------------------------------------------------------------------------

locret_A46F:                            ; jumptable 0000A3ED case 3
                retn
; ---------------------------------------------------------------------------
DrawDecorationsAroundCanvas_proc  dw 0
DrawDecorationsAroundCanvas_seg   dw 3000h
is_restore_game       dw 0
game                  ends
                      end     start
