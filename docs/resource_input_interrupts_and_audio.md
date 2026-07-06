# Resource loading, input, interrupts, and audio

## Scope

This document covers the resident support layer and audio drivers:

- `stick.asm`
- `mscadlib.asm`
- `sndadlib.asm`
- `adlib.inc`
- resource loading behavior used by all other modules

## `stick.bin` overview

`stick.asm` is loaded at `org 100h`. Its first bytes are a mixed entry table:

```text
0100h  jump Keyboard_ISR_Hook
0103h  jump timer_ISR_int8_chained
0106h  jump Quiet_Critical_Error_Handler
0109h  jump Int_61_handler
010Ch  dw res_dispatcher
010Eh  dw reserved_nop
0110h  dw Confirm_Exit_Dialog
...
0120h  dw raw_joystick_calibration_read
```

This makes `stick.bin` both an interrupt module and a resident services module.

Important procedures found in `stick.asm`:

`space_alt_edge_detector`, `joystick_buttons_edge_detectors`, `joystick_btn1_edge_detector`, `F1_F2_edge_detector`, `timer_ISR_int8_chained`, `Keyboard_ISR_Hook`, `scan_code_dispatcher`, `Map_ScanCode_To_ASCII`, `Read_Joystick_Axes`, `Int_61_handler`, `joystick_axis_direction_bits`, `Confirm_Exit_Dialog`, `Handle_Pause_State`, `restore_dialog_background`, `Handle_Speed_Change`, `wait_digit_or_Esc`, `Joystick_Calibration`, `raw_joystick_calibration_read`, `Joystick_Deactivator`, `get_random`, `Handle_Restore_Game`, `draw_dialog_overlay_background`, `restore_dialog_overlay_background`, `flush_console_input`, `Scan_Saved_Games`, `res_dispatcher`, `fn1_load_mdt_idx_ah`, `fn2_segmented_load`, `fn4_load_sword_graphics`, `fn5_load_music`, `fn0_swap_town_vs_cavern_gfx_drv_and_jmp_bx`, `fn6_get_virtual_file_size`, `fn3_read_virtual_file`, `read_vfile_size`, `read_vfile_to_buffer`, `fclose`, `unpack_dispatcher`, `fn1_RLE_with_lookup_table_hi_nib`, `RLE_with_lookup_table_hi_nib_step`, `scan_till_sentinel_ff`, `RLE_with_lookup_table_lo_nib_step`, `lookup_byte_read_count`, `Quiet_Critical_Error_Handler`

## Keyboard handling

The keyboard hook is `Keyboard_ISR_Hook`. It receives scan codes, updates packed input state bytes, and maps scan codes to ASCII through `Map_ScanCode_To_ASCII`.

The shared input bytes live at `0FFxxh`:

| Symbol | Meaning |
|---|---|
| `____Alt_Space` | Packed Alt/Space state. |
| `____right_left_down_up` | Directional key state. |
| `F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter` | Packed keyboard state for function keys, letters, escape, control, shift, enter. |
| `Current_ASCII_Char` | Current decoded ASCII character. |
| `spacebar_latch` | Edge-detected spacebar event. |
| `altkey_latch` | Edge-detected Alt event. |

The routines `space_alt_edge_detector`, `F1_F2_edge_detector`, and related helpers convert held keys into edge-triggered latches. This prevents a single key press from triggering the same dialog/menu action repeatedly every frame.

## Timer handling

`timer_ISR_int8_chained` replaces the standard BIOS timer flow. `zeliard.asm` also reprograms the PIT to a faster tick rate of about 236.7 Hz. The game uses this high-frequency tick for frame pacing, animation timing, input latches, music polling, SFX polling, and callbacks.

Relevant shared fields:

| Symbol | Role |
|---|---|
| `frame_timer` | Counts frame timing intervals. |
| `anim_timer` | Drives animation phases. |
| `tick_counter` | Generic dialog/menu timing. |
| `fn_per_tick_callback` | Callback invoked by timer flow. |
| `fn_per_tick_user_ptr` | User callback pointer. |
| `per_tick_user_enabled` | Enables/disables the user callback. |

## Joystick handling

Joystick support reads port `201h`, which is the standard PC game-port address. The code supports:

- raw calibration reads,
- joystick activation/deactivation,
- button edge detection,
- axis timing reads,
- conversion into directional bits.

The joystick path is optional, controlled by config and `joystick_enabled_flag`.

## INT 61h service

`Int_61_handler` is a custom interrupt service for input/joystick-oriented calls. It gives other modules a stable way to ask for input services without needing to know `stick.bin` internals.

## Resource dispatcher

The most important non-input service in `stick.bin` is `res_dispatcher` at `010Ch`.

Dispatcher functions:

| AL | Function | Purpose |
|---:|---|---|
| `0` | `fn0_swap_town_vs_cavern_gfx_drv_and_jmp_bx` | Swap active graphics context and jump through BX. |
| `1` | `fn1_load_mdt_idx_ah` | Load a packed MDT map by index into `mdt_buffer` at `0C000h`. |
| `2` | `fn2_segmented_load` | Load a segmented/compressed resource, usually GRP, with unpacking. |
| `3` | `fn3_read_virtual_file` | Read a binary resource into the destination buffer. |
| `4` | `fn4_load_sword_graphics` | Load sword graphics by sword id. |
| `5` | `fn5_load_music` | Load music into the music driver area. |
| `6` | `fn6_get_virtual_file_size` | Query virtual file size. |

