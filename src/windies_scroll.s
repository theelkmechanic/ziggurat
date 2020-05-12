.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.code

; win_scroll - Scroll a window's contents up one line
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_scroll
    ; Get the window table entry pointer
    jsr win_getptr

    ; Scroll it up one line
    pha
    phx
    phy
    jsr curwin_scroll
    ply
    plx
    pla
    rts
.endproc

; curwin_scroll - Scroll the current window's contents up one line
; In:   win_ptr     - Pointer to window table entry
.proc curwin_scroll
@lines = $740
@cols = $741
@curr_line = $742

    ; The number of rows to scroll is the heigth of the window minus 1
    ldy #Window::height
    lda (win_ptr),y
    dec
    sta @lines

    ; The number of columns to copy in each line is the width * 2 (need to copy color bytes as well)
    dey
    lda (win_ptr),y
    asl
    sta @cols

    ; Now copy lines up
    stz @curr_line

@scroll_loop:
    ; Calculate the address of the current line in the window
    ldx #0
    ldy @curr_line
    jsr curwin_calcaddr

    ; Set destination to current line
    lda #$10
    sta blt_dst+2
    stx blt_dst+1
    sty blt_dst

    ; Set source to next line
    inx
    sta blt_src+2
    stx blt_src+1
    sty blt_src

    ; Length is number of columns
    lda @cols
    sta blt_len
    stz blt_len+1

    ; Blit the line
    jsr vera_blt

    ; Do the same line in layer 1
    lda blt_src+1
    ora #$20
    sta blt_src+1
    lda blt_dst+1
    ora #$20
    sta blt_dst+1
    lda @cols
    sta blt_len
    stz blt_len+1
    jsr vera_blt

    ; Skip to next line
    lda @curr_line
    inc
    cmp @lines
    sta @curr_line
    bne @scroll_loop

    ; And clear the last line
    tay
    jsr curwin_clearline

    ; Pause every full window scroll (height-1 lines) on buffered windows
    ldy #Window::scrlcnt
    lda (win_ptr),y
    inc
    sta (win_ptr),y
    lda (win_ptr)
    and #WIN_BUFFER
    beq @scroll_done
    ldy #Window::scrlcnt
    lda (win_ptr),y
    cmp @lines
    bcs @more
@scroll_done:
    rts

@more:
    ; Display [MORE] prompt and wait for ENTER/space
    ldx #6
@more_loop:
    dex
    lda more_prompt,x
    phx
    ldx #0
    tay
    sec
    jsr curwin_putchr_nobuffer
    plx
    bne @more_loop
@1: jsr GETIN
    cmp #CH::ENTER
    beq @more_done
    cmp #' '
    bne @1

@more_done:
    ; Reset the scroll count and erase the more prompt
    lda #0
    ldy #Window::cur_x
    sta (win_ptr),y
    ldy #Window::scrlcnt
    sta (win_ptr),y
    ldy @curr_line
    jmp curwin_clearline
.endproc

; win_scrolldown - Scroll a window's contents down one line
; In:   a           - Window ID (0-MAX_WINDOWS-1)
.proc win_scrolldown
    ; Get the window table entry pointer
    jsr win_getptr

    ; Scroll it down one line
    pha
    phx
    phy
    jsr curwin_scrolldown
    ply
    plx
    pla
    rts
.endproc

; curwin_scrolldown - Scroll the current window's contents down one line
; In:   win_ptr     - Pointer to window table entry
.proc curwin_scrolldown
@lines = $740
@cols = $741
@curr_line = $742

    ; The number of columns to copy in each line is the width * 2 (need to copy color bytes as well)
    ldy #Window::width
    lda (win_ptr),y
    asl
    sta @cols

    ; The number of rows to scroll is the heigth of the window minus 1
    iny
    lda (win_ptr),y
    dec
    sta @lines

    ; Now copy lines down
    dec
    sta @curr_line

@scroll_loop:
    ; Calculate the address of the current line in the window
    ldx #0
    ldy @curr_line
    jsr curwin_calcaddr

    ; Set source to current line
    lda #$10
    sta blt_src+2
    stx blt_src+1
    sty blt_src

    ; Set destination to next line
    inx
    sta blt_dst+2
    stx blt_dst+1
    sty blt_dst

    ; Length is number of columns
    lda @cols
    sta blt_len
    stz blt_len+1

    ; Blit the line
    jsr vera_blt

    ; Do the same line in layer 1
    lda blt_src+1
    ora #$20
    sta blt_src+1
    lda blt_dst+1
    ora #$20
    sta blt_dst+1
    lda @cols
    sta blt_len
    stz blt_len+1
    jsr vera_blt

    ; Skip to next line
    lda @curr_line
    dec @curr_line
    bpl @scroll_loop

    ; And clear the first line
    lda #0
    jsr curwin_clearline
    rts
.endproc

.rodata

more_prompt: .byte "]erom["