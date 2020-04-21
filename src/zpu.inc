; Global ZPU definitions

; Control functions
.global fetch_and_dispatch

; Memory and helper functions
.global memory_init
.global encode_baddr
.global decode_baddr
.global decode_waddr
.global decode_paddr_r
.global decode_paddr_s
.global pc_fetch_and_advance
.global mem_fetch_and_advance
.global mem_store_and_advance
.global mem_advance_block
.global mem_advance
.global mem_retreat
.global mem2_fetch_and_advance
.global mem2_store_and_advance
.global mem2_advance_block
.global mem2_advance
.global mem2_retreat
.global read_array_byte
.global read_array_word
.global write_array_byte
.global write_array_word
.global fetch_varvalue
.global store_varvalue
.global follow_branch
.global print_encoded
.global convert_zsciihigh_to_unicode
.global show_status

.global numtobit
.global atab_default
.global atab_v1_default
.global zscii_ctype_table

; Push/pop a word on the stack (assumed big-endian). Routine takes value in x (high byte)/y (low byte).
; Macro gives you shortcuts for immediate and absolute addressing.
; (NOTE: Assumes stack is properly aligned; i.e., always on even byte)
.global zpush_word
.macro zpush w
.scope
.ifnblank w
    .if (.match (.left (1, {arg}), #))
        ; Immediate mode
        ldx #>(.right (.tcount ({arg})-1, {arg}))
        ldy #<(.right (.tcount ({arg})-1, {arg}))
    .else
        ; Assume absolute or immediate mode
        ldx w
        ldy 1+w
    .endif
.endif
    jsr zpush_word
.endscope
.endmacro

.global zpop_word
.macro zpop w
.scope
    jsr zpop_word
.ifnblank w
    .if (.match (.left (1, {arg}), #))
        ; Immediate mode
        .error "Can't ZPOP immediate"
    .else
        ; Assume absolute or immediate mode
        stx w
        sty 1+w
    .endif
.endif
.endscope
.endmacro

; Opcode handlers
.global op_add
.global op_and
.global op_buffer_mode
.global op_call_save
.global op_call_void
.global op_check_arg_count
.global op_clear_attr
.global op_copy_table
.global op_dec
.global op_dec_chk
.global op_div
.global op_encode_text
.global op_erase_line
.global op_erase_window
.global op_extended
.global op_get_child
.global op_get_cursor
.global op_get_next_prop
.global op_get_parent
.global op_get_prop
.global op_get_prop_addr
.global op_get_prop_len
.global op_get_sibling
.global op_illegal
.global op_inc
.global op_inc_chk
.global op_input_stream
.global op_insert_obj
.global op_je
.global op_jg
.global op_jin
.global op_jl
.global do_lt ; This is a helper that does the work of op_jl without printing the debug line so that jg/inc_chk/dec_chk can use it
.global op_jump
.global op_jz
.global do_jz ; This is a helper that does the work of op_jz without printing the debug line so that get_sibling/get_child can use it
.global op_load
.global op_loadb
.global op_loadw
.global op_mod
.global op_mul
.global op_new_line
.global op_nop
.global op_not
.global op_not_v5
.global op_not_or_callvoid
.global op_or
.global op_output_stream
.global op_piracy
.global op_pop_or_catch
.global op_print
.global op_print_addr
.global op_print_char
.global op_print_num
.global do_print_num ; This is a helper that does the work of op_print_num so that show_status can use it
.global op_print_obj
.global do_print_obj ; This is a helper that does the work of op_print_obj so that show_status can use it
.global op_print_paddr
.global op_print_ret
.global op_print_table
.global op_pull
.global op_push
.global op_put_prop
.global op_quit
.global op_random
.global op_read
.global op_read_char
.global op_remove_obj
.global op_restart
.global op_restore
.global op_ret
.global op_ret_popped
.global op_rfalse
.global op_rtrue
.global op_save
.global op_scan_table
.global op_set_attr
.global op_set_colour
.global op_set_cursor
.global op_set_text_style
.global op_set_window
.global op_show_status
.global op_sound_effect
.global op_split_window
.global op_store
.global op_storeb
.global op_storew
.global op_sub
.global op_test
.global op_test_attr
.global op_throw
.global op_tokenise
.global op_verify

; Extended opcodes
.global opext_save
.global opext_restore
.global opext_log_shift
.global opext_art_shift
.global opext_set_font
.global opext_draw_picture
.global opext_picture_data
.global opext_erase_picture
.global opext_set_margins
.global opext_save_undo
.global opext_restore_undo
.global opext_print_unicode
.global opext_check_unicode
.global opext_set_true_colour
.global opext_illegal
.global opext_move_window
.global opext_window_size
.global opext_window_style
.global opext_get_wind_prop
.global opext_scroll_window
.global opext_pop_stack
.global opext_read_mouse
.global opext_mouse_window
.global opext_push_stack
.global opext_put_wind_prop
.global opext_print_form
.global opext_make_menu
.global opext_picture_table
.global opext_buffer_screen

; ZPU "registers"
.globalzp zpu_sp
.globalzp zpu_bp
.globalzp zpu_pc
.globalzp zpu_mem
.globalzp zpu_mem_2
.globalzp opcode
.globalzp optypes
.globalzp operands
.globalzp operand_0
.globalzp operand_1
.globalzp operand_2
.globalzp operand_3
.globalzp operand_4
.globalzp operand_5
.globalzp operand_6
.globalzp operand_7
.globalzp atab_addr

; ZPU variables
.global dict_base
.global obj_base
.global objtbl_base
.global glob_base
.global stat_base
.global himem_base
.global abbrev_base
.global trmchr_base
.global hdrext_base
.global num_operands
.global opcode_ext
.global objentry_offset_parent
.global objentry_offset_sibling
.global objentry_offset_child
.global objentry_offset_propaddr
.global window_status
.global current_window
.global zm_windows

.define SHOW_DEBUG_WINDOW 1
.define SCREEN_HEIGHT 5
.define SCREEN_WIDTH 80
.define FONT_WIDTH 4
.define FONT_HEIGHT 8
