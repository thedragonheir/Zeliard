;==============================================================================
; ZELIARD ADLIB MUSIC DRIVER (YM3812 / OPL2)
;==============================================================================
; This driver provides multi‑channel music playback on the AdLib OPL2
; synthesizer.  It is called periodically via interrupt 60h and processes up
; to 6 melodic channels + 1 rhythm/percussion channel.  The event language
; is a compact command/note stream similar to the sound‑effect driver.
;
; OPL2 I/O:
;   Status/Index port   388h
;   Data port           389h
;   Register write implementation: see OPL_WriteReg (formerly sub_B08)
; All writes are guarded by a channel mute flag (sub_B00 / Ch_MuteCheck).
;
; Channel state structure (size 44 bytes):
MusicCh_State   struc
seq_ptr         dw ?    ; 0x00 ; pointer to next event in sequence
seq_save        dw ?    ; 0x02 ; saved seq_ptr (used by sub‑routines)
dur_tbl_save    dw ?    ; 0x04 ; saved dur_tbl_base (for sub‑routines)
loop_cnt        db ?    ; 0x06 ; loop counter (unused in melodic channels)
                db ?    ; 0x07
                db ?    ; 0x08
                db ?    ; 0x09
dur_tbl_base    dw ?    ; 0x0A ; pointer to duration multiplier table
opl_channel     db ?    ; 0x0C ; OPL channel number (0‑5 melodic, 6 rhythm)
flags           db ?    ; 0x0D ; bit 0: track finished, bit 6: envelope enabled
note_timer      db ?    ; 0x0E ; countdown for current event
volume          db ?    ; 0x0F ; total level (0‑7Fh, higher = quieter)
octave_shift    db ?    ; 0x10 ; octave / block multiplier (0..7)
flags2          db ?    ; 0x11 ; bit 1: envelope active, bit 4: pause, bit 5: vibrato active, etc.
note_dur_init   db ?    ; 0x12 ; initial note duration (from sequence)
algo_feedback   db ?    ; 0x13 ; low nibble = register C0h value (feedback/algorithm)
default_dur     db ?    ; 0x14 ; default note duration (used by rhythm channel)
perc_mask       db ?    ; 0x15 ; percussion instrument mask (rhythm channel only)
fnum_block      dw ?    ; 0x16 ; frequency: upper 5 bits = block, lower 10 bits = F‑number
transpose       db ?    ; 0x18 ; semitone transpose
pitch_bend_acc  dw ?    ; 0x19 ; pitch bend accumulator
pitch_bend_frac db ?    ; 0x1A ; fractional part of pitch bend
env_countdown   db ?    ; 0x1B ; envelope step counter
env_step_up     dw ?    ; 0x1C ; envelope increment (direction up)
env_step_down   dw ?    ; 0x1E ; envelope decrement (direction down)
env_scale       db ?    ; 0x20 ; envelope multiplier/scale (derived from note freq)
env_hold        db ?    ; 0x21 ; hold counter (from envelope data)
env_par1        db ?    ; 0x22 ; envelope parameter #1
env_par2        db ?    ; 0x23 ; envelope parameter #2
env_par3        db ?    ; 0x24 ; envelope parameter #3
env_par4        db ?    ; 0x25 ; envelope parameter #4
env_flags       db ?    ; 0x26 ; bit 7: alternate; lower 5 bits: period divider
env_alt_count   db ?    ; 0x27 ; toggle counter for par3/par4
instr_ptr       dw ?    ; 0x28 ; pointer to current instrument definition (15 bytes)
                db ?    ; 0x2A ; unused?
channel_mute    db ?    ; 0x2B ; 0 = channel plays, non‑zero = silenced
MusicCh_State   ends

include common.inc
include adlib.inc
                .286
                .model small

; Note that music_seg intersects with game_seg
; music_seg region 0x0000-0x00FF is the same as game_seg region 0xff00-0xffff
segment_shift   equ 0ff00h

music_seg       segment byte public 'CODE'
                assume cs:music_seg
                org 100h
start:

music_drv_poll_far      proc far
                jmp     near ptr sub_3E5
music_drv_poll_far      endp


; =============== S U B R O U T I N E =======================================

; AL: function (0..7)
; fn0	Init/Play	  Clears buffers, loads music data, and starts playback.
; fn1	Stop	      Silences all channels and halts the driver.
; fn2	BGM Toggle	  Pauses or Resumes the main music track.
; fn3	SFX Toggle	  Pauses or Resumes sound effects/secondary tracks.
; fn4	Raw Write	  Writes a byte directly to OPL2 Register 0.
; fn5	Drum Config	  Sets up OPL Rhythm Mode and percussion bits.
; fn6	Fade/Mute	  Manages channel fading and selective muting.
; fn7	Master Vol	  Adjusts global attenuation/volume (0-63).
int60_new       proc far
                push    ax
                push    bx
                push    cx
                push    dx
                push    di
                push    si
                push    bp
                push    ds
                push    es
                push    cs
                pop     es
                cld
                cmp     ax, 8
                jnb     short loc_11D
                mov     bx, ax
                shl     bx, 1
                call    cs:music_funcs[bx]
loc_11D:
                pop     es
                pop     ds
                pop     bp
                pop     si
                pop     di
                pop     dx
                pop     cx
                pop     bx
                pop     ax
                iret
int60_new       endp

