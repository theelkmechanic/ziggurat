.include "ziggurat.inc"
.include "zpu.inc"

.code

; op_not_or_call:
;  - Versions 1-4: not value -> (result)
;  - Versions 5+:  call_1n routine
.proc op_not_or_callvoid
    chkver V1|V2|V3|V4,op_call_void
    jmp op_not
.endproc

op_call_void:
    lda #<msg_op_call_void
    sta gREG::r6L
    lda #>msg_op_call_void
    sta gREG::r6H
    jsr printf

    ; For calls that don't save the result, clear the high bit in our param info byte
    ldy #0
    ;.byte $2c   ; NOP out the next load
    bra op_call

op_call_save:
    lda #<msg_op_call_save
    sta gREG::r6L
    lda #>msg_op_call_save
    sta gREG::r6H
    jsr printf
    ; For calls that save the result, set the high bit in our param info byte
    ldy #$80

.proc op_call
; Use temp storage at $400 for these function locals
num_locals = $400
ops_and_locals = $401

    ; Calling a routine at address 0 does nothing and returns false
    lda operand_0
    ora operand_0+1
    bne @do_call
    cpy #$80
    bne @void_nullcall
    ldx #0
    ldy #0
    jsr pc_fetch_and_advance
    clc ; Push to stack if necessary
    jsr store_varvalue
@void_nullcall:
    jmp fetch_and_dispatch

@do_call:
    ; Push the return address and parameter byte on the stack, followed by the current frame pointer
    ldx zpu_pc+2
    zpush
    zpush zpu_pc
    zpush zpu_bp
    lda zpu_sp
    sta zpu_bp
    lda zpu_sp+1
    sta zpu_bp+1

    ; Now unpack operand 0 as the routine address and jump there
    ldx operand_0
    ldy operand_0+1
    jsr decode_paddr_r
    sty zpu_pc
    stx zpu_pc+1
    sta zpu_pc+2
    sta VIA1::PRA

    ; Save the number of locals and number of operands into the parameter byte in our stack frame
    ; (which is at bp+5). Local count is in low nibble, operand count is in bits 6-4.
    jsr pc_fetch_and_advance
    sta num_locals
    lda num_operands
    asl
    asl
    asl
    asl
    ora num_locals
    sta ops_and_locals
    ldy #5
    lda (zpu_bp),y
    ora ops_and_locals
    sta (zpu_bp),y

    ; Initialize the locals. First, figure out how many arguments the call had
    ; so we can copy them first, but not more than the number of variables
    dec num_operands
    lda num_locals
    cmp num_operands
    bcs @copy_operands
    sta num_operands
@copy_operands:
    ; Set local and operand counts to 2n so we can easily compare indices as we copy
    asl num_operands
    asl num_locals

    ; Copy operands while we have them, then initialize locals
    ldy #0
@copy_op_loop:
    cpy num_operands
    bcs @check_copy_locals
    lda operand_1,y
    tax
    iny
    lda operand_1,y
    iny
    phy
    tay
    jsr zpush_word
    ply

    ; For v1-4, we need to skip local variable initialization values for the operands we have
    chkver V1|V2|V3|V4,@copy_op_loop
    jsr pc_fetch_and_advance
    jsr pc_fetch_and_advance
    bra @copy_op_loop

    ; For v1-4, we want to copy initialization values to the remaining local variables
@check_copy_locals:
    chkver V1|V2|V3|V4,@init_locals
@copy_local_loop:
    cpy num_locals
    bcs @done
    jsr pc_fetch_and_advance
    tax
    iny
    jsr pc_fetch_and_advance
    iny
    phy
    tay
    jsr zpush_word
    ply
    bra @copy_local_loop

@init_locals:
    lda #0
@init_local_loop:
    ; For v5+, we just want to set remaining local variables to zero
    cpy num_locals
    bcs @done
    ldx #0
    iny
    iny
    phy
    ldy #0
    jsr zpush_word
    ply
    bra @init_local_loop

