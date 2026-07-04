                .286
                .model tiny

nec             segment byte public 'CODE'
                assume cs:nec, ds:nec

; I added this startup code to make it standalone .com file
; It shows the extracted bitmaps exactly as in Zeliard
                org     100h
start:
        mov ax, cs
        add ax, 1000h
        mov seg1, ax

		push offset nec_filename
		push offset nec_buffer
		push 5786 ; size
		call read_file
        
		push offset hou_filename
		push offset hou_buffer
		push 1500 ; size
		call read_file
        
		push offset font_filename
		push offset bold_font_8x8
		push 1623
		call read_file

        add word ptr ds:bold_font_8x8, offset bold_font_8x8

                mov     ax, 13h
                int     10h         ; set video mode
                call    set_mcga_palette


                mov     es, word ptr cs:seg1
                mov     si, offset nec_buffer
                mov     di, 4000h
                call    sub_6D5E
                call    Clear_Screen
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                mov     ax, 1
                call    GDMCGA_Fade_Palette
                mov     al, 0FFh
                mov     bx, 1220h
                mov     cx, 2C68h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    Decompress_3Plane_2Row
                call    sub_6358
                mov     ax, 2
                call    GDMCGA_Fade_Palette
                mov     al, 0FFh
                mov     bx, 1220h
                mov     cx, 2C68h
                mov     es, word ptr cs:seg1
                mov     di, 4000h
                call    Decompress_3Plane_Interleaved
                mov     es, word ptr cs:seg1
                mov     si, offset hou_buffer
                mov     di, 9000h
                call    sub_6D5E
                mov     bx, 2048h
                mov     cx, 1040h
                mov     es, word ptr cs:seg1
                mov     di, 75A0h
                call    Decompress_And_Copy_To_VRAM
;                mov     byte ptr cs:soundFX_request, 4
;                mov     si, 9060h
;                call    Animate_Sprites

                ; done
wait_for_esc:   in      al, 60h
                dec     al
                jnz     short wait_for_esc
                mov     ax, 3
                int     10h
                retn

read_file proc
    push bp
    mov bp, sp
    
    ; Stack Frame Layout:
    ; [bp + 8] -> Filename Offset
    ; [bp + 6] -> Buffer Offset
    ; [bp + 4] -> Size
    ; [bp + 2] -> Return Address
    ; [bp + 0] -> Saved BP

    ; --- 1. Open File ---
    mov dx, [bp + 8]    ; Get Filename offset
    mov ax, 3D00h       ; Open for reading
    int 21h
    jc  file_error      ; Use JC (Jump if Carry) for DOS errors
    mov bx, ax          ; BX = file handle

    ; --- 2. Read File ---
    mov dx, [bp + 6]    ; Get Buffer offset
    mov cx, [bp + 4]    ; Get Size
    mov ah, 3Fh         ; Read from handle
    int 21h
    jc  file_error

    ; --- 3. Close File ---
    mov ah, 3Eh         ; Close handle
    int 21h
    jc  file_error

    pop bp
    retn 6               ; Return and clean up 6 bytes from stack
read_file endp

file_error:
    int 20h             ; Terminate if any operation fails

set_mcga_palette:
                push    cs
                pop     ds
                mov     si, offset byte_A456
                xor     bx, bx
                mov     cx, 8

loc_A425:
                push    cx
                lodsb
                mov     dh, al
                lodsb
                mov     dl, al
                lodsb
                mov     ah, al
                push    si
                mov     si, offset byte_A456
                mov     cx, 8

loc_A436:
                push    cx
                push    ax
                push    dx
                lodsb
                add     dh, al
                lodsb
                add     al, dl
                mov     ch, al
                lodsb
                add     al, ah
                mov     cl, al
                mov     ax, 1010h
                int     10h             ; - VIDEO - SET INDIVIDUAL DAC REGISTER (EGA, VGA/MCGA)
                                        ; BX = register number, CH = new value for green (0-63)
                                        ; CL = new value for blue (0-63), DH = new value for red (0-63)
                inc     bx
                pop     dx
                pop     ax
                pop     cx
                loop    loc_A436
                pop     si
                pop     cx
                loop    loc_A425
                retn
; ---------------------------------------------------------------------------
byte_A456       db 0, 0, 0, 1Fh, 1Fh, 1Fh, 1Fh, 0, 0, 0, 1Fh, 0, 0, 1Fh
                db 1Fh, 0, 0, 1Fh, 1Fh, 1Fh, 0, 1Fh, 0, 1Fh

Clear_Screen proc near
                mov     ax, 0A000h
                mov     es, ax
                xor     di, di
                mov     cx, 8

loc_2C0B:
                push    cx
                push    di
                mov     cx, 19h

loc_2C10:
                push    cx
                push    di
                mov     cx, 0A0h
                xor     ax, ax
                rep stosw
                pop     di
                add     di, 0A00h
                pop     cx
                loop    loc_2C10
                pop     di
                add     di, 140h
                pop     cx
                loop    loc_2C0B
                retn
Clear_Screen endp


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

; Decompress 3-plane graphics and copy directly to VRAM
;   Input:
;     CH = height
;     CL = width
;     DI = source data pointer (DS:DI)
;     ES = destination segment (VRAM)
;     BH = screen Y
;     BL = screen X
Decompress_And_Copy_To_VRAM        proc near
                push    ds
                push    ax
                push    bx
                push    cx
                mov     al, ch
                mul     cl
                mov     bp, ax
                push    es
                pop     ds
                mov     si, di
                mov     ax, cs
                add     ax, 3000h
                mov     es, ax          ; seg3
                mov     di, 0
                mov     cs:decomp_plane3, 0
                mov     cx, bp
                shr     cx, 1

