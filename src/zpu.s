; Ziggurat Z-machine CPU

.include "ziggurat.inc"
.include "zpu.inc"

.zeropage

zpu_bp: .res 2
zpu_sp: .res 2
zpu_mem: .res 3
zpu_mem_2: .res 3
zpu_pc: .res 3
opcode: .res 1
optypes: .res 2
operands:
operand_0: .res 2
operand_1: .res 2
operand_2: .res 2
operand_3: .res 2
operand_4: .res 2
operand_5: .res 2
operand_6: .res 2
operand_7: .res 2
atab_addr: .res 3

.data

zpu_verflag: .res 1
dict_base: .res 2
obj_base: .res 2
objtbl_base: .res 2
glob_base: .res 2
stat_base: .res 2
himem_base: .res 2
abbrev_base: .res 2
trmchr_base: .res 2
hdrext_base: .res 2
num_operands: .res 1
opcode_ext: .res 1
objentry_offset_parent: .res 1
objentry_offset_sibling: .res 1
objentry_offset_child: .res 1
objentry_offset_propaddr: .res 1
line_counter: .res 1
window_main: .res 1
window_upper: .res 1
window_status: .res 1
window_debug: .res 1
current_window: .res 1
current_font: .res 1
printf_use_chrout: .res 1

.code

.proc zpu_start
    ; Load header fields into our zeropage
    ; Map version to bitfield
    stz printf_use_chrout
    lda #50
    sta line_counter
    lda #1
    sta BANKSEL::RAM
    ldx ZMheader::version
    beq @bad_version
    cpx #9
    bcc @set_verflag
@bad_version:
    stx operand_0
    lda #ERR_ILLEGAL_VERSION
    jmp print_error_and_exit
@set_verflag:
    dex
    lda numtobit,x
    sta zpu_verflag

    ; Initialize the address decode routines
    jsr memory_init

    ; Initialize to the default alphabet table
    chkver V1,@new_default
    ldx #>atab_v1_default
    ldy #<atab_v1_default
    bra @save_atab_default
@new_default:
    ldx #>atab_default
    ldy #<atab_default
@save_atab_default:
    lda #1
    sty atab_addr
    stx atab_addr+1
    sta atab_addr+2

    ; Initialize to the default Unicode translation table
    lda #<utf_xlat_default
    sta utf_xlat_addr
    lda #>utf_xlat_default
    sta utf_xlat_addr+1
    lda #1
    sta utf_xlat_addr+2

@load_bases:
    ; Make copies of our base offsets into low memory so we don't have to bank to read them
    lda ZMheader::version
    ldx ZMheader::himem_base
    ldy ZMheader::himem_base+1
    stx himem_base
    sty himem_base+1
    ldx ZMheader::dict_base
    ldy ZMheader::dict_base+1
    stx dict_base
    sty dict_base+1
    ldx ZMheader::obj_base
    ldy ZMheader::obj_base+1
    stx obj_base
    sty obj_base+1
    ldx ZMheader::glob_base
    ldy ZMheader::glob_base+1
    stx glob_base
    sty glob_base+1
    ldx ZMheader::stat_base
    ldy ZMheader::stat_base+1
    stx stat_base
    sty stat_base+1
    cmp #2
    bcc @done_header
    ldx ZMheader::abbrev_base
    ldy ZMheader::abbrev_base+1
    stx abbrev_base
    sty abbrev_base+1
    cmp #5
    bcc @done_header
    ldx ZMheader::trmchr_base
    ldy ZMheader::trmchr_base+1
    stx trmchr_base
    sty trmchr_base+1
    lda ZMheader::atab_base
    ora ZMheader::atab_base+1
    beq @use_default_atab
    ldx ZMheader::atab_base
    ldy ZMheader::atab_base+1
    jsr decode_baddr
    sty atab_addr
    stx atab_addr+1
    sta atab_addr+2
@use_default_atab:
    ldx ZMheader::hdrext_base
    ldy ZMheader::hdrext_base+1
    stx hdrext_base
    sty hdrext_base+1

@done_header:
    ; Precalculate offsets and sizes for the object table entries (offsets/sizes are different in V1-3 vs. V4+)
    chkver V1|V2|V3,@calc_v4_objtbl

    ; Calculate V1-3 object table offsets -- There are 31 property defaults, and property address is 7 bytes into object
    lda #31*2
    ldx #7
    bra @calc_objtbl

@calc_v4_objtbl:
    ; Calculate V1-3 object table offsets -- There are 63 property defaults, and property address is 12 bytes into object
    lda #63*2
    ldx #12
@calc_objtbl:
    stx objentry_offset_propaddr
    clc
    adc obj_base+1
    sta objtbl_base+1
    lda #0
    adc obj_base
    sta objtbl_base

@startup:
    ; Set header fields
    chkver V1|V2|V3,@set_v4_header

    ; Set V1-3 flags 1
    lda ZMheader::flags
    ora #F1V3_CANSPLITSCRN
    sta ZMheader::flags
    jmp @init_windows

@set_v4_header:
    ; Set V4+ flags 1
    lda ZMheader::flags
    ora #F1V4_HASCOLOR | F1V4_HASBOLD | F1V4_HASFIXED
    sta ZMheader::flags

    lda #7
    sta ZMheader::int_ver
    lda #'A'
    sta ZMheader::int_ver+1
    lda #SCREEN_HEIGHT
    sta ZMheader::height
    lda #SCREEN_WIDTH
    sta ZMheader::width

    ; Set V5 headers
    chkver V4,@set_v5_headers
    jmp @init_windows
