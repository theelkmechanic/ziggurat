; zwin.s - Windies-to-UniLib adapter (shim)
;
; Implements the win_* API from windies.inc using UniLib ulwin_* calls.
; Keeps all ZPU interpreter code unchanged.

.include "ziggurat.inc"

MAX_WINDOWS = 4

; Per-window shim state layout (5 bytes each)
ZWIN_FLAGS      = 0     ; WIN_BUFFER | WIN_WRAP | WIN_SCROLL | WIN_STYLEFLAGS
ZWIN_SCRLCNT    = 1     ; Lines scrolled since last [MORE] reset
ZWIN_BUFOFF     = 2     ; Characters in word-wrap buffer
ZWIN_BASE_FG    = 3     ; Base foreground color (before style mapping)
ZWIN_BASE_BG    = 4     ; Base background color (before style mapping)
ZWIN_STATE_SIZE = 5

.code

; ============================================================================
; Internal: find shim state offset for window handle
; In:  A = window handle
; Out: Y = offset into zwin_state (slot * ZWIN_STATE_SIZE)
;      A preserved
; ============================================================================
zwin_getstate:
    cmp zwin_handles+0
    beq @s0
    cmp zwin_handles+1
    beq @s1
    cmp zwin_handles+2
    beq @s2
    ldy #3*ZWIN_STATE_SIZE
    rts
@s0:
    ldy #0
    rts
@s1:
    ldy #1*ZWIN_STATE_SIZE
    rts
@s2:
    ldy #2*ZWIN_STATE_SIZE
    rts

; ============================================================================
; win_open - Open a new window with default parameters
; Out: A = window handle
; ============================================================================
.proc win_open
    phx
    phy
    stz gREG::r0L
    stz gREG::r0H
    lda #80
    sta gREG::r1L
    lda #30
    sta gREG::r1H
    lda #ULCOLOR::LGREY
    sta gREG::r2L
    lda #ULCOLOR::BLACK
    sta gREG::r2H
    stz gREG::r3L
    stz gREG::r3H
    stz gREG::r4H
    jsr ulwin_open

    ; Register in a free handle slot
    ldx #0
@find:
    ldy zwin_handles,x
    bmi @got
    inx
    cpx #MAX_WINDOWS
    bcc @find
    ldx #0                  ; fallback to slot 0
@got:
    sta zwin_handles,x

    ; Initialize shim state
    jsr zwin_getstate
    pha
    lda #0
    sta zwin_state + ZWIN_FLAGS,y
    sta zwin_state + ZWIN_SCRLCNT,y
    sta zwin_state + ZWIN_BUFOFF,y
    lda #ULCOLOR::LGREY
    sta zwin_state + ZWIN_BASE_FG,y
    lda #ULCOLOR::BLACK
    sta zwin_state + ZWIN_BASE_BG,y
    pla

    ply
    plx
    rts
.endproc

; ============================================================================
; win_close - Close a window
; In:  A = window handle
; ============================================================================
.proc win_close
    phx
    ldx #0
@find:
    cmp zwin_handles,x
    beq @found
    inx
    cpx #MAX_WINDOWS
    bcc @find
    bra @do
@found:
    pha
    lda #$FF
    sta zwin_handles,x
    pla
@do:
    plx
    jmp ulwin_close
.endproc

; ============================================================================
; win_clear - Clear window and reset scroll count + buffer offset
; In:  A = window handle
; ============================================================================
.proc win_clear
    phy
    jsr zwin_getstate
    pha
    lda #0
    sta zwin_state + ZWIN_SCRLCNT,y
    sta zwin_state + ZWIN_BUFOFF,y
    pla
    ply
    jmp ulwin_clear
.endproc

; ============================================================================
; win_erasecurrtoeol
; In:  A = window handle
; ============================================================================
.proc win_erasecurrtoeol
    jmp ulwin_eraseeol
.endproc

; ============================================================================
; win_getcursor
; In:  A = window handle
; Out: X = column, Y = line
; ============================================================================
.proc win_getcursor
    jmp ulwin_getcursor
.endproc

; ============================================================================
; win_setcursor
; In:  A = window handle, X = column, Y = line
; ============================================================================
.proc win_setcursor
    jmp ulwin_putcursor
.endproc

; ============================================================================
; win_getsize
; In:  A = window handle
; Out: X = width, Y = height
; ============================================================================
.proc win_getsize
    jmp ulwin_getsize
.endproc

