.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.code

; win_init - Initialize the window system
;
; This initializes the VERA to display in one of two modes:
;   Text mode (default): 80x30x256 text, used for displaying text. Uses both layers so we can double the # of font chars.
;       - Text mode, 1bpp, T256C=1
;       - Map size = 128x32, tile size = 8x16
;       - Layer 0 (extras) map is from $02000-03fff, line stride is 256, tile set is at $05000
;       - Layer 1 (normal) map is from $00000-01fff, line stride is 256, tile set is at $04000
;   Graphics mode: 640x200x16 bitmap, used for displaying graphics in V6 games that need it. (TODO)
;       - Bitmap mode, 4bpp, TILEW=1,TILEH=0
;       - Screen buffer is from $00000-$1f3ff
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
    lda #WIN_ISOPEN | WIN_WRAP
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
    .byte $42
@clearit:
    and #($FF & ~WIN_WRAP)
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
    lda #Window::left
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
    bra win_get_word_to_xy
.endproc

; win_getfont - Get window font
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  x           - Font (high byte)
;       y           - Fond (low byte)
win_getfont:
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to font and load
    ldy #Window::font
win_get_word_to_xy:
    pha
    lda (win_ptr),y
    tax
    iny
    lda (win_ptr),y
    tay
    pla
    rts

; win_disablebuffer - Clear window buffer flag
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Wrap flag (0 = disabled, non-zero = enabled)
.proc win_disablebuffer
    ; Get the window table entry pointer
    jsr win_getptr

    ; If we're buffering, flush the buffer now just in case
    pha
    lda (win_ptr)
    bit #WIN_BUFFER
    beq @noflush
    jsr curwin_flushbuffer

@noflush:
    ; Clear the buffering flag
    and #($FF & ~WIN_BUFFER)
    sta (win_ptr)
    pla
    rts
.endproc

; win_flushbuffer - Print any text in a window's buffer to the screen
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_flushbuffer
    ; Get the window table entry pointer and flush it
    jsr win_getptr

    ; FALL THRU INTENTIONAL
.endproc

; win_enablebuffer - Enable buffering and set buffer pointer
; In:   a           - Window ID (0-31)
;       x           - Buffer pointer (high byte)
;       y           - Buffer pointer (low byte)
.proc win_enablebuffer
    ; Get the window table entry pointer
    jsr win_getptr

    ; Set the buffering flag
    pha
    lda (win_ptr)
    ora #WIN_BUFFER
    sta (win_ptr)

    ; Reset the buffer offset
    phy
    ldy #Window::bufoff
    lda #0
    sta (win_ptr),y
    ply
    phy

    ; Skip to buffer pointer and store
    lda #Window::bufptr
    bra win_set_word_from_xy
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
    bra win_set_word_from_xy
.endproc

; win_setfont - Set window font
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Font (high byte)
;       y           - Font (low byte)
win_setfont:
    ; Get the window table entry pointer
    jsr win_getptr

    ; Skip to cursor x/y and store
    pha
    phy
    lda #Window::font
win_set_word_from_xy:
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
    lda (win_ptr),y
    tax
    ply
    pla
    rts
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
    sta (win_ptr),y
    ply
    pla
    rts
.endproc

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
    dey
@1: phy
    jsr curwin_clearline
    ply
    dey
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