@set_v5_headers:
    lda ZMheader::flags2+1
    and #$ff & (F2_WANTPICTURES | F2_WANTUNDO | F2_WANTMOUSE | F2_WANTSOUND)
    sta ZMheader::flags2+1
    lda ZMheader::flags2
    and #$ff & F2_WANTMENU

    lda #>(SCREEN_WIDTH * FONT_WIDTH)
    sta ZMheader::width_u
    lda #<(SCREEN_WIDTH * FONT_WIDTH)
    sta ZMheader::width_u+1
    lda #>(SCREEN_HEIGHT * FONT_HEIGHT)
    sta ZMheader::height_u
    lda #<(SCREEN_HEIGHT * FONT_HEIGHT)
    sta ZMheader::height_u+1

    lda #DEFAULT_BG
    sta ZMheader::dflt_bg
    lda #DEFAULT_FG
    sta ZMheader::dflt_fg

    ; V5 and V6 store font widths backwards from each other
    chkver V5,@set_v6_fontwidth
    lda #FONT_WIDTH
    sta ZMheader::font_width
    lda #FONT_HEIGHT
    sta ZMheader::font_height
    bra @set_headerext

@set_v6_fontwidth:
    lda #FONT_HEIGHT
    sta ZMheader::font_width
    lda #FONT_WIDTH
    sta ZMheader::font_height

@set_headerext:
    lda ZMheader::hdrext_base
    ora ZMheader::hdrext_base+1
    bne @haveheaderext
    jmp @init_windows

@haveheaderext:
    ldx ZMheader::hdrext_base
    ldy ZMheader::hdrext_base+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta BANK_RAM

    jsr mem_fetch_and_advance
    tax
    jsr mem_fetch_and_advance
    tay
    txa
    bne @have6
    cpy #6
    bcc @check5
@have6:
    lda #10
    jsr mem_advance
    lda #3
    jsr mem_store_and_advance
    lda #$bd
    sta (zpu_mem)
    lda #11
    jsr mem_retreat

@check5:
    txa
    bne @have5
    cpy #5
    bcc @check4
@have5:
    lda #8
    jsr mem_advance
    lda #0
    jsr mem_store_and_advance
    sta (zpu_mem)
    lda #9
    jsr mem_retreat

@check4:
    txa
    bne @have4
    cpy #4
    bcc @check3
@have4:
    lda #6
    jsr mem_advance
    lda #0
    jsr mem_store_and_advance
    lda (zpu_mem)
    and #$01
    sta (zpu_mem)
    lda #7
    jsr mem_retreat

@check3:
    txa
    bne @have3
    cpy #3
    bcc @init_windows
@have3:
    lda #4
    jsr mem_advance
    jsr mem_fetch_and_advance
    tax
    lda (zpu_mem)
    tay
    jsr decode_baddr
    sty utf_xlat_addr
    stx utf_xlat_addr+1
    sta utf_xlat_addr+2

@init_windows:
    ; Open our windows (main, upper, status, and debug)
    ldx #3
    lda #$ff
@clearwinlist:
    sta window_main,x
    dex
    bpl @clearwinlist
    inc
    inc
    sta current_font
    jsr win_open
    sta window_main
    sta current_window
    ldx #SCREEN_WIDTH
    ldy #SCREEN_HEIGHT
    jsr win_setsize
    jsr win_open
    sta window_upper
    ldx #SCREEN_WIDTH
    ldy #0
    jsr win_setsize
    chkver V1|V2|V3,@dontneedstatus
    jsr win_open
    sta window_status
    ldy #1
    jsr win_setsize
    ldx #0
    lda window_upper
    jsr win_setpos
    lda window_main
    jsr win_setpos
    jsr win_getsize
    dey
    jsr win_setsize

@dontneedstatus:
.if SHOW_DEBUG_WINDOW
    jsr win_open
    sta window_debug
    ldy #30-SCREEN_HEIGHT
    jsr win_setsize
.endif
    lda window_main
    ldx #(DEFAULT_BG << 4) | DEFAULT_FG
    jsr win_setcolor
    ldx #1
    jsr win_setbuffer
    jsr win_setwrap
    jsr win_setscroll
    jsr win_clear
    jsr win_getsize
    ldx #0
    dey
    lda window_main
    jsr win_setcursor

    jsr win_getcolor
    lda window_upper
    jsr win_setcolor

    lda window_debug
    bmi @nodebugwindow
    ldx #0
    ldy #SCREEN_HEIGHT
    jsr win_setpos
    ldx #(W_BLUE << 4) + W_WHITE
    jsr win_setcolor
    ldx #1
    jsr win_setwrap
    jsr win_setscroll
    jsr win_clear

@nodebugwindow:
    chkver V1|V2|V3,@start_zmachine
    lda window_status
    ldx #(DEFAULT_FG << 4) | DEFAULT_BG
    jsr win_setcolor
    jsr win_clear

@start_zmachine:
;    jsr debugchrdump

    ; Start the Z-machine
    lda #<msg_launching
    sta gREG::r6L
    lda #>msg_launching
    sta gREG::r6H
;    jsr printf

    ; Initialize SP/BP to top of low memory (we will grow down)
    sec
    jsr MEMTOP
    stx zpu_bp
    sty zpu_bp+1
    stx zpu_sp
    sty zpu_sp+1

    ; Initialize the PC based on the init vector in the header
    ldx ZMheader::pc_init
    ldy ZMheader::pc_init+1

    ; For version 6, the PC is the start of the main routine, not the first instruction, so we
    ; need to fake a call to it to build a stack frame before we start executing
    chkver V6,@bytepc
    lda #$e0        ; call_vs
    sta opcode
    lda #$3f        ; one large constant operand (routine address)
    sta optypes
    stx operand_0    ; routine address
    sty operand_0+1
    jmp op_call_save

    ; For all other versions, pc_init is a byte address where we should start executing code.
@bytepc:
    jsr decode_baddr
    sty zpu_pc
    stx zpu_pc+1
    sta zpu_pc+2
    bra fetch_and_dispatch
.endproc

.proc fetch_varops
    ; Save the types of up to 4 operators
    jsr pc_fetch_and_advance
    sta optypes

    ; Check for our two special 8OP opcodes
    lda opcode
    cmp #$ec
    beq @fetch_8_optypes
    cmp #$fa
    bne @fetch_varop_values

