.include "ziggurat.inc"
.include "zpu.inc"

do_check_flag = $400
do_arith_shift_flag = $400
want_remainder = $400
muldiv_sign = $401

.code

.proc op_dec_chk
    ; Set "do check" flag
    lda #$ff
    .byte $2c

    ; FALL THRU INTENTIONAL
.endproc

.proc op_dec
    ; Clear "do check flag"
    lda #0
    sta do_check_flag
    bit #$80
    beq @just_dec
    ldy #<msg_op_dec_chk
    ldx #>msg_op_dec_chk
    bra @print_it
@just_dec:
    ldy #<msg_op_dec
    ldx #>msg_op_dec
@print_it:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf

    ; Fetch the variable
    lda operand_0+1
    sec ; Modify stack in place
    jsr fetch_varvalue

    ; Decrement it
    cpy #0
    bne @1
    dex
@1: dey

    ; And store it back
    sec ; Modify stack in place
    jsr store_varvalue

    ; Now if do_check is set, we need to compare
    bit do_check_flag
    bpl op_nop
    stx operand_0
    sty operand_0+1
    jmp do_lt
.endproc

.proc op_nop
    ; Just go on to next instruction
    jmp fetch_and_dispatch
.endproc

.proc op_inc_chk
    ; Set "do check" flag
    lda #$ff
    .byte $2c

    ; FALL THRU INTENTIONAL
.endproc

.proc op_inc
    ; Clear "do check flag"
    lda #0
    sta do_check_flag
    bit #$80
    beq @just_dec
    ldy #<msg_op_inc_chk
    ldx #>msg_op_inc_chk
    bra @print_it
@just_dec:
    ldy #<msg_op_inc
    ldx #>msg_op_inc
@print_it:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf

    ; Fetch the variable
    lda operand_0+1
    sec ; Modify stack in place
    jsr fetch_varvalue

    ; Increment it
    iny
    bne @1
    inx

    ; And store it back
@1: sec ; Modify stack in place
    jsr store_varvalue

    ; Now if do_check is set, we need to compare; need to swap args to change gt to lt
    bit do_check_flag
    bpl op_nop
    lda operand_1
    sta operand_0
    lda operand_1+1
    sta operand_0+1
    stx operand_1
    sty operand_1+1
    jmp do_lt
.endproc

.proc op_mul
    lda #<msg_op_mul
    sta gREG::r6L
    lda #>msg_op_mul
    sta gREG::r6H
    jsr printf

    ; Figure out result sign and negate operands if we need to
    jsr init_muldiv_sign

    ; We will use r2 for the result
    stz operand_2
    stz operand_2+1

@loop:
    ; Loop while operand_1 is non-zero
    lda operand_1
    ora operand_1+1
    beq @done

    ; If operand_1 is odd, add operand_0 to product
    lda operand_1+1
    and #1
    beq @rotate
    lda operand_0+1
    clc
    adc operand_2+1
    sta operand_2+1
    lda operand_0
    adc operand_2
    sta operand_2

@rotate:
    ; For next round, multiply operand_0 by 2 and divide operand_1 by 2
    asl operand_0+1
    rol operand_0
    lsr operand_1
    ror operand_1+1
    bra @loop

@done:
    ; Move 16-bit result into x/y and store it
    ldx operand_2
    ldy operand_2+1
    bit muldiv_sign
    bpl @1
    jsr negate_xy
@1: bra store_math_result
.endproc

.proc op_add
    lda #<msg_op_add
    sta gREG::r6L
    lda #>msg_op_add
    sta gREG::r6H
    jsr printf

    ; Add params 0 and 1 into x/y
    lda operand_0+1
    clc
    adc operand_1+1
    tay
    lda operand_0
    adc operand_1
    tax
    bra store_math_result
.endproc

.proc op_sub
    lda #<msg_op_sub
    sta gREG::r6L
    lda #>msg_op_sub
    sta gREG::r6H
    jsr printf

    ; Subtract param 1 from param 0 into x/y
    lda operand_0+1
    sec
    sbc operand_1+1
    tay
    lda operand_0
    sbc operand_1
    tax
    bra store_math_result
