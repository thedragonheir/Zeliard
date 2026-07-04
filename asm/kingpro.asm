include common.inc
include town.inc
                .286
                .model small

seg000          segment byte public 'CODE'
                assume cs:seg000, ds:seg000
                org 0A000h
start:
                dw offset sub_A004
                dw offset sub_A302

; =============== S U B R O U T I N E =======================================


sub_A004        proc near
                mov     es, word ptr ds:seg1
                mov     di, 8000h
                mov     si, offset vfs_king_grp
                mov     al, 2   ; fn2_segmented_load
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
                mov     si, offset place_name
                call    word ptr cs:Render_Pascal_String_1_proc
                call    sub_A114
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                call    sub_A3E8
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
                add     bx, bx
                jmp     cs:jpt_A073[bx] ; switch jump
sub_A06D        endp

; ---------------------------------------------------------------------------
jpt_A073        dw offset loc_A0E4
                dw offset get_1000_gold
                dw offset loc_A0D4
                dw offset loc_A092
                dw offset loc_A084
                dw offset loc_A08A
; ---------------------------------------------------------------------------

loc_A084:
                mov     byte_A79D, 0FFh
                retn
; ---------------------------------------------------------------------------

loc_A08A:
                xor     al, al
                mov     byte_A79D, al
                jmp     loc_A3A6
; ---------------------------------------------------------------------------

loc_A092:
                mov     al, 0FFh
                mov     byte_A7A0, al
                jmp     loc_A3A6
; ---------------------------------------------------------------------------

get_1000_gold:
                mov     cx, 10
loc_A09D:
                push    cx
                mov     ax, ds:hero_gold_lo
                mov     dl, ds:hero_gold_hi
                add     ax, 100
                adc     dl, 0
                mov     ds:hero_gold_lo, ax
                mov     ds:hero_gold_hi, dl
                call    word ptr cs:Print_Gold_Decimal_proc
                mov     byte ptr ds:soundFX_request, 19
                mov     byte ptr ds:frame_timer, 0
loc_A0C1:
                call    sub_A302
                cmp     byte ptr ds:frame_timer, 15
                jb      short loc_A0C1
                pop     cx
                loop    loc_A09D
                mov     byte ptr ds:spoke_to_king, 0FFh
                retn
; ---------------------------------------------------------------------------
loc_A0D4:
                mov     byte ptr ds:frame_timer, 0
loc_A0D9:
                call    sub_A302
                cmp     byte ptr ds:frame_timer, 150
                jb      short loc_A0D9
                retn
; ---------------------------------------------------------------------------

loc_A0E4:
                mov     si, offset byte_A0F8
                mov     cx, 12
loc_A0EA:
                push    cx
                lodsb
                push    si
                call    loc_A142
                call    loc_A104
                pop     si
                pop     cx
                loop    loc_A0EA
                retn
; ---------------------------------------------------------------------------
byte_A0F8       db 0, 0, 1, 2, 2, 1, 0, 3, 4, 4, 5, 6
; ---------------------------------------------------------------------------
loc_A104:
                mov     byte ptr ds:frame_timer, 0
loc_A109:
                call    sub_A302
                cmp     byte ptr ds:frame_timer, 25
                jb      short loc_A109
                retn

; =============== S U B R O U T I N E =======================================


sub_A114        proc near
                mov     si, offset byte_A16E
                mov     bx, 0E17h
                mov     cx, 8
loc_A11D:
                push    cx
                mov     cx, 12
loc_A121:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc ; gtmcga
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A121
                sub     bh, 0Ch
                add     bl, 8
                pop     cx
                loop    loc_A11D
                test    byte ptr ds:is_death_already_processed, 0FFh
                jnz     short loc_A140
                retn
; ---------------------------------------------------------------------------

loc_A140:
                mov     al, 6

loc_A142:
                mov     bl, al
                xor     bh, bh
                add     bx, bx
                mov     si, off_A1CE[bx]
                mov     bx, 1117h
                mov     cx, 7
loc_A152:
                push    cx
                mov     cx, 6
loc_A156:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc ; gtmcga
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A156
                sub     bh, 6
                add     bl, 8
                pop     cx
                loop    loc_A152
                retn
sub_A114        endp

