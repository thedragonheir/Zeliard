include common.inc
include town.inc

                .286
                .model small

seg000          segment byte public 'CODE'
                assume cs:seg000, ds:seg000
                org 0A000h
start:
                dw offset sub_A004
                dw offset sub_A644

; =============== S U B R O U T I N E =======================================


sub_A004        proc near
                mov     es, word ptr ds:seg1
                mov     di, 8000h
                mov     si, offset vfs_drug_grp
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
                mov     byte ptr unk_B217, 0
                call    word ptr cs:Clear_Viewport_proc
                call    word ptr cs:Clear_Place_Enemy_Bar_proc
                mov     si, offset unk_A81C
                call    word ptr cs:Render_Pascal_String_1_proc
                call    sub_A08C
                push    cs
                pop     es
                mov     bl, ds:town_id
                dec     bl
                add     bl, bl
                xor     bh, bh
                mov     si, prices_by_town[bx]
                mov     di, offset byte_B1F6
                mov     cx, 12
                rep movsw
                call    sub_A5BF
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:dialog_string_ptr, offset aOh

loc_A079:
                call    word ptr cs:render_menu_dialog_proc
                cmp     al, 0FFh
                jz      short loc_A087
                call    sub_A0B8
                jmp     short loc_A079
; ---------------------------------------------------------------------------

loc_A087:
                jmp     word ptr cs:Fade_To_Black_Dithered_proc
sub_A004        endp


; =============== S U B R O U T I N E =======================================


sub_A08C        proc near
                mov     si, offset muralla_magic_items_inventory_bitmask
                mov     al, ds:town_id
                dec     al
                xor     ah, ah
                add     si, ax
                mov     dl, [si]
                push    cs
                pop     es
                mov     di, offset byte_B20F
                xor     dh, dh
                mov     cx, 8

loc_A0A4:
                add     dl, dl
                jnb     short loc_A0B1
                mov     al, cl
                neg     al
                add     al, 8
                stosb
                inc     dh

loc_A0B1:
                loop    loc_A0A4
                mov     byte ptr unk_B20E, dh
                retn
sub_A08C        endp


; =============== S U B R O U T I N E =======================================


sub_A0B8        proc near

                mov     bl, al
                xor     bh, bh
                add     bx, bx          ; switch 9 cases
                jmp     cs:jpt_A0BE[bx] ; switch jump
sub_A0B8        endp

; ---------------------------------------------------------------------------
jpt_A0BE        dw offset loc_A0D5      ; jump table for switch statement
                dw offset loc_A0EB
                dw offset loc_A10C
                dw offset loc_A18D
                dw offset loc_A1AA
                dw offset loc_A300
                dw offset loc_A4BA
                dw offset loc_A100
                dw offset loc_A106
; ---------------------------------------------------------------------------
; START OF FUNCTION CHUNK FOR sub_A0B8

loc_A0D5:
                mov     byte ptr ds:frame_timer, 0

loc_A0DA:
                call    sub_A644
                cmp     byte ptr ds:frame_timer, 80
                jb      short loc_A0DA
                mov     si, offset byte_A745
                call    sub_A708
                retn
; ---------------------------------------------------------------------------

loc_A0EB:
                mov     byte ptr ds:frame_timer, 0

loc_A0F0:
                call    sub_A644
                cmp     byte ptr ds:frame_timer, 80
                jb      short loc_A0F0
                mov     si, offset byte_A74F
                jmp     sub_A708
; ---------------------------------------------------------------------------

loc_A100:                               ; jumptable 0000A0BE case 7
                mov     si, offset byte_A759
                jmp     sub_A708
; ---------------------------------------------------------------------------

loc_A106:                               ; jumptable 0000A0BE case 8
                mov     si, offset byte_A761
                jmp     sub_A708
; ---------------------------------------------------------------------------

loc_A10C:                               ; jumptable 0000A0BE case 2
                call    sub_A5B2
                mov     bx, 2722h
                mov     cx, 1C2Dh
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 2725h
                mov     byte ptr ds:menu_item_count, 4
                mov     byte ptr ds:menu_max_items, 4
                mov     cx, 4
                mov     si, offset aGoOutside ; "Go outside"
                call    word ptr cs:render_menu_string_list_proc
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     bl, byte ptr unk_B217
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A149
                xor     bl, bl

