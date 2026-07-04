include common.inc
include town.inc

                .286
                .model small

; Segment type: Pure code
innapro         segment byte public 'CODE'
                assume cs:innapro, ds:innapro
                org 0A000h
start:
                dw offset sub_A004
                dw offset sub_A22F

; =============== S U B R O U T I N E =======================================


sub_A004        proc near
                mov     es, word ptr ds:seg1
                mov     di, 8000h
                mov     si, offset vfs_inn_grp
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
                mov     si, offset byte_A2EB
                call    word ptr cs:Render_Pascal_String_1_proc
                call    sub_A05F
                mov     word ptr ds:dialog_string_ptr, offset aWelcomeSir

loc_A04C:
                call    word ptr cs:render_menu_dialog_proc
                cmp     al, 0FFh
                jz      short loc_A05A
                call    sub_A075
                jmp     short loc_A04C
; ---------------------------------------------------------------------------

loc_A05A:
                jmp     word ptr cs:Fade_To_Black_Dithered_proc
sub_A004        endp


; =============== S U B R O U T I N E =======================================


sub_A05F        proc near
                call    sub_A1AA
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte_A505, 0FFh
                retn
sub_A05F        endp


; =============== S U B R O U T I N E =======================================


sub_A075        proc near
                mov     bl, al
                xor     bh, bh
                add     bx, bx          ; switch 5 cases
                jmp     cs:jpt_A07B[bx] ; switch jump
sub_A075        endp

; ---------------------------------------------------------------------------
jpt_A07B        dw offset loc_A08A      ; jump table for switch statement
                dw offset loc_A0BE
                dw offset loc_A114
                dw offset loc_A12A
                dw offset sub_A15F
; ---------------------------------------------------------------------------

loc_A08A:
                mov     bl, ds:town_id
                dec     bl
                xor     bh, bh
                add     bx, bx
                mov     dx, word ptr byte_A2D1[bx]
                mov     word ptr byte_A506, dx
                mov     ax, dx
                xor     dl, dl
                mov     di, offset byte_A508
                call    word ptr cs:convert_ax_to_decimal_proc
                mov     si, ds:dialog_string_ptr
                push    si
                mov     word ptr ds:dialog_string_ptr, offset byte_A508
                call    word ptr cs:render_menu_dialog_proc
                pop     si
                mov     ds:dialog_string_ptr, si
                retn
; ---------------------------------------------------------------------------

loc_A0BE:
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     word ptr ds:menu_base_addr, 302Eh
                call    word ptr cs:show_yes_no_dialog_proc
                pushf
                mov     bx, 2F2Bh
                mov     cx, 0C19h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                popf
                mov     word ptr ds:dialog_string_ptr, offset byte_A3BD
                jnb     short loc_A0EE
                retn
; ---------------------------------------------------------------------------

loc_A0EE:
                mov     ax, word ptr byte_A506
                xor     dl, dl
                call    word ptr cs:check_gold_sufficient_proc
                mov     word ptr ds:dialog_string_ptr, offset byte_A41A
                jnb     short loc_A101
                retn
; ---------------------------------------------------------------------------

loc_A101:
                mov     ds:hero_gold_hi, dl
                mov     ds:hero_gold_lo, ax
                call    word ptr cs:Print_Gold_Decimal_proc
                mov     word ptr ds:dialog_string_ptr, offset byte_A483
                retn
; ---------------------------------------------------------------------------

loc_A114:
                mov     byte_A505, 0
                xor     al, al

loc_A11B:
                push    ax
                call    sub_A17F
                call    sub_A16F
                pop     ax
                inc     al
                cmp     al, 4
                jnz     short loc_A11B
                retn
; ---------------------------------------------------------------------------

loc_A12A:
                call    sub_A15F
                call    word ptr cs:Fade_To_Black_Dithered_proc
                call    sub_A15F
                call    sub_A15F
                mov     ax, ds:heroMaxHp
                mov     ds:hero_HP, ax
                call    word ptr cs:Draw_Hero_Health_proc
                push    cs
                pop     es
                mov     si, offset espada_count
                mov     di, offset spells_espada
                mov     cx, 7
                rep movsb
                test    byte ptr ds:current_magic_spell, 0FFh
                jz      short loc_A15C
                call    word ptr cs:Print_Magic_Left_Decimal_proc

loc_A15C:
                jmp     sub_A05F
; END OF FUNCTION CHUNK FOR sub_A075

; =============== S U B R O U T I N E =======================================


sub_A15F        proc near
                mov     byte ptr ds:frame_timer, 0

loc_A164:
                call    sub_A22F
                cmp     byte ptr ds:frame_timer, 150
                jb      short loc_A164
                retn
sub_A15F        endp


; =============== S U B R O U T I N E =======================================


sub_A16F        proc near
                mov     byte ptr ds:frame_timer, 0

loc_A174:
                call    sub_A22F
                cmp     byte ptr ds:frame_timer, 50
                jb      short loc_A174
                retn
sub_A16F        endp


; =============== S U B R O U T I N E =======================================


sub_A17F        proc near
                mov     cl, 14h
                mul     cl
                add     ax, offset byte_A281
                mov     si, ax
                mov     bx, 827h
                mov     cx, 4

loc_A18E:
                push    cx
                mov     cx, 5

loc_A192:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A192
                sub     bh, 5
                add     bl, 8
                pop     cx
                loop    loc_A18E
                retn
sub_A17F        endp