@done:
    ; Start executing the routine
    jmp fetch_and_dispatch
.endproc

.proc op_check_arg_count
    lda #<msg_op_check_arg_count
    sta gREG::r6L
    lda #>msg_op_check_arg_count
    sta gREG::r6H
    jsr printf

    ; The number of arguments to the current routine is stored in the parameter flag byte,
    ; which is at BP+5, in bits 6-4.
    ldy #5
    lda (zpu_bp),y
    lsr
    lsr
    lsr
    lsr
    and #$07

    ; Now test that the number of arguments is greater than or equal to the argument we want
    cmp operand_0+1
    lda #0
    bcc @missing_arg
    ora #$80
@missing_arg:
    jmp follow_branch
.endproc

.proc op_test
    lda operand_2
    sta operand_3
    lda operand_2+1
    sta operand_3+1
    lda #<msg_op_test
    sta gREG::r6L
    lda #>msg_op_test
    sta gREG::r6H
    jsr printf

    ; Calculate r0 & r1 and fall through to op_je to test if it equals r1
    lda operand_0
    and operand_1
    sta operand_0
    lda operand_0+1
    and operand_1+1
    sta operand_0+1

    ; FALL THRU INTENTIONAL
.endproc

.proc op_je
    ; Branch if first parameter equals any of the following parameters
    lda num_operands
    cmp #2
    bcs @check_for_2
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@check_for_2:
    beq @has_2
    cmp #3
    beq @has_3
    ldy #<msg_op_je_4
    ldx #>msg_op_je_4
    bra @debug
@has_3:
    ldy #<msg_op_je_3
    ldx #>msg_op_je_3
    bra @debug
@has_2:
    ldy #<msg_op_je_2
    ldx #>msg_op_je_2
@debug:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf

    asl
    sta num_operands
    ldx #2
    ldy operand_0+1
@check_op:
    lda operand_0
    cmp operand_0,x
    bne @check_next
    tya
    cmp operand_0+1,x
    bne @check_next

    ; Found a match, so set true and follow branch
    lda #$80
    bra follow_branch

@check_next:
    ; Step to next operand (if we have one)
    inx
    inx
    cpx num_operands
    bcc @check_op

    ; No match found, so set false and follow branch
    lda #0
    bra follow_branch
.endproc

.proc op_jg
    lda #<msg_op_jl
    sta gREG::r6L
    lda #>msg_op_jl
    sta gREG::r6H
    jsr printf

    ; Swap parameters and do a less than instead
    ldx operand_0
    ldy operand_0+1
    lda operand_1
    sta operand_0
    lda operand_1+1
    sta operand_0+1
    stx operand_1
    sty operand_1+1
    bra do_lt
.endproc

op_jl:
do_lt:
    lda #<msg_op_jl
    sta gREG::r6L
    lda #>msg_op_jl
    sta gREG::r6H
    jsr printf

    ; Branch if first parameter is less than second parameter
    lda num_operands
    cmp #2
    bcs @check_for_lt
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@check_for_lt:
    ; Need to do signed comparison
    lda operand_0+1
    cmp operand_1+1
    lda operand_0
    sbc operand_1
    bvc @1
    eor #$80
@1: bmi @is_lt

    ; Not less than, so set false and follow branch
    lda #0
    .byte $2c

@is_lt:
    ; Is less than, so set true and follow branch
    lda #$80
    bra follow_branch

.proc op_jz
    lda #<msg_op_jz
    sta gREG::r6L
    lda #>msg_op_jz
    sta gREG::r6H
    jsr printf
.endproc

.proc do_jz
    ; Branch if first parameter is zero
    lda num_operands
    bne @check_for_zero
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@check_for_zero:
    lda operand_0
    ora operand_0+1
    beq @is_zero

    ; Not zero, so set false and follow branch
    lda #0
    .byte $2c

