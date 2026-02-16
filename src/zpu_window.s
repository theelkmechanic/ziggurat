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
    ; Start with a space
    pha
    phx
    phy
    lda operand_0
    sta ss_save_op0
    lda operand_0+1
    sta ss_save_op0+1
    lda window_status
    ldx #0
    ldy #0
    jsr ulwin_putcursor
    lda window_status
    ldx #0
    ldy #' '
    jsr zmwin_putchr

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
    jsr zmwin_putchr
    lda window_status
    jsr ulwin_getcursor
    cpx #70
    bcc @clear_to_score

    ; Load the second and third globals
    lda #$11
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx ss_g2
    sty ss_g2+1
    lda #$12
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx ss_g3
    sty ss_g3+1
    stz ss_timeflags

    ; Is this a score or a timed game?
    chkver V3,@show_score_or_time
    lda #ZIF_BASE_BANK
    sta BANK_RAM
    lda ZMheader::flags
    and #F1V3_ISTIMED
    beq @show_score_or_time

    ; It's a timed game--load the hours from the second global
    dec ss_timeflags
    lda ss_g2+1
    cmp #12
    bcs @is_pm

    ; For AM, we change to 12 if 0 and clear bit 6 of ss_timeflags
    bne @2
    lda #12
    sta ss_g2+1
@2: lda ss_timeflags
    and #$bf
    sta ss_timeflags
    bra @show_score_or_time

@is_pm:
    ; For PM, we subtract 11 from hours and change to 12 if 0
    sec
    sbc #11
    bne @3
    lda #12
@3: sta ss_g2+1

@show_score_or_time:
    ; Print ss_g2
    lda ss_g2
    sta operand_0
    lda ss_g2+1
    sta operand_0+1
    sec ; No leading zeroes
    lda window_status
    jsr do_print_num

    ; For score game print '/', for timed game print ':'
    bit ss_timeflags
    bmi @1
    ldy #'/'
    .byte $2c
