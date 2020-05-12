.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.bss

putch_utf16: .res 2
putch_flags: .res 1 ; $80 = advance after print, $40 = no buffering

newline_winheight: .res 1

bufferchar_chlo: .res 1
bufferchar_chhi: .res 1
bufferchar_font: .res 1
bufferchar_colors: .res 1
bufferchar_offsetx4: .res 2

drawchar_chlo: .res 1
drawchar_chhi: .res 1
drawchar_font: .res 1
drawchar_colors: .res 1
drawchar_line: .res 1
drawchar_column: .res 1

drawchar_normal: .res 1
drawchar_extra: .res 1
drawchar_colors_extra: .res 1
drawchar_colors_reverse: .res 1
drawchar_color_flags: .res 1

.code

; curwin_putchr_nobuffer - Write a Unicode character to the current window, flush and bypass buffer if enabled
; In:   x/y         - UTF-16 character to write (x=hi, y=lo)
;       carry       - set to advance cursor
.proc curwin_putchr_nobuffer
    ; Set the no buffering flag
    lda #$80
    sta putch_flags
    bra curwin_putchr
.endproc

.import printhex

; win_putchr - Put a Unicode character in the specified window at the current cursor and optionally advance
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x/y         - UTF-16 character to write (x=hi, y=lo)
;       carry       - set to advance cursor
.proc win_putchr
    ; Get the window table entry pointer
    php
    jsr win_getptr
    plp

    ; Clear the no buffering flag
    stz putch_flags

    ; FALL THRU INTENTIONAL
.endproc

; curwin_putchr - Write a Unicode character to the current window
; In:   x/y         - UTF-16 character to write (x=hi, y=lo)
;       carry       - set to advance cursor
.proc curwin_putchr
    ; Save registers and the character we're printing
    pha
    phx
    phy
    sty putch_utf16
    stx putch_utf16+1

    ; Set the advance flag
    ror putch_flags

    ; Check for special characters
    cpx #0
    bne @printable
    cpy #32
    bcc @special
    cpy #127
    bcc @printable
    cpy #160
    bcs @printable

@special:
    ; Right now the only specials are carriage return/line feed (CR/LF, U+000d/U+000a), either one of
    ; which moves the cursor to the start of the next line (scrolling if necessary); backspace (U+0008),
    ; which moves the cursor back one space and erases the character there; and tab (U+0009), which does
    ; an indent when at the beginning of a line, and otherwise prints a space.
    cpy #13
    beq @do_crlf

@do_crlf:
    ; If not both buffering and wrapping, can just do newline
    ldy #0
    lda (win_ptr),y
    and #WIN_BUFFER | WIN_WRAP
    cmp #WIN_BUFFER | WIN_WRAP
    bne @do_newline

    ; See if there's more in the buffer than will fit on the current line
    ldy #Window::cur_x
    lda (win_ptr),y
    ldy #Window::bufoff
    clc
    adc (win_ptr),y
    ldy #Window::width
    cmp (win_ptr),y
    bcc @do_newline

    ; Buffered characters won't fit, so we need to do a newline before we flush, and then we can
    ; do the regular newline which will flush the buffer first
    jsr curwin_newline_noflush

@do_newline:
    jsr curwin_newline
    bra @done

@check_bksp:
    cpy #8
    bne @check_tab

    ; TODO: Back the cursor up and erase the character at its new location

@check_tab:
    cpy #9
    bne @done

    ; Tab at beginning of line, space otherwise
    ldy #Window::cur_x
    lda (win_ptr),y
    beq @dotab
@print_space:
    ldy #' '
    sty putch_utf16
    bra @printable
@dotab:
    lda #5
    sta (win_ptr),y

@done:
    ply
    plx
    pla
    rts

@printable:
    ; Don't print past the width of the window
    ldy #Window::cur_x
    lda (win_ptr),y
    ldy #Window::width
    cmp (win_ptr),y
    lda (win_ptr)
    bcc @printit

    ; If we hit the window width, exit it we're not wrapping
    and #WIN_WRAP
    beq @done

    ; Wrap to next line
    jsr curwin_newline

@printit:
    ; Get the window colors and font
    pha
    ldy #Window::colors
    lda (win_ptr),y
    tax
    ldy #Window::font
    lda (win_ptr),y
    tay
    pla

    ; Now check to see if we should be buffering
    bit putch_flags
    bvs @actuallyprint
    and #WIN_BUFFER
    beq @actuallyprint

    ; Buffer the character
    lda putch_utf16
    sta bufferchar_chlo
    lda putch_utf16+1
    sta bufferchar_chhi
    stx bufferchar_colors
    sty bufferchar_font
    jsr bufferchar

    ; See if we're supposed to print the character
    bcs @done
    ldx bufferchar_colors
    ldy bufferchar_font

