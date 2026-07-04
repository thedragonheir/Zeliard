include common.inc
include town.inc

                .286
                .model small

seg000          segment byte public 'CODE'
                assume cs:seg000, ds:seg000
                org 0A000h
start:
                dw offset sub_A004
                dw offset sub_A1D7

; =============== S U B R O U T I N E =======================================


sub_A004        proc near
                mov     es, word ptr ds:seg1
                mov     di, 8000h
                mov     si, offset vfs_church_grp
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
                mov     si, offset unk_A2A6
                call    word ptr cs:Render_Pascal_String_1_proc
                call    sub_A152
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                call    sub_A288
                mov     ds:dialog_string_ptr, si

loc_A05A:
                call    word ptr cs:render_menu_dialog_proc
                cmp     al, 0FFh
                jz      short loc_A068
                call    sub_A06D
                jmp     short loc_A05A
; ---------------------------------------------------------------------------

loc_A068:
                jmp     word ptr cs:Fade_To_Black_Dithered_proc
sub_A004        endp


; =============== S U B R O U T I N E =======================================


sub_A06D        proc near

                mov     bl, al
                xor     bh, bh
                add     bx, bx          ; switch 5 cases
                jmp     cs:jpt_A073[bx] ; switch jump
sub_A06D        endp

; ---------------------------------------------------------------------------
jpt_A073        dw offset loc_A0E5      ; jump table for switch statement
                dw offset loc_A082
                dw offset sub_A089
                dw offset loc_A099
                dw offset loc_A0CB
; ---------------------------------------------------------------------------

loc_A082:
                mov     word ptr ds:dialog_string_ptr, offset aBraveKnightYou
                retn

; =============== S U B R O U T I N E =======================================


sub_A089        proc near
                mov     byte ptr ds:frame_timer, 0

loc_A08E:
                call    sub_A1D7
                cmp     byte ptr ds:frame_timer, 250
                jb      short loc_A08E
                retn
sub_A089        endp

; ---------------------------------------------------------------------------

loc_A099:
                mov     ax, ds:hero_HP
                add     ax, 8
                cmp     ax, ds:heroMaxHp
                jnb     short loc_A0BE
                mov     ds:hero_HP, ax
                call    word ptr cs:Draw_Hero_Health_proc
                mov     byte ptr ds:frame_timer, 0

loc_A0B2:
                call    sub_A1D7
                cmp     byte ptr ds:frame_timer, 20
                jb      short loc_A0B2
                jmp     short loc_A099  ; jumptable 0000A073 case 3
; ---------------------------------------------------------------------------

loc_A0BE:
                mov     ax, ds:heroMaxHp
                mov     ds:hero_HP, ax
                call    word ptr cs:Draw_Hero_Health_proc
                jmp     short $+2       ; jumptable 0000A073 case 4
; ---------------------------------------------------------------------------

loc_A0CB:                               ; jumptable 0000A073 case 4
                push    cs
                pop     es
                mov     si, offset espada_count
                mov     di, offset spells_espada
                mov     cx, 7
                rep movsb
                test    byte ptr ds:current_magic_spell, 0FFh
                jz      short locret_A0E4
                call    word ptr cs:Print_Magic_Left_Decimal_proc

locret_A0E4:
                retn
; ---------------------------------------------------------------------------

loc_A0E5:                               ; jumptable 0000A073 case 0
                mov     byte_A3E4, 0

loc_A0EA:
                mov     byte ptr ds:frame_timer, 0
                cmp     byte_A3E4, 5
                jb      short loc_A0F7
                retn
; ---------------------------------------------------------------------------

loc_A0F7:
                mov     al, byte_A3E4
                mov     cl, 6
                mul     cl
                add     ax, offset byte_A134
                mov     si, ax
                mov     bx, 163Fh
                mov     cx, 3

loc_A109:
                push    cx
                mov     cx, 2

loc_A10D:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A10D
                sub     bh, 2
                add     bl, 8
                pop     cx
                loop    loc_A109

loc_A124:
                call    sub_A1D7
                cmp     byte ptr ds:frame_timer, 32
                jb      short loc_A124
                inc     byte_A3E4
                jmp     short loc_A0EA
; ---------------------------------------------------------------------------
byte_A134       db 41h, 42h, 4Dh, 4Eh, 57h, 58h
                db 41h, 42h, 6Bh, 6Ch, 6Dh, 6Eh
                db 41h, 42h, 6Fh, 70h, 71h, 72h
                db 73h, 42h, 74h, 75h, 76h, 77h
                db 78h, 79h, 7Ah, 7Bh, 7Ch, 77h

; =============== S U B R O U T I N E =======================================


sub_A152        proc near
                mov     si, offset byte_A177
                mov     bx, 0E17h
                mov     cx, 8

loc_A15B:
                push    cx
                mov     cx, 12

loc_A15F:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A15F
                sub     bh, 0Ch
                add     bl, 8
                pop     cx
                loop    loc_A15B
                retn
sub_A152        endp

