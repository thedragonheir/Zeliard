; fight.asm — Zeliard dungeon (cavern) engine
;
; --------
; This module implements the entire dungeon gameplay loop:
;   - Dungeon init & map decompression (MDT format)
;   - Per-frame hero movement: walk, jump, squat, rope climb, slope slide
;   - Hero sword attacks (forward / overhead swing / downward thrust)
;   - Hero damage, shield absorption, knockback, death + respawn
;   - Monster proximity culling, AI dispatching, spawning
;   - Contact damage, projectile collision with hero
;   - Magic spell projectiles (Espada, Saeta, Fuego, Lanzar, Rascar, Agua, Guerra)
;   - Collectible items/keys/gold/potions picked up via monster flags
;   - Door/platform logic (dchr.grp tiles)
;   - Dungeon-to-town and dungeon-to-dungeon transitions
;   - Boss cavern HUD, Jashiin special-case startup
;
; COORDINATE SYSTEM
; -----------------
; The dungeon map is mapWidth × 64 tiles (64 rows always).
; A 36 × 64 'proximity map' (0xE000–0xE8FF) is a sliding window over the
; full map, centered ±18 tiles around the hero's X position.
; The 28 × 19 'viewport buffer' (0xE900h) is a sub-window for screen tiles.
; Both wrap circularly; wrap_map_from_above / wrap_map_from_below enforce this.
;
; SPRITE SUMMARY (for JS renderer)
; ----------------------------------
; fman.grp  — hero in dungeon: 3×3 grid of 8×8 px tiles (= 24×24 px per frame).
;             Hero frame is composed by layering the body, right hand, optional shield and sword.
;             Frame table stored at the start of the file (groups × 9 bytes).
;             Palette: PAL_DECODE_TABLES[0]; tile format: 32 bytes/tile (mode 8 in grp_viewer.py).
; dchr.grp  — doors (multi-tile composites) and platforms (8×8 px tiles, mode 10).
; mpp?.grp  — dungeon tileset for the current cavern (8×8 px tiles, mode 10).
;             Loaded to seg1:8000h. Layout metadata: tile_anim_count_table @ 8000h,
;             special_tile_list @ 8002h, animation replacements @ 8004h.
; enp?.grp  — monsters/items: 2×2 grid of 8×8 px tiles (= 16×16 px per frame).
;             Each frame: [palette_idx, tl, tr, bl, br] (mode 11).
;             Loaded to seg1:monster_gfx (4000h), transparency masks at A000h.
; crab.grp  — boss sprite (multi-part body, mode 12).
; All these GRP files are compressed with the custom unpack() scheme (method 0-7)
; documented in grp_viewer.py.
;
; MDT MAP FORMAT
; --------------
; Each dungeon map file (*.mdt) contains:
;   [mdt_descriptor] 7 bytes — see common.inc mdt_descriptor STRUC
;   [cavern data]  — map name string, monsters table, doors table, platforms
;   [packed map]   — column-run-length encoded tile map, 64 rows × mapWidth cols
;                    4 encoding cases based on high 2 bits of each byte.
;
; MONSTER TABLE FORMAT  (monster struc from dungeon.inc)
; -------------------------------------------------------
; Each entry is 16 bytes. The table ends with 0xFFFF.
; Flags byte distinguishes live monsters (AI-controlled) from static items
; (keys, potions, chests, almas, signs, shoes). Items have flags 0x10-0x1E.
; Big monsters (4×4 tiles) occupy 2 consecutive table entries.
; ===========================================================================

include common.inc
include dungeon.inc
                .286
                .model small

; Range: 6000h - 9F2Eh Loaded length: 3F2Eh
fight           segment byte public 'CODE'
                assume cs:fight, ds:fight
                org 6000h
; ===========================================================================
; EXPORT TABLE — call gate for external callers (town.bin, AI modules, etc.)
; Each entry is the offset of a callable function, indexed by slot number.
; Callers reach these via the fight.bin base address + slot*2.
; Slots are declared in common.inc as fight.bin equates.
; ===========================================================================
start:
                dw Cavern_Game_Init
                dw offset prepare_dungeon ; run from town to dungeon
                dw offset monster_move_in_direction ; al=angle starting from right, counter-clockwise
                dw offset Check_collision_in_direction
                dw offset move_monster_E
                dw offset move_monster_NE
                dw offset move_monster_N
                dw offset move_monster_NW
                dw offset move_monster_W
                dw offset move_monster_SW
                dw offset move_monster_S
                dw offset move_monster_SE
                dw offset check_collision_E2
                dw offset check_collision_W2
                dw offset check_collision_N2
                dw offset check_collision_S2
                dw offset check_collision_NE2
                dw offset check_collision_SE2
                dw offset check_collision_NW2
                dw offset check_collision_SW2
                dw offset coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                dw offset wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                dw offset wrap_map_from_below ; if (si < 0E000h) si += 900h
                dw offset is_blocking
                dw offset check_monster_on_aggressive_ground
                dw offset Check_Vertical_Distance_Between_Hero_And_Monster
                dw offset Hero_Hits_monster
                dw offset is_in_proximity_window    ; Checks if given map X lies within the proximity window (width 36).
                                                    ; Returns CF if outside the window, accounting for world wrap.
                                                    ;         NC if inside the window, then BL = relative X in the window.

                dw offset Get_Stats     ; al=0: return ah=hero_level/2
                                        ; al=1: return ah=sword_total_damage
                                        ; al=2..8: return ah=byte_98BE[al-2]
                                        ; al=9: NOP
                dw offset Add_Projectile_To_Array ; In: BX pointing to projectile struct
                dw offset Browse_Projectiles
                dw offset Find_Monsters_Near_Hero ; Return dl: number of monsters found nearby
                dw offset Move_Monster_NWE_Depending_On_Whats_Below ; si points to monster struc

; ===========================================================================
; Entry point called when the dungeon scene begins (after MDT load).
; Also re-entered after room transitions (load_place_and_reinit → Cavern_Game_Init).
;
; Flow:
;   1. Reset SP, init projectile arrays and boss/flash flags.
;   2. Boss cavern path (is_boss_cavern != 0):
;      a. Draw enemy HUD bars.
;      b. Load boss music (fn5 → seg1:3000h).
;      c. Load ENCNT.GRP encounter intro sprite (fn2 → seg1:4000h).
;      d. Animate 6 'encounter flashing' intervals.
;      e. Override enp_grp_idx with boss_grp from mdt_descriptor.
;      f. Load boss enp?.grp → seg1:monster_gfx, decompress tile data.
;      g. Draw boss name (Pascal string from AI boss_state_block_ptr+9) and HP bars.
;   3. Jashiin special path (is_jashiin_cavern != 0):
;      Shifted viewport (hero not centered), loads MDT 30 (MPA0.MDT).
;   4. Regular cavern path:
;      Draw place name and gold label.
;   5. Common tail — draw hero HP bars, then fall through to init_cavern.
;
; main_loop (within Cavern_Game_Init):
;   Tightly coupled per-frame loop:
;     - Rope state check → over_rope handler if needed
;     - input_handling  : sword swing & spacebar latch
;     - sliding_physics_step
;     - main_update_render : full simulation + render tick
;     - magic_spell_fire_handler
;     - hero_interaction_check : tile-based interactions
;     - hero_knockback_handler
;     - State machine dispatcher (left/right/up/down key routing)
Cavern_Game_Init proc near
                cli
                mov     sp, 2000h
                sti
                push    cs
                pop     ds
                mov     slide_ticks_remaining, 0
                mov     horiz_movement_sub_tile_accum, 0
                mov     slide_direction, 0
                mov     ax, 0FFFFh
                mov     ds:projectiles_array, al
                mov     ds:boss_explosion_rings_list, al
                mov     ds:word ptr magic_projectiles, ax
                mov     byte ptr ds:boss_being_hit, 0
                mov     byte ptr ds:sprite_flash_flag, 0
                mov     byte ptr ds:boss_is_dead, 0
                mov     byte ptr ds:byte_9F01, 0
                test    byte ptr ds:is_boss_cavern, 0FFh
                jnz     short boss_place
                jmp     regular_cavern
; ---------------------------------------------------------------------------

; --- BOSS CAVERN INIT ---
; Draws enemy HUD, loads & plays encounter music, shows encounter intro sprite
; (ENCNT.GRP), animates 6 flash intervals at 0x41 timer ticks each.
; After animation: loads the actual boss enp sprite group and decompresses it.
boss_place:      
                call    render_hud_bars_with_enemy
                mov     ax, 1  ; fn1 (Stop) - Silences all channels and halts the driver.
                int     60h             ; mscadlib.drv
                mov     byte_9F02, 0FFh
                mov     al, byte ptr ds:msd_index
                mov     bl, 11
                mul     bl
                add     ax, offset vfs_mgt1_msd
                mov     si, ax
                mov     es, cs:seg1
                mov     di, 3000h       ; music buffer seg1:3000h
                mov     al, 5           ; fn5_load_music
                call    cs:res_dispatcher_proc ; =0A84
                mov     si, offset encnt_grp
                mov     es, cs:seg1
                mov     di, 4000h       ; seg1:4000h - decorations for encounter warning scene
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc ; =0A84h
                call    word ptr cs:Render_Animated_Tile_Strip_proc
                mov     byte ptr ds:hero_sprite_hidden, 0
                call    word ptr cs:Update_Local_Attribute_Cache_proc
                call    word ptr cs:Copy_Tile_Buffer_To_VRAM_proc
                call    clear_hero_in_viewport
                mov     byte_9F02, 0
                push    ds
                mov     ds, cs:seg1
                mov     si, 3000h
                xor     ax, ax  ; fn0 (Init/Play) - Clears buffers, loads music data, and starts playback.
                int     60h             ; mscadlib.drv
                pop     ds
; Flash big word 'ENCOUNTER' on screen 6 times
                mov     cx, 6
loc_60E9:        
                push    cx
                mov     byte ptr ds:frame_timer, 0
waiter0:         
                cmp     byte ptr ds:frame_timer, 65
                jb      short waiter0
                mov     bx, 0C28h
                mov     cx, 3828h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr ds:frame_timer, 0
loc_6108:        
                cmp     byte ptr ds:frame_timer, 65
                jb      short loc_6108
                call    word ptr cs:Render_Animated_Tile_Strip_proc
                pop     cx
                loop    loc_60E9
; flash animation end
                mov     si, ds:mdt_buffer
                add     si, 5           ; mdt_descriptor.boss_grp
                mov     al, [si]        ; boss idx
                mov     [si-1], al      ; mdt_descriptor.enp_grp_idx overridden by boss_grp idx
; load boss sprites
                mov     bl, 11
                mul     bl
                add     ax, offset vfs_enp1_grp
                mov     si, ax
                mov     es, cs:seg1
                mov     di, monster_gfx
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc ; =0A84h
                push    ds
                mov     ds, cs:seg1
                mov     si, monster_gfx
                mov     bp, monsters_transparency_masks
                mov     cx, 100h
                call    cs:Decompress_Tile_Data_proc
                pop     ds

; Boss HUD: display boss name from AI data, draw HP bars
render_boss_hud: 
                mov     si, ds:boss_state_block_ptr
                add     si, 8
                lodsb               ; boss_state.bs_unk_8
                mov     ds:byte_9F01, al
                mov     si, [si]    ; boss_state.bs_name_block_ptr
                call    cs:Render_Pascal_String_1_proc
                mov     si, ds:boss_state_block_ptr
                add     si, 3
                mov     bx, [si]    ; boss_state.bs_hp
                push    bx
                call    cs:Draw_Boss_Max_Health_proc ; bx: boss maxHP
                pop     bx
                call    cs:Draw_Boss_Health_proc ; bx: boss health
                jmp     short loc_618F
; ---------------------------------------------------------------------------

; REGULAR CAVERN INIT
; Clear place/enemy bar, render cavern name label and gold label.
regular_cavern:  
                call    cs:Clear_Place_Enemy_Bar_proc
                call    render_place_and_gold_labels
                mov     si, ds:cavern_name_rendering_info
                call    cs:Render_Pascal_String_1_proc
                call    cs:Print_Gold_Decimal_proc

; Common cavern HUD: hero max HP, current HP, almas counter
loc_618F:        
                call    cs:Draw_Hero_Max_Health_proc
                call    cs:Draw_Hero_Health_proc
                call    cs:Print_Almas_Decimal_proc
                test    byte ptr ds:is_jashiin_cavern, 0FFh
                jnz     short jashiin_place
                jmp     init_cavern

; Jashiin special path
; Viewport offset: hero appears at x=5 in viewport (x+36=41 in proximity map).
; Waits until is_jashiin_cavern flag clears (set by transition animation).
; Loads MPA0.MDT — Jashiin boss room
jashiin_place:   
                mov     ds:byte_9F26, 0FFh
                mov     word ptr ds:proximity_map_left_col_x, 41
                mov     byte ptr ds:hero_x_in_viewport, 5 ; 5+36=41; in the Jashiin's cavern hero appears not centered in viewport
                call    unpack_map
                call    clear_viewport_buffer

loc_61BE:        
                call    main_update_render
                test    byte ptr ds:is_jashiin_cavern, 0FFh
                jnz     short loc_61BE  ; wait until fully entered the boss cavern
                push    ds
                mov     ds, cs:seg1
                mov     si, 3000h
                xor     ax, ax  ; fn0 (Init/Play) - Clears buffers, loads music data, and starts playback.
                int     60h             ; mscadlib.drv
                pop     ds
                mov     ds:byte_9F02, 0
                mov     ah, 30          ; MPA0.MDT - Jashiin's room
                mov     al, 1           ; fn1_load_mdt_idx_ah
                call    cs:res_dispatcher_proc
                 
                mov     byte ptr ds:is_boss_cavern, 0FFh
                mov     ds:byte_9F27, 0FFh
                mov     si, ds:mdt_buffer
                lodsb                   ; al = first byte of mdt_descr
                call    process_mdt_descriptor
                call    load_cavern_sprites_ai_music ; load dchr.grp
                                        ; load mpp{mpp_grp_index}.grp
                                        ; load eai{eai_bin_index}.bin
                                        ; load enp{enp_grp_index}.grp
                                        ; load mgt{mgt_msd_index}.msd
                push    ds
                mov     ds, cs:seg1
                mov     si, 8030h
                mov     cx, 102
                call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                call    word ptr cs:NoOperation_proc
                pop     ds
                push    ds
                call    word ptr cs:Load_Magic_Spell_Sprite_Group_proc
                mov     cx, 24
                call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                pop     ds
                mov     ds:hero_x_in_proximity_map, 24
                mov     ds:door_target_y, 0Dh
                mov     byte ptr ds:hero_x_in_viewport, 12
                mov     ds:byte_9F00, 0Ch
                call    hero_left_16_down_1
                call    render_hud_bars_with_enemy
                jmp     render_boss_hud
; ---------------------------------------------------------------------------

; --- Normal dungeon startup ---
; Unpack the MDT map, update monster positions, check death flag.
init_cavern:     
                call    unpack_map      ; unpack *.mdt
                test    ds:byte_9F27, 0FFh
                jz      short loc_6254
                call    clear_viewport_buffer
                call    main_update_render
                mov     ds:byte_9F26, 0
                jmp     short loc_6266
; ---------------------------------------------------------------------------
loc_6254:        
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_6260
                call    cs:Render_Viewport_Tiles_proc
loc_6260:        
                call    clear_viewport_buffer ; 28x19
                call    update_all_monsters_in_map
loc_6266:        
                test    byte ptr ds:is_death_already_processed, 0FFh
                jz      short not_dead
                jmp     process_hero_death
; ---------------------------------------------------------------------------
not_dead:        
                test    ds:byte_9F02, 0FFh
                jz      short loc_628A
                mov     ds:byte_9F02, 0
                push    ds
                mov     ds, cs:seg1
                mov     si, 3000h
                xor     ax, ax          ; fn0 (Init/Play) - Clears buffers, loads music data, and starts playback.
                int     60h             ; mscadlib.drv
                pop     ds
loc_628A:        
                xor     al, al
                mov     ds:spacebar_latch, al
                mov     ds:altkey_latch, al
                mov     byte ptr ds:frame_timer, 0
                mov     ds:byte_9F27, 0

; ===========================================================================
; main_loop — per-frame game loop (called via PUSH/RET trick)
; Frame structure:
;   1. Check if on rope → separate rope-handling path
;   2. input_handling
;   3. sliding_physics_step
;   4. main_update_render
;   5. magic_spell_fire_handler
;   6. hero_interaction_check
;   7. hero_knockback_handler
;   8. frame_ticks counter: reset squat flag at tick 2
;   9. Read direction bits → route to state_machine_dispatcher
; ===========================================================================
main_loop:       
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jnz     short over_rope
                ; normal path
                call    input_handling
                call    sliding_physics_step
                call    main_update_render
                call    magic_spell_fire_handler
                call    hero_interaction_check
                call    hero_knockback_handler
                inc     ds:frame_ticks
                cmp     ds:frame_ticks, 2
                jne     short loc_62C5
                mov     byte ptr ds:squat_flag, 0

loc_62C5:        
                mov     dx, offset main_loop
                push    dx  ; main_loop will be called on return
                                        ; check input keys buffer
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 2
                jz      short no_down_pressed
                and     byte ptr ds:facing_direction, 11111101b ; down (not up)

no_down_pressed: 
                call    airborne_movement
                call    state_machine_dispatcher
                retn                    ; to main_loop or returns, if airborne_movement popped the return address
; ---------------------------------------------------------------------------

over_rope:       
                mov     byte ptr ds:squat_flag, 0
                mov     byte ptr ds:jump_phase_flags, 0 ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     byte ptr ds:slope_direction, 0
                mov     byte ptr ds:spell_active_flag, 0
                call    cs:Flush_Ui_Element_If_Dirty_proc
                mov     byte ptr ds:sword_swing_flag, 0
                call    main_update_render
                call    hero_knockback_handler
                call    state_machine_dispatcher
                cmp     byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jne     short move_off_rope
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                inc     si              ; hero head
                call    is_over_rope    ; set CF if [si] is rope (0 or 1)
                jc      short over_rope
                add     si, 36          ; fall down 1 tile
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                call    is_over_rope    ; set CF if [si] is rope (0 or 1)
                jc      short over_rope

move_off_rope:   
                and     byte ptr ds:facing_direction, 11111101b ; down
                mov     byte ptr ds:on_rope_flags, 0 ; any reason, including being hit by monster
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                mov     ds:slide_ticks_remaining, 0
                mov     ds:horiz_movement_sub_tile_accum, 0
                mov     byte ptr ds:hero_animation_phase, 7Fh
                jmp     main_loop
Cavern_Game_Init endp


; ===========================================================================
; Reads the current direction input and branches to the correct hero movement handler.
;
; Input combinations dispatched (al = right/left/down/up bitfield):
;   101b  (left+up)   → left_up_pressed
;   1001b (right+up)  → right_up_pressed
;   001b  (up only)   → up_pressed
;   100b  (left)      → on_left_pressed (left_up_pressed tail)
;   1000b (right)     → on_right_pressed (right_up_pressed tail)
;   010b  (down)      → down_pressed
;   else              → init_horizontal_sliding + idle animation
;
; Also manages the byte_9F24 direction-change latch for sliding init.
; ===========================================================================
state_machine_dispatcher proc near
                mov     ds:slide_direction, 0
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                cmp     al, 101b
                jne     short loc_6351
                jmp     left_up_pressed
; ---------------------------------------------------------------------------

loc_6351:        
                cmp     al, 1001b
                jne     short loc_6358
                jmp     right_up_pressed
; ---------------------------------------------------------------------------

loc_6358:        
                cmp     al, 1
                jne     short loc_635F
                jmp     up_pressed
; ---------------------------------------------------------------------------

loc_635F:        
                mov     ah, al  ; ah: ____right_left_down_up
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jnz     short loc_6399
                test    byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short loc_6399
                test    ds:byte_9F0B, 0FFh
                jnz     short loc_6379
                jmp     state_machine_dispatcher_idle_default
; ---------------------------------------------------------------------------

loc_6379:        
                mov     ds:byte_9F0B, 0
                test    byte ptr ds:facing_direction, 10b ; up
                jnz     short no_squat_mode
                jmp     state_machine_dispatcher_idle_default
; ---------------------------------------------------------------------------

no_squat_mode:   
                mov     dx, offset state_machine_dispatcher_idle_default
                push    dx
                test    byte ptr ds:facing_direction, LEFT
                jnz     short loc_6396
                jmp     on_right_pressed ; and then state_machine_dispatcher_idle_default
; ---------------------------------------------------------------------------

loc_6396:        
                jmp     on_left_pressed ; and then state_machine_dispatcher_idle_default
; ---------------------------------------------------------------------------

loc_6399:
                push    ax                ; ah = ____right_left_down_up
                    mov     al, ds:facing_direction
                    and     al, LEFT
                    cmp     al, ds:byte_9F24
                    mov     ds:byte_9F24, al  ; sliding direction = facing direction
                    je      short loc_63AB    ; already sliding, skip
                    call    init_horizontal_sliding
loc_63AB:        
                pop     ax
                mov     al, ah            ; al = ____right_left_down_up
                push    ax
                    cmp     al, 2
                    jne     short loc_63B6
                    call    down_pressed
loc_63B6:        
                pop     ax
                and     al, 1100b
                cmp     al, 4
                jne     short loc_63C0
                ; left pressed
                jmp     on_left_pressed
; ---------------------------------------------------------------------------

loc_63C0:        
                cmp     al, 8
                jne     short loc_63C7
                ; right pressed
                jmp     on_right_pressed
; ---------------------------------------------------------------------------

loc_63C7:        
                call    init_horizontal_sliding
                mov     al, ds:on_rope_flags ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                or      al, ds:squat_flag
                jz      short loc_63D4
                retn
; ---------------------------------------------------------------------------

loc_63D4:        
                mov     byte ptr ds:hero_animation_phase, 80h
                retn
state_machine_dispatcher endp


; ===========================================================================
; Checks whether the 3-tile-wide hero footprint overlaps a rope or door tile,
; routing to hero_moves_left / hero_moves_right if so.
; Skipped while squatting or airborne.
; Called every frame from main_loop.
; ===========================================================================
hero_interaction_check proc near
                test    byte ptr ds:squat_flag, 0FFh
                jz      short loc_63E2
                retn    ; squatting: skip
; ---------------------------------------------------------------------------
loc_63E2:        
                test    byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short loc_63EA
                retn    ; airborne: skip
; ---------------------------------------------------------------------------
loc_63EA:        
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                mov     al, [si] ; [0e10ch]=58h
                call    is_blocking_tile ; ZF if can pass; 58h -> ZF, NC
                jnz     short loc_63F5
                retn    ; hero's top left can't be here: skip
; ---------------------------------------------------------------------------
loc_63F5:        
                inc     si
                inc     si      ; si = hero top-right coord
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jnz     short loc_63FF
                retn    ; hero's top right can't be here: skip
; ---------------------------------------------------------------------------
loc_63FF:        
                add     si, 36  ; hero mid right coord
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jz      short loc_640F
                jmp     hero_moves_left
; ---------------------------------------------------------------------------
loc_640F:        
                jmp     hero_moves_right
hero_interaction_check endp


; ===========================================================================
; Applies knockback when the hero was just hit by a monster this frame.
; (byte_9F14 is set by check_hero_contact_damage when hit.)
;
; Behaviour:
;   - If byte_9F01 is set (boss cavern special flag), or byte_9F0E/9F10 vectors
;     indicate horizontal push: call move_hero_left/right twice.
;   - If on rope during knockback: drop off rope, enter descending state.
;   - If in an air-up tile: no extra push.
;   - If climbing down rope (jump_phase_flags 0x80): just move viewport down.
;   - Otherwise check floor landing, potentially scroll viewport down.
; ===========================================================================
hero_knockback_handler proc near
                test    ds:byte_9F14, 0FFh
                jnz     short loc_641A
                retn
; ---------------------------------------------------------------------------

loc_641A:        
                test    ds:byte_9F01, 0FFh
                jnz     short loc_6440
                mov     si, offset word_9F0E
                mov     al, [si]
                or      al, [si+1]
                mov     ah, [si+2]
                or      ah, [si+3]
                test    al, ah
                jz      short loc_643C
                test    byte ptr ds:facing_direction, 1
                jnz     short loc_6440
                jmp     short loc_6463
; ---------------------------------------------------------------------------

loc_643C:        
                or      al, al
                jnz     short loc_6463

loc_6440:       ; move left
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_645B
                and     byte ptr ds:facing_direction, 11111100b
                or      byte ptr ds:facing_direction, LEFT
                mov     byte ptr ds:jump_phase_flags, 7Fh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     byte ptr ds:spacebar_latch, 0

loc_645B:        
                call    move_hero_left_if_no_obstacles
                call    move_hero_left_if_no_obstacles
                jmp     short loc_6481
; ---------------------------------------------------------------------------

loc_6463:       ; move right
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_6479
                and     byte ptr ds:facing_direction, 11111100b ; right
                mov     byte ptr ds:jump_phase_flags, 7Fh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     byte ptr ds:spacebar_latch, 0

loc_6479:        
                call    move_hero_right_if_no_obstacles
                call    move_hero_right_if_no_obstacles
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_6481:        
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_6492  ;
                                        ; was on rope, hit by monster
                mov     byte ptr ds:on_rope_flags, 80h ; transition rope -> ground
                mov     byte ptr ds:jump_phase_flags, 0 ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope

loc_6492:        
                test    ds:air_up_tile_found, 0FFh
                jz      short loc_649A
                retn
; ---------------------------------------------------------------------------

loc_649A:        
                test    byte ptr ds:jump_phase_flags, 80h ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short loc_64A2
                retn
; ---------------------------------------------------------------------------

loc_64A2:        
                call    check_floor_for_landing
                jnc     short loc_64A8
                retn
; ---------------------------------------------------------------------------

loc_64A8:        
                test    ds:byte_9F09, 0FFh
                jnz     short loc_64B2
                jmp     hero_scroll_down
; ---------------------------------------------------------------------------

loc_64B2:        
                dec     ds:byte_9F09
                inc     byte ptr ds:hero_head_y_in_viewport
                retn
hero_knockback_handler endp


; ===========================================================================
; Applies one tick of ice-slide movement.
; Only active when cavern_level == 4 (ice cavern) AND no Ruzeria shoes.
; Consumes one tick from slide_ticks_remaining.
; Slides in the direction stored in slide_direction (1=right, 2=left),
; but respects the direction-lock bit in byte_9F23.
; If the tile underfoot is a non-ice tile (0x40-0x48), stops sliding.
; ===========================================================================
sliding_physics_step proc near
                call    set_zero_flag_if_slippery
                jz      short loc_64C1
                retn                    ; not slippery
; ---------------------------------------------------------------------------

loc_64C1:        
                test    byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short on_ground
                retn
; ---------------------------------------------------------------------------

on_ground:       
                test    ds:slide_ticks_remaining, 0FFh
                jnz     short loc_64D1
                retn
; ---------------------------------------------------------------------------

loc_64D1:        
                dec     ds:slide_ticks_remaining
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 3*36+1      ; points to tile under feet
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     al, [si]
                cmp     al, 40h
                jb      short loc_64EE
                cmp     al, 49h
                jnb     short loc_64EE
                ; al = 40h ... 48h
                mov     ds:slide_ticks_remaining, 0 ; stop sliding
                retn
; ---------------------------------------------------------------------------
                ; on the ice
loc_64EE:        
                mov     al, ds:slide_direction ; slide_direction: 1 = right, 2 = left
                test    ds:byte_9F23, 1 ; slide_direction_flags: Bit 0 = moving direction from previous tick
                jz      short loc_6500
                ; was moving right, try move right
                cmp     al, 1
                jne     short loc_64FD
                ; was already moving right
                retn
; ---------------------------------------------------------------------------
                ; slide_direction != 1 => confirm moving right
loc_64FD:        
                jmp     move_hero_right_if_no_obstacles
; ---------------------------------------------------------------------------
                ; was moving left, try move left
loc_6500:        
                cmp     al, 2
                jne     short loc_6505
                ; was already moving left
                retn
; ---------------------------------------------------------------------------
                ; slide_direction != 2 => confirm moving left
loc_6505:        
                jmp     move_hero_left_if_no_obstacles
sliding_physics_step endp



; When the hero starts moving on an ice surface, converts the accumulated
; horiz_movement_sub_tile_accum into slide_ticks_remaining (capped at 10).
; Called each time a directional key is read in the state machine.
; ===========================================================================
init_horizontal_sliding proc near
                call    set_zero_flag_if_slippery
                jz      short loc_650E
                retn
; ---------------------------------------------------------------------------

loc_650E:        
                test    ds:slide_ticks_remaining, 0FFh
                jz      short loc_6516
                retn
; ---------------------------------------------------------------------------

loc_6516:        
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_651E
                retn
; ---------------------------------------------------------------------------

loc_651E:        
                mov     al, ds:horiz_movement_sub_tile_accum
                shr     al, 1
                or      al, al
                jnz     short loc_6528
                retn
; ---------------------------------------------------------------------------

loc_6528:        
                cmp     al, 10
                jb      short loc_652E
                mov     al, 10

loc_652E:        
                mov     ds:slide_ticks_remaining, al
                mov     ds:horiz_movement_sub_tile_accum, 0
                retn
init_horizontal_sliding endp



; ===========================================================================
; Handles UP direction (no left/right).
; Tries (in order):
;   1. try_door_interaction — check for a door tile above hero
;   2. try_move_platform_up — raise a vertical platform if hero is on it
;   3. try_climb_rope       — grab a rope if hero is over it
; Falls through silently to jumping if none apply.
; ===========================================================================
up_pressed:
                mov     ds:byte_9F18, 0
                call    try_door_interaction ; can drop return address and continue to move_right/left_if_no_obstacles
                call    try_move_platform_up
                call    try_climb_rope
                ; otherwise, jump
; ===========================================================================
; Handles the jump initiation when UP+button is pressed.
; Increments slide_ticks_remaining (up to 10) while button is held.
;
; On ground:
;   - Checks tile above hero head; if clear, sets jump_phase_flags = 0xFF
;     (ascending), computes initial height_above_ground.
;   - Feruza shoes: height_above_ground starts at 2 (vs 1 normally),
;     allowing 4 vs 2 jump height steps.
;   - If hero head y < 7 (near viewport top), calls move_hero_up instead of
;     decrementing y directly.
; On slope or rope: transitions to descending (jump_phase_flags = 0x7F).
; ===========================================================================
jump_press_handler proc near  
                inc     ds:slide_ticks_remaining
                cmp     ds:slide_ticks_remaining, 10
                jb      short loc_6555
                mov     ds:slide_ticks_remaining, 10

loc_6555:        
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short on_ground1
                retn
; ---------------------------------------------------------------------------

on_ground1:       
                mov     byte ptr ds:squat_flag, 0
                mov     al, ds:byte_9F09
                cmp     al, ds:jump_height_including_shoes
                jnb     short state_machine_dispatcher_idle_default
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                sub     si, 35          ; points above hero head
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     al, [si] ; 1: [E0E9]=00; 2: [E0C5]=07
                call    is_blocking_tile ; ZF if can pass
                jnz     short loc_65A5
                mov     byte ptr ds:hero_animation_phase, 0
                and     byte ptr ds:facing_direction, 11111101b ; clear Up bit
                mov     byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     al, ds:jump_height_including_shoes
                shr     al, 1
                mov     ds:height_above_ground, al
                inc     ds:byte_9F09
                cmp     byte ptr ds:hero_head_y_in_viewport, 7
                jnb     short simple_jump
                jmp     move_hero_up
; ---------------------------------------------------------------------------

simple_jump:     
                dec     byte ptr ds:hero_head_y_in_viewport
                retn
; ---------------------------------------------------------------------------

loc_65A5:        
                test    ds:byte_9F09, 0FFh  ; [9F09]=01
                jnz     short state_machine_dispatcher_idle_default
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_65B4
                retn
; ---------------------------------------------------------------------------

loc_65B4:        
                mov     byte ptr ds:hero_animation_phase, 80h
                retn
; ---------------------------------------------------------------------------

state_machine_dispatcher_idle_default:        
                mov     byte ptr ds:slope_direction, 0
                mov     byte ptr ds:jump_phase_flags, 7Fh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                retn
jump_press_handler endp


; ===========================================================================
; Called from up_pressed.
; Checks the 3 possible hero-relative X positions for a rope tile (tile 0 or 1).
; If found directly above: begins climbing animation — moves hero up row by row
; (calling move_hero_up + main_update_render) until rope is no longer above.
; Sets on_rope_flags = 0xFF.
; ===========================================================================
try_climb_rope  proc near 
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                inc     si  ; points to hero head
                call    is_over_rope    ; set CF if rope found
                jc      short climb_to_rope_from_ground
                dec     si  ; check tile to the left of head
                call    is_over_rope    ; set CF if [si] is rope (0 or 1)
                jnc     short loc_65DC
                test    byte ptr ds:facing_direction, 1
                jnz     short on_left_pressed  ; move left to center on rope
                retn
; ---------------------------------------------------------------------------

loc_65DC:        
                inc     si
                inc     si  ; check tile to the right of head
                call    is_over_rope    ; set CF if [si] is rope (0 or 1)
                jc      short loc_65E4
                retn
; ---------------------------------------------------------------------------

loc_65E4:        
                test    byte ptr ds:facing_direction, 1
                jnz     short locret_65EE
                jmp     on_right_pressed  ; move right to center on rope
; ---------------------------------------------------------------------------

locret_65EE:     
                retn
; ---------------------------------------------------------------------------

climb_to_rope_from_ground:
                mov     byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                mov     byte ptr ds:squat_flag, 0

loc_65F9:        
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                sub     si, 35  ; points to tile above head
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                dec     byte ptr ds:hero_animation_phase
                call    is_over_rope    ; set CF if over rope
                jc      short loc_6611
                or      byte ptr ds:hero_animation_phase, 1
                retn
; ---------------------------------------------------------------------------

loc_6611:        
                call    move_hero_up
                call    main_update_render
                test    byte ptr ds:hero_animation_phase, 1
                jz      short loc_661F
                retn
; ---------------------------------------------------------------------------

loc_661F:        
                jmp     short loc_65F9
try_climb_rope  endp



; move_hero_up() {
;   viewport_top_row_y--;
;   viewport_left_top_addr -= 36;
;   if (viewport_left_top_addr < 0xE000) viewport_left_top_addr += 0x900;
; }
;
; Scrolls the viewport up by one tile row:
;   viewport_top_row_y--
;   viewport_left_top_addr -= 36  (with circular wrap if below 0xE000)
; ===========================================================================
move_hero_up    proc near 
                dec     byte ptr ds:viewport_top_row_y ; hero goes up
                mov     si, ds:viewport_left_top_addr ; viewport goes up too
                sub     si, 36
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     ds:viewport_left_top_addr, si
                retn
move_hero_up    endp


; ===========================================================================
; left_up_pressed / on_left_pressed (left movement without jump)
; Handles LEFT direction (optionally combined with UP for jump-left).
;
; - If facing right: flip_facing_direction, reset animation.
; - If squatting: ignore.
; - If on a right slope and moving left: clear Up bit, transition slope state.
; - Otherwise: call move_hero_left_if_no_obstacles.
;   On success: set slide_direction=2 (move dir=left), increment accum, set Up flag.
; ===========================================================================
left_up_pressed proc near 
                mov     ds:byte_9F0B, 0FFh
                call    jump_press_handler
                jmp     short $+2
; ---------------------------------------------------------------------------

on_left_pressed:        
                mov     ds:byte_9F18, 0
                test    byte ptr ds:facing_direction, left
                jnz     short loc_664D
                jmp     flip_facing_direction
; ---------------------------------------------------------------------------

loc_664D:        
                test    byte ptr ds:squat_flag, 0FFh
                jz      short loc_6655
                retn
; ---------------------------------------------------------------------------

loc_6655:        
                cmp     byte ptr ds:slope_direction, SLOPE_RIGHT
                jne     short loc_665F
                jmp     init_on_ground
; ---------------------------------------------------------------------------

loc_665F:        
                call    move_hero_left_if_no_obstacles
                jnc     short loc_6667
                ; CF: cannot move left
                jmp     init_on_ground
; ---------------------------------------------------------------------------

loc_6667:        
                mov     ds:slide_direction, 2   ; move dir=left
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_6674
                retn
; ---------------------------------------------------------------------------

loc_6674:        
                call    set_zero_flag_if_slippery
                jnz     short loc_6689
                test    ds:slide_ticks_remaining, 0FFh
                jnz     short loc_6689
                mov     ds:byte_9F23, 0  ; left movement
                inc     ds:horiz_movement_sub_tile_accum

loc_6689:        
                or      byte ptr ds:facing_direction, 10b
                test    byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short on_ground2
                retn
; ---------------------------------------------------------------------------

on_ground2:       
                inc     byte ptr ds:hero_animation_phase
                and     byte ptr ds:hero_animation_phase, 7Fh
                mov     ds:byte_9F19, 0
                retn
left_up_pressed endp


; ===========================================================================
; Attempts to move hero left (scroll the dungeon one tile to the right).
; Returns CF=1 if cannot move.
;
; 1. Check the 4 tiles (3 hero rows + 1 above) at hero x-1 for:
;    - Active monsters (proximity byte with bit 7 set) → block
;    - Solid/blocking tile type → block
;    - Airflow category 2 (right-flow wind) → block for normal cavern
; 2. If clear: decrement proximity_map_left_col_x,
;    shift proximity map 1 column right (rep movsb backward),
;    unpack new leftmost column from packed_map_ptr_for_prox_left.
; 3. After scroll: call every_projectile_moves_right_in_viewport,
;    then stamp the newly-entering right-edge monsters from monsters_table.
;
; SPRITE NOTE: The hero occupies a 3×3 tile area (3 columns wide) in the
; proximity map. hero_coords_to_addr_in_proximity returns the top-left corner.
; hero_x_in_viewport is always 0x0C (column 12) in normal caverns.
; ===========================================================================
move_hero_left_if_no_obstacles proc near
                call    hero_coords_to_addr_in_proximity
                mov     di, si
                sub     si, 36
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                dec     si              ; tile NW of hero top left
                mov     cx, 4

check_4_tiles_to_the_left_of_hero:
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags
                add     al, al          ; destroyable walls have bit 7 set
                jnb     short loc_66BC
                retn                    ; destroyable wall to the left of hero, can't move
; ---------------------------------------------------------------------------

loc_66BC:        
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                loop    check_4_tiles_to_the_left_of_hero
                xchg    di, si
                test    byte ptr ds:squat_flag, 0FFh ; =0
                jnz     short loc_66DC
                mov     al, [si]        ; tile where hero head will come
                call    is_blocking_tile ; ZF if can pass
                stc
                jz      short loc_66D6
                retn
