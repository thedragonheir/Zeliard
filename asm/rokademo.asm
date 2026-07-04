include common.inc
include gdmcga.inc
                .286
                .model small
seg000          segment byte public 'CODE'
                assume cs:seg000, ds:seg000
                org 0A000h
start:
                dw offset sub_A002

sub_A002        proc near
                mov     si, offset vfs_mfan_msd
                mov     es, word ptr cs:seg1
                mov     di, 3000h
                mov     al, 5           ; fn_5_load_music
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, offset vfs_dman_grp
                mov     di, 6000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc ; fn2_segmented_load
                push    ds
                mov     ds, word ptr cs:seg1
                mov     si, 6000h
                mov     bp, 0D000h
                mov     cx, 100h
                call    word ptr cs:Render_Animated_Tile_Rows_proc
                                        ;  DS:SI - compressed data (will be unpacked in place)
                                        ;  BP - transparency masks buffer
                                        ;  CX - number of 8x8 tiles to decompress
                pop     ds
                inc     byte ptr ds:Tears_of_Esmesanti_count
                mov     al, 0           ; small blue Tear
                cmp     byte ptr ds:Tears_of_Esmesanti_count, 9
                jb      short loc_A04F
                mov     byte ptr ds:Tears_of_Esmesanti_count, 9
                mov     al, 1           ; big red Tear

loc_A04F:
                mov     byte_A5A4, al
                mov     bx, 2552h
                call    word ptr cs:Render_Icon_16x13_proc
                                        ; ; AL: tear index (0-small blue Tear, 1-large red Tear)
                                        ; ; BH: left margin
                                        ; ; BL: top margin
                and     byte ptr ds:facing_direction, 0FEh
                mov     bx, 0C6Eh
                mov     cx, 0Dh

loc_A065:
                test    cx, 1
                jnz     short loc_A070
                mov     byte ptr ds:soundFX_request, 26

loc_A070:
                push    cx
                push    bx
                inc     byte ptr ds:hero_animation_phase
                and     byte ptr ds:hero_animation_phase, 3
                call    sub_A407
                call    sub_A48F
                pop     bx
                cmp     bh, 24h ; '$'
                jz      short loc_A096
                push    bx
                mov     cx, 218h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                pop     bx
                add     bh, 2

loc_A096:
                pop     cx
                loop    loc_A065
                mov     byte ptr ds:hero_animation_phase, 4
                mov     bx, 246Eh
                call    sub_A407
                mov     cx, 5

loc_A0A7:
                push    cx
                call    sub_A48F
                pop     cx
                loop    loc_A0A7
                mov     byte ptr ds:hero_animation_phase, 5

loc_A0B3:
                mov     bx, 246Eh
                call    sub_A407
                call    sub_A48F
                call    sub_A48F
                inc     byte ptr ds:hero_animation_phase
                cmp     byte ptr ds:hero_animation_phase, 9
                jb      short loc_A0B3
                mov     bx, 246Eh
                call    sub_A407
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                xor     bh, bh
                mov     bl, byte ptr ds:Tears_of_Esmesanti_count
                dec     bx
                mov     al, byte_A569[bx]
                mov     byte_A59A, al
                mov     byte_A59B, 2
                call    sub_A4A3
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Capture_Screen_Rect_to_seg3_proc
                mov     byte_A5A5, 0

loc_A107:
                mov     al, byte_A5A5
                mov     bl, byte_A59C
                xor     bh, bh
                mov     cl, byte_A59D
                call    word ptr cs:Pack_3Plane_And_Render_proc
                call    sub_A48F
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                inc     byte_A5A5
                cmp     byte_A5A5, 2
                jb      short loc_A107
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                sub     ah, 6
                mov     al, byte_A59D
                mov     cx, 1110h
                xor     di, di
                call    word ptr cs:Capture_Screen_Rect_to_seg3_proc
                mov     byte ptr ds:soundFX_request, 27
                mov     byte_A5A5, 0

loc_A162:
                mov     al, byte_A5A5
                or      al, 80h
                mov     bl, byte_A59C
                xor     bh, bh
                sub     bx, 18h
                mov     cl, byte_A59D
                call    word ptr cs:Pack_3Plane_And_Render_proc
                call    sub_A48F
                call    sub_A48F
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                sub     ah, 6
                mov     al, byte_A59D
                mov     cx, 1110h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                inc     byte_A5A5
                cmp     byte_A5A5, 2
                jb      short loc_A162
                mov     bx, 2552h
                mov     cx, 410h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Capture_Screen_Rect_to_seg3_proc
                mov     byte_A5A5, 0

loc_A1D2:
                mov     al, byte_A5A5
                mov     bl, byte_A59C
                xor     bh, bh
                mov     cl, byte_A59D
                call    word ptr cs:Pack_3Plane_And_Render_proc
                call    sub_A48F
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                inc     byte_A5A5
                cmp     byte_A5A5, 4
                jb      short loc_A1D2
                mov     byte_A5A7, 0C8h

