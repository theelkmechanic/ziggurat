; zmwin.inc - Z-machine window state and UniLib interface
;
; Minimal state layer between Ziggurat and UniLib's ulwin_* API.
; Tracks only Z-machine-specific metadata; all position/size/cursor
; state lives in UniLib natively.

; Z-machine window helpers
.global zmwin_init
.global zmwin_putchr
.global zmwin_putchr_noadv
.global zmwin_setcolor
.global zmwin_getslot
.global zmwin_scroll_up

; Z-machine window state (direct BSS access for flags/scrlcnt)
.global zmwin_slots
.global zmwin_current

; ZSCII-to-Unicode translation
.global utf_xlat_default
.global utf_xlat_addr

; Z-machine color lookup table
.global zmcolor_to_ulcolor

; UniLib window functions (resolved at link time via thunks)
.global ul_init
.global ulwin_open
.global ulwin_close
.global ulwin_clear
.global ulwin_move
.global ulwin_resize
.global ulwin_scroll
.global ulwin_putchar
.global ulwin_putcursor
.global ulwin_getcursor
.global ulwin_putcolor
.global ulwin_getcolor
.global ulwin_getpos
.global ulwin_getsize
.global ulwin_eraseeol
.global ulwin_refresh
.global ulwin_flash
.global ulwin_picklist

; UniLib string/table functions
.global ulstr_fromUtf8
.global ulstr_release
.global ulstb_create
.global ulstb_put
.global ulstb_delete

; Per-window slot (8 bytes, indexed by ZM window # 0-2)
ZMWIN_HANDLE  = 0   ; UniLib handle ($FF = not created)
ZMWIN_FLAGS   = 1   ; WIN_BUFFER | WIN_WRAP | WIN_SCROLL
ZMWIN_SCRLCNT = 2   ; scroll count (for [MORE] prompt)
ZMWIN_STYLE   = 3   ; REVERSE | BOLD | ITALIC
ZMWIN_FG      = 4   ; base foreground (ULCOLOR value)
ZMWIN_BG      = 5   ; base background (ULCOLOR value)
ZMWIN_SIZE    = 8   ; padded for ASL*3 indexing

; Flag constants
WIN_BUFFER    = $40
WIN_WRAP      = $20
WIN_SCROLL    = $10
WIN_STYLEFLAGS = $07
WINSTYLE_REVERSE = $01
WINSTYLE_BOLD    = $02
WINSTYLE_ITALIC  = $04

; ULCOLOR values (must match unilib.inc enum)
; Defined as plain constants to avoid enum redefinition conflicts
; when both zmwin.inc and unilib.inc are included.
ULC_BLACK     = 1
ULC_DGREY     = 2
ULC_MGREY     = 3
ULC_LGREY     = 4
ULC_WHITE     = 5
ULC_RED       = 6
ULC_BROWN     = 7
ULC_GREEN     = 8
ULC_CYAN      = 9
ULC_BLUE      = 10
ULC_MAGENTA   = 11
ULC_LIGHTRED  = 12
ULC_YELLOW    = 13
ULC_LIGHTGREEN = 14
ULC_LIGHTBLUE = 15

; Window border flag (for ulwin_open r4H)
ULWIN_BORDER  = $80