; ---------------------------------------------------------------------------

loc_66D6:        
                call    is_right_airflow
                jnb     short loc_66DC
                retn
; ---------------------------------------------------------------------------

loc_66DC:        
                mov     cx, 2

loc_66DF:        
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     al, [si]        ; map element (tile)
                call    is_blocking_tile_simple
                stc
                jz      short loc_66EE
                retn
; ---------------------------------------------------------------------------

loc_66EE:        
                push    cx
                call    is_right_airflow
                pop     cx
                jnb     short loc_66F6
                retn
; ---------------------------------------------------------------------------

loc_66F6:        
                loop    loc_66DF

hero_moves_left: 
                dec     word ptr ds:proximity_map_left_col_x
                cmp     word ptr ds:proximity_map_left_col_x, 0FFFFh
                jnz     short proximity_map_scrolls_right ; no wrap
                mov     ax, ds:mapWidth ; wrap to end of map
                dec     ax
                mov     ds:proximity_map_left_col_x, ax ; mapWidth - 1
                mov     si, ds:packed_map_end_ptr ; end of packed map + 1
                mov     ds:packed_map_ptr_for_prox_left, si

proximity_map_scrolls_right:  
                push    cs              ; free left column of proximity map
                pop     es
                std
                mov     si, offset proximity_map+36*64-2
                mov     di, offset proximity_map+36*64-1
                mov     cx, 36*64-1
                rep movsb
                cld
                mov     si, ds:packed_map_ptr_for_prox_left
                dec     si              ; points to the last byte of packed column
                mov     di, offset proximity_map+36*(64-1) ; last row, leftmost column
                xor     dl, dl          ; y = 0

fill_column_backward:     
                call    unpack_step_backward
                dec     si
                add     dl, bh          ; y += count

repeat_bh_times: 
                mov     [di], bl        ; tile
                sub     di, 36          ; move up one row
                dec     bh
                jnz     short repeat_bh_times
                cmp     dl, 64
                jb      short fill_column_backward
                inc     si
                mov     ds:packed_map_ptr_for_prox_left, si
                mov     si, ds:packed_map_end_ptr
                dec     si              ; end of packed map
                mov     ax, ds:proximity_map_left_col_x ; already decremented and wrapped
                add     ax, 36          ; hero_x_plus_18_abs
                cmp     ax, ds:mapWidth
                jz      short no_column_skip_needed ;
                                        ; we need to prepare pointer also for unpacking rightmost column of proximity map
                                        ; they both need to be in sync (36 columns apart)
                mov     si, ds:packed_map_ptr_for_prox_right
                xor     dh, dh          ; y = 0

skip_bh_times:   
                call    unpack_step_backward
                dec     si
                add     dh, bh          ; y += count
                cmp     dh, 64
                jb      short skip_bh_times

no_column_skip_needed:    
                mov     ds:packed_map_ptr_for_prox_right, si
                call    every_projectile_moves_right_in_viewport ; x coord in viewport increases
                mov     bx, ds:proximity_map_left_col_x
                mov     byte ptr ds:monster_index, 0
                mov     si, ds:monsters_table_addr

next_monster:    
                mov     ax, [si+monster.currX]
                cmp     ax, 0FFFFh      ; end of monsters marker
                jnz     short loc_6782
                retn
; ---------------------------------------------------------------------------

loc_6782:        
                cmp     ah, 0FFh        ; special 'monster'
                jz      short skip_monster
                cmp     ax, bx          ; only process monsters on the left proximity margin
                jnz     short skip_monster
                xor     ah, ah          ; x relative to left proximity margin = 0
                mov     al, [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     al, ds:monster_index
                or      al, 80h
                mov     [di], al

skip_monster:    
                inc     byte ptr ds:monster_index
                add     si, 10h
                jmp     short next_monster
move_hero_left_if_no_obstacles endp


; ===========================================================================
; Returns CF=1 (cannot pass) if tile [si] is an airflow tile of category 2
; (right-flowing wind). Used for left-movement blocking in level 5 caverns.
; get_airflow_direction → ZF + cl=0/1/2 for up/left/right.
; ===========================================================================
is_right_airflow proc near
                cmp     byte ptr ds:cavern_level, 7
                clc
                jne     short loc_67AC
                retn    ; level 7, no airflows: NC
; ---------------------------------------------------------------------------

loc_67AC:        
                mov     al, [si]
                push    si
                call    get_airflow_direction ; Is input tile an airflow?
                                        ; Input: al
                                        ; Output:
                                        ; NZ, cl=0xff (no airflow)
                                        ; ZF, cl=0 (Up), 1 (Left), 2 (Right)
                pop     si
                cmp     cl, 2
                stc
                jne     short loc_67BA
                retn    ; right airflow: CF
; ---------------------------------------------------------------------------

loc_67BA:        
                clc
                retn    ; not right airflow: NC
is_right_airflow endp



; ===========================================================================
; right_up_pressed / on_right_pressed (right movement without jump)
; Mirror of left_up_pressed for rightward movement.
; - If facing left: flip_facing_direction.
; - If on right slope and moving right: transition slope state.
; - Otherwise: call move_hero_right_if_no_obstacles.
; ===========================================================================
right_up_pressed proc near
                mov     ds:byte_9F0B, 0FFh
                call    jump_press_handler
                jmp     short $+2
; ---------------------------------------------------------------------------

on_right_pressed:        ; @67C6
                mov     ds:byte_9F18, 0
                test    byte ptr ds:facing_direction, LEFT
                jnz     short flip_facing_direction
                test    byte ptr ds:squat_flag, 0FFh
                jz      short loc_67DA
                retn
; ---------------------------------------------------------------------------

loc_67DA:        
                cmp     byte ptr ds:slope_direction, SLOPE_LEFT
                je      short init_on_ground
                call    move_hero_right_if_no_obstacles
                jc      short init_on_ground   ; CF: cannot move right
                mov     ds:slide_direction, 1  ; move dir = right
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_67F3
                retn
; ---------------------------------------------------------------------------

loc_67F3:        
                call    set_zero_flag_if_slippery
                jnz     short loc_6808
                test    ds:slide_ticks_remaining, 0FFh
                jnz     short loc_6808
                mov     ds:byte_9F23, 1   ; 1 => right movement
                inc     ds:horiz_movement_sub_tile_accum

loc_6808:        
                or      byte ptr ds:facing_direction, UP
                test    byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short loc_6815
                retn
; ---------------------------------------------------------------------------

loc_6815:        
                inc     byte ptr ds:hero_animation_phase
                and     byte ptr ds:hero_animation_phase, 7Fh
                mov     ds:byte_9F19, 0
                retn
right_up_pressed endp


; ===========================================================================
; flip_facing_direction
; Toggles facing_direction left/right.
; If on ground: resets hero_animation_phase to 0x80 (idle frame).
; ===========================================================================
flip_facing_direction proc near 
                xor     byte ptr ds:facing_direction, 1
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short on_ground3
                retn
; ---------------------------------------------------------------------------

on_ground3:       
                mov     byte ptr ds:hero_animation_phase, 80h
                retn
flip_facing_direction endp

; ============================================================
init_on_ground  proc near
                and     byte ptr ds:facing_direction, 11111101b ; clear Up
                mov     al, ds:on_rope_flags ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                or      al, ds:jump_phase_flags ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short loc_6846
                retn
; ---------------------------------------------------------------------------

loc_6846:        
                mov     byte ptr ds:hero_animation_phase, 80h
                retn
init_on_ground  endp

; ===========================================================================
; Attempts to scroll the dungeon one tile to the left (hero moves right).
; Mirror of move_hero_left_if_no_obstacles:
; 1. Check 4 tiles at hero x+2 for monsters or solid tiles.
; 2. If clear: increment proximity_map_left_col_x,
;    shift proximity map 1 column left (rep movsb forward),
;    unpack new rightmost column from packed_map_ptr_for_prox_right.
; 3. Call every_projectile_moves_left_in_viewport,
;    stamp newly-entering left-edge monsters.
; ===========================================================================
move_hero_right_if_no_obstacles proc near
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                inc     si
                inc     si              ; x+=2
                mov     di, si
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     cx, 4
loc_685C:        
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags
                add     al, al          ; destroyable walls have bit 7 set
                jnc     short loc_6864
                retn                    ; destroyable wall to the right of hero, can't move
; ---------------------------------------------------------------------------

loc_6864:        
                add     si, 36          ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                loop    loc_685C
                xchg    di, si
                test    byte ptr ds:squat_flag, 0FFh
                jnz     short loc_6884
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                stc
                jz      short loc_687E
                retn
; ---------------------------------------------------------------------------

loc_687E:        
                call    is_left_airflow
                jnc     short loc_6884
                retn
; ---------------------------------------------------------------------------

loc_6884:        
                mov     cx, 2

loc_6887:        
                add     si, 36          ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     al, [si]
                call    is_blocking_tile_simple
                stc
                jz      short loc_6896
                retn
; ---------------------------------------------------------------------------

loc_6896:        
                push    cx
                call    is_left_airflow
                pop     cx
                jnb     short loc_689E
                retn
; ---------------------------------------------------------------------------

loc_689E:        
                loop    loc_6887

hero_moves_right:
                inc     word ptr ds:proximity_map_left_col_x
                mov     ax, ds:proximity_map_left_col_x
                add     ax, 36-1
                cmp     ax, ds:mapWidth
                jnz     short proximity_map_scrolls_left
                mov     ds:packed_map_ptr_for_prox_right, (offset packed_map_end_ptr+1)

proximity_map_scrolls_left:   
                push    cs
                pop     es
                mov     si, offset proximity_map+1
                mov     di, offset proximity_map
                mov     cx, 36*64-1
                rep movsb
                mov     si, ds:packed_map_ptr_for_prox_right ; =c7e7
                inc     si
                mov     di, offset proximity_map+36-1 ; right column offset
                call    unpack_column
                dec     si
                mov     ds:packed_map_ptr_for_prox_right, si
                mov     ax, ds:proximity_map_left_col_x
                cmp     ax, ds:mapWidth
                jnz     short loc_68E7
                mov     word ptr ds:proximity_map_left_col_x, 0
                mov     si, offset packed_map_start
                jmp     short loc_68F8
; ---------------------------------------------------------------------------

loc_68E7:        
                mov     si, ds:packed_map_ptr_for_prox_left
                xor     dh, dh

unpack_left_column:       
                call    unpack_step_forward ; unpack extra column to /dev/null
                inc     si
                add     dh, bh
                cmp     dh, 64
                jb      short unpack_left_column ; unpack extra column to /dev/null

loc_68F8:        
                mov     ds:packed_map_ptr_for_prox_left, si
                call    every_projectile_moves_left_in_viewport
                mov     byte ptr ds:monster_index, 0
                mov     bx, ds:proximity_map_left_col_x
                add     bx, 36-1
                mov     ax, bx
                sub     ax, ds:mapWidth
                jb      short loc_6915
                mov     bx, ax

loc_6915:        
                mov     si, ds:monsters_table_addr

next_monster1:    
                mov     ax, [si+monster.currX]
                cmp     ax, 0FFFFh
                jne     short loc_6921
                retn                    ; monsters end marker
; ---------------------------------------------------------------------------

loc_6921:        
                cmp     ah, 0FFh
                je      short loc_6939
                cmp     ax, bx
                jne     short loc_6939
                mov     ah, 35
                mov     al, [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     al, ds:monster_index
                or      al, 80h
                mov     [di], al

loc_6939:        
                inc     byte ptr ds:monster_index
                add     si, 16
                jmp     short next_monster1
move_hero_right_if_no_obstacles endp


; ===========================================================================
; Returns CF=1 if tile [si] is left airflow.
; Used for right-movement blocking in non-level 7 caverns.
; ===========================================================================
is_left_airflow proc near
                cmp     byte ptr ds:cavern_level, 7
                clc
                jne     short loc_694B
                retn  ; level 7, no airflows: NC
; ---------------------------------------------------------------------------

loc_694B:        
                mov     al, [si]
                push    si
                call    get_airflow_direction ; Is input tile an airflow?
                                        ; Input: al
                                        ; Output:
                                        ; NZ, cl=0xff (no airflow)
                                        ; ZF, cl=0 (Up), 1 (Left), 2 (Right)
                pop     si
                dec     cl
                stc
                jnz     short loc_6958
                retn  ; left airflow: CF
; ---------------------------------------------------------------------------

loc_6958:        
                clc
                retn  ; not left airflow: NC
is_left_airflow endp



; ===========================================================================
; Handles all in-air physics each frame (ascending and descending).
;
; Skip if air_up_tile_found or jump_phase_flags bit 7 (rope-descend mode).
;
; Per tick:
;   1. hero_collapse_platform — collapse any crumbling platform hero stands on
;   2. slope_assist_on_landing — slide hero along slope during descent
;   3. check_floor_for_landing — if floor tile found below: jmp land_after_jump
;   4. Increment jump_height_counter.
;   5. Scroll viewport down (byte_9F09 driven) if near viewport bottom.
;   6. Fall-off-cliff path: hero_scroll_down.
;   7. Rope grab check during flight.
;   8. If descending (was ascending before): read arrow keys for in-air steering.
; ===========================================================================
airborne_movement proc near   
                test    ds:air_up_tile_found, 0FFh
                jz      short loc_6962 ; v
                retn
; ---------------------------------------------------------------------------

loc_6962:        
                test    byte ptr ds:jump_phase_flags, 80h ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short loc_696A ; 0v
                retn
; ---------------------------------------------------------------------------

loc_696A:        
                call    hero_collapse_platform
                call    slope_assist_on_landing
                call    check_floor_for_landing ; after death: CF NZ
                jnc     short loc_6978 ; no jump
                jmp     land_after_jump ; on return, will jump to main_loop
; ---------------------------------------------------------------------------

loc_6978:        
                inc     ds:jump_height_counter
                test    ds:byte_9F09, 0FFh
                jz      short loc_698D
                pushf
                dec     ds:byte_9F09
                inc     byte ptr ds:hero_head_y_in_viewport
                popf

loc_698D:        
                pop     ax              ; return address - ignore
                jnz     short loc_6993  ;
                                        ; fall off cliff
                call    hero_scroll_down

loc_6993:        
                test    byte ptr ds:facing_direction, UP ; 03 when walked left
                jnz     short loc_69AE
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 36*2+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                call    is_over_rope    ; set CF if [si] is rope (0 or 1)
                jnc     short loc_69AE
                mov     byte ptr ds:on_rope_flags, 0FFh ; hang on rope by walking
                retn
; ---------------------------------------------------------------------------

loc_69AE:        
                mov     byte ptr ds:hero_animation_phase, 80h
                mov     al, ds:jump_phase_flags ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     byte ptr ds:jump_phase_flags, 7Fh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                test    byte ptr ds:slope_direction, 0FFh
                jz      short loc_69C3
                retn
; ---------------------------------------------------------------------------

loc_69C3:        
                test    byte ptr ds:invincibility_flag, 0FFh
                jz      short loc_69CB
                retn
; ---------------------------------------------------------------------------

loc_69CB:        
                test    al, 0FFh   ; old phase
                jnz     short read_keys_buffer
                mov     ax, offset loc_69E0
                push    ax
                test    byte ptr ds:facing_direction, LEFT
                jz      short loc_69DD
                jmp     on_left_pressed
; ---------------------------------------------------------------------------

loc_69DD:        
                jmp     on_right_pressed
; ---------------------------------------------------------------------------

loc_69E0:        
                and     byte ptr ds:facing_direction, 11111101b
                retn
; ---------------------------------------------------------------------------

read_keys_buffer:
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                and     al, 1100b
                cmp     al, 100b        ; left
                je      short left_pressed
                cmp     al, 1000b       ; right
                je      short right_pressed

loc_69F2:       ; default case
                test    byte ptr ds:facing_direction, UP
                jnz     short loc_6A02
                cmp     al, 100b        ; left
                jz      short right_default
                cmp     al, 1000b       ; right
                jz      short left_default
                retn
; ---------------------------------------------------------------------------

loc_6A02:        
                test    byte ptr ds:facing_direction, LEFT
                jz      short loc_6A0C
                jmp     on_left_pressed
; ---------------------------------------------------------------------------

loc_6A0C:        
                jmp     on_right_pressed
; ---------------------------------------------------------------------------

left_pressed:    
                test    byte ptr ds:facing_direction, 1
                jnz     short loc_69F2 ; default case
                and     byte ptr ds:facing_direction, 11111101b
                call    flip_facing_direction

left_default:        
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 3*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jz      short loc_6A2F
                retn
; ---------------------------------------------------------------------------

loc_6A2F:        
                inc     si
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jnz     short loc_6A38
                retn
; ---------------------------------------------------------------------------

loc_6A38:        
                jmp     move_hero_right_if_no_obstacles
; ---------------------------------------------------------------------------

right_pressed:   
                test    byte ptr ds:facing_direction, LEFT
                jz      short loc_69F2  ; default case
                and     byte ptr ds:facing_direction, 11111101b
                call    flip_facing_direction

right_default:        
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 3*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jz      short loc_6A5B
                retn
; ---------------------------------------------------------------------------

loc_6A5B:        
                dec     si
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jnz     short loc_6A64
                retn
; ---------------------------------------------------------------------------

loc_6A64:        
                jmp     move_hero_left_if_no_obstacles
airborne_movement endp


; ===========================================================================
; Called each airborne frame to handle slope interactions.
; Reads tile at hero feet+2 rows via get_slope_direction_by_tile_under_feet.
; If on a slope:
;   - Slide down every 4th tick (unless input holds uphill direction).
;   - Silkarn shoes: no forced sliding.
;   - height_above_ground counts down; at 0, slides freely every frame.
; Slope tiles defined in seg1:8018h (left slope 0x0B) and 801Ch (right slope 0x0C).
; ===========================================================================
slope_assist_on_landing proc near
                mov     byte ptr ds:slope_direction, 0
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 2*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                call    get_slope_direction_by_tile_under_feet ; NZ: no slope
                                        ; ZF dl=1: right slope \
                                        ; ZF dl=2: left slope /
                jz      short loc_6A7B
                retn                    ; no slope
; ---------------------------------------------------------------------------

loc_6A7B:       ; slope
                and     byte ptr ds:facing_direction, 11111101b
                mov     ds:slope_direction, dl
                test    ds:height_above_ground, 0FFh
                jnz     short check_silkarn_shoes_and_slopes
                ; height_above_ground == 0
                mov     al, ds:ticks
                inc     ds:ticks
                and     al, 3           ; every 4th tick
                jz      short time_to_check_sliding_down ; ah: 0FF16h   ; Alt_Space
                                        ; al: 0FF17h   ; right_left_down_up
                retn
; ---------------------------------------------------------------------------

time_to_check_sliding_down:   
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                cmp     byte ptr ds:slope_direction, SLOPE_RIGHT
                je      short right_slope
                test    al, 1000b       ; left slope, check Right keypress
                je      short slide_off_leftwards
                retn                    ; right pressed on left slope - no slide
; ---------------------------------------------------------------------------

slide_off_leftwards:      
                jmp     move_hero_left_if_no_obstacles
; ---------------------------------------------------------------------------

right_slope:     
                test    al, 100b
                jz      short no_left_pressed
                retn                    ; left pressed on right slope - no slide
; ---------------------------------------------------------------------------

no_left_pressed: 
                jmp     move_hero_right_if_no_obstacles
; ---------------------------------------------------------------------------

check_silkarn_shoes_and_slopes: 
                mov     al, ds:current_accessory
                cmp     al, SHOES_SILKARN
                jne     short no_silkarn_shoes_slide_off_slope
                retn                    ; silkarn shoes - no slide
; ---------------------------------------------------------------------------

no_silkarn_shoes_slide_off_slope:
                dec     ds:height_above_ground
                cmp     byte ptr ds:slope_direction, SLOPE_RIGHT
                jne     short loc_6AC6
                jmp     move_hero_right_if_no_obstacles
; ---------------------------------------------------------------------------

loc_6AC6:        
                jmp     move_hero_left_if_no_obstacles
slope_assist_on_landing endp


; Handles DOWN key press.
; - If on slope: do nothing (slope_direction != 0).
; - Try move_platform_down_damage_monster (lower active platform).
; - If rope above feet: dismount rope (on_rope_flags = 0x80, jump = 0x80).
; - If on ground: set squat_flag = 0xFF (crouching).
; ===========================================================================
down_pressed    proc near 
                mov     ds:byte_9F18, 0
                test    byte ptr ds:slope_direction, 0FFh
                jz      short climb_off_rope_to_ground
                retn
; ---------------------------------------------------------------------------

climb_off_rope_to_ground: 
                call    move_platform_down_damage_monster
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 109         ; 3*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                call    is_over_rope    ; set CF if [si] is rope (0 or 1)
                jb      short loc_6B04  ;
                                        ; no more over rope
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_6AF9  ;
                                        ; was on rope
                mov     byte ptr ds:on_rope_flags, 80h ; ff -> 80h
                                        ; transition rope -> ground
                mov     byte ptr ds:jump_phase_flags, 80h ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                retn
; ---------------------------------------------------------------------------

loc_6AF9:        
                mov     ds:frame_ticks, 0
                mov     byte ptr ds:squat_flag, 0FFh
                retn
; ---------------------------------------------------------------------------

loc_6B04:        
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 109         ; 3*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                inc     byte ptr ds:hero_animation_phase
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jz      short loc_6B1E
                or      byte ptr ds:hero_animation_phase, 1
                retn
; ---------------------------------------------------------------------------

loc_6B1E:        
                call    hero_scroll_down
                call    main_update_render
                test    byte ptr ds:hero_animation_phase, 1
                jz      short loc_6B2C
                retn
; ---------------------------------------------------------------------------

loc_6B2C:        
                jmp     short loc_6B04
down_pressed    endp


; =============== S U B R O U T I N E =======================================

; hero_scroll_down() {
;   viewport_top_row_y++;
;   viewport_left_top_addr += 36;
;   if (viewport_left_top_addr >= 0xE900) viewport_left_top_addr -= 0x900;
; }
hero_scroll_down proc near
                inc     byte ptr ds:viewport_top_row_y ; hero goes down
                mov     si, ds:viewport_left_top_addr ; viewport goes down too
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     ds:viewport_left_top_addr, si
                retn
hero_scroll_down endp


; =============== S U B R O U T I N E =======================================


land_after_jump proc near 
                mov     al, ds:jump_phase_flags ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                xor     al, 7Fh  ; 00=>7F
                jz      short loc_6B49
                retn  ; return to main_loop (after call airborne_movement, to state_machine_dispatcher); repeats while idle
; ---------------------------------------------------------------------------

loc_6B49:       ; descending -> landing
                pop     ax              ; discard return address, will return to main_loop label (skip state_machine_dispatcher)
                mov     dl, ds:jump_height_counter ; =2
                mov     byte ptr ds:jump_phase_flags, 0 ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     ds:frame_ticks, 0
                mov     ds:jump_height_counter, 0
                mov     byte ptr ds:hero_animation_phase, 80h
                test    byte ptr ds:slope_direction, 0FFh
                jz      short loc_6B6A
                retn  ; no squats on slope
; ---------------------------------------------------------------------------

loc_6B6A:        
                cmp     dl, 2
                jnb     short squat_after_landing_from_big_height
                retn
; ---------------------------------------------------------------------------

squat_after_landing_from_big_height: ; for heights >= 2
                mov     byte ptr ds:squat_flag, 0FFh
                retn
land_after_jump endp


; =============== S U B R O U T I N E =======================================
; CF if cannot move down
check_floor_for_landing proc near
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI (=e10c)
                add     si, 3*36+1      ; directly under feet (=e179)
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     di, si
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying) (=CF ZF)
                                              ; AL = monster.flags (=4)
                add     al, al          ; destroyable walls have bit 7 set (=8)
                jnc     short loc_6B89  ; v (NC)
                retn                    ; destroyable wall under feet, can't move down
loc_6B89:        
                dec     si              ; one tile left beneath hero (=e178)
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying) (=CF ZF)
                                              ; AL = monster.flags (=4)
                add     al, al          ; destroyable walls have bit 7 set (=8)
                jnc     short loc_6B92  ; v (NC)
                retn                    ; destroyable wall under feet, can't move down
loc_6B92:        
                mov     si, di          ; (=e179)
                mov     al, [si]        ; (=4)
                call    is_blocking_tile_simple ; (CF NZ AL=0); NZ=blocking
                stc
                jz      short loc_6B9D ; no jump
                retn
loc_6B9D:        
                cmp     byte ptr ds:hero_animation_phase, 80h
                clc
                jne     short loc_6BA6
                retn
loc_6BA6:        
                dec     si
                mov     al, [si]
                call    is_blocking_tile_simple
                clc
                jnz     short loc_6BB0
                retn
loc_6BB0:        
                inc     si
                inc     si
                mov     al, [si]
                call    is_blocking_tile_simple
                stc
                jz      short loc_6BBB
                retn
loc_6BBB:        
                clc
                retn
check_floor_for_landing endp


; =============== S U B R O U T I N E =======================================

; set CF if [si] is rope (0 or 1)

is_over_rope    proc near 
                mov     al, [si]
                dec     al              ; al=1 or 2
                cmp     al, 2           ; al=0,1 => CF
                retn
is_over_rope    endp


; =============== S U B R O U T I N E =======================================

; NZ: no slope
; ZF dl=1: right slope \
; ZF dl=2: left slope /
; Checks tile at [si] (hero feet position in proximity map).
; Searches seg1:8018h (left-slope table, up to 4 entries) and
; seg1:801Ch (right-slope table, up to 4 entries).
; Returns: ZF=1, dl=2 → left slope (/); ZF=1, dl=1 → right slope (\).
; Returns: NZ → not a slope tile.
get_slope_direction_by_tile_under_feet proc near ; ...
                mov     es, cs:seg1
                mov     al, [si]        ; tile under hero feet
                mov     di, 8018h       ; 0xB, 0, 0, 0 - left slope tile defined as 0xb
                mov     dl, 2           ; try left slope
                mov     cx, 4

loc_6BD3:        
                test    byte ptr es:[di], 0FFh
                jz      short no_left_slope_defined
                cmp     al, es:[di]
                jnz     short loc_6BDF
                retn                    ; hero stays on left slope
; ---------------------------------------------------------------------------

loc_6BDF:        
                inc     di
                loop    loc_6BD3

no_left_slope_defined:    
                mov     di, 801Ch       ; 0xC, 0, 0, 0 - right slope tile defined as 0xc
                mov     dl, 1           ; try right slope
                mov     cx, 4

loc_6BEA:        
                test    byte ptr es:[di], 0FFh
                jz      short no_right_slope_defined
                cmp     al, es:[di]
                jnz     short loc_6BF6
                retn                    ; hero stays on right slope
; ---------------------------------------------------------------------------

loc_6BF6:        
                inc     di
                loop    loc_6BEA

no_right_slope_defined:   
                or      dl, dl          ; NZ if no slope
                retn
get_slope_direction_by_tile_under_feet endp


; ===========================================================================
; Scans the accomplished_items_checker_table (MDT-embedded).
; For each entry: reads a savegame byte and checks a bitmask.
; If condition is met (item was already collected / boss defeated):
;   Iterates a list of (address, value) pairs and writes them to the monsters
;   table — effectively removing collected items or opening doors in memory.
; This reconciles the savegame state with the current MDT's monster list.
; ===========================================================================
remove_accomplished_items proc near
                mov     si, ds:accomplished_items_checker_table

next_item:       
                mov     di, [si]        ; addr to check against the mask
                cmp     di, 0FFFFh
                jnz     short loc_6C08
                retn
; ---------------------------------------------------------------------------

loc_6C08:        
                add     si, 3
                mov     al, [si-1]      ; mask to check
                and     al, [di]        ; boss defeated?
                jnz     short move_loop

skip_loop:       
                mov     di, [si]
                cmp     di, 0FFFFh
                jz      short loc_6C2F
                add     si, 4
                jmp     short skip_loop
; ---------------------------------------------------------------------------

move_loop:       
                mov     di, [si]        ; =c013, d65e,
                cmp     di, 0FFFFh
                jz      short loc_6C2F
                mov     ax, [si+2]
                mov     [di], ax
                add     si, 4
                jmp     short move_loop
; ---------------------------------------------------------------------------

loc_6C2F:        
                inc     si
                inc     si
                jmp     short next_item
remove_accomplished_items endp


; ===========================================================================
; render_place_and_gold_labels
; Renders the 'PLACE' and 'GOLD' text labels on the HUD bar (non-boss cavern).
; Uses hard-coded Pascal strings with pixel positions.
; ===========================================================================
render_place_and_gold_labels proc near
                mov     si, offset byte_6C44
                call    cs:Render_Pascal_String_0_proc
                mov     si, offset byte_6C4C
                call    cs:Render_Pascal_String_0_proc
                retn
render_place_and_gold_labels endp

; ---------------------------------------------------------------------------
byte_6C44       db 0Dh                  ; marginLeft
                db 0BBh                 ; marginTop
                db    1
aGold           db 4,'GOLD'
byte_6C4C       db 0Dh                  ; marginLeft
                db 0AFh                 ; marginTop
                db    1
aPlace          db 5,'PLACE'


; ===========================================================================
; render_hud_bars_with_enemy
; Sets up the HUD layout for boss encounters.
; Draws two HUD bar areas, copies a screen region, and renders the 'ENEMY' label.
; Called on boss cavern init and Jashiin cavern init.
; ===========================================================================
render_hud_bars_with_enemy proc near
                mov     bx, 210h
                xor     al, al
                mov     ch, 21h ; '!'
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                mov     bx, 2310h
                mov     al, 80h
                mov     ch, 67h ; 'g'
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                mov     bx, 0AA9h
                mov     dx, 0AB5h
                mov     cx, 0E03h
                call    cs:Copy_Screen_Rect_VRAM_proc
                mov     bx, 21Ch
                xor     al, al
                mov     ch, 42h ; 'B'
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                mov     si, offset byte_6C8F
                jmp     cs:Render_Pascal_String_0_proc
render_hud_bars_with_enemy endp

; ---------------------------------------------------------------------------
byte_6C8F       db 0Dh                  ; marginLeft
                db 0AFh                 ; marginTop
                db    2
aEnemy          db 5,'ENEMY'


; ===========================================================================
; Decompresses the column-RLE packed dungeon map into the 36×64 proximity map.
;
; The packed map (at packed_map_start in the MDT data) stores each column of
; 64 tile-rows as a sequence of RLE tokens. Column order is left-to-right.
;
; Steps:
;   1. Skip proximity_map_left_col_x columns (decompress to /dev/null).
;      Saves the pointer as packed_map_ptr_for_prox_left.
;   2. Decompress 36 columns into proximity_map[0..35].
;      Each column: call unpack_column (calls unpack_step_forward in a loop).
;      X wraps around mapWidth (circular world).
;   3. Save pointer as packed_map_ptr_for_prox_right.
;   4. Compute viewport_left_top_addr from viewport_top_row_y.
;
; ENCODING (4 cases based on high 2 bits of first byte):
;   00xxxxxx count_byte, tile_byte  → repeat tile (count+1) times
;   01xxxxxx nibble_encoded         → short RLE: count=(hi nibble)+2, tile=(lo+1)
;   10xxxxxx empty_count            → 0-tile run of (byte & 0x3F) rows
;   11xxxxxx single_tile            → 1 occurrence of tile (byte & 0x3F)
; ===========================================================================
unpack_map      proc near 
                mov     si, offset packed_map_start ; unpack to /dev/null by columns, until the hero_x-18 position (proximity map left edge)
                mov     cx, ds:proximity_map_left_col_x
                or      cx, cx
                jz      short loc_6CB2

columns_skip_loop:        
                xor     dh, dh          ; rows counter

loc_6CA5:        
                call    unpack_step_forward
                inc     si
                add     dh, bh
                cmp     dh, 64          ; last row?
                jb      short loc_6CA5
                loop    columns_skip_loop

loc_6CB2:        
                mov     ds:packed_map_ptr_for_prox_left, si ; unpack 36 columns from the hero_x_minus_18
                mov     di, offset proximity_map ; unpacked proximity map
                mov     ax, ds:proximity_map_left_col_x ; in absolute map coords
                mov     cx, 36          ; proximity map width

columns_loop:    
                push    di
                call    unpack_column
                pop     di
                inc     di
                inc     ax              ; x++
                cmp     ax, ds:mapWidth
                jnz     short loc_6CD1
                mov     si, offset packed_map_start ; continue from x=0 (map start)
                xor     ax, ax          ; x = 0

loc_6CD1:        
                loop    columns_loop    ; fill 36 columns
                or      ax, ax          ; x in absolute map coords
                jnz     short loc_6CDB  ;
                                        ; last column of map unpacked
                mov     si, ds:packed_map_end_ptr

loc_6CDB:        
                dec     si
                mov     ds:packed_map_ptr_for_prox_right, si
                mov     al, ds:viewport_top_row_y ; 3d
                xor     ah, ah
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     ds:viewport_left_top_addr, di
                retn
unpack_map      endp


; ===========================================================================
; Decode one RLE token from the packed map stream.
; Output: BH = repeat count, BL = tile value.
; 'forward' increments SI (for left→right decompression).
; 'backward' decrements SI (for right→left decompression when scrolling).
; Dispatch via a 4-entry function pointer table based on high 2 bits.
; ===========================================================================
unpack_step_forward proc near 
                mov     bl, [si]        ; 0,4,8,C
                and     bl, 0C0h
                rol     bl, 1
                rol     bl, 1
                xor     bh, bh
                add     bx, bx
                jmp     ds:funcs_6CFA[bx]
unpack_step_forward endp

; ---------------------------------------------------------------------------
funcs_6CFA      dw offset unpack_forward_case0
                dw offset unpack_case1
                dw offset unpack_case2
                dw offset unpack_case3

; =============== S U B R O U T I N E =======================================


unpack_step_backward proc near
                mov     bl, [si]
                and     bl, 0C0h
                rol     bl, 1
                rol     bl, 1
                xor     bh, bh
                add     bx, bx
                jmp     ds:funcs_6D13[bx]
unpack_step_backward endp

; ---------------------------------------------------------------------------
funcs_6D13      dw offset unpack_backward_case0
                dw offset unpack_case1
                dw offset unpack_case2
                dw offset unpack_case3

; =============== S U B R O U T I N E =======================================


unpack_forward_case0 proc near
                mov     bh, [si]        ; 00...... ........
                inc     bh              ; count = (byte & 3fh)+1
                inc     si
                mov     bl, [si]        ; tile = next_byte
                retn
unpack_forward_case0 endp


; =============== S U B R O U T I N E =======================================


unpack_backward_case0 proc near 
                mov     bl, [si]        ; only works if tile < 0x40
                dec     si
                mov     bh, [si]
                inc     bh
                retn
unpack_backward_case0 endp


; =============== S U B R O U T I N E =======================================


unpack_case1    proc near 
                mov     bl, [si]
                mov     bh, bl
                shr     bh, 1
                shr     bh, 1
                shr     bh, 1
                shr     bh, 1
                and     bh, 3
                add     bh, 2
                and     bl, 0Fh
                inc     bl
                retn
unpack_case1    endp


; =============== S U B R O U T I N E =======================================


unpack_case2    proc near 
                mov     bh, [si]
                and     bh, 3Fh
                xor     bl, bl
                retn
unpack_case2    endp


; =============== S U B R O U T I N E =======================================


unpack_case3    proc near 
                mov     bl, [si]
                and     bl, 3Fh
                mov     bh, 1
                retn
unpack_case3    endp


; ===========================================================================
; Decompresses one full column (64 rows) into the proximity map.
; Input: SI = packed map pointer; DI = proximity_map + col_offset
; Writes each tile BH times at [DI], DI += 36 per row.
; Loops until 64 rows are filled (DL accumulates row count).
; ===========================================================================
unpack_column   proc near 
                xor     dl, dl          ; y=0

loc_6D59:        
                call    unpack_step_forward
                inc     si
                add     dl, bh          ; column height

loc_6D5F:        
                mov     [di], bl
                add     di, 36
                dec     bh
                jnz     short loc_6D5F
                cmp     dl, 64          ; 64 rows
                jb      short loc_6D59
                retn
unpack_column   endp


; =============== S U B R O U T I N E =======================================

; uint8_t y = AL
; uint8_t x = AH
; y &= 0x3F;
; uint16_t di = (y * 36) + x + 0xE000;
; ===========================================================================
; Converts relative (x, y) coordinates within proximity map to an address.
; AL = y (0-63), AH = x (0-35); y masked to 6 bits.
; DI = (y & 0x3F) * 36 + x + 0xE000
; Frequently used by all collision, monster placement, and spell code.
; ===========================================================================
coords_in_ax_to_proximity_map_addr_in_di proc near ; ...
                push    bx
                and     al, 3Fh         ; y
                mov     bl, ah          ; x
                mov     bh, 36
                mul     bh              ; 36*y
                xor     bh, bh
                add     ax, bx
                add     ax, offset proximity_map
                mov     di, ax
                pop     bx
                retn
coords_in_ax_to_proximity_map_addr_in_di endp


; =============== S U B R O U T I N E =======================================

; if (si >= 0E900h) si -= 900h

; ===========================================================================
; wrap_map_from_above / wrap_map_from_below
; Maintain the circular 36×64 proximity map buffer (0xE000–0xE8FF).
; wrap_map_from_above: if SI >= 0xE900, subtract 0x900 (wrap past bottom).
; wrap_map_from_below: if SI <  0xE000, add    0x900 (wrap past top).
; Called after every SI offset adjustment
; ===========================================================================
wrap_map_from_above proc near 
                cmp     si, proximity_map + 36*64
                jnb     short loc_6D89
                retn
; ---------------------------------------------------------------------------

loc_6D89:        
                sub     si, 36*64
                retn
wrap_map_from_above endp


; =============== S U B R O U T I N E =======================================

; if (si < 0E000h) si += 900h

wrap_map_from_below proc near 
                cmp     si, proximity_map
                jb      short loc_6D95
                retn
; ---------------------------------------------------------------------------

loc_6D95:        
                add     si, 36*64
                retn
wrap_map_from_below endp


; ===========================================================================
; set_zero_flag_if_slippery
; Returns ZF=1 (slippery) if cavern_level == 4 (ice dungeon) AND hero is
; not wearing Ruzeria shoes (current_accessory != SHOES_RUZERIA).
; Used by sliding_physics_step and init_horizontal_sliding.
; ===========================================================================
set_zero_flag_if_slippery proc near
                cmp     byte ptr ds:cavern_level, 4 ; danger type: slippery ground
                je      short loc_6DA2
                retn                    ; NZ
; ---------------------------------------------------------------------------

loc_6DA2:        
                cmp     byte ptr ds:current_accessory, SHOES_RUZERIA
                jne     short no_ruzeria
                mov     al, 0FFh
                or      al, al
                retn                    ; NZ
