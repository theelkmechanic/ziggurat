.include "ziggurat.inc"
.include "zpu.inc"

.code

.proc op_show_status
    lda #<msg_op_show_status
    sta gREG::r6L
    lda #>msg_op_show_status
    sta gREG::r6H
;    jsr printf

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
    sta BANK_RAM
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
    lda #<msg_op_buffer_mode
    sta gREG::r6L
    lda #>msg_op_buffer_mode
    sta gREG::r6H
;    jsr printf

    ; Set buffer mode on main window
    lda window_main
    ldx operand_0+1
    jsr win_setbuffer
    jmp fetch_and_dispatch
.endproc

.proc op_set_cursor
    chkver V6,@nowindow
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

    ; Check v4 or later
    chkver V1|V2|V3,@ok
    jmp op_illegal

@ok:
    ; Set the cursor for the current window
    ldy operand_0+1
    ldx operand_1+1
    dey
    dex
    lda current_window
    jsr win_setcursor
    jmp fetch_and_dispatch
.endproc

.proc op_get_cursor
    lda #<msg_op_get_cursor
    sta gREG::r6L
    lda #>msg_op_get_cursor
    sta gREG::r6H
    jsr printf

    ; Check v4 or later
    chkver V1|V2|V3,@ok
    jmp op_illegal

@ok:
    ; Get the address we want to store the cursor position in
    ldx operand_0
    ldy operand_0+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta BANK_RAM

    ; Get the cursor for the current window
    lda current_window
    jsr win_getcursor
    inx
    iny

    ; And store them in the array
    lda #0
    jsr mem_store_and_advance
    tya
    jsr mem_store_and_advance
    lda #0
    jsr mem_store_and_advance
    txa
    jsr mem_store_and_advance
    jmp fetch_and_dispatch
.endproc

.proc opext_set_font
    chkver V6,@nowindow
    lda #ERR_ILLEGAL_OPCODE
    jmp print_error_and_exit
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

    ; Get the current font
    ldx #0
    ldy current_font

    ; Font 0 just returns the current font
    lda operand_0
    ora operand_0+1
    beq @done

    ; We only support fonts 1, 3, and 4.
    lda operand_0
    bne @bad_font
    lda operand_0+1
    cmp #1
    beq @good_font
    cmp #4
    beq @good_font
    cmp #3
    beq @good_font
@bad_font:
    ldy #0
    bra @done
@good_font:
    sta current_font

@done:
    ; Store the previous font in the result
    jsr pc_fetch_and_advance
    clc ; Push stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc op_erase_line
    ; If operand_0 is 1, erase from the current cursor position in the current window to the end of the line
    lda operand_0
    bne @done
    lda operand_0+1
    cmp #1
    bne @done
    lda current_window
    jsr win_getsize
    cpy #0
    bne @done
    jsr win_erasecurrtoeol

@done:
    jmp fetch_and_dispatch
.endproc

.proc op_erase_window
    lda #<msg_op_erase_window
    sta gREG::r6L
    lda #>msg_op_erase_window
    sta gREG::r6H
    jsr printf

    ; Valid from V4 on
    chkver V1|V2|V3,@ok
    jmp op_illegal

@ok:
    ; Which window are we erasing?
    lda operand_0
    beq @checkvalid
    cmp #$ff
    beq @special
@done:
    jmp fetch_and_dispatch

@checkvalid:
    ; Is it window 0 or 1?
    lda operand_0+1
    beq @erase_main
    cmp #1
    bne @done

    ; Erase the upper window
    lda window_upper
    jsr win_clear
    bra @done

@erase_main:
    ; Erase the main window
    lda window_main
    jsr win_clear

    ; For version 4, put the cursor at the bottom
    chkver V4,@done
    lda window_main
    jsr win_getsize
    cpy #2
    bcc @done
    dey
    ldx #0
    jsr win_setcursor
    bra @done

@special:
    lda operand_0+1
    cmp #$fe
    bcc @done
    cmp #$ff
    bne @justclear

    ; Unsplit and clear
    lda window_upper
    jsr win_getsize
    cpy #0
    beq @justclear
    stz operand_0
    stz operand_0+1
    jsr do_split_window
    bra @done

@justclear:
    ; Clear upper and lower windows
    lda window_upper
    jsr win_clear
    lda window_main
    jsr win_clear

    ; For V4, put lower window cursor at bottom line
    chkver V4,@done
    lda window_main
    jsr win_getsize
    cpy #0
    beq @done
    dey
    sty $420
    jsr win_getcursor
    cpy $420
    bcs @done
    ldy $420
    ldx #0
    jsr win_setcursor
    jmp @done
.endproc

.proc op_set_text_style
    lda #<msg_op_set_text_style
    sta gREG::r6L
    lda #>msg_op_set_text_style
    sta gREG::r6H
    jsr printf

    ; Set the appropriate text style
    ldx operand_0+1
    lda window_main
    jsr win_setstyle
    lda window_upper
    jsr win_setstyle

    jmp fetch_and_dispatch
.endproc

.proc op_set_window
    lda #<msg_op_set_window
    sta gREG::r6L
    lda #>msg_op_set_window
    sta gREG::r6H
    jsr printf

    ; Which window are we setting to?
    lda operand_0
    bne @done
    lda operand_0+1
    beq @setmain
    dec
    bne @done

    ; Set to upper window and move cursor to top left
    lda window_upper
    sta current_window
    ldx #0
    ldy #0
    jsr win_setcursor
    bra @done