@actuallyprint:
    ; Print our character glyph on the screen at the correct location
    stx drawchar_colors
    sty drawchar_font
    ldy #Window::top
    lda (win_ptr),y
    ldy #Window::cur_y
    clc
    adc (win_ptr),y
    sta drawchar_line
    ldy #Window::left
    lda (win_ptr),y
    ldy #Window::cur_x
    clc
    adc (win_ptr),y
    sta drawchar_column
    lda putch_utf16
    sta drawchar_chlo
    lda putch_utf16+1
    sta drawchar_chhi
    jsr drawchar

@check_advance:
    ; Advance the cursor one space if we're supposed to
    bit putch_flags
    bpl @jump_done
    ldy #Window::cur_x
    lda (win_ptr),y
    inc
    sta (win_ptr),y
@jump_done:
    jmp @done
.endproc

.proc curwin_newline
    ; Flush the buffer first
    jsr curwin_flushbuffer

    ; FALL THRU INTENTIONAL
.endproc

.proc curwin_newline_noflush
    ; Move the cursor to the beginning of the next line
    ldy #Window::cur_x
    lda #0
    sta (win_ptr),y
    ldy #Window::height
    lda (win_ptr),y
    sta newline_winheight
    ldy #Window::cur_y
    lda (win_ptr),y
    inc

    ; If we hit the end of the window, scroll it
    cmp newline_winheight
    bcc @1
    jmp curwin_scroll
@1: sta (win_ptr),y
    rts
.endproc

; bufferchar - Handle character buffering in the current window
; In:   bufferchar_chlo     - UTF-16 character (low byte)
;       bufferchar_chhi     - UTF-16 character (high byte)
;       bufferchar_font     - Font (3 = Z-machine Font 3, anything else = normal)
;       bufferchar_colors   - Text colors (foreground = low nibble, background = high nibble)
; Out:  carry               - Set if we buffered the character, clear means print and advance
.proc bufferchar
    ; If it's a space, we need to:
    ;   * If there isn't room on the current line for the buffer, do a newline without flush
    ;   * Flush the current buffer
    ;   * If there is still room on the line, print the space
    ;   * Otherwise do a newline and don't print the space
    lda bufferchar_chhi
    bne @check_buffer_space
    lda bufferchar_chlo
    cmp #32
    bne @check_buffer_space

    ; See if there's anything in the buffer and if not, just buffer the space
    ldy #Window::bufoff
    lda (win_ptr),y
    beq @check_buffer_space

    ; See if there's room for the buffer contents on the current line
    ldy #Window::cur_x
    clc
    adc (win_ptr),y
    ldy #Window::width
    cmp (win_ptr),y
    bcc @flushit
    beq @flushit

    ; Do a newline without flushing the buffer
    jsr curwin_newline_noflush

@flushit:
    ; Flush the buffer
    jsr curwin_flushbuffer

    ; Reset current character to a space
    lda #' '
    sta putch_utf16
    stz putch_utf16+1

    ; See if there's room for a space on the line after flushing
    ldy #Window::cur_x
    lda (win_ptr),y
    ldy #Window::width
    cmp (win_ptr),y
    bcc @room_for_space ; Carry is already clear so we can just return

    ; Space at end of full line, so just do newline and don't print
    jsr curwin_newline
    sec

@room_for_space:
    rts

@check_buffer_space:
    ; Get buffer pointers ready
    ldy #Window::bufptr
    lda (win_ptr),y
    sta buf_ptr+1
    iny
    lda (win_ptr),y
    sta buf_ptr

    ; Check if we have space left on the line including what's in the buffer
    iny
    lda (win_ptr),y
    ldy #Window::width
    cmp (win_ptr),y
    bcc @check_add_to_buffer

    ; No space left, so flush the buffer and move to the next line, and then we can definitely add
    ; the character to the buffer
    jsr curwin_newline

    ; Retry the buffering now that it's empty
    bra @check_buffer_space

@check_add_to_buffer:
    ; Advance our pointer by the offset (which should be in a) * 4
    stz bufferchar_offsetx4+1
    asl
    rol bufferchar_offsetx4+1
    asl
    rol bufferchar_offsetx4+1
    sta bufferchar_offsetx4
    lda buf_ptr
    clc
    adc bufferchar_offsetx4
    sta buf_ptr
    lda buf_ptr+1
    adc bufferchar_offsetx4+1
    sta buf_ptr+1

@add_to_buffer:
    ; Save the character info in the buffer
    ldy #1
    lda bufferchar_chlo
    sta (buf_ptr)
    lda bufferchar_chhi
    sta (buf_ptr),y
    iny
    lda bufferchar_colors
    sta (buf_ptr),y
    iny
    lda bufferchar_font
    sta (buf_ptr),y

    ; And increment the buffer offset
    ldy #Window::bufoff
    lda (win_ptr),y
    inc
    sta (win_ptr),y

    ; Buffered the character, so don't advance the cursor
    sec
    rts
.endproc

; win_flushbuffer - Print any text in a window's buffer to the screen
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_flushbuffer
    ; Get the window table entry pointer and flush it
    jsr win_getptr

    ; FALL THRU INTENTIONAL