; ---------------------------------------------------------------------------
byte_A16E       db 0, 1, 2, 3, 3Eh, 3Fh, 40h, 41h, 18h, 19h, 1Ah, 1Bh
                db 4, 5, 6, 7, 42h, 43h, 44h, 45h, 1Ch, 1Dh, 1Eh, 1Fh
                db 8, 9, 0Ah, 46h, 47h, 48h, 49h, 4Ah, 4Bh, 20h, 21h, 22h
                db 0Bh, 0Ch, 0Dh, 4Ch, 4Dh, 4Eh, 4Fh, 50h, 51h, 23h, 24h, 25h
                db 0Eh, 0Fh, 10h, 52h, 53h, 54h, 55h, 56h, 57h, 26h, 27h, 28h
                db 11h, 12h, 13h, 58h, 59h, 5Ah, 5Bh, 5Ch, 29h, 2Ah, 2Bh, 2Ch
                db 14h, 15h, 16h, 17h, 5Dh, 5Eh, 5Fh, 2Dh, 2Eh, 2Fh, 30h, 31h
                db 32h, 33h, 34h, 35h, 36h, 37h, 38h, 39h, 3Ah, 3Bh, 3Ch, 3Dh
off_A1CE        dw offset byte_A1DC
                dw offset byte_A206
                dw offset byte_A230
                dw offset byte_A25A
                dw offset byte_A284
                dw offset byte_A2AE
                dw offset byte_A2D8
byte_A1DC       db 3, 3Eh, 3Fh, 40h, 41h, 18h
                db 7, 42h, 43h, 44h, 45h, 1Ch
                db 46h, 47h, 48h, 49h, 4Ah, 4Bh
                db 4Ch, 4Dh, 4Eh, 4Fh, 50h, 51h
                db 52h, 53h, 54h, 55h, 56h, 57h
                db 58h, 59h, 5Ah, 5Bh, 5Ch, 29h
                db 17h, 5Dh, 5Eh, 5Fh, 2Dh, 2Eh
byte_A206       db 3, 3Eh, 3Fh, 40h, 41h, 18h
                db 7, 42h, 43h, 44h, 45h, 1Ch
                db 46h, 47h, 48h, 49h, 4Ah, 4Bh
                db 4Ch, 4Dh, 4Eh, 4Fh, 50h, 51h
                db 52h, 60h, 61h, 62h, 56h, 57h
                db 58h, 59h, 5Ah, 5Bh, 5Ch, 29h
                db 17h, 5Dh, 5Eh, 5Fh, 2Dh, 2Eh
byte_A230       db 3, 3Eh, 3Fh, 40h, 41h, 18h
                db 7, 42h, 43h, 44h, 45h, 1Ch
                db 46h, 47h, 48h, 49h, 4Ah, 4Bh
                db 4Ch, 4Dh, 4Eh, 4Fh, 50h, 51h
                db 52h, 63h, 64h, 65h, 56h, 57h
                db 58h, 59h, 5Ah, 5Bh, 5Ch, 29h
                db 17h, 5Dh, 5Eh, 5Fh, 2Dh, 2Eh
byte_A25A       db 3, 66h, 67h, 68h, 69h, 18h
                db 7, 6Ah, 6Bh, 6Ch, 6Dh, 1Ch
                db 6Eh, 6Fh, 70h, 71h, 72h, 73h
                db 74h, 75h, 76h, 77h, 78h, 79h
                db 7Ah, 7Bh, 7Ch, 7Dh, 7Eh, 7Fh
                db 80h, 81h, 82h, 83h, 84h, 29h
                db 17h, 85h, 86h, 87h, 2Dh, 2Eh
byte_A284       db 3, 88h, 89h, 8Ah, 8Bh, 18h
                db 7, 8Ch, 8Dh, 8Eh, 8Fh, 1Ch
                db 90h, 91h, 92h, 93h, 94h, 95h
                db 96h, 0ADh, 0ABh, 0AEh, 9Ah, 9Bh
                db 9Ch, 9Dh, 9Eh, 9Fh, 0A0h, 0A1h
                db 0A2h, 0A3h, 0A4h, 0A5h, 0A6h, 29h
                db 17h, 0A7h, 0A8h, 0A9h, 2Dh, 2Eh
