.include "ziggurat.inc"
.include "zpu.inc"

.data

; Output streams
.define OSTREAM_TABLE       $80
.define OSTREAM_SCREEN      $40
.define OSTREAM_OUTTRANS    $20
.define OSTREAM_INTRANS     $10

ostream_flags:          .byte   OSTREAM_SCREEN  ; High nibble is stream flags, low nibble is current index into stream arrays
ostream_table_bases:    .res    16*3

table_aryidx = $4c0

.code

.proc op_output_stream
stream_num = $400
stream_select = $401

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

    ; Which stream number are we?
    stz stream_select
    lda operand_0+1
    beq @done
    bpl :+
    sec
    ror stream_select
    lda #0
    sec
    sbc operand_0+1

    ; Are we table?
    ; TODO: Implement the other streams
:   cmp #3
    beq @do_table

    ; Are we screen?
    ; TODO: Implement the other streams
    cmp #1
    bne @done

    ; Enable/disable the screen flag
    lda ostream_flags
    bit stream_select
    bmi @deselect_screen

    ; Enable the screen flag
    ora #OSTREAM_SCREEN
    bra :+

    ; Disable the screen flag
@deselect_screen:
    and #(~OSTREAM_SCREEN) & $ff
:   sta ostream_flags

@done:
    jmp fetch_and_dispatch

    ; Are we selecting or deselecting the table?
@do_table:
    bit stream_select
    bmi @deselect_table

    ; See if we already have a table going
    lda ostream_flags
    bmi @check_overflow

    ; First table in the stack, so enable table flag and save address
    ora #OSTREAM_TABLE
    sta ostream_flags

@save_table_address:
    ; Decode the table address
    ldx operand_1
    ldy operand_1+1
    jsr decode_baddr
    pha
    phx
    phy

    ; Save the table address and zero the length there
    lda ostream_flags
    and #$0f
    sta table_aryidx
    asl
    clc
    adc table_aryidx
    sta table_aryidx
    tax
    pla
    sta ostream_table_bases,x
    sta zpu_mem
    inx
    pla
    sta ostream_table_bases,x
    sta zpu_mem+1
    inx
    pla
    sta ostream_table_bases,x
    sta zpu_mem+2
    sta BANK_RAM
    lda #0
    jsr mem_store_and_advance
    sta (zpu_mem)
    bra @done

@check_overflow:
    ; Already tables in stack, so see if we have room for another one
    and #$0f
    cmp #$0f
    beq @overflow

    ; There's room, so increment our index
    inc ostream_flags
    bra @save_table_address

@overflow:
    ; No room, so die a horrible death
    lda #ERR_STREAM_OVERFLOW
    jmp print_error_and_exit

@deselect_table:
    ; Is this the last table?
    lda ostream_flags
    bit #$0f
    beq @last_table

    ; Not the last table, so just decrement the table index
    dec ostream_flags
    bra @done

@last_table:
    ; Last table, so clear the table stream flag
    and #(~OSTREAM_TABLE) & $ff
    sta ostream_flags
    bra @done
.endproc

; print_zscii_to_table - Print a zscii character into the current table (if any)
; In:   a               - zscii character to print
; Out:  carry           - set if character was printed to a table
.proc print_zscii_to_table
    ; Check if there's a table stream open and return immediately if not
    bit ostream_flags
    bmi :+
    clc
    rts

    ; Load the stream index
table_aryidx = $4c0
:   phx
    phy
    pha
    lda ostream_flags
    and #$0f
    sta table_aryidx
    asl
    clc
    adc table_aryidx
    sta table_aryidx
    tax

    ; Save the table address into zpu_mem_2 so we can get at it
    lda ostream_table_bases,x
    sta zpu_mem_2
    inx
    lda ostream_table_bases,x
    sta zpu_mem_2+1
    inx
    lda ostream_table_bases,x
    sta zpu_mem_2+2
    sta BANK_RAM

    ; Get the current length
    jsr mem2_fetch_and_advance
    tay
    jsr mem2_fetch_and_advance
    tax
    phx
    phy

    ; Skip past the current contents of the table
    cpy #0
    beq @check_skip_bytes
@skip_blocks:
    jsr mem2_advance_block
    dey
    bne @skip_blocks
@check_skip_bytes:
    cpx #0
    beq @store_zscii
    txa
    jsr mem2_advance

    ; Store zscii in the table
@store_zscii:
    ply
    plx
    pla
    pha
    sta (zpu_mem_2)

    ; And increment the table length
    inx
    bne :+
    iny

    ; Store the new table length
:   phx
    ldx table_aryidx
    lda ostream_table_bases,x
    sta zpu_mem_2
    inx
    lda ostream_table_bases,x
    sta zpu_mem_2+1
    inx
    lda ostream_table_bases,x
    sta zpu_mem_2+2
    sta BANK_RAM
    tya
    jsr mem2_store_and_advance
    pla
    jsr mem2_store_and_advance

@done:
    pla
    ply
    plx
    sec
    rts
.endproc

.rodata

msg_op_output_stream:                   .byte "Output stream @", CH::ENTER, 0
msg_op_output_stream_with_table:        .byte "Output stream @ table=@", CH::ENTER, 0
msg_op_output_stream_with_table_width:  .byte "Output stream @ table=@ width=@", CH::ENTER, 0
