; Deals damage to the hero if standing on harmful tiles.
; Pirika shoes grant immunity.
; Scans the hero's bottom 2-3 rows (squatting: +1 row) by calling
; is_tile_safe_to_stay on each tile.
; Also checks the tile directly under the hero centre.
; If any match: set hero_damage_this_frame, play SFX 9, deal damage.
; Damage table aggressive_tiles_damage_table: per cavern_level (1,1,4,8,20,20,20,20,20).
step_on_aggressive_ground proc near
                cmp     byte ptr ds:current_accessory, SHOES_PIRIKA
                jnz     short no_pirika_shoes ; hero feets get hurting
                retn

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
