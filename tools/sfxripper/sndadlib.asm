include common.inc
                .286
                .model small

; Note that music_seg intersects with game_seg
; music_seg region 0x0000-0x00FF is the same as game_seg region 0xff00-0xffff
segment_shift   equ 0ff00h

music_seg       segment byte public 'CODE' use16
                assume cs:music_seg, ds:music_seg
                org 1100h
start:

sound_drv_poll_farproc  proc far
                jmp     short loc_1104
; ---------------------------------------------------------------------------
                dw offset OPL_save_al_to_reg_ah ; AH: Register Index
                                                ; AL: Data
; ---------------------------------------------------------------------------

loc_1104:
                push    cs
                pop     ds
                call    sub_1188
                call    sub_15A3
                retf
sound_drv_poll_farproc  endp


; =============== S U B R O U T I N E =======================================


sub_110D        proc near
                mov     al, ds:(soundFX_request - segment_shift)
                mov     byte ptr ds:(soundFX_request - segment_shift), 0
                test    byte ptr ds:(sound_fx_toggle_by_f2 - segment_shift), 0FFh
                jz      short loc_111D
                retn
; ---------------------------------------------------------------------------

loc_111D:
                dec     al
                mov     ah, 7
                mul     ah
                add     ax, offset byte_1743
                mov     si, ax
                mov     al, [si]
                cmp     al, byte_20BC
                jnb     short loc_1131
                retn
; ---------------------------------------------------------------------------

loc_1131:
                mov     byte_20BC, al
                inc     si
                mov     di, offset byte_2076
                mov     cx, 2
                mov     bh, 1
                mov     bl, 4

loc_113F:
                call    sub_1166
                add     di, 23h ; '#'
                inc     bh
                inc     bl
                loop    loc_113F
                lodsw
                mov     word_20C0, ax
                mov     byte ptr ds:9, 0
                mov     byte_20BD, 7Fh
                mov     byte_20C2, 0
                mov     byte_20C3, 0
                jmp     int60_fn6
sub_110D        endp


; =============== S U B R O U T I N E =======================================


sub_1166        proc near
                lodsw
                mov     [di], ax
                mov     byte ptr [di+6], 1
                mov     byte ptr [di+8], 3
                mov     byte ptr [di+0Ah], 1
                mov     byte ptr [di+7], 7Fh
                mov     byte ptr [di+9], 0
                mov     byte ptr [di+5], 0
                mov     [di+4], bl
                mov     [di+22h], bh
                retn
sub_1166        endp


; =============== S U B R O U T I N E =======================================


sub_1188        proc near
                test    byte ptr ds:(soundFX_request - segment_shift), 0FFh
                jz      short loc_1192
                call    sub_110D

loc_1192:
                test    byte ptr ds:(exit_pending_flag - segment_shift), 0FFh
                jz      short loc_119A
                retn
; ---------------------------------------------------------------------------

loc_119A:
                push    cs
                pop     es
                mov     al, byte_20BD
                add     byte_20BE, al
                sbb     al, al
                mov     byte_20BF, al
                cld
                mov     di, offset byte_2076
                call    sub_11B4
                mov     di, offset byte_2099
                jmp     short $+2
sub_1188        endp


; =============== S U B R O U T I N E =======================================


sub_11B4        proc near

                test    byte ptr [di+5], 1
                jz      short loc_11BB
                retn
; ---------------------------------------------------------------------------

loc_11BB:
                mov     ax, offset sub_1458
                push    ax
                test    byte_20BF, 0FFh
                jz      short loc_11C7
                retn
; ---------------------------------------------------------------------------

loc_11C7:
                dec     byte ptr [di+6]
                jz      short loc_11DF
                mov     al, [di+0Ah]
                cmp     al, [di+6]
                jnb     short loc_11D5
                retn
; ---------------------------------------------------------------------------

loc_11D5:
                test    byte ptr [di+9], 10h
                jz      short loc_11DC
                retn
; ---------------------------------------------------------------------------

loc_11DC:
                jmp     loc_142D
; ---------------------------------------------------------------------------

loc_11DF:
                mov     si, [di]

loc_11E1:
                lodsb
                or      al, al
                js      short loc_11E9
                jmp     loc_13B0
; ---------------------------------------------------------------------------

loc_11E9:
                mov     bx, offset loc_11E1
                push    bx
                test    al, 40h
                jnz     short loc_11F4
                jmp     loc_1292
; ---------------------------------------------------------------------------

loc_11F4:
                cmp     al, 0D0h
                jnb     short loc_11FB
                jmp     loc_1367
; ---------------------------------------------------------------------------

loc_11FB:
                cmp     al, 0D8h
                jnb     short loc_1202
                jmp     loc_1397
; ---------------------------------------------------------------------------

loc_1202:
                cmp     al, 0E0h
                jnb     short loc_1209
                jmp     loc_139D
; ---------------------------------------------------------------------------

loc_1209:
                and     al, 1Fh
                add     al, al
                mov     bl, al
                xor     bh, bh
                jmp     off_1215[bx]
; ---------------------------------------------------------------------------
off_1215        dw offset loc_1255
                dw offset loc_125A
                dw offset loc_125F
                dw offset loc_127D
                dw offset loc_1281
                dw offset loc_1285
                dw offset locret_1291
                dw offset loc_128C
                dw offset locret_1291
                dw offset locret_1291
                dw offset locret_1291
                dw offset locret_1291
                dw offset locret_1291
                dw offset locret_1291
                dw offset locret_1291
                dw offset locret_1291
                dw offset loc_14FA
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset locret_150B
                dw offset loc_150C
; ---------------------------------------------------------------------------

loc_1255:
                lodsb
                mov     byte_20BD, al
                retn
; ---------------------------------------------------------------------------

loc_125A:
                lodsb
                mov     [di+0Fh], al
                retn
; ---------------------------------------------------------------------------

loc_125F:
                and     byte ptr [di+5], 0BFh
                lodsb
                or      al, al
                jnz     short loc_1269
                retn
; ---------------------------------------------------------------------------

loc_1269:
                or      byte ptr [di+5], 40h
                push    di
                add     di, 1Ah
                mov     [di-1], al
                movsw
                movsw
                movsb
                pop     di
                and     byte ptr [di+9], 0FDh
                retn
; ---------------------------------------------------------------------------

loc_127D:
                dec     byte ptr [di+8]
                retn
; ---------------------------------------------------------------------------

loc_1281:
                inc     byte ptr [di+8]
                retn
; ---------------------------------------------------------------------------

