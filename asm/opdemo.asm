include common.inc
include gdmcga.inc

                .286
                .model small

seg000          segment byte public 'CODE'
                assume cs:seg000, ds:seg000
                org 6000h
start:
                dw offset sub_6002

sub_6002        proc near

                cli
                mov     sp, 2000h
                sti
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                push    cs
                pop     ds
                call    word ptr cs:Clear_Screen_proc
                push    cs
                pop     ds
                push    cs
                pop     es
                mov     si, offset vfs_ttl3_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    RLE_decompress
                mov     ax, 4
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                xor     bx, bx
                mov     cl, 96h
                mov     si, offset copyright_str
                call    word ptr cs:Render_String_FF_Terminated_proc ; BX: starting X coord
                                                        ; CL: starting Y coord
                                                        ; SI: string pointer
                                                        ;   Control codes: 0Dh = newline, 80h-87h = color change
                mov     bx, 70Fh
                mov     cx, 4170h  ; width = 70h, height = 41h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_XOR_proc
                push    cs
                pop     es
                mov     si, offset vfs_nec_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     si, offset vfs_hou_grp
                mov     di, 0B800h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                call    word ptr cs:Clear_Screen_proc
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                mov     ax, 1
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     al, 0FFh
                mov     bx, 1220h
                mov     cx, 2C68h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_2Row_proc
                call    sub_6358
                mov     ax, 2
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     al, 0FFh
                mov     bx, 1220h
                mov     cx, 2C68h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_Interleaved_proc
                mov     es, word ptr cs:seg1
                mov     si, 0B800h
                mov     di, 9000h
                call    sub_6D5E
                mov     bx, 2048h
                mov     cx, 1040h
                mov     es, word ptr cs:seg1
                mov     di, 75A0h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                mov     byte ptr cs:soundFX_request, 4
                mov     si, 9060h
                call    word ptr cs:Animate_Sprites_proc
                push    cs
                pop     es
                mov     si, offset vfs_dmaou_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 97C0h
                call    sub_6D5E
                call    sub_6E0F
                mov     bx, 1220h
                mov     cx, 2C68h
                call    word ptr cs:Render_With_MaskErase_Callback_proc
                mov     ax, 3
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     al, 0FFh
                mov     bx, 1720h
                mov     cx, 2270h
                mov     di, 0
                call    word ptr cs:Decompress_3Plane_Interleaved_proc
                mov     si, offset byte_911E

loc_6154:
                mov     byte ptr ds:frame_timer, 0
                lodsb
                or      al, al
                jz      short loc_6171
                push    si
                dec     al
                mov     bx, 1720h
                call    word ptr cs:Load_Tiles_From_Big_Block_proc
                pop     si
                mov     al, 14h
                call    sub_63AB
                jmp     short loc_6154
; ---------------------------------------------------------------------------

loc_6171:
;============ Done above this line =============
                mov     byte ptr ds:frame_timer, 0
                mov     al, 0F0h
                call    sub_63AB
                mov     si, 9096h
                call    sub_62D1
                mov     byte ptr ds:frame_timer, 0
                mov     al, 0F0h
                call    sub_63AB
                mov     al, 2
                mov     bx, 1720h
                call    word ptr cs:Load_Tiles_From_Big_Block_proc
                mov     byte ptr ds:frame_timer, 0
                mov     al, 0Fh
                call    sub_63AB
                mov     al, 3
                mov     bx, 1720h
                call    word ptr cs:Load_Tiles_From_Big_Block_proc
                mov     byte ptr ds:frame_timer, 0
                mov     al, 0F0h
                call    sub_63AB
                xor     al, al
                mov     bx, 94h
                mov     cx, 501Eh
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                push    cs
                pop     es
                mov     si, offset vfs_ttl1_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    RLE_decompress
                push    cs
                pop     es
                mov     si, offset vfs_ttl2_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     si, offset vfs_ttl3_grp
                mov     di, 0B000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     si, offset vfs_zopn_msd
                mov     es, word ptr cs:0FF2Ch ; seg1
                mov     di, 3000h
                mov     al, 5
                call    word ptr cs:res_dispatcher_proc
                mov     bx, 1720h
                mov     cx, 2270h
                call    word ptr cs:Render_With_MaskErase_Callback_proc
                mov     ax, 4
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     byte ptr ds:frame_timer, 0
                push    ds
                mov     ds, word ptr cs:seg1
                mov     si, 3000h
                xor     ax, ax
                int     60h             ; adlib fn 0
                pop     ds
                call    word ptr cs:GDMCGA_Clear_Viewport_proc
                mov     al, 0F0h
                call    sub_63AB
                xor     al, al
                mov     bx, 0B48h
                mov     cx, 3180h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_Interleaved_proc
                mov     byte ptr ds:frame_timer, 0
                mov     es, word ptr cs:seg1
                mov     si, 0B000h
                mov     di, 4000h
                call    RLE_decompress
                mov     al, 0F0h
                call    sub_63AB
                mov     bx, 70Fh
                mov     cx, 4170h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_XOR_proc
                mov     byte ptr ds:frame_timer, 0
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    RLE_decompress
                mov     si, 912Bh
                call    word ptr cs:Render_Tile_Grid_proc
                mov     al, 0F0h
                call    sub_63AB
                mov     ax, 0C7h
                mov     cx, 64h ; 'd'

loc_62A1:
                push    cx
                mov     byte ptr ds:frame_timer, 0
                push    ax
                call    word ptr cs:Blit_And_Or_Xor_Masked_proc
                pop     ax
                push    ax
                mov     al, ah
                call    word ptr cs:Blit_And_Or_Xor_Masked_proc
                mov     al, 50h ; 'P'
                call    sub_63AB
                pop     ax
                add     ah, 2
                sub     al, 2
                pop     cx
                loop    loc_62A1

loc_62C4:
                call    sub_63CC
                test    byte ptr ds:music_status_flag, 0FFh
                jz      short loc_62C4
                jmp     loc_63E5
sub_6002        endp


; =============== S U B R O U T I N E =======================================


sub_62D1        proc near
                mov     byte_653F, 8Ah

loc_62D6:
                mov     byte ptr ds:frame_timer, 0

loc_62DB:
                lodsb
                or      al, al
                jnz     short loc_62E1
                retn
; ---------------------------------------------------------------------------

loc_62E1:
                cmp     al, 5
                jnb     short loc_62F3
                push    si
                dec     al
                mov     bx, 1F70h
                call    word ptr cs:Load_Tiles_From_Small_Block_proc
                pop     si
                jmp     short loc_62DB
; ---------------------------------------------------------------------------

loc_62F3:
                call    sub_62FD
                mov     al, 14h
                call    sub_63AB
                jmp     short loc_62D6
sub_62D1        endp


; =============== S U B R O U T I N E =======================================


sub_62FD        proc near
                cmp     al, 0FFh
                jnz     short loc_631E
                lodsb
                or      al, al
                jnz     short loc_6307
                retn
; ---------------------------------------------------------------------------

loc_6307:
                cmp     al, 1
                jz      short loc_630C
                retn
; ---------------------------------------------------------------------------

loc_630C:
                xor     ax, ax
                lodsb
                add     ax, ax
                add     ax, ax
                add     ax, ax
                mov     word_653D, ax
                add     byte_653F, 0Ah
                retn
; ---------------------------------------------------------------------------

loc_631E:
                push    ax
                push    si
                push    ax
                mov     bx, word_653D
                add     bx, 2
                mov     cl, byte_653F
                add     cl, 1
                mov     ah, 2
                call    word ptr cs:GDMCGA_Font_Glyph_Thunk_proc
                pop     ax
                mov     bx, word_653D
                mov     cl, byte_653F
                mov     ah, 7
                call    word ptr cs:GDMCGA_Font_Glyph_Thunk_proc
                pop     si
                add     word_653D, 8
                pop     ax
                cmp     al, 20h ; ' '
                jnz     short loc_6352
                retn
; ---------------------------------------------------------------------------

loc_6352:
                mov     byte ptr ds:soundFX_request, 63
                retn
sub_62FD        endp


; =============== S U B R O U T I N E =======================================


sub_6358        proc near
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    word ptr cs:Clear_Seg2_Buffer_proc
                mov     si, offset aTwoThousandYea ; "           Two thousand years, \rfrom t"...

loc_6366:                               ;
                call    word ptr cs:Render_Text_String_proc
                push    si
                mov     cx, 0Ah

loc_636F:
                push    cx
                mov     ax, cx
                neg     ax
                add     ax, 0Ah
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    word ptr cs:Blit_Sprite_To_Screen_proc
                mov     al, 1Ch
                call    sub_63AB
                pop     cx
                loop    loc_636F
                pop     si
                cmp     byte ptr [si-1], 0FFh
                jnz     short loc_6366
                mov     cx, 78h ; 'x'

loc_6394:
                push    cx
                xor     ax, ax
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    word ptr cs:Blit_Sprite_To_Screen_proc
                mov     al, 1Ch
                call    sub_63AB
                pop     cx
                loop    loc_6394
                retn
sub_6358        endp


; =============== S U B R O U T I N E =======================================


sub_63AB        proc near

                test    byte ptr cs:spacebar_latch, 0FFh
                jnz     short loc_63E5
                cmp     byte ptr cs:Current_ASCII_Char, 0Dh
                jz      short loc_63E5
                call    sub_63CC
                cmp     cs:frame_timer, al
                jb      short sub_63AB
                mov     byte ptr cs:frame_timer, 0
                retn
sub_63AB        endp


; =============== S U B R O U T I N E =======================================


sub_63CC        proc near
                push    si
                push    ax
                call    word ptr cs:Confirm_Exit_Dialog_proc
                call    word ptr cs:Handle_Pause_State_proc
                call    word ptr cs:Joystick_Calibration_proc
                call    word ptr cs:Joystick_Deactivator_proc
                pop     ax
                pop     si
                retn
sub_63CC        endp

; ---------------------------------------------------------------------------
loc_63E5:
                mov     byte ptr ds:byte_FF24, 8
                mov     al, 0FFh
                mov     bx, 0
                mov     cx, 50C8h
                call    word ptr cs:Render_With_MaskErase_Callback_proc