loc_A149:
                mov     byte ptr unk_B217, bl
                xor     bh, bh
                add     bx, bx          ; switch 4 cases
                jmp     jpt_A151[bx]    ; switch jump
; ---------------------------------------------------------------------------
jpt_A151        dw offset loc_A15D      ; jump table for switch statement
                dw offset loc_A167
                dw offset loc_A16E
                dw offset loc_A186
; ---------------------------------------------------------------------------

loc_A15D:                               ; jumptable 0000A151 case 0
                call    sub_A5B2
                mov     word ptr ds:dialog_string_ptr, offset unk_AB0E
                retn
; ---------------------------------------------------------------------------

loc_A167:
                mov     word ptr ds:dialog_string_ptr, offset unk_A88C
                retn
; ---------------------------------------------------------------------------

loc_A16E:                               ; jumptable 0000A151 case 2
                call    sub_A49C
                mov     word ptr ds:dialog_string_ptr, offset unk_A98D
                test    byte ptr ds:menu_max_items, 0FFh
                jz      short loc_A17F
                retn
; ---------------------------------------------------------------------------

loc_A17F:
                mov     word ptr ds:dialog_string_ptr, offset unk_AA79
                retn
; ---------------------------------------------------------------------------

loc_A186:
                mov     word ptr ds:dialog_string_ptr, offset unk_AAA6
                retn
; ---------------------------------------------------------------------------

loc_A18D:                               ; jumptable 0000A0BE case 3
                push    cs
                pop     es
                mov     si, offset byte_B20F
                mov     di, offset byte_FF58
                mov     cx, 8
                rep movsb
                mov     al, byte ptr unk_B20E
                mov     ds:menu_max_items, al
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     byte ptr unk_B218, 0

loc_A1AA:                               ; jumptable 0000A0BE case 4
                mov     al, byte ptr unk_B20E
                mov     ds:menu_max_items, al
                cmp     al, 3
                jb      short loc_A1B6
                mov     al, 3

loc_A1B6:
                mov     ds:menu_item_count, al
                mov     bx, 156Eh
                mov     cx, 2524h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:menu_digits_render_flag, 0FFh
                mov     word ptr ds:menu_base_addr, 1571h
                mov     word ptr ds:string_width_bytes, 33
                mov     word ptr ds:numeric_display_x_offset, 23
                mov     si, offset off_B08A ; "Ken\\ko Potion"
                mov     di, offset byte_B1F6
                mov     cl, ds:menu_item_count
                xor     ch, ch
                mov     al, ds:menu_cursor_pos
                call    word ptr cs:render_menu_list_scrolling_proc
                mov     bl, byte ptr unk_B218
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A203
                mov     word ptr ds:dialog_string_ptr, offset unk_A965
                retn
; ---------------------------------------------------------------------------

loc_A203:
                mov     byte ptr unk_B218, bl
                mov     al, bl
                add     al, ds:menu_cursor_pos
                mov     bx, offset byte_FF58
                xlat
                push    ax
                mov     word ptr ds:dialog_string_ptr, offset unk_A8C4
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                push    ax
                mov     si, ds:dialog_string_ptr
                push    si
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_B08A[bx] ; "Ken\\ko Potion"
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
                mov     si, offset byte_B1F6
                add     si, ax
                mov     dl, [si]
                mov     ax, [si+1]
                mov     byte ptr unk_B21B, dl
                mov     word ptr unk_B21C, ax
                call    word ptr cs:check_gold_sufficient_proc
                pop     bx
                mov     word ptr ds:dialog_string_ptr, offset aYouHaveNoMoney
                jb      short loc_A2BE
                push    dx
                push    ax
                mov     si, offset magic_items
                mov     cx, 5

loc_A271:
                test    byte ptr [si], 0FFh
                jz      short loc_A282
                inc     si
                loop    loc_A271
                pop     ax
                pop     dx
                mov     word ptr ds:dialog_string_ptr, offset aYouCanTPossibl
                retn
; ---------------------------------------------------------------------------