loc_1285:
                lodsb
                mov     [di+7], al
                jmp     sub_1319
; ---------------------------------------------------------------------------

loc_128C:
                or      byte ptr [di+9], 20h
                retn
; ---------------------------------------------------------------------------

locret_1291:
                retn
; ---------------------------------------------------------------------------

loc_1292:
                and     al, 3Fh
                push    si
                mov     cl, 9
                mul     cl
                add     ax, offset byte_2020
                mov     si, ax
                mov     [di+20h], si
                mov     bl, [di+4]
                xor     bh, bh
                mov     ah, byte_159A[bx]
                mov     al, 0FFh
                add     ah, 40h ; '@'
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                add     ah, 3
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                sub     ah, 23h
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                add     ah, 3
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                add     ah, 1Dh
                lodsb
                lodsb
                add     ah, 20h ; ' '
                mov     cx, 2

loc_12D1:
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                add     ah, 3
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                add     ah, 1Dh
                loop    loc_12D1
                add     ah, 40h
                lodsb
                mov     bl, al
                rol     al, 1
                rol     al, 1
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                add     ah, 3
                rol     al, 1
                rol     al, 1
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                mov     ah, [di+4]
                mov     al, bl
                and     al, 0Fh
                mov     [di+0Bh], al
                add     ah, 0C0h
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                              ; AL: Data
                call    sub_1319
                pop     si
                mov     al, [di+22h]
                or      byte_20C3, al
                call    int60_fn6
                jmp     loc_142D
sub_11B4        endp ; sp-analysis failed


; =============== S U B R O U T I N E =======================================


sub_1319        proc near
                push    si
                mov     si, [di+20h]
                mov     bl, [di+4]
                xor     bh, bh
                mov     ah, byte_159A[bx]
                add     ah, 40h ; '@'
                mov     bl, [di+7]
                shr     bl, 1
                mov     al, [si+2]
                test    byte ptr [di+0Bh], 1
                jz      short loc_1348
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                cmp     al, 40h ; '@'
                jb      short loc_1343
                mov     al, 3Fh ; '?'

loc_1343:
                and     bh, 0C0h
                or      al, bh

loc_1348:                               ; AH: Register Index
                call    OPL_save_al_to_reg_ah ; AL: Data
                add     ah, 3
                mov     al, [si+3]
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                cmp     al, 40h ; '@'
                jb      short loc_135D
                mov     al, 3Fh ; '?'

loc_135D:
                and     bh, 0C0h
                or      al, bh
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                pop     si
                retn
sub_1319        endp

; ---------------------------------------------------------------------------

loc_1367:
                mov     bl, [di+7]
                and     al, 0Fh
                shl     al, 1
                shl     al, 1
                shl     al, 1
                shl     al, 1
                sar     al, 1
                sar     al, 1
                or      al, al
                js      short loc_1389
                add     al, 4
                sub     bl, al
                test    bl, 0C0h
                jz      short loc_1392
                xor     bl, bl
                jmp     short loc_1392
; ---------------------------------------------------------------------------

loc_1389:
                sub     bl, al
                test    bl, 0C0h
                jz      short loc_1392
                mov     bl, 3Fh ; '?'

loc_1392:
                mov     [di+7], bl
                jmp     short sub_1319
; ---------------------------------------------------------------------------

loc_1397:
                and     al, 7
                mov     [di+8], al
                retn
; ---------------------------------------------------------------------------

loc_139D:
                xor     bx, bx
                and     al, 7
                mov     bl, al
                mov     ax, [di+2]
                push    di
                mov     di, ax
                mov     al, [bx+di]
                pop     di
                mov     [di+0Ah], al
                retn
; ---------------------------------------------------------------------------

loc_13B0:
                mov     [di], si
                and     byte ptr [di+9], 0EFh
                cmp     byte ptr [si], 0E7h
                jnz     short loc_13BF
                or      byte ptr [di+9], 10h

loc_13BF:
                mov     dl, al
                mov     bx, [di+2]
                shr     dl, 1
                shr     dl, 1
                shr     dl, 1
                shr     dl, 1
                xor     dh, dh
                add     bx, dx
                mov     dl, [bx]
                mov     [di+6], dl
                mov     dl, al
                and     al, 0Fh
                jz      short loc_142D
                cmp     al, 0Fh
                jnz     short loc_13E0
                retn
; ---------------------------------------------------------------------------

loc_13E0:
                call    sub_1409
                mov     al, [di+9]
                and     byte ptr [di+9], 0DFh
                test    al, 20h
                jnz     short loc_1407
                push    dx
                mov     al, [di+19h]
                mov     [di+13h], al
                mov     word ptr [di+10h], 0
                mov     byte ptr [di+12h], 80h
                and     byte ptr [di+9], 0FDh
                pop     dx
                or      byte ptr [di+9], 40h

loc_1407:
                jmp     short loc_1433

; =============== S U B R O U T I N E =======================================


sub_1409        proc near
                dec     al
                xor     ah, ah
                mov     bx, ax
                mov     al, byte_158E[bx]
                mov     [di+18h], al
                add     bx, bx
                mov     al, [di+0Fh]
                cbw
                add     ax, word_1576[bx]
                mov     ch, [di+8]
                shl     ch, 1
                shl     ch, 1
                or      ah, ch
                mov     [di+0Dh], ax
                retn
sub_1409        endp

; ---------------------------------------------------------------------------

loc_142D:
                and     byte ptr [di+9], 0BFh
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_1433:
                mov     cx, [di+0Dh]
                add     cx, [di+10h]
                and     ch, 1Fh
                mov     al, [di+9]
                and     al, 40h
                shr     al, 1
                or      ch, al
                mov     ah, [di+4]
                add     ah, 0A0h
                mov     al, cl
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 10h
                mov     al, ch
                jmp     OPL_save_al_to_reg_ah ; AH: Register Index
; END OF FUNCTION CHUNK FOR sub_11B4    ; AL: Data

; =============== S U B R O U T I N E =======================================


sub_1458        proc near
                test    byte ptr [di+5], 40h
                jnz     short loc_145F
                retn
; ---------------------------------------------------------------------------

loc_145F:
                dec     byte ptr [di+13h]
                jz      short loc_1465
                retn
; ---------------------------------------------------------------------------

loc_1465:
                test    byte ptr [di+9], 2
                jnz     short loc_149F
                mov     al, [di+1Ah]
                mul     byte ptr [di+18h]
                mov     [di+14h], ax
                mov     al, [di+1Bh]
                mul     byte ptr [di+18h]
                mov     [di+16h], ax
                mov     al, [di+1Ch]
                mov     ah, [di+1Eh]
                and     ah, 80h
                jz      short loc_148B
                mov     al, [di+1Dh]

