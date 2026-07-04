include common.inc
include town.inc
                .286
                .model tiny

kenjpro         segment byte public 'CODE'
                assume cs:kenjpro, ds:kenjpro
                org 0A000h
start:
                dw offset sage_normal
                dw offset sub_AB47
                dw offset sage_resurrect

; =============== S U B R O U T I N E =======================================


sage_resurrect  proc near
                call    sub_A05A
                mov     word_BB12, 0E17h
                call    sub_A990
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:dialog_string_ptr, offset byte_BA67 ; 'While you were...'
                jmp     short sage_common
; ---------------------------------------------------------------------------

sage_normal:
                call    sub_A05A
                mov     word_BB12, 717h
                call    sub_A990
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                call    sub_AC07
                mov     ds:dialog_string_ptr, si

sage_common:
                call    word ptr cs:render_menu_dialog_proc ; al = dialog result
                cmp     al, 0FFh ; Go outside
                je      short loc_A055
                call    on_dialog_result
                jmp     short sage_common
; ---------------------------------------------------------------------------

loc_A055:
                jmp     word ptr cs:Fade_To_Black_Dithered_proc
sage_resurrect  endp


; =============== S U B R O U T I N E =======================================


sub_A05A        proc near
                mov     es, word ptr ds:seg1
                mov     di, 8000h
                mov     si, offset vfs_kenjya_grp
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                push    ds
                mov     ds, word ptr cs:seg1
                mov     si, 8000h
                mov     cx, 100h
                call    word ptr cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                pop     ds
                mov     byte ptr ds:dialog_cursor_x, 0
                mov     byte ptr ds:dialog_scroll_counter, 0
                call    word ptr cs:Clear_Viewport_proc
                call    word ptr cs:Clear_Place_Enemy_Bar_proc
                mov     bl, ds:town_id
                dec     bl
                xor     bh, bh
                add     bx, bx
                mov     si, sage_names[bx]
                jmp     word ptr cs:Render_Pascal_String_1_proc
sub_A05A        endp


; =============== S U B R O U T I N E =======================================


on_dialog_result        proc near

                mov     bl, al
                xor     bh, bh
                add     bx, bx          ; switch 14 cases
                jmp     cs:jpt_A0AA[bx] ; switch jump
on_dialog_result        endp

; ---------------------------------------------------------------------------
jpt_A0AA        dw offset loc_A0CB ; on_0
                dw offset loc_A18E
                dw offset sub_A914
                dw offset loc_A862
                dw offset sub_A410
                dw offset level_up ; on_5=level_up
                dw offset loc_A420
                dw offset sub_A93B
                dw offset loc_A93F
                dw offset loc_A943
                dw offset loc_A947
                dw offset loc_A94B
                dw offset loc_A94F
                dw offset loc_A953
; ---------------------------------------------------------------------------

loc_A0CB:
                call    sub_A983
                mov     bx, 2722h
                mov     cx, 1C2Dh
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 2725h
                mov     byte ptr ds:menu_item_count, 4
                mov     byte ptr ds:menu_max_items, 4
                mov     cx, 4           ; number of menu items
                mov     si, offset aGoOutside ; "Go outside"
                call    word ptr cs:render_menu_string_list_proc
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     bl, menu_item_selected
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A108
                xor     bl, bl

loc_A108:
                mov     menu_item_selected, bl
                xor     bh, bh
                add     bx, bx          ; switch 4 cases
                jmp     jpt_A110[bx]    ; switch jump
; ---------------------------------------------------------------------------
jpt_A110        dw offset on_go_outside ; jump table for switch statement
                dw offset on_see_power
                dw offset on_listen_knowledge
                dw offset on_record_experience

; =============== S U B R O U T I N E =======================================

on_go_outside   proc near
                call    sub_A983
                mov     word ptr ds:dialog_string_ptr, offset byte_ADEB
                retn
on_go_outside   endp


; =============== S U B R O U T I N E =======================================

on_see_power    proc near
                call    sub_A983
                test    byte_BB15, 0FFh
                jnz     short loc_A137
                mov     word ptr ds:dialog_string_ptr, offset byte_AE08
                retn
; ---------------------------------------------------------------------------

loc_A137:
                test    byte_BB16, 0FFh
                jnz     short loc_A150
                mov     di, offset byte_AEA7
                test    byte_BB17, 0FFh
                jz      short loc_A14B
                mov     di, offset byte_AF03
                ; I can no longer impart the power
loc_A14B:
                mov     ds:dialog_string_ptr, di
                retn
; ---------------------------------------------------------------------------

loc_A150:       ; spirits are no longer with you
                mov     word ptr ds:dialog_string_ptr, offset byte_AE42
                retn
on_see_power    endp


; =============== S U B R O U T I N E =======================================

on_listen_knowledge proc near
                call    sub_A983
                mov     bl, ds:town_id
                dec     bl
                xor     bh, bh
                add     bx, bx
                mov     si, off_B5EB[bx]
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset byte_ADBF
                retn
on_listen_knowledge endp

; ---------------------------------------------------------------------------

on_record_experience:
                call    sub_A983
                call    sub_A427
                mov     word ptr ds:dialog_string_ptr, offset byte_ADBF
                jnb     short loc_A187
                retn
; ---------------------------------------------------------------------------

loc_A187:
                mov     word ptr ds:dialog_string_ptr, offset byte_AF7C
                retn
; ---------------------------------------------------------------------------

loc_A18E:
                mov     byte_BB15, 0FFh
                call    sub_A1D1
                call    sub_A410
                mov     byte_BB18, 0FFh
                mov     byte_BB19, 0FFh
                mov     word ptr ds:dialog_string_ptr, offset unk_AFDE

loc_A1A9:
                call    sub_A410
                call    word ptr cs:render_menu_dialog_proc
                cmp     al, 4
                jz      short loc_A1A9
                mov     byte_BB1A, 0FFh
                call    sub_A200
                call    word ptr cs:render_menu_dialog_proc
                call    checkLevelUp
                add     ax, ax
                mov     bx, ax
                mov     ax, dialog_by_levelup_check[bx]
                mov     ds:dialog_string_ptr, ax
                retn

; =============== S U B R O U T I N E =======================================


sub_A1D1        proc near
                mov     si, offset byte_A1FD
                mov     byte_BB19, 0FFh
                mov     byte_BB1B, 0FFh
                mov     cx, 3

loc_A1E1:
                push    cx
                mov     byte ptr ds:frame_timer, 0
                lodsb
                push    si
                call    sub_AA16

loc_A1EC:
                cmp     byte ptr ds:frame_timer, 25
                jb      short loc_A1EC
                pop     si
                pop     cx
                loop    loc_A1E1
                mov     byte_BB19, 0
                retn
