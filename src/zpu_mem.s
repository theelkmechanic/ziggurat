; Memory handling routines

.include "ziggurat.inc"
.include "zpu.inc"

.data
v_decode_paddr_r: .word decode_waddr ; default the decoders to v1-3
v_decode_paddr_s: .word decode_waddr

.bss
offset_r_premul: .res 3
offset_s_premul: .res 3
retreat_save: .res 1

.code

.proc op_load
    ; Get the result variable # for printing
    jsr pc_fetch_and_advance
    sta operand_1
    ldx #<msg_loading
    stx gREG::r6L
    ldx #>msg_loading
    stx gREG::r6H
    jsr printf

    ; Fetch the variable # from r0
    lda operand_0+1
    sec ; Modify stack in place
    jsr fetch_varvalue

    ; And store it in the result variable
    lda operand_1
    clc ; Push stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc op_loadb
    ; Get the result variable # for printing
    jsr pc_fetch_and_advance
    sta operand_2
    ldx #<msg_loading_byte
    stx gREG::r6L
    ldx #>msg_loading_byte
    stx gREG::r6H
    jsr printf

    ; Add index to array base
    clc
    lda operand_0+1
    adc operand_1+1
    tay
    lda operand_0
    adc operand_1
    tax

    ; Decode the address into zpu_mem
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2

    ; Read one byte
    pushb zpu_mem+2
    lda (zpu_mem)
    tay
    ldx #0
    popb

    ; Store it in the result
    lda operand_2
    clc ; Push stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc op_loadw
    ; Get the result variable # for printing
    jsr pc_fetch_and_advance
    sta operand_2
    ldx #<msg_loading_word
    stx gREG::r6L
    ldx #>msg_loading_word
    stx gREG::r6H
    jsr printf

    ; Add index to array base
    asl operand_1+1
    rol operand_1
    clc
    lda operand_0+1
    adc operand_1+1
    tay
    lda operand_0
    adc operand_1
    tax

    ; Decode the address into zpu_mem
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2

    ; Read two byte
    pushb zpu_mem+2
    jsr mem_fetch_and_advance
    tax
    lda (zpu_mem)
    tay
    popb

    ; Store it in the result
    lda operand_2
    clc ; Push stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc op_store
    lda #<msg_storing
    sta gREG::r6L
    lda #>msg_storing
    sta gREG::r6H
    jsr printf

    ; Variable # is in r0, value in r1
    lda operand_0+1
    ldx operand_1
    ldy operand_1+1
    sec ; Modify stack in place
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc op_storeb
    ldx #<msg_storing_byte
    stx gREG::r6L
    ldx #>msg_storing_byte
    stx gREG::r6H
    jsr printf

    ; Add index to array base
    clc
    lda operand_0+1
    adc operand_1+1
    tay
    lda operand_0
    adc operand_1
    tax

    ; Decode the address into zpu_mem
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2

    ; Write one byte
    pushb zpu_mem+2
    lda operand_2+1
    sta (zpu_mem)
    popb
    jmp fetch_and_dispatch
.endproc

.proc op_storew
    ldx #<msg_storing_word
    stx gREG::r6L
    ldx #>msg_storing_word
    stx gREG::r6H
    jsr printf

    ; Add index to array base
    asl operand_1+1
    rol operand_1
    clc
    lda operand_0+1
    adc operand_1+1
    tay
    lda operand_0
    adc operand_1
    tax

    ; Decode the address into zpu_mem
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2

    ; Write two bytes
    pushb zpu_mem+2
    lda operand_2
    jsr mem_store_and_advance
    lda operand_2+1
    sta (zpu_mem)
    popb
    jmp fetch_and_dispatch
.endproc

; memory_init - Initialize memory handling
;
; Prerequisite: The ZIF must already be loaded
.proc memory_init
    ; Switch to bank 1 so we can read the header
    pushb #1

    ; Set up the packed address decoder vectors based on the ZIF version

    ; For versions 1-3, we don't need to change anything
    chkver V4|V5|V6|V7|V8,alldone

    ; Check for version 4-5 and use 4P if so
    chkver V4|V5,chkversion8
    ldx #<decode_packed4
    ldy #>decode_packed4
    bra setbothvectors

    ; Check for version 8 and use 8P if so
