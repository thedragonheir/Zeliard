include common.inc
include town.inc

                .286
                .model small

bankpro         segment byte public 'CODE'
                assume cs:bankpro, ds:bankpro
                org 0A000h
start:
                dw offset sub_A004
                dw offset sub_A728

; =============== S U B R O U T I N E =======================================


sub_A004        proc near
                mov     es, word ptr ds:seg1
                mov     di, 8000h
                mov     si, offset vfs_bank_grp
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
                mov     byte_AD1E, 0
                call    word ptr cs:Clear_Viewport_proc
                call    word ptr cs:Clear_Place_Enemy_Bar_proc
                mov     si, offset byte_A8EE
                call    word ptr cs:Render_Pascal_String_1_proc
                call    sub_A6A3
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte_AD21, 0FFh
                mov     word_AD1F, offset byte_A773
                mov     word ptr ds:dialog_string_ptr, offset unk_A989
                call    word ptr cs:render_menu_dialog_proc
                mov     cx, 5

loc_A071:
                push    cx
                mov     byte ptr ds:frame_timer, 0
                mov     word ptr ds:dialog_string_ptr, offset unk_A98B
                call    word ptr cs:render_menu_dialog_proc

loc_A082:
                call    sub_A728
                cmp     byte ptr ds:frame_timer, 63
                jb      short loc_A082
                pop     cx
                loop    loc_A071
                mov     byte_AD21, 0
                mov     word ptr ds:dialog_string_ptr, offset aOhExcuseMe

loc_A09A:
                call    word ptr cs:render_menu_dialog_proc
                cmp     al, 0FFh
                jz      short loc_A0A8
                call    sub_A0AD
                jmp     short loc_A09A
; ---------------------------------------------------------------------------

loc_A0A8:
                jmp     word ptr cs:Fade_To_Black_Dithered_proc
sub_A004        endp


; =============== S U B R O U T I N E =======================================


sub_A0AD        proc near

                mov     bl, al
                xor     bh, bh
                add     bx, bx          ; switch 4 cases
                jmp     cs:jpt_A0B3[bx] ; switch jump
sub_A0AD        endp

; ---------------------------------------------------------------------------
jpt_A0B3        dw offset loc_A0C0      ; jump table for switch statement
                dw offset loc_A0D2
                dw offset loc_A5F3
                dw offset loc_A619
; ---------------------------------------------------------------------------

loc_A0C0:
                mov     byte ptr ds:frame_timer, 0

loc_A0C5:
                cmp     byte ptr ds:frame_timer, 60
                jb      short loc_A0C5
                mov     si, offset off_A82F
                jmp     sub_A813
; ---------------------------------------------------------------------------

loc_A0D2:                               ; jumptable 0000A0B3 case 1
                call    sub_A61F
                mov     bx, 281Dh
                mov     cx, 1A37h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 2820h
                mov     byte ptr ds:menu_item_count, 5
                mov     byte ptr ds:menu_max_items, 5
                mov     cx, 5
                mov     si, offset aGoOutside ; "Go outside"
                call    word ptr cs:render_menu_string_list_proc
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     bl, byte_AD1E
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A10F
                xor     bl, bl

loc_A10F:
                mov     byte_AD1E, bl
                xor     bh, bh
                add     bx, bx          ; switch 5 cases
                jmp     jpt_A117[bx]    ; switch jump
; ---------------------------------------------------------------------------
jpt_A117        dw offset on_go_outside_bank      ; jump table for switch statement
                dw offset on_exchange_almas
                dw offset on_deposit_money
                dw offset on_withdraw_money
                dw offset on_check_balance
; ---------------------------------------------------------------------------

on_go_outside_bank:                               ; jumptable 0000A117 case 0
                call    sub_A61F
                mov     word ptr ds:dialog_string_ptr, offset unk_ACD4 ; 'Thank you. Come again to make a deposit for a large sum in savings. '
                test    byte_AD24, 0FFh
                jz      short loc_A136
                retn
; ---------------------------------------------------------------------------