sub_A1D1        endp

; ---------------------------------------------------------------------------
byte_A1FD       db 0
byte_A1FE       db 1
                db 2

; =============== S U B R O U T I N E =======================================


sub_A200        proc near
                mov     si, offset byte_A1FE
                mov     byte_BB19, 0FFh
                mov     cx, 2

loc_A20B:
                push    cx
                mov     byte ptr ds:frame_timer, 0
                mov     al, [si]
                dec     si
                push    si
                call    sub_AA16

loc_A218:
                cmp     byte ptr ds:frame_timer, 25
                jb      short loc_A218
                pop     si
                pop     cx
                loop    loc_A20B
                mov     byte_BB19, 0
                mov     byte_BB1B, 0
                retn
sub_A200        endp


; =============== S U B R O U T I N E =======================================

; Returns:
;   0: xp < threshold/2
;   1: xp < 3*threshold/4
;   2: xp < threshold
;   3: xp >= threshold, hero_level < sage_max_level_up
;   4: hero_level >= sage_max_level_up
checkLevelUp    proc near
                xor     bx, bx
                mov     bl, ds:hero_level
                cmp     bl, 15
                jb      short loc_A23B
                mov     bl, 15

loc_A23B:
                add     bx, bx
                add     bx, offset xp_threshold_per_level
                mov     dx, [bx] ; threshold for level-up; =50
                mov     cx, dx
                xor     ax, ax
                shr     cx, 1 ; threshold/2
                cmp     ds:hero_xp, cx
                jnb     short loc_A250
                retn ; xp < threshold/2, result 0
; ---------------------------------------------------------------------------

loc_A250:
                mov     ax, dx ; threshold
                shr     cx, 1 ; threshold/4
                sub     ax, cx ; 3*threshold/4
                mov     cx, ax
                mov     ax, 1
                cmp     ds:hero_xp, cx
                jnb     short loc_A262
                retn ; xp < 3*threshold/4, result 1
; ---------------------------------------------------------------------------

loc_A262:
                mov     ax, 2
                cmp     ds:hero_xp, dx
                jnb     short loc_A26C
                retn ; xp < threshold, result 2
; ---------------------------------------------------------------------------

loc_A26C:       ; xp >= threshold, result 3
                xor     bx, bx
                mov     bl, ds:town_id
                dec     bx
                add     bx, offset sage_max_level_up
                mov     ax, 3
                mov     cl, ds:hero_level
                cmp     cl, [bx]
                jnb     short loc_A283
                retn    ; hero_level < sage_max_level_up, result 3
; ---------------------------------------------------------------------------

loc_A283:
                mov     byte_BB17, 0FFh
                mov     ax, 4
                retn    ; hero_level >= sage_max_level_up, result 4
checkLevelUp    endp

; ---------------------------------------------------------------------------
xp_threshold_per_level  dw 50, 150, 300, 420, 1000, 1500, 3000, 5000, 6000
                        dw 8000, 10000, 15000, 20000, 40000, 50000, 60000
sage_max_level_up       db 3, 6, 9, 11, 13, 15, 18, 0FFh

; =============== S U B R O U T I N E =======================================


level_up        proc near
                mov     byte_BB16, 0FFh
                mov     cx, 8
                ; flash screen 8 times
loc_A2BC:
                push    cx
                call    word ptr cs:apply_screen_xor_grid_proc
                mov     byte ptr ds:frame_timer, 0
loc_A2C7:       ; delay 10 frames
                cmp     byte ptr ds:frame_timer, 10
                jb      short loc_A2C7
                pop     cx
                loop    loc_A2BC
                push    cs
                pop     es
                mov     al, ds:hero_level
                cmp     al, 16
                jb      short loc_A2F5
                mov     max_hp, 800  ; max possible HP
                mov     cx, 7
                mov     si, espada_count
                mov     di, offset spells_cap
loc_A2E9:       ; max all spells capacity
                lodsb
                add     al, 2
                jnb     short loc_A2F0
                mov     al, 0FFh
loc_A2F0:
                stosb
                loop    loc_A2E9
                jmp     short loc_A306
; ---------------------------------------------------------------------------

loc_A2F5:       ; update max HP and spells cap
                mov     bl, 9
                mul     bl
                mov     si, offset stats_per_level
                add     si, ax
                mov     di, offset max_hp
                mov     cx, 9
                rep movsb

loc_A306:
                mov     al, ds:hero_level
                inc     al
                jnz     short loc_A30F
                mov     al, 0FFh

loc_A30F:
                mov     ds:hero_level, al
                mov     ax, max_hp
                mov     ds:heroMaxHp, ax
                mov     ds:hero_HP, ax
                call    word ptr cs:Draw_Hero_Max_Health_proc
                call    word ptr cs:Draw_Hero_Health_proc
                push    cs
                pop     es
                mov     di, espada_count
                mov     si, offset spells_cap
                mov     cx, 7
                rep movsb
                mov     di, spells_espada
                mov     si, offset spells_cap
                mov     cx, 7
                rep movsb
                test    byte ptr ds:current_magic_spell, 0FFh
                jz      short loc_A349
                call    word ptr cs:Print_Magic_Left_Decimal_proc

loc_A349:
                xor     bx, bx
                mov     bl, ds:hero_level
                dec     bl
                cmp     bl, 15
                jb      short loc_A358
                mov     bl, 15

loc_A358:
                add     bx, bx
                mov     ax, xp_threshold_per_level[bx]
                sub     ds:hero_xp, ax
                xor     bx, bx
                mov     bl, ds:hero_level
                cmp     bl, 15
                jb      short loc_A36F
                mov     bl, 15

loc_A36F:
                add     bx, bx
                mov     ax, xp_threshold_per_level[bx]
                cmp     ds:hero_xp, ax
                jb      short locret_A37F
                dec     ax ; no second level-up
                mov     ds:hero_xp, ax

locret_A37F:
                retn
level_up        endp