loc_33DA:
                add     bp, bp
                mov     ax, ds:[bp+si]
                xchg    ah, al
                mov     cs:decomp_plane2, ax
                shr     bp, 1
                mov     ax, ds:[bp+si]
                xchg    ah, al
                mov     cs:decomp_plane1, ax
                lodsw
                xchg    ah, al
                mov     cs:decomp_plane0, ax
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                loop    loc_33DA
                pop     cx
                pop     bx
                pop     ax
                pop     ds

loc_340D:
                push    ds
                call    Calc_VRAM_Addr
                mov     di, ax
                mov     si, 0
                push    es
                pop     ds
                mov     ax, 0A000h
                mov     es, ax
                xor     bx, bx
                mov     bl, ch
                add     bx, bx
                add     bx, bx
                xor     ch, ch

loc_3427:
                push    cx
                push    di
                mov     cx, bx
                rep movsb
                pop     di
                pop     cx
                add     di, 320
                loop    loc_3427
                pop     ds
                retn
Decompress_And_Copy_To_VRAM        endp


; Core 3-plane to 2bpp bit interleaver (decompressor)
;   Input:
;     decomp_plane0..3 = 4 plane words with bits to interleave
;   Output:
;     AX = decompressed 2bpp word (8 pixels × 2bpp)
;   Clobbers: AX, CX, flags, plane registers shifted
Decompress_3Plane_To_2bpp        proc near
                push    cx
                mov     cx, 2
loc_446D:
                rol     cs:decomp_plane3, 1
                adc     ax, ax
                rol     cs:decomp_plane2, 1
                adc     ax, ax
                rol     cs:decomp_plane1, 1
                adc     ax, ax
                rol     cs:decomp_plane0, 1
                adc     ax, ax
                rol     cs:decomp_plane3, 1
                adc     ax, ax
                rol     cs:decomp_plane2, 1
                adc     ax, ax
                rol     cs:decomp_plane1, 1
                adc     ax, ax
                rol     cs:decomp_plane0, 1
                adc     ax, ax
                loop    loc_446D
                xchg    ah, al
                pop     cx
                retn
Decompress_3Plane_To_2bpp        endp

; Convert screen tile coordinates to VRAM address
;   Input:
;     BH = screen Y coordinate (rows, each row = 320 bytes)
;     BL = screen X coordinate (tiles, each tile = 4 bytes wide)
;   Output:
;     AX = VRAM offset (320 * BH + BL * 4)
;   Clobbers: AX, BX, DX, flags
Calc_VRAM_Addr  proc near
                mov     dl, bl
                mov     bl, bh
                xor     bh, bh
                mov     dh, bh
                add     bx, bx
                add     bx, bx
                mov     ax, 320
                mul     dx
                add     ax, bx
                retn
Calc_VRAM_Addr  endp

; Core 8-plane render loop: iterates 8 bit-plane groups, calls render_callback per row
;   Input:
;     CH = tile width (columns)
;     render_callback = function pointer (Render_SetOr_Pixel / Render_SetOr_Transparent / Render_MaskErase_2bpp)
;     render_mode = mode flag for callbacks
;     decomp_plane0..3 = pre-loaded decompressed plane data
;   Clobbers: ES:DI (VRAM), SI, AX, CX, flags
Render_8Plane_Loop  proc near
                mov     cs:plane_group, 0
                mov     ax, 0A000h
                mov     es, ax
                mov     bp, 8
loc_31C2:
                mov     al, cs:plane_group
                mov     cs:plane_row, al
                push    cx
                push    si
                push    di
loc_31D3:
                mov     bl, cs:plane_row
                and     bx, 7
                mov     bl, cs:byte_32B9[bx]
                call    cs:render_callback
                inc     cs:plane_row
                mov     al, ch
                xor     ah, ah
                add     ax, ax
                add     ax, ax
                add     si, ax
                add     di, 320
                dec     cl
                jz      short loc_3225
                mov     bl, cs:plane_row
                and     bx, 7
                mov     bl, cs:byte_32C1[bx]
                call    cs:render_callback
                inc     cs:plane_row
                mov     al, ch
                xor     ah, ah
                add     ax, ax
                add     ax, ax
                add     si, ax
                add     di, 320
                dec     cl
                jnz     short loc_31D3

loc_3225:
                pop     di
                pop     si
                pop     cx
                inc     cs:plane_group

                call    delay100
                dec     bp
                jnz     short loc_31C2
                retn
Render_8Plane_Loop  endp

; Like Render_SetOr_Pixel but skips zero-value source pixels (transparent pixel handling)
;   Input:
;     SI = source pixel data pointer
;     DI = VRAM destination
;     CH = number of pixels to render
;     BL = bitmask
;     render_mode = 0 = OR onto VRAM, 0FFh = direct write
;   Clobbers: AX, CX, SI, DI, flags
Render_SetOr_Transparent        proc near
                test    cs:render_mode, 0FFh
                jz      short loc_325B
                push    si
                push    di
                push    cx
                mov     cl, ch
                xor     ch, ch
                add     cx, cx
                add     cx, cx

loc_328A:
                lodsb
                rol     bl, 1
                jnb     short loc_3296
                or      al, al
                jz      short loc_3296
                mov     es:[di], al

loc_3296:
                inc     di
                loop    loc_328A
                pop     cx
                pop     di
                pop     si
                retn
Render_SetOr_Transparent        endp