; =============== S U B R O U T I N E =======================================


sub_A1AA        proc near
                mov     si, offset byte_A1CF
                mov     bx, 717h
                mov     cx, 8

loc_A1B3:
                push    cx
                mov     cx, 0Ch

loc_A1B7:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A1B7
                sub     bh, 0Ch
                add     bl, 8
                pop     cx
                loop    loc_A1B3
                retn
sub_A1AA        endp

; ---------------------------------------------------------------------------
byte_A1CF       db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0Ah, 0Bh, 0Ch, 0Dh, 0Eh
                db 0Fh, 10h, 11h, 12h, 13h, 14h, 15h, 16h, 17h, 18h, 19h
                db 1Ah, 1Bh, 10h, 1Ch, 1Dh, 1Eh, 1Fh, 20h, 21h, 22h, 23h
                db 24h, 25h, 26h, 10h, 27h, 28h, 29h, 2Ah, 2Bh, 2Ch, 2Dh
                db 2Eh, 2Fh, 30h, 31h, 32h, 33h, 34h, 35h, 36h, 37h, 38h
                db 39h, 3Ah, 3Bh, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h
                db 44h, 45h, 46h, 47h, 48h, 49h, 4Ah, 4Bh, 4Ch, 4Dh, 4Eh
                db 4Fh, 50h, 51h, 52h, 53h, 54h, 55h, 56h, 57h, 58h, 59h
                db 5Ah, 5Bh, 5Ch, 5Dh

; =============== S U B R O U T I N E =======================================


sub_A22F        proc near
                test    byte_A505, 0FFh
                jnz     short loc_A237
                retn
; ---------------------------------------------------------------------------

loc_A237:
                cmp     word ptr ds:tick_counter, 40
                jnb     short loc_A23F
                retn
; ---------------------------------------------------------------------------

loc_A23F:
                mov     word ptr ds:tick_counter, 0
                call    word ptr cs:get_random_proc
                and     al, 1
                add     al, al
                add     al, al
                xor     ah, ah
                add     ax, offset byte_A279
                mov     si, ax
                mov     bx, 827h
                mov     cx, 2

loc_A25D:
                push    cx
                mov     cx, 2

loc_A261:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A261
                sub     bh, 2
                add     bl, 8
                pop     cx
                loop    loc_A25D
                retn
sub_A22F        endp

; ---------------------------------------------------------------------------
byte_A279       db 19h, 1Ah, 24h, 25h, 5Eh, 5Fh, 24h, 60h
byte_A281       db 19h, 1Ah, 1Bh, 10h, 1Ch, 24h, 25h, 26h, 10h, 27h, 2Fh
                db 30h, 31h, 32h, 33h, 3Bh, 3Ch, 3Dh, 3Eh, 3Fh, 19h, 1Ah
                db 1Bh, 10h, 1Ch, 24h, 25h, 26h, 10h, 27h, 2Fh, 30h, 31h
                db 32h, 33h, 3Bh, 3Ch, 3Dh, 3Eh, 3Fh, 19h, 1Ah, 1Bh, 10h
                db 1Ch, 24h, 61h, 62h, 10h, 27h, 2Fh, 63h, 64h, 32h, 33h
                db 3Bh, 65h, 66h, 3Eh, 3Fh, 19h, 1Ah, 1Bh, 10h, 1Ch, 24h
                db 25h, 26h, 67h, 68h, 2Fh, 69h, 6Ah, 6Bh, 6Ch, 3Bh, 6Dh
                db 6Eh, 6Fh, 3Fh
byte_A2D1       db 0
                db    0
                db  1Eh
                db    0
                db  32h ; 2
                db    0
                db  46h ; F
                db    0
                db  64h ; d
                db    0
                db  96h
                db    0
                db 0C8h
                db    0
                db  90h
                db    1
vfs_inn_grp     db 1
                db 19h
aInnGrp         db 'INN.GRP',0
byte_A2EB       db 19h
                db 0AFh
                db    0
aTheInn         db 7,'The Inn'
aWelcomeSir     db 12,'Welcome, sir!/'
aYouLookLikeYou db 'You look like you\ve come a long way./One night of rest in my inn'
                db ' is all you need to recover your strength. You can have the best '
                db 'room in the house for only '
                db 0FFh
                db    0
aGoldsWillYouSt db '&golds. Will you stay? '
                db 0FFh
                db    1
byte_A3BD       db 0Ch
aOhIMSorryToHea db 'Oh, I\m sorry to hear that./Well, if you should ever need a place'
                db ' to rest, do come back. '
                db  11h
                db 0FFh
                db 0FFh
byte_A41A       db 0Ch
aIMSorrySirButI db 'I\m sorry sir, but I can\t accommodate you without funds./'
                db 0FFh
                db    4
aPleaseComeBack db 'Please come back when you can afford it. '
                db  11h
                db 0FFh
                db 0FFh
byte_A483       db 0Ch
aThankYouSirEnj db 'Thank you, sir. Enjoy your stay. '
                db 0FFh
                db    2
                db 0FFh
                db    4
                db 0FFh
                db    3
                db  0Ch
                db 0FFh
                db    4
aITrustYouHadAG db 'I trust you had a good night\s sleep. We\ll be looking forward to seeing you again./'
                db  11h
                db 0FFh
                db 0FFh
byte_A505       db 0
byte_A506       db 0
                db    0
byte_A508       db 0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0

innapro         ends
                end     start
