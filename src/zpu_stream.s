.include "ziggurat.inc"
.include "zpu.inc"

.code

.proc op_output_stream
    jmp op_illegal

    lda num_operands
    dec
    bpl @check_for_1
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@check_for_1:
    beq @has_1
    dec
    beq @has_2
    ldy #<msg_op_output_stream_with_table_width
    ldx #>msg_op_output_stream_with_table_width
    bra @debug
@has_2:
    ldy #<msg_op_output_stream_with_table
    ldx #>msg_op_output_stream_with_table
    bra @debug
@has_1:
    ldy #<msg_op_output_stream
    ldx #>msg_op_output_stream
@debug:
    sty gREG::r6L
    stx gREG::r6H
    jsr printf

    jmp fetch_and_dispatch
.endproc

.rodata

msg_op_output_stream:                   .byte "Output stream @", CH::ENTER, 0
msg_op_output_stream_with_table:        .byte "Output stream @ table=@", CH::ENTER, 0
msg_op_output_stream_with_table_width:  .byte "Output stream @ table=@ width=@", CH::ENTER, 0