; ---------------------------------------------------------------------------
music_funcs     dw offset music_fn0  ; Init/Play
                dw offset music_fn1  ; Stop
                dw offset music_fn2  ; BGM Toggle
                dw offset music_fn3  ; SFX Toggle
                dw offset music_fn4  ; Raw Write
                dw offset music_fn5  ; Drum Config
                dw offset music_fn6  ; Fade/Mute
                dw offset music_fn7  ; Master Vol

; =============== S U B R O U T I N E =======================================

; BGM Toggle	  Pauses or Resumes the main music track.
; CL = 00h -> Pause, CL != 00h -> Resume
music_fn2       proc near

                or      cl, cl
                jnz     short loc_145
                call    sub_3D2
                mov     byte ptr cs:(music_channel_param - segment_shift), 0FFh
                retn
; ---------------------------------------------------------------------------

loc_145:
                mov     byte ptr cs:(music_channel_param - segment_shift), 0
                jmp     loc_386
music_fn2       endp


; =============== S U B R O U T I N E =======================================

; SFX Toggle	  Pauses or Resumes sound effects/secondary tracks.
music_fn3       proc near

                or      cl, cl
                jz      short loc_15C
                call    sub_3D2
                mov     byte ptr cs:(byte_FF0B - segment_shift), 0FFh
                retn
; ---------------------------------------------------------------------------

loc_15C:
                mov     byte ptr cs:(byte_FF0B - segment_shift), 0
                jmp     loc_386
music_fn3       endp


; =============== S U B R O U T I N E =======================================

; Raw Write	  Writes a byte directly to OPL2 Register 0.
music_fn4       proc near
                xor     ah, ah
                jmp     word ptr cs:OPL_save_al_to_reg_ah_proc
music_fn4       endp


; =============== S U B R O U T I N E =======================================

; Drum Config	  Sets up OPL Rhythm Mode and percussion bits.
; CL: percussion flags
music_fn5       proc near
                test    cl, 38h
                jnz     short loc_178
                mov     al, 0FFh
                call    word ptr cs:OPL_save_al_to_reg_ah_proc

loc_178:
                mov     ch, cl
                mov     dl, 3
                xor     dh, dh

loc_17E:
                shr     ch, 1
                sbb     al, al
                jnz     short loc_199
                mov     al, dh
                add     al, al
                inc     al
                add     al, al
                add     al, al
                add     al, al
                add     al, al
                or      al, 8Fh
                call    word ptr cs:OPL_save_al_to_reg_ah_proc

loc_199:
                inc     dh
                dec     dl
                jnz     short loc_17E
                retn
music_fn5       endp


; =============== S U B R O U T I N E =======================================

; Fade/Mute	  Manages channel fading and selective muting.
music_fn6       proc near

                or      cl, cl
                jnz     short loc_1F6
                mov     di, offset opl_buf4
                test    byte ptr es:[di+2Bh], 0FFh
                jz      short loc_1B1
                call    sub_1EE

loc_1B1:
                add     di, 44
                test    byte ptr es:[di+2Bh], 0FFh
                jz      short loc_1BE
                call    sub_1EE

loc_1BE:
                test    byte ptr es:(music_status_flag - segment_shift), 0FFh
                jz      short loc_1C9
                jmp     sub_3D2
; ---------------------------------------------------------------------------

loc_1C9:
                test    byte ptr es:(byte_FF0B - segment_shift), 0FFh
                jz      short loc_1D4
                jmp     sub_3D2
; ---------------------------------------------------------------------------

loc_1D4:
                test    byte ptr es:(music_channel_param - segment_shift), 0FFh ; music_channel_param
                jz      short loc_1DF
                jmp     sub_3D2
; ---------------------------------------------------------------------------

loc_1DF:
                mov     ds, es:word_CBF
                mov     al, 4
                call    sub_3B1
                mov     al, 5
                jmp     sub_3B1
music_fn6       endp


; =============== S U B R O U T I N E =======================================


sub_1EE         proc near

                mov     byte ptr es:[di+2Bh], 0
                jmp     loc_778
sub_1EE         endp

; ---------------------------------------------------------------------------

loc_1F6:
                mov     di, offset opl_buf4
                shr     cl, 1
                sbb     al, al
                mov     es:[di+2Bh], al
                add     di, 2Ch ; ','
                shr     cl, 1
                sbb     al, al
                mov     es:[di+2Bh], al
                retn

; =============== S U B R O U T I N E =======================================

; Master Vol	  Adjusts global attenuation/volume (0-63).
; CL: attenuation/volume (0-63)
music_fn7       proc near
                not     cl
                mov     cs:(byte_FF76 - segment_shift), cl
                mov     al, cl
                and     al, 3Fh
                mov     ah, 7
                jmp     word ptr cs:OPL_save_al_to_reg_ah_proc
music_fn7       endp


; =============== S U B R O U T I N E =======================================


sub_21F         proc near
                cld
                push    cs
                pop     es
                mov     di, offset opl_buf0
                mov     cx, 302
                xor     al, al
                rep stosb
                mov     es:(byte_FF21 - segment_shift), al
                mov     es:(byte_FF22 - segment_shift), al
                mov     es:(byte_FF23 - segment_shift), al
                mov     es:(byte_FF24 - segment_shift), al
                mov     es:(byte_FF25 - segment_shift), al
                not     al
                mov     es:(music_status_flag - segment_shift), al
                retn
sub_21F         endp


; =============== S U B R O U T I N E =======================================

