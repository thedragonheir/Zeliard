                .286
                .model tiny

ttl3            segment byte public 'CODE'
                assume cs:ttl3, ds:ttl3

; I added this startup code to make it standalone .com file
; It shows the extracted bitmaps exactly as in Zeliard
                org     100h
start:
		mov	dx, offset ttl3_filename
		mov	ax, 3D00h
		int	21h
		jnb	open_ok
        retn
open_ok:        
		mov	bx, ax		; handle
		mov	dx, offset ttl3_buffer
		mov cx, 7797
		mov	ah, 3Fh
		int	21h		; DOS -	2+ - READ FROM FILE WITH HANDLE
					; BX = file handle, CX = number	of bytes to read
					; DS:DX	-> buffer
		jnb	read_ok
        retn
read_ok:        
		mov	ah, 3Eh
		int	21h		; DOS -	2+ - CLOSE A FILE WITH HANDLE
					; BX = file handle
		jnb	close_ok
        retn
close_ok:
		mov	dx, offset font_filename
		mov	ax, 3D00h
		int	21h
		jnb	open_ok1
        retn
open_ok1:        
		mov	bx, ax		; handle
		mov	dx, offset bold_font_8x8
		mov cx, 1623
		mov	ah, 3Fh
		int	21h		; DOS -	2+ - READ FROM FILE WITH HANDLE
					; BX = file handle, CX = number	of bytes to read
					; DS:DX	-> buffer
		jnb	read_ok1
        retn
read_ok1:        
		mov	ah, 3Eh
		int	21h		; DOS -	2+ - CLOSE A FILE WITH HANDLE
					; BX = file handle
		jnb	close_ok1
        retn
close_ok1:
        add word ptr ds:bold_font_8x8, offset bold_font_8x8

                mov     ax, 13h
                int     10h         ; set video mode

                call    set_mcga_palette


                mov     si, offset ttl3_buffer ; source graphics data after unpack
                mov     di, 4000h
                call    RLE_decompress
                
                push    es
                mov     ax, 4
                call    GDMCGA_Fade_Palette
                pop     es

                push    es
                xor     bx, bx
                mov     cl, 96h
                mov     si, offset copyright_str
                call    Render_String_FF_Terminated     ; BX: starting X coord
                                                        ; CL: starting Y coord
                                                        ; SI: string pointer
                                                        ;   Control codes: 0Dh = newline, 80h-87h = color change
                pop     es

                mov     bx, 70Fh
                mov     cx, 4170h  ; width = 70h, height = 41h
                mov     di, 4000h
                call    Decompress_3Plane_XOR
                ; done
wait_for_esc:   in      al, 60h
                dec     al
                jnz     short wait_for_esc
                mov     ax, 3
                int     10h
                retn

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

                call    delay10
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


ttl3_filename   db 'ttl3_grp.unp', 0
font_filename   db 'font_grp.unp', 0
bold_font_8x8:  db 1623 dup(?)
ttl3_buffer:

ttl3            ends

                end     start