@fetch_8_optypes:
    ; Save the types of up to 8 operators
    jsr pc_fetch_and_advance
    sta optypes+1

    ; Now fetch the values of up to 8 operators
@fetch_varop_values:
    lda optypes
    ldx #0
    jsr fetch_4_operands
    bcs @calc_num_operands
    lda optypes+1
    jsr fetch_4_operands

@calc_num_operands:
    ; The number of operands we have is X/2
    txa
    lsr
    sta num_operands
    jmp fetched
.endproc

; fetch_and_dispatch - Fetch the next instruction and its operands and dispatch it
;                      to the correct handler
.proc fetch_and_dispatch
;    lda #<msg_fetch_and_dispatch
;    sta gREG::r6L
;    lda #>msg_fetch_and_dispatch
;    sta gREG::r6H
;    jsr printf

    ; Default to 2OP large, because then we can OR in the correct bits for small constant/variable for 2OP instructions
    lda #$0f
    sta optypes
    lda #$ff
    sta optypes+1

    ; Make sure we're on the right RAM bank
    lda zpu_pc+2
    sta BANK_RAM

    ; Fetch and save the opcode
    jsr pc_fetch_and_advance
    sta opcode

    ; Need to check the top three bits to find out what kind of opcode it is
    lda #$20
    bit opcode

    ; If bit 7 is clear, it's a long opcode (2OP)
    bpl @fetch_long

    ; If bit 6 is set, it's a variable opcode
    bvs fetch_varops

@fetch_short:
    ; It's a short opcode, check operands
    lda opcode
    cmp #$b0
    bcs @fetch_0op
    stz operand_0    ; Clears r0 high byte in case of small constant
    cmp #$90
    bcs @fetch_1op1byte

    ; For large operand, fetch high byte first
    jsr pc_fetch_and_advance
    sta operand_0

@fetch_1op1byte:
    ; For small/variable operand, fetch low byte
    jsr pc_fetch_and_advance
    sta operand_0+1

    ; Remember that we have one operand
    lda #1
    sta num_operands

    ; Save argument type, which is bits 5-4 of the opcode, so we need to shift left 2 bits and
    ; set the remaining bits to mark them as omitted
    lda opcode
    asl
    asl
    ora #$3f
    sta optypes
    
    ; If the first operand is a variable, load it
    cmp #$bf
    bne fetched
    lda operand_0+1
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx operand_0
    sty operand_0+1
    bra fetched

@fetch_0op:
    ; Remember that we have no operands
    stz num_operands

    ; Check for extended opcode
    cmp #$be
    bne fetched

    ; Fetch the extended opcode and its parameters
    jsr pc_fetch_and_advance
    sta opcode_ext
    jmp fetch_varops

@fetch_long:
    ; Save the flags so we can figure out operand types later
    php

    ; Remember that we have two operands
    lda #2
    sta num_operands

    ; Fetch both operands and store in r0/r1 low byte
    jsr pc_fetch_and_advance
    stz operand_0
    sta operand_0+1
    jsr pc_fetch_and_advance
    stz operand_1
    sta operand_1+1

    ; Store the operand types:
    ;  - First operand type is bit 6, second is bit 5.
    ;  - Set is variable, clear is small constant.

    ; Check first operand first
    plp
    php
    bvs @first_is_var
    ;smb6 optypes
    lda optypes
    ora #$40
    sta optypes
    bra @check_second_op

    ; First operand is a variable, load the value into r1
@first_is_var:
    ;smb7 optypes
    lda optypes
    ora #$80
    sta optypes
    lda operand_0+1
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx operand_0
    sty operand_0+1

@check_second_op:
    plp
    bne @second_is_var
    ;smb4 optypes
    lda optypes
    ora #$10
    sta optypes
    bra fetched

    ; Second operand is a variable, load the value into r1
@second_is_var:
    ;smb5 optypes
    lda optypes
    ora #$20
    sta optypes
    lda operand_1+1
    clc ; Pop stack if needed
    jsr fetch_varvalue
    stx operand_1
    sty operand_1+1

    ; FALL THRU INTENTIONAL
.endproc

.proc fetched
    ; Okay, the instruction operands are fetched at this point, with the values stored as follows:
    ;  opcode:      Z-machine opcode
    ;  opcode_ext:  Z-machine extended opcode (if opcode=$be)
    ;  optypes:     operand types
    ;  r0-r7:       operand 1-8 values (big-endian)

    ; Now we jump to the correct handler based on the opcode
    lda opcode
    asl
    tax
    bcc @dispatch_long
    jmp (opcode_vectors_upper,x)
@dispatch_long:
    jmp (opcode_vectors_lower,x)
.endproc

; fetch_4_operands - Helper function to fetch up to 4 operands and store them in r0-r7
;
; In:   a           - Operand types
;       x           - Offset to first register
; Out:  carry       - Set if we hit an omitted operand
.proc fetch_4_operands
optype_shift = gREG::r11L   ; temporary storage for checking operands
    ldy #4
    sta optype_shift
@load_operand:
    bit optype_shift
    bmi @is_var_or_omitted
    bvs @is_short

    ; It's a long, so read two bytes into the register (stored big-endian, so L and H will be wrong)
    jsr pc_fetch_and_advance
    bra @load_op_lowbyte

@is_short:
    ; It's a short, so set the high byte to 0 and read the low byte
    lda #0

    ; Store the constant in the register
@load_op_lowbyte:
    sta operand_0,x
    inx
    jsr pc_fetch_and_advance
    sta operand_0,x
    inx
    bra @step_next_operand

@is_var_or_omitted:
    ; If bit 6 is also set we're at the end of the operands, so set carry to indicate end of operands and return
    bvc @is_variable
    sec
    rts

@is_variable:
    ; For variables, save x/y and fetch the variable value
    phy
    phx
    jsr pc_fetch_and_advance
    clc ; Pop stack if needed
    jsr fetch_varvalue
    txa
    plx
    sta operand_0,x
    inx
    sty operand_0,x
    inx
    ply
    ; And fall through to check next operand