; Init/Play	  Clears buffers, loads music data, and starts playback.
music_fn0       proc near
                call    sub_21F
                call    sub_3D2
                mov     ax, 120h
                call    loc_B11
                mov     es:music_seq_ptr, si
                mov     es:word_CBF, ds
                mov     dx, si
                inc     si
                mov     di, offset opl_buf0
                mov     cx, 6
                xor     bl, bl

loc_268:
                call    sub_350
                add     di, 44
                inc     bl
                loop    loc_268
                add     si, 6
                mov     di, offset opl_buf6
                call    sub_376
                mov     byte ptr es:[di+0Ch], 80h
                lodsw
                add     ax, dx
                mov     es:word_CC1, ax
                lodsw
                lodsw
                add     ax, dx
                mov     es:word_CC3, ax
                mov     ax, 0BD20h
                call    loc_B11
                xor     al, al
                mov     es:24h, al
                mov     es:26h, al
                mov     es:byte_CBB, al
                mov     es:byte_CBC, al
                inc     al
                mov     es:byte_CB9, al
                mov     es:byte_CC6, al
                mov     es:byte_CB7, 7Fh
                mov     es:byte_CB8, 0
                mov     es:byte_CC5, 0
                push    cs
                pop     ds
                assume ds:music_seg
                mov     si, offset byte_B7E
                mov     bl, 6
                call    sub_30D
                mov     bl, 7
                call    sub_30D
                mov     bl, 8
                call    sub_30D
                mov     cx, 520h
                add     ah, 0A6h
                mov     al, cl
                call    loc_B11
                mov     ah, 0B6h
                mov     al, ch
                call    loc_B11
                mov     cx, 550h
                mov     ah, 0A7h
                mov     al, cl
                call    loc_B11
                add     ah, 0B7h
                mov     al, ch
                call    loc_B11
                mov     cx, 3C0h
                mov     ah, 0A8h
                mov     al, cl
                call    loc_B11
                add     ah, 0B8h
                mov     al, ch
                jmp     loc_B11
music_fn0       endp


; =============== S U B R O U T I N E =======================================


sub_30D         proc near
                push    bx
                xor     bh, bh
                mov     ah, byte_B75[bx]
                add     ah, 20h ; ' '
                mov     cx, 4

loc_31A:
                lodsb
                call    loc_B11
                add     ah, 3
                lodsb
                call    loc_B11
                add     ah, 1Dh
                loop    loc_31A
                add     ah, 40h ; '@'
                lodsb
                rol     al, 1
                rol     al, 1
                call    loc_B11
                add     ah, 3
                rol     al, 1
                rol     al, 1
                call    loc_B11
                pop     bx
                mov     ah, bl
                ror     al, 1
                ror     al, 1
                ror     al, 1
                ror     al, 1
                add     ah, 0C0h
                jmp     loc_B11
sub_30D         endp


; =============== S U B R O U T I N E =======================================


sub_350         proc near
                call    sub_376
                mov     byte ptr es:[di+10h], 3
                mov     es:[di+0Ch], bl
                mov     byte ptr es:[di+12h], 1
                mov     byte ptr es:[di+0Fh], 7Fh
                mov     byte ptr es:[di+18h], 0
                and     byte ptr es:[di+0Dh], 0BFh
                mov     byte ptr es:[di+11h], 0
                retn
sub_350         endp


; =============== S U B R O U T I N E =======================================


sub_376         proc near
                lodsw
                add     ax, dx
                mov     es:[di], ax
                mov     es:[di+2], ax
                mov     byte ptr es:[di+0Eh], 1
                retn
sub_376         endp

; ---------------------------------------------------------------------------
loc_386:
                push    cs
                pop     ds
                mov     si, offset byte_B7E
                mov     bl, 6
                call    sub_30D
                mov     bl, 7
                call    sub_30D
                mov     bl, 8
                call    sub_30D
                mov     di, offset opl_buf6
                call    sub_988
                xor     al, al
                mov     cx, 6

loc_3A5:
                push    cx
                push    ax
                call    sub_3B1
                pop     ax
                inc     al
                pop     cx
                loop    loc_3A5
                retn

; =============== S U B R O U T I N E =======================================


sub_3B1         proc near
                push    cs
                pop     es
                mov     ds, es:word_CBF
                mov     cl, 44
                mul     cl
                add     ax, offset opl_buf0
                mov     di, ax
                mov     si, es:[di+29h]
                jmp     sub_5AF
sub_3B1         endp


; =============== S U B R O U T I N E =======================================

; Stop	      Silences all channels and halts the driver.
music_fn1       proc near
                call    sub_3D2
                mov     byte ptr es:(music_status_flag - segment_shift), 0FFh
                retn
music_fn1       endp


; =============== S U B R O U T I N E =======================================


sub_3D2         proc near
                mov     ax, 0BD00h
                call    loc_B11
                mov     cx, 9
                mov     ah, 0B0h

loc_3DD:
                call    loc_B11
                inc     ah
                loop    loc_3DD
                retn
sub_3D2         endp


; =============== S U B R O U T I N E =======================================


sub_3E5         proc far
                cld
                call    sub_3EA
                retf
sub_3E5         endp


; =============== S U B R O U T I N E =======================================


sub_3EA         proc near

                test    byte ptr cs:(music_status_flag - segment_shift), 0FFh
                jz      short loc_3F3
                retn
; ---------------------------------------------------------------------------

loc_3F3:
                test    byte ptr cs:(byte_FF0B - segment_shift), 0FFh
                jz      short loc_3FC
                retn