; ============================================================================
; win_setsize
; In:  A = window handle, X = width, Y = height
; ============================================================================
.proc win_setsize
    jmp ulwin_resize
.endproc

; ============================================================================
; win_getpos
; In:  A = window handle
; Out: X = column, Y = line
; ============================================================================
.proc win_getpos
    jmp ulwin_getpos
.endproc

; ============================================================================
; win_setpos
; In:  A = window handle, X = column, Y = line
; ============================================================================
.proc win_setpos
    jmp ulwin_move
.endproc

; ============================================================================
; win_getcolor - Get packed BASE color (before style mapping)
; In:  A = window handle
; Out: X = (bg << 4) | fg   (ULCOLOR values)
; ============================================================================
.proc win_getcolor
    phy
    jsr zwin_getstate
    lda zwin_state + ZWIN_BASE_BG,y
    asl
    asl
    asl
    asl
    ora zwin_state + ZWIN_BASE_FG,y
    tax
    ply
    rts
.endproc

; ============================================================================
; win_setcolor - Store base colors, apply current style, set window color
; In:  A = window handle, X = (bg << 4) | fg   (ULCOLOR values)
; ============================================================================
.proc win_setcolor
    sta zwin_tmp
    phy
    phx
    jsr zwin_getstate
    ; Store base fg
    txa
    and #$0F
    sta zwin_state + ZWIN_BASE_FG,y
    ; Store base bg
    txa
    lsr
    lsr
    lsr
    lsr
    sta zwin_state + ZWIN_BASE_BG,y
    ; Apply current style and set window color
    jsr apply_style
    plx
    ply
    lda zwin_tmp
    rts
.endproc

; ============================================================================
; win_getflags
; In:  A = window handle
; Out: X = flags
; ============================================================================
.proc win_getflags
    phy
    jsr zwin_getstate
    ldx zwin_state + ZWIN_FLAGS,y
    ply
    rts
.endproc

; ============================================================================
; win_setwrap
; In:  A = window handle, X = 0 to disable, nonzero to enable
; ============================================================================
.proc win_setwrap
    sta zwin_tmp
    phy
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    cpx #0
    beq @off
    ora #WIN_WRAP
    bra @set
@off:
    and #<~WIN_WRAP
@set:
    sta zwin_state + ZWIN_FLAGS,y
    ply
    lda zwin_tmp
    rts
.endproc

; ============================================================================
; win_setscroll
; In:  A = window handle, X = 0 to disable, nonzero to enable
; ============================================================================
.proc win_setscroll
    sta zwin_tmp
    phy
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    cpx #0
    beq @off
    ora #WIN_SCROLL
    bra @set
@off:
    and #<~WIN_SCROLL
@set:
    sta zwin_state + ZWIN_FLAGS,y
    ply
    lda zwin_tmp
    rts
.endproc

; ============================================================================
; win_setbuffer - Enable/disable word-wrap buffering
; In:  A = window handle, X = 0 to disable, nonzero to enable
; ============================================================================
.proc win_setbuffer
    sta zwin_tmp
    cpx #0
    bne @enable

    ; Disabling: flush buffer first
    phy
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    and #WIN_BUFFER
    beq @already_off
    lda zwin_tmp
    ply
    jsr win_flushbuffer
    phy
    lda zwin_tmp
    jsr zwin_getstate
@already_off:
    lda zwin_state + ZWIN_FLAGS,y
    and #<~WIN_BUFFER
    sta zwin_state + ZWIN_FLAGS,y
    ply
    lda zwin_tmp
    rts

@enable:
    phy
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    ora #WIN_BUFFER
    sta zwin_state + ZWIN_FLAGS,y
    ply
    lda zwin_tmp
    rts
.endproc

; ============================================================================
; win_setstyle - Set text style flags (bold/italic/reverse)
; In:  A = window handle, X = style flags (low 3 bits)
; ============================================================================
.proc win_setstyle
    sta zwin_tmp
    phy
    phx
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    and #<~WIN_STYLEFLAGS
    sta zwin_state + ZWIN_FLAGS,y
    txa
    and #WIN_STYLEFLAGS
    ora zwin_state + ZWIN_FLAGS,y
    sta zwin_state + ZWIN_FLAGS,y
    ; Reapply style to window color
    jsr apply_style
    plx
    ply
    lda zwin_tmp
    rts
.endproc