.endproc

; curwin_flushbuffer - Print any text in the current window's buffer to the screen
.proc curwin_flushbuffer
@buf_off = $760 

    ; Make sure we're actually buffering
    pha
    phx
    phy
    lda (win_ptr)
    and #WIN_BUFFER
    beq @done

    ; Get the buffer pointer into a zp register and save the buffer offset and colors
    ldy #Window::bufptr
    lda (win_ptr),y
    sta buf_ptr+1
    iny
    lda (win_ptr),y
    sta buf_ptr
    iny
    lda (win_ptr),y
    sta @buf_off

    ; And reset the buffer offset since we're going to empty it
    lda #0
    sta (win_ptr),y

    ; Now we need to loop through all the buffer characters and print them
@flush_loop:
    ; See if we're done
    dec @buf_off
    bmi @done

    ; Print a character
    ldy #0
    lda (buf_ptr),y
    sta drawchar_chlo
    iny
    lda (buf_ptr),y
    sta drawchar_chhi
    iny
    lda (buf_ptr),y
    sta drawchar_colors
    iny
    lda (buf_ptr),y
    sta drawchar_font
    ldy #Window::top
    lda (win_ptr),y
    clc
    ldy #Window::cur_y
    adc (win_ptr),y
    sta drawchar_line
    ldy #Window::left
    lda (win_ptr),y
    clc
    ldy #Window::cur_x
    adc (win_ptr),y
    sta drawchar_column
    jsr drawchar
    ldy #Window::cur_x
    lda (win_ptr),y
    inc
    sta (win_ptr),y

    ; Step to next buffer entry (4 bytes)
    lda buf_ptr
    clc
    adc #4
    sta buf_ptr
    lda buf_ptr+1
    adc #0
    sta buf_ptr+1
    bra @flush_loop

@done:
    ply
    plx
    pla
    rts
.endproc

; drawchar - Draw a character glyph onto the screen
; In:   drawchar_chlo       - UTF-16 character (low byte)
;       drawchar_chhi       - UTF-16 character (high byte)
;       drawchar_font       - Font (3 = Z-machine Font 3, anything else = normal)
;       drawchar_colors     - Text colors (foreground = low nibble, background = high nibble)
;       drawchar_line       - Line to draw character
;       drawchar_column     - Column to draw character
.proc drawchar
    ; Make sure we're drawing on screen somewhere
    pha
    phx
    phy
    lda drawchar_line
    cmp #30
    bcs @done
    lda drawchar_column
    cmp #80
    bcs @done

    ; Find the fontmap entry for our character
    lda drawchar_colors
    sta drawchar_colors_extra
    ldy drawchar_chlo
    ldx drawchar_chhi
    lda drawchar_font
    jsr utf_find_charinfo
    stx drawchar_normal
    sty drawchar_extra
    bcs @foundit

@done:
    ply
    plx
    pla
    rts

@foundit:
    ; See if we need to reverse colors
    sta drawchar_color_flags
    lda #$20
    bit drawchar_color_flags
    bne @need_reverse
    bvc @check_trans

@need_reverse:
    ; Swap the colors
    php
    lda drawchar_colors
    asl
    asl
    asl
    asl
    sta drawchar_colors_reverse
    lda drawchar_colors
    lsr
    lsr
    lsr
    lsr
    ora drawchar_colors_reverse

    ; Put swapped colors where we need them
    plp
    bvc @check_reverse_extras
    sta drawchar_colors
@check_reverse_extras:
    beq @draw_glyphs
    sta drawchar_colors_extra

@check_trans:
    ; Is the layer 1 background supposed to be transparent?
    bpl @draw_glyphs

    ; If we reversed layer 1, set normal color foreground to transparent
    lda drawchar_colors
    bvc @trans_bg
    and #$f0
    bra @save_trans

@trans_bg:
    ; Otherwise set normal color background to transparent (0)
    and #$0f
@save_trans:
    sta drawchar_colors

@draw_glyphs:
    ; Set the location to write (normal page)
    lda drawchar_column
    asl
    tax
    ldy drawchar_line
    lda VERA::CTRL
    and #$fe
    sta VERA::CTRL
    lda #$10
    sta VERA::ADDR+2
    sty VERA::ADDR+1
    stx VERA::ADDR

    ; Set the location to write (extras page)
    lda VERA::CTRL
    ora #$01
    sta VERA::CTRL
    lda #$10
    sta VERA::ADDR+2
    tya
    clc
    adc #$20
    sta VERA::ADDR+1
    stx VERA::ADDR

    ; Write the normal character glyph and color
    lda drawchar_normal
    sta VERA::DATA0
    lda drawchar_colors
    sta VERA::DATA0

    ; Write the extras character glyph and color
    lda drawchar_extra
    sta VERA::DATA1
    beq @nobackcolor
    lda drawchar_colors_extra
    .byte $2c
@nobackcolor:
    lda #0
    sta VERA::DATA1
    clc
    jmp @done
.endproc