loc_A282:
                pop     ax
                pop     dx
                mov     ds:hero_gold_hi, dl
                mov     ds:hero_gold_lo, ax
                inc     bl
                mov     [si], bl
                mov     word ptr ds:dialog_string_ptr, offset aThatWillBe
                call    word ptr cs:render_menu_dialog_proc
                mov     dl, byte ptr unk_B21B
                mov     ax, word ptr unk_B21C
                mov     di, offset unk_B21E
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_B21E
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si

loc_A2BE:
                call    word ptr cs:render_menu_dialog_proc
                call    word ptr cs:Print_Gold_Decimal_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_A909
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                pushf
                call    sub_A5B2
                popf
                mov     word ptr ds:dialog_string_ptr, offset unk_A8A8
                jb      short loc_A2F9
                retn
; ---------------------------------------------------------------------------

loc_A2F9:
                mov     word ptr ds:dialog_string_ptr, offset unk_A965
                retn
; ---------------------------------------------------------------------------

loc_A300:                               ; jumptable 0000A0BE case 5
                call    sub_A49C
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     al, ds:menu_max_items
                cmp     al, 2
                jb      short loc_A311
                mov     al, 2

loc_A311:
                mov     ds:menu_item_count, al
                mov     bx, 1778h
                mov     cx, 211Ah
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:menu_digits_render_flag, 0
                mov     word ptr ds:menu_base_addr, 197Bh
                mov     word ptr ds:string_width_bytes, 25
                mov     si, offset off_B08A ; "Ken\\ko Potion"
                mov     cl, ds:menu_item_count
                xor     ch, ch
                mov     al, ds:menu_cursor_pos
                call    word ptr cs:render_menu_list_scrolling_proc
                xor     bl, bl
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A353
                mov     word ptr ds:dialog_string_ptr, offset unk_A965
                retn
; ---------------------------------------------------------------------------

loc_A353:
                mov     byte ptr unk_B218, bl
                mov     word ptr ds:dialog_string_ptr, offset unk_A8D7
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte ptr unk_B218
                add     al, ds:menu_cursor_pos
                mov     bx, offset byte_FF58
                xlat
                push    ax
                mov     si, ds:dialog_string_ptr
                push    si
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_B08A[bx] ; "Ken\\ko Potion"
                mov     ds:dialog_string_ptr, ax
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                mov     cl, 3
                mul     cl
                mov     bx, offset byte_B1F6
                add     bx, ax
                mov     dl, [bx]
                mov     ax, [bx+1]
                shr     dl, 1
                rcr     ax, 1
                mov     byte ptr unk_B21B, dl
                mov     word ptr unk_B21C, ax
                push    ax
                push    dx
                mov     word ptr ds:dialog_string_ptr, offset aILlGiveYou
                call    word ptr cs:render_menu_dialog_proc
                pop     dx
                pop     ax
                mov     di, offset unk_B21E
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset unk_B21E
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 3421h
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 3524h
                call    word ptr cs:show_yes_no_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_A9FE
                jnb     short loc_A3FB
                retn
; ---------------------------------------------------------------------------

loc_A3FB:
                mov     dl, byte ptr unk_B21B
                mov     ax, word ptr unk_B21C
                call    word ptr cs:add_gold_to_hero_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_A9AD
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte ptr unk_B218
                add     al, ds:menu_cursor_pos
                mov     bx, offset byte_FF58
                xlat
                inc     al
                mov     si, offset magic_items
                mov     cx, 5

loc_A425:
                cmp     al, [si]
                jz      short loc_A42C
                inc     si
                loop    loc_A425

loc_A42C:
                mov     byte ptr [si], 0
                dec     al
                xor     ah, ah
                push    ax
                mov     al, ds:town_id
                dec     al
                mov     si, offset muralla_magic_items_inventory_bitmask
                add     si, ax
                pop     ax
                mov     di, offset byte_A494
                add     di, ax
                mov     al, [di]
                or      [si], al
                call    word ptr cs:Print_Gold_Decimal_proc
                call    sub_A49C
                mov     word ptr ds:dialog_string_ptr, offset aIsThereSomethi
                test    byte ptr ds:menu_max_items, 0FFh
                jnz     short loc_A45E
                retn
; ---------------------------------------------------------------------------

