; call example:
                mov     ds, cs:seg1
                mov     si, packed_tile_ptr       ; roka_grp unpacked
                mov     cx, 124                   ; repack 124 tiles, 48 bytes each
                call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                pop     ds
                xor     al, al
                call    cs:Render_Roca_Tilemap_proc


; Reassembles 3-plane sprite data into packed 6bpp bitmap in place
; DS:SI: source (3-plane data)
; CX: number of 48-byte elements to reassemble (24 for magic spells)
; Output: packed 6bpp bitmap in DS:SI
; Uses seg3:3000h as temporary buffer
Reassemble_3_Planes_To_Packed_Bitmap proc near
                push    cx
                push    ds
                push    si
                mov     ax, cs
                add     ax, 3000h
                mov     es, ax          ; seg3
                mov     ax, 48
                mul     cx
                mov     cx, ax
                mov     di, 0
                rep movsb              ; copy to seg3:0 buffer
                pop     di             ; es:di = source
                pop     es
                pop     cx
                mov     ax, cs
                add     ax, 3000h
                mov     ds, ax
                mov     si, 0
next_48_bytes:
                push    cx
                call    assemble_48_bytes
                pop     cx
                loop    next_48_bytes
                retn
Reassemble_3_Planes_To_Packed_Bitmap endp

assemble_48_bytes proc near
                mov     cx, 8
eight_times:
                push    cx
                lodsw
                xchg    ah, al
                mov     cs:plane1, ax
                lodsw
                xchg    ah, al
                mov     cs:plane2, ax
                lodsw
                xchg    ah, al
                mov     cs:plane3, ax
                call    assemble_48_bits
                pop     cx
                loop    eight_times
                retn
assemble_48_bytes endp

assemble_48_bits proc near
                mov     cx, 2
two_times:
                call    assemble_3_bits
                call    assemble_3_bits
                call    assemble_3_bits
                call    assemble_3_bits
                call    assemble_3_bits
                rol     cs:plane3, 1
                adc     ax, ax
                stosw
                rol     cs:plane2, 1
                adc     ax, ax
                rol     cs:plane1, 1
                adc     ax, ax
                call    assemble_3_bits
                call    assemble_3_bits
                stosb
                loop    two_times
                retn
assemble_48_bits endp

assemble_3_bits proc near
                rol     cs:plane3, 1
                adc     ax, ax
                rol     cs:plane2, 1
                adc     ax, ax
                rol     cs:plane1, 1
                adc     ax, ax
                retn
assemble_3_bits endp

; ---------------------------------------------------------------------------
plane1          dw 0
plane2          dw 0
plane3          dw 0

; Input:
; AL = 0 or door.d_flags & 7
Render_Roca_Tilemap proc near
                mov     ds:render_counter, al
                mov     si, offset roca_tile_indices_28x18
                mov     ds:screen_address, viewport_top_left_vram_offset
                mov     cx, 18
viewport_rows:
                push    cx
                mov     cx, 28
viewport_cols:
                push    cx
                lodsb
                push    si
                call    RenderTileFrom_seg1
                pop     si
                add     ds:screen_address, 8
                pop     cx
                loop    viewport_cols
                add     ds:screen_address, 48+7*320+48
                pop     cx
                loop    viewport_rows
                retn
Render_Roca_Tilemap endp


; AL: tile index (0-based)
RenderTileFrom_seg1 proc near
                push    ds
                mov     cl, 48
                mul     cl   ; 48 bytes per tile
                add     ax, packed_tile_ptr
                mov     si, ax   ; si points to 48 bytes tile data
                mov     ds, cs:seg1
                mov     ax, 0A000h
                mov     es, ax
                mov     di, cs:screen_address
                mov     cx, 8
next_8px:
                push    cx
                call    Render8pxWithPaletteTransform
                add     di, 320-8
                pop     cx
                loop    next_8px
                pop     ds
                retn
RenderTileFrom_seg1 endp

; ds:si points to 48 bytes tile data
Render8pxWithPaletteTransform proc near
                mov     cx, 2
loc_466C:
                push    cx
                lodsw
                mov     dx, ax        ; dh=b23_16, dl=b15_8
                lodsb
                mov     bl, al        ; bl=b7_0, al=b7_0
                mov     bh, dl        ; bh=b15_8
                shr     dx, 1
                shr     dx, 1         ; dh=b23_18, dl=b17_10
                mov     es:[di], dh   ; b23_18
                shr     dl, 1
                shr     dl, 1         ; dl=b17_12
                mov     es:[di+1], dl ; b17_12
                add     bx, bx
                add     bx, bx        ; bh=b13_6, bl=b5_0
                and     bh, 3Fh       ; bh=b11_6
                mov     es:[di+2], bh ; b11_6
                and     al, 3Fh       ; al=b5_0
                mov     es:[di+3], al ; b5_0
                mov     bl, cs:render_counter
                xor     bh, bh
                add     bx, bx
                mov     cx, 4
loc_46A1:
                mov     al, es:[di]
                or      al, al
                jz      short skip_zero

                mov     ah, al
                shr     ah, 1
                shr     ah, 1
                shr     ah, 1   ; transform 3 higher bits
                call    cs:PaletteTransformTable[bx]
                add     ah, ah
                add     ah, ah
                add     ah, ah
                and     al, 111b
                or      al, ah
                mov     ah, al
                and     ah, 111b ; transform 3 lower bits
                call    cs:PaletteTransformTable[bx]
                and     al, 111000b
                or      al, ah
skip_zero:
                stosb
                loop    loc_46A1
                pop     cx
                loop    loc_466C
                retn