; ---------------------------------------------------------------------------

no_ruzeria:      
                xor     al, al
                retn                    ; ZF
set_zero_flag_if_slippery endp


; =============== S U B R O U T I N E =======================================

; Hero is 3x3 matrix. Return top-left coord in SI
; // viewport left border starts +4 columns from the proximity map left edge
; uint16_t si = viewport_left_top_addr + 4 + hero_head_y_in_viewport * 36 + hero_x_in_viewport;
; if (si >= 0xE900) si -= 0x900;
; return si;
; ===========================================================================
; Returns SI = proximity map address of hero's top-left 8×8 tile.
; Formula: SI = viewport_left_top_addr + (hero_head_y_in_viewport * 36)
;              + hero_x_in_viewport + 4
; The +4 accounts for the 4-column dead-zone at the left edge of the
; proximity map (proximity is 36 wide, viewport is 28 wide, offset = 4).
; hero_x_in_viewport is normally 0x0C (column 12 = center).
; Result is wrapped through wrap_map_from_above.
; ===========================================================================
hero_coords_to_addr_in_proximity proc near
                mov     al, ds:hero_head_y_in_viewport ; =0xa
                mov     cl, 36
                mul     cl              ; =0x168
                mov     cl, ds:hero_x_in_viewport ; =0xc
                add     cl, 4           ; =0x10; viewport left border starts +4 columns from the proximity map left edge
                xor     ch, ch
                add     ax, cx          ; =0x178
                mov     si, ax
                add     si, ds:viewport_left_top_addr ; (+e894 = EA0C)
                jmp     short wrap_map_from_above ; if (si >= 0E900h) si -= 900h; (=E10C)
hero_coords_to_addr_in_proximity endp


; =============== S U B R O U T I N E =======================================

; CF: no monster
; NC: active monster; al=type, bx=monster struct

; ===========================================================================
; Reads one byte from the proximity map at [SI].
; If bit 7 is clear: CF=1 (no monster/item).
; If bit 7 is set: the low 7 bits are a monster_index (0-127).
;   Looks up monsters_table_addr + index*16 to get the monster struct.
;   CF if no monster/item
;   NC if monster/item; AL = monster.flags; BX = monster struct
; ===========================================================================
get_dst_monster_flags proc near 
                mov     al, [si]
                test    al, 80h
                stc
                jnz     short monster_there
                retn                    ; CF, ZF if no monster/item
; ---------------------------------------------------------------------------
monster_there:   
                and     al, 7Fh         ; monster id
                mov     cl, 10h         ; 16 bytes per monster
                mul     cl
                mov     bx, ax
                add     bx, ds:monsters_table_addr
                mov     al, [bx+monster.flags]
                or      al, al  ; NC; NZ if non-passable monster (non-flying); ZF if flying monster
                retn
get_dst_monster_flags endp


; =============== S U B R O U T I N E =======================================

; ZF if can pass

; ===========================================================================
; is_blocking_tile family
; Three variants checking whether a tile index in AL can be passed through.
;
; is_blocking_tile (fastest):
;   AL < 0x40 → lookup in 24-byte passable-tile table at seg1:8000h.
;   AL >= 0x40 → NZ (solid).
;
; is_blocking_tile_extended:
;   AL < 0x49 → table lookup.
;   Also checks bits 7:5 of AL for special cases (monster/item bytes 0x90-0x91).
;
; is_blocking_tile_simple:
;   AL < 0x49 → table lookup.
;   AL >= 0x80 → NZ (non-passable).
;
; The passable-tile table at seg1:8000h contains tile IDs like:
;   0x00 (air), 0x01/0x02 (rope), 0x08-0x19 (various walk-through tiles).
; Sets ZF=1 when passable, NZ when blocked.
; ===========================================================================
is_blocking_tile proc near
                cmp     al, 40h
                jb      short lookup_shared
                cmp     al, al
                retn                    ; ZF: can pass
is_blocking_tile endp


; =============== S U B R O U T I N E =======================================


is_blocking_tile_extended proc near
                cmp     al, 49h ; doors
                jb      short lookup_shared
                cmp     al, al
                retn                    ; ZF: can pass
; ---------------------------------------------------------------------------

lookup_shared:   
                push    di
                push    cx
                mov     es, cs:seg1
                mov     di, 8000h       ; 00 01 02 08  09 0A 0B 0C  0F 10 11 12  13 14 15 16  17 18 19 00  00 00 00 00
                mov     cx, 24
                repne scasb
                pop     cx
                pop     di
                jnz     short loc_6E07
                retn                    ; ZF: one of passable tiles
; ---------------------------------------------------------------------------

loc_6E07:        
                and     al, 9Fh
                cmp     al, 90h
                je      short cant_pass
                cmp     al, 91h
                je      short cant_pass
                and     al, 80h
                cmp     al, 80h
                retn
; ---------------------------------------------------------------------------

cant_pass:       
                mov     al, 0FFh
                or      al, al
                retn                    ; NZ: cannot pass
is_blocking_tile_extended endp


; =============== S U B R O U T I N E =======================================

; Return ZF if non-blocked, NZ if blocked.
is_blocking_tile_simple proc near
                cmp     al, 49h        ; =4
                jb      short loc_6E22 ; v
                cmp     al, al         ; ZF: can pass
                retn
; ---------------------------------------------------------------------------

loc_6E22:        
                push    di
                push    cx
                mov     es, cs:seg1
                mov     di, 8000h
                mov     cx, 24
                repne scasb ; cx=0, NZ
                pop     cx
                pop     di
                jnz     short loc_6E36 ; v
                retn  ; found within the passable tiles, return ZF
; ---------------------------------------------------------------------------
; not found: check for monster/item entity
loc_6E36:        
                and     al, 80h ; =0
                cmp     al, 80h ; 0 != 80h => NZ
                retn  ; ZF (passable) if monster or item ; =NZ
is_blocking_tile_simple endp


; ===========================================================================
; Reads keyboard state and decides which sword-swing mode to trigger.
;
; SPACE + Up + Down → downward thrust (sword_hit_type=2)
;   If not already held (down_thrust_held_flag): play SFX 4.
; SPACE latched (from previous frame) → normal or overhead swing:
;   - Scans 4×8-tile area in front of hero for monsters; if any found → overhead
;   - OR if Up is pressed → overhead swing (sword_hit_type=1)
;   - Otherwise → forward hit (sword_hit_type=0)
; Sets sword_swing_flag=0xFF to trigger apply_sword_hit_to_map_tiles.
; ===========================================================================
input_handling  proc near 
                test    byte ptr ds:sword_type, 0FFh ; sword present?
                jnz     short loc_6E43  ; ah: 0FF16h   ; Alt_Space
                                        ; al: 0FF17h   ; right_left_down_up
                retn                    ; no sword
; ---------------------------------------------------------------------------

loc_6E43:        
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    ah, 1
                jz      short sword_default ;
                                        ; space pressed
                test    byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jz      short sword_default ;
                                        ; space+up
                test    byte ptr ds:slope_direction, 0FFh
                jnz     short sword_default
                test    al, 10b         ; down
                jz      short sword_default ;
                                        ; space+up+down
                mov     byte ptr ds:sword_hit_type, 2 ; Ground downward thrust
                mov     byte ptr ds:sword_movement_phase, 2
                test    byte ptr ds:down_thrust_held_flag, 0FFh
                jz      short loc_6E70
                jmp     loc_6EF7 ; set_swing_latches (skip default body)
; ---------------------------------------------------------------------------

loc_6E70:        
                mov     byte ptr ds:down_thrust_held_flag, 0FFh
                mov     byte ptr ds:soundFX_request, 4
                jmp     short loc_6EF7 ; set_swing_latches (skip default body)
; ---------------------------------------------------------------------------

sword_default:   
                mov     byte ptr ds:down_thrust_held_flag, 0
                test    byte ptr ds:spacebar_latch, 0FFh
                jnz     short loc_6E89
                retn
; ---------------------------------------------------------------------------

loc_6E89:        
                test    byte ptr ds:sword_swing_flag, 0FFh
                jz      short loc_6E91
                retn
; ---------------------------------------------------------------------------

loc_6E91:        
                test    byte ptr ds:spell_active_flag, 0FFh
                jz      short loc_6E99
                retn
; ---------------------------------------------------------------------------

loc_6E99:        
                test    byte ptr ds:is_boss_cavern, 0FFh
                jnz     short loc_6ED6
                ; ordinary cavern path
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                sub     si, (4*36+3)        ; =E10C-(4*36+3) = E079
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xor     dl, dl
                mov     cx, 4
four_rows:       
                push    cx
                mov     cx, 8

row_of_eight_tiles:       
                push    cx
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags; BX = monster struct
                jc      short no_monster ; no monster
                ; CF: monster
                test    al, 01100000b
                jnz     short no_monster
                test    byte ptr [bx+monster.state_flags], 10h
                jnz     short no_monster
                mov     dl, 0FFh        ; monster found

no_monster:      
                inc     si
                pop     cx
                loop    row_of_eight_tiles
                add     si, (36-8)
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                pop     cx
                loop    four_rows
                or      dl, dl
                jnz     short loc_6EDC

loc_6ED6:       ; common path for boss caverns and ordinary caverns
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 1
                jz      short no_up_pressed ;
                                        ; up pressed

loc_6EDC:        
                mov     byte ptr ds:sword_hit_type, 1 ; Overhead swing
                mov     byte ptr ds:sword_movement_phase, 0
                jmp     short loc_6EF2
; ---------------------------------------------------------------------------

no_up_pressed:   
                mov     byte ptr ds:sword_hit_type, 0 ; Forward hit
                mov     byte ptr ds:sword_movement_phase, 0

loc_6EF2:        
                mov     byte ptr ds:soundFX_request, 3

loc_6EF7:       ; set_swing_latches
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                mov     byte ptr ds:sword_swing_flag, 0FFh
                retn
input_handling  endp



; ===========================================================================
; Called every frame while sword_swing_flag is set.
; Walks the sword reachability table (at seg1:sword_reachability_lists) to
; determine which proximity map offsets the sword tip can reach.
; Table index = (facing_dir * 16) + sword_movement_phase + swing_type_offset.
;   Forward hit:      al = phase | (dir * 16)
;   Overhead swing:   al = phase | (dir * 16) | 6
;   Downward thrust:  al = dir * 16 + 10
; For each tile offset in the table: if a live monster is present (via
; get_dst_monster_flags), sets monster.ai_flags |= 0x41 (hit marker bit 6 + type 1).
; ===========================================================================
apply_sword_hit_to_map_tiles proc near
                test    byte ptr ds:sword_swing_flag, 0FFh
                jnz     short loc_6F0F
                retn
; ---------------------------------------------------------------------------

loc_6F0F:        
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_6F1E
                test    byte ptr ds:boss_being_hit, 0FFh
                jz      short loc_6F1E
                retn
; ---------------------------------------------------------------------------

loc_6F1E:        
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                mov     bx, 4*36
                test    byte ptr ds:squat_flag, 0FFh
                jz      short loc_6F2E
                mov     bx, 3*36

loc_6F2E:        
                sub     si, bx ; 3 or 4 rows above the hero
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     bl, ds:facing_direction
                and     bl, 1
                add     bl, bl
                add     bl, bl
                add     bl, bl
                add     bl, bl   ; dir*16
                mov     al, ds:sword_hit_type ; 0=Forward hit, 1=Overhead swing, 2=Ground downward thrust
                mov     ah, 0
                or      al, al
                jz      short loc_6F57
                ; not forward hit
                mov     ah, 6
                dec     al
                jz      short loc_6F57 ; overhead swing
                ; ground downward thrust
                mov     al, bl
                add     al, 10         ; dir*16+10
                jmp     short loc_6F5E ; al=10 or 26
; ---------------------------------------------------------------------------
loc_6F57:                              ; forward hit (ah=0) or overhead swing (ah=6)
                mov     al, ds:sword_movement_phase
                or      al, bl         ; dir*16 + phase => 0..4 or 16..20
                add     al, ah         ; 0..4, 6..9, 16..20 or 22..25
loc_6F5E:
                and     al, 0FEh        ; clear bit 0
                mov     bl, al
                xor     bh, bh
                mov     es, cs:seg1
                mov     di, es:sword_reachability_lists[bx]

loc_6F6E:
                mov     al, es:[di] ; offset to next tile in proximity window, that is reachable by the sword
                inc     di
                cmp     al, 0FFh ; reachability list terminator
                jne     short loc_6F77
                retn
; ---------------------------------------------------------------------------

loc_6F77:        
                xor     ah, ah
                add     si, ax
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags; BX = monster struct
                jc      short loc_6F6E ; CF: no monster/item
                test    al, 20h        ; flags bit 5: cannot be hit
                jnz     short loc_6F6E
                test    byte ptr [bx+monster.ai_flags], 20h
                jnz     short loc_6F6E ; ai_flags bit 5: cannot be hit
                or      byte ptr [bx+monster.ai_flags], 40h ; hit marker: ai_flags bit 6
                and     byte ptr [bx+monster.ai_flags], 0E0h
                or      byte ptr [bx+monster.ai_flags], 1   ; ai_flags bit 0: monster processed, its AI can react
                jmp     short loc_6F6E
apply_sword_hit_to_map_tiles endp


; ===========================================================================
; Master simulation + render tick called every frame.
;
; Simulation phase:
;   - Feruza shoes → jump_height_including_shoes = 4 (else 2).
;   - check_airflows_on_hero — detect and apply wind tunnel tiles.
;   - If not airborne: reset byte_9F09 (fall sub-step counter).
;   - Re-center hero if hero_x_in_viewport drifts from 0x0C.
;   - Compute hero_y_absolute = (hero_head_y_in_viewport + viewport_top_row_y) & 0x3F.
;   - update_boss_heartbeat_volume
;   - update_and_render_horiz_platforms
;   - render_vertical_platforms_to_proximity
;   - process_visible_collapsing_platforms
;   - process_doors
;   - dispatch_spell_projectile_movement
;   - monsters_spawning  (unless boss is already dead)
;   - check_hero_contact_damage
;   - Flush UI dirty element
;   - projectiles_collision_processing
;   - monsters_updates  (render)
;   - step_on_aggressive_ground
;   - Temperature damage (cavern_level 7 = heat, every 0x40 ticks, 0x0F damage)
;     Protected by CAPE_ASBESTOS.
;   - screen_flash_overlay
; ===========================================================================
main_update_render proc near  
                mov     al, 2
                cmp     byte ptr ds:current_accessory, SHOES_FERUZA
                jnz     short no_feruza
                mov     al, 4

no_feruza:       
                mov     ds:jump_height_including_shoes, al
                call    check_airflows_on_hero
                test    byte ptr ds:jump_phase_flags, 0FFh ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jnz     short loc_6FD3
                mov     ds:byte_9F09, 0
                mov     al, ds:byte_9F00
                cmp     al, ds:hero_head_y_in_viewport
                jz      short loc_6FD3
                jb      short loc_6FCC
                call    move_hero_up
                inc     byte ptr ds:hero_head_y_in_viewport
                jmp     short loc_6FD3
; ---------------------------------------------------------------------------

loc_6FCC:        
                call    hero_scroll_down
                dec     byte ptr ds:hero_head_y_in_viewport

loc_6FD3:        
                test    byte ptr ds:is_jashiin_cavern, 0FFh
                jnz     short loc_6FE1
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_6FF9

loc_6FE1:        
                mov     si, ds:boss_state_block_ptr
                add     si, 7
                mov     al, [si]
                cmp     ds:hero_x_in_viewport, al
                jz      short loc_7007
                call    move_hero_right_if_no_obstacles
                dec     byte ptr ds:hero_x_in_viewport
                jmp     short loc_7007
; ---------------------------------------------------------------------------

loc_6FF9:        
                mov     al, ds:hero_x_in_viewport
                cmp     al, 0Ch
                jz      short loc_7007
                call    move_hero_left_if_no_obstacles
                inc     byte ptr ds:hero_x_in_viewport

loc_7007:        
                mov     al, ds:hero_head_y_in_viewport ; hanging on rope, head at ground level: 0a
                add     al, ds:viewport_top_row_y ; 40h
                and     al, 3Fh
                mov     ds:hero_y_absolute, al ; hero Y absolute coord within the map
                call    update_boss_heartbeat_volume
                call    update_and_render_horiz_platforms
                call    render_vertical_platforms_to_proximity
                call    process_visible_collapsing_platforms
                call    process_doors
                call    dispatch_spell_projectile_movement
                test    byte ptr ds:boss_is_dead, 0FFh
                jnz     short loc_702F
                call    monsters_spawning

loc_702F:        
                mov     byte ptr ds:hero_damage_this_frame, 0
                mov     ds:byte_9F14, 0
                call    check_hero_contact_damage
                call    cs:Flush_Ui_Element_If_Dirty_proc
                call    projectiles_collision_processing
                call    monsters_updates
                call    cs:Render_Sword_Overlay_proc
                call    step_on_aggressive_ground
                cmp     byte ptr ds:cavern_level, 7 ; danger type = temperature
                jne     short skip_temperature_damage
                cmp     byte ptr ds:current_accessory, CAPE_ASBESTOS
                jz      short skip_temperature_damage
                inc     ds:temperature_timer
                test    ds:temperature_timer, 3Fh
                jnz     short skip_temperature_damage
                mov     byte ptr ds:hero_damage_this_frame, 0FFh
                mov     byte ptr ds:soundFX_request, 9
                mov     ax, 0Fh
                call    damage_hero     ; ax: damage level
                mov     dx, offset its_too_hot_str
                call    render_notification_string

skip_temperature_damage:  
                call    screen_flash_overlay
                test    byte ptr ds:invincibility_flag, 0FFh
                jz      short game_loop_render_and_timing
                mov     byte ptr ds:hero_damage_this_frame, 0
                jmp     short loc_7094 ; invincibility entry point
main_update_render endp


; ===========================================================================
; Rendering + timing portion of the per-frame cycle.
;
; Rendering sequence:
;   1. Shield/spell overlay active flag → shield_anim_active + shield_variant_index.
;   2. If hero_sprite_hidden: clear hero viewport area.
;   3. Sample_Neighborhood_Attributes — build attribute cache for viewport tiles.
;   4. Healing potion timer: +8 HP/tick while active.
;   5. Refresh_Dirty_Tiles — redraw tile changes to VRAM.
;   6. If sprite_flash_flag: Boss_Explosions_Renderer (enp/fman sprites).
;
; Frame-rate timing:
;   Wait until frame_timer >= speed_const*2, then continue:
;   7. monsters_updates (second pass — commit sprite positions).
;   8. Flush UI dirty element.
;   9. update_and_render_projectile_row_pair.
;   10. render_and_collision_pass_row.
;   11. update_active_projectiles_render.
;   12. apply_sword_hit_to_map_tiles.
;   13. Render_Sword_Overlay.
;   Wait again until frame_timer >= speed_const*4.
;
; Post-render checks:
;   - If hero HP == 0 and not invincible: process_hero_death.
;   - Passive HP regen: +2 HP every 16 slow-intervals.
;   - Boss death reward: update XP + almas when boss_is_dead fires.
;   - Handle inventory (ENTER key) → bring_inventory_window.
; ===========================================================================
game_loop_render_and_timing proc near
                mov     byte ptr ds:hero_sprite_hidden, 0

loc_7094:       ; invincibility entry point
                mov     byte ptr ds:shield_anim_active, 0
                test    byte ptr ds:sword_swing_flag, 0FFh
                jz      short loc_70B3
                mov     byte ptr ds:shield_anim_active, 0FFh
                mov     al, ds:sword_hit_type
                mov     ds:shield_variant_index, al ; during sword swing, shield_variant_index = sword_hit_type
                mov     al, ds:sword_movement_phase
                mov     ds:shield_anim_phase, al ; during sword swing, shield_anim_phase = sword_movement_phase
                jmp     short loc_70CA
; ---------------------------------------------------------------------------

loc_70B3:        
                test    byte ptr ds:spell_active_flag, 0FFh
                jz      short loc_70CA
                mov     byte ptr ds:shield_anim_active, 0FFh
                mov     al, ds:byte_9F2B
                mov     ds:shield_anim_phase, al
                mov     byte ptr ds:shield_variant_index, 1 ; during spell, shield_variant_index = 1

loc_70CA:        
                test    byte ptr ds:hero_sprite_hidden, 0FFh
                jnz     short loc_70D4
                call    clear_hero_in_viewport

loc_70D4:        
                call    cs:Sample_Neighborhood_Attributes_proc
                test    byte ptr ds:invincibility_flag, 0FFh
                jnz     short loc_710F
                mov     ax, ds:healing_potion_timer
                or      ax, ax
                jz      short loc_710F
                dec     ax
                mov     ds:healing_potion_timer, ax
                add     word ptr ds:hero_HP, 8   ; faster hp restoration
                mov     ax, ds:heroMaxHp
                cmp     ax, ds:hero_HP
                jnb     short loc_7105
                mov     ax, ds:heroMaxHp
                mov     ds:hero_HP, ax
                mov     word ptr ds:healing_potion_timer, 0

loc_7105:        
                mov     byte ptr ds:soundFX_request, 19
                call    cs:Draw_Hero_Health_proc

loc_710F:        
                call    cs:Refresh_Dirty_Tiles_proc
                test    byte ptr ds:sprite_flash_flag, 0FFh
                jz      short loc_7125
; combine 3x3 body, 3x3 left hand (with or without shield), 3x3 right hand from fman.grp
; with optional 4x4 sword from sword.grp into complete hero image, depending on animation phase
                call    cs:Boss_Explosions_Renderer_proc
                mov     byte ptr ds:byte_FF24, 0Ah

loc_7125:        
                mov     cl, ds:speed_const
                mov     al, 2
                mul     cl

loc_712D:        
                cmp     ds:frame_timer, al
                jb      short loc_712D
                call    monsters_updates
                call    cs:Flush_Ui_Element_If_Dirty_proc
                call    update_and_render_projectile_row_pair
                call    render_and_collision_pass_row
                call    update_active_projectiles_render
                call    apply_sword_hit_to_map_tiles
                call    cs:Render_Sword_Overlay_proc
                mov     cl, ds:speed_const
                mov     al, 4
                mul     cl

loc_7154:        
                push    ax
                call    cs:Confirm_Exit_Dialog_proc
                call    cs:Handle_Pause_State_proc
                call    cs:Handle_Speed_Change_proc
                call    cs:Joystick_Calibration_proc
                call    cs:Joystick_Deactivator_proc
                call    cs:Handle_Restore_Game_proc
                jnb     short loc_7178
                call    restore_game

loc_7178:        
                pop     ax
                cmp     ds:frame_timer, al
                jb      short loc_7154
                mov     byte ptr ds:frame_timer, 0
                test    byte ptr ds:invincibility_flag, 0FFh
                jz      short loc_718C
                retn
; ---------------------------------------------------------------------------

loc_718C:        
                test    byte ptr ds:hero_invincibility, 0FFh
                jnz     short increase_hp
                test    word ptr ds:hero_HP, 0FFFFh
                jnz     short increase_hp
                jmp     process_hero_death
; ---------------------------------------------------------------------------

increase_hp:     
                inc     ds:byte_9F18
                cmp     ds:byte_9F18, 16 ; increase hero HP by 2 every 16 time intervals
                jb      short loc_71C2
                mov     ds:byte_9F18, 0
                mov     ax, ds:hero_HP
                cmp     ax, ds:heroMaxHp
                jnb     short loc_71C2
                add     ax, 2           ; normal HP restoration speed
                mov     ds:hero_HP, ax
                call    cs:Draw_Hero_Health_proc

loc_71C2:        
                test    ds:byte_9F1E, 0FFh
                jz      short loc_71CC
                jmp     load_place_and_reinit
; ---------------------------------------------------------------------------

loc_71CC:        
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_71FA
                test    byte ptr ds:boss_is_dead, 0FFh
                jz      short loc_71FA
                cmp     byte ptr ds:boss_explosion_rings_list, 0FFh
                jne     short loc_71FA
                mov     si, ds:boss_state_block_ptr
                add     si, 5
                lodsw  ; xp_reward
                push    si
                call    update_hero_XP
                pop     si
                add     si, 4 ; almas_reward
                lodsw
                call    hero_got_almas  ; ax: almas to add
                mov     ds:byte_9F1E, 0FFh

loc_71FA:        
                test    byte ptr ds:boss_being_hit, 0FFh
                jz      short loc_7202
                retn
; ---------------------------------------------------------------------------

loc_7202:        
                test    word ptr ds:F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter, KEY_ENTER
                jnz     short bring_inventory_window
                mov     ds:byte_9EF5, 0
                retn
game_loop_render_and_timing endp


; ===========================================================================
; screen_flash_overlay
; Handles two overlay effects in the viewport buffer:
;   byte_9EF0 path: wide panel flash (sign display area, 18 tiles wide × byte_9EF1 rows).
;                   Fills viewport_buffer rows starting at row 2 with 0xFC/0xFE markers.
;   byte_9EEF path: narrow 2-row flash (notification bar at rows 2-3, 26 tiles).
;                   Used for item pickup notifications and boss-hit flash.
; Both flash effects decay after 0x1F ticks (byte_9EEE/byte_9EED counters).
; The 0xFC/0xFE tile IDs are special 'overlay' values recognized by the renderer.
; ===========================================================================
screen_flash_overlay proc near
                test    ds:byte_9EF0, 0FFh
                jz      short loc_7242
                mov     al, 0FCh
                inc     ds:byte_9EEE
                test    ds:byte_9EEE, 1Fh
                jnz     short loc_722B
                mov     al, 0FEh
                mov     ds:byte_9EF0, 0

loc_722B:        
                push    cs
                pop     es
                mov     di, viewport_buffer_28x19+(28+5) ; row 1, col 5 (0-based)
                mov     cl, ds:byte_9EF1  ; num rows to set
                xor     ch, ch

loc_7236:        
                push    cx
                mov     cx, 18
                rep stosb      ; set columns 5..22 to 0xFC/0xFE
                add     di, 10
                pop     cx
                loop    loc_7236

loc_7242:        
                test    ds:byte_9EEF, 0FFh
                jnz     short loc_724A
                retn
; ---------------------------------------------------------------------------

loc_724A:        
                mov     al, 0FCh
                inc     ds:byte_9EED
                and     ds:byte_9EED, 1Fh
                jnz     short loc_725E
                mov     al, 0FEh
                mov     ds:byte_9EEF, 0

loc_725E:        
                push    ds
                pop     es
                mov     di, viewport_buffer_28x19+(2*28+1) ; row 2, col 1 (0-based)
                mov     cx, 2

fill_viewport_2_lines:    
                push    cx
                push    di
                mov     cx, 26  ; fill rows 2 and 3, columns 1..26; leave columns 0 and 27 untouched
                rep stosb
                pop     di
                add     di, 28
                pop     cx
                loop    fill_viewport_2_lines
                retn
screen_flash_overlay endp


; ===========================================================================
; Opens the inventory/equipment screen when ENTER is pressed.
; Preconditions: no active spell, no screen effect, not in intro animation.
;
; 1. Play SFX 11.
; 2. swap_eai_and_inventory_code_regions: XOR-swap 0x800 words between
;    the enemy AI region (0xA000) and inventory region (seg1:0xC000).
;    This temporarily replaces the live AI code with select.bin code.
; 3. Call Inventory_Screen_proc.
; 4. Swap back.
; 5. If byte_FF4B == 8 (save/load from inventory): jmp to resurrection code.
; 6. Reload magic spell sprites, clear viewport, reinit.
; ===========================================================================
bring_inventory_window proc near
                mov     al, ds:byte_9EF5
                or      al, ds:spell_active_flag
                or      al, ds:byte_FF3E
                or      al, ds:byte_9F26
                jz      short loc_7287
                retn
; ---------------------------------------------------------------------------

loc_7287:        
                mov     byte ptr ds:soundFX_request, 11
                call    cs:Clear_Viewport_proc
                call    swap_eai_and_inventory_code_regions
                call    cs:Inventory_Screen_proc
                call    swap_eai_and_inventory_code_regions
                cmp     byte ptr ds:byte_FF4B, 8 ; use of Kioku Feather teleports to Muralla sage
                jnz     short loc_72A6
                jmp     transit_to_sage
; ---------------------------------------------------------------------------

loc_72A6:        
                call    cs:Clear_Viewport_proc
                push    ds
                call    word ptr cs:Load_Magic_Spell_Sprite_Group_proc
                mov     cx, 24
                call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                pop     ds
                mov     ds:byte_9EF5, 0FFh
                call    clear_viewport_buffer
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                mov     ds:byte_9EEF, 0
                mov     ds:byte_9EF0, 0
                jmp     main_update_render
bring_inventory_window endp


; ===========================================================================
; XOR-swaps 0x800 words (2KB each) between:
;   - ES:0xA000 (eai{N}.bin enemy AI code, in CS segment)
;   - ES:0xC000 (select.bin inventory code, in CS segment)
; After the swap: Monster_AI_proc at 0xA000 now runs the inventory screen.
; swap_eai_and_inventory_code_regions is idempotent (double-swap restores).
; ===========================================================================
swap_eai_and_inventory_code_regions proc near
                mov     es, cs:seg1 ; =1ac5
                mov     di, 0C000h      ; select.bin region (inventory)
                mov     si, 0A000h      ; eai{i}.bin region (enemy AI)
                mov     cx, 800h

loc_72E7:        
                mov     ax, es:[di]
                movsw
                mov     [si-2], ax
                loop    loc_72E7
                retn
swap_eai_and_inventory_code_regions endp


; ===========================================================================
; Called when boss_is_dead fires and the game needs to transition the cavern
; from boss mode back to post-boss state.
;
; 1. Load saved monsters AI binary (eai from mdt_descriptor.boss_ai) → 0xA000.
; 2. Load boss enp sprite group (from mdt_descriptor.enp_grp_idx).
; 3. Decompress boss monster tiles.
; 4. Clear is_boss_cavern flag.
; 5. Process optional initializers from MDT (list of word writes).
; 6. Update hero X position, recalculate door tile, call process_doors.
; 7. Reinit cavern display, jump back to Cavern_Game_Init.
; ===========================================================================
load_place_and_reinit proc near 
                test    byte ptr ds:invincibility_flag, 0FFh
                jz      short loc_72F9
                retn
; ---------------------------------------------------------------------------

loc_72F9:        
                mov     si, ds:mdt_buffer    ; mdt_buffer[0] is mdt_descriptor_addr; [C000]=C20A
                add     si, mdt_descriptor.boss_ai
                lodsb  ; saved eai_bin_index
                push    si
                    mov     ds:eai_bin_index, al ; enemy ai restored with saved value
                    mov     bl, 11
                    mul     bl
                    add     ax, offset eai1_bin
                    mov     si, ax
                    push    cs
                    pop     es
                    mov     di, 0A000h      ; destination buffer
                    mov     al, 3           ; fn3_read_virtual_file
                    call    cs:res_dispatcher_proc
                pop     si
                lodsb                   ; mdt_descriptor.enp_grp_idx
                mov     ds:enp_grp_index, al
                mov     bl, 11
                mul     bl
                add     ax, offset vfs_enp1_grp
                mov     si, ax
                mov     es, cs:seg1
                mov     di, monster_gfx
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                push    ds
                mov     ds, cs:seg1
                mov     si, monster_gfx
                mov     bp, monsters_transparency_masks
                mov     cx, 100h
                call    cs:Decompress_Tile_Data_proc
                pop     ds
                mov     byte ptr ds:is_boss_cavern, 0
                mov     si, ds:mdt_buffer  ; mdt_buffer[0] is mdt_descriptor_addr
                add     si, 8          ; mdt_descriptor+8 is post-boss initializers (addr - value pairs)

next_optional_initializer: ; addr, value pairs
                lodsw
                cmp     ax, 0FFFFh
                jz      short end_of_initializers ;
                                        ; if not ffff: optional initializers follow
                mov     bx, ax          ; address to init
                lodsw                   ; 16 bit word to write
                mov     [bx], ax
                jmp     short next_optional_initializer
; ---------------------------------------------------------------------------

end_of_initializers:    
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                mov     ax, ds:proximity_map_left_col_x
                mov     bl, ds:hero_x_in_viewport
                xor     bh, bh
                add     ax, bx
                test    byte ptr [si-5], 0FFh
                jz      short loc_737C
                add     ax, 9

loc_737C:        
                mov     bx, ax
                sub     bx, ds:mapWidth
                jc      short loc_7386
                mov     ax, bx

loc_7386:        
                mov     si, ds:doors_table_addr
                mov     [si], ax
                call    process_doors
                call    screen_flash_overlay
                call    clear_hero_in_viewport
                call    cs:Render_Viewport_Tiles_proc
                mov     bx, 21Ch
                xor     al, al
                mov     ch, 42h
                call    cs:Clear_HUD_Bar_proc
                mov     ax, 1  ; fn1 (Stop) Silences all channels and halts the driver.
                int     60h             ; mscadlib.drv
                mov     ds:byte_9F1E, 0
                jmp     Cavern_Game_Init
load_place_and_reinit endp


; ===========================================================================
; Fills the 28×19 viewport_buffer (at 0xE900h) with 0xFD.
; 0xFD means 'undrawn tile' — forces a full redraw next render pass.
; ===========================================================================
clear_viewport_buffer proc near 
                push    cs
                pop     es
                mov     di, viewport_buffer_28x19
                mov     cx, 28*19
                mov     al, 0FDh
                rep stosb
                retn
clear_viewport_buffer endp


; ===========================================================================
; Searches for tile value AL in the 4-byte 'aggressive ground' list at
; seg1:8020h. These are the tile IDs that hurt the hero when stood upon
; (e.g., lava, spikes), set per-dungeon in the mpp?.grp descriptor.
; Input: AL = tile value to search for.
; Returns: ZF=1 (not safe - match found) or NZ (AH=0xFF, no match, safe).
; ===========================================================================
is_tile_safe_to_stay proc near
                push    di
                mov     es, cs:seg1
                mov     di, offset aggressive_ground_list
                mov     cx, 4

loc_73CC:        
                mov     ah, es:[di]
                inc     di
                or      ah, ah
                jz      short loc_73DA ; end of list
                cmp     ah, al
                je      short loc_73DE ; match found
                loop    loc_73CC

loc_73DA:        
                mov     ah, 0FFh
                or      ah, ah

loc_73DE:        
                pop     di
                retn
is_tile_safe_to_stay endp


; ===========================================================================
; render_notification_string
; Displays a short pickup/event notification in the centre of the screen.
; Input: DX → pointer to a Pascal-like length-prefixed string.
; Draws a bordered rectangle, then renders the text.
; Sets byte_9EEF=0xFF to trigger the 2-row flash overlay for 0x1F ticks.
; ===========================================================================
render_notification_string proc near    ; ...
                push    si
                push    dx
                mov     bx, 0E1Eh
                mov     cx, 3410h
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                mov     ds:byte_9EED, 0
                mov     ds:byte_9EEF, 0FFh
                mov     ds:byte_9EEE, 0FFh
                pop     si
                lodsw
                add     ax, 3Ah ; ':'
                mov     bx, ax
                mov     cl, 22h ; '"'
                call    cs:Render_String_FF_Terminated_proc ; BX: starting x coord
                                        ; CL: starting y coord
                                        ; SI: string pointer
                pop     si
                retn
render_notification_string endp


; ===========================================================================
; render_cavern_signs
; Renders multi-line in-dungeon sign text.
; Input: SI → sign descriptor: [x_offset, num_lines, (x_delta, text...0xFF)...].
; Calls Render_Font_Glyph_proc for each character, '/' triggers newline.
; Draws a bordered rectangle sized to the text.
; ===========================================================================
render_cavern_signs proc near 
                lodsb
                add     al, 19h
                mov     cl, al
                push    cx
                lodsb
                push    si
                add     al, 2
                mov     ds:byte_9EF1, al
                mov     bl, 8
                mul     bl
                mov     bx, 1616h
                mov     ch, 24h ; '$'
                mov     cl, al
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                pop     si
                mov     ds:byte_9EED, 0
                mov     ds:byte_9EEF, 0
                mov     ds:byte_9EEE, 0
                mov     ds:byte_9EF0, 0FFh
                mov     bx, 58h ; 'X'
                pop     cx

loc_7446:        
                mov     ds:word_9EF2, bx
                mov     ds:byte_9EF4, cl
                lodsb
                xor     ah, ah
                add     bx, ax

loc_7453:        
                lodsb
                cmp     al, 0FFh
                jnz     short loc_7459
                retn
; ---------------------------------------------------------------------------

loc_7459:        
                cmp     al, 2Fh ; '/'
                jz      short loc_746F
                mov     ah, 1
                push    cx
                push    bx
                push    si
                call    cs:Render_Font_Glyph_proc ; AL: ASCII character code
                                        ; AH: Palette/colour index
                                        ; BX: X pixel coordinate in framebuffer
                                        ; CX: Y pixel coordinate (row)
                                        ; CS:0xFF77: Flag: 0 = normal colour mode, nonzero = "bright/highlight" mode
                pop     si
                pop     bx
                pop     cx
                add     bx, 8
                jmp     short loc_7453
; ---------------------------------------------------------------------------

loc_746F:        
                mov     bx, ds:word_9EF2
                mov     cl, ds:byte_9EF4
                add     cl, 0Ch
                jmp     short loc_7446
render_cavern_signs endp


; ===========================================================================
; Erases the hero's 3×3 tile area in the viewport buffer by writing 0xFF.
; 0xFF is the 'hero slot' sentinel — tells the renderer to draw the hero
; sprite (fman.grp 24×24 px) at this position instead of a map tile.
; ===========================================================================
clear_hero_in_viewport proc near
                mov     al, ds:hero_head_y_in_viewport
                mov     cl, 28
                mul     cl              ; ax=viewport_row_start
                mov     cl, ds:hero_x_in_viewport
                xor     ch, ch
                add     ax, cx
                add     ax, viewport_buffer_28x19
                mov     di, ax
                push    cs
                pop     es
                mov     al, 0FFh
                mov     cx, 3

three_tiles:     
                stosb                   ; hero occupies 3x3 bytes in viewport buffer
                stosb
                stosb
                add     di, 28-3
                loop    three_tiles
                retn
clear_hero_in_viewport endp


; ===========================================================================
; Deals damage to the hero if standing on harmful tiles.
; Pirika shoes grant immunity.
; Scans the hero's bottom 2-3 rows (squatting: +1 row) by calling
; is_tile_safe_to_stay on each tile.
; Also checks the tile directly under the hero centre.
; If any match: set hero_damage_this_frame, play SFX 9, deal damage.
; Damage table aggressive_tiles_damage_table: per cavern_level (1,1,4,8,20,20,20,20,20).
; ===========================================================================
step_on_aggressive_ground proc near
                cmp     byte ptr ds:current_accessory, SHOES_PIRIKA
                jnz     short no_pirika_shoes ; hero feets get hurting
                retn
