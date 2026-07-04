include common.inc
include town.inc
                .286
                .model small

town            segment byte public 'CODE' use16
                assume cs:town, ds:town
                org 6000h
start:
                dw offset town_entry_enabling_edge_scroll
town_exports    dw offset town_entry_disabling_edge_scroll           ; primary town init, called from fight.bin
                dw offset render_menu_dialog        ; render FF-terminated dialog text
                dw offset convert_ax_to_decimal     ; convert AX to 7-digit decimal string
                dw offset show_yes_no_dialog        ; Yes/No confirmation dialog
                dw offset check_gold_sufficient     ; check if gold subtraction fits
                dw offset add_gold_to_hero          ; add gold to hero inventory
                dw offset render_menu_string_list   ; render list of C-strings for menus
                dw offset select_from_menu          ; menu selection with cursor navigation
                dw offset render_menu_list_scrolling ; render scrollable menu list
cursor_exports  dw offset houseCursorShow           ; draw menu cursor arrow
                dw offset npcAnimation              ; NPC animation / frame tick handler
cursor_up_export dw offset houseCursorUp            ; animate cursor moving up
cursor_down_export dw offset houseCursorDown        ; animate cursor moving down
                dw offset restore_game              ; restore game from save file

; =============== S U B R O U T I N E =======================================
; town_entry_disabling_edge_scroll — Primary town initialization entry point, called from:
; - after opening intro
;   fight.bin after hero returns from cavern.
;   Input: (none — reads state from shared memory)
;   Sets disable_edge_scroll=0FFh to prevent edge-scroll on first frame.

town_entry_disabling_edge_scroll   proc near
                mov     cs:disable_edge_scroll, 0FFh
                jmp     short town_entry_common
; ---------------------------------------------------------------------------

; town_entry_enabling_edge_scroll — Town re-entry after transitions (sage resurrection,
;   falter warp). Clears disable_edge_scroll to enable edge-scroll handler.
;   Input: (none — state already set in shared memory)
town_entry_enabling_edge_scroll:
                mov     cs:disable_edge_scroll, 0

town_entry_common:
                mov     ds, cs:seg1
                mov     si, 4100h
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax   ; seg2
                mov     di, 7000h
                mov     cx, 164
                call    cs:apply_sprite_mask_proc
                cli
                mov     sp, 2000h
                sti
                push    cs
                pop     ds
                call    load_hero_town_sprite
                mov     byte ptr ds:hero_animation_phase, 0
                test    byte ptr ds:is_death_already_processed, 0FFh
                jz      short loc_6061
                mov     byte ptr ds:invincibility_flag, 0
loc_6061:
                call    cs:Clear_Viewport_proc
                mov     si, ds:town_descriptor_addr
                inc     si   ; skip MSD index
skip_til_ff:
                lodsb        ; [1]: NPC type; 0 -> mman.grp, 1 -> cman.grp
                inc     al
                jnz     short skip_til_ff
                lodsb
                mov     ds:town_has_middle_layer, al
                lodsb
                mov     ds:pat_id, al    ; cpat/mpat/dpat
                mov     ds:edge_scroll_enabled, 0
                test    byte ptr ds:invincibility_flag, 0FFh
                jnz     short town_entry_internal
                test    byte ptr ds:town_has_middle_layer, 1
                jz      short loc_6097
                test    ds:disable_edge_scroll, 0FFh
                jnz     short loc_6097
                mov     ds:edge_scroll_enabled, 0FFh

loc_6097:   
                call    load_town_background
                call    load_patterns_and_call_background
                call    cs:backup_upper_town_3_tiles_proc ; skips top 8 tiles (sky, distant mountains)
                                        ; saves town top (3 tiles of 8) to screen buffer
                test    byte ptr ds:is_death_already_processed, 0FFh
                jnz     short town_entry_internal
                push    ds
                mov     ds, cs:seg1
                mov     si, 3000h
                xor     ax, ax
                int     60h             ; adlib fn_0
                pop     ds
town_entry_disabling_edge_scroll   endp ; sp-analysis failed

;   ADDITIONAL PARENT FUNCTION town_entry_disabling_edge_scroll

town_entry_internal:
                cli
                mov     sp, 2000h
                sti
                push    cs
                pop     ds
                call    init_c015_obj_if_exists
                xor     al, al
                mov     byte ptr ds:spacebar_latch, al
                mov     byte ptr ds:altkey_latch, al
                mov     byte ptr ds:byte_E4, al
                mov     byte ptr ds:byte_9F, al
                mov     bx, 204h
                xor     al, al
                mov     ch, 21h ; '!'
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                mov     bx, 21Ch
                xor     al, al
                mov     ch, 42h ; 'B'
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                mov     bx, 481Ch
                xor     al, al
                mov     ch, 42h ; 'B'
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                call    cs:Clear_Place_Enemy_Bar_proc
                call    render_life_almas_gold_place
                call    cs:Draw_Hero_Max_Health_proc
                call    cs:Draw_Hero_Health_proc
                call    cs:Print_Almas_Decimal_proc
                call    cs:Print_Gold_Decimal_proc
                test    byte ptr ds:current_magic_spell, 0FFh
                jz      short loc_6127
                mov     bx, 0AA1Ch
                xor     al, al
                mov     ch, 17h
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                call    cs:Print_Magic_Left_Decimal_proc

loc_6127:   
                test    byte ptr ds:shield_type, 0FFh
                jz      short loc_613F
                mov     bx, 0C61Ch
                xor     al, al
                mov     ch, 17h
                call    cs:Clear_HUD_Bar_proc ; bh: paddingLeft
                                        ; bl: paddingTop
                                        ; al: masking mode
                call    cs:Print_ShieldHP_Decimal_proc

loc_613F:   
                mov     si, ds:town_descriptor_addr
                inc     si
skip_until_ff:
                lodsb      ; background type ympd/ckpd
                inc     al
                jnz     short skip_until_ff
                inc     si
                lodsb      ; pat_id cpat/mpat/dpat
                mov     ds:pat_id, al
                mov     si, ds:town_name_rendering_info
                call    cs:Render_Pascal_String_1_proc
                mov     al, byte ptr ds:proximity_map_left_col_x ; =b3
                xor     ah, ah
                shl     ax, 1
                shl     ax, 1
                shl     ax, 1           ; x*8 = 0x598
                add     ax, offset town_tiles ; unpacked town map offset =c5af
                mov     ds:proximity_start_tiles, ax
                call    save_head_level_tiles_in_npcs
                test    byte ptr ds:invincibility_flag, 0FFh
                jz      short normal_game
                ; resurrect at sage
                mov     byte ptr ds:invincibility_flag, 0
                call    load_town_background
                mov     bx, offset town_loop_start
                push    bx
                mov     bx, offset loc_6EAF
                push    bx
                mov     si, offset kenjpro_bin
                push    cs
                pop     es
                mov     di, sage_bin_addr
                mov     al, 3 ; fn3_read_virtual_file ; load binary resource to dest buffer
                call    cs:res_dispatcher_proc
                call    cs:fade_to_black_dithered_proc
                mov     ax, 1
                int     60h             ; adlib fn_1
                mov     ds:town_transition_flag, 0FFh
                jmp     cs:word_A004    ; sage resurrects hero
; ---------------------------------------------------------------------------

normal_game:
                push    cs
                pop     es
                mov     al, 0FEh
                mov     di, offset viewport_buffer
                mov     cx, 224         ; viewport width
                rep stosb
                call    update_npcs_and_render
                test    ds:edge_scroll_enabled, 0FFh
                jz      short loc_61E2
                mov     ds:edge_scroll_handler, offset loc_6781 ; left edge scroll handler
                test    byte ptr ds:facing_direction, 1  ; bit0: 0=Right, 1=Left
                jnz     short loc_61CE
                mov     ds:edge_scroll_handler, offset loc_67F4 ; right edge scroll handler

loc_61CE:   
                mov     cx, 4

loc_61D1:   
                push    cx
                call    cs:edge_scroll_handler
                call    update_npcs_and_render
                pop     cx
                loop    loc_61D1
                call    cs:edge_scroll_handler

loc_61E2:   
                mov     ds:hero_moved_flag, 0
                test    byte ptr ds:is_death_already_processed, 0FFh
                jz      short town_loop_start
                push    ds
                mov     ds, cs:seg1
                mov     si, 3000h
                xor     ax, ax
                int     60h             ; adlib fn_0
                pop     ds

town_loop_start:   
                call    update_npcs_and_render
                call    handle_inventory_key
                call    handle_edge_screen_transition
                call    hero_spacebar_interaction
                test    ds:hero_moved_flag, 0FFh
                jnz     short loc_6212
                call    check_special_npc_conversation

loc_6212:   
                mov     ds:hero_moved_flag, 0
                mov     dx, offset town_loop_start
                push    dx
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                cmp     al, 1
                jne     short loc_6224
                jmp     town_up_pressed  ; up arrow pressed
; ---------------------------------------------------------------------------

loc_6224:   
                and     al, 0Ch   ; left or right
                cmp     al, 4
                jne     short loc_622D
                jmp     loc_6781  ; left arrow pressed: left edge scroll handler
; ---------------------------------------------------------------------------

loc_622D:   
                cmp     al, 8
                jnz     short loc_6234
                jmp     loc_67F4  ; right arrow pressed: right edge scroll handler
; ---------------------------------------------------------------------------

loc_6234:   
                or      byte ptr ds:hero_animation_phase, 1
                mov     ds:hero_moved_flag, 0FFh
                retn

; =============== S U B R O U T I N E =======================================


; On spacebar latch, looks for NPC tile ahead of hero and starts conversation.
;   Input: ds:spacebar_latch (non-zero to trigger)
;   Output: clears spacebar_latch; may start NPC conversation
;   Uses: si = pointer to NPC struct when found
;   Modifies: si, al, ah (restored after conversation call)
hero_spacebar_interaction        proc near
                test    byte ptr byte ptr ds:spacebar_latch, 0FFh
                jnz     short loc_6247
                retn
; ---------------------------------------------------------------------------

loc_6247:   
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     bl, ds:hero_x_in_viewport
                add     bl, 4  ; viewport_col
                xor     bh, bh
                mov     dx, bx
                add     dx, ds:proximity_map_left_col_x ; abs_x
                add     bl, bl
                add     bl, bl
                add     bl, bl
                add     bl, 5
                add     bx, ds:proximity_start_tiles ; bx = (viewport_col * 8 + 5) + PROX_START;
                test    byte ptr ds:facing_direction, 1
                jnz     short loc_62AE
                ; hero facing right
                inc     dx
                cmp     byte ptr [bx+8], 0FDh
                je      short loc_6285
                inc     dx
                cmp     byte ptr [bx+16], 0FDh
                je      short loc_6285
                inc     dx
                cmp     byte ptr [bx+24], 0FDh
                je      short loc_6285
                retn
; ---------------------------------------------------------------------------
; found NPC to the right of hero
loc_6285:   
                call    find_first_npc_at_x
                mov     al, [si+NPC.n_flags]
                and     al, 0C0h
                jz      short loc_6290
                retn
; ---------------------------------------------------------------------------

loc_6290:   
                mov     al, [si+NPC.n_facing]
                mov     ah, [si+NPC.n_ai_type]
                push    ax
                mov     byte ptr [si+NPC.n_ai_type], 7
                or      byte ptr [si+NPC.n_facing], 80h
                or      byte ptr [si+NPC.n_anim_phase], 1
                call    start_npc_conversation
                pop     ax
                mov     [si+NPC.n_ai_type], ah
                mov     [si+NPC.n_facing], al
                retn
; ---------------------------------------------------------------------------
; hero facing left
loc_62AE:   
                dec     dx
                cmp     byte ptr [bx-8], 0FDh
                je      short loc_62C4
                dec     dx
                cmp     byte ptr [bx-16], 0FDh
                je      short loc_62C4
                dec     dx
                cmp     byte ptr [bx-24], 0FDh
                je      short loc_62C4
                retn
; ---------------------------------------------------------------------------
; found NPC to the left of hero
loc_62C4:   
                call    find_first_npc_at_x
                mov     al, [si+NPC.n_flags]
                and     al, 0C0h
                jz      short loc_62CF
                retn
; ---------------------------------------------------------------------------

loc_62CF:   
                mov     al, [si+NPC.n_facing]
                mov     ah, [si+NPC.n_ai_type]
                push    ax
                mov     byte ptr [si+NPC.n_ai_type], 7
                and     byte ptr [si+NPC.n_facing], 7Fh
                or      byte ptr [si+NPC.n_anim_phase], 1
                call    start_npc_conversation
                pop     ax
                mov     [si+NPC.n_ai_type], ah
                mov     [si+NPC.n_facing], al
                retn
hero_spacebar_interaction        endp


; =============== S U B R O U T I N E =======================================


; Checks if hero is 2 tiles ahead of NPC with n_flags bit7 set
; and initiates special NPC dialog.
;   Input: ds:hero_x_in_viewport, ds:proximity_map_left_col_x,
;          ds:facing_direction
;   Output: may set dialog_exit_flag=0FFh and start NPC conversation
;   Uses: si = pointer to NPC struct when found
check_special_npc_conversation        proc near
                mov     bl, ds:hero_x_in_viewport
                add     bl, 4  ; viewport_col
                xor     bh, bh
                mov     dx, bx
                add     dx, ds:proximity_map_left_col_x ; abs_x
                add     bl, bl
                add     bl, bl
                add     bl, bl
                add     bl, 5
                add     bx, ds:proximity_start_tiles ; bx = (viewport_col * 8 + 5) + PROX_START;
                test    byte ptr ds:facing_direction, 1
                jnz     short loc_6335
            ; facing right
                inc     dx
                inc     dx
                cmp     byte ptr [bx+16], 0FDh ; NPC 2 columns ahead
                je      short loc_6319
                retn
; ---------------------------------------------------------------------------
loc_6319:   
                call    find_first_npc_at_x  ; input: dx = target x
                test    byte ptr [si+2], 80h ; n_facing; left==towards hero
                jnz     short loc_6323
                retn
; ---------------------------------------------------------------------------
loc_6323:   
                test    byte ptr [si+6], 80h ; n_flags
                jnz     short loc_632A
                retn
; ---------------------------------------------------------------------------
loc_632A:   
                or      byte ptr [si+4], 1 ; n_anim_phase
                mov     ds:dialog_exit_flag, 0FFh
                jmp     short start_npc_conversation
; ---------------------------------------------------------------------------
            ; facing left
loc_6335:   
                dec     dx
                dec     dx
                cmp     byte ptr [bx-16], 0FDh ; NPC 2 columns ahead
                jz      short loc_633E
                retn
; ---------------------------------------------------------------------------
loc_633E:   
                call    find_first_npc_at_x
                test    byte ptr [si+2], 80h ; n_facing
                jz      short loc_6348
                retn
; ---------------------------------------------------------------------------
loc_6348:   
                test    byte ptr [si+6], 80h ; n_flags
                jnz     short loc_634F
                retn
; ---------------------------------------------------------------------------
loc_634F:   
                or      byte ptr [si+4], 1 ; n_anim_phase
                mov     ds:dialog_exit_flag, 0FFh
                jmp     short $+2
check_special_npc_conversation        endp


; =============== S U B R O U T I N E =======================================


; Begins NPC dialog: captures screen behind
;   dialog box, renders dialog text, then restores screen.
;   Input: si = pointer to NPC struct
;          [si+6] bit 7 cleared to mark NPC as "in conversation"
;          [si+7] = conversation pattern group index
;          ds:facing_direction determines dialog box position
;   Output: dialog rendered on screen; spacebar_latch cleared
;   Modifies: ax, cx, di (used for screen capture/restore)

start_npc_conversation        proc near
                and     byte ptr [si+NPC.n_flags], 7Fh
                mov     al, [si+NPC.n_id]
                push    si
                push    ax
                mov     byte ptr ds:frame_timer, 40
                call    game_loop_with_frame_wait
                mov     byte ptr byte ptr ds:soundFX_request, 30
                mov     ax, 718h
                test    byte ptr ds:facing_direction, 1
                jnz     short loc_637D
                mov     ax, 0B18h

loc_637D:   
                mov     ds:dialog_rect_pos, ax
                xor     di, di
                mov     cx, 1658h
                call    cs:Capture_Screen_Rect_to_seg3_proc
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                pop     bx
                mov     ax, ds:dialog_rect_pos
                call    render_dialog_text
                mov     ax, ds:dialog_rect_pos
                xor     di, di
                mov     cx, 1658h
                call    cs:Put_Image_proc  ; restore screen
                pop     si
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                push    cs
                pop     es
                mov     al, 0FEh
                mov     di, viewport_buffer
                mov     cx, 28*8
                rep stosb
                mov     ds:dialog_exit_flag, 0
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     byte ptr byte ptr ds:altkey_latch, 0
                retn
