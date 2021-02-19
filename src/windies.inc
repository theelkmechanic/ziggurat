.global win_init
.global win_open
.global win_close
.global win_clear
.global win_erasecurrtoeol
.global win_getflags
.global win_setwrap
.global win_setbuffer
.global win_setscroll
.global win_setstyle
.global win_flushbuffer
.global win_getpos
.global win_setpos
.global win_getsize
.global win_setsize
.global win_getcursor
.global win_setcursor
.global win_getcolor
.global win_setcolor
.global win_putchr
.global win_scroll
.global win_scrolldown
.global win_getscrlcnt
.global win_resetscrlcnt

.global utf_xlat_default
.global utf_xlat_addr

WIN_ISOPEN = $80
WIN_BUFFER = $40
WIN_WRAP = $20
WIN_SCROLL = $10
WIN_TRANSCRIPT = $08
WIN_STYLEFLAGS = $07
WINSTYLE_REVERSE = $01
WINSTYLE_BOLD = $02
WINSTYLE_ITALIC = $04

W_BLACK     = 2
W_RED       = 3
W_GREEN     = 4
W_YELLOW    = 5
W_BLUE      = 6
W_MAGENTA   = 7
W_CYAN      = 8
W_WHITE     = 9
W_LGREY     = 10
W_MGREY     = 11
W_DGREY     = 12