loc_A45E:
                mov     word ptr ds:dialog_string_ptr, offset aDoYouHaveAnyth
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_A965
                jnb     short loc_A48A
                retn
; ---------------------------------------------------------------------------

loc_A48A:
                call    sub_A5B2
                mov     word ptr ds:dialog_string_ptr, offset unk_A98D
                retn
; END OF FUNCTION CHUNK FOR sub_A0B8
; ---------------------------------------------------------------------------
byte_A494       db 80h, 40h, 20h, 10h, 8, 4, 2, 1

; =============== S U B R O U T I N E =======================================


sub_A49C        proc near
                push    cs
                pop     es
                mov     si, offset magic_items
                mov     di, offset byte_FF58
                mov     cx, 5
                xor     dl, dl

loc_A4A9:
                lodsb
                or      al, al
                jz      short loc_A4B3
                dec     al
                stosb
                inc     dl

loc_A4B3:
                loop    loc_A4A9
                mov     ds:menu_max_items, dl
                retn
sub_A49C        endp

; ---------------------------------------------------------------------------

loc_A4BA:                               ; jumptable 0000A0BE case 6
                mov     byte ptr unk_B218, 0
                mov     byte ptr ds:menu_cursor_pos, 0

loc_A4C4:
                push    cs
                pop     es
                mov     si, offset byte_B20F
                mov     di, offset byte_FF58
                mov     cx, 8
                rep movsb
                mov     al, byte ptr unk_B20E
                mov     ds:menu_max_items, al
                mov     al, ds:menu_max_items
                cmp     al, 2
                jb      short loc_A4E0
                mov     al, 2

loc_A4E0:
                mov     ds:menu_item_count, al
                mov     bx, 1778h
                mov     cx, 211Ah
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:menu_digits_render_flag, 0
                mov     word ptr ds:menu_base_addr, 197Bh
                mov     word ptr ds:string_width_bytes, 25
                mov     si, offset off_B08A ; "Ken\\ko Potion"
                mov     cl, ds:menu_item_count
                xor     ch, ch
                mov     al, ds:menu_cursor_pos
                call    word ptr cs:render_menu_list_scrolling_proc
                mov     bl, byte ptr unk_B218
                call    word ptr cs:select_from_menu_proc
                jnb     short loc_A524
                mov     word ptr ds:dialog_string_ptr, offset unk_A965
                retn
; ---------------------------------------------------------------------------

loc_A524:
                mov     byte ptr unk_B218, bl
                mov     word ptr ds:dialog_string_ptr, offset unk_AACA
                call    word ptr cs:render_menu_dialog_proc
                mov     al, byte ptr unk_B218
                add     al, ds:menu_cursor_pos
                mov     bx, offset byte_FF58
                xlat
                push    ax
                mov     si, ds:dialog_string_ptr
                push    si
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_B08A[bx] ; "Ken\\ko Potion"
                mov     ds:dialog_string_ptr, ax
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                call    word ptr cs:render_menu_dialog_proc
                pop     ax
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                mov     ax, off_AB3A[bx] ; "Well, it\\s a special blend of yunkel f"...
                mov     ds:dialog_string_ptr, ax
                call    word ptr cs:render_menu_dialog_proc
                mov     word ptr ds:dialog_string_ptr, offset unk_AAE9
                call    word ptr cs:render_menu_dialog_proc
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                pushf
                call    sub_A5B2
                popf
                mov     word ptr ds:dialog_string_ptr, offset unk_A965
                jnb     short loc_A5A4
                retn
; ---------------------------------------------------------------------------

loc_A5A4:
                mov     word ptr ds:dialog_string_ptr, offset unk_AAA6
                call    word ptr cs:render_menu_dialog_proc
                jmp     loc_A4C4

; =============== S U B R O U T I N E =======================================


sub_A5B2        proc near
                mov     bx, 2717h
                mov     cx, 1D41h
                xor     al, al
                jmp     word ptr cs:Draw_Bordered_Rectangle_proc
sub_A5B2        endp


; =============== S U B R O U T I N E =======================================


sub_A5BF        proc near
                mov     si, offset byte_A5E4
                mov     bx, 717h
                mov     cx, 8