loc_A136:
                mov     word ptr ds:dialog_string_ptr, offset unk_AC9D ; 'Next time please deposit a large sum in savings. '
                test    byte_AD23, 0FFh
                jz      short loc_A144
                retn
; ---------------------------------------------------------------------------

loc_A144:
                mov     word ptr ds:dialog_string_ptr, offset unk_AC5A ; 'Unless you have business, don\t come in here. I\m a busy man.'
                retn
; ---------------------------------------------------------------------------

on_exchange_almas:                               ; jumptable 0000A117 case 1
                call    sub_A61F
                mov     byte_AD21, 0
                mov     si, offset byte_A8BB
                call    loc_A751
                test    word ptr ds:hero_almas, 0FFFFh
                mov     word ptr ds:dialog_string_ptr, offset unk_A9B2
                jnz     short loc_A168
                retn
; ---------------------------------------------------------------------------

loc_A168:
                mov     bl, ds:town_id
                xor     bh, bh
                dec     bl
                add     bx, bx
                mov     al, byte ptr almas_exchange_rates_by_town[bx]
                mov     byte_AD25, al
                mov     al, byte ptr (almas_exchange_rates_by_town+1)[bx]
                mov     byte_AD26, al
                mov     word ptr ds:dialog_string_ptr, offset unk_A9D9
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte_AD25
                add     al, 30h ; '0'
                mov     byte_AD27, al
                mov     word ptr ds:dialog_string_ptr, offset byte_AD27
                call    word ptr cs:render_menu_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset aAlmasTo
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte_AD26
                add     al, 30h ; '0'
                mov     byte_AD27, al
                mov     word ptr ds:dialog_string_ptr, offset byte_AD27
                call    word ptr cs:render_menu_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset aGoldsWillThatB
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_AA48
                jnb     short loc_A1E8
                retn
; ---------------------------------------------------------------------------

loc_A1E8:
                mov     ax, ds:hero_almas
                mov     dl, byte_AD25
                xor     dh, dh
                sub     ax, dx
                mov     word ptr ds:dialog_string_ptr, offset unk_AA1D
                jnb     short loc_A1FC
                retn
; ---------------------------------------------------------------------------

loc_A1FC:
                push    dx
                call    sub_A61F
                pop     dx
                mov     byte_AD23, 0FFh
                mov     word ptr ds:dialog_string_ptr, offset unk_AA82 ; 'Will there be anything else?'

loc_A20C:
                xor     cx, cx

loc_A20E:
                mov     ax, ds:hero_almas
                sub     ax, dx
                jnb     short loc_A216
                retn
; ---------------------------------------------------------------------------

loc_A216:
                push    cx
                mov     ds:hero_almas, ax
                push    dx
                xor     dl, dl
                mov     al, byte_AD26
                xor     ah, ah
                call    word ptr cs:add_gold_to_hero_proc
                call    word ptr cs:Print_Gold_Decimal_proc
                call    word ptr cs:Print_Almas_Decimal_proc
                pop     dx
                pop     cx
                inc     cx
                and     cx, 7
                jnz     short loc_A20E
                jmp     short loc_A20C
; ---------------------------------------------------------------------------

on_deposit_money:                               ; jumptable 0000A117 case 2
                call    sub_A61F
                mov     byte_AD21, 0
                mov     si, offset byte_A8BB
                call    loc_A751
                mov     word ptr ds:dialog_string_ptr, offset unk_AAA1
                mov     ax, ds:hero_gold_lo
                mov     dl, ds:hero_gold_hi
                or      dl, al
                or      dl, ah
                jnz     short loc_A25D
                retn
; ---------------------------------------------------------------------------

loc_A25D:
                mov     word ptr ds:dialog_string_ptr, offset unk_AACA
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2C1Dh
                mov     cx, 1237h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 2A20h
                mov     byte ptr ds:menu_item_count, 4
                mov     byte ptr ds:menu_max_items, 4
                mov     byte ptr ds:menu_digits_render_flag, 0
                mov     cx, 4
                mov     si, offset aGoldCarried ; "GOLD CARRIED"
                call    word ptr cs:render_menu_string_list_proc
                mov     byte_AD29, 0
                mov     word_AD2A, 0
                mov     dl, ds:hero_gold_hi
                mov     ax, ds:hero_gold_lo
                mov     byte_AD2C, dl
                mov     word_AD2D, ax