; Render a single row of pixels with set-or-OR logic (callback for Render_8Plane_Loop)
;   Input:
;     SI = source pixel data pointer
;     DI = VRAM destination
;     CH = number of pixels to render
;     BL = bitmask (from byte_32B9/byte_32C1 lookup table)
;     render_mode = 0 = OR onto VRAM, 0FFh = direct write
;   Clobbers: AX, CX, SI, DI, flags
Render_SetOr_Pixel        proc near
                test    cs:render_mode, 0FFh
                jz      short loc_325B
                push    si
                push    di
                push    cx
                mov     cl, ch
                xor     ch, ch
                add     cx, cx
                add     cx, cx

loc_324C:
                lodsb
                rol     bl, 1
                jnb     short loc_3254
                mov     es:[di], al

loc_3254:
                inc     di
                loop    loc_324C
                pop     cx
                pop     di
                pop     si
                retn
; ---------------------------------------------------------------------------

loc_325B:
                push    si
                push    di
                push    cx
                mov     cl, ch
                xor     ch, ch
                add     cx, cx
                add     cx, cx

loc_3266:
                lodsb
                rol     bl, 1
                sbb     ah, ah
                and     al, ah
                or      es:[di], al
                inc     di
                loop    loc_3266
                pop     cx
                pop     di
                pop     si
                retn
Render_SetOr_Pixel        endp

; Decompress 3-plane graphics, 2 source rows per dest row
;   Input:
;     CH = height (number of tile rows)
;     CL = width (number of tile columns)
;     DI = source data pointer (DS:DI)
;   Output:
;     ES = seg3 buffer, decompressed 2bpp bitmap at ES:0
Decompress_3Plane_2Row        proc near
                push    ax
                push    bx
                push    cx
                push    ds
                mov     al, ch
                mul     cl
                mov     bp, ax
                push    es
                pop     ds
                mov     si, di
                mov     ax, cs
                add     ax, 3000h
                mov     es, ax          ; seg3
                mov     di, 0
                mov     cs:decomp_plane1, 0
                mov     cs:decomp_plane2, 0
                mov     cx, bp
                shr     cx, 1

loc_305C:
                mov     ax, ds:[bp+si]
                xchg    ah, al
                mov     cs:decomp_plane3, ax
                lodsw
                xchg    ah, al
                mov     cs:decomp_plane0, ax
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                loop    loc_305C
                pop     ds
                pop     cx
                pop     bx
                pop     ax
                mov     di, 0
                jmp     loc_3189
; ---------------------------------------------------------------------------

; Decompress 3-plane graphics, interleaved source addressing
;   Input:
;     CH = height (number of tile rows)
;     CL = width (number of tile columns)
;     DI = source data pointer (DS:DI)
;   Output:
;     ES = seg3 buffer, decompressed 2bpp bitmap at ES:0
Decompress_3Plane_Interleaved:
                push    ax
                push    bx
                push    cx
                push    ds
                mov     al, ch
                mul     cl
                mov     bp, ax
                push    es
                pop     ds
                mov     si, di
                mov     ax, cs
                add     ax, 3000h
                mov     es, ax          ; seg3
                mov     di, 0
                mov     cs:decomp_plane3, 0
                mov     cx, bp
                shr     cx, 1

loc_30AB:
                add     bp, bp
                mov     ax, ds:[bp+si]
                xchg    al, ah
                mov     cs:decomp_plane2, ax
                shr     bp, 1
                mov     ax, ds:[bp+si]
                xchg    al, ah
                mov     cs:decomp_plane1, ax
                lodsw
                xchg    al, ah
                mov     cs:decomp_plane0, ax
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                loop    loc_30AB
                pop     ds
                pop     cx
                pop     bx
                pop     ax
                mov     di, 0
                jmp     loc_3189
; ---------------------------------------------------------------------------

; Render with MaskErase callback (2bpp erase via NOT+AND)
;   Input:
;     CH = height
;     CL = width
;     BH = screen Y coordinate
;     BL = screen X coordinate / 4
Render_With_MaskErase_Callback:
                push    ds
                push    ax
                push    es
                push    di
                call    Calc_VRAM_Addr
                mov     di, ax
                pop     si
                pop     ds
                pop     ax
                mov     cs:render_callback, offset Render_MaskErase_2bpp
                call    Render_8Plane_Loop
                pop     ds
                retn
; ---------------------------------------------------------------------------

; Decompress 3-plane graphics with XOR logic (AND+OR blend)
;   Input:
;     CH = height
;     CL = width
;     DI = source data pointer (DS:DI)
Decompress_3Plane_XOR:
                push    bx
                push    cx
                push    ds
                mov     al, ch
                mul     cl
                mov     bp, ax
                push    es
                pop     ds
                mov     si, di
                mov     ax, cs
                add     ax, 3000h
                mov     es, ax          ; seg3
                mov     di, 0
                mov     cs:decomp_plane0, 0
                mov     cx, bp
                shr     cx, 1
loc_311E:
                push    cx
                mov     bx, ds:[bp+si]
                xchg    bh, bl
                lodsw
                xchg    ah, al
                mov     dx, bx
                and     dx, ax
                mov     cx, bx
                or      cx, ax
                not     dx
                and     ax, dx
                and     bx, dx
                mov     cs:decomp_plane2, bx
                mov     cs:decomp_plane1, ax
                mov     cs:decomp_plane3, cx
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                call    Decompress_3Plane_To_2bpp
                stosw
                pop     cx
                loop    loc_311E
                pop     ds
                pop     cx
                pop     bx
                xor     ax, ax
                mov     di, 0
                push    ds
                push    ax
                push    es
                push    di
                call    Calc_VRAM_Addr
                mov     di, ax
                pop     si
                pop     ds
                pop     ax
                mov     cs:render_callback, offset Render_SetOr_Transparent
                mov     cs:render_mode, 0
                or      al, al
                jnz     short loc_317E
                call    Render_8Plane_Loop