; ============================================================================
; apply_style - Compute styled colors from base + flags, set on window
; Reads base_fg/base_bg and style flags from shim state for window in zwin_tmp
; Style priority (mutually exclusive): italic > bold > reverse
; Clobbers A, X, Y. Preserves zwin_tmp.
; ============================================================================
.proc apply_style
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    sta zwin_slot           ; flags
    ldx zwin_state + ZWIN_BASE_FG,y     ; working fg in X
    lda zwin_state + ZWIN_BASE_BG,y
    sta zwin_save_y         ; working bg

    ; Check italic (highest priority)
    lda zwin_slot
    and #WINSTYLE_ITALIC
    bne @do_italic

    ; Check bold
    lda zwin_slot
    and #WINSTYLE_BOLD
    bne @do_bold

    ; Check reverse
    lda zwin_slot
    and #WINSTYLE_REVERSE
    bne @do_reverse

    bra @done

@do_italic:
    lda colormap_italic,x
    tax
    bra @done

@do_bold:
    lda colormap_bold,x
    tax
    bra @done

@do_reverse:
    ; Swap fg and bg
    lda zwin_save_y         ; old bg
    stx zwin_save_y         ; old fg becomes new bg
    tax                     ; old bg becomes new fg

@done:
    ; X = styled fg, zwin_save_y = styled bg
    ldy zwin_save_y
    lda zwin_tmp
    clc                     ; don't recolor existing content
    jmp ulwin_putcolor
.endproc

; ============================================================================
; win_getscrlcnt - Get scroll count
; In:  A = window handle
; Out: X = scroll count
; ============================================================================
.proc win_getscrlcnt
    phy
    jsr zwin_getstate
    ldx zwin_state + ZWIN_SCRLCNT,y
    ply
    rts
.endproc

; ============================================================================
; win_resetscrlcnt - Reset scroll count to 0
; In:  A = window handle
; ============================================================================
.proc win_resetscrlcnt
    phy
    jsr zwin_getstate
    pha
    lda #0
    sta zwin_state + ZWIN_SCRLCNT,y
    pla
    ply
    rts
.endproc

; ============================================================================
; win_scroll - Scroll up one line, increment scroll count, handle [MORE]
; In:  A = window handle
; ============================================================================
.proc win_scroll
    sta zwin_tmp
    phx
    phy
    ldx #0
    ldy #$FF                ; scroll up
    jsr ulwin_scroll

    ; Increment scroll count
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_SCRLCNT,y
    inc
    sta zwin_state + ZWIN_SCRLCNT,y

    ; Only check [MORE] on buffered windows
    lda zwin_state + ZWIN_FLAGS,y
    and #WIN_BUFFER
    beq @done

    ; Get height-1
    lda zwin_tmp
    jsr ulwin_getsize       ; Y = height
    dey
    cpy #1
    bcc @done               ; height <= 1, skip [MORE]
    sty zwin_slot           ; save height-1

    ; Check scrlcnt >= height-1
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_SCRLCNT,y
    cmp zwin_slot
    bcc @done

    jsr show_more

@done:
    ply
    plx
    lda zwin_tmp
    rts
.endproc

; ============================================================================
; win_scrolldown - Scroll down one line
; In:  A = window handle
; ============================================================================
.proc win_scrolldown
    phx
    phy
    ldx #0
    ldy #1                  ; scroll down
    jsr ulwin_scroll
    ply
    plx
    rts
.endproc

; ============================================================================
; win_flushbuffer - Print buffered word via ulwin_putchar
; In:  A = window handle
; Note: uses a single shared buffer; only one window should be buffered at a
;       time (the ZPU engine flushes before switching windows).
; ============================================================================
.proc win_flushbuffer
    sta zwin_tmp
    phy
    phx

    jsr zwin_getstate
    lda zwin_state + ZWIN_BUFOFF,y
    beq @done               ; nothing to flush
    sta zwin_slot           ; chars to flush

    ; Clear bufoff now (safe: no reentrance into buffering during flush)
    lda #0
    sta zwin_state + ZWIN_BUFOFF,y

    ; Output each buffered character
    ldx #0
@loop:
    phx
    lda zwin_buf,x
    sta gREG::r0L
    inx
    lda zwin_buf,x
    sta gREG::r0H
    stz gREG::r1L
    lda zwin_tmp
    jsr ulwin_putchar
    plx
    inx
    inx                     ; next pair (lo+hi = 2 bytes)
    dec zwin_slot
    bne @loop

@done:
    plx
    ply
    lda zwin_tmp
    rts
.endproc

