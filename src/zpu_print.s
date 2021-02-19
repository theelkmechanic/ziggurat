.include "ziggurat.inc"
.include "zpu.inc"

.code

op_encode_text:
op_print_table:
    jmp op_illegal

opext_check_unicode:
opext_print_form:
opext_print_unicode:
    jmp opext_illegal

return_after_printing = $400
three_chars = $401
end_flag = $404
alphabet_offset = $405
special_flags = $406
working_encchr = $407
partial_zscii = $408
abbrev_offset = $409
print_window = $40a
print_len = $40b
print_so_far = $40c
print_dots_at = $40d
zscii_work = $40e
zscii_zmem_save = $40f
memreg_save = $412

ALPHA_OFFSET_A1 = 26
ALPHA_OFFSET_A2 = 52

.proc op_print_ret
    lda #<msg_op_print_ret
    sta gREG::r6L
    lda #>msg_op_print_ret
    sta gREG::r6H
;    jsr printf

    lda #$80
    .byte $2c

    ; FALL THRU INTENTIONAL
.endproc

.proc op_print
    ; Print the encoded string at the PC
    lda #0
    sta return_after_printing
    lda #<msg_op_print
    sta gREG::r6L
    lda #>msg_op_print
    sta gREG::r6H
;    jsr printf

    lda zpu_pc
    sta zpu_mem
    lda zpu_pc+1
    sta zpu_mem+1
    lda zpu_pc+2
    sta zpu_mem+2
    lda current_window ; print to current window
    ldx #0 ; print whole string
    jsr print_encoded

    ; Advance the PC past the end of the string and keep executing
    lda zpu_mem
    sta zpu_pc
    lda zpu_mem+1
    sta zpu_pc+1
    lda zpu_mem+2
    sta zpu_pc+2

    ; Are we doing a newline/return true after we print?
    bit return_after_printing
    bmi @return_true
    jmp fetch_and_dispatch
@return_true:
    jsr print_new_line
    jmp op_rtrue
.endproc

op_print_paddr:
    lda #<msg_op_print_paddr
    sta gREG::r6L
    lda #>msg_op_print_paddr
    sta gREG::r6H
;    jsr printf

    ; Print the encoded string at the packed address in r0
    ldx operand_0
    ldy operand_0+1
    jsr decode_paddr_s
    bra print_addr_in_xya

op_print_addr:
    lda #<msg_op_print_addr
    sta gREG::r6L
    lda #>msg_op_print_addr
    sta gREG::r6H
;    jsr printf

    ; Print the encoded string at the byte-address in r0
    ldx operand_0
    ldy operand_0+1
    jsr decode_baddr
print_addr_in_xya:
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    pushb zpu_mem+2
    lda current_window ; print to current window
    ldx #0 ; print whole string
    jsr print_encoded
    popb
    jmp fetch_and_dispatch

.proc op_new_line
    ; Load a new-line into r0
    lda #<msg_op_new_line
    sta gREG::r6L
    lda #>msg_op_new_line
    sta gREG::r6H
;    jsr printf

    lda #CH::ENTER
    sta operand_0+1
    stz operand_0

    ; FALL THRU INTENTIONAL
.endproc

.proc op_print_char
    lda #<msg_op_print_char
    sta gREG::r6L
    lda #>msg_op_print_char
    sta gREG::r6H
;    jsr printf

    ; Set the print window to the current window
    lda current_window
    sta print_window

    ; Print the character in r0
    lda operand_0+1
    jsr print_zscii
    jmp fetch_and_dispatch
.endproc