byte_A2AE       db 3, 88h, 89h, 8Ah, 8Bh, 18h
                db 7, 8Ch, 8Dh, 8Eh, 8Fh, 1Ch
                db 90h, 91h, 92h, 93h, 94h, 95h
                db 96h, 0AAh, 0ABh, 0ACh, 9Ah, 9Bh
                db 9Ch, 9Dh, 9Eh, 9Fh, 0A0h, 0A1h
                db 0A2h, 0A3h, 0A4h, 0A5h, 0A6h, 29h
                db 17h, 0A7h, 0A8h, 0A9h, 2Dh, 2Eh
byte_A2D8       db 3, 88h, 89h, 8Ah, 8Bh, 18h
                db 7, 8Ch, 8Dh, 8Eh, 8Fh, 1Ch
                db 90h, 91h, 92h, 93h, 94h, 95h
                db 96h, 97h, 98h, 99h, 9Ah, 9Bh
                db 9Ch, 9Dh, 9Eh, 9Fh, 0A0h, 0A1h
                db 0A2h, 0A3h, 0A4h, 0A5h, 0A6h, 29h
                db 17h, 0A7h, 0A8h, 0A9h, 2Dh, 2Eh

; =============== S U B R O U T I N E =======================================


sub_A302        proc near

                cmp     word ptr ds:tick_counter, 4
                jnb     short loc_A30A
                retn
; ---------------------------------------------------------------------------

loc_A30A:
                mov     word ptr ds:tick_counter, 0
                call    sub_A315
                jmp     short loc_A386
sub_A302        endp


; =============== S U B R O U T I N E =======================================


sub_A315        proc near
                test    byte_A7A0, 0FFh
                jnz     short loc_A31D
                retn
; ---------------------------------------------------------------------------

loc_A31D:
                inc     byte_A7A1
                cmp     byte_A7A1, 26
                jb      short loc_A338
                call    word ptr cs:get_random_proc
                or      al, al
                jz      short loc_A332
                retn
; ---------------------------------------------------------------------------

loc_A332:
                mov     byte_A7A1, 0FFh
                retn
; ---------------------------------------------------------------------------

loc_A338:
                mov     bx, offset byte_A360
                mov     al, byte_A7A1
                xlat
                xor     ah, ah
                add     ax, ax
                add     ax, ax
                mov     si, ax
                add     si, offset byte_A37A
                mov     bx, 112Fh
                mov     cx, 4

loc_A351:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc ; gtmcga
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A351
                retn
sub_A315        endp

; ---------------------------------------------------------------------------
byte_A360       db 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1
                db 1, 1, 1, 0, 0, 0, 0, 0
byte_A37A       db 96h, 97h, 98h, 99h, 96h, 0AAh, 0ABh, 0ACh, 96h, 0ADh, 0ABh, 0AEh
; ---------------------------------------------------------------------------

loc_A386:
                test    byte_A79D, 0FFh
                jnz     short loc_A38E
                retn
; ---------------------------------------------------------------------------

loc_A38E:
                inc     byte_A79E
                cmp     byte_A79E, 6
                jnb     short loc_A39A
                retn
; ---------------------------------------------------------------------------

loc_A39A:
                mov     byte_A79E, 0
                inc     byte_A79F
                mov     al, byte_A79F

loc_A3A6:
                and     al, 1
                mov     cl, 10
                mul     cl
                mov     si, ax
                add     si, offset byte_A3D4
                mov     bx, 113Fh
                mov     cx, 2

loc_A3B8:
                push    cx
                mov     cx, 5

loc_A3BC:
                push    cx
                push    bx
                lodsb
                call    word ptr cs:draw_tile_to_screen_proc ; gtmcga
                pop     bx
                inc     bh
                pop     cx
                loop    loc_A3BC
                sub     bh, 5
                add     bl, 8
                pop     cx
                loop    loc_A3B8
                retn
; ---------------------------------------------------------------------------
byte_A3D4       db 0A2h, 0A3h, 0A4h, 0A5h, 0A6h
                db 17h, 0A7h, 0A8h, 0A9h, 2Dh
                db 0AFh, 0B0h, 0B1h, 0B2h, 0B3h
                db 17h, 0B4h, 0B5h, 0B6h, 2Dh

; =============== S U B R O U T I N E =======================================