; ---------------------------------------------------------------------------
;                   max_hp  esp sae fue lan ras agu gue
stats_per_level db  78h, 0, 12,  6,  8,  8,  3,  4,  3 ; max_hp=120
                db 0A0h, 0, 12,  6,  8,  8,  3,  4,  3 ; max_hp=160
                db 0C8h, 0, 12,  6,  8,  8,  3,  4,  3 ; max_hp=200
                db 0F0h, 0, 12,  6,  8,  8,  3,  4,  3 ; max_hp=240
                db  18h, 1, 16,  6,  8,  8,  3,  4,  3 ; max_hp=280
                db  40h, 1, 20,  6,  8,  8,  3,  4,  3 ; max_hp=320
                db  7Ch, 1, 24,  6,  8,  8,  3,  4,  3 ; max_hp=380
                db 0CCh, 1, 28, 12,  8,  8,  3,  4,  3 ; max_hp=460
                db  1Ch, 2, 32, 18, 12,  8,  3,  4,  3 ; max_hp=640
                db  58h, 2, 36, 24, 16,  8,  3,  4,  3 ; max_hp=600
                db  80h, 2, 40, 30, 20, 16,  3,  4,  3 ; max_hp=640
                db 0A8h, 2, 44, 36, 24, 24,  3,  4,  3 ; max_hp=680
                db 0D0h, 2, 48, 42, 28, 32,  3,  4,  3 ; max_hp=720
                db 0F8h, 2, 52, 48, 36, 48,  9,  8,  6 ; max_hp=760
                db  0Ch, 3, 56, 54, 44, 54, 15, 12,  9 ; max_hp=780
                db  20h, 3, 60, 60, 60, 72, 21, 16, 12 ; max_hp=800

; =============== S U B R O U T I N E =======================================


sub_A410        proc near
                mov     byte ptr ds:frame_timer, 0

loc_A415:
                call    sub_AB47
                cmp     byte ptr ds:frame_timer, 140
                jb      short loc_A415
                retn
sub_A410        endp

; ---------------------------------------------------------------------------

loc_A420:
                mov     word ptr ds:dialog_string_ptr, offset byte_ADBF
                retn

; =============== S U B R O U T I N E =======================================


sub_A427        proc near
                push    cs
                pop     es
                mov     si, offset vfs_stdply_bin
                mov     al, 6  ; fn6_get_virtual_file_size (dword at 0f64)
                call    word ptr cs:res_dispatcher_proc
                mov     ax, cs
                mov     es, ax
                mov     ds, ax
                mov     di, 0E000h
                mov     dx, 0A516h
                call    word ptr cs:Scan_Saved_Games_proc
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     bx, 0D60h
                mov     cx, 2637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                push    cs
                pop     es
                mov     di, offset byte_BB27
                mov     al, 60h
                mov     cx, 8
                rep stosb
                mov     al, 0FFh
                stosb
                mov     ds:byte_BB25, 0
                mov     si, save_name
                mov     di, offset byte_BB27
                mov     cx, 8

loc_A47B:
                lodsb
                or      al, al
                jz      short loc_A487
                inc     ds:byte_BB25
                stosb
                loop    loc_A47B

loc_A487:
                mov     al, ds:byte_BB25
                mov     ds:byte_BB26, al
                mov     bx, 3Ch
                mov     cl, 6Ch
                mov     si, offset aInputName
                call    word ptr cs:Render_String_FF_Terminated_proc
                mov     ds:word_BB21, 60h
                mov     ds:byte_BB23, 7Eh
                mov     word ptr ds:menu_base_addr, 3463h
                mov     word ptr ds:string_width_bytes, 0Ah
                mov     al, ds:0E000h
                cmp     al, 5
                jb      short loc_A4BA
                mov     al, 5

loc_A4BA:
                xor     ah, ah
                mov     cx, ax
                xor     al, al
                mov     si, 0E001h
                jcxz    short loc_A4C8
                call    sub_A528

loc_A4C8:
                mov     si, 0E001h
                mov     al, ds:0E000h
                mov     ds:menu_max_items, al
                mov     byte ptr ds:menu_item_count, 5
                call    sub_A559
                pushf
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                popf
                jnb     short loc_A4EB
                retn
; ---------------------------------------------------------------------------

loc_A4EB:
                push    cs
                pop     es
                mov     di, save_name
                mov     cx, 8
                xor     al, al
                rep stosb
                cmp     ds:byte_BB26, 0
                stc
                jnz     short loc_A500
                retn
; ---------------------------------------------------------------------------

loc_A500:
                mov     si, offset byte_BB27
                mov     di, save_name

loc_A506:
                lodsb
                cmp     al, 0FFh
                clc
                jnz     short loc_A50D
                retn
; ---------------------------------------------------------------------------

loc_A50D:
                cmp     al, 60h ; '`'
                clc
                jnz     short loc_A513
                retn
; ---------------------------------------------------------------------------

loc_A513:
                stosb
                jmp     short loc_A506
sub_A427        endp

; ---------------------------------------------------------------------------
aUsr            db '*.usr',0
aInputName      db 'Input name:'
                db 0FFh

; =============== S U B R O U T I N E =======================================


sub_A528        proc near
                xor     ah, ah

loc_A52A:
                push    cx
                push    si
                push    ax
                call    word ptr cs:format_string_to_buffer_proc
                pop     ax
                push    ax
                mov     al, ah
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                add     ax, ax
                add     ax, ax
                add     bx, ax
                add     bx, ds:menu_base_addr
                add     bx, 300h
                call    word ptr cs:draw_string_buffer_to_screen_proc
                pop     ax
                inc     al
                inc     ah
                pop     si
                pop     cx
                loop    loc_A52A
                retn
sub_A528        endp


; =============== S U B R O U T I N E =======================================


sub_A559        proc near

                mov     byte ptr ds:keyboard_alt_mode_flag, 0FFh
                mov     byte ptr ds:Current_ASCII_Char, 0
                mov     byte ptr ds:Current_ASCII_Char, 0
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     ds:byte_BB24, 0
                xor     bl, bl
                test    byte ptr ds:menu_max_items, 0FFh
                jz      short loc_A58A
                call    word ptr cs:houseCursorShow_proc

loc_A58A:
                call    sub_A7FD
                xor     al, al
                call    sub_A790

loc_A592:
                call    word ptr cs:npcAnimation_proc
                mov     byte ptr ds:frame_timer, 0
                test    byte ptr ds:altkey_latch, 0FFh
                stc
                jnz     short loc_A5AE
                test    word ptr cs:F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter, 1
                jz      short loc_A5B9
                ; Enter pressed
                clc

loc_A5AE:
                mov     byte ptr ds:keyboard_alt_mode_flag, 0
                mov     byte ptr ds:altkey_latch, 0
                retn
; ---------------------------------------------------------------------------

loc_A5B9:
                test    byte ptr ds:spacebar_latch, 0FFh
                jz      short loc_A623
                ; Space pressed
                push    si
                xor     bh, bh
                mov     bl, ds:menu_cursor_pos
                add     bl, ds:byte_BB24
                add     bx, bx
                mov     si, [bx+si]
                push    cs
                pop     es
                mov     di, offset byte_BB27
                mov     al, 60h
                mov     cx, 8
                rep stosb
                mov     al, 0FFh
                stosb
                mov     ds:byte_BB25, 0
                mov     di, offset byte_BB27
                mov     cx, 8

