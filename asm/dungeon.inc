monster            STRUC
  currX            dw   ?  ; 0
  currY            db   ?  ; 2 ; Y always 0..63, no need to call it "relative"
  m_x_rel          db   ?  ; 3 ; X relative to proximity left (0..35)
  flags            db   ?  ; 4
  ai_flags         db   ?  ; 5
  anim_counter     db   ?  ; 6
  state_flags      db   ?  ; 7
  hp               db   ?  ; 8
  ai_state         db   ?  ; 9
  ai_timer         db   ?  ; 10
  spwnX            dw   ?  ; 11
  spwnY            db   ?  ; 13
  type_            db   ?  ; 14
  counter          db   ?  ; 15
monster            ENDS

boss_state         STRUC
  bs_x                dw   ?   ; +0
  bs_y                db   ?   ; +2
  bs_hp               dw   ?   ; +3
  bs_xp_reward        dw   ?   ; +5
  bs_arena_center_x   db   ?   ; +7
  bs_unk_8            db   ?   ; +8
  bs_name_block_ptr   dw   ?   ; +9
  bs_almas_reward     db   ?   ; +11
boss_state         ENDS

door               STRUC
  x0                      dw   ? ; 0 ; Door X position on current map
  y0                      db   ? ; 2 ; Door Y position on current map
  d_flags                 db   ? ; 3 ; bit 7: open, bit 6: exit face left, bits 2-0: tile type
  d_place_map_id          db   ? ; 4 ; Destination map ID
  x1                      dw   ? ; 5 ; X after transition
  y1                      db   ? ; 7 ; Y after transition; 0FFh means "door to town"
  d_features              db   ? ; 8 ; bit 0=Lion Key needed, bit 7=town transition animation flag
  d_save_achievement_addr dw   ? ; 9 ; (if not ffff) savegame address of achievement 
  d_achievement_flag      db   ? ; 11 ; mask of achievement to save at address above
door               ENDS

; collapsing and vertical platforms share the same struct
vert_platform      STRUC
  x                dw   ?
  y                db   ?
vert_platform      ENDS

horiz_platform     STRUC
  x_and_flags      dw   ? ; 0 ; high byte bits 6-7 = speed (0: skip, 1: normal, 2,3: fast)
  y_and_flags      db   ? ; 2 ; bit 7: direction (1=left), bit 6: pause
  min_x            dw   ? ; 3 ;
  max_x            dw   ? ; 5 ;
horiz_platform     ENDS

; enemy projectile
projectile         STRUC
  p_x_rel                 db   ? ; 0
  p_y_rel                 db   ? ; 1
  p_base_tile_idx         db   ? ; 2 ; bits 7,6 select a mask to AND with [si+3] (a screen dirty mask byte) and then added to the base (bits 5..0), forming a quarter-tile decomposition index
  p_trajectory_step_count db   ? ; 3
  p_max_step_count        db   ? ; 4
  p_trajectory_dir        db   ? ; 5 ; bits 2..0: direction 0..7
  p_damage                db   ? ; 6
  p_vram_addr_d           dw   ? ; 7 ; bit 15: dirty flag, bit 14..0: VRAM address
  p_curved_path_data_ptr  dw   ? ; 9 ; Pointer to curved path data table
  p_cached_x_rel          db   ? ; 11
  p_cached_y_rel          db   ? ; 12
projectile         ENDS

; hero magic projectile
magic_projectile   STRUC
  mp_x_rel                  dw   ?
  mp_y_rel                  db   ?
  mp_dir                    db   ? ; bit 7: return/deactivate flag, bit 1,0: direction
  mp_life_timer             db   ?
  mp_anim_frame             db   ?
  mp_cached_x_offset_tiles  db   ?
  mp_cached_y_offset        db   ?
  mp_vram_addr_tile00       dw   ?
  mp_vram_addr_tile10       dw   ?
  mp_vram_addr_tile01       dw   ?
  mp_vram_addr_tile11       dw   ?
magic_projectile   ENDS

spirit             STRUC
  s_orbit_phase    db   ? ; FF: inactive; bits 3..0: orbit phase
  s_orbit_speed    db   ?
  s_active_shots   db   ?
  s_vram_addr      dw   ? ; bit 15: dirty flag, bit 14..0: VRAM address
  s_screen_x       db   ?
  s_screen_y       db   ?