loc_A2AE:
                mov     dl, byte_AD29
                mov     ax, word_AD2A
                push    dx
                push    ax
                call    word ptr cs:check_gold_sufficient_proc
                call    word ptr cs:render_numeric_score_proc
                mov     bx, 312Eh
                call    word ptr cs:draw_string_buffer_to_screen_proc
                pop     ax
                pop     dx
                call    word ptr cs:render_numeric_score_proc
                mov     bx, 3148h
                call    word ptr cs:draw_string_buffer_to_screen_proc
                int     61h             ; check input keys buffer
                                        ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                call    update_24bit_value_according_to_al_flags
                test    ah, 1
                jnz     short loc_A31B
                mov     word ptr ds:dialog_string_ptr, offset unk_AA48
                test    ah, 2
                jz      short loc_A2EE
                retn
; ---------------------------------------------------------------------------

loc_A2EE:
                or      al, al
                jnz     short loc_A2F9
                mov     byte ptr unk_AD2F, 23h ; '#'
                jmp     short loc_A2AE
; ---------------------------------------------------------------------------

loc_A2F9:
                mov     byte ptr ds:frame_timer, 0

loc_A2FE:
                int     61h             ; check input keys buffer
                                        ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                or      al, al
                jz      short loc_A2AE
                mov     al, byte ptr unk_AD2F
                cmp     ds:frame_timer, al
                jb      short loc_A2FE
                sub     byte ptr unk_AD2F, 1
                jnb     short loc_A2AE
                mov     byte ptr unk_AD2F, 1
                jmp     short loc_A2AE
; ---------------------------------------------------------------------------

loc_A31B:
                mov     word ptr ds:dialog_string_ptr, offset unk_AA48
                mov     ax, word_AD2A
                mov     dl, byte_AD29
                mov     cl, dl
                or      cl, al
                or      cl, ah
                jnz     short loc_A331
                retn
; ---------------------------------------------------------------------------

loc_A331:
                or      dl, dl           ; deposit amount high byte
                jnz     short loc_A33A   ; if high byte != 0 => laugh
                cmp     ax, 1000         ; low word of deposit amount
                jb      short loc_A345   ; if < 1000 => no laugh

loc_A33A:
                mov     byte_AD21, 0FFh  ; enable animation
                mov     word_AD1F, offset byte_A7C3 ; laughing tile set

loc_A345:
                add     ds:bank_gold_lo, ax
                adc     ds:bank_gold_hi, dl
                mov     dl, byte_AD29
                mov     ax, word_AD2A
                call    word ptr cs:check_gold_sufficient_proc
                mov     ds:hero_gold_hi, dl
                mov     ds:hero_gold_lo, ax
                call    word ptr cs:Print_Gold_Decimal_proc
                mov     byte_AD23, 0FFh
                test    byte_AD21, 0FFh
                jnz     short loc_A3C9
                mov     word ptr ds:dialog_string_ptr, offset unk_ABF7
                mov     dl, ds:bank_gold_hi
                mov     ax, ds:bank_gold_lo
                or      dl, ah
                or      dl, al
                jnz     short loc_A385
                retn
; ---------------------------------------------------------------------------

loc_A385:
                mov     word ptr ds:dialog_string_ptr, offset unk_AC35
                test    ds:bank_gold_hi, al
                jnz     short loc_A399
                cmp     word ptr ds:bank_gold_lo, 1
                jnz     short loc_A399
                retn
; ---------------------------------------------------------------------------

loc_A399:
                mov     word ptr ds:dialog_string_ptr, offset unk_AAF4
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, ds:bank_gold_hi
                mov     ax, ds:bank_gold_lo
                mov     di, offset unk_AD30
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_AD30
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                retn
; ---------------------------------------------------------------------------

loc_A3C9:
                mov     word ptr ds:dialog_string_ptr, offset unk_AB10
                retn
; ---------------------------------------------------------------------------