loc_A5E9:
                lodsb
                or      al, al
                jz      short loc_A5F5
                inc     ds:byte_BB25
                stosb
                loop    loc_A5E9

loc_A5F5:
                mov     al, ds:byte_BB25
                mov     ds:byte_BB26, al
                pop     si
                mov     byte ptr ds:spacebar_latch, 0
                mov     ax, ds:word_BB21
                shr     ax, 1
                shr     ax, 1
                mov     bh, al
                mov     bl, ds:byte_BB23
                mov     cx, 1010h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                call    sub_A7FD
                xor     al, al
                call    sub_A790
                jmp     loc_A592
; ---------------------------------------------------------------------------

loc_A623:
                mov     cx, offset loc_A592
                push    cx
                test    byte ptr ds:Current_ASCII_Char, 0FFh
                jz      short loc_A65F
                mov     al, ds:Current_ASCII_Char
                mov     byte ptr ds:Current_ASCII_Char, 0
                cmp     al, 0Dh
                jnz     short loc_A63B
                retn
; ---------------------------------------------------------------------------

loc_A63B:
                cmp     al, 8
                jnz     short loc_A642
                jmp     loc_A827
; ---------------------------------------------------------------------------

loc_A642:
                xor     bx, bx
                mov     bl, ds:byte_BB25
                cmp     ds:byte_BB27[bx], 60h
                jnz     short loc_A653
                inc     ds:byte_BB26

loc_A653:
                mov     ds:byte_BB27[bx], al
                call    sub_A7FD
                mov     al, 1
                jmp     sub_A790
; ---------------------------------------------------------------------------

loc_A65F:
                int     61h             ; check input keys buffer
                                        ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 8
                jz      short loc_A676
                ; Right pressed
                mov     al, 1
                call    sub_A790

wait_for_right_released:
                int     61h             ; check input keys buffer
                                        ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 8
                jnz     short wait_for_right_released
                mov     byte ptr ds:Current_ASCII_Char, 0
                retn
; ---------------------------------------------------------------------------

loc_A676:
                test    al, 4
                jz      short loc_A68B
                ; Left pressed
                mov     al, 0FFh
                call    sub_A790

wait_for_left_released:
                int     61h             ; check input keys buffer
                                        ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 4
                jnz     short wait_for_left_released
                mov     byte ptr ds:Current_ASCII_Char, 0
                retn
; ---------------------------------------------------------------------------

loc_A68B:
                test    byte ptr ds:menu_max_items, 0FFh
                jnz     short loc_A693
                retn
; ---------------------------------------------------------------------------

loc_A693:
                and     al, 3
                cmp     al, 1
                jnz     short loc_A709
                test    ds:byte_BB24, 0FFh
                jz      short loc_A6AE
                mov     bl, ds:byte_BB24
                call    word ptr cs:houseCursorUp_proc
                dec     ds:byte_BB24
                retn
; ---------------------------------------------------------------------------

loc_A6AE:
                test    byte ptr ds:menu_cursor_pos, 0FFh
                jnz     short loc_A6B6
                retn
; ---------------------------------------------------------------------------

loc_A6B6:
                push    di
                push    si
                dec     byte ptr ds:menu_cursor_pos
                mov     al, ds:menu_cursor_pos
                add     al, ds:byte_BB24
                call    word ptr cs:format_string_to_buffer_proc
                mov     cx, 0Ah

loc_A6CB:
                push    cx
                mov     bx, ds:menu_base_addr
                add     bx, 301h
                mov     al, cl
                dec     al
                mov     cl, ds:menu_item_count
                add     cl, cl
                mov     dl, cl
                add     cl, cl
                add     cl, cl
                add     cl, dl
                sub     cl, 2
                mov     ch, ds:string_width_bytes
                call    word ptr cs:scroll_hud_up_proc

loc_A6F2:
                call    word ptr cs:npcAnimation_proc
                cmp     byte ptr ds:frame_timer, 4
                jb      short loc_A6F2
                mov     byte ptr ds:frame_timer, 0
                pop     cx
                loop    loc_A6CB
                pop     si
                pop     di
                retn
; ---------------------------------------------------------------------------

loc_A709:
                cmp     al, 2
                jz      short loc_A70E
                retn
; ---------------------------------------------------------------------------

loc_A70E:
                mov     al, ds:byte_BB24
                add     al, ds:menu_cursor_pos
                inc     al
                mov     ah, ds:menu_max_items
                dec     ah
                cmp     ah, al
                jnb     short loc_A722
                retn
; ---------------------------------------------------------------------------

loc_A722:
                mov     al, ds:menu_item_count
                dec     al
                cmp     ds:byte_BB24, al
                jnb     short loc_A73B
                mov     bl, ds:byte_BB24
                call    word ptr cs:houseCursorDown_proc
                inc     ds:byte_BB24
                retn
; ---------------------------------------------------------------------------

loc_A73B:
                push    di
                push    si
                inc     byte ptr ds:menu_cursor_pos
                mov     al, ds:menu_cursor_pos
                add     al, ds:byte_BB24
                call    word ptr cs:format_string_to_buffer_proc
                mov     cx, 0Ah

loc_A750:
                push    cx
                mov     bx, ds:menu_base_addr
                add     bx, 301h
                mov     al, cl
                neg     al
                add     al, 0Ah
                mov     cl, ds:menu_item_count
                add     cl, cl
                mov     dl, cl
                add     cl, cl
                add     cl, cl
                add     cl, dl
                sub     cl, 2
                mov     ch, ds:string_width_bytes
                call    word ptr cs:scroll_hud_down_proc

loc_A779:                               ;
                call    word ptr cs:npcAnimation_proc
                cmp     byte ptr ds:frame_timer, 4
                jb      short loc_A779
                mov     byte ptr ds:frame_timer, 0
                pop     cx
                loop    loc_A750
                pop     si
                pop     di
                retn
sub_A559        endp


; =============== S U B R O U T I N E =======================================


sub_A790        proc near
                push    si
                push    ax
                mov     ax, ds:word_BB21
                shr     ax, 1
                shr     ax, 1
                mov     bh, al
                mov     al, ds:byte_BB25
                add     al, al
                add     bh, al
                mov     bl, ds:byte_BB23
                add     bl, 8
                mov     cx, 208h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                pop     ax
                add     ds:byte_BB25, al
                test    ds:byte_BB25, 80h
                jz      short loc_A7C4
                mov     ds:byte_BB25, 0

loc_A7C4:
                cmp     ds:byte_BB25, 8
                jb      short loc_A7CF
                dec     ds:byte_BB25