loc_148B:
                shr     al, 1
                mov     [di+1Fh], al
                mov     byte ptr [di+12h], 80h
                and     byte ptr [di+5], 7Fh
                or      [di+5], ah
                or      byte ptr [di+9], 2

loc_149F:
                mov     al, [di+1Eh]
                and     al, 1Fh
                mov     [di+13h], al
                dec     byte ptr [di+1Fh]
                jnz     short loc_14C8
                test    byte ptr [di+5], 80h
                jz      short loc_14BE
                mov     al, [di+1Ch]
                mov     [di+1Fh], al
                and     byte ptr [di+5], 7Fh
                jmp     short loc_14C8
; ---------------------------------------------------------------------------

loc_14BE:
                mov     al, [di+1Dh]
                mov     [di+1Fh], al
                or      byte ptr [di+5], 80h

loc_14C8:
                test    byte ptr [di+5], 80h
                jnz     short loc_14E4
                mov     cx, [di+14h]
                add     [di+12h], cl
                adc     ch, 0
                jnz     short loc_14DA
                retn
; ---------------------------------------------------------------------------

loc_14DA:
                mov     cl, ch
                xor     ch, ch
                add     [di+10h], cx
                jmp     loc_1433
; ---------------------------------------------------------------------------

loc_14E4:
                mov     cx, [di+16h]
                sub     [di+12h], cl
                adc     ch, 0
                jnz     short loc_14F0
                retn
; ---------------------------------------------------------------------------

loc_14F0:
                mov     cl, ch
                xor     ch, ch
                sub     [di+10h], cx
                jmp     loc_1433
sub_1458        endp

; ---------------------------------------------------------------------------
; START OF FUNCTION CHUNK FOR sub_11B4

loc_14FA:
                lodsb
                shl     al, 1
                shl     al, 1
                shl     al, 1
                xor     ah, ah
                add     ax, word_20C0
                mov     [di+2], ax
                retn
; ---------------------------------------------------------------------------

locret_150B:
                retn
; ---------------------------------------------------------------------------

loc_150C:
                pop     cx
                or      byte ptr [di+5], 1
                inc     byte_20C2
                cmp     byte_20C2, 2
                jz      short loc_151D
                retn
; ---------------------------------------------------------------------------

loc_151D:
                mov     byte ptr ds:9, 0FFh
                mov     byte_20BC, 0
                mov     byte_20C3, 0
; END OF FUNCTION CHUNK FOR sub_11B4

; =============== S U B R O U T I N E =======================================


int60_fn6       proc near
                mov     cl, byte_20C3
                mov     ax, 6
                int     60h             ; adlib fn_6
                retn
int60_fn6       endp


; =============== S U B R O U T I N E =======================================

; AH: Register Index
; AL: Data
OPL_save_al_to_reg_ah proc near
                push    dx
                push    ax
                mov     dx, 388h        ; Status/Index port
                xchg    ah, al          ; al: register Index
                out     dx, al
                in      al, dx          ; OPL2 needs 3.3us after Index write
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                mov     dx, 389h        ; AdLib Data port
                xchg    ah, al          ; al: Data
                out     dx, al          ; Send actual configuration/note data to previously selected register
                mov     dx, 388h        ; Status/Index port
                in      al, dx          ; OPL2 needs 23us delay after a data write
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                in      al, dx
                pop     ax
                pop     dx
                retn
OPL_save_al_to_reg_ah endp

; ---------------------------------------------------------------------------
word_1576       dw 156h, 16Bh, 180h, 197h, 1B0h, 1C9h, 1E4h, 201h, 220h
                dw 240h, 263h, 287h
byte_158E       db 13h, 14h, 15h, 16h, 18h, 19h, 1Bh, 1Ch, 1Eh, 20h, 22h
                db 24h
byte_159A       db 0, 1, 2, 8, 9, 0Ah, 10h, 11h, 12h

; =============== S U B R O U T I N E =======================================


sub_15A3        proc near
                test    byte ptr ds:(sound_fx_toggle_by_f2 - segment_shift), 0FFh
                jnz     short loc_15B8
                test    byte ptr ds:(byte_FF0B - segment_shift), 0FFh
                jnz     short loc_15B8
                test    byte ptr ds:(heartbeat_volume - segment_shift), 0FFh
                jnz     short loc_15D5

loc_15B8:
                test    byte_2071, 0FFh
                jnz     short loc_15C0
                retn
; ---------------------------------------------------------------------------

loc_15C0:
                mov     byte_2071, 0
                test    byte ptr ds:(exit_pending_flag - segment_shift), 0FFh
                jnz     short loc_15CD
                retn
; ---------------------------------------------------------------------------

loc_15CD:
                mov     ax, 6
                xor     cl, cl
                int     60h             ; adlib fn_6
                retn
; ---------------------------------------------------------------------------

loc_15D5:
                dec     byte_2072
                jz      short loc_15DC
                retn
; ---------------------------------------------------------------------------

loc_15DC:
                mov     byte_2072, 4
                inc     byte_2073
                mov     al, byte_2073
                mov     byte_2073, 0FFh
                cmp     al, 96h
                jb      short loc_15F2
                retn
; ---------------------------------------------------------------------------

loc_15F2:
                mov     byte_2073, al
                test    byte ptr ds:(exit_pending_flag - segment_shift), 0FFh
                jnz     short loc_15FD
                retn
; ---------------------------------------------------------------------------

loc_15FD:
                cmp     al, 1Eh
                jb      short loc_1603
                sub     al, 1Eh

loc_1603:
                push    ax
                xor     ah, ah
                mov     cl, 1Eh
                div     cl
                jnz     short loc_1611
                mov     byte_2075, 0FFh

loc_1611:
                pop     ax
                mov     ch, al
                shr     al, 1
                shr     al, 1
                shr     al, 1
                mov     ah, ds:(heartbeat_volume - segment_shift)
                sub     ah, al
                cmc
                sbb     al, al
                and     ah, al
                add     ah, ah
                add     ah, ah
                mov     al, ah
                or      al, al
                jz      short loc_15B8
                mov     byte_2074, al
                push    cx
                mov     ax, 6
                mov     cl, 3
                int     60h             ; adlib fn_6 - Fade Out channel
                call    sub_169E
                pop     cx
                neg     ch
                mov     cl, ch
                mov     ch, 0FFh
                add     cx, cx
                add     cx, 980h
                test    byte_2075, 0FFh
                jz      short loc_1674
                mov     ah, 0A4h
                mov     al, cl
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 10h
                mov     al, ch
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                mov     ah, 0A5h
                mov     al, cl
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 10h
                mov     al, ch
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                mov     byte_2075, 0

