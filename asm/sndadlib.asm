;==============================================================================
; ZELIARD ADLIB SOUND DRIVER (YM3812 / OPL2)
;==============================================================================
; This driver provides music playback and sound effects on the AdLib OPL2
; synthesizer.  It is called periodically (usually from a timer interrupt)
; to update up to two channels.  Each channel is a small state machine that
; interprets a simple event‑driven “sequence” language.
;
; Memory segment layout (simplified):
;   music_seg   segment byte public 'CODE' use16
;               org 1100h
; All code and data reside in the same segment.  Some variables are shared
; with the game segment through the `segment_shift` mechanism:
;   segment_shift = 0FF00h
; e.g., ds:(soundFX_request - segment_shift) reads a byte at absolute
; address 0FF00h lower than the label.  This is a hack to overlay the two
; segments.
;
; OPL2 I/O:
;   Status/Index port   388h
;   Data port           389h
;   Register write implementation: see OPL_WriteReg
;
; Instrument definition (13 bytes per instrument at InstrTable):
;   Offset  Description
;   0       OPL operator 1 (modulator) → register 0x20+opNum (AM/VIB/EG/KSR/MULT)
;   1       Operator 1 → register 0x40+opNum (KSL/Total Level)
;   2       Operator 1 → register 0x60+opNum (Attack Rate / Decay Rate)
;   3       Operator 1 → register 0x80+opNum (Sustain Level / Release Rate)
;   4       Operator 1 → register 0xE0+opNum (Wave Select)
;   5       Operator 2 (carrier) → register 0x23+opNum  ; (actually opNum+3)
;   6       Operator 2 → register 0x43+opNum
;   7       Operator 2 → register 0x63+opNum
;   8       Operator 2 → register 0x83+opNum
;   9..12   Additional data loaded by InstrLoadFeedback etc.
;==============================================================================
include common.inc

; Channel state structure (size 35)
Ch_State        struc ;   Offset ; Description
seq_ptr         dw ?  ;   0x00   ; pointer to next event in sequence
dur_tbl_base    dw ?  ;   0x02   ; pointer to duration multiplier table (from sfx definition)
opl_channel     db ?  ;   0x04   ; OPL channel number (4 or 5)
flags           db ?  ;   0x05   ; bit 0: note_on, bit 7: envelope direction, etc.
note_timer      db ?  ;   0x06   ; countdown for the current note/event
volume          db ?  ;   0x07   ; total level (0-3Fh, higher = quieter)
octave_shift    db ?  ;   0x08   ; octave / block multiplier (0..7)
flags2          db ?  ;   0x09   ; bit 2: vibrato active, bit 4: pause, bit 5: ramp, bit 6: env active
note_dur_init   db ?  ;   0x0A   ; initial note duration (from sequence)
algo_feedback   db ?  ;   0x0B   ; low nibble = register C0h value (feedback/algorithm)
unused          db ?  ;   0x0C   ; 
fnum_block      dw ?  ;   0x0D   ; frequency: upper 5 bits = block (octave), lower 10 bits = F-number
transpose       db ?  ;   0x0F   ; semitone transpose
pitch_bend_acc  dw ?  ;   0x10   ; pitch bend accumulator
pitch_bend_frac db ?  ;   0x12   ; fractional part of pitch bend
env_countdown   db ?  ;   0x13   ; envelope step counter (downcounter)
env_step_up     dw ?  ;   0x14   ; envelope increment (when direction = up)
env_step_down   dw ?  ;   0x16   ; envelope decrement (when direction = down)
env_scale       db ?  ;   0x18   ; envelope multiplier/scale
env_hold        db ?  ;   0x19   ; hold counter for vibrato (from sequence)
env_par1        db ?  ;   0x1A   ; envelope parameter #1
env_par2        db ?  ;   0x1B   ; envelope parameter #2
env_par3        db ?  ;   0x1C   ; envelope parameter #3
env_par4        db ?  ;   0x1D   ; envelope parameter #4
env_flags       db ?  ;   0x1E   ; bit 7: alternate between par3/par4, lower 5 bits: period divider
env_alt_count   db ?  ;   0x1F   ; toggle counter for par3/par4
instr_ptr       dw ?  ;   0x20   ; pointer to current instrument definition (9+4 bytes)
channel_mask    db ?  ;   0x22   ; 1 for ChA, 2 for ChB (used to notify int 60h)
Ch_State        ends

                .286
                .model small

; Memory overlap trick: Note that music_seg intersects with game_seg
; music_seg region 0x0000-0x00FF is the same as game_seg region 0xff00-0xffff
segment_shift   equ 0ff00h

music_seg       segment byte public 'CODE' use16
                assume cs:music_seg, ds:music_seg
                org 1100h
start:

sound_drv_poll_farproc  proc far
                jmp     short init
; ---------------------------------------------------------------------------
                dw offset OPL_WriteReg ; AH: Register Index, AL: Data
; ---------------------------------------------------------------------------

init:
                push    cs
                pop     ds
                call    ProcessTick     ; handle pending SFX and run sequencer
                call    HeartbeatTick   ; heart beat, volume fade, sound FX toggle
                retf
sound_drv_poll_farproc  endp


; =============== S U B R O U T I N E =======================================


; ---------------------------------------------------------------------------
; Start a new sound effect.  Called when the game sets soundFX_request to a
; non‑zero value (SFX number + 1).  It copies the SFX definition's three
; data pointers and resets the two channels if necessary.
; ---------------------------------------------------------------------------
SFX_Start      proc near
                mov     al, ds:(soundFX_request - segment_shift)
                mov     byte ptr ds:(soundFX_request - segment_shift), 0
                test    byte ptr ds:(sound_fx_toggle_by_f2 - segment_shift), 0FFh
                jz      short check_sfx
                retn
check_sfx:
                dec     al                  ; al = SFX index (0..63)
                mov     ah, 7
                mul     ah                  ; each SFX entry is 7 bytes
                add     ax, offset SFX_Table
                mov     si, ax
                mov     al, [si]            ; priority byte
                cmp     al, SfxPriority
                jnb     short build_sfx
                retn                        ; lower priority → ignore
build_sfx:
                mov     SfxPriority, al
                inc     si                  ; skip priority byte
                ; load two duration‑table pointers into the two channels
                mov     di, offset ChA_State
                mov     cx, 2
                mov     bh, 1               ; channel mask for ChA
                mov     bl, 4               ; OPL channel 4
load_sfx_loop:
                call    Ch_InitOp
                add     di, size Ch_State   ; skip to next channel state
                inc     bh                  ; mask 2 for ChB
                inc     bl                  ; channel 5
                loop    load_sfx_loop
                ; load the base pointer for the duration multiplier table
                lodsw
                mov     SfxDurTblPtr, ax
                mov     byte ptr ds:(exit_pending_flag - segment_shift), 0
                mov     TempoAccum, 7Fh
                mov     ActiveChCnt, 0
                mov     ChannelMask, 0
                jmp     int60_fn6           ; notify that a new SFX/music started
SFX_Start      endp


; ---------------------------------------------------------------------------
; Initialise one operator with hard‑coded default values, then set the
; channel’s instrument pointer to the first SFX instrument (later the
; sequence may change it).  Called for both ChA and ChB.
; Input:  SI → first two words of SFX definition (pointer to seq data)
;         DI → Ch_State structure
;         BL = OPL channel number (4/5)
;         BH = channel mask (1/2)
; ---------------------------------------------------------------------------
Ch_InitOp      proc near
                lodsw
                mov     word ptr ds:[di+Ch_State.seq_ptr], ax
                mov     byte ptr [di+Ch_State.note_timer], 1
                mov     byte ptr [di+Ch_State.octave_shift], 3
                mov     byte ptr [di+Ch_State.note_dur_init], 1
                mov     byte ptr [di+Ch_State.volume], 7Fh
                mov     byte ptr [di+Ch_State.flags2], 0
                mov     byte ptr [di+Ch_State.flags], 0
                mov     [di+Ch_State.opl_channel], bl
                mov     [di+Ch_State.channel_mask], bh
                retn
Ch_InitOp      endp


; ===========================================================================
; Main per‑tick processing.  Checks for new SFX requests, runs the two‑
; channel sequencer, and handles tempo.
; ===========================================================================
ProcessTick    proc near
                test    byte ptr ds:(soundFX_request - segment_shift), 0FFh
                jz      short no_sfx
                call    SFX_Start
no_sfx:
                test    byte ptr ds:(exit_pending_flag - segment_shift), 0FFh
                jz      short run_seq
                retn
run_seq:
                push    cs
                pop     es
                ; simple tempo accumulator (adds an 8‑bit fraction)
                mov     al, TempoAccum
                add     TempoCounter, al
                sbb     al, al
                mov     TempoCarry, al      ; carry flag stored for sequence engine
                cld
                mov     di, offset ChA_State
                call    Ch_Sequencer
                mov     di, offset ChB_State
                jmp     short $+2           ; flush prefetch (8086 quirk)
ProcessTick    endp


; ===========================================================================
; Channel sequencer – interprets the event stream for one channel.
; ===========================================================================
Ch_Sequencer   proc near
                test    byte ptr [di+Ch_State.flags], 1     ; note_on?
                jz      short not_active
                retn
not_active:
                mov     ax, offset Ch_DoEnvelope
                push    ax                      ; return address for note end
                test    TempoCarry, 0FFh
                jz      short do_step
                retn                            ; no tick this frame