; ============================================================================
; win_putchr - Put a character in a window
; In:  A = window handle
;      X = UTF-16 hi byte, Y = UTF-16 lo byte
;      carry = set to advance cursor, clear to stay
; ============================================================================
.proc win_putchr
    sta zwin_tmp
    stx zwin_chr_hi
    sty zwin_chr_lo
    bcs @advancing
    jmp putchr_no_advance

@advancing:
    ; Check for CR/LF
    ldx zwin_chr_hi
    bne @not_newline
    lda zwin_chr_lo
    cmp #$0D
    beq @is_newline
    cmp #$0A
    bne @not_newline

@is_newline:
    ; In buffered+wrap mode, check if buffer fits before newline
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    and #WIN_BUFFER | WIN_WRAP
    cmp #WIN_BUFFER | WIN_WRAP
    bne @just_newline

    ; Check col + bufoff vs width
    lda zwin_state + ZWIN_BUFOFF,y
    beq @just_newline       ; empty buffer
    sta zwin_slot
    lda zwin_tmp
    jsr ulwin_getcursor     ; X = col
    txa
    clc
    adc zwin_slot           ; A = col + bufoff
    sta zwin_slot
    lda zwin_tmp
    jsr ulwin_getsize       ; X = width
    lda zwin_slot
    stx zwin_slot
    cmp zwin_slot           ; col+bufoff >= width?
    bcc @just_newline       ; fits on current line
    ; Buffer won't fit: wrap to next line first, then newline flushes
    jsr do_newline_noflush

@just_newline:
    jmp do_newline

@not_newline:
    ; Check buffered + wrapping mode
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    and #WIN_BUFFER | WIN_WRAP
    cmp #WIN_BUFFER | WIN_WRAP
    beq :+
    jmp @direct_print
:
    ; Buffered+wrapping: check for space
    lda zwin_chr_hi
    bne @buffer_char
    lda zwin_chr_lo
    cmp #' '
    beq @handle_space

@buffer_char:
    ; Add character to word-wrap buffer
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_BUFOFF,y
    cmp #80                 ; buffer full?
    bcs @buf_overflow
    phy                     ; save state offset
    asl
    tax
    lda zwin_chr_lo
    sta zwin_buf,x
    lda zwin_chr_hi
    sta zwin_buf+1,x
    ply                     ; restore state offset
    lda zwin_state + ZWIN_BUFOFF,y
    inc
    sta zwin_state + ZWIN_BUFOFF,y
    rts

@buf_overflow:
    ; Buffer full: flush via newline (flush + scroll), then retry
    lda zwin_tmp
    jsr do_newline
    jmp @buffer_char

@handle_space:
    ; Space in buffered+wrapping mode
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_BUFOFF,y
    beq @direct_print       ; empty buffer: just print space directly

    ; Check if word fits on current line: col + bufoff vs width
    sta zwin_slot           ; save bufoff
    lda zwin_tmp
    jsr ulwin_getcursor     ; X = col
    txa
    clc
    adc zwin_slot           ; A = col + bufoff
    sta zwin_slot
    lda zwin_tmp
    jsr ulwin_getsize       ; X = width
    lda zwin_slot
    stx zwin_slot
    cmp zwin_slot           ; col+bufoff vs width
    bcc @flush_word         ; col+bufoff < width: fits
    beq @flush_word         ; col+bufoff == width: fits exactly

    ; Word doesn't fit: wrap to next line, then flush
    jsr do_newline_noflush

@flush_word:
    ; Print the buffered word
    lda zwin_tmp
    jsr win_flushbuffer

    ; Check if there's room for the space character
    lda zwin_tmp
    jsr ulwin_getcursor     ; X = col
    stx zwin_slot
    lda zwin_tmp
    jsr ulwin_getsize       ; X = width
    lda zwin_slot           ; A = col
    stx zwin_slot
    cmp zwin_slot           ; col >= width?
    bcc @do_print           ; room for space

    ; No room: space consumed as line break
    lda zwin_tmp
    jmp do_newline

@direct_print:
    ; Non-buffered character output: check end-of-line wrapping
    lda zwin_tmp
    jsr ulwin_getcursor     ; X = col
    stx zwin_slot
    lda zwin_tmp
    jsr ulwin_getsize       ; X = width
    lda zwin_slot           ; A = col
    stx zwin_slot
    cmp zwin_slot           ; col >= width?
    bcc @do_print           ; not at end, just print

    ; At end of line: check wrap flag
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    and #WIN_WRAP
    beq @clip               ; no wrap: discard character

    ; Wrap: move to next line
    jsr do_newline_noflush