on_withdraw_money:                               ; jumptable 0000A117 case 3
                call    sub_A61F
                mov     byte_AD21, 0
                mov     si, offset byte_A8BB
                call    loc_A751
                mov     word ptr ds:dialog_string_ptr, offset unk_AB32
                mov     ax, ds:bank_gold_lo
                mov     dl, ds:bank_gold_hi
                or      dl, al
                or      dl, ah
                jnz     short loc_A3F2
                retn
; ---------------------------------------------------------------------------

loc_A3F2:
                mov     word ptr ds:dialog_string_ptr, offset unk_AB80
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2C1Dh
                mov     cx, 1237h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 2A20h
                mov     byte ptr ds:menu_item_count, 4
                mov     byte ptr ds:menu_max_items, 4
                mov     byte ptr ds:menu_digits_render_flag, 0
                mov     cx, 4
                mov     si, offset aGoldInBank ; "GOLD IN BANK"
                call    word ptr cs:render_menu_string_list_proc
                mov     byte_AD29, 0
                mov     word_AD2A, 0
                mov     dl, ds:bank_gold_hi
                mov     ax, ds:bank_gold_lo
                mov     byte_AD2C, dl
                mov     word_AD2D, ax

loc_A443:
                mov     dl, byte_AD29
                mov     ax, word_AD2A
                push    dx
                push    ax
                mov     cl, ds:bank_gold_hi
                mov     bx, ds:bank_gold_lo
                sub     bx, ax
                sbb     cl, dl
                xchg    ax, bx
                xchg    dl, cl
                call    word ptr cs:render_numeric_score_proc
                mov     bx, 312Eh
                call    word ptr cs:draw_string_buffer_to_screen_proc
                pop     ax
                pop     dx
                call    word ptr cs:render_numeric_score_proc
                mov     bx, 3148h
                call    word ptr cs:draw_string_buffer_to_screen_proc
                int     61h             ; check input keys buffer
                                        ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                call    update_24bit_value_according_to_al_flags
                test    ah, 1
                jnz     short loc_A4BA
                mov     word ptr ds:dialog_string_ptr, offset unk_AA48
                test    ah, 2
                jz      short loc_A48D
                retn
; ---------------------------------------------------------------------------

loc_A48D:
                or      al, al
                jnz     short loc_A498
                mov     byte ptr unk_AD2F, 23h ; '#'
                jmp     short loc_A443
; ---------------------------------------------------------------------------

loc_A498:
                mov     byte ptr ds:frame_timer, 0

loc_A49D:
                int     61h             ; check input keys buffer
                                        ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                or      al, al
                jz      short loc_A443
                mov     al, byte ptr unk_AD2F
                cmp     ds:frame_timer, al
                jb      short loc_A49D
                sub     byte ptr unk_AD2F, 1
                jnb     short loc_A443
                mov     byte ptr unk_AD2F, 1
                jmp     short loc_A443
; ---------------------------------------------------------------------------

loc_A4BA:
                mov     word ptr ds:dialog_string_ptr, offset unk_AA48
                mov     ax, word_AD2A
                mov     dl, byte_AD29
                mov     cl, dl
                or      cl, al
                or      cl, ah
                jnz     short loc_A4D0
                retn
; ---------------------------------------------------------------------------

loc_A4D0:
                mov     byte_AD23, 0FFh
                mov     word ptr ds:dialog_string_ptr, offset aHereYouAreSirO
                mov     dl, byte_AD29
                mov     ax, word_AD2A
                or      dl, dl
                jnz     short loc_A4EB
                cmp     ax, 1
                jz      short loc_A51A

loc_A4EB:
                mov     word ptr ds:dialog_string_ptr, offset aHereYouAreSir
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, byte_AD29
                mov     ax, word_AD2A
                mov     di, offset unk_AD30
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_AD30
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si