; print_encoded - Print the encoded string at zpu_mem
; In:   a               - window to print to
;       x               - maximum print length
;       zpu_mem         - start of encoded string
; Out:  zpu_mem         - byte address immediately after the end of the encoded string
.proc print_encoded
    ; Save print window and print length and calculate index to start printing dots (if there's space)
    sta print_window
    stx print_len
    cpx #0
    beq print_encoded_abbrev
    cpx #4
    bcc @dont_print_dots
    txa
    sec
    sbc #3
    .byte $2c ; skip next instruction
@dont_print_dots:
    lda #$ff
@save_print_dots:
    sta print_dots_at
    stz print_so_far

    ; FALL THRU INTENTIONAL
.endproc

.proc print_encoded_abbrev
    ; Set alphabet to A0 and clear special flags and chars printed
    stz alphabet_offset
    stz special_flags

    ; FALL THRU INTENTIONAL
.endproc

.proc print_encoded_word
    ; Pull two bytes at a time
    jsr mem_fetch_and_advance
    tax
    jsr mem_fetch_and_advance
    tay

    ; High bit of X is the end of string flag
    stx end_flag

    ; Split out the first character
    txa
    lsr
    lsr
    and #$1f
    sta three_chars

    ; Split out the second character
    sty three_chars+1
    txa
    lsr
    ror three_chars+1
    lsr
    ror three_chars+1
    lsr three_chars+1
    lsr three_chars+1
    lsr three_chars+1

    ; Split out third character
    tya
    and #$1f
    sta three_chars+2

    ; Now map them to ZSCII and print them
    pushb atab_addr+2
    lda three_chars
    jsr print_encoded_char
    lda three_chars+1
    jsr print_encoded_char
    lda three_chars+2
    jsr print_encoded_char
    popb

    ; Check if we've reached the end
    bit end_flag
    bpl print_encoded_word
    rts
.endproc

; print_encoded_char - Print a single encoded character, keeping track of printing state
; In:   a           - Encoded character
.proc print_encoded_char
    ; Test the special flags:
    ;   $80 - this is an abbreviation byte
    ;   $40 - this is a zscii 10-bit ($20 clear = first part, $20 set = second part)
    sta working_encchr
    lda #$20
    bit special_flags
    bvs @handle_zscii
    bmi @handle_abbrev

    ; Is it a special character?
    lda working_encchr
    cmp #6
    bcc @handle_special
    bne @handle_regular

    ; Character 6 in alphabet A2 is special; it turns the next two characters into a 10-bit ZSCII character,
    ; so we need to set that we're waiting for the first of two characters to build our special character
    ldy alphabet_offset
    cpy #ALPHA_OFFSET_A2
    bne @handle_regular
    lda #$40
    sta special_flags
    rts

@handle_regular:
    ; Subtract 6, add the current alphabet offset, and look up the right character mapping
    sec
    sbc #6
    clc
    adc alphabet_offset
    pha
    lda atab_addr
    sta zpu_mem_2
    lda atab_addr+1
    sta zpu_mem_2+1
    lda atab_addr+2
    sta zpu_mem_2+2
    sta BANK_RAM
    pla
    jsr mem2_advance
    lda (zpu_mem_2)

    ; Clear the alphabet offset for next time
    ; TODO: FIX FOR V1/2
    stz alphabet_offset
    jmp print_zscii_check_len

@handle_special:
    ; Jump to the correct handler
    asl
    tax
    chkver V1|V2,@handle_special_v3plus
    jmp (specchr_handler_v1_vectors,x)
@handle_special_v3plus:
    jmp (specchr_handler_v3_vectors,x)

@handle_zscii:
    ; Are we on the first or second byte?
    bne @second_byte

    ; Store the low 5 bits into the top of our partial zscii character
    lda working_encchr
    asl
    asl
    asl
    asl
    asl
    sta partial_zscii

    ; And set flag that we're waiting for second byte
    lda #$60
    sta special_flags
    rts

@second_byte:
    ; Merge the low 5 bits into our partial
    lda working_encchr
    and #$1f
    ora partial_zscii

    ; Clear the special flags and alphabet for next time
    stz alphabet_offset
    stz special_flags

    ; And print the ZSCII character
    jmp print_zscii_check_len

@handle_abbrev:
    ; Save the current string position and characters
    lda zpu_mem
    sta memreg_save
    lda zpu_mem+1
    sta memreg_save+1
    lda zpu_mem+2
    sta memreg_save+2
    lda three_chars
    sta memreg_save+3
    lda three_chars+1
    sta memreg_save+4
    lda three_chars+2
    sta memreg_save+5
    lda end_flag
    sta memreg_save+6

    ; Add our abbreviation offset and the base of our abbreviation table
    lda working_encchr
    asl
    clc
    adc abbrev_base+1
    tay
    lda #0
    adc abbrev_base
    tax
    clc
    tya
    adc abbrev_offset
    tay
    txa
    adc #0
    tax

    ; Print the abbreviation
    jsr decode_baddr    ; Get the address of the abbreviation
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta BANK_RAM
    jsr mem_fetch_and_advance   ; Get the address of the actual abbreviation string
    tax
    lda (zpu_mem)
    tay
    jsr decode_waddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta BANK_RAM
    jsr print_encoded_abbrev

    ; Restore the current string position and characters
    lda memreg_save+6
    sta end_flag
    lda memreg_save+5
    sta three_chars+2
    lda memreg_save+4
    sta three_chars+1
    lda memreg_save+3
    sta three_chars
    lda memreg_save+2
    sta zpu_mem+2
    lda memreg_save+1
    sta zpu_mem+1
    lda memreg_save
    sta zpu_mem

    ; And go on to the next character
    stz alphabet_offset
    stz special_flags
    rts
.endproc

.proc specchr_handler_abbrev_or_crlf
    chkver V2,print_new_line

    ; FALL THROUGH INTENTIONAL
.endproc

.proc specchr_handler_abbrev
    ; Set the abbreviation offset (32*(z-1) words) and flag
    lda #$80
    sta special_flags
    lda working_encchr
    dec
    asl
    asl
    asl
    asl
    asl
    asl
    sta abbrev_offset
    rts
.endproc

.proc specchr_handler_shift_a1
    ; Set the alphabet offset for the next round
    lda #ALPHA_OFFSET_A1
    .byte $2c

    ; FALL THRU INTENTIONAL
.endproc

.proc specchr_handler_shift_a2
    ; Set the alphabet offset for the next round
    lda #ALPHA_OFFSET_A2
    sta alphabet_offset
    rts
.endproc

.proc specchr_handler_space
    ; Want to print a space
    lda #' '

    ; FALL THRU INTENTIONAL
.endproc

.proc print_zscii_check_len
    ; Are we restricting length?
    phy
    phx
    ldx print_len
    beq print_zscii_1
    ldx print_so_far
    cpx print_len
    bcc @1
    plx
    ply
    rts
@1: cpx print_dots_at
    bcc print_zscii_1
    lda #'.'
    bra print_zscii_1
.endproc

.proc print_new_line
    ; Zero out the length since we've gone to a new line
    stz print_len
    stz print_so_far

    ; Print a new-line
    lda #CH::ENTER

    ; FALL THRU INTENTIONAL
.endproc

; print_zscii - Print the ZSCII character in a
print_zscii:
    phy
    phx
.proc print_zscii_1
    ; First make sure the character is printable
    jsr z_isoutput
    bcc @done

    ; Convert the ZSCII character in a to a UTF-16 character in x/y. Everything less than 128 matches Unicode.
    bit #$80
    bne @check_high
    ldx #0
    tay
    bra @print_it

@check_high:
    ; Characters from 155 on up we have to convert using the Unicode table
    cmp #155
    bcc @done
    jsr convert_zsciihigh_to_unicode

    ; If carry is set at this point, we didn't find it
    bcs @done

@print_it:
    ; Print the character in x/y and advance the cursor
    lda print_window
    sec
    jsr win_putchr
    inc print_so_far
@done:
    plx
    ply
    rts
.endproc

.proc convert_zsciihigh_to_unicode
    sec
    sbc #155
    sta zscii_work

    ; Switch to Unicode table
    lda utf_xlat_addr
    sta zpu_mem_2
    lda utf_xlat_addr+1
    sta zpu_mem_2+1
    lda utf_xlat_addr+2
    sta zpu_mem_2+2
    ldx BANK_RAM
    phx
    sta BANK_RAM

    ; See if we have the specified character in our table
    jsr mem2_fetch_and_advance
    cmp zscii_work
    bcc @restore_bank

    ; It's in the table, so load it into x/y
    lda zscii_work
    asl
    beq @1
    jsr mem2_advance
@1: jsr mem2_fetch_and_advance
    tax
    lda (zpu_mem_2)
    tay

    ; And flag that we found it
    clc

@restore_bank:
    ; Restore previous bank
    pla
    sta BANK_RAM
    rts
.endproc

specchr_handler_shiftlock_up:
specchr_handler_shiftlock_down:
    ; TODO: Implement this properly
    lda #ERR_ILLEGAL_VERSION
    jmp print_error_and_exit

.proc op_print_num
    lda #<msg_op_print_num
    sta gREG::r6L
    lda #>msg_op_print_num
    sta gREG::r6H
;    jsr printf

    lda current_window ; print to current window
    sec ; No leading zeroes
    jsr do_print_num
    jmp fetch_and_dispatch
.endproc

.proc do_print_num
dec_value = $400
started_printing_digits = $403
print_two_digits = $404
    ; Print the number in operand_0 as a signed integer
    sta print_window
    stz print_len

    ; If carry set, no leading zeroes; if carry clear, make sure we print two digits (for time display)
    lda #0
    sbc #0
    sta print_two_digits

    ; First print minus sign if we're negative
    bit operand_0
    bpl @positive
    lda #'-'
    jsr print_zscii

    ; Then invert and add 1 to make us positive
    lda operand_0+1
    eor #$ff
    clc
    adc #1
    sta operand_0+1
    lda operand_0
    eor #$ff
    adc #0
    sta operand_0

@positive:
    ; Convert to decimal value in zpu_mem by adding in bits from high to low in decimal mode
    sed
    stz dec_value
    stz dec_value+1
    stz dec_value+2
    ldx #16 ; Loop over all 16 bits

@shiftadd_loop:
    ; Get the high bit in the carry
    asl operand_0+1
    rol operand_0

    ; And add it into our decimal version
    lda dec_value+2
    adc dec_value+2
    sta dec_value+2
    lda dec_value+1
    adc dec_value+1
    sta dec_value+1
    lda dec_value
    adc dec_value
    sta dec_value
    dex
    bne @shiftadd_loop
    cld

    ; Okay, now we have the digits in dec_value nibbles, so we can print them like printhex does,
    ; except we won't print zeroes until we've printed a non-zero value or we're on the last one
    stz started_printing_digits
    ldy #0
@printloop:
    lda dec_value,y
    lsr
    lsr
    lsr
    lsr
    bne @print_digit1
    cpy #2
    bne @check_started
    bit print_two_digits
    bpl @skip_digit1
    dec started_printing_digits
@check_started:
    bit started_printing_digits
    bpl @skip_digit1
@print_digit1:
    ora #$30
    jsr print_zscii
    dec started_printing_digits
@skip_digit1:
    lda dec_value,y
    and #$0f
    bne @print_digit2
    bit started_printing_digits
    bmi @print_digit2
    cpy #2
    bne @skip_digit2
@print_digit2:
    ora #$30
    jsr print_zscii
    dec started_printing_digits
@skip_digit2:
    iny
    cpy #3
    bne @printloop
    rts
.endproc

.rodata

specchr_handler_v1_vectors:
    .word specchr_handler_space
    .word specchr_handler_abbrev_or_crlf
    .word specchr_handler_shift_a1
    .word specchr_handler_shift_a2
    .word specchr_handler_shiftlock_up
    .word specchr_handler_shiftlock_down

specchr_handler_v3_vectors:
    .word specchr_handler_space
    .word specchr_handler_abbrev
    .word specchr_handler_abbrev
    .word specchr_handler_abbrev
    .word specchr_handler_shift_a1
    .word specchr_handler_shift_a2

atab_default:       .byte $61, $62, $63, $64, $65, $66, $67, $68, $69, $6a, $6b, $6c, $6d, $6e, $6f, $70, $71, $72, $73, $74, $75, $76, $77, $78, $79, $7a
                    .byte $41, $42, $43, $44, $45, $46, $47, $48, $49, $4a, $4b, $4c, $4d, $4e, $4f, $50, $51, $52, $53, $54, $55, $56, $57, $58, $59, $5a
                    .byte $00, $0d, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $2e, $2c, $21, $3f, $5f, $23, $27, $22, $2f, $5c, $2d, $3a, $28, $29
atab_v1_default:    .byte $61, $62, $63, $64, $65, $66, $67, $68, $69, $6a, $6b, $6c, $6d, $6e, $6f, $70, $71, $72, $73, $74, $75, $76, $77, $78, $79, $7a
                    .byte $41, $42, $43, $44, $45, $46, $47, $48, $49, $4a, $4b, $4c, $4d, $4e, $4f, $50, $51, $52, $53, $54, $55, $56, $57, $58, $59, $5a
                    .byte $00, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $2e, $2c, $21, $3f, $5f, $23, $27, $22, $2f, $5c, $3c, $2d, $3a, $28, $29

msg_op_print: .byte "Printing encoded text at PC", CH::ENTER, 0
msg_op_print_ret: .byte "Return after print", CH::ENTER, 0
msg_op_new_line: .byte "Print new-line", CH::ENTER, 0
msg_op_print_char: .byte "Printing ZSCII character @", CH::ENTER, 0
msg_op_print_num: .byte "Printing number @", CH::ENTER, 0
msg_op_print_addr: .byte "Printing encoded text at byte addr @", CH::ENTER, 0
msg_op_print_paddr: .byte "Printing encoded text at packed addr @", CH::ENTER, 0
