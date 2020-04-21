.include "ziggurat.inc"
.include "zpu.inc"

.code

.proc op_show_status
    lda #<msg_op_show_status
    sta gREG::r6L
    lda #>msg_op_show_status
    sta gREG::r6H
    jsr printf

    ; Only show for V1-3
    chkver V1|V2|V3,@show_status_is_nop
    jsr show_status
@show_status_is_nop:
    jmp fetch_and_dispatch
.endproc

.proc show_status
@g2 = $480
@g3 = $482
@save_op0 = $484
@timeflags = $486
    ; Start with a space
    pha
    phx
    phy
    lda operand_0
    sta @save_op0
    lda operand_0+1
    sta @save_op0+1
    lda window_status
    ldx #0
    ldy #0
    jsr win_setcursor
    ldy #' '
    sec
    jsr win_putchr

    ; Print the encoded name of object in the first global variable (up to 60 characters worth)
    lda #$10
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx operand_0
    sty operand_0+1
    lda window_status
    ldx #64
    jsr do_print_obj

@clear_to_score:
    ; Print spaces over to column 70
    lda window_status
    ldx #0
    ldy #' '
    sec
    jsr win_putchr
    jsr win_getcursor
    cpx #70
    bcc @clear_to_score

    ; Load the second and third globals
    lda #$11
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx @g2
    sty @g2+1
    lda #$12
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx @g3
    sty @g3+1
    stz @timeflags

    ; Is this a score or a timed game?
    chkver V3,@show_score_or_time
    lda #1
    sta VIA1::PRA
    lda ZMheader::flags
    and #F1V3_ISTIMED
    beq @show_score_or_time

    ; It's a timed game--load the hours from the second global
    dec @timeflags
    lda @g2+1
    cmp #12
    bcs @is_pm

    ; For AM, we change to 12 if 0 and clear bit 6 of @timeflags
    bne @2
    lda #12
    sta @g2+1
@2: lda @timeflags
    and #$bf
    sta @timeflags
    bra @show_score_or_time

@is_pm:
    ; For PM, we subtract 11 from hours and change to 12 if 0
    sec
    sbc #11
    bne @3
    lda #12
@3: sta @g2+1

@show_score_or_time:
    ; Print @g2
    lda @g2
    sta operand_0
    lda @g2+1
    sta operand_0+1
    sec ; No leading zeroes
    lda window_status
    jsr do_print_num

    ; For score game print '/', for timed game print ':'
    bit @timeflags
    bmi @1
    ldy #'/'
    .byte $2c