loc_A7CF:
                mov     al, ds:byte_BB26
                cmp     ds:byte_BB25, al
                jb      short loc_A7DB
                mov     ds:byte_BB25, al

loc_A7DB:
                mov     bx, ds:word_BB21
                mov     cl, ds:byte_BB23
                xor     ax, ax
                mov     al, ds:byte_BB25
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     bx, ax
                add     cl, 8
                mov     ax, 67Fh
                call    word ptr cs:Render_Font_Glyph_proc
                pop     si
                retn
sub_A790        endp


; =============== S U B R O U T I N E =======================================


sub_A7FD        proc near
                push    si
                mov     ax, ds:word_BB21
                shr     ax, 1
                shr     ax, 1
                mov     bh, al
                mov     bl, ds:byte_BB23
                mov     cx, 1008h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     bx, ds:word_BB21
                mov     cl, ds:byte_BB23
                mov     si, offset byte_BB27
                call    word ptr cs:Render_String_FF_Terminated_proc
                pop     si
                retn
sub_A7FD        endp

; ---------------------------------------------------------------------------

loc_A827:
                push    si
                mov     bl, ds:byte_BB25
                or      bl, bl
                jnz     short loc_A832
                inc     bl

loc_A832:
                xor     bh, bh
                push    cs
                pop     es
                mov     si, offset byte_BB27
                add     si, bx
                mov     di, si
                dec     di
                mov     al, 8
                sub     al, bl
                mov     cl, al
                xor     ch, ch
                rep movsb
                test    ds:byte_BB26, 0FFh
                jz      short loc_A853
                dec     ds:byte_BB26

loc_A853:
                mov     ds:byte_BB2E, 60h
                mov     al, 0FFh
                call    sub_A790
                call    sub_A7FD
                pop     si
                retn
; ---------------------------------------------------------------------------

loc_A862:
                push    cs
                pop     es
                mov     si, save_name
                mov     di, offset byte_BB27
                mov     cx, 8

loc_A86D:
                lodsb
                or      al, al
                jz      short loc_A875
                stosb
                loop    loc_A86D

loc_A875:
                mov     byte ptr es:[di], '.'
                mov     byte ptr es:[di+1], 'u'
                mov     byte ptr es:[di+2], 's'
                mov     byte ptr es:[di+3], 'r'
                mov     byte ptr es:[di+4], 0
                mov     dx, offset byte_BB27
                mov     cx, 0
                mov     ah, 3Ch
                int     21h             ; DOS - 2+ - CREATE A FILE WITH HANDLE (CREAT)
                                        ; CX = attributes for file
                                        ; DS:DX -> ASCIZ filename (may include drive and path)
                jb      short loc_A8B2
                push    ax
                mov     dx, 0
                mov     cx, 100h
                mov     bx, ax
                mov     ah, 40h
                int     21h             ; DOS - 2+ - WRITE TO FILE WITH HANDLE
                                        ; BX = file handle, CX = number of bytes to write, DS:DX -> buffer
                pop     ax
                pushf
                mov     bx, ax
                mov     ah, 3Eh
                int     21h             ; DOS - 2+ - CLOSE A FILE WITH HANDLE
                                        ; BX = file handle
                popf
                jb      short loc_A8B2
                retn
; ---------------------------------------------------------------------------

loc_A8B2:
                mov     ax, 849h
                mov     cx, 1926h
                xor     di, di
                call    word ptr cs:Capture_Screen_Rect_to_seg3_proc
                mov     bx, 1049h
                mov     cx, 3226h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     bx, 4Ch
                mov     cl, 50h
                mov     si, offset aDiskErrorPleas
                call    word ptr cs:Render_String_FF_Terminated_proc
                mov     byte ptr ds:spacebar_latch, 0

loc_A8DE:
                test    byte ptr ds:spacebar_latch, 0FFh
                jz      short loc_A8DE
                mov     byte ptr ds:spacebar_latch, 0
                mov     ax, 849h
                mov     cx, 1926h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                jmp     on_record_experience
; ---------------------------------------------------------------------------
vfs_stdply_bin  db    0
                db    0
aStdplyBin      db 'STDPLY.BIN',0

; =============== S U B R O U T I N E =======================================


sub_A914        proc near
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                pushf
                call    sub_A983
                popf
                jb      short loc_A934
                retn
; ---------------------------------------------------------------------------

loc_A934:
                xor     ax, ax
                jmp     dword ptr cs:fn_exit_far_ptr
sub_A914        endp


; =============== S U B R O U T I N E =======================================


sub_A93B        proc near
                mov     al, 1
                jmp     short loc_A957
; ---------------------------------------------------------------------------

loc_A93F:
                mov     al, 2
                jmp     short loc_A957
; ---------------------------------------------------------------------------

loc_A943:
                mov     al, 3
                jmp     short loc_A957
; ---------------------------------------------------------------------------

loc_A947:
                mov     al, 4
                jmp     short loc_A957
; ---------------------------------------------------------------------------

loc_A94B:
                mov     al, 5
                jmp     short loc_A957
; ---------------------------------------------------------------------------

loc_A94F:
                mov     al, 6
                jmp     short loc_A957
; ---------------------------------------------------------------------------

loc_A953:
                mov     al, 7
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_A957:
                push    ax
                mov     bx, 0AA1Ch
                xor     al, al
                mov     ch, 17h
                call    word ptr cs:Clear_HUD_Bar_proc
                pop     ax
                mov     ds:current_magic_spell, al
                mov     bl, al
                dec     bl
                xor     bh, bh
                mov     byte ptr espada_active[bx], 0FFh
                mov     al, ds:current_magic_spell
                mov     bx, 37A4h
                call    word ptr cs:Render_Magic_Spell_Item_Sprite_16x16_proc
                jmp     word ptr cs:Print_Magic_Left_Decimal_proc
sub_A93B        endp


; =============== S U B R O U T I N E =======================================


sub_A983        proc near
                mov     bx, 2717h
                mov     cx, 1D41h
                xor     al, al
                jmp     word ptr cs:Draw_Bordered_Rectangle_proc
sub_A983        endp


; =============== S U B R O U T I N E =======================================


sub_A990        proc near
                mov     si, offset byte_A9B6
                mov     bx, ds:word_BB12
                mov     cx, 8

loc_A99A:
                push    cx
                mov     cx, 12

loc_A99E:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A99E
                sub     bh, 0Ch
                add     bl, 8
                pop     cx
                loop    loc_A99A
                retn
sub_A990        endp