loc_A20E:
                inc     byte_A5A6
                test    byte_A5A6, 1
                jnz     short loc_A232
                inc     byte_A5A5
                inc     byte_A5A7
                cmp     byte_A5A7, 3
                jb      short loc_A232
                mov     byte_A5A7, 0
                mov     byte ptr ds:soundFX_request, 28

loc_A232:
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                call    sub_A50A
                pushf
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Capture_Screen_Rect_to_seg3_proc
                mov     al, byte_A5A5
                and     al, 1
                add     al, 2
                mov     bl, byte_A59C
                xor     bh, bh
                mov     cl, byte_A59D
                call    word ptr cs:Pack_3Plane_And_Render_proc
                call    sub_A48F
                popf
                jnb     short loc_A20E
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                sub     ah, 6
                mov     al, byte_A59D
                mov     cx, 1110h
                xor     di, di
                call    word ptr cs:Capture_Screen_Rect_to_seg3_proc
                mov     byte ptr ds:soundFX_request, 27
                mov     byte_A5A5, 0

loc_A2BB:
                mov     al, byte_A5A5
                or      al, 80h
                mov     bl, byte_A59C
                xor     bh, bh
                sub     bx, 18h
                mov     cl, byte_A59D
                call    word ptr cs:Pack_3Plane_And_Render_proc
                call    sub_A48F
                call    sub_A48F
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                sub     ah, 6
                mov     al, byte_A59D
                mov     cx, 1110h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                inc     byte_A5A5
                cmp     byte_A5A5, 2
                jb      short loc_A2BB
                mov     al, byte_A5A4
                mov     bl, byte ptr ds:Tears_of_Esmesanti_count
                dec     bl
                xor     bh, bh
                add     bx, bx
                mov     bx, tears_coords[bx]
                call    word ptr cs:Render_Icon_16x13_proc
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Capture_Screen_Rect_to_seg3_proc
                mov     byte_A5A5, 4

loc_A32F:
                mov     al, byte_A5A5
                dec     al
                mov     bl, byte_A59C
                xor     bh, bh
                mov     cl, byte_A59D
                call    word ptr cs:Pack_3Plane_And_Render_proc
                call    sub_A48F
                mov     ah, byte_A59C
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1
                mov     al, byte_A59D
                mov     cx, 310h
                xor     di, di
                call    word ptr cs:Put_Image_proc
                dec     byte_A5A5
                jnz     short loc_A32F
                push    ds
                mov     ds, word ptr cs:seg1
                mov     si, 3000h
                xor     ax, ax
                int     60h             ; adlib fn 0
                pop     ds

loc_A371:                               ;
                test    byte ptr ds:music_status_flag, 0FFh
                jz      short loc_A371
                mov     ax, 1
                int     60h             ; adlib fn_1
                mov     bx, 2456h
                mov     cx, 618h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:hero_animation_phase, 8

loc_A38F:
                mov     bx, 246Eh
                call    sub_A407
                call    sub_A48F
                call    sub_A48F
                dec     byte ptr ds:hero_animation_phase
                cmp     byte ptr ds:hero_animation_phase, 5
                jnb     short loc_A38F
                mov     bx, 246Eh
                call    sub_A407
                mov     cx, 5

loc_A3AF:
                push    cx
                call    sub_A48F
                pop     cx
                loop    loc_A3AF
                mov     bx, 246Eh
                mov     cx, 218h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                mov     bx, 266Eh
                mov     cx, 0Dh

loc_A3C9:
                test    cx, 1
                jnz     short loc_A3D4
                mov     byte ptr ds:soundFX_request, 26

loc_A3D4:
                push    cx
                push    bx
                inc     byte ptr ds:hero_animation_phase
                and     byte ptr ds:hero_animation_phase, 3
                call    sub_A407
                call    sub_A48F
                pop     bx
                cmp     bh, 3Eh ; '>'
                jz      short loc_A3FA
                push    bx
                mov     cx, 218h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                pop     bx
                add     bh, 2

loc_A3FA:
                pop     cx
                loop    loc_A3C9
                mov     cx, 618h
                xor     al, al
                jmp     word ptr cs:Draw_Bordered_Rectangle_proc
sub_A002        endp


; =============== S U B R O U T I N E =======================================


sub_A407        proc near
                mov     al, byte ptr ds:hero_animation_phase
                mov     cl, 9
                mul     cl
                add     ax, offset tiles_grouping3x3
                mov     si, ax
                mov     cx, 3

loc_A416:
                push    cx
                mov     cx, 3

loc_A41A:
                push    cx
                lodsb
                push    si
                push    bx
                call    word ptr cs:Render_Animated_Tiles_proc
                pop     bx
                pop     si
                add     bl, 8
                pop     cx
                loop    loc_A41A
                sub     bl, 24
                add     bh, 2
                pop     cx
                loop    loc_A416
                retn