do_step:
                dec     byte ptr [di+Ch_State.note_timer]
                jz      short fetch_event       ; timer expired
                ; check if note is in "pause" phase (flags2 bit 4 set)
                mov     al, [di+Ch_State.note_dur_init]
                cmp     al, [di+Ch_State.note_timer]
                jnb     short no_pause
                retn
no_pause:
                test    byte ptr [di+Ch_State.flags2], 10h   ; pause flag?
                jz      short skip_pause
                retn
skip_pause:
                jmp     Ch_NoteUpdate           ; still playing, update freq/vol
; --- fetch next event from sequence ---
fetch_event:
                mov     si, [di+Ch_State.seq_ptr]
ch_event_loop:
                lodsb
                or      al, al
                js      short cmd_event         ; high bit set → command
                jmp     ch_note_event           ; else → note event

cmd_event:
                mov     bx, offset ch_event_loop
                push    bx                      ; most commands return to loop
                test    al, 40h
                jnz     short cmd_group1
                jmp     cmd_group2

; ---------- Command group 1 (0xC0‑0xDF) ----------
cmd_group1:
                cmp     al, 0D0h
                jnb     short cmd_ge_D0
                jmp     cmd_volume_relative     ; 0xC0..0xCF
cmd_ge_D0:
                cmp     al, 0D8h
                jnb     short cmd_ge_D8
                jmp     cmd_set_octave          ; 0xD0..0xD7
cmd_ge_D8:
                cmp     al, 0E0h
                jnb     short cmd_ge_E0
                jmp     cmd_duration           ; 0xD8..0xDF
cmd_ge_E0:
                and     al, 1Fh
                add     al, al
                mov     bl, al
                xor     bh, bh
                jmp     word ptr CmdTable_E0[bx]  ; dispatch 0xE0..0xFF

CmdTable_E0:
                dw ChCmd_SetTempo        ; 0xE0
                dw ChCmd_SetTranspose    ; 0xE1
                dw ChCmd_EnvSetup        ; 0xE2
                dw ChCmd_DecOctave       ; 0xE3
                dw ChCmd_IncOctave       ; 0xE4
                dw ChCmd_SetVolume       ; 0xE5
                dw ChCmd_Ret             ; 0xE7
                dw ChCmd_SetVibrato      ; 0xE6
                dw ChCmd_Ret             ; 0xE8
                dw ChCmd_Ret             ; 0xE9
                dw ChCmd_Ret             ; 0xEA
                dw ChCmd_Ret             ; 0xEB
                dw ChCmd_Ret             ; 0xEC
                dw ChCmd_Ret             ; 0xED
                dw ChCmd_Ret             ; 0xEE
                dw ChCmd_Ret             ; 0xEF
                dw ChCmd_SetDurTbl       ; 0xF0
                dw locret_150B           ; 0xF1
                dw locret_150B           ; 0xF2
                dw locret_150B           ; 0xF3
                dw locret_150B           ; 0xF4
                dw locret_150B           ; 0xF5
                dw locret_150B           ; 0xF6
                dw locret_150B           ; 0xF7
                dw locret_150B           ; 0xF8
                dw locret_150B           ; 0xF9
                dw locret_150B           ; 0xFA
                dw locret_150B           ; 0xFB
                dw locret_150B           ; 0xFC
                dw locret_150B           ; 0xFD
                dw locret_150B           ; 0xFE
                dw ChCmd_EndOfTrack      ; 0xFF

; ---------- Group 1 sub‑commands ----------
ChCmd_SetTempo:
                lodsb
                mov     TempoAccum, al
                retn
ChCmd_SetTranspose:
                lodsb
                mov     [di+Ch_State.transpose], al
                retn
ChCmd_EnvSetup:
                and     byte ptr [di+Ch_State.flags], 0BFh   ; clear envelope flag
                lodsb
                or      al, al
                jnz     short set_envelope
                retn
set_envelope:
                or      byte ptr [di+Ch_State.flags], 40h   ; enable envelope
                push    di
                add     di, Ch_State.env_par1       ; di+1 → env_hold
                mov     [di-1], al                  ; store first byte in env_hold
                movsw                                   ; copy env_par1, env_par2
                movsw                                   ; copy env_par3, env_par4
                movsb                                   ; copy env_flags
                pop     di
                and     byte ptr [di+Ch_State.flags2], 0FDh  ; clear "envelope active"
                retn
ChCmd_DecOctave:
                dec     byte ptr [di+Ch_State.octave_shift]
                retn
ChCmd_IncOctave:
                inc     byte ptr [di+Ch_State.octave_shift]
                retn
ChCmd_SetVolume:
                lodsb
                mov     [di+Ch_State.volume], al
                jmp     Ch_UpdateTotalLevel
ChCmd_SetVibrato:
                or      byte ptr [di+Ch_State.flags2], 20h   ; set vibrato flag
                retn
ChCmd_Ret:
                retn

; ---------- Command group 2 (0x80‑0xBF) : instrument change ----------
cmd_group2:
                and     al, 3Fh                 ; 6‑bit instrument number
                push    si
                mov     cl, 9
                mul     cl
                add     ax, offset InstrTable
                mov     si, ax                  ; si → instrument data
                mov     [di+Ch_State.instr_ptr], si
                mov     bl, [di+Ch_State.opl_channel]
                xor     bh, bh
                mov     ah, ChOpBaseTbl[bx]     ; operator base number
                ; --- load operator 1 (modulator) ---
                mov     al, 0FFh
                add     ah, 40h                 ; KSL/TL reg for operator 1
                call    OPL_WriteReg            ; set total level to 0FFh (silence) temporarily
                add     ah, 3                   ; now KSL/TL for operator 2
                call    OPL_WriteReg
                sub     ah, 23h                 ; back to 0x20+op (AM/VIB/...)
                lodsb
                call    OPL_WriteReg            ; write am/vib/eg/ksr/mult
                add     ah, 3                   ; 0x23+op → operator 2 same reg
                lodsb
                call    OPL_WriteReg
                add     ah, 1Dh                 ; 0x40+op → KSL/TL operator 1
                lodsb
                lodsb                           ; skip, we'll reload later
                add     ah, 20h                 ; 0x60+op → AR/DR operator 1
                mov     cx, 2
inst_loop:
                lodsb
                call    OPL_WriteReg            ; AR/DR op1
                add     ah, 3
                lodsb
                call    OPL_WriteReg            ; AR/DR op2
                add     ah, 1Dh
                loop    inst_loop               ; next: SL/RR
                add     ah, 40h                 ; 0xC0+op? No, see below.
                ; --- load feedback / algorithm and remaining data ---
                lodsb                           ; instrument byte 9
                mov     bl, al
                rol     al, 1
                rol     al, 1                   ; bits 6-5 → bits 1-0
                call    OPL_WriteReg            ; write ?? (likely unused)
                add     ah, 3
                rol     al, 1
                rol     al, 1
                call    OPL_WriteReg            ; write ??
                mov     ah, [di+Ch_State.opl_channel]
                mov     al, bl
                and     al, 0Fh
                mov     [di+Ch_State.algo_feedback], al
                add     ah, 0C0h                ; register 0xC0+channel (feedback/algorithm)
                call    OPL_WriteReg
                call    Ch_UpdateTotalLevel
                pop     si
                mov     al, [di+Ch_State.channel_mask]
                or      ChannelMask, al
                call    int60_fn6               ; notify new instrument
                jmp     Ch_NoteUpdate
Ch_Sequencer   endp    ; (sp-analysis may fail – original code works fine)


; ---------------------------------------------------------------------------
; Update total level (volume) registers for both operators.
; Called after a volume change or instrument load.
; ---------------------------------------------------------------------------
Ch_UpdateTotalLevel proc near
                push    si
                mov     si, [di+Ch_State.instr_ptr]   ; instrument data
                mov     bl, [di+Ch_State.opl_channel]
                xor     bh, bh
                mov     ah, ChOpBaseTbl[bx]
                add     ah, 40h                 ; KSL/TL operator 1
                mov     bl, [di+Ch_State.volume]      ; requested total level
                shr     bl, 1                   ; scale to 0..1Fh
                ; operator 1
                mov     al, [si+2]              ; instrument's KSL/TL
                test    byte ptr [di+Ch_State.algo_feedback], 1  ; check feedback bit
                jz      short no_ksl_correction
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                cmp     al, 40h
                jb      short ok1
                mov     al, 3Fh
ok1:
                and     bh, 0C0h
                or      al, bh
no_ksl_correction:
                call    OPL_WriteReg
                add     ah, 3                   ; operator 2 KSL/TL
                mov     al, [si+3]              ; instrument byte for op2
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                cmp     al, 40h
                jb      short ok2
                mov     al, 3Fh
ok2:
                and     bh, 0C0h
                or      al, bh
                call    OPL_WriteReg
                pop     si
                retn
Ch_UpdateTotalLevel endp

; ---------------------------------------------------------------------------
; Volume‑relative commands (0xC0..0xCF) – add/sub from current volume.
; ---------------------------------------------------------------------------
cmd_volume_relative:
                mov     bl, [di+Ch_State.volume]
                and     al, 0Fh
                shl     al, 1
                shl     al, 1
                shl     al, 1
                shl     al, 1
                sar     al, 1                   ; sign extend to 8 bits
                sar     al, 1
                or      al, al
                js      short sub_vol
                add     al, 4
                sub     bl, al
                test    bl, 0C0h
                jz      short set_vol
                xor     bl, bl
                jmp     short set_vol
sub_vol:
                sub     bl, al
                test    bl, 0C0h
                jz      short set_vol
                mov     bl, 3Fh
set_vol:
                mov     [di+Ch_State.volume], bl
                jmp     Ch_UpdateTotalLevel

