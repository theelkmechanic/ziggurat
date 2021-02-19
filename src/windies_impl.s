.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.zeropage

win_tbl: .res 2
win_ptr: .res 2
buf_ptr: .res 2

.code

; win_getptr - Get a pointer to the window table entry we're working on
; In:   a           - Window ID (0-MAX_WINDOWS-1)
; Out:  win_ptr     - Pointer to window table entry
.proc win_getptr
    ; Multiply by 16 and put in low byte of win_ptr (high byte never changes)
    pha
    asl
    asl
    asl
    asl
    clc
    adc win_tbl
    sta win_ptr
    pla
    rts
.endproc

; curwin_calcaddr - Calculate the VERA start address for the line/column in x/y for the current window.
;                   Conveniently, our line stride is 256 bytes and the map is page-aligned, so the middle
;                   byte is map base + top + line, and the low byte is (left + column) * 2
; In:   x           - Column to find
;       y           - Line to find
;       win_ptr     - Current window table entry
; Out:  x           - Address middle byte
;       y           - Address low byte
.proc curwin_calcaddr
    ; Add line to window top and return it in x
    tya
    ldy #Window::top
    clc
    adc (win_ptr),y
    pha
    txa
    plx

    ; Now add column to window left and return in y
    ldy #Window::left
    clc
    adc (win_ptr),y
    asl
    tay
    rts
.endproc

; curwin_clearline - Clear the specified line in the current window
; In:   y           - Line to clear (0 to height-1)
;       win_ptr     - Current window
.proc curwin_clearline
    ; Calculate the line start address and put in VERA::ADDR0
    ldx #0
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

    ; Now get the line width and write that many spaces to the window
    ldy #Window::width
    lda (win_ptr),y
    tax
    ldy #Window::colors
    lda (win_ptr),y
    ldy #' '
@1: stz VERA::DATA0
    stz VERA::DATA0
    sty VERA::DATA1
    sta VERA::DATA1
    dex
    bne @1
    rts
.endproc