loc_1674:
                or      ch, 20h
                mov     ah, 0A4h
                mov     al, cl
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 10h
                mov     al, ch
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                mov     ah, 0A5h
                mov     al, cl
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 10h
                mov     al, ch
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                call    sub_16FE
                mov     byte_2071, 0FFh
                retn
sub_15A3        endp


; =============== S U B R O U T I N E =======================================


sub_169E        proc near
                mov     si, offset byte_173A
                mov     bx, 4
                call    sub_16AD
                mov     si, offset byte_173A
                mov     bx, 5
sub_169E        endp


; =============== S U B R O U T I N E =======================================


sub_16AD        proc near
                mov     ah, byte_159A[bx]
                push    bx
                add     ah, 20h ; ' '
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 3
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 3Dh ; '='
                lodsb
                lodsb
                mov     cx, 2

loc_16C8:
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 3
                lodsb
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 1Dh
                loop    loc_16C8
                add     ah, 40h ; '@'
                lodsb
                mov     bl, al
                rol     al, 1
                rol     al, 1
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 3
                rol     al, 1
                rol     al, 1
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                mov     al, bl
                and     al, 0Fh
                pop     bx
                mov     ah, bl
                add     ah, 0C0h
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                jmp     short $+2
sub_16AD        endp


; =============== S U B R O U T I N E =======================================


sub_16FE        proc near
                mov     bx, 4
                call    sub_1707
                mov     bx, 5
sub_16FE        endp


; =============== S U B R O U T I N E =======================================


sub_1707        proc near
                mov     si, offset byte_173A
                mov     ah, byte_159A[bx]
                add     ah, 40h ; '@'
                mov     al, [si+2]
                call    OPL_save_al_to_reg_ah ; AH: Register Index
                                        ; AL: Data
                add     ah, 3
                mov     bl, byte_2074
                neg     bl
                add     bl, 3Fh ; '?'
                mov     al, [si+3]
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                cmp     al, 40h ; '@'
                jb      short loc_1732
                mov     al, 3Fh ; '?'

loc_1732:
                and     bh, 0C0h
                or      al, bh
                jmp     OPL_save_al_to_reg_ah ; AH: Register Index
sub_1707        endp                    ; AL: Data