start_npc_conversation        endp


; =============== S U B R O U T I N E =======================================

; Renders dialog text with word wrap,
;   scrolling, and control codes (0x81-0x8B for shop/quest triggers, 0xFF=end).
;   Input: ds:dialog_text_ptr = initial dialog text string pointer
;   Output: dialog text rendered; modifies ds:dialog_* variables
;   Returns: when spacebar pressed or 0xFF terminator reached

render_dialog_text        proc near       

                or      byte ptr ds:hero_animation_phase, 1

loc_63CA:   
                mov     ds:dialog_src_rect, ax
                mov     ds:dialog_cursor_pos, ax
                xor     bh, bh
                add     bx, bx
                add     bx, ds:npc_conversations_addr
                mov     si, [bx]
                mov     ds:dialog_char_x, 0
                mov     ds:dialog_char_y, 0
                mov     ds:dialog_line_start_x, 0
                mov     ds:dialog_lines_rendered, 0
                mov     ds:dialog_text_ptr, si
                call    count_dialog_lines
                mov     al, cl
                mov     ds:dialog_chars_on_line, al
                cmp     al, 8
                jb      short loc_6400
                mov     al, 8

loc_6400:   
                push    ax
                mov     cl, 0Ah
                mul     cl
                add     al, 6
                mov     cl, al
                mov     ch, 2Ch ; ','
                mov     ds:dialog_rect_end, cx
                mov     al, 56h ; 'V'
                sub     al, cl
                mov     bx, ds:dialog_cursor_pos
                add     bl, al
                pop     ax
                and     al, 0FEh
                add     al, al
                add     al, al
                add     al, al
                mov     ah, 40h ; '@'
                sub     ah, al
                shr     ah, 1
                sub     bl, ah
                mov     ds:dialog_cursor_pos, bx
                add     bh, bh
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc

loc_6437:   
                mov     si, ds:dialog_text_ptr
                lodsb
                mov     ds:dialog_text_ptr, si
                cmp     al, 2Fh ; '/'
                jnz     short loc_6447
                jmp     loc_64E6
; ---------------------------------------------------------------------------

loc_6447:   
                cmp     al, 81h
                jne     short loc_644E
                jmp     on_flag_0x81
; ---------------------------------------------------------------------------

loc_644E:   
                cmp     al, 83h
                jne     short loc_6455
                jmp     on_flag_0x83
; ---------------------------------------------------------------------------

loc_6455:   
                cmp     al, 85h
                jne     short loc_645C
                jmp     on_flag_0x85
; ---------------------------------------------------------------------------

loc_645C:   
                cmp     al, 87h
                jne     short loc_6463
                jmp     on_flag_0x87
; ---------------------------------------------------------------------------

loc_6463:   
                cmp     al, 89h
                jne     short loc_646A
                jmp     on_flag_0x89
; ---------------------------------------------------------------------------

loc_646A:   
                cmp     al, 8Bh
                jne     short loc_6471
                jmp     on_flag_0x8b
; ---------------------------------------------------------------------------

loc_6471:   
                cmp     al, 0FFh
                jnz     short loc_6478
                jmp     wait_for_dialog_input
; ---------------------------------------------------------------------------

loc_6478:   
                push    ax
                mov     cx, ds:dialog_cursor_pos
                xor     bh, bh
                mov     bl, ch
                add     bx, bx
                add     bx, bx
                add     bx, bx
                mov     al, ds:dialog_char_x
                xor     ah, ah
                add     bx, ax
                add     bx, 4
                mov     al, ds:dialog_char_y
                mov     dl, 0Ah
                mul     dl
                add     cl, al
                add     cl, 4
                pop     ax
                push    bx
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     dl, ds:char_x_offset[bx]
                mov     dh, bh
                pop     bx
                push    ax
                sub     bx, dx
                mov     ah, 1
                call    cs:Render_Font_Glyph_proc
                pop     ax
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     cl, ds:char_width_table[bx]
                add     ds:dialog_char_x, cl
                cmp     al, 20h ; ' '
                jz      short loc_64CE
                jmp     loc_6437
; ---------------------------------------------------------------------------

loc_64CE:   
                mov     si, ds:dialog_text_ptr
                call    measure_text_to_delimiter
                mov     dl, ds:dialog_char_x
                xor     dh, dh
                add     dx, cx
                cmp     dx, 0A8h
                jnb     short loc_64E6
                jmp     loc_6437
; ---------------------------------------------------------------------------

loc_64E6:   
                mov     ds:dialog_char_x, 0
                inc     ds:dialog_char_y
                cmp     ds:dialog_char_y, 8
                jnz     short loc_6516
                dec     ds:dialog_char_y
                mov     cx, 10

loc_64FD:   
                push    cx
                mov     bx, ds:dialog_cursor_pos
                add     bl, 4
                mov     cx, ds:dialog_rect_end
                shr     ch, 1
                sub     cl, 8
                call    cs:Scroll_Screen_Rect_Down_proc
                pop     cx
                loop    loc_64FD

loc_6516:   
                inc     ds:dialog_lines_rendered
                cmp     ds:dialog_lines_rendered, 7
                jnb     short loc_6524
                jmp     loc_6437
; ---------------------------------------------------------------------------

loc_6524:   
                cmp     ds:dialog_chars_on_line, 8
                jnz     short loc_652E
                jmp     loc_6437
; ---------------------------------------------------------------------------

loc_652E:   
                sub     ds:dialog_chars_on_line, 7
                mov     cx, ds:dialog_cursor_pos
                xor     bh, bh
                mov     bl, ch
                add     bx, bx
                add     bx, bx
                add     bx, bx
                add     bx, 54h ; 'T'
                add     cl, 4Ah ; 'J'
                push    cx
                push    bx
                mov     ax, 27Ch
                call    cs:Render_Font_Glyph_proc
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     byte ptr byte ptr ds:altkey_latch, 0
                pop     bx
                pop     cx

loc_655D:   
                push    cx
                push    bx
                call    draw_dialog_cursor
                call    update_npcs_and_render
                pop     bx
                pop     cx
                test    ds:dialog_exit_flag, 0FFh
                jnz     short loc_6576
                test    byte ptr byte ptr ds:altkey_latch, 0FFh
                jz      short loc_6576
                retn
; ---------------------------------------------------------------------------

loc_6576:   
                test    byte ptr byte ptr ds:spacebar_latch, 0FFh
                jz      short loc_655D
                shr     bx, 1
                shr     bx, 1
                mov     bh, bl
                mov     bl, cl
                xor     al, al
                mov     cx, 208h
                call    cs:Draw_Bordered_Rectangle_proc
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     ds:dialog_lines_rendered, 0
                mov     byte ptr byte ptr ds:soundFX_request, 29
                jmp     loc_6437 ; next dialog page
render_dialog_text        endp


; =============== S U B R O U T I N E =======================================


; waits for player input during dialog
;   Input: (none — polls spacebar_latch, altkey_latch, joystick direction)
;   Output: returns on spacebar press; CF set on direction input
wait_for_dialog_input        proc near     
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     byte ptr byte ptr ds:altkey_latch, 0

loc_65AB:   
                call    draw_dialog_cursor
                call    update_npcs_and_render
                test    byte ptr byte ptr ds:spacebar_latch, 0FFh
                jz      short loc_65B9
                retn
; ---------------------------------------------------------------------------

loc_65B9:   
                test    byte ptr byte ptr ds:altkey_latch, 0FFh
                jz      short loc_65C1
                retn
; ---------------------------------------------------------------------------

loc_65C1:   
                test    byte ptr ds:____right_left_down_up, 0FFh
                jnz     short loc_65AB

loc_65C8:   
                call    draw_dialog_cursor
                call    update_npcs_and_render
                test    byte ptr byte ptr ds:spacebar_latch, 0FFh
                jz      short loc_65D6
                retn
; ---------------------------------------------------------------------------

loc_65D6:   
                test    byte ptr byte ptr ds:altkey_latch, 0FFh
                jz      short loc_65DE
                retn
; ---------------------------------------------------------------------------

loc_65DE:   
                test    byte ptr ds:____right_left_down_up, 0FFh
                jz      short loc_65C8
                retn
wait_for_dialog_input        endp


; =============== S U B R O U T I N E =======================================


; measures pixel width of text until
;   space (0x20), slash (0x2F), negative byte, or terminator.
;   Input: si = pointer to text string
;   Output: cl = total pixel width, si advanced past measured text
measure_text_to_delimiter        proc near 
                xor     cx, cx

loc_65E8:   
                lodsb
                or      al, al
                jns     short loc_65EE
                retn
; ---------------------------------------------------------------------------

loc_65EE:   
                cmp     al, 20h ; ' '
                jnz     short loc_65F3
                retn
; ---------------------------------------------------------------------------

loc_65F3:   
                cmp     al, 2Fh ; '/'
                jnz     short loc_65F8
                retn
; ---------------------------------------------------------------------------

loc_65F8:   
                sub     al, 20h ; ' '
                jb      short loc_65E8
                mov     bl, al
                xor     bh, bh
                add     cl, cs:char_width_table[bx]
                adc     ch, bh
                jmp     short loc_65E8
measure_text_to_delimiter        endp


; =============== S U B R O U T I N E =======================================


; count_dialog_lines — counts lines and columns needed to
;   render dialog text within 0xA8 pixel width limit.
;   Input: si = pointer to dialog text string
;   Output: cl = number of lines, cx = chars on last line

count_dialog_lines        proc near
                xor     cx, cx
                xor     dx, dx

loc_660D:   
                lodsb
                or      al, al
                js      short loc_6646
                cmp     al, 2Fh ; '/'
                jnz     short loc_661B
                inc     cx
                xor     dx, dx
                jmp     short loc_660D
; ---------------------------------------------------------------------------

loc_661B:   
                push    cx
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     cl, ds:char_width_table[bx]
                mov     ch, bh
                add     dx, cx
                pop     cx
                cmp     al, 20h ; ' '
                jnz     short loc_660D
                push    cx
                push    si
                push    dx
                call    measure_text_to_delimiter
                add     dx, cx
                cmp     dx, 0A8h
                pop     dx
                pop     si
                pop     cx
                jb      short loc_660D
                xor     dx, dx
                inc     cx
                jmp     short loc_660D
; ---------------------------------------------------------------------------

loc_6646:   
                or      dx, dx
                jnz     short loc_664B
                retn
; ---------------------------------------------------------------------------

loc_664B:   
                inc     cx
                retn
count_dialog_lines        endp

; ---------------------------------------------------------------------------

on_flag_0x8b:   
                or      byte ptr ds:byte_4, 80h
                jmp     init_c015_obj_if_exists
; ---------------------------------------------------------------------------

on_flag_0x81:   
                mov     bx, ds:dialog_rect_pos
                add     bh, bh
                add     bx, 193Fh
                push    bx
                mov     cx, 0C19h
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                pop     bx
                add     bx, 103h
                mov     ds:menu_base_addr, bx
                call    show_yes_no_dialog
                mov     ax, ds:dialog_rect_pos
                mov     bl, 0Dh
                jnb     short loc_6680
                jmp     render_dialog_text
; ---------------------------------------------------------------------------

loc_6680:   
                mov     bl, 0Ch
                jmp     render_dialog_text
; ---------------------------------------------------------------------------

on_flag_0x83:   
                or      byte ptr ds:caliente_items, 80h ; +128 - Spoke to the girl after defeating Paguro
                mov     byte ptr ds:elf_crest, 0FFh
                call    init_c015_obj_if_exists
                jmp     wait_for_dialog_input
; ---------------------------------------------------------------------------

on_flag_0x85:   
                mov     ds:dialog_exit_flag, 0FFh
                mov     bl, 4
                mov     ax, ds:dialog_src_rect
                jmp     render_dialog_text
; ---------------------------------------------------------------------------

on_flag_0x87:   
                call    wait_for_dialog_input
                mov     bl, 5
                mov     ax, ds:dialog_src_rect
                jmp     render_dialog_text
; ---------------------------------------------------------------------------

on_flag_0x89:   
                mov     bx, ds:dialog_rect_pos
                add     bh, bh
                add     bx, 1832h
                push    bx
                mov     cx, 1219h
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                pop     bx
                add     bx, 203h
                mov     ds:menu_base_addr, bx
                call    confirm_purchase_dialog
                mov     ax, ds:dialog_rect_pos
                mov     bl, 6
                jnb     short loc_66D8
                jmp     render_dialog_text
; ---------------------------------------------------------------------------

loc_66D8:   
                mov     dx, ds:hero_almas
                sub     dx, 2500
                mov     bl, 7
                jnb     short loc_66E7
                jmp     render_dialog_text
; ---------------------------------------------------------------------------

loc_66E7:   
                mov     word ptr ds:hero_almas, dx
                call    cs:Print_Almas_Decimal_proc
                or      byte ptr ds:caliente_items, 40h ; +64 - Purchased the Asbestos Cape
                mov     si, Feruza_Shoes

loc_66F8:   
                test    byte ptr [si], 0FFh
                jz      short loc_6700
                inc     si
                jmp     short loc_66F8
; ---------------------------------------------------------------------------
            ; empty slot found
loc_6700:   
                mov     byte ptr [si], 5  ; put Asbestos_Cape id in the first empty slot
                call    init_c015_obj_if_exists
                mov     ax, ds:dialog_rect_pos
                mov     bl, 8
                jmp     render_dialog_text

; =============== S U B R O U T I N E =======================================


; confirm_purchase_dialog — shows "Take/No Take" purchase confirmation.
;   Input: (none — uses ds:word_FF52/FF53 for menu dimensions)
;   Output: CF=set if "Take" selected, CF=clear if "No Take"

confirm_purchase_dialog        proc near
                mov     byte ptr ds:menu_item_count, 2
                mov     byte ptr ds:menu_max_items, 2
                mov     cx, 2
                mov     si, offset aTake ; "Take"
                call    render_menu_string_list
                mov     byte ptr ds:menu_cursor_pos, 0
                xor     bl, bl
                call    select_from_menu
                jnb     short loc_672F
                mov     bl, 1

loc_672F:   
                or      bl, bl
                jnz     short loc_6734
                retn
; ---------------------------------------------------------------------------

loc_6734:   
                stc
                retn
confirm_purchase_dialog        endp

; ---------------------------------------------------------------------------
aTake           db 'Take',0            
aNoTake         db 'No Take',0

; =============== S U B R O U T I N E =======================================


; draw_dialog_cursor — draws the '>' arrow next to dialog text.
;   Input: ds:dialog_cursor_pos (top-left), ds:dialog_rect_end (bottom-right),
;          ds:dialog_char_y (current row)

draw_dialog_cursor        proc near
                mov     ax, ds:dialog_cursor_pos
                sub     ah, 6
                mov     cx, ds:dialog_rect_end
                add     al, cl
                cmp     al, 56h ; 'V'
                jnb     short loc_6754
                retn
; ---------------------------------------------------------------------------

loc_6754:   
                push    ax
                xor     ah, ah
                sub     al, 4Eh ; 'N'
                mov     cx, 8
                div     cl
                mov     cl, al
                pop     ax
                push    cs
                pop     es
                mov     di, 0E000h
                mov     al, ah
                mov     dl, 8
                mul     dl
                add     di, ax
                mov     al, 0FFh

loc_6770:   
                push    cx
                push    di
                mov     cx, 16h

loc_6775:   
                stosb
                add     di, 7
                loop    loc_6775
                pop     di
                inc     di
                pop     cx
                loop    loc_6770
                retn
draw_dialog_cursor        endp

; ---------------------------------------------------------------------------
; left edge scroll handler
loc_6781:   
                xor     bx, bx
                mov     bl, ds:hero_x_in_viewport
                add     bl, 3
                add     bx, bx
                add     bx, bx
                add     bx, bx  ; (HERO_XV + 3) * 8
                add     bx, ds:proximity_start_tiles
                mov     al, [bx+7] ; bottom tile to the left of hero
                call    check_tile_in_special_list ; NZ if tile not found, ZF if found
                jnz     short loc_679D
                retn  ; tile ahead is not passable, return
; ---------------------------------------------------------------------------
; tile ahead is passable, process movement/scrolling
loc_679D:   
                xor     bx, bx
                mov     bl, ds:hero_x_in_viewport
                add     bl, 4
                add     bx, ds:proximity_map_left_col_x
                dec     bx
                call    find_non_passable_npc_at_x_pos
                jz      short loc_67B1
                retn
