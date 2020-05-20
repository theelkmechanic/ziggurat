.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.bss

win_buffers: .res 80*3*4
buf_off: .res 2

.code

; win_init - Initialize the window system
.proc win_init
    ; Initialize the VERA
    jsr vera_init

    ; Reserve room for MAX_WINDOWS window entries at top of memory and clear it out
    sec
    jsr MEMTOP
    sec
    txa
    sbc #MAX_WINDOWS * 16
    tax
    tya
    sbc #0
    tay
    stx win_tbl
    sty win_tbl+1
    stx win_ptr
    sty win_ptr+1
    clc
    jsr MEMTOP
    lda #0
    ldy #MAX_WINDOWS * 16
@3: sta (win_tbl),y
    dey
    bne @3
    rts
.endproc

; win_open - Open a new window
; Out:  a           - Window ID (0-31), failure if negative
.proc win_open
    ; Look for a free window slot
    phy
    lda #0
@1: tay
    lda (win_tbl),y
    and #WIN_ISOPEN
    beq @found
    tya
    clc
    adc #16
    cmp #MAX_WINDOWS * 16
    bcc @1

    ; Ran out of slots
    lda #$ff
    ply
    rts

@found:
    ; Set the open flag
    lda #WIN_ISOPEN
    sta (win_tbl),y

    ; Divide by 16 to get the window ID
    tya
    lsr
    lsr
    lsr
    lsr

    ; And clear the rest of the window entry
    pha
    tya
    clc
    adc win_tbl
    sta win_ptr
    lda win_tbl+1
    adc #0
    sta win_ptr+1
    lda #0
    tay
@clear_loop:
    iny
    sta (win_ptr),y
    cpy #.sizeof(Window)
    bcc @clear_loop
    pla
    ply
    rts
.endproc

; win_close - Close a window
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_close
    ; Get the window table entry pointer
    jsr win_getptr

    ; And clear the flags
    lda #0
    sta (win_ptr)
    rts
.endproc

; win_getflags - Get window flags
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  x           - Flags
.proc win_getflags
    ; Get the window table entry pointer
    jsr win_getptr

    ; Read the flags byte
    pha
    lda (win_ptr)
    tax
    pla
    rts
.endproc

; win_setwrap - Set window wrap flag
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Wrap flag (0 = disabled, non-zero = enabled)
.proc win_setwrap
    ; Get the window table entry pointer
    jsr win_getptr

    ; Are we setting or clearing the flag?
    pha
    lda (win_ptr)
    cpx #0
    beq @clearit
    ora #WIN_WRAP
    .byte $2c
@clearit:
    and #($FF & ~WIN_WRAP)
    sta (win_ptr)
    pla
    rts
.endproc

; win_setscroll - Set window scroll flag
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Scroll flag (0 = disabled, non-zero = enabled)
.proc win_setscroll
    ; Get the window table entry pointer
    jsr win_getptr

    ; Are we setting or clearing the flag?
    pha
    lda (win_ptr)
    cpx #0
    beq @clearit
    ora #WIN_SCROLL
    .byte $2c
@clearit:
    and #($FF & ~WIN_SCROLL)
    sta (win_ptr)
    pla
    rts
.endproc

; win_setstyle - Set window style flags
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Style flags
.proc win_setstyle
    ; Get the window table entry pointer
    jsr win_getptr

    ; Clear old flags
    pha
    lda (win_ptr)
    and #($FF & ~WIN_STYLEFLAGS)
    sta (win_ptr)

    ; And set new ones
    txa
    and #WIN_STYLEFLAGS
    ora (win_ptr)
    sta (win_ptr)
    pla
    rts
.endproc

; win_getpos - Get window top-left position
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  x           - Window left position (0-79)
;       y           - Window top position (0-59)
.proc win_getpos
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to left/top and load
    ldy #Window::left
    bra win_get_word_to_xy
.endproc

; win_getsize - Get window width/height
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  x           - Window width (1-79)
;       y           - Window height (1-59)
.proc win_getsize
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to width/height and load
    ldy #Window::width
    bra win_get_word_to_xy
.endproc

; win_getcursor - Get window cursor x/y
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  x           - Window cursor x position (0 to width-1)
;       y           - Window height (0 to height-1)
.proc win_getcursor
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to cursor x/y and load
    ldy #Window::cur_x

    ; FALL THRU INTENTIONAL
.endproc

.proc win_get_word_to_xy
    pha
    lda (win_ptr),y
    tax
    iny
    lda (win_ptr),y
    tay
    pla
    rts
.endproc

; win_setbuffer - Clear window buffer flag
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Buffering flag (0 = disabled, non-zero = enabled)
.proc win_setbuffer
    ; Get the window table entry pointer
    jsr win_getptr

    ; Are we turning on buffering?
    phx
    pha
    lda (win_ptr)
    cpx #0
    bne @buffer_on

    ; If we're turning off buffering, flush the buffer now just in case
    bit #WIN_BUFFER
    beq @buffer_off
    jsr curwin_flushbuffer
    bra @buffer_off

