.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.bss

putch_utf16: .res 2
putch_flags: .res 1 ; $80 = advance after print, $40 = no buffering

newline_winheight: .res 1

bufferchar_chlo: .res 1
bufferchar_chhi: .res 1
bufferchar_colors: .res 1
bufferchar_offset: .res 1

drawchar_chlo: .res 1
drawchar_chhi: .res 1
drawchar_colors: .res 1
drawchar_line: .res 1
drawchar_column: .res 1

drawchar_base: .res 1
drawchar_overlay: .res 1
drawchar_flags: .res 1

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

    ; Don't do anything in zero-height windows
    ldy #Window::height
    lda (win_ptr),y
    beq @done
    ldy putch_utf16

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
    lda (win_ptr)
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
    ; See if we actually have glyphs for it
    ldy putch_utf16
    ldx putch_utf16+1
    jsr utf_find_charinfo
    bcc @done

    ; Don't print past the width of the window
    ldy #Window::cur_x
    lda (win_ptr),y
    ldy #Window::width
    cmp (win_ptr),y
    lda (win_ptr)
    bcc @printit

    ; If we hit the window end, exit if we're not scrolling
    bit #WIN_SCROLL
    bne @check_wrap
    ldy #Window::cur_y
    lda (win_ptr),y
    inc
    ldy #Window::height
    cmp (win_ptr),y
    bcs @done
    lda (win_ptr)

@check_wrap:
    ; If we hit the window width, exit if we're not wrapping
    bit #WIN_WRAP
    beq @done

    ; Wrap to next line
    jsr curwin_newline

@printit:
    ; Get the window colors
    pha
    ldy #Window::colors
    lda (win_ptr),y
    tax

    ; Apply the style to the colors
    lda (win_ptr)
    bit #WINSTYLE_ITALIC
    beq @checkbold

    ; Italic style, so map the foreground color
    txa
    and #$f0
    sta drawchar_colors
    txa
    and #$0f
    tax
    lda colormap_italic,x
    ora drawchar_colors
    tax
    bra @done_style

@checkbold:
    bit #WINSTYLE_BOLD
    beq @checkreverse

    ; Bold style, so map the foreground color
    txa
    and #$f0
    sta drawchar_colors
    txa
    and #$0f
    tax
    lda colormap_bold,x
    ora drawchar_colors
    tax
    bra @done_style

@checkreverse:
    bit #WINSTYLE_REVERSE
    beq @done_style

    ; Reverse video style, so swap colors
    txa
    asl
    asl
    asl
    asl
    pha
    txa
    lsr
    lsr
    lsr
    lsr
    sta drawchar_colors
    pla
    ora drawchar_colors
    tax

@done_style:
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
    jsr bufferchar

    ; See if we're supposed to print the character
    bcs @jump_done
    ldx bufferchar_colors

@actuallyprint:
    ; Print our character glyph on the screen at the correct location
    stx drawchar_colors
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

    ; If we hit the end of the window, scroll it if we're allowed
    cmp newline_winheight
    bcc @1
    pha
    lda (win_ptr)
    and #WIN_SCROLL
    tax
    pla
    cpx #0
    beq @2
    jmp curwin_scroll
@1: sta (win_ptr),y
@2: rts
.endproc

; bufferchar - Handle character buffering in the current window
; In:   bufferchar_chlo     - UTF-16 character (low byte)
;       bufferchar_chhi     - UTF-16 character (high byte)
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
    ; Find the next empty space in the buffer (offset*3)
    sta bufferchar_offset
    asl
    clc
    adc bufferchar_offset
    tay

    ; Save the character info in the buffer
    lda bufferchar_chlo
    sta (buf_ptr),y
    iny
    lda bufferchar_chhi
    sta (buf_ptr),y
    iny
    lda bufferchar_colors
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
    sta bufferchar_offset

    ; And reset the buffer offset since we're going to empty it
    lda #0
    sta (win_ptr),y

    ; Now we need to loop through all the buffer characters and print them
    ldy #0
@flush_loop:
    ; See if we're done
    dec bufferchar_offset
    bmi @done

    ; Print a character
    lda (buf_ptr),y
    sta drawchar_chlo
    iny
    lda (buf_ptr),y
    sta drawchar_chhi
    iny
    lda (buf_ptr),y
    sta drawchar_colors
    iny
    phy
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
    ply
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
    ldy drawchar_chlo
    ldx drawchar_chhi
    jsr utf_find_charinfo
    bcs @foundit

@done:
    ply
    plx
    pla
    rts

@foundit:
    ; See if we need to reverse colors
    stx drawchar_base
    sty drawchar_overlay
    sta drawchar_flags
    bit #$80
    beq @draw_glyphs

    ; Swap the colors
    lda drawchar_colors
    asl
    asl
    asl
    asl
    pha
    lda drawchar_colors
    lsr
    lsr
    lsr
    lsr
    sta drawchar_colors
    pla
    ora drawchar_colors
    sta drawchar_colors

@draw_glyphs:
    ; Put the foregroud color in the flags high nibble
    lda drawchar_flags
    and #$0f
    sta drawchar_flags
    lda drawchar_colors
    asl
    asl
    asl
    asl
    ora drawchar_flags
    sta drawchar_flags

    ; Set the location to write (base page)
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

    ; Set the location to write (overlay page)
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
    lda drawchar_base
    sta VERA::DATA0
    lda drawchar_colors
    sta VERA::DATA0

    ; Write the extras character glyph and color
    lda drawchar_overlay
    sta VERA::DATA1
    lda drawchar_flags
    sta VERA::DATA1
    clc
    jmp @done
.endproc

.rodata

colormap_bold:
    .byte 0, 0, W_BLACK, W_MAGENTA, W_WHITE, W_WHITE, W_CYAN, W_MAGENTA, W_WHITE, W_WHITE, W_WHITE, W_MGREY, W_BLACK, 0, 0, 0
colormap_italic:
    .byte 0, 0, W_DGREY, W_YELLOW, W_YELLOW, W_GREEN, W_YELLOW, W_CYAN, W_GREEN, W_LGREY, W_YELLOW, W_MGREY, W_BLUE, 0, 0, 0