; ---------------------------------------------------------------------------

no_pirika_shoes: 
                mov     ds:danger_found, 0
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                mov     cx, 3
                test    byte ptr ds:squat_flag, 0FFh
                jz      short loc_74C1
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                dec     cx

loc_74C1:        
                push    cx
                mov     cx, 3

three_times:     
                push    cx
                mov     al, [si]
                inc     si
                call    is_tile_safe_to_stay
                jnz     short loc_74D3
                mov     ds:danger_found, 0FFh

loc_74D3:        
                pop     cx
                loop    three_times
                add     si, 33          ; 36-3
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                pop     cx
                loop    loc_74C1
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jnz     short loc_74F3
                inc     si
                mov     al, [si]
                call    is_tile_safe_to_stay
                jnz     short loc_74F3
                mov     ds:danger_found, 0FFh

loc_74F3:        
                test    ds:danger_found, 0FFh
                jnz     short loc_74FB
                retn
; ---------------------------------------------------------------------------

loc_74FB:        
                mov     byte ptr ds:hero_damage_this_frame, 0FFh
                mov     byte ptr ds:soundFX_request, 9
                mov     bl, ds:cavern_level
                dec     bl
                xor     bh, bh
                mov     al, ds:aggressive_tiles_damage_table[bx]
                xor     ah, ah
                jmp     damage_hero     ; ax: damage level
step_on_aggressive_ground endp

; ---------------------------------------------------------------------------
aggressive_tiles_damage_table       db 1, 1, 4, 8, 20, 20, 20, 20, 20 ; ...

; ===========================================================================
; Per-frame check: does the hero overlap any live monster?
; Skipped in boss caverns while boss is actively attacking.
;
; Scans a 4-tile column to the left and right of the hero (4 slots each).
; For each slot: calls get_monster_in_row_or_above (or loc_7651 when squatting).
; If monster found: calls apply_hit_from_left or apply_hit_from_right.
;
; Results stored in word_9F0E/9F10 (knockback direction vectors).
; byte_9F14 set to 0xFF if any monster hit was recorded.
; Updates shield HP display if hit occurred.
; ===========================================================================
check_hero_contact_damage proc near     ; ...
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_752E
                test    byte ptr ds:boss_being_hit, 0FFh
                jz      short loc_752E
                retn
; ---------------------------------------------------------------------------

loc_752E:        
                mov     ds:accumulated_contact_damage, 0
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                dec     si
                mov     di, offset word_9F0E
                mov     bx, offset loc_7651
                test    byte ptr ds:squat_flag, 0FFh
                jnz     short loc_754E
                mov     bx, offset get_monster_in_row_or_above
                sub     si, 36
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h

loc_754E:        
                push    bx
                push    di
                push    si
                call    bx ; get_monster_in_row_or_above
                sbb     al, al
                mov     [di], al
                jz      short loc_755C
                call    apply_hit_from_left

loc_755C:        
                pop     si
                pop     di
                pop     bx
                inc     si
                inc     di
                push    bx
                push    di
                push    si
                call    bx ; get_monster_in_row_or_above
                jb      short loc_756B
                call    get_monster_one_row_above

loc_756B:        
                sbb     al, al
                mov     [di], al
                jz      short loc_7574
                call    apply_hit_from_left

loc_7574:        
                pop     si
                pop     di
                pop     bx
                inc     si
                inc     di
                push    bx
                push    di
                push    si
                call    bx ; get_monster_in_row_or_above
                jb      short loc_7583
                call    get_monster_one_row_above

loc_7583:        
                sbb     al, al
                mov     [di], al
                jz      short loc_758C
                call    apply_hit_from_right

loc_758C:        
                pop     si
                pop     di
                pop     bx
                inc     si
                inc     di
                call    bx ; get_monster_in_row_or_above
                sbb     al, al
                mov     [di], al
                jz      short loc_759C
                call    apply_hit_from_right

loc_759C:        
                mov     di, offset word_9F0E
                mov     al, [di]
                or      al, [di+1]
                or      al, [di+2]
                or      al, [di+3]
                mov     ds:byte_9F14, al
                mov     ds:hero_damage_this_frame, al
                or      al, al
                jz      short locret_75B9
                call    cs:Print_ShieldHP_Decimal_proc

locret_75B9:     
                retn
check_hero_contact_damage endp


; ===========================================================================
; apply_hit_from_left / apply_hit_from_right
; Applies monster contact damage after determining shield blocking.
;
; Shield blocks only when facing TOWARD the attacking monster:
;   from_left: hero must face LEFT (facing_direction bit 0 = 1).
;   from_right: hero must face RIGHT.
; Shield absorbs damage = base_damage / 2 / 2^(shield_tier).
; If shield_HP goes negative: destroy shield, then deal remaining damage.
; Without shield: full damage_hero + SFX 9.
; With shield: reduced damage_hero + SFX 8.
; ===========================================================================
apply_hit_from_left proc near 
                test    byte ptr ds:invincibility_flag, 0FFh
                jz      short loc_75C2
                retn
; ---------------------------------------------------------------------------

loc_75C2:        
                mov     ax, ds:accumulated_contact_damage
                test    byte ptr ds:facing_direction, LEFT
                jz      short no_shield ; hero faced right (opposite direction) => shield useless
                jmp     short loc_75E2
apply_hit_from_left endp


apply_hit_from_right proc near
                test    byte ptr ds:invincibility_flag, 0FFh
                jz      short loc_75D6
                retn
; ---------------------------------------------------------------------------

loc_75D6:        
                mov     ax, ds:accumulated_contact_damage
                test    byte ptr ds:facing_direction, LEFT
                jnz     short no_shield ; hero faced left (opposite direction) => shield useless
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_75E2:        
                test    byte ptr ds:shield_type, 0FFh
                jz      short no_shield
                shr     ax, 1
                mov     cl, ds:shield_type
                inc     cl
                shr     cl, 1
                shr     ax, cl
                sub     ds:shield_HP, ax ; shield absorbs AX damage
                jb      short shield_destroyed
                jnz     short hero_absorbs_damage

shield_destroyed:
                push    ax
                call    destroy_shield
                mov     word ptr ds:shield_HP, 0
                pop     ax

hero_absorbs_damage:      
                call    damage_hero     ; ax: damage level
                mov     byte ptr ds:soundFX_request, 8
                retn
; ---------------------------------------------------------------------------

no_shield:       
                call    damage_hero     ; ax: damage level
                mov     byte ptr ds:soundFX_request, 9
                retn
apply_hit_from_right endp


; ===========================================================================
; destroy_shield
; Clears shield_type to 0, wipes the shield HP bar area on HUD,
; draws a small bordered rectangle, shows 'Shield broken.' notification.
; ===========================================================================
destroy_shield  proc near 
                mov     byte ptr ds:shield_type, 0
                mov     bx, 0C51Ch
                mov     al, 0FFh
                mov     ch, 18h
                call    cs:Clear_HUD_Bar_proc
                mov     bx, 3EA3h
                mov     cx, 511h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                mov     dx, offset shield_broken_str
                jmp     render_notification_string
destroy_shield  endp


; =============== S U B R O U T I N E =======================================


get_monster_in_row_or_above proc near
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags
                jc      short loc_764B
                test    al, 40h
                jnz     short loc_764B
                and     al, 0Fh
                jmp     short loc_7675
; ---------------------------------------------------------------------------

loc_764B:        
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h

loc_7651:        
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags
                jc      short get_monster_one_row_above
                test    al, 40h
                jnz     short get_monster_one_row_above
                and     al, 0Fh
                jmp     short loc_7675
get_monster_in_row_or_above endp


; =============== S U B R O U T I N E =======================================


get_monster_one_row_above proc near
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags
                cmc
                jc      short loc_766B
                retn
; ---------------------------------------------------------------------------

loc_766B:        
                clc
                test    al, 40h
                jz      short loc_7671
                retn
; ---------------------------------------------------------------------------

loc_7671:        
                and     al, 0Fh
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_7675:        
                mov     bl, al
                xor     bh, bh
                mov     al, ds:byte_A010[bx]
                xor     ah, ah
                add     ds:accumulated_contact_damage, ax
                stc
                retn
get_monster_one_row_above endp


; =============== S U B R O U T I N E =======================================

; ax: damage level
damage_hero     proc near 
                sub     ds:hero_HP, ax
                jnb     short loc_7691
                mov     word ptr ds:hero_HP, 0

loc_7691:        
                push    si
                call    cs:Draw_Hero_Health_proc
                pop     si
                retn
damage_hero     endp


; =============== S U B R O U T I N E =======================================


check_airflows_on_hero proc near
                mov     ds:air_up_tile_found, 0
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 2*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     cx, 3

check_across_hero_height: 
                push    cx
                call    dispatch_airflows
                sub     si, 36
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                pop     cx
                loop    check_across_hero_height
                retn
check_airflows_on_hero endp


; =============== S U B R O U T I N E =======================================


dispatch_airflows proc near   
                mov     al, [si]
                push    si
                call    get_airflow_direction ; Is input tile an airflow?
                                        ; Input: al
                                        ; Output:
                                        ; NZ, cl=0xff (no airflow)
                                        ; ZF, cl=0 (Up), 1 (Left), 2 (Right)
                pop     si
                jz      short airflow_detected
                retn
; ---------------------------------------------------------------------------

airflow_detected:
                pop     ax
                pop     ax
                mov     bl, cl
                xor     bh, bh
                add     bx, bx          ; switch 3 cases
                jmp     ds:airflows_table[bx] ; switch jump
dispatch_airflows endp

; ---------------------------------------------------------------------------
airflows_table  dw offset airflow_up
                dw offset airflow_left
                dw offset airflow_right
; ---------------------------------------------------------------------------

airflow_up:      
                call    move_hero_up
                call    move_hero_up
                mov     ds:air_up_tile_found, 0FFh
                mov     byte ptr ds:jump_phase_flags, 0 ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     byte ptr ds:hero_animation_phase, 80h
                retn
; ---------------------------------------------------------------------------

airflow_right:   
                call    move_hero_right_if_no_obstacles
                jmp     move_hero_right_if_no_obstacles
; ---------------------------------------------------------------------------

airflow_left:    
                call    move_hero_left_if_no_obstacles
                jmp     move_hero_left_if_no_obstacles

; =============== S U B R O U T I N E =======================================

; Is input tile an airflow?
; Input: al
; Output:
; NZ, cl=0xff (no airflow)
; ZF, cl=0 (Up), 1 (Left), 2 (Right)

get_airflow_direction proc near 
                or      al, al
                jz      short default
                mov     es, cs:seg1 ; 1ac5
                mov     bh, al
                xor     cl, cl          ; check for airflow Up
                mov     si, 8024h
                mov     bl, 4

category0_check_loop:     
                mov     al, es:[si]
                inc     si
                or      al, al
                jz      short category0_break_on_0
                cmp     al, bh
                jnz     short loc_7715
                retn                    ; found airflow Up
; ---------------------------------------------------------------------------

loc_7715:        
                dec     bl
                jnz     short category0_check_loop

category0_break_on_0:     
                inc     cl              ; check for airflow Left
                mov     si, 8028h
                mov     bl, 4

loc_7720:        
                mov     al, es:[si]
                inc     si
                or      al, al
                jz      short category1_break_on_0
                cmp     al, bh
                jnz     short loc_772D
                retn                    ; found airflow Left
; ---------------------------------------------------------------------------

loc_772D:        
                dec     bl
                jnz     short loc_7720

category1_break_on_0:     
                inc     cl              ; check for airflow Right
                mov     si, 802Ch
                mov     bl, 4

loc_7738:        
                mov     al, es:[si]
                inc     si
                or      al, al
                jz      short default
                cmp     al, bh
                jnz     short loc_7745
                retn                    ; found airflow Right
; ---------------------------------------------------------------------------

loc_7745:        
                dec     bl
                jnz     short loc_7738

default:         
                mov     cl, 0FFh
                or      cl, cl          ; NZ: no airflow, cl=0xff
                retn
get_airflow_direction endp


; =============== S U B R O U T I N E =======================================


update_boss_heartbeat_volume proc near
                mov     ax, ds:tear_x
                cmp     ax, 0FFFFh
                je      short distance_big
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.
                jc      short distance_big
                mov     al, ds:hero_x_in_viewport
                add     al, 4
                mov     ah, al
                sub     al, bl
                jnb     short abs_al
                neg     al

abs_al:          
                mov     bh, al
                sub     bl, ah
                jnb     short abs_bl
                neg     bl

abs_bl:          
                cmp     bl, bh
                jb      short min_bl_bh
                mov     bl, bh

min_bl_bh:       
                mov     ds:delta_x, bl
                mov     bl, ds:tear_y
                mov     bh, ds:hero_y_absolute
                mov     al, bh
                sub     al, bl
                and     al, 3Fh         ; wrap y
                sub     bl, bh
                and     bl, 3Fh
                cmp     bl, al
                jb      short min_al_bl
                mov     bl, al

min_al_bl:       
                mov     ds:delta_y, bl  ; dy
                cmp     ds:delta_x, 16
                jnb     short distance_big
                mov     al, ds:delta_x  ; dx
                mov     bx, offset squares
                xlat
                mov     dl, al          ; dx^2
                cmp     ds:delta_y, 16
                jnb     short distance_big
                mov     al, ds:delta_y
                mov     bx, offset squares
                xlat                    ; dy^2
                add     al, dl          ; dx^2+dy^2
                jb      short distance_big ; dist^2 > 255
                mov     bx, offset distance_attenuation
                xlat
                mov     ds:heartbeat_volume, al
                retn
; ---------------------------------------------------------------------------

distance_big:    
                mov     byte ptr ds:heartbeat_volume, 0
                retn
update_boss_heartbeat_volume endp

; ---------------------------------------------------------------------------
squares         db 0, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100, 121, 144, 169, 196, 225
distance_attenuation db 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Fh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh
                db 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Eh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh
                db 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Dh, 0Ch, 0Ch, 0Ch, 0Ch
                db 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch
                db 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ch, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah
                db 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 0Ah, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
                db 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6
                db 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6
                db 6, 6, 6, 6, 6, 6, 6, 6

; =============== S U B R O U T I N E =======================================


restore_game    proc near 
                mov     bx, 601Ch       ; far jump address to the town code (restore_game)
                jmp     transfer_to_town
restore_game    endp


; =============== S U B R O U T I N E =======================================


process_doors   proc near 
                mov     bp, ds:doors_table_addr

next_door:       
                mov     ax, ds:[bp+door.x0]
                cmp     ax, 0FFFFh      ; doors end marker
                jnz     short loc_78EB
                retn
; ---------------------------------------------------------------------------

loc_78EB:        
                call    calc_object_viewport_x_offset
                jb      short loc_7933
                mov     al, ds:[bp+door.d_flags]
                and     al, 7
                add     al, 61h ; 'a'
                mov     ds:byte_79B6, al
                mov     ds:byte_79CA, al
                mov     al, ds:[bp+door.y0]
                xor     ah, ah
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                cmp     bl, 4
                jb      short loc_7938
                mov     cx, bx
                sub     bl, 36+3
                neg     bl
                inc     bl
                mov     al, bl
                cmp     al, 6
                jb      short loc_791D
                mov     al, 5

loc_791D:        
                sub     cl, 4
                xor     ch, ch
                add     di, cx
                mov     si, offset opened_door_tiles
                test    ds:[bp+door.d_flags], 80h
                jnz     short loc_7951
                mov     si, offset closed_door_tiles
                jmp     short loc_7951
; ---------------------------------------------------------------------------

loc_7933:        
                add     bp, 0Ch
                jmp     short next_door
; ---------------------------------------------------------------------------

loc_7938:        
                mov     si, offset opened_door_tiles
                test    ds:[bp+door.d_flags], 80h
                jnz     short loc_7945
                mov     si, offset closed_door_tiles

loc_7945:        
                mov     al, bl
                inc     al
                mov     cl, 5
                sub     cl, al
                xor     ch, ch
                add     si, cx

loc_7951:        
                mov     cx, 4

four_times:      
                push    cx
                push    ax
                push    di
                push    si

al_times:        
                call    move_if_dst_high_bit_zero
                inc     di
                inc     si
                dec     al
                jnz     short al_times
                pop     si
                add     si, 5
                xchg    si, di
                pop     si
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    di, si
                pop     ax
                pop     cx
                loop    four_times
                jmp     short loc_7933
process_doors   endp


; =============== S U B R O U T I N E =======================================


move_if_dst_high_bit_zero proc near
                test    byte ptr [di], 80h
                jz      short loc_797C
                retn
loc_797C:        
                mov     dl, [si]
                mov     [di], dl
                retn
move_if_dst_high_bit_zero endp


; =============== S U B R O U T I N E =======================================


calc_object_viewport_x_offset proc near
                add     ax, 3           ; door.x0 + 3
                push    ax
                sub     ax, ds:mapWidth ; ax = door.x0 + 3 - mapWidth
                pop     bx              ; bx = door.x0 + 3
                jnb     short x_coord_wrapped
                xchg    ax, bx

x_coord_wrapped: 
                push    ax              ; wrappedX3
                sub     ax, ds:proximity_map_left_col_x ; ax = wrappedX3 - prox_left
                pop     bx              ; bx = wrappedX3
                jc      short loc_799C
                ; wrappedX3 >= prox_left
                xchg    ax, bx          ; bx = wrappedX3 - prox_left
                mov     ax, 36+3
                sub     ax, bx          ; ax = 39 + prox_left - wrappedX3
                retn    ; CF if (wrappedX3 > prox_left+39) ; outside the right edge
; ---------------------------------------------------------------------------

loc_799C:       ; wrappedX3 < prox_left
                mov     ax, 36+3
                sub     ax, bx          ; ax = 39 - wrappedX3
                jnc     short loc_79A4
                retn    ; CF if (wrappedX3 > 39) ; outside the left edge
; ---------------------------------------------------------------------------

loc_79A4:       ; wrappedX3 <= 39
                mov     ax, ds:mapWidth
                sub     ax, ds:proximity_map_left_col_x
                add     ax, bx          ; ax = mapWidth - prox_left + wrappedX3
                                        ; bx = wrappedX3
                xchg    ax, bx          ; bx = mapWidth - prox_left + wrappedX3
                mov     ax, 36+3
                sub     ax, bx          ; ax = 39 + prox_left - wrappedX3 - mapWidth
                retn    ; CF if (wrappedX3 > prox_left+39-mapWidth)
calc_object_viewport_x_offset endp

; ---------------------------------------------------------------------------
closed_door_tiles       db 49h, 4Ah   
byte_79B6       db 61h, 4Bh, 4Ch, 4Dh, 4Fh, 50h, 51h, 4Eh, 5Fh, 52h, 53h, 54h, 60h, 5Fh, 55h, 56h, 57h, 60h
opened_door_tiles       db 49h, 4Ah   
byte_79CA       db 61h, 4Bh, 4Ch, 4Dh, 58h, 0, 59h, 4Eh, 5Fh, 5Ah, 0, 5Bh, 60h, 5Fh, 5Ch, 5Dh, 5Eh, 60h

; =============== S U B R O U T I N E =======================================

; run from town to dungeon

prepare_dungeon proc near 
                cli
                mov     sp, 2000h
                sti
                mov     ax, cs
                mov     ds, ax
                mov     es, ax
                mov     di, offset byte_9EED
                mov     cx, offset byte_9F2E
                sub     cx, offset byte_9EED
                dec     cx              ; 0x9f2e-0x9eed-1 = 64
                xor     al, al
                rep stosb
                not     al
                mov     ds:byte_9EF5, al
                mov     ds:eai_bin_index, al
                mov     ds:enp_grp_index, al
                call    reset_dungeon_state_vars
                mov     al, 0FFh
                mov     ds:spirit_sprite_0, al
                mov     ds:spirit_sprite_1, al
                mov     ds:spirit_sprite_2, al
                mov     ds:spirit_sprite_3, al
                mov     byte ptr ds:hero_hidden_flag, 0
                mov     es, cs:seg1
                mov     si, offset vfs_fman_grp
                mov     di, fman_gfx
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                push    ds
                mov     ds, cs:seg1
                mov     si, fman_gfx + 333h  ; TILE_BANK_OFFSET = 0x333
                mov     bp, hero_transparency_masks
                mov     cx, 230
                call    cs:Decompress_Tile_Data_proc
                pop     ds
                mov     si, ds:mdt_buffer
                lodsb
                call    process_mdt_descriptor
                call    cs:Clear_Viewport_proc
                mov     si, offset vfs_roka_grp_2
                mov     es, cs:seg1
                mov     di, packed_tile_ptr
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                push    ds
                mov     ds, cs:seg1
                mov     si, packed_tile_ptr       ; roka_grp unpacked
                mov     cx, 80h
                call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                pop     ds
                xor     al, al
                call    cs:Render_Roca_Tilemap_proc
                mov     al, ds:place_map_id
                or      al, al
                js      short loc_7A80
                call    remove_accomplished_items
loc_7A80:        
                jmp     roka_run
prepare_dungeon endp


; =============== S U B R O U T I N E =======================================
; 49 4A 61 4B 4C
; 4D 58 00 59 4E
; 5F 5A 00 5B 60
; 5F 5C 5D 5E 60
; This matrix 5x4 tiles describes the door frame
try_door_interaction proc near
                call    hero_coords_to_addr_in_proximity
                sub     si, 36+1        ; x--, y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                cmp     byte ptr [si], 4Ah
                je      short on_the_right_door_tile ; hero is on the right tile of the door
                inc     si
                cmp     byte ptr [si], 4Ah
                je      short enter_the_door ; hero is centered on door
                inc     si
                cmp     byte ptr [si], 4Ah
                je      short on_the_left_door_tile
                retn
; ---------------------------------------------------------------------------

on_the_left_door_tile:    
                test    byte ptr ds:facing_direction, LEFT
                jz      short loc_7AA6
                retn                    ; faced left - skip door interaction
; ---------------------------------------------------------------------------

loc_7AA6:        
                pop     ax              ; drop return address
                jmp     move_hero_right_if_no_obstacles
; ---------------------------------------------------------------------------

on_the_right_door_tile:   
                test    byte ptr ds:facing_direction, LEFT
                jnz     short loc_7AB2
                retn                    ; faced right - skip door interaction
; ---------------------------------------------------------------------------

loc_7AB2:        
                pop     ax              ; drop return address
                jmp     move_hero_left_if_no_obstacles
; ---------------------------------------------------------------------------

enter_the_door:  
                mov     ax, ds:proximity_map_left_col_x ; proximity map left edge in the absolute map coords
                mov     bl, ds:hero_x_in_viewport
                add     bl, 4           ; viewport offset from proximity map margin
                xor     bh, bh
                add     ax, bx          ; ax = hero x absolute
                ; wrapping trick: if (ax >= mapWidth) ax -= mapWidth
                mov     bx, ds:mapWidth
                dec     bx
                sub     bx, ax
                jnb     short no_wrap
                not     bx
                mov     ax, bx
no_wrap:        ; wrapping done
                mov     bl, ds:hero_head_y_in_viewport
                dec     bl
                add     bl, ds:viewport_top_row_y
                and     bl, 3Fh         ; wrap vertically
                mov     si, ds:doors_table_addr

next_door1:       
                cmp     word ptr [si], 0FFFFh ; end of doors marker
                jnz     short loc_7AE8
                retn
; ---------------------------------------------------------------------------

loc_7AE8:        
                cmp     ax, [si+door.x0]
                jnz     short loc_7AF1
                cmp     bl, [si+door.y0]
                jz      short loc_7AF6

loc_7AF1:        
                add     si, 12
                jmp     short next_door1
; ---------------------------------------------------------------------------
; door coords match
loc_7AF6:        
                pop     ax              ; drop return address
                test    [si+door.d_flags], 80h ; door.d_flags bit 7 = open
                jnz     short enter_opened_door
                call    open_door
                jc      short loc_7B03
                retn ; NC = success
; ---------------------------------------------------------------------------

loc_7B03:        
                mov     byte ptr ds:hero_animation_phase, 80h
                mov     ds:horiz_movement_sub_tile_accum, 0
                test    ds:byte_9F19, 0FFh
                jz      short loc_7B15
                retn
; ---------------------------------------------------------------------------

loc_7B15:        
                mov     ds:byte_9F19, 0FFh
                mov     byte ptr ds:soundFX_request, 22
                mov     dx, offset cant_open_this_door_str
                jmp     render_notification_string
; ---------------------------------------------------------------------------
enter_opened_door:        
                mov     bx, [si+door.d_save_achievement_addr]
                cmp     bx, 0FFFFh
                je      short loc_7B32
                mov     al, [si+door.d_achievement_flag]
                or      [bx], al

loc_7B32:        
                push    si
                    call    Browse_Projectiles
                    call    clear_viewport_buffer
                    call    cs:Flush_Ui_Element_If_Dirty_proc
                    call    reset_dungeon_state_vars
                    call    game_loop_render_and_timing
                    mov     si, ds:monsters_table_addr
                    mov     word ptr [si], 0FFFFh ; end-of-monsters marker
                pop     si              ; doors struct
                mov     al, [si+door.d_flags]
                and     al, 111b
                push    ax
                    mov     ax, [si+door.x1]
                    mov     ds:hero_x_in_proximity_map, ax
                    mov     al, [si+door.y1]
                    mov     ds:door_target_y, al
                    mov     al, [si+door.d_flags]
                    and     al, 01000000b
                    mov     ds:is_left_run, al
                    mov     al, [si+door.d_features]
                    mov     ds:door_features, al
                    mov     ah, [si+door.d_place_map_id]
                    cmp     [si+door.y1], 0FFh
                    jne     short skip_if_cavern
                    or      ah, 80h         ; door leads to town

skip_if_cavern:  
                    mov     ds:place_map_id, ah ; cavern/town id
                    mov     al, 1           ; fn_1 Load mdt
                    call    cs:res_dispatcher_proc ; fn0_swap_town_vs_cavern_gfx_drv_and_jmp_bx
                                            ; fn1_load_mdt_idx_ah
                    
                    test    byte ptr ds:place_map_id, 80h
                    jnz     short skip_if_town ;
                                            ; place is cavern
                    call    remove_accomplished_items
skip_if_town:    
                    call    hero_left_16_down_1
                    mov     si, ds:mdt_buffer
                    lodsb   ; b7b6_msd_idx_b0
                    test    al, 1 ; current Resource Disk inserted
                    jnz     short loc_7BD0
                    mov     si, offset vfs_roka_grp_1
                    mov     es, cs:seg1
                    mov     di, packed_tile_ptr
                    mov     al, 2           ; fn2_segmented_load
                    call    cs:res_dispatcher_proc
                    push    ds
                    mov     ds, cs:seg1
                    mov     si, packed_tile_ptr
                    mov     cx, 80h
                    call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                    pop     ds
                pop     ax  ; door.d_flags & 7
                call    cs:Render_Roca_Tilemap_proc

                mov     ds:mman_grp_index, 0FFh
                mov     byte ptr ds:byte_FF24, 10
                jmp     short loc_7C02
; ---------------------------------------------------------------------------

loc_7BD0:        
                    mov     si, offset vfs_roka_grp_2
                    mov     es, cs:seg1
                    mov     di, packed_tile_ptr
                    mov     al, 2           ; fn2_segmented_load
                    call    cs:res_dispatcher_proc
                    push    ds
                    mov     ds, cs:seg1
                    mov     si, packed_tile_ptr
                    mov     cx, 80h
                    call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                    pop     ds
                pop     ax ; door.d_flags & 7
                call    cs:Render_Roca_Tilemap_proc

                mov     si, ds:mdt_buffer ; mdt_descriptor
                lodsb                   ; b7b6_msd_idx_b0
                call    process_mdt_descriptor

loc_7C02:        
                mov     byte ptr ds:hero_hidden_flag, 0
                mov     ds:byte_9EF5, 0FFh
                mov     byte ptr ds:projectiles_array, 0FFh
                test    ds:door_features, 80h
                jz      short roka_run
                ; after defeating the boss, play 'RokaDemo' animation
                mov     si, offset rokademo_bin
                push    cs
                pop     es
                mov     di, 0A000h      ; rokademo.bin loaded
                mov     al, 3           ; fn3_read_virtual_file
                call    cs:res_dispatcher_proc
                call    cs:roca_entrypoint
                ; then load the cavern
                mov     ds:enp_grp_index, 0FFh
                mov     ds:eai_bin_index, 0FFh
                mov     al, ds:msd_index
                mov     ds:byte_9EFA, al
                mov     ds:byte_9F02, 0FFh
                call    load_cavern_sprites_ai_music ; load dchr.grp
                                        ; load mpp{mpp_grp_index}.grp
                                        ; load eai{eai_bin_index}.bin
                                        ; load enp{enp_grp_index}.grp
                                        ; load mgt{mgt_msd_index}.msd
                mov     es, cs:seg1
                mov     si, offset vfs_fman_grp
                mov     di, fman_gfx
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                push    ds
                mov     ds, cs:seg1
                mov     si, fman_gfx + 333h  ; TILE_BANK_OFFSET = 0x333
                mov     bp, hero_transparency_masks
                mov     cx, 230
                call    cs:Decompress_Tile_Data_proc
                pop     ds
                jmp     after_run_animation
; ---------------------------------------------------------------------------
roka_run:        
                test    byte ptr ds:is_left_run, 0FFh
                jnz     short run_to_the_left
                and     byte ptr ds:facing_direction, 11111110b 
; run to the right
                mov     bx, 0A6Eh ; x=0Ah*4=48-8, y=6Eh; => hero starts with his left tile column hidden, 2 columns visible
                mov     cx, 26          ; 26 steps to animate

loc_7C80:        
                push    cx              ; animate hero running in cavern entrance
                push    bx
                inc     byte ptr ds:hero_animation_phase
                call    cs:Update_Local_Attribute_Cache_proc
                pop     bx
                add     bh, 2
                push    bx
                call    cs:Calculate_Tile_VRAM_Address_proc
                call    sleep_loop_handle_system_keys
                pop     bx
                push    bx
                mov     cx, 218h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                pop     bx
                pop     cx
                loop    loc_7C80        ; animate hero running in cavern entrance
                mov     cx, 618h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                jmp     short after_run_animation
; ---------------------------------------------------------------------------

run_to_the_left:     
                or      byte ptr ds:facing_direction, 1
                mov     bx, 406Eh ; x=40h*4=48+224-16, y=6Eh; => hero starts with his right tile column hidden, 2 columns visible
                mov     cx, 26          ; 26 steps to animate

loc_7CBF:        
                push    cx
                push    bx
                inc     byte ptr ds:hero_animation_phase
                call    cs:Update_Local_Attribute_Cache_proc
                pop     bx
                sub     bh, 2
                push    bx
                call    cs:Calculate_Tile_VRAM_Address_proc
                call    sleep_loop_handle_system_keys
                pop     bx
                push    bx
                add     bh, 4
                mov     cx, 218h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                pop     bx
                pop     cx
                loop    loc_7CBF
                mov     cx, 618h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
after_run_animation:        
                mov     si, ds:mdt_buffer  ; mdt_descriptor
                lodsb                      ; .b7b6_msd_idx_b0
                mov     ah, al
                and     al, 1              ; 0 ? town : dungeon
                jz      short loc_7D64
                ; dungeon init
                call    load_cavern_sprites_ai_music ; load dchr.grp
                                        ; load mpp{mpp_grp_index}.grp
                                        ; load eai{eai_bin_index}.bin
                                        ; load enp{enp_grp_index}.grp
                                        ; load mgt{mgt_msd_index}.msd
                mov     si, ds:mdt_buffer
                lodsb                   ; mdt_descriptor.b7b6_msd_idx_b0
                mov     ah, al
                add     ah, ah
                sbb     bl, bl          ; if ah bit 7 is set => bl = ff (boss cavern)
                mov     ds:is_boss_cavern, bl
                add     ah, ah
                sbb     bl, bl          ; if ah bit 6 was set => bl = ff (Jashiin cavern)
                mov     ds:is_jashiin_cavern, bl
                mov     byte ptr ds:boss_being_hit, 0
                mov     byte ptr ds:sprite_flash_flag, 0
                call    cs:Clear_Viewport_proc
                mov     byte ptr ds:hero_x_in_viewport, 0Ch
                mov     al, ds:hero_head_y_in_viewport_initial_from_mdt
                mov     ds:hero_head_y_in_viewport, al
                mov     ds:byte_9F00, al
                mov     byte ptr ds:hero_animation_phase, 80h ; state IDLE
                push    ds
                mov     ds, cs:seg1
                mov     si, 8030h
                mov     cx, 66h
                call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                call    cs:NoOperation_proc
                pop     ds
                push    ds
                call    word ptr cs:Load_Magic_Spell_Sprite_Group_proc ; Input: none (uses global current_magic_spell)
                                                                ; Reads corresponding sprite group fron seg2:0 buffer to seg1:9350h
                                                                ; Output: Loads sprite sheet for current_magic_spell
                                                                ; DS:SI -> seg1:9350h buffer

                mov     cx, 24
                call    cs:Reassemble_3_Planes_To_Packed_Bitmap_proc
                pop     ds
                jmp     Cavern_Game_Init
; ---------------------------------------------------------------------------
; town init
loc_7D64:        
                mov     si, ds:mdt_buffer
                inc     si
                lodsb                   ; mdt_descriptor.mman_grp_idx
                mov     bl, 11
                mul     bl
                add     ax, offset vfs_mman_grp
                mov     si, ax
                mov     es, cs:seg1
                mov     di, 4000h
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                mov     bx, 6000h       ; jump address to the town code

transfer_to_town:
                mov     ax, 1  ; fn1 (Stop) Silences all channels and halts the driver.
                int     60h             ; mscadlib.drv
                push    bx
                    call    edge_locking_scrolling_window ; Return:
                                            ; AX: proximity_map_left_col_x
                                            ; BL: hero_x_in_viewport
                    mov     ds:proximity_map_left_col_x, ax
                    mov     ds:hero_x_in_viewport, bl
                    mov     si, ds:mdt_buffer ; mdt_descriptor
                    lodsb                   ; b7b6_msd_idx_b0
                    shr     al, 1
                    and     al, 11111b
                    mov     ds:msd_index, al
                    mov     bl, 11
                    mul     bl
                    add     ax, offset vfs_mgt1_msd
                    mov     si, ax
                    mov     es, cs:seg1
                    mov     di, 3000h
                    mov     al, 5           ; fn5_load_music
                    call    cs:res_dispatcher_proc
                pop     bx               ; bx points to one of town entries
                xor     al, al           ; fn0_swap_town_vs_cavern_gfx_drv_and_jmp_bx
                jmp     cs:res_dispatcher_proc ; on return will jump to the town entry code
try_door_interaction endp
                 

; =============== S U B R O U T I N E =======================================


hero_left_16_down_1 proc near 
                mov     ax, ds:hero_x_in_proximity_map
                add     ax, -16
                or      ah, ah
                jns     short loc_7DCF
                add     ax, ds:mapWidth

loc_7DCF:        
                mov     ds:proximity_map_left_col_x, ax
                mov     al, ds:door_target_y
                inc     al
                sub     al, ds:hero_head_y_in_viewport_initial_from_mdt
                and     al, 3Fh
                mov     ds:viewport_top_row_y, al
                retn
hero_left_16_down_1 endp


; =============== S U B R O U T I N E =======================================
; Reads hero_x_in_proximity_map
; Return:
; AX: proximity_map_left_col_x
; BL: hero_x_in_viewport
edge_locking_scrolling_window proc near
                mov     bx, 13
                mov     ax, ds:hero_x_in_proximity_map
                mov     cx, ds:mapWidth
                sub     cx, bx
                sub     cx, ax ; mapWidth - 13 - hero_x_in_proximity_map
                jnb     short loc_7E03 ; cx >= 0
                ; hero_x_in_proximity_map > mapWidth - 13
                mov     ax, ds:mapWidth
                add     ax, -36 ; mapWidth - 36; CF = mapWidth >= 36 ? 1 : 0
                mov     cx, ds:hero_x_in_proximity_map
                sbb     cx, ax ; cx = hero_x_in_proximity_map - (mapWidth - 36) - CF
                mov     bl, cl
                sub     bl, 3
                retn
; ---------------------------------------------------------------------------
loc_7E03: ; mapWidth - 13 - hero_x_in_proximity_map >= 0    
                add     ax, -17  ; hero_x_in_proximity_map - 17
                or      ah, ah
                jnz     short loc_7E0B ; ax >= 256
                ; hero_x_in_proximity_map >= 17
                ; ax = hero_x_in_proximity_map - 17; bl = 13
                retn
; ---------------------------------------------------------------------------
loc_7E0B:       ; hero_x_in_proximity_map < 17
                xor     ax, ax
                mov     bl, byte ptr ds:hero_x_in_proximity_map
                sub     bl, 4           ; hero_x_in_viewport
                retn
edge_locking_scrolling_window endp


; =============== S U B R O U T I N E =======================================

; return NC on success, CF on failure
open_door       proc near 
                mov     bl, [si+door.d_features]
                and     bl, 1
                jnz     short lion_head_key_needed ;
                                        ; ordinary key needed
                test    byte ptr ds:keys_amount, 0FFh
                stc
                jnz     short has_keys
                retn                    ; CF: no keys
; ---------------------------------------------------------------------------

has_keys:        
                dec     byte ptr ds:keys_amount  ; use ordinary key
                mov     byte ptr ds:soundFX_request, 21
                or      [si+door.d_flags], 80h   ; open
                mov     bx, [si+door.d_save_achievement_addr]
                mov     al, [si+door.d_achievement_flag]
                or      [bx], al
                retn
; ---------------------------------------------------------------------------

lion_head_key_needed:     
                test    byte ptr ds:lion_head_keys, 0FFh
                stc
                jnz     short loc_7E45
                retn
; ---------------------------------------------------------------------------

loc_7E45:        
                dec     byte ptr ds:lion_head_keys
                mov     byte ptr ds:soundFX_request, 21
                or      byte ptr [si+door.d_flags], 80h
                mov     bx, [si+door.d_save_achievement_addr]
                mov     al, [si+door.d_achievement_flag]
                or      [bx], al
                retn
open_door       endp


; =============== S U B R O U T I N E =======================================


reset_dungeon_state_vars proc near
                xor     al, al
                mov     ds:sword_swing_flag, al
                mov     ds:ui_element_dirty, al
                mov     ds:spell_active_flag, al
                mov     ds:jump_phase_flags, al ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     ds:squat_flag, al
                mov     ds:hero_damage_this_frame, al
                mov     ds:byte_9EEF, al
                mov     ds:byte_FF3E, al
                mov     ds:byte_FF4B, al
                mov     ds:heartbeat_volume, al
                mov     ds:hero_animation_phase, al
                mov     ax, 0FFFFh
                mov     ds:projectiles_array, al
                mov     ds:boss_explosion_rings_list, al
                mov     word ptr ds:magic_projectiles, ax
                mov     ds:hero_hidden_flag, al
                mov     ds:byte_9EF5, al
                jmp     clear_viewport_buffer