loc_A51A:
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, ds:bank_gold_hi
                mov     ax, ds:bank_gold_lo
                sub     ax, word_AD2A
                sbb     dl, byte_AD29
                mov     ds:bank_gold_hi, dl
                mov     ds:bank_gold_lo, ax
                mov     word ptr ds:dialog_string_ptr, offset unk_ABDE
                or      dl, ah
                or      dl, al
                jz      short loc_A584
                mov     word ptr ds:dialog_string_ptr, offset unk_AC35
                test    ds:bank_gold_hi, al
                jnz     short loc_A555
                cmp     word ptr ds:bank_gold_lo, 1
                jnz     short loc_A555
                retn
; ---------------------------------------------------------------------------

loc_A555:
                mov     word ptr ds:dialog_string_ptr, offset unk_AAF4
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, ds:bank_gold_hi
                mov     ax, ds:bank_gold_lo
                mov     di, offset unk_AD30
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_AD30
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si

loc_A584:
                mov     dl, byte_AD29
                mov     ax, word_AD2A
                call    word ptr cs:add_gold_to_hero_proc
                jmp     word ptr cs:Print_Gold_Decimal_proc
; ---------------------------------------------------------------------------

on_check_balance:                               ; jumptable 0000A117 case 4
                call    sub_A61F
                mov     word ptr ds:dialog_string_ptr, offset unk_ABF7
                mov     al, ds:bank_gold_hi
                xor     ah, ah
                or      ax, ds:bank_gold_lo
                jnz     short loc_A5AA
                retn
; ---------------------------------------------------------------------------

loc_A5AA:
                mov     byte_AD23, 0FFh
                mov     word ptr ds:dialog_string_ptr, offset unk_AC35
                test    ds:bank_gold_hi, al
                jnz     short loc_A5C3
                cmp     word ptr ds:bank_gold_lo, 1
                jnz     short loc_A5C3
                retn
; ---------------------------------------------------------------------------

loc_A5C3:
                mov     word ptr ds:dialog_string_ptr, offset unk_AC10
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, ds:bank_gold_hi
                mov     ax, ds:bank_gold_lo
                mov     di, offset unk_AD30
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_AD30
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                retn
; ---------------------------------------------------------------------------

loc_A5F3:                               ; jumptable 0000A0B3 case 2
                mov     byte_AD21, 0
                mov     si, offset off_A839
                call    sub_A813
                mov     byte_AD21, 0FFh
                mov     word_AD1F, offset byte_A773
                mov     byte ptr ds:frame_timer, 0

loc_A60E:
                call    sub_A728
                cmp     byte ptr ds:frame_timer, 100
                jb      short loc_A60E
                retn
; ---------------------------------------------------------------------------

loc_A619:                               ; jumptable 0000A0B3 case 3
                mov     byte_AD24, 0FFh
                retn

; =============== S U B R O U T I N E =======================================


sub_A61F        proc near
                mov     bx, 2717h
                mov     cx, 1C41h
                xor     al, al
                jmp     word ptr cs:Draw_Bordered_Rectangle_proc
sub_A61F        endp


; =============== S U B R O U T I N E =======================================


update_24bit_value_according_to_al_flags proc near
                mov     dl, byte_AD29
                mov     bx, word_AD2A
                test    al, 8
                jz      short loc_A646
                sub     bx, 10
                sbb     dl, 0
                jnb     short loc_A69A
                xor     bx, bx
                xor     dl, dl
                jmp     short loc_A69A
; ---------------------------------------------------------------------------

loc_A646:
                test    al, 4
                jz      short loc_A668
                add     bx, 10
                adc     dl, 0
                mov     cx, bx
                sub     cx, word_AD2D
                mov     cl, dl
                sbb     cl, byte_AD2C
                jb      short loc_A69A
                mov     dl, byte_AD2C
                mov     bx, word_AD2D
                jmp     short loc_A69A
; ---------------------------------------------------------------------------

loc_A668:
                test    al, 2
                jz      short loc_A67A
                sub     bx, 1
                sbb     dl, 0
                jnb     short loc_A69A
                xor     bx, bx
                xor     dl, dl
                jmp     short loc_A69A
; ---------------------------------------------------------------------------