; ---------------------------------------------------------------------------
; Set octave command (0xD0..0xD7).
; ---------------------------------------------------------------------------
cmd_set_octave:
                and     al, 7
                mov     [di+Ch_State.octave_shift], al
                retn

; ---------------------------------------------------------------------------
; Duration command (0xD8..0xDF) – sets the initial note duration from a
; small table.
; ---------------------------------------------------------------------------
cmd_duration:
                xor     bx, bx
                and     al, 7
                mov     bl, al
                mov     ax, [di+Ch_State.dur_tbl_base] ; pointer to byte table
                push    di
                mov     di, ax
                mov     al, [bx+di]
                pop     di
                mov     [di+Ch_State.note_dur_init], al
                retn

; ---------------------------------------------------------------------------
; Note event (0x00..0x7F).
; ---------------------------------------------------------------------------
ch_note_event:
                mov     [di+Ch_State.seq_ptr], si
                and     byte ptr [di+Ch_State.flags2], 0EFh  ; clear pause
                cmp     byte ptr [si], 0E7h    ; peek ahead: if next is "vibrato" cmd?
                jnz     short not_pause
                or      byte ptr [di+Ch_State.flags2], 10h   ; set pause flag
not_pause:
                mov     dl, al                  ; note number
                mov     bx, [di+Ch_State.dur_tbl_base]
                shr     dl, 1
                shr     dl, 1
                shr     dl, 1
                shr     dl, 1                   ; high nibble → index into step table
                xor     dh, dh
                add     bx, dx
                mov     dl, [bx]                ; duration multiplier
                mov     [di+Ch_State.note_timer], dl
                mov     dl, al
                and     al, 0Fh                  ; low nibble = note index (0..11)
                jz      short Ch_NoteUpdate
                cmp     al, 0Fh
                jnz     short calc_freq
                retn                            ; note 0xF = rest?
calc_freq:
                call    Ch_SetFrequency
                mov     al, [di+Ch_State.flags2]
                and     byte ptr [di+Ch_State.flags2], 0DFh  ; clear vibrato active?
                test    al, 20h
                jnz     short freq_done
                ; reset envelope/vibrato state
                push    dx
                mov     al, [di+Ch_State.env_hold]
                mov     [di+Ch_State.env_countdown], al
                mov     word ptr [di+Ch_State.pitch_bend_acc], 0
                mov     byte ptr [di+Ch_State.pitch_bend_frac], 80h
                and     byte ptr [di+Ch_State.flags2], 0FDh
                pop     dx
                or      byte ptr [di+Ch_State.flags2], 40h   ; envelope active
freq_done:
                jmp     short Ch_OutputFreq

; ---------------------------------------------------------------------------
; Compute frequency and octave from note index + transpose + octave shift.
; Writes freq/block to Ch_State.fnum_block.
; ---------------------------------------------------------------------------
Ch_SetFrequency proc near
                dec     al                      ; note 1..12 -> 0..11
                xor     ah, ah
                mov     bx, ax
                mov     al, NoteFreqTbl[bx]     ; F‑number low bits? Actually a scale multiplier
                mov     [di+Ch_State.env_scale], al
                add     bx, bx
                mov     al, [di+Ch_State.transpose]
                cbw
                add     ax, FreqBaseTbl[bx]     ; base F‑number for note
                mov     ch, [di+Ch_State.octave_shift]
                shl     ch, 1
                shl     ch, 1
                or      ah, ch                  ; merge block (octave) into high bits
                mov     [di+Ch_State.fnum_block], ax
                retn
Ch_SetFrequency endp

; ---------------------------------------------------------------------------
; Called at the end of each non‑command event.
; Computes the final pitch (fnum + bend) and sends it to the OPL2.
; ---------------------------------------------------------------------------
Ch_NoteUpdate:
                and     byte ptr [di+Ch_State.flags2], 0BFh  ; clear some flag
                jmp     short $+2
                ; fall through to compute output frequency
Ch_OutputFreq:
                mov     cx, [di+Ch_State.fnum_block]
                add     cx, [di+Ch_State.pitch_bend_acc]    ; add pitch bend
                and     ch, 1Fh                        ; block limited to 5 bits
                mov     al, [di+Ch_State.flags2]
                and     al, 40h                        ; envelope active?
                shr     al, 1
                or      ch, al                         ; bit 5 = envelope/key on?
                mov     ah, [di+Ch_State.opl_channel]
                add     ah, 0A0h                       ; register A0+ch (F‑number low)
                mov     al, cl
                call    OPL_WriteReg
                add     ah, 10h                        ; register B0+ch (block / key on)
                mov     al, ch
                jmp     OPL_WriteReg

; ===========================================================================
; Envelope processor.  Handles pitch envelope (vibrato) and possibly
; volume effects.  Called via the stack return address trick.
; ===========================================================================
Ch_DoEnvelope  proc near
                test    byte ptr [di+Ch_State.flags], 40h   ; envelope enabled?
                jnz     short do_env
                retn
do_env:
                dec     byte ptr [di+Ch_State.env_countdown]
                jz      short env_tick
                retn
env_tick:
                test    byte ptr [di+Ch_State.flags2], 2    ; envelope active?
                jnz     short env_active
                ; initialise envelope parameters
                mov     al, [di+Ch_State.env_par1]
                mul     byte ptr [di+Ch_State.env_scale]
                mov     [di+Ch_State.env_step_up], ax        ; step up value
                mov     al, [di+Ch_State.env_par2]
                mul     byte ptr [di+Ch_State.env_scale]
                mov     [di+Ch_State.env_step_down], ax      ; step down value
                mov     al, [di+Ch_State.env_par3]
                mov     ah, [di+Ch_State.env_flags]
                and     ah, 80h
                jz      short not_alt
                mov     al, [di+Ch_State.env_par4]

not_alt:
                shr     al, 1
                mov     [di+Ch_State.env_alt_count], al
                mov     byte ptr [di+Ch_State.pitch_bend_frac], 80h
                and     byte ptr [di+Ch_State.flags], 7Fh    ; direction = up
                or      [di+Ch_State.flags], ah
                or      byte ptr [di+Ch_State.flags2], 2     ; envelope active
env_active:
                mov     al, [di+Ch_State.env_flags]
                and     al, 1Fh
                mov     [di+Ch_State.env_countdown], al
                dec     byte ptr [di+Ch_State.env_alt_count]
                jnz     short no_toggle
                test    byte ptr [di+Ch_State.flags], 80h    ; direction
                jz      short set_up
                mov     al, [di+Ch_State.env_par3]
                mov     [di+Ch_State.env_alt_count], al
                and     byte ptr [di+Ch_State.flags], 7Fh
                jmp     short no_toggle
set_up:
                mov     al, [di+Ch_State.env_par4]
                mov     [di+Ch_State.env_alt_count], al
                or      byte ptr [di+Ch_State.flags], 80h
no_toggle:
                test    byte ptr [di+Ch_State.flags], 80h
                jnz     short loc_14E4
                ; direction up
                mov     cx, [di+Ch_State.env_step_up]
                add     [di+Ch_State.pitch_bend_frac], cl
                adc     ch, 0
                jnz     short dir_down
                retn
dir_down:
                mov     cl, ch
                xor     ch, ch
                add     [di+Ch_State.pitch_bend_acc], cx
                jmp     Ch_OutputFreq
loc_14E4:
                mov     cx, [di+Ch_State.env_step_down]
                sub     [di+Ch_State.pitch_bend_frac], cl
                adc     ch, 0
                jnz     short apply_bend
                retn
apply_bend:
                mov     cl, ch
                xor     ch, ch
                sub     [di+Ch_State.pitch_bend_acc], cx
                jmp     Ch_OutputFreq
Ch_DoEnvelope  endp

; ---------------------------------------------------------------------------
ChCmd_SetDurTbl:
                lodsb
                shl     al, 1
                shl     al, 1
                shl     al, 1                   ; *8
                xor     ah, ah
                add     ax, SfxDurTblPtr
                mov     word ptr ds:[di+Ch_State.dur_tbl_base], ax
                retn
; ---------------------------------------------------------------------------

locret_150B:
                retn
; ---------------------------------------------------------------------------

ChCmd_EndOfTrack:
                pop     cx                      ; discard return address
                or      byte ptr ds:[di+Ch_State.flags], 1      ; set note_on (track finished)
                inc     ActiveChCnt
                cmp     ActiveChCnt, 2
                jz      short both_done
                retn
both_done:
                mov     byte ptr ds:(exit_pending_flag - segment_shift), 0FFh
                mov     SfxPriority, 0
                mov     ChannelMask, 0
                ; fall through to int60_fn6
; ===========================================================================
; Notify the game via interrupt 60h function 6 that a channel’s state
; changed (instrument loaded, note on, etc.).
;   cl = bitmask of channels that need attention
; ===========================================================================
int60_fn6       proc near
                mov     cl, ChannelMask
                mov     ax, 6
                int     60h             ; adlib fn_6
                retn
int60_fn6       endp

; ===========================================================================
; OPL2 register write with mandatory delays.
; Input:   AH = register index
;          AL = data
; Ports:   388h (index), 389h (data)
; Timing for YM3812: 3.3 µs after index write, 23 µs after data write.
; ===========================================================================
OPL_WriteReg   proc near
                push    dx
                push    ax
                mov     dx, 388h
                xchg    ah, al          ; al = index
                out     dx, al
                in      al, dx          ; OPL2 needs to wait 3.3us after Index write
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
                xchg    ah, al          ; al = data
                out     dx, al
                mov     dx, 388h
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
OPL_WriteReg   endp

