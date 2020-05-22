.include "ziggurat.inc"
.include "zpu.inc"

.code

.proc op_extended
    ; Check whether our extended opcode is in range
    lda opcode_ext
    sta gREG::r6L
    asl
    cmp #opcode_ext_vectors_end-opcode_ext_vectors
    bcs @unknown_opcode

    ; Jump to good opcode vector
    tax
    jmp (opcode_ext_vectors,x)

@unknown_opcode:
    ; Print warning for unknown extended opcodes
    lda gREG::r6L
    sta operand_0
    lda #<msg_unimplemented
    sta gREG::r6L
    lda #>msg_unimplemented
    sta gREG::r6H
;    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc opext_illegal
    ; Bail on illegal extended opcodes
    lda opcode_ext
    sta operand_0
    lda #ERR_ILLEGAL_EXTENDED
    jmp print_error_and_exit
.endproc

.rodata
opcode_ext_vectors:
    .word opext_save                    ; Extended opcode $00 - save table bytes name prompt -> (result)
    .word opext_restore                 ; Extended opcode $01 - restore table bytes name prompt -> (result)
    .word opext_log_shift               ; Extended opcode $02 - log_shift number places -> (result)
    .word opext_art_shift               ; Extended opcode $03 - art_shift number places -> (result)
    .word opext_set_font                ; Extended opcode $04 - version 5: set_font font -> (result)
                                        ;                     - versions 6+: set_font font window -> (result)
    .word opext_draw_picture            ; Extended opcode $05 - draw_picture picture-number y x
    .word opext_picture_data            ; Extended opcode $06 - picture_data picture-number array ?(label)
    .word opext_erase_picture           ; Extended opcode $07 - erase_picture picture-number y x
    .word opext_set_margins             ; Extended opcode $08 - set_margins left right window
    .word opext_save_undo               ; Extended opcode $09 - save_undo -> (result)
    .word opext_restore_undo            ; Extended opcode $0a - restore_undo -> (result)
    .word opext_print_unicode           ; Extended opcode $0b - print_unicode char-number
    .word opext_check_unicode           ; Extended opcode $0c - check_unicode char-number -> (result)
    .word opext_set_true_colour         ; Extended opcode $0d - version 5: set_true_colour foreground background
                                        ;                     - versions 6+: set_true_colour foreground background window
    .word opext_illegal                 ; Extended opcode $0e - illegal
    .word opext_illegal                 ; Extended opcode $0f - illegal

    .word opext_move_window             ; Extended opcode $10 - move_window window y x
    .word opext_window_size             ; Extended opcode $11 - window_size window y x
    .word opext_window_style            ; Extended opcode $12 - window_style window flags operation
    .word opext_get_wind_prop           ; Extended opcode $13 - get_wind_prop window property-number -> (result)
    .word opext_scroll_window           ; Extended opcode $14 - scroll_window window pixels
    .word opext_pop_stack               ; Extended opcode $15 - pop_stack items stack
    .word opext_read_mouse              ; Extended opcode $16 - read_mouse array
    .word opext_mouse_window            ; Extended opcode $17 - mouse_window window
    .word opext_push_stack              ; Extended opcode $18 - push_stack value stack ?(label)
    .word opext_put_wind_prop           ; Extended opcode $19 - put_wind_prop window property-number value
    .word opext_print_form              ; Extended opcode $1a - print_form formatted-table
    .word opext_make_menu               ; Extended opcode $1b - make_menu number table ?(label)
    .word opext_picture_table           ; Extended opcode $1c - picture_table table
    .word opext_buffer_screen           ; Extended opcode $1d - buffer_screen mode -> (result)
opcode_ext_vectors_end:

msg_unimplemented: .byte "WARNING: Unimplemented extended opcode # (ignored)", CH::ENTER, 0