loc_A67A:
                test    al, 1
                jz      short loc_A69A
                add     bx, 1
                adc     dl, 0
                mov     cx, bx
                sub     cx, word_AD2D
                mov     cl, dl
                sbb     cl, byte_AD2C
                jb      short loc_A69A
                mov     dl, byte_AD2C
                mov     bx, word_AD2D

loc_A69A:
                mov     byte_AD29, dl
                mov     word_AD2A, bx
                retn
update_24bit_value_according_to_al_flags endp


; =============== S U B R O U T I N E =======================================


sub_A6A3        proc near
                mov     si, offset byte_A6C8
                mov     bx, 717h
                mov     cx, 8

loc_A6AC:
                push    cx
                mov     cx, 12

loc_A6B0:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A6B0
                sub     bh, 12
                add     bl, 8
                pop     cx
                loop    loc_A6AC
                retn
sub_A6A3        endp

; ---------------------------------------------------------------------------
byte_A6C8       db 6Ch, 6Dh, 6Eh, 6Fh, 70h, 71h, 72h, 73h, 74h, 75h, 76h, 77h
                db 78h, 79h, 0, 1, 2, 3, 4, 5, 6, 7, 7Ah, 7Bh
                db 7Ch, 7Dh, 8, 9, 0Ah, 0Bh, 0Ch, 0Dh, 0Eh, 0Fh, 7Eh, 7Fh
                db 80h, 81h, 10h, 11h, 12h, 13h, 14h, 15h, 16h, 17h, 82h, 83h
                db 84h, 85h, 18h, 19h, 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 86h, 87h
                db 88h, 89h, 20h, 21h, 22h, 23h, 24h, 25h, 26h, 27h, 8Ah, 8Bh
                db 8Ch, 8Dh, 8Eh, 8Fh, 90h, 91h, 92h, 93h, 94h, 95h, 96h, 97h
                db 98h, 99h, 9Ah, 9Bh, 9Ch, 9Dh, 9Eh, 9Fh, 0A0h, 0A1h, 0A2h, 0A3h

; =============== S U B R O U T I N E =======================================


sub_A728        proc near
                test    byte_AD21, 0FFh
                jnz     short loc_A730
                retn
; ---------------------------------------------------------------------------

loc_A730:
                cmp     word ptr ds:tick_counter, 30
                jnb     short loc_A738
                retn
; ---------------------------------------------------------------------------

loc_A738:
                mov     word ptr ds:tick_counter, 0
                inc     byte ptr unk_AD22
                mov     al, byte ptr unk_AD22
                and     al, 1
                mov     cl, 40
                mul     cl
                mov     si, ax
                add     si, word_AD1F

loc_A751:
                mov     bx, 91Fh
                mov     cx, 5

loc_A757:
                push    cx
                mov     cx, 8

loc_A75B:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A75B
                sub     bh, 8
                add     bl, 8
                pop     cx
                loop    loc_A757
                retn
sub_A728        endp

; ---------------------------------------------------------------------------
byte_A773       db 0, 1, 2, 3, 4, 5, 6, 7
                db 8, 9, 0Ah, 0Bh, 0Ch, 0Dh, 0Eh, 0Fh
                db 10h, 11h, 12h, 13h, 14h, 15h, 16h, 17h
                db 18h, 19h, 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh
                db 20h, 21h, 22h, 23h, 24h, 25h, 26h, 27h
                db 0, 1, 2, 3, 4, 5, 6, 7
                db 8, 9, 0Ah, 0Bh, 0Ch, 0Dh, 0Eh, 0Fh
                db 28h, 29h, 12h, 13h, 14h, 15h, 16h, 17h
                db 2Ah, 2Bh, 2Ch, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh
                db 20h, 2Dh, 2Eh, 23h, 24h, 25h, 26h, 27h