; ---------------------------------------------------------------------------
byte_173A       db 20h, 21h, 4, 0, 0F8h, 0F4h, 8Fh, 8Fh, 40h
byte_1743       db 0, 0Ah, 19h, 1Fh, 20h, 14h, 19h
                db 0FFh, 15h, 19h, 1Fh, 20h, 23h, 19h
                db 0, 24h, 19h, 31h, 19h, 3Ch, 19h
                db 0, 3Eh, 19h, 4Ah, 19h, 55h, 19h
                db 0, 57h, 19h, 1Fh, 20h, 61h, 19h
                db 1, 62h, 19h, 78h, 19h, 89h, 19h
                db 9, 8Ah, 19h, 9Dh, 19h, 0AEh, 19h
                db 9, 0B0h, 19h, 0BAh, 19h, 0C6h, 19h
                db 8, 0C9h, 19h, 0D8h, 19h, 0E5h, 19h
                db 7, 0E6h, 19h, 1Fh, 20h, 0F0h, 19h
                db 0FFh, 0F1h, 19h, 0FEh, 19h, 0Bh, 1Ah
                db 0FFh, 0Dh, 1Ah, 17h, 1Ah, 1Fh, 1Ah
                db 0FFh, 20h, 1Ah, 2Ah, 1Ah, 32h, 1Ah
                db 0FFh, 33h, 1Ah, 3Fh, 1Ah, 49h, 1Ah
                db 0FFh, 4Ah, 1Ah, 87h, 1Ah, 0ACh, 1Ah
                db 9, 0ADh, 1Ah, 1Fh, 20h, 0BAh, 1Ah
                db 9, 0BCh, 1Ah, 0BCh, 1Ah, 0CAh, 1Ah
                db 9, 0CCh, 1Ah, 0DCh, 1Ah, 0EAh, 1Ah
                db 0, 0ECh, 1Ah, 1Fh, 20h, 0F6h, 1Ah
                db 9, 0F7h, 1Ah, 2, 1Bh, 0Eh, 1Bh
                db 0, 10h, 1Bh, 21h, 1Bh, 29h, 1Bh
                db 0, 2Ah, 1Bh, 3Bh, 1Bh, 4Ah, 1Bh
                db 0, 4Bh, 1Bh, 1Fh, 20h, 55h, 1Bh
                db 0, 56h, 1Bh, 61h, 1Bh, 6Bh, 1Bh
                db 9, 6Dh, 1Bh, 8Ah, 1Bh, 99h, 1Bh
                db 0FFh, 9Dh, 1Bh, 0AAh, 1Bh, 0B5h, 1Bh
                db 0FFh, 0B6h, 1Bh, 0C3h, 1Bh, 0D5h, 1Bh
                db 0FFh, 0D8h, 1Bh, 1Fh, 20h, 0E6h, 1Bh
                db 0FFh, 0EAh, 1Bh, 1Fh, 20h, 4, 1Ch
                db 0FFh, 5, 1Ch, 11h, 1Ch, 25h, 1Ch
                db 0FFh, 29h, 1Ch, 37h, 1Ch, 43h, 1Ch
                db 0FFh, 45h, 1Ch, 59h, 1Ch, 69h, 1Ch
                db 9, 6Ch, 1Ch, 7Ch, 1Ch, 8Bh, 1Ch
                db 9, 8Eh, 1Ch, 9Ah, 1Ch, 0A4h, 1Ch
                db 9, 0A6h, 1Ch, 0B7h, 1Ch, 0C6h, 1Ch
                db 9, 0C7h, 1Ch, 0D3h, 1Ch, 0DDh, 1Ch
                db 9, 0DFh, 1Ch, 0F1h, 1Ch, 0FBh, 1Ch
                db 1, 0FDh, 1Ch, 1Fh, 20h, 11h, 1Dh
                db 1, 12h, 1Dh, 1Fh, 20h, 26h, 1Dh
                db 9, 28h, 1Dh, 56h, 1Dh, 68h, 1Dh
                db 9, 6Ah, 1Dh, 79h, 1Dh, 87h, 1Dh
                db 0, 88h, 1Dh, 0A1h, 1Dh, 0B8h, 1Dh
                db 0, 0BAh, 1Dh, 1Fh, 20h, 0C4h, 1Dh
                db 9, 0C5h, 1Dh, 0F5h, 1Dh, 0Ch, 1Eh
                db 9, 0Fh, 1Eh, 20h, 1Eh, 2Ch, 1Eh
                db 9, 2Dh, 1Eh, 3Eh, 1Eh, 46h, 1Eh
                db 9, 48h, 1Eh, 5Bh, 1Eh, 65h, 1Eh
                db 1, 67h, 1Eh, 71h, 1Eh, 86h, 1Eh
                db 0, 88h, 1Eh, 92h, 1Eh, 9Ah, 1Eh
                db 0, 9Bh, 1Eh, 0AAh, 1Eh, 0B7h, 1Eh
                db 9, 0BAh, 1Eh, 0CBh, 1Eh, 0DAh, 1Eh
                db 9, 0DBh, 1Eh, 0E9h, 1Eh, 0F6h, 1Eh
                db 8, 0F7h, 1Eh, 3, 1Fh, 0Dh, 1Fh
                db 0, 0Eh, 1Fh, 27h, 1Fh, 36h, 1Fh
                db 9, 38h, 1Fh, 68h, 1Fh, 7Fh, 1Fh
                db 0, 82h, 1Fh, 1Fh, 20h, 8Fh, 1Fh
                db 9, 91h, 1Fh, 0A2h, 1Fh, 0B0h, 1Fh
                db 0, 0B2h, 1Fh, 1Fh, 20h, 0BFh, 1Fh
                db 0, 0C1h, 1Fh, 1Fh, 20h, 0DEh, 1Fh
                db 9, 0E0h, 1Fh, 1Fh, 20h, 0EBh, 1Fh
                db 0FFh, 0ECh, 1Fh, 1Fh, 20h, 0F6h, 1Fh
                db 0FFh, 0F7h, 1Fh, 1Fh, 20h, 0F6h, 1Fh
                db 0FFh, 1, 20h, 1Fh, 20h, 0F6h, 1Fh
                db 0FFh, 0Bh, 20h, 1Fh, 20h, 0F6h, 1Fh
                db 0FFh, 15h, 20h, 1Fh, 20h, 0F6h, 1Fh
                db 0F0h, 0, 0E0h, 7Fh, 87h, 0E5h, 7
                db 0D5h, 5, 0FFh, 3, 0F0h, 0, 0E0h
                db 37h, 83h, 0E5h, 7, 0D5h, 8, 0Ah
                db 0Ch, 0E4h, 1, 0FFh, 0Ch, 0F0h, 0
                db 0E0h, 46h, 0E5h, 7, 80h, 0D5h, 1
                db 81h, 0D4h, 11h, 0FFh, 0F0h, 0, 0E5h
                db 17h, 80h, 0D3h, 1, 81h, 0D1h, 11h
                db 0FFh, 3, 18h, 0F0h, 0, 0E0h, 9Bh
                db 82h, 0E5h, 7, 0D6h, 1, 0, 1Ah
                db 0FFh, 0F0h, 0, 82h, 0E5h, 7, 0D3h
                db 1, 0, 0D6h, 11h, 0FFh, 3, 0Ch
                db 0F0h, 0, 0E0h, 0, 87h, 0E5h, 7
                db 0D4h, 1, 0FFh, 12h, 0F0h, 0, 0E0h
                db 69h, 0E5h, 7, 83h, 0E2h, 1, 1
                db 0FEh, 2, 0FFh, 81h, 0D2h, 3, 82h
                db 0E2h, 0, 0D6h, 2, 0FFh, 0F0h, 0
                db 0E5h, 17h, 83h, 0E2h, 1, 1, 0FEh
                db 2, 0FFh, 81h, 0D1h, 9, 84h, 1
                db 0FFh, 0Ch, 0F0h, 0, 0E0h, 69h, 86h
                db 0E5h, 7, 0E2h, 1, 1, 0FFh, 2
                db 0FFh, 90h, 0D1h, 5, 0D1h, 17h, 0FFh
                db 0F0h, 0, 82h, 0E5h, 0Fh, 0E2h, 1
                db 0, 0FFh, 2, 2, 1, 0D2h, 5
                db 0D1h, 17h, 0FFh, 0Ch, 18h, 0F0h, 0
                db 0E0h, 0, 0E5h, 7, 84h, 1, 11h
                db 0FFh, 0F0h, 0, 0E5h, 7, 88h, 0D2h
                db 1, 20h, 0D3h, 21h, 20h, 0FFh, 6
                db 9, 3, 0F0h, 0, 0E0h, 37h, 0E5h
                db 7, 88h, 0D1h, 0Ch, 0E7h, 0E4h, 3
                db 0E7h, 1, 0FFh, 0F0h, 0, 0E5h, 7
                db 88h, 0D1h, 0Bh, 0E7h, 9, 0E7h, 0D5h
                db 1, 0FFh, 6, 0F0h, 0, 0E0h, 69h
                db 0E5h, 7, 82h, 0D5h, 3, 0FFh, 18h
                db 0F0h, 0, 0E0h, 9Bh, 0E5h, 7, 83h
                db 0D8h, 0D5h, 13h, 14h, 16h, 0FFh, 0F0h
                db 0, 0E5h, 7, 83h, 0D8h, 0D7h, 1Bh
                db 0D3h, 15h, 0E4h, 13h, 0FFh, 2, 6
                db 0F0h, 0, 0E0h, 9Bh, 0E5h, 7, 87h
                db 0D5h, 7, 0FFh, 0F0h, 0, 0E5h, 7
                db 87h, 0D5h, 0Bh, 0FFh, 6, 0F0h, 0
                db 0E0h, 9Bh, 0E5h, 7, 87h, 0D5h, 3
                db 0FFh, 0F0h, 0, 0E5h, 7, 87h, 0D5h
                db 7, 0FFh, 6, 0F0h, 0, 0E0h, 9Bh
                db 0E5h, 7, 87h, 0D6h, 8, 8, 4
                db 0FFh, 0F0h, 0, 0E5h, 7, 87h, 0D5h
                db 9, 1, 0Bh, 0FFh, 6, 0F0h, 0
                db 83h, 0E2h, 1, 40h, 40h, 11h, 41h
                db 81h, 0D2h, 0E5h, 7, 0E0h, 9Bh, 6
                db 0CEh, 0E0h, 91h, 6, 0CEh, 0E0h, 87h
                db 6, 0CEh, 0E0h, 7Dh, 6, 0CEh, 0E0h
                db 73h, 6, 0CEh, 0E0h, 69h, 6, 0CEh
                db 0E0h, 5Fh, 6, 0CEh, 0E0h, 55h, 6
                db 0CEh, 0E0h, 4Bh, 6, 0CEh, 0E0h, 41h
                db 6, 0CEh, 0E0h, 37h, 6, 0CEh, 0E0h
                db 2Dh, 6, 0FFh, 0F0h, 0, 83h, 0E2h
                db 1, 40h, 40h, 21h, 11h, 81h, 0D0h
                db 0E5h, 17h, 0CDh, 1, 9, 0E4h, 0CDh
                db 1, 9, 0E4h, 0CDh, 1, 9, 0E4h
                db 0CDh, 1, 9, 0E4h, 0CDh, 1, 9
                db 0E4h, 0CDh, 1, 9, 0FFh, 18h, 0F0h
                db 0, 0E0h, 4Bh, 0E5h, 7, 87h, 0D8h
                db 0D5h, 1Ah, 0E3h, 1Ah, 0FFh, 6, 0Ch
                db 0F0h, 0, 0E0h, 4Bh, 0E5h, 7, 87h
                db 0D8h, 0D4h, 13h, 0E7h, 0E4h, 14h, 0FFh
                db 6, 0Ch, 0F0h, 0, 0E0h, 69h, 82h
                db 0E5h, 2Fh, 0D2h, 0Ah, 0E5h, 1Fh, 2
                db 0E5h, 7, 11h, 0FFh, 0F0h, 0, 84h
                db 0D3h, 0E5h, 2Fh, 1, 0E5h, 1Fh, 1
                db 0E5h, 7, 11h, 0FFh, 0Ch, 12h, 0F0h
                db 0, 0E0h, 7Fh, 87h, 0E5h, 7, 0D4h
                db 1, 0FFh, 3, 0F0h, 0, 0E0h, 9Bh
                db 82h, 0E5h, 7, 0D6h, 5, 15h, 0FFh
                db 0F0h, 0, 83h, 0E5h, 2Fh, 0E1h, 4
                db 0D4h, 5, 0E4h, 15h, 0FFh, 9, 3
                db 0F0h, 0, 0E0h, 9Bh, 83h, 0E5h, 7
                db 0E2h, 1, 40h, 40h, 21h, 21h, 81h
                db 0D4h, 3, 0FFh, 0F0h, 0, 82h, 0E5h
                db 7, 0D3h, 3, 0FFh, 3, 0F0h, 0
                db 0E0h, 9Bh, 87h, 0E5h, 7, 0E2h, 1
                db 40h, 40h, 21h, 21h, 81h, 0D1h, 8
                db 0FFh, 0F0h, 0, 83h, 0E5h, 27h, 0E2h
                db 1, 40h, 40h, 21h, 21h, 81h, 0D1h
                db 8, 0FFh, 3, 0F0h, 0, 0E0h, 46h
                db 0E5h, 7, 81h, 0D7h, 1, 0FFh, 0Ch
                db 0F0h, 0, 0E0h, 46h, 0E5h, 7, 0D2h
                db 82h, 1, 11h, 0FFh, 0F0h, 0, 0E5h
                db 7, 86h, 0D3h, 6, 0D4h, 16h, 0FFh
                db 0Ch, 18h, 0F0h, 0, 0E0h, 4Bh, 0E5h
                db 7, 0E2h, 1, 78h, 1, 2, 2
                db 1, 85h, 0D2h, 1, 0E7h, 0CEh, 11h
                db 0E7h, 0CEh, 11h, 0E7h, 0CEh, 11h, 0E7h
                db 0CEh, 21h, 0FFh, 0F0h, 0, 0E5h, 7
                db 81h, 0D3h, 1, 0D2h, 11h, 82h, 0D1h
                db 11h, 0D0h, 31h, 0FFh, 18h, 0Ch, 12h
                db 24h, 0F0h, 0, 0E0h, 9Bh, 80h, 0E5h
                db 7, 0D0h, 1, 0E5h, 5Fh, 1, 0FFh
                db 0F0h, 0, 80h, 0E5h, 7, 0D3h, 1
                db 0E5h, 5Fh, 1, 0FFh, 6, 0F0h, 0
                db 0E0h, 4Bh, 86h, 0E5h, 7, 0D5h, 8
                db 18h, 0D6h, 2Ah, 0FFh, 0F0h, 0, 86h
                db 0E5h, 7, 0E2h, 1, 28h, 28h, 3
                db 3, 1, 0D5h, 8, 18h, 0D7h, 23h
                db 0FFh, 3, 0Ch, 30h, 0F0h, 0, 0E0h
                db 5, 86h, 0E5h, 7, 0D5h, 8, 18h
                db 0D6h, 23h, 3Ah, 0FFh, 3, 0Ch, 18h
                db 60h, 0F0h, 0, 0E0h, 87h, 83h, 0E2h
                db 1, 40h, 40h, 3, 3, 1, 0E5h
                db 7, 0D5h, 3, 0E5h, 17h, 3, 0E5h
                db 7, 8, 0E5h, 17h, 8, 0FFh, 6
                db 0F0h, 0, 0E0h, 87h, 83h, 0E5h, 7
                db 0D5h, 1, 0, 16h, 0FFh, 0F0h, 0
                db 83h, 0E2h, 1, 40h, 40h, 5, 5
                db 2, 0E1h, 4, 0E5h, 17h, 20h, 0D5h
                db 1, 0, 36h, 0FFh, 3, 18h, 6
                db 12h, 0F0h, 0, 0E0h, 9Bh, 87h, 0E5h
                db 7, 0D5h, 1, 15h, 0E5h, 27h, 5
                db 0FFh, 0F0h, 0, 87h, 0E5h, 17h, 0
                db 0E1h, 2, 0D5h, 1, 15h, 0FFh, 6
                db 9, 0F0h, 0, 0E0h, 87h, 82h, 0E5h
                db 0Fh, 0D0h, 1, 0, 0E2h, 1, 80h
                db 80h, 3, 3, 1, 0D1h, 18h, 0FFh
                db 0F0h, 0, 83h, 0E2h, 1, 0, 0FFh
                db 0, 1Fh, 81h, 0E5h, 0Fh, 0D1h, 21h
                db 11h, 0FFh, 3, 24h, 6, 0F0h, 0
                db 0E0h, 9Bh, 0E5h, 7, 87h, 0D6h, 8
                db 0D5h, 1, 0D4h, 1, 0D5h, 18h, 0FFh
                db 0F0h, 0, 0E5h, 7, 82h, 0D3h, 5
                db 0D1h, 8, 84h, 0E5h, 0Fh, 0D5h, 21h
                db 0FFh, 6, 0Ch, 18h, 0F0h, 0, 0E0h
                db 9Bh, 83h, 0E5h, 7, 0D2h, 1, 0D1h
                db 16h, 0FFh, 0F0h, 0, 83h, 0E5h, 7
                db 0D2h, 7, 0D1h, 13h, 0FFh, 6, 0Ch
                db 0F0h, 0, 0E0h, 9Bh, 82h, 0E5h, 7
                db 0E2h, 1, 2, 2, 0Bh, 0DDh, 1
                db 0D1h, 1, 0FFh, 0F0h, 0, 88h, 0E5h
                db 0Fh, 0E2h, 1, 2, 2, 0Bh, 0DDh
                db 1, 0D1h, 1, 0FFh, 48h, 0F0h, 0
                db 0E0h, 0AFh, 83h, 0E5h, 7, 0D1h, 4
                db 0D1h, 13h, 0FFh, 0F0h, 0, 83h, 0E5h
                db 7, 0D4h, 2, 0D1h, 1Bh, 0FFh, 6
                db 0Ch, 0F0h, 0, 0E0h, 0AFh, 88h, 0E5h
                db 7, 0E2h, 1, 14h, 14h, 15h, 15h
                db 1, 0D3h, 1, 13h, 0FFh, 0F0h, 0
                db 88h, 0E5h, 0Fh, 0D1h, 3, 0D2h, 1Bh
                db 0FFh, 6, 0Ch, 0F0h, 0, 0E0h, 5
                db 82h, 0E5h, 7, 0D4h, 1, 0D1h, 0Ch
                db 0D4h, 1, 0D1h, 0Ch, 0D4h, 1, 0D1h
                db 0Ch, 0FFh, 18h, 0F0h, 0, 0E0h, 9Bh
                db 88h, 0E5h, 7, 0E2h, 1, 1, 1
                db 65h, 0C9h, 1, 0D3h, 4, 82h, 0D1h
                db 11h, 0FFh, 0Ch, 12h, 0F0h, 0, 0E0h
                db 4Bh, 88h, 0E5h, 7, 0E2h, 1, 1
                db 80h, 3, 3, 1, 0D3h, 4, 0D1h
                db 4, 0D5h, 2, 0D4h, 6, 0E2h, 1
                db 1Ch, 0E1h, 5, 9, 1, 0D1h, 3
                db 0D3h, 2, 0D5h, 5, 0D3h, 4, 0D1h
                db 4, 0D5h, 2, 0D4h, 6, 0D4h, 11h
                db 0FFh, 0F0h, 0, 84h, 0E5h, 17h, 1
                db 1, 1, 1, 1, 1, 1, 1
                db 1, 1, 1, 11h, 0FFh, 6, 30h
                db 0F0h, 0, 0E0h, 0, 83h, 0E5h, 7
                db 0D1h, 7, 0D1h, 0Ah, 0D4h, 2, 1
                db 0FFh, 0F0h, 0, 83h, 0E5h, 7, 0D2h
                db 1, 0D2h, 7, 0D3h, 0Bh, 0D1h, 7
                db 0FFh, 6, 0F0h, 0, 0E0h, 0, 83h
                db 0E5h, 17h, 0E2h, 1, 60h, 60h, 7
                db 7, 1, 0D5h, 7, 0E2h, 1, 60h
                db 78h, 7, 7, 1, 17h, 0FFh, 0F0h
                db 0, 83h, 0E5h, 17h, 0E2h, 1, 80h
                db 80h, 7, 7, 1, 0D5h, 8, 0E2h
                db 1, 80h, 0A0h, 7, 7, 1, 18h
                db 0FFh, 0Ch, 30h, 0F0h, 0, 0E0h, 0
                db 81h, 0E5h, 7, 0D2h, 0Ch, 0FFh, 60h
                db 0F0h, 0, 0E0h, 4Bh, 88h, 0E5h, 1Fh
                db 0E2h, 1, 1, 80h, 3, 3, 1
                db 0D3h, 4, 0D1h, 4, 0D5h, 2, 0D4h
                db 6, 0E2h, 1, 1Ch, 0E1h, 5, 9
                db 1, 0D1h, 3, 0D3h, 2, 0D5h, 5
                db 0D3h, 4, 0D1h, 4, 0D5h, 2, 0D4h
                db 6, 0D3h, 5, 0D4h, 11h, 0FFh, 0F0h
                db 0, 83h, 0E5h, 7, 0E2h, 1, 60h
                db 60h, 7, 7, 1, 0D5h, 1Ah, 0E2h
                db 1, 60h, 78h, 7, 7, 1, 2Ah
                db 0FFh, 6, 30h, 48h, 0F0h, 0, 0E0h
                db 37h, 83h, 0E5h, 7, 0D3h, 0Ch, 0D5h
                db 6, 0D3h, 0Ah, 0D1h, 1, 1, 0FFh
                db 0F0h, 0, 84h, 0E5h, 7, 1, 1
                db 0D1h, 1, 1, 1, 0FFh, 3, 0F0h
                db 0, 0E0h, 0, 87h, 0E5h, 7, 0E2h
                db 1, 2, 2, 15h, 15h, 1, 0D3h
                db 0Ah, 0FFh, 0F0h, 0, 84h, 0E5h, 7
                db 0D3h, 1Ah, 0FFh, 15h, 0Ch, 0F0h, 0
                db 0E0h, 0AFh, 87h, 0E5h, 7, 0E2h, 1
                db 1, 0FFh, 2, 0FBh, 1, 0D2h, 1
                db 0D1h, 16h, 0FFh, 0F0h, 0, 82h, 0E5h
                db 17h, 0D2h, 7, 0D1h, 12h, 0FFh, 6
                db 0Ch, 0F0h, 0, 0E0h, 0AFh, 84h, 0E5h
                db 7, 0D1h, 1, 0FFh, 0F0h, 0, 83h
                db 0E5h, 7, 0E2h, 1, 0FFh, 80h, 2
                db 0FFh, 81h, 0D1h, 18h, 18h, 0E7h, 0E2h
                db 0, 0D0h, 18h, 0FFh, 24h, 0Ch, 0F0h
                db 0, 0E0h, 4Bh, 80h, 0E5h, 7, 0D1h
                db 5, 0FFh, 0F0h, 0, 80h, 0E5h, 7
                db 0D2h, 7, 0FFh, 6, 0F0h, 0, 0E0h
                db 0AFh, 84h, 0E5h, 7, 1, 0E5h, 1Fh
                db 1, 0E5h, 2Fh, 11h, 0FFh, 0F0h, 0
                db 82h, 0E5h, 7, 0D5h, 21h, 2Ah, 2Ch
                db 25h, 0D1h, 13h, 0FFh, 6, 18h, 3
                db 0F0h, 0, 0E0h, 0AFh, 84h, 0E5h, 7
                db 0E2h, 1, 2, 2, 0Bh, 0DDh, 1
                db 0D4h, 3, 0FFh, 0F0h, 0, 88h, 0E5h
                db 7, 0E2h, 1, 2, 2, 0Bh, 0DDh
                db 1, 0D2h, 1, 0FFh, 48h, 0F0h, 0
                db 0E0h, 5Fh, 84h, 0E5h, 7, 0D1h, 7
                db 0D1h, 8, 0D1h, 8, 0FFh, 0F0h, 0
                db 83h, 0E5h, 7, 0D1h, 0Ah, 0D3h, 7
                db 82h, 0D2h, 4, 0FFh, 0Ch, 0F0h, 0
                db 0E0h, 87h, 83h, 0E5h, 7, 0D2h, 1
                db 0D1h, 5, 0FFh, 0F0h, 0, 83h, 0E5h
                db 7, 0D2h, 7, 0D1h, 3, 0FFh, 6
                db 0F0h, 0, 0E0h, 0, 83h, 0E5h, 17h
                db 0D1h, 1, 0Ch, 8, 3, 1, 5
                db 6, 8, 0Ah, 0Ch, 1, 3, 3
                db 5, 6, 7, 0FFh, 0F0h, 0, 84h
                db 0E5h, 7, 0D3h, 11h, 18h, 11h, 16h
                db 1Ah, 11h, 13h, 16h, 0FFh, 3, 6
                db 0F0h, 0, 0E0h, 4Bh, 85h, 0E5h, 7
                db 0E2h, 1, 1, 40h, 3, 3, 1
                db 0D3h, 4, 0D1h, 4, 0D5h, 2, 0D4h
                db 6, 0E2h, 1, 1Ch, 64h, 5, 9
                db 1, 0D1h, 3, 0D3h, 2, 0D5h, 5
                db 0D3h, 4, 0D1h, 4, 0D5h, 2, 0D4h
                db 6, 0D3h, 5, 0D4h, 11h, 0FFh, 0F0h
                db 0, 84h, 0E5h, 7, 0E2h, 1, 60h
                db 60h, 7, 7, 1, 0D3h, 1Ah, 0E2h
                db 1, 60h, 78h, 7, 7, 1, 2Ah
                db 0FFh, 6, 30h, 48h, 0F0h, 0, 0E0h
                db 9Bh, 81h, 0E5h, 7, 0D4h, 1, 0E7h
                db 0D1h, 11h, 0FFh, 0Ch, 18h, 0F0h, 0
                db 0E0h, 9Bh, 83h, 0E5h, 7, 0D2h, 3
                db 0D1h, 0Ch, 0D1h, 6, 85h, 0D1h, 11h
                db 0FFh, 0F0h, 0, 84h, 0E5h, 7, 0D2h
                db 1, 0D1h, 6, 0D1h, 1, 0D2h, 11h
                db 0FFh, 2, 0Ch, 0F0h, 0, 0E0h, 4Bh
                db 88h, 0E5h, 7, 0D1h, 0Bh, 84h, 0D5h
                db 11h, 0FFh, 0Ch, 18h, 0F0h, 0, 0E0h
                db 9Bh, 83h, 0E2h, 1, 0FFh, 0FEh, 0FFh
                db 2, 1, 0D0h, 0E5h, 7, 3, 0E5h
                db 3Fh, 14h, 0E5h, 17h, 14h, 0E5h, 1Fh
                db 14h, 0E5h, 27h, 14h, 0FFh, 0Ch, 6
                db 0F0h, 0, 0E0h, 37h, 88h, 0D3h, 0E5h
                db 0Fh, 3, 0Ch, 0FFh, 0Ch, 0F0h, 0
                db 0E0h, 7Fh, 88h, 0E5h, 2Fh, 0D3h, 0Ch
                db 0FFh, 6, 0F0h, 0, 0E0h, 7Fh, 88h
                db 0E5h, 2Fh, 0D3h, 6, 0FFh, 0F0h, 0
                db 0E0h, 7Fh, 88h, 0E5h, 2Fh, 0D2h, 6
                db 0FFh, 0F0h, 0, 0E0h, 7Fh, 87h, 0E5h
                db 2Fh, 0D4h, 6, 0FFh, 0F0h, 0, 0E0h
                db 7Fh, 87h, 0E5h, 2Fh, 0D4h, 0Ch, 0FFh
                db 0FFh