.endproc

.proc op_and
    lda #<msg_op_and
    sta gREG::r6L
    lda #>msg_op_and
    sta gREG::r6H
    jsr printf

    ; And params 0 and 1 into x/y
    lda operand_0
    and operand_1
    tax
    lda operand_0+1
    and operand_1+1
    tay
    bra store_math_result
.endproc

.proc op_or
    lda #<msg_op_or
    sta gREG::r6L
    lda #>msg_op_or
    sta gREG::r6H
    jsr printf

    ; And params 0 and 1 into x/y
    lda operand_0
    ora operand_1
    tax
    lda operand_0+1
    ora operand_1+1
    tay
    bra store_math_result
.endproc

op_not_v5:
    chkver V1|V2|V3|V4,op_not
    jmp op_illegal

.proc op_not
    lda #<msg_op_not
    sta gREG::r6L
    lda #>msg_op_not
    sta gREG::r6H
    jsr printf

    ; Invert param 0 into x/y
    lda operand_0
    eor #$ff
    tax
    lda operand_0+1
    eor #$ff
    tay

    ; FALL THRU INTENTIONAL
    ; ***** DO NOT ADD CODE BETWEEN *****
.endproc

store_math_result:
    ; Fetch the result variable number
    jsr pc_fetch_and_advance

store_math_var:    
    ; Store x/y in it
    clc ; Push stack if necessary
    jsr store_varvalue

    ; And move on to the next instruction
    jmp fetch_and_dispatch

.proc op_div
    ; Do division and return quotient
    lda #0
    .byte $2c
.endproc

.proc op_mod
    ; Do division and return remainder
    lda #$80
    sta want_remainder
    bne @doing_mod
    ldy #<msg_op_div
    ldx #>msg_op_div
    bra @do_division
@doing_mod:
    ldy #<msg_op_mod
    ldx #>msg_op_mod
@do_division:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf

    ; Figure out result sign and negate operands if we need to
    jsr init_muldiv_sign

    ; Clear the remainder in r3
    stz operand_3
    stz operand_3+1

    ; Loop through all 16 bits, setting bits from r0 into the remainder, and then shifting them
    ; into the quotient when we can subtract r1 from the remainder
    ldx #16
@1: asl operand_0+1
    rol operand_0
    rol operand_3+1
    rol operand_3
    sec
    lda operand_3+1
    sbc operand_1+1
    tay
    lda operand_3
    sbc operand_1
    bcc @2
    sta operand_3
    sty operand_3+1
    rol operand_2+1
    rol operand_2
@2: dex
    bne @1

    ; Now which result do we want
    bit want_remainder
    bmi @store_remainder

    ; Move quotient into x/y and store it
    ldx operand_2
    ldy operand_2+1
    bra @check_sign_and_store_math_result

@store_remainder:
    ; Move remainder into x/y and store it
    ldx operand_3
    ldy operand_3+1

@check_sign_and_store_math_result:
    bit muldiv_sign
    bpl store_math_result
    jsr negate_xy
.endproc
extend_bra_store_math_result:
    bra store_math_result

.proc opext_log_shift
    lda #0          ; Clear arithmetic shift flag
    .byte $2c

    ; FALL THRU INTENTIONAL
.endproc

.proc opext_art_shift
    lda #$80        ; Set arithmetic shift flag

    ; See if we're shifting right or left
    bit operand_1
    bmi @do_right_shift

    ; Make sure it's not more than 15
    lda operand_1+1
    cmp #16
    bcs @out_of_range

    ; Loop n times doing 16-bit ASL
    tax
@lshift_loop:
    asl operand_0+1
    rol operand_0
    dex
    bne @lshift_loop

    ; Put it in x/y and store it
    ldx operand_0
    ldy operand_0+1
    bra extend_bra_store_math_result

@do_right_shift:
    ; Do right shift -- first step is to invert the shift value
    lda operand_1+1
    eor #$ff
    inc

    ; Make sure it's not more than 15
    cmp #16
    bcc @rshift_is_okay