reset_dungeon_state_vars endp


; =============== S U B R O U T I N E =======================================

; AL: mdt_descriptor.b7b6_msd_idx_b0
; SI: &mdt_descriptor+1
process_mdt_descriptor proc near
                push    cs
                pop     es
                mov     di, offset mman_grp_index
                mov     cx, 4
                rep movsb               ; mdt_descr[1..4]
                shr     al, 1           ; mdt_descr[0]>>1
                and     al, 0Fh
                mov     ah, al
                mov     al, 0FFh
                cmp     ah, ds:msd_index
                je      short loc_7EB6
                mov     byte ptr ds:byte_FF24, 0Ah
                mov     ds:msd_index, ah
                mov     al, ah

loc_7EB6:        
                stosb  ; [9efah]
                mov     al, 0FFh
                stosb  ; [9efbh]
                retn
process_mdt_descriptor endp


; =============== S U B R O U T I N E =======================================

; load dchr.grp
; load mpp{mpp_grp_index}.grp
; load eai{eai_bin_index}.bin
; load enp{enp_grp_index}.grp
; load mgt{mgt_msd_index}.msd
load_cavern_sprites_ai_music proc near
                mov     es, cs:seg1
                mov     si, offset dchr_grp
                mov     di, offset dchr_gfx  ; doors, platforms tiles gfx
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                mov     bl, ds:mpp_grp_index
                mov     al, 11
                mul     bl
                add     ax, offset mpp_grp
                mov     si, ax
                mov     es, cs:seg1
                mov     di, mpp_gfx     ; static cavern tiles gfx
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                mov     bl, ds:eai_bin_index_
                cmp     bl, 0FFh
                jnz     short loc_7EF3
                retn
; ---------------------------------------------------------------------------

loc_7EF3:        
                cmp     bl, ds:eai_bin_index
                je      short loc_7F12   ; monsters AI already loaded
                mov     ds:eai_bin_index, bl
                mov     al, 11
                mul     bl
                add     ax, offset eai1_bin
                mov     si, ax
                push    cs
                pop     es
                mov     di, offset Monster_AI_proc
                mov     al, 3           ; fn3_read_virtual_file
                call    cs:res_dispatcher_proc

loc_7F12:        
                mov     bl, ds:enp_grp_index_
                cmp     bl, 0FFh
                jnz     short loc_7F1C
                retn
; ---------------------------------------------------------------------------

loc_7F1C:        
                cmp     bl, ds:enp_grp_index
                je      short loc_7F53   ; monsters gfx already loaded
                mov     ds:enp_grp_index, bl
                mov     al, 11
                mul     bl
                add     ax, offset vfs_enp1_grp
                mov     si, ax
                mov     es, cs:seg1
                mov     di, monster_gfx
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                push    ds
                mov     ds, cs:seg1
                mov     si, monster_gfx
                mov     bp, monsters_transparency_masks
                mov     cx, 100h
                call    cs:Decompress_Tile_Data_proc
                pop     ds
loc_7F53:
                mov     bl, ds:byte_9EFA
                cmp     bl, 0FFh
                jnz     short load_music
                retn
; ---------------------------------------------------------------------------
load_music:
                push    bx
                mov     ax, 1  ; fn1 (Stop) Silences all channels and halts the driver.
                int     60h             ; mscadlib.drv
                mov     ds:byte_9F02, 0FFh
                pop     bx              ; music index from mdt_descriptor
                mov     al, 11
                mul     bl
                add     ax, offset vfs_mgt1_msd
                mov     si, ax
                mov     es, cs:seg1
                mov     di, 3000h
                mov     al, 5           ; fn5_load_music
                call    cs:res_dispatcher_proc
                retn
load_cavern_sprites_ai_music endp


; =============== S U B R O U T I N E =======================================


sleep_loop_handle_system_keys proc near
                mov     cl, ds:speed_const
                mov     al, 4
                mul     cl
loc_7F8A:        
                push    ax
                call    cs:Confirm_Exit_Dialog_proc
                call    cs:Handle_Pause_State_proc
                call    cs:Handle_Speed_Change_proc
                call    cs:Joystick_Calibration_proc
                call    cs:Joystick_Deactivator_proc
                pop     ax
                cmp     ds:frame_timer, al
                jb      short loc_7F8A
                mov     byte ptr ds:frame_timer, 0
                retn
sleep_loop_handle_system_keys endp


; =============== S U B R O U T I N E =======================================


render_vertical_platforms_to_proximity proc near
                mov     si, ds:vertical_platforms_table_addr
next_vert_platform:
                mov     ax, [si+vert_platform.x]
                cmp     ax, 0FFFFh
                jnz     short loc_7FBD
                retn
; ---------------------------------------------------------------------------

loc_7FBD:        
                call    abs_x_to_proximity_rel
                jb      short loc_7FD7
                mov     ah, bl
                mov     al, [si+vert_platform.y]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     cx, 3           ; 3 platform tiles
                mov     dl, 40h ; '@'   ; vertical platform has tiles 0x40, 0x41, 0x42

loc_7FCF:        
                call    put_dl_to_proximity_layered
                inc     di              ; x++
                inc     dl              ; next platform tile
                loop    loc_7FCF

loc_7FD7:        
                add     si, 3
                jmp     short next_vert_platform
render_vertical_platforms_to_proximity endp


; =============== S U B R O U T I N E =======================================


move_platform_down_damage_monster proc near
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short on_ground4
                retn
; ---------------------------------------------------------------------------

on_ground4:       
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 3*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     dl, 40h         ; vertical platform: tiles 0x40, 0x41, 0x42
                call    identify_platform_tile ; NZ: not a platform
                                        ; ZF: platform; dh={1, 0, -1} for {left, mid, right} tile
                jz      short vert_platform_beneath
                retn
; ---------------------------------------------------------------------------

vert_platform_beneath:     
                mov     di, ds:vertical_platforms_table_addr
                mov     dl, 40h
                call    try_move_platform_down ; NC: platform is blocked
                                        ; CF: platform successfully moved down
                jnb     short blocked
                pop     ax
                mov     byte ptr ds:hero_animation_phase, 80h
                jmp     hero_scroll_down
; ---------------------------------------------------------------------------

blocked:         
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags; BX = monster struct
                jnc     short alive_or_dead_monster
                retn                    ; blocked by non-monster
; ---------------------------------------------------------------------------

alive_or_dead_monster:    
                and     al, 1100000b    ; dead slug (almas) = 0x74
                jz      short alive_monster
                retn
; ---------------------------------------------------------------------------

alive_monster:   
                test    [bx+monster.ai_flags], 100000b ; is damageable?
                jz      short monster_can_be_damaged
                retn
; ---------------------------------------------------------------------------

monster_can_be_damaged:   
                or      [bx+monster.ai_flags], 1000000b ; damage monster
                and     [bx+monster.ai_flags], 11100000b
                retn
move_platform_down_damage_monster endp


; =============== S U B R O U T I N E =======================================

; NC: platform is blocked
; CF: platform successfully moved down

try_move_platform_down proc near
                push    dx
                call    find_platform_under_hero
                pop     dx
                mov     bx, si
                add     si, 36-1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                test    byte ptr [si], 80h ; if high bit is set => platform is blocked below by monster
                clc
                jz      short loc_8038
                retn                    ; NC (blocked by monster)
; ---------------------------------------------------------------------------

loc_8038:        
                mov     cx, 3           ; platform is 3 tiles

three_times__:    
                inc     si
                test    byte ptr [si], 0FFh
                jz      short loc_8042
                retn                    ; NC: blocked by nonzero tile
; ---------------------------------------------------------------------------

loc_8042:        
                loop    three_times__
                mov     si, bx          ; bx is platform offset in proximity map
                add     si, 36          ; row under the platform
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                push    di
                mov     di, si          ; platform struc offset
                mov     cx, 3

three_times_:     
                push    dx
                push    bx
                call    put_dl_to_proximity_layered
                pop     bx
                xchg    di, bx
                push    bx
                xor     dl, dl
                call    put_dl_to_proximity_layered
                pop     bx
                xchg    di, bx
                inc     di
                inc     bx
                pop     dx
                inc     dl
                loop    three_times_
                pop     di
                inc     [di+vert_platform.y]
                and     [di+vert_platform.y], 3Fh
                stc
                retn                    ; CF: platform successfully moved down
try_move_platform_down endp


; =============== S U B R O U T I N E =======================================


try_move_platform_up proc near
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jz      short loc_807C
                retn
; ---------------------------------------------------------------------------

loc_807C:        
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                sub     si, 36-1
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     al, [si]
                call    is_blocking_tile ; ZF if can pass
                jz      short hero_not_blocked_above
                retn
; ---------------------------------------------------------------------------

hero_not_blocked_above:   
                add     si, 36*4
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     dl, 40h         ; vertical platform: tiles 0x40, 0x41, 0x42
                call    identify_platform_tile ; NZ: not a platform
                                        ; ZF: platform; dh={1, 0, -1} for {left, mid, right} tile
                jz      short vert_platform_beneath_
                retn
; ---------------------------------------------------------------------------

vert_platform_beneath_:     
                mov     di, ds:vertical_platforms_table_addr
                mov     dl, 40h
                push    dx
                call    find_platform_under_hero
                pop     dx
                mov     ax, si
                sub     si, 36
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     bx, si
                sub     si, 36
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     cx, 3           ; platform is 3 tiles

check_across_platform_width:  
                test    byte ptr [si], 80h
                jz      short not_blocked
                retn
; ---------------------------------------------------------------------------

not_blocked:     
                test    byte ptr [bx], 0FFh
                jz      short not_blocked_
                retn
; ---------------------------------------------------------------------------

not_blocked_:    
                inc     si
                inc     bx
                loop    check_across_platform_width
                mov     bx, ax
                mov     si, bx
                sub     si, 36
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                push    di
                mov     di, si
                mov     cx, 3

loc_80DA:        
                push    dx
                push    bx
                call    put_dl_to_proximity_layered
                pop     bx
                xchg    di, bx
                push    bx
                xor     dl, dl
                call    put_dl_to_proximity_layered
                pop     bx
                xchg    di, bx
                inc     di
                inc     bx
                pop     dx
                inc     dl              ; 40h, 41h, 42h
                loop    loc_80DA
                pop     di
                dec     [di+door.y0]    ; move platform up
                and     [di+door.y0], 3Fh
                pop     ax
                pop     ax
                mov     byte ptr ds:hero_animation_phase, 80h
                mov     byte ptr ds:jump_phase_flags, 0 ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                jmp     move_hero_up
try_move_platform_up endp


; =============== S U B R O U T I N E =======================================


find_platform_under_hero proc near
                mov     al, ds:hero_x_in_viewport
                add     al, 4           ; viewport starts +4 from proximity window
                add     al, dh          ; hero position on platform {-1, 0, 1}
                xor     ah, ah
                add     ax, ds:proximity_map_left_col_x
                cmp     ax, ds:mapWidth
                jb      short inside_the_map
                sub     ax, ds:mapWidth ; ax = hero absolute coord x

inside_the_map:  
                mov     cl, ds:viewport_top_row_y
                add     cl, ds:hero_head_y_in_viewport ; hero absolute y coord in map
                add     cl, 3           ; hero height
                and     cl, 3Fh         ; hero feets y

next_platform:   
                cmp     ax, [di+vert_platform.x]
                jnz     short loc_8137
                cmp     cl, [di+vert_platform.y]
                jz      short platform_found

loc_8137:        
                add     di, 3           ; vertical platform descriptor is 3 bytes
                jmp     short next_platform
; ---------------------------------------------------------------------------

platform_found:  
                call    abs_x_to_proximity_rel
                mov     al, [di+vert_platform.y]
                mov     ah, bl
                push    di
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     si, di
                pop     di
                retn
find_platform_under_hero endp


; =============== S U B R O U T I N E =======================================

; NZ: not a platform
; ZF: platform; dh={1, 0, -1} for {left, mid, right} tile

identify_platform_tile proc near
                mov     dh, 1
                cmp     dl, [si]
                jnz     short loc_8153
                retn                    ; left platform tile, return ZF and dh=1
; ---------------------------------------------------------------------------

loc_8153:        
                dec     dh
                inc     dl
                cmp     dl, [si]
                jnz     short loc_815C
                retn                    ; middle platform tile, return ZF and dh=0
; ---------------------------------------------------------------------------

loc_815C:        
                dec     dh
                inc     dl
                cmp     dl, [si]
                retn                    ; right platform tile, return ZF and dh=-1
identify_platform_tile endp


; =============== S U B R O U T I N E =======================================

; Note: collapsing and vertical platforms share the same struct
process_visible_collapsing_platforms proc near
                mov     si, ds:collapsing_platforms_table_addr

next_collapsing_platform: 
                mov     ax, [si+vert_platform.x]
                cmp     ax, 0FFFFh
                jnz     short loc_816F
                retn
; ---------------------------------------------------------------------------

loc_816F:        
                call    abs_x_to_proximity_rel
                jb      short loc_8189
                mov     ah, bl
                mov     al, [si+vert_platform.y] ; y
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     cx, 3
                mov     dl, 43h ; 'C'   ; collapsing platform tiles are 0x43, 0x44, 0x45

loc_8181:        
                call    put_dl_to_proximity_layered
                inc     di
                inc     dl
                loop    loc_8181

loc_8189:        
                add     si, 3
                jmp     short next_collapsing_platform
process_visible_collapsing_platforms endp


; =============== S U B R O U T I N E =======================================


hero_collapse_platform proc near
                call    hero_coords_to_addr_in_proximity ; Hero is 3x3 matrix. Return top-left coord in SI
                add     si, 3*36+1
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                mov     dl, 43h         ; collapsing platform tiles are 0x43, 0x44, 0x45
                call    identify_platform_tile ; NZ: not a platform
                                        ; ZF: platform; dh={1, 0, -1} for {left, mid, right} tile
                jz      short loc_819F
                retn
; ---------------------------------------------------------------------------

loc_819F:        
                mov     di, ds:collapsing_platforms_table_addr
                mov     dl, 43h
                call    try_move_platform_down ; NC: platform is blocked
                                        ; CF: platform successfully moved down
                jb      short loc_81AB
                retn
; ---------------------------------------------------------------------------

loc_81AB:        
                jmp     hero_scroll_down
hero_collapse_platform endp


; =============== S U B R O U T I N E =======================================


update_and_render_horiz_platforms proc near
                inc     ds:byte_9F07
                mov     si, ds:horiz_platforms_table_addr ; =d55f

next_platform_:   
                mov     ax, [si+horiz_platform.x_and_flags]
                cmp     ax, 0FFFFh
                jnz     short loc_81BE
                retn
; ---------------------------------------------------------------------------

loc_81BE:        
                and     ax, 3FFFh       ; x
                call    horiz_platform_proximity_x_offset
                jb      short loc_820A
                mov     cl, bl
                dec     bx
                dec     bx
                or      bh, bh
                jns     short loc_81DA
                inc     cl
                mov     al, [si+horiz_platform.y_and_flags]
                xor     ah, ah
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                jmp     short loc_8200
; ---------------------------------------------------------------------------

loc_81DA:        
                mov     ax, bx
                sub     ax, 34
                jb      short loc_81F6
                push    ax
                mov     al, [si+horiz_platform.y_and_flags]
                mov     ah, 34
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                pop     ax
                add     di, ax
                mov     cl, al
                neg     cl
                add     cl, 2
                jmp     short loc_8200
; ---------------------------------------------------------------------------

loc_81F6:        
                mov     ah, bl
                mov     al, [si+horiz_platform.y_and_flags]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     cl, 3           ; platform has 3 tiles

loc_8200:        
                xor     ch, ch
                xor     dl, dl

clear_next_platform_tile: 
                call    put_dl_to_proximity_layered
                inc     di
                loop    clear_next_platform_tile

loc_820A:        
                mov     ax, [si+horiz_platform.x_and_flags]
                mov     bl, ah
                and     ax, 3FFFh
                rol     bl, 1
                rol     bl, 1
                and     bl, 3           ; 00, 01, 10, 11
                jz      short skip_if_0
                dec     bl
                xor     bh, bh
                add     bx, bx
                call    ds:funcs_8220[bx]

skip_if_0:       
                call    abs_x_to_proximity_rel
                jb      short loc_823E
                mov     ah, bl
                mov     al, [si+horiz_platform.y_and_flags]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     cx, 3
                mov     dl, 46h         ; Horizontal platform has tiles 0x46, 0x47, 0x48

loc_8236:        
                call    put_dl_to_proximity_layered
                inc     di
                inc     dl
                loop    loc_8236

loc_823E:        
                add     si, 7
                jmp     next_platform_
update_and_render_horiz_platforms endp

; ---------------------------------------------------------------------------
funcs_8220      dw offset update_slow_horiz_platform_coords
                dw offset update_horiz_platform_coords
                dw offset update_horiz_platform_coords

; =============== S U B R O U T I N E =======================================


update_slow_horiz_platform_coords proc near
                test    ds:byte_9F07, 1
                jnz     short update_horiz_platform_coords
                retn
update_slow_horiz_platform_coords endp


; =============== S U B R O U T I N E =======================================


update_horiz_platform_coords proc near
                mov     cl, [si+horiz_platform.y_and_flags]
                and     [si+horiz_platform.y_and_flags], 10111111b
                test    cl, 40h         ; paused platform
                jz      short moving_platform
                retn
; ---------------------------------------------------------------------------

moving_platform: 
                test    [si+horiz_platform.y_and_flags], 80h ; y bit 7 is direction: 0=right, 1=left
                jnz     short leftward
                inc     ax
                mov     bx, ax
                sub     ax, ds:mapWidth
                jz      short loc_826F
                xchg    ax, bx

loc_826F:        
                push    si
                push    ax
                call    hero_on_horiz_platform
                jb      short loc_8279
                call    move_hero_right_if_no_obstacles

loc_8279:        
                pop     ax
                pop     si
                mov     bx, [si+horiz_platform.max_x] ; platform moving rightward
                jmp     short loc_8299
; ---------------------------------------------------------------------------

leftward:        
                dec     ax
                cmp     ax, 0FFFFh
                jnz     short loc_828A
                mov     ax, ds:mapWidth
                dec     ax

loc_828A:        
                push    si
                push    ax
                call    hero_on_horiz_platform
                jb      short loc_8294
                call    move_hero_left_if_no_obstacles

loc_8294:        
                pop     ax
                pop     si
                mov     bx, [si+horiz_platform.min_x] ; platform moving leftward

loc_8299:        
                mov     dl, [si+1]
                and     dl, 11000000b   ; x_and_flags speed part
                or      dl, ah
                mov     byte ptr [si+horiz_platform.x_and_flags], al ; =2f
                mov     [si+1], dl      ; horiz. platform x = 40h => normal speed
                sub     bx, ax          ; 0024h-002f=fff5
                jz      short loc_82AB
                retn
; ---------------------------------------------------------------------------

loc_82AB:        
                xor     [si+horiz_platform.y_and_flags], 80h ; change direction
                or      [si+horiz_platform.y_and_flags], 40h ; pause platform for several ticks
                retn
update_horiz_platform_coords endp


; =============== S U B R O U T I N E =======================================


hero_on_horiz_platform proc near
                mov     dl, ds:jump_phase_flags ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                or      dl, ds:on_rope_flags ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                stc
                jz      short on_ground5
                retn
; ---------------------------------------------------------------------------

on_ground5:       
                mov     al, ds:hero_head_y_in_viewport
                add     al, ds:viewport_top_row_y
                add     al, 3
                and     al, 3Fh
                mov     ah, [si+horiz_platform.y_and_flags]
                and     ah, 3Fh
                cmp     al, ah
                stc
                jz      short loc_82D7
                retn
; ---------------------------------------------------------------------------

loc_82D7:        
                mov     ax, [si+horiz_platform.x_and_flags]
                and     ax, 3FFFh
                call    abs_x_to_proximity_rel
                jnb     short loc_82E2
                retn
; ---------------------------------------------------------------------------

loc_82E2:        
                mov     dl, ds:hero_x_in_viewport
                add     dl, 4
                mov     cx, 3

loc_82EC:        
                cmp     dl, al
                clc
                jnz     short loc_82F2
                retn
; ---------------------------------------------------------------------------

loc_82F2:        
                inc     dl
                loop    loc_82EC
                stc
                retn
hero_on_horiz_platform endp


; =============== S U B R O U T I N E =======================================


abs_x_to_proximity_rel proc near
                mov     bx, ax          ; ax=bx=inX (absolute x coord in the map)
                sub     ax, ds:proximity_map_left_col_x ; ax = inX-proximityLeft
                jb      short inX_lt_proxLeft ;
                                        ; case0:
                                        ; proximityLeft <= inX < mapWidth
                xchg    ax, bx          ; ax = inX
                                        ; bx = inX - proximityLeft
                mov     ax, 36-3
                sub     ax, bx          ; ax = 33 - (inX - proximityLeft)
                                        ; bx = inX - proximityLeft
                retn                    ; CF if: proximityLeft + 34 <= inX
                                        ; NC if: proximityLeft <= inX < proximityLeft + 34
; ---------------------------------------------------------------------------

inX_lt_proxLeft: 
                mov     ax, 36-3        ; case1:
                                        ; inX < proximityLeft
                sub     ax, bx          ; ax = 33 - inX
                                        ; bx = inX
                jnb     short inX_le_33
                retn                    ; CF if: 33 < inX < proximityLeft
; ---------------------------------------------------------------------------

inX_le_33:       
                mov     ax, ds:mapWidth ; case2:
                                        ; inX <= 33 < proximityLeft
                sub     ax, ds:proximity_map_left_col_x
                add     ax, bx          ; ax = mapWidth - proximity_map_left_col_x + inX
                                        ; bx = inX
                xchg    ax, bx          ; ax = inX
                                        ; bx = mapWidth - proximity_map_left_col_x + inX
                mov     ax, 36-3
                sub     ax, bx          ; ax = 33 - (mapWidth - proximity_map_left_col_x + inX)
                                        ; bx = mapWidth - proximity_map_left_col_x + inX
                retn                    ; CF if: 33 - inX < mapWidth - proximity_map_left_col_x
abs_x_to_proximity_rel endp


; =============== S U B R O U T I N E =======================================


horiz_platform_proximity_x_offset proc near
                add     ax, 2
                mov     bx, ax
                sub     ax, ds:mapWidth
                jnb     short loc_832B
                xchg    ax, bx

loc_832B:        
                mov     bx, ax
                sub     ax, ds:proximity_map_left_col_x
                jb      short loc_833A
                xchg    ax, bx
                mov     ax, 37
                sub     ax, bx
                retn
; ---------------------------------------------------------------------------

loc_833A:        
                mov     ax, 37
                sub     ax, bx
                jnb     short loc_8342
                retn
; ---------------------------------------------------------------------------

loc_8342:        
                mov     ax, ds:mapWidth
                sub     ax, ds:proximity_map_left_col_x
                add     ax, bx
                xchg    ax, bx
                mov     ax, 37
                sub     ax, bx
                retn
horiz_platform_proximity_x_offset endp


; =============== S U B R O U T I N E =======================================


put_dl_to_proximity_layered proc near   ; ...
                test    byte ptr [di], 80h ; monster here?
                jnz     short loc_835A
                mov     [di], dl        ; di is destination
                retn
; ---------------------------------------------------------------------------

loc_835A:        
                mov     bl, [di]        ; [di] contains offset to destination table of 128 values
                and     bl, 7Fh         ; bl = monster id
                xor     bh, bh
                mov     ds:proximity_second_layer[bx], dl ; proximity map is designed to keep only one item
                                        ; at given address. So when we need to put other object,
                                        ; when position is already occupied by monster,
                                        ; we use second layer: 128 bytes of additional buffer
                                        ; (1 byte per monster id)
                retn
put_dl_to_proximity_layered endp


; =============== S U B R O U T I N E =======================================


update_and_render_projectile_row_pair proc near
                mov     si, offset projectiles_array

loc_8369:        
                cmp     byte ptr [si+projectile.p_x_rel], 0FFh
                jnz     short loc_836F
                retn
; ---------------------------------------------------------------------------

loc_836F:        
                push    si
                call    flush_dirty_projectile
                pop     si
                mov     al, [si+projectile.p_x_rel]
                mov     [si+projectile.p_cached_x_rel], al
                sub     al, 4
                cmp     al, 28
                jnb     short loc_83D2
                mov     al, [si+projectile.p_y_rel]
                sub     al, ds:viewport_top_row_y
                and     al, 3Fh
                cmp     al, 12h
                jnb     short loc_83D2
                mov     [si+projectile.p_cached_y_rel], al
                mov     ah, [si+projectile.p_cached_x_rel]
                push    ax
                call    proximity_map_coords_to_viewport_offset ; AL: proximity map relative y
                                        ; AH: proximity map relative x
                                        ; Return: address in DI
                pop     ax
                cmp     byte ptr [di], 0FFh
                jz      short loc_83CD
                cmp     byte ptr [di], 0FCh
                jz      short loc_83CD
                call    cs:Viewport_Coords_To_Screen_Addr_proc ; AL: y
                                        ; AH: x
                                        ; Returns video memory address in DI
                or      di, 8000h
                mov     [si+projectile.p_vram_addr_d], di
                mov     al, [si+projectile.p_base_tile_idx]
                mov     bl, al
                rol     bl, 1
                rol     bl, 1
                and     bx, 3
                mov     bl, ds:masks[bx]
                and     bl, [si+projectile.p_trajectory_step_count]
                add     al, bl
                and     al, 3Fh
                and     di, 7FFFh
                call    cs:Uncompress_And_Render_Tile_proc ; AL: tile index
                                        ; DI: screen address

loc_83CD:
                add     si, 13          ; size of a projectile struct
                jmp     short loc_8369

loc_83D2:
                mov     byte ptr [si], 0
                jmp     short loc_83CD
update_and_render_projectile_row_pair endp

; ---------------------------------------------------------------------------
masks           db 0, 1, 11b, 111b 

; =============== S U B R O U T I N E =======================================


Browse_Projectiles proc near  
                mov     si, offset projectiles_array ; example:
                                        ; 1E 19 2B 00 0F 04 28 00 00 00 00 00 00

loc_83DE:        
                cmp     [si+projectile.p_x_rel], 0FFh
                jz      short no_projectiles
                push    si
                call    flush_dirty_projectile
                pop     si
                add     si, 13
                jmp     short loc_83DE
; ---------------------------------------------------------------------------

no_projectiles:  
                mov     byte ptr ds:projectiles_array, 0FFh
                retn
Browse_Projectiles endp


; =============== S U B R O U T I N E =======================================


flush_dirty_projectile proc near
                test    [si+projectile.p_vram_addr_d], 8000h
                jnz     short loc_83FB
                retn
; ---------------------------------------------------------------------------

loc_83FB:        
                and     [si+projectile.p_vram_addr_d], 7FFFh
                mov     dx, [si+projectile.p_vram_addr_d]
                mov     al, [si+projectile.p_cached_y_rel]
                mov     ah, [si+projectile.p_cached_x_rel]
flush_dirty_projectile endp


; =============== S U B R O U T I N E =======================================


restore_bg_tile_at_given_position proc near
                push    ax
                call    proximity_map_coords_to_viewport_offset ; AL: proximity map relative y
                                        ; AH: proximity map relative x
                                        ; Return: address in DI
                pop     ax
                cmp     byte ptr [di], 0FCh
                jb      short loc_8414
                retn
; ---------------------------------------------------------------------------

loc_8414:        
                add     al, ds:viewport_top_row_y
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     al, [di]
                jmp     cs:Dungeon_Static_Tile_Cached_Drawer_proc ; AL: Tile Index
restore_bg_tile_at_given_position endp  ; DX: Screen destination


; =============== S U B R O U T I N E =======================================


projectiles_collision_processing proc near
                mov     si, offset projectiles_array
                mov     di, offset projectiles_array
                push    cs
                pop     es
                mov     ds:last_projectile_index, 0

next_projectile: 
                mov     al, [si+projectile.p_x_rel]
                or      al, al
                jnz     short loc_843C
                test    [si+projectile.p_vram_addr_d], 8000h
                jz      short loc_846A

loc_843C:        
                inc     al
                jnz     short loc_8444
                mov     [di+projectile.p_x_rel], 0FFh
                retn
; ---------------------------------------------------------------------------

loc_8444:        
                inc     [si+projectile.p_trajectory_step_count]
                push    es
                push    di
                call    sub_846F
                pop     di
                pop     es
                push    si
                mov     cx, 13
                rep movsb
                pop     si
                test    [si+projectile.p_trajectory_dir], 40h
                jnz     short loc_8466
                mov     al, [si+projectile.p_trajectory_step_count]
                cmp     al, [si+projectile.p_max_step_count]
                jb      short loc_8466
                mov     [si+projectile.p_x_rel], 0

loc_8466:        
                inc     ds:last_projectile_index

loc_846A:        
                add     si, 13
                jmp     short next_projectile
projectiles_collision_processing endp


; =============== S U B R O U T I N E =======================================


sub_846F        proc near 
                call    projectile_advance_position
                test    [si+projectile.p_trajectory_dir], 8
                jnz     short loc_8490
                mov     ah, [si+projectile.p_x_rel]
                or      ah, ah
                jnz     short loc_847F
                retn
; ---------------------------------------------------------------------------

loc_847F:        
                mov     al, [si+projectile.p_y_rel]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     al, [di]
                call    is_blocking_tile_extended
                jz      short loc_8490
                mov     [si+projectile.p_x_rel], 0
                retn
; ---------------------------------------------------------------------------

loc_8490:        
                mov     al, ds:viewport_top_row_y
                add     al, ds:hero_head_y_in_viewport
                test    byte ptr ds:squat_flag, 0FFh
                jnz     short loc_84A5
                and     al, 3Fh
                cmp     al, [si+projectile.p_y_rel]
                jz      short loc_84B4

loc_84A5:        
                mov     cx, 2

loc_84A8:        
                inc     al
                and     al, 3Fh
                cmp     al, [si+projectile.p_y_rel]
                jz      short loc_84B4
                loop    loc_84A8
                retn
; ---------------------------------------------------------------------------

loc_84B4:        
                mov     al, ds:hero_x_in_viewport
                add     al, 4
                test    byte ptr ds:facing_direction, 1
                jz      short loc_84C2
                inc     al

loc_84C2:        
                cmp     al, [si+projectile.p_x_rel]
                jz      short loc_84CD
                inc     al
                cmp     al, [si+projectile.p_x_rel]
                jz      short loc_84CD
                retn
; ---------------------------------------------------------------------------

loc_84CD:        
                mov     [si+projectile.p_x_rel], 0
                test    byte ptr ds:shield_type, 0FFh
                jz      short loc_850E
                test    byte ptr ds:sword_swing_flag, 0FFh
                jnz     short loc_850E
                test    byte ptr ds:on_rope_flags, 0FFh ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                jnz     short loc_850E
                mov     al, [si+projectile.p_trajectory_dir]
                and     al, 7
                cmp     al, 2
                jz      short loc_850E
                cmp     al, 6
                jz      short loc_850E
                or      al, al
                jz      short loc_8507
                cmp     al, 1
                jz      short loc_8507
                cmp     al, 7
                jz      short loc_8507
                test    byte ptr ds:facing_direction, 1
                jnz     short loc_850E
                jmp     short loc_854F
; ---------------------------------------------------------------------------

loc_8507:        
                test    byte ptr ds:facing_direction, 1
                jnz     short loc_854F

loc_850E:        
                mov     al, [si+projectile.p_damage]
                xor     ah, ah
                call    damage_hero     ; ax: damage level
                mov     byte ptr ds:soundFX_request, 9
                mov     al, 0FFh
                mov     ds:byte_9F14, al
                mov     ds:hero_damage_this_frame, al
                mov     bx, 0FFFFh
                mov     cx, 0FFFFh
                mov     al, [si+projectile.p_trajectory_dir]
                and     al, 7
                cmp     al, 2
                jz      short loc_8546
                cmp     al, 6
                jz      short loc_8546
                xor     bx, bx
                or      al, al
                jz      short loc_8546
                cmp     al, 1
                jz      short loc_8546
                cmp     al, 7
                jz      short loc_8546
                xchg    cx, bx

loc_8546:        
                mov     ds:word_9F0E, cx
                mov     ds:word_9F10, bx
                retn
; ---------------------------------------------------------------------------

loc_854F:        
                cmp     byte ptr ds:shield_type, SHIELD_HONOR
                jnb     short loc_856D
                mov     al, ds:hero_head_y_in_viewport
                add     al, ds:viewport_top_row_y
                inc     al
                test    byte ptr ds:squat_flag, 0FFh
                jz      short loc_8568
                inc     al

loc_8568:        
                call    projectile_y_vs_hero_row_dispatch
                jb      short loc_850E

loc_856D:        
                mov     byte ptr ds:soundFX_request, 10
                retn
sub_846F        endp


; =============== S U B R O U T I N E =======================================


projectile_y_vs_hero_row_dispatch proc near
                mov     bl, [si+projectile.p_trajectory_dir]
                and     bx, 7
                add     bx, bx
                and     al, 3Fh
                jmp     ds:funcs_857D[bx]
projectile_y_vs_hero_row_dispatch endp

; ---------------------------------------------------------------------------
funcs_857D      dw offset check_y_eq_projectile_row
                dw offset check_prev_y_eq_projectile_row
                dw offset check_prev_y_eq_projectile_row
                dw offset check_prev_y_eq_projectile_row
                dw offset check_y_eq_projectile_row
                dw offset check_next_y_eq_projectile_row
                dw offset check_next_y_eq_projectile_row
                dw offset check_next_y_eq_projectile_row

; =============== S U B R O U T I N E =======================================


check_y_eq_projectile_row proc near
                cmp     al, [si+projectile.p_y_rel]
                jnz     short loc_8597
                retn
; ---------------------------------------------------------------------------

loc_8597:        
                stc
                retn
check_y_eq_projectile_row endp


; =============== S U B R O U T I N E =======================================


check_prev_y_eq_projectile_row proc near
                dec     al
                and     al, 3Fh
                jmp     short check_y_eq_projectile_row
check_prev_y_eq_projectile_row endp


; =============== S U B R O U T I N E =======================================


check_next_y_eq_projectile_row proc near
                inc     al
                and     al, 3Fh
                jmp     short check_y_eq_projectile_row
check_next_y_eq_projectile_row endp


; =============== S U B R O U T I N E =======================================


projectile_advance_position proc near
                test    [si+projectile.p_trajectory_dir], 40h
                jz      short loc_85B1
                call    projectile_read_curved_path_step
                jnb     short loc_85B1
                retn
; ---------------------------------------------------------------------------

loc_85B1:        
                mov     bl, [si+projectile.p_trajectory_dir] ; trajectory type
                and     bx, 7
                add     bx, bx
                call    ds:funcs_85B9[bx]
                and     [si+projectile.p_y_rel], 3Fh
                retn
projectile_advance_position endp

; ---------------------------------------------------------------------------
funcs_85B9      dw offset incX
                dw offset decY
                dw offset decY__
                dw offset decY_
                dw offset decX
                dw offset decX_incY
                dw offset incY
                dw offset incX_incY

; =============== S U B R O U T I N E =======================================


decY            proc near 
                dec     [si+projectile.p_y_rel]
decY            endp


; =============== S U B R O U T I N E =======================================


incX            proc near 
                inc     [si+projectile.p_x_rel]
                retn
incX            endp


; =============== S U B R O U T I N E =======================================


incX_incY       proc near 
                inc     [si+projectile.p_y_rel]
                inc     [si+projectile.p_x_rel]
                retn
incX_incY       endp


; =============== S U B R O U T I N E =======================================


decY_           proc near 
                dec     [si+projectile.p_y_rel]
decY_           endp


; =============== S U B R O U T I N E =======================================


decX            proc near 
                dec     [si+projectile.p_x_rel]
                retn
decX            endp


; =============== S U B R O U T I N E =======================================


decX_incY       proc near 
                inc     [si+projectile.p_y_rel]
                dec     [si+projectile.p_x_rel]
                retn
decX_incY       endp


; =============== S U B R O U T I N E =======================================


incY            proc near 
                inc     [si+projectile.p_y_rel]
                retn
incY            endp


; =============== S U B R O U T I N E =======================================


decY__          proc near 
                dec     [si+projectile.p_y_rel]
                retn
decY__          endp


; =============== S U B R O U T I N E =======================================


projectile_read_curved_path_step proc near
                mov     bl, [si+projectile.p_trajectory_step_count]
                xor     bh, bh
                mov     di, [si+projectile.p_curved_path_data_ptr]
                mov     al, [bx+di]
                cmp     al, 0FFh
                jnz     short loc_8607
                mov     byte ptr [si+80h], 0
                stc
                retn
; ---------------------------------------------------------------------------

loc_8607:        
                and     al, 7
                and     [si+projectile.p_trajectory_dir], 0F8h
                or      [si+projectile.p_trajectory_dir], al
                retn
projectile_read_curved_path_step endp


; =============== S U B R O U T I N E =======================================

; In: BX pointing to projectile struct

Add_Projectile_To_Array proc near
                cmp     ds:last_projectile_index, 31 ; max 32 projectiles
                jb      short loc_8619
                retn
; ---------------------------------------------------------------------------

loc_8619:        
                push    si
                push    cs
                pop     es
                mov     si, bx
                mov     di, offset projectiles_array

find_array_end:  
                cmp     byte ptr [di], 0FFh
                jz      short found_end_marker
                add     di, 13
                jmp     short find_array_end
; ---------------------------------------------------------------------------

found_end_marker:
                mov     cx, 13
                rep movsb               ; add new projectile to array
                mov     al, 0FFh        ; set end marker
                stosb
                inc     ds:last_projectile_index
                pop     si
                retn
Add_Projectile_To_Array endp


; =============== S U B R O U T I N E =======================================


every_projectile_moves_left_in_viewport proc near
                mov     si, offset projectiles_array

next_projectile_: 
                mov     al, [si+projectile.p_x_rel]
                cmp     al, 0FFh
                jnz     short loc_8643
                retn
; ---------------------------------------------------------------------------

loc_8643:        
                or      al, al
                jz      short loc_8649
                dec     [si+projectile.p_x_rel]

loc_8649:        
                add     si, 13
                jmp     short next_projectile_
every_projectile_moves_left_in_viewport endp


; =============== S U B R O U T I N E =======================================


every_projectile_moves_right_in_viewport proc near
                mov     si, offset projectiles_array

next_projectile__: 
                mov     al, [si+projectile.p_x_rel]
                cmp     al, 0FFh
                jnz     short loc_8658
                retn