loc_A5C8:
                push    cx
                mov     cx, 0Ch

loc_A5CC:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A5CC
                sub     bh, 0Ch
                add     bl, 8
                pop     cx
                loop    loc_A5C8
                retn
sub_A5BF        endp

; ---------------------------------------------------------------------------
byte_A5E4       db 0, 1, 2, 3, 4, 5, 1Ch, 1Dh, 1Eh, 1Fh, 20h, 21h, 6, 9
                db 7Dh, 7Eh, 7Fh, 80h, 22h, 23h, 24h, 25h, 26h, 27h, 6
                db 0Ah, 81h, 82h, 83h, 84h, 28h, 29h, 2Ah, 2Bh, 2Ch, 2Dh
                db 6, 0Bh, 85h, 86h, 87h, 88h, 2Eh, 2Fh, 30h, 31h, 32h
                db 33h, 6, 0Ch, 89h, 8Ah, 8Bh, 8Ch, 34h, 35h, 36h, 37h
                db 38h, 39h, 6, 0Dh, 8Dh, 8Eh, 8Fh, 90h, 3Ah, 3Bh, 3Ch
                db 3Dh, 3Eh, 3Fh, 7, 0Eh, 91h, 92h, 93h, 94h, 10h, 11h
                db 12h, 13h, 14h, 15h, 8, 0Fh, 95h, 96h, 97h, 98h, 16h
                db 17h, 18h, 19h, 1Ah, 1Bh

; =============== S U B R O U T I N E =======================================


sub_A644        proc near
                cmp     word ptr ds:tick_counter, 2
                jnb     short loc_A64C
                retn
; ---------------------------------------------------------------------------

loc_A64C:
                mov     word ptr ds:tick_counter, 0
                inc     byte ptr unk_B219
                cmp     byte ptr unk_B219, 20
                jnb     short loc_A65E
                retn
; ---------------------------------------------------------------------------

loc_A65E:
                mov     byte ptr unk_B219, 0
                mov     al, byte ptr unk_B21A
                inc     al
                cmp     al, 3
                jb      short loc_A66E
                xor     al, al

loc_A66E:
                mov     byte ptr unk_B21A, al
                mov     cl, 24h ; '$'
                mul     cl
                mov     si, offset byte_A69C
                add     si, ax
                mov     bx, 0D17h
                mov     cx, 6

loc_A680:
                push    cx
                mov     cx, 6

loc_A684:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A684
                sub     bh, 6
                add     bl, 8
                pop     cx
                loop    loc_A680
                retn
sub_A644        endp

; ---------------------------------------------------------------------------
byte_A69C       db 1Ch, 1Dh, 1Eh, 1Fh, 20h, 21h, 22h, 23h, 24h, 25h, 26h
                db 27h, 28h, 29h, 2Ah, 2Bh, 2Ch, 2Dh, 2Eh, 2Fh, 30h, 31h
                db 32h, 33h, 34h, 35h, 36h, 37h, 38h, 39h, 3Ah, 3Bh, 3Ch
                db 3Dh, 3Eh, 3Fh, 5Fh, 60h, 61h, 62h, 63h, 64h, 65h, 66h
                db 67h, 68h, 69h, 6Ah, 28h, 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 2Eh
                db 70h, 30h, 31h, 52h, 33h, 71h, 72h, 73h, 74h, 75h, 76h
                db 77h, 78h, 79h, 7Ah, 7Bh, 7Ch, 40h, 41h, 42h, 43h, 44h
                db 45h, 46h, 47h, 48h, 49h, 4Ah, 4Bh, 28h, 4Ch, 4Dh, 4Eh
                db 4Fh, 50h, 2Eh, 51h, 30h, 31h, 52h, 53h, 54h, 55h, 56h
                db 37h, 57h, 58h, 59h, 5Ah, 5Bh, 5Ch, 5Dh, 5Eh

; =============== S U B R O U T I N E =======================================


sub_A708        proc near
                mov     byte ptr ds:frame_timer, 0
                lodsw
                cmp     ax, 0FFFFh
                jnz     short loc_A714
                retn
; ---------------------------------------------------------------------------

loc_A714:
                push    si
                mov     si, ax
                mov     bx, 91Fh
                mov     cx, 7