; ===========================================================================
; Frequency base numbers for 12 notes (upper byte = block 0, lower = F‑num).
; ===========================================================================
FreqBaseTbl    dw 0156h, 016Bh, 0180h, 0197h, 01B0h, 01C9h
               dw 01E4h, 0201h, 0220h, 0240h, 0263h, 0287h
; ===========================================================================
; Note frequency scaling factors (used in envelope calculations).
; ===========================================================================
NoteFreqTbl    db 13h, 14h, 15h, 16h, 18h, 19h, 1Bh, 1Ch, 1Eh, 20h, 22h, 24h
; ===========================================================================
; Channel operator base numbers.  Used to convert a logical channel (0..8)
; into the OPL operator number that will receive the instrument settings.
; Our music engine uses only channels 4 and 5.
;   Channel 4 → op 9  (carrier of ch4)
;   Channel 5 → op 10 (modulator of ch5)
; ===========================================================================
ChOpBaseTbl     db 0, 1, 2, 8, 9, 0Ah, 10h, 11h, 12h

; ===========================================================================
; Heartbeat / sound‑fx toggle processor.
; Handles the periodic "heartbeat" sound and the F2 toggle for sound effects.
; ===========================================================================
HeartbeatTick  proc near
                test    byte ptr ds:(sound_fx_toggle_by_f2 - segment_shift), 0FFh
                jnz     short check_heartbeat_trigger
                test    byte ptr ds:(byte_FF0B - segment_shift), 0FFh
                jnz     short check_heartbeat_trigger
                test    byte ptr ds:(heartbeat_volume - segment_shift), 0FFh
                jnz     short do_heartbeat
check_heartbeat_trigger:
                test    HeartbeatTrigger, 0FFh
                jnz     short clear_trigger
                retn
clear_trigger:
                mov     HeartbeatTrigger, 0
                test    byte ptr ds:(exit_pending_flag - segment_shift), 0FFh
                jnz     short maybe_fade_out
                retn
maybe_fade_out:
                mov     ax, 6
                xor     cl, cl
                int     60h                     ; fade out all channels
                retn

do_heartbeat:
                dec     HeartbeatTimer
                jz      short heartbeat_tick
                retn
heartbeat_tick:
                mov     HeartbeatTimer, 4       ; every 4th tick
                inc     HeartbeatCounter
                mov     al, HeartbeatCounter
                mov     HeartbeatCounter, 0FFh
                cmp     al, 96h                 ; max beats?
                jb      short continue_beat
                retn
continue_beat:
                mov     HeartbeatCounter, al
                test    byte ptr ds:(exit_pending_flag - segment_shift), 0FFh
                jnz     short beat_active
                retn
beat_active:
                cmp     al, 1Eh
                jb      short use_index
                sub     al, 1Eh
use_index:
                push    ax
                xor     ah, ah
                mov     cl, 1Eh
                div     cl
                jnz     short no_flip
                mov     HeartbeatFlipFlop, 0FFh  ; toggle every 30 beats
no_flip:
                pop     ax
                mov     ch, al
                shr     al, 1
                shr     al, 1
                shr     al, 1                   ; /8
                mov     ah, ds:(heartbeat_volume - segment_shift)
                sub     ah, al
                cmc
                sbb     al, al
                and     ah, al
                add     ah, ah
                add     ah, ah                  ; *4
                mov     al, ah
                or      al, al
                jz      check_heartbeat_trigger
                mov     HeartbeatAttenuation, al
                push    cx
                mov     ax, 6
                mov     cl, 3                   ; master volume control?
                int     60h
                call    Heartbeat_SetupInstr
                pop     cx
                neg     ch
                mov     cl, ch
                mov     ch, 0FFh
                add     cx, cx
                add     cx, 980h                ; some frequency
                test    HeartbeatFlipFlop, 0FFh
                jz      short write_freq
                mov     ah, 0A4h
                mov     al, cl
                call    OPL_WriteReg
                add     ah, 10h
                mov     al, ch
                call    OPL_WriteReg
                mov     ah, 0A5h
                mov     al, cl
                call    OPL_WriteReg
                add     ah, 10h
                mov     al, ch
                call    OPL_WriteReg
                mov     HeartbeatFlipFlop, 0
write_freq:
                or      ch, 20h                 ; key on bit
                mov     ah, 0A4h
                mov     al, cl
                call    OPL_WriteReg
                add     ah, 10h
                mov     al, ch
                call    OPL_WriteReg
                mov     ah, 0A5h
                mov     al, cl
                call    OPL_WriteReg
                add     ah, 10h
                mov     al, ch
                call    OPL_WriteReg
                call    Heartbeat_UpdateVol
                mov     HeartbeatTrigger, 0FFh
                retn
HeartbeatTick  endp


; ===========================================================================
; Load the heartbeat instrument onto operators 4 and 5.
; ===========================================================================
Heartbeat_SetupInstr proc near
                mov     si, offset HeartbeatInstr
                mov     bx, 4
                call    Heartbeat_LoadOp
                mov     si, offset HeartbeatInstr
                mov     bx, 5
Heartbeat_SetupInstr endp


Heartbeat_LoadOp proc near
                mov     ah, ChOpBaseTbl[bx]
                push    bx
                add     ah, 20h                 ; 0x20+op
                lodsb
                call    OPL_WriteReg
                add     ah, 3                   ; 0x23+op (operator 2)
                lodsb
                call    OPL_WriteReg
                add     ah, 3Dh                 ; 0x60+op (AR/DR)
                lodsb
                lodsb
                mov     cx, 2
hb_ld_lp:
                lodsb
                call    OPL_WriteReg
                add     ah, 3
                lodsb
                call    OPL_WriteReg
                add     ah, 1Dh
                loop    hb_ld_lp
                add     ah, 40h                 ; 0xC0+op? No, see below.
                lodsb
                mov     bl, al
                rol     al, 1
                rol     al, 1
                call    OPL_WriteReg
                add     ah, 3
                rol     al, 1
                rol     al, 1
                call    OPL_WriteReg
                mov     al, bl
                and     al, 0Fh
                pop     bx
                mov     ah, bl
                add     ah, 0C0h                ; feedback/algorithm
                call    OPL_WriteReg
                jmp     short $+2
Heartbeat_LoadOp endp


; ===========================================================================
; Apply heartbeat volume attenuation to both operators.
; ===========================================================================
Heartbeat_UpdateVol proc near
                mov     bx, 4
                call    Heartbeat_SetAttenuation
                mov     bx, 5
Heartbeat_UpdateVol endp


Heartbeat_SetAttenuation proc near
                mov     si, offset HeartbeatInstr
                mov     ah, ChOpBaseTbl[bx]
                add     ah, 40h                 ; KSL/TL
                mov     al, [si+2]              ; operator 1 TL
                call    OPL_WriteReg
                add     ah, 3
                mov     bl, HeartbeatAttenuation
                neg     bl
                add     bl, 3Fh
                mov     al, [si+3]
                mov     bh, al
                and     al, 3Fh
                add     al, bl
                cmp     al, 40h
                jb      short hb_ok
                mov     al, 3Fh
hb_ok:
                and     bh, 0C0h
                or      al, bh
                jmp     OPL_WriteReg
Heartbeat_SetAttenuation endp