loc_317E:
                mov     cs:render_mode, 0FFh
                call    Render_8Plane_Loop
                pop     ds
                retn
; ---------------------------------------------------------------------------
loc_3189:
                push    ds
                push    ax
                push    es
                push    di
                call    Calc_VRAM_Addr
                mov     di, ax
                pop     si
                pop     ds
                pop     ax
                mov     cs:render_callback, offset Render_SetOr_Pixel
                mov     cs:render_mode, 0
                or      al, al
                jnz     short loc_31A9
                call    Render_8Plane_Loop
loc_31A9:
                mov     cs:render_mode, 0FFh
                call    Render_8Plane_Loop
                pop     ds
                retn
Decompress_3Plane_2Row        endp

; Erase 2bpp pixels in VRAM using NOT+AND masking
;   Input:
;     DI = VRAM destination
;     CH = number of 2bpp pixels to erase
;     BL = bitmask (inverted)
;   Clobbers: AX, CX, SI, DI, flags
Render_MaskErase_2bpp        proc near
                push    di
                push    cx
                not     bl
                mov     cl, ch
                xor     ch, ch
                add     cx, cx

loc_32A7:
                rol     bl, 1
                sbb     al, al
                rol     bl, 1
                sbb     ah, ah
                and     es:[di], ax
                inc     di
                inc     di
                loop    loc_32A7
                pop     cx
                pop     di
                retn
Render_MaskErase_2bpp        endp

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


; Renders a 0FFh-terminated string with control codes
; BX: starting X coord
; CL: starting Y coord
; SI: string pointer
;   Control codes: 0Dh = newline, 80h-87h = color change
Render_String_FF_Terminated proc near
                mov     cs:word_2CC0, bx
                mov     cs:byte_2CC2, cl
                mov     al, 1
                test    byte ptr cs:font_highlight_flag, 0FFh
                jz      short loc_2930
                mov     al, 7

loc_2930:
                mov     cs:byte_2CBF, al

loc_2934:
                lodsb
                cmp     al, 0FFh
                jnz     short loc_293A
                retn
; ---------------------------------------------------------------------------

loc_293A:
                cmp     al, 0Dh
                jz      short loc_2955
                or      al, al
                js      short loc_2967
                push    cx
                push    bx
                push    si
                mov     ah, cs:byte_2CBF
                call    Render_Font_Glyph ; AL: ASCII character code
                                        ; AH: Palette/colour index
                                        ; BX: X pixel coordinate in frame_buffer
                                        ; CX: Y pixel coordinate (row)
                                        ; CS:0xFF77: Flag: 0 = normal colour mode, nonzero = "bright/highlight" mode
                pop     si
                pop     bx
                pop     cx
                add     bx, 8
                jmp     short loc_2934
; ---------------------------------------------------------------------------

loc_2955:
                add     cs:byte_2CC2, 8
                mov     cl, cs:byte_2CC2
                mov     bx, cs:word_2CC0
                jmp     short loc_2934
; ---------------------------------------------------------------------------

loc_2967:
                and     al, 7
                mov     cs:byte_2CBF, al
                jmp     short loc_2934
Render_String_FF_Terminated endp

; Renders an 8x8 font glyph from the letters font table
; AL: ASCII character code
; AH: Palette/colour index
; BX: X pixel coordinate in frame_buffer
; CX: Y pixel coordinate (row)
; font_highlight_flag: 0 = normal colour mode, nonzero = "bright/highlight" mode
Render_Font_Glyph proc near
                push    ds
                push    cs
                pop     ds
                push    bx
                xor     bx, bx
                mov     bl, ah
                mov     ah, ds:mul9[bx]
                test    byte ptr cs:font_highlight_flag, 0FFh
                jz      short loc_2809
                mov     ah, bl
                add     ah, ah
                add     ah, ah
                add     ah, ah
                add     ah, ah
                or      ah, bl
loc_2809:
                mov     ds:primary_color, ah
                pop     bx
                xor     ah, ah
                sub     al, 20h ; ' '
                add     ax, ax
                add     ax, ax
                add     ax, ax          ; glyphId*8
                add     ax, word ptr ds:bold_font_8x8
                push    ax
                mov     al, bl
                and     al, 3
                add     al, al
                mov     ds:shadow_color, al
                mov     ax, 320
                xor     ch, ch
                mul     cx
                add     ax, bx
                mov     di, ax
                pop     si
                mov     ax, 0A000h
                mov     es, ax
                mov     cx, 8
loc_283A:
                push    cx
                lodsb
                mov     cx, 8
next_bit:
                add     al, al          ; al bit 7
                jnb     short skip_zero_bit
                mov     dl, cs:primary_color
                mov     es:[di], dl
skip_zero_bit:
                inc     di
                loop    next_bit
                pop     cx
                add     di, 320-8
                loop    loc_283A
                pop     ds
                retn
Render_Font_Glyph endp

sub_6358        proc near
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    Clear_Seg2_Buffer
                mov     si, offset aTwoThousandYea ; "           Two thousand years, \rfrom t"...
loc_6366:
                call    Render_Text_String
                push    si
                mov     cx, 0Ah
