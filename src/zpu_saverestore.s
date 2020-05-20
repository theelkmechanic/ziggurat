.include "ziggurat.inc"
.include "zpu.inc"

.code

;    .word op_restart                    ; Opcode $b7 - restart
;    .word op_restore                    ; Opcode $b6 - versions 1-3: restore ?(label)
;                                        ;            - version 4: restore -> (result)
;                                        ;            - version 5+: illegal
;    .word op_save                       ; Opcode $b5 - versions 1-3: save ?(label)
;                                        ;            - version 4: save -> (result)
;                                        ;            - version 5+: illegal
;    .word opext_restore                 ; Extended opcode $01 - restore table bytes name prompt -> (result)
;    .word opext_restore_undo            ; Extended opcode $0a - restore_undo -> (result)
;    .word opext_save                    ; Extended opcode $00 - save table bytes name prompt -> (result)
;    .word opext_save_undo               ; Extended opcode $09 - save_undo -> (result)

op_restart:
op_save:
op_restore:
    jmp op_illegal

opext_restore:
opext_save:
    jmp opext_illegal

.proc opext_restore_undo
    lda #<msg_restore_undo
    sta gREG::r6L
    lda #>msg_restore_undo
    sta gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc opext_save_undo
    lda #<msg_save_undo
    sta gREG::r6L
    lda #>msg_save_undo
    sta gREG::r6H
    jsr printf
    jmp fetch_and_dispatch
.endproc

.proc op_verify
    ; Validate the loaded data
    lda #<msg_validating
    sta gREG::r6L
    lda #>msg_validating
    sta gREG::r6H
    jsr printf

    ; Since we're going to call op_je to do the branch, tell it that we have 2 large constant operands
    lda #$0f
    sta optypes
    lda #$ff
    sta optypes+1
    lda #2
    sta num_operands

    ; Versions 1 and 2 don't have checksums, so for them just branch on false
    chkver V1|V2, @val_chksum
    sta operand_0
    stz operand_1
    jmp op_je

@val_chksum:
    ; Save the old PC and bank
    lda zpu_pc
    pha
    lda zpu_pc+1
    pha
    lda zpu_pc+2
    pha
    pushb #1

    ; Get the length of the file in bytes
    ldx ZMheader::zif_len
    stx zpu_mem+1
    ldx ZMheader::zif_len+1
    stx zpu_mem
    stz zpu_mem+2
    chkver V6|V7|V8,@length_x4
    asl zpu_mem
    rol zpu_mem+1
    rol zpu_mem+2
@length_x4:
    chkver V4|V5|V6|V7|V8,@length_x2
    asl zpu_mem
    rol zpu_mem+1
    rol zpu_mem+2
@length_x2:
    asl zpu_mem
    rol zpu_mem+1
    rol zpu_mem+2

    ; Invert the length so we can count up to 0 (easier to do multibyte)
    lda zpu_mem
    eor #$ff
    sta zpu_mem
    lda zpu_mem+1
    eor #$ff
    sta zpu_mem+1
    lda zpu_mem+2
    eor #$ff
    sta zpu_mem+2

    ; Use the PC to scan the loaded data and add the values into r0, and save the
    ; expected checksum into r1 for later op_je
    lda #$a0
    sta zpu_pc+1
    lda #1
    sta zpu_pc+2
    stz operand_0
    stz operand_0+1
    lda ZMheader::checksum
    sta operand_1
    lda ZMheader::checksum+1
    sta operand_1+1

    ; Skip the first 64 bytes
    lda #64
    sta zpu_pc
    inc
    clc
    adc zpu_mem
    sta zpu_mem
    lda zpu_mem+1
    adc #0
    sta zpu_mem+1
    lda zpu_mem+2
    adc #0
    sta zpu_mem+2
@chksum_loop:
    jsr pc_fetch_and_advance
    clc
    adc operand_0+1
    sta operand_0+1
    lda #0
    adc operand_0
    sta operand_0
    inc zpu_mem
    bne @chksum_loop
    inc zpu_mem+1
    bne @chksum_loop
    inc zpu_mem+2
    bne @chksum_loop

@comp_chksum:
    ; Restore the PC and bank
    popb
    pla
    sta zpu_pc+2
    pla
    sta zpu_pc+1
    pla
    sta zpu_pc

    ; And head over to op_je to branch on matching checksum
    jmp op_je
.endproc

.proc op_piracy
    ; Assume piracy has been legalized
    lda #$0f
    sta optypes
    lda #$ff
    sta optypes+1
    lda #2
    sta num_operands
    stz operand_0
    stz operand_0+1
    stz operand_1
    stz operand_1+1
    jmp op_je
.endproc

.rodata

msg_validating:                 .byte "Validating Z-machine data", CH::ENTER, 0
msg_restore_undo:               .byte "Restoring from undo state (unimplemented)", CH::ENTER, 0
msg_save_undo:                  .byte "Saving undo state (unimplemented)", CH::ENTER, 0