; ===========================================================================
; Data area
; ===========================================================================
HeartbeatInstr  db 20h, 21h, 4, 0, 0F8h, 0F4h, 8Fh, 8Fh, 40h ; 9 bytes
; ---------------------------------------------------------------------------
; SFX Table – 65 entries, each 7 bytes:
;   byte priority
;   word ptr to seq data for ChA
;   word ptr to seq data for ChB (often same as first if no re‑trigger)
;   word ptr to duration multiplier table (base for dur_tbl_base)
; ---------------------------------------------------------------------------
SFX_Table:
                db 0                    ; sfx1
                dw offset byte_190A
                dw offset byte_201F
                dw offset byte_1914
                db 0FFh                 ; sfx2
                dw offset byte_1915
                dw offset byte_201F
                dw offset byte_1923
                db 0                    ; sfx3
                dw offset byte_1924
                dw offset byte_1931
                dw offset byte_193C
                db 0                    ; sfx4
                dw offset byte_193E
                dw offset byte_194A
                dw offset byte_1955
                db 0                    ; sfx5
                dw offset byte_1957
                dw offset byte_201F
                dw offset byte_1961
                db 1                    ; sfx6
                dw offset byte_1962
                dw offset byte_1978
                dw offset byte_1989
                db 9                    ; sfx7
                dw offset byte_198A
                dw offset byte_199D
                dw offset byte_19AE
                db 9                    ; sfx8
                dw offset byte_19B0
                dw offset byte_19BA
                dw offset byte_19C6
                db 8                    ; sfx9
                dw offset byte_19C9
                dw offset byte_19D8
                dw offset byte_19E5
                db 7                    ; sfx10
                dw offset byte_19E6
                dw offset byte_201F
                dw offset byte_19F0
                db 0FFh                 ; sfx11
                dw offset byte_19F1
                dw offset byte_19FE
                dw offset byte_1A0B
                db 0FFh                 ; sfx12
                dw offset byte_1A0D
                dw offset byte_1A17
                dw offset byte_1A1F
                db 0FFh                 ; sfx13
                dw offset byte_1A20
                dw offset byte_1A2A
                dw offset byte_1A32
                db 0FFh                 ; sfx14
                dw offset byte_1A33
                dw offset byte_1A3F
                dw offset byte_1A49
                db 0FFh                 ; sfx15
                dw offset byte_1A4A
                dw offset byte_1A87
                dw offset byte_1AAC
                db 9                    ; sfx16
                dw offset byte_1AAD
                dw offset byte_201F
                dw offset byte_1ABA
                db 9                    ; sfx17
                dw offset byte_1ABC
                dw offset byte_1ABC
                dw offset byte_1ACA
                db 9                    ; sfx18
                dw offset byte_1ACC
                dw offset byte_1ADC
                dw offset byte_1AEA
                db 0                    ; sfx19
                dw offset byte_1AEC
                dw offset byte_201F
                dw offset byte_1AF6
                db 9                    ; sfx20
                dw offset byte_1AF7
                dw offset byte_1B02
                dw offset byte_1B0E
                db 0                    ; sfx21
                dw offset byte_1B10
                dw offset byte_1B21
                dw offset byte_1B29
                db 0                    ; sfx22
                dw offset byte_1B2A
                dw offset byte_1B3B
                dw offset byte_1B4A
                db 0                    ; sfx23
                dw offset byte_1B4B
                dw offset byte_201F
                dw offset byte_1B55
                db 0                    ; sfx24
                dw offset byte_1B56
                dw offset byte_1B61
                dw offset byte_1B6B
                db 9                    ; sfx25
                dw offset byte_1B6D
                dw offset byte_1B8A
                dw offset byte_1B99
                db 0FFh                 ; sfx26
                dw offset byte_1B9D
                dw offset byte_1BAA
                dw offset byte_1BB5
                db 0FFh                 ; sfx27
                dw offset byte_1BB6
                dw offset byte_1BC3
                dw offset byte_1BD5
                db 0FFh                 ; sfx28
                dw offset byte_1BD8
                dw offset byte_201F
                dw offset byte_1BE6
                db 0FFh                 ; sfx29
                dw offset byte_1BEA
                dw offset byte_201F
                dw offset byte_1C04
                db 0FFh                 ; sfx30
                dw offset byte_1C05
                dw offset byte_1C11
                dw offset byte_1C25
                db 0FFh                 ; sfx31
                dw offset byte_1C29
                dw offset byte_1C37
                dw offset byte_1C43
                db 0FFh                 ; sfx32
                dw offset byte_1C45
                dw offset byte_1C59
                dw offset byte_1C69
                db 9                    ; sfx33
                dw offset byte_1C6C
                dw offset byte_1C7C
                dw offset byte_1C8B
                db 9                    ; sfx34
                dw offset byte_1C8E
                dw offset byte_1C9A
                dw offset byte_1CA4
                db 9                    ; sfx35
                dw offset byte_1CA6
                dw offset byte_1CB7
                dw offset byte_1CC6
                db 9                    ; sfx36
                dw offset byte_1CC7
                dw offset byte_1CD3
                dw offset byte_1CDD
                db 9                    ; sfx37
                dw offset byte_1CDF
                dw offset byte_1CF1
                dw offset byte_1CFB
                db 1                    ; sfx38
                dw offset byte_1CFD
                dw offset byte_201F
                dw offset byte_1D11
                db 1                    ; sfx39
                dw offset byte_1D12
                dw offset byte_201F
                dw offset byte_1D26
                db 9                    ; sfx40
                dw offset byte_1D28
                dw offset byte_1D56
                dw offset byte_1D68
                db 9                    ; sfx41
                dw offset byte_1D6A
                dw offset byte_1D79
                dw offset byte_1D87
                db 0                    ; sfx42
                dw offset byte_1D88
                dw offset byte_1DA1
                dw offset byte_1DB8
                db 0                    ; sfx43
                dw offset byte_1DBA
                dw offset byte_201F
                dw offset byte_1DC4
                db 9                    ; sfx44
                dw offset byte_1DC5
                dw offset byte_1DF5
                dw offset byte_1E0C
                db 9                    ; sfx45
                dw offset byte_1E0F
                dw offset byte_1E20
                dw offset byte_1E2C
                db 9                    ; sfx46
                dw offset byte_1E2D
                dw offset byte_1E3E
                dw offset byte_1E46
                db 9                    ; sfx47
                dw offset byte_1E48
                dw offset byte_1E5B
                dw offset byte_1E65
                db 1                    ; sfx48
                dw offset byte_1E67
                dw offset byte_1E71
                dw offset byte_1E86
                db 0                    ; sfx49
                dw offset byte_1E88
                dw offset byte_1E92
                dw offset byte_1E9A
                db 0                    ; sfx50
                dw offset byte_1E9B
                dw offset byte_1EAA
                dw offset byte_1EB7
                db 9                    ; sfx51
                dw offset byte_1EBA
                dw offset byte_1ECB
                dw offset byte_1EDA
                db 9                    ; sfx52
                dw offset byte_1EDB
                dw offset byte_1EE9
                dw offset byte_1EF6
                db 8                    ; sfx53
                dw offset byte_1EF7
                dw offset byte_1F03
                dw offset byte_1F0D
                db 0                    ; sfx54
                dw offset byte_1F0E
                dw offset byte_1F27
                dw offset byte_1F36
                db 9                    ; sfx55
                dw offset byte_1F38
                dw offset byte_1F68
                dw offset byte_1F7F
                db 0                    ; sfx56
                dw offset byte_1F82
                dw offset byte_201F
                dw offset byte_1F8F
                db 9                    ; sfx57
                dw offset byte_1F91
                dw offset byte_1FA2
                dw offset byte_1FB0
                db 0                    ; sfx58
                dw offset byte_1FB2
                dw offset byte_201F
                dw offset byte_1FBF
                db 0                    ; sfx59
                dw offset byte_1FC1
                dw offset byte_201F
                dw offset byte_1FDE
                db 9                    ; sfx60
                dw offset byte_1FE0
                dw offset byte_201F
                dw offset byte_1FEB
                db 0FFh                 ; sfx61
                dw offset byte_1FEC
                dw offset byte_201F
                dw offset byte_1FF6
                db 0FFh                 ; sfx62
                dw offset byte_1FF7
                dw offset byte_201F
                dw offset byte_1FF6
                db 0FFh                 ; sfx63
                dw offset byte_2001
                dw offset byte_201F
                dw offset byte_1FF6
                db 0FFh                 ; sfx64
                dw offset byte_200B
                dw offset byte_201F
                dw offset byte_1FF6
                db 0FFh                 ; sfx65
                dw offset byte_2015
                dw offset byte_201F
                dw offset byte_1FF6
byte_190A       db 0F0h
                db    0
                db 0E0h
                db  7Fh ; 
                db  87h
                db 0E5h
                db    7
                db 0D5h
                db    5
                db 0FFh
byte_1914       db 3
byte_1915       db 0F0h
                db    0
                db 0E0h
                db  37h ; 7
                db  83h
                db 0E5h
                db    7
                db 0D5h
                db    8
                db  0Ah
                db  0Ch
                db 0E4h
                db    1
                db 0FFh
byte_1923       db 0Ch
byte_1924       db 0F0h
                db    0
                db 0E0h
                db  46h ; F
                db 0E5h
                db    7
                db  80h
                db 0D5h
                db    1
                db  81h
                db 0D4h
                db  11h
                db 0FFh
byte_1931       db 0F0h
                db    0
                db 0E5h
                db  17h
                db  80h
                db 0D3h
                db    1
                db  81h
                db 0D1h
                db  11h
                db 0FFh
byte_193C       db 3
                db  18h
byte_193E       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  82h
                db 0E5h
                db    7
                db 0D6h
                db    1
                db    0
                db  1Ah
                db 0FFh
byte_194A       db 0F0h
                db    0
                db  82h
                db 0E5h
                db    7
                db 0D3h
                db    1
                db    0
                db 0D6h
                db  11h
                db 0FFh
byte_1955       db 3
                db  0Ch
byte_1957       db 0F0h
                db    0
                db 0E0h
                db    0
                db  87h
                db 0E5h
                db    7
                db 0D4h
                db    1
                db 0FFh
byte_1961       db 12h
byte_1962       db 0F0h
                db    0
                db 0E0h
                db  69h ; i
                db 0E5h
                db    7
                db  83h
                db 0E2h
                db    1
                db    1
                db 0FEh
                db    2
                db 0FFh
                db  81h
                db 0D2h
                db    3
                db  82h
                db 0E2h
                db    0
                db 0D6h
                db    2
                db 0FFh
byte_1978       db 0F0h
                db    0
                db 0E5h
                db  17h
                db  83h
                db 0E2h
                db    1
                db    1
                db 0FEh
                db    2
                db 0FFh
                db  81h
                db 0D1h
                db    9
                db  84h
                db    1
                db 0FFh
byte_1989       db 0Ch
byte_198A       db 0F0h
                db    0
                db 0E0h
                db  69h ; i
                db  86h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    1
                db 0FFh
                db    2
                db 0FFh
                db  90h
                db 0D1h
                db    5
                db 0D1h
                db  17h
                db 0FFh
byte_199D       db 0F0h
                db    0
                db  82h
                db 0E5h
                db  0Fh
                db 0E2h
                db    1
                db    0
                db 0FFh
                db    2
                db    2
                db    1
                db 0D2h
                db    5
                db 0D1h
                db  17h
                db 0FFh
byte_19AE       db 0Ch
                db  18h
byte_19B0       db 0F0h
                db    0
                db 0E0h
                db    0
                db 0E5h
                db    7
                db  84h
                db    1
                db  11h
                db 0FFh
byte_19BA       db 0F0h
                db    0
                db 0E5h
                db    7
                db  88h
                db 0D2h
                db    1
                db  20h
                db 0D3h
                db  21h ; !
                db  20h
                db 0FFh