byte_2020       db 0Fh, 0, 2, 0, 0FAh, 0F7h, 6Fh, 8Fh, 0Eh
                db 0Fh, 10h, 0, 80h, 0F0h, 45h, 46h, 0D8h, 8Eh
                db 3Fh, 25h, 40h, 0, 0F4h, 0F6h, 0A3h, 88h, 0Eh
                db 24h, 22h, 14h, 4, 0F3h, 0E4h, 6, 8, 0
                db 2Fh, 5, 0, 0, 0F3h, 0F4h, 0Fh, 0FFh, 0Eh
                db 20h, 21h, 40h, 0, 0F8h, 0F3h, 4Fh, 3Fh, 0
                db 32h, 22h, 0CAh, 0, 0F5h, 0F5h, 5Fh, 0FFh, 0Eh
                db 4, 2, 86h, 0, 0F2h, 0F6h, 3Ch, 5Dh, 0
                db 24h, 22h, 8Ah, 0, 0F5h, 0F5h, 6Fh, 6Fh, 80h
byte_2071       db 0
byte_2072       db 2
byte_2073       db 0
byte_2074       db 0
byte_2075       db 0
byte_2076       db 23h dup(0)
byte_2099       db 23h dup(0)
byte_20BC       db 0
byte_20BD       db 0
byte_20BE       db 0
byte_20BF       db 0
word_20C0       dw 0
byte_20C2       db 0
byte_20C3       db 0
music_seg       ends


                end    start