@step_next_operand:
    ; See if we have another operand
    asl optype_shift
    asl optype_shift
    dey
    bne @load_operand
    clc ; May have more operands
    rts
.endproc

.proc op_illegal
    ; Exit wtih illegal opcode message
    lda opcode
    sta operand_0
    lda #ERR_ILLEGAL_OPCODE

    ; Fall through to print error and exit
.endproc

; print_error_and_exit - Prints an error message and exits
;
; In:   a           - Error message number
;       op0-op9     - Error parameters to print
.proc print_error_and_exit
    ; Reset the screen if we don't have a debug window
    bit window_debug
    bpl @showerror
    pha
    jsr CINT
    lda #2
    jsr SCREEN_SET_MODE
    lda #3
    jsr SCREEN_SET_CHARSET
    dec printf_use_chrout
    stz window_debug
    pla

@showerror:
    ; Get an offset into the error message table
    asl
    tax
    lda error_msg_list,x
    sta gREG::r6L
    lda error_msg_list+1,x
    sta gREG::r6H

    ; Print the string and any parameters
    jsr printf

@exit:
    ; Exit to BASIC
    clc
    jmp RESTORE_BASIC
.endproc

.proc printf_putchr
    bit printf_use_chrout
    bmi @use_chrout
    sec
    jmp win_putchr
@use_chrout:
    pha
    tya
    cpy #$41
    bcc @1
    cpy #$5b
    bcc @2
    cpy #$61
    bcc @1
    cpy #$7b
    bcs @1
    sec
    sbc #$20
    bra @1
@2: clc
    adc #$20
@1: jsr CHROUT
    pla
    rts
.endproc

.proc printf
    ; Print the PC
    pha
    lda window_debug
    bpl @have_debug_window
    pla
    rts

@have_debug_window:
    phx
    phy
    ldx #0
    ldy #'p'
    jsr printf_putchr
    ldy #'c'
    jsr printf_putchr
    ldy #'('
    jsr printf_putchr
    ldy zpu_pc+2
    jsr printhex
    ldy #':'
    jsr printf_putchr
    ldy zpu_pc+1
    jsr printhex
    ldy zpu_pc
    jsr printhex
    ldy #')'
    jsr printf_putchr
    ldy #' '
    jsr printf_putchr
    ldy #'b'
    jsr printf_putchr
    ldy #'p'
    jsr printf_putchr
    ldy #'('
    jsr printf_putchr
    ldy zpu_bp+1
    jsr printhex
    ldy zpu_bp
    jsr printhex
    ldy #')'
    jsr printf_putchr
    ldy #' '
    jsr printf_putchr
    ldy #'s'
    jsr printf_putchr
    ldy #'p'
    jsr printf_putchr
    ldy #'('
    jsr printf_putchr
    ldy zpu_sp+1
    jsr printhex
    ldy zpu_sp
    jsr printhex
    ldy #')'
    jsr printf_putchr
    ldy #' '
    jsr printf_putchr

    ; Print the string in r6
    ldx #0
    ldy #$ff