Render8pxWithPaletteTransform endp

; ---------------------------------------------------------------------------
PaletteTransformTable dw offset PaletteTransform_0
                dw offset PaletteTransform_1
                dw offset PaletteTransform_2
                dw offset PaletteTransform_3
                dw offset PaletteTransform_4


PaletteTransform_0 proc near
                cmp     ah, 6
                jne     short loc_46E6
                mov     ah, 3
                retn
loc_46E6:
                cmp     ah, 7
                je      short loc_46EC
                retn
loc_46EC:
                mov     ah, 5
                retn
PaletteTransform_0 endp


PaletteTransform_1 proc near
                cmp     ah, 4
                je      short loc_46F5
                retn
loc_46F5:
                mov     ah, 2
                retn
PaletteTransform_1 endp


PaletteTransform_2 proc near
                cmp     ah, 4
                jne     short loc_4700
                mov     ah, 5
                retn
loc_4700:
                cmp     ah, 7
                je      short loc_4706
                retn
loc_4706:
                mov     ah, 4
                retn
PaletteTransform_2 endp


PaletteTransform_3 proc near
                cmp     ah, 4
                jnz     short loc_4711
                mov     ah, 3
                retn
loc_4711:
                cmp     ah, 7
                jnz     short loc_4719
                mov     ah, 5
                retn
loc_4719:
                cmp     ah, 6
                jz      short loc_471F
                retn
loc_471F:
                mov     ah, 7
                retn
PaletteTransform_3 endp


PaletteTransform_4 proc near
                cmp     ah, 7
                jnz     short loc_472A
                mov     ah, 5
                retn
loc_472A:
                cmp     ah, 4
                jnz     short loc_4732
                mov     ah, 7
                retn
loc_4732:
                cmp     ah, 6
                jz      short loc_4738
                retn
loc_4738:
                mov     ah, 4
                retn
PaletteTransform_4 endp

; ---------------------------------------------------------------------------
roca_tile_indices_28x18:
db 07h, 08h, 09h, 0Ah, 07h, 08h, 0Bh, 0Ch, 07h, 08h, 09h, 0Ah, 19h, 3Dh, 61h, 27h, 1Dh, 1Eh, 1Dh, 1Eh, 1Fh, 20h, 1Fh, 20h, 1Dh, 1Eh, 1Fh, 20h 
db 0Dh, 0Eh, 0Fh, 10h, 0Fh, 10h, 0Dh, 0Eh, 0Fh, 10h, 17h, 18h, 3Eh, 5Ch, 62h, 26h, 2Ah, 25h, 21h, 22h, 21h, 22h, 23h, 24h, 21h, 22h, 21h, 22h 
db 09h, 0Ah, 07h, 08h, 07h, 08h, 09h, 0Ah, 07h, 08h, 19h, 54h, 59h, 5Dh, 63h, 32h, 2Fh, 2Eh, 1Fh, 20h, 1Fh, 20h, 1Dh, 1Eh, 1Fh, 20h, 1Fh, 20h 
db 0Fh, 10h, 11h, 12h, 0Fh, 10h, 0Dh, 0Eh, 17h, 18h, 50h, 55h, 5Ah, 5Eh, 64h, 66h, 28h, 30h, 23h, 24h, 21h, 22h, 23h, 24h, 21h, 22h, 23h, 24h 
db 07h, 08h, 0Ah, 0Ch, 07h, 08h, 09h, 0Ah, 1Ah, 34h, 51h, 56h, 5Bh, 5Fh, 65h, 67h, 2Fh, 2Dh, 1Dh, 1Eh, 1Fh, 20h, 1Dh, 1Eh, 1Fh, 20h, 1Dh, 1Eh 
db 0Fh, 10h, 0Dh, 0Eh, 0Dh, 0Eh, 17h, 18h, 49h, 4Dh, 52h, 57h, 00h, 60h, 69h, 68h, 6Ah, 6Bh, 28h, 26h, 21h, 22h, 2Bh, 26h, 21h, 22h, 21h, 22h 
db 07h, 08h, 09h, 0Ah, 09h, 0Ah, 1Bh, 46h, 4Ah, 4Eh, 53h, 58h, 00h, 00h, 00h, 00h, 69h, 6Ch, 31h, 2Dh, 1Fh, 20h, 2Ch, 2Dh, 1Fh, 20h, 1Fh, 20h 
db 13h, 14h, 13h, 14h, 17h, 18h, 43h, 47h, 4Bh, 4Fh, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 6Dh, 6Eh, 6Fh, 29h, 26h, 21h, 22h, 2Ah, 25h, 21h, 22h 
db 15h, 16h, 15h, 16h, 1Ch, 35h, 44h, 48h, 4Ch, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 69h, 71h, 73h, 74h, 1Fh, 20h, 2Ch, 27h, 1Fh, 20h 
db 17h, 18h, 38h, 3Ah, 3Fh, 42h, 45h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 6Dh, 75h, 77h, 79h, 6Fh, 2Bh, 26h, 29h, 26h 
db 1Ah, 34h, 39h, 3Bh, 40h, 41h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 76h, 78h, 7Ah, 7Bh, 31h, 32h, 2Fh, 2Dh 
db 33h, 36h, 37h, 3Ch, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 6Dh, 71h, 70h, 72h, 70h 
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h 
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h 
db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h, 00h 
db 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h, 01h, 02h 
db 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h, 03h, 04h 
db 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 05h, 06h, 06h, 05h, 05h, 06h, 05h, 06h 

render_counter     db 0

viewport_top_left_vram_offset equ (48+14*320)