; ---------------------------------------------------------------------------
byte_A9B6       db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0Ah, 0Bh
                db 0Ch, 0Dh, 0Eh, 0Fh, 10h, 11h, 12h, 13h, 14h, 15h, 16h, 17h
                db 18h, 19h, 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 1Bh, 20h, 21h, 22h
                db 23h, 24h, 25h, 1Bh, 26h, 27h, 28h, 29h, 1Bh, 2Bh, 2Ch, 2Dh
                db 2Eh, 2Fh, 30h, 31h, 32h, 33h, 34h, 35h, 36h, 37h, 38h, 39h
                db 3Ah, 3Bh, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h, 44h, 45h
                db 46h, 47h, 48h, 49h, 4Ah, 4Bh, 4Ch, 4Dh, 4Eh, 4Fh, 50h, 51h
                db 52h, 53h, 54h, 55h, 56h, 57h, 58h, 59h, 5Ah, 5Bh, 5Ch, 5Dh

; =============== S U B R O U T I N E =======================================


sub_AA16        proc near
                mov     cl, 32
                mul     cl
                mov     bx, ds:word_BB12
                add     bx, 210h
                mov     si, ax
                add     si, offset byte_AA47
                mov     cx, 4

loc_AA2B:
                push    cx
                mov     cx, 8

loc_AA2F:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_AA2F
                sub     bh, 8
                add     bl, 8
                pop     cx
                loop    loc_AA2B
                retn
sub_AA16        endp

; ---------------------------------------------------------------------------
byte_AA47       db 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 1Bh, 20h, 25h, 1Bh, 26h, 27h, 28h, 29h, 1Bh, 2Bh
                db 30h, 31h, 32h, 33h, 34h, 35h, 36h, 37h, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h
                db 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 1Bh, 20h, 25h, 1Bh, 71h, 27h, 28h, 74h, 1Bh, 2Bh
                db 30h, 31h, 75h, 33h, 34h, 76h, 36h, 37h, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h
                db 5Eh, 5Fh, 1Ch, 1Dh, 1Eh, 1Fh, 60h, 61h, 62h, 63h, 64h, 65h, 66h, 67h, 69h, 6Ah
                db 30h, 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 70h, 37h, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h
                db 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 77h, 78h, 20h, 25h, 1Bh, 79h, 65h, 7Ah, 72h, 73h, 2Bh
                db 30h, 7Bh, 7Ch, 7Dh, 7Eh, 7Fh, 36h, 37h, 3Ch, 80h, 81h, 3Fh, 40h, 41h, 42h, 43h
                db 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 1Bh, 20h, 25h, 82h, 83h, 65h, 7Ah, 84h, 85h, 2Bh
                db 30h, 86h, 87h, 7Dh, 88h, 89h, 36h, 37h, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h
                db 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 1Bh, 20h, 25h, 8Ah, 8Bh, 65h, 66h, 8Ch, 8Dh, 2Bh
                db 30h, 8Eh, 8Fh, 7Dh, 90h, 91h, 92h, 37h, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h
                db 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 1Bh, 20h, 25h, 93h, 94h, 65h, 95h, 96h, 97h, 2Bh
                db 30h, 31h, 98h, 7Dh, 88h, 99h, 9Ah, 37h, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h
                db 1Ah, 9Bh, 9Ch, 1Dh, 1Eh, 1Fh, 1Bh, 20h, 25h, 9Dh, 9Eh, 65h, 95h, 9Fh, 1Bh, 2Bh
                db 30h, 0A0h, 0A1h, 7Dh, 6Eh, 0A2h, 0A3h, 37h, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 0A4h, 0A5h, 43h

; =============== S U B R O U T I N E =======================================


sub_AB47        proc near
                cmp     word ptr ds:tick_counter, 2
                jnb     short loc_AB4F
                retn
; ---------------------------------------------------------------------------

loc_AB4F:
                mov     word ptr ds:tick_counter, 0
                test    ds:byte_BB18, 0FFh
                jz      short loc_ABB9
                test    ds:byte_BB1A, 0FFh
                jz      short loc_AB89
                inc     ds:byte_BB1C
                and     ds:byte_BB1C, 0Fh
                cmp     ds:byte_BB1C, 1
                jnz     short loc_ABB9
                mov     ds:byte_BB18, 0
                mov     ds:byte_BB1A, 0
                mov     ds:byte_BB1C, 0
                mov     ds:byte_BB1D, 0
                jmp     short loc_ABB9
; ---------------------------------------------------------------------------

loc_AB89:
                inc     ds:byte_BB20
                cmp     ds:byte_BB20, 20
                jnb     short loc_AB95
                retn
; ---------------------------------------------------------------------------

loc_AB95:
                mov     ds:byte_BB20, 0
                inc     ds:byte_BB1D
                mov     bl, ds:byte_BB1D
                dec     bl
                and     bl, 7
                xor     bh, bh
                mov     al, ds:byte_ABFF[bx]
                call    sub_AA16
                inc     ds:byte_BB1C
                and     ds:byte_BB1C, 0Fh

loc_ABB9:
                test    ds:byte_BB19, 0FFh
                jz      short loc_ABC1
                retn
; ---------------------------------------------------------------------------

loc_ABC1:
                inc     ds:byte_BB1F
                cmp     ds:byte_BB1F, 20
                jnb     short loc_ABCD
                retn
; ---------------------------------------------------------------------------

loc_ABCD:
                mov     ds:byte_BB1F, 0
                mov     bl, ds:byte_BB1E
                not     ds:byte_BB1E
                and     bl, 1
                xor     bh, bh
                mov     di, offset byte_ABFB
                test    ds:byte_BB1B, 0FFh
                jz      short loc_ABEC
                mov     di, offset byte_ABFD

loc_ABEC:
                mov     al, [bx+di]
                mov     bx, ds:word_BB12
                add     bx, 718h
                jmp     word ptr cs:draw_tile_to_screen_proc
sub_AB47        endp

; ---------------------------------------------------------------------------
byte_ABFB       db 29h, 2Ah
byte_ABFD       db 67h, 68h
byte_ABFF       db 5, 6, 7, 6, 5, 4, 3, 4

; =============== S U B R O U T I N E =======================================


sub_AC07        proc near

                mov     si, offset byte_AD9D
                mov     bl, ds:town_id
                dec     bl
                xor     bh, bh
                add     bx, bx          ; switch 8 cases
                jmp     ds:jpt_AC14[bx] ; switch jump
sub_AC07        endp

; ---------------------------------------------------------------------------
jpt_AC14        dw offset loc_AC28
                dw offset loc_AC39
                dw offset loc_AC4A
                dw offset loc_AC5B
                dw offset loc_AC6C
                dw offset loc_AC7D
                dw offset loc_AC8E
                dw offset loc_AC9F
