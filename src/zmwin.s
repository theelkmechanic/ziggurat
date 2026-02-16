; zmwin.s - Z-machine window state module
;
; Provides minimal Z-machine-specific window metadata (flags, scroll count,
; style, colors) and helper functions. All position/size/cursor state is
; managed by UniLib natively via ulwin_* calls.
;
; Register preservation: zmwin_putchr/zmwin_putchr_noadv preserve r0/r1L.

.include "cx16.inc"
.include "cbm_kernal.inc"
.include "unilib.inc"
.include "zmwin.inc"

MAX_WINDOWS = 3

.code

; =========================================================================
; zmwin_init - Zero the slot array
; =========================================================================
.proc zmwin_init
    ldx #MAX_WINDOWS * ZMWIN_SIZE
    lda #0
@loop:
    dex
    sta zmwin_slots,x
    bne @loop
    ; Set all handles to $FF (not created)
    lda #$ff
    sta zmwin_slots + ZMWIN_HANDLE
    sta zmwin_slots + ZMWIN_SIZE + ZMWIN_HANDLE
    sta zmwin_slots + ZMWIN_SIZE * 2 + ZMWIN_HANDLE
    stz zmwin_current
    rts
.endproc

; =========================================================================
; zmwin_getslot - Get slot offset from ZM window number
; In:  A = ZM window # (0-2)
; Out: Y = slot offset (A * 8)
; Preserves: A, X
; =========================================================================
.proc zmwin_getslot
    pha
    asl
    asl
    asl
    tay
    pla
    rts
.endproc

; =========================================================================
; zmwin_putchr - Put character at current cursor position (always advances)
; In:  A = UniLib window handle
;      X = Unicode page (high byte)
;      Y = char (low byte)
; Preserves: r0L, r0H, r1L
; Out: A = handle (preserved)
; =========================================================================
.proc zmwin_putchr
    sta zmpc_handle
    stx zmpc_page
    sty zmpc_char

    ; Save caller's r0/r1L
    lda gREG::r0L
    sta zmpc_save_r0L
    lda gREG::r0H
    sta zmpc_save_r0H
    lda gREG::r1L
    sta zmpc_save_r1L

    ; Check for newline (Unicode page=0, char=$0D)
    lda zmpc_page
    bne @printable
    lda zmpc_char
    cmp #$0d
    beq @newline

@printable:
    ; Set up Unicode char in r0/r1L
    lda zmpc_char
    sta gREG::r0L
    lda zmpc_page
    sta gREG::r0H
    stz gREG::r1L

    ; Call ulwin_putchar
    lda zmpc_handle
    jsr ulwin_putchar

    ; Check if cursor actually advanced — if putchar hit the end of the
    ; window (last col of last row), the cursor stays put. In that case
    ; we need to scroll up and wrap to column 0 of the last row.
    lda zmpc_handle
    jsr ulwin_getcursor
    stx zmpc_savex          ; current col
    sty zmpc_savey          ; current line
    lda zmpc_handle
    jsr ulwin_getsize
    dex                     ; last col
    dey                     ; last line
    cpx zmpc_savex
    bne @done               ; cursor moved — all good
    cpy zmpc_savey
    bne @done               ; cursor moved — all good

    ; Cursor stuck at last col/last line — scroll up and wrap
    lda zmpc_handle
    ldx #0
    ldy #$ff
    jsr ulwin_scroll
    lda zmpc_handle
    jsr ulwin_getsize
    dey                     ; last line
    ldx #0
    lda zmpc_handle
    jsr ulwin_putcursor
    bra @done

@newline:
    ; Move cursor to column 0 of next line; scroll if at bottom
    lda zmpc_handle
    jsr ulwin_getcursor
    ; X=col, Y=line
    sty zmpc_savey          ; current line

    lda zmpc_handle
    jsr ulwin_getsize
    ; X=ncol, Y=nlin
    dey                     ; last line index
    cpy zmpc_savey
    beq @nl_scroll          ; already on last line — scroll

    ; Not at bottom — just advance to next line
    ldy zmpc_savey
    iny
    ldx #0
    lda zmpc_handle
    jsr ulwin_putcursor
    bra @done

@nl_scroll:
    ; At bottom line — scroll content up and stay on last line, col 0
    sty zmpc_savey          ; save last line index
    lda zmpc_handle
    ldx #0
    ldy #$ff
    jsr ulwin_scroll
    ldx #0
    ldy zmpc_savey
    lda zmpc_handle
    jsr ulwin_putcursor

@done:
    ; Restore caller's r0/r1L
    lda zmpc_save_r0L
    sta gREG::r0L
    lda zmpc_save_r0H
    sta gREG::r0H
    lda zmpc_save_r1L
    sta gREG::r1L

    lda zmpc_handle
    rts
.endproc

; =========================================================================
; zmwin_putchr_noadv - Put character without advancing cursor
; In:  A = UniLib window handle
;      X = Unicode page (high byte)
;      Y = char (low byte)
; Preserves: r0L, r0H, r1L, cursor position
; Out: A = handle (preserved)
; =========================================================================
.proc zmwin_putchr_noadv
    sta zmpc_handle
    stx zmpc_page
    sty zmpc_char

    ; Save caller's r0/r1L
    lda gREG::r0L
    sta zmpc_save_r0L
    lda gREG::r0H
    sta zmpc_save_r0H
    lda gREG::r1L
    sta zmpc_save_r1L

    ; Save cursor position
    lda zmpc_handle
    jsr ulwin_getcursor
    stx zmpc_savex
    sty zmpc_savey

    ; Set up Unicode char in r0/r1L
    lda zmpc_char
    sta gREG::r0L
    lda zmpc_page
    sta gREG::r0H
    stz gREG::r1L

    ; Call ulwin_putchar
    lda zmpc_handle
    jsr ulwin_putchar

    ; Restore cursor position
    lda zmpc_handle
    ldx zmpc_savex
    ldy zmpc_savey
    jsr ulwin_putcursor

    ; Restore caller's r0/r1L
    lda zmpc_save_r0L
    sta gREG::r0L
    lda zmpc_save_r0H
    sta gREG::r0H
    lda zmpc_save_r1L
    sta gREG::r1L

    lda zmpc_handle
    rts