; ---------------------------------------------------------------------------

loc_8658:        
                or      al, al
                jz      short loc_865E
                inc     [si+projectile.p_x_rel]

loc_865E:        
                add     si, 13
                jmp     short next_projectile__
every_projectile_moves_right_in_viewport endp


; =============== S U B R O U T I N E =======================================

; AL: proximity map relative y
; AH: proximity map relative x
; Return: address in DI

proximity_map_coords_to_viewport_offset proc near
                and     al, 3Fh         ; clamp y
                mov     bl, ah          ; proximity map relative x
                mov     bh, 28          ; viewport width
                mul     bh              ; ax=row offset in viewport buffer
                sub     bl, 4           ; viewport relative x
                xor     bh, bh
                add     ax, bx
                mov     di, ax
                add     di, viewport_buffer_28x19
                retn
proximity_map_coords_to_viewport_offset endp


; =============== S U B R O U T I N E =======================================


render_and_collision_pass_row proc near
                mov     si, offset spirit_sprite_0
                mov     cx, 4

next_spirit:
                push    cx
                cmp     byte ptr [si], 0FFh
                jz      short loc_86DC
                call    restore_bg_under_spirit_sprite
                test    byte ptr [si+2], 0FFh
                jnz     short loc_8693
                mov     byte ptr [si], 0FFh
                jmp     short loc_86DC

loc_8693:
                mov     bl, [si]
                and     bl, 0Fh
                xor     bh, bh
                add     bx, bx
                add     bx, offset circle ;
                                        ; ..345..
                                        ; .2...6.
                                        ; 1.....7
                                        ; 0.....8
                                        ; f.....9
                                        ; .e...a.
                                        ; ..dcb..
                mov     ah, ds:hero_x_in_viewport
                add     ah, [bx]
                mov     [si+spirit.s_screen_x], ah
                mov     al, ds:hero_head_y_in_viewport
                add     al, [bx+1]
                and     al, 3Fh
                mov     [si+spirit.s_screen_y], al
                push    ax
                call    proximity_map_coords_to_viewport_offset ; AL: proximity map relative y
                                        ; AH: proximity map relative x
                                        ; Return: address in DI
                pop     ax
                cmp     byte ptr [di], 0FFh
                jz      short loc_86DC
                cmp     byte ptr [di], 0FCh
                jz      short loc_86DC
                call    cs:Viewport_Coords_To_Screen_Addr_proc ; AL: y
                                        ; AH: x
                                        ; Returns video memory address in DI
                or      di, 8000h
                mov     [si+spirit.s_vram_addr], di
                mov     al, 66h ; 'f'
                and     di, 7FFFh  ; DI = screen address (half)
                push    si
                call    cs:Uncompress_And_Render_Tile_proc ; AL: tile index
                                        ; DI: screen address
                pop     si

loc_86DC:
                add     si, 7  ; size of spirit struct
                pop     cx
                loop    next_spirit
                retn
render_and_collision_pass_row endp


; =============== S U B R O U T I N E =======================================


restore_bg_under_spirit_sprite proc near
                test    word ptr [si+spirit.s_vram_addr], 8000h
                jnz     short loc_86EB
                retn

loc_86EB:
                and     word ptr [si+spirit.s_vram_addr], 7FFFh
                mov     dx, [si+spirit.s_vram_addr]
                mov     ah, [si+spirit.s_screen_x]
                mov     al, [si+spirit.s_screen_y]
                jmp     restore_bg_tile_at_given_position
restore_bg_under_spirit_sprite endp


; =============== S U B R O U T I N E =======================================


monsters_updates proc near
                mov     si, offset spirit_sprite_0
                mov     cx, 4

next_spirit_:     
                push    cx
                cmp     [si+spirit.s_orbit_phase], 0FFh
                jz      short loc_873A
                mov     bl, [si+spirit.s_orbit_phase]
                add     bl, [si+spirit.s_orbit_speed]
                and     bl, 0Fh
                mov     [si+spirit.s_orbit_phase], bl
                xor     bh, bh
                add     bx, bx
                add     bx, offset circle ;
                                        ; ..345..
                                        ; .2...6.
                                        ; 1.....7
                                        ; 0.....8
                                        ; f.....9
                                        ; .e...a.
                                        ; ..dcb..
                mov     ah, ds:hero_x_in_viewport
                add     ah, [bx]
                mov     al, ds:hero_head_y_in_viewport
                add     al, [bx+1]
                add     al, ds:viewport_top_row_y
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                xchg    si, di
                sub     si, 37
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xchg    si, di
                call    spirit_sprite_place_in_proximity_rows

loc_873A:        
                add     si, 7
                pop     cx
                loop    next_spirit_
                retn
monsters_updates endp


; =============== S U B R O U T I N E =======================================


spirit_sprite_place_in_proximity_rows proc near
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_8750
                test    byte ptr ds:boss_is_dead, 0FFh
                jz      short loc_8750
                retn
; ---------------------------------------------------------------------------

loc_8750:        
                call    proximity_cell_inject_spell_target
                inc     di
                call    proximity_cell_inject_spell_target
                xchg    si, di
                add     si, 35
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                call    proximity_cell_inject_spell_target
                inc     di
spirit_sprite_place_in_proximity_rows endp


; =============== S U B R O U T I N E =======================================

; Input:
;   DI: address in proximity map
;   SI: ?
proximity_cell_inject_spell_target proc near
                test    byte ptr [si+2], 0FFh
                jnz     short loc_876C
                retn
; ---------------------------------------------------------------------------

loc_876C:        
                xchg    si, di
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags; BX = monster struct
                xchg    si, di
                jnc     short loc_8776
                retn
; ---------------------------------------------------------------------------

loc_8776:        
                test    byte ptr [bx+monster.flags], 20h
                jz      short loc_877D
                retn
; ---------------------------------------------------------------------------

loc_877D:        
                test    byte ptr [bx+monster.ai_flags], 20h
                jz      short loc_8784
                retn
; ---------------------------------------------------------------------------

loc_8784:        
                and     byte ptr [bx+monster.ai_flags], 0E0h
                or      byte ptr [bx+monster.ai_flags], 49h
                dec     byte ptr [si+2]
                retn
proximity_cell_inject_spell_target endp

; ---------------------------------------------------------------------------
;   ..345..
;   .2...6.
; ⊙.1.....7
;   0.....8
;   f.....9
;   .e...a.
;   ..dcb..
                ;    y x
circle          dw  0102h ; 0   
                dw  0002h ; 1
                dw 0FF03h ; 2
                dw 0FE04h ; 3
                dw 0FE05h ; 4
                dw 0FE06h ; 5
                dw 0FF07h ; 6
                dw  0008h ; 7
                dw  0108h ; 8
                dw  0208h ; 9
                dw  0307h ; a
                dw  0406h ; b
                dw  0405h ; c
                dw  0404h ; d
                dw  0303h ; e
                dw  0202h ; f

; =============== S U B R O U T I N E =======================================


magic_spell_fire_handler proc near
                test    byte ptr ds:current_magic_spell, 0FFh
                jnz     short loc_87B8
                retn
; ---------------------------------------------------------------------------

loc_87B8:        
                test    byte ptr ds:spell_active_flag, 0FFh
                jnz     short loc_87F1
                test    byte ptr ds:altkey_latch, 0FFh
                jnz     short loc_87C7
                retn
; ---------------------------------------------------------------------------

loc_87C7:        
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                test    byte ptr ds:sword_swing_flag, 0FFh
                jz      short loc_87D9
                retn
; ---------------------------------------------------------------------------

loc_87D9:        
                test    byte ptr ds:byte_FF3E, 0FFh
                jz      short loc_87E1
                retn
; ---------------------------------------------------------------------------

loc_87E1:        
                mov     ds:byte_9F2B, 0
                mov     byte ptr ds:spell_active_flag, 0FFh
                mov     byte ptr ds:soundFX_request, 23
                retn
; ---------------------------------------------------------------------------

loc_87F1:        
                add     ds:byte_9F2B, 2
                cmp     ds:byte_9F2B, 4
                jz      short loc_880B
                cmp     ds:byte_9F2B, 6
                jnb     short loc_8805
                retn
; ---------------------------------------------------------------------------

loc_8805:        
                mov     byte ptr ds:spell_active_flag, 0
                retn
; ---------------------------------------------------------------------------

loc_880B:        
                mov     bl, ds:current_magic_spell  ; 1..7
                dec     bl
                xor     bh, bh
                test    byte ptr ds:spells_espada[bx], 0FFh
                jnz     short loc_881B
                retn
; ---------------------------------------------------------------------------

loc_881B:        
                dec     byte ptr ds:spells_espada[bx]
                call    cs:Print_Magic_Left_Decimal_proc
                mov     byte ptr ds:soundFX_request, 24
                mov     si, offset magic_projectiles
                mov     byte ptr ds:byte_FF3E, 0FFh
                mov     bl, ds:current_magic_spell
                dec     bl  ; 0..6
                xor     bh, bh
                add     bx, bx
                jmp     ds:funcs_883B[bx]
magic_spell_fire_handler endp

; ---------------------------------------------------------------------------
funcs_883B      dw offset init_magic_projectile ; espada
                dw offset init_magic_projectile ; saeta
                dw offset init_magic_projectile ; fuego
                dw offset init_magic_projectile ; lanzar
                dw offset init_rascar
                dw offset init_agua
                dw offset init_guerra

; =============== S U B R O U T I N E =======================================


init_magic_projectile proc near 
                mov     al, ds:facing_direction
                not     al
                and     al, 1
                mov     [si+magic_projectile.mp_dir], al
                mov     al, ds:squat_flag
                and     al, 1
                add     al, ds:hero_head_y_in_viewport
                add     al, ds:viewport_top_row_y
                and     al, 3Fh
                mov     [si+magic_projectile.mp_y_rel], al
                mov     al, ds:hero_x_in_viewport
                add     al, 4
                mov     ah, [si+magic_projectile.mp_dir]
                not     ah
                and     ah, 1
                add     al, ah
                xor     ah, ah
                add     ax, ds:proximity_map_left_col_x
                cmp     ax, ds:mapWidth
                jb      short loc_8888
                sub     ax, ds:mapWidth

loc_8888:        
                mov     [si+magic_projectile.mp_x_rel], ax
                mov     byte ptr [si+magic_projectile.mp_vram_addr_tile00+1], 0
                mov     byte ptr [si+magic_projectile.mp_vram_addr_tile10+1], 0
                mov     byte ptr [si+magic_projectile.mp_vram_addr_tile01+1], 0
                mov     byte ptr [si+magic_projectile.mp_vram_addr_tile11+1], 0
                mov     [si+magic_projectile.mp_life_timer], 0
                mov     [si+magic_projectile.mp_anim_frame], 0
                mov     word ptr [si+16], 0FFFFh ; terminate
                retn
init_magic_projectile endp


; =============== S U B R O U T I N E =======================================


init_rascar     proc near 
                mov     cx, 4

four_beams_of_rascar:     
                push    cx
                mov     al, 6
                mul     cl
                add     ax, 2
                add     ax, ds:proximity_map_left_col_x
                cmp     ax, ds:mapWidth
                jb      short loc_88C1
                sub     ax, ds:mapWidth

loc_88C1:        
                mov     [si], ax
                call    cs:get_random_proc
                and     al, 3
                mov     ah, ds:viewport_top_row_y
                sub     ah, 3
                sub     ah, al
                and     ah, 3Fh
                mov     [si+2], ah
                mov     byte ptr [si+9], 0
                mov     byte ptr [si+0Bh], 0
                mov     byte ptr [si+0Dh], 0
                mov     byte ptr [si+0Fh], 0
                mov     byte ptr [si+4], 0
                mov     byte ptr [si+5], 0
                add     si, 10h
                pop     cx
                loop    four_beams_of_rascar
                retn
init_rascar     endp


; =============== S U B R O U T I N E =======================================


init_agua       proc near 
                push    si
                mov     cx, 3

loc_88FC:        
                push    cx
                call    init_magic_projectile
                add     si, 10h
                pop     cx
                loop    loc_88FC
                pop     si
                sub     byte ptr [si+2], 2
                and     byte ptr [si+2], 3Fh
                add     byte ptr [si+12h], 2
                and     byte ptr [si+12h], 3Fh
                retn
init_agua       endp


; =============== S U B R O U T I N E =======================================


init_guerra     proc near 
                mov     ds:byte_9EED, 0FFh
                mov     ds:byte_9EEE, 0FFh
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_8930
                test    byte ptr ds:boss_being_hit, 0FFh
                jnz     short loc_8954

loc_8930:        
                mov     si, ds:viewport_left_top_addr
                sub     si, 36          ; up from hero
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     cx, 19

rows_19:         
                push    cx
                mov     cx, 36

columns_36:      
                push    cx
                test    byte ptr [si], 80h
                jz      short loc_894A
                call    mark_proximity_monster_as_spell_target

loc_894A:        
                inc     si
                pop     cx
                loop    columns_36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                pop     cx
                loop    rows_19

loc_8954:        
                mov     byte ptr ds:byte_FF3E, 0
                mov     byte ptr ds:soundFX_request, 25
                call    cs:Render_Viewport_Border_Walls_proc
                mov     byte ptr ds:altkey_latch, 0
                call    clear_viewport_buffer
                jmp     main_update_render
init_guerra     endp


; =============== S U B R O U T I N E =======================================


update_active_projectiles_render proc near ; ...
                mov     si, offset magic_projectiles
                mov     cx, 4

next_magic_projectile:    
                cmp     [si+magic_projectile.mp_x_rel], 0FFFFh
                jnz     short loc_897A
                retn
; ---------------------------------------------------------------------------

loc_897A:        
                push    cx
                call    projectile_erase_old_tiles
                cmp     byte ptr [si+1], 0FFh
                jnz     short loc_898B
                mov     [si+magic_projectile.mp_x_rel], 0FFFFh
                jmp     loc_8A2B
; ---------------------------------------------------------------------------

loc_898B:        
                mov     bl, [si+magic_projectile.mp_anim_frame]
                add     bl, bl
                add     bl, bl
                xor     bh, bh
                mov     al, ds:current_magic_spell
                dec     al
                add     al, al
                xor     ah, ah
                mov     di, offset sequences0
                test    [si+magic_projectile.mp_dir], 0FFh
                jnz     short loc_89A9
                mov     di, offset sequences1

loc_89A9:        
                add     di, ax
                mov     di, [di]
                add     di, bx
                mov     ax, [si+magic_projectile.mp_x_rel]
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.
                jb      short loc_8A2B
                mov     [si+magic_projectile.mp_cached_x_offset_tiles], bl
                mov     al, [si+magic_projectile.mp_y_rel]
                sub     al, ds:viewport_top_row_y
                and     al, 3Fh
                mov     [si+magic_projectile.mp_cached_y_offset], al
                mov     bh, al
                xchg    bh, bl
                push    si
                add     si, 8
                mov     bp, offset byte_8C79
                mov     cx, 4

loc_89D3:        
                push    cx
                push    bx
                push    bp
                add     bh, ds:[bp+0]
                mov     al, bh
                sub     al, 4
                cmp     al, 28
                jnb     short outside_viewport
                inc     bp
                add     bl, ds:[bp+0]
                and     bl, 3Fh
                cmp     bl, 18
                jnb     short outside_viewport
                mov     al, [di]   ; tile index to render
                push    di
                push    ax
                mov     ax, bx
                push    ax
                call    proximity_map_coords_to_viewport_offset ; AL: proximity map relative y
                                        ; AH: proximity map relative x
                                        ; Return: address in DI
                pop     ax
                cmp     byte ptr [di], 0FFh
                jz      short loc_8A1E
                cmp     byte ptr [di], 0FCh
                jz      short loc_8A1E
                call    cs:Viewport_Coords_To_Screen_Addr_proc ; AL: y
                                        ; AH: x
                                        ; Returns video memory address in DI
                or      di, 8000h
                mov     [si], di
                and     di, 7FFFh
                pop     ax
                push    si
                call    cs:Uncompress_And_Render_Tile_proc ; AL: tile index
                                        ; DI: screen address
                pop     si
                pop     di
                jmp     short outside_viewport
; ---------------------------------------------------------------------------

loc_8A1E:        
                pop     ax
                pop     di

outside_viewport:
                pop     bp
                inc     si
                inc     si
                inc     di
                inc     bp
                inc     bp
                pop     bx
                pop     cx
                loop    loc_89D3
                pop     si

loc_8A2B:        
                add     si, 16
                pop     cx
                loop    next_magic_projectile_
                jmp     short locret_8A36
; ---------------------------------------------------------------------------

next_magic_projectile_:   
                jmp     next_magic_projectile
; ---------------------------------------------------------------------------

locret_8A36:     
                retn
update_active_projectiles_render endp


; =============== S U B R O U T I N E =======================================


projectile_erase_old_tiles proc near
                test    word ptr [si+magic_projectile.mp_vram_addr_tile00], 8000h
                jz      short loc_8A51
                and     word ptr [si+magic_projectile.mp_vram_addr_tile00], 7FFFh
                mov     dx, [si+magic_projectile.mp_vram_addr_tile00]
                mov     ah, [si+magic_projectile.mp_cached_x_offset_tiles]
                mov     al, [si+magic_projectile.mp_cached_y_offset]
                push    si
                call    restore_bg_tile_at_given_position
                pop     si

loc_8A51:        
                test    word ptr [si+magic_projectile.mp_vram_addr_tile10], 8000h
                jz      short loc_8A6D
                and     word ptr [si+magic_projectile.mp_vram_addr_tile10], 7FFFh
                mov     dx, [si+magic_projectile.mp_vram_addr_tile10]
                mov     ah, [si+magic_projectile.mp_cached_x_offset_tiles]
                inc     ah
                mov     al, [si+magic_projectile.mp_cached_y_offset]
                push    si
                call    restore_bg_tile_at_given_position
                pop     si

loc_8A6D:        
                test    word ptr [si+magic_projectile.mp_vram_addr_tile01], 8000h
                jz      short loc_8A8B
                and     word ptr [si+magic_projectile.mp_vram_addr_tile01], 7FFFh
                mov     dx, [si+magic_projectile.mp_vram_addr_tile01]
                mov     ah, [si+magic_projectile.mp_cached_x_offset_tiles]
                mov     al, [si+magic_projectile.mp_cached_y_offset]
                inc     al
                and     al, 3Fh
                push    si
                call    restore_bg_tile_at_given_position
                pop     si

loc_8A8B:        
                test    word ptr [si+magic_projectile.mp_vram_addr_tile11], 8000h
                jnz     short loc_8A93
                retn
; ---------------------------------------------------------------------------

loc_8A93:        
                and     word ptr [si+magic_projectile.mp_vram_addr_tile11], 7FFFh
                mov     dx, [si+magic_projectile.mp_vram_addr_tile11]
                mov     ah, [si+magic_projectile.mp_cached_x_offset_tiles]
                inc     ah
                mov     al, [si+magic_projectile.mp_cached_y_offset]
                inc     al
                and     al, 3Fh
                push    si
                call    restore_bg_tile_at_given_position
                pop     si
                retn
projectile_erase_old_tiles endp


; =============== S U B R O U T I N E =======================================


dispatch_spell_projectile_movement proc near
                test    byte ptr ds:byte_FF3E, 0FFh
                jnz     short loc_8AB5
                retn
; ---------------------------------------------------------------------------

loc_8AB5:        
                mov     si, offset magic_projectiles
                mov     bl, ds:current_magic_spell
                dec     bl
                xor     bh, bh
                add     bx, bx
                jmp     ds:funcs_8AC2[bx]
dispatch_spell_projectile_movement endp

; ---------------------------------------------------------------------------
funcs_8AC2      dw offset espada_move
                dw offset saeta_move
                dw offset fuego_move
                dw offset saeta_move
                dw offset rascar_move
                dw offset agua_move
                dw offset locret_8B9C

; =============== S U B R O U T I N E =======================================


espada_move     proc near 
                test    [si+magic_projectile.mp_dir], 80h
                jz      short loc_8ADD
                jmp     loc_8BB5
; ---------------------------------------------------------------------------

loc_8ADD:        
                inc     [si+magic_projectile.mp_life_timer]
                cmp     [si+magic_projectile.mp_life_timer], 5  ; espada lives 5 ticks
                jb      short espada_alive
                jmp     loc_8BB5
; ---------------------------------------------------------------------------

espada_alive:        
                call    sub_8BC2
                call    monster_is_in_spawn_range_and_clear
                jnb     short loc_8AF2
                retn
; ---------------------------------------------------------------------------

loc_8AF2:        
                or      [si+magic_projectile.mp_dir], 80h
                retn
espada_move     endp


; =============== S U B R O U T I N E =======================================


saeta_move      proc near 
                inc     [si+magic_projectile.mp_life_timer]
                cmp     [si+magic_projectile.mp_life_timer], 0Ah
                jb      short loc_8B03
                jmp     loc_8BB5
; ---------------------------------------------------------------------------

loc_8B03:        
                call    sub_8BC2
                jmp     monster_is_in_spawn_range_and_clear
saeta_move      endp


; =============== S U B R O U T I N E =======================================


fuego_move      proc near 
                inc     [si+magic_projectile.mp_life_timer]
                cmp     [si+magic_projectile.mp_life_timer], 0Ch
                jb      short loc_8B15
                jmp     loc_8BB5
; ---------------------------------------------------------------------------

loc_8B15:        
                cmp     [si+magic_projectile.mp_life_timer], 4
                jnb     short loc_8B20
                call    loc_8BD0
                jmp     short loc_8B61
; ---------------------------------------------------------------------------

loc_8B20:        
                and     [si+magic_projectile.mp_anim_frame], 3
                inc     [si+magic_projectile.mp_anim_frame]
                cmp     [si+magic_projectile.mp_life_timer], 3
                jz      short loc_8B61
                mov     ax, [si+magic_projectile.mp_x_rel]
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.
                jc      short loc_8B61
                cmp     bl, 33
                jnb     short loc_8B61
                mov     ah, bl
                mov     al, [si+magic_projectile.mp_y_rel]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                xchg    si, di
                add     si, 72
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                mov     al, [di]
                call    is_blocking_tile ; ZF if can pass
                jnz     short loc_8B61
                mov     al, [di+1]
                call    is_blocking_tile ; ZF if can pass
                jnz     short loc_8B61
                inc     [si+magic_projectile.mp_y_rel]
                and     [si+magic_projectile.mp_y_rel], 3Fh

loc_8B61:        
                jmp     monster_is_in_spawn_range_and_clear
fuego_move      endp


; =============== S U B R O U T I N E =======================================


rascar_move     proc near 
                inc     [si+magic_projectile.mp_life_timer]
                cmp     [si+magic_projectile.mp_life_timer], 0Ch
                jnb     short loc_8B9D
                mov     cx, 4

loc_8B70:        
                push    cx
                add     [si+magic_projectile.mp_y_rel], 2
                and     [si+magic_projectile.mp_y_rel], 3Fh
                call    monster_is_in_spawn_range_and_clear
                add     si, 10h
                pop     cx
                loop    loc_8B70
                retn
rascar_move     endp


; =============== S U B R O U T I N E =======================================


agua_move       proc near 
                inc     [si+magic_projectile.mp_life_timer]
                cmp     [si+magic_projectile.mp_life_timer], 0Ah
                jnb     short loc_8BA5
                mov     cx, 3

loc_8B8F:        
                push    cx
                call    sub_8BC2
                call    monster_is_in_spawn_range_and_clear
                add     si, 10h
                pop     cx
                loop    loc_8B8F

locret_8B9C:     
                retn
; ---------------------------------------------------------------------------

loc_8B9D:        
                mov     byte ptr [si+30h], 0
                mov     byte ptr [si+31h], 0FFh

loc_8BA5:        
                mov     byte ptr [si+20h], 0
                mov     byte ptr [si+21h], 0FFh
                mov     byte ptr [si+10h], 0
                mov     byte ptr [si+11h], 0FFh

loc_8BB5:        
                mov     byte ptr [si], 0
                mov     byte ptr [si+1], 0FFh
                mov     byte ptr ds:byte_FF3E, 0
                retn
agua_move       endp


; =============== S U B R O U T I N E =======================================


sub_8BC2        proc near 
                mov     al, [si+magic_projectile.mp_anim_frame]
                inc     al
                cmp     al, 3
                jb      short loc_8BCD
                xor     al, al

loc_8BCD:        
                mov     [si+magic_projectile.mp_anim_frame], al

loc_8BD0:        
                mov     ax, [si+magic_projectile.mp_x_rel]
                mov     bl, [si+magic_projectile.mp_dir]
                and     bx, 1
                add     bx, bx
                add     bx, bx
                dec     bx
                dec     bx
                add     ax, bx
                or      ax, ax
                jns     short loc_8BEA
                add     ax, ds:mapWidth
                jmp     short loc_8BF4
; ---------------------------------------------------------------------------

loc_8BEA:        
                cmp     ax, ds:mapWidth
                jb      short loc_8BF4
                sub     ax, ds:mapWidth

loc_8BF4:        
                mov     [si], ax
                retn
sub_8BC2        endp


; =============== S U B R O U T I N E =======================================


monster_is_in_spawn_range_and_clear proc near ; ...
                test    byte ptr ds:is_boss_cavern, 0FFh
                jz      short loc_8C07
                test    byte ptr ds:boss_being_hit, 0FFh
                stc
                jz      short loc_8C07
                retn
; ---------------------------------------------------------------------------

loc_8C07:        
                mov     ax, [si+magic_projectile.mp_x_rel]
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.
                jnc     short loc_8C0F
                retn
; ---------------------------------------------------------------------------

loc_8C0F:        
                mov     ah, bl
                sub     bl, 2
                cmp     bl, 20h ; ' '
                cmc
                jnb     short loc_8C1B
                retn
; ---------------------------------------------------------------------------

loc_8C1B:        
                mov     al, [si+magic_projectile.mp_y_rel]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                push    si
                xchg    di, si
                sub     si, 37
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                mov     ds:byte_9F2A, 0
                mov     cx, 3

loc_8C32:        
                push    cx
                mov     cx, 3

loc_8C36:        
                push    cx
                call    mark_proximity_monster_as_spell_target
                pop     cx
                inc     si
                loop    loc_8C36
                add     si, 33
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                pop     cx
                loop    loc_8C32
                pop     si
                mov     al, ds:byte_9F2A
                add     al, al
                cmc
                retn
monster_is_in_spawn_range_and_clear endp


; =============== S U B R O U T I N E =======================================


mark_proximity_monster_as_spell_target proc near
                call    get_dst_monster_flags ; CF: no monster/item; NC: monster/item (NZ: non-passable, ZF: flying)
                                              ; AL = monster.flags; BX = monster struct
                jnc     short loc_8C55
                retn
; ---------------------------------------------------------------------------

loc_8C55:        
                test    al, 20h
                jz      short loc_8C5A
                retn
; ---------------------------------------------------------------------------

loc_8C5A:        
                test    [bx+monster.ai_flags], 20h
                jz      short loc_8C61
                retn
; ---------------------------------------------------------------------------

loc_8C61:        
                mov     al, [bx+monster.ai_flags]
                or      al, 40h
                and     al, 0E0h
                mov     ah, ds:current_magic_spell
                inc     ah
                or      al, ah
                mov     [bx+monster.ai_flags], al
                mov     ds:byte_9F2A, 0FFh
                retn
mark_proximity_monster_as_spell_target endp

; ---------------------------------------------------------------------------
byte_8C79       db 0, 0, 1, 0, 0, 1, 1, 1
sequences0      dw offset byte_8C99
                dw offset byte_8CA5
                dw offset byte_8CBD
                dw offset byte_8CE5
                dw offset byte_8CFD
                dw offset byte_8D01
sequences1      dw offset byte_8C99
                dw offset byte_8CB1
                dw offset byte_8CD1
                dw offset byte_8CF1
                dw offset byte_8CFD
                dw offset byte_8D0D
byte_8C99       db 67h, 68h, 69h, 6Ah, 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 70h, 71h, 72h
byte_8CA5       db 67h, 68h, 69h, 6Ah, 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 70h, 71h, 72h
byte_8CB1       db 73h, 74h, 75h, 76h, 77h, 78h, 79h, 7Ah, 7Bh, 7Ch, 7Dh, 7Eh
byte_8CBD       db 67h, 68h, 69h, 6Ah, 6Fh, 70h, 71h, 72h, 73h, 74h, 75h, 76h, 77h, 78h, 79h, 7Ah, 7Bh, 7Ch, 7Dh, 7Eh
byte_8CD1       db 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 70h, 71h, 72h, 73h, 74h, 75h, 76h, 77h, 78h, 79h, 7Ah, 7Bh, 7Ch, 7Dh, 7Eh
byte_8CE5       db 67h, 68h, 69h, 6Ah, 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 70h, 71h, 72h
byte_8CF1       db 73h, 74h, 75h, 76h, 77h, 78h, 79h, 7Ah, 7Bh, 7Ch, 7Dh, 7Eh
byte_8CFD       db 73h, 74h, 75h, 76h
byte_8D01       db 67h, 68h, 69h, 6Ah, 6Bh, 6Ch, 6Dh, 6Eh, 6Fh, 70h, 71h, 72h
byte_8D0D       db 73h, 74h, 75h, 76h, 77h, 78h, 79h, 7Ah, 7Bh, 7Ch, 7Dh, 7Eh


; ===========================================================================
; Main monster AI tick (called once per frame from main_update_render).
; Boss/Jashiin caverns: delegate entirely to Monster_AI_proc (eai binary).
; Regular caverns:
;   Iterates the monsters_table (each 16-byte monster struct).
;   For each monster:
;     - Skip if high byte of currX == 0xFF (stationary item, not a creature).
;     - Call is_in_proximity_window: if monster is outside proximity window, skip.
;     - Set m_x_rel = BL (relative X position in proximity window).
;     - Write monster index | 0x80 to proximity map (primary + second layer).
;     - If monster.state_flags bit 4: also stamp 2 rows below (big monster lower half).
;     - If state_flags bit 5 is clear: call monster_activation (spawn check).
;     - Else: increment monster.counter, call Monster_AI_proc on activation.
;
; MONSTER TABLE ENTRY (16 bytes, monster struc from dungeon.inc):
;   [0..1] currX     : absolute map X (0xFFFF = end of table)
;   [2]    currY     : absolute map Y (0-63)
;   [3]    m_x_rel   : relative X in proximity window (0-34), 0xFF = out of range
;   [4]    flags     : monster type / behavior flags
;   [5]    ai_flags  : AI state bits (bit6=spell-hit, bits4:0=spell-type)
;   [6]    anim_counter
;   [7]    state_flags: bit4=big monster, bit5=active-spawned, bit7=state-active
;   [8..9] spwnX     : respawn X (0xFFFF = no respawn)
;   [A]    spwnY     : respawn Y
;   [B]    type_     : original type byte for respawn
;   [C]    counter   : general purpose counter
;   [D]    save_addr : savegame achievement address (for items)
;   [E..F] ai_state/hp
; ===========================================================================
monsters_spawning proc near   
                mov     si, ds:monsters_table_addr
                mov     al, ds:is_boss_cavern
                or      al, ds:is_jashiin_cavern
                jz      short loc_8D2B
                jmp     cs:Monster_AI_proc
; ---------------------------------------------------------------------------

loc_8D2B:        
                mov     byte ptr ds:monster_index, 0

next_monster2:    
                mov     ax, [si+monster.currX]
                cmp     ax, 0FFFFh      ; end-monsters-marker
                jnz     short loc_8D38
                retn                    ; all monsters processed
; ---------------------------------------------------------------------------

loc_8D38:        
                mov     [si+monster.m_x_rel], 0FFh
                cmp     ah, 0FFh    ; 
                je      short skip
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.
                jc      short skip
                mov     [si+monster.m_x_rel], bl
                call    place_monster_in_proximity_and_run_ai
                cmp     byte ptr [si+1], 0FFh ; monster x coord high byte; ff => stationary item
                je      short skip
                mov     ax, word ptr [si+monster.currY] ; al=currY, ah=m_x_rel
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     bl, ds:monster_index
                xor     bh, bh
                mov     al, bl
                or      al, 80h ; new = monster_index | 80h
                xchg    al, [di] ; old = [prox]; [prox] = new
                mov     ds:proximity_second_layer[bx], al ; second[monster_index] = old
                                        ; proximity map is designed to keep only one item
                                        ; at given address. So when we need to put other object,
                                        ; when position is already occupied by monster,
                                        ; we use second layer: 128 bytes of additional buffer
                                        ; (1 byte per monster id)
                test    [si+monster.flags], 10001b
                jnz     short skip
                test    [si+monster.state_flags], 10000b
                jz      short skip
                xchg    si, di ; si=monster_prox_addr, di points to monster struct
                add     si, 2*36 ; si=monster_prox_addr+2*36 (below upper 2x2 tiles)
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di ; di=monster_bottom_prox_addr, si points to monster struct
                mov     bl, ds:monster_index
                inc     bl ; bl=monster_index+1
                xor     bh, bh
                mov     al, bl
                or      al, 80h
                xchg    al, [di]
                mov     ds:proximity_second_layer[bx], al ; proximity map is designed to keep only one item
                                        ; at given address. So when we need to put other object,
                                        ; when position is already occupied by monster,
                                        ; we use second layer: 128 bytes of additional buffer
                                        ; (1 byte per monster id)
skip:            
                test    [si+monster.state_flags], 100000b
                jnz     short loc_8DA5
                mov     al, [si+monster.counter]
                inc     al
                jz      short loc_8DA0
                mov     [si+monster.counter], al

loc_8DA0:        
                jnz     short loc_8DA5
                call    monster_activation ; pass si (pointer to monster struct)

loc_8DA5:        
                inc     byte ptr ds:monster_index
                add     si, 16
                jmp     short next_monster2
monsters_spawning endp


; ===========================================================================
; Places a monster in the proximity map and optionally runs its AI.
;
; 1. Converts currX/currY to proximity map address (coords_in_ax_to_proximity).
; 2. Processes the 'spell target' flag (ai_flags bit 6 → flags bit 5).
; 3. Reads proximity_second_layer[monster_index] and writes it to [di]
;    (preserves any existing tile if second layer was occupied).
; 4. For big monsters (state_flags bit 4): also stamps [di + 2*36].
;
; Item/monster type switch (flags bits 4:0):
;   0x00-0x0F: regular monster → call Monster_AI_proc
;   0x10 (flag_10): drop-item trigger (falling item / platform drop)
;   0x11 (flag_11): projectile spawner (aims at hero Y, triggers shot at range)
;   0x12 (flag_12): delay animation
;   0x13 (flag_13): item pickup — contact collision check
;   0x14/0x15/0x1B (flag_14): almas orb — falling, picked up on contact
;     almas count: flags&0x0F: 4→1 almas, 5→10 almas, else→100 almas
;   0x16 (flag_16): ordinary key pickup
;   0x17 (flag_17): lion's head key pickup
;   0x18 (flag_18): small potion (red) → healing_potion_timer += 0x0A
;   0x19 (flag_19): large potion (blue) → healing_potion_timer += heroMaxHP/8
;   0x1A (flag_1a): shoes pickup (Ruzeria/Pirika/Silkarn based on cavern_level-4)
;   0x1B: see 0x14
;   0x1C (flag_1c): dungeon sign → render_cavern_signs
;   0x1D (flag_1d): hero's crest pickup
;   0x1E (flag_1e): Feruza shoes pickup
;   0x00-0x0F (default, flag_10 handled above): chest animation dispatch:
;     chest sub-types: 50g / 100g / empty / 500g / 1000g / glory crest / enchantment sword
;
; On item pickup (loc_914C): set currX high byte to 0xFF00 (mark as collected),
; optionally write the item's save achievement bitmask to savegame.
;
; SPRITE NOTE: Items use enp?.grp 2×2 tiles. The frame to display is encoded
; in monster.flags low nibble (see ENP1_FRAMES lookup in grp_viewer.py).
; ===========================================================================
place_monster_in_proximity_and_run_ai proc near
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     al, [si+monster.ai_flags]
                and     al, 0DFh
                test    al, 40h
                jz      short loc_8DC7
                test    [si+monster.flags], 20h
                jnz     short loc_8DC5
                or      al, 20h

loc_8DC5:        
                and     al, 0BFh

loc_8DC7:        
                mov     [si+monster.ai_flags], al
                mov     al, ds:monster_index
                mov     bx, offset proximity_second_layer ; proximity map is designed to keep only one item
                                        ; at given address. So when we need to put other object,
                                        ; when position is already occupied by monster,
                                        ; we use second layer: 128 bytes of additional buffer
                                        ; (1 byte per monster id)
                xlat
                mov     [di], al
                test    [si+monster.flags], 11h
                jnz     short loc_8DF1
                test    [si+monster.state_flags], 10h
                jz      short loc_8DF1
                xchg    si, di
                add     si, 2*36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                mov     al, ds:monster_index
                inc     al
                xlat
                mov     [di], al

loc_8DF1:        
                test    [si+monster.flags], 11000b
                jnz     short loc_8DFC
                jmp     cs:Monster_AI_proc
; ---------------------------------------------------------------------------

loc_8DFC:        
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_8DFE:        
                xor     bh, bh
                mov     bl, [si+monster.flags]
                and     bl, 1Fh
                sub     bl, 10h
                jnb     short loc_8E0E
                jmp     loc_90E6
; ---------------------------------------------------------------------------

loc_8E0E:        
                add     bx, bx          ; switch 15 cases
                jmp     ds:jpt_8E10[bx] ; switch jump
; ---------------------------------------------------------------------------
jpt_8E10        dw offset flag_10
                dw offset flag_11
                dw offset flag_12
                dw offset flag_13
                dw offset flag_14_15_1b
                dw offset flag_14_15_1b
                dw offset flag_16
                dw offset flag_17
                dw offset flag_18
                dw offset flag_19
                dw offset flag_1a
                dw offset flag_14_15_1b
                dw offset flag_1c
                dw offset flag_1d
                dw offset flag_1e
; ---------------------------------------------------------------------------

flag_10:         
                test    [si+monster.ai_timer], 1 ; jumptable 00008E10 case 0
                jnz     short loc_8E54
                test    [si+monster.ai_flags], 100000b
                jnz     short loc_8E3F
                retn
; ---------------------------------------------------------------------------

loc_8E3F:        
                mov     byte ptr ds:soundFX_request, 18
                and     [si+monster.ai_flags], 10010000b
                and     [si+monster.flags], 1111111b
                or      [si+monster.flags], 1100000b
                or      [si+monster.ai_timer], 1

loc_8E54:        
                add     [si+monster.anim_counter], 80h
                jc      short loc_8E5B
                retn
; ---------------------------------------------------------------------------

loc_8E5B:        
                inc     [si+monster.anim_counter]
                cmp     [si+monster.anim_counter], 4
                jnb     short loc_8E65
                retn