@setmain:
    ; Set to main window
    lda window_main
    sta current_window

@done:
    jmp fetch_and_dispatch
.endproc

.proc op_split_window

    lda #<msg_op_split_window
    sta gREG::r6L
    lda #>msg_op_split_window
    sta gREG::r6H
    jsr printf

    jsr do_split_window
    jmp fetch_and_dispatch
.endproc

.proc do_split_window
@main_top = $420
@main_height = $421
@main_cur_y = $422
@upper_top = $423
@upper_height = $424
@upper_diff = $425

    ; Get the current state of things
    lda window_main
    jsr win_getpos
    sty @main_top
    jsr win_getsize
    sty @main_height
    jsr win_getcursor
    sty @main_cur_y
    lda window_upper
    jsr win_getpos
    sty @upper_top
    jsr win_getsize
    sty @upper_height

    ; Are we unsplitting?
    lda operand_0
    ora operand_0+1
    bne @do_split

@do_unsplit:
    ; Make sure main is current window
    lda window_main
    sta current_window

    ; Do we need to unsplit?
    ldy @upper_height
    bne @calc_change
    jmp @done

@calc_change:
    ; Figure out how many lines we're going to move main up
    lda @main_top
    sec
    sbc @upper_top
    sta @upper_diff

    ; Move main up, expand it, and move its cursor down, and set upper height to 0
    lda @main_height
    clc
    adc @upper_diff
    sta @main_height
    chkver V4,@noforcebottom
    lda @main_height
    dec
    bra @setmaincury
@noforcebottom:
    lda @main_cur_y
    clc
    adc @upper_diff
@setmaincury:
    sta @main_cur_y
    lda @upper_top
    sta @main_top
    stz @upper_height
    jmp @update_windows

@do_split:
    ; Upper height needs to get set to the param but not more than screen height
    lda operand_0
    beq @calcupperheight
    lda #$ff
    sta operand_0+1
@calcupperheight:
    lda #SCREEN_HEIGHT
    sec
    sbc @upper_top
    cmp operand_0+1
    bcs @upperheightok
    sta operand_0+1
@upperheightok:
    lda operand_0+1
    sec
    sbc @upper_height
    sta @upper_diff
    bmi @shrinking
    bne @growing
    jmp @done

@growing:
    ; Grow the upper window and shrink the main window
    lda @upper_height
    clc
    adc @upper_diff
    sta @upper_height
    lda @main_top
    clc
    adc @upper_diff
    sta @main_top
    lda @main_cur_y
    sec
    sbc @upper_diff
    bpl @yinrange
    lda #0
@yinrange:
    sta @main_cur_y
    lda @main_height
    sec
    sbc @upper_diff
    sta @main_height
    bra @update_windows

@shrinking:
    ; Shrink the upper window and grow the main window
    lda @upper_height
    sec
    sbc @upper_diff
    sta @upper_height
    lda @main_top
    sec
    sbc @upper_diff
    sta @main_top
    lda @main_cur_y
    clc
    adc @upper_diff
    sta @main_cur_y
    lda @main_height
    clc
    adc @upper_diff
    sta @main_height

@update_windows:
    ; Update main and upper windows
    lda window_main
    jsr win_getpos
    ldy @main_top
    jsr win_setpos
    jsr win_getsize
    ldy @main_height
    jsr win_setsize
    jsr win_getcursor
    ldy @main_cur_y
    jsr win_setcursor
    lda window_upper
    jsr win_getsize
    ldy @upper_height
    jsr win_setsize
    ldx #0
    ldy #0
    jsr win_setcursor

    ; Clear upper window in V3
    chkver V3, @done
    lda window_upper
    jsr win_clear

@done:
    rts
.endproc

.proc op_set_colour
;    jmp op_illegal

    chkver V6,@nowindow
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

    ; Set the appropriate text colors
    lda window_main
    jsr win_getcolor
    lda operand_1+1
    bne @checkdefaultbg
    txa
    and #$f0
    bra @getfg
@checkdefaultbg:
    cmp #1
    bpl @setbg
    lda #DEFAULT_BG
@setbg:
    asl
    asl
    asl
    asl

@getfg:
    sta operand_1+1
    lda operand_0+1
    bne @checkdefaultfg
    txa
    bra @setfg
@checkdefaultfg:
    cmp #1
    bpl @setfg
    lda #DEFAULT_FG
@setfg:
    and #$0f
    ora operand_1+1
    lda window_main
    jsr win_setcolor
    lda window_upper
    jsr win_setcolor

    jmp fetch_and_dispatch
.endproc

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
msg_op_set_cursor:          .byte "Setting cursor line=@ col=@", CH::ENTER, 0
msg_op_set_cursor_v6:       .byte "Setting cursor line=@ col=@ window=@", CH::ENTER, 0
msg_op_get_cursor:          .byte "Getting cursor into @", CH::ENTER, 0
msg_opext_set_font:         .byte "Setting font @", CH::ENTER, 0
msg_opext_set_font_v6:      .byte "Setting font @ window=@", CH::ENTER, 0
msg_op_show_status:         .byte "Show status", CH::ENTER, 0