; ---------------------------------------------------------------------------

loc_3FC:
                dec     cs:byte_CC6
                jz      short loc_404
                retn
; ---------------------------------------------------------------------------

loc_404:
                mov     cs:byte_CC6, 2
                push    cs
                pop     es
                mov     ds, es:word_CBF
                test    byte ptr es:(byte_FF24 - segment_shift), 0FFh
                jz      short loc_425
                call    sub_463
                test    byte ptr es:(music_status_flag - segment_shift), 0FFh
                jz      short loc_425
                retn
; ---------------------------------------------------------------------------

loc_425:
                not     es:byte_CBB
                mov     al, es:byte_CB7
                add     es:byte_CB8, al
                sbb     al, al
                mov     es:byte_CBA, al
                mov     di, offset opl_buf0
                call    sub_49D
                mov     di, offset opl_buf1
                call    sub_49D
                mov     di, offset opl_buf2
                call    sub_49D
                mov     di, offset opl_buf3
                call    sub_49D
                mov     di, offset opl_buf4
                call    sub_49D
                mov     di, offset opl_buf5
                call    sub_49D
                mov     di, offset opl_buf6
                jmp     loc_8A9
sub_3EA         endp ; sp-analysis failed


; =============== S U B R O U T I N E =======================================


sub_463         proc near
                mov     es:byte_CBC, 0
                dec     es:byte_CB9
                jz      short loc_471
                retn
; ---------------------------------------------------------------------------

loc_471:
                mov     al, es:(byte_FF24 - segment_shift)
                mov     es:byte_CB9, al
                mov     es:byte_CBC, 0FFh
                mov     al, es:(byte_FF25 - segment_shift)
                add     al, 4
                jnb     short loc_498
                mov     byte ptr es:(byte_FF24 - segment_shift), 0
                mov     byte ptr es:(music_status_flag - segment_shift), 0FFh
                call    sub_3D2
                mov     al, 0FFh

loc_498:
                mov     es:(byte_FF25 - segment_shift), al
                retn
sub_463         endp


; =============== S U B R O U T I N E =======================================


sub_49D         proc near

                test    byte ptr es:[di+0Dh], 1
                jz      short loc_4A5
                retn
; ---------------------------------------------------------------------------

loc_4A5:
                mov     ax, offset sub_7A6
                push    ax
                test    es:byte_CBA, 0FFh
                jz      short loc_4B2
                retn
; ---------------------------------------------------------------------------

loc_4B2:
                dec     byte ptr es:[di+0Eh]
                jz      short loc_4CE
                mov     al, es:[di+12h]
                cmp     al, es:[di+0Eh]
                jnb     short loc_4C3
                retn
; ---------------------------------------------------------------------------

loc_4C3:
                test    byte ptr es:[di+11h], 10h
                jz      short loc_4CB
                retn
; ---------------------------------------------------------------------------

loc_4CB:
                jmp     loc_778
; ---------------------------------------------------------------------------

loc_4CE:
                mov     si, es:[di]
loc_4D1:
                lodsb
                or      al, al
                js      short loc_4D9
                jmp     loc_6E8
; ---------------------------------------------------------------------------

loc_4D9:
                mov     bx, offset loc_4D1
                push    bx
                test    al, 40h
                jnz     short loc_4E4
                jmp     loc_598
; ---------------------------------------------------------------------------

loc_4E4:
                cmp     al, 0D0h
                jnb     short loc_4EB
                jmp     loc_699
; ---------------------------------------------------------------------------

loc_4EB:
                cmp     al, 0D8h
                jnb     short loc_4F2
                jmp     loc_6CC
; ---------------------------------------------------------------------------

loc_4F2:
                cmp     al, 0E0h
                jnb     short loc_4F9
                jmp     loc_6D3
; ---------------------------------------------------------------------------

loc_4F9:
                and     al, 1Fh
                add     al, al
                mov     bl, al
                xor     bh, bh
                jmp     es:off_506[bx]
sub_49D         endp

; ---------------------------------------------------------------------------
off_506         dw offset loc_546
                dw offset loc_54C
                dw offset sub_552
                dw offset loc_574
                dw offset loc_579
                dw offset loc_57E
                dw offset locret_597
                dw offset loc_591
                dw offset locret_597
                dw offset locret_597
                dw offset locret_597
                dw offset locret_597
                dw offset locret_597
                dw offset locret_597
                dw offset locret_597
                dw offset locret_597
off_526         dw offset loc_9C6
                dw offset loc_9D9
                dw offset loc_9E3
                dw offset loc_9ED
                dw offset loc_9F7
                dw offset loc_A0D
                dw offset loc_A1E
                dw offset loc_A3B
                dw offset loc_A58
                dw offset loc_A78
                dw offset loc_A82
                dw offset loc_A8C
                dw offset loc_A95
                dw offset loc_AAA
                dw offset loc_AD6
                dw offset loc_AE3
; ---------------------------------------------------------------------------

loc_546:
                lodsb
                mov     es:byte_CB7, al
                retn
; ---------------------------------------------------------------------------

loc_54C:
                lodsb
                mov     es:[di+18h], al
                retn

; =============== S U B R O U T I N E =======================================


sub_552         proc near
                and     byte ptr es:[di+0Dh], 0BFh
                lodsb
                or      al, al
                jnz     short loc_55D
                retn
; ---------------------------------------------------------------------------