@1: ldy #':'
    ldx #0
    sec
    lda window_status
    jsr win_putchr

    ; Print @g3 (print two digits if it's a timed game)
    lda @g3
    sta operand_0
    lda @g3+1
    sta operand_0+1
    lda #$0
    sec
    sbc @timeflags
    lda window_status
    jsr do_print_num

    ; For timed game, print AM/PM
    bit @timeflags
    bpl @finish_status
    php
    lda window_status
    ldx #0
    ldy #' '
    sec
    jsr win_putchr
    plp
    bvc @print_am
    ldy #'p'
    .byte $2c
@print_am:
    ldy #'a'
    ldx #0
    sec
    jsr win_putchr
    ldy #'m'
    sec
    jsr win_putchr

@finish_status:
    ; Print spaces over to column 70
    lda window_status
    ldx #0
    ldy #' '
    sec
    jsr win_putchr
    jsr win_getcursor
    cpx #80
    bcc @finish_status
    lda @save_op0
    sta operand_0
    lda @save_op0+1
    sta operand_0+1
    ply
    plx
    pla
    rts
.endproc

.proc op_buffer_mode
    jmp op_illegal

    lda #<msg_op_buffer_mode
    sta gREG::r6L
    lda #>msg_op_buffer_mode
    sta gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc op_set_cursor
    jmp op_illegal

    chkver V6|V7|V8,@nowindow
    ldy #<msg_op_set_cursor_v6
    ldx #>msg_op_set_cursor_v6
    bra @debug
@nowindow:
    ldy #<msg_op_set_cursor
    ldx #>msg_op_set_cursor
@debug:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc opext_set_font
    chkver V6|V7|V8,@nowindow
    ldy #<msg_opext_set_font_v6
    ldx #>msg_opext_set_font_v6
    bra @debug
@nowindow:
    ldy #<msg_opext_set_font
    ldx #>msg_opext_set_font
@debug:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf

    ; Set the current font
    lda current_window
    ldx operand_0
    ldy operand_0+1
    jsr win_setfont
    jmp fetch_and_dispatch
.endproc

.proc op_output_stream
    jmp op_illegal

    lda num_operands
    cmp #1
    bcs @check_for_1
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@check_for_1:
    beq @has_1
    cmp #3
    beq @has_2
    ldy #<msg_op_output_stream_v6
    ldx #>msg_op_output_stream_v6
    bra @debug
@has_2:
    ldy #<msg_op_output_stream_v5
    ldx #>msg_op_output_stream_v5
    bra @debug
@has_1:
    ldy #<msg_op_output_stream_v3
    ldx #>msg_op_output_stream_v3
@debug:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc op_erase_window
    jmp op_illegal

    lda #<msg_op_erase_window
    sta gREG::r6L
    lda #>msg_op_erase_window
    sta gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc op_set_text_style
    jmp op_illegal

    lda #<msg_op_set_text_style
    sta gREG::r6L
    lda #>msg_op_set_text_style
    sta gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc op_set_window
    jmp op_illegal

    lda #<msg_op_set_window
    sta gREG::r6L
    lda #>msg_op_set_window
    sta gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc op_split_window
    jmp op_illegal

@main_left = $420
@main_top = $421
@main_width = $422
@main_height = $423
@main_cur_x = $424
@main_cur_y = $425
@upper_height = $426
@upper_diff = $427

    lda #<msg_op_split_window
    sta gREG::r6L
    lda #>msg_op_split_window
    sta gREG::r6H
    jsr printf

    ; Are we splitting or closing?
    lda operand_0+1
    beq @unsplit

    ; Get the main window info
    lda zm_windows
    jsr win_getpos
    stx @main_left
    sty @main_top
    jsr win_getsize
    stx @main_width
    sty @main_height
    jsr win_getcursor
    stx @main_cur_x
    sty @main_cur_y

    ; See if we have an upper window already
    lda zm_windows+1
    bmi @have_upper
    jsr win_open
    sta zm_windows+1

@have_upper:
    ; Set the upper window as current
    sta current_window

    ; Get upper window height
    jsr win_getsize
    sty @upper_height

    ; Figure out the difference in height
    lda operand_0+1
    sec
    sbc @upper_height
    sta @upper_diff

    ; Move the main window down

@unsplit:
    ; See if we have an upper window
    lda zm_windows+1
    bmi @done

    ; Get the cursor position of the upper window and close it
    jsr win_getcursor
    jsr win_close

    ; Set the main window cursor
    lda zm_windows
    jsr win_setcursor

    ; Move the main window back to the top and resize it
    ldx #0
    ldy #0
    jsr win_setpos
    ldx #SCREEN_WIDTH
    ldy #SCREEN_HEIGHT
    jsr win_setsize

    ; Set the main window as current
    sta current_window

@done:
    jmp fetch_and_dispatch
.endproc

.proc op_set_colour
    jmp op_illegal

    chkver V6|V7|V8,@nowindow
    ldy #<msg_op_set_colour_v6
    ldx #>msg_op_set_colour_v6
    bra @debug
@nowindow:
    ldy #<msg_op_set_colour
    ldx #>msg_op_set_colour
@debug:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf

    jmp fetch_and_dispatch
.endproc

op_get_cursor:
op_erase_line:
    jmp op_illegal

opext_buffer_screen:
opext_set_true_colour:
opext_get_wind_prop:
opext_make_menu:
opext_mouse_window:
opext_move_window:
opext_put_wind_prop:
opext_read_mouse:
opext_scroll_window:
opext_set_margins:
opext_window_size:
opext_window_style:
    jmp opext_illegal

.rodata

msg_op_erase_window:        .byte "Erasing window @", CH::ENTER, 0
msg_op_set_text_style:      .byte "Setting text style @", CH::ENTER, 0
msg_op_set_window:          .byte "Setting window @", CH::ENTER, 0
msg_op_split_window:        .byte "Split window lines=@", CH::ENTER, 0
msg_op_set_colour:          .byte "Set colour fg=@ bg=@", CH::ENTER, 0
msg_op_set_colour_v6:       .byte "Set colour fg=@ bg=@ window=@", CH::ENTER, 0
msg_op_buffer_mode:         .byte "Setting buffer mode @", CH::ENTER, 0
msg_op_output_stream_v3:    .byte "Output stream @", CH::ENTER, 0
msg_op_output_stream_v5:    .byte "Output stream @ table=@", CH::ENTER, 0
msg_op_output_stream_v6:    .byte "Output stream @ table=@ width=@", CH::ENTER, 0
msg_op_set_cursor:          .byte "Setting cursor line=@ col=@", CH::ENTER, 0
msg_op_set_cursor_v6:       .byte "Setting cursor line=@ col=@ window=@", CH::ENTER, 0
msg_opext_set_font:         .byte "Setting font @", CH::ENTER, 0
msg_opext_set_font_v6:      .byte "Setting font @ window=@", CH::ENTER, 0
msg_op_show_status:         .byte "Show status", CH::ENTER, 0