loc_63F7:
                test    byte ptr ds:music_status_flag, 0FFh
                jz      short loc_63F7
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_640C:
                cli
                mov     sp, 2000h
                sti
                push    cs
                pop     ds
                call    word ptr cs:Clear_Screen_proc
                mov     si, offset vfs_zend_msd
                mov     es, word ptr cs:seg1
                mov     di, 3000h
                mov     al, 5
                call    word ptr cs:res_dispatcher_proc
                mov     byte ptr ds:frame_timer, 0
                push    ds
                mov     ds, word ptr cs:seg1
                mov     si, 3000h
                xor     ax, ax
                int     60h             ; adlib fn 0
                pop     ds
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                mov     ax, 1
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                call    sub_6497
                jmp     short loc_6477

; =============== S U B R O U T I N E =======================================


sub_6456        proc near

                test    byte ptr cs:spacebar_latch, 0FFh
                jnz     short loc_6477
                cmp     byte ptr cs:Current_ASCII_Char, 0Dh
                jz      short loc_6477
                call    sub_63CC
                cmp     cs:frame_timer, al
                jb      short sub_6456
                mov     byte ptr cs:frame_timer, 0
                retn
; ---------------------------------------------------------------------------

loc_6477:
                mov     byte ptr ds:byte_FF24, 8
                call    word ptr cs:Clear_Screen_proc

loc_6481:
                test    byte ptr ds:music_status_flag, 0FFh
                jz      short loc_6481
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                jmp     loc_6540
sub_6456        endp


; =============== S U B R O U T I N E =======================================


sub_6497        proc near
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    word ptr cs:Clear_Seg2_Buffer_proc
                mov     si, offset aTheHumbleGuysZ ; "           The Humble Guys!            "...

loc_64A5:
                call    word ptr cs:Render_Text_String_proc
                push    si
                mov     cx, 0Ah

loc_64AE:
                push    cx
                mov     ax, cx
                neg     ax
                add     ax, 0Ah
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    word ptr cs:Blit_Sprite_To_Screen_proc
                mov     al, 1Ch
                call    sub_6456
                pop     cx
                loop    loc_64AE
                pop     si
                cmp     byte ptr [si-1], 0FFh
                jnz     short loc_64A5
                mov     cx, 78h ; 'x'

loc_64D3:
                push    cx
                xor     ax, ax
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    word ptr cs:Blit_Sprite_To_Screen_proc
                mov     al, 1Ch
                call    sub_6456
                pop     cx
                loop    loc_64D3
                retn
sub_6497        endp

; ---------------------------------------------------------------------------
copyright_str   db 87h, '    Copyright (C)1987,1990 GAME ARTS    ', 0Dh, '    Copyright (C)1990 Sierra On-Line    ', 0FFh
word_653D       dw 0
byte_653F       db 0
; ---------------------------------------------------------------------------

loc_6540:
                cli
                mov     sp, 2000h
                sti
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                mov     cs:off_6D56, 79C6h
                mov     ax, 5
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                push    cs
                pop     es
                mov     si, offset vfs_waku_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     si, 0A000h
                mov     di, 0
                call    sub_6D5E
                push    cs
                pop     es
                mov     si, offset vfs_ame_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                mov     bx, 0
                mov     cx, 5088h
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     di, 0
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                mov     bx, 410h
                mov     cx, 4868h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                call    sub_6A75
                mov     ax, 9
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     bx, 410h
                mov     cx, 4868h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                push    cs
                pop     es
                mov     si, offset vfs_hime_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                call    sub_6A75
                xor     ax, ax
                call    word ptr cs:Render_Scrolling_Border_proc
                mov     ax, 6
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     bx, 410h
                mov     cx, 4868h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                push    cs
                pop     es
                mov     si, offset vfs_dmaou_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 97C0h
                call    sub_6D5E
                call    sub_6A75
                mov     al, 4
                call    sub_6E8F
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     di, 0
                call    sub_6ED8
                mov     bx, 410h
                mov     cx, 4868h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                call    sub_6A75
                call    sub_6A75
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     di, 0
                mov     bx, 1728h
                mov     cx, 2230h
                mov     al, 7
                call    word ptr cs:Render_Animated_Tiles_proc
                call    sub_6A75
                call    sub_6A75
                mov     al, 2
                call    sub_6E8F
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     di, 0
                mov     bx, 1728h
                mov     cx, 2230h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                mov     byte ptr cs:frame_timer, 0
                mov     al, 0Fh
                call    sub_6A07
                mov     al, 3
                call    sub_6E8F
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     di, 0
                mov     bx, 1728h
                mov     cx, 2230h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                push    cs
                pop     es
                mov     si, offset vfs_isi_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                mov     bx, 410h
                mov     cx, 4868h
                call    word ptr cs:Render_With_MaskErase_Callback_proc
                call    sub_6A75
                mov     ax, 7
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     al, 0FFh
                mov     bx, 410h
                mov     cx, 4868h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_Interleaved_proc
                call    sub_6A75
                push    cs
                pop     es
                mov     si, offset vfs_oui_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                xor     al, al
                mov     bx, 410h
                mov     cx, 4868h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_Interleaved_proc
                call    sub_6A75
                call    sub_6A75
                push    cs
                pop     es
                mov     si, offset vfs_sei_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                mov     di, 4000h
                mov     bx, 1610h
                mov     cx, 2468h
                mov     al, 5
                call    word ptr cs:Render_Animated_Tiles_proc
                call    sub_6A75
                xor     ax, ax
                call    word ptr cs:Render_Scrolling_Border_proc
                call    sub_6A75
                push    cs
                pop     es
                mov     si, offset vfs_yuu1_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                mov     al, 0FFh
                mov     bx, 410h
                mov     cx, 4868h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_Interleaved_proc
                push    cs
                pop     es
                mov     si, offset vfs_yuup_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                push    cs
                pop     es
                mov     si, offset vfs_oup_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 8000h
                call    sub_6D5E
                call    sub_6A75
                call    sub_6A75
                xor     ax, ax
                call    word ptr cs:Render_Scrolling_Border_proc
                mov     ax, 6
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     bx, 0A15h
                mov     cx, 1A5Dh
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                mov     bx, 0B18h
                mov     cx, 1858h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                mov     bx, 2C15h
                mov     cx, 1A5Dh
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     es, word ptr cs:seg1
                mov     di, 8000h
                mov     bx, 2D18h
                mov     cx, 1858h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                call    sub_6A75
                call    sub_6A75
                push    cs
                pop     es
                mov     si, offset vfs_maop_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 8000h
                call    sub_6D5E
                xor     ax, ax
                call    word ptr cs:Render_Scrolling_Border_proc
                mov     ax, 8
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     bx, 1515h
                mov     cx, 315Dh
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     es, word ptr cs:seg1
                mov     di, 8000h
                mov     bx, 1618h
                call    word ptr cs:Pack_3Plane_And_Render_proc
                call    sub_6A75
                call    sub_6A75
                mov     bx, 1515h
                mov     dx, 315Dh
                mov     cx, 18h

loc_68A1:
                push    cx
                push    dx
                push    bx
                mov     byte ptr cs:frame_timer, 0
                mov     cx, dx
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     al, 0Fh
                call    sub_6A07
                pop     bx
                pop     dx
                inc     bh
                dec     dh
                pop     cx
                loop    loc_68A1
                mov     bx, 2C15h
                mov     cx, 1A5Dh
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     bx, 0A15h
                mov     cx, 1A5Dh
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                mov     bx, 0B18h
                mov     cx, 1858h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                call    sub_6A75
                call    sub_6A75
                mov     bx, 2C15h
                mov     dx, 1A5Dh
                mov     cx, 18h

loc_68F7:
                push    cx
                push    dx
                push    bx
                mov     byte ptr cs:frame_timer, 0
                mov     cx, dx
                call    word ptr cs:GDMCGA_Draw_Bordered_Rect_proc
                mov     al, 0Fh
                call    sub_6A07
                pop     bx
                pop     dx
                inc     bh
                dec     dh
                pop     cx
                loop    loc_68F7
                xor     ax, ax
                call    word ptr cs:Render_Scrolling_Border_proc
                mov     ax, 7
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                push    cs
                pop     es
                mov     si, offset vfs_yuu2_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                mov     bx, 1010h
                mov     cx, 3160h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                call    sub_6A75
                push    cs
                pop     es
                mov     si, offset vfs_yuu3_grp
                mov     di, 0A000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     si, offset vfs_yuu4_grp
                mov     di, 0D000h
                mov     al, 2
                call    word ptr cs:res_dispatcher_proc
                mov     es, word ptr cs:seg1
                mov     si, 0A000h
                mov     di, 4000h
                call    sub_6D5E
                mov     bx, 0
                mov     cx, 50C8h
                call    word ptr cs:Render_With_MaskErase_Callback_proc
                mov     bx, 808h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    sub_6FAC
                mov     es, word ptr cs:seg1
                mov     si, 0D000h
                mov     di, 0D000h
                call    sub_6D5E
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                mov     si, 0D000h
                call    sub_6F41
                mov     al, 0FFh
                mov     bx, 808h
                mov     cx, 40C0h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_Interleaved_proc
                mov     byte ptr cs:frame_timer, 0
                mov     al, 0F0h
                call    sub_6A07
                mov     al, 0FFh
                mov     bx, 808h
                mov     cx, 40C0h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    word ptr cs:Decompress_3Plane_2Row_proc
                mov     ax, 1
                call    word ptr cs:GDMCGA_Fade_Palette_proc
                mov     si, offset aAtLastTheDoorO ; "                At last,               "...
                call    sub_6D04
                mov     cx, 0Ah

loc_69FC:
                push    cx
                mov     al, 0C8h
                call    sub_6A07
                pop     cx
                loop    loc_69FC
                jmp     short loc_6A41

; =============== S U B R O U T I N E =======================================


sub_6A07        proc near
                call    sub_6A18
                cmp     cs:frame_timer, al
                jb      short sub_6A07
                mov     byte ptr cs:frame_timer, 0
                retn
sub_6A07        endp


; =============== S U B R O U T I N E =======================================


sub_6A18        proc near
                test    byte ptr cs:spacebar_latch, 0FFh
                jnz     short loc_6A41
                cmp     byte ptr cs:Current_ASCII_Char, 0Dh
                jz      short loc_6A41
                push    si
                push    ax
                call    word ptr cs:Confirm_Exit_Dialog_proc
                call    word ptr cs:Handle_Pause_State_proc
                call    word ptr cs:Joystick_Calibration_proc
                call    word ptr cs:Joystick_Deactivator_proc
                pop     ax
                pop     si
                retn
; ---------------------------------------------------------------------------