@do_print:
    lda zwin_chr_lo
    sta gREG::r0L
    lda zwin_chr_hi
    sta gREG::r0H
    stz gREG::r1L
    lda zwin_tmp
    jmp ulwin_putchar

@clip:
    rts
.endproc

; ============================================================================
; putchr_no_advance - Print character without moving cursor
; Uses: zwin_tmp (handle), zwin_chr_lo, zwin_chr_hi
; ============================================================================
.proc putchr_no_advance
    ; Save cursor position
    lda zwin_tmp
    jsr ulwin_getcursor
    stx zwin_save_x
    sty zwin_save_y

    ; Print the character
    lda zwin_chr_lo
    sta gREG::r0L
    lda zwin_chr_hi
    sta gREG::r0H
    stz gREG::r1L
    lda zwin_tmp
    jsr ulwin_putchar

    ; Restore cursor
    ldx zwin_save_x
    ldy zwin_save_y
    lda zwin_tmp
    jmp ulwin_putcursor
.endproc

; ============================================================================
; do_newline - Flush buffer, then move to start of next line (scroll if needed)
; Uses zwin_tmp (window handle)
; ============================================================================
.proc do_newline
    lda zwin_tmp
    jsr win_flushbuffer
    ; fall through to do_newline_noflush
.endproc

; ============================================================================
; do_newline_noflush - Move cursor to col 0 on next line, scroll if needed
; Uses zwin_tmp (window handle)
; Uses hardware stack for next_line to avoid conflict with show_more's
; use of zwin_save_x/zwin_save_y.
; ============================================================================
.proc do_newline_noflush
    ; Get current cursor line
    lda zwin_tmp
    jsr ulwin_getcursor     ; X=col, Y=line
    iny                     ; next line
    phy                     ; push next_line on stack

    ; Get window height
    lda zwin_tmp
    jsr ulwin_getsize       ; X=width, Y=height
    sty zwin_slot           ; save height

    ; Compare next_line vs height
    pla                     ; A = next_line
    cmp zwin_slot           ; next_line >= height?
    bcc @move_down          ; no: just move cursor down

    ; At bottom of window
    pha                     ; re-save next_line
    lda zwin_tmp
    jsr zwin_getstate
    lda zwin_state + ZWIN_FLAGS,y
    and #WIN_SCROLL
    beq @stay

    ; Scroll up (handles [MORE] prompt)
    lda zwin_tmp
    jsr win_scroll

    ; After scroll, cursor stays on bottom line (height-1), col 0
    pla                     ; next_line (== height)
    dec                     ; height-1
    tay
    ldx #0
    lda zwin_tmp
    jmp ulwin_putcursor

@stay:
    ; No scroll: stay on current line, just move to col 0
    pla                     ; next_line
    dec                     ; undo iny → original line
    tay
    ldx #0
    lda zwin_tmp
    jmp ulwin_putcursor

@move_down:
    ; A = next_line, move cursor there at col 0
    tay
    ldx #0
    lda zwin_tmp
    jmp ulwin_putcursor
.endproc

; ============================================================================
; show_more - Display [more] prompt and wait for keypress
; Uses zwin_tmp (window handle), zwin_save_x, zwin_save_y
; ============================================================================
.proc show_more
    ; Save cursor position
    lda zwin_tmp
    jsr ulwin_getcursor
    stx zwin_save_x
    sty zwin_save_y

    ; Print "[more]"
    ldx #0
@print:
    lda more_text,x
    beq @wait
    sta gREG::r0L
    stz gREG::r0H
    stz gREG::r1L
    phx
    lda zwin_tmp
    jsr ulwin_putchar
    plx
    inx
    bra @print

@wait:
    jsr GETIN
    cmp #CH::ENTER
    beq @done
    cmp #' '
    bne @wait

@done:
    ; Restore cursor and erase the [more] prompt
    ldx zwin_save_x
    ldy zwin_save_y
    lda zwin_tmp
    jsr ulwin_putcursor
    lda zwin_tmp
    jsr ulwin_eraseeol

    ; Reset scroll count
    lda zwin_tmp
    jsr zwin_getstate
    lda #0
    sta zwin_state + ZWIN_SCRLCNT,y
    lda zwin_tmp
    rts
.endproc

; ============================================================================
.rodata

more_text:  .byte "[more]", 0