@buffer_on:
    ; Is buffering already on?
    bit #WIN_BUFFER
    bne @done

    ; Find the buffer to use (win_buffers + (80*4) * window ID). ID * 320 is the same as ID * 256 + ID * 64,
    ; so we can shift ID right 6 bits, and then add ID to the high byte.
    pla
    pha
    tax
    stz buf_off+1
    asl
    rol buf_off+1
    asl
    rol buf_off+1
    asl
    rol buf_off+1
    asl
    rol buf_off+1
    asl
    rol buf_off+1
    asl
    rol buf_off+1
    sta buf_off
    txa
    clc
    adc buf_off+1
    sta buf_off+1

    ; Then add the buffer base and store in the window buffer address
    phy
    ldy #Window::bufptr
    iny
    lda #<win_buffers
    clc
    adc buf_off
    sta (win_ptr),y
    lda #>win_buffers
    adc buf_off
    dey
    sta (win_ptr),y
    ply

    ; Set the buffering flag
    lda (win_ptr)
    ora #WIN_BUFFER
    .byte $2c ; Skip next and

@buffer_off:
    ; Clear the buffering flag
    and #($FF & ~WIN_BUFFER)
    sta (win_ptr)
@done:
    pla
    plx
    rts
.endproc

; win_setpos - Set window top-left position
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Window left position (0-79)
;       y           - Window top position (0-59)
.proc win_setpos
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to left/top and store
    pha
    phy
    lda #Window::left
    bra win_set_word_from_xy
.endproc

; win_setsize - Set window width/height
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Window width (1-79)
;       y           - Window height (1-59)
.proc win_setsize
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to width/height and store
    pha
    phy
    lda #Window::width
    bra win_set_word_from_xy
.endproc

; win_setcursor - Set window cursor x/y
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Window cursor x position (0 to width-1)
;       y           - Window height (0 to height-1)
.proc win_setcursor
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to cursor x/y and store
    pha
    phy
    lda #Window::cur_x

    ; FALL THRU INTENTIONAL
.endproc

.proc win_set_word_from_xy
    pha
    tya
    ply
    iny
    sta (win_ptr),y
    txa
    dey
    sta (win_ptr),y
    ply
    pla
    rts
.endproc

; win_getcolor - Get window foreground/background colors
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  x           - Window colors (high nibble = background, low nibble = foreground)
.proc win_getcolor
    ; Get the window table entry pointer
    jsr win_getptr

    ; And read the colors
    pha
    phy
    ldy #Window::colors

    ; FALL THRU INTENTIONAL
.endproc

read_x_from_y:
    lda (win_ptr),y
    tax
    ply
    pla
    rts

; win_getscrlcnt - Get window scroll count
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  x           - Window scroll count (# of lines scrolled)
.proc win_getscrlcnt
    ; Get the window table entry pointer
    jsr win_getptr

    ; And read the scroll count
    pha
    phy
    ldy #Window::scrlcnt
    bra read_x_from_y
.endproc

; win_resetscrlcnt - Reset the window scroll count to 0
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_resetscrlcnt
    ; Get the window table entry pointer
    jsr win_getptr

    ; And reset the scroll count
    pha
    phy
    ldy #Window::scrlcnt
    lda #0
    bra set_y_from_a
.endproc

; win_setcolor - Set window foreground/background colors
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Window colors (high nibble = background, low nibble = foreground)
.proc win_setcolor
    ; Get the window table entry pointer
    jsr win_getptr

    ; And store the colors
    pha
    phy
    ldy #Window::colors
    txa

    ; FALL THRU INTENTIONAL
.endproc

set_y_from_a:
    sta (win_ptr),y
    ply
    pla
    rts

; win_clear - Clear specified window to its fg/bg colors
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_clear
    ; Get the window table entry pointer
    jsr win_getptr

    ; Clear all the lines
    pha
    phx
    phy
    ldy #Window::height
    lda (win_ptr),y
    tay
    bra @2
@1: phy
    jsr curwin_clearline
    ply
@2: dey
    bpl @1

    ; And set cursor position back to 0,0
    ldy #Window::cur_x
    lda #0
    sta (win_ptr),y
    iny
    sta (win_ptr),y
    ply
    plx
    pla
    rts
.endproc


; win_erasecurrtoeol - Erase from the current cursor position to the end of its line
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_erasecurrtoeol
    ; Get the window table entry pointer
    jsr win_getptr

    ; Calculate the cursor position address and put in VERA::ADDR0
    pha
    phx
    phy
    ldy #Window::cur_x
    lda (win_ptr),y
    tax
    iny
    lda (win_ptr),y
    tay
    jsr curwin_calcaddr
    lda VERA::CTRL
    ora #$01
    sta VERA::CTRL
    lda #$10
    sta VERA::ADDR+2
    stx VERA::ADDR+1
    sty VERA::ADDR
    lda VERA::CTRL
    and #$fe
    sta VERA::CTRL
    lda #$10
    sta VERA::ADDR+2
    txa
    ora #$20
    sta VERA::ADDR+1
    sty VERA::ADDR

    ; Now get the remaining width and write that many spaces to the window
    ldy #Window::width
    lda (win_ptr),y
    ldy #Window::cur_x
    sec
    sbc (win_ptr),y
    tax
    ldy #Window::colors
    lda (win_ptr),y
    ldy #' '
@1: dex
    bpl @2
    stz VERA::DATA0
    stz VERA::DATA0
    sty VERA::DATA1
    sta VERA::DATA1
    bra @1
@2: ply
    plx
    pla
    rts
.endproc