chkversion8:
    chkver V8,mustbe6or7
    ldx #<decode_packed8
    ldy #>decode_packed8
setbothvectors:
    stx v_decode_paddr_r
    sty v_decode_paddr_r+1
setstrvector:
    stx v_decode_paddr_s
    sty v_decode_paddr_s+1

    ; Restore the bank
alldone:
    popb
    rts

    ; For version 6 or 7, we need to precalculate the routine and string offsets
mustbe6or7:
    lda ZMheader::roff+1
    sta offset_r_premul
    lda ZMheader::roff
    sta offset_r_premul+1
    stz offset_r_premul+2
    lda ZMheader::soff
    sta offset_s_premul+1
    stz offset_s_premul+2
    lda ZMheader::soff+1
    ldx #3
x2loop:
    asl
    rol offset_s_premul+1
    rol offset_s_premul+2
    asl offset_r_premul
    rol offset_r_premul+1
    rol offset_r_premul+2
    dex
    bne x2loop
    sta offset_s_premul

    ; And store the two different vectors
    ldx #<decode_packed6_routine
    ldy #>decode_packed6_routine
    stx v_decode_paddr_r
    sty v_decode_paddr_r+1
    ldx #<decode_packed6_string
    ldy #>decode_packed6_string
    bra setstrvector
.endproc

; Vectored packed address decoders
.proc decode_paddr_r
    jmp (v_decode_paddr_r)
.endproc
.proc decode_paddr_s
    jmp (v_decode_paddr_s)
.endproc


; encode_baddr - Encode bank/page into a byte address
;
; In:   a - bank
;       x - page address (hi)
; Out:  x - ZIF byte address (hi)
.proc encode_baddr
    ; Byte address hi is low 5 bits of page address plus (bank - 1) * 32
    dec
    asl
    asl
    asl
    asl
    asl
    sta gREG::r13L
    txa
    and #$1f
    ora gREG::r13L
    tax
    rts
.endproc

; decode_baddr - Decode a byte address into bank/page
;
; In: x - ZIF byte address (hi)
; Out: a - bank
; x - page address (hi)
.proc decode_baddr
    ; Page address hi is low 5 bits | $A0
    phx
    txa
    and #$1f
    ora #$a0
    tax

    ; Divide hibyte by 32 and add 1 to get bank
    pla
    lsr
    lsr
    lsr
    lsr
    lsr
    inc
    rts
.endproc

; decode_packed4 - Decode a packed address into bank/page (version 4 and 5)
;
; In: x - ZIF packed address (hi)
; y - ZIF packed address (lo)
; Out: a - bank
; x - page address (hi)
; y - page address (lo)
.proc decode_packed4
    ; Put high portion of address in zero page
    stx gREG::r11L
    stz gREG::r11H

    ; Multiply by 4
    tya
    asl
    rol gREG::r11L
    rol gREG::r11H
    asl
    rol gREG::r11L
    rol gREG::r11H
    tay

    ; And convert it to bank/page
    bra return_converted_zaddr
.endproc

; decode_waddr - Decode a word address into bank/page
;   (Note: This is also how to decode a packed address in v1-3)
;
; In: x - ZIF word address (hi)
; y - ZIF word address (lo)
; Out: a - bank
; x - page address (hi)
; y - page address (lo)
.proc decode_waddr
    ; Put high portion of address in zero page
    stx gREG::r11L
    stz gREG::r11H

    ; Multiply address by 2
    tya
    asl
    rol gREG::r11L
    rol gREG::r11H
    tay

    ; And convert it to bank/page
    bra return_converted_zaddr
.endproc

; decode_packed8 - Decode a packed address into bank/page (version 8)
;
; In: x - ZIF packed address (hi)
; y - ZIF packed address (lo)
; Out: a - bank
; x - page address (hi)
; y - page address (lo)
.proc decode_packed8
    ; Put high portion of address in zero page
    stx gREG::r11L
    stz gREG::r11H

    ; Multiply by 8
    tya
    asl
    rol gREG::r11L
    rol gREG::r11H
    asl
    rol gREG::r11L
    rol gREG::r11H
    asl
    rol gREG::r11L
    rol gREG::r11H
    tay

    ; And convert it to bank/page

    ; *** FALL THROUGH HERE IS INTENTIONAL ***
    ; *** DO NOT INSERT CODE BETWEEN THESE ***