; Z-machine color to ULCOLOR translation table (index by Z-machine color 0-12)
zmcolor_to_ulcolor:
    .byte 0                     ; 0 = current (handled by caller)
    .byte 0                     ; 1 = default (handled by caller)
    .byte ULCOLOR::BLACK        ; 2 = black
    .byte ULCOLOR::RED          ; 3 = red
    .byte ULCOLOR::GREEN        ; 4 = green
    .byte ULCOLOR::YELLOW       ; 5 = yellow
    .byte ULCOLOR::BLUE         ; 6 = blue
    .byte ULCOLOR::MAGENTA      ; 7 = magenta
    .byte ULCOLOR::CYAN         ; 8 = cyan
    .byte ULCOLOR::WHITE        ; 9 = white
    .byte ULCOLOR::LGREY        ; 10 = light grey
    .byte ULCOLOR::MGREY        ; 11 = medium grey
    .byte ULCOLOR::DGREY        ; 12 = dark grey

; Bold style: map ULCOLOR fg to bold equivalent
colormap_bold:
    .byte 0                     ; 0 unused
    .byte ULCOLOR::BLACK        ; 1 BLACK -> BLACK
    .byte ULCOLOR::BLACK        ; 2 DGREY -> BLACK
    .byte ULCOLOR::MGREY        ; 3 MGREY -> MGREY
    .byte ULCOLOR::WHITE        ; 4 LGREY -> WHITE
    .byte ULCOLOR::WHITE        ; 5 WHITE -> WHITE
    .byte ULCOLOR::MAGENTA      ; 6 RED -> MAGENTA
    .byte ULCOLOR::BROWN        ; 7 BROWN -> BROWN
    .byte ULCOLOR::WHITE        ; 8 GREEN -> WHITE
    .byte ULCOLOR::WHITE        ; 9 CYAN -> WHITE
    .byte ULCOLOR::CYAN         ; 10 BLUE -> CYAN
    .byte ULCOLOR::MAGENTA      ; 11 MAGENTA -> MAGENTA
    .byte ULCOLOR::LIGHTRED     ; 12 LIGHTRED -> LIGHTRED
    .byte ULCOLOR::YELLOW       ; 13 YELLOW -> YELLOW
    .byte ULCOLOR::LIGHTGREEN   ; 14 LIGHTGREEN -> LIGHTGREEN
    .byte ULCOLOR::LIGHTBLUE    ; 15 LIGHTBLUE -> LIGHTBLUE

; Italic style: map ULCOLOR fg to italic equivalent
colormap_italic:
    .byte 0                     ; 0 unused
    .byte ULCOLOR::DGREY        ; 1 BLACK -> DGREY
    .byte ULCOLOR::BLUE         ; 2 DGREY -> BLUE
    .byte ULCOLOR::MGREY        ; 3 MGREY -> MGREY
    .byte ULCOLOR::YELLOW       ; 4 LGREY -> YELLOW
    .byte ULCOLOR::LGREY        ; 5 WHITE -> LGREY
    .byte ULCOLOR::YELLOW       ; 6 RED -> YELLOW
    .byte ULCOLOR::BROWN        ; 7 BROWN -> BROWN
    .byte ULCOLOR::YELLOW       ; 8 GREEN -> YELLOW
    .byte ULCOLOR::GREEN        ; 9 CYAN -> GREEN
    .byte ULCOLOR::YELLOW       ; 10 BLUE -> YELLOW
    .byte ULCOLOR::CYAN         ; 11 MAGENTA -> CYAN
    .byte ULCOLOR::LIGHTRED     ; 12 LIGHTRED -> LIGHTRED
    .byte ULCOLOR::LIGHTGREEN   ; 13 YELLOW -> LIGHTGREEN
    .byte ULCOLOR::LIGHTGREEN   ; 14 LIGHTGREEN -> LIGHTGREEN
    .byte ULCOLOR::LIGHTBLUE    ; 15 LIGHTBLUE -> LIGHTBLUE

; ============================================================================
.bss

zwin_handles:   .res MAX_WINDOWS        ; UniLib window handles ($FF = free)
zwin_state:     .res MAX_WINDOWS * ZWIN_STATE_SIZE  ; per-window shim state
zwin_buf:       .res 160                ; word-wrap buffer (80 chars * 2 bytes)
zwin_tmp:       .res 1
zwin_slot:      .res 1
zwin_chr_lo:    .res 1
zwin_chr_hi:    .res 1
zwin_save_x:    .res 1
zwin_save_y:    .res 1
