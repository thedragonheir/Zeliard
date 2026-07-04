include common.inc
include town.inc

                .286
                .model small
armpro          segment byte public 'CODE'
                assume cs:armpro, ds:armpro
                org 0A000h
start:
                dw offset sub_A004
                dw offset sub_A90F

; =============== S U B R O U T I N E =======================================


sub_A004        proc near
                mov     es, word ptr ds:seg1
                mov     di, 8000h
                mov     si, offset vfs_armor_grp
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
                mov     byte_BC21, 0
                call    word ptr cs:Clear_Viewport_proc
                call    word ptr cs:Clear_Place_Enemy_Bar_proc
                mov     si, offset word_ACAE
                call    word ptr cs:Render_Pascal_String_1_proc
                call    sub_A0B6
                call    sub_A0E2
                push    cs
                pop     es
                mov     bl, ds:town_id
                dec     bl
                add     bl, bl
                xor     bh, bh
                mov     si, prices_by_town[bx]
                mov     di, offset byte_BBFD
                mov     cx, 12h
                rep movsw
                xor     al, al
                call    sub_A9CF
                mov     byte ptr unk_BC23, 0FFh
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:dialog_string_ptr, offset aMayIBeOfServic
                test    byte ptr ds:cementar_items_1, 2 ; 2 - Returned the Crest of Glory, Changes 0xD6, reduces value by -16 (To remove Knight's Sword from the inventory)
                jnz     short loc_A0A3
                cmp     byte ptr ds:town_id, 5
                jnz     short loc_A0A3
                test    byte ptr ds:crest_of_glory, 0FFh
                jz      short loc_A0A3
                mov     word ptr ds:dialog_string_ptr, offset unk_B2A2
                mov     byte ptr unk_BC23, 0

loc_A0A3:
                call    word ptr cs:render_menu_dialog_proc
                cmp     al, 0FFh
                jz      short loc_A0B1
                call    sub_A10E
                jmp     short loc_A0A3
; ---------------------------------------------------------------------------

loc_A0B1:
                jmp     word ptr cs:Fade_To_Black_Dithered_proc
sub_A004        endp


; =============== S U B R O U T I N E =======================================


sub_A0B6        proc near
                mov     si, offset muralla_arm_swords_inventory_bitmask
                mov     al, ds:town_id
                dec     al
                xor     ah, ah
                add     si, ax
                mov     dl, [si]
                push    cs
                pop     es
                mov     di, offset unk_BC3B
                xor     dh, dh
                mov     cx, 6

loc_A0CE:
                add     dl, dl
                jnb     short loc_A0DB
                mov     al, cl
                neg     al
                add     al, 6
                stosb
                inc     dh

loc_A0DB:
                loop    loc_A0CE
                mov     byte_BC31, dh
                retn
sub_A0B6        endp


; =============== S U B R O U T I N E =======================================


sub_A0E2        proc near
                mov     si, offset muralla_arm_shields_inventory_bitmask
                mov     al, ds:town_id
                dec     al
                xor     ah, ah
                add     si, ax
                mov     dl, [si]
                push    cs
                pop     es
                mov     di, offset byte_BC41
                xor     dh, dh
                mov     cx, 6

loc_A0FA:
                add     dl, dl
                jnb     short loc_A107
                mov     al, cl
                neg     al
                add     al, 6
                stosb
                inc     dh

loc_A107:
                loop    loc_A0FA
                mov     byte ptr unk_BC32, dh
                retn
sub_A0E2        endp


; =============== S U B R O U T I N E =======================================


sub_A10E        proc near

                mov     bl, al
                xor     bh, bh
                add     bx, bx          ; switch 10 cases
                jmp     cs:jpt_A114[bx] ; switch jump
sub_A10E        endp

; ---------------------------------------------------------------------------
jpt_A114        dw offset loc_A12D      ; jump table for switch statement
                dw offset loc_A259
                dw offset loc_A498
                dw offset loc_A6CB
                dw offset sub_A706
                dw offset loc_A716
                dw offset loc_A759
                dw offset sub_A870
                dw offset loc_A880
                dw offset loc_A8FD
; ---------------------------------------------------------------------------

loc_A12D:                               ; jumptable 0000A114 case 0
                call    sub_A902
                mov     bx, 291Dh
                mov     cx, 1837h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 2920h
                mov     byte ptr ds:menu_item_count, 5
                mov     byte ptr ds:menu_max_items, 5
                mov     cx, 5
                mov     si, offset aGoOutside ; "Go outside"
                call    word ptr cs:render_menu_string_list_proc
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     bl, byte_BC21
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A16A
                xor     bl, bl

loc_A16A:
                mov     byte_BC21, bl
                xor     bh, bh
                add     bx, bx          ; switch 5 cases
                jmp     jpt_A172[bx]    ; switch jump
; ---------------------------------------------------------------------------
jpt_A172        dw offset loc_A180      ; jump table for switch statement
                dw offset loc_A198
                dw offset loc_A244
                dw offset loc_A24B
                dw offset loc_A252
; ---------------------------------------------------------------------------

loc_A180:                               ; jumptable 0000A172 case 0
                call    sub_A902
                mov     si, offset unk_B1DE
                test    byte ptr unk_BC28, 0FFh
                jnz     short loc_A193
                call    sub_A706
                mov     si, offset unk_B1FF

loc_A193:
                mov     ds:dialog_string_ptr, si
                retn
; ---------------------------------------------------------------------------

loc_A198:                               ; jumptable 0000A172 case 1
                call    sub_A902
                test    byte ptr ds:shield_type, 0FFh
                jnz     short loc_A1A9
                mov     word ptr ds:dialog_string_ptr, offset unk_AE4A
                retn
; ---------------------------------------------------------------------------

loc_A1A9:
                mov     ax, ds:shield_max_HP
                sub     ax, ds:shield_HP
                jnz     short loc_A1B9
                mov     word ptr ds:dialog_string_ptr, offset unk_AEB1
                retn
; ---------------------------------------------------------------------------

loc_A1B9:
                mov     byte ptr unk_BC28, 0FFh
                shr     ax, 1
                adc     ax, 0
                mov     word ptr unk_BC29, ax
                mov     word ptr ds:dialog_string_ptr, offset unk_AEF8
                call    word ptr cs:render_menu_dialog_proc
                xor     dl, dl
                mov     ax, word ptr unk_BC29
                mov     di, offset unk_BC33
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_BC33
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                pushf
                call    sub_A902
                popf
                mov     word ptr ds:dialog_string_ptr, offset unk_ADEF
                jnb     short loc_A21E
                retn
; ---------------------------------------------------------------------------

loc_A21E:
                mov     ax, word ptr unk_BC29
                xor     dl, dl
                call    word ptr cs:check_gold_sufficient_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_AF53
                jnb     short loc_A231
                retn
; ---------------------------------------------------------------------------

loc_A231:
                mov     ds:hero_gold_hi, dl
                mov     ds:hero_gold_lo, ax
                call    word ptr cs:Print_Gold_Decimal_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_AFAF
                retn
; ---------------------------------------------------------------------------

loc_A244:
                mov     word ptr ds:dialog_string_ptr, offset unk_B026
                retn
; ---------------------------------------------------------------------------

loc_A24B:
                mov     word ptr ds:dialog_string_ptr, offset unk_B081
                retn
; ---------------------------------------------------------------------------

loc_A252:
                mov     word ptr ds:dialog_string_ptr, offset unk_B11F
                retn
; ---------------------------------------------------------------------------

loc_A259:                               ; jumptable 0000A114 case 1
                mov     byte ptr unk_BC28, 0FFh
                push    cs
                pop     es
                mov     di, offset byte_FF58
                mov     si, offset unk_BC3B
                mov     cx, 6
                rep movsb
                mov     al, byte_BC31
                mov     ds:menu_max_items, al
                cmp     al, 3
                jb      short loc_A277
                mov     al, 3

loc_A277:
                mov     ds:menu_item_count, al
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     byte ptr unk_BC22, 0
                mov     bx, 156Eh
                mov     cx, 2524h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:menu_digits_render_flag, 0FFh
                mov     word ptr ds:menu_base_addr, 1571h
                mov     word ptr ds:string_width_bytes, 21h
                mov     word ptr ds:numeric_display_x_offset, 17h
                mov     si, offset off_AD05 ; "Training sword"
                mov     di, offset byte_BBFD
                mov     cl, ds:menu_item_count
                xor     ch, ch
                mov     al, ds:menu_cursor_pos
                call    word ptr cs:render_menu_list_scrolling_proc
                mov     bl, byte ptr unk_BC22
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A2CE
                mov     word ptr ds:dialog_string_ptr, offset unk_ADEF
                retn
; ---------------------------------------------------------------------------

loc_A2CE:
                mov     byte ptr unk_BC22, bl
                mov     al, bl
                add     al, ds:menu_cursor_pos
                mov     bx, offset byte_FF58
                xlat
                call    sub_A47B
                push    ax
                mov     word ptr ds:dialog_string_ptr, offset unk_B0DC
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                push    ax
                mov     si, ds:dialog_string_ptr
                push    si
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_AD05[bx] ; "Training sword"
                mov     ds:dialog_string_ptr, ax
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                push    ax
                xor     ah, ah
                mov     bx, ax
                add     ax, ax
                add     ax, bx
                mov     si, offset byte_BBFD
                add     si, ax
                mov     dl, [si]
                mov     ax, [si+1]
                mov     byte ptr unk_BC29, dl
                mov     word ptr unk_BC2A, ax
                call    word ptr cs:check_gold_sufficient_proc
                pop     bx
                mov     word ptr ds:dialog_string_ptr, offset aIMSorrySirYouA
                jnb     short loc_A338
                retn
; ---------------------------------------------------------------------------

loc_A338:
                mov     byte ptr unk_BC2C, dl
                mov     word ptr unk_BC2D, ax
                inc     bl
                mov     byte ptr unk_BC2F, bl
                mov     word ptr ds:dialog_string_ptr, offset aThatWillBe
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, byte ptr unk_BC29
                mov     ax, word ptr unk_BC2A
                mov     di, offset unk_BC33
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_BC33
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                mov     byte ptr unk_BC29, 0
                mov     word ptr unk_BC2A, 0
                test    byte ptr ds:sword_type, 0FFh
                jz      short loc_A3DE
                mov     al, ds:sword_type
                mov     byte ptr unk_BC30, al
                mov     word ptr ds:dialog_string_ptr, offset aILlGiveYou
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte ptr unk_BC30
                dec     al
                xor     ah, ah
                mov     bx, ax
                add     ax, ax
                add     bx, ax
                mov     dl, byte_BBFD[bx]
                mov     ax, word_BBFE[bx]
                shr     dl, 1
                rcr     ax, 1
                mov     byte ptr unk_BC29, dl
                mov     word ptr unk_BC2A, ax
                mov     di, offset unk_BC33
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_BC33
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc

loc_A3DE:
                mov     word ptr ds:dialog_string_ptr, offset aWillThatBeAllR ; "Will that be all right?"
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_ADEF
                jnb     short loc_A40A
                retn
; ---------------------------------------------------------------------------

loc_A40A:
                mov     word ptr ds:dialog_string_ptr, offset unk_AE1C
                mov     dl, byte ptr unk_BC2C
                mov     ax, word ptr unk_BC2D
                mov     ds:hero_gold_hi, dl
                mov     ds:hero_gold_lo, ax
                mov     dl, byte ptr unk_BC29
                mov     ax, word ptr unk_BC2A
                call    word ptr cs:add_gold_to_hero_proc
                call    word ptr cs:Print_Gold_Decimal_proc
                test    byte ptr unk_BC30, 0FFh
                jz      short loc_A44B
                mov     al, byte ptr unk_BC30
                dec     al
                mov     bx, offset unk_AC9C
                xlat
                mov     bl, ds:town_id
                dec     bl
                xor     bh, bh
                or      muralla_arm_swords_inventory_bitmask[bx], al

loc_A44B:
                mov     al, byte ptr unk_BC2F
                mov     ds:sword_type, al
                cmp     al, 6
                jnz     short loc_A462
                mov     bl, ds:town_id
                dec     bl
                xor     bh, bh
                and     byte ptr muralla_arm_swords_inventory_bitmask[bx], 0FBh

loc_A462:
                call    sub_A0B6
                mov     ah, ds:sword_type
                mov     al, 4           ; fn4_load_sword_graphics
                call    word ptr cs:res_dispatcher_proc
                mov     al, ds:sword_type
                mov     bx, 18ABh
                jmp     word ptr cs:Render_Sword_Item_Sprite_20x18_proc

; =============== S U B R O U T I N E =======================================


sub_A47B        proc near
                cmp     al, 3
                jz      short loc_A480
                retn
; ---------------------------------------------------------------------------

loc_A480:
                test    byte ptr ds:cementar_items_1, 2 ; 2 - Returned the Crest of Glory, Changes 0xD6, reduces value by -16 (To remove Knight's Sword from the inventory)
                jz      short loc_A488
                retn
; ---------------------------------------------------------------------------

loc_A488:
                cmp     byte ptr ds:town_id, 5
                jz      short loc_A490
                retn
; ---------------------------------------------------------------------------

loc_A490:
                pop     ax
                mov     word ptr ds:dialog_string_ptr, offset unk_B24C
                retn
sub_A47B        endp

; ---------------------------------------------------------------------------

loc_A498:                               ; jumptable 0000A114 case 2
                mov     byte ptr unk_BC28, 0FFh
                push    cs
                pop     es
                mov     di, offset byte_FF58
                mov     si, offset byte_BC41
                mov     cx, 6
                rep movsb
                mov     al, byte ptr unk_BC32
                mov     ds:menu_max_items, al
                cmp     al, 3
                jb      short loc_A4B6
                mov     al, 3

loc_A4B6:
                mov     ds:menu_item_count, al
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     byte ptr unk_BC22, 0
                mov     bx, 156Eh
                mov     cx, 2524h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:menu_digits_render_flag, 0FFh
                mov     word ptr ds:menu_base_addr, 1571h
                mov     word ptr ds:string_width_bytes, 21h
                mov     word ptr ds:numeric_display_x_offset, 17h
                mov     si, offset off_AD11 ; "Clay shield"
                mov     di, offset byte_BC0F
                mov     cl, ds:menu_item_count
                xor     ch, ch
                mov     al, ds:menu_cursor_pos
                call    word ptr cs:render_menu_list_scrolling_proc
                mov     bl, byte ptr unk_BC22
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A50D
                mov     word ptr ds:dialog_string_ptr, offset unk_ADEF
                retn
; ---------------------------------------------------------------------------

loc_A50D:
                mov     byte ptr unk_BC22, bl
                mov     word ptr ds:dialog_string_ptr, offset unk_B0DC
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte ptr unk_BC22
                add     al, ds:menu_cursor_pos
                mov     bx, offset byte_FF58
                xlat
                push    ax
                mov     si, ds:dialog_string_ptr
                push    si
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_AD11[bx] ; "Clay shield"
                mov     ds:dialog_string_ptr, ax
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                push    ax
                xor     ah, ah
                mov     bx, ax
                add     ax, ax
                add     ax, bx
                mov     si, offset byte_BC0F
                add     si, ax
                mov     dl, [si]
                mov     ax, [si+1]
                mov     byte ptr unk_BC29, dl
                mov     word ptr unk_BC2A, ax
                call    word ptr cs:check_gold_sufficient_proc
                pop     bx
                mov     word ptr ds:dialog_string_ptr, offset aIMSorrySirYouA
                jnb     short loc_A573
                retn
; ---------------------------------------------------------------------------

loc_A573:
                mov     byte ptr unk_BC2C, dl
                mov     word ptr unk_BC2D, ax
                inc     bl
                mov     byte ptr unk_BC2F, bl
                mov     word ptr ds:dialog_string_ptr, offset aThatWillBe
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, byte ptr unk_BC29
                mov     ax, word ptr unk_BC2A
                mov     di, offset unk_BC33
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_BC33
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                mov     byte ptr unk_BC29, 0
                mov     word ptr unk_BC2A, 0
                test    byte ptr ds:shield_type, 0FFh
                jz      short loc_A619
                mov     al, ds:shield_type
                mov     byte ptr unk_BC30, al
                mov     word ptr ds:dialog_string_ptr, offset aILlGiveYou_0
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte ptr unk_BC30
                dec     al
                xor     ah, ah
                mov     bx, ax
                add     ax, ax
                add     bx, ax
                mov     dl, byte_BC0F[bx]
                mov     ax, word_BC10[bx]
                shr     dl, 1
                rcr     ax, 1
                mov     byte ptr unk_BC29, dl
                mov     word ptr unk_BC2A, ax
                mov     di, offset unk_BC33
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_BC33
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc

loc_A619:
                mov     word ptr ds:dialog_string_ptr, offset aWillThatBeAllR
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_ADEF
                jnb     short loc_A645
                retn
; ---------------------------------------------------------------------------

loc_A645:
                mov     word ptr ds:dialog_string_ptr, offset unk_AE1C
                mov     dl, byte ptr unk_BC2C
                mov     ax, word ptr unk_BC2D
                mov     ds:hero_gold_hi, dl
                mov     ds:hero_gold_lo, ax
                mov     dl, byte ptr unk_BC29
                mov     ax, word ptr unk_BC2A
                call    word ptr cs:add_gold_to_hero_proc
                call    word ptr cs:Print_Gold_Decimal_proc
                test    byte ptr unk_BC30, 0FFh
                jz      short loc_A686
                mov     al, byte ptr unk_BC30
                dec     al
                mov     bx, offset unk_AC9C
                xlat
                mov     bl, ds:town_id
                dec     bl
                xor     bh, bh
                or      muralla_arm_shields_inventory_bitmask[bx], al

loc_A686:
                mov     al, byte ptr unk_BC2F
                mov     ds:shield_type, al
                call    sub_A0E2
                mov     al, ds:shield_type
                mov     bx, 3EA4h
                call    word ptr cs:Render_Shield_Item_Sprite_16x16_proc
                mov     bx, 0C61Ch
                xor     al, al
                mov     ch, 17h
                call    word ptr cs:Clear_HUD_Bar_proc
                mov     bl, ds:shield_type
                dec     bl
                xor     bh, bh
                add     bx, bx
                mov     ax, word_A6BF[bx]
                mov     ds:shield_max_HP, ax
                mov     ds:shield_HP, ax
                jmp     word ptr cs:Print_ShieldHP_Decimal_proc
; ---------------------------------------------------------------------------
word_A6BF       dw 30
                dw 80
                dw 180
                dw 300
                dw 300
                dw 600
; ---------------------------------------------------------------------------

loc_A6CB:                               ; jumptable 0000A114 case 3
                mov     byte ptr unk_BC23, 0
                test    byte ptr unk_BC26, 0FFh
                jz      short loc_A6DF
                mov     al, 1
                call    sub_A9CF
                call    sub_A870

loc_A6DF:
                mov     si, offset byte_A6FD

loc_A6E2:
                lodsb
                cmp     al, 0FFh
                jnz     short loc_A6E8
                retn
; ---------------------------------------------------------------------------

loc_A6E8:
                push    si
                or      al, al
                jns     short loc_A6F2
                mov     byte ptr ds:soundFX_request, 32

loc_A6F2:
                and     al, 7
                call    sub_A9CF
                call    sub_A870
                pop     si
                jmp     short loc_A6E2
; ---------------------------------------------------------------------------
byte_A6FD       db 3, 4, 5, 5, 86h, 6, 7, 7, 0FFh

; =============== S U B R O U T I N E =======================================


sub_A706        proc near
                mov     byte ptr ds:frame_timer, 0

loc_A70B:
                call    sub_A90F
                cmp     byte ptr ds:frame_timer, 150
                jb      short loc_A70B
                retn
sub_A706        endp

; ---------------------------------------------------------------------------

loc_A716:
                call    word ptr cs:Fade_To_Black_Dithered_proc
                mov     word ptr ds:tick_counter, 0

loc_A721:
                cmp     word ptr ds:tick_counter, 400
                jb      short loc_A721
                mov     ax, ds:shield_max_HP
                mov     ds:shield_HP, ax
                call    word ptr cs:Print_ShieldHP_Decimal_proc
                mov     byte ptr unk_BC24, 0
                mov     byte ptr unk_BC25, 0
                mov     byte ptr unk_BC26, 0
                mov     byte ptr unk_BC27, 0
                xor     al, al
                call    sub_A9CF
                mov     byte ptr unk_BC23, 0FFh
                mov     word ptr ds:dialog_string_ptr, offset unk_AFE0
                retn
; ---------------------------------------------------------------------------

loc_A759:                               ; jumptable 0000A114 case 6
                mov     byte ptr unk_BC22, 0
                mov     byte ptr ds:menu_cursor_pos, 0

loc_A763:
                push    cs
                pop     es
                mov     cl, byte_BC31
                xor     ch, ch
                mov     si, offset unk_BC3B
                mov     di, offset byte_FF58
                rep movsb
                mov     cl, byte ptr unk_BC32
                mov     si, 0BC41h

loc_A77A:
                lodsb
                add     al, 6
                stosb
                loop    loc_A77A
                mov     al, byte_BC31
                add     al, byte ptr unk_BC32
                mov     ds:menu_max_items, al
                mov     al, ds:menu_max_items
                cmp     al, 6
                jb      short loc_A793
                mov     al, 6

loc_A793:
                mov     ds:menu_item_count, al
                mov     bx, 2717h
                mov     cx, 1B41h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:menu_digits_render_flag, 0
                mov     word ptr ds:menu_base_addr, 271Ah
                mov     word ptr ds:string_width_bytes, 17h
                mov     si, offset off_AD05 ; "Training sword"
                mov     cl, ds:menu_item_count
                xor     ch, ch
                mov     al, ds:menu_cursor_pos
                call    word ptr cs:render_menu_list_scrolling_proc
                mov     bl, byte ptr unk_BC22
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A7D7
                mov     word ptr ds:dialog_string_ptr, offset unk_ADEF
                retn
; ---------------------------------------------------------------------------

loc_A7D7:
                mov     byte ptr unk_BC22, bl
                mov     word ptr ds:dialog_string_ptr, offset unk_B0EA
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte ptr unk_BC22
                add     al, ds:menu_cursor_pos
                mov     bx, offset byte_FF58
                xlat
                call    sub_A8E0
                push    ax
                push    ax
                mov     word ptr ds:dialog_string_ptr, offset aOhThe
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                mov     si, ds:dialog_string_ptr
                push    si
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_AD05[bx] ; "Training sword"
                mov     ds:dialog_string_ptr, ax
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_B3DE[bx] ; "Well, I\\d say this sword is all right "...
                mov     ds:dialog_string_ptr, ax
                call    word ptr cs:render_menu_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset aIsThereAnother
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_ADEF
                jnb     short loc_A862
                retn
; ---------------------------------------------------------------------------

loc_A862:
                mov     word ptr ds:dialog_string_ptr, offset unk_B17E
                call    word ptr cs:render_menu_dialog_proc
                jmp     loc_A763

; =============== S U B R O U T I N E =======================================


sub_A870        proc near
                mov     byte ptr ds:frame_timer, 0

loc_A875:
                call    sub_A90F
                cmp     byte ptr ds:frame_timer, 50
                jb      short loc_A875
                retn
sub_A870        endp

; ---------------------------------------------------------------------------

loc_A880:                               ; jumptable 0000A114 case 8
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                pushf
                call    sub_A902
                popf
                mov     word ptr ds:dialog_string_ptr, offset unk_B336
                jnb     short loc_A8A6
                retn
; ---------------------------------------------------------------------------

loc_A8A6:
                xor     al, al
                call    sub_A9CF
                mov     word ptr ds:dialog_string_ptr, offset unk_B375
                call    word ptr cs:render_menu_dialog_proc
                mov     byte ptr ds:sword_type, 4
                mov     byte ptr ds:crest_of_glory, 0
                mov     al, 4
                mov     bx, 18ABh
                call    word ptr cs:Render_Sword_Item_Sprite_20x18_proc
                and     byte ptr ds:tumba_arm_swords_inventory_bitmask, 0EFh
                or      byte ptr ds:cementar_items_1, 2 ; 2 - Returned the Crest of Glory, Changes 0xD6, reduces value by -16 (To remove Knight's Sword from the inventory)
                mov     ah, ds:sword_type
                mov     al, 4           ; fn4_load_sword_graphics
                call    word ptr cs:res_dispatcher_proc
                retn

; =============== S U B R O U T I N E =======================================


sub_A8E0        proc near
                cmp     al, 3
                jz      short loc_A8E5
                retn
; ---------------------------------------------------------------------------

loc_A8E5:
                test    byte ptr ds:cementar_items_1, 2 ; 2 - Returned the Crest of Glory, Changes 0xD6, reduces value by -16 (To remove Knight's Sword from the inventory)
                jz      short loc_A8ED
                retn
; ---------------------------------------------------------------------------

loc_A8ED:
                cmp     byte ptr ds:town_id, 5
                jz      short loc_A8F5
                retn
; ---------------------------------------------------------------------------

loc_A8F5:
                pop     ax
                mov     word ptr ds:dialog_string_ptr, offset unk_B240
                retn
sub_A8E0        endp

; ---------------------------------------------------------------------------

loc_A8FD:                               ; jumptable 0000A114 case 9
                mov     al, 3
                jmp     sub_A9CF

; =============== S U B R O U T I N E =======================================


sub_A902        proc near
                mov     bx, 2717h
                mov     cx, 1C41h
                xor     al, al
                jmp     word ptr cs:Draw_Bordered_Rectangle_proc
sub_A902        endp


; =============== S U B R O U T I N E =======================================


sub_A90F        proc near
                test    byte ptr unk_BC23, 0FFh
                jnz     short loc_A917
                retn
; ---------------------------------------------------------------------------

loc_A917:
                cmp     word ptr ds:tick_counter, 2
                jnb     short loc_A91F
                retn
; ---------------------------------------------------------------------------

loc_A91F:
                mov     word ptr ds:tick_counter, 0
                inc     byte ptr unk_BC24
                cmp     byte ptr unk_BC24, 30
                jnb     short loc_A931
                retn
; ---------------------------------------------------------------------------

loc_A931:
                mov     byte ptr unk_BC24, 0
                inc     byte ptr unk_BC25
                test    byte ptr unk_BC26, 0FFh
                jz      short loc_A985
                cmp     byte ptr unk_BC26, 7Fh
                jnz     short loc_A951
                mov     byte ptr unk_BC26, 0FFh
                mov     al, 2
                jmp     short sub_A9CF
; ---------------------------------------------------------------------------

loc_A951:
                cmp     byte ptr unk_BC26, 80h
                jnz     short loc_A961
                mov     byte ptr unk_BC26, 0
                xor     al, al
                jmp     short sub_A9CF
; ---------------------------------------------------------------------------

loc_A961:
                mov     si, offset unk_AB68
                mov     al, byte ptr unk_BC25
                and     ax, 3
                add     ax, ax
                add     si, ax
                mov     bx, 0B37h
                mov     cx, 2

loc_A974:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                add     bl, 8
                pop     cx
                loop    loc_A974
                jmp     short loc_A9A6
; ---------------------------------------------------------------------------

loc_A985:
                mov     si, offset unk_AAD0
                mov     al, byte ptr unk_BC25
                and     ax, 3
                add     ax, ax
                add     si, ax
                mov     bx, 104Fh
                mov     cx, 2

loc_A998:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A998

loc_A9A6:
                call    word ptr cs:get_random_proc
                and     al, 1
                jz      short loc_A9B0
                retn
; ---------------------------------------------------------------------------

loc_A9B0:
                inc     byte ptr unk_BC27
                cmp     byte ptr unk_BC27, 30
                jnb     short loc_A9BC
                retn
; ---------------------------------------------------------------------------

loc_A9BC:
                mov     byte ptr unk_BC27, 0
                mov     al, byte ptr unk_BC26
                not     al
                xor     al, 80h
                mov     byte ptr unk_BC26, al
                mov     al, 1
                jmp     short $+2
sub_A90F        endp


; =============== S U B R O U T I N E =======================================


sub_A9CF        proc near
                xor     ah, ah
                add     ax, ax
                mov     cx, ax
                add     ax, ax
                add     ax, cx
                add     ax, offset byte_AA10
                mov     si, ax
                mov     bx, 717h
                mov     cx, 2

loc_A9E4:
                lodsb
                or      al, al
                jnz     short loc_A9EA
                retn
; ---------------------------------------------------------------------------

loc_A9EA:
                push    cx
                mov     cl, al
                lodsw
                xchg    ax, si
                push    ax

loc_A9F0:
                push    cx
                mov     cx, 12

loc_A9F4:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A9F4
                sub     bh, 0Ch
                add     bl, 8
                pop     cx
                loop    loc_A9F0
                pop     si
                pop     cx
                loop    loc_A9E4
                retn
sub_A9CF        endp

; ---------------------------------------------------------------------------
byte_AA10       db 2
                dw offset unk_AA40
                db 6
                dw offset unk_AA88
                db 2
                dw offset unk_AA40
                db 6
                dw offset unk_AAD8
                db 2
                dw offset unk_AA40
                db 6
                dw offset unk_AB20
                db 4
                dw offset unk_AA58
                db 4
                dw offset unk_AB70
                db 3
                dw offset unk_AA58
                db 5
                dw offset unk_ABA0
                db 8
                dw offset unk_ABDC
                db 0
                db    0
                db    0
                db 4
                dw offset unk_AA58
                db 4
                dw offset unk_AC3C
                db 4
                dw offset unk_AA58
                db 4
                dw offset unk_AC6C
unk_AA40        db    0
                db    1
                db    2
                db    3
                db    1
                db    1
                db    1
                db    1
                db    1
                db    4
                db    5
                db    6
                db    7
                db    8
                db    9
                db  0Ah
                db  0Bh
                db  0Ch
                db  0Ch
                db  0Ch
                db  0Ch
                db  0Dh
                db  0Eh
                db  0Fh
unk_AA58        db    0
                db    1
                db    2
                db    3
                db    1
                db    1
                db    1
                db    1
                db    1
                db    4
                db    5
                db    6
                db    7
                db    8
                db    9
                db  0Ah
                db  0Bh
                db  0Ch
                db  0Ch
                db  0Ch
                db  0Ch
                db  0Dh
                db  0Eh
                db  0Fh
                db  10h
                db  11h
                db  12h
                db  13h
                db  14h
                db  15h
                db  16h
                db  0Ch
                db  0Ch
                db  17h
                db  18h
                db  19h
                db  1Ah
                db  1Bh
                db  0Ch
                db  8Fh
                db  90h
                db  1Eh
                db  91h
                db  92h
                db  93h
                db  21h ; !
                db  22h ; "
                db  23h ; #
unk_AA88        db  10h
                db  11h
                db  12h
                db  13h
                db  14h
                db  15h
                db  16h
                db  0Ch
                db  0Ch
                db  17h
                db  18h
                db  19h
                db  1Ah
                db  1Bh
                db  0Ch
                db  1Ch
                db  1Dh
                db  1Eh
                db  1Fh
                db  20h
                db  0Ch
                db  21h ; !
                db  22h ; "
                db  23h ; #
                db  24h ; $
                db  25h ; %
                db  0Ch
                db  26h ; &
                db  27h ; '
                db  28h ; (
                db  29h ; )
                db  2Ah ; *
                db  2Bh ; +
                db  2Ch ; ,
                db  2Dh ; -
                db  2Eh ; .
                db  2Fh ; /
                db  30h ; 0
                db  31h ; 1
                db  32h ; 2
                db  33h ; 3
                db  34h ; 4
                db  35h ; 5
                db  36h ; 6
                db  37h ; 7
                db  38h ; 8
                db  39h ; 9
                db  3Ah ; :
                db  3Bh ; ;
                db  3Ch ; <
                db  3Dh ; =
                db  3Eh ; >
                db  3Fh ; ?
                db  40h ; @
                db  41h ; A
                db  42h ; B
                db  43h ; C
                db  44h ; D
                db  45h ; E
                db  46h ; F
                db  47h ; G
                db  48h ; H
                db  49h ; I
                db  4Ah ; J
                db  4Bh ; K
                db  4Ch ; L
                db  4Dh ; M
                db  4Eh ; N
                db  4Fh ; O
                db  50h ; P
                db  51h ; Q
                db  52h ; R
unk_AAD0        db  50h ; P
                db  51h ; Q
                db  50h ; P
                db  51h ; Q
                db  50h ; P
                db  51h ; Q
                db  53h ; S
                db  54h ; T
unk_AAD8        db  10h
                db  11h
                db  12h
                db  13h
                db  55h ; U
                db  56h ; V
                db  57h ; W
                db  0Ch
                db  0Ch
                db  17h
                db  18h
                db  19h
                db  1Ah
                db  1Bh
                db  0Ch
                db  1Ch
                db  58h ; X
                db  59h ; Y
                db  5Ah ; Z
                db  5Bh ; [
                db  0Ch
                db  21h ; !
                db  22h ; "
                db  23h ; #
                db  24h ; $
                db  25h ; %
                db  0Ch
                db  5Ch ; \
                db  5Dh ; ]
                db  5Eh ; ^
                db  5Fh ; _
                db  60h ; `
                db  61h ; a
                db  2Ch ; ,
                db  2Dh ; -
                db  2Eh ; .
                db  2Fh ; /
                db  30h ; 0
                db  62h ; b
                db  63h ; c
                db  64h ; d
                db  65h ; e
                db  66h ; f
                db  67h ; g
                db  68h ; h
                db  69h ; i
                db  39h ; 9
                db  3Ah ; :
                db  3Bh ; ;
                db  3Ch ; <
                db  6Ah ; j
                db  6Bh ; k
                db  6Ch ; l
                db  6Dh ; m
                db  6Eh ; n
                db  6Fh ; o
                db  70h ; p
                db  71h ; q
                db  45h ; E
                db  46h ; F
                db  47h ; G
                db  72h ; r
                db  73h ; s
                db  74h ; t
                db  75h ; u
                db  76h ; v
                db  77h ; w
                db  78h ; x
                db  79h ; y
                db  7Ah ; z
                db  7Bh ; {
                db  52h ; R
unk_AB20        db  10h
                db  11h
                db  12h
                db  13h
                db  55h ; U
                db  56h ; V
                db  57h ; W
                db  0Ch
                db  0Ch
                db  17h
                db  18h
                db  19h
                db  1Ah
                db  1Bh
                db  0Ch
                db  1Ch
                db  58h ; X
                db  59h ; Y
                db  5Ah ; Z
                db  5Bh ; [
                db  0Ch
                db  21h ; !
                db  22h ; "
                db  23h ; #
                db  24h ; $
                db  25h ; %
                db  0Ch
                db  7Ch ; |
                db  5Dh ; ]
                db  5Eh ; ^
                db  5Fh ; _
                db  7Dh ; }
                db  7Eh ; ~
                db  2Ch ; ,
                db  2Dh ; -
                db  2Eh ; .
                db  2Fh ; /
                db  30h ; 0
                db  6Ah ; j
                db  80h
                db  81h
                db  82h
                db  83h
                db  84h
                db  85h
                db  69h ; i
                db  39h ; 9
                db  3Ah ; :
                db  3Bh ; ;
                db  3Ch ; <
                db  0Ch
                db  7Fh ; 
                db  86h
                db  87h
                db  88h
                db  89h
                db  8Ah
                db  71h ; q
                db  45h ; E
                db  46h ; F
                db  47h ; G
                db  72h ; r
                db  73h ; s
                db  4Ah ; J
                db  4Bh ; K
                db  4Ch ; L
                db  4Dh ; M
                db  4Eh ; N
                db  79h ; y
                db  7Ah ; z
                db  7Bh ; {
                db  52h ; R
unk_AB68        db  5Dh ; ]
                db  81h
                db  5Dh ; ]
                db  81h
                db  5Dh ; ]
                db  81h
                db  8Dh
                db  8Eh
unk_AB70        db  24h ; $
                db  25h ; %
                db  94h
                db  95h
                db  96h
                db  28h ; (
                db  97h
                db  98h
                db  99h
                db  2Ch ; ,
                db  2Dh ; -
                db  2Eh ; .
                db  2Fh ; /
                db  30h ; 0
                db  9Ah
                db  9Bh
                db  9Ch
                db  9Dh
                db  9Eh
                db  9Fh
                db 0A0h
                db 0A1h
                db  39h ; 9
                db  3Ah ; :
                db  3Bh ; ;
                db  3Ch ; <
                db 0A2h
                db 0A3h
                db 0A4h
                db 0A5h
                db 0A6h
                db 0A7h
                db 0A8h
                db 0A9h
                db  45h ; E
                db  46h ; F
                db  47h ; G
                db  72h ; r
                db 0AAh
                db 0ABh
                db  4Bh ; K
                db  4Ch ; L
                db  4Dh ; M
                db  4Eh ; N
                db 0ACh
                db 0ADh
                db  7Bh ; {
                db  52h ; R
unk_ABA0        db  1Ah
                db  1Bh
                db  0Ch
                db 0AEh
                db 0AFh
                db  1Eh
                db  91h
                db 0B0h
                db 0B1h
                db  21h ; !
                db  22h ; "
                db  23h ; #
                db  24h ; $
                db 0B2h
                db 0B3h
                db 0B4h
                db 0B5h
                db 0B6h
                db  97h
                db 0B7h
                db 0B8h
                db 0B9h
                db  2Dh ; -
                db  2Eh ; .
                db  2Fh ; /
                db 0BAh
                db 0BBh
                db 0BCh
                db  9Ch
                db  9Dh
                db  9Eh
                db 0BDh
                db 0BEh
                db 0BFh
                db  39h ; 9
                db  3Ah ; :
                db  3Bh ; ;
                db  3Ch ; <
                db  0Ch
                db  0Ch
                db 0C0h
                db 0A5h
                db 0A6h
                db 0C1h
                db  8Ah
                db  71h ; q
                db  45h ; E
                db  46h ; F
                db  47h ; G
                db  72h ; r
                db  73h ; s
                db  4Ah ; J
                db  4Bh ; K
                db  4Ch ; L
                db  4Dh ; M
                db  4Eh ; N
                db  79h ; y
                db  7Ah ; z
                db  7Bh ; {
                db  52h ; R
unk_ABDC        db    0
                db    1
                db    2
                db 0C2h
                db 0C3h
                db 0C4h
                db 0C5h
                db 0C6h
                db    1
                db    4
                db    5
                db    6
                db    7
                db    8
                db 0C7h
                db 0C8h
                db 0C9h
                db 0CAh
                db 0CBh
                db 0CCh
                db 0CDh
                db  0Dh
                db  0Eh
                db  0Fh
                db  10h
                db  11h
                db 0CEh
                db 0CFh
                db 0D0h
                db 0D1h
                db 0D2h
                db 0D3h
                db 0D4h
                db  17h
                db  18h
                db  19h
                db  1Ah
                db  1Bh
                db  0Ch
                db 0D5h
                db 0D6h
                db 0D7h
                db 0D8h
                db 0D9h
                db 0DAh
                db  21h ; !
                db  22h ; "
                db  23h ; #
                db  24h ; $
                db  25h ; %
                db  0Ch
                db 0DBh
                db 0B5h
                db 0DCh
                db 0DDh
                db 0DEh
                db  0Ch
                db  2Ch ; ,
                db  2Dh ; -
                db  2Eh ; .
                db  2Fh ; /
                db  30h ; 0
                db  0Ch
                db  6Ah ; j
                db  9Ch
                db  9Dh
                db 0DFh
                db 0E0h
                db  0Ch
                db  69h ; i
                db  39h ; 9
                db  3Ah ; :
                db  3Bh ; ;
                db  3Ch ; <
                db  0Ch
                db  0Ch
                db 0C0h
                db 0E1h
                db 0E2h
                db 0C1h
                db  8Ah
                db  71h ; q
                db  45h ; E
                db  46h ; F
                db  47h ; G
                db  72h ; r
                db  73h ; s
                db  4Ah ; J
                db  4Bh ; K
                db  4Ch ; L
                db  4Dh ; M
                db  4Eh ; N
                db  79h ; y
                db  7Ah ; z
                db  7Bh ; {
                db  52h ; R
unk_AC3C        db 0E3h
                db 0E4h
                db  94h
                db  95h
                db  96h
                db  28h ; (
                db  97h
                db  98h
                db  99h
                db  2Ch ; ,
                db  2Dh ; -
                db  2Eh ; .
                db 0E5h
                db 0E6h
                db 0E7h
                db  9Bh
                db  9Ch
                db  9Dh
                db  9Eh
                db  9Fh
                db 0A0h
                db 0A1h
                db  39h ; 9
                db  3Ah ; :
                db 0E8h
                db 0E9h
                db 0EAh
                db 0EBh
                db 0A4h
                db 0A5h
                db 0A6h
                db 0A7h
                db 0ECh
                db 0EDh
                db  45h ; E
                db  46h ; F
                db 0EEh
                db 0EFh
                db 0F0h
                db 0F1h
                db 0F2h
                db 0F3h
                db 0F4h
                db 0F5h
                db 0F6h
                db 0F7h
                db 0F8h
                db 0F9h
unk_AC6C        db  24h ; $
                db  25h ; %
                db  94h
                db  95h
                db  96h
                db  28h ; (
                db  97h
                db  98h
                db  99h
                db  2Ch ; ,
                db  2Dh ; -
                db  2Eh ; .
                db  2Fh ; /
                db  30h ; 0
                db 0E7h
                db  9Bh
                db  9Ch
                db  9Dh
                db  9Eh
                db  9Fh
                db 0A0h
                db 0A1h
                db  39h ; 9
                db  3Ah ; :
                db 0FAh
                db 0FBh
                db 0EAh
                db 0EBh
                db 0A4h
                db 0A5h
                db 0A6h
                db 0A7h
                db 0ECh
                db 0EDh
                db  45h ; E
                db  46h ; F
                db 0FCh
                db 0FDh
                db 0F0h
                db 0FEh
                db  4Bh ; K
                db  4Ch ; L
                db  4Dh ; M
                db  4Eh ; N
                db 0F6h
                db 0FFh
                db  7Bh ; {
                db  52h ; R
unk_AC9C        db  80h
                db  40h ; @
                db  20h
                db  10h
                db    8
                db    4
vfs_armor_grp   db 1
                db  15h
aArmorGrp       db 'ARMOR.GRP',0
word_ACAE       dw 0AF10h
                db    0
aWeaponAndArmou db 22,'Weapon and Armour Shop'
aGoOutside      db 'Go outside',0
aRepairShield   db 'Repair shield',0
aBuyWeapon      db 'Buy weapon',0
aBuyShield      db 'Buy shield',0
aExplainGoods   db 'Explain goods',0
off_AD05        dw offset aTrainingSword ; "Training sword"
                dw offset aWiseManSSword ; "Wise man\\s sword"
                dw offset aSpiritSword  ; "Spirit sword"
                dw offset aKnightSSword ; "Knight\\s sword"
                dw offset aIlluminationSw ; "Illumination sword"
                dw offset aEnchantmentSwo ; "Enchantment sword"
off_AD11        dw offset aClayShield   ; "Clay shield"
                dw offset aWiseManSShield ; "Wise man\\s shield"
                dw offset aStoneShield  ; "Stone shield"
                dw offset aHonorShield  ; "Honor shield"
                dw offset aLightShield  ; "Light shield"
                dw offset aTitaniumShield ; "Titanium Shield"
aTrainingSword  db 'Training sword',0
aWiseManSSword  db 'Wise man\s sword',0
aSpiritSword    db 'Spirit sword',0
aKnightSSword   db 'Knight\s sword',0
aIlluminationSw db 'Illumination sword',0
aEnchantmentSwo db 'Enchantment sword',0
aClayShield     db 'Clay shield',0
aWiseManSShield db 'Wise man\s shield',0
aStoneShield    db 'Stone shield',0
aHonorShield    db 'Honor shield',0
aLightShield    db 'Light shield',0
aTitaniumShield db 'Titanium Shield',0
aMayIBeOfServic db 'May I&be of service, sir?/'
                db 0FFh
                db    0
unk_ADEF        db  0Ch
aIsThereSomethi db 'Is there something I&can do for you, sir?/'
                db 0FFh
                db    0
unk_AE1C        db  0Ch
aWillThereBeSom db 'Will there be something else for you, sir?/'
                db 0FFh
                db    0
unk_AE4A        db  0Ch
aSirYouArenTCar db 'Sir, you aren\t carrying a shield -- however, I do have a fine se'
                db 'lection, if you\d like to buy one./'
                db 0FFh
                db    0
unk_AEB1        db  0Ch
aSirYourShieldI db 'Sir, your shield is not in need of repair. How else can I help yo'
                db 'u?/'
                db 0FFh
                db    0
unk_AEF8        db  0Ch
aILlBeGladToRep db 'I\ll be glad to repair your shield, sir, for the low price of '
                db 0FFh
                db    0
aGoldsShallIPro db '&golds. Shall I&proceed?'
                db 0FFh
                db    0
unk_AF53        db  0Dh
aIMSorrySirYouA db 'I\m sorry sir, you aren\t carrying enough gold. Perhaps after you'
                db '\ve visited the bank.../'
                db 0FFh
                db    0
unk_AFAF        db  0Dh
aPleaseWaitHere db 'Please wait here, I\ll only be a moment.'
                db 0FFh
                db    4
                db 0FFh
                db    4
                db 0FFh
                db    5
                db 0FFh
                db    0
unk_AFE0        db  0Ch
aTheRepairsToYo db 'The repairs to your armour are complete. It is now as good as new'
                db './'
                db 0FFh
                db    0
unk_B026        db  0Ch
aSomethingElseF db 'Something else for you, sir?/'
                db 0FFh
                db    1
aILlGiveYou     db 'I\ll give you '
                db 0FFh
                db    0
aGoldsOnYourOld db '&golds on your old weapon as a trade-in.',0Dh
                db 0FFh
                db    0
unk_B081        db  0Ch
aSomethingElseF_0 db 'Something else for you, sir?/'
                db 0FFh
                db    2
aILlGiveYou_0   db 'I\ll give you '
                db 0FFh
                db    0
aGoldsOnYourOld_0 db '&golds on your old shield as a trade-in.',0Dh
                db 0FFh
                db    0
unk_B0DC        db  0Ch
aOhThe          db 'Oh, the '
                db 0FFh
                db    0
                db  3Fh ; ?
                db  2Fh ; /
                db 0FFh
unk_B0EA        db  0Ch
                db 0FFh
                db    0
aWillThatBeAllR db 'Will that be all right?'
                db 0FFh
                db    0
aThatWillBe     db 'That will be '
                db 0FFh
                db    0
aGolds          db '&golds./'
                db 0FFh
                db    0
unk_B11F        db  0Ch
aAllOfMyGoodsAr db 'All of my goods are of the highest quality. Which item would you '
                db 'like me to tell you about?/'
                db 0FFh
                db    6
unk_B17E        db  0Ch
aWhichItemWould db 'Which item would you like to know about?/'
                db 0FFh
aIsThereAnother db 'Is there another item you would like to know about?/'
                db 0FFh
unk_B1DE        db  0Ch
aThankYouPlease db 'Thank you, please come again.'
                db  11h
                db 0FFh
                db 0FFh
unk_B1FF        db  0Ch
aIfYouReGoingTo db 'If you\re going to waste my time, please be on your way./'
                db 0FFh
                db    7
                db 0FFh
                db    3
                db  11h
                db 0FFh
                db 0FFh
unk_B240        db  0Ch
aUh             db 'Uh....../'
                db 0FFh
                db    0
unk_B24C        db  0Ch
aIDoNotSellThat db 'I do not sell that weapon. I haven\t a single one in stock. Pleas'
                db 'e choose another./'
                db 0FFh
                db    0
unk_B2A2        db  0Ch
aWellILlBe      db 'Well I\ll be... '
                db 0FFh
                db    4
                db 0FFh
                db    4
aSir            db 'Sir! '
                db 0FFh
                db    9
                db 0FFh
                db    4
aIsnTThatTheCre db 'Isn\t that the crest of honor you bear? Please come in... I mean.'
                db '..uh... /Might I trade you a knight\s sword for it?'
                db 0FFh
                db    8
unk_B336        db  0Ch
aOhISeeWellIfYo db 'Oh, I&see. Well, if you change your mind, please come back.'
                db  11h
                db 0FFh
                db 0FFh
unk_B375        db  0Ch
aOhThankYouSirA db 'Oh, thank you, sir! As promised, here is your knight\s sword./'
                db 0FFh
                db    0
aThankYouAndPle db 'Thank you, and please come back soon.'
                db  11h
                db 0FFh
                db 0FFh
off_B3DE        dw offset aWellIDSayThisS ; "Well, I\\d say this sword is all right "...
                dw offset aThisOneIsJustA ; "This one is just a bit better than the "...
                dw offset aYouLikeThisOne ; "You like this one?/A wise choice./This "...
                dw offset aOhIDBeMoreThan ; "Oh, I\\d be more than happy to tell you"...
                dw offset aYouVeGotALotOf ; "You\\ve got a lot of grit I\\d say. Thi"...
                dw offset aIsnTThatTheSwo ; "Isn\\t that the sword you brought in wi"...
                dw offset aThisShieldIsSm ; "This shield is small and has limited de"...
                dw offset aWellItSSlightl ; "Well, it\\s slightly better than the Cl"...
                dw offset aThisOneIsMoreO ; "This one is more of a general-use shiel"...
                dw offset aThisShieldIsIn ; "This shield is in a class by itself. It"...
                dw offset aHoYouVeGotQuit ; "Ho! You\\ve got quite an eye for these "...
                dw offset aThisShieldMake ; "This shield makes the mightiest swords "...
aWellIDSayThisS db 'Well, I\d say this sword is all right for a beginner./You get wha'
                db 't you pay for./It\s your standard, maintenance-free sword. If mon'
                db 'ey\s a problem, this one\s for you.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisOneIsJustA db 'This one is just a bit better than the Training Sword. Once you g'
                db 'et the hang of it, it\s an easy one to wield. The price is a bit '
                db 'higher, but you can\t lose on this one./Why not take it with you?'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aYouLikeThisOne db 'You like this one?/A wise choice./This is a high grade product. I'
                db 't\s one of my biggest sellers.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aOhIDBeMoreThan db 'Oh, I\d be more than happy to tell you about this one./This is a '
                db 'real man\s sword. It\ll topple monsters in the wink of an eye.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aYouVeGotALotOf db 'You\ve got a lot of grit I\d say. This one really packs a punch. '
                db 'A top-of-the-line sword for a top-of-the-line-swordsman. Will you'
                db ' take it?'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aIsnTThatTheSwo db 'Isn\t that the sword you brought in with you?'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisShieldIsSm db 'This shield is small and has limited defense capability. It\s not'
                db ' very durable -- unless it\s used with great skill, it won\t last'
                db ' long. It\s better than nothing, I guess.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aWellItSSlightl db 'Well, it\s slightly better than the Clay Shield. Long ago, a well'
                db '-known hero used it for a short time. You could do a lot worse.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisOneIsMoreO db 'This one is more of a general-use shield. It\s not the best one I'
                db ' carry. I can\t really recommend it, I think it will soon be obso'
                db 'lete.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisShieldIsIn db 'This shield is in a class by itself. It is strong and light and e'
                db 'asy to use. This is a superior shield, the least a brave man shou'
                db 'ld have.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aHoYouVeGotQuit db 'Ho! You\ve got quite an eye for these things, I see. This shield '
                db 'is not made of common iron. It is made of a magic metal called Ma'
                db 'gane. Against ordinary weapons, it\s unbreakable.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisShieldMake db 'This shield makes the mightiest swords seem like paper. It\s ligh'
                db 't as a feather and hard as a diamond. Used well, this one will la'
                db 'st you a lifetime.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
prices_by_town  dw offset muralla_prices
                dw offset satono_prices
                dw offset bosque_prices
                dw offset hellada_prices
                dw offset tumba_prices
                dw offset dorado_prices
                dw offset llama_prices
                dw offset pureza_prices
                dw offset esco_prices
muralla_prices  db 0
                dw 400
                db 0
                dw 1500
                db 0
                dw 6800
                db 0
                dw 9800
                db 1, 90h, 5Fh          ; 15f90h=90000
                db 0
                dw 4
                db 0
                dw 50
                db 0
                dw 150
                db 0
                dw 2980
                db 0
                dw 9800
                db 0
                dw 14800
                db 0
                dw 39800
satono_prices   db 0
                dw 800
                db 0
                dw 1500
                db 0
                dw 6800
                db 0
                dw 9800
                db 1, 0A8h, 10h         ; 110a8h=69800
                db 0
                dw 4
                db 0
                dw 50
                db 0
                dw 150
                db 0
                dw 2980
                db 0
                dw 9800
                db 0
                dw 14800
                db 0
                dw 39800
bosque_prices   db 0
                dw 800
                db 0
                dw 1500
                db 0
                dw 6800
                db 0
                dw 9800
                db 1, 0A8h, 10h         ; 110a8h=69800
                db 0
                dw 4
                db 0
                dw 5
                db 0
                dw 150
                db 0
                dw 2380
                db 0
                dw 9800
                db 0
                dw 14800
                db 0
                dw 39800
hellada_prices  db 0
                dw 400
                db 0
                dw 3000
                db 0
                dw 5440
                db 0
                dw 9800
                db 1, 0A8h, 10h         ; 110a8h=69800
                db 0
                dw 4
                db 0
                dw 5
                db 0
                dw 50
                db 0
                dw 1780
                db 0
                dw 9800
                db 0
                dw 14800
                db 0
                dw 39800
tumba_prices    db 0
                dw 400
                db 0
                dw 3000
                db 0
                dw 4760
                db 0
                dw 4900
                db 1, 0A8h, 10h         ; 110a8h=69800
                db 0
                dw 4
                db 0
                dw 5
                db 0
                dw 50
                db 0
                dw 1780
                db 0
                dw 7840
                db 0
                dw 14800
                db 0
                dw 39800
dorado_prices   db 0
                dw 200
                db 0
                dw 1500
                db 0
                dw 3400
                db 0
                dw 7840
                db 1, 0A8h, 10h         ; 110a8h=69800
                db 0
                dw 4
                db 0
                dw 5
                db 0
                dw 20
                db 0
                dw 890
                db 0
                dw 5880
                db 0
                dw 14800
                db 0
                dw 39800
llama_prices    db 0
                dw 200
                db 0
                dw 1500
                db 0
                dw 1360
                db 0
                dw 5880
                db 0
                dw 34800
                db 0
                dw 4
                db 0
                dw 5
                db 0
                dw 20
                db 0
                dw 890
                db 0
                dw 5880
                db 0
                dw 10360
                db 0
                dw 39800
pureza_prices   db 0
                dw 100
                db 0
                dw 1000
                db 0
                dw 1360
                db 0
                dw 3920
                db 0
                dw 32800
                db 0
                dw 4
                db 0
                dw 5
                db 0
                dw 20
                db 0
                dw 890
                db 0
                dw 3920
                db 0
                dw 7400
                db 0
                dw 31800
esco_prices     db 0
                dw 10
                db 0
                dw 100
                db 0
                dw 680
                db 0
                dw 1960
                db 0
                dw 29800
                db 0
                dw 4
                db 0
                dw 2
                db 0
                dw 10
                db 0
                dw 298
                db 0
                dw 1960
                db 0
                dw 5920
                db 0
                dw 23800
byte_BBFD       db 0
word_BBFE       dw 0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
byte_BC0F       db 0
word_BC10       dw 0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
byte_BC21       db 0
unk_BC22        db    0
unk_BC23        db    0
unk_BC24        db    0
unk_BC25        db    0
unk_BC26        db    0
unk_BC27        db    0
unk_BC28        db    0
unk_BC29        db    0
unk_BC2A        db    0
                db    0
unk_BC2C        db    0
unk_BC2D        db    0
                db    0
unk_BC2F        db    0
unk_BC30        db    0
byte_BC31       db 0
unk_BC32        db    0
unk_BC33        db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
unk_BC3B        db    0
                db    0
                db    0
                db    0
                db    0
                db    0
byte_BC41       db 0
                db    0
                db    0
                db    0
                db    0
                db    0

armpro          ends
                end     start