; ---------------------------------------------------------------------------

loc_8E65:        
                mov     [si+monster.anim_counter], 0
                mov     al, [si+monster.ai_state]
                or      al, al
                jnz     short loc_8E73
                jmp     loc_914C
; ---------------------------------------------------------------------------

loc_8E73:        
                test    al, 10h
                jz      short loc_8E81
                or      al, 60h
                or      [si+monster.state_flags], 80h
                mov     [si+monster.counter], 0

loc_8E81:        
                mov     [si+monster.flags], al
                and     [si+monster.ai_flags], 80h
                mov     [si+monster.ai_state], 0
                retn
; ---------------------------------------------------------------------------

flag_11:         
                test    [si+monster.ai_timer], 1 ; jumptable 00008E10 case 1
                jnz     short loc_8ECA
                mov     ah, [si+monster.currY]
                sub     ah, 3
                and     ah, 3Fh
                cmp     ah, ds:hero_y_absolute
                je      short loc_8EA3
                retn
; ---------------------------------------------------------------------------

loc_8EA3:        
                mov     al, ds:hero_x_in_viewport
                add     al, 3
                mov     ah, ds:facing_direction
                and     ah, LEFT
                add     ah, ah
                add     al, ah
                mov     cx, 2

loc_8EB6:        
                cmp     al, [si+monster.m_x_rel]
                je      short loc_8EC0
                inc     al
                loop    loc_8EB6
                retn
; ---------------------------------------------------------------------------

loc_8EC0:        
                mov     byte ptr ds:soundFX_request, 18
                or      [si+monster.ai_timer], 1
                retn
; ---------------------------------------------------------------------------

loc_8ECA:        
                and     [si+monster.flags], 7Fh
                call    move_monster_S
                add     [si+monster.anim_counter], 80h
                jc      short loc_8ED8
                retn
; ---------------------------------------------------------------------------

loc_8ED8:        
                inc     [si+monster.anim_counter]
                cmp     [si+monster.anim_counter], 4
                jnb     short loc_8EE2
                retn
; ---------------------------------------------------------------------------

loc_8EE2:        
                mov     [si+monster.anim_counter], 0
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_12:         
                inc     [si+monster.anim_counter] ; jumptable 00008E10 case 2
                cmp     [si+monster.anim_counter], 3
                je      short loc_8EF3
                retn
; ---------------------------------------------------------------------------

loc_8EF3:        
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_13:         
                call    check_monster_aligned_to_hero_and_tick ; jumptable 00008E10 case 3
                jnb     short loc_8EFC
                retn
; ---------------------------------------------------------------------------

loc_8EFC:        
                mov     byte ptr ds:soundFX_request, 20
                test    [si+monster.anim_counter], 0Fh
                jnz     short chest
                mov     al, [si+monster.ai_state]
                test    al, 10h
                jz      short loc_8F18
                or      al, 60h
                or      [si+monster.state_flags], 80h
                mov     [si+monster.counter], 0

loc_8F18:        
                mov     [si+monster.flags], al
                mov     [si+monster.ai_state], 0
                retn
; ---------------------------------------------------------------------------

chest:           
                call    loc_914C
                mov     bl, [si+monster.anim_counter]
                and     bl, 0Fh         ; chest type (1..8)
                dec     bl
                add     bl, bl
                xor     bh, bh
                jmp     ds:off_8F33[bx]
; ---------------------------------------------------------------------------
off_8F33        dw offset got_50_gold
                dw offset got_100_gold
                dw offset loc_8F59
                dw offset got_500_gold
                dw offset got_1000_gold
                dw offset got_crest_of_glory
                dw offset got_ench_sword
; ---------------------------------------------------------------------------

got_50_gold:     
                mov     dx, offset you_get_50_gold_str
                call    render_notification_string
                mov     ax, 50
                jmp     hero_got_gold   ; ax: gold to add
; ---------------------------------------------------------------------------

got_100_gold:    
                mov     dx, offset you_get_100_gold_str
                call    render_notification_string
                mov     ax, 100
                jmp     hero_got_gold   ; ax: gold to add
; ---------------------------------------------------------------------------

loc_8F59:        
                mov     dx, offset nothing_in_the_box_str
                jmp     render_notification_string
; ---------------------------------------------------------------------------

got_500_gold:    
                mov     dx, offset you_get_500_gold_str
                call    render_notification_string
                mov     ax, 500
                jmp     hero_got_gold   ; ax: gold to add
; ---------------------------------------------------------------------------

got_1000_gold:   
                mov     dx, offset you_get_1000_gold_str
                call    render_notification_string
                mov     ax, 1000
                jmp     hero_got_gold   ; ax: gold to add
; ---------------------------------------------------------------------------

got_crest_of_glory:       
                mov     dx, offset you_get_glory_crest_str
                call    render_notification_string
                mov     byte ptr ds:crest_of_glory, 0FFh
                retn
; ---------------------------------------------------------------------------

got_ench_sword:        
                mov     dx, offset get_enchantment_sword_str
                call    render_notification_string
                push    si
                call    cs:Flush_Ui_Element_If_Dirty_proc
                mov     byte ptr ds:sword_type, SWORD_ENCHANTMENT
                mov     al, 6
                mov     bx, 18ABh
                call    cs:Render_Sword_Item_Sprite_20x18_proc
                mov     ah, ds:sword_type
                mov     al, 4           ; fn4_load_sword_graphics
                call    cs:res_dispatcher_proc
                pop     si
                retn
; ---------------------------------------------------------------------------

flag_14_15_1b:   
                call    move_monster_S  ; jumptable 00008E10 cases 4,5,11
                inc     [si+monster.anim_counter]
                and     [si+monster.anim_counter], 3
                call    check_monster_aligned_to_hero_and_tick
                jnb     short almas_picked_up
                retn
; ---------------------------------------------------------------------------

almas_picked_up: 
                mov     byte ptr ds:soundFX_request, 16
                mov     al, [si+monster.flags]
                and     al, 0Fh         ; monster almas price:
                                        ; 4 => 1 almas
                                        ; 5 => 10 almas
                                        ; else => 100 almas
                cmp     al, 4
                jnz     short loc_8FD2
                mov     ax, 1
                call    hero_got_almas  ; ax: almas to add
                jmp     loc_914C
; ---------------------------------------------------------------------------

loc_8FD2:        
                cmp     al, 5
                jnz     short got_100_almas
                mov     ax, 10
                call    hero_got_almas  ; ax: almas to add
                jmp     loc_914C
; ---------------------------------------------------------------------------

got_100_almas:   
                mov     ax, 100
                call    hero_got_almas  ; ax: almas to add
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_16:         
                mov     dx, offset you_get_key_str ; jumptable 00008E10 case 6
                call    pickup_common
                jnb     short got_ordinary_key
                retn
; ---------------------------------------------------------------------------

got_ordinary_key:
                inc     byte ptr ds:keys_amount
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_17:         
                mov     dx, offset get_lions_head_key_str ; jumptable 00008E10 case 7
                call    pickup_common
                jnb     short got_lion_head_key
                retn
; ---------------------------------------------------------------------------

got_lion_head_key:        
                inc     byte ptr ds:lion_head_keys
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_18:         
                call    check_monster_aligned_to_hero_and_tick ; jumptable 00008E10 case 8
                jnb     short loc_900E
                retn
; ---------------------------------------------------------------------------

loc_900E:        
                mov     dx, offset you_have_recovered_str
                call    render_notification_string
                add     byte ptr ds:healing_potion_timer, 10
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_19:         
                call    move_monster_S  ; jumptable 00008E10 case 9
                call    check_monster_aligned_to_hero_and_tick
                jnb     short loc_9025
                retn
; ---------------------------------------------------------------------------

loc_9025:        
                mov     dx, offset you_have_recovered_full_str
                call    render_notification_string
                mov     ax, ds:heroMaxHp
                shr     ax, 1
                shr     ax, 1
                shr     ax, 1
                inc     ax
                add     ds:healing_potion_timer, ax
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_1c:         
                mov     [si+monster.counter], 0 ; jumptable 00008E10 case 12
                test    [si+monster.ai_state], 1
                jnz     short loc_9070
                call    check_monster_aligned_to_hero_and_tick
                jnb     short loc_904C
                retn
; ---------------------------------------------------------------------------

loc_904C:        
                mov     byte ptr ds:soundFX_request, 17
                or      [si+monster.state_flags], 80h
                or      [si+monster.ai_state], 1
                mov     [si+monster.ai_timer], 0EBh
                mov     bl, [si+monster.anim_counter] ; sign index
                add     bl, bl
                xor     bh, bh
                add     bx, ds:cavern_signs_rendering_info
                push    si
                mov     si, [bx]
                call    render_cavern_signs
                pop     si
                retn
; ---------------------------------------------------------------------------

loc_9070:        
                test    [si+monster.ai_timer], 0FFh
                jz      short loc_907A
                inc     [si+monster.ai_timer]
                retn
; ---------------------------------------------------------------------------

loc_907A:        
                and     [si+monster.ai_state], 0FEh
                retn
; ---------------------------------------------------------------------------

flag_1d:         
                mov     dx, offset get_heros_crest_str ; jumptable 00008E10 case 13
                call    pickup_common
                jnb     short got_hero_crest
                retn
; ---------------------------------------------------------------------------

got_hero_crest:  
                mov     byte ptr ds:hero_crest, 0FFh
                jmp     loc_914C
; ---------------------------------------------------------------------------

flag_1e:         
                mov     dx, offset get_feruza_shoes_str ; jumptable 00008E10 case 14
                call    pickup_common
                jnb     short loc_9099
                retn
; ---------------------------------------------------------------------------

loc_9099:        
                mov     al, 1
                jmp     short put_shoes_to_inventory
; ---------------------------------------------------------------------------

flag_1a:         
                mov     al, ds:cavern_level ; jumptable 00008E10 case 10
                sub     al, 4
                mov     cl, 3
                mul     cl
                mov     di, offset shoes_strings_array
                add     di, ax
                mov     al, [di]
                mov     dx, [di+1]      ; different shoes strings
                push    ax
                call    pickup_common
                pop     ax
                jnb     short put_shoes_to_inventory
                retn
; ---------------------------------------------------------------------------

; SI points to monster struct
put_shoes_to_inventory:        
                push    ax
                mov     di, offset Feruza_Shoes

loc_90BC:        
                test    byte ptr [di], 0FFh
                jz      short free_slot_found
                inc     di              ; next accessory
                jmp     short loc_90BC
; ---------------------------------------------------------------------------

free_slot_found: 
                pop     ax
                mov     [di], al
                jmp     loc_914C
; ---------------------------------------------------------------------------
shoes_strings_array:      
                db 4
                dw offset get_ruzeria_shoes_str
                db 2
                dw offset get_pirika_shoes_str
                db 3
                dw offset get_silkarn_shoes_str
; ---------------------------------------------------------------------------

pickup_common:        
                push    dx
                call    move_monster_S
                call    check_monster_aligned_to_hero_and_tick
                pop     dx
                jnb     short loc_90DE
                retn
; ---------------------------------------------------------------------------

loc_90DE:        
                mov     byte ptr ds:soundFX_request, 17
                jmp     render_notification_string
; ---------------------------------------------------------------------------
; default_0toF_handler
loc_90E6:        
                add     byte ptr [si+monster.anim_counter], 80h
                jc      short loc_90ED
                retn
; ---------------------------------------------------------------------------

loc_90ED:        
                inc     byte ptr [si+monster.anim_counter]
                cmp     byte ptr [si+monster.anim_counter], 3
                je      short loc_90F7
                retn
; ---------------------------------------------------------------------------

loc_90F7:        
                mov     byte ptr [si+monster.counter], 0
                test    byte ptr [si+monster.state_flags], 40h
                jz      short loc_9116
                and     byte ptr [si+monster.state_flags], 0BFh
                mov     al, [si+monster.ai_timer]
                mov     cl, 16   ; size of monster struct
                mul     cl
                add     ax, ds:monsters_table_addr
                mov     di, ax
                mov     byte ptr [di+monster.currY], 0

loc_9116:        
                test    byte ptr [si+monster.state_flags], 10h
                jz      short loc_9122
                test    byte ptr [si+monster.flags], 1
                jz      short loc_914C

loc_9122:        
                mov     byte ptr [si+monster.anim_counter], 0
                mov     byte ptr [si+monster.flags], 72h
                mov     al, [si+monster.state_flags]
                and     al, 0Fh
                jnz     short loc_9132
                retn
; ---------------------------------------------------------------------------

loc_9132:        
                cmp     al, 1
                je      short loc_914C
                or      al, 70h
                or      byte ptr [si+monster.state_flags], 80h
                mov     byte ptr [si+monster.counter], 4
                mov     [si+monster.flags], al
                and     byte ptr [si+monster.ai_flags], 80h
                and     byte ptr [si+monster.state_flags], 0F0h
                retn
; ---------------------------------------------------------------------------

loc_914C:        
                mov     word ptr [si], 0FF00h
                test    byte ptr [si+monster.state_flags], 20h
                jnz     short loc_9157
                retn
; ---------------------------------------------------------------------------

loc_9157:        
                mov     di, [si+monster.spwnX] ; looks like it is proximity address, not X coord
                cmp     di, 0FFFFh  ; already spawned
                jne     short loc_9160
                retn
; ---------------------------------------------------------------------------

loc_9160:        
                mov     al, [si+monster.spwnY] ; looks like it is entity index, not Y coord
                or      [di], al
                mov     word ptr [si+monster.spwnX], 0FFFFh
                retn
place_monster_in_proximity_and_run_ai endp


; =============== S U B R O U T I N E =======================================

; ax: gold to add

; ===========================================================================
; hero_got_gold / hero_got_almas
; Add gold or almas to hero totals, capped at 0xFFFF, redraw the HUD counter.
; ===========================================================================
hero_got_gold   proc near 
                add     ds:hero_gold_lo, ax
                adc     byte ptr ds:hero_gold_hi, 0
                push    si
                call    cs:Print_Gold_Decimal_proc
                pop     si
                retn
hero_got_gold   endp


; =============== S U B R O U T I N E =======================================

; ax: almas to add

hero_got_almas  proc near 
                add     ds:hero_almas, ax
                jnc     short loc_9188
                mov     ds:hero_almas, 0FFFFh

loc_9188:        
                push    si
                call    cs:Print_Almas_Decimal_proc
                pop     si
                retn
hero_got_almas  endp


; ===========================================================================
; Returns NC (item can be picked up) only when:
;   - hero_y_absolute matches one of 4 monster Y rows
;   - hero_x_in_viewport is within ±2 of monster m_x_rel
;   - monster state_flags bit 7 is SET (active/visible)
;   - monster.counter counts up to bit 3 being set (throttles pickup rate)
; Returns CF (stc) when misaligned or inactive.
; ===========================================================================
check_monster_aligned_to_hero_and_tick proc near
                test    byte ptr ds:invincibility_flag, 0FFh
                stc
                jz      short loc_9199
                retn
; ---------------------------------------------------------------------------

loc_9199:        
                mov     ah, [si+monster.currY]
                add     ah, 2
                mov     cx, 4

loc_91A2:        
                dec     ah
                and     ah, 3Fh
                cmp     ah, ds:hero_y_absolute
                jz      short loc_91B5
                loop    loc_91A2
                and     [si+monster.state_flags], 7Fh
                stc
                retn
; ---------------------------------------------------------------------------

loc_91B5:        
                mov     al, ds:hero_x_in_viewport
                add     al, 4
                mov     ah, [si+monster.m_x_rel]
                sub     ah, 3
                mov     cx, 4

loc_91C3:        
                inc     ah
                cmp     ah, al
                jz      short loc_91D1
                loop    loc_91C3
                and     [si+monster.state_flags], 7Fh
                stc
                retn
; ---------------------------------------------------------------------------

loc_91D1:        
                test    [si+monster.state_flags], 80h
                clc
                jnz     short loc_91D9
                retn
; ---------------------------------------------------------------------------

loc_91D9:        
                inc     [si+monster.counter]
                test    [si+monster.counter], 111b
                jnz     short loc_91E3
                retn                    ; NC
; ---------------------------------------------------------------------------

loc_91E3:        
                stc
                retn
check_monster_aligned_to_hero_and_tick endp


; ===========================================================================
; move_monster_E / NE / N / NW / W / SW / S / SE
; Called by Monster_AI_proc (eai*.bin) to move a monster one step.
;
; Each direction has a range check for m_x_rel (proximity column):
;   E/NE/SE: allowed when m_x_rel <= 33 (keep inside right margin)
;   W/NW/SW: allowed when m_x_rel >= 2  (keep inside left margin)
;   N/S: allowed when m_x_rel is 1-34.
; Then calls the corresponding check_collision_X2 routine.
; If no collision: adjusts currX/currY (with map wrapping) and m_x_rel.
;
; COORDINATE SYSTEM:
;   +X = East (right), +Y = South (down) — same as screen.
;   incrementX / decrementX: wrap at mapWidth.
;   incrementY / decrementY: mask to 0x3F (map always 64 rows tall).
; ===========================================================================
move_monster_E  proc near 
                cmp     [si+monster.m_x_rel], 34 ; Movement State / Frame Counter
                                        ; if 0..33 => Carry
                cmc                     ; if 0..33 => no carry
                jnb     short loc_91ED
                retn                    ; m_x_rel >= 34; CF
; ---------------------------------------------------------------------------

loc_91ED:        
                call    check_collision_E2 ; case 0..33
                jnb     short loc_91F3
                retn
; ---------------------------------------------------------------------------

loc_91F3:        
                jmp     incrementX
move_monster_E  endp


; =============== S U B R O U T I N E =======================================


move_monster_NE proc near 
                cmp     [si+monster.m_x_rel], 34 ; Movement State / Frame Counter
                                        ; if 0..33 => Carry
                cmc
                jnb     short loc_91FE
                retn                    ; phase >= 34
; ---------------------------------------------------------------------------

loc_91FE:        
                call    check_collision_NE2
                jnb     short incX_decY
                retn
; ---------------------------------------------------------------------------

incX_decY:       
                call    incrementX
                jmp     decrementY
move_monster_NE endp


; =============== S U B R O U T I N E =======================================


move_monster_N  proc near 
                mov     al, [si+monster.m_x_rel] ; Movement State / Frame Counter
                or      al, al
                stc
                jnz     short loc_9213
                retn                    ; zero phase
; ---------------------------------------------------------------------------

loc_9213:        
                cmp     al, 35
                stc
                jnz     short loc_9219
                retn                    ; phase 35
; ---------------------------------------------------------------------------

loc_9219:        
                call    check_collision_N2
                jnb     short loc_921F
                retn
; ---------------------------------------------------------------------------

loc_921F:        
                jmp     decrementY
move_monster_N  endp


; =============== S U B R O U T I N E =======================================


move_monster_NW proc near 
                cmp     [si+monster.m_x_rel], 2
                jnb     short loc_9229
                retn                    ; phase < 2
; ---------------------------------------------------------------------------

loc_9229:        
                call    check_collision_NW2
                jnb     short decX_decY
                retn
; ---------------------------------------------------------------------------

decX_decY:       
                call    decrementX
                jmp     short decrementY
move_monster_NW endp


; =============== S U B R O U T I N E =======================================


move_monster_W  proc near 
                cmp     [si+monster.m_x_rel], 2
                jnb     short loc_923B
                retn                    ; phase < 2
; ---------------------------------------------------------------------------

loc_923B:        
                call    check_collision_W2
                jnb     short loc_9241
                retn
; ---------------------------------------------------------------------------

loc_9241:        
                jmp     short decrementX
move_monster_W  endp


; =============== S U B R O U T I N E =======================================


move_monster_SW proc near 
                cmp     [si+monster.m_x_rel], 2
                jnb     short loc_924A
                retn                    ; phase < 2
; ---------------------------------------------------------------------------

loc_924A:        
                call    check_collision_SW2
                jnb     short decX_incY_
                retn
; ---------------------------------------------------------------------------

decX_incY_:       
                call    decrementX
                jmp     short incrementY
move_monster_SW endp


; =============== S U B R O U T I N E =======================================


move_monster_S  proc near 
                mov     al, [si+monster.m_x_rel]
                or      al, al
                stc
                jnz     short non_zero
                retn                    ; phase=0
; ---------------------------------------------------------------------------

non_zero:        
                cmp     al, 35
                stc
                jnz     short less_35
                retn                    ; phase=35
; ---------------------------------------------------------------------------

less_35:         
                call    check_collision_S2
                jnb     short loc_926A
                retn
; ---------------------------------------------------------------------------

loc_926A:        
                jmp     short incrementY
; ---------------------------------------------------------------------------

move_monster_SE: 
                cmp     [si+monster.m_x_rel], 34
                cmc
                jnb     short phase0_33
                retn                    ; phase >= 34
; ---------------------------------------------------------------------------

phase0_33:       
                call    check_collision_SE2
                jnb     short incX_incY_
                retn
; ---------------------------------------------------------------------------

incX_incY_:       
                call    incrementX
                jmp     short incrementY
; ---------------------------------------------------------------------------

incrementX:      
                mov     ax, [si+monster.currX]        ; current X coord
                inc     ax              ; try to move right
                mov     bx, ax
                sub     bx, ds:mapWidth
                jb      short loc_928C
                mov     ax, bx          ; wrap X

loc_928C:        
                mov     [si+monster.currX], ax ; monster X coord update
                inc     [si+monster.m_x_rel]
                clc
                retn
; ---------------------------------------------------------------------------

decrementX:      
                mov     ax, [si+monster.currX]
                or      ax, ax
                jnz     short loc_929C
                mov     ax, ds:mapWidth

loc_929C:        
                dec     ax
                mov     [si+monster.currX], ax
                dec     [si+monster.m_x_rel]
                clc
                retn
; ---------------------------------------------------------------------------

incrementY:      
                inc     [si+monster.currY]
                and     [si+monster.currY], 3Fh ; wrap Y: dungeon map height is always 64
                retn
move_monster_S  endp

; ---------------------------------------------------------------------------

decrementY:      
                dec     [si+monster.currY]
                and     [si+monster.currY], 3Fh ; wrap Y: dungeon map height is always 64
                retn


; ===========================================================================
; check_collision_E2 / W2 / N2 / S2 / NE2 / SE2 / NW2 / SW2
; Collision detection for a 2×2-tile monster footprint.
;
; Each function checks a set of proximity map tiles in the direction of
; movement. Monster occupies tiles (0,0) and (1,0) (or (0,0),(0,1) for N/S).
; Returns CF=1 if any tile in the 'leading edge' is blocked.
;
; Tile categorization for level 5 (wind-tunnel) caverns:
;   - Airflow category 1 (left-flowing): blocks Westward movement (is_left_airflow).
;   - Airflow category 2 (right-flowing): blocks Eastward movement.
;
; CF detection trick: OR multiple proximity bytes together,
; then 'add al, al' → shifts bit 7 into CF. If any byte had bit 7 set
; (= monster/item marker), CF fires — used as second-layer monster detection.
; ===========================================================================
check_collision_E2 proc near  
                mov     ax, word ptr [si+monster.currY] ; monster Y coord
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                inc     di
                inc     di              ; x+=2, check (+2, 0)
                call    check_collision_E_including_danger5
                jnb     short loc_92C2
                retn
; ---------------------------------------------------------------------------

loc_92C2:        
                xchg    si, di
                add     si, 36          ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di          ; check (+2, +1)
                call    check_collision_E_including_danger5
                jnb     short loc_92D2
                retn
; ---------------------------------------------------------------------------

loc_92D2:        
                xchg    si, di
                mov     al, [si]        ; (+2, +1)
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                or      al, [si]        ; (+2, +1)|(+2, 0)
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                or      al, [si]        ; (+2, +1)|(+2, 0)|(+2, -1)
                xchg    si, di
                add     al, al          ; ..~
                                        ; x.⭉
                                        ; ..⭉
                retn                    ; CF is only set if any of {(+2, +1), (+2, 0), (+2, -1)} has high bit set (negative)
check_collision_E2 endp

check_collision_E_including_danger5 proc near
                mov     al, [di]
                call    is_blocking
                stc
                jz      short loc_92F4
                retn  ; cannot pass => CF
; ---------------------------------------------------------------------------

loc_92F4:        
                cmp     byte ptr ds:cavern_level, 5
                clc
                je      short loc_92FD
                retn  ; can pass, NC
; ---------------------------------------------------------------------------

loc_92FD:        
                push    si
                call    get_airflow_direction ; Is input tile an airflow?
                                        ; Input: al
                                        ; Output:
                                        ; NZ, cl=0xff (no airflow)
                                        ; ZF, cl=0 (Up), 1 (Left), 2 (Right)
                pop     si
                dec     cl
                clc
                jz      short category_1
                retn  ; can pass, NC
; ---------------------------------------------------------------------------

category_1:     ; Left airflow - headwind
                stc  ; cannot pass, CF
                retn
check_collision_E_including_danger5 endp

; =============== S U B R O U T I N E =======================================


check_collision_W2 proc near  
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                dec     di              ; x--, check (-1, 0)
                call    check_collision_W_including_danger5
                jnb     short loc_9317
                retn                    ; CF if (-1, 0) unpassable, including danger 5
; ---------------------------------------------------------------------------

loc_9317:        
                xchg    si, di
                add     si, 36          ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di          ; check (-1, +1)
                call    check_collision_W_including_danger5
                jnb     short loc_9327
                retn                    ; CF if (-1, +1) unpassable, including danger 5
; ---------------------------------------------------------------------------

loc_9327:        
                dec     di              ; x--
                xchg    si, di
                mov     al, [si]        ; (-2, +1)
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                or      al, [si]        ; (-2, +1)|(-2, 0)
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                or      al, [si]        ; (-2, +1)|(-2, 0)|(-2, -1)
                xchg    si, di          ; ?..
                                        ; ??x
                                        ; ??.
                add     al, al          ; CF is only set if any of {(-2, +1), (-2, 0), (-2, -1)} has high bit set (negative)
                retn
check_collision_W2 endp


; =============== S U B R O U T I N E =======================================


check_collision_W_including_danger5 proc near
                mov     al, [di]
                call    is_blocking
                stc
                jz      short loc_934A
                retn
; ---------------------------------------------------------------------------

loc_934A:        
                cmp     byte ptr ds:cavern_level, 5
                clc
                jz      short danger_five
                retn                    ; no danger 5, NC
; ---------------------------------------------------------------------------

danger_five:     
                push    si
                call    get_airflow_direction ; Is input tile an airflow?
                                        ; Input: al
                                        ; Output:
                                        ; NZ, cl=0xff (no airflow)
                                        ; ZF, cl=0 (Up), 1 (Left), 2 (Right)
                pop     si
                dec     cl
                dec     cl
                clc
                jz      short category_2
                retn
; ---------------------------------------------------------------------------

category_2:      
                stc                     ; non passable, CF
                retn
check_collision_W_including_danger5 endp


; =============== S U B R O U T I N E =======================================


check_collision_N2 proc near  
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                xchg    si, di
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xchg    si, di
                mov     al, [di]        ; check (0, -1)
                call    is_blocking
                stc
                jz      short loc_937B
                retn
; ---------------------------------------------------------------------------

loc_937B:        
                mov     al, [di+1]      ; check (+1, -1)
                call    is_blocking
                stc
                jz      short loc_9385
                retn
; ---------------------------------------------------------------------------

loc_9385:        
                xchg    si, di
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xchg    si, di
                mov     al, [di+1]      ; (+1, -2)
                or      al, [di]        ; (+1, -2)|(0, -2)
                or      al, [di-1]      ; (+1, -2)|(0, -2)|(-1, -2)
                add     al, al          ; ???
                                        ; .??
                                        ; .x.
                retn                    ; CF is only set if any of {(+1, -2), (0, -2), (-1, -2)} has high bit set (negative)
check_collision_N2 endp


; =============== S U B R O U T I N E =======================================


check_collision_S2 proc near  
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                xchg    si, di
                add     si, 36*2
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                mov     al, [di]        ; check (0, +2)
                call    is_blocking
                stc
                jz      short loc_93B3
                retn                    ; tile (0, +2) is solid, CF set
; ---------------------------------------------------------------------------

loc_93B3:        
                mov     al, [di+1]      ; check (+1, +2)
                call    is_blocking
                stc
                jz      short loc_93BD
                retn                    ; tile (1, +2) is solid, CF set
; ---------------------------------------------------------------------------

loc_93BD:        
                or      al, [di]        ; al=(+1, +2)|(0, +2)
                or      al, [di-1]      ; al=(+1, +2)|(0, +2)|(-1, +2)
                add     al, al          ; .x.
                 
                                        ; ???
                retn                    ; CF is only set if any of {(+1, +2), (0, +2), (-1, +2)} has high bit set (negative)
check_collision_S2 endp


; =============== S U B R O U T I N E =======================================


check_collision_NE2 proc near 
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                inc     di
                inc     di              ; x+=2
                mov     al, [di]        ; check (+2, 0)
                call    is_blocking
                stc
                jz      short loc_93D6
                retn
; ---------------------------------------------------------------------------

loc_93D6:        
                mov     cl, al          ; cl=(+2, 0)
                xchg    si, di
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xchg    si, di
                mov     al, [di]        ; check (+2, -1)
                call    is_blocking
                stc
                jz      short loc_93EB
                retn
; ---------------------------------------------------------------------------

loc_93EB:        
                or      cl, al          ; cl=(+2, 0)|(+2, -1)
                mov     al, [di-1]      ; check (+1, -1)
                call    is_blocking
                stc
                jz      short loc_93F7
                retn
; ---------------------------------------------------------------------------

loc_93F7:        
                xchg    si, di
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xchg    si, di
                or      cl, [di]        ; cl=(+2, 0)|(+2, -1)|(+2, -2)
                or      cl, [di-1]      ; cl=(+2, 0)|(+2, -1)|(+2, -2)|(+1, -2)
                or      cl, [di-2]      ; cl=(+2, 0)|(+2, -1)|(+2, -2)|(+1, -2)|(0, -2)
                add     cl, cl          ; ???
                                        ; .??
                                        ; x.?
                retn
check_collision_NE2 endp


; =============== S U B R O U T I N E =======================================


check_collision_SE2 proc near 
                mov     ax, word ptr [si+monster.currY] ; al=currY, ah=phase
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                inc     di
                inc     di
                mov     cl, [di]        ; save tile (+2, 0)
                xchg    si, di          ; si: proximity map, di: monster struc
                add     si, 36          ; move 1 down
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di          ; di: proximity map, si: monster struc
                mov     al, [di]        ; check tile (+2, +1)
                call    is_blocking
                stc
                jz      short loc_9429
                retn                    ; tile (+2, +1) is solid, CF set
; ---------------------------------------------------------------------------

loc_9429:        
                or      cl, al          ; cl=(+2, 0)|(+2, +1)
                xchg    si, di          ; si: proximity map, di: monster struc
                add     si, 36          ; move 1 down
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di          ; di: proximity map, si: monster struc
                mov     al, [di]        ; check tile (+2, +2)
                call    is_blocking
                stc
                jz      short loc_943E
                retn                    ; tile (+2, +2) is solid, CF set
; ---------------------------------------------------------------------------

loc_943E:        
                or      cl, al          ; cl=(+2, 0)|(+2, +1)|(+2, +2)
                mov     al, [di-1]      ; check tile (+1, +2)
                call    is_blocking
                stc
                jz      short loc_944A
                retn                    ; tile (+1, +2) is solid, CF set
; ---------------------------------------------------------------------------

loc_944A:        
                or      cl, al          ; cl = (+2, 0) | (+2, +1) | (+2, +2) | (+1, +2)
                or      cl, [di-2]      ; cl = (+2, 0) | (+2, +1) | (+2, +2) | (+1, +2) | (0, +2)
                add     cl, cl          ; x.?
                                        ; ..?
                                        ; ???
                retn                    ; CF is only set if any of {(+2, 0), (+2, +1), (+2, +2), (+1, +2), (0, +2)} has high bit set (negative)
check_collision_SE2 endp


; =============== S U B R O U T I N E =======================================


check_collision_NW2 proc near 
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                dec     di              ; x--
                mov     al, [di]        ; check (-1, 0)
                call    is_blocking
                stc
                jz      short loc_9462
                retn
; ---------------------------------------------------------------------------

loc_9462:        
                dec     di              ; x--
                mov     cl, [di]        ; cl=(-2, 0)
                xchg    si, di
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xchg    si, di
                or      cl, [di]        ; cl=(-2, 0)|(-2, -1)
                mov     al, [di+1]      ; check (-1, -1)
                call    is_blocking
                stc
                jz      short loc_947B
                retn
; ---------------------------------------------------------------------------

loc_947B:        
                mov     al, [di+2]      ; check (0, -1)
                call    is_blocking
                stc
                jz      short loc_9485
                retn
; ---------------------------------------------------------------------------

loc_9485:        
                xchg    si, di
                sub     si, 36          ; y--
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xchg    si, di
                or      cl, [di+2]      ; cl=(-2, 0)|(-2, -1)|(0, -2)
                or      cl, [di+1]      ; cl=(-2, 0)|(-2, -1)|(0, -2)|(-1, -2)
                or      cl, [di]        ; cl=(-2, 0)|(-2, -1)|(0, -2)|(-1, -2)|(-2, -2)
                add     cl, cl          ; ???
                                        ; ??.
                                        ; ??x
                retn                    ; CF is only set if any of {(-2, 0), (-2, -1), (0, -2), (-1, -2), (-2, -2)} has high bit set (negative)
check_collision_NW2 endp


; =============== S U B R O U T I N E =======================================


check_collision_SW2 proc near 
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                dec     di
                dec     di              ; x-=2
                mov     cl, [di]        ; check (-2, 0)
                xchg    si, di
                add     si, 36          ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                or      cl, [di]        ; cl=(-2, 0)|(-2, +1)
                inc     di              ; x++
                mov     al, [di]        ; check (-1, +1)
                call    is_blocking
                stc
                jz      short loc_94BA
                retn
; ---------------------------------------------------------------------------

loc_94BA:        
                xchg    si, di
                add     si, 36          ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                mov     al, [di]        ; check (-1, +2)
                call    is_blocking
                stc
                jz      short loc_94CD
                retn
; ---------------------------------------------------------------------------

loc_94CD:        
                or      cl, al          ; cl=(-2, 0)|(-2, +1)|(-1, +2)
                mov     al, [di+1]      ; check (0, +2)
                call    is_blocking
                stc
                jz      short loc_94D9
                retn
; ---------------------------------------------------------------------------

loc_94D9:        
                or      cl, al          ; cl=(-2, 0)|(-2, +1)|(-1, +2)|(0, +2)
                or      cl, [di-1]      ; cl=(-2, 0)|(-2, +1)|(-1, +2)|(0, +2)|(-2, +2)
                add     cl, cl          ; ?.x
                                        ; ?..
                                        ; ???
                retn                    ; CF is only set if any of {(-2, 0), (-2, +1), (-1, +2), (0, +2), (-2, +2)} has high bit set (negative)
check_collision_SW2 endp


; ===========================================================================
; Core passability test used by monster collision checks.
; AL = tile value.
;   AL >= 0x80: NZ (non-passable — monster or item marker)
;   AL in 0x49-0x7F: NZ (solid tile range)
;   AL < 0x49: search the 24-byte passable list at seg1:8000h.
;            ZF=1 if found (passable), NZ if not.
; Note: this is subtly different from is_blocking_tile_extended,
; which does NOT use the 73-based threshold (uses 0x40 and 0x49 variants).
; ===========================================================================
is_blocking proc near  
                cmp     al, 49h
                jb      short in_zero_to_x48
                or      al, al
                jns     short in_x49_to_x7F
                retn                    ; for >= 80h return NZ (non-passable item or monster)
; ---------------------------------------------------------------------------

in_x49_to_x7F:  ; doors
                cmp     al, al
                retn                    ; for 0x49..0x7F return ZF (passable)
; ---------------------------------------------------------------------------

in_zero_to_x48:   
                push    di
                push    cx
                mov     es, cs:seg1
                mov     di, 8000h
                mov     cx, 24
                repne scasb             ; al in (00 01 02 08 09 0A 0B 0C 0F 10 11 12 13 14 15 16 17 18 19 00 00 00 00 00)
                pop     cx
                pop     di
                retn                    ; ZF if one of predefined passable tiles; NZ otherwise
is_blocking endp


; ===========================================================================
; Spawns a monster from its spawn point when the hero comes close enough.
; Conditions for spawn:
;   - Monster currX high byte == 0xFF (currently deactivated/item state).
;   - spawn X != 0xFFFF (has a defined respawn point).
;   - Within is_in_proximity_window range, and NOT at proximity left/right edge (bl 3..32).
;   - Spawn Y within 24 rows of viewport_top_row_y.
;   - Spawn position in proximity map has no existing monster (OR of 3×3 tiles).
; On spawn: copies spawnX → currX, spawnY → currY, type_ → flags, resets counters.
; Big monsters (state_flags bit 4): spawn as two consecutive table entries,
; placing second entry 2 rows below the first.
; Input: SI = monster struct pointer.
; ===========================================================================
monster_activation proc near  
                cmp     byte ptr [si+1], 0FFh ; monster x coord high byte
                je      short loc_9506
                retn
; ---------------------------------------------------------------------------

loc_9506:        
                test    [si+monster.state_flags], 10h ; is big monster? (occupy 2 structs in table)
                jz      short loc_9513
                cmp     byte ptr [si+11h], 0FFh ; big monster's (second part) x coord high byte
                jz      short loc_9513
                retn
; ---------------------------------------------------------------------------

loc_9513:        
                mov     ax, [si+monster.spwnX]
                cmp     ax, 0FFFFh
                jnz     short loc_951C
                retn
; ---------------------------------------------------------------------------

loc_951C:        
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.
                jnc     short loc_9522
                retn
; ---------------------------------------------------------------------------

loc_9522:        
                or      bl, bl
                jnz     short loc_9527
                retn
; ---------------------------------------------------------------------------

loc_9527:        
                cmp     bl, 35
                jne     short loc_952D
                retn
; ---------------------------------------------------------------------------

loc_952D:        
                mov     al, ds:viewport_top_row_y
                sub     al, 2
                and     al, 3Fh         ; wrap y
                sub     al, [si+monster.spwnY]
                neg     al
                and     al, 3Fh         ; wrap y
                cmp     al, 24
                jnb     short loc_954A
                cmp     bl, 3
                jb      short loc_954A
                cmp     bl, 32
                jnb     short loc_954A
                retn
; ---------------------------------------------------------------------------

loc_954A:        
                test    [si+monster.state_flags], 10h
                jnz     short big_monster
                mov     [si+monster.m_x_rel], bl
                mov     al, [si+monster.spwnY]
                mov     ah, bl
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                push    di
                xchg    si, di
                sub     si, (36+1)
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xor     al, al
                mov     cx, 3