loc_55D:
                or      byte ptr es:[di+0Dh], 40h
                push    di
                add     di, 23h ; '#'
                mov     es:[di-1], al
                movsw
                movsw
                movsb
                pop     di
                and     byte ptr es:[di+11h], 0FDh
                retn
sub_552         endp

; ---------------------------------------------------------------------------

loc_574:
                dec     byte ptr es:[di+10h]
                retn
; ---------------------------------------------------------------------------

loc_579:
                inc     byte ptr es:[di+10h]
                retn
; ---------------------------------------------------------------------------

loc_57E:
                lodsb
                mov     es:[di+0Fh], al

; =============== S U B R O U T I N E =======================================


sub_583         proc near
                mov     al, es:[di+0Ch]
                add     al, al
                jnb     short loc_58E
                jmp     sub_988
; ---------------------------------------------------------------------------

loc_58E:
                jmp     loc_630
sub_583         endp

; ---------------------------------------------------------------------------

loc_591:
                or      byte ptr es:[di+11h], 20h
                retn
; ---------------------------------------------------------------------------

locret_597:
                retn
; ---------------------------------------------------------------------------

loc_598:
                and     al, 3Fh
                push    si
                mov     cl, 0Fh
                mul     cl
                add     ax, es:word_CC1
                mov     si, ax
                mov     es:[di+29h], si
                call    sub_5AF
                pop     si
                retn

; =============== S U B R O U T I N E =======================================


sub_5AF         proc near
                push    si
                call    sub_552
                pop     si
                add     si, 6
                mov     bl, es:[di+0Ch]
                xor     bh, bh
                mov     ah, es:byte_B75[bx]
                mov     al, 0FFh
                add     ah, 80h
                call    sub_B00
                add     ah, 3
                call    sub_B00
                sub     ah, 43h ; 'C'
                mov     al, 0FFh
                call    sub_B00
                add     ah, 3
                call    sub_B00
                sub     ah, 23h ; '#'
                lodsb
                call    sub_B00
                add     ah, 3
                lodsb
                call    sub_B00
                add     ah, 1Dh
                lodsb
                lodsb
                add     ah, 20h ; ' '
                mov     cx, 2

loc_5F7:
                lodsb
                call    sub_B00
                add     ah, 3
                lodsb
                call    sub_B00
                add     ah, 1Dh
                loop    loc_5F7
                add     ah, 40h ; '@'
                lodsb
                mov     bl, al
                rol     al, 1
                rol     al, 1
                call    sub_B00
                add     ah, 3
                rol     al, 1
                rol     al, 1
                call    sub_B00
                mov     ah, es:[di+0Ch]
                mov     al, bl
                and     al, 0Fh
                mov     es:[di+13h], al
                add     ah, 0C0h
                call    sub_B00

loc_630:
                push    si
                mov     si, es:[di+29h]
                mov     bl, es:[di+0Ch]
                xor     bh, bh
                mov     ah, es:byte_B75[bx]
                add     ah, 40h ; '@'
                mov     bl, es:[di+0Fh]
                shr     bl, 1
                mov     al, [si+8]
                test    byte ptr es:[di+13h], 1
                jz      short loc_66F
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                mov     dl, es:25h
                shr     dl, 1
                shr     dl, 1
                add     al, dl
                cmp     al, 40h ; '@'
                jb      short loc_66A
                mov     al, 3Fh ; '?'

loc_66A:
                and     bh, 0C0h
                or      al, bh

loc_66F:
                call    sub_B00
                add     ah, 3
                mov     al, [si+9]
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                mov     dl, es:(byte_FF25 - segment_shift)
                shr     dl, 1
                shr     dl, 1
                add     al, dl
                cmp     al, 40h ; '@'
                jb      short loc_68F
                mov     al, 3Fh ; '?'

loc_68F:
                and     bh, 0C0h
                or      al, bh
                call    sub_B00
                pop     si
                retn
sub_5AF         endp

; ---------------------------------------------------------------------------

loc_699:
                mov     bl, es:[di+0Fh]
                and     al, 0Fh
                shl     al, 1
                shl     al, 1
                shl     al, 1
                shl     al, 1
                sar     al, 1
                sar     al, 1
                or      al, al
                js      short loc_6BC
                add     al, 4
                sub     bl, al
                test    bl, 0C0h
                jz      short loc_6C5
                xor     bl, bl
                jmp     short loc_6C5
; ---------------------------------------------------------------------------

loc_6BC:
                sub     bl, al
                test    bl, 0C0h
                jz      short loc_6C5
                mov     bl, 3Fh ; '?'

loc_6C5:
                mov     es:[di+0Fh], bl
                jmp     loc_630
; ---------------------------------------------------------------------------

loc_6CC:
                and     al, 7
                mov     es:[di+10h], al
                retn
; ---------------------------------------------------------------------------

loc_6D3:
                xor     bx, bx
                and     al, 7
                mov     bl, al
                mov     ax, es:[di+0Ah]
                push    di
                mov     di, ax
                mov     al, [bx+di]
                pop     di
                mov     es:[di+12h], al
                retn
; ---------------------------------------------------------------------------

loc_6E8:
                mov     es:[di], si
                and     byte ptr es:[di+11h], 0EFh
                cmp     byte ptr [si], 0E7h
                jnz     short loc_6FA
                or      byte ptr es:[di+11h], 10h