byte_A7C3       db 0, 1, 2, 3, 4, 5, 6, 7
                db 8, 9, 41h, 42h, 43h, 44h, 45h, 0Fh
                db 10h, 11h, 46h, 4Dh, 4Eh, 49h, 4Ah, 39h
                db 18h, 19h, 1Ah, 4Fh, 50h, 51h, 4Ch, 3Dh
                db 20h, 21h, 22h, 52h, 53h, 3Eh, 3Fh, 40h
                db 0, 1, 54h, 55h, 56h, 5, 6, 7
                db 8, 9, 57h, 58h, 59h, 5Ah, 5Bh, 0Fh
                db 10h, 5Ch, 5Dh, 5Eh, 5Fh, 60h, 61h, 17h
                db 18h, 19h, 62h, 63h, 64h, 65h, 66h, 67h
                db 20h, 21h, 22h, 68h, 69h, 3Eh, 6Ah, 6Bh

; =============== S U B R O U T I N E =======================================


sub_A813        proc near
                mov     byte ptr ds:frame_timer, 0
                lodsw
                cmp     ax, 0FFFFh
                jnz     short loc_A81F
                retn
; ---------------------------------------------------------------------------

loc_A81F:
                push    si
                mov     si, ax
                call    loc_A751

loc_A825:
                cmp     byte ptr ds:frame_timer, 40
                jb      short loc_A825
                pop     si
                jmp     short sub_A813
sub_A813        endp

; ---------------------------------------------------------------------------
off_A82F        dw offset byte_A843
                dw offset byte_A86B
                dw offset byte_A893
                dw offset byte_A8BB
                dw 0FFFFh
off_A839        dw offset byte_A8BB
                dw offset byte_A893
                dw offset byte_A86B
                dw offset byte_A843
                dw 0FFFFh
byte_A843       db 0, 1, 2, 3, 4, 5, 6, 7
                db 8, 9, 0Ah, 0Bh, 0Ch, 0Dh, 0Eh, 0Fh
                db 10h, 11h, 12h, 13h, 14h, 15h, 16h, 17h
                db 18h, 19h, 1Ah, 2Fh, 30h, 1Dh, 1Eh, 1Fh
                db 20h, 21h, 22h, 23h, 24h, 25h, 26h, 27h
byte_A86B       db 0, 1, 2, 3, 4, 5, 6, 7
                db 8, 9, 0Ah, 0Bh, 0Ch, 0Dh, 0Eh, 0Fh
                db 10h, 11h, 12h, 13h, 14h, 15h, 16h, 17h
                db 18h, 19h, 1Ah, 2Fh, 30h, 1Dh, 1Eh, 1Fh
                db 20h, 21h, 22h, 23h, 31h, 32h, 33h, 27h
byte_A893       db 0, 1, 2, 3, 4, 5, 6, 7
                db 8, 9, 0Ah, 0Bh, 34h, 35h, 0Eh, 0Fh
                db 10h, 11h, 12h, 13h, 36h, 37h, 38h, 39h
                db 18h, 19h, 1Ah, 2Fh, 3Ah, 3Bh, 3Ch, 3Dh
                db 20h, 21h, 22h, 23h, 24h, 3Eh, 3Fh, 40h
byte_A8BB       db 0, 1, 2, 3, 4, 5, 6, 7
                db 8, 9, 41h, 42h, 43h, 44h, 45h, 0Fh
                db 10h, 11h, 46h, 47h, 48h, 49h, 4Ah, 39h
                db 18h, 19h, 1Ah, 2Fh, 30h, 4Bh, 4Ch, 3Dh
                db 20h, 21h, 22h, 23h, 24h, 3Eh, 3Fh, 40h
vfs_bank_grp    db 1
                db 16h
aBankGrp        db 'BANK.GRP',0
byte_A8EE       db 18h
                db 0AFh
                db 2
aTheBank        db 8,'The Bank'
almas_exchange_rates_by_town dw 601h, 601h, 801h, 401h, 201h, 401h, 204h, 601h
                dw 801h
aGoOutside      db 'Go outside',0
aExchangeAlmas  db 'Exchange almas',0
aDepositMoney   db 'Deposit money',0
aWithdrawMoney  db 'Withdraw money',0
aCheckBalance   db 'Check balance',0
aGoldCarried    db 'GOLD CARRIED',0
                db    0
                db    0
aDepositAmt     db ' DEPOSIT AMT',0
aGoldInBank     db 'GOLD IN BANK',0
                db    0
                db    0
