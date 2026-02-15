; zwin.inc - Windies-to-UniLib adapter definitions
;
; Exports the same win_* API as windies.inc, implemented using UniLib ulwin_* calls.
; ZPU code includes this instead of windies.inc.

; Window management
.global win_open
.global win_close
.global win_clear
.global win_erasecurrtoeol

; Flags and modes
.global win_getflags
.global win_setwrap
.global win_setbuffer
.global win_setscroll
.global win_setstyle
.global win_flushbuffer

; Position and size
.global win_getpos
.global win_setpos
.global win_getsize
.global win_setsize

; Cursor
.global win_getcursor
.global win_setcursor

; Color
.global win_getcolor
.global win_setcolor

; Character output
.global win_putchr

; Scrolling
.global win_scroll
.global win_scrolldown
.global win_getscrlcnt
.global win_resetscrlcnt

; ZSCII-to-Unicode table (defined in zpu_window.s, not in shim)
.global utf_xlat_default
.global utf_xlat_addr

; Z-machine color to ULCOLOR translation table (for op_set_colour)
.global zmcolor_to_ulcolor

; Shim flags (same bit positions as windies for ZPU compatibility)
WIN_ISOPEN = $80
WIN_BUFFER = $40
WIN_WRAP = $20
WIN_SCROLL = $10
WIN_TRANSCRIPT = $08
WIN_STYLEFLAGS = $07
WINSTYLE_REVERSE = $01
WINSTYLE_BOLD = $02
WINSTYLE_ITALIC = $04

; Z-machine / windies color constants mapped to ULCOLOR values
W_BLACK     = ULCOLOR::BLACK
W_RED       = ULCOLOR::RED
W_GREEN     = ULCOLOR::GREEN
W_YELLOW    = ULCOLOR::YELLOW
W_BLUE      = ULCOLOR::BLUE
W_MAGENTA   = ULCOLOR::MAGENTA
W_CYAN      = ULCOLOR::CYAN
W_WHITE     = ULCOLOR::WHITE
W_LGREY     = ULCOLOR::LGREY
W_MGREY     = ULCOLOR::MGREY
W_DGREY     = ULCOLOR::DGREY