byte_19C6       db 6
                db    9
                db    3
byte_19C9       db 0F0h
                db    0
                db 0E0h
                db  37h ; 7
                db 0E5h
                db    7
                db  88h
                db 0D1h
                db  0Ch
                db 0E7h
                db 0E4h
                db    3
                db 0E7h
                db    1
                db 0FFh
byte_19D8       db 0F0h
                db    0
                db 0E5h
                db    7
                db  88h
                db 0D1h
                db  0Bh
                db 0E7h
                db    9
                db 0E7h
                db 0D5h
                db    1
                db 0FFh
byte_19E5       db 6
byte_19E6       db 0F0h
                db    0
                db 0E0h
                db  69h ; i
                db 0E5h
                db    7
                db  82h
                db 0D5h
                db    3
                db 0FFh
byte_19F0       db 18h
byte_19F1       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db 0E5h
                db    7
                db  83h
                db 0D8h
                db 0D5h
                db  13h
                db  14h
                db  16h
                db 0FFh
byte_19FE       db 0F0h
                db    0
                db 0E5h
                db    7
                db  83h
                db 0D8h
                db 0D7h
                db  1Bh
                db 0D3h
                db  15h
                db 0E4h
                db  13h
                db 0FFh
byte_1A0B       db 2
                db    6
byte_1A0D       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db 0E5h
                db    7
                db  87h
                db 0D5h
                db    7
                db 0FFh
byte_1A17       db 0F0h
                db    0
                db 0E5h
                db    7
                db  87h
                db 0D5h
                db  0Bh
                db 0FFh
byte_1A1F       db 6
byte_1A20       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db 0E5h
                db    7
                db  87h
                db 0D5h
                db    3
                db 0FFh
byte_1A2A       db 0F0h
                db    0
                db 0E5h
                db    7
                db  87h
                db 0D5h
                db    7
                db 0FFh
byte_1A32       db 6
byte_1A33       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db 0E5h
                db    7
                db  87h
                db 0D6h
                db    8
                db    8
                db    4
                db 0FFh
byte_1A3F       db 0F0h
                db    0
                db 0E5h
                db    7
                db  87h
                db 0D5h
                db    9
                db    1
                db  0Bh
                db 0FFh
byte_1A49       db 6
byte_1A4A       db 0F0h
                db    0
                db  83h
                db 0E2h
                db    1
                db  40h ; @
                db  40h ; @
                db  11h
                db  41h ; A
                db  81h
                db 0D2h
                db 0E5h
                db    7
                db 0E0h
                db  9Bh
                db    6
                db 0CEh
                db 0E0h
                db  91h
                db    6
                db 0CEh
                db 0E0h
                db  87h
                db    6
                db 0CEh
                db 0E0h
                db  7Dh ; }
                db    6
                db 0CEh
                db 0E0h
                db  73h ; s
                db    6
                db 0CEh
                db 0E0h
                db  69h ; i
                db    6
                db 0CEh
                db 0E0h
                db  5Fh ; _
                db    6
                db 0CEh
                db 0E0h
                db  55h ; U
                db    6
                db 0CEh
                db 0E0h
                db  4Bh ; K
                db    6
                db 0CEh
                db 0E0h
                db  41h ; A
                db    6
                db 0CEh
                db 0E0h
                db  37h ; 7
                db    6
                db 0CEh
                db 0E0h
                db  2Dh ; -
                db    6
                db 0FFh
byte_1A87       db 0F0h
                db    0
                db  83h
                db 0E2h
                db    1
                db  40h ; @
                db  40h ; @
                db  21h ; !
                db  11h
                db  81h
                db 0D0h
                db 0E5h
                db  17h
                db 0CDh
                db    1
                db    9
                db 0E4h
                db 0CDh
                db    1
                db    9
                db 0E4h
                db 0CDh
                db    1
                db    9
                db 0E4h
                db 0CDh
                db    1
                db    9
                db 0E4h
                db 0CDh
                db    1
                db    9
                db 0E4h
                db 0CDh
                db    1
                db    9
                db 0FFh
byte_1AAC       db 18h
byte_1AAD       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db 0E5h
                db    7
                db  87h
                db 0D8h
                db 0D5h
                db  1Ah
                db 0E3h
                db  1Ah
                db 0FFh
byte_1ABA       db 6
                db  0Ch
byte_1ABC       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db 0E5h
                db    7
                db  87h
                db 0D8h
                db 0D4h
                db  13h
                db 0E7h
                db 0E4h
                db  14h
                db 0FFh
byte_1ACA       db 6
                db  0Ch
byte_1ACC       db 0F0h
                db    0
                db 0E0h
                db  69h ; i
                db  82h
                db 0E5h
                db  2Fh ; /
                db 0D2h
                db  0Ah
                db 0E5h
                db  1Fh
                db    2
                db 0E5h
                db    7
                db  11h
                db 0FFh
byte_1ADC       db 0F0h
                db    0
                db  84h
                db 0D3h
                db 0E5h
                db  2Fh ; /
                db    1
                db 0E5h
                db  1Fh
                db    1
                db 0E5h
                db    7
                db  11h
                db 0FFh
byte_1AEA       db 0Ch
                db  12h
byte_1AEC       db 0F0h
                db    0
                db 0E0h
                db  7Fh ; 
                db  87h
                db 0E5h
                db    7
                db 0D4h
                db    1
                db 0FFh
byte_1AF6       db 3
byte_1AF7       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  82h
                db 0E5h
                db    7
                db 0D6h
                db    5
                db  15h
                db 0FFh
byte_1B02       db 0F0h
                db    0
                db  83h
                db 0E5h
                db  2Fh ; /
                db 0E1h
                db    4
                db 0D4h
                db    5
                db 0E4h
                db  15h
                db 0FFh
byte_1B0E       db 9
                db    3
byte_1B10       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  83h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db  40h ; @
                db  40h ; @
                db  21h ; !
                db  21h ; !
                db  81h
                db 0D4h
                db    3
                db 0FFh
byte_1B21       db 0F0h
                db    0
                db  82h
                db 0E5h
                db    7
                db 0D3h
                db    3
                db 0FFh
byte_1B29       db 3
byte_1B2A       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  87h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db  40h ; @
                db  40h ; @
                db  21h ; !
                db  21h ; !
                db  81h
                db 0D1h
                db    8
                db 0FFh
byte_1B3B       db 0F0h
                db    0
                db  83h
                db 0E5h
                db  27h ; '
                db 0E2h
                db    1
                db  40h ; @
                db  40h ; @
                db  21h ; !
                db  21h ; !
                db  81h
                db 0D1h
                db    8
                db 0FFh
byte_1B4A       db 3
byte_1B4B       db 0F0h
                db    0
                db 0E0h
                db  46h ; F
                db 0E5h
                db    7
                db  81h
                db 0D7h
                db    1
                db 0FFh
byte_1B55       db 0Ch
byte_1B56       db 0F0h
                db    0
                db 0E0h
                db  46h ; F
                db 0E5h
                db    7
                db 0D2h
                db  82h
                db    1
                db  11h
                db 0FFh
byte_1B61       db 0F0h
                db    0
                db 0E5h
                db    7
                db  86h
                db 0D3h
                db    6
                db 0D4h
                db  16h
                db 0FFh
byte_1B6B       db 0Ch
                db  18h
byte_1B6D       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db 0E5h
                db    7
                db 0E2h
                db    1
                db  78h ; x
                db    1
                db    2
                db    2
                db    1
                db  85h
                db 0D2h
                db    1
                db 0E7h
                db 0CEh
                db  11h
                db 0E7h
                db 0CEh
                db  11h
                db 0E7h
                db 0CEh
                db  11h
                db 0E7h
                db 0CEh
                db  21h ; !
                db 0FFh
byte_1B8A       db 0F0h
                db    0
                db 0E5h
                db    7
                db  81h
                db 0D3h
                db    1
                db 0D2h
                db  11h
                db  82h
                db 0D1h
                db  11h
                db 0D0h
                db  31h ; 1
                db 0FFh
byte_1B99       db 18h
                db  0Ch
                db  12h
                db  24h ; $
byte_1B9D       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  80h
                db 0E5h
                db    7
                db 0D0h
                db    1
                db 0E5h
                db  5Fh ; _
                db    1
                db 0FFh
byte_1BAA       db 0F0h
                db    0
                db  80h
                db 0E5h
                db    7
                db 0D3h
                db    1
                db 0E5h
                db  5Fh ; _
                db    1
                db 0FFh
byte_1BB5       db 6
byte_1BB6       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db  86h
                db 0E5h
                db    7
                db 0D5h
                db    8
                db  18h
                db 0D6h
                db  2Ah ; *
                db 0FFh
