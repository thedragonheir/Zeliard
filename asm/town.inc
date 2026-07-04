NPC STRUC
  n_x           dw   ? ; 0
  n_facing      db   ? ; 2
  n_head_tile   db   ? ; 3
  n_anim_phase  db   ? ; 4
  n_ai_type     db   ? ; 5
  n_flags       db   ? ; 6
  n_id          db   ? ; 7
NPC ENDS

TOWN_DOOR STRUC
  td_x          dw   ? ; 0
  td_dest_id    db   ? ; 2; 0=king, 1=princess, 2=sage, 3=weapon, 4=magic, 5=church, 6=bank, 7=inn, 8=cavern; ff=terminator
TOWN_DOOR ENDS

DUNGEON_ENTRANCE STRUC
  de_target_x   dw   ? ; 0 ; hero absolute x in the target map
  de_target_y   db   ? ; 2 ; hero head y in the target map
  de_is_roka_left db   ? ; 3 ; bit 0: 0=right, 1=left (direction of run in rokademo)
  de_map_id     db   ? ; 4 ; 0 = cavern Malicia, ...

DUNGEON_ENTRANCE ENDS
; Following group of definitions share the same space as gfmcga.bin, 
; so they are in separate include files

; gtmcga.bin (driver for towns)
gtmcga_drv_addr                                    equ 3000h
apply_screen_xor_grid_proc                         equ 3000h
backup_upper_town_3_tiles_proc                     equ 3002h
render_town_tiles_28_columns_proc                  equ 3004h
scroll_floor_right_8px_proc                        equ 3006h
scroll_ceiling_right_4px_proc                      equ 3008h
scroll_floor_left_8px_proc                         equ 300Ah
scroll_ceiling_left_4px_proc                       equ 300Ch
unpack_to_shadow_memory_six_tiles_proc             equ 300Eh
ui_draw_routine_dispatcher_proc                    equ 3010h
blit_6_tiles_to_shadow_memory_proc                 equ 3012h
get_sprite_vram_address_proc                       equ 3014h
draw_tile_to_screen_proc                           equ 3016h
draw_arrow_icon_or_ui_symbol_proc                  equ 3018h
format_string_to_buffer_proc                       equ 301Ah
draw_string_buffer_to_screen_proc                  equ 301Ch
scroll_hud_up_proc                                 equ 301Eh
scroll_hud_down_proc                               equ 3020h
render_numeric_score_proc                          equ 3022h
decompress_patterns_proc                           equ 3024h
apply_sprite_mask_proc                             equ 3026h

; town.bin exports
town_entry_enabling_edge_scroll_proc               equ 6000h
town_entry_disabling_edge_scroll_proc              equ 6002h
render_menu_dialog_proc                            equ 6004h
convert_ax_to_decimal_proc                         equ 6006h
show_yes_no_dialog_proc                            equ 6008h
check_gold_sufficient_proc                         equ 600Ah
add_gold_to_hero_proc                              equ 600Ch
render_menu_string_list_proc                       equ 600Eh
select_from_menu_proc                              equ 6010h
render_menu_list_scrolling_proc                    equ 6012h
houseCursorShow_proc                               equ 6014h
npcAnimation_proc                                  equ 6016h
houseCursorUp_proc                                 equ 6018h
houseCursorDown_proc                               equ 601Ah
restore_game_proc                                  equ 601Ch


; mdt info - towns
town_descriptor_addr                               equ 0C000h
  ; [0]: bits 5..1 - msd index in [MGT1.MSD, UGM1.MSD, MGT2.MSD, UGM2.MSD]
  ; [1]: NPC category; 0 -> mman.grp, 1 -> cman.grp
  ; [2]: ff
  ; [3]: town_has_middle_layer
  ; [4]: pat_id
town_map_width                                     equ 0C002h
town_name_rendering_info                           equ 0C004h
town_id                                            equ 0C006h ; 1-based
town_transition_table                              equ 0C007h
doors_array_addr                                   equ 0C009h
dungeon_entrance_table                             equ 0C00Bh
npc_conversations_addr                             equ 0C00Dh
npc_array_addr                                     equ 0C00Fh
npc_patrol_boundaries                              equ 0C011h
word_C015                                          equ 0C015h
town_tiles                                         equ 0C017h
town_head_level_tiles                              equ town_tiles+5 ; the row where NPC IDs live
;Offset | Muralla Town | Details
;-----------------------------------------------
; c000  | c6d3         | Town descriptor: 00 00 ff 00 01
; c002  | 00d7         | mapWidth
; c004  | c6d8         | Town name rendering info
; c006  | 1            |
; c007  | c6e8         | town_transition_table
; c009  | c6ec         | Town doors array (struct size = 3)
; c00b  | c700         | 3D 00 07 00 00 FF FF
; c00d  | c707         | array of pointers to ff-terminated strings (NPC conversation)
; c00f  | ceaf         | NPC array (struct size = 8)
; c011  | c6cf         | 05 00 96 00
; c013  | 00ac         |
; c015  | c705         | ff ff
; c017  | -            | Unpacked town map c017...c6cf = 0x6b8 bytes = 0xd7 * 8 (8 x 1 vertical blocks)

viewport_buffer                                    equ 0E000h
word_E001                                          equ 0E001h