@1: iny
    lda (gREG::r6),y
    beq @exit

    ; Check for parameter characters (#=print byte param, %=print word param, $=print string)
    cmp #'#'
    beq @print_byteparam
    cmp #'%'
    beq @print_wordparam
    cmp #'@'
    beq @print_bewordparam
    cmp #'$'
    beq @print_string
    cmp #13
    beq @asis
    cmp #32
    bcc @1
    cmp #65
    bcc @asis
    cmp #91
    bcs @notlower
    clc
    adc #$20
    bra @asis
@notlower:
    cmp #$c1
    bcc @asis
    cmp #$db
    bcs @asis
    sec
    sbc #$80
@asis:
    phx
    phy
    tay
    ldx #0
    lda window_debug
    jsr printf_putchr
    ply
    plx
    bra @1

@exit:
    jsr GETIN
    cmp #' '
    bne @exit
    ply
    plx
    pla
    rts

@print_bewordparam:
    ; Print high byte
    phy
    lda operand_0,x
    tay
    lda window_debug
    jsr printhex

    ; Print low byte
    ply
    phy
    lda operand_0+1,x
    bra @print_and_next

@print_wordparam:
    ; Print high byte
    phy
    lda operand_0+1,x
    tay
    lda window_debug
    jsr printhex
    ply

@print_byteparam:
    ; Print low byte
    phy
    lda operand_0,x
@print_and_next:
    tay
    lda window_debug
    jsr printhex
    ply
    inx
    inx
    jmp @1

@print_string:
    ; Print string
    phx
    phy
    lda operand_0,x
    sta gREG::r14L
    lda operand_0+1,x
    sta gREG::r14H
    ldy #0
@2: lda (gREG::r14),y
    beq @3
    phy
    tay
    ldx #0
    lda window_debug
    jsr printf_putchr
    ply
    iny
    bne @2
@3: ply
    plx
    inx
    inx
    jmp @1
.endproc

.proc printhex
    phx
    phy
    pha
    tya
    lsr
    lsr
    lsr
    lsr
    tay
    lda hexchars,y
    tay
    ldx #0
    pla
    jsr printf_putchr
    ply
    phy
    pha
    tya
    and #$0f
    tay
    lda hexchars,y
    tay
    pla
    sec
    jsr printf_putchr
    ply
    plx
    rts
.endproc

.proc op_quit
    lda #SUCCESS
    jmp print_error_and_exit
.endproc

.proc debugprtstr
    pha
    phx
    phy
    ldx #0
    ldy #0
@prtloop:
    lda (gREG::r6),y
    beq @dun
    phy
    tay
    lda window_main
    sec
    jsr win_putchr
    ply
    iny
    bne @prtloop
@dun:
    ply
    plx
    pla
    rts
.endproc

.rodata

dbgstr_testline: .byte "this is a test line that should be a little longer than 80 characters like hollywood.", CH::ENTER, 0
dbgstr_unicode: .byte "unicode:", CH::ENTER, 0
dbgstr_font3: .byte "z-machine font 3:", CH::ENTER, 0

.proc debugchrdump
;    lda #<dbgstr_testline
;    sta gREG::r6L
;    lda #>dbgstr_testline
;    sta gREG::r6H
;    jsr debugprtstr

    lda #<dbgstr_unicode
    sta gREG::r6L
    lda #>dbgstr_unicode
    sta gREG::r6H
    jsr debugprtstr

    lda window_main
    ldx #0
    ldy #32
@loopa:
    sec
    jsr win_putchr
    iny
    cpy #127
    bne @loopa
    ldy #160
@loopb:
    sec
    jsr win_putchr
    iny
    bne @loopb
    ldx #1
@loopc:
    sec
    jsr win_putchr
    iny
    cpy #128
    bne @loopc
    ldx #$20
    ldy #0
@loopd:
    sec
    jsr win_putchr
    iny
    cpy #$a0
    bne @loopd
    ldx #$25
    ldy #0
@loope:
    sec
    jsr win_putchr
    iny
    cpy #$a0
    bne @loope
    ldx #0
    ldy #$0d
    sec
    jsr win_putchr
    sec
    jsr win_putchr

    lda #<dbgstr_font3
    sta gREG::r6L
    lda #>dbgstr_font3
    sta gREG::r6H
    jsr debugprtstr

    lda window_main
    ldx #$e0
    ldy #32
@loopz:
    sec
    jsr win_putchr
    iny
    cpy #127
    bne @loopz

    ldx #0
    ldy #$0d
    sec
    jsr win_putchr
    sec
    jsr win_putchr
    rts
.endproc

.rodata

opcode_vectors_lower:
    .word op_illegal                    ; Opcode $00 - illegal
    .word op_je                         ; Opcode $01 - je a b ?(label)
    .word op_jl                         ; Opcode $02 - jl a b ?(label)
    .word op_jg                         ; Opcode $03 - jg a b ?(label)
    .word op_dec_chk                    ; Opcode $04 - dec_chk (variable) value ?(label)
    .word op_inc_chk                    ; Opcode $05 - inc_chk (variable) value ?(label)
    .word op_jin                        ; Opcode $06 - jin obj1 obj2 ?(label)
    .word op_test                       ; Opcode $07 - test bitmap flags ?(label)
    .word op_or                         ; Opcode $08 - or a b -> (result)
    .word op_and                        ; Opcode $09 - and a b -> (result)
    .word op_test_attr                  ; Opcode $0a - test_attr object attribute ?(label)
    .word op_set_attr                   ; Opcode $0b - set_attr object attribute
    .word op_clear_attr                 ; Opcode $0c - clear_attr object attribute
    .word op_store                      ; Opcode $0d - store (variable) value
    .word op_insert_obj                 ; Opcode $0e - insert_obj object destination
    .word op_loadw                      ; Opcode $0f - loadw array word-index -> (result)

    .word op_loadb                      ; Opcode $10 - loadb array byte-index -> (result)
    .word op_get_prop                   ; Opcode $11 - get_prop object property -> (result)
    .word op_get_prop_addr              ; Opcode $12 - get_prop_addr object property -> (result)
    .word op_get_next_prop              ; Opcode $13 - get_next_prop object property -> (result)
    .word op_add                        ; Opcode $14 - add a b -> (result)
    .word op_sub                        ; Opcode $15 - sub a b -> (result)
    .word op_mul                        ; Opcode $16 - mul a b -> (result)
    .word op_div                        ; Opcode $17 - div a b -> (result)
    .word op_mod                        ; Opcode $18 - mod a b -> (result)
    .word op_call_save                  ; Opcode $19 - call_2s routine arg1 -> (result)
    .word op_call_void                  ; Opcode $1a - call_2n routine arg1
    .word op_set_colour                 ; Opcode $1b - set_colour foreground background
    .word op_throw                      ; Opcode $1c - throw value stack-frame
    .word op_illegal                    ; Opcode $1d - illegal
    .word op_illegal                    ; Opcode $1e - illegal
    .word op_illegal                    ; Opcode $1f - illegal

    .word op_illegal                    ; Opcode $20 - illegal
    .word op_je                         ; Opcode $21 - je a b ?(label)
    .word op_jl                         ; Opcode $22 - jl a b ?(label)
    .word op_jg                         ; Opcode $23 - jg a b ?(label)
    .word op_dec_chk                    ; Opcode $24 - dec_chk (variable) value ?(label)
    .word op_inc_chk                    ; Opcode $25 - inc_chk (variable) value ?(label)
    .word op_jin                        ; Opcode $26 - jin obj1 obj2 ?(label)
    .word op_test                       ; Opcode $27 - test bitmap flags ?(label)
    .word op_or                         ; Opcode $28 - or a b -> (result)
    .word op_and                        ; Opcode $29 - and a b -> (result)
    .word op_test_attr                  ; Opcode $2a - test_attr object attribute ?(label)
    .word op_set_attr                   ; Opcode $2b - set_attr object attribute
    .word op_clear_attr                 ; Opcode $2c - clear_attr object attribute
    .word op_store                      ; Opcode $2d - store (variable) value
    .word op_insert_obj                 ; Opcode $2e - insert_obj object destination
    .word op_loadw                      ; Opcode $2f - loadw array word-index -> (result)

    .word op_loadb                      ; Opcode $30 - loadb array byte-index -> (result)
    .word op_get_prop                   ; Opcode $31 - get_prop object property -> (result)
    .word op_get_prop_addr              ; Opcode $32 - get_prop_addr object property -> (result)
    .word op_get_next_prop              ; Opcode $33 - get_next_prop object property -> (result)
    .word op_add                        ; Opcode $34 - add a b -> (result)
    .word op_sub                        ; Opcode $35 - sub a b -> (result)
    .word op_mul                        ; Opcode $36 - mul a b -> (result)
    .word op_div                        ; Opcode $37 - div a b -> (result)
    .word op_mod                        ; Opcode $38 - mod a b -> (result)
    .word op_call_save                  ; Opcode $39 - call_2s routine arg1 -> (result)
    .word op_call_void                  ; Opcode $3a - call_2n routine arg1
    .word op_set_colour                 ; Opcode $3b - set_colour foreground background
    .word op_throw                      ; Opcode $3c - throw value stack-frame
    .word op_illegal                    ; Opcode $3d - illegal
    .word op_illegal                    ; Opcode $3e - illegal
    .word op_illegal                    ; Opcode $3f - illegal

    .word op_illegal                    ; Opcode $40 - illegal
    .word op_je                         ; Opcode $41 - je a b ?(label)
    .word op_jl                         ; Opcode $42 - jl a b ?(label)
    .word op_jg                         ; Opcode $43 - jg a b ?(label)
    .word op_dec_chk                    ; Opcode $44 - dec_chk (variable) value ?(label)
    .word op_inc_chk                    ; Opcode $45 - inc_chk (variable) value ?(label)
    .word op_jin                        ; Opcode $46 - jin obj1 obj2 ?(label)
    .word op_test                       ; Opcode $47 - test bitmap flags ?(label)
    .word op_or                         ; Opcode $48 - or a b -> (result)
    .word op_and                        ; Opcode $49 - and a b -> (result)
    .word op_test_attr                  ; Opcode $4a - test_attr object attribute ?(label)
    .word op_set_attr                   ; Opcode $4b - set_attr object attribute
    .word op_clear_attr                 ; Opcode $4c - clear_attr object attribute
    .word op_store                      ; Opcode $4d - store (variable) value
    .word op_insert_obj                 ; Opcode $4e - insert_obj object destination
    .word op_loadw                      ; Opcode $4f - loadw array word-index -> (result)

    .word op_loadb                      ; Opcode $50 - loadb array byte-index -> (result)
    .word op_get_prop                   ; Opcode $51 - get_prop object property -> (result)
    .word op_get_prop_addr              ; Opcode $52 - get_prop_addr object property -> (result)
    .word op_get_next_prop              ; Opcode $53 - get_next_prop object property -> (result)
    .word op_add                        ; Opcode $54 - add a b -> (result)
    .word op_sub                        ; Opcode $55 - sub a b -> (result)
    .word op_mul                        ; Opcode $56 - mul a b -> (result)
    .word op_div                        ; Opcode $57 - div a b -> (result)
    .word op_mod                        ; Opcode $58 - mod a b -> (result)
    .word op_call_save                  ; Opcode $59 - call_2s routine arg1 -> (result)
    .word op_call_void                  ; Opcode $5a - call_2n routine arg1
    .word op_set_colour                 ; Opcode $5b - set_colour foreground background
    .word op_throw                      ; Opcode $5c - throw value stack-frame
    .word op_illegal                    ; Opcode $5d - illegal
    .word op_illegal                    ; Opcode $5e - illegal
    .word op_illegal                    ; Opcode $5f - illegal

    .word op_illegal                    ; Opcode $60 - illegal
    .word op_je                         ; Opcode $61 - je a b ?(label)
    .word op_jl                         ; Opcode $62 - jl a b ?(label)
    .word op_jg                         ; Opcode $63 - jg a b ?(label)
    .word op_dec_chk                    ; Opcode $64 - dec_chk (variable) value ?(label)
    .word op_inc_chk                    ; Opcode $65 - inc_chk (variable) value ?(label)
    .word op_jin                        ; Opcode $66 - jin obj1 obj2 ?(label)
    .word op_test                       ; Opcode $67 - test bitmap flags ?(label)
    .word op_or                         ; Opcode $68 - or a b -> (result)
    .word op_and                        ; Opcode $69 - and a b -> (result)
    .word op_test_attr                  ; Opcode $6a - test_attr object attribute ?(label)
    .word op_set_attr                   ; Opcode $6b - set_attr object attribute
    .word op_clear_attr                 ; Opcode $6c - clear_attr object attribute
    .word op_store                      ; Opcode $6d - store (variable) value
    .word op_insert_obj                 ; Opcode $6e - insert_obj object destination
    .word op_loadw                      ; Opcode $6f - loadw array word-index -> (result)

    .word op_loadb                      ; Opcode $70 - loadb array byte-index -> (result)
    .word op_get_prop                   ; Opcode $71 - get_prop object property -> (result)
    .word op_get_prop_addr              ; Opcode $72 - get_prop_addr object property -> (result)
    .word op_get_next_prop              ; Opcode $73 - get_next_prop object property -> (result)
    .word op_add                        ; Opcode $74 - add a b -> (result)
    .word op_sub                        ; Opcode $75 - sub a b -> (result)
    .word op_mul                        ; Opcode $76 - mul a b -> (result)
    .word op_div                        ; Opcode $77 - div a b -> (result)
    .word op_mod                        ; Opcode $78 - mod a b -> (result)
    .word op_call_save                  ; Opcode $79 - call_2s routine arg1 -> (result)
    .word op_call_void                  ; Opcode $7a - call_2n routine arg1
    .word op_set_colour                 ; Opcode $7b - set_colour foreground background
    .word op_throw                      ; Opcode $7c - throw value stack-frame
    .word op_illegal                    ; Opcode $7d - illegal
    .word op_illegal                    ; Opcode $7e - illegal
    .word op_illegal                    ; Opcode $7f - illegal

opcode_vectors_upper:
    .word op_jz                         ; Opcode $80 - jz a ?(label)
    .word op_get_sibling                ; Opcode $81 - get_sibling object -> (result) ?(label)
    .word op_get_child                  ; Opcode $82 - get_child object -> (result) ?(label)
    .word op_get_parent                 ; Opcode $83 - get_parent object -> (result)
    .word op_get_prop_len               ; Opcode $84 - get_prop_len property-address -> (result) 	
    .word op_inc                        ; Opcode $85 - inc (variable)
    .word op_dec                        ; Opcode $86 - dec (variable)
    .word op_print_addr                 ; Opcode $87 - print_addr byte-address-of-string
    .word op_call_save                  ; Opcode $88 - call_1s routine -> (result)
    .word op_remove_obj                 ; Opcode $89 - remove_obj object
    .word op_print_obj                  ; Opcode $8a - print_obj object
    .word op_ret                        ; Opcode $8b - ret value
    .word op_jump                       ; Opcode $8c - jump (label)
    .word op_print_paddr                ; Opcode $8d - print_paddr packed-address-of-string
    .word op_load                       ; Opcode $8e - load (variable) -> (result)
    .word op_not_or_callvoid            ; Opcode $8f - v1-4: not value -> (result), v5+: call_1n routine

    .word op_jz                         ; Opcode $90 - jz a ?(label)
    .word op_get_sibling                ; Opcode $91 - get_sibling object -> (result) ?(label)
    .word op_get_child                  ; Opcode $92 - get_child object -> (result) ?(label)
    .word op_get_parent                 ; Opcode $93 - get_parent object -> (result)
    .word op_get_prop_len               ; Opcode $94 - get_prop_len property-address -> (result) 	
    .word op_inc                        ; Opcode $95 - inc (variable)
    .word op_dec                        ; Opcode $96 - dec (variable)
    .word op_print_addr                 ; Opcode $97 - print_addr byte-address-of-string
    .word op_call_save                  ; Opcode $98 - call_1s routine -> (result)
    .word op_remove_obj                 ; Opcode $99 - remove_obj object
    .word op_print_obj                  ; Opcode $9a - print_obj object
    .word op_ret                        ; Opcode $9b - ret value
    .word op_jump                       ; Opcode $9c - jump (label)
    .word op_print_paddr                ; Opcode $9d - print_paddr packed-address-of-string
    .word op_load                       ; Opcode $9e - load (variable) -> (result)
    .word op_not_or_callvoid            ; Opcode $9f - v1-4: not value -> (result), v5+: call_1n routine

    .word op_jz                         ; Opcode $a0 - jz a ?(label)
    .word op_get_sibling                ; Opcode $a1 - get_sibling object -> (result) ?(label)
    .word op_get_child                  ; Opcode $a2 - get_child object -> (result) ?(label)
    .word op_get_parent                 ; Opcode $a3 - get_parent object -> (result)
    .word op_get_prop_len               ; Opcode $a4 - get_prop_len property-address -> (result) 	
    .word op_inc                        ; Opcode $a5 - inc (variable)
    .word op_dec                        ; Opcode $a6 - dec (variable)
    .word op_print_addr                 ; Opcode $a7 - print_addr byte-address-of-string
    .word op_call_save                  ; Opcode $a8 - call_1s routine -> (result)
    .word op_remove_obj                 ; Opcode $a9 - remove_obj object
    .word op_print_obj                  ; Opcode $aa - print_obj object
    .word op_ret                        ; Opcode $ab - ret value
    .word op_jump                       ; Opcode $ac - jump (label)
    .word op_print_paddr                ; Opcode $ad - print_paddr packed-address-of-string
    .word op_load                       ; Opcode $ae - load (variable) -> (result)
    .word op_not_or_callvoid            ; Opcode $af - v1-4: not value -> (result), v5+: call_1n routine

    .word op_rtrue                      ; Opcode $b0 - rtrue
    .word op_rfalse                     ; Opcode $b1 - rfalse
    .word op_print                      ; Opcode $b2 - print (literal-string)
    .word op_print_ret                  ; Opcode $b3 - print_ret (literal-string)
    .word op_nop                        ; Opcode $b4 - nop
    .word op_save                       ; Opcode $b5 - versions 1-3: save ?(label)
                                        ;            - version 4: save -> (result)
                                        ;            - version 5+: illegal
    .word op_restore                    ; Opcode $b6 - versions 1-3: restore ?(label)
                                        ;            - version 4: restore -> (result)
                                        ;            - version 5+: illegal
    .word op_restart                    ; Opcode $b7 - restart
    .word op_ret_popped                 ; Opcode $b8 - ret_popped
    .word op_pop_or_catch               ; Opcode $b9 - versions 1-4: pop
                                        ;            - versions 5+: catch -> (result)
    .word op_quit                       ; Opcode $ba - quit
    .word op_new_line                   ; Opcode $bb - new_line
    .word op_show_status                ; Opcode $bc - versions 1-3: show_status
                                        ;            - versions 4+: illegal
    .word op_verify                     ; Opcode $bd - verify ?(label)
    .word op_extended                   ; Opcode $be - extended opcode
    .word op_piracy                     ; Opcode $bf - piracy ?(label)

    .word op_illegal                    ; Opcode $c0 - illegal
    .word op_je                         ; Opcode $c1 - je a b c d ?(label)
    .word op_jl                         ; Opcode $c2 - jl a b ?(label)
    .word op_jg                         ; Opcode $c3 - jg a b ?(label)
    .word op_dec_chk                    ; Opcode $c4 - dec_chk (variable) value ?(label)
    .word op_inc_chk                    ; Opcode $c5 - inc_chk (variable) value ?(label)
    .word op_jin                        ; Opcode $c6 - jin obj1 obj2 ?(label)
    .word op_test                       ; Opcode $c7 - test bitmap flags ?(label)
    .word op_or                         ; Opcode $c8 - or a b -> (result)
    .word op_and                        ; Opcode $c9 - and a b -> (result)
    .word op_test_attr                  ; Opcode $ca - test_attr object attribute ?(label)
    .word op_set_attr                   ; Opcode $cb - set_attr object attribute
    .word op_clear_attr                 ; Opcode $cc - clear_attr object attribute
    .word op_store                      ; Opcode $cd - store (variable) value
    .word op_insert_obj                 ; Opcode $ce - insert_obj object destination
    .word op_loadw                      ; Opcode $cf - loadw array word-index -> (result)

    .word op_loadb                      ; Opcode $d0 - loadb array byte-index -> (result)
    .word op_get_prop                   ; Opcode $d1 - get_prop object property -> (result)
    .word op_get_prop_addr              ; Opcode $d2 - get_prop_addr object property -> (result)
    .word op_get_next_prop              ; Opcode $d3 - get_next_prop object property -> (result)
    .word op_add                        ; Opcode $d4 - add a b -> (result)
    .word op_sub                        ; Opcode $d5 - sub a b -> (result)
    .word op_mul                        ; Opcode $d6 - mul a b -> (result)
    .word op_div                        ; Opcode $d7 - div a b -> (result)
    .word op_mod                        ; Opcode $d8 - mod a b -> (result)
    .word op_call_save                  ; Opcode $d9 - call_2s routine arg1 -> (result)
    .word op_call_void                  ; Opcode $da - call_2n routine arg1
    .word op_set_colour                 ; Opcode $db - versions 1-5: set_colour foreground background
                                        ;            - versions 6+: set_colour foreground background window
    .word op_throw                      ; Opcode $dc - throw value stack-frame
    .word op_illegal                    ; Opcode $dd - illegal
    .word op_illegal                    ; Opcode $de - illegal
    .word op_illegal                    ; Opcode $df - illegal

    .word op_call_save                  ; Opcode $e0 - call_vs routine ...0 to 3 args... -> (result)
    .word op_storew                     ; Opcode $e1 - storew array word-index value
    .word op_storeb                     ; Opcode $e2 - storeb array byte-index value
    .word op_put_prop                   ; Opcode $e3 - put_prop object property value
    .word op_read                       ; Opcode $e4 - versions 1-3: sread text parse
                                        ;            - version 4: sread text parse time routine
                                        ;            - versions 5+: aread text parse time routine -> (result)
    .word op_print_char                 ; Opcode $e5 - print_char output-character-code
    .word op_print_num                  ; Opcode $e6 - print_num value
    .word op_random                     ; Opcode $e7 - random range -> (result)
    .word op_push                       ; Opcode $e8 - push value
    .word op_pull                       ; Opcode $e9 - versions 1-5: pull (variable)
                                        ;            - versions 6+: pull stack -> (result)
    .word op_split_window               ; Opcode $ea - split_window lines
    .word op_set_window                 ; Opcode $eb - set_window window
    .word op_call_save                  ; Opcode $ec - call_vs2 routine ...0 to 7 args... -> (result)
    .word op_erase_window               ; Opcode $ed - erase_window window
    .word op_erase_line                 ; Opcode $ee - erase_line value
    .word op_set_cursor                 ; Opcode $ef - versions 4-5: set_cursor line column
                                        ;            - versions 6+: set_cursor line column window

    .word op_get_cursor                 ; Opcode $f0 - get_cursor array
    .word op_set_text_style             ; Opcode $f1 - set_text_style style
    .word op_buffer_mode                ; Opcode $f2 - buffer_mode flag
    .word op_output_stream              ; Opcode $f3 - versions 3-4: output_stream number
                                        ;            - version 5: output_stream number table
                                        ;            - versions 6+: output_stream number table width
    .word op_input_stream               ; Opcode $f4 - input_stream number
    .word op_sound_effect               ; Opcode $f5 - sound_effect number effect volume routine
    .word op_read_char                  ; Opcode $f6 - read_char 1 time routine -> (result)
    .word op_scan_table                 ; Opcode $f7 - scan_table x table len form -> (result)
    .word op_not_v5                     ; Opcode $d8 - Version 5+: not value -> (result)
    .word op_call_void                  ; Opcode $f9 - call_vn routine ...up to 3 args...
    .word op_call_void                  ; Opcode $fa - call_vn2 routine ...up to 7 args...
    .word op_tokenise                   ; Opcode $fb - tokenise text parse dictionary flag
    .word op_encode_text                ; Opcode $fc - encode_text zscii-text length from coded-text
    .word op_copy_table                 ; Opcode $fd - copy_table first second size
    .word op_print_table                ; Opcode $fe - print_table zscii-text width height skip
    .word op_check_arg_count            ; Opcode $ff - check_arg_count argument-number

numtobit:
    .byte V1, V2, V3, V4, V5, V6, V7, V8

error_msg_list:
    .word error_msg_success
    .word error_msg_illegal_version
    .word error_msg_illegal_opcode
    .word error_msg_bad_checksum
    .word error_msg_cant_open_file
    .word error_msg_stack_empty
    .word error_msg_invalid_param
    .word error_msg_illegal_extended
    .word error_msg_invalid_property
    .word error_msg_invalid_parse_char
    .word error_msg_stream_overflow
    .word error_msg_todo

hexchars:                       .byte   "0123456789abcdef"

msg_launching:                  .byte "Launching Z-machine", CH::ENTER, 0
msg_fetch_and_dispatch:         .byte "Fetch and dispatch", CH::ENTER, 0
error_header:                   .byte CH::ENTER, CH::ENTER, "ERROR: ", 0
error_msg_success:              .byte "Goodbye!", 0
error_msg_illegal_version:      .byte "Illegal version #", 0
error_msg_illegal_opcode:       .byte "Illegal opcode #", 0
error_msg_bad_checksum:         .byte "Bad checksum %, expected %", 0
error_msg_cant_open_file:       .byte "Can't open file $, error #", 0
error_msg_stack_empty:          .byte "Can't pop from empty stack", 0
error_msg_invalid_param:        .byte "Invalid parameters", 0
error_msg_illegal_extended:     .byte "Illegal extended opcode #", 0
error_msg_invalid_property:     .byte "Invalid property obj @ prop @", 0
error_msg_invalid_parse_char:   .byte "Invalid character # in word while parsing", 0
error_msg_stream_overflow:      .byte "Too many table streams opened", 0
error_msg_todo:                 .byte "Unimplemented, TODO", 0