loc_636F:
                push    cx
                mov     ax, cx
                neg     ax
                add     ax, 0Ah
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    Blit_Sprite_To_Screen
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
                call    Blit_Sprite_To_Screen
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
                call    sub_63CC  ; nop
                call    delay10
;                cmp     cs:frame_timer, al
;                jb      short sub_63AB
;                mov     byte ptr cs:frame_timer, 0
                retn
sub_63AB        endp


; =============== S U B R O U T I N E =======================================


sub_63CC        proc near
;                push    si
;                push    ax
;                call    word ptr cs:Confirm_Exit_Dialog_proc
;                call    word ptr cs:Handle_Pause_State_proc
;                call    word ptr cs:Joystick_Calibration_proc
;                call    word ptr cs:Joystick_Deactivator_proc
;                pop     ax
;                pop     si
                retn
sub_63CC        endp

loc_63E5:
                mov     byte ptr ds:byte_FF24, 8
                mov     al, 0FFh
                mov     bx, 0
                mov     cx, 50C8h
                call    Render_With_MaskErase_Callback

                call delay100
;loc_63F7:
;                test    byte ptr ds:music_status_flag, 0FFh
;                jz      short loc_63F7
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
                call    Clear_Screen
;                mov     si, offset vfs_zend_msd
;                mov     es, word ptr cs:seg1
;                mov     di, 3000h
;                mov     al, 5
;                call    word ptr cs:res_dispatcher_proc
;                mov     byte ptr ds:frame_timer, 0
;                push    ds
;                mov     ds, word ptr cs:seg1
;                mov     si, 3000h
;                xor     ax, ax
;                int     60h             ; adlib fn 0
;                pop     ds
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
                mov     ax, 1
                call    GDMCGA_Fade_Palette
                call    sub_6497
                jmp     short loc_6477

sub_6456        proc near

                test    byte ptr cs:spacebar_latch, 0FFh
                jnz     short loc_6477
                cmp     byte ptr cs:Current_ASCII_Char, 0Dh
                jz      short loc_6477
                call    sub_63CC  ; nop
                call    delay100
;                cmp     cs:frame_timer, al
;                jb      short sub_6456
;                mov     byte ptr cs:frame_timer, 0
                retn
; ---------------------------------------------------------------------------

loc_6477:
                mov     byte ptr ds:byte_FF24, 8
                call    Clear_Screen

                call delay100
;loc_6481:
;                test    byte ptr ds:music_status_flag, 0FFh
;                jz      short loc_6481
                mov     byte ptr cs:spacebar_latch, 0
                mov     byte ptr cs:Current_ASCII_Char, 0
;                jmp     loc_6540
           retn
sub_6456        endp


sub_6497        proc near
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    Clear_Seg2_Buffer
                mov     si, offset aTheHumbleGuysZ ; "           The Humble Guys!            "...

loc_64A5:
                call    Render_Text_String
                push    si
                mov     cx, 0Ah

loc_64AE:
                push    cx
                mov     ax, cx
                neg     ax
                add     ax, 0Ah
                mov     bx, 20h ; ' '
                mov     cx, 5078h
                call    Blit_Sprite_To_Screen
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
                call    Blit_Sprite_To_Screen
                mov     al, 1Ch
                call    sub_6456
                pop     cx
                loop    loc_64D3
                retn
sub_6497        endp

; Clear OR/AND blit buffer in seg2 (0x8000 words to zero)
;   Input: none
Clear_Seg2_Buffer        proc near
                mov     ax, cs:seg1
                add     ax, 1000h
                mov     es, ax          ; seg2
                xor     ax, ax
                mov     di, 0
                mov     cx, 8000h
                rep stosw
                retn
Clear_Seg2_Buffer        endp

; Render text string to text buffer using 8x8 font
;   Input:
;     SI = pointer to FF-terminated string
;   Output:
;     text_buffer = rendered 2bpp bitmap
Render_Text_String        proc near
                push    cs
                pop     es
                mov     di, offset text_buffer
                xor     ax, ax
                mov     cx, 1600
                rep stosw
                mov     di, offset text_buffer

loc_32D8:
                lodsb
                cmp     al, 0FFh
                jnz     short loc_32DE
                retn
; ---------------------------------------------------------------------------

loc_32DE:
                sub     al, 20h ; ' '
                jnb     short loc_32E3
                retn
; ---------------------------------------------------------------------------

loc_32E3:
                jz      short loc_331E
                push    si
                push    di
                xor     ah, ah
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     ax, word ptr ds:bold_font_8x8
                mov     si, ax
                mov     cx, 8

loc_32F8:
                push    cx
                lodsb
                call    Expand_1bpp_To_2bpp
                mov     es:[di], dx
                call    Expand_1bpp_To_2bpp
                mov     es:[di+2], dx
                call    Expand_1bpp_To_2bpp
                mov     es:[di+4], dx
                call    Expand_1bpp_To_2bpp
                mov     es:[di+6], dx
                add     di, 320
                pop     cx
                loop    loc_32F8
                pop     di
                pop     si

loc_331E:
                add     di, 8
                jmp     short loc_32D8
Render_Text_String        endp


; Convert 1bpp to 2bpp: takes low 2 bits of AL, expands each to full byte in DX
;   Input:
;     AL = 1bpp source byte (bits 0-1 used)
;   Output:
;     DH:DL = expanded 2bpp (each bit duplicated to byte)
;   Clobbers: AX, DX, flags
Expand_1bpp_To_2bpp        proc near
                add     al, al
                sbb     dl, dl
                add     al, al
                sbb     dh, dh
                retn
Expand_1bpp_To_2bpp        endp

; Blit sprite to screen with AND/OR composite masking
;   Input:
;     CH = sprite height
;     CL = sprite width
;     BH = screen Y coordinate
;     BL = screen X coordinate / 160
Blit_Sprite_To_Screen        proc near
                push    ds
                push    cx
                push    bx
                mov     dl, 160
                mul     dl
                add     ax, ax
                add     ax, offset text_buffer
                mov     si, ax
                add     cl, bl
                mov     al, 160
                mul     cl
                add     ax, ax
                add     ax, 0
                push    ax
                push    si
                mov     ax, cs
                add     ax, 2000h
                mov     ds, ax          ; seg2
                push    ds
                pop     es
                mov     di, 0
                mov     si, 320
                mov     cx, 7F60h
                rep movsw
                pop     si
                pop     di
                push    cs
                pop     ds
                mov     cx, 160
                rep movsw
                pop     bx
                push    bx
                call    Calc_VRAM_Addr
                mov     di, ax
                pop     bx
                mov     al, 160
                mul     bl
                add     ax, ax
                mov     bl, bh
                xor     bh, bh
                add     bx, bx
                add     bx, bx
                add     ax, bx
                mov     si, ax
                add     si, 0
                mov     ax, cs
                add     ax, 2000h
                mov     ds, ax          ; seg2
                mov     ax, 0A000h
                mov     es, ax
                pop     cx
                mov     dx, 1001100110011001b
                mov     bp, 0110011001100110b
                xor     bx, bx
                mov     bl, ch
                add     bx, bx
                xor     ch, ch

loc_339C:
                push    cx
                push    di
                mov     cx, bx

loc_33A0:
                and     es:[di], dx
                lodsw
                and     ax, bp
                or      es:[di], ax
                inc     di
                inc     di
                loop    loc_33A0
                pop     di
                add     di, 320
                pop     cx
                loop    loc_339C
                pop     ds
                retn
Blit_Sprite_To_Screen        endp

; Animate 9 on-screen entities with frame-timer pacing
;   Input: none (uses entity data at VRAM A000:0000)
Animate_Sprites        proc near
                push    cs
                pop     es
                mov     di, 0A000h
                xor     dx, dx
                mov     cx, 9

loc_3441:
                mov     al, 1
                stosb
                mov     ax, dx
                stosw
                movsw
                stosw
                mov     ax, 101h
                stosw
                movsb
                movsb
                xor     al, al
                stosb
                stosb
                movsb
                movsb
                add     dx, 300h
                loop    loc_3441
                mov     ds:plane_row, 0
;                mov     byte ptr ds:frame_timer, 0

loc_3465:
                mov     si, 0A000h
                mov     cx, 9

loc_346B:
                push    cx
                test    byte ptr [si], 0FFh
                jz      short loc_34CD
                mov     al, [si+0Dh]
                cmp     al, [si+0Eh]
                jz      short loc_3485
                inc     byte ptr [si+0Ch]
                test    byte ptr [si+0Ch], 1
                jnz     short loc_3485
                inc     byte ptr [si+0Dh]

loc_3485:
                xor     bx, bx
                mov     bl, [si+0Dh]
                add     bx, bx
                add     bx, bx
                mov     cx, ds:word_3619[bx]
                mov     [si+7], cx
                mov     al, [si+4]
                add     al, [si+0Ah]
                mov     [si+4], al
                mov     bh, al
                mov     al, [si+3]
                add     al, [si+9]
                mov     [si+3], al
                mov     bl, al
                call    Calc_VRAM_Addr
                mov     [si+5], ax
                mov     di, ax
                mov     bp, [si+1]
                push    ds
                push    si
                mov     ax, 0A000h
                mov     ds, ax
                mov     ax, cs
                add     ax, 3000h
                mov     es, ax          ; seg3
                mov     si, di
                mov     di, bp
                call    Copy_VRAM_Block_Fwd
                pop     si
                pop     ds

loc_34CD:
                pop     cx
                add     si, 0Fh
                loop    loc_346B
                mov     si, 0A000h
                mov     cx, 9

loc_34D9:
                push    cx
                push    si
                mov     al, ds:plane_row
                and     al, 7
                mov     ah, 3
                mul     ah
                add     ax, offset byte_3637
                mov     si, ax
                lodsb
                mov     ds:byte_4289, al
                lodsb
                mov     ds:byte_428A, al
                lodsb
                mov     ds:byte_428B, al
                inc     ds:plane_row
                xor     ax, ax
                call    GDMCGA_Fade_Palette
                pop     si
                test    byte ptr cs:[si], 0FFh
                jz      short loc_353E
                xor     bx, bx
                mov     bl, [si+0Dh]
                add     bx, bx
                add     bx, bx
                mov     bp, ds:word_3617[bx]
                mov     cx, [si+7]
                mov     dl, [si]
                mov     byte ptr [si], 0
                mov     ax, [si+3]
                cmp     ah, 4Bh ; 'K'
                jnb     short loc_353E
                cmp     al, 0A0h
                jnb     short loc_353E
                mov     [si], dl
                mov     di, [si+5]
                push    ds
                push    si
                mov     ax, 0A000h
                mov     es, ax
                mov     ds, word ptr cs:seg1
                mov     si, bp
                call    Blit_Masked_OR_From_Seg1
                pop     si
                pop     ds

loc_353E:
                pop     cx
                add     si, 0Fh
                loop    loc_34D9

loc_3544:
                call    delay10
;                cmp     byte ptr cs:frame_timer, 1Eh
;                jb      short loc_3544
;                mov     byte ptr cs:frame_timer, 0
                mov     si, 0A000h
                mov     cx, 9

loc_3558:
                push    cx
                mov     bp, [si+1]
                mov     di, [si+5]
                mov     cx, [si+7]
                push    ds
                push    si
                mov     ax, 0A000h
                mov     es, ax
                mov     ax, cs
                add     ax, 3000h
                mov     ds, ax          ; seg3
                mov     si, bp
                call    Copy_VRAM_Block_Rev
                pop     si
                pop     ds
                pop     cx
                add     si, 0Fh
                loop    loc_3558
                mov     si, 0A000h
                mov     cx, 9

loc_3583:
                test    byte ptr [si], 0FFh
                jz      short loc_358B
                jmp     loc_3465
; ---------------------------------------------------------------------------

loc_358B:
                add     si, 0Fh
                loop    loc_3583
                mov     ax, 2
                jmp     GDMCGA_Fade_Palette
Animate_Sprites        endp


; save cx, si, di, bp
wait_vsync:
    mov dx, 03DAh

; Wait until NOT in retrace
.wait1:
    in al, dx
    test al, 08h
    jnz .wait1

; Wait until retrace starts
.wait2:
    in al, dx
    test al, 08h
    jz .wait2
    ret

delay10:
    push cx
    push dx
    mov cx, 10        ; ~1 second (70 Hz)
delay_loop:
    call wait_vsync
    loop delay_loop
    pop dx
    pop cx
    retn
delay100:
    push cx
    push dx
    mov cx, 100        ; ~10 second (70 Hz)
    jmp delay_loop

; VGA palette fade via DAC ports 0x3C8/0x3C9
;   Input:
; AL: palette index (0-255)
;     DS:SI = pointer to 16-block palette data sequence
GDMCGA_Fade_Palette        proc near
                mov     dx, 48
                mul     dx
                add     ax, offset byte_4289
                mov     si, ax
                mov     ds:fade_pal_ptr, si
                pushf
                cli
                mov     si, ds:fade_pal_ptr
                mov     ax, 40h
                mov     es, ax
                mov     dx, es:63h
                add     dx, 6

                push    dx
                in      al, dx          ; read Vertical Retrace
                mov     ds:fade_color_idx, 0
                mov     cx, 16

loc_424C:
                push    cx
                lodsb
                mov     bh, al
                lodsb
                mov     bl, al
                lodsb
                mov     ah, al
                push    si
                mov     si, ds:fade_pal_ptr
                mov     cx, 16

loc_425E:
                mov     dx, 3C8h        ; VGA Palette Address Register
                mov     al, ds:fade_color_idx
                out     dx, al          ; color index to change
                jmp     short $+2
                mov     dl, 0C9h        ; 3C9h: VGA Palette Data Register
                lodsb
                add     al, bh
                out     dx, al          ; modify red
                jmp     short $+2
                lodsb
                add     al, bl
                out     dx, al          ; modify green
                jmp     short $+2
                lodsb
                add     al, ah
                out     dx, al          ; modify blue
                jmp     short $+2
                inc     ds:fade_color_idx
                loop    loc_425E
                pop     si
                pop     cx
                loop    loc_424C
                pop     dx
                in      al, dx
                popf
                retn
GDMCGA_Fade_Palette        endp

; Copy a rectangular block forward within VRAM (SI source → DI dest, 8 rows tall)
;   Input:
;     SI = source VRAM address
;     DI = dest VRAM address
;     CH = width in pixels
;   Output: SI, DI unchanged
;   Clobbers: AX, CX, flags
Copy_VRAM_Block_Fwd        proc near
                push    si
                push    cx
loc_3598:
                push    si
                push    cx
                mov     cl, ch
                xor     ch, ch
                add     cx, cx
                add     cx, cx
                rep movsb
                pop     cx
                pop     si
                add     si, 320
                dec     cl
                jnz     short loc_3598
                pop     cx
                pop     si
                retn
Copy_VRAM_Block_Fwd        endp

; Copy a rectangular block within VRAM with DI as outer loop (reverse direction restore)
;   Input:
;     SI = source VRAM address
;     DI = dest VRAM address
;     CH = width in pixels
;   Output: SI unchanged, DI advanced by rows
;   Clobbers: AX, CX, DI, flags
Copy_VRAM_Block_Rev        proc near
                push    di
                push    cx

loc_35B3:
                push    di
                push    cx
                mov     cl, ch
                xor     ch, ch
                add     cx, cx
                add     cx, cx
                rep movsb
                pop     cx
                pop     di
                add     di, 320
                dec     cl
                jnz     short loc_35B3
                pop     cx
                pop     di
                retn
Copy_VRAM_Block_Rev        endp

; Read 3 planes from seg1 source, decompress, OR onto VRAM
;   Input:
;     CH = height
;     CL = width
;     SI = source data offset in seg1
;     BX = row stride within source
;     DI = dest VRAM address
;   Clobbers: AX, BX, CX, SI, DI, flags
Blit_Masked_OR_From_Seg1        proc near
                push    di
                push    cx
                mov     al, ch
                mul     cl
                mov     bx, ax
                mov     cs:decomp_plane3, 0

loc_35DB:
                push    di
                push    cx
                mov     cl, ch
                xor     ch, ch