loc_6A41:
                mov     bx, 0
                mov     cx, 50C8h
                call    word ptr cs:Render_With_MaskErase_Callback_proc
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                mov     ax, cs
                mov     es, ax
                mov     ds, ax
                mov     si, offset vfs_game_bin
                mov     di, game_bin_entry
                mov     al, 3
                call    word ptr cs:res_dispatcher_proc
                mov     ax, 0FFFFh
                jmp     cs:game_bin_addr
sub_6A18        endp

; ---------------------------------------------------------------------------
game_bin_addr   dw game_bin_entry

; =============== S U B R O U T I N E =======================================


sub_6A75        proc near
                mov     byte ptr cs:frame_timer, 0

loc_6A7B:
                mov     al, 10h
                call    sub_6A07

loc_6A80:
                push    cs
                pop     ds
                mov     si, ds:off_6D56
                lodsb
                mov     ds:off_6D56, si
                test    al, 80h
                jz      short loc_6A92
                jmp     loc_6B21
; ---------------------------------------------------------------------------

loc_6A92:
                cmp     al, 20h ; ' '
                jz      short loc_6AAE
                cmp     al, 2Eh ; '.'
                jz      short loc_6AAE
                cmp     al, 2Ch ; ','
                jz      short loc_6AAE
                cmp     al, 22h ; '"'
                jz      short loc_6AAE
                cmp     al, 27h ; '''
                jz      short loc_6AAE
                mov     ah, ds:byte_6D5D
                mov     ds:soundFX_request, ah

loc_6AAE:
                push    ax
                mov     bx, ds:word_6D58
                add     bx, 4
                mov     al, ds:byte_6D5A
                mov     dl, 0Ah
                mul     dl
                add     ax, 8Fh
                mov     cx, ax
                pop     ax
                push    bx
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     dl, ds:byte_947D[bx]
                mov     dh, bh
                pop     bx
                push    ax
                sub     bx, dx
                push    ax
                push    bx
                push    cx
                inc     bx
                inc     cx
                mov     ah, ds:byte_6D5B
                call    word ptr cs:GDMCGA_Font_Glyph_Thunk_proc
                pop     cx
                pop     bx
                pop     ax
                mov     ah, ds:byte_6D5C
                call    word ptr cs:GDMCGA_Font_Glyph_Thunk_proc
                pop     ax
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     cl, ds:byte_94DD[bx]
                mov     ch, bh
                add     ds:word_6D58, cx
                cmp     al, 20h ; ' '
                jz      short loc_6B08
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6B08:
                mov     si, ds:off_6D56
                call    sub_6CC4
                mov     dx, ds:word_6D58
                add     dx, cx
                cmp     dx, 138h
                jb      short loc_6B1E
                jmp     loc_6BF0
; ---------------------------------------------------------------------------

loc_6B1E:
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6B21:
                cmp     al, 0FFh
                jnz     short loc_6B26
                retn
; ---------------------------------------------------------------------------

loc_6B26:
                cmp     al, 0FDh
                jnz     short loc_6B2B
                retn
; ---------------------------------------------------------------------------

loc_6B2B:
                mov     ah, al
                and     ah, 0F0h
                cmp     ah, 80h
                jnz     short loc_6B38
                jmp     loc_6C28
; ---------------------------------------------------------------------------

loc_6B38:
                cmp     ah, 90h
                jnz     short loc_6B40
                jmp     loc_6C77
; ---------------------------------------------------------------------------

loc_6B40:
                mov     bx, 701h
                cmp     al, 0FBh
                jnz     short loc_6B4A
                jmp     loc_6BD8
; ---------------------------------------------------------------------------

loc_6B4A:
                mov     bx, 700h
                cmp     al, 0FAh
                jnz     short loc_6B54
                jmp     loc_6BD8
; ---------------------------------------------------------------------------

loc_6B54:
                mov     bx, 602h
                cmp     al, 0F9h
                jz      short loc_6BD8
                cmp     al, 0F5h
                jnz     short loc_6B62
                jmp     loc_6C0E
; ---------------------------------------------------------------------------

loc_6B62:
                cmp     al, 0F6h
                jnz     short loc_6B69
                jmp     loc_6C16
; ---------------------------------------------------------------------------

loc_6B69:
                xor     ah, ah
                cmp     al, 0F7h
                jz      short loc_6BE3
                inc     ah
                cmp     al, 0F3h
                jz      short loc_6BE3
                inc     ah
                cmp     al, 0F2h
                jz      short loc_6BE3
                inc     ah
                cmp     al, 0F1h
                jz      short loc_6BE3
                cmp     al, 0FEh
                jz      short loc_6BFD
                mov     ah, ds:byte_6D5D
                mov     ds:byte_6D5D, 0
                cmp     al, 0F0h
                jnz     short loc_6B95
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6B95:
                mov     ds:byte_6D5D, 3Dh ; '='
                cmp     al, 0EFh
                jnz     short loc_6BA1
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BA1:
                mov     ds:byte_6D5D, 3Eh ; '>'
                cmp     al, 0EEh
                jnz     short loc_6BAD
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BAD:
                mov     ds:byte_6D5D, 3Fh ; '?'
                cmp     al, 0EDh
                jnz     short loc_6BB9
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BB9:
                mov     ds:byte_6D5D, 40h ; '@'
                cmp     al, 0ECh
                jnz     short loc_6BC5
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BC5:
                mov     ds:byte_6D5D, 41h ; 'A'
                cmp     al, 0EBh
                jnz     short loc_6BD1
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BD1:
                mov     ds:byte_6D5D, ah
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BD8:
                mov     ds:byte_6D5B, bl
                mov     ds:byte_6D5C, bh
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BE3:
                mov     ds:word_6D58, 0
                mov     ds:byte_6D5A, ah
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BF0:
                mov     ds:word_6D58, 0
                inc     ds:byte_6D5A
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6BFD:
                mov     bx, 8Fh
                mov     cx, 5039h
                xor     al, al
                call    word ptr cs:Draw_Bordered_Rectangle_proc
                xor     ah, ah
                jmp     short loc_6BE3
; ---------------------------------------------------------------------------

loc_6C0E:
                mov     al, 0F0h
                call    sub_6A07
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6C16:
                mov     al, 0F0h
                call    sub_6A07
                mov     al, 0F0h
                call    sub_6A07
                mov     al, 0F0h
                call    sub_6A07
                jmp     loc_6A7B
; ---------------------------------------------------------------------------

loc_6C28:
                mov     es, word ptr cs:seg1
                and     al, 0Fh
                cmp     al, 6
                jnb     short loc_6C56
                mov     ah, 15h
                mul     ah
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, 98C0h
                mov     di, ax
                mov     bx, 3350h
                mov     cx, 0E20h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                jmp     loc_6A80
; ---------------------------------------------------------------------------

loc_6C56:
                sub     al, 6
                mov     ah, 21h ; '!'
                mul     ah
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, 0B840h
                mov     di, ax
                mov     bx, 3338h
                mov     cx, 0B10h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                jmp     loc_6A80
; ---------------------------------------------------------------------------

loc_6C77:
                mov     es, word ptr cs:seg1
                and     al, 0Fh
                cmp     al, 6
                jnb     short loc_6CA3
                mov     ah, 1Bh
                mul     ah
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, 58C0h
                mov     di, ax
                mov     bx, 1350h
                mov     cx, 920h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                jmp     loc_6A80
; ---------------------------------------------------------------------------

loc_6CA3:
                sub     al, 6
                mov     ah, 21h ; '!'
                mul     ah
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, 6D00h
                mov     di, ax
                mov     bx, 1238h
                mov     cx, 0B10h
                call    word ptr cs:Decompress_And_Copy_To_VRAM_proc
                jmp     loc_6A80
sub_6A75        endp


; =============== S U B R O U T I N E =======================================


sub_6CC4        proc near
                xor     cx, cx

loc_6CC6:
                lodsb
                cmp     al, 20h ; ' '
                jnz     short loc_6CCC
                retn
; ---------------------------------------------------------------------------

loc_6CCC:
                cmp     al, 0FFh
                jnz     short loc_6CD1
                retn
; ---------------------------------------------------------------------------

loc_6CD1:
                cmp     al, 0FEh
                jnz     short loc_6CD6
                retn
; ---------------------------------------------------------------------------

loc_6CD6:
                cmp     al, 0FDh
                jnz     short loc_6CDB
                retn
; ---------------------------------------------------------------------------

loc_6CDB:
                cmp     al, 0F7h
                jnz     short loc_6CE0
                retn
; ---------------------------------------------------------------------------

loc_6CE0:
                cmp     al, 0F3h
                jnz     short loc_6CE5
                retn
; ---------------------------------------------------------------------------

loc_6CE5:
                cmp     al, 0F2h
                jnz     short loc_6CEA
                retn
; ---------------------------------------------------------------------------

loc_6CEA:
                cmp     al, 0F1h
                jnz     short loc_6CEF
                retn
; ---------------------------------------------------------------------------

loc_6CEF:
                or      al, al
                js      short loc_6CC6
                sub     al, 20h ; ' '
                jb      short loc_6CC6
                mov     bl, al
                xor     bh, bh
                add     cl, cs:byte_94DD[bx]
                adc     ch, bh
                jmp     short loc_6CC6
sub_6CC4        endp


; =============== S U B R O U T I N E =======================================


sub_6D04        proc near
                push    si
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    word ptr cs:Clear_Seg2_Buffer_proc
                pop     si

loc_6D11:
                call    word ptr cs:Render_Text_String_proc
                push    si
                mov     cx, 0Ah

loc_6D1A:
                push    cx
                mov     ax, cx
                neg     ax
                add     ax, 0Ah
                mov     bx, 14h
                mov     cx, 50A0h
                call    word ptr cs:Blit_Sprite_To_Screen_proc
                mov     al, 1Ch
                call    sub_6A07
                pop     cx
                loop    loc_6D1A
                pop     si
                cmp     byte ptr [si-1], 0FFh
                jnz     short loc_6D11
                mov     cx, 0A0h

loc_6D3F:
                push    cx
                xor     ax, ax
                mov     bx, 14h
                mov     cx, 50A0h
                call    word ptr cs:Blit_Sprite_To_Screen_proc
                mov     al, 1Ch
                call    sub_6A07
                pop     cx
                loop    loc_6D3F
                retn
sub_6D04        endp

; ---------------------------------------------------------------------------
off_6D56        dw offset byte_79C6
word_6D58       dw 0
byte_6D5A       db 0
byte_6D5B       db 0
byte_6D5C       db 0
byte_6D5D       db 0

; =============== S U B R O U T I N E =======================================


sub_6D5E        proc near

                call    sub_6D63
                jmp     short loc_6D8D  
sub_6D5E        endp                    

; =============== S U B R O U T I N E =======================================


sub_6D63        proc near
                push    di
                lodsw
                mov     cx, ax
                push    cx
                mov     bp, si
                add     si, cx

loc_6D6C:
                push    cx
                xor     al, al
                mov     cx, 8

loc_6D72:
                rol     byte ptr ds:[bp+0], 1
                jb      short loc_6D7D
                stosb
                loop    loc_6D72
                jmp     short loc_6D80
; ---------------------------------------------------------------------------

loc_6D7D:
                movsb
                loop    loc_6D72

loc_6D80:
                inc     bp
                pop     cx
                loop    loc_6D6C
                pop     cx
                add     cx, cx
                add     cx, cx
                add     cx, cx
                pop     di
                retn
sub_6D63        endp

; ---------------------------------------------------------------------------
; /**
;  * @brief Decodes a bitstream using a 2-bit XOR delta pattern.
;  * @param source      Pointer to the input bitstream buffer.
;  * @param destination Pointer to the output buffer.
;  * @param count       Number of bytes to generate (the 'loop' counter).
;  */
; void decode_bits(uint8_t *source, uint8_t *destination, int count) {
;     uint8_t state_dh = 0; // Running XOR state
;
;     for (int i = 0; i < count; i++) {
;         uint8_t result_ah = 0;
;
;         // Process 4 pairs of bits to fill one byte (4 * 2 = 8 bits)
;         for (int j = 0; j < 4; j++) {
;             // 1. Extract 2 bits from the source
;             // Note: The ASM uses 'rcl', suggesting it pulls from
;             // the top of the byte at [di] repeatedly.
;             uint8_t bits = 0;
;
;             // Extract Bit 1
;             bits = (*source >> 7) & 1;
;             *source <<= 1;
;
;             // Extract Bit 2
;             bits = (bits << 1) | ((*source >> 7) & 1);
;             *source <<= 1;
loc_6D8D:
                xor     dh, dh

loc_6D8F:
                xor     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                xor     dh, al
                mov     ah, dh
                xor     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                xor     dh, al
                add     ah, ah
                add     ah, ah
                or      ah, dh
                xor     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                xor     dh, al
                add     ah, ah
                add     ah, ah
                or      ah, dh
                xor     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                rcl     byte ptr es:[di], 1
                adc     al, al
                xor     dh, al
                add     ah, ah
                add     ah, ah
                or      ah, dh
                mov     al, ah
                stosb
                loop    loc_6D8F
                retn

; =============== S U B R O U T I N E =======================================


RLE_decompress  proc near
                test    byte ptr [si], 40h
                jz      short control_mode_byte
                lodsw
                xchg    ah, al
                mov     cx, ax
                cmp     ax, 0FFFFh
                jnz     short loc_6DF1
                retn
; ---------------------------------------------------------------------------

loc_6DF1:
                and     cx, 3FFFh
                test    ax, 8000h
                jz      short copy_bytes

fill_with_byte:
                lodsb
                rep stosb
                jmp     short RLE_decompress
; ---------------------------------------------------------------------------

copy_bytes:
                rep movsb
                jmp     short RLE_decompress
; ---------------------------------------------------------------------------

control_mode_byte:
                lodsb
                mov     cl, al
                and     cx, 3Fh
                test    al, 80h
                jz      short copy_bytes
                jmp     short fill_with_byte
RLE_decompress  endp


; =============== S U B R O U T I N E =======================================


sub_6E0F        proc near
                push    ds
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     di, 0
                mov     cx, 1650h
                xor     ax, ax
                rep stosw
                mov     ds, word ptr cs:seg1
                mov     di, 0
                mov     bx, 0
                mov     cx, 2230h
                mov     si, 0AB40h
                call    sub_6E4F
                mov     bx, 0F30h
                mov     cx, 620h
                mov     si, 0A9C0h
                call    sub_6E4F
                mov     bx, 850h
                mov     cx, 1220h
                mov     si, 9C40h
                call    sub_6E5E
                pop     ds
                retn
sub_6E0F        endp


; =============== S U B R O U T I N E =======================================


sub_6E4F        proc near
                push    di
                add     di, 0EE0h
                call    sub_6E6D
                pop     di
                push    di
                call    sub_6E6D
                pop     di
                retn
sub_6E4F        endp


; =============== S U B R O U T I N E =======================================


sub_6E5E        proc near
                push    di
                call    sub_6E6D
                pop     di
                push    di
                add     di, 0EE0h
                call    sub_6E6D
                pop     di
                retn
sub_6E5E        endp


; =============== S U B R O U T I N E =======================================


sub_6E6D        proc near
                push    bx
                push    cx
                mov     al, 22h ; '"'
                mul     bl
                mov     bl, bh
                xor     bh, bh
                add     ax, bx
                add     di, ax

loc_6E7B:
                push    cx
                push    di
                mov     cl, ch
                xor     ch, ch
                rep movsb
                pop     di
                add     di, 22h ; '"'
                pop     cx
                dec     cl
                jnz     short loc_6E7B
                pop     cx
                pop     bx
                retn
sub_6E6D        endp


; =============== S U B R O U T I N E =======================================


sub_6E8F        proc near
                push    ds
                xor     ah, ah
                mov     dx, 0CC0h
                mul     dx
                add     ax, 0AB40h
                mov     ds, word ptr cs:seg1
                mov     si, ax
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax
                mov     di, 0
                call    sub_6EB0
                pop     ds
                retn
sub_6E8F        endp


; =============== S U B R O U T I N E =======================================


sub_6EB0        proc near
                mov     cx, 30h ; '0'

loc_6EB3:
                push    cx
                mov     cx, 22h ; '"'

loc_6EB7:
                mov     ah, [si+660h]
                lodsb
                mov     bh, al
                not     bh
                and     bh, ah
                xor     ah, bh
                mov     es:[di], al
                mov     es:[di+660h], bh
                mov     es:[di+0CC0h], ah
                inc     di
                loop    loc_6EB7
                pop     cx
                loop    loc_6EB3
                retn
sub_6EB0        endp


; =============== S U B R O U T I N E =======================================


sub_6ED8        proc near
                push    ds
                push    es
                pop     ds
                mov     si, di
                mov     es, word ptr cs:seg1
                mov     di, 46D3h
                mov     cx, 30h ; '0'

loc_6EE8:
                push    cx
                push    di
                mov     cx, 11h

loc_6EED:
                push    cx
                mov     ax, es:[di]
                mov     bx, es:[di+1D40h]
                not     ax
                not     bx
                and     ax, bx
                and     ax, es:[di+3A80h]
                mov     dx, ax
                not     dx
                mov     bx, ax
                and     ax, [si]
                and     es:[di], dx
                or      es:[di], ax
                mov     ax, bx
                and     ax, [si+660h]
                and     es:[di+1D40h], dx
                or      es:[di+1D40h], ax
                mov     ax, bx
                and     ax, [si+0CC0h]
                and     es:[di+3A80h], dx
                or      es:[di+3A80h], ax
                add     di, 2
                add     si, 2
                pop     cx
                loop    loc_6EED
                pop     di
                add     di, 48h ; 'H'
                pop     cx
                loop    loc_6EE8
                pop     ds
                retn
sub_6ED8        endp


; =============== S U B R O U T I N E =======================================


sub_6F41        proc near
                add     di, 819h
                mov     cx, 0A0h

loc_6F48:
                push    cx
                push    di
                mov     cx, 15h

loc_6F4D:
                push    cx
                mov     al, es:[si]
                and     al, es:[si+0D20h]
                mov     ah, es:[si+1A40h]
                not     ah
                and     al, ah
                not     al
                mov     ah, es:[si]
                or      ah, es:[si+0D20h]
                or      ah, es:[si+1A40h]
                and     es:[si], al
                and     es:[si+0D20h], al
                not     ah
                and     es:[di], ah
                and     es:[di+3000h], ah
                and     es:[di+6000h], ah
                mov     al, es:[si]
                or      es:[di], al
                mov     al, es:[si+0D20h]
                or      es:[di+3000h], al
                mov     al, es:[si+1A40h]
                or      es:[di+6000h], al
                inc     di
                inc     si
                pop     cx
                loop    loc_6F4D
                pop     di
                add     di, 40h ; '@'
                pop     cx
                loop    loc_6F48
                retn
sub_6F41        endp


; =============== S U B R O U T I N E =======================================


sub_6FAC        proc near

                push    bx
                push    es
                push    di
                mov     cx, 3000h

loc_6FB2:
                mov     byte ptr es:[di+6000h], 0
                mov     al, es:[di+3000h]
                mov     ah, es:[di]
                not     ah
                and     al, ah
                or      es:[di], al
                or      es:[di+6000h], al
                not     al
                and     es:[di+3000h], al
                mov     al, es:[di+3000h]
                and     al, es:[di]
                or      es:[di+6000h], al
                inc     di
                loop    loc_6FB2
                pop     di
                pop     es
                pop     bx
                mov     cx, 40C0h
                mov     al, 0FFh
                jmp     word ptr cs:Decompress_3Plane_Interleaved_proc
sub_6FAC        endp ; sp-analysis failed

; ---------------------------------------------------------------------------
aTwoThousandYea db '           Two thousand years, ',0Dh,'from the dark reaches of an'
                db 'other galaxy,',0Dh,'        a demon with not a shred',0Dh,'      '
                db 'of compassion for humankind,',0Dh,'         descended upon earth.'
                db 0Dh,0Dh,'          He defiled the land,',0Dh,'  sending vile creat'
                db 'ures to live in it,',0Dh,'   and thus became ruler of the world.',0Dh
                db 0Dh,'         The King of Felishika,',0Dh,'     appalled by what h'
                db 'ad happened,',0Dh,'          prayed to the Spirit',0Dh,'      of '
                db 'the Holy Land of Zeliard',0Dh,'    for help in defeating this mon'
                db 'ster.',0Dh,0Dh,'    With the help of the holy crystals',0Dh,'    '
                db '   called Tears of Esmesanti,',0Dh,'    the King managed to wrest'
                db ' power',0Dh,'    from the fiend and seal him deep',0Dh,'     with'
                db 'in the bowels of the earth.',0Dh,0Dh,'            And once again,'
                db 0Dh,' the light of peace came to shine upon',0Dh,'              th'
                db 'e earth.',0Dh,0Dh,0Dh,'However, it is written in',0Dh,'       the'
                db ' Sixth Book of Esmesanti:',0Dh,'                    The Age of Da'
                db 'rkness.',0Dh
                db 0FFh
aAtLastTheDoorO db '                At last,                ',0Dh,'     the door of d'
                db 'estiny was opened.    ',0Dh,'        The labyrinths are deep,    '
                db '    ',0Dh,'          and the way is long.          ',0Dh,'     Wi'
                db 'll Duke Garland be successful    ',0Dh,'   in dethroning the Empe'
                db 'ror of Chaos?  ',0Dh
                db 0FFh
aTheHumbleGuysZ db '           The Humble Guys!             ',0Dh,'               ZEL'
                db 'IARD                  ',0Dh,0Dh,'             -- STAFF --        '
                db '        ',0Dh,0Dh,'Producer -- Japanese Version',0Dh,'           '
                db '           Mitsuhiro Mazda   ',0Dh,0Dh,'Producer -- English Versi'
                db 'on',0Dh,'                        Josh Mandel     ',0Dh,0Dh,'Lead '
                db 'Programmer      Tomoyuki Shimada   ',0Dh,0Dh,'Graphic Designers  '
                db '   Akihiko Yoshida   ',0Dh,'                      Masatoshi Azumi'
                db '   ',0Dh,0Dh,'English Text Translation by',0Dh,'                 '
                db '      Marti McKenna    ',0Dh,0Dh,'Music Composers  -- MECANO ASSO'
                db 'CIATES --',0Dh,'                    Fumihito Kasatani   ',0Dh,'  '
                db '                  Nobuyuki Aoshima    ',0Dh,0Dh,'Story Maker     '
                db '      Masaru Takeuchi   ',0Dh,0Dh,'Sound Effects by     Tomoyuki '
                db 'Shimada   ',0Dh,0Dh,'Advisers               Osamu Harada     ',0Dh
                db '                       Hiromi Ohba      ',0Dh,'                  '
                db '     Greg Miyaji      ',0Dh,0Dh,'System Designer      Rocky Cave '
                db 'Maker   ',0Dh,0Dh,'Special Thanks to',0Dh,'                    To'
                db 'shiyuki Uchida    ',0Dh,'                       Yuzo Sunaga      '
                db 0Dh,'                     Takeshi Miyaji     ',0Dh,'              '
                db '       Naozumi Honma      ',0Dh,'                     Toshi Masub'
                db 'uchi    ',0Dh,'                     Ray E. Nakazato    ',0Dh,'   '
                db '                  Hiroyuki Koyama    ',0Dh,'                     '
                db 'Satoshi Uesaka     ',0Dh,'              Sierra On-Line Japan, Inc'
                db '.',0Dh,'                    Eiji (Ed) Nagano    ',0Dh,0Dh,0Dh,0Dh
                db '    Copyright (C)1987,1990 GAME ARTS    ',0Dh,'    Copyright (C)1'
                db '990 Sierra On-Line    ',0Dh,'  This edition first published 1987 '
                db 'by  ',0Dh,'  GAME ARTS Co.,Ltd./ Tomoyuki Shimada  ',0Dh
                db 0FFh
byte_79C6       db 50h
                db 0F0h
                db 0FEh
                db 0F3h
                db 0FAh
aOnceLongAgoATe db 'Once, long ago, a terrible storm came to the land of Zeliard. '
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aDarkCloudsFill db 'Dark clouds filled the sky; lightning flashed and thunder crashed'
                db '. '
                db 0F2h
aDayAfterDayRai db 'Day after day, rain poured from the heavens as if in lament.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
                db 0F5h
aOnTheSeventhDa db 'On the seventh day of rain, a beautiful young girl stood on her b'
                db 'alcony watching this dark, sad rain.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
aTheGirlWasPrin db 'The girl was Princess Felicia la Felishika.  She was the only dau'
                db 'ghter of King Felishika, and the light of his life.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
                db 0F5h
aHerSmilesWereL db 'Her smiles were like sunshine, her voice as beautiful as that of '
                db 'an angel.  She was adored by the people of the kingdom.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0EBh
                db 0FEh
                db 0F5h
                db 0F3h
                db 0FBh
                db 0A0h
aWhatADreadfulS db '"What a dreadful storm!  Will it never end?"'
                db 0F0h
                db 0F6h
                db 0FEh
                db 0F5h
                db 0F3h
                db 0FAh
aJustAsThePrinc db 'Just as the princess spoke these words, the raindrops turned to g'
                db 'rains of sand which covered the ground below her. '
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0FEh
                db 0F5h
                db 0F3h
aAsSheWatchedAS db 'As she watched, a startling transformation began to take place.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
aInAnInstantThe db 'In an instant, the green hills and plains turned a dusty brown. '
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aTreesAndFlower db 'Trees and flowers crumpled and were buried. '
                db 0F3h
aRiversAndLakes db 'Rivers and lakes disappeared beneath the sand.'
                db 0F1h
aThisEverGreenL db 'This ever-green land was turning to desert before her very eyes.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0F5h
                db 0F3h
                db 0FBh
                db 0EBh
                db 0A2h
aHowCanThisBe   db '"How can this be?" '
                db 0F0h
                db 0FAh
aSheCried       db 'she cried, '
                db 0EBh
                db 0FBh
aWhatEvilPowerC db '"What evil power could cause such a terrible thing to happen?"'
                db 0F0h
                db 0F6h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
                db 0FAh
aPrincessFelici db 'Princess Felicia shivered as she felt a dark presence near her, '
                db 0FDh
aAndSuddenlyATe db 'and suddenly, a terrifying voice bellowed as loud as thunder...'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
                db 0F9h
                db 0EDh
aIAmJashiinTheE db '"I am Jashiin, the Emperor of Chaos.  The descendants of those wh'
                db 'o imprisoned me under the earth shall know that my wrath has smol'
                db 'dered for two thousand years!"'
                db 0F0h
                db 0F5h
                db 0F5h
                db 0FDh
                db 0FDh
                db 0FEh
                db 0F7h
                db 0EDh
aBeautifulPrinc db '"Beautiful Princess Felicia, you will make a lovely and terrifyin'
                db 'g symbol of my awakening.  Your father will not make the mistakes'
                db ' of his ancestors!"'
                db 0F0h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0F3h
                db 0FAh
aAsTheWordsOfTh db 'As the words of the demon resounded over the land, Princess Felic'
                db 'ia was turned to stone.'
                db 0FDh
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0F3h
aTheRainOfSandC db 'The rain of sand continued for 108 days and transformed the once-'
                db 'fertile land into desert.'
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
aThePeopleOfThe db 'The people of the kingdom wept at the terrible fate of their coun'
                db 'try, and of their princess.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0FEh
                db 0F7h
                db 0FAh
aTheKingWeptMos db 'The King wept most of all. '
                db 0F3h
                db 0EEh
                db 0FBh
aOhMyBelovedFel db '"Oh, my beloved Felicia!  I fear the Age of Darkness is upon us. '
                db ' I am powerless to stop it ... and powerless to help you."'
                db 0F0h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0F3h
                db 0FAh
aButTheTearsOfT db 'But the tears of the King and his people soon awakened another po'
                db 'wer.'
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0F3h
aAsTheKingGriev db 'As the King grieved, an apparition appeared before him.'
                db 0F5h
                db 0F5h
                db 0FEh
                db 0ECh
                db 0F7h
                db 0FBh
aIAmTheGuardian db '"I am the Guardian Spirit of the Holy Land of Zeliard.  The demon'
                db ' Jashiin has been resurrected, and indeed his evil magic will plu'
                db 'nge this world into the Age of Darkness once again."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aHeedMyWordsKin db '"Heed my words, King Felishika: There is but one way to stop this'
                db ' demon.  A brave warrior must venture into the labyrinths and rec'
                db 'over the nine Holy Crystals, the Tears of Esmesanti."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aManyTerribleCr db '"Many terrible creatures dwell within the labyrinths, all of them'
                db ' Jashiin',27h,'s minions.  No mortal man could defeat these deadl'
                db 'y beasts and wrest the crystals from them."'
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aHoweverThereIs db '"However, there is one with the power to oppose Jashiin.'
                db 0F2h
aTheManWhoIsDes db 'The man who is destined to fight him will soon arrive in your kin'
                db 'gdom."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
aThisManIsTheOn db '"This man is the only being strong enough to banish Jashiin forev'
                db 'er."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aYouMustAwaitTh db '"You must await the arrival of this brave and noble knight, and t'
                db 'ell him everything.  Only with his help can you hope to restore t'
                db 'his land to its former beauty, and free your daughter from her te'
                db 'rrible curse."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F0h
                db 0FDh
                db 0F3h
                db 0FAh
aHavingSpokenTh db 'Having spoken these words, the Spirit disappeared.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aKingFelishikaC db 'King Felishika could not believe what he had seen.'
                db 0F2h
                db 0FBh
aSurelyMyMindIs db '"Surely my mind is playing tricks on me!  I',27h,'m afraid I have'
                db ' gone mad with grief."'
                db 0FAh
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
aButTheNextDayA db 'But the next day, a stranger appeared in the kingdom...'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0EFh
                db 0FDh
                db 0F3h
                db 0FBh
aWhatADesolateP db '"What a desolate place!  Why has the Spirit led me here?"'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F0h
                db 0F3h
                db 0FAh
aGuidedByTheLig db 'Guided by the light of the Spirit, brave Duke Garland had journey'
                db 'ed many days to the land of Zeliard.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db 0F3h
aEnteringTheCas db 'Entering the castle, he was quickly escorted to the throne of the'
                db ' grieving King Felishika.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0EEh
                db 0FDh
                db 0F5h
                db 0FEh
                db 0FBh
                db 0F7h
                db  22h ; "
                db  81h
                db  44h ; D
                db  75h ; u
                db  6Bh ; k
                db  65h ; e
                db  20h
                db  80h
                db  47h ; G
                db  61h ; a
                db  72h ; r
                db  6Ch ; l
                db  61h ; a
                db  84h
                db  6Eh ; n
                db  83h
                db  64h ; d
                db  21h ; !
                db  20h
                db  20h
                db  84h
                db  85h
                db  59h ; Y
                db  87h
                db  6Fh ; o
                db  88h
                db  75h ; u
                db  87h
                db  20h
                db  86h
                db  80h
                db  6Dh ; m
                db  75h ; u
                db  81h
                db  73h ; s
                db  83h
                db  74h ; t
                db  20h
                db  82h
                db  62h ; b
                db  65h ; e
                db  20h
                db  81h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  80h
                db  6Dh ; m
                db  61h ; a
                db  84h
                db  6Eh ; n
                db  20h
                db  83h
                db  6Fh ; o
                db  84h
                db  66h ; f
                db  20h
                db  81h
                db  64h ; d
                db  65h ; e
                db  73h ; s
                db  82h
                db  74h ; t
                db  69h ; i
                db  6Eh ; n
                db  79h ; y
                db  20h
                db  83h
                db  6Fh ; o
                db  84h
                db  66h ; f
                db  20h
                db  83h
                db  77h ; w
                db  68h ; h
                db  6Fh ; o
                db  84h
                db  6Dh ; m
                db  20h
                db  81h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  83h
                db  53h ; S
                db  82h
                db  70h ; p
                db  69h ; i
                db  72h ; r
                db  69h ; i
                db  74h ; t
                db  20h
                db  83h
                db  73h ; s
                db  70h ; p
                db  6Fh ; o
                db  81h
                db  6Bh ; k
                db  65h ; e
                db  2Eh ; .
                db  20h
                db  20h
                db  84h
                db  97h
                db  80h
                db  49h ; I
                db  98h
                db  87h
                db  20h
                db  81h
                db  88h
                db  62h ; b
                db  87h
                db  65h ; e
                db  85h
                db  86h
                db  67h ; g
                db  20h
                db  83h
                db  6Fh ; o
                db  84h
                db  66h ; f
                db  20h
                db  85h
                db  79h ; y
                db  6Fh ; o
                db  75h ; u
                db  20h
                db  83h
                db  74h ; t
                db  6Fh ; o
                db  20h
                db  82h
                db  64h ; d
                db  65h ; e
                db  85h
                db  73h ; s
                db  74h ; t
                db  72h ; r
                db  6Fh ; o
                db  79h ; y
                db  20h
                db  81h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  83h
                db  64h ; d
                db  65h ; e
                db  80h
                db  6Dh ; m
                db  6Fh ; o
                db  6Eh ; n
                db  20h
                db  84h
                db  4Ah ; J
                db  80h
                db  61h ; a
                db  73h ; s
                db  82h
                db  68h ; h
                db  69h ; i
                db  69h ; i
                db  84h
                db  6Eh ; n
                db  20h
                db  80h
                db  87h
                db  77h ; w
                db  88h
                db  68h ; h
                db  87h
                db  6Fh ; o
                db  86h
                db  20h
                db  85h
                db  68h ; h
                db  61h ; a
                db  73h ; s
                db  20h
                db  83h
                db  63h ; c
                db  75h ; u
                db  81h
                db  72h ; r
                db  83h
                db  73h ; s
                db  65h ; e
                db  64h ; d
                db  20h
                db  80h
                db  6Dh ; m
                db  79h ; y
                db  20h
                db  85h
                db  6Bh ; k
                db  69h ; i
                db  81h
                db  6Eh ; n
                db  67h ; g
                db  64h ; d
                db  6Fh ; o
                db  6Dh ; m
                db  20h
                db  85h
                db  61h ; a
                db  82h
                db  6Eh ; n
                db  64h ; d
                db  20h
                db  84h
                db  74h ; t
                db  75h ; u
                db  72h ; r
                db  81h
                db  6Eh ; n
                db  65h ; e
                db  64h ; d
                db  20h
                db  80h
                db  87h
                db  6Dh ; m
                db  82h
                db  88h
                db  79h ; y
                db  87h
                db  20h
                db  81h
                db  86h
                db  62h ; b
                db  65h ; e
                db  83h
                db  6Ch ; l
                db  6Fh ; o
                db  81h
                db  76h ; v
                db  65h ; e
                db  83h
                db  64h ; d
                db  20h
                db  85h
                db  64h ; d
                db  61h ; a
                db  75h ; u
                db  67h ; g
                db  68h ; h
                db  80h
                db  74h ; t
                db  65h ; e
                db  72h ; r
                db  20h
                db  85h
                db  74h ; t
                db  6Fh ; o
                db  20h
                db  83h
                db  87h
                db  73h ; s
                db  88h
                db  74h ; t
                db  87h
                db  6Fh ; o
                db  84h
                db  86h
                db  6Eh ; n
                db  65h ; e
                db  2Eh ; .
                db  22h ; "
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F0h
                db 0FEh
                db 0F7h
                db 0FAh
aDukeGarlandKne db 'Duke Garland knelt before the King. '
                db 0FBh
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F3h
                db 0EFh
                db  97h
                db  22h ; "
                db  93h
                db  96h
                db  59h ; Y
                db  6Fh ; o
                db  90h
                db  75h ; u
                db  72h ; r
                db  20h
                db  4Dh ; M
                db  61h ; a
                db  91h
                db  6Ah ; j
                db  65h ; e
                db  95h
                db  73h ; s
                db  74h ; t
                db  79h ; y
                db  2Ch ; ,
                db  20h
                db  90h
                db  49h ; I
                db  20h
                db  91h
                db  68h ; h
                db  61h ; a
                db  93h
                db  76h ; v
                db  65h ; e
                db  20h
                db  93h
                db  66h ; f
                db  6Fh ; o
                db  6Ch ; l
                db  6Ch ; l
                db  6Fh ; o
                db  77h ; w
                db  95h
                db  65h ; e
                db  64h ; d
                db  20h
                db  91h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  90h
                db  6Ch ; l
                db  69h ; i
                db  92h
                db  67h ; g
                db  68h ; h
                db  93h
                db  74h ; t
                db  20h
                db  94h
                db  93h
                db  6Fh ; o
                db  66h ; f
                db  20h
                db  91h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  93h
                db  53h ; S
                db  92h
                db  70h ; p
                db  69h ; i
                db  91h
                db  72h ; r
                db  92h
                db  69h ; i
                db  74h ; t
                db  20h
                db  95h
                db  74h ; t
                db  6Fh ; o
                db  20h
                db  92h
                db  74h ; t
                db  68h ; h
                db  92h
                db  69h ; i
                db  97h
                db  73h ; s
                db  98h
                db  20h
                db  97h
                db  95h
                db  70h ; p
                db  96h
                db  90h
                db  6Ch ; l
                db  61h ; a
                db  93h
                db  63h ; c
                db  65h ; e
                db  2Eh ; .
                db  22h ; "
                db  94h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
                db  22h ; "
                db  90h
                db  49h ; I
                db  20h
                db  93h
                db  6Bh ; k
                db  95h
                db  6Eh ; n
                db  6Fh ; o
                db  77h ; w
                db  94h
                db  20h
                db  93h
                db  6Eh ; n
                db  6Fh ; o
                db  74h ; t
                db  94h
                db  20h
                db  93h
                db  6Fh ; o
                db  95h
                db  66h ; f
                db  20h
                db  92h
                db  74h ; t
                db  68h ; h
                db  69h ; i
                db  95h
                db  73h ; s
                db  20h
                db  91h
                db  64h ; d
                db  65h ; e
                db  93h
                db  6Dh ; m
                db  6Fh ; o
                db  94h
                db  6Eh ; n
                db  2Ch ; ,
                db  20h
                db  93h
                db  6Eh ; n
                db  6Fh ; o
                db  90h
                db  72h ; r
                db  20h
                db  93h
                db  77h ; w
                db  68h ; h
                db  90h
                db  61h ; a
                db  93h
                db  74h ; t
                db  20h
                db  90h
                db  70h ; p
                db  6Fh ; o
                db  95h
                db  77h ; w
                db  65h ; e
                db  72h ; r
                db  93h
                db  73h ; s
                db  20h
                db  92h
                db  68h ; h
                db  65h ; e
                db  20h
                db  91h
                db  97h
                db  6Dh ; m
                db  98h
                db  61h ; a
                db  97h
                db  92h
                db  79h ; y
                db  96h
                db  20h
                db  93h
                db  70h ; p
                db  6Fh ; o
                db  91h
                db  73h ; s
                db  73h ; s
                db  65h ; e
                db  93h
                db  73h ; s
                db  73h ; s
                db  2Ch ; ,
                db  20h
                db  90h
                db  62h ; b
                db  75h ; u
                db  93h
                db  74h ; t
                db  20h
                db  92h
                db  69h ; i
                db  95h
                db  66h ; f
                db  20h
                db  91h
                db  74h ; t
                db  68h ; h
                db  90h
                db  65h ; e
                db  72h ; r
                db  65h ; e
                db  20h
                db  92h
                db  69h ; i
                db  93h
                db  73h ; s
                db  20h
                db  93h
                db  6Eh ; n
                db  6Fh ; o
                db  94h
                db  6Eh ; n
                db  65h ; e
                db  20h
                db  91h
                db  65h ; e
                db  6Ch ; l
                db  93h
                db  73h ; s
                db  65h ; e
                db  20h
                db  93h
                db  77h ; w
                db  68h ; h
                db  6Fh ; o
                db  20h
                db  90h
                db  63h ; c
                db  61h ; a
                db  94h
                db  6Eh ; n
                db  20h
                db  91h
                db  64h ; d
                db  65h ; e
                db  92h
                db  66h ; f
                db  65h ; e
                db  93h
                db  61h ; a
                db  74h ; t
                db  20h
                db  92h
                db  68h ; h
                db  69h ; i
                db  93h
                db  6Dh ; m
                db  2Ch ; ,
                db  20h
                db  99h
                db  91h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  94h
                db  6Eh ; n
                db  20h
                db  90h
                db  49h ; I
                db  20h
                db  93h
                db  77h ; w
                db  92h
                db  69h ; i
                db  93h
                db  6Ch ; l
                db  6Ch ; l
                db  20h
                db  91h
                db  64h ; d
                db  65h ; e
                db  92h
                db  64h ; d
                db  69h ; i
                db  90h
                db  63h ; c
                db  61h ; a
                db  92h
                db  74h ; t
                db  65h ; e
                db  20h
                db  90h
                db  6Dh ; m
                db  92h
                db  79h ; y
                db  20h
                db  90h
                db  6Ch ; l
                db  95h
                db  69h ; i
                db  94h
                db  66h ; f
                db  65h ; e
                db  20h
                db  93h
                db  74h ; t
                db  6Fh ; o
                db  20h
                db  92h
                db  74h ; t
                db  68h ; h
                db  93h
                db  69h ; i
                db  73h ; s
                db  20h
                db  90h
                db  74h ; t
                db  61h ; a
                db  97h
                db  93h
                db  73h ; s
                db  98h
                db  6Bh ; k
                db  97h
                db  2Eh ; .
                db  96h
                db  22h ; "
                db  94h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0EEh
                db 0FEh
                db 0F3h
                db  22h ; "
                db  83h
                db  46h ; F
                db  6Fh ; o
                db  80h
                db  72h ; r
                db  20h
                db  81h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  80h
                db  66h ; f
                db  69h ; i
                db  83h
                db  72h ; r
                db  73h ; s
                db  74h ; t
                db  20h
                db  80h
                db  74h ; t
                db  82h
                db  69h ; i
                db  83h
                db  6Dh ; m
                db  65h ; e
                db  20h
                db  82h
                db  73h ; s
                db  69h ; i
                db  84h
                db  6Eh ; n
                db  83h
                db  63h ; c
                db  65h ; e
                db  20h
                db  81h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  80h
                db  73h ; s
                db  61h ; a
                db  84h
                db  6Eh ; n
                db  83h
                db  64h ; d
                db  85h
                db  73h ; s
                db  83h
                db  74h ; t
                db  6Fh ; o
                db  80h
                db  72h ; r
                db  84h
                db  6Dh ; m
                db  20h
                db  82h
                db  62h ; b
                db  87h
                db  65h ; e
                db  88h
                db  81h
                db  67h ; g
                db  87h
                db  61h ; a
                db  84h
                db  86h
                db  6Eh ; n
                db  2Ch ; ,
                db  20h
                db  83h
                db  79h ; y
                db  6Fh ; o
                db  75h ; u
                db  20h
                db  81h
                db  68h ; h
                db  61h ; a
                db  83h
                db  76h ; v
                db  65h ; e
                db  20h
                db  80h
                db  62h ; b
                db  83h
                db  72h ; r
                db  6Fh ; o
                db  75h ; u
                db  84h
                db  67h ; g
                db  68h ; h
                db  83h
                db  74h ; t
                db  20h
                db  68h ; h
                db  6Fh ; o
                db  85h
                db  70h ; p
                db  65h ; e
                db  20h
                db  82h
                db  69h ; i
                db  84h
                db  6Eh ; n
                db  83h
                db  74h ; t
                db  6Fh ; o
                db  20h
                db  80h
                db  6Dh ; m
                db  82h
                db  79h ; y
                db  20h
                db  80h
                db  68h ; h
                db  65h ; e
                db  61h ; a
                db  72h ; r
                db  83h
                db  74h ; t
                db  2Ch ; ,
                db  20h
                db  80h
                db  44h ; D
                db  75h ; u
                db  83h
                db  6Bh ; k
                db  65h ; e
                db  20h
                db  87h
                db  80h
                db  47h ; G
                db  88h
                db  61h ; a
                db  87h
                db  72h ; r
                db  86h
                db  84h
                db  80h
                db  6Ch ; l
                db  61h ; a
                db  84h
                db  6Eh ; n
                db  64h ; d
                db  2Eh ; .
                db  20h
                db  20h
                db  80h
                db  4Dh ; M
                db  61h ; a
                db  82h
                db  79h ; y
                db  20h
                db  83h
                db  47h ; G
                db  6Fh ; o
                db  64h ; d
                db  84h
                db  20h
                db  83h
                db  67h ; g
                db  6Fh ; o
                db  20h
                db  82h
                db  77h ; w
                db  69h ; i
                db  83h
                db  74h ; t
                db  68h ; h
                db  20h
                db  83h
                db  79h ; y
                db  85h
                db  6Fh ; o
                db  75h ; u
                db  20h
                db  83h
                db  6Fh ; o
                db  84h
                db  6Eh ; n
                db  20h
                db  83h
                db  79h ; y
                db  6Fh ; o
                db  80h
                db  75h ; u
                db  72h ; r
                db  20h
                db  83h
                db  71h ; q
                db  75h ; u
                db  81h
                db  65h ; e
                db  73h ; s
                db  83h
                db  74h ; t
                db  2Eh ; .
                db  84h
                db  22h ; "
                db  84h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F0h
                db 0FDh
                db 0FDh
                db 0FAh
                db 0F3h
aSuddenlyTheRoo db 'Suddenly, the room grew cold.  A black mist swirled around them, '
                db 'then took on a hideous shape.'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0EDh
                db 0FDh
                db 0F3h
                db 0F9h
aAreYouTheFoolW db '"Are you the fool who dares to challenge me?  Don',27h,'t be absu'
                db 'rd!"'
                db 0F5h
                db 0F5h
                db 0FEh
                db 0FDh
                db  99h
                db 0F5h
                db 0FEh
                db 0F3h
                db 0FBh
                db 0EFh
                db  9Ah
                db  22h ; "
                db  90h
                db  41h ; A
                db  94h
                db  6Eh ; n
                db  93h
                db  64h ; d
                db  20h
                db  93h
                db  79h ; y
                db  6Fh ; o
                db  75h ; u
                db  20h
                db  90h
                db  6Dh ; m
                db  75h ; u
                db  93h
                db  73h ; s
                db  74h ; t
                db  20h
                db  92h
                db  62h ; b
                db  65h ; e
                db  20h
                db  90h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  91h
                db  65h ; e
                db  92h
                db  76h ; v
                db  69h ; i
                db  93h
                db  6Ch ; l
                db  20h
                db  90h
                db  4Ah ; J
                db  61h ; a
                db  92h
                db  73h ; s
                db  68h ; h
                db  69h ; i
                db  94h
                db  69h ; i
                db  6Eh ; n
                db  21h ; !
                db  22h ; "
                db 0F5h
                db 0F5h
                db 0EDh
                db 0FEh
                db 0F3h
                db 0F9h
aYouShallAddres db '"You shall address me as the Emperor of Chaos... '
                db  9Bh
aTheEmperorOfCh db 'THE EMPEROR OF CHAOS!"'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F7h
aYoungFoolICoul db '"Young fool, I could destroy you now, but I need a little amuseme'
                db 'nt.  I will give you some time to perform your little quest, but '
                db 'you must promise not to bore me."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
aOfCourseYouHav db '"Of course, you have no hope of defeating me."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0EFh
                db 0FEh
                db 0F3h
                db 0FBh
                db  22h ; "
                db  9Ah
                db  90h
                db  4Dh ; M
                db  61h ; a
                db  72h ; r
                db  95h
                db  6Bh ; k
                db  20h
                db  90h
                db  6Dh ; m
                db  92h
                db  79h ; y
                db  20h
                db  90h
                db  77h ; w
                db  6Fh ; o
                db  72h ; r
                db  93h
                db  64h ; d
                db  73h ; s
                db  2Ch ; ,
                db  20h
                db  91h
                db  65h ; e
                db  92h
                db  76h ; v
                db  69h ; i
                db  93h
                db  6Ch ; l
                db  20h
                db  90h
                db  6Fh ; o
                db  94h
                db  6Eh ; n
                db  65h ; e
                db  3Ah ; :
                db  20h
                db  90h
                db  49h ; I
                db  20h
                db  95h
                db  77h ; w
                db  92h
                db  69h ; i
                db  93h
                db  6Ch ; l
                db  6Ch ; l
                db  20h
                db  93h
                db  6Eh ; n
                db  6Fh ; o
                db  74h ; t
                db  94h
                db  20h
                db  93h
                db  73h ; s
                db  74h ; t
                db  6Fh ; o
                db  94h
                db  70h ; p
                db  20h
                db  90h
                db  75h ; u
                db  94h
                db  6Eh ; n
                db  92h
                db  74h ; t
                db  69h ; i
                db  93h
                db  6Ch ; l
                db  20h
                db  90h
                db  49h ; I
                db  20h
                db  91h
                db  68h ; h
                db  61h ; a
                db  93h
                db  76h ; v
                db  65h ; e
                db  20h
                db  91h
                db  72h ; r
                db  65h ; e
                db  93h
                db  63h ; c
                db  6Ch ; l
                db  90h
                db  61h ; a
                db  69h ; i
                db  93h
                db  6Dh ; m
                db  65h ; e
                db  64h ; d
                db  20h
                db  91h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  90h
                db  6Eh ; n
                db  69h ; i
                db  94h
                db  6Eh ; n
                db  65h ; e
                db  20h
                db  93h
                db  68h ; h
                db  6Fh ; o
                db  92h
                db  6Ch ; l
                db  79h ; y
                db  20h
                db  93h
                db  63h ; c
                db  72h ; r
                db  92h
                db  79h ; y
                db  73h ; s
                db  90h
                db  74h ; t
                db  61h ; a
                db  6Ch ; l
                db  93h
                db  73h ; s
                db  2Ch ; ,
                db  20h
                db  90h
                db  61h ; a
                db  94h
                db  6Eh ; n
                db  93h
                db  64h ; d
                db  20h
                db  92h
                db  73h ; s
                db  65h ; e
                db  61h ; a
                db  93h
                db  6Ch ; l
                db  65h ; e
                db  64h ; d
                db  20h
                db  95h
                db  79h ; y
                db  6Fh ; o
                db  75h ; u
                db  20h
                db  90h
                db  75h ; u
                db  94h
                db  6Eh ; n
                db  90h
                db  64h ; d
                db  65h ; e
                db  72h ; r
                db  20h
                db  91h
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db  90h
                db  65h ; e
                db  61h ; a
                db  72h ; r
                db  93h
                db  74h ; t
                db  68h ; h
                db  20h
                db  90h
                db  6Fh ; o
                db  94h
                db  6Eh ; n
                db  93h
                db  63h ; c
                db  65h ; e
                db  20h
                db  90h
                db  61h ; a
                db  94h
                db  6Eh ; n
                db  93h
                db  64h ; d
                db  20h
                db  93h
                db  66h ; f
                db  6Fh ; o
                db  90h
                db  72h ; r
                db  20h
                db  95h
                db  61h ; a
                db  93h
                db  6Ch ; l
                db  6Ch ; l
                db  21h ; !
                db  99h
                db  94h
                db  22h ; "
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F0h
                db 0F5h
                db 0F7h
                db 0FAh
aTheDemonLaughe db 'The demon laughed, and the sound was like breaking glass.'
                db 0F2h
                db 0F9h
                db 0EDh
aMyLabyrinthsAr db '"My labyrinths are immense, and run deep into the earth.  You',27h
                db 'll soon lose your way, and then my underlings will finish you off'
                db '."'
                db 0F5h
                db 0F5h
                db 0FEh
                db 0F3h
aItSBeenManyYea db '"It',27h,'s been many years since a stray mortal has wandered int'
                db 'o their realm. They are hungry for human flesh."'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0F0h
                db 0FDh
                db 0FEh
                db 0F3h
                db 0FAh
aWithThatJashii db 'With that, Jashiin disappeared leaving echoes of earsplitting lau'
                db 'ghter.'
                db 0F5h
                db 0F5h
                db 0FDh
                db 0FEh
                db 0EFh
                db 0F3h
                db 0FBh
aYouHavenTSeenT db '"You haven',27h,'t seen the last of me, Jashiin!'
                db 0F2h
aYourReignOfEvi db 'Your reign of evil is near its end!"'
                db 0F5h
                db 0F5h
                db 0F5h
                db 0FFh
                db  58h ; X
                db  25h ; %
                db 0F0h
                db    0
                db    0
                db    3
                db  68h ; h
                db  21h ; !
                db 0FCh
                db 0FCh
                db    4
                db    7
                db  70h ; p
                db  23h ; #
                db    1
                db 0FDh
                db    4
                db    7
                db  70h ; p
                db  24h ; $
                db    4
                db 0FDh
                db    4
                db    7
                db  78h ; x
                db  25h ; %
                db    6
                db 0FEh
                db    4
                db    7
                db  78h ; x
                db  28h ; (
                db    6
                db    2
                db    4
                db    7
                db  70h ; p
                db  29h ; )
                db    4
                db    3
                db    4
                db    7
                db  70h ; p
                db  2Ah ; *
                db    1
                db    3
                db    4
                db    7
                db  68h ; h
                db  2Ch ; ,
                db 0FCh
                db    4
                db    4
                db    7
                db 0FFh
                db    1
                db    8
                db    1
                db  42h ; B
                db  65h ; e
                db    3
                db  77h ; w
                db  61h ; a
                db    4
                db  72h ; r
                db  65h ; e
                db  2Ch ; ,
                db  20h
                db    3
                db  66h ; f
                db  6Fh ; o
                db    4
                db  72h ; r
                db  20h
                db    4
                db  49h ; I
                db  20h
                db    1
                db  73h ; s
                db  68h ; h
                db  61h ; a
                db    3
                db  6Ch ; l
                db  6Ch ; l
                db  20h
                db  77h ; w
                db    4
                db  61h ; a
                db  6Bh ; k
                db    3
                db  65h ; e
                db 0FFh
                db    1
                db    6
                db    3
                db  66h ; f
                db  72h ; r
                db  6Fh ; o
                db    3
                db  6Dh ; m
                db  20h
                db    2
                db  6Dh ; m
                db    1
                db  79h ; y
                db  20h
                db    3
                db  73h ; s
                db    1
                db  6Ch ; l
                db  65h ; e
                db  65h ; e
                db    1
                db  70h ; p
                db  20h
                db  6Fh ; o
                db  66h ; f
                db  20h
                db    3
                db  32h ; 2
                db  2Ch ; ,
                db    4
                db  30h ; 0
                db  30h ; 0
                db  30h ; 0
                db  20h
                db    1
                db  79h ; y
                db  65h ; e
                db    4
                db  61h ; a
                db  72h ; r
                db    3
                db  73h ; s
                db 0FFh
                db    1
                db    2
                db    4
                db  61h ; a
                db    2
                db  6Eh ; n
                db    3
                db  64h ; d
                db  20h
                db    3
                db  6Fh ; o
                db    2
                db  6Eh ; n
                db  63h ; c
                db  65h ; e
                db  20h
                db    4
                db  61h ; a
                db  67h ; g
                db  61h ; a
                db    1
                db  69h ; i
                db  6Eh ; n
                db  20h
                db    2
                db  72h ; r
                db  65h ; e
                db    4
                db  69h ; i
                db    1
                db  67h ; g
                db  6Eh ; n
                db  20h
                db    3
                db  6Fh ; o
                db  76h ; v
                db    4
                db  65h ; e
                db  72h ; r
                db  20h
                db    1
                db  74h ; t
                db  68h ; h
                db  65h ; e
                db  20h
                db    4
                db  77h ; w
                db  6Fh ; o
                db  72h ; r
                db    3
                db  6Ch ; l
                db  64h ; d
                db  2Eh ; .
                db    2
                db    0
byte_911E       db 1, 1, 1, 2, 2, 1, 1, 2, 2, 3, 3, 5, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 0
                db 0, 0, 0, 0, 0, 5, 6, 7, 8, 9, 0Ah, 0Bh, 0Ch, 0Dh, 0Eh, 0Fh, 10h, 11h, 12h, 13h, 14h, 15h, 16h, 0
                db 0, 0, 17h, 18h, 19h, 1Ah, 1Bh, 1Ch, 1Dh, 1Eh, 1Fh, 20h, 21h, 22h, 23h, 24h, 25h, 26h, 27h, 28h, 29h, 2Ah, 2Bh, 2Ch
                db 2Dh, 2Eh, 0, 0, 2Fh, 30h, 31h, 32h, 33h, 0, 0, 34h, 35h, 36h, 37h, 38h, 0, 39h, 26h, 3Ah, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3Bh, 3Ch, 3Dh, 0, 0, 0, 3Eh, 3Fh, 40h
                db 41h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 42h, 43h, 44h, 45h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 46h, 47h, 16h, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 48h, 49h, 4Ah, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 4Bh, 4Ch, 4Dh, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4Eh, 4Fh, 50h, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 51h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 52h, 53h, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 54h, 55h, 56h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 57h, 58h, 59h, 5Ah, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5Bh, 5Ch, 5Dh, 5Eh
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 5Fh, 60h, 61h, 62h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 63h, 64h, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 65h, 66h, 67h, 68h, 69h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6Ah, 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 70h, 71h, 72h, 73h, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 74h, 75h
                db 76h, 77h, 78h, 79h, 7Ah, 7Bh, 7Ch, 7Dh, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 7Eh, 7Fh, 80h, 81h, 82h, 83h, 84h, 85h, 86h, 87h, 88h, 89h, 0, 0, 0, 0
                db 0Fh, 8Ah, 8Bh, 8Ch, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2Fh, 8Dh, 8Eh, 8Fh, 90h, 91h
                db 92h, 93h, 94h, 95h, 96h, 97h, 0, 0, 0, 98h, 99h, 9Ah, 9Bh, 9Ch, 9Dh, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 9Eh, 9Fh, 0A0h, 0A1h, 0A2h, 0A3h, 0A4h, 0A5h, 0A6h, 0A7h, 0A8h, 0A9h, 16h, 0, 0AAh, 0ABh, 0ACh, 0ADh, 0AEh
                db 0AFh, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0B0h, 0B1h, 0B2h, 0B3h, 0B4h, 0B5h, 0B6h, 0B7h, 0B8h
                db 26h, 26h, 0B9h, 0BAh, 0BBh, 0BCh, 0BDh, 0BEh, 0BFh, 0C0h, 0C1h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
byte_947D       db 0, 2, 2, 3, 1, 0, 0, 2, 2, 3, 1, 1, 1, 2, 2, 0, 1, 2, 1, 1, 1, 1, 1, 1
                db 1, 1, 3, 2, 1, 1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 2, 2, 2, 1, 1, 1, 0, 0, 1, 0, 1, 1, 0
                db 0, 2, 1, 0, 2, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 2, 0, 3, 1, 0
byte_94DD       db 5, 4, 4, 4, 6, 8, 5, 3, 4, 4, 6, 6, 6, 5, 6, 8, 7, 5, 7, 7, 7, 7, 7, 7
                db 7, 7, 3, 4, 6, 6, 6, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 5, 8, 8, 8, 8, 8, 8
                db 8, 8, 8, 8, 7, 8, 8, 8, 8, 8, 7, 5, 3, 5, 6, 7, 7, 8, 8, 7, 8, 7, 7, 8
                db 8, 5, 6, 8, 5, 8, 7, 7, 8, 8, 8, 7, 6, 8, 8, 8, 7, 7, 7, 4, 8, 4, 7, 8
vfs_nec_grp     db    0
                db  17h
aNecGrp         db 'nec.grp',0
vfs_hou_grp     db    0
                db  12h
aHouGrp         db 'hou.grp',0
vfs_dmaou_grp   db    0
                db  0Fh
aDmaouGrp       db 'dmaou.grp',0
vfs_zopn_msd    db    0
                db  28h ; (
aZopnMsd        db 'zopn.msd',0
vfs_ttl1_grp    db    0
                db  1Eh
aTtl1Grp        db 'ttl1.grp',0
vfs_ttl2_grp    db    0
                db  1Fh
aTtl2Grp        db 'ttl2.grp',0
vfs_ttl3_grp    db    0
                db  20h
aTtl3Grp        db 'ttl3.grp',0
vfs_zend_msd    db    0
                db  27h ; '
aZendMsd        db 'zend.msd',0
vfs_waku_grp    db    0
                db  21h ; !
aWakuGrp        db 'waku.grp',0
vfs_ame_grp     db    0
                db  0Eh
aAmeGrp         db 'ame.grp',0
vfs_hime_grp    db    0
                db  10h
aHimeGrp        db 'hime.grp',0
vfs_isi_grp     db    0
                db  13h
aIsiGrp         db 'isi.grp',0
vfs_oui_grp     db    0
                db  1Ah
aOuiGrp         db 'oui.grp',0
vfs_sei_grp     db    0
                db  1Ch
aSeiGrp         db 'sei.grp',0
vfs_yuu1_grp    db    0
                db  22h ; "
aYuu1Grp        db 'yuu1.grp',0
vfs_yuu2_grp    db    0
                db  23h ; #
aYuu2Grp        db 'yuu2.grp',0
vfs_yuu3_grp    db    0
                db  24h ; $
aYuu3Grp        db 'yuu3.grp',0
vfs_yuu4_grp    db    0
                db  25h ; %
aYuu4Grp        db 'yuu4.grp',0
vfs_yuup_grp    db    0
                db  26h ; &
aYuupGrp        db 'yuup.grp',0
vfs_oup_grp     db    0
                db  1Bh
aOupGrp         db 'oup.grp',0
vfs_maop_grp    db    0
                db  14h
aMaopGrp        db 'maop.grp',0
vfs_game_bin    db    0
                db    0
aGameBin        db 'game.bin',0
seg000          ends

                end     start