.endproc

; return_converted_zaddr - Convert a Z-machine expanded address into bank/page address
;      (helper for word/packed addresses)
; In: r11 - 20-bit Z-machine expanded address (high 12 bits)
; y - 20-bit Z-machine expanded address (low 8 bits)
; Out: a - bank
; x - $A0 page address (hi)
; y - $A0 page address (lo) (returned unchanged since it's the same in both addresses)
.proc return_converted_zaddr
    ; Page address high is $A0 plus low 5 bits
    lda gREG::r11L
    and #$1f
    ora #$a0
    tax

    ; Bank is whole Z-machine expanded address / 8K (= shifted right 13 bits);
    ; however, we can just shift high 16 bytes by 5 since the low byte would be
    ; completely shifted out anyway (unrolled loop because loop is half the size
    ; but twice as slow)
    lda gREG::r11L
    lsr gREG::r11H
    ror
    lsr gREG::r11H
    ror
    lsr gREG::r11H
    ror
    lsr gREG::r11H
    ror
    lsr gREG::r11H
    ror

    ; And add 1 because we can't use bank 0
    clc
    adc #1
    rts
.endproc

; decode_packed6_routine - Decode a packed routine address into bank/page (version 6 and 7)
;
; In: x - ZIF packed address (hi)
; y - ZIF packed address (lo)
; Out: a - bank
; x - page address (hi)
; y - page address (lo)
.proc decode_packed6_routine
    ; Load the premultiplied routine offset into r12
    lda offset_r_premul
    sta gREG::r12
    lda offset_r_premul+1
    sta gREG::r12+1
    lda offset_r_premul+2
    sta gREG::r12+2

    ; And call the shared v6 decoder

    ; *** FALL THROUGH HERE IS INTENTIONAL ***
    ; *** DO NOT INSERT CODE BETWEEN THESE ***
.endproc

; decode_packed6 - Decode a packed address into bank/page (version 6 and 7)
;
; In: x - ZIF packed address (hi)
; y - ZIF packed address (lo)
; r12 - Offset to add to expanded address
; Out: a - bank
; x - page address (hi)
; y - page address (lo)
.proc decode_packed6
    ; Put high portion of address in zero page
    stx gREG::r11L
    stz gREG::r11H

    ; Multiply by 4
    tya
    asl
    rol gREG::r11L
    rol gREG::r11H
    asl
    rol gREG::r11L
    rol gREG::r11H

    ; Add offset
    clc
    adc gREG::r12
    tay
    lda gREG::r11L
    adc gREG::r12+1
    sta gREG::r11L
    lda gREG::r11H
    adc gREG::r12+2
    sta gREG::r11H

    ; Move y back to a
    bra return_converted_zaddr
.endproc

; decode_packed6_string - Decode a packed string address into bank/page (version 6 and 7)
;
; In: x - ZIF packed address (hi)
; y - ZIF packed address (lo)
; Out: a - bank
; x - page address (hi)
; y - page address (lo)
.proc decode_packed6_string
    ; Load the premultiplied string offset into r12
    lda offset_s_premul
    sta gREG::r12L
    lda offset_s_premul+1
    sta gREG::r12H
    lda offset_s_premul+2
    sta gREG::r12+2

    ; And call the shared v6 decoder
    bra decode_packed6
.endproc

; pc_fetch_and_advance - Fetch the next byte at the PC register and advance by 1
; (Note: Assumes bank is correctly set beforehand)
.proc pc_fetch_and_advance
    lda (zpu_pc)
    inc zpu_pc
    bne @skip
    inc zpu_pc+1
    bit zpu_pc+1
    bvc @skip
    pha
    lda #$a0
    sta zpu_pc+1
    inc zpu_pc+2
    lda zpu_pc+2
    sta VIA1::PRA
    pla
@skip:
    rts
.endproc

; mem_fetch_and_advance - Fetch the next byte at the mem register and advance by 1
; (Note: Assumes bank is correctly set beforehand)
.proc mem_fetch_and_advance
    lda (zpu_mem)
    pha
    inc zpu_mem
    beq mem_advance_finish
    pla
    rts
.endproc

; mem_store_and_advance - Store a at the mem register and advance by 1
; (Note: Assumes bank is correctly set beforehand)
.proc mem_store_and_advance
    sta (zpu_mem)
    pha
    inc zpu_mem
    beq mem_advance_finish
    pla
    rts
.endproc

; mem_advance_block - Advance mem register by 256 bytes
; (Note: Assumes bank is correctly set beforehand)
.proc mem_advance_block
    pha
    bra mem_advance_finish
.endproc

; mem_advance - Advance mem register by value in a
; (Note: Assumes bank is correctly set beforehand)
.proc mem_advance
    pha
    clc
    adc zpu_mem
    sta zpu_mem
    bcc mem_advance_skip

    ; FALL THRU INTENTIONAL
.endproc

mem_advance_finish:
    inc zpu_mem+1
    bit zpu_mem+1
    bvc mem_advance_skip
    lda #$a0
    sta zpu_mem+1
    inc zpu_mem+2
    lda zpu_mem+2
    sta VIA1::PRA
mem_advance_skip:
    pla
    rts

; read_array_word - Read one word from a word array
; In:   zpu_mem     - Start of array
;       a           - Array index
; Out:  x/y         - Word value (x=hi,y=lo)
.proc read_array_word
    asl
    pha
    jsr mem_advance
    jsr mem_fetch_and_advance
    tax
    lda (zpu_mem)
    tay
    pla
    inc
    bra mem_retreat
.endproc

; read_array_byte - Read one byte from a byte array
; In:   zpu_mem     - Start of array
;       a           - Array index
; Out:  x/y         - Byte value (x=0,y=byte)
.proc read_array_byte
    pha
    jsr mem_advance
    lda (zpu_mem)
    tay
    ldx #0
    pla

    ; FALL THRU INTENTIONAL
.endproc

; mem_retreat - Move mem register down by value in a
.proc mem_retreat
    sta retreat_save
    lda zpu_mem
    sec
    sbc retreat_save
    sta zpu_mem
    bcs @mem_retreat_skip
    dec zpu_mem+1
    lda zpu_mem+1
    cmp #$a0
    bcs @mem_retreat_skip
    lda #$bf
    sta zpu_mem+1
    dec zpu_mem+2
    lda zpu_mem+2
    sta VIA1::PRA
@mem_retreat_skip:
    lda retreat_save
    rts
.endproc

; write_array_byte - Write one word to a word array
; In:   zpu_mem     - Start of array
;       a           - Array index
;       y           - Byte value
.proc write_array_byte
    pha
    jsr mem_advance
    tya
    sta (zpu_mem)
    pla
    bra mem_retreat
.endproc

; write_array_word - Write one word to a word array
; In:   zpu_mem     - Start of array
;       a           - Array index
;       x/y         - Word value (x=hi,y=lo)
.proc write_array_word
    asl
    pha
    jsr mem_advance
    txa
    jsr mem_store_and_advance
    tya
    sta (zpu_mem)
    pla
    inc
    bra mem_retreat
.endproc

.proc op_pull
    lda #<msg_op_pull
    sta gREG::r6L
    lda #>msg_op_pull
    sta gREG::r6H
    jsr printf

    ; Check for version 6 behavior
    chkver V1|V2|V3|V4|V5,@pull_v6

    ; Pop the top value off the stack and store it in the variable
    jsr zpop_word
    lda operand_0+1
    sec ; Modify stack in place
    jsr store_varvalue
    jmp fetch_and_dispatch

@pull_v6:
    lda #ERR_TODO
    jmp print_error_and_exit
.endproc

; zpop_word - Pull a word off the Z-machine stack (big-endian)
;
; Out:  x           - high byte
;       y           - low byte
.proc zpop_word
    pha
    lda (zpu_sp)
    tax
    inc zpu_sp
    lda (zpu_sp)
    tay
    inc zpu_sp
    bne @1
    inc zpu_sp+1
@1: pla
    rts
.endproc

; fetch_varvalue - Fetch a variable value
;
; In:   a       - Variable # (preserved)
;       carry   - If variable # is 0, set means don't pop stack
; Out:  x       - Variable value (hi)
;       y       - Variable value (lo)
.proc fetch_varvalue
    ; Check for global variable
    bit #$f0
    bne @fetch_global

    ; Variaable $00 is the stack top, so just pop off a value (or just read if we don't want to pop)
    bit #$0f
    bne @fetch_local
    bcc zpop_word
    pha
    ldy #1
    lda (zpu_sp)
    tax
    lda (zpu_sp),y
    tay
    pla
    rts

@fetch_local:
    ; Locals (variables $01-$0f) are stored on the stack zpu_bp - 2*varnum, so calculate an offset to it
    pha
    asl
    sta zpu_mem+2
    lda zpu_bp
    sec
    sbc zpu_mem+2
    sta zpu_mem
    lda zpu_bp+1
    sbc #0
    sta zpu_mem+1
    lda (zpu_mem)
    tax
    ldy #1
    lda (zpu_mem),y
    tay
    pla
    rts

@fetch_global:
    ; Globals (variables $10-$ff) are located at glob_base + 2*(var-$10), so calculate an offset for glob_base
    pha
    stz zpu_mem+1
    sec
    sbc #$10
    asl
    rol zpu_mem+1
    clc
    adc glob_base+1
    tay
    lda zpu_mem+1
    adc glob_base
    tax

    ; Decode it as a byte address
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2

    ; Switch to the right bank and read a word out of it
    pushb zpu_mem+2
    jsr mem_fetch_and_advance
    pha
    lda (zpu_mem)
    tay
    plx
    popb
    pla
    rts
.endproc

.proc op_push
    lda #<msg_op_push
    sta gREG::r6L
    lda #>msg_op_push
    sta gREG::r6H
    jsr printf

    ; Push the value in r0 onto the stack
    ldx operand_0
    ldy operand_0+1
    jsr zpush_word
    jmp fetch_and_dispatch
.endproc

; zpush_word - Push a word onto the Z-machine stack (big-endian) (preserves a/x/y)
;
; In:   x           - high byte (preserved)
;       y           - low byte (preserved)
.proc zpush_word
    pha
    lda zpu_sp
    bne @1
    dec zpu_sp+1
@1: dec zpu_sp
    tya
    sta (zpu_sp)
    dec zpu_sp
    txa
    sta (zpu_sp)
    pla
    rts
.endproc

; store_varvalue - Store a variable value (preserves a/x/y)
;
; In:   a       - Variable # (preserved)
;       x       - Variable value (hi) (preserved)
;       y       - Variable value (lo) (preserved)
.proc store_varvalue
    ; Check for global variable
    bit #$f0
    bne @store_global

    ; Variable $00 is the stack top, so push the value
    bit #$0f
    bne @store_local
    bcc zpush_word
    pha
    txa
    sta (zpu_sp)
    tya
    ldy #1
    sta (zpu_sp),y
    tay
    pla
    rts

@store_local:
    ; Locals (variables $01-$0f) are stored on the stack zpu_bp - 2*varnum, so calculate an offset to it
    pha
    asl
    sta zpu_mem+2
    lda zpu_bp
    sec
    sbc zpu_mem+2
    sta zpu_mem
    lda zpu_bp+1
    sbc #0
    sta zpu_mem+1
    txa
    sta (zpu_mem)
    tya
    ldy #1
    sta (zpu_mem),y
    tay
    pla
    rts

@store_global:
    ; Globals (variables $10-$ff) are located at glob_base + 2*(var-$10), so calculate an offset for glob_base
    pha
    phy
    phx
    stz zpu_mem+1
    sec
    sbc #$10
    asl
    rol zpu_mem+1
    clc
    adc glob_base+1
    tay
    lda zpu_mem+1
    adc glob_base
    tax

    ; Decode it as a byte address
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2

    ; Switch to the right bank and write a word to it
    plx
    ply
    pushb zpu_mem+2
    txa
    jsr mem_store_and_advance
    tya
    sta (zpu_mem)
    popb
    pla
    rts
.endproc

.proc op_copy_table
@iscopy = gREG::r6L
@first = operand_0
@second = operand_1
@size = operand_2
@first_end = operand_3
@second_end = operand_4

    ldx #<msg_op_copy_table
    stx gREG::r6L
    ldx #>msg_op_copy_table
    stx gREG::r6H
    jsr printf

    ; Get the first address
    ldx @first
    ldy @first+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2

    ; If second is 0, it's a fill, not a copy
    lda @second
    ora @second+1
    beq @fillmem

    ; It's a copy, so get the second address
    ldx @second
    ldy @second+1
    jsr decode_baddr
    sty zpu_mem_2
    stx zpu_mem_2+1
    sta zpu_mem_2+2
    lda #$80
    bra @checknegative

@fillmem:
    ; We're filling first, so move first into second so we store to the right place
    lda zpu_mem
    sta zpu_mem_2
    lda zpu_mem+1
    sta zpu_mem_2+1
    lda zpu_mem+2
    sta zpu_mem_2+2
    lda #0

@checknegative:
    ; Save the flag whether we're copying or filling
    sta @iscopy

    ; If size is negative, we have to copy up (and turn size positive)
    bit operand_2
    bpl @ispositive
    lda #$80
    lda #0
    sec
    sbc @size+1
    sta @size+1
    lda #0
    sbc @size
    sta @size
    bra @copy_up

@ispositive:
    ; Check for overlap to see if we need to copy up or down to avoid corruption (unless we're filling)
    bit @iscopy
    bpl @copy_up
    lda @first+1
    clc
    adc @size+1
    sta @first_end+1
    lda @first
    adc @size
    sta @first_end
    lda @second+1
    clc
    adc @size+1
    sta @second_end+1
    lda @second
    adc @size
    sta @second_end

    ; If second+size is greater than first AND less than first+size, then we need to copy down
    tax
    ldy @second_end+1
    cpx @first
    bne @check_gt_first
    cpy @first+1
@check_gt_first:
    bcc @copy_up
    beq @copy_up

    cpx @first_end
    bne @check_lt_first_end
    cpy @first_end+1
@check_lt_first_end:
    bcc @copy_down

    ; Note for copies: We store source page in x and dest page in y for faster page switching

@copy_up:
    ; Copy from first to second going up
    ldx zpu_mem+2
    ldy zpu_mem_2+2

@copy_up_loop:
    ; Are we filling?
    bit @iscopy
    bpl @justfilling

    ; When copying, load from zpu_mem and advance it
    stx VIA1::PRA
    lda (zpu_mem)
    inc zpu_mem
    bne @copy_up_doneload
    inc zpu_mem+1
    bit zpu_mem+1
    bvc @copy_up_doneload
    inx
    stx zpu_mem+2
@copy_up_doneload:
    .byte $2c ; Skip next lda imm

@justfilling:
    ; Just filling with zeroes
    lda #0

    ; Now store the value to zpu_mem_2 and advance it
    sty VIA1::PRA
    sta (zpu_mem_2)
    inc zpu_mem_2
    bne @copy_up_donestore
    inc zpu_mem_2+1
    bit zpu_mem_2+1
    bvc @copy_up_donestore
    iny
    sty zpu_mem_2+2

@copy_up_donestore:
    ; Decrement size and exit when we hit zero
    lda @size+1
    bne @1
    dec @size
@1: dec @size+1
    dec
    ora @size
    bne @copy_up_loop

@done:
    jmp fetch_and_dispatch

@copy_down:
    ; Copy from first to second going down - need the end addresses
    ldx @first_end
    ldy @first_end+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    ldx @second_end
    ldy @second_end+1
    jsr decode_baddr
    sty zpu_mem_2
    stx zpu_mem_2+1
    sta zpu_mem_2+2
    tay
    ldx zpu_mem+2

@copy_down_loop:
    ; Decrement zpu_mem and load from it
    lda zpu_mem
    sec
    sbc #1
    sta zpu_mem
    bcs @copy_down_doload
    dec zpu_mem+1
    lda zpu_mem+1
    cmp #$a0
    bcs @copy_down_doload
    lda #$bf
    sta zpu_mem+1
    dec zpu_mem+2
    ldx zpu_mem+2
@copy_down_doload:
    stx VIA1::PRA
    lda (zpu_mem)

    ; Now decrement zpu_mem_2 and store the value to it
    pha
    lda zpu_mem_2
    sec
    sbc #1
    sta zpu_mem_2
    bcs @copy_down_dostore
    dec zpu_mem_2+1
    lda zpu_mem_2+1
    cmp #$a0
    bcs @copy_down_doload
    lda #$bf
    sta zpu_mem_2+1
    dec zpu_mem_2+2
    ldy zpu_mem_2+2
@copy_down_dostore:
    pla
    sty VIA1::PRA
    sta (zpu_mem_2)

    ; Decrement size and exit when we hit zero
    lda @size+1
    bne @2
    dec @size
@2: dec @size+1
    dec
    ora @size
    bne @copy_down_loop
    bra @done
.endproc

.proc op_scan_table
@x = operand_0
@table = operand_1
@len = operand_2
@form = operand_3+1
@x_size = operand_3
@field_len = operand_3+1

    ldx #<msg_op_scan_table
    stx gREG::r6L
    ldx #>msg_op_scan_table
    stx gREG::r6H
    jsr printf

    ; Check the form (if present)
    lda num_operands
    ldx @form
    cmp #4
    bcs @have_form
    ldx #$82 ; (default to words)

@have_form:
    ; Turn form into x size flag and field_len
    txa
    and #$80
    bne @1
    ldy operand_0+1
    sty operand_0
@1: sta @x_size
    txa
    and #$7f
    dec
    bit @x_size
    bpl @2
    dec
@2: sta @field_len

    ; Get the table address
    ldx @table
    ldy @table+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA

    ; Scan for a matching value
@scan_loop:
    jsr mem_fetch_and_advance
    tax
    bit @x_size
    bpl @compareit
    jsr mem_fetch_and_advance
@compareit:
    cpx @x
    bne @nomatch
    bit @x_size
    bpl @match
    cmp @x+1
    bne @nomatch

@match:
    ; Found a match, reverse zpu_mem into a byte address
    lda zpu_mem+2
    ldx zpu_mem+1
    jsr encode_baddr
    ldy zpu_mem

    ; And step back the 1 or 2 bytes to get to the address we found it at
    bit @x_size
    beq @3
    lda #2
    .byte $2c
@3: lda #1
    sta @x_size
    tya
    sec
    sbc @x_size
    tay
    txa
    sbc #0
    tax

    ; And make sure we follow the branch as well
    lda #0

@return_xy:
    ; Store the return value in the result variable
    pha
    lda zpu_pc+2
    sta VIA1::PRA
    jsr pc_fetch_and_advance
    clc ; Push stack if necessary
    jsr store_varvalue

    ; And branch if we found it
    pla
    sta operand_0
    sta operand_0+1
    jmp do_jz

@nomatch:
    ; Didn't find a match, so see if we have more entries
    lda @len+1
    bne @4
    dec @len
@4: dec @len+1
    dec
    ora @len
    bne @5

    ; Out of entries, so store 0 in result and ignore branch
    lda #1
    tax
    tay
    bra @return_xy

    ; Step ahead to the next entry in the table
@5: lda @field_len
    beq @scan_loop
    jsr mem_advance
    bra @scan_loop
.endproc

opext_push_stack:
opext_pop_stack:
    jmp opext_illegal

.rodata

msg_loading: .byte "Loading @ into var #", CH::ENTER, 0
msg_loading_byte: .byte "Loading byte @[@] into var #", CH::ENTER, 0
msg_loading_word: .byte "Loading word @[@] into var #", CH::ENTER, 0
msg_storing: .byte "Storing in var @ value=@", CH::ENTER, 0
msg_storing_byte: .byte "Storing byte in @[@] value=@", CH::ENTER, 0
msg_storing_word: .byte "Storing word in @[@] value=@", CH::ENTER, 0
msg_op_push: .byte "Pushing @", CH::ENTER, 0
msg_op_pull: .byte "Pulling into var @", CH::ENTER, 0
msg_op_copy_table: .byte "Copying table @ => @ size=@", CH::ENTER, 0
msg_op_scan_table: .byte "Scanning for @ in table @ size=@ (form=@)", CH::ENTER, 0