@out_of_range:
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@rshift_is_okay:
    ; Loop n times doing 16-bit LSR with sign-extension if needed
    tax
    lda operand_0
    and #$80
    and do_arith_shift_flag
@rshift_loop:
    bit do_arith_shift_flag
    bmi @sign_extend_rshift
    lsr operand_0
    bra @next_rshift
@sign_extend_rshift:
    sec
    ror operand_0
@next_rshift:
    ror operand_0+1
    dex
    bne @rshift_loop

    ; Put it in x/y and store it
    ldx operand_0
    ldy operand_0+1
    bra extend_bra_store_math_result
.endproc

.proc negate_xy
    ; Negate value in x/y (x=hi, y=lo)
    pha
    stx gREG::r10H
    sty gREG::r10L
    lda #0
    sec
    sbc gREG::r10L
    tay
    lda #0
    sbc gREG::r10H
    tax
    pla
    rts
.endproc

.proc init_muldiv_sign
    ; Figure out sign of result
    ldx #0
    bit operand_0
    bpl @1
    inx
@1: bit operand_1
    bpl @2
    inx
@2: txa
    lsr
    ror
    sta muldiv_sign

    ; Now flip operands that are negative to be positive instead
    bit operand_0
    bpl @3
    ldx operand_0
    ldy operand_0+1
    jsr negate_xy
    stx operand_0
    sty operand_0+1

@3: bit operand_1
    bpl @4
    ldx operand_1
    ldy operand_1+1
    jsr negate_xy
    stx operand_1
    sty operand_1+1
@4: rts
.endproc

.proc op_random
    ; If range is 0, seed with a random value
    ldy operand_0+1
    tya
    ora operand_0
    beq @seed_random

    ; If range is negative, invert and seed with that value
    ldx operand_0
    bpl @getrandom_range

    ; Invert the value and store it in the seed
    ldx operand_0
    ldy operand_0+1
    jsr negate_xy
    stx random_seed
    sty random_seed+1

    ; Return 0 when we set the seed
@return_0:
    ldx #0
    ldy #0

@return_result:
    ; Save the random value in operand_1 so we can print it out
    stx operand_1
    sty operand_1+1
    lda #<msg_op_random
    sta gREG::r6L
    lda #>msg_op_random
    sta gREG::r6H
    jsr printf

    ; Return our result
    jsr pc_fetch_and_advance
    clc ; Push to stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch

@seed_random:
    ; Get the system ticks into the seed
    jsr RDTIM
    bra @return_0

@getrandom_range:
    ; Generate our next random value in the range specified
    inc random_seed+1
    bne @1
    inc random_seed
@1: ldx random_seed
    ldy random_seed+1
    bra @return_result
.endproc

.rodata

msg_op_add: .byte "Adding @ + @", CH::ENTER, 0
msg_op_sub: .byte "Subtracting @ - @", CH::ENTER, 0
msg_op_mul: .byte "Multiplying @ * @", CH::ENTER, 0
msg_op_div: .byte "Dividing @ / @", CH::ENTER, 0
msg_op_mod: .byte "Dividing @ MOD @", CH::ENTER, 0
msg_op_and: .byte "Combining @ AND @", CH::ENTER, 0
msg_op_or: .byte "Combining @ OR @", CH::ENTER, 0
msg_op_not: .byte "Inverting @", CH::ENTER, 0
msg_op_inc: .byte "Incrementing var @", CH::ENTER, 0
msg_op_dec: .byte "Decrementing var @", CH::ENTER, 0
msg_op_inc_chk: .byte "Incrementing var @ and check > @", CH::ENTER, 0
msg_op_dec_chk: .byte "Decrementing var @ and check < @", CH::ENTER, 0
msg_op_log_shift: .byte "Shift @ by @ into var @ (logical)", CH::ENTER, 0
msg_op_art_shift: .byte "Shift @ by @ into var @ (arithmetic)", CH::ENTER, 0
msg_op_random: .byte "Random range=@ value=@", CH::ENTER, 0

.bss

random_seed:    .res 2