@is_zero:
    ; Is zero, so set true and follow branch
    lda #$80

    ; FALL THRU INTENTIONAL
    ; ***** DO NOT ADD CODE BETWEEN *****
.endproc

; follow_branch - Load a branch offset and follow it based on the flag in a's high bit
; In:   pc          - pointing to branch offset
;       a           - flag to check against branch jump flag ($80=true, $00=false)
.proc follow_branch
    sta operand_1
    lda (zpu_pc)
    bit #$80
    beq @str_false
    ldy #<msg_true
    ldx #>msg_true
    bra @save_flagstr
@str_false:
    ldy #<msg_false
    ldx #>msg_false
@save_flagstr:
    sty operand_0
    stx operand_0+1
    lda #<msg_branch
    sta gREG::r6L
    lda #>msg_branch
    sta gREG::r6H
    jsr printf
    lda operand_1

; Use temp storage at $400 for these function locals
branch_offset = $400
do_branch_flag = $402

    ; Check the first branch byte. Bit 7 tells us if we need to branch on true (set)
    ; or false (clear). If we eor a with the first branch byte, we should then have
    ; the high bit clear if we need to branch or set if we don't.
    eor (zpu_pc)
    and #$80
    sta do_branch_flag

    ; Bit 6 tells us whether we have a one or two byte branch offset.
    ;   Set - one byte offset
    ;   Clear - two byte offset
    jsr pc_fetch_and_advance
    bit #$40
    bne @one_byte_offset

    ; It's a long offset, so sign-extend the low six bits and put them in x as our
    ; high byte, and read the low byte into y
    and #$3f
    bit #$20
    beq @1
    ora #$c0
@1: tax
    jsr pc_fetch_and_advance
    bra @do_branch_if_we_need_to

    ; It's a short offset, so it's just the low 6 bits of the branch byte
@one_byte_offset:
    ldx #0
    and #$3f

@do_branch_if_we_need_to:
    ; Now that we know the offset, we check to see if we need to branch or not
    tay
    lda do_branch_flag
    bne dont_branch

    stx operand_0
    sty operand_0+1
    lda #<msg_branching
    sta gREG::r6L
    lda #>msg_branching
    sta gREG::r6H
    jsr printf

    ; Check for 0/1 offset, which mean return false/true from current routine instead
    ; of doing a branch
    cpx #0
    bne do_branch
    tya
    bit #$fe
    bne do_branch

    ; Return false if y is even and true if it is odd
    bit #$01
    beq op_rfalse
    bra op_rtrue

    ; FALL THRU INTENTIONAL
    ; ***** DO NOT ADD CODE BETWEEN *****
.endproc

.proc do_branch
    ; To do the branch, we subtract 2 from the offset, then add our offset to our PC.
    ; Then if we're outside of the high RAM page, we adjust the bank until we are back inside.
    cpy #2
    bcs @y_minus_2
    dex
@y_minus_2:
    dey
    dey
    clc
    tya
    adc zpu_pc
    sta zpu_pc
    txa
    adc zpu_pc+1

    ; Check if we're above the end of bank and move up a bank until we aren't, then
    ; check if we're below and move down until we aren't
@check_above:
    cmp #$c0
    bcc @check_below
    inc zpu_pc+2
    sec
    sbc #$20
    bra @check_above
@check_below:
    cmp #$a0
    bcs @switch_bank
    dec zpu_pc+2
    clc
    adc #$20
    bra @check_below
@switch_bank:
    sta zpu_pc+1
    lda zpu_pc+2
    sta VIA1::PRA

    ; FALL THRU INTENTIONAL
    ; ***** DO NOT ADD CODE BETWEEN *****
.endproc

.proc dont_branch
    ; Go back to executing the next instruction
    jmp fetch_and_dispatch
.endproc

.proc op_jump
    lda #<msg_jumping
    sta gREG::r6L
    lda #>msg_jumping
    sta gREG::r6H
    jsr printf

    ; Put branch offset from r0 into x/y
    ldx operand_0
    ldy operand_0+1

    ; And do the branch unconditionally
    bra do_branch