spirit             ENDS

; Following group of definitions share the same space as gtmcga.bin, 
; so they are in separate include files

; gfmcga.bin (driver for dungeons)
Refresh_Dirty_Tiles_proc                           equ 3000h
Sample_Neighborhood_Attributes_proc                equ 3002h
Flush_Ui_Element_If_Dirty_proc                     equ 3004h
Render_Sword_Overlay_proc                          equ 3006h
Uncompress_And_Render_Tile_proc                    equ 3008h
Viewport_Coords_To_Screen_Addr_proc                equ 300Ah
Sword_Overlay_EntryPoint_proc                      equ 300Ch
Dungeon_Static_Tile_Cached_Drawer_proc             equ 300Eh
Boss_Explosions_Renderer_proc                      equ 3010h
Render_Viewport_Tiles_proc                         equ 3012h
Copy_Tile_Buffer_To_VRAM_proc                      equ 3014h
Update_Local_Attribute_Cache_proc                  equ 3016h
Render_Viewport_Border_Walls_proc                  equ 3018h

; Input: none (uses global current_magic_spell)
; Reads corresponding sprite group fron seg2:0 buffer to seg1:9350h
; Output: Loads sprite sheet for current_magic_spell
; DS:SI -> seg1:9350h buffer
Load_Magic_Spell_Sprite_Group_proc                 equ 301Ah

Render_Animated_Tile_Strip_proc                    equ 301Ch
Render_Roca_Tilemap_proc                           equ 301Eh
Calculate_Tile_VRAM_Address_proc                   equ 3020h
Render_16x16_Sprite_proc                           equ 3022h
Render_Status_Indicator_proc                       equ 3024h
Render_Entity_Sprite_proc                          equ 3026h
Decompress_Tile_Data_proc                          equ 3028h
NoOperation_proc                                   equ 302Ah

monster_ai_move_left_frames                        equ 0A030h
monster_ai_death_left_frames                       equ 0A040h
monster_ai_item_animation_left_frames              equ 0A050h
monster_ai_potions_left_frames                     equ 0A060h
monster_ai_move_right_frames                       equ 0A070h
monster_ai_death_right_frames                      equ 0A080h
monster_ai_item_animation_right_frames             equ 0A090h
monster_ai_potions_right_frames                    equ 0A0A0h

; mdt info - dungeons
mdt_descriptor_addr                                equ 0C000h
map_width                                          equ 0C002h
vertical_platforms_table_addr                      equ 0C004h
collapsing_platforms_table_addr                    equ 0C006h
horiz_platforms_table_addr                         equ 0C008h
doors_table_addr                                   equ 0C00Ah
accomplished_items_checker_table                   equ 0C00Ch
cavern_name_rendering_info                         equ 0C00Eh
monsters_table_addr                                equ 0C010h
cavern_level                                       equ 0C012h
tear_x                                             equ 0C013h ; word
  ; put it to hero_x_in_proximity_map and call edge_locking_scrolling_window to place hero near sage hut
tear_y                                             equ 0C015h
hero_head_y_in_viewport_initial_from_mdt           equ 0C016h
cavern_signs_rendering_info                        equ 0C017h
packed_map_end_ptr                                 equ 0C019h ; word
packed_map_start                                   equ 0C01Bh

; seg1 offsets (code seg + 1000h)
monster_gfx                                        equ 4000h
fman_gfx                                           equ 6000h ; hero in dungeon
; packed tiles data (48 bytes each)
mpp_gfx                                            equ 8000h ; static tiles, 8000h..802Fh are headers, so tile 0 is skipped
mpp_gfx_tile_1                                     equ 8030h
dchr_gfx                                           equ 8C00h ; doors, platforms, etc. Tiles 40h..66h
aggressive_ground_list                             equ 8020h
monsters_transparency_masks                        equ 0A000h
sword_animation_gfx                                equ 0B000h
sword_reachability_lists                           equ 0B002h

; seg2 offsets (code seg + 2000h)
magic_grp_sprites                                  equ 0
sword_grp_sprites                                  equ 1800h