.endproc

; =========================================================================
; zmwin_setcolor - Set window color based on style (handles REVERSE)
; In:  A = UniLib window handle
;      Y = slot offset
; Reads fg/bg from slot, swaps if REVERSE style, calls ulwin_putcolor.
; =========================================================================
.proc zmwin_setcolor
    sta zmsc_handle
    sty zmsc_offset

    ; Read fg/bg from slot
    lda zmwin_slots + ZMWIN_FG,y
    sta zmsc_fg
    lda zmwin_slots + ZMWIN_BG,y
    sta zmsc_bg

    ; Check for REVERSE style - swap fg/bg
    lda zmwin_slots + ZMWIN_STYLE,y
    and #WINSTYLE_REVERSE
    beq @no_swap
    ldx zmsc_fg
    lda zmsc_bg
    sta zmsc_fg
    stx zmsc_bg

@no_swap:
    ; Call ulwin_putcolor (A=handle, X=fg, Y=bg, clc=current text only)
    lda zmsc_handle
    ldx zmsc_fg
    ldy zmsc_bg
    clc
    jsr ulwin_putcolor
    rts
.endproc

; =========================================================================
; zmwin_scroll_up - Scroll content up one line, increment scroll count
; In:  A = UniLib window handle
;      Y = slot offset
; Preserves: A
; =========================================================================
.proc zmwin_scroll_up
    pha
    ; Increment scroll count
    lda zmwin_slots + ZMWIN_SCRLCNT,y
    inc
    sta zmwin_slots + ZMWIN_SCRLCNT,y

    ; Scroll content UP (Y=$FF)
    pla
    pha
    ldx #0
    ldy #$ff
    jsr ulwin_scroll
    pla
    rts
.endproc

; =========================================================================
; Data
; =========================================================================
.rodata

; ZSCII-to-Unicode default translation table
; Used by ZPU for Z-machine characters 155+ (accented letters etc.)
utf_xlat_default:
    .byte 69    ; Number of Unicode characters in the table (2 bytes each, big-endian)
    .dbyt $00e4
    .dbyt $00f6
    .dbyt $00fc
    .dbyt $00c4
    .dbyt $00d6
    .dbyt $00dc
    .dbyt $00df
    .dbyt $00bb
    .dbyt $00ab
    .dbyt $00eb
    .dbyt $00ef
    .dbyt $00ff
    .dbyt $00cb
    .dbyt $00cf
    .dbyt $00e1
    .dbyt $00e9
    .dbyt $00ed
    .dbyt $00f3
    .dbyt $00fa
    .dbyt $00fd
    .dbyt $00c1
    .dbyt $00c9
    .dbyt $00cd
    .dbyt $00d3
    .dbyt $00da
    .dbyt $00dd
    .dbyt $00e0
    .dbyt $00e8
    .dbyt $00ec
    .dbyt $00f2
    .dbyt $00f9
    .dbyt $00c0
    .dbyt $00c8
    .dbyt $00cc
    .dbyt $00d2
    .dbyt $00d9
    .dbyt $00e2
    .dbyt $00ea
    .dbyt $00ee
    .dbyt $00f4
    .dbyt $00fb
    .dbyt $00c2
    .dbyt $00ca
    .dbyt $00ce
    .dbyt $00d4
    .dbyt $00db
    .dbyt $00e5
    .dbyt $00c5
    .dbyt $00f8
    .dbyt $00d8
    .dbyt $00e3
    .dbyt $00f1
    .dbyt $00f5
    .dbyt $00c3
    .dbyt $00d1
    .dbyt $00d5
    .dbyt $00e6
    .dbyt $00c6
    .dbyt $00e7
    .dbyt $00c7
    .dbyt $00fe
    .dbyt $00f0
    .dbyt $00de
    .dbyt $00d0
    .dbyt $00a3
    .dbyt $0153
    .dbyt $0152
    .dbyt $00a1
    .dbyt $00bf

; Z-machine color number (2-12) to ULCOLOR value lookup table
zmcolor_to_ulcolor:
    .byte 0, 0                  ; 0,1 = current/default (unused indices)
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

; =========================================================================
; BSS
; =========================================================================
.bss

zmwin_slots:    .res MAX_WINDOWS * ZMWIN_SIZE   ; 24 bytes (main=0, upper=1, status=2)
zmwin_current:  .res 1                          ; current ZM window number (0-2)

; Temporaries for zmwin_putchr / zmwin_putchr_noadv
zmpc_handle:    .res 1
zmpc_char:      .res 1
zmpc_page:      .res 1
zmpc_savex:     .res 1
zmpc_savey:     .res 1
zmpc_save_r0L:  .res 1
zmpc_save_r0H:  .res 1
zmpc_save_r1L:  .res 1

; Temporaries for zmwin_setcolor
zmsc_handle:    .res 1
zmsc_offset:    .res 1
zmsc_fg:        .res 1
zmsc_bg:        .res 1

; ZSCII-to-Unicode translation table pointer (3 bytes: bank:hi:lo)
.data
utf_xlat_addr:  .res 3