; ---------------------------------------------------------------------------
loc_67B1:   
                inc     byte ptr ds:hero_animation_phase
                and     byte ptr ds:hero_animation_phase, 3  ; 4 walking phases total
                or      byte ptr ds:facing_direction, 1  ; set facing Left
                cmp     byte ptr ds:hero_x_in_viewport, 11
                jb      short loc_67CB ; need to scroll
                dec     byte ptr ds:hero_x_in_viewport
                retn
; ---------------------------------------------------------------------------
loc_67CB:   
                test    word ptr ds:proximity_map_left_col_x, 0FFFFh
                jnz     short loc_67D8
                dec     byte ptr ds:hero_x_in_viewport
                retn
; ---------------------------------------------------------------------------
loc_67D8:   
                dec     word ptr ds:proximity_map_left_col_x
                sub     word ptr ds:proximity_start_tiles, 8
                call    cs:scroll_floor_right_8px_proc
                cmp     ds:town_has_middle_layer, 1
                jz      short loc_67EE
                retn
; ---------------------------------------------------------------------------
loc_67EE:   
                call    cs:scroll_ceiling_right_4px_proc
                retn
; ---------------------------------------------------------------------------
; right edge scroll handler
loc_67F4:   
                xor     bx, bx
                mov     bl, ds:hero_x_in_viewport
                add     bl, 6
                add     bx, bx
                add     bx, bx
                add     bx, bx
                add     bx, ds:proximity_start_tiles
                mov     al, [bx+7]  ; tile to the right of hero
                call    check_tile_in_special_list  ; NZ if tile not found, ZF if found
                jnz     short loc_6810
                retn
; ---------------------------------------------------------------------------

loc_6810:   
                xor     bx, bx
                mov     bl, ds:hero_x_in_viewport
                add     bl, 4
                add     bx, ds:proximity_map_left_col_x
                inc     bx
                call    find_non_passable_npc_at_x_pos
                jz      short loc_6824
                retn
; ---------------------------------------------------------------------------

loc_6824:   
                inc     byte ptr ds:hero_animation_phase
                and     byte ptr ds:hero_animation_phase, 3
                and     byte ptr ds:facing_direction, 0FEh
                cmp     byte ptr ds:hero_x_in_viewport, 10h
                jnb     short loc_683E
                inc     byte ptr ds:hero_x_in_viewport
                retn
; ---------------------------------------------------------------------------

loc_683E:   
                mov     ax, ds:mapWidth
                sub     ax, 23h ; '#'
                mov     bx, ds:proximity_map_left_col_x
                inc     bx
                cmp     ax, bx
                jnz     short loc_6852
                inc     byte ptr ds:hero_x_in_viewport
                retn
; ---------------------------------------------------------------------------

loc_6852:   
                inc     word ptr ds:proximity_map_left_col_x
                add     word ptr ds:proximity_start_tiles, 8
                call    cs:scroll_floor_left_8px_proc
                cmp     ds:town_has_middle_layer, 1
                jz      short loc_6868
                retn
; ---------------------------------------------------------------------------

loc_6868:   
                call    cs:scroll_ceiling_left_4px_proc
                retn

; =============== S U B R O U T I N E =======================================


; Checks if tile AL is in a special list (non-passable).
;   Input: al = tile ID
;   Output: NZ if tile not found, ZF if found
;   Uses: es:seg1:special_tile_list_ptr = pointer to tile list (counted)
check_tile_in_special_list        proc near
                mov     es, cs:seg1
                mov     si, es:special_tile_list_ptr  ; seg1:8002h
                mov     cl, es:[si]  ; list length
                or      cl, cl
                jz      short loc_688B
                xor     ch, ch
                inc     si  ; points to special tiles
loc_6882:   
                cmp     al, es:[si]
                jne     short loc_6888
                retn  ; found => set ZF on exit
loc_6888:   
                inc     si
                loop    loc_6882
loc_688B:   
                not     cl   ; empty list or not found => set NZ on exit
                or      cl, cl
                retn
check_tile_in_special_list        endp


; =============== S U B R O U T I N E =======================================


; find_non_passable_npc_at_x_pos — searches NPC array for NPC whose x coordinate
;   matches and has bit 6 set in n_flags (non-passable).
;   Input: bx = target x coordinate
;   Output: NZ if found (si = pointer to NPC), ZF=set if not found
find_non_passable_npc_at_x_pos        proc near
                mov     si, ds:npc_array_addr
loc_6894:   
                mov     ax, [si]
                cmp     ax, 0FFFFh
                jnz     short loc_689C
                retn  ; not found => set ZF
; ---------------------------------------------------------------------------
loc_689C:   
                sub     ax, bx
                jnz     short loc_68A7
                test    byte ptr [si+NPC.n_flags], 01000000b ; non-passable NPC
                jz      short loc_68A7
                retn  ; found non-passable NPC => set NZ
; ---------------------------------------------------------------------------
loc_68A7:   
                add     si, size NPC
                jmp     short loc_6894
find_non_passable_npc_at_x_pos        endp


; =============== S U B R O U T I N E =======================================


; updates NPCs then calls game_loop_with_frame_wait for one frame of rendering.
;   Input: (none)
update_npcs_and_render        proc near
                call    update_npcs
update_npcs_and_render        endp


; =============== S U B R O U T I N E =======================================


; Main game loop that waits for frame_timer
;   to expire. Runs exit dialog, pause, speed change, joystick calibration,
;   and restore game handlers each iteration.
;   Input: ds:speed_const (controls loop duration)
;   Output: returns when frame_timer reaches speed_const * 4
;   Side effects: may call restore_game if Handle_Restore_Game returns CF
game_loop_with_frame_wait        proc near
                call    prepare_hero_sprite
                call    clear_6_hero_tiles_in_viewport_buffer
                call    cs:render_town_tiles_28_columns_proc
                mov     cl, ds:speed_const ; =5 (standard speed?)
                mov     al, 4
                mul     cl  ; 4*speed = sleep delay

loc_68C2:   
                push    ax
                call    cs:Confirm_Exit_Dialog_proc ; Confirm_Exit_Dialog
                call    cs:Handle_Pause_State_proc ; Handle_Pause_State
                call    cs:Handle_Speed_Change_proc ; Handle_Speed_Change
                call    cs:Joystick_Calibration_proc ; Joystick_Calibration
                call    cs:Joystick_Deactivator_proc ; Joystick_Deactivator
                call    cs:Handle_Restore_Game_proc ; Handle_Restore_Game
                jnb     short loc_68E6
                call    restore_game

loc_68E6:   
                pop     ax
                cmp     ds:frame_timer, al
                jb      short loc_68C2
                mov     byte ptr ds:frame_timer, 0
                retn
game_loop_with_frame_wait        endp


; =============== S U B R O U T I N E =======================================


; handle_inventory_key — on Enter key, clears viewport and calls
;   the overlay handler at cs:0A002h, then restores town background.
;   Input: bit 0 of F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter (Enter)

handle_inventory_key        proc near
                test    word ptr ds:F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter, 1
                jnz     short loc_68FC
                retn
; ---------------------------------------------------------------------------

loc_68FC:   
                mov     byte ptr byte ptr ds:soundFX_request, 11
                call    cs:Clear_Viewport_proc
                call    swap_a000_c000_buffers
                call    cs:word_A002
                call    swap_a000_c000_buffers
                call    cs:Clear_Viewport_proc
                call    call_background_code
                call    cs:backup_upper_town_3_tiles_proc ; skips top 8 tiles (sky, distant mountains)
                                        ; saves town top (3 tiles of 8) to screen buffer
                push    cs
                pop     es
                mov     al, 0FEh
                mov     di, 0E000h
                mov     cx, 0E0h
                rep stosb
                call    game_loop_with_frame_wait
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     byte ptr byte ptr ds:altkey_latch, 0
                retn
handle_inventory_key        endp


; =============== S U B R O U T I N E =======================================


; swap_a000_c000_buffers — swaps 2KB between 0C000h and 0A000h in seg1.
;   Used to save/restore town data before calling building binary.
;   Input/Output: seg1:0C000h and seg1:0A000h contents exchanged

swap_a000_c000_buffers        proc near
                mov     es, cs:seg1
                mov     di, 0C000h
                mov     si, 0A000h
                mov     cx, 800h

loc_6946:   
                mov     ax, es:[di]
                movsw
                mov     [si-2], ax
                loop    loc_6946
                retn
swap_a000_c000_buffers        endp


; =============== S U B R O U T I N E =======================================


; clear_6_hero_tiles_in_viewport_buffer — clears 6 tiles (2 columns × 3 rows)
;   around the hero in the viewport_buffer, marking them for redraw.
;   Input: ds:hero_x_in_viewport (0..27)
;   Modifies: viewport_buffer at hero position

clear_6_hero_tiles_in_viewport_buffer proc near
                mov     al, ds:hero_x_in_viewport
                cmp     al, 27
                jb      short loc_6958
                retn
; ---------------------------------------------------------------------------

loc_6958:   
                add     al, al
                add     al, al
                add     al, al
                add     al, 5
                xor     ah, ah
                add     ax, offset viewport_buffer
                mov     di, ax
                push    cs
                pop     es
                mov     al, 0FFh
                stosb                   ; clear 3 tiles
                stosb
                stosb
                add     di, 5           ; skip to next column
                stosb                   ; clear 3 tiles
                stosb
                stosb
                retn
clear_6_hero_tiles_in_viewport_buffer endp


; =============== S U B R O U T I N E =======================================


; prepare_hero_sprite — copies hero's 2×3 tile column from proximity map
;   into hero_2x3_tile_buf, handles 0xFD (NPC) tiles by loading NPC data,
;   sets up hero_1x3_tile_buf and hero_x, draws hero sprite to shadow memory.
;   Input: ds:hero_x_in_viewport, ds:proximity_start_tiles,
;          ds:proximity_map_left_col_x
;   Output: ds:hero_x (absolute), hero_2x3_tile_buf filled,
;           hero sprite rendered via ui_draw_routine_dispatcher
prepare_hero_sprite proc near
                push    cs
                pop     es
                xor     ax, ax
                mov     al, ds:hero_x_in_viewport
                add     al, 4           ; x in proximity map
                add     ax, ax
                add     ax, ax
                add     ax, ax          ; *8
                add     ax, 5           ; NPC head level
                add     ax, ds:proximity_start_tiles ; = +c5af
                push    ax
                mov     si, ax
                mov     di, offset hero_2x3_tile_buf
                movsw                   ; move 3 tiles from src to dst
                movsb
                add     si, 5           ; skip the rest (advanse to next column)
                mov     cx, 3
                movsw
                movsb
                xor     dx, dx
                mov     dl, ds:hero_x_in_viewport
                add     dl, 4           ; x in proximity map
                add     dx, ds:proximity_map_left_col_x
                push    dx              ; absolute hero x coord
                mov     si, offset hero_2x3_tile_buf
                mov     cx, 2

two_columns:
                push    si
                mov     al, [si]        ; CD CE CE CF D0 D0
                cmp     al, 0FDh
                jnz     short loc_69C8
                call    find_first_npc_at_x

loc_69B9:   
                mov     al, [si+3]
                cmp     al, 0FDh
                jnz     short loc_69C8
                add     si, 8
                call    find_first_npc_at_x_after_current
                jmp     short loc_69B9
; ---------------------------------------------------------------------------

loc_69C8:   
                pop     si
                mov     [si], al
                add     si, 3
                inc     dx              ; absolute hero x
                loop    two_columns
                mov     si, offset hero_2x3_tile_buf
                call    cs:unpack_to_shadow_memory_six_tiles_proc
                pop     dx
                dec     dx
                mov     ds:hero_x, dx   ; sprite absolute x
                pop     si              ; =c684
                push    cs
                pop     es
                mov     di, offset hero_1x3_tile_buf
                mov     al, [si-8]      ; [c67c]
                stosb
                mov     al, [si]        ; [c684]
                stosb
                mov     al, [si+8]      ; [c68c]
                stosb
                mov     si, ds:npc_array_addr

next_npc:   
                call    is_hero_close_to_npc ; Return:
                                        ; AL=3 if hero_1x3_tile_buf contains 0xfd special tile
                                        ; AL=0 otherwise
                or      al, al
                jz      short loc_6A11
                push    ax
                call    cs:get_sprite_vram_address_proc
                pop     bx
                mov     es, cs:seg1
                push    si
                mov     si, offset hero_2x3_tile_buf
                call    cs:ui_draw_routine_dispatcher_proc
                pop     si

loc_6A11:   
                add     si, 8
                cmp     [si+NPC.n_x], 0FFFFh
                jnz     short next_npc
                mov     si, offset hero_faced_left
                test    ds:byte ptr facing_direction, 1 ; bit0: 0=Right, 1=Left
                jnz     short loc_6A26
                mov     si, offset hero_faced_right

loc_6A26:   
                xor     ax, ax
                mov     al, ds:hero_animation_phase
                add     ax, ax
                mov     bx, ax
                add     ax, ax
                add     ax, bx          ; phase*6
                add     si, ax
                call    cs:blit_6_tiles_to_shadow_memory_proc
                retn
prepare_hero_sprite endp

; ---------------------------------------------------------------------------
; 0 1   6 7   00 01   06 07   20 21
; 2 3   8 9   12 13   16 17   22 23
; 4 5   A B   14 15   18 19   24 25
hero_faced_left db 0, 2, 4, 1, 3, 5    
                db 6, 8, 0Ah, 7, 9, 0Bh
                db 0, 0Ch, 0Eh, 1, 0Dh, 0Fh
                db 6, 10h, 12h, 7, 11h, 13h
                db 14h, 16h, 18h, 15h, 17h, 19h
hero_faced_right db 1Ah, 1Ch, 1Eh, 1Bh, 1Dh, 1Fh
                db 20h, 22h, 24h, 21h, 23h, 25h
                db 1Ah, 26h, 28h, 1Bh, 27h, 29h
                db 20h, 2Ah, 2Ch, 21h, 2Bh, 2Dh
                db 14h, 16h, 18h, 15h, 17h, 19h

; =============== S U B R O U T I N E =======================================

; Return:
; AL=3 if hero_1x3_tile_buf contains 0xfd special tile
; AL=0 otherwise

; is_hero_close_to_npc — checks if hero's tile row (hero_1x3_tile_buf)
;   contains 0xFD and if NPC at [si] matches hero's x position.
;   Input: si = pointer to NPC struct, dx = hero absolute x,
;          hero_1x3_tile_buf[3] = hero's tile row (horizontal)
;   Output: AL=3 (row count) if NPC is at hero's position with 0xFD tile,
;           AL=0 otherwise

is_hero_close_to_npc proc near
                mov     cx, 3
                mov     dx, ds:hero_x
                mov     di, offset hero_1x3_tile_buf

loc_6A81:   
                cmp     byte ptr [di], 0FDh
                jnz     short loc_6A8D
                mov     al, cl
                cmp     dx, [si+NPC.n_x]
                jnz     short loc_6A8D
                retn
; ---------------------------------------------------------------------------

loc_6A8D:   
                inc     di
                inc     dx
                loop    loc_6A81
                xor     al, al
                retn
is_hero_close_to_npc endp


; =============== S U B R O U T I N E =======================================


; Sets si to point to npc_array_addr.
;   Input: dx = target x
;   Output: si = ds:npc_array_addr

find_first_npc_at_x        proc near
                mov     si, ds:npc_array_addr
find_first_npc_at_x        endp


; find_first_npc_at_x_after_current — searches NPC array starting at [si] for NPC
;   whose x coordinate matches dx.
;   Input: dx = target x, si = current NPC pointer
;   Output: si = pointer to matching NPC, or si past end marker

find_first_npc_at_x_after_current        proc near
                cmp     dx, [si]
                jnz     short loc_6A9D
                retn
; ---------------------------------------------------------------------------

loc_6A9D:   
                add     si, 8
                jmp     short find_first_npc_at_x_after_current
find_first_npc_at_x_after_current        endp


; =============== S U B R O U T I N E =======================================
; Load pattern group and call town background entry
; Loads and decompresses the pattern tile set for the current town,
; then calls the background entry point via bg_entry_offset.
; Input: ds:pat_id (pattern group index), ds:bg_entry_offset (far ptr to background code)
; Output: patterns loaded to seg1:8000h, background code executed
; Modifies: ax, si, di, es
load_patterns_and_call_background        proc near               
                call    load_and_decompress_patterns