; ---------------------------------------------------------------------------
byte_A177       db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0Ah, 0Bh
                db 0Ch, 0Dh, 0Eh, 0Fh, 10h, 11h, 12h, 10h, 13h, 14h, 15h, 16h
                db 17h, 18h, 19h, 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 20h, 21h, 22h
                db 23h, 24h, 25h, 26h, 26h, 27h, 28h, 26h, 29h, 2Ah, 2Bh, 2Ch
                db 2Dh, 2Eh, 2Fh, 30h, 31h, 32h, 33h, 34h, 35h, 36h, 37h, 38h
                db 39h, 3Ah, 3Bh, 3Ch, 3Dh, 3Eh, 3Fh, 40h, 41h, 42h, 43h, 44h
                db 45h, 46h, 47h, 48h, 49h, 4Ah, 4Bh, 4Ch, 4Dh, 4Eh, 4Fh, 50h
                db 51h, 52h, 53h, 54h, 53h, 55h, 56h, 53h, 57h, 58h, 59h, 5Ah

; =============== S U B R O U T I N E =======================================


sub_A1D7        proc near

                cmp     word ptr ds:tick_counter, 32
                jnb     short loc_A1DF
                retn
; ---------------------------------------------------------------------------

loc_A1DF:
                mov     word ptr ds:tick_counter, 0
                inc     byte_A3E5
                cmp     byte_A3E5, 3
                jnz     short loc_A1F5
                mov     byte_A3E5, 0

loc_A1F5:
                call    sub_A1FA
                jmp     short loc_A246
sub_A1D7        endp


; =============== S U B R O U T I N E =======================================


sub_A1FA        proc near
                mov     bl, byte_A3E5
                xor     bh, bh
                add     bx, bx
                mov     ax, bx
                add     bx, bx
                add     bx, ax
                mov     si, bx
                add     si, offset byte_A234
                mov     bx, 1037h
                mov     cx, 2

loc_A214:
                push    cx
                mov     cx, 3

loc_A218:
                push    cx
                push    bx
                lodsb
                cmp     al, 0FFh
                jz      short loc_A224
                call    word ptr cs:draw_tile_to_screen_proc

loc_A224:
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A218
                sub     bh, 3
                add     bl, 8
                pop     cx
                loop    loc_A214
                retn
sub_A1FA        endp

; ---------------------------------------------------------------------------
byte_A234       db 0FFh, 30h, 31h, 3Bh, 3Ch, 3Dh
                db 0FFh, 5Bh, 5Ch, 5Dh, 5Eh, 5Fh
                db 0FFh, 60h, 61h, 62h, 63h, 64h
; ---------------------------------------------------------------------------
; START OF FUNCTION CHUNK FOR sub_A1D7

loc_A246:
                mov     bl, byte_A3E5
                xor     bh, bh
                add     bx, bx
                add     bx, bx
                mov     si, bx
                add     si, offset byte_A27C
                mov     bx, 1537h
                mov     cx, 2

loc_A25C:
                push    cx
                mov     cx, 2

loc_A260:
                push    cx
                push    bx
                lodsb
                cmp     al, 0FFh
                jz      short loc_A26C
                call    word ptr cs:draw_tile_to_screen_proc

loc_A26C:
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A260
                sub     bh, 2
                add     bl, 8
                pop     cx
                loop    loc_A25C
                retn
; END OF FUNCTION CHUNK FOR sub_A1D7
; ---------------------------------------------------------------------------
byte_A27C       db 34h, 35h, 40h, 0FFh
                db 65h, 66h, 67h, 0FFh
                db 68h, 69h, 6Ah, 0FFh

; =============== S U B R O U T I N E =======================================


sub_A288        proc near
                mov     ax, ds:hero_HP
                cmp     ax, ds:heroMaxHp
                mov     si, offset unk_A2B4
                jnz     short loc_A295
                retn
; ---------------------------------------------------------------------------

loc_A295:
                mov     si, offset unk_A2F2
                retn
sub_A288        endp

; ---------------------------------------------------------------------------
vfs_church_grp  db    1
                db  17h
aChurchGrp      db 'CHURCH.GRP',0
unk_A2A6        db  17h
                db 0AFh
                db    2
aTheChurch      db 10,'The Church'
unk_A2B4        db  0Ch
aBraveKnightWhe db 'Brave Knight, whenever you\re tired come to this church./'
                db 0FFh
                db    4
                db 0FFh
                db    1
unk_A2F2        db  0Ch
aBraveKnightWhe_0 db 'Brave Knight, whenever you\re weary, come here to rest. '
                db 0FFh
                db    2
                db 0FFh
                db    2
aTheHolySpiritW db 'The Holy Spirit will help you to regain your strength.'
                db 0FFh
                db    3
                db  0Dh
                db 0FFh
                db    1
aBraveKnightYou db 'Brave Knight, you look fatigued from battle. Why not rest awhile '
                db 'and let the Spirit heal you. '
                db 0FFh
                db    2
                db  2Fh ; /
aMayGodGoWithYo db 'May God go with you.'
                db 0FFh
                db    0
                db  11h
                db 0FFh
                db 0FFh
byte_A3E4       db 0
byte_A3E5       db 0

seg000          ends
                end     start
