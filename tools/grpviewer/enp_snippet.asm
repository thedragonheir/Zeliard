; usage:
mov     ds, cs:seg1
mov     si, monster_gfx
mov     bp, 0A000h ; transparency masks buffer
mov     cx, 256
call    Decompress_Tile_Data
; ...


; DS:SI - compressed data (will be unpacked in place)
; DS:BP - transparency masks buffer
; CX - number of 8x8 tiles to decompress
Decompress_Tile_Data proc near
                push    cx
                push    ds
                push    si
                mov     ax, cs
                add     ax, 3000h
                mov     es, ax          ; seg3
                mov     ax, 32
                mul     cx
                mov     cx, ax
                mov     di, 0
                rep movsb               ; copy compressed data to temp buffer seg3:0
                pop     di
                pop     es
                pop     cx
                mov     ax, cs
                add     ax, 3000h
                mov     ds, ax          ; seg3
                mov     si, 0
next_tile:
                push    cx
                mov     cx, 8
next_row_of_8:
                push    cx
                lodsw
                xchg    ah, al
                mov     dx, ax
                lodsw
                xchg    ah, al
                mov     cx, ax
                mov     cs:viewport_row_vram_offset, dx
                mov     cs:plane1_buf, cx
                or      ax, dx
                mov     bx, ax
                shr     bx, 1
                or      ax, bx
                add     bx, bx
                add     bx, bx
                or      ax, bx
                not     ax
                mov     cs:transparency_mask_bitplane_f, ax
                call    build_16_bits_from_2_planes
                mov     ax, dx
                stosw
                call    build_16_bits_from_2_planes
                mov     ax, dx
                stosw
                call    extract_transparency_byte_from_mask_plane_f
                mov     es:[bp+0], dl
                inc     bp
                pop     cx
                loop    next_row_of_8
                pop     cx
                loop    next_tile
                retn
Decompress_Tile_Data endp


build_16_bits_from_2_planes proc near
                mov     cx, 4
loc_4F4B:
                rol     word ptr cs:plane1_buf, 1
                adc     dx, dx
                rol     word ptr cs:viewport_row_vram_offset, 1
                adc     dx, dx
                rol     word ptr cs:plane1_buf, 1
                adc     dx, dx
                rol     word ptr cs:viewport_row_vram_offset, 1
                adc     dx, dx
                loop    loc_4F4B
                retn
build_16_bits_from_2_planes endp


extract_transparency_byte_from_mask_plane_f proc near
                mov     cx, 8
loc_4F6D:
                xor     al, al
                rol     cs:transparency_mask_bitplane_f, 1
                adc     al, al
                rol     cs:transparency_mask_bitplane_f, 1
                adc     al, al
                cmp     al, 11b
                je      short loc_4F83
                xor     al, al
loc_4F83:
                and     al, 1
                add     dl, dl
                or      dl, al
                loop    loc_4F6D
                retn
extract_transparency_byte_from_mask_plane_f endp

viewport_row_vram_offset                   dw 0       
plane1_buf                   dw 0
transparency_mask_bitplane_f dw 0       

; used in Decode_And_Render_MonsterEntity_Tile_With_Blit, hero_background_continue
pal_decode_tbl     dw offset pal_decode_data0
                   dw offset pal_decode_data1
                   dw offset pal_decode_data2
                   dw offset pal_decode_data3
                   dw offset pal_decode_data4
                   dw offset pal_decode_data3
pal_decode_data0   db 0, 1, 2, 3, 8, 9, 0Ah, 0Bh, 10h, 11h, 12h, 13h, 18h, 19h, 1Ah, 1Bh
pal_decode_data1   db 0, 2, 4, 6, 10h, 12h, 14h, 16h, 20h, 22h, 24h, 26h, 30h, 32h, 34h, 36h
pal_decode_data2   db 0, 1, 4, 5, 8, 9, 0Ch, 0Dh, 20h, 21h, 24h, 25h, 28h, 29h, 2Ch, 2Dh
pal_decode_data3   db 0, 5, 6, 7, 28h, 2Dh, 2Eh, 2Fh, 30h, 35h, 36h, 37h, 38h, 3Dh, 3Eh, 3Fh
pal_decode_data4   db 0, 6, 5, 7, 30h, 36h, 35h, 37h, 28h, 2Eh, 2Dh, 2Fh, 38h, 3Eh, 3Dh, 3Fh
nibble_decode_lut  dw 0       

; AH: nible-compressed tile idx; =4f
; AL: 6bit-packed tile idx;      =00
; DX: VRAM destination address
Decode_And_Render_MonsterEntity_Tile_With_Blit proc near
                push    es
                push    ds
                mov     bl, ds:tile_blit_mode ; =0
                or      al, al                ; =0
                jz      short loc_35A8
                js      short loc_35A8
                or      bl, 80h