loc_35E1:
                xor     al, al
                mov     ah, [bx+si]
                mov     cs:decomp_plane1, ax
                mov     ah, [si]
                mov     cs:decomp_plane0, ax
                mov     cs:decomp_plane2, ax
                inc     si
                push    bx
                call    Decompress_3Plane_To_2bpp
                pop     bx
                or      es:[di], ax
                push    bx
                call    Decompress_3Plane_To_2bpp
                pop     bx
                or      es:[di+2], ax
                add     di, 4
                loop    loc_35E1
                pop     cx
                pop     di
                add     di, 320
                dec     cl
                jnz     short loc_35DB
                pop     cx
                pop     di
                retn
Blit_Masked_OR_From_Seg1        endp

; ---------------------------------------------------------------------------
fade_pal_ptr    dw 0                    ; pointer to current palette data in fade sequence
fade_color_idx  db 0                    ; current VGA color index (0-255) during fade
byte_4289       db 0
byte_428A       db 0
byte_428B       db 0
                db 0, 0Fh, 0Fh,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,   0,   0, 0,   1Fh, 1Fh, 1Fh, 1Fh,   0, 1Fh, 1Fh, 1Fh
                db 7,   7,   7, 0Fh, 0Fh, 0Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh, 0,   1Fh,   0,   0, 1Fh, 1Fh, 0Fh, 0Fh,   0,  0Fh, 0Fh, 0Fh
                db 0,   0,   0,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh,  1Fh, 1Fh, 1Fh
                db 7,   7,   7, 0Fh, 0Fh, 0Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh,  1Fh, 1Fh, 1Fh
                db 0,   0,   0,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0,   0,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7, 0Fh, 0Fh, 0Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh,   0,   0, 1Fh, 1Fh, 0Fh, 0Fh,   0,  0Fh, 0Fh, 0Fh
                db 0,   0,   0, 1Fh,   0,   0,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,   0,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7, 1Fh, 1Fh, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  0Fh, 0Fh, 0Fh
                db 0,   0,   0,   0,   0, 0Fh, 0Fh,   0,   0, 0Fh,   0, 0Fh,   0, 0Fh, 0Fh,   0, 0Fh, 0Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh, 1Fh,   0, 1Fh, 1Fh, 0Fh, 0Fh,   0,  1Fh, 1Fh, 1Fh
                db 0,   0,   0,   0,   0, 1Fh, 1Fh,   0,   0,   0, 0Fh, 0Fh,   0, 1Fh,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh, 1Fh,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 0,   0,   0,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0,   0,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh,  1Fh,  0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 0,   0,   0,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7, 0Fh, 0Fh, 0Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh, 1Fh,  1Fh, 1Fh, 1Fh
                db 0,   0,   0,   0,   0, 1Fh, 1Fh,   0,   0,   0, 1Fh,   0,   0,   0,   0,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh, 1Fh,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 0,   0,   0,   0,   0, 1Fh, 1Fh,   0,   0, 0Fh,   0,   0,   0, 1Fh,   0, 1Fh,   0,   0, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh
                db 7,   7,   7,   0,   0, 1Fh, 1Fh,   0,   0, 1Fh,   0, 1Fh,   0, 1Fh, 1Fh,   0, 1Fh, 1Fh, 1Fh, 1Fh,   0,  1Fh, 1Fh, 1Fh

word_3617       dw 9000h
word_3619       dw 620h, 9180h, 620h, 9300h, 620h, 9480h, 620h, 9600h, 418h, 96C0h, 418h, 9780h, 418h, 9840h, 418h
byte_3637       db 1Fh, 1Fh, 0, 0Fh, 0Fh, 0, 1Fh, 1Fh, 1Fh, 0Fh, 0Fh, 0Fh
                db 1Fh, 0, 1Fh, 0Fh, 0, 0Fh, 1Fh, 0, 0, 0Fh, 0, 0

decomp_plane0   dw 0                    ; plane 0 source for 3-plane decompression
decomp_plane1   dw 0                    ; plane 1 source for 3-plane decompression
decomp_plane2   dw 0                    ; plane 2 source for 3-plane decompression
decomp_plane3   dw 0                    ; plane 3 / accumulation shift register
render_callback dw 0                    ; render callback pointer / tile width
render_mode     db 0                    ; 0=OR mode, 0FFh=direct write; plane-select bitfield
plane_group     db 0                    ; current bit-plane group (0-7) / animation direction
plane_row       db 0                    ; current bit-plane row index (0-7) / animation phase
byte_32B9       db 80h, 20h, 8, 2, 40h, 10h, 4, 1
byte_32C1       db 1, 4, 10h, 40h, 2, 8, 20h, 80h
byte_2CBF       db 0
word_2CC0       dw 0
byte_2CC2       db 0
font_highlight_flag db 0ffh
copyright_str   db 87h, '    Copyright (C)1987,1990 GAME ARTS    ', 0Dh, '    Copyright (C)1990 Sierra On-Line    ', 0FFh
mul9            db 0, 9, 12h, 1Bh, 24h, 2Dh, 36h, 3Fh
primary_color   db 0
shadow_color    db 0
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
aTheHumbleGuysZ db '               ZELIARD                  ',0Dh,0Dh,'             -- STAFF --        '
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

seg1            dw 0
spacebar_latch  db 0
Current_ASCII_Char db 0
byte_FF24       db 0
nec_filename    db 'nec_grp.unp', 0
hou_filename    db 'hou_grp.unp', 0
font_filename   db 'font_grp.unp', 0
text_buffer     db 3200 dup(?)          ; off-screen text rendering buffer
bold_font_8x8   db 1623 dup(?)
nec_buffer      db 5786 dup(?)
hou_buffer      db 1500 dup(?)

nec            ends

                end     start
