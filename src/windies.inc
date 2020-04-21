.global win_init
.global win_open
.global win_close
.global win_clear
.global win_clearline
.global win_getflags
.global win_setwrap
.global win_setbuffer
.global win_flushbuffer
.global win_getpos
.global win_setpos
.global win_getsize
.global win_setsize
.global win_getcursor
.global win_setcursor
.global win_getcolor
.global win_setcolor
.global win_getfont
.global win_setfont
.global win_putchr
.global win_scroll
.global win_getscrlcnt
.global win_resetscrlcnt

.global utf_xlat_default
.global utf_xlat_addr

WIN_ISOPEN = $80
WIN_BUFFER = $40
WIN_WRAP = $20