call_background_code:
                mov     al, ds:video_drv_id
                push    ds
                call    dword ptr ds:bg_entry_offset
                pop     ds
                retn
load_patterns_and_call_background        endp


; =============== S U B R O U T I N E =======================================
; Load town background (mountains, stalactites etc)
; Loads the appropriate background (foreground+background or just background
; depending on town_has_middle_layer) via res_dispatcher_proc.
; Input: ds:town_has_middle_layer (0 or 1), ds:pat_id (pattern index)
; Output: background sprites loaded to memory
; Modifies: ax, si, di, es
load_town_background        proc near               
                mov     al, ds:town_has_middle_layer
                and     al, 1
                mov     cl, 11
                mul     cl
                mov     si, ax
                add     si, offset vfs_ympd_bin
                mov     ax, cs
                add     ax, 2000h
                mov     ds:bg_entry_segment, ax   ; seg2
                mov     es, ax
                mov     di, town_background_decorations
                mov     al, 3     ; fn3_read_virtual_file
                call    cs:res_dispatcher_proc
                retn
load_town_background        endp

; ---------------------------------------------------------------------------
vfs_ympd_bin       dw 901h
aYmpdBin           db 'YMPD.BIN',0
                   dw 0A01h
aCkpdBin           db 'CKPD.BIN',0
bg_entry_offset    dw 3300h               
bg_entry_segment   dw 3000h               

; =============== S U B R O U T I N E =======================================


init_c015_obj_if_exists proc near       ; Initialize objects from word_C015 data table
                ; Iterates through a table of object descriptors at ds:word_C015,
                ; copying or skipping data blocks based on destination flags.
                ; Terminated by entry where (lo & hi) == 0xFF.
                ; Input: ds:word_C015 (pointer to object descriptor table)
                ; Output: objects copied to their destination addresses in memory
                ; Modifies: si, ax, bx

                mov     si, ds:word_C015

next_object:
                lodsw
                mov     bx, ax          ; dst addr
                and     al, ah
                inc     al
                jnz     short loc_6AFB
                retn                    ; ffff - stop marker
; ---------------------------------------------------------------------------

loc_6AFB:   
                lodsb
                and     al, [bx]
                jnz     short copy_mode

skip_until_ffff:       
                lodsw
                and     al, ah
                inc     al
                jz      short ffff_found
                inc     si
                jmp     short skip_until_ffff
; ---------------------------------------------------------------------------

copy_mode:  
                lodsw                   ; dst addr
                mov     bx, ax
                and     al, ah
                inc     al
                jz      short ffff_found
                mov     al, [si]        ; src byte
                mov     [bx], al
                inc     si
                jmp     short copy_mode
; ---------------------------------------------------------------------------

ffff_found: 
                jmp     short next_object
init_c015_obj_if_exists endp


; =============== S U B R O U T I N E =======================================


; Update all NPCs by running their AI procedures
; Calls restore_head_level_tiles_from_npcs to update NPC sprite tiles, then iterates
; through the NPC array dispatching each NPC's AI update function
; via npc_ai_jump_table based on n_ai_type value.
; Input: ds:npc_array_addr (pointer to NPC array, terminated by x=0FFFFh)
;       ds:npc_ai_jump_table (8-entry jump table)
; Output: NPC structs updated with correct x positions and states
; Modifies: si, ax, bx, dx
update_npcs     proc near               
                call    restore_head_level_tiles_from_npcs
                mov     si, ds:npc_array_addr

next_npc_:   
                mov     dx, [si+NPC.n_x]  ; NPC array
                cmp     dx, 0FFFFh
                jnz     short loc_6B2D
                jmp     save_head_level_tiles_in_npcs
; ---------------------------------------------------------------------------

loc_6B2D:   
                mov     bl, [si+NPC.n_ai_type]
                xor     bh, bh
                add     bx, bx
                mov     ax, ds:npc_ai_jump_table[bx]
                call    ax
                mov     [si+NPC.n_x], dx
                add     si, 8
                jmp     short next_npc_
update_npcs     endp

; ---------------------------------------------------------------------------
npc_ai_jump_table  dw offset npc_ai_look_at_hero_and_bob     
                dw offset npc_ai_patrol_1bit_phase
                dw offset npc_ai_patrol_2bit_phase
                dw offset npc_ai_face_hero
                dw offset npc_ai_bob_in_place
                dw offset npc_ai_patrol_bounce_1bit
                dw offset npc_ai_patrol_bounce_2bit
                dw offset npc_ai_static

; =============== S U B R O U T I N E =======================================


; NPC AI: face hero then bob in place
; Sets NPC to face the hero (bit 7 of field_2 based on hero position),
; then falls through to npc_ai_bob_in_place for bobbing animation.
; Input: si = pointer to NPC struct, ds:hero_x_in_viewport, 
;        dx = NPC x position
; Output: [si+NPC.n_facing] bit 7 set/cleared, [si+NPC.n_anim_phase] incremented
; Modifies: ax, bx
npc_ai_look_at_hero_and_bob        proc near               
                or      [si+NPC.n_facing], 80h
                mov     bl, ds:hero_x_in_viewport
                add     bl, 4
                xor     bh, bh
                add     bx, ds:proximity_map_left_col_x
                cmp     bx, dx
                jb      short npc_ai_bob_in_place
                and     [si+NPC.n_facing], 7Fh
                jmp     short npc_ai_bob_in_place
npc_ai_look_at_hero_and_bob        endp


; =============== S U B R O U T I N E =======================================

; Fast NPC patrol (every 2nd call)
; NPC AI: patrol between boundaries (1-bit phase counter)
; Increments n_anim_phase by 0x10 each frame; when bit 4 wraps to zero,
; Input: si = pointer to NPC struct, [si+NPC.n_anim_phase] = phase counter
; Output: [si+NPC.n_anim_phase] incremented, NPC may move to boundary
; Modifies: ax, ch
npc_ai_patrol_1bit_phase        proc near               
                mov     al, [si+NPC.n_anim_phase]
                add     al, 10h
                mov     [si+NPC.n_anim_phase], al
                mov     ch, al
                and     al, 10h
                jz      short patrol_between_boundaries
                retn
npc_ai_patrol_1bit_phase        endp

; CH: anim. phase
; DX: current X position of NPC
; AL: always 0
patrol_between_boundaries:   
                inc     ch ; anim_phase+1
                and     ch, 0Fh
                or      ch, al
                mov     [si+NPC.n_anim_phase], ch
                mov     bx, ds:npc_patrol_boundaries ; points to two 16-bit words: minX, maxX
                test    [si+NPC.n_facing], 80h
                jz      short loc_6B9A
; was walking left
                dec     dx  ; currX--
                cmp     [bx], dx  ; patrol minX
                jnb     short loc_6B95
                retn
; ---------------------------------------------------------------------------

loc_6B95:   
                and     [si+NPC.n_facing], 7Fh ; start walking right
                retn
; ---------------------------------------------------------------------------
; was walking right
loc_6B9A:   
                inc     dx  ; currX++
                cmp     word ptr [bx+2], dx ; patrol maxX
                jb      short loc_6BA1
                retn
; ---------------------------------------------------------------------------

loc_6BA1:   
                or      [si+NPC.n_facing], 80h ; start walking left
                retn

; =============== S U B R O U T I N E =======================================

; Slow NPC patrol (every 4th call)
; NPC AI: patrol between boundaries (2-bit phase counter)
; Increments field_4 by 0x10 each frame; when bits 4-5 wrap to zero,
; Input: si = pointer to NPC struct, [si+NPC.n_anim_phase] = phase counter
; Output: [si+NPC.n_anim_phase] incremented, NPC may move to boundary
; Modifies: ax, ch
npc_ai_patrol_2bit_phase        proc near               
                mov     al, [si+NPC.n_anim_phase]
                add     al, 10h
                mov     [si+NPC.n_anim_phase], al
                mov     ch, al
                and     al, 30h
                jz      short loc_6BB5
                retn
; ---------------------------------------------------------------------------

loc_6BB5:   
                jmp     short patrol_between_boundaries
npc_ai_patrol_2bit_phase        endp


; =============== S U B R O U T I N E =======================================


; NPC AI: face towards hero
; Sets bit 7 of n_facing based on whether hero is to the left or right
; of the NPC. Bit 7 clear = face right (toward hero if hero is right),
; bit 7 set = face left.
; Input: si = pointer to NPC struct, ds:hero_x_in_viewport, dx = NPC x position
; Output: [si+NPC.n_facing] bit 7 set/cleared based on hero position
; Modifies: ax, bx
npc_ai_face_hero        proc near               
                or      [si+NPC.n_facing], 80h
                mov     bl, ds:hero_x_in_viewport
                add     bl, 4
                xor     bh, bh
                add     bx, ds:proximity_map_left_col_x ; bx = hero x position in proximity map
                cmp     bx, dx
                jnb     short loc_6BCD
                retn  ; heroX < npcX; n_facing |= 0x80
; ---------------------------------------------------------------------------
; heroX >= npcX
loc_6BCD:   
                and     [si+NPC.n_facing], 7Fh ; n_facing &= ~0x80
                retn
npc_ai_face_hero        endp


; =============== S U B R O U T I N E =======================================

; NPC AI: bob up and down in place
; Increments n_anim_phase by 0x10 each frame; when bits 4-5 wrap,
; toggles the lowest bit of the phase into n_anim_phase for bobbing animation.
; Input: si = pointer to NPC struct, [si+NPC.n_anim_phase] = phase counter
; Output: [si+NPC.n_anim_phase] updated with bob animation bits
; Modifies: ax, ch
npc_ai_bob_in_place        proc near               
                mov     al, [si+NPC.n_anim_phase]
                add     al, 10h
                mov     [si+NPC.n_anim_phase], al
                mov     ch, al
                and     al, 30h ; every 4th call
                jz      short loc_6BE1
                retn
; ---------------------------------------------------------------------------
; every 4-th frame. 0->1, 1->0
loc_6BE1:   
                inc     ch
                and     ch, 1 ; for bobbing in place NPC only low bit matters
                or      al, ch ; al is always 0
                mov     [si+NPC.n_anim_phase], al
                retn
npc_ai_bob_in_place        endp


; =============== S U B R O U T I N E =======================================


npc_ai_patrol_bounce_1bit        proc near               ; NPC AI: patrol with bounce direction toggle (1-bit)
                ; Increments field_4 by 0x10 each frame; when bit 4 wraps,
                ; falls through to patrol_bounce_at_phase to toggle facing direction.
                ; Input: si = pointer to NPC struct, [si+NPC.n_anim_phase] = phase counter
                ; Output: [si+NPC.n_anim_phase] incremented, may toggle facing direction
                ; Modifies: ax, ch
                mov     al, [si+NPC.n_anim_phase]
                add     al, 10h
                mov     [si+NPC.n_anim_phase], al
                mov     ch, al
                and     al, 10h
                jz      short patrol_bounce_at_phase
                retn
npc_ai_patrol_bounce_1bit        endp

; ---------------------------------------------------------------------------
;   ADDITIONAL PARENT FUNCTION npc_ai_patrol_bounce_1bit

patrol_bounce_at_phase:   
                inc     ch
                and     ch, 0Fh
                or      ch, al
                mov     [si+NPC.n_anim_phase], ch
                and     ch, 7
                jnz     short loc_6C0F
                xor     [si+NPC.n_facing], 80h
                retn
; ---------------------------------------------------------------------------

loc_6C0F:   
                test    [si+NPC.n_facing], 80h
                jz      short loc_6C17
                dec     dx
                retn
; ---------------------------------------------------------------------------

loc_6C17:   
                inc     dx
                retn

; =============== S U B R O U T I N E =======================================


; NPC AI: patrol with bounce direction toggle (2-bit)
; Increments field_4 by 0x10 each frame; when bits 4-5 wrap,
; falls through to patrol_bounce_at_phase for wider bounce range.
; Input: si = pointer to NPC struct, [si+NPC.n_anim_phase] = phase counter
; Output: [si+NPC.n_anim_phase] incremented, may toggle facing direction
; Modifies: ax, ch
npc_ai_patrol_bounce_2bit        proc near               

                mov     al, [si+NPC.n_anim_phase]
                add     al, 10h
                mov     [si+NPC.n_anim_phase], al
                mov     ch, al
                and     al, 30h
                jz      short loc_6C28
                retn
; ---------------------------------------------------------------------------

loc_6C28:   
                jmp     short patrol_bounce_at_phase
npc_ai_patrol_bounce_2bit        endp

npc_ai_static       proc near               ; NPC AI: do nothing (static NPC)
                ; No-op AI function; NPC remains in place with no animation.
                ; Input: si = pointer to NPC struct
                ; Output: none
                ; Modifies: nothing
                retn
npc_ai_static       endp

; =============== S U B R O U T I N E =======================================


; Mark all NPCs as initialized by replacing head tiles
; Iterates the NPC array, reads each town tile under NPC's head from town_head_level_tiles,
; replaces it with 0xFD (marker "NPC is here"), and stores original
; in n_head_tile for later restoration.
; Input: none
; Output: none
; Modifies: si, bx, al
save_head_level_tiles_in_npcs proc near          
                mov     si, ds:npc_array_addr

_next_npc:   
                mov     bx, [si+NPC.n_x]
                cmp     bx, 0FFFFh
                jnz     short loc_6C37
                retn
; ---------------------------------------------------------------------------

loc_6C37:   
                add     bx, bx
                add     bx, bx
                add     bx, bx
                mov     al, ds:town_head_level_tiles[bx] ; original town tile on the head level
                mov     byte ptr ds:town_head_level_tiles[bx], 0FDh
                mov     [si+NPC.n_head_tile], al ; keep town tile ID in the NPC struc for later restoration
                add     si, 8
                jmp     short _next_npc
save_head_level_tiles_in_npcs endp


; =============== S U B R O U T I N E =======================================


; Restore town head-level tiles from corresponding NPC structs
; Iterates the NPC array and for each NPC whose n_head_tile != 0xFD,
; restores the original town_tiles buffer.
; Input: none
; Output: none
; Modifies: si, bx, al
restore_head_level_tiles_from_npcs proc near              
                mov     si, ds:npc_array_addr

next_npc__:   
                mov     bx, [si+NPC.n_x]
                cmp     bx, 0FFFFh
                jnz     short loc_6C5A
                retn
; ---------------------------------------------------------------------------

loc_6C5A:   
                mov     al, [si+NPC.n_head_tile]
                cmp     al, 0FDh
                je      short skip_head
                add     bx, bx
                add     bx, bx
                add     bx, bx          ; x*8
                add     bx, offset town_head_level_tiles
                mov     [bx], al        ; modify head tile

skip_head:  
                add     si, 8
                jmp     short next_npc__
restore_head_level_tiles_from_npcs endp


; =============== S U B R O U T I N E =======================================


render_life_almas_gold_place proc near  ; Render HUD labels: LIFE, ALMAS, GOLD, PLACE
                ; Draws the four Pascal-string labels for the status bar using
                ; Render_Pascal_String_0_proc at their predefined screen positions.
                ; Input: none (label positions embedded in string data)
                ; Output: four labels rendered on screen
                ; Modifies: si
                mov     si, offset life_str
                call    cs:Render_Pascal_String_0_proc
                mov     si, offset almas_str
                call    cs:Render_Pascal_String_0_proc
                mov     si, offset gold_str
                call    cs:Render_Pascal_String_0_proc
                mov     si, offset place_str
                call    cs:Render_Pascal_String_0_proc
                retn
render_life_almas_gold_place endp

; ---------------------------------------------------------------------------
life_str        dw 0A30Eh              
                db    0
aLife           db 4,'LIFE'
almas_str       dw 0BB1Eh              
                db    3
aAlmas          db 5,'ALMAS'
gold_str        dw 0BB0Dh              
                db    1
aGold           db 4,'GOLD'
place_str       dw 0AF0Dh              
                db    1
aPlace          db 5,'PLACE'

; =============== S U B R O U T I N E =======================================


; Handle hero walking off screen edge to adjacent town
; Checks if hero is at left edge (x=0) or right edge (x=28) of viewport.
; If so, looks up transition data from town_transition_table, waits for
; animation frames, then calls load_town_transition_data to load
; the new town and reinitialize.
; Input: ds:hero_x_in_viewport, ds:town_transition_table (transition data table)
; Output: may load new town and jump to town init
; Modifies: ax, si
handle_edge_screen_transition        proc near               

                mov     al, ds:hero_x_in_viewport
                inc     al
                jnz     short maybe_crossed_right
; crossed left edge
                call    restore_head_level_tiles_from_npcs
                mov     byte ptr ds:frame_timer, 40
                call    game_loop_with_frame_wait
                mov     si, ds:town_transition_table