loc_A71D:
                push    cx
                mov     cx, 4

loc_A721:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A721
                sub     bh, 4
                add     bl, 8
                pop     cx
                loop    loc_A71D

loc_A738:
                call    sub_A644
                cmp     byte ptr ds:frame_timer, 40
                jb      short loc_A738
                pop     si
                jmp     short sub_A708
sub_A708        endp

; ---------------------------------------------------------------------------
byte_A745       db 69h, 0A7h, 85h, 0A7h, 0A1h, 0A7h, 0BDh, 0A7h, 0FFh
                db 0FFh
byte_A74F       db 0BDh, 0A7h, 0A1h, 0A7h, 85h, 0A7h, 69h, 0A7h, 0FFh
                db 0FFh
byte_A759       db 0BDh, 0A7h, 0D9h, 0A7h, 0F5h, 0A7h, 0FFh, 0FFh
byte_A761       db 0F5h, 0A7h, 0D9h, 0A7h, 0BDh, 0A7h, 0FFh, 0FFh, 7Dh
                db 7Eh, 7Fh, 80h, 81h, 82h, 83h, 84h, 85h, 86h, 87h, 88h
                db 89h, 8Ah, 8Bh, 8Ch, 8Dh, 8Eh, 8Fh, 90h, 91h, 92h, 93h
                db 94h, 95h, 96h, 97h, 98h, 99h, 9Ah, 7Fh, 80h, 9Bh, 9Ch
                db 83h, 84h, 9Dh, 9Eh, 9Fh, 88h, 0A0h, 0A1h, 0A2h, 0A3h
                db 8Dh, 0A4h, 0A5h, 0A6h, 91h, 92h, 93h, 94h, 95h, 96h
                db 97h, 98h, 99h, 9Ah, 7Fh, 80h, 9Bh, 9Ch, 83h, 84h, 9Dh
                db 9Eh, 9Fh, 88h, 0A0h, 0A1h, 0A2h, 0A3h, 8Dh, 0A4h, 0A5h
                db 0A6h, 91h, 92h, 93h, 94h, 95h, 96h, 97h, 98h, 99h, 9Ah
                db 0B8h, 0BFh, 0A7h, 0B3h, 0B9h, 0C0h, 85h, 0A9h, 0BAh
                db 0C1h, 0ACh, 0B4h, 0BBh, 0C2h, 8Dh, 0B5h, 0BCh, 0C3h
                db 91h, 0B6h, 0BDh, 0C4h, 95h, 0B7h, 0BEh, 0C5h, 99h, 9Ah
                db 0C7h, 0C6h, 0A7h, 0CAh, 0C9h, 0C8h, 85h, 0A9h, 0CCh
                db 0CBh, 0ACh, 0B4h, 0BBh, 0C2h, 8Dh, 0B5h, 0BCh, 0C3h
                db 91h, 0B6h, 0BDh, 0C4h, 95h, 0B7h, 0BEh, 0C5h, 99h, 9Ah
                db 0CEh, 0CDh, 0A7h, 0D1h, 0D0h, 0CFh, 85h, 0A9h, 0D3h
                db 0D2h, 0ACh, 0B4h, 0BBh, 0C2h, 8Dh, 0B5h, 0BCh, 0C3h
                db 91h, 0B6h, 0BDh, 0C4h, 95h, 0B7h, 0BEh, 0C5h
vfs_drug_grp    db    1
                db  18h
aDrugGrp        db 'DRUG.GRP',0
unk_A81C        db  0Eh
                db 0AFh
                db    0
aWitchcraftImpl db 25,'Witchcraft Implement shop'
aGoOutside      db 'Go outside',0
aBuyItem        db 'Buy item',0
aSellItem       db 'Sell item',0
aDescriptionOfI db 'Description of item',0
aOh             db 'Oh... '
                db 0FFh
                db    0
aHelloCanIHelpY db 'hello, can I help you?/'
                db 0FFh
                db    2
unk_A88C        db  0Ch
aWhatAreYouLook_0 db 'What are you looking for?'
                db 0FFh
                db    3
unk_A8A8        db  0Ch
aWhatAreYouLook db 'What are you looking for?'
                db 0FFh
                db    4
