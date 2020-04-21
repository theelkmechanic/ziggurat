.include "windies.inc"

.struct Window
    flags   .byte
    colors  .byte
    left    .byte
    top     .byte
    width   .byte
    height  .byte
    cur_x   .byte
    cur_y   .byte
    font    .word   ; (big-endian)
    bufptr  .word   ; (big-endian)
    bufoff  .byte
    scrlcnt .byte
.endstruct

MAX_WINDOWS = 10

VERA_DC_VIDEO = $9f29
VERA_DC_HSCALE = $9f2a
VERA_DC_VSCALE = $9f2b
VERA_DC_BORDER = $9f2c
VERA_DC_HSTART = $9f29
VERA_DC_HSTOP = $9f2a
VERA_DC_VSTART = $9f2b
VERA_DC_VSTOP = $9f2c
VERA_L0_CONFIG = $9f2d
VERA_L0_MAPBASE = $9f2e
VERA_L0_TILEBASE = $9f2f
VERA_L0_HSCROLL_L = $9f30
VERA_L0_HSCROLL_H = $9f31
VERA_L0_VSCROLL_L = $9f32
VERA_L0_VSCROLL_H = $9f33
VERA_L1_CONFIG = $9f34
VERA_L1_MAPBASE = $9f35
VERA_L1_TILEBASE = $9f36
VERA_L1_HSCROLL_L = $9f37
VERA_L1_HSCROLL_H = $9f38
VERA_L1_VSCROLL_L = $9f39
VERA_L1_VSCROLL_H = $9f3a

.global win_getptr
.global curwin_calcaddr
.global curwin_clearline
.global curwin_flushbuffer
.global curwin_newline
.global curwin_putchr
.global curwin_putchr_nobuffer
.global curwin_scroll

.global vera_init
.global vera_blt
.global blt_src
.global blt_dst
.global blt_len

.globalzp win_tbl
.globalzp win_ptr
.globalzp buf_ptr

.global utf_find_charinfo

CHINFO_L0_REV       = $20
CHINFO_L1_REV       = $40
CHINFO_L1_TRANS     = $80

.global zmachine_default_font_8x16