loc_35A8:
                mov     cl, al                ; =0
                mov     al, ah ; compressed tile idx, =4f
                mov     ch, 32 ; 32 bytes (64 nibbles) per compressed tile
                mul     ch     ; =9e0
                mov     si, ax
                add     si, 4000h ; seg1:4000h - nible-compressed tiles (mman_cman_gfx, enpX_gfx); =49e0
                shr     ax, 1
                shr     ax, 1
                mov     bp, ax
                add     bp, 0A000h  ; =a278
                mov     ds, word ptr cs:seg1
                mov     di, dx   ; VRAM destination address
                mov     ax, 0A000h
                mov     es, ax
                mov     ch, bl
                and     bl, 7Fh
                xor     bh, bh
                add     bx, bx
                mov     ax, cs:pal_decode_tbl[bx]
                mov     cs:nibble_decode_lut, ax ; 16 bytes table addr, indexed by nibbles
                mov     al, cl
                or      ch, ch
                js      short with_blit
                push    di
                mov     di, vram_shadow_addr
                call    render_nibble_compressed_tile ; si: src (compressed) - 32 bytes (64 nibbles)
                pop     di
                mov     si, vram_shadow_addr
                mov     ax, 0A000h
                mov     ds, ax
                call    Copy_Tile_To_VRAM
                pop     ds
                pop     es
                retn
; ---------------------------------------------------------------------------

with_blit:
                push    di
                mov     di, vram_shadow_addr
                call    decode_and_render_tile_with_blitting
                pop     di
                mov     si, vram_shadow_addr
                mov     ax, 0A000h
                mov     ds, ax
                call    Copy_Tile_To_VRAM
                pop     ds
                pop     es
                retn
Decode_And_Render_MonsterEntity_Tile_With_Blit endp


; =============== S U B R O U T I N E =======================================

; CL: tile idx + 1 (in seg1:8030h packed)
decode_and_render_tile_with_blitting proc near
                push    bp
                push    si
                push    di
                dec     cl ; packed tile idx
                mov     al, 48
                mul     cl
                add     ax, 8030h
                mov     si, ax ; source addr of packed tile
                call    render_48bytes_packed_tile ; prepare BG tile (48 bytes packed)
                pop     di
                pop     si
                pop     bp
                jmp     short $+2

; render hero tile over background
; SI: pointer to tile data (packed nibbles)
; BP: transparency data (1 bit per pixel)
; ES:DI: screen destination address; DI += 64
render_tile_to_temp_buffer:
                mov     cx, 8
loc_3629:
                push    cx
                mov     dl, ds:[bp+0]      ; blit mask
                lodsw                      ; 4 nibbles for extracting and blitting
                call    four_pixels_or_blit ; DL bits 7..4 - 4 bits to AND-blit background es:[di]
                                            ; AX: 4 nibbles to translate via LUT and OR-blit es:[di]
                lodsw                      ; next 4 nibbles
                call    four_pixels_or_blit ; DL bits 7..4 - 4 bits to AND-blit background es:[di]
                                            ; AX: 4 nibbles to translate via LUT and OR-blit es:[di]
                inc     bp
                pop     cx
                loop    loc_3629
                retn
decode_and_render_tile_with_blitting endp


; =============== S U B R O U T I N E =======================================

; Input: AX: 4 nibbles to translate via LUT and OR-blit es:[di]
;        DL: bits 7..4 - 4 bits to AND-blit background es:[di]
;        ES:DI: destination address
; Output: DL <<= 4; DI += 4
four_pixels_or_blit proc near
                mov     cx, 4
next_pixel_of_4:
                add     dl, dl ; extract dl bit7
                sbb     dh, dh
                and     dh, es:[di] ; blit with background
                call    get_pixel_from_table_by_ax_hi_nibble ; AH bits 7..4 - nibble to translate -> BL - translated byte; AX <<= 4
                or      bl, dh
                mov     es:[di], bl ; OR-blit dest. pixel with extracted
                inc     di
                loop    next_pixel_of_4
                retn
four_pixels_or_blit endp


; =============== S U B R O U T I N E =======================================

; si: src (compressed) - 32 bytes (64 nibbles)
; di: render address
render_nibble_compressed_tile proc near
                mov     cx, 8
loc_3654:
                push    cx
                lodsw
                call    draw_4_pix_from_table_by_ax
                lodsw
                call    draw_4_pix_from_table_by_ax
                pop     cx
                loop    loc_3654
                retn
render_nibble_compressed_tile endp


; =============== S U B R O U T I N E =======================================


draw_4_pix_from_table_by_ax proc near
                mov     cx, 4
loc_3664:
                call    get_pixel_from_table_by_ax_hi_nibble ; BL = cs:nibble_decode_lut[AH 7...4]
                mov     es:[di], bl
                inc     di
                loop    loc_3664
                retn
draw_4_pix_from_table_by_ax endp


; =============== S U B R O U T I N E =======================================

; Input:
;   AH bits 7..4 - nibble to translate
;   BX = 0
; BL - translated byte
get_pixel_from_table_by_ax_hi_nibble proc near
                add     ax, ax
                adc     bx, bx
                add     ax, ax
                adc     bx, bx
                add     ax, ax
                adc     bx, bx
                add     ax, ax
                adc     bx, bx
                and     bx, 0Fh
                add     bx, cs:nibble_decode_lut ; 16 bytes table addr, one of the pal_decode_data0..4
                mov     bl, cs:[bx]
                retn
get_pixel_from_table_by_ax_hi_nibble endp