loc_6FA:
                mov     dl, al
                mov     bx, es:[di+0Ah]
                shr     dl, 1
                shr     dl, 1
                shr     dl, 1
                shr     dl, 1
                xor     dh, dh
                add     bx, dx
                mov     dl, [bx]
                mov     es:[di+0Eh], dl
                mov     dl, al
                and     al, 0Fh
                jz      short loc_778
                cmp     al, 0Fh
                jnz     short loc_71D
                retn
; ---------------------------------------------------------------------------

loc_71D:
                call    sub_74E
                mov     al, es:[di+11h]
                and     byte ptr es:[di+11h], 0DFh
                test    al, 20h
                jnz     short loc_74C
                push    dx
                mov     al, es:[di+22h]
                mov     es:[di+1Ch], al
                mov     word ptr es:[di+19h], 0
                mov     byte ptr es:[di+1Bh], 80h
                and     byte ptr es:[di+11h], 0FDh
                pop     dx
                or      byte ptr es:[di+11h], 40h

loc_74C:
                jmp     short loc_77D

; =============== S U B R O U T I N E =======================================


sub_74E         proc near
                dec     al
                xor     ah, ah
                mov     bx, ax
                mov     al, es:byte_B69[bx]
                mov     es:[di+21h], al
                add     bx, bx
                mov     al, es:[di+18h]
                cbw
                add     ax, es:word_B51[bx]
                mov     ch, es:[di+10h]
                shl     ch, 1
                shl     ch, 1
                or      ah, ch
                mov     es:[di+16h], ax
                retn
sub_74E         endp

; ---------------------------------------------------------------------------

loc_778:
                and     byte ptr es:[di+11h], 0BFh

loc_77D:
                mov     cx, es:[di+16h]
                add     cx, es:[di+19h]
                and     ch, 1Fh
                mov     al, es:[di+11h]
                and     al, 40h
                shr     al, 1
                or      ch, al
                mov     ah, es:[di+0Ch]
                add     ah, 0A0h
                mov     al, cl
                call    sub_B00
                add     ah, 10h
                mov     al, ch
                jmp     sub_B00

; =============== S U B R O U T I N E =======================================


sub_7A6         proc near
                test    es:byte_CBC, 0FFh
                jz      short loc_7B1
                call    loc_630

loc_7B1:
                test    es:byte_CBB, 0FFh
                jnz     short loc_7BA
                retn
; ---------------------------------------------------------------------------

loc_7BA:
                test    byte ptr es:[di+0Dh], 40h
                jnz     short loc_7C2
                retn
; ---------------------------------------------------------------------------

loc_7C2:
                dec     byte ptr es:[di+1Ch]
                jz      short loc_7C9
                retn
; ---------------------------------------------------------------------------

loc_7C9:
                test    byte ptr es:[di+11h], 2
                jnz     short loc_83D
                test    byte ptr es:[di+0Ch], 20h
                jnz     short loc_7F1
                mov     al, es:[di+23h]
                mul     byte ptr es:[di+21h]
                mov     es:[di+1Dh], ax
                mov     al, es:[di+24h]
                mul     byte ptr es:[di+21h]
                mov     es:[di+1Fh], ax
                jmp     short loc_813
; ---------------------------------------------------------------------------

loc_7F1:
                mov     al, es:[di+23h]
                mul     byte ptr es:[di+21h]
                mov     dx, ax
                mov     al, es:[di+24h]
                mul     byte ptr es:[di+21h]
                mov     cl, es:[di+10h]
                shr     ax, cl
                shr     dx, cl
                mov     es:[di+1Fh], ax
                mov     es:[di+1Dh], dx

loc_813:
                mov     al, es:[di+25h]
                mov     ah, es:[di+27h]
                and     ah, 80h
                jz      short loc_824
                mov     al, es:[di+26h]

loc_824:
                shr     al, 1
                mov     es:[di+28h], al
                mov     byte ptr es:[di+1Bh], 80h
                and     byte ptr es:[di+0Dh], 7Fh
                or      es:[di+0Dh], ah
                or      byte ptr es:[di+11h], 2

loc_83D:
                mov     al, es:[di+27h]
                and     al, 1Fh
                mov     es:[di+1Ch], al
                dec     byte ptr es:[di+28h]
                jnz     short loc_870
                test    byte ptr es:[di+0Dh], 80h
                jz      short loc_863
                mov     al, es:[di+25h]
                mov     es:[di+28h], al
                and     byte ptr es:[di+0Dh], 7Fh
                jmp     short loc_870
; ---------------------------------------------------------------------------

loc_863:
                mov     al, es:[di+26h]
                mov     es:[di+28h], al
                or      byte ptr es:[di+0Dh], 80h

loc_870:
                test    byte ptr es:[di+0Dh], 80h
                jnz     short loc_890
                mov     cx, es:[di+1Dh]
                add     es:[di+1Bh], cl
                adc     ch, 0
                jnz     short loc_885
                retn
; ---------------------------------------------------------------------------

loc_885:
                mov     cl, ch
                xor     ch, ch
                add     es:[di+19h], cx
                jmp     loc_77D
; ---------------------------------------------------------------------------

loc_890:
                mov     cx, es:[di+1Fh]
                sub     es:[di+1Bh], cl
                adc     ch, 0
                jnz     short loc_89E
                retn
; ---------------------------------------------------------------------------

loc_89E:
                mov     cl, ch
                xor     ch, ch
                sub     es:[di+19h], cx
                jmp     loc_77D
sub_7A6         endp

; ---------------------------------------------------------------------------

loc_8A9:
                test    byte ptr es:[di+0Dh], 1
                jz      short loc_8B1
                retn