aWithdrawAmt    db 'WITHDRAW AMT',0
unk_A989        db  0Ch
                db 0FFh
unk_A98B        db  2Eh ; .
                db 0FFh
aOhExcuseMe     db 'Oh, excuse me. '
                db 0FFh
                db    0
aCanIHelpYou    db 'Can I help you?/'
                db 0FFh
                db    1
                db 0FFh
                db 0FFh
unk_A9B2        db  0Ch
aSirYouArenTCar db 'Sir, you aren\t carrying any almas. '
                db 0FFh
                db    1
unk_A9D9        db  0Ch
aOurExchangeRat db 'Our exchange rate is '
                db 0FFh
                db    0
aAlmasTo        db '&almas to '
                db 0FFh
                db    0
aGoldsWillThatB db '&golds./Will that be all right?'
                db 0FFh
unk_AA1D        db  0Ch
aIMSorryYouDoNo db 'I\m sorry, you do not have enough almas.'
                db 0FFh
                db    1
unk_AA48        db  0Ch
aIDonTUnderstan db 'I don\t understand. Please state your business clearly.'
                db 0FFh
                db    1
unk_AA82        db  0Ch
aWillThereBeAny db 'Will there be anything else?'
                db 0FFh
                db    1
unk_AAA1        db  0Ch
aYouArenTCarryi db 'You aren\t carrying any gold, are you?'
                db 0FFh
                db    1
unk_AACA        db  0Ch
aHowMuchGoldWou db 'How much gold would you like to deposit?'
                db 0FFh
unk_AAF4        db  0Dh
aYourBalanceIs  db 'Your balance is '
                db 0FFh
                db    0
aGolds_0        db '&golds.'
                db 0FFh
                db    1
unk_AB10        db  0Ch
aThankYouPlease db 'Thank you. Please come again.'
                db 0FFh
                db    3
                db 0FFh
                db    1
unk_AB32        db  0Ch
aIMAfraidWeHave db 'I\m afraid we have a problem here. You don\t have any gold in you'
                db 'r account.'
                db 0FFh
                db    1
unk_AB80        db  0Ch
aHowMuchDoYouWi db 'How much do you wish to withdraw?/'
                db 0FFh
aHereYouAreSir  db 'Here you are, sir. '
                db 0FFh
                db    0
aGolds          db '&golds.'
                db 0FFh
aHereYouAreSirO db 'Here you are, sir. One gold.'
                db 0FFh
unk_ABDE        db  0Dh
aYourAccountIsE_0 db 'Your account is empty.'
                db 0FFh
                db    1
unk_ABF7        db  0Ch
aYourAccountIsE db 'Your account is empty.'
                db 0FFh
                db    1
unk_AC10        db  0Ch
aYouHave        db 'You have '
                db 0FFh
                db    0
aGoldsInYourAcc db '&golds in your account.'
                db 0FFh
                db    1
unk_AC35        db  0Ch
aYouHaveOneGold db 'You have one gold in your account.'
                db 0FFh
                db    1
unk_AC5A        db  0Ch
aUnlessYouHaveB db 'Unless you have business, don\t come in here. I\m a busy man.'
                db 0FFh
                db    2
                db  11h
                db 0FFh
                db 0FFh
unk_AC9D        db  0Ch
aNextTimePlease db 'Next time please deposit a large sum in savings. '
                db 0FFh
                db    2
                db  11h
                db 0FFh
                db 0FFh
unk_ACD4        db  0Ch
aThankYouComeAg db 'Thank you. Come again to make a deposit for a large sum in savings. '
                db 0FFh
                db    2
                db  11h
                db 0FFh
                db 0FFh
byte_AD1E       db 0
word_AD1F       dw 0
byte_AD21       db 0
unk_AD22        db    0
byte_AD23       db 0
byte_AD24       db 0
byte_AD25       db 0
byte_AD26       db 0
byte_AD27       db 30h
                db 0FFh
byte_AD29       db 0
word_AD2A       dw 0
byte_AD2C       db 0
word_AD2D       dw 0
unk_AD2F        db    0
unk_AD30        db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0

bankpro         ends
                end     start