sub_A407        endp

; ---------------------------------------------------------------------------
tiles_grouping3x3 db 0, 2, 4, 1, 3, 5, 0, 0, 6
                db 7, 9, 11, 8, 10, 12, 0, 0, 0
                db 0, 2, 14, 1, 13, 15, 0, 0, 16
                db 7, 9, 17, 8, 10, 18, 0, 0, 0
                db 0, 20, 22, 19, 21, 23, 0, 0, 24
                db 25, 0, 28, 26, 27, 29, 0, 0, 30
                db 31, 0, 35, 32, 33, 36, 0, 34, 37
                db 31, 0, 35, 32, 38, 40, 0, 39, 41
                db 31, 0, 35, 42, 44, 40, 43, 45, 41
                db 46, 49, 35, 47, 50, 52, 48, 51, 53

; =============== S U B R O U T I N E =======================================


sub_A48F        proc near
                mov     cl, byte ptr ds:speed_const
                mov     al, 4
                mul     cl

loc_A497:
                cmp     byte ptr ds:frame_timer, al
                jb      short loc_A497
                mov     byte ptr ds:frame_timer, 0
                retn
sub_A48F        endp


; =============== S U B R O U T I N E =======================================


sub_A4A3        proc near
                mov     byte_A59C, 94h
                mov     byte_A59D, 50h ; 'P'
                xor     cl, cl
                mov     al, byte_A59A
                sub     al, byte_A59C
                jz      short loc_A4C2
                jnb     short loc_A4C0
                neg     al
                dec     cl
                jmp     short loc_A4C2
; ---------------------------------------------------------------------------

loc_A4C0:
                inc     cl

loc_A4C2:
                mov     byte_A5A0, al
                mov     byte_A59E, cl
                xor     cl, cl
                mov     al, byte_A59B
                sub     al, byte_A59D
                jz      short loc_A4DE
                jnb     short loc_A4DC
                neg     al
                dec     cl
                jmp     short loc_A4DE
; ---------------------------------------------------------------------------

loc_A4DC:
                inc     cl

loc_A4DE:
                mov     byte_A5A1, al
                mov     byte_A59F, cl
                mov     al, byte_A5A0
                shr     al, 1
                mov     byte_A5A3, al
                mov     byte_A5A2, 0
                mov     al, byte_A5A0
                cmp     al, byte_A5A1
                jb      short loc_A4FC
                retn
; ---------------------------------------------------------------------------

loc_A4FC:
                mov     al, byte_A5A1
                shr     al, 1
                mov     byte_A5A3, al
                mov     byte_A5A2, 0FFh
                retn
sub_A4A3        endp


; =============== S U B R O U T I N E =======================================


sub_A50A        proc near
                test    byte_A5A2, 0FFh
                jnz     short loc_A53D
                mov     al, byte_A5A3
                sub     al, byte_A5A1
                jnb     short loc_A526
                add     al, byte_A5A0
                mov     ah, byte_A59F
                add     byte_A59D, ah

loc_A526:
                mov     byte_A5A3, al
                mov     al, byte_A59E
                add     byte_A59C, al
                mov     al, byte_A59A
                cmp     al, byte_A59C
                stc
                jnz     short loc_A53B
                retn
; ---------------------------------------------------------------------------

loc_A53B:
                clc
                retn
; ---------------------------------------------------------------------------

loc_A53D:
                mov     al, byte_A5A3
                sub     al, byte_A5A0
                jnb     short loc_A552
                add     al, byte_A5A1
                mov     ah, byte_A59E
                add     byte_A59C, ah

loc_A552:
                mov     byte_A5A3, al
                mov     al, byte_A59F
                add     byte_A59D, al
                mov     al, byte_A59B
                cmp     al, byte_A59D
                stc
                jnz     short loc_A567
                retn
; ---------------------------------------------------------------------------

loc_A567:
                clc
                retn
sub_A50A        endp

; ---------------------------------------------------------------------------
byte_A569       db 3Ch, 0F4h, 54h, 0DCh, 6Ch, 0C4h, 84h, 0ACh, 98h
tears_coords    dw 0F00h, 3D00h, 1500h, 3700h, 1B00h, 3100h, 2100h, 2B00h, 2600h
vfs_mfan_msd    db 2
                db 5Fh
aMfanMsd        db 'MFAN.MSD',0
vfs_dman_grp    db 2
                db 36h
aDmanGrp        db 'DMAN.GRP',0
byte_A59A       db 0
byte_A59B       db 0
byte_A59C       db 0
byte_A59D       db 0
byte_A59E       db 0
byte_A59F       db 0
byte_A5A0       db 0
byte_A5A1       db 0
byte_A5A2       db 0
byte_A5A3       db 0
byte_A5A4       db 0
byte_A5A5       db 0
byte_A5A6       db 0
byte_A5A7       db 0

seg000          ends
                end  start