byte_1BC3       db 0F0h
                db    0
                db  86h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db  28h ; (
                db  28h ; (
                db    3
                db    3
                db    1
                db 0D5h
                db    8
                db  18h
                db 0D7h
                db  23h ; #
                db 0FFh
byte_1BD5       db 3
                db  0Ch
                db  30h ; 0
byte_1BD8       db 0F0h
                db    0
                db 0E0h
                db    5
                db  86h
                db 0E5h
                db    7
                db 0D5h
                db    8
                db  18h
                db 0D6h
                db  23h ; #
                db  3Ah ; :
                db 0FFh
byte_1BE6       db 3
                db  0Ch
                db  18h
                db  60h ; `
byte_1BEA       db 0F0h
                db    0
                db 0E0h
                db  87h
                db  83h
                db 0E2h
                db    1
                db  40h ; @
                db  40h ; @
                db    3
                db    3
                db    1
                db 0E5h
                db    7
                db 0D5h
                db    3
                db 0E5h
                db  17h
                db    3
                db 0E5h
                db    7
                db    8
                db 0E5h
                db  17h
                db    8
                db 0FFh
byte_1C04       db 6
byte_1C05       db 0F0h
                db    0
                db 0E0h
                db  87h
                db  83h
                db 0E5h
                db    7
                db 0D5h
                db    1
                db    0
                db  16h
                db 0FFh
byte_1C11       db 0F0h
                db    0
                db  83h
                db 0E2h
                db    1
                db  40h ; @
                db  40h ; @
                db    5
                db    5
                db    2
                db 0E1h
                db    4
                db 0E5h
                db  17h
                db  20h
                db 0D5h
                db    1
                db    0
                db  36h ; 6
                db 0FFh
byte_1C25       db 3
                db  18h
                db    6
                db  12h
byte_1C29       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  87h
                db 0E5h
                db    7
                db 0D5h
                db    1
                db  15h
                db 0E5h
                db  27h ; '
                db    5
                db 0FFh
byte_1C37       db 0F0h
                db    0
                db  87h
                db 0E5h
                db  17h
                db    0
                db 0E1h
                db    2
                db 0D5h
                db    1
                db  15h
                db 0FFh
byte_1C43       db 6
                db    9
byte_1C45       db 0F0h
                db    0
                db 0E0h
                db  87h
                db  82h
                db 0E5h
                db  0Fh
                db 0D0h
                db    1
                db    0
                db 0E2h
                db    1
                db  80h
                db  80h
                db    3
                db    3
                db    1
                db 0D1h
                db  18h
                db 0FFh
byte_1C59       db 0F0h
                db    0
                db  83h
                db 0E2h
                db    1
                db    0
                db 0FFh
                db    0
                db  1Fh
                db  81h
                db 0E5h
                db  0Fh
                db 0D1h
                db  21h ; !
                db  11h
                db 0FFh
byte_1C69       db 3
                db  24h ; $
                db    6
byte_1C6C       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db 0E5h
                db    7
                db  87h
                db 0D6h
                db    8
                db 0D5h
                db    1
                db 0D4h
                db    1
                db 0D5h
                db  18h
                db 0FFh
byte_1C7C       db 0F0h
                db    0
                db 0E5h
                db    7
                db  82h
                db 0D3h
                db    5
                db 0D1h
                db    8
                db  84h
                db 0E5h
                db  0Fh
                db 0D5h
                db  21h ; !
                db 0FFh
byte_1C8B       db 6
                db  0Ch
                db  18h
byte_1C8E       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  83h
                db 0E5h
                db    7
                db 0D2h
                db    1
                db 0D1h
                db  16h
                db 0FFh
byte_1C9A       db 0F0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0D2h
                db    7
                db 0D1h
                db  13h
                db 0FFh
byte_1CA4       db 6
                db  0Ch
byte_1CA6       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  82h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    2
                db    2
                db  0Bh
                db 0DDh
                db    1
                db 0D1h
                db    1
                db 0FFh
byte_1CB7       db 0F0h
                db    0
                db  88h
                db 0E5h
                db  0Fh
                db 0E2h
                db    1
                db    2
                db    2
                db  0Bh
                db 0DDh
                db    1
                db 0D1h
                db    1
                db 0FFh
byte_1CC6       db 48h
byte_1CC7       db 0F0h
                db    0
                db 0E0h
                db 0AFh
                db  83h
                db 0E5h
                db    7
                db 0D1h
                db    4
                db 0D1h
                db  13h
                db 0FFh
byte_1CD3       db 0F0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0D4h
                db    2
                db 0D1h
                db  1Bh
                db 0FFh
byte_1CDD       db 6
                db  0Ch
byte_1CDF       db 0F0h
                db    0
                db 0E0h
                db 0AFh
                db  88h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db  14h
                db  14h
                db  15h
                db  15h
                db    1
                db 0D3h
                db    1
                db  13h
                db 0FFh
byte_1CF1       db 0F0h
                db    0
                db  88h
                db 0E5h
                db  0Fh
                db 0D1h
                db    3
                db 0D2h
                db  1Bh
                db 0FFh
byte_1CFB       db 6
                db  0Ch
byte_1CFD       db 0F0h
                db    0
                db 0E0h
                db    5
                db  82h
                db 0E5h
                db    7
                db 0D4h
                db    1
                db 0D1h
                db  0Ch
                db 0D4h
                db    1
                db 0D1h
                db  0Ch
                db 0D4h
                db    1
                db 0D1h
                db  0Ch
                db 0FFh
byte_1D11       db 18h
byte_1D12       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  88h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    1
                db    1
                db  65h ; e
                db 0C9h
                db    1
                db 0D3h
                db    4
                db  82h
                db 0D1h
                db  11h
                db 0FFh
byte_1D26       db 0Ch
                db  12h
byte_1D28       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db  88h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    1
                db  80h
                db    3
                db    3
                db    1
                db 0D3h
                db    4
                db 0D1h
                db    4
                db 0D5h
                db    2
                db 0D4h
                db    6
                db 0E2h
                db    1
                db  1Ch
                db 0E1h
                db    5
                db    9
                db    1
                db 0D1h
                db    3
                db 0D3h
                db    2
                db 0D5h
                db    5
                db 0D3h
                db    4
                db 0D1h
                db    4
                db 0D5h
                db    2
                db 0D4h
                db    6
                db 0D4h
                db  11h
                db 0FFh
byte_1D56       db 0F0h
                db    0
                db  84h
                db 0E5h
                db  17h
                db    1
                db    1
                db    1
                db    1
                db    1
                db    1
                db    1
                db    1
                db    1
                db    1
                db    1
                db  11h
                db 0FFh
byte_1D68       db 6
                db  30h ; 0
byte_1D6A       db 0F0h
                db    0
                db 0E0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0D1h
                db    7
                db 0D1h
                db  0Ah
                db 0D4h
                db    2
                db    1
                db 0FFh
byte_1D79       db 0F0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0D2h
                db    1
                db 0D2h
                db    7
                db 0D3h
                db  0Bh
                db 0D1h
                db    7
                db 0FFh
byte_1D87       db 6
byte_1D88       db 0F0h
                db    0
                db 0E0h
                db    0
                db  83h
                db 0E5h
                db  17h
                db 0E2h
                db    1
                db  60h ; `
                db  60h ; `
                db    7
                db    7
                db    1
                db 0D5h
                db    7
                db 0E2h
                db    1
                db  60h ; `
                db  78h ; x
                db    7
                db    7
                db    1
                db  17h
                db 0FFh
byte_1DA1       db 0F0h
                db    0
                db  83h
                db 0E5h
                db  17h
                db 0E2h
                db    1
                db  80h
                db  80h
                db    7
                db    7
                db    1
                db 0D5h
                db    8
                db 0E2h
                db    1
                db  80h
                db 0A0h
                db    7
                db    7
                db    1
                db  18h
                db 0FFh
byte_1DB8       db 0Ch
                db  30h ; 0
byte_1DBA       db 0F0h
                db    0
                db 0E0h
                db    0
                db  81h
                db 0E5h
                db    7
                db 0D2h
                db  0Ch
                db 0FFh
byte_1DC4       db 60h
byte_1DC5       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db  88h
                db 0E5h
                db  1Fh
                db 0E2h
                db    1
                db    1
                db  80h
                db    3
                db    3
                db    1
                db 0D3h
                db    4
                db 0D1h
                db    4
                db 0D5h
                db    2
                db 0D4h
                db    6
                db 0E2h
                db    1
                db  1Ch
                db 0E1h
                db    5
                db    9
                db    1
                db 0D1h
                db    3
                db 0D3h
                db    2
                db 0D5h
                db    5
                db 0D3h
                db    4
                db 0D1h
                db    4
                db 0D5h
                db    2
                db 0D4h
                db    6
                db 0D3h
                db    5
                db 0D4h
                db  11h
                db 0FFh
byte_1DF5       db 0F0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db  60h ; `
                db  60h ; `
                db    7
                db    7
                db    1
                db 0D5h
                db  1Ah
                db 0E2h
                db    1
                db  60h ; `
                db  78h ; x
                db    7
                db    7
                db    1
                db  2Ah ; *
                db 0FFh
byte_1E0C       db 6
                db  30h ; 0
                db  48h ; H
byte_1E0F       db 0F0h
                db    0
                db 0E0h
                db  37h ; 7
                db  83h
                db 0E5h
                db    7
                db 0D3h
                db  0Ch
                db 0D5h
                db    6
                db 0D3h
                db  0Ah
                db 0D1h
                db    1
                db    1
                db 0FFh
byte_1E20       db 0F0h
                db    0
                db  84h
                db 0E5h
                db    7
                db    1
                db    1
                db 0D1h
                db    1
                db    1
                db    1
                db 0FFh
byte_1E2C       db 3
byte_1E2D       db 0F0h
                db    0
                db 0E0h
                db    0
                db  87h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    2
                db    2
                db  15h
                db  15h
                db    1
                db 0D3h
                db  0Ah
                db 0FFh
byte_1E3E       db 0F0h
                db    0
                db  84h
                db 0E5h
                db    7
                db 0D3h
                db  1Ah
                db 0FFh
byte_1E46       db 15h
                db  0Ch
byte_1E48       db 0F0h
                db    0
                db 0E0h
                db 0AFh
                db  87h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    1
                db 0FFh
                db    2
                db 0FBh
                db    1
                db 0D2h
                db    1
                db 0D1h
                db  16h
                db 0FFh
byte_1E5B       db 0F0h
                db    0
                db  82h
                db 0E5h
                db  17h
                db 0D2h
                db    7
                db 0D1h
                db  12h
                db 0FFh
byte_1E65       db 6
                db  0Ch
byte_1E67       db 0F0h
                db    0
                db 0E0h
                db 0AFh
                db  84h
                db 0E5h
                db    7
                db 0D1h
                db    1
                db 0FFh
byte_1E71       db 0F0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db 0FFh
                db  80h
                db    2
                db 0FFh
                db  81h
                db 0D1h
                db  18h
                db  18h
                db 0E7h
                db 0E2h
                db    0
                db 0D0h
                db  18h
                db 0FFh
byte_1E86       db 24h
                db  0Ch
byte_1E88       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db  80h
                db 0E5h
                db    7
                db 0D1h
                db    5
                db 0FFh
byte_1E92       db 0F0h
                db    0
                db  80h
                db 0E5h
                db    7
                db 0D2h
                db    7
                db 0FFh
byte_1E9A       db 6
byte_1E9B       db 0F0h
                db    0
                db 0E0h
                db 0AFh
                db  84h
                db 0E5h
                db    7
                db    1
                db 0E5h
                db  1Fh
                db    1
                db 0E5h
                db  2Fh ; /
                db  11h
                db 0FFh
byte_1EAA       db 0F0h
                db    0
                db  82h
                db 0E5h
                db    7
                db 0D5h
                db  21h ; !
                db  2Ah ; *
                db  2Ch ; ,
                db  25h ; %
                db 0D1h
                db  13h
                db 0FFh
byte_1EB7       db 6
                db  18h
                db    3
byte_1EBA       db 0F0h
                db    0
                db 0E0h
                db 0AFh
                db  84h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    2
                db    2
                db  0Bh
                db 0DDh
                db    1
                db 0D4h
                db    3
                db 0FFh
byte_1ECB       db 0F0h
                db    0
                db  88h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    2
                db    2
                db  0Bh
                db 0DDh
                db    1
                db 0D2h
                db    1
                db 0FFh
byte_1EDA       db 48h
byte_1EDB       db 0F0h
                db    0
                db 0E0h
                db  5Fh ; _
                db  84h
                db 0E5h
                db    7
                db 0D1h
                db    7
                db 0D1h
                db    8
                db 0D1h
                db    8
                db 0FFh
byte_1EE9       db 0F0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0D1h
                db  0Ah
                db 0D3h
                db    7
                db  82h
                db 0D2h
                db    4
                db 0FFh
byte_1EF6       db 0Ch
byte_1EF7       db 0F0h
                db    0
                db 0E0h
                db  87h
                db  83h
                db 0E5h
                db    7
                db 0D2h
                db    1
                db 0D1h
                db    5
                db 0FFh
byte_1F03       db 0F0h
                db    0
                db  83h
                db 0E5h
                db    7
                db 0D2h
                db    7
                db 0D1h
                db    3
                db 0FFh
byte_1F0D       db 6
byte_1F0E       db 0F0h
                db    0
                db 0E0h
                db    0
                db  83h
                db 0E5h
                db  17h
                db 0D1h
                db    1
                db  0Ch
                db    8
                db    3
                db    1
                db    5
                db    6
                db    8
                db  0Ah
                db  0Ch
                db    1
                db    3
                db    3
                db    5
                db    6
                db    7
                db 0FFh
byte_1F27       db 0F0h
                db    0
                db  84h
                db 0E5h
                db    7
                db 0D3h
                db  11h
                db  18h
                db  11h
                db  16h
                db  1Ah
                db  11h
                db  13h
                db  16h
                db 0FFh
byte_1F36       db 3
                db    6
byte_1F38       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db  85h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db    1
                db  40h ; @
                db    3
                db    3
                db    1
                db 0D3h
                db    4
                db 0D1h
                db    4
                db 0D5h
                db    2
                db 0D4h
                db    6
                db 0E2h
                db    1
                db  1Ch
                db  64h ; d
                db    5
                db    9
                db    1
                db 0D1h
                db    3
                db 0D3h
                db    2
                db 0D5h
                db    5
                db 0D3h
                db    4
                db 0D1h
                db    4
                db 0D5h
                db    2
                db 0D4h
                db    6
                db 0D3h
                db    5
                db 0D4h
                db  11h
                db 0FFh
byte_1F68       db 0F0h
                db    0
                db  84h
                db 0E5h
                db    7
                db 0E2h
                db    1
                db  60h ; `
                db  60h ; `
                db    7
                db    7
                db    1
                db 0D3h
                db  1Ah
                db 0E2h
                db    1
                db  60h ; `
                db  78h ; x
                db    7
                db    7
                db    1
                db  2Ah ; *
                db 0FFh
byte_1F7F       db 6
                db  30h ; 0
                db  48h ; H
byte_1F82       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  81h
                db 0E5h
                db    7
                db 0D4h
                db    1
                db 0E7h
                db 0D1h
                db  11h
                db 0FFh
byte_1F8F       db 0Ch
                db  18h
byte_1F91       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  83h
                db 0E5h
                db    7
                db 0D2h
                db    3
                db 0D1h
                db  0Ch
                db 0D1h
                db    6
                db  85h
                db 0D1h
                db  11h
                db 0FFh
byte_1FA2       db 0F0h
                db    0
                db  84h
                db 0E5h
                db    7
                db 0D2h
                db    1
                db 0D1h
                db    6
                db 0D1h
                db    1
                db 0D2h
                db  11h
                db 0FFh
byte_1FB0       db 2
                db  0Ch
byte_1FB2       db 0F0h
                db    0
                db 0E0h
                db  4Bh ; K
                db  88h
                db 0E5h
                db    7
                db 0D1h
                db  0Bh
                db  84h
                db 0D5h
                db  11h
                db 0FFh
byte_1FBF       db 0Ch
                db  18h
byte_1FC1       db 0F0h
                db    0
                db 0E0h
                db  9Bh
                db  83h
                db 0E2h
                db    1
                db 0FFh
                db 0FEh
                db 0FFh
                db    2
                db    1
                db 0D0h
                db 0E5h
                db    7
                db    3
                db 0E5h
                db  3Fh ; ?
                db  14h
                db 0E5h
                db  17h
                db  14h
                db 0E5h
                db  1Fh
                db  14h
                db 0E5h
                db  27h ; '
                db  14h
                db 0FFh
byte_1FDE       db 0Ch
                db    6
byte_1FE0       db 0F0h
                db    0
                db 0E0h
                db  37h ; 7
                db  88h
                db 0D3h
                db 0E5h
                db  0Fh
                db    3
                db  0Ch
                db 0FFh
byte_1FEB       db 0Ch
byte_1FEC       db 0F0h
                db    0
                db 0E0h
                db  7Fh ; 
                db  88h
                db 0E5h
                db  2Fh ; /
                db 0D3h
                db  0Ch
                db 0FFh
byte_1FF6       db 6
byte_1FF7       db 0F0h
                db    0
                db 0E0h
                db  7Fh ; 
                db  88h
                db 0E5h
                db  2Fh ; /
                db 0D3h
                db    6
                db 0FFh
byte_2001       db 0F0h
                db    0
                db 0E0h
                db  7Fh ; 
                db  88h
                db 0E5h
                db  2Fh ; /
                db 0D2h
                db    6
                db 0FFh
byte_200B       db 0F0h
                db    0
                db 0E0h
                db  7Fh ; 
                db  87h
                db 0E5h
                db  2Fh ; /
                db 0D4h
                db    6
                db 0FFh
byte_2015       db 0F0h
                db    0
                db 0E0h
                db  7Fh ; 
                db  87h
                db 0E5h
                db  2Fh ; /
                db 0D4h
                db  0Ch
                db 0FFh
byte_201F       db 0FFh
; OPL2 Instrument Table (9 bytes per instrument, base at InstrTable)
;==============================================================================
InstrTable     db 0Fh, 0, 2, 0, 0FAh, 0F7h, 6Fh, 8Fh, 0Eh
               db 0Fh, 10h, 0, 80h, 0F0h, 45h, 46h, 0D8h, 8Eh
               db 3Fh, 25h, 40h, 0, 0F4h, 0F6h, 0A3h, 88h, 0Eh
               db 24h, 22h, 14h, 4, 0F3h, 0E4h, 6, 8, 0
               db 2Fh, 5, 0, 0, 0F3h, 0F4h, 0Fh, 0FFh, 0Eh
               db 20h, 21h, 40h, 0, 0F8h, 0F3h, 4Fh, 3Fh, 0
               db 32h, 22h, 0CAh, 0, 0F5h, 0F5h, 5Fh, 0FFh, 0Eh
               db 4, 2, 86h, 0, 0F2h, 0F6h, 3Ch, 5Dh, 0
               db 24h, 22h, 8Ah, 0, 0F5h, 0F5h, 6Fh, 6Fh, 80h
; ---------------------------------------------------------------------------
; Driver global variables
; ---------------------------------------------------------------------------
HeartbeatTrigger     db 0
HeartbeatTimer       db 2
HeartbeatCounter     db 0
HeartbeatAttenuation db 0
HeartbeatFlipFlop    db 0
ChA_State            Ch_State <>
ChB_State            Ch_State <>
SfxPriority          db 0
TempoAccum           db 0
TempoCounter         db 0
TempoCarry           db 0
SfxDurTblPtr         dw 0
ActiveChCnt          db 0
ChannelMask          db 0

music_seg       ends
                end    start
