.include "ziggurat.inc"
.include "zpu.inc"
.include "zscii_type.inc"

.code

op_input_stream:
op_tokenise:
    jmp op_illegal

.proc op_read_char
    lda #<msg_op_read_char
    sta gREG::r6L
    lda #>msg_op_read_char
    sta gREG::r6H
    jsr printf

    ; Read a character from the keyboard
@1: jsr GETIN
    jsr z_isinput
    bcc @1

    ; Return it in the result
    ldx #0
    tay
    jsr pc_fetch_and_advance
    clc ; Push to stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc op_sread
    lda #<msg_op_read
    sta gREG::r6L
    lda #>msg_op_read
    sta gREG::r6H
    jsr printf

    ; Show the status line in versions 1-3
    chkver V1|V2|V3,@nostatus
    jsr show_status

@nostatus:
    ; Get the text buffer size
    ldx operand_0
    ldy operand_0+1
    jsr mem_fetch_and_advance

    ; Read an input line from the current window
    tax
    lda current_window
    jsr win_readln

    ; Stop
    brk
.endproc

msg_op_read_char: .byte "Reading @ char", CH::ENTER, 0
msg_op_read: .byte "Reading input", CH::ENTER, 0