unk_A8C4        db  0Ch
aYouDLikeA      db 'You\d like a '
                db 0FFh
                db    0
                db './'
                db 0FFh
unk_A8D7        db  0Ch
aYouDLikeToSell db 'You\d like to sell a '
                db 0FFh
                db    0
                db './'
                db 0FFh
aThatWillBe     db 'That will be '
                db 0FFh
                db    0
aGolds          db '&golds.'
                db 0FFh
unk_A909        db  0Dh
aWillThereBeSom db 'Will there be something else?'
                db 0FFh
aYouHaveNoMoney db 'You have no money, sir.'
                db 0FFh
aYouCanTPossibl db 'You can\t possibly carry any more./'
                db 0FFh
                db    2
unk_A965        db  0Ch
aIsThereSomethi db 'Is there something I&can do for you?/'
                db 0FFh
                db    2
unk_A98D        db  0Ch
aWhatWouldYouLi db 'What would you like to sell?/'
                db 0FFh
                db    5
unk_A9AD        db  0Ch
aThankYouVeryMu db 'Thank you very much./'
                db 0FFh
aILlGiveYou     db 'I\ll give you '
                db 0FFh
                db    0
aGoldsForThatWi db '&golds for that./Will that be all right?'
                db 0FFh
                db    0
unk_A9FE        db  0Ch
aOhISeeWellThat db 'Oh, I&see. Well, that\s the best I&can do. I\m sorry it is\t sati'
                db 'sfactory.'
                db 0FFh
                db    2
aDoYouHaveAnyth db 'Do you have anything else you\d like to sell?'
                db 0FFh
unk_AA79        db  0Ch
aYouArenTCarryi db 'You aren\t carrying any magic items, sir./'
                db 0FFh
                db    2
unk_AAA6        db  0Ch
aWhichItemCanIT db 'Which item can I tell you about?/'
                db 0FFh
                db    6
unk_AACA        db  0Ch
aYouReIntereste db 'You\re interested in the '
                db 0FFh
                db    0
                db './'
                db 0FFh
unk_AAE9        db  0Ch
aCanITellYouAbo db 'Can I tell you about anything else?'
                db 0FFh
unk_AB0E        db  0Ch
                db 0FFh
                db    7
aThankYouSir    db 'Thank you, sir. '
                db 0FFh
                db    8
aPleaseComeAgai db 'Please come again.'
                db 0FFh
                db    1
                db  11h
                db 0FFh
                db 0FFh
off_AB3A        dw offset aWellItSASpecia ; "Well, it\\s a special blend of yunkel f"...
                dw offset aThisIsTheFruit ; "This is the fruit of the Juu-en tree wh"...
                dw offset aThisPotionIsMa ; "This potion is made from the broth of m"...
                dw offset aThisIsMadeFrom ; "This is made from a mixture of the powd"...
                dw offset aThisStoneProte ; "This stone protects the aura that livin"...
                dw offset aThisIsALiquifi ; "This is a liquified metal made from mer"...
                dw offset aHmmIDonTKnowMu ; "Hmm... I don\\t know much about this on"...
                dw offset aThisFeatherRem ; "This feather remembers the voice of the"...
aWellItSASpecia db 'Well, it\s a special blend of yunkel fruit and ripodi leaf./It\s '
                db 'low in price and as a mild health tonic, it\s perfect.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisIsTheFruit db 'This is the fruit of the Juu-en tree which bears only once every '
                db 'ten years./The price is a bit high, but it provides excellent rel'
                db 'ief from wounds and exhaustion -- it\s quite a bit better than th'
                db 'e Ken\ko potion.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisPotionIsMa db 'This potion is made from the broth of mistletoe simmered on the n'
                db 'ight of a full moon./It restores magical powers. It\s very bitter'
                db ', but the price is low.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisIsMadeFrom db 'This is made from a mixture of the powdered dragon scales and cru'
                db 'shed Wise Man\s Stone steamed for one hundred days./It will fully'
                db ' restore your magical powers. The price, however..... is high.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisStoneProte db 'This stone protects the aura that living beings exude./It surroun'
                db 'ds the aura to prevent interference from other auras and acts as '
                db 'a protection against enemy attacks.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisIsALiquifi db 'This is a liquified metal made from mercury and iron./If you pain'
                db 't it on a shield weakened by battle, the shield will regain its o'
                db 'riginal strength.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aHmmIDonTKnowMu db 'Hmm... I don\t know much about this one, but I do know that it in'
                db 'creases the offensive power of a sword./Don\t worry, it hasn\t ki'
                db 'lled anyone yet.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