; ---------------------------------------------------------------------------

loc_AC28:
                test    byte ptr ds:sages_spoken_to_hero, 80h
                jz      short loc_AC30
                retn
; ---------------------------------------------------------------------------

loc_AC30:
                mov     si, offset aIAmTheSageMari
                or      byte ptr ds:sages_spoken_to_hero, 80h
                retn
; ---------------------------------------------------------------------------

loc_AC39:
                test    byte ptr ds:sages_spoken_to_hero, 40h
                jz      short loc_AC41
                retn
; ---------------------------------------------------------------------------

loc_AC41:
                mov     si, offset aIAmTheSageYasm
                or      byte ptr ds:sages_spoken_to_hero, 40h
                retn
; ---------------------------------------------------------------------------

loc_AC4A:
                test    byte ptr ds:sages_spoken_to_hero, 20h
                jz      short loc_AC52
                retn
; ---------------------------------------------------------------------------

loc_AC52:
                mov     si, offset aIAmTheSageHajj
                or      byte ptr ds:sages_spoken_to_hero, 20h
                retn
; ---------------------------------------------------------------------------

loc_AC5B:
                test    byte ptr ds:sages_spoken_to_hero, 10h
                jz      short loc_AC63
                retn
; ---------------------------------------------------------------------------

loc_AC63:
                mov     si, offset aIAmTheSageChir
                or      byte ptr ds:sages_spoken_to_hero, 10h
                retn
; ---------------------------------------------------------------------------

loc_AC6C:
                test    byte ptr ds:sages_spoken_to_hero, 8
                jz      short loc_AC74
                retn
; ---------------------------------------------------------------------------

loc_AC74:
                mov     si, offset aIAmTheSageHish
                or      byte ptr ds:sages_spoken_to_hero, 8
                retn
; ---------------------------------------------------------------------------

loc_AC7D:
                test    byte ptr ds:sages_spoken_to_hero, 4
                jz      short loc_AC85
                retn
; ---------------------------------------------------------------------------

loc_AC85:
                mov     si, offset aIAmTheSageMary
                or      byte ptr ds:sages_spoken_to_hero, 4
                retn
; ---------------------------------------------------------------------------

loc_AC8E:
                test    byte ptr ds:sages_spoken_to_hero, 2
                jz      short loc_AC96
                retn
; ---------------------------------------------------------------------------

loc_AC96:
                mov     si, offset aIAmTheSageSaie
                or      byte ptr ds:sages_spoken_to_hero, 2
                retn
; ---------------------------------------------------------------------------

loc_AC9F:
                test    byte ptr ds:sages_spoken_to_hero, 1
                jz      short loc_ACA7
                retn
; ---------------------------------------------------------------------------

loc_ACA7:
                mov     si, offset aIAmTheSageOfAl
                or      byte ptr ds:sages_spoken_to_hero, 1
                retn
; ---------------------------------------------------------------------------
vfs_kenjya_grp  db    1
                db  1Ah
aKenjyaGrp      db 'KENJYA.GRP',0
sage_names      dw offset byte_ACCD
                dw offset byte_ACDF
                dw offset byte_ACF2
                dw offset byte_AD05
                dw offset byte_AD19
                dw offset byte_AD2C
                dw offset byte_AD3F
                dw offset byte_AD51
byte_ACCD       db 16h
                db 0AFh
                db    0
aTheSageMarid   db 14,'The Sage Marid'
byte_ACDF       db 15h
                db 0AFh
                db    0
aTheSageYasmin  db 15,'The Sage Yasmin'
byte_ACF2       db 14h
                db 0AFh
                db    0
aTheSageHajjar  db 15,'The Sage Hajjar'
byte_AD05       db 14h
                db 0AFh
                db    2
aTheSageChiriga db 16,'The Sage Chiriga'
byte_AD19       db 14h
                db 0AFh
                db    0
aTheSageHisham  db 15,'The Sage Hisham'
byte_AD2C       db 14h
                db 0AFh
                db    0
aTheSageMaryam  db 15,'The Sage Maryam'
byte_AD3F       db 15h
                db 0AFh
                db    0
aTheSageSaied   db 14,'The Sage Saied'
byte_AD51       db 14h
                db 0AFh
                db    0
aTheSageIndihar db 16,'The Sage Indihar'
aGoOutside      db 'Go outside',0
aSeePower       db 'See Power',0
aListenKnowledg db 'Listen Knowledge',0
aRecordExperien db 'Record Experience',0
byte_AD9D       db 0Ch
aHowCanIHelpYou db 'How can I help you, Brave One?/'
                db 0FFh
                db    0
byte_ADBF       db 0Ch
aIsThereAnythin db 'Is there anything else I can do for you?/'
                db 0FFh
                db    0
byte_ADEB       db 0Ch
aTheSpiritsAreW db 'The Spirits are with you.'
                db  11h
                db 0FFh
                db 0FFh
byte_AE08       db 0Ch
aIShallCallUpon db 'I shall call upon the Spirits and their powers..... /'
                db 0FFh
                db    4
                db 0FFh
                db    1
byte_AE42       db 0Ch
aIFearTheSpirit db 'I fear the spirits are no longer with you. No matter how many times'
                db ' I try, it comes out the same. '
                db 0FFh
                db    0
byte_AEA7       db 0Ch
aYouAreBraveBut db 'You are brave, but your experience is lacking. Come back when you'
                db ' have accomplished more.'
                db 0FFh
                db    0
byte_AF03       db 0Ch
aICanNoLongerIm db 'I can no longer impart the power of the Spirits to you. Continue '
                db 'on your quest. You will soon find others to help you.'
                db 0FFh
                db    0
byte_AF7C       db 0Ch
aIShallRecordYo db 'I shall record your experiences./'
                db 0FFh
                db    3
aPlaceIsSavedOn db 'Place is saved on user disk. Will you continue your quest?'
                db 0FFh
                db    2
                db 0FFh
                db    6
unk_AFDE        db  13h
                db 0FFh
                db    4
aOhHolySpiritsP db 'Oh, Holy Spirits, purify my thoughts and grant me strength. '
                db 0FFh
                db    4
                db 0FFh
                db    4
                db  0Dh
                db  15h
                db 0FFh
                db    0
                db 0FFh
                db    0
                db 0FFh
                db 0FFh
dialog_by_levelup_check dw offset aYourExperience
                        dw offset aYouMustAccumul
                        dw offset aICanSeeTheFain
                        dw offset aTheLightOfTheS
                        dw offset aICanNoLongerIm_0
aYourExperience db 'Your experience is lacking. Persevere in your quest.'
                db 0FFh
                db    0 ; on_0
