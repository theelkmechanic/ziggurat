; Ziggurat main definitions

.include "cx16.inc"
.include "cbm_kernal.inc"

.include "windies.inc"

; We can use $0400-$07ff as 1k of temporary buffer for loading/saving/etc.
temp_buffer = $0400

; Global functions for everyone to use
.global printf
.global printhex
.global zpu_start
.global z_isinput
.global z_isoutput
.global z_iswhitespace
.global z_canbreakafter
.global z_tolower

; Version checks (for checking version in zero-page version field)
V1 = $80
V2 = $40
V3 = $20
V4 = $10
V5 = $08
V6 = $04
V7 = $02
V8 = $01
.macro chkver versions, failtarget
    lda #versions
    bit zpu_verflag
    beq failtarget
.endmacro
.global zpu_verflag

; Definition of standard Z-machine header block fields
.struct ZMheader
    .org $a000
    version         .byte
    flags           .byte
    release         .word
    himem_base      .word
    pc_init         .word
    dict_base       .word
    obj_base        .word
    glob_base       .word
    stat_base       .word

    flags2          .word
    serial          .byte 6
    abbrev_base     .word
    zif_len         .word
    checksum        .word
    int_ver         .word

    height          .byte
    width           .byte
    width_u         .word
    height_u        .word
    font_width      .byte
    font_height     .byte
    roff            .word
    soff            .word
    dflt_bg         .byte
    dflt_fg         .byte
    trmchr_base     .word

    textwidth_3     .word
    stdrev          .word
    atab_base       .word
    hdrext_base     .word
.endstruct

; Extended header fields
.struct ZMheader_ext
    num_words       .word
    mouse_x         .word
    mouse_y         .word
    unicode_base    .word
    flags3          .word
    fg_true         .word
    bg_true         .word
.endstruct

; Flags definitions
F1V3_ISTIMED        = $02
F1V3_STORYSPLIT     = $04
F1V3_ISTANDY        = $08
F1V3_HASSTATUS      = $10
F1V3_CANSPLITSCRN   = $20
F1V3_VARPITCH       = $40

F1V4_HASCOLOR       = $01
F1V4_HASPICTURES    = $02
F1V4_HASBOLD        = $04
F1V4_HASITALIC      = $08
F1V4_HASFIXED       = $10
F1V4_HASSOUND       = $20
F1V4_HASTIMEDKBD    = $80

F2_TRANSCRIPT       = $0001
F2_FORCEFIXED       = $0002
F2_REDRAW           = $0004
F2_WANTPICTURES     = $0008
F2_WANTUNDO         = $0010
F2_WANTMOUSE        = $0020
F2_WANTCOLOR        = $0040
F2_WANTSOUND        = $0080
F2_WANTMENU         = $0100

F3_WANTTRANS        = $0001

; Error codes
.global print_error_and_exit
SUCCESS                     = $00
ERR_ILLEGAL_VERSION         = $01
ERR_ILLEGAL_OPCODE          = $02
ERR_BAD_CHECKSUM            = $03
ERR_CANT_OPEN_FILE          = $04
ERR_STACK_EMPTY             = $05
ERR_INVALID_PARAM           = $06
ERR_ILLEGAL_EXTENDED        = $07
ERR_INVALID_PROPERTY        = $08
ERR_INVALID_PARSE_CHAR      = $09
ERR_TODO                    = $0a

; Helper macros

; For actual hardware
;BANK_RAM = $00
;BANK_ROM = $01

; For r38 emulator
BANK_RAM = VIA1::PRA
BANK_ROM = VIA1::PRB

.macro pushb bank
.scope
    lda BANK_RAM
    pha
    lda bank
    sta BANK_RAM
.endscope
.endmacro

.macro popb
.scope
    pla
    sta BANK_RAM
skip:
.endscope
.endmacro