; ---------------------------------------------------------------------------

loc_8B1:
                test    byte ptr es:(byte_FF24 - segment_shift), 0FFh
                jz      short loc_8BC
                call    sub_583

loc_8BC:
                test    es:byte_CBA, 0FFh
                jz      short loc_8C5
                retn
; ---------------------------------------------------------------------------

loc_8C5:
                dec     byte ptr es:[di+0Eh]
                jz      short loc_8CC
                retn
; ---------------------------------------------------------------------------

loc_8CC:
                mov     si, es:[di]
loc_8CF:
                lodsb
                or      al, al
                jns     short loc_8F8
                mov     cx, offset loc_8CF
                push    cx
                cmp     al, 0A0h
                jb      short loc_932
                cmp     al, 0C8h
                jb      short loc_945
                cmp     al, 0CDh
                jb      short loc_956
                cmp     al, 0D2h
                jnb     short loc_8EB
                jmp     loc_979
; ---------------------------------------------------------------------------

loc_8EB:
                and     al, 0Fh
                add     al, al
                mov     bl, al
                xor     bh, bh
                jmp     es:off_526[bx]
; ---------------------------------------------------------------------------

loc_8F8:
                mov     dl, al
                and     al, 1Fh
                jz      short loc_91E
                not     al
                and     al, 1Fh
                and     al, es:[di+15h]
                or      al, 20h
                mov     ah, 0BDh
                call    sub_B08
                mov     al, dl
                and     al, 1Fh
                or      al, 20h
                or      es:[di+15h], al
                mov     al, es:[di+15h]
                call    sub_B08

loc_91E:
                test    dl, 20h
                jz      short loc_926
                lodsb
                jmp     short loc_92A
; ---------------------------------------------------------------------------

loc_926:
                mov     al, es:[di+14h]

loc_92A:
                mov     es:[di+0Eh], al
                mov     es:[di], si
                retn
; ---------------------------------------------------------------------------

loc_932:
                not     al
                and     al, 1Fh
                and     al, es:[di+15h]
                or      al, 20h
                mov     es:[di+15h], al
                mov     ah, 0BDh
                jmp     sub_B08
; ---------------------------------------------------------------------------

loc_945:
                and     al, 7
                mov     bx, es:[di+0Ah]
                xor     ah, ah
                add     bx, ax
                mov     al, [bx]
                mov     es:[di+14h], al
                retn
; ---------------------------------------------------------------------------

loc_956:
                sub     al, 0C8h
                mov     bl, al
                xor     bh, bh
                lodsb
                mov     ah, es:[bx+di+0Fh]
                and     ah, 3Fh
                add     ah, al
                or      ah, ah
                jns     short loc_96C
                xor     ah, ah

loc_96C:
                cmp     ah, 40h ; '@'
                jb      short loc_973
                mov     ah, 3Fh ; '?'

loc_973:
                mov     es:[bx+di+0Fh], ah
                jmp     short sub_988
; ---------------------------------------------------------------------------

loc_979:
                sub     al, 0CDh
                mov     bl, al
                xor     bh, bh
                lodsb
                add     al, al
                add     al, al
                mov     es:[bx+di+0Fh], al

; =============== S U B R O U T I N E =======================================


sub_988         proc near
                mov     dl, es:(byte_FF25 - segment_shift)
                shr     dl, 1
                shr     dl, 1
                mov     al, es:[di+0Fh]
                mov     ah, 53h ; 'S'
                call    sub_9BB
                mov     al, es:[di+10h]
                mov     ah, 51h ; 'Q'
                call    sub_9BB
                mov     al, es:[di+11h]
                mov     ah, 54h ; 'T'
                call    sub_9BB
                mov     al, es:[di+12h]
                mov     ah, 52h ; 'R'
                call    sub_9BB
                mov     al, es:[di+13h]
                mov     ah, 55h ; 'U'
sub_988         endp


; =============== S U B R O U T I N E =======================================


sub_9BB         proc near
                add     al, dl
                cmp     al, 40h ; '@'
                jb      short loc_9C3
                mov     al, 3Fh ; '?'

loc_9C3:
                jmp     sub_B08
sub_9BB         endp

; ---------------------------------------------------------------------------

loc_9C6:
                lodsb
                shl     al, 1
                shl     al, 1
                shl     al, 1
                xor     ah, ah
                add     ax, es:word_CC3
                mov     es:[di+0Ah], ax
                retn
; ---------------------------------------------------------------------------

loc_9D9:
                lodsb
                xor     ah, ah
                mov     bx, ax
                inc     byte ptr es:[bx+21h]
                retn
; ---------------------------------------------------------------------------

loc_9E3:
                lodsb
                xor     ah, ah
                mov     bx, ax
                dec     byte ptr es:[bx+21h]
                retn
; ---------------------------------------------------------------------------

loc_9ED:
                lodsw
                mov     bx, ax
                xor     bh, bh
                mov     es:[bx+21h], ah
                retn
; ---------------------------------------------------------------------------

loc_9F7:
                lodsw
                mov     bx, ax
                mov     dl, ah
                xor     bh, bh
                lodsw
                cmp     es:[bx+21h], dl
                jnz     short locret_A0C
                add     ax, es:music_seq_ptr
                mov     si, ax

locret_A0C:
                retn
; ---------------------------------------------------------------------------

loc_A0D:
                lodsb
                xor     bh, bh
                mov     bl, al
                and     bl, 3
                shr     al, 1
                shr     al, 1
                mov     es:[bx+di+6], al
                retn