aYouMustAccumul db 'You must accumulate more experience.'
                db 0FFh
                db    0 ; on_0
aICanSeeTheFain db 'I can see the faint light of the Spirits in you. You must endure a little longer.'
                db 0FFh
                db    0 ; on_0
aTheLightOfTheS db 'The light of the Spirits is bursting forth within you. '
                db 0FFh
                db    4 ; on_4
                db  0Dh
aIndeedYourPowe db 'Indeed, your power has grown.'
                db 0FFh
                db    5 ; on_5
                db 0FFh
                db    4
                db 0FFh
                db    0
aICanNoLongerIm_0 db 'I can no longer impart the power of the Spirits to you. Continue '
                db 'on your quest. You will soon find others to help you. '
                db 0FFh
                db    0
aIAmTheSageMari db 'I am the Sage Marid./You are very brave to embark on such a dange'
                db 'rous journey. I&shall assist you in your travels. '
                db 0FFh
                db    0
aIAmTheSageYasm db 'I am the Sage Yasmin./I have been expecting you. I&shall teach yo'
                db 'u the Magic Spell of Throwing Swords: Espada.'
                db 0FFh
                db    7 ; on_7
                db 0FFh
                db    0
aIAmTheSageHajj db 'I am the Sage Hajjar./I am happy to see you\ve made it this far. '
                db 'I&shall teach you the Magic Spell of Arrows: Saeta.'
                db 0FFh
                db    8 ; on_8
                db 0FFh
                db    0
aIAmTheSageChir db 'I am the Sage Chiriga./You have come far, and you must be cold. I'
                db '&shall teach you the Magic Spell of Fire: Fuego.'
                db 0FFh
                db    9 ; on_9
                db 0FFh
                db    0
aIAmTheSageHish db 'I am the Sage Hisham./You are doing well to stand before me. I&sh'
                db 'all teach you the Magic Spell of Flame: Lanzar.'
                db 0FFh
                db  0Ah ; on_10
                db 0FFh
                db    0
aIAmTheSageMary db 'I am the Sage Maryam./You have made the Spirits proud with your b'
                db 'ravery. I&shall teach you the Magic Spell of Falling Rocks: Rascar.'
                db 0FFh
                db  0Bh ; on_11
                db 0FFh
                db    0
aIAmTheSageSaie db 'I am the Sage Saied./You have lived through much, but your journey'
                db ' is not over. You must be hot. I&shall teach you the Magic Spell'
                db ' of Water: Agua.'
                db 0FFh
                db  0Ch ; on_12
                db 0FFh
                db    0
aIAmTheSageOfAl db 'I am the Sage of All Sages, Indihar./Brave lad, you\ve done well '
                db 'to get this far./'
                db  0Fh
aIShallTeachYou db 'I&shall teach you the Magic Spell of Lightning: Guerra.'
                db 0FFh
                db  0Dh ; on_13
                db 0FFh
                db    0
aDiskErrorPleas db '      Disk error.',0Dh,'Please check your disk',0Dh,'  and press '
                db 'spacebar.'
                db 0FFh
off_B5EB        dw offset byte_B5FB
                dw offset byte_B670
                dw offset byte_B6EB
                dw offset byte_B76D
                dw offset byte_B81C
                dw offset byte_B8B2
                dw offset byte_B954
                dw offset byte_B9AF
byte_B5FB       db 0Ch
aMyMasterTheSag db 'My master, the Sage Yasmin, resides in the underground town. She '
                db 'is a person you can turn to if you are in need. '
                db  11h
                db 0FFh
                db    0
byte_B670       db 0Ch
aWhenYouLeaveTh db 'When you leave the city, climb to the plateau on the left. You\ll'
                db ' see a door that looks like the exit from this world. '
                db  11h
                db 0FFh
                db    0
byte_B6EB       db 0Ch
aTheExitFromThi db 'The exit from this world is very near the exit from the village. '
                db 'However, before you go there you must have the Hero\s Crest. '
                db  11h
                db 0FFh
                db    0
byte_B76D       db 0Ch
aThisIsAMessage db 'This is a message from the Spirits: Bend when you walk a low road'
                db '. Walk not on the steep path with the needles of ice, choose anot'
                db 'her path instead. Heed well these words. '
                db  11h
                db 0FFh
                db    0
byte_B81C       db 0Ch
aYouCanTDefeatT db 'You can\t defeat the demons at the edge of the badlands without the'
                db ' Knight\s Sword. Until you get that sword, do not open the door'
                db ' of the demons. '
                db  11h
                db 0FFh
                db    0
byte_B8B2       db 0Ch
aOnceYouLeaveTh db 'Once you leave this world, get the Silkarn shoes made by the spirits'
                db ' at the behest of Percel. If you do not get those, you cannot '
                db 'travel far from this world. '
                db  11h
                db 0FFh
                db    0
byte_B954       db 0Ch
aThatWorldIsCon db 'That world is controlled by dragons. To get there, you have to open'
                db ' three closed doors.'
                db  11h
                db 0FFh
                db    0
byte_B9AF       db 0Ch
aAtTheEdgeOfThi db 'At the edge of this world is the final foe, Jashiin./To fight Jashiin'
                db ', you must have the Sword of the Fairy Flame. And to get there'
                db ', you must topple the invincible monster Alguien.'
                db  11h
                db 0FFh
                db    0
byte_BA67       db 0Ch
aWhileYouWereUn db 'While you were unconscious, the spirits brought you here./'
                db 0FFh
                db    4
                db 0FFh
                db    4
aBeCarefulNotTo db 'Be careful not to exhaust yourself in battle./'
                db 0FFh
                db    4
aNowBeOnYourWay db 'Now be on your way. '
                db 0FFh
                db    4
aTheSpiritsAreL db 'The spirits are looking after you. '
                db  11h
                db 0FFh
                db 0FFh
word_BB12       dw 0
menu_item_selected db 0
byte_BB15       db 0
byte_BB16       db 0
byte_BB17       db 0
byte_BB18       db 0
byte_BB19       db 0
byte_BB1A       db 0
byte_BB1B       db 0
byte_BB1C       db 0
byte_BB1D       db 0
byte_BB1E       db 0
byte_BB1F       db 0
byte_BB20       db 0
word_BB21       dw 0
byte_BB23       db 0
byte_BB24       db 0
byte_BB25       db 0
byte_BB26       db 0
byte_BB27       db 0, 0, 0, 0, 0, 0, 0
byte_BB2E       db 0
                db    0
                db    0
                db    0
                db    0
                db    0
max_hp          dw 0
spells_cap      db 0, 0, 0, 0, 0, 0, 0
kenjpro         ends

                end     start