The virtual file descriptor format used throughout the code is usually:

```text
byte or word index/data selector
length/id field
zero-terminated filename
```

The exact structure depends on function, but the code passes `SI` to a descriptor and `DI` as the destination offset.

## GRP unpack dispatcher in `stick.asm`

`unpack_dispatcher` selects one of eight unpacking methods based on the low bits of the compressed payload header. The jump table contains:

| Method | Routine | Summary |
|---:|---|---|
| 0 | `fn0_raw_copy` | Direct copy. |
| 1 | `fn1_RLE_with_lookup_table_hi_nib` | RLE using high-nibble selector and lookup table. |
| 2 | `fn2_RLE_with_inline_marker_hi_nib` | High-nibble RLE with inline marker. |
| 3 | `fn3_RLE_with_lookup_table_lo_nib` | Low-nibble version of method 1. |
| 4 | `fn4_RLE_with_inline_marker_lo_nib` | Low-nibble version of method 2. |
| 5 | `fn5_byte_pair_RLE` | Byte-pair run encoding. |
| 6 | `fn6_RLE_with_word_sentinel_table` | Word/sentinel-table based RLE. |
| 7 | `fn7_three_byte_run_encoding` | Three-byte run encoding. |

This is the same family of unpacking logic described in the Python GRP viewer analysis.

## File loading path

Most resource loads follow this pattern:

1. Module sets `SI` to a virtual file descriptor.
2. Module sets `ES:DI` to the destination buffer.
3. Module sets `AL` to a dispatcher function.
4. Module calls `res_dispatcher_proc`.
5. `stick.bin` finds the file, reads size, reads compressed payload, and optionally unpacks to the destination.

Example from many shop modules:

```asm
mov es, word ptr ds:seg1
mov di, 8000h
mov si, offset vfs_armor_grp
mov al, 2
call word ptr cs:res_dispatcher_proc
```

This loads a `.grp` file into `seg1:8000h` and then the caller reassembles or decodes it for display.

## Music driver, `mscadlib.asm`

`mscadlib.asm` is the music driver. It is loaded as `mscadlib.drv`. It hooks/uses `INT 60h`, exposes music functions, and polls music state.

Important procedures:

`music_drv_poll_far`, `int60_new`, `music_fn2`, `music_fn3`, `music_fn4`, `music_fn5`, `music_fn6`, `sub_1EE`, `music_fn7`, `sub_21F`, `music_fn0`, `sub_30D`, `sub_350`, `sub_376`, `sub_3B1`, `music_fn1`, `sub_3D2`, `sub_3E5`, `sub_3EA`, `sub_463`, `sub_49D`, `sub_552`, `sub_583`, `sub_5AF`, `sub_74E`, `sub_7A6`, `sub_988`, `sub_9BB`, `sub_B00`, `sub_B08`

The function names are partly generic because the file is close to disassembly output, but the external behavior is clear:

- poll the music driver,
- start/stop music,
- load music data,
- update AdLib/MT-style channel state,
- handle an interrupt-driven music service.

## Sound effects driver, `sndadlib.asm`

`sndadlib.asm` is the AdLib sound effects driver. It is loaded as `sndadlib.drv`, likely using `INT 61h`/poll integration and direct OPL writes.

Important procedures:

`sound_drv_poll_farproc`, `SFX_Start`, `Ch_InitOp`, `ProcessTick`, `Ch_Sequencer`, `Ch_UpdateTotalLevel`, `Ch_SetFrequency`, `Ch_DoEnvelope`, `int60_fn6`, `OPL_WriteReg`, `HeartbeatTick`, `Heartbeat_SetupInstr`, `Heartbeat_LoadOp`, `Heartbeat_UpdateVol`, `Heartbeat_SetAttenuation`

Key responsibilities:

| Routine | Role |
|---|---|
| `SFX_Start` | Starts a sound effect. |
| `ProcessTick` | Per-tick SFX state update. |
| `Ch_Sequencer` | Advances a channel sequence. |
| `Ch_SetFrequency` | Programs pitch/frequency. |
| `Ch_DoEnvelope` | Updates envelope behavior. |
| `OPL_WriteReg` | Writes to AdLib OPL registers. |
| `HeartbeatTick` | Updates the heartbeat sound effect. |
| `Heartbeat_SetAttenuation` | Applies heartbeat volume/attenuation. |

The game uses `soundFX_request` and `heartbeat_volume` as shared control variables.

## Audio hardware concept

The SFX driver writes to the OPL chip registers. This means the original game does not render sampled audio. It drives FM synthesis. Music and sound effects are state machines that are updated regularly by the timer service.

## Practical porting notes

A faithful port should model three layers:

1. **Input state layer**: Preserve edge latches and packed directional bits first.
2. **Resource layer**: Implement virtual file lookup and unpacking before rendering.
3. **Audio abstraction**: Start with event-level sound triggers, then recreate OPL behavior or map events to modern audio samples.

For resource compatibility, the first target should be a byte-exact implementation of the GRP unpacker. Without that, the graphics drivers cannot be validated reliably.