loc_6CCB:   
                test    byte ptr [si], 1 ; town_transition_data[0] & 1 != 0 => data for crossing from left
                jnz     short loc_6CD5
                add     si, 4
                jmp     short loc_6CCB
; ---------------------------------------------------------------------------

loc_6CD5:   
                lodsb      ; town_transition_data[0] = flags
                mov     ah, al
                lodsb      ; town_transition_data[1] = dest_map_id
                and     ah, 0FEh
                jz      short town_transition_from_left
                ; some towns at the map edge transit to the dungeon
                jmp     dungeon_transition ; Input: al = dest_map_id
; ---------------------------------------------------------------------------

town_transition_from_left:   
                call    load_town_transition_data
                mov     byte ptr ds:hero_x_in_viewport, 26
                mov     ax, ds:mapWidth
                sub     ax, 36
                mov     ds:proximity_map_left_col_x, ax
                jmp     town_entry_internal
; ---------------------------------------------------------------------------

maybe_crossed_right:   
                cmp     al, 28
                jz      short crossed_right_edge
                retn
; ---------------------------------------------------------------------------
crossed_right_edge:   
                call    restore_head_level_tiles_from_npcs
                mov     byte ptr ds:frame_timer, 40
                call    game_loop_with_frame_wait
                mov     si, ds:town_transition_table

loc_6D09:   
                test    byte ptr [si], 1   ; town_transition_data[0] & 1 == 0 => data for crossing from right
                jz      short loc_6D13
                add     si, 4
                jmp     short loc_6D09
; ---------------------------------------------------------------------------

loc_6D13:   
                lodsb      ; town_transition_data[0] = flags
                mov     ah, al
                lodsb      ; town_transition_data[1] = dest_map_id
                and     ah, 0FEh
                jz      short town_transition_from_right
                ; some towns at the map edge transit to the dungeon
                jmp     dungeon_transition ; Input: al = dest_map_id
; ---------------------------------------------------------------------------

town_transition_from_right:   
                call    load_town_transition_data
                mov     byte ptr ds:hero_x_in_viewport, 0
                mov     word ptr ds:proximity_map_left_col_x, 0
                jmp     town_entry_internal
handle_edge_screen_transition        endp ; sp-analysis failed


; =============== S U B R O U T I N E =======================================