; ---------------------------------------------------------------------------

loc_A1E:
                lodsw
                mov     bl, ah
                rol     bl, 1
                rol     bl, 1
                and     bl, 3
                xor     bh, bh
                dec     byte ptr es:[bx+di+6]
                jz      short locret_A3A
                and     ax, 3FFFh
                add     ax, es:music_seq_ptr
                mov     si, ax

locret_A3A:
                retn
; ---------------------------------------------------------------------------

loc_A3B:
                lodsw
                mov     bl, ah
                rol     bl, 1
                rol     bl, 1
                and     bl, 3
                xor     bh, bh
                dec     byte ptr es:[bx+di+6]
                jnz     short locret_A57
                and     ax, 3FFFh
                add     ax, es:music_seq_ptr
                mov     si, ax

locret_A57:
                retn
; ---------------------------------------------------------------------------

loc_A58:
                lodsb
                mov     cl, al
                lodsw
                mov     bl, ah
                rol     bl, 1
                rol     bl, 1
                and     bl, 3
                xor     bh, bh
                cmp     es:[bx+di+6], cl
                jnz     short locret_A77
                and     ax, 3FFFh
                add     ax, es:music_seq_ptr
                mov     si, ax

locret_A77:
                retn
; ---------------------------------------------------------------------------

loc_A78:
                lodsb
                mov     bl, al
                xor     bh, bh
                inc     byte ptr es:[bx+di+6]
                retn
; ---------------------------------------------------------------------------

loc_A82:
                lodsb
                mov     bl, al
                xor     bh, bh
                dec     byte ptr es:[bx+di+6]
                retn
; ---------------------------------------------------------------------------

loc_A8C:
                lodsw
                add     ax, es:music_seq_ptr
                mov     si, ax
                retn
; ---------------------------------------------------------------------------

loc_A95:
                lodsw
                mov     es:[di+2], si
                mov     cx, es:[di+0Ah]
                mov     es:[di+4], cx
                add     ax, es:music_seq_ptr
                mov     si, ax
                retn
; ---------------------------------------------------------------------------

loc_AAA:
                lodsb
                mov     cl, al
                lodsw
                mov     bl, ah
                rol     bl, 1
                rol     bl, 1
                and     bl, 3
                xor     bh, bh
                cmp     es:[bx+di+6], cl
                jnz     short locret_AD5
                mov     es:[di+2], si
                mov     cx, es:[di+0Ah]
                mov     es:[di+4], cx
                and     ax, 3FFFh
                add     ax, es:music_seq_ptr
                mov     si, ax

locret_AD5:
                retn
; ---------------------------------------------------------------------------

loc_AD6:
                mov     si, es:[di+2]
                mov     cx, es:[di+4]
                mov     es:[di+0Ah], cx
                retn
; ---------------------------------------------------------------------------

loc_AE3:
                pop     cx
                or      byte ptr es:[di+0Dh], 1
                inc     es:byte_CC5
                cmp     es:byte_CC5, 7
                jz      short loc_AF7
                retn
; ---------------------------------------------------------------------------

loc_AF7:
                mov     byte ptr es:(music_status_flag - segment_shift), 3Fh
                jmp     sub_3D2
; END OF FUNCTION CHUNK FOR sub_49D

; =============== S U B R O U T I N E =======================================


sub_B00         proc near
                test    byte ptr cs:[di+2Bh], 0FFh
                jz      short sub_B08
                retn
sub_B00         endp


; =============== S U B R O U T I N E =======================================


sub_B08         proc near
                test    byte ptr cs:(music_channel_param - segment_shift), 0FFh
                jz      short loc_B11
                retn
; ---------------------------------------------------------------------------

loc_B11:
                push    dx
                push    ax
                mov     dx, 388h
                xchg    ah, al
                out     dx, al
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
                mov     dx, 389h
                xchg    ah, al
                out     dx, al
                mov     dx, 388h
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
                in      al, dx
                pop     ax
                pop     dx
                retn
sub_B08         endp

; ---------------------------------------------------------------------------
word_B51        dw 156h
                dw 16Bh
                dw 180h
                dw 197h
                dw 1B0h
                dw 1C9h
                dw 1E4h
                dw 201h
                dw 220h
                dw 240h
                dw 263h
                dw 287h
byte_B69        db 13h, 14h, 15h, 16h, 18h, 19h, 1Bh, 1Ch, 1Eh, 20h, 22h
                db 24h
byte_B75        db 0, 1, 2, 8, 9, 0Ah, 10h, 11h, 12h
byte_B7E        db 0, 0, 0Bh, 40h, 0A8h, 0D6h, 0BCh, 0BFh, 0, 1, 0Ch, 0
                db 0, 0D8h, 0C7h, 68h, 46h, 0Fh, 2, 88h, 0, 0, 0C8h, 0F5h
                db 67h, 65h, 0
opl_buf0        db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0
opl_buf1        db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0
opl_buf2        db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0
opl_buf3        db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0
opl_buf4        db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0
opl_buf5        db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 0, 0, 0
opl_buf6        db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0
byte_CB7        db 0
byte_CB8        db 0
byte_CB9        db 0
byte_CBA        db 0
byte_CBB        db 0
byte_CBC        db 0
music_seq_ptr   dw 0
word_CBF        dw 0
word_CC1        dw 0
word_CC3        dw 0
byte_CC5        db 0
byte_CC6        db 0
music_seg       ends

                end    start