@1: ldy #':'
    ldx #0
    lda window_status
    jsr zmwin_putchr

    ; Print ss_g3 (print two digits if it's a timed game)
    lda ss_g3
    sta operand_0
    lda ss_g3+1
    sta operand_0+1
    lda #$0
    sec
    sbc ss_timeflags
    lda window_status
    jsr do_print_num

    ; For timed game, print AM/PM
    bit ss_timeflags
    bpl @finish_status
    php
    lda window_status
    ldx #0
    ldy #' '
    jsr zmwin_putchr
    plp
    bvc @print_am
    ldy #'p'
    .byte $2c
@print_am:
    ldy #'a'
    ldx #0
    lda window_status
    jsr zmwin_putchr
    lda window_status
    ldx #0
    ldy #'m'
    jsr zmwin_putchr

@finish_status:
    ; Clear from cursor to end of status line
    lda window_status
    jsr ulwin_eraseeol
    lda ss_save_op0
    sta operand_0
    lda ss_save_op0+1
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

    ; Set/clear buffer mode in main window slot
    lda zmwin_slots + ZMWIN_FLAGS
    ldx operand_0+1
    beq @buffer_off
    ora #WIN_BUFFER
    bra @buffer_done
@buffer_off:
    and #WIN_BUFFER ^ $FF
@buffer_done:
    sta zmwin_slots + ZMWIN_FLAGS
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
    jsr ulwin_putcursor
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
    jsr ulwin_getcursor
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
    jsr ulwin_eraseeol

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
    jsr ulwin_clear
    bra @done

@erase_main:
    ; Erase the main window
    lda window_main
    jsr ulwin_clear

    ; For version 4, put the cursor at the bottom
    chkver V4,@done
    lda window_main
    jsr ulwin_getsize
    cpy #2
    bcc @done
    dey
    ldx #0
    lda window_main
    jsr ulwin_putcursor
    bra @done

@special:
    lda operand_0+1
    cmp #$fe
    bcc @done
    cmp #$ff
    bne @justclear

    ; Unsplit and clear
    lda zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    cmp #$FF
    beq @justclear
    stz operand_0
    stz operand_0+1
    jsr do_split_window
    bra @done

@justclear:
    ; Clear upper and lower windows
    lda zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    cmp #$FF
    beq @clear_main_only
    lda window_upper
    jsr ulwin_clear
@clear_main_only:
    lda window_main
    jsr ulwin_clear

    ; For V4, put lower window cursor at bottom line
    chkver V4,@done
    lda window_main
    jsr ulwin_getsize
    cpy #0
    beq @done
    dey
    sty ew_temp
    lda window_main
    jsr ulwin_getcursor
    cpy ew_temp
    bcc :+
    jmp @done
:   ldy ew_temp
    ldx #0
    lda window_main
    jsr ulwin_putcursor
    jmp @done
.endproc

.proc op_set_text_style
    lda #<msg_op_set_text_style
    sta gREG::r6L
    lda #>msg_op_set_text_style
    sta gREG::r6H
    jsr printf

    ; Set the appropriate text style in slots
    ldx operand_0+1
    beq @clear_style
    ; OR style into both window slots
    txa
    ora zmwin_slots + ZMWIN_STYLE
    sta zmwin_slots + ZMWIN_STYLE
    txa
    ora zmwin_slots + ZMWIN_SIZE + ZMWIN_STYLE
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_STYLE
    bra @update_color

@clear_style:
    stz zmwin_slots + ZMWIN_STYLE
    stz zmwin_slots + ZMWIN_SIZE + ZMWIN_STYLE

@update_color:
    ; Update UniLib color for main window
    ldy #0
    lda window_main
    jsr zmwin_setcolor
    ; Update UniLib color for upper window (if it exists)
    lda zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    cmp #$FF
    beq @done
    ldy #ZMWIN_SIZE
    lda window_upper
    jsr zmwin_setcolor

@done:
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
    lda #1
    sta zmwin_current
    ldx #0
    ldy #0
    lda window_upper
    jsr ulwin_putcursor
    bra @done

@setmain:
    ; Set to main window
    lda window_main
    sta current_window
    stz zmwin_current

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

; do_split_window - Overlay model
;
; Main window is always full screen (never moved/resized).
; Upper window overlays on top via UniLib z-ordering.
; - split N>0: create/resize upper to height N
; - split 0: close upper (main content revealed)
.proc do_split_window

    ; Are we unsplitting?
    lda operand_0
    ora operand_0+1
    bne @do_split

@do_unsplit:
    ; Make sure main is current window
    lda window_main
    sta current_window
    stz zmwin_current

    ; Is upper window even open?
    lda zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    cmp #$FF
    bne :+
    rts
:
    ; Close the upper window
    lda window_upper
    jsr ulwin_close
    lda #$FF
    sta window_upper
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    rts

@do_split:
    ; Clamp upper height to screen
    lda operand_0
    beq @clampheight
    lda #SCREEN_HEIGHT
    sta operand_0+1
@clampheight:
    lda operand_0+1
    cmp #SCREEN_HEIGHT
    bcc @heightok
    lda #SCREEN_HEIGHT
@heightok:
    sta dsw_upper_height

    ; Is upper window already open?
    lda zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    cmp #$FF
    beq @create_upper

    ; Resize existing upper window
    lda window_upper
    ldx #SCREEN_WIDTH
    ldy dsw_upper_height
    jsr ulwin_resize
    ; Reset cursor to top-left
    ldx #0
    ldy #0
    lda window_upper
    jsr ulwin_putcursor
    ; V3: also clear upper window on every split
    chkver V3, @done
    lda window_upper
    jsr ulwin_clear
    bra @done

@create_upper:
    ; Open upper window
    stz gREG::r0L               ; left = 0
    ; Top row depends on version: V1-V3 at row 1 (below status), V4+ at row 0
    chkver V1|V2|V3, @upper_at_top
    lda #1                      ; V1-V3: below status bar
    bra @set_upper_top
@upper_at_top:
    lda #0                      ; V4+: at top of screen
@set_upper_top:
    sta gREG::r0H
    lda #SCREEN_WIDTH
    sta gREG::r1L               ; width = 80
    lda dsw_upper_height
    sta gREG::r1H               ; height
    lda zmwin_slots + ZMWIN_FG  ; inherit main window colors
    sta gREG::r2L
    lda zmwin_slots + ZMWIN_BG
    sta gREG::r2H
    stz gREG::r4L
    stz gREG::r4H               ; no border
    jsr ulwin_open
    sta window_upper
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    ; Copy main window colors/style to upper slot
    lda zmwin_slots + ZMWIN_FG
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_FG
    lda zmwin_slots + ZMWIN_BG
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_BG
    lda zmwin_slots + ZMWIN_STYLE
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_STYLE
    ; Clear and reset cursor
    lda window_upper
    jsr ulwin_clear
    ldx #0
    ldy #0
    lda window_upper
    jsr ulwin_putcursor

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

    ; Handle foreground: 0=current, 1=default, 2-12=Z-machine color
    lda operand_0+1
    beq @fg_current
    cmp #1
    beq @fg_default
    tax
    lda zmcolor_to_ulcolor,x
    bra @fg_done
@fg_default:
    lda #DEFAULT_FG
    bra @fg_done
@fg_current:
    lda zmwin_slots + ZMWIN_FG
@fg_done:
    sta sc_new_fg

    ; Handle background: 0=current, 1=default, 2-12=Z-machine color
    lda operand_1+1
    beq @bg_current
    cmp #1
    beq @bg_default
    tax
    lda zmcolor_to_ulcolor,x
    bra @bg_done
@bg_default:
    lda #DEFAULT_BG
    bra @bg_done
@bg_current:
    lda zmwin_slots + ZMWIN_BG
@bg_done:
    sta sc_new_bg

    ; Store to both window slots
    lda sc_new_fg
    sta zmwin_slots + ZMWIN_FG
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_FG
    lda sc_new_bg
    sta zmwin_slots + ZMWIN_BG
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_BG

    ; Update UniLib color for main window
    ldy #0
    lda window_main
    jsr zmwin_setcolor
    ; Update UniLib color for upper window (if it exists)
    lda zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    cmp #$FF
    beq @done
    ldy #ZMWIN_SIZE
    lda window_upper
    jsr zmwin_setcolor

@done:
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

.bss

; show_status temps
ss_g2:          .res 2
ss_g3:          .res 2
ss_save_op0:    .res 2
ss_timeflags:   .res 1

; do_split_window temps
dsw_upper_height: .res 1

; op_erase_window temp
ew_temp:         .res 1

; op_set_colour temps
sc_new_fg:       .res 1
sc_new_bg:       .res 1