; Sets the new place_map_id, loads the new town's MDT data to fixed address 0xc000,
; NPC sprite group, applies sprite masks, and loads patterns if the pattern ID changed.
; Input: al = transition data byte (or'd with 80h for place_map_id),
;        ah - ignored
;        [si+1] = pattern group ID, [si+2] = transition flags
; Output: new town data loaded, patterns decompressed if needed
; Modifies: ax, si, di, es, ds
load_town_transition_data        proc near               ; Load transition data for town edge crossing
                or      al, 80h  ; high bit set for towns
                mov     byte ptr ds:place_map_id, al
                lodsw  ; town_transition_data[i].2
                push    ax
                mov     ah, byte ptr ds:place_map_id
                mov     al, 1 ; fn1_load_mdt_idx_ah
                call    cs:res_dispatcher_proc
                pop     ax  ; popped town_transition_data[i].2
                push    ax  ; pushed town_transition_data[i].2
                mov     cl, 11
                mul     cl
                mov     si, ax
                add     si, offset vfs_mman_grp
                mov     es, cs:seg1
                mov     di, mman_cman_gfx
                mov     al, 2    ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                push    ds
                mov     ds, cs:seg1
                mov     si, mman_cman_gfx + 100h
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax    ; seg2
                mov     di, 7000h
                mov     cx, 160
                call    cs:apply_sprite_mask_proc
                pop     ds
                pop     ax  ; popped town_transition_data[i].2
                cmp     ah, ds:pat_id
                jz      short locret_6D87
                mov     ds:pat_id, ah
                call    load_and_decompress_patterns

locret_6D87:
                retn
load_town_transition_data        endp

; ---------------------------------------------------------------------------
vfs_mman_grp    db 1                    ; town NPC sprite group descriptors
                db 1Eh
aMmanGrp        db 'MMAN.GRP',0
vfs_cman_grp    db 1
                db 1Fh
aCmanGrp        db 'CMAN.GRP',0

; =============== S U B R O U T I N E =======================================

; Load and decompress pattern tile group (town static tiles)
; Loads the pattern group file (CPAT/MPAT/DPAT) indexed by ds:pat_id
; via res_dispatcher_proc, adjusts segment offsets, then calls
; decompress_patterns_proc to unpack the tiles.
; Input: ds:pat_id (pattern group index 0-2)
; Output: patterns loaded and decompressed to seg1:8000h
; Modifies: ax, si, di, es
load_and_decompress_patterns proc near       
                mov     al, 11
                mul     ds:pat_id
                add     ax, offset pattern_grp_desc
                mov     si, ax
                mov     es, cs:seg1
                mov     di, tile_anim_count_table
                mov     al, 2           ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                add     word ptr es:[di], tile_anim_count_table
                add     word ptr es:[di+2], tile_anim_count_table
                add     word ptr es:[di+4], tile_anim_count_table
                jmp     cs:decompress_patterns_proc
load_and_decompress_patterns endp

; ---------------------------------------------------------------------------
pattern_grp_desc db 1
                db 22h
aCpatGrp        db 'CPAT.GRP',0
mpat_grp        db 1
                db 23h
aMpatGrp        db 'MPAT.GRP',0
dpat_grp        db 1
                db 24h
aDpatGrp        db 'DPAT.GRP',0

; =============== S U B R O U T I N E =======================================

; town NPC sprites
; Loads TMAN.GRP sprite group to seg1:6000h, then applies
; sprite mask from seg1:6000h to seg2:8000h for town rendering.
; Input: none (uses hardcoded tman_grp descriptor)
; Output: hero sprite loaded and masked to memory
; Modifies: ax, si, di, es, ds
load_hero_town_sprite   proc near               ; Load hero sprite for town mode
                mov     es, cs:seg1
                mov     si, offset tman_grp
                mov     di, tman_gfx
                mov     al, 2   ; fn2_segmented_load
                call    cs:res_dispatcher_proc
                push    ds
                mov     ds, cs:seg1
                mov     si, tman_gfx
                mov     ax, cs
                add     ax, 2000h
                mov     es, ax   ; seg2
                mov     di, 8000h
                mov     cx, 46
                call    cs:apply_sprite_mask_proc
                pop     ds
                retn
load_hero_town_sprite   endp

; ---------------------------------------------------------------------------
tman_grp        db 1                    ; hero town sprite descriptor
                db 20h
aTmanGrp        db 'TMAN.GRP',0
; ---------------------------------------------------------------------------

town_up_pressed:   
                or      byte ptr ds:hero_animation_phase, 1
                mov     ax, ds:proximity_map_left_col_x ; =00b3 (absolute x coord of proximity map left border)
                mov     bl, ds:hero_x_in_viewport ; =16h
                xor     bh, bh
                add     ax, bx          ; =00c9
                add     ax, 4           ; =00cd (viewport offset from proximity map left border)
                                        ; ax = absolute hero x coord
                mov     si, ds:doors_array_addr

check_next_door:       
                cmp     word ptr [si], 0FFFFh
                jnz     short loc_6E46
                retn
; ---------------------------------------------------------------------------

loc_6E46:   
                cmp     [si], ax
                jz      short door_x_coord_match
                inc     ax
                cmp     [si], ax
                jz      short door_x_coord_match
                dec     ax
                dec     ax
                cmp     [si], ax
                jz      short door_x_coord_match
                inc     ax
                add     si, 3
                jmp     short check_next_door
; ---------------------------------------------------------------------------

door_x_coord_match:    
                mov     byte ptr ds:hero_animation_phase, 4
                push    si
                    call    restore_head_level_tiles_from_npcs
                    mov     byte ptr ds:frame_timer, 40
                    call    game_loop_with_frame_wait
                pop     si              ; door struct pointer
                mov     al, [si+TOWN_DOOR.td_dest_id]
                cmp     al, 0FFh
                jne     short loc_6E77
                jmp     loc_6F77 ; Falter special building
; ---------------------------------------------------------------------------

loc_6E77:   
                sub     al, 8
                jb      short loc_6E7E  ; in-town buildings
                ; td_dest_id >=8 -> dungeon transition
                jmp     dungeon_transition ; Input: al = dest_map_id
; ---------------------------------------------------------------------------

loc_6E7E:   
                mov     byte ptr ds:byte_FF24, 4
                mov     bl, [si+TOWN_DOOR.td_dest_id]
                mov     al, 14
                mul     bl
                add     ax, offset vfs_kingpro_bin ; king palace, shops, inn etc
                mov     si, ax
                push    cs
                pop     es
                mov     di, town_indoors_bin_addr
                mov     al, 3 ; fn3_read_virtual_file ; load town indoor binary resource to dest buffer
                call    cs:res_dispatcher_proc 
                call    cs:fade_to_black_dithered_proc
                mov     ax, 1
                int     60h             ; adlib fn_1
                mov     ds:town_transition_flag, 0FFh
                call    cs:word_A000
loc_6EAF:
                call    cs:Clear_Viewport_proc
                mov     ds:town_transition_flag, 0
                call    cs:Clear_Place_Enemy_Bar_proc
                call    render_life_almas_gold_place
                mov     si, ds:town_name_rendering_info
                call    cs:Render_Pascal_String_1_proc
                call    load_patterns_and_call_background
                call    cs:backup_upper_town_3_tiles_proc ; skips top 8 tiles (sky, distant mountains)
                                        ; saves town top (3 tiles of 8) to screen buffer
                push    cs
                pop     es
                mov     al, 0FEh
                mov     di, 0E000h
                mov     cx, 0E0h
                rep stosb
                call    init_c015_obj_if_exists
                mov     byte ptr ds:frame_timer, 40
                call    game_loop_with_frame_wait
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     byte ptr byte ptr ds:altkey_latch, 0
                mov     byte ptr ds:hero_animation_phase, 1
                push    ds
                mov     ds, cs:seg1
                mov     si, 3000h
                xor     ax, ax
                int     60h             ; adlib fn_0
                pop     ds
                retn
; ---------------------------------------------------------------------------
vfs_kingpro_bin db    1
                db  0Bh
aKingproBin     db 'KINGPRO.BIN',0
princess_binary db    1
                db  0Ch
aOmoyproBin     db 'OMOYPRO.BIN',0
kenjpro_bin     db 1   
                db  12h
aKenjproBin     db 'KENJPRO.BIN',0
weaponry_binary db    1
                db  0Dh
aArmrproBin     db 'ARMRPRO.BIN',0
magicshop_binary db    1
                db  10h
aDrugproBin     db 'DRUGPRO.BIN',0
church_binary   db    1
                db  0Fh
aChurproBin     db 'CHURPRO.BIN',0
bank_binary     db    1
                db  0Eh
aBankproBin     db 'BANKPRO.BIN',0
inn_binary      db    1
                db  11h
aInnaproBin     db 'INNAPRO.BIN',0
; ---------------------------------------------------------------------------

loc_6F77:   
                mov     byte ptr ds:hero_animation_phase, 4 ; phase 4: face from viewer
                call    game_loop_with_frame_wait
                test    byte ptr ds:falter_items, 80h ; +128 - Travel back to Dorado Town using the building in the back.
                jnz     short loc_6F9D
                mov     ds:dialog_exit_flag, 0FFh
                mov     ax, 918h
                xor     bl, bl
                call    loc_63CA
                mov     ds:dialog_exit_flag, 0
                or      byte ptr ds:falter_items, 80h ; +128 - Travel back to Dorado Town using the building in the back.

loc_6F9D:   
                mov     byte ptr ds:byte_FF24, 4
                mov     ah, 86h ; Dorado place map id
                mov     byte ptr ds:place_map_id, ah
                mov     al, 1 ; fn1_load_mdt_idx_ah
                call    cs:res_dispatcher_proc ; res_dispatcher
                mov     si, offset vfs_mman_grp
                mov     es, cs:seg1
                mov     di, mman_cman_gfx
                mov     al, 2 ; fn2_segmented_load
                call    cs:res_dispatcher_proc ; res_dispatcher

loc_6FC1:   
                test    byte ptr ds:music_status_flag, 0FFh
                jz      short loc_6FC1
                mov     si, offset falter_transition_desc
                mov     es, cs:seg1
                mov     di, town_msd_music
                mov     al, 5 ; fn5_load_music
                call    cs:res_dispatcher_proc ; res_dispatcher
                mov     word ptr ds:proximity_map_left_col_x, 84h
                mov     byte ptr ds:hero_x_in_viewport, 0Dh
                call    cs:fade_to_black_dithered_proc
                jmp     town_entry_disabling_edge_scroll
; ---------------------------------------------------------------------------
falter_transition_desc dw 3201h                ; falter warp descriptor
aUgm2Msd               db 'UGM2.MSD',0
; ---------------------------------------------------------------------------
; Input:
;   AL: dest_map_id
dungeon_transition:   
                mov     bl, 5           ; ax=0
                mul     bl
                add     ax, ds:dungeon_entrance_table ; 0+C700=c700
                mov     si, ax
                lodsw                   ; 003d = 61 ; hero absolute x in the target map
                push    ax
                    lodsb                   ; 07 ; hero head y in the target map
                    sub     al, 10          ; -3 = fd
                    and     al, 3Fh         ; wrap y => 3d = 61
                    mov     byte ptr ds:viewport_top_row_y, al ; viewport y_top
                    lodsb                   ; 0
                    shr     al, 1           ; 0
                    sbb     al, al          ; 0
                    mov     byte ptr ds:is_left_run, al
                    lodsb                   ; 0
                    mov     byte ptr ds:place_map_id, al
                    mov     ah, al          ; 0 => mp10.mdt
                    mov     al, 1           ; fn1_load_mdt_idx_ah
                    call    cs:res_dispatcher_proc ; res_dispatcher
                pop     ax              ; hero absolute x in the target map
                add     ax, -16         ; proximity_map_left_col_x in absolute map coords
                jns     short loc_702B
                add     ax, ds:mapWidth

loc_702B:   
                mov     ds:proximity_map_left_col_x, ax ; =2d for Malicia entrance
                mov     byte ptr ds:entered_cavern_first_time, 0FFh
                call    cs:fade_to_black_dithered_proc ; fade_to_black_dithered
                mov     bx, prepare_dungeon_proc ; in fight.bin
                xor     al, al          ; fn0_swap_town_vs_cavern_gfx_drv_and_jmp_bx
                jmp     cs:res_dispatcher_proc ; res_dispatcher

; =============== S U B R O U T I N E =======================================
; npcAnimation — NPC animation / frame tick handler
;   Input: (none — reads NPC state from npc_array_addr)

npcAnimation    proc near
                push    si
                push    di
                call    cs:Confirm_Exit_Dialog_proc ; Confirm_Exit_Dialog
                call    cs:Handle_Pause_State_proc ; Handle_Pause_State
                call    cs:Handle_Restore_Game_proc ; Handle_Restore_Game
                jnb     short loc_7058
                call    restore_game

loc_7058:   
                pop     di
                pop     si
                test    ds:town_transition_flag, 0FFh
                jnz     short loc_7062
                retn
; ---------------------------------------------------------------------------

loc_7062:   
                push    si
                push    di
                call    cs:word_A002
                pop     di
                pop     si
                retn
npcAnimation    endp


; =============== S U B R O U T I N E =======================================
; render_menu_dialog — renders FF-terminated dialog text with scroll support
;   Reads text string from ds:dialog_string_ptr

render_menu_dialog proc near

                mov     si, ds:dialog_string_ptr
                call    measure_single_word
                mov     dl, ds:dialog_cursor_x
                xor     dh, dh
                add     dx, cx
                cmp     dx, 0D0h
                jb      short loc_7084
                call    advance_dialog_page

loc_7084:   
                mov     byte ptr ds:frame_timer, 0
; delay 6 frame ticks
loc_7089:   
                call    npcAnimation
                cmp     byte ptr ds:frame_timer, 6
                jb      short loc_7089
                mov     si, ds:dialog_string_ptr
                lodsb
                mov     ds:dialog_string_ptr, si
                cmp     al, 2Fh ; '/'
                jnz     short loc_70A3
                jmp     loc_7163
; ---------------------------------------------------------------------------

loc_70A3:   
                cmp     al, 0Dh
                jnz     short loc_70AA
                jmp     loc_7163
; ---------------------------------------------------------------------------

loc_70AA:   
                cmp     al, 0Ch
                jnz     short loc_70B1
                jmp     loc_7205
; ---------------------------------------------------------------------------

loc_70B1:   
                cmp     al, 0Fh
                jnz     short loc_70B8
                jmp     loc_71B0
; ---------------------------------------------------------------------------

loc_70B8:   
                cmp     al, 11h
                jnz     short loc_70BF
                jmp     loc_71B6
; ---------------------------------------------------------------------------

loc_70BF:   
                cmp     al, 13h
                jnz     short loc_70CA
                mov     ds:menu_highlight_toggle, 0FFh
                jmp     short loc_7084
; ---------------------------------------------------------------------------

loc_70CA:   
                cmp     al, 15h
                jnz     short loc_70D5
                mov     ds:menu_highlight_toggle, 0
                jmp     short loc_7084
; ---------------------------------------------------------------------------

loc_70D5:   
                cmp     al, 0FFh
                jnz     short loc_70DF
                lodsb ; return first byte after final FF
                mov     ds:dialog_string_ptr, si
                retn
; ---------------------------------------------------------------------------

loc_70DF:   
                or      al, al
                jnz     short loc_70E4
                retn
; ---------------------------------------------------------------------------

loc_70E4:   
                push    ax
                cmp     byte ptr ds:dialog_cursor_x, 0D0h
                jb      short loc_70EF
                call    advance_dialog_page

loc_70EF:   
                mov     bl, ds:dialog_cursor_x
                xor     bh, bh
                mov     cl, ds:dialog_scroll_counter
                mov     al, 0Ah
                mul     cl
                mov     cl, al
                pop     ax
                push    bx
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     dl, ds:char_x_offset[bx]
                mov     dh, bh
                pop     bx
                push    bx
                push    ax
                sub     bx, dx
                mov     ah, 1
                add     bx, 38h ; '8'
                add     cl, 63h ; 'c'
                call    cs:Render_Font_Glyph_proc
                pop     ax
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     cl, ds:char_width_table[bx]
                mov     ch, bh
                pop     bx
                add     bx, cx
                mov     ds:dialog_cursor_x, bl
                test    ds:menu_highlight_toggle, 0FFh
                jnz     short loc_7148
                cmp     al, 20h ; ' '
                jz      short loc_7148
                mov     byte ptr byte ptr ds:soundFX_request, 5
                jmp     loc_7084
; ---------------------------------------------------------------------------

loc_7148:   
                mov     si, ds:dialog_string_ptr
                call    measure_single_word
                mov     dl, ds:dialog_cursor_x
                xor     dh, dh
                add     dx, cx
                cmp     dx, 0D0h
                jb      short loc_7160
                call    advance_dialog_page

loc_7160:   
                jmp     loc_7084
; ---------------------------------------------------------------------------

loc_7163:   
                call    advance_dialog_page
                jmp     loc_7084
render_menu_dialog endp


; =============== S U B R O U T I N E =======================================


advance_dialog_page        proc near               ; Advance to next page of dialog text
                ; Increments dialog_page_count and dialog_scroll_counter, scrolls the dialog
                ; down, and draws a next-page arrow if more than 2 lines remain.
                ; Input: ds:dialog_page_count, ds:dialog_scroll_counter
                ; Output: dialog scrolled, arrow drawn if needed
                ; Modifies: ax, cx
                mov     byte ptr ds:dialog_cursor_x, 0
                inc     ds:dialog_page_count
                inc     byte ptr ds:dialog_scroll_counter
                cmp     ds:dialog_page_count, 4
                jb      short scroll_dialog_down
                call    count_remaining_dialog_lines
                push    cx
                call    scroll_dialog_down
                pop     cx
                cmp     cx, 2
                jb      short locret_718D
                call    draw_next_page_arrow

locret_718D:
                retn
advance_dialog_page        endp


; =============== S U B R O U T I N E =======================================


scroll_dialog_down        proc near               ; Scroll dialog box down by animated rows
                ; Scrolls the dialog region down by 10 rows using repeated
                ; Scroll_Screen_Rect_Down_proc calls with frame waits for animation.
                ; Input: ds:dialog_scroll_counter (scroll counter, max 5)
                ; Output: dialog screen scrolled down, dialog_scroll_counter decremented
                ; Modifies: bx, cx
                cmp     byte ptr ds:dialog_scroll_counter, 5
                jnb     short loc_7196
                retn
; ---------------------------------------------------------------------------

loc_7196:   
                dec     byte ptr ds:dialog_scroll_counter
                mov     cx, 0Ah

loc_719D:   
                push    cx
                call    npcAnimation
                mov     bx, 762h
                mov     cx, 1A32h
                call    cs:Scroll_Screen_Rect_Down_proc
                pop     cx
                loop    loc_719D
                retn
scroll_dialog_down        endp

; ---------------------------------------------------------------------------

loc_71B0:   
                call    draw_next_page_arrow
                jmp     loc_7084
; ---------------------------------------------------------------------------

loc_71B6:   
                call    wait_for_dialog_continue
                jmp     loc_7084

; =============== S U B R O U T I N E =======================================


draw_next_page_arrow        proc near               ; Draw continuation arrow and wait for input
                ; Renders a right-arrow glyph at the bottom of the dialog box,
                ; waits for user to press spacebar/alt, then clears the arrow area
                ; and resets dialog_page_count.
                ; Input: ds:dialog_rect_pos (dialog position)
                ; Output: arrow rendered and cleared, dialog_page_count reset to 0
                ; Modifies: ax, bx, cx
                mov     bx, 9Ch
                mov     cl, 8Bh
                mov     ax, 27Ch
                call    cs:Render_Font_Glyph_proc
                call    wait_for_dialog_continue
                mov     bx, 278Bh
                mov     cx, 20Ah
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                mov     ds:dialog_page_count, 0
                retn
draw_next_page_arrow        endp


; =============== S U B R O U T I N E =======================================


wait_for_dialog_continue        proc near               ; Wait for player to press spacebar or alt to continue
                ; Clears input latches, then polls in a loop with NPC animation
                ; until spacebar or alt is pressed. Plays sound effect on continue.
                ; Input: none (reads ds:spacebar_latch, ds:altkey_latch)
                ; Output: clears latches, sets ds:soundFX_request = 29
                ; Modifies: al
                mov     byte ptr byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0

loc_71E9:   
                call    npcAnimation
                mov     al, byte ptr ds:spacebar_latch
                or      al, byte ptr ds:altkey_latch
                jz      short loc_71E9
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                mov     byte ptr ds:soundFX_request, 29
                retn
wait_for_dialog_continue        endp

; ---------------------------------------------------------------------------

loc_7205:   
                mov     byte ptr ds:dialog_cursor_x, 0
                mov     byte ptr ds:dialog_scroll_counter, 0
                mov     ds:dialog_page_count, 0
                mov     bx, 0D60h
                mov     cx, 3637h
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                jmp     loc_7084

; =============== S U B R O U T I N E =======================================


measure_single_word        proc near               ; Measure pixel width of a single word
                ; Reads characters from [si] until space/null/terminator,
                ; sums character widths from char_width_table. Returns width
                ; in CX only for single-character words ending in '.' or ','.
                ; Input: si = pointer to text string
                ; Output: cx = total pixel width (0 for multi-char or non-punctuation words),
                ;        si advanced past the word
                ; Modifies: ax, cx, dx
                xor     cx, cx
                xor     dx, dx

loc_7228:   
                lodsb
                or      al, al
                jz      short loc_7255
                cmp     al, 0FFh
                jz      short loc_7255
                cmp     al, 20h ; ' '
                jz      short loc_7255
                cmp     al, 2Fh ; '/'
                jz      short loc_7255
                cmp     al, 0Dh
                jz      short loc_7255
                cmp     al, 0Ch
                jz      short loc_7255
                mov     ah, al
                sub     al, 20h ; ' '
                jb      short loc_7228
                inc     dx
                mov     bl, al
                xor     bh, bh
                add     cl, cs:char_width_table[bx]
                adc     ch, bh
                jmp     short loc_7228
; ---------------------------------------------------------------------------

loc_7255:   
                cmp     dx, 1
                jz      short loc_725B
                retn
; ---------------------------------------------------------------------------

loc_725B:   
                cmp     ah, 2Eh ; '.'
                jz      short loc_7266
                cmp     ah, 2Ch ; ','
                jz      short loc_7266
                retn
; ---------------------------------------------------------------------------

loc_7266:   
                xor     cx, cx
                retn
measure_single_word        endp


; =============== S U B R O U T I N E =======================================


count_remaining_dialog_lines        proc near               ; Count remaining line breaks in dialog text
                ; Scans the dialog string from ds:dialog_string_ptr counting '/' and 0x0D
                ; as line breaks, resetting on page boundaries (double 0xFF).
                ; Input: ds:dialog_string_ptr = pointer to dialog text
                ; Output: cx = number of remaining lines
                ; Modifies: si, dx
                mov     si, ds:dialog_string_ptr
                xor     cx, cx
                xor     dx, dx

loc_7271:   
                lodsb
                or      al, al
                jz      short loc_72C0
                cmp     al, 0FFh
                jnz     short loc_7281
                lodsb
                cmp     al, 0FFh
                jz      short loc_72C0
                jmp     short loc_7271
; ---------------------------------------------------------------------------

loc_7281:   
                cmp     al, 0Ch
                jz      short loc_72C0
                cmp     al, 2Fh ; '/'
                jnz     short loc_728E
                xor     dx, dx
                inc     cx
                jmp     short loc_7271
; ---------------------------------------------------------------------------

loc_728E:   
                cmp     al, 0Dh
                jnz     short loc_7297
                xor     dx, dx
                inc     cx
                jmp     short loc_7271
; ---------------------------------------------------------------------------

loc_7297:   
                mov     bl, al
                sub     bl, 20h ; ' '
                xor     bh, bh
                mov     bl, ds:char_width_table[bx]
                add     dx, bx
                cmp     al, 20h ; ' '
                jnz     short loc_7271
                push    cx
                push    si
                push    dx
                push    dx
                call    measure_single_word
                pop     dx
                add     dx, cx
                cmp     dx, 0D0h
                pop     dx
                pop     si
                pop     cx
                jb      short loc_7271
                xor     dx, dx
                inc     cx
                jmp     short loc_7271
; ---------------------------------------------------------------------------

loc_72C0:   
                or      dx, dx
                jnz     short loc_72C5
                retn
; ---------------------------------------------------------------------------

loc_72C5:   
                inc     cx
                retn
count_remaining_dialog_lines        endp


; =============== S U B R O U T I N E =======================================


convert_ax_to_decimal proc near         ; converts AX to 7-digit decimal string
;   Input: ax = 16-bit value
;   Output: 7 bytes at di, terminated with 0FFh
                push    ds
                pop     es
                push    di
                mov     bl, 0Fh
                mov     cx, 16960
                call    div_by_sub
                mov     bl, 1
                mov     cx, 34464
                call    div_by_sub
                xor     bl, bl
                mov     cx, 10000
                call    div_by_sub
                mov     cx, 1000
                call    div_mod
                mov     cx, 100
                call    div_mod
                mov     cx, 10
                call    div_mod
                stosb
                mov     al, 0FFh
                stosb
                pop     di
                mov     si, di
                mov     cx, 7

loc_72FE:   
                lodsb
                or      al, al
                jnz     short loc_7305
                loop    loc_72FE

loc_7305:   
                add     al, 30h ; '0'
                stosb
                jcxz    short loc_7313
                dec     cx
                jz      short loc_7313

loc_730D:   
                lodsb
                add     al, 30h ; '0'
                stosb
                loop    loc_730D

loc_7313:   
                mov     al, 0FFh
                stosb
                retn
convert_ax_to_decimal endp


; =============== S U B R O U T I N E =======================================


div_by_sub      proc near               ; Division by repeated subtraction
                ; Divides AX by CX using repeated subtraction of BL from DL and
                ; CX from AX. Stores quotient bytes to [di] and returns remainder in AX.
                ; Input: ax = dividend, bl = divisor for low byte, cx = divisor for high byte
                ; Output: [di] = quotient bytes, ax = remainder
                ; Modifies: ax, di, dh, dl
                xor     dh, dh

loc_7319:   
                sub     dl, bl
                jb      short loc_732D
                sub     ax, cx
                jnb     short loc_7327
                or      dl, dl
                jz      short loc_732B
                dec     dl

loc_7327:   
                inc     dh
                jmp     short loc_7319
; ---------------------------------------------------------------------------

loc_732B:   
                add     ax, cx

loc_732D:   
                add     dl, bl
                push    ax
                mov     al, dh
                stosb
                pop     ax
                retn
div_by_sub      endp


; =============== S U B R O U T I N E =======================================


div_mod         proc near               ; Divide AX by CX, store quotient and remainder
                ; Performs unsigned division of AX by CX. Stores the quotient
                ; byte to [di] and returns the remainder in AX.
                ; Input: ax = dividend, cx = divisor
                ; Output: [di] = quotient byte, ax = remainder
                ; Modifies: ax, di, dx
                xor     dh, dh
                div     cx
                xchg    ax, dx
                mov     dh, dl
                xor     dl, dl
                push    ax
                mov     al, dh
                stosb
                pop     ax
                retn
div_mod         endp


; =============== S U B R O U T I N E =======================================
; select_from_menu — handles menu selection with cursor navigation
;   Input: bl = initial cursor row
;   Returns: CF=clear if spacebar confirmed (bl=selected row), CF=set if alt cancelled

select_from_menu proc near
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                push    bx
                call    houseCursorShow
                pop     bx

loc_7353:   
                push    bx
                call    npcAnimation
                pop     bx
                mov     byte ptr ds:frame_timer, 0
                test    byte ptr ds:altkey_latch, 0FFh
                stc
                jz      short loc_7366
                retn
; ---------------------------------------------------------------------------

loc_7366:   
                test    byte ptr ds:spacebar_latch, 0FFh
                jz      short loc_7374
                clc
                mov     byte ptr ds:soundFX_request, 31
                retn
; ---------------------------------------------------------------------------

loc_7374:   
                mov     ax, offset loc_7353
                push    ax
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                and     al, 3
                cmp     al, 1
                jnz     short up_pressed
                or      bl, bl
                jz      short loc_738C
                push    bx
                call    houseCursorUp
                pop     bx
                dec     bl
                retn
; ---------------------------------------------------------------------------

loc_738C:   
                test    byte ptr ds:menu_cursor_pos, 0FFh
                jnz     short loc_7394
                retn
; ---------------------------------------------------------------------------

loc_7394:   
                push    di
                push    si
                push    bx
                dec     byte ptr ds:menu_cursor_pos
                mov     al, ds:menu_cursor_pos
                add     al, bl
                mov     bx, 0FF58h
                xlat
                call    cs:format_string_to_buffer_proc
                mov     cx, 0Ah

loc_73AC:   
                push    cx
                mov     bx, ds:menu_base_addr
                add     bx, 301h
                mov     al, cl
                dec     al
                mov     cl, ds:menu_item_count
                add     cl, cl
                mov     dl, cl
                add     cl, cl
                add     cl, cl
                add     cl, dl
                sub     cl, 2
                mov     ch, ds:string_width_bytes
                call    cs:scroll_hud_up_proc
; delay 4 frame ticks
loc_73D3:   
                call    npcAnimation
                cmp     byte ptr ds:frame_timer, 4
                jb      short loc_73D3
                mov     byte ptr ds:frame_timer, 0
                pop     cx
                loop    loc_73AC
                pop     bx
                pop     si
                pop     di
                retn
; ---------------------------------------------------------------------------

up_pressed: 
                cmp     al, 2
                jz      short loc_73EE
                retn
; ---------------------------------------------------------------------------

loc_73EE:   
                mov     al, ds:menu_item_count
                dec     al
                cmp     bl, al
                jnb     short loc_73FF
                push    bx
                call    houseCursorDown
                pop     bx
                inc     bl
                retn
; ---------------------------------------------------------------------------

loc_73FF:   
                mov     al, bl
                add     al, ds:menu_cursor_pos
                inc     al
                mov     ah, ds:menu_max_items
                dec     ah
                cmp     ah, al
                jnb     short loc_7412
                retn
; ---------------------------------------------------------------------------

loc_7412:   
                push    di
                push    si
                push    bx
                inc     byte ptr ds:menu_cursor_pos
                mov     al, ds:menu_cursor_pos
                add     al, bl
                mov     bx, 0FF58h
                xlat
                call    cs:format_string_to_buffer_proc
                mov     cx, 0Ah

loc_742A:   
                push    cx
                mov     bx, ds:menu_base_addr
                add     bx, 301h
                mov     al, cl
                neg     al
                add     al, 0Ah
                mov     cl, ds:menu_item_count
                add     cl, cl
                mov     dl, cl
                add     cl, cl
                add     cl, cl
                add     cl, dl
                sub     cl, 2
                mov     ch, ds:string_width_bytes
                call    cs:scroll_hud_down_proc
; delay 4 frame ticks
loc_7453:   
                call    npcAnimation
                cmp     byte ptr ds:frame_timer, 4
                jb      short loc_7453
                mov     byte ptr ds:frame_timer, 0
                pop     cx
                loop    loc_742A
                pop     bx
                pop     si
                pop     di
                retn
select_from_menu endp


; =============== S U B R O U T I N E =======================================


houseCursorShow proc near               ; draws menu cursor arrow
;   Input: bl = cursor row index
                mov     al, 0Ah         ; bx = bl*10+0x100+vFF54
                mul     bl
                add     ax, ds:menu_base_addr
                add     ax, 100h
                mov     bx, ax
                jmp     cs:draw_arrow_icon_or_ui_symbol_proc ; draw cursor
houseCursorShow endp


; =============== S U B R O U T I N E =======================================


houseCursorUp   proc near               ; animates cursor moving up one row
;   Input: bl = current cursor row index
                mov     al, 0Ah         ; bx=bl*10+0x100+vFF54
                mul     bl
                add     ax, ds:menu_base_addr
                add     ax, 100h
                mov     bx, ax
                mov     cx, 0Ah         ; Height

loc_748B:   
                push    cx
                mov     byte ptr ds:frame_timer, 0
                dec     bx
                push    bx
                call    cs:draw_arrow_icon_or_ui_symbol_proc
; delay 4 frame ticks
loc_7498:   
                call    npcAnimation
                cmp     byte ptr ds:frame_timer, 4 ; delay
                jb      short loc_7498
                pop     bx
                pop     cx
                loop    loc_748B
                retn
houseCursorUp   endp


; =============== S U B R O U T I N E =======================================


houseCursorDown proc near               ; animates cursor moving down one row
;   Input: bl = current cursor row index
                mov     al, 0Ah         ; bx=bl*10+0x100+vFF54
                mul     bl
                add     ax, ds:menu_base_addr
                add     ax, 100h
                mov     bx, ax
                mov     cx, 0Ah

loc_74B7:   
                push    cx
                mov     byte ptr ds:frame_timer, 0
                inc     bx
                push    bx
                call    cs:draw_arrow_icon_or_ui_symbol_proc
; delay 4 frame ticks
loc_74C4:   
                call    npcAnimation
                cmp     byte ptr ds:frame_timer, 4
                jb      short loc_74C4
                pop     bx
                pop     cx
                loop    loc_74B7
                retn
houseCursorDown endp


; =============== S U B R O U T I N E =======================================
; show_yes_no_dialog — displays Yes/No confirmation dialog
;   Returns: CF set if "Yes" selected, CF clear if "No"

show_yes_no_dialog proc near
                mov     al, ds:menu_item_count
                mov     ah, ds:menu_max_items
                push    ax
                mov     al, ds:menu_cursor_pos
                push    ax
                mov     byte ptr ds:menu_item_count, 2
                mov     byte ptr ds:menu_max_items, 2
                mov     cx, 2
                mov     si, offset aYes ; "Yes"
                call    render_menu_string_list
                mov     byte ptr ds:menu_cursor_pos, 0
                xor     bl, bl
                call    select_from_menu
                jnb     short loc_7500
                mov     bl, 1

loc_7500:   
                pop     ax
                mov     ds:menu_cursor_pos, al
                pop     ax
                mov     ds:menu_item_count, al
                mov     ds:menu_max_items, ah
                or      bl, bl
                jnz     short loc_7511
                retn
; ---------------------------------------------------------------------------

loc_7511:   
                stc
                retn
show_yes_no_dialog endp

; ---------------------------------------------------------------------------
aYes            db 'Yes',0             
aNo             db 'No',0

; =============== S U B R O U T I N E =======================================
; render_menu_string_list — renders an array of C-strings for menu display
;   Input: si = pointer to string array, cx = count, uses menu_base_addr as base addr

render_menu_string_list proc near
                xor     dl, dl

loc_751C:   
                push    cx
                push    dx
                mov     al, 0Ah
                mul     dl
                add     ax, ds:menu_base_addr
                add     ax, 301h
                mov     bx, ax
                xor     cl, cl
                call    cs:Render_C_String_proc
                pop     dx
                pop     cx
                inc     dl
                loop    loc_751C
                retn
render_menu_string_list endp


; =============== S U B R O U T I N E =======================================
; render_menu_list_scrolling — renders formatted menu strings from FF58 table
;   Input: cx = count, si = format index table, uses menu_base_addr as base addr

render_menu_list_scrolling proc near
                xor     ah, ah

loc_753B:   
                push    cx
                push    si
                push    di
                push    ax
                mov     bx, offset byte_FF58
                xlat
                call    cs:format_string_to_buffer_proc
                pop     ax
                push    ax
                mov     al, ah
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                add     ax, ax
                add     ax, ax
                add     bx, ax
                add     bx, ds:menu_base_addr
                add     bx, 300h
                call    cs:draw_string_buffer_to_screen_proc
                pop     ax
                inc     al
                inc     ah
                pop     di
                pop     si
                pop     cx
                loop    loc_753B
                retn
render_menu_list_scrolling endp ; sp-analysis failed


; =============== S U B R O U T I N E =======================================
; check_gold_sufficient — checks if hero_gold - (dl:ax) fits without underflow
;   Input: dl = high byte to subtract, ax = low word to subtract
;   Returns: CF=1 if not enough gold or borrow needed; dl = adjusted high byte

check_gold_sufficient proc near
                mov     bl, ds:hero_gold_hi
                sub     bl, dl
                jnb     short loc_7579
                retn
; ---------------------------------------------------------------------------

loc_7579:   
                mov     dl, bl
                mov     bx, ds:hero_gold_lo
                xchg    ax, bx
                sub     ax, bx
                jb      short loc_7585
                retn
; ---------------------------------------------------------------------------

loc_7585:   
                sub     dl, 1
                retn
check_gold_sufficient endp


; =============== S U B R O U T I N E =======================================
; add_gold_to_hero — adds gold to hero's inventory
;   Input: ax = low word to add, dl = high byte to add

add_gold_to_hero proc near
                add     word ptr ds:hero_gold_lo, ax
                adc     byte ptr ds:hero_gold_hi, dl
                retn
add_gold_to_hero endp


; =============== S U B R O U T I N E =======================================


restore_game    proc near               ; restores game from .usr save file
;   Input: (none — scans for save files, prompts user for selection)
                mov     cl, 0FFh
                mov     ax, 3
                int     60h             ; adlib: AX=3 stops a channel (CL=FF: mute)
                push    cs
                pop     es
                mov     si, offset vfs_stdply_bin
                mov     al, 6 ; fn6_get_virtual_file_size
                call    cs:res_dispatcher_proc ; res_dispatcher
                mov     byte ptr ds:menu_digits_render_flag, 0
                call    choose_game_to_restore
                push    cs
                pop     es
                test    cs:save_is_restart, 0FFh
                jz      short loc_75C6
                mov     di, save_name
                xor     al, al
                mov     cx, 8
                rep stosb
                mov     si, offset vfs_stdply_bin
                jmp     short loc_75F8
; ---------------------------------------------------------------------------

loc_75C6:   
                mov     si, offset save_name
                mov     di, offset save_name_buffer
                mov     cx, 8

loc_75CF:   
                lodsb
                or      al, al
                jz      short loc_75D7
                stosb
                loop    loc_75CF

loc_75D7:   
                mov     byte ptr es:[di], '.'
                mov     byte ptr es:[di+1], 'U'
                mov     byte ptr es:[di+2], 'S'
                mov     byte ptr es:[di+3], 'R'
                mov     byte ptr es:[di+4], 0
                mov     si, offset save_buffer_padding
                mov     byte ptr cs:disk_swap_suppressed, 0FFh

loc_75F8:   
                mov     di, savegame_area
                mov     al, 3 ; fn3_read_virtual_file ; load binary resource to dest buffer
                call    cs:res_dispatcher_proc ; fn0_buffer_swap_and_go
                                        ; fn1_load_mdt_idx_ah
            
                mov     byte ptr cs:disk_swap_suppressed, 0
                jb      short loc_762F
                mov     si, offset vfs_game_bin
                mov     di, game_bin_entry
                mov     al, 3 ; fn3_read_virtual_file ; load binary resource to dest buffer
                call    cs:res_dispatcher_proc ; fn0_buffer_swap_and_go
                                        ; fn1_load_mdt_idx_ah
            
                call    cs:Clear_Screen_proc
                mov     ax, 1
                int     60h             ; adlib fn_1
                xor     cl, cl
                mov     ax, 3
                int     60h             ; adlib: AX=3 stops a channel (CL=FF: mute)
                mov     ax, 0FFFFh
                jmp     ds:game_bin_entry_ptr
; ---------------------------------------------------------------------------

loc_762F:   
                mov     bx, 1A46h
                mov     cx, 1E1Ah
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                push    cs
                pop     ds
                mov     si, offset aUserFileNotFou ; "User File\rNot Found"
                mov     bx, 80h
                mov     cl, 4Ch ; 'L'
                call    cs:Render_String_FF_Terminated_proc
                mov     byte ptr cs:spacebar_latch, 0

loc_7651:   
                call    cs:Confirm_Exit_Dialog_proc
                test    byte ptr cs:spacebar_latch, 0FFh
                jz      short loc_7651
                mov     byte ptr cs:spacebar_latch, 0
                jmp     restore_game
restore_game    endp

; ---------------------------------------------------------------------------
aUserFileNotFou db 'User File', 0Dh, 'Not Found'
                db 0FFh
vfs_game_bin    db 0
                db    0
aGameBin        db 'GAME.BIN',0
game_bin_entry_ptr  dw game_bin_entry               ; entry point of loaded GAME.BIN
vfs_stdply_bin   db 0                    ; STDPLY.BIN load descriptor
                db    0
aStdplyBin      db 'STDPLY.BIN',0

; =============== S U B R O U T I N E =======================================


; Choose a saved game or restart, with name input
; Scans for .usr save files, displays a Re-Start option, allows
; the player to input a save name, and copies the name to the
; save slot area (save_name). Returns with carry set if a name was entered.
; Input: ds:viewport_buffer (determines whether to show save list)
; Output: save name copied to save_name, CF=1 if save slot has name
; Modifies: ax, bx, cx, si, di, es
choose_game_to_restore proc near        
                mov     ax, cs
                mov     es, ax
                mov     ds, ax
                mov     di, viewport_buffer
                mov     dx, offset aUsr ; "*.usr"
                call    cs:Scan_Saved_Games_proc ; Scan_Saved_Games
                mov     di, viewport_buffer
                inc     byte ptr [di]
                jnz     short loc_76AF
                dec     byte ptr [di]

loc_76AF:   
                std
                mov     si, 0E1FDh
                mov     di, 0E1FFh
                mov     cx, 0FFh
                rep movsw
                cld
                mov     ds:word_E001, offset aReStart ; "Re-Start"
                mov     bx, 0D38h
                mov     cx, 3637h
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                mov     bx, 0D38h
                mov     cx, 2637h
                mov     al, 0FFh
                call    cs:Draw_Bordered_Rectangle_proc
                push    cs
                pop     es
                mov     di, offset save_name_buffer
                mov     al, 60h ; '`'
                mov     cx, 8
                rep stosb
                mov     al, 0FFh
                stosb
                mov     ds:save_name_count, 0
                mov     si, save_name
                mov     di, offset save_name_buffer
                mov     cx, 8

loc_76F9:   
                lodsb
                or      al, al
                jz      short loc_7705
                inc     ds:save_name_count
                stosb
                loop    loc_76F9

loc_7705:   
                mov     al, ds:save_name_count
                mov     ds:save_slot_has_name, al
                push    cs
                pop     es
                mov     di, offset save_name_buffer
                mov     al, 60h ; '`'
                mov     cx, 8

loc_7715:   
                scasb
                jnz     short loc_7725
                loop    loc_7715
                mov     si, offset aReStart ; "Re-Start"
                mov     di, offset save_name_buffer
                mov     cx, 8
                rep movsb

loc_7725:   
                mov     bx, 3Ch ; '<'
                mov     cl, 44h ; 'D'
                mov     si, offset aInputName ; "Input name:"
                call    cs:Render_String_FF_Terminated_proc
                mov     ds:save_name_rect_pos, 60h ; '`'
                mov     ds:save_name_rect_y, 56h ; 'V'
                mov     ds:menu_base_addr, 343Bh
                mov     word ptr ds:string_width_bytes, 0Ah
                mov     al, byte ptr ds:viewport_buffer
                or      al, al
                jz      short loc_77A0
                cmp     al, 5
                jb      short loc_7756
                mov     al, 5

loc_7756:   
                xor     ah, ah
                mov     cx, ax
                xor     al, al
                mov     si, word_E001
                jcxz    short loc_7764
                call    render_save_game_list

loc_7764:   
                mov     si, word_E001
                mov     al, byte ptr ds:viewport_buffer
                mov     ds:menu_max_items, al
                mov     byte ptr ds:menu_item_count, 5
                call    save_name_input_handler
                push    cs
                pop     es
                mov     di, save_name
                mov     cx, 8
                xor     al, al
                rep stosb
                cmp     ds:save_slot_has_name, 0
                stc
                jnz     short loc_778A
                retn
; ---------------------------------------------------------------------------

loc_778A:   
                mov     si, offset save_name_buffer
                mov     di, save_name

loc_7790:   
                lodsb
                cmp     al, 0FFh
                clc
                jnz     short loc_7797
                retn
; ---------------------------------------------------------------------------

loc_7797:   
                cmp     al, 60h ; '`'
                clc
                jnz     short loc_779D
                retn
; ---------------------------------------------------------------------------

loc_779D:   
                stosb
                jmp     short loc_7790
; ---------------------------------------------------------------------------

loc_77A0:   
                mov     ax, 0FFFFh
                jmp     dword ptr cs:fn_exit_far_ptr
choose_game_to_restore endp

; ---------------------------------------------------------------------------
aUsr            db '*.usr',0           
aInputName      db 'Input name:'       
                db 0FFh
aReStart        db 'Re-Start',0        

; =============== S U B R O U T I N E =======================================


check_save_is_restart        proc near               ; Check if current save name is "Re-Start"
                ; Scans save_name_buffer for a '-' character; if found, sets
                ; save_is_restart flag and clears save_name_count.
                ; Input: save_name_buffer (8-byte buffer)
                ; Output: cs:save_is_restart = 0FFh if restart, cs:save_name_count = 0
                ; Modifies: di
                mov     cs:save_is_restart, 0
                push    cs
                pop     es
                mov     di, offset save_name_buffer
                mov     al, 2Dh ; '-'
                mov     cx, 8
                repne scasb
                jz      short loc_77D8
                retn
; ---------------------------------------------------------------------------

loc_77D8:   
                mov     cs:save_is_restart, 0FFh
                mov     cs:save_name_count, 0
                retn
check_save_is_restart        endp


; =============== S U B R O U T I N E =======================================


clear_save_name        proc near               ; Clear save name buffer if in restart mode
                ; If save_is_restart is set, clears the flag, fills save_name_buffer
                ; with 0x60 (placeholder char), and resets save_slot_has_name to 0.
                ; Input: cs:save_is_restart flag
                ; Output: save_name_buffer cleared, save_slot_has_name = 0
                ; Modifies: di
                test    cs:save_is_restart, 0FFh
                jnz     short loc_77EE
                retn
; ---------------------------------------------------------------------------

loc_77EE:   
                mov     cs:save_is_restart, 0
                push    cs
                pop     es
                mov     di, offset save_name_buffer
                mov     al, 60h ; '`'
                mov     cx, 8
                rep stosb
                mov     cs:save_slot_has_name, 0
                retn
clear_save_name        endp


; =============== S U B R O U T I N E =======================================


render_save_game_list        proc near               ; Render list of saved game slots
                ; Iterates CX save slots, formats each entry via format_string_to_buffer_proc,
                ; and draws each string to screen at computed positions.
                ; Input: cx = number of slots, si = source data, ax = starting index,
                ;        ds:menu_base_addr = base Y position
                ; Output: save game list rendered on screen
                ; Modifies: ax, bx
                xor     ah, ah

loc_7809:   
                push    cx
                push    si
                push    ax
                call    cs:format_string_to_buffer_proc
                pop     ax
                push    ax
                mov     al, ah
                xor     ah, ah
                add     ax, ax
                mov     bx, ax
                add     ax, ax
                add     ax, ax
                add     bx, ax
                add     bx, ds:menu_base_addr
                add     bx, 300h
                call    cs:draw_string_buffer_to_screen_proc
                pop     ax
                inc     al
                inc     ah
                pop     si
                pop     cx
                loop    loc_7809
                retn
render_save_game_list        endp ; sp-analysis failed


; =============== S U B R O U T I N E =======================================


save_name_input_handler        proc near               ; Handle save name keyboard input
                ; Main loop for save name entry: processes keyboard input (Enter, Backspace,
                ; ASCII chars), updates save name buffer, redraws the name and cursor.
                ; Input: ds:save_name_buffer, ds:save_name_rect_pos, ds:save_name_rect_y
                ; Output: save name buffer updated, exits on Enter or all-buffer-empty check
                ; Modifies: ax, bx, cx, si, di
                call    check_save_is_restart
                mov     byte ptr ds:keyboard_alt_mode_flag, 0FFh
                mov     byte ptr ds:Current_ASCII_Char, 0
                mov     byte ptr ds:spacebar_latch, 0
                mov     byte ptr ds:altkey_latch, 0
                mov     byte ptr ds:menu_cursor_pos, 0
                mov     ds:save_cursor_row, 0
                xor     bl, bl
                test    byte ptr ds:menu_max_items, 0FFh
                jz      short loc_7867
                call    cs:cursor_exports

loc_7867:   
                call    render_save_name_string
                xor     al, al
                call    highlight_save_cursor

loc_786F:   
                mov     byte ptr ds:frame_timer, 0
                test    word ptr cs:F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter, 1
                jz      short loc_78BF
                push    cs
                pop     es
                mov     di, offset save_name_buffer
                mov     al, 60h ; '`'
                mov     cx, 8

loc_7887:   
                scasb
                jnz     short loc_78AF
                loop    loc_7887
                push    si
                mov     si, offset aReStart ; "Re-Start"
                mov     di, offset save_name_buffer
                mov     cx, 8
                rep movsb
                pop     si
                call    check_save_is_restart
                call    render_save_name_string
                mov     byte ptr ds:soundFX_request, 1

loc_78A4:   
                test    word ptr cs:F9_F7_F2_F1_KREJSNYQ_Esc_Ctrl_Shift_Enter, 1
                jnz     short loc_78A4
                jmp     short loc_786F
; ---------------------------------------------------------------------------

loc_78AF:   
                mov     byte ptr ds:soundFX_request, 31
                mov     byte ptr ds:keyboard_alt_mode_flag, 0
                mov     byte ptr ds:altkey_latch, 0
                retn
; ---------------------------------------------------------------------------

loc_78BF:   
                test    byte ptr ds:spacebar_latch, 0FFh
                jz      short loc_7931
                mov     byte ptr ds:soundFX_request, 1
                push    si
                xor     bh, bh
                mov     bl, ds:menu_cursor_pos
                add     bl, ds:save_cursor_row
                add     bx, bx
                mov     si, [bx+si]
                push    cs
                pop     es
                mov     di, offset save_name_buffer
                mov     al, 60h ; '`'
                mov     cx, 8
                rep stosb
                mov     al, 0FFh
                stosb
                mov     ds:save_name_count, 0
                mov     di, offset save_name_buffer
                mov     cx, 8

loc_78F4:   
                lodsb
                or      al, al
                jz      short loc_7900
                inc     ds:save_name_count
                stosb
                loop    loc_78F4

loc_7900:   
                mov     al, ds:save_name_count
                mov     ds:save_slot_has_name, al
                pop     si
                call    check_save_is_restart
                mov     byte ptr ds:spacebar_latch, 0
                mov     ax, ds:save_name_rect_pos
                shr     ax, 1
                shr     ax, 1
                mov     bh, al
                mov     bl, ds:save_name_rect_y
                mov     cx, 1010h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                call    render_save_name_string
                xor     al, al
                call    highlight_save_cursor
                jmp     loc_786F
; ---------------------------------------------------------------------------

loc_7931:   
                mov     cx, offset loc_786F
                push    cx
                test    byte ptr ds:Current_ASCII_Char, 0FFh
                jz      short loc_797C
                mov     byte ptr ds:soundFX_request, 1
                mov     al, ds:Current_ASCII_Char
                mov     byte ptr ds:Current_ASCII_Char, 0
                cmp     al, 0Dh
                jnz     short loc_794E
                retn
; ---------------------------------------------------------------------------

loc_794E:   
                cmp     al, 8
                jnz     short loc_7955
                jmp     loc_7B44
; ---------------------------------------------------------------------------

loc_7955:   
                push    ax
                call    clear_save_name
                pop     ax
                xor     bx, bx
                mov     bl, ds:save_name_count
                cmp     ds:save_name_buffer[bx], 60h ; '`'
                jnz     short loc_796B
                inc     ds:save_slot_has_name

loc_796B:   
                mov     ds:save_name_buffer[bx], al
                call    render_save_name_string
                mov     byte ptr ds:soundFX_request, 1
                mov     al, 1
                jmp     highlight_save_cursor
; ---------------------------------------------------------------------------

loc_797C:   
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 8
                jz      short loc_7998
                mov     byte ptr ds:soundFX_request, 1
                mov     al, 1
                call    highlight_save_cursor

loc_798C:   
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 8
                jnz     short loc_798C
                mov     byte ptr ds:Current_ASCII_Char, 0
                retn
; ---------------------------------------------------------------------------

loc_7998:   
                test    al, 4
                jz      short loc_79B2
                mov     byte ptr ds:soundFX_request, 1
                mov     al, 0FFh
                call    highlight_save_cursor

loc_79A6:   
                int     61h             ; ah: ____Alt_Space
                                        ; al: ____right_left_down_up
                test    al, 4
                jnz     short loc_79A6
                mov     byte ptr ds:Current_ASCII_Char, 0
                retn
; ---------------------------------------------------------------------------

loc_79B2:   
                test    byte ptr ds:menu_max_items, 0FFh
                jnz     short loc_79BA
                retn
; ---------------------------------------------------------------------------

loc_79BA:   
                and     al, 3
                cmp     al, 1
                jnz     short loc_7A2B
                test    ds:save_cursor_row, 0FFh
                jz      short loc_79D5
                mov     bl, ds:save_cursor_row
                call    cs:cursor_up_export
                dec     ds:save_cursor_row
                retn
; ---------------------------------------------------------------------------

loc_79D5:   
                test    byte ptr ds:menu_cursor_pos, 0FFh
                jnz     short loc_79DD
                retn
; ---------------------------------------------------------------------------

loc_79DD:   
                push    di
                push    si
                dec     byte ptr ds:menu_cursor_pos
                mov     al, ds:menu_cursor_pos
                add     al, ds:save_cursor_row
                call    cs:format_string_to_buffer_proc
                mov     cx, 0Ah

loc_79F2:   
                push    cx
                mov     bx, ds:menu_base_addr
                add     bx, 301h
                mov     al, cl
                dec     al
                mov     cl, ds:menu_item_count
                add     cl, cl
                mov     dl, cl
                add     cl, cl
                add     cl, cl
                add     cl, dl
                sub     cl, 2
                mov     ch, ds:string_width_bytes
                call    cs:scroll_hud_up_proc
; delay 4 frame ticks
loc_7A19:   
                cmp     byte ptr ds:frame_timer, 4
                jb      short loc_7A19
                mov     byte ptr ds:frame_timer, 0
                pop     cx
                loop    loc_79F2
                pop     si
                pop     di
                retn
; ---------------------------------------------------------------------------

loc_7A2B:   
                cmp     al, 2
                jz      short loc_7A30
                retn
; ---------------------------------------------------------------------------

loc_7A30:   
                mov     al, ds:save_cursor_row
                add     al, ds:menu_cursor_pos
                inc     al
                mov     ah, ds:menu_max_items
                dec     ah
                cmp     ah, al
                jnb     short loc_7A44
                retn
; ---------------------------------------------------------------------------

loc_7A44:   
                mov     al, ds:menu_item_count
                dec     al
                cmp     ds:save_cursor_row, al
                jnb     short loc_7A5D
                mov     bl, ds:save_cursor_row
                call    cs:cursor_down_export
                inc     ds:save_cursor_row
                retn
; ---------------------------------------------------------------------------

loc_7A5D:   
                push    di
                push    si
                inc     byte ptr ds:menu_cursor_pos
                mov     al, ds:menu_cursor_pos
                add     al, ds:save_cursor_row
                call    cs:format_string_to_buffer_proc
                mov     cx, 0Ah

loc_7A72:   
                push    cx
                mov     bx, ds:menu_base_addr
                add     bx, 301h
                mov     al, cl
                neg     al
                add     al, 0Ah
                mov     cl, ds:menu_item_count
                add     cl, cl
                mov     dl, cl
                add     cl, cl
                add     cl, cl
                add     cl, dl
                sub     cl, 2
                mov     ch, ds:string_width_bytes
                call    cs:scroll_hud_down_proc
; delay 4 frame ticks
loc_7A9B:   
                cmp     byte ptr ds:frame_timer, 4
                jb      short loc_7A9B
                mov     byte ptr ds:frame_timer, 0
                pop     cx
                loop    loc_7A72
                pop     si
                pop     di
                retn
save_name_input_handler        endp ; sp-analysis failed


; =============== S U B R O U T I N E =======================================


highlight_save_cursor        proc near               ; Draw cursor highlight and arrow at current save name position
                ; Clears the previous cursor highlight, updates save_name_count
                ; based on parameter al, clamps to valid range, and renders
                ; the cursor arrow glyph (0x67F) at the current character position.
                ; Input: al = delta to add to save_name_count (signed via overflow check)
                ;        ds:save_name_rect_pos, ds:save_name_rect_y, ds:save_slot_has_name
                ; Output: cursor arrow rendered, save_name_count updated and clamped
                ; Modifies: ax, bx, cx
                push    si
                push    ax
                mov     ax, ds:save_name_rect_pos
                shr     ax, 1
                shr     ax, 1
                mov     bh, al
                mov     al, ds:save_name_count
                add     al, al
                add     bh, al
                mov     bl, ds:save_name_rect_y
                add     bl, 8
                mov     cx, 208h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                pop     ax
                add     ds:save_name_count, al
                test    ds:save_name_count, 80h
                jz      short loc_7AE1
                mov     ds:save_name_count, 0

loc_7AE1:   
                cmp     ds:save_name_count, 8
                jb      short loc_7AEC
                dec     ds:save_name_count

loc_7AEC:   
                mov     al, ds:save_slot_has_name
                cmp     ds:save_name_count, al
                jb      short loc_7AF8
                mov     ds:save_name_count, al

loc_7AF8:   
                mov     bx, ds:save_name_rect_pos
                mov     cl, ds:save_name_rect_y
                xor     ax, ax
                mov     al, ds:save_name_count
                add     ax, ax
                add     ax, ax
                add     ax, ax
                add     bx, ax
                add     cl, 8
                mov     ax, 67Fh
                call    cs:Render_Font_Glyph_proc
                pop     si
                retn
highlight_save_cursor        endp


; =============== S U B R O U T I N E =======================================


render_save_name_string        proc near               ; Render the current save name string
                ; Clears the save name area with a bordered rectangle, then
                ; renders the save name string from save_name_buffer at the dialog position.
                ; Input: ds:save_name_rect_pos, ds:save_name_rect_y
                ; Output: save name rendered in bordered rectangle on screen
                ; Modifies: ax, bx, cx
                push    si
                mov     ax, ds:save_name_rect_pos
                shr     ax, 1
                shr     ax, 1
                mov     bh, al
                mov     bl, ds:save_name_rect_y
                mov     cx, 1008h
                xor     al, al
                call    cs:Draw_Bordered_Rectangle_proc
                mov     bx, ds:save_name_rect_pos
                mov     cl, ds:save_name_rect_y
                mov     si, offset save_name_buffer
                call    cs:Render_String_FF_Terminated_proc
                pop     si
                retn
render_save_name_string        endp

; ---------------------------------------------------------------------------

loc_7B44:   
                call    clear_save_name
                push    si
                mov     bl, ds:save_name_count
                or      bl, bl
                jnz     short loc_7B52
                inc     bl

loc_7B52:   
                xor     bh, bh
                push    cs
                pop     es
                mov     si, offset save_name_buffer
                add     si, bx
                mov     di, si
                dec     di
                mov     al, 8
                sub     al, bl
                mov     cl, al
                xor     ch, ch
                rep movsb
                test    ds:save_slot_has_name, 0FFh
                jz      short loc_7B73
                dec     ds:save_slot_has_name

loc_7B73:   
                mov     ds:save_name_terminator, 60h ; '`'
                mov     al, 0FFh
                call    highlight_save_cursor
                call    render_save_name_string
                pop     si
                retn
; ---------------------------------------------------------------------------
; 7B82
char_x_offset   db 0, 2, 2, 3, 1, 0     ; per-char x offset adjustment before render
                db 0, 2, 2, 3, 1, 1
                db 1, 2, 2, 0, 1, 2
                db 1, 1, 1, 1, 1, 1
                db 1, 1, 3, 2, 1, 1
                db 2, 1, 0, 0, 0, 0
                db 0, 0, 0, 0, 0, 2
                db 0, 0, 0, 0, 0, 0
                db 0, 0, 0, 0, 1, 0
                db 0, 0, 0, 0, 1, 2
                db 2, 2, 1, 1, 1, 0
                db 0, 1, 0, 1, 1, 0
                db 0, 2, 1, 0, 2, 0
                db 1, 1, 0, 0, 0, 1
                db 1, 0, 0, 0, 1, 1
                db 1, 2, 0, 3, 1, 0
; 7BE2
char_width_table  db 5, 4, 4, 4, 6, 8     ; per-char pixel width after render
                db 5, 3, 4, 4, 6, 6
                db 6, 5, 6, 8, 7, 5
                db 7, 7, 7, 7, 7, 7
                db 7, 7, 3, 4, 6, 6
                db 6, 7, 8, 8, 8, 8
                db 8, 8, 8, 8, 8, 5
                db 8, 8, 8, 8, 8, 8
                db 8, 8, 8, 8, 7, 8
                db 8, 8, 8, 8, 7, 5
                db 3, 5, 6, 7, 7, 8
                db 8, 7, 8, 7, 7, 8
                db 8, 5, 6, 8, 5, 8
                db 7, 7, 8, 8, 8, 7
                db 6, 8, 8, 8, 7, 7
                db 7, 4, 8, 4, 7, 8
town_transition_flag db 0           ; 7C42
disable_edge_scroll  db 0           ; 7C43
edge_scroll_enabled  db 0           ; 7C44
town_has_middle_layer db 0          ; 7C45
pat_id               db 0           ; 7C46
edge_scroll_handler  dw 0           ; 7C47
hero_x               dw 0           ; 7C49
hero_moved_flag      db 0           ; 7C4B
dialog_rect_pos      dw 0           ; 7C4C
dialog_cursor_pos    dw 0           ; 7C4E
dialog_src_rect      dw 0           ; 7C50
dialog_page_count    db 0           ; 7C52
dialog_char_x        db 0           ; 7C53
dialog_char_y        db 0           ; 7C54
dialog_line_start_x  db 0           ; 7C55
dialog_chars_on_line db 0           ; 7C56
dialog_lines_rendered db 0          ; 7C57
dialog_text_ptr       dw 0          ; 7C58
dialog_rect_end       dw 0          ; 7C5A
dialog_exit_flag      db 0          ; 7C5C
menu_highlight_toggle db 0          ; 7C5D
save_name_count       db 0          ; 7C5E
save_slot_has_name    db 0          ; 7C5F
save_name_rect_pos    dw 0          ; 7C60
save_name_rect_y      db 0          ; 7C62
save_cursor_row       db 0          ; 7C63
save_is_restart       db 0          ; 7C64
save_buffer_padding   db 0          ; 7C65
                      db    0
save_name_buffer      db 0          ; 7C67
                db    0
                db    0
                db    0
                db    0
                db    0
                db    0
save_name_terminator       db 0     ; 7C6E
                db    0
                db    0
                db    0
                db    0
                db    0
hero_2x3_tile_buf dw 0              ; 7C74; 2 columns × 3 rows hero tile buffer
                db 0
                dw 0
                db 0
hero_1x3_tile_buf db 0              ; 7C7A
                db 0
                db 0

town            ends

                end    start