sub_A3E8        proc near
                mov     si, offset byte_A42F
                mov     al, ds:spoke_to_king
                or      al, ds:entered_cavern_first_time
                jnz     short loc_A3F5
                retn
; ---------------------------------------------------------------------------

loc_A3F5:
                mov     si, offset byte_A53C
                test    byte ptr ds:entered_cavern_first_time, 0FFh
                jnz     short loc_A400
                retn
; ---------------------------------------------------------------------------

loc_A400:
                mov     si, offset byte_A5D2
                test    byte ptr ds:is_death_already_processed, 0FFh
                jnz     short loc_A40B
                retn
; ---------------------------------------------------------------------------

loc_A40B:
                mov     si, offset byte_A6C1
                retn
sub_A3E8        endp

; ---------------------------------------------------------------------------
vfs_king_grp    db    1
                db  13h
aKingGrp        db 'KING.GRP', 0
place_name      db  13h
                db 0AFh
                db    0
aKingOfFelishik db 17, 'King of Felishika'
byte_A42F       db 0Ch
                db 0FFh
                db    0
                db 0FFh
                db    3
                db 0FFh
                db    4
aBraveDukeGarla db 'Brave Duke Garland, '
                db 0FFh
                db    5
                db 0FFh
                db    2
                db 0FFh
                db    4
aYouLlNeedMoney db 'you\ll need money for your journey./I&hereby bestow upon you 1000'
                db '&Golds.'
                db 0FFh
                db    5
                db 0FFh
                db    2
                db 0FFh
                db    1
                db  0Dh
                db 0FFh
                db    4
aGoToTownAndOut db 'Go to town and outfit yourself, then make haste to the labyrinth to defeat the forces of Jashiin. '
                db 'My kingdom and the life of my daughter are at stake.'
                db 0FFh
                db    5
                db  11h
                db 0FFh
                db 0FFh
byte_A53C       db 0Ch
                db 0FFh
                db    0
                db 0FFh
                db    3
                db 0FFh
                db    4
aBraveDukeDidYo db 'Brave Duke, did you forget something?'
                db 0FFh
                db    5
                db 0FFh
                db    2
                db  0Dh
                db 0FFh
                db    4
aTheEntranceToT db 'The entrance to the labyrinth is at the edge of town.'
                db 0FFh
                db    5
                db  0Dh
                db 0FFh
                db    4
aPleaseHurryBef db 'Please hurry, before it\s too late! '
                db 0FFh
                db    5
                db  11h
                db 0FFh
                db 0FFh
byte_A5D2       db 0Ch
                db 0FFh
                db    0
                db 0FFh
                db    3
                db 0FFh
                db    4
aDukeGarland    db 'Duke Garland, '
                db 0FFh
                db    5
                db 0FFh
                db    2
                db 0FFh
                db    4
aIAmInDebtToYou db 'I am in debt to you for your efforts. '
                db 0FFh
                db    5
                db 0FFh
                db    2
                db 0FFh
                db    4
aHaveYouNotYetS db 'Have you not yet succeeded in vanquishing Jashiin? '
                db 0FFh
                db    5
                db 0FFh
                db    2
                db  0Dh
                db 0FFh
                db    4
aIPrayThatTheSp db 'I pray that the spirits will guide you. Please don\t give up, the people of Zeliard are depending on you!'
                db 0FFh
                db    5
                db  11h
                db 0FFh
                db 0FFh
byte_A6C1       db 0Ch
                db 0FFh
                db    3
                db 0FFh
                db    4
aDukeGarland_0  db 'Duke Garland, '
                db 0FFh
                db    5
                db 0FFh
                db    2
                db 0FFh
                db    4
aYouAreABraveMa db 'you are a brave man. You have conquered Jashiin and returned the nine Tears of Esmesanti. '
                db 0FFh
                db    5
                db 0FFh
                db    2
                db  0Dh
                db 0FFh
                db    4
aNowGoQuicklyTo db 'Now go quickly to the chamber of Princess Felicia. The&crystals will bring her back to life. '
                db 0FFh
                db    5
                db  11h
                db 0FFh
                db 0FFh
byte_A79D       db 0
byte_A79E       db 0
byte_A79F       db 0
byte_A7A0       db 0
byte_A7A1       db 0

seg000          ends
                end    start