aThisFeatherRem db 'This feather remembers the voice of the last wise man who spoke t'
                db 'o you./If you hold it in your right hand and swing it once, you\l'
                db 'l return to him. It\s never failed anyone I know.'
                db  11h
                db  0Ch
                db 0FFh
                db 0FFh
off_B08A        dw offset aKenKoPotion  ; "Ken\\ko Potion"
                dw offset aJuuEnFruit   ; "Juu-en Fruit"
                dw offset aElixirOfKashi ; "Elixir of Kashi"
                dw offset aChikaraPowder ; "Chikara Powder"
                dw offset aMagiaStone   ; "Magia Stone"
                dw offset aHolyWaterOfAce ; "Holy Water of Acero"
                dw offset aSabreOil     ; "Sabre Oil"
                dw offset aKiokuFeather ; "Kioku Feather"
aKenKoPotion    db 'Ken\ko Potion',0
aJuuEnFruit     db 'Juu-en Fruit',0
aElixirOfKashi  db 'Elixir of Kashi',0
aChikaraPowder  db 'Chikara Powder',0
aMagiaStone     db 'Magia Stone',0
aHolyWaterOfAce db 'Holy Water of Acero',0
aSabreOil       db 'Sabre Oil',0
aKiokuFeather   db 'Kioku Feather',0
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
                dw 50
                db 0
                dw 240
                db 0
                dw 60
                db 0
                dw 320
                db 0
                dw 1000
                db 0
                dw 100
                db 0
                dw 1200
                db 0
                dw 350
satono_prices   db 0
                dw 50
                db 0
                dw 240
                db 0
                dw 60
                db 0
                dw 320
                db 0
                dw 1000
                db 0
                dw 100
                db 0
                dw 1200
                db 0
                dw 350
bosque_prices   db 0
                dw 50
                db 0
                dw 240
                db 0
                dw 60
                db 0
                dw 320
                db 0
                dw 1500
                db 0
                dw 100
                db 0
                dw 1200
                db 0
                dw 350
hellada_prices  db 0
                dw 50
                db 0
                dw 300
                db 0
                dw 120
                db 0
                dw 320
                db 0
                dw 1500
                db 0
                dw 100
                db 0
                dw 1200
                db 0
                dw 350
tumba_prices    db 0
                dw 5
                db 0
                dw 600
                db 0
                dw 240
                db 0
                dw 480
                db 0
                dw 2000
                db 0
                dw 200
                db 0
                dw 2000
                db 0
                dw 350
dorado_prices   db 0
                dw 5
                db 0
                dw 600
                db 0
                dw 240
                db 0
                dw 480
                db 0
                dw 2000
                db 0
                dw 200
                db 0
                dw 2000
                db 0
                dw 350
llama_prices    db 0
                dw 5
                db 0
                dw 900
                db 0
                dw 360
                db 0
                dw 960
                db 0
                dw 2500
                db 0
                dw 400
                db 0
                dw 2400
                db 0
                dw 350
pureza_prices   db 0
                dw 5
                db 0
                dw 900
                db 0
                dw 360
                db 0
                dw 960
                db 0
                dw 2500
                db 0
                dw 400
                db 0
                dw 2400
                db 0
                dw 350
esco_prices     db 0
                dw 2
                db 0
                dw 200
                db 0
                dw 40
                db 0
                dw 280
                db 0
                dw 800
                db 0
                dw 80
                db 0
                dw 1000
                db 0
                dw 150
byte_B1F6       db 24 dup(0)
unk_B20E        db    0
byte_B20F       db 8 dup(0)
unk_B217        db    0
unk_B218        db    0
unk_B219        db    0
unk_B21A        db    0
unk_B21B        db    0
unk_B21C        db    0
                db    0
unk_B21E        db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0

seg000          ends
                end     start