.endproc

.proc op_throw
    ; In versions 5+, this switches back to a previously caught stack frame
    chkver V5|V6|V7|V8,@do_throw
    jmp op_illegal
@do_throw:
    lda operand_1+1
    sta zpu_bp
    lda operand_1
    sta zpu_bp+1

    ; And return the thrown value
    bra op_ret
.endproc

.proc op_ret_popped
    ; Pop a value off the stack into r0
    zpop operand_0
    bra op_ret
.endproc

.proc op_rfalse
    ; Set operand 0 to #0 and ret
    lda #0
    .byte $2c
.endproc

.proc op_rtrue
    ; Set operand 0 to #1 and ret
    lda #1
    stz operand_0
    sta operand_0+1
.endproc

.proc op_ret
    ; Jump up one stack frame
    lda zpu_bp
    sta zpu_sp
    lda zpu_bp+1
    sta zpu_sp+1
    zpop zpu_bp

    ; Pop the PC and the flag for whether we're returning the value or throwing it away
    ; (because of zeropage layout, opcode is immediately after the PC, so that's where the
    ; flag will end up)
    zpop zpu_pc
    zpop zpu_pc+2
    lda zpu_pc
    sta operand_1
    lda zpu_pc+1
    sta operand_1+1
    lda zpu_pc+2
    sta operand_2
    lda zpu_sp
    sta operand_3
    lda zpu_sp+1
    sta operand_3+1
    lda #<msg_returning
    sta gREG::r6L
    lda #>msg_returning
    sta gREG::r6H
    lda #<msg_void
    sta operand_4
    lda #>msg_void
    sta operand_4+1
    stz operand_5

    ; If we're returning a value, it's in r0, so store it to the result variable
    bit opcode
    bpl @done
    lda #<msg_int
    sta operand_4
    lda #>msg_int
    sta operand_4+1
    ldx operand_0
    ldy operand_0+1
    lda zpu_pc+2
    sta VIA1::PRA
    jsr pc_fetch_and_advance
    sta operand_5
    clc ; Push to stack if necessary
    jsr store_varvalue

    ; And start executing the next instruction
@done:
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc op_pop_or_catch
    ; In versions 1-4, this just does a pop and throws away the result
    chkver V1|V2|V3|V4,do_catch
    zpop
    jmp fetch_and_dispatch

do_catch:
    ; In versions 5+, this "catches" the current stack frame
    ldx zpu_bp+1
    ldy zpu_bp
    lda operand_0+1
    clc ; Push to stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.rodata

msg_op_call_save: .byte "Calling int routine at @", CH::ENTER, 0
msg_op_call_void: .byte "Calling void routine at @", CH::ENTER, 0
msg_op_je_2: .byte "Jumping if @ = @", CH::ENTER, 0
msg_op_je_3: .byte "Jumping if @ = @ or @", CH::ENTER, 0
msg_op_je_4: .byte "Jumping if @ = @ or @ or @", CH::ENTER, 0
msg_op_jl: .byte "Jumping if @ < @", CH::ENTER, 0
msg_op_jg: .byte "Jumping if @ > @", CH::ENTER, 0
msg_op_jz: .byte "Jumping if @ is zero", CH::ENTER, 0
msg_branch: .byte "Branch if $ flag=#", CH::ENTER, 0
msg_branching: .byte "Branching offset=@", CH::ENTER, 0
msg_jumping: .byte "Jumping offset=@", CH::ENTER, 0
msg_true: .byte "true", 0
msg_false: .byte "false", 0
msg_returning: .byte "Returning @ to addr % bank # sp=% $ rvar=#", CH::ENTER, 0
msg_int: .byte "int", 0
msg_void: .byte "void", 0
msg_op_test: .byte "Testing @ & @ == 0", CH::ENTER, 0
msg_op_check_arg_count: .byte "Checking if have arg @", CH::ENTER, 0