loc_9569:        
                or      al, [si+0]
                or      al, [si+1]
                or      al, [si+2]
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                loop    loc_9569
                xchg    si, di
                pop     di
                or      al, al ; any monster within 3x3 tiles?
                jns     short loc_9581
                retn
; ---------------------------------------------------------------------------

loc_9581:        
                mov     al, ds:monster_index
                or      al, 80h
                mov     [di], al
                mov     ax, [si+monster.spwnX]
                mov     [si+monster.currX], ax
                mov     al, [si+monster.spwnY]
                mov     [si+monster.currY], al
                mov     al, [si+monster.type_]
                mov     [si+monster.flags], al
                mov     [si+monster.anim_counter], 10h
                mov     [si+monster.ai_flags], 0
                mov     word ptr [si+monster.ai_state], 0
                mov     [si+monster.hp], 0
                mov     bl, ds:monster_index
                xor     bh, bh
                mov     byte ptr ds:proximity_second_layer[bx], 0 ; proximity map is designed to keep only one item
                                        ; at given address. So when we need to put other object,
                                        ; when position is already occupied by monster,
                                        ; we use second layer: 128 bytes of additional buffer
                                        ; (1 byte per monster id)
                retn
; ---------------------------------------------------------------------------

big_monster:     
                test    [si+monster.type_], 1
                jz      short big_type1
                retn
; ---------------------------------------------------------------------------

big_type1:       
                mov     [si+monster.m_x_rel], bl
                mov     [si+(monster.m_x_rel+10h)], bl
                mov     al, [si+monster.spwnY]
                mov     ah, bl
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                push    di
                xchg    si, di ; di: monster, si: proximity map
                sub     si, (36+1)
                call    wrap_map_from_below ; if (si < 0E000h) si += 900h
                xor     al, al
                mov     cx, 5

loc_95D9:        
                or      al, [si+0]
                or      al, [si+1]
                or      al, [si+2]
                add     si, 36
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                loop    loc_95D9
                xchg    si, di ; si: monster, di: proximity map
                pop     di
                or      al, al
                jns     short loc_95F1
                retn
; ---------------------------------------------------------------------------

loc_95F1:        
                mov     al, ds:monster_index
                or      al, 80h
                mov     [di], al
                xchg    si, di
                add     si, 36*2
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                inc     al
                mov     [di], al
                mov     ax, [si+monster.spwnX]
                mov     [si+monster.currX], ax
                mov     [si+(monster.currX+16)], ax

                mov     al, [si+monster.spwnY]
                mov     [si+monster.currY], al
                add     al, 2
                and     al, 3Fh
                mov     [si+(monster.currY+16)], al
                
                mov     al, [si+monster.type_]
                mov     [si+monster.flags], al
                inc     al
                mov     [si+(monster.flags+16)], al
                
                mov     [si+monster.anim_counter], 10h
                mov     [si+(monster.anim_counter+16)], 10h
                
                mov     [si+monster.ai_flags], 0
                mov     [si+(monster.ai_flags+16)], 0
                
                mov     word ptr [si+monster.ai_state], 0
                mov     word ptr [si+(monster.ai_state+16)], 0
                
                mov     [si+monster.hp], 0
                mov     [si+(monster.hp+16)], 0
                
                and     [si+(monster.state_flags+16)], 0F0h
                mov     bl, ds:monster_index
                xor     bh, bh
                mov     word ptr ds:proximity_second_layer[bx], 0 ; proximity map is designed to keep only one item
                                        ; at given address. So when we need to put other object,
                                        ; when position is already occupied by monster,
                                        ; we use second layer: 128 bytes of additional buffer
                                        ; (1 byte per monster id)
                retn
monster_activation endp


; ===========================================================================
; Called once from init_cavern at room load (NOT per frame).
; Clears proximity_second_layer, iterates all monsters,
; stamps each in-range monster's index | 0x80 into the proximity map.
; Used to pre-populate the map with monsters before the main loop starts.
; ===========================================================================
update_all_monsters_in_map proc near
                push    cs
                pop     es
                mov     di, offset proximity_second_layer ; proximity map is designed to keep only one item
                                        ; at given address. So when we need to put other object,
                                        ; when position is already occupied by monster,
                                        ; we use second layer: 128 bytes of additional buffer
                                        ; (1 byte per monster id)
                mov     cx, 80h
                xor     al, al
                rep stosb
                jmp     short $+2
; ---------------------------------------------------------------------------

loc_9667:        
                mov     byte ptr ds:monster_index, 0
                mov     si, ds:monsters_table_addr

next_monster3:    
                mov     ax, [si+monster.currX]
                cmp     ax, 0FFFFh
                jnz     short loc_9678
                retn                    ; no more monsters
; ---------------------------------------------------------------------------

loc_9678:        
                cmp     ah, 0FFh
                je      short loc_9698
                mov     [si+monster.m_x_rel], 0FFh
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.
                jc      short loc_9698  ; monster is outside the window
                mov     [si+monster.m_x_rel], bl
                mov     al, [si+monster.currY]
                mov     ah, bl
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                mov     al, ds:monster_index
                or      al, 80h
                mov     [di], al        ; put monster to map

loc_9698:        
                inc     byte ptr ds:monster_index
                add     si, 10h
                jmp     short next_monster3
update_all_monsters_in_map endp


; =============== S U B R O U T I N E =======================================

; Checks if given map X lies within the proximity window (width 36).
; Returns CF if outside the window, accounting for world wrap.
;         NC if inside the window, then BL = relative X in the window.
; ===========================================================================
; Cases:
;  1. |left=0|p=36|right=mapWidth-36|
;    a. x=0..35; return: NC
;    b. x=36..mapWidth-1; return: CF
;  2. |left=L|p=36|right=mapWidth-36-L|  where 0 < L < mapWidth-36
;    c. x=0..L-1; return: CF
;    d. x=L..L+35; return: NC
;    e. x=L+36..mapWidth-1; return: CF
;  3. |left=L|p=36|right=0|  where L = mapWidth-36
;    f. x=0..L-1; return: CF
;    g. x=L..L+35; return: NC
;  4. |        left=L        |p0=mapWidth-L|  where mapWidth-36 < L < mapWidth
;     |p1=36-mapWidth+L|...................|  (proximity window intersects map edge)
;    h. x=0..35-mapWidth+L; return: NC
;    i. x=36-mapWidth+L..L-1; return: CF
;    j. x=L..mapWidth-1; return: NC
is_in_proximity_window proc near  
                mov     bx, ax          ; monster_x in absolute map coords
                sub     ax, ds:proximity_map_left_col_x
                jnb     short loc_96BA
                ; x < L
                mov     ax, 35
                sub     ax, bx
                jnb     short loc_96B1
                retn ; 35 < x < L
loc_96B1:       ; x <= 35
                mov     ax, ds:mapWidth
                sub     ax, ds:proximity_map_left_col_x
                add     ax, bx ; mapWidth - L + x
loc_96BA:        
                xchg    ax, bx
                mov     ax, 35 ; proximity window width - 1
                sub     ax, bx
                retn
is_in_proximity_window endp


; ===========================================================================
; Called when a monster's HP drops to 0.
; Adds XP to hero (from death XP table at word_A008 indexed by flags&7).
; Sets monster flags |= 0x68 (death animation bits), clears AI flags.
; For big monsters: handles both top and bottom halves.
; Check_Vertical_Distance_Between_Hero_And_Monster:
;   If dying monster is within 19 rows of viewport: play SFX 7 (death sound).
; ===========================================================================
monster_split_or_die proc near
                mov     al, [si+monster.flags]
                test    al, 10h
                jnz     short Check_Vertical_Distance_Between_Hero_And_Monster
                and     al, 0Fh
                mov     bx, 0A008h
                xlat
                xor     ah, ah
                call    update_hero_XP
                jmp     short $+2
; ---------------------------------------------------------------------------

Check_Vertical_Distance_Between_Hero_And_Monster:
                mov     [si+monster.anim_counter], 0
                or      [si+monster.flags], 68h
                and     [si+monster.ai_flags], 80h
                test    [si+monster.state_flags], 10h ; big monster?
                jz      short usual_monster
                test    [si+monster.flags], 1
                jnz     short usual_monster
                mov     [si+monster.anim_counter], 80h
                mov     [si+(monster.anim_counter+10h)], 0
                or      [si+(monster.flags+10h)], 68h
                and     [si+(monster.ai_flags+10h)], 80h

usual_monster:   
                mov     al, [si+monster.currY]
                mov     ah, ds:viewport_top_row_y
                dec     ah
                sub     al, ah
                and     al, 3Fh
                cmp     al, 19
                jb      short monster_close_to_hero_vertically_19
                retn
; ---------------------------------------------------------------------------

monster_close_to_hero_vertically_19:
                mov     byte ptr ds:soundFX_request, 7
                retn
monster_split_or_die endp


; =============== S U B R O U T I N E =======================================


update_hero_XP  proc near 
                add     ds:hero_xp, ax
                jc      short loc_971C
                retn
; ---------------------------------------------------------------------------

loc_971C:        
                mov     ds:hero_xp, 0FFFFh
                retn
update_hero_XP  endp


; =============== S U B R O U T I N E =======================================

; al=angle starting from right, counter-clockwise

; ===========================================================================
; monster_move_in_direction / Check_collision_in_direction
; Public dispatch tables exported to AI binaries (eai*.bin).
; al = direction index 0-7 (0=E, 1=NE, 2=N, 3=NW, 4=W, 5=SW, 6=S, 7=SE)
; counter-clockwise from East.
; monster_move_in_direction: calls the corresponding move_monster_X.
; Check_collision_in_direction: calls the corresponding check_collision_X2.
; ===========================================================================
monster_move_in_direction proc near
                and     al, 7
                mov     bl, al
                xor     bh, bh
                add     bx, bx
                jmp     ds:funcs_972B[bx]
monster_move_in_direction endp

; ---------------------------------------------------------------------------
funcs_972B      dw offset move_monster_E
                dw offset move_monster_NE
                dw offset move_monster_N
                dw offset move_monster_NW
                dw offset move_monster_W
                dw offset move_monster_SW
                dw offset move_monster_S
                dw offset move_monster_SE

; =============== S U B R O U T I N E =======================================


Check_collision_in_direction proc near
                and     al, 7
                mov     bl, al
                xor     bh, bh
                add     bx, bx
                jmp     ds:funcs_9747[bx]
Check_collision_in_direction endp

; ---------------------------------------------------------------------------
funcs_9747      dw offset check_collision_E2
                dw offset check_collision_NE2
                dw offset check_collision_N2
                dw offset check_collision_NW2
                dw offset check_collision_W2
                dw offset check_collision_SW2
                dw offset check_collision_S2
                dw offset check_collision_SE2

; =============== S U B R O U T I N E =======================================

; si points to monster struc

; ===========================================================================
; Move_Monster_NWE_Depending_On_Whats_Below
; Exported helper for AI: checks the tile BELOW the monster (y+1) for
; airflow direction. Calls move_monster_N/W/E accordingly (twice each).
; Used by flying/swimming monster AIs that follow air/water currents.
; Airflow categories: 0=Up → move N; 1=Left → move W; 2=Right → move E.
; ===========================================================================
Move_Monster_NWE_Depending_On_Whats_Below proc near
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                xchg    di, si
                add     si, 36          ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    di, si
                mov     cx, 2           ; monster occupies 2 tiles, so we check both tiles below monster

loc_976E:        
                push    cx
                push    si
                mov     al, [di]
                call    get_airflow_direction ; Is input tile an airflow?
                                        ; Input: al
                                        ; Output:
                                        ; NZ, cl=0xff (no airflow)
                                        ; ZF, cl=0 (Up), 1 (Left), 2 (Right)
                mov     bl, cl          ; category
                pop     si
                pop     cx
                jz      short loc_977F
                inc     di
                loop    loc_976E
                retn
; ---------------------------------------------------------------------------

loc_977F:        
                pop     ax
                xor     bh, bh
                add     bx, bx          ; switch 3 cases
                jmp     ds:jpt_9784[bx] ; switch jump
Move_Monster_NWE_Depending_On_Whats_Below endp

; ---------------------------------------------------------------------------
jpt_9784        dw offset category0_moveN
                dw offset category1_moveW
                dw offset category2_moveE
; ---------------------------------------------------------------------------

category2_moveE: 
                call    move_monster_E  ; jumptable 00009784 case 2
                jmp     move_monster_E
; ---------------------------------------------------------------------------

category1_moveW: 
                call    move_monster_W  ; jumptable 00009784 case 1
                jmp     move_monster_W
; ---------------------------------------------------------------------------

category0_moveN: 
                call    move_monster_N  ; jumptable 00009784 case 0
                jmp     move_monster_N


; ===========================================================================
; Exported helper for AI: checks the proximity map at monster position Y+2.
; Calls is_tile_safe_to_stay to test if it is an 'aggressive'
; ground tile. Used by AIs to detect lava/spike floors for evasion.
; Input: si = monster struct
; ===========================================================================
check_monster_on_aggressive_ground proc near
                mov     ax, word ptr [si+monster.currY]
                call    coords_in_ax_to_proximity_map_addr_in_di ; uint8_t y = AL
                                        ; uint8_t x = AH
                                        ; y &= 0x3F; // Clamp Y to 0-63
                                        ; uint16_t di = (y * 36) + x + 0xE000;
                xchg    si, di
                add     si, 2*36        ; y++
                call    wrap_map_from_above ; if (si >= 0E900h) si -= 900h
                xchg    si, di
                mov     al, [di]        ; monster_id
                jmp     is_tile_safe_to_stay
check_monster_on_aggressive_ground endp



; ===========================================================================
; Exported from fight.bin. Called by Monster_AI_proc when the AI decides
; the hero's sword has hit the monster.
;
; 1. Reads ai_flags low 5 bits as 'stat index' → call Get_Stats.
;    Stat index 0: damage = hero_level/2.
;    Stat index 1: damage = sword_damage[type] + level/2 (doubled for downward thrust).
;    Stat index 2-8: damage from byte_98BE table.
; 2. Deduct AH from monster.hp.
; 3. If HP > 0: SFX 6 (hit sound), return.
; 4. If HP <= 0: look up death_split_table to get split/death state.
;    Random (0-3) selects split type, unless downward thrust (always 0).
;    Write new state_flags for death animation → monster_split_or_die.
; ===========================================================================
Hero_Hits_monster proc near   
                mov     al, [si+monster.ai_flags]
                and     al, 1Fh
                call    Get_Stats       ; al=0: return ah=hero_level/2
                                        ; al=1: return ah=sword_total_damage
                                        ; al=2..8: return ah=byte_98BE[al-2]
                                        ; al=9: NOP
                mov     al, [si+monster.hp]
                sub     al, ah
                jbe     short loc_97CD
                mov     [si+monster.hp], al
                mov     byte ptr ds:soundFX_request, 6
                retn
; ---------------------------------------------------------------------------

loc_97CD:        
                test    [si+monster.flags], 1
                jnz     short loc_97D9
                test    [si+monster.state_flags], 10h ; big monster?
                jnz     short loc_9815

loc_97D9:        
                test    [si+monster.state_flags], 0Fh
                jz      short loc_97E2
                jmp     monster_split_or_die
; ---------------------------------------------------------------------------

loc_97E2:        
                mov     di, ds:death_descriptors_ptr
                mov     bl, [si+monster.flags]
                and     bl, 7
                xor     bh, bh
                add     bx, bx
                mov     di, [bx+di]
                call    cs:get_random_proc
                mov     bl, al
                and     bx, 3
                cmp     byte ptr ds:sword_hit_type, 2
                jnz     short loc_9805
                xor     bx, bx

loc_9805:        
                mov     al, [bx+di]
                mov     ah, [si+monster.state_flags]
                and     ah, 0F0h
                or      al, ah
                mov     [si+monster.state_flags], al
                jmp     monster_split_or_die
; ---------------------------------------------------------------------------

loc_9815:        
                test    [si+(monster.state_flags+10h)], 0Fh
                jz      short loc_981E
                jmp     monster_split_or_die
; ---------------------------------------------------------------------------

loc_981E:        
                mov     di, ds:death_descriptors_ptr
                mov     bl, [si+monster.flags]
                and     bl, 7
                xor     bh, bh
                add     bx, bx
                mov     di, [bx+di]
                call    cs:get_random_proc
                mov     bl, al
                and     bx, 3
                cmp     byte ptr ds:sword_hit_type, 2
                jnz     short loc_9841
                xor     bx, bx

loc_9841:        
                mov     al, [bx+di]
                mov     ah, [si+(monster.state_flags+10h)]
                and     ah, 0F0h
                or      al, ah
                mov     [si+(monster.state_flags+10h)], al
                jmp     monster_split_or_die
Hero_Hits_monster endp


; =============== S U B R O U T I N E =======================================

; al=0: return ah=hero_level/2
; al=1: return ah=sword_total_damage
; al=2..8: return ah=byte_98BE[al-2]
; al=9: NOP

; ===========================================================================
; Returns hero combat statistics.
; al=0 → ah = hero_level/2 + 1 (basic defense stat)
; al=1 → ah = total sword damage:
;          base = sword_damages[sword_type-1] (table: 1,2,4,8,32,127)
;          + hero_level/2
;          × (byte_E4+1)  [difficulty multiplier]
;          × 2 if downward thrust (sword_hit_type==2)
; al=2..8 → ah = byte_98BE[al-2] (static stat table: 2,4,8,16,32,64,255)
; al=9 → ah = (hero_level+1)*4
; ===========================================================================
Get_Stats       proc near 
                mov     ah, ds:hero_level
                shr     ah, 1
                inc     ah
                or      al, al
                jnz     short loc_985E
                retn
; ---------------------------------------------------------------------------

loc_985E:        
                cmp     al, 1
                je      short stats_case1
                mov     ah, ds:hero_level
                inc     ah
                add     ah, ah
                jb      short loc_9870
                add     ah, ah
                jnb     short loc_9872

loc_9870:        
                mov     ah, 0FFh

loc_9872:        
                cmp     al, 9
                jne     short al_2_8
                retn
; ---------------------------------------------------------------------------

al_2_8:          
                sub     al, 2
                mov     bl, al
                xor     bh, bh
                mov     ah, ds:byte_98BE[bx]
                retn
; ---------------------------------------------------------------------------

stats_case1:        
                mov     bl, ds:sword_type
                dec     bl
                xor     bh, bh
                mov     al, ds:sword_damages[bx]
                mov     bl, ds:hero_level
                shr     bl, 1
                add     al, bl          ; base_damage[sword_type] + hero_level/2
                jb      short loc_98A4
                mov     cl, ds:byte_E4
                inc     cl
                mul     cl
                or      ah, ah
                jz      short loc_98A6

loc_98A4:        
                mov     al, 0FFh

loc_98A6:        
                mov     ah, al
                cmp     byte ptr ds:sword_hit_type, 2
                jz      short loc_98B0
                retn
; ---------------------------------------------------------------------------

loc_98B0:        
                add     ah, ah
                jb      short loc_98B5
                retn
; ---------------------------------------------------------------------------

loc_98B5:        
                mov     ah, 0FFh
                retn
Get_Stats       endp

; ---------------------------------------------------------------------------
sword_damages   db 1, 2, 4, 8, 32, 127
byte_98BE       db 2, 4, 8, 16, 32, 64, 255

; =============== S U B R O U T I N E =======================================

; Return dl: number of monsters found nearby

; ===========================================================================
; Find_Monsters_Near_Hero
; Exported from fight.bin. Counts nearby movable monsters.
; Iterates the monsters_table, for each non-item monster checks is_in_proximity_window.
; Returns DL = count of monsters in range.
; Returns CF=1 if hero should die (monster aligned with dead hero position).
; Used by AI to trigger special hero-death interactions.
; ===========================================================================
Find_Monsters_Near_Hero proc near
                xor     dl, dl
                mov     di, ds:monsters_table_addr

loc_98CB:        
                cmp     word ptr [di], 0FFFFh ; monsters end marker
                stc
                jnz     short loc_98D2
                retn
; ---------------------------------------------------------------------------

loc_98D2:        
                cmp     [di+monster.spwnX], 0FFFFh
                jnz     short loc_98ED
                cmp     byte ptr [di+1], 0FFh
                jz      short loc_98F4
                mov     ax, [di+monster.currX]
                push    dx
                call    is_in_proximity_window  ; Checks if given map X lies within the proximity window (width 36).
                                                ; Returns CF if outside the window, accounting for world wrap.
                                                ;         NC if inside the window, then BL = relative X in the window.

                pop     dx
                jnc     short loc_98ED
                test    [di+monster.flags], 10h
                jz      short loc_98FA

loc_98ED:        
                inc     dl              ; monsters counter
                add     di, 10h
                jmp     short loc_98CB
; ---------------------------------------------------------------------------

loc_98F4:        
                cmp     [di+monster.currY], 7Fh
                jz      short loc_98ED

loc_98FA:        
                clc                     ; error
                retn
Find_Monsters_Near_Hero endp


; ===========================================================================
; Hero death sequence.
;
; Phase 1 — falling: calls airborne_movement in a loop until landed.
; Phase 2 — flashing: hero_animation_phase cycles 0→1→2 at 1/8 speed,
;   while hero_sprite_hidden flickers at 1/2 speed after phase 2.
; Phase 3 — 30-frame fade: alternates show/hide then calls Fade_To_Black.
;
; Post-death (first death):
;   - XP += (127 - 2 × hero_level)
;   - Gold reset to 0.
;   - Almas halved.
; Post-death (already processed, i.e. no-XP death):
;   - last_sage_visited = 0x80 (Felishika's Castle entry sage).
; Both: restore HP to heroMaxHp.
;
; Resurrection: load the MDT for last_sage_visited town, restore hero_x
; from tear_x, load NPC sprites, transfer to town via transfer_to_town.
; ===========================================================================
process_hero_death proc near  
                call    cs:Flush_Ui_Element_If_Dirty_proc
                mov     byte ptr ds:sword_swing_flag, 0
                mov     byte ptr ds:jump_phase_flags, 0 ; 0: on ground, ff: ascending, 7f: descending, 80h: climbing down off rope
                mov     byte ptr ds:squat_flag, 0
                mov     byte ptr ds:hero_damage_this_frame, 0
                mov     byte ptr ds:invincibility_flag, 0FFh
                mov     ds:byte_9F28, 0
                mov     ds:byte_9F29, 0
                call    cs:Draw_Hero_Health_proc

repeat:         ; 9929
                mov     byte ptr ds:hero_animation_phase, 0
                mov     byte ptr ds:on_rope_flags, 0 ; 0: on ground, ff: on rope, 80h: transition from rope to ground
                mov     byte ptr ds:hero_sprite_hidden, 0
                call    main_update_render
                mov     ax, offset repeat
                push    ax
                call    airborne_movement
                pop     ax ; after death returns here
                mov     byte ptr ds:hero_sprite_hidden, 0

loc_9948:        
                call    main_update_render
                mov     byte ptr ds:hero_sprite_hidden, 0
                cmp     byte ptr ds:hero_animation_phase, 2
                je      short loc_9972
                inc     ds:byte_9F28 ; after death
                test    ds:byte_9F28, 7
                jnz     short loc_9948 ; repeat main_update_render 8 times
                mov     al, ds:hero_animation_phase
                inc     al
                and     al, 3
                cmp     al, 3
                je      short loc_9948
                mov     ds:hero_animation_phase, al
                jmp     short loc_9948
; ---------------------------------------------------------------------------

loc_9972:        
                inc     ds:byte_9F29
                test    ds:byte_9F29, 0Fh
                jz      short loc_998B ; exit flash animation loop
                test    ds:byte_9F29, 1
                jz      short loc_9948
                mov     byte ptr ds:hero_sprite_hidden, 0FFh
                jmp     short loc_9948
; ---------------------------------------------------------------------------

loc_998B:       ; after death flash animation
                mov     byte ptr ds:byte_FF24, 8
                mov     cx, 30

loc_9993:        
                push    cx
                call    main_update_render
                pop     cx
                mov     al, cl
                and     al, 1 ; even: 0, odd: 1
                dec     al ; even: 0xFF, odd: 0
                mov     ds:hero_sprite_hidden, al
                loop    loc_9993
                mov     ax, 1  ; fn1 (Stop) - Silences all channels and halts the driver.
                int     60h             ; mscadlib.drv
                call    cs:Fade_To_Black_Dithered_proc
                test    byte ptr ds:is_death_already_processed, 0FFh ; [0049]=0000
                jz      short loc_99BB
                mov     byte ptr ds:last_sage_visited, 80h
                jmp     short skip_death_math
; ---------------------------------------------------------------------------

loc_99BB:        
                mov     al, ds:hero_level
                add     al, al
                neg     al
                add     al, 127         ; xp += (127 - 2 * level)
                xor     ah, ah
                call    update_hero_XP
                mov     byte ptr ds:hero_gold_hi, 0
                mov     word ptr ds:hero_gold_lo, 0
                shr     word ptr ds:hero_almas, 1

skip_death_math: 
                mov     ax, ds:heroMaxHp
                mov     ds:hero_HP, ax
                jmp     short $+2
; ---------------------------------------------------------------------------

transit_to_sage:        
                mov     byte ptr ds:heartbeat_volume, 0
                mov     ah, ds:last_sage_visited ; resurrect in sage's hut
                mov     ds:place_map_id, ah
                mov     al, 1           ; fn1_load_mdt_idx_ah
                call    cs:res_dispatcher_proc
                mov     ax, ds:tear_x
                mov     ds:hero_x_in_proximity_map, ax
                mov     si, ds:mdt_buffer ; si=mdt_descr
                inc     si
                lodsb                   ; mdt_descr[1] = mman_grp_idx
                mov     bl, 11
                mul     bl
                add     ax, offset vfs_mman_grp
                mov     si, ax
                mov     es, cs:seg1
                mov     di, 4000h
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                mov     bx, 6002h       ; town_entry_disabling_edge_scroll
                jmp     transfer_to_town
process_hero_death endp

; ---------------------------------------------------------------------------
you_get_50_gold_str dw 26h
aYouGet50Golds  db 'You get 50 golds.'
                db 0FFh
you_get_100_gold_str dw 22h   
aYouGet100Golds db 'You get 100 golds.'
                db 0FFh
you_get_500_gold_str dw 22h   
aYouGet500Golds db 'You get 500 golds.'
                db 0FFh
you_get_1000_gold_str dw 1Eh  
aYouGet1000Gold db 'You get 1000 golds.'
                db 0FFh
you_get_key_str dw 32h    
aYouGetAKey     db 'You get a Key.'
                db 0FFh
you_have_recovered_str dw 1Ch 
aYouHaveRecover db 'You have recovered.'
                db 0FFh
you_have_recovered_full_str dw 8
aYouHaveRecover_0 db 'You have recovered full.'
                db 0FFh
shield_broken_str dw 3Ch  
aShieldBroken   db 'Shield broken.'
                db 0FFh
cant_open_this_door_str dw 14h
aCanTOpenThisDo db 'Can\t open this door.'
                db 0FFh
nothing_in_the_box_str dw 1Ch 
aNothingInTheBo db 'Nothing in the box.'
                db 0FFh
get_heros_crest_str dw 6  
aYouGetTheHeroS db 'You get the Hero\s Crest.'
                db 0FFh
get_ruzeria_shoes_str dw 0
aYouGetTheRuzer db 'You get the Ruzeria shoes.'
                db 0FFh
you_get_glory_crest_str dw 8  
aYouGetTheGlory db 'You get the Glory Crest.'
                db 0FFh
get_pirika_shoes_str dw 6 
aYouGetThePirik db 'You get the Pirika shoes.'
                db 0FFh
get_feruza_shoes_str dw 6 
aYouGetTheFeruz db 'You get the Feruza shoes.'
                db 0FFh
get_silkarn_shoes_str dw 0
aYouGetTheSilka db 'You get the Silkarn shoes.'
                db 0FFh
get_enchantment_sword_str dw 0
aGetTheEnchantm db 'Get the Enchantment sword.'
                db 0FFh
its_too_hot_str dw 30h    
aItSTooHot      db 'It\s too hot !!'
                db 0FFh
get_lions_head_key_str dw 8   
aGetTheLionSHea db 'Get the lion\s head Key.'
                db 0FFh
; ===========================================================================
; VFS (Virtual File System) resource descriptor tables
; Each entry: [disk_id byte] [file_id byte] [filename string, null-terminated]
; Used by res_dispatcher_proc (fn2/fn3/fn5) to load/decompress assets.
;
; fman.grp   — hero dungeon sprite sheet (24×24 px per frame, 3×3 tiles, mode 8)
; encnt.grp  — encounter intro animation (boss entry screen)
; roka.grp   — dungeon entrance decoration (28×18 tile map, animated palette)
; dchr.grp   — door and platform component tiles (8×8, mode 10)
; mman.grp   — surface towns NPC sprite sheet
; cman.grp   — underground towns NPC sprite sheet
; mpp1-b.grp — dungeon tilesets 1-11 (8×8 tiles, mode 10)
;              Loaded to seg1:8000h as the current dungeon environment
; eai1-8.bin — enemy AI modules 1-8 (regular cavern monster AIs)
; crab/tako/tori/zela/meda/lega/drgn/akma/mao1/mao2.bin — boss AIs
; enp1-8.grp — monster/item sprite sheets 1-8 (16×16 px, 2×2 tiles, mode 11)
; crab/tako/tori/zela/meda/lega/drgn/akma/mao1/mao2.grp — boss sprite sheets
; mgt1-2.msd + ugm1-2.msd — town background music tracks
; mus1-8.msd + mbos/mmao.msd — dungeon music tracks
; ===========================================================================
vfs_fman_grp    db 2
                db 34h
aFmanGrp        db 'FMAN.GRP',0
encnt_grp       db 2      
                db 38h
aEncntGrp       db 'ENCNT.GRP',0
vfs_roka_grp_2  db 2      
                db 35h
aRokaGrp        db 'ROKA.GRP',0
vfs_roka_grp_1  db 1      
                db 3Ah
aRokaGrp_0      db 'ROKA.GRP',0
dchr_grp        db 2      
                db 37h
aDchrGrp        db 'DCHR.GRP',0
rokademo_bin    db 2      
                db 1
aRokademoBin    db 'ROKADEMO.BIN',0
vfs_mman_grp    db 1      
                db 1Eh
aMmanGrp        db 'MMAN.GRP',0
                db 1
                db 1Fh
aCmanGrp        db 'CMAN.GRP',0
mpp_grp         db 2      
                db 4Bh
aMpp1Grp        db 'MPP1.GRP',0
                db 2
                db 4Ch
aMpp2Grp        db 'MPP2.GRP',0
                db 2
                db 4Dh
aMpp3Grp        db 'MPP3.GRP',0
                db 2
                db 4Eh
aMpp4Grp        db 'MPP4.GRP',0
                db 2
                db 4Fh
aMpp5Grp        db 'MPP5.GRP',0
                db 2
                db 50h
aMpp6Grp        db 'MPP6.GRP',0
                db 2
                db 51h
aMpp7Grp        db 'MPP7.GRP',0
                db 2
                db 52h
aMpp8Grp        db 'MPP8.GRP',0
                db 2
                db 53h
aMpp9Grp        db 'MPP9.GRP',0
                db 2
                db 54h
aMppaGrp        db 'MPPA.GRP',0
                db 2
                db 55h
aMppbGrp        db 'MPPB.GRP',0
eai1_bin        db 2      
                db 2
aEai1Bin        db 'EAI1.BIN',0
                db 2
                db 0Ah
aCrabBin        db 'CRAB.BIN',0
                db 2
                db 3
aEai2Bin        db 'EAI2.BIN',0
                db 2
                db 0Bh
aTakoBin        db 'TAKO.BIN',0
                db 2
                db 4
aEai3Bin        db 'EAI3.BIN',0
                db 2
                db 0Ch
aToriBin        db 'TORI.BIN',0
                db 2
                db 5
aEai4Bin        db 'EAI4.BIN',0
                db 2
                db 0Dh
aZelaBin        db 'ZELA.BIN',0
                db 2
                db 6
aEai5Bin        db 'EAI5.BIN',0
                db 2
                db 0Eh
aMedaBin        db 'MEDA.BIN',0
                db 2
                db 7
aEai6Bin        db 'EAI6.BIN',0
                db 2
                db 0Fh
aLegaBin        db 'LEGA.BIN',0
                db 2
                db 8
aEai7Bin        db 'EAI7.BIN',0
                db 2
                db 11h
aDrgnBin        db 'DRGN.BIN',0
                db 2
                db 9
aEai8Bin        db 'EAI8.BIN',0
                db 2
                db 12h
aAkmaBin        db 'AKMA.BIN',0
                db 2
                db 13h
aMao1Bin        db 'MAO1.BIN',0
                db 2
                db 14h
aMao2Bin        db 'MAO2.BIN',0
                db 2
                db 10h
aZel2Bin        db 'ZEL2.BIN',0
vfs_enp1_grp    db 2
                db 39h
aEnp1Grp        db 'ENP1.GRP',0
                db 2
                db 41h
aCrabGrp        db 'CRAB.GRP',0
                db 2
                db 3Ah
aEnp2Grp        db 'ENP2.GRP',0
                db 2
                db 42h
aTakoGrp        db 'TAKO.GRP',0
                db 2
                db 3Bh
aEnp3Grp        db 'ENP3.GRP',0
                db 2
                db 43h
aToriGrp        db 'TORI.GRP',0
                db 2
                db 3Ch
aEnp4Grp        db 'ENP4.GRP',0
                db 2
                db 44h
aZelaGrp        db 'ZELA.GRP',0
                db 2
                db 3Dh
aEnp5Grp        db 'ENP5.GRP',0
                db 2
                db 45h
aMedaGrp        db 'MEDA.GRP',0
                db 2
                db 3Eh
aEnp6Grp        db 'ENP6.GRP',0
                db 2
                db 46h
aLegaGrp        db 'LEGA.GRP',0
                db 2
                db 3Fh
aEnp7Grp        db 'ENP7.GRP',0
                db 2
                db 47h
aDrgnGrp        db 'DRGN.GRP',0
                db 2
                db 40h
aEnp8Grp        db 'ENP8.GRP',0
                db 2
                db 48h
aAkmaGrp        db 'AKMA.GRP',0
                db 2
                db 49h
aMao1Grp        db 'MAO1.GRP',0
                db 2
                db 4Ah
aMao2Grp        db 'MAO2.GRP',0
vfs_mgt1_msd    db 1
                db 2Fh
aMgt1Msd        db 'MGT1.MSD',0
                db 1
                db 31h
aUgm1Msd        db 'UGM1.MSD',0
                db 1
                db 30h
aMgt2Msd        db 'MGT2.MSD',0
                db 1
                db 32h
aUgm2Msd        db 'UGM2.MSD',0
                db 2
                db 56h
aMus1Msd        db 'MUS1.MSD',0
                db 2
                db 57h
aMus2Msd        db 'MUS2.MSD',0
                db 2
                db 58h
aMus3Msd        db 'MUS3.MSD',0
                db 2
                db 59h
aMus4Msd        db 'MUS4.MSD',0
                db 2
                db 5Ah
aMus5Msd        db 'MUS5.MSD',0
                db 2
                db 5Bh
aMus6Msd        db 'MUS6.MSD',0
                db 2
                db 5Ch
aMus7Msd        db 'MUS7.MSD',0
                db 2
                db 5Dh
aMus8Msd        db 'MUS8.MSD',0
                db 2
                db 5Eh
aMbosMsd        db 'MBOS.MSD',0
                db 2
                db 60h
aMmaoMsd        db 'MMAO.MSD',0
; ===========================================================================
; PER-DUNGEON STATE VARIABLES
; These are zero-initialised at start and reset on dungeon transitions.
; ===========================================================================
byte_9EED       db 0      
byte_9EEE       db 0      
byte_9EEF       db 0      
byte_9EF0       db 0      
byte_9EF1       db 0      
word_9EF2       dw 0      
byte_9EF4       db 0      
byte_9EF5       db 0FFh   
; ---- Loaded GRP/BIN index cache (from last MDT) ----
mman_grp_index  db 0    ; 9EF6h; mdt_descriptor.mman_grp_idx
mpp_grp_index   db 0    ; 9EF7h; mdt_descriptor.mpp_grp_idx
eai_bin_index_  db 0    ; 9EF8h; mdt_descriptor.eai_bin_idx
enp_grp_index_  db 0    ; 9EF9h; mdt_descriptor.enp_grp_idx
byte_9EFA       db 0      
                db    0      ; 9EFBh
                db    0      ; 9EFCh
                db    0      ; 9EFDh
eai_bin_index   db 0FFh     ; 9EFEh
enp_grp_index   db 0FFh     ; 9EFFh
byte_9F00       db 0      
byte_9F01       db 0      
byte_9F02       db 0      
; ---- Map streaming pointers ----
packed_map_ptr_for_prox_left dw 0 ; 9f03
packed_map_ptr_for_prox_right dw 0  ; 9f05
byte_9F07       db 0      
; ---- Hero movement state ----
jump_height_counter db 0  ; 9F08
byte_9F09       db 0      
frame_ticks     db 0      ; 9F0A
byte_9F0B       db 0      
height_above_ground db 0  ; 9F0C
jump_height_including_shoes db 2 
; ---- Knockback / hit vectors ----
; word_9F0E/9F10: X-component vectors for knockback (set by contact damage)
word_9F0E       dw 0      
word_9F10       dw 0      
; ---- Damage / invincibility ----
accumulated_contact_damage dw 0 
byte_9F14       db 0      
air_up_tile_found db 0    ; 9f15h
; ---- Airflow ----
ticks           db 0      ; 9F16h
danger_found       db 0      ; 9F17h
byte_9F18       db 0      
byte_9F19       db 0      
; ---- Map / scroll ----
hero_x_in_proximity_map dw 0  ; 9F1Ah
door_target_y       db 0      ; 9F1Ch
door_features       db 0      ; 9F1Dh
byte_9F1E       db 0      
; ---- Projectile tracking ----
last_projectile_index db 0 ; 9F1F
; ---- Ice slide state ----
slide_ticks_remaining db 0 ; 9F20
horiz_movement_sub_tile_accum db 0 ; 9F21
; ---- Input / animation state ----
slide_direction       db 0      ; 9F22
byte_9F23       db 0      ; ADDR_SLIDE_DIRECTION_LOCK
byte_9F24       db 0      
; ---- Temperature / cavern flags ----
temperature_timer db 0    ; 9F25h
byte_9F26       db 0      
byte_9F27       db 0      
byte_9F28       db 0      
byte_9F29       db 0      
byte_9F2A       db 0      
byte_9F2B       db 0      
delta_x         db 0      
delta_y         db 0      
byte_9F2E       db 0D2h dup(?)

fight           ends

                end      start
