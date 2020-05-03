.include "ziggurat.inc"
.include "zpu.inc"
.include "zscii_type.inc"

was_buffering = $440
last_flash = $441
last_flash_on = $442

read_start_x = $443
read_start_y = $444
last_scrl_cnt = $445
max_chars = $446
chars_typed = $447
read_v5 = $448
term_char = $449

max_words = $44a
words_typed = $44b
text_idx = $440
skip_unknown = $441
parse_char = $442
num_seps = $443
word_dict = $44c
word_pos = $44e
word_len = $44f
word_buf = $500

encoded_buf = $600
encoded_size = $60f
max_zchars = $610
current_zchar = $611


entry_count = $444
entry_size = $446
dict_0 = $612
dict_addr = $614
dict_idx_x2 = $616
dict_idx_x4 = $618
dict_idx_x8 = $616
curr_idx = $61a
range_begin = $61c
range_end = $61e
memreg_save = $620

.code

op_input_stream:
    jmp op_illegal

.proc op_read_char
    lda #<msg_op_read_char
    sta gREG::r6L
    lda #>msg_op_read_char
    sta gREG::r6H
    jsr printf

    ; Flush the current buffer and reset the scroll count
    lda current_window
    jsr win_flushbuffer
    jsr win_resetscrlcnt

    ; Read a key from the keyboard
    jsr read_char

    ; Return it in the result
    ldx #0
    tay
    jsr pc_fetch_and_advance
    clc ; Push to stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc read_char
    ; Turn off buffering if necessary (but remember if it was on)
    phx
    phy
    lda current_window
    jsr win_getflags
    txa
    and #WIN_BUFFER
    sta was_buffering
    beq @start_flashing
    lda current_window
    ldx #0
    jsr win_setbuffer

@start_flashing:
    ; Start the cursor flashing
    stz last_flash_on
    jsr RDTIM

    ; Flash the cursor on/off as needed
@flash_cursor:
    phy
    lda current_window
    ldx #0
    ldy last_flash_on
    bmi @flash_off

    ; Flash cursor on
    ldy #$5f
    .byte $2c

@flash_off:
    ; Flash cursor off
    ldy #$20
    clc ; Don't advance cursor
    jsr win_putchr

    ; Flip flash bit and update flash time
    lda last_flash_on
    eor #$ff
    sta last_flash_on
    pla
    sta last_flash

@read_loop:
    ; Read a character from the keyboard
    jsr GETIN

    ; Map the key to ZSCII
    tax
    lda x16key_to_zscii,x

    ; Is it a valid input key?
    jsr z_isinput
    bcs @return_char

    ; Flash cursor every 30 ticks
    jsr RDTIM
    tya
    sec
    sbc last_flash
    cmp #30
    bcc @read_loop
    bra @flash_cursor

@return_char:
    ; Erase the cursor
    pha
    lda current_window
    ldx #0
    ldy #$20
    clc ; Don't advance the cursor
    jsr win_putchr
    pla

    ; Reenable buffering if we need to
    bit was_buffering
    bvc @done
    pha
    lda current_window
    ldx #1
    jsr win_setbuffer
    pla

@done:
    ply
    plx
    rts
.endproc

.proc op_read
    lda #<msg_op_read
    sta gREG::r6L
    lda #>msg_op_read
    sta gREG::r6H
    jsr printf

    ; Show the status line in versions 1-3
    lda zpu_verflag
    bit #V1|V2|V3
    beq @nostatus
    jsr show_status

@nostatus:
    ; Are we v5+?
    stz read_v5
    bit #V5|V6|V7|V8
    beq @getbufsize
    dec read_v5

@getbufsize:
    ; Get the text buffer size
    ldx operand_0
    ldy operand_0+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA
    jsr mem_fetch_and_advance
    sta max_chars
    stz chars_typed

    ; Flush the window buffer (if any) and reset the scroll count
    lda current_window
    jsr win_flushbuffer
    jsr win_resetscrlcnt
    stz last_scrl_cnt

    ; Save the starting entry position
    jsr win_getcursor
    stx read_start_x
    sty read_start_y

    ; If we're v5+, byte 1 is where we return the length. Also, if it's non-zero, it's the number of
    ; characters already in the buffer, so we need to keep track of that as well.
    bit read_v5
    bpl @read_loop
    jsr mem_fetch_and_advance
    cmp #0
    beq @read_loop
    cmp max_chars
    bcc @skip_already_in_buffer
    lda max_chars
@skip_already_in_buffer:
    sta chars_typed
    jsr mem_advance

@read_loop:
    ; Read a character from the current window
    jsr read_char

    ; Has the window scrolled?
    tay
    lda current_window
    jsr win_getscrlcnt
    cpx last_scrl_cnt
    bne @update_startline
    tya
    bra @check_bksp

@update_startline:
    ; Scroll count changed, so update starting line based on the change
    txa
    sec
    sbc last_scrl_cnt
    sta last_scrl_cnt
    lda read_start_y
    sec
    sbc last_scrl_cnt
    sta read_start_y
    stx last_scrl_cnt
    tya

@check_bksp:
    ; Check for backspace
    cmp #8
    bne @check_term

    ; Can we back up at all?
    lda current_window
    jsr win_getcursor
    cpy read_start_y
    bcc @read_loop
    bne @check_beginning

    ; If we're at our starting position, don't back up any more
    cpx read_start_x
    bne @just_back_up
    bra @read_loop

@check_beginning:
    ; Are we at the beginning of a line?
    cpx #0
    bne @just_back_up

    ; Can we go back one line?
    cpy read_start_y
    beq @read_loop

    ; Need to go back one line
    dey
    phy
    jsr win_getsize
    ply

@just_back_up:
    ; Step back one character
    dex
    lda current_window
    jsr win_setcursor

    ; Remove a character from the buffer
    lda #1
    jsr mem_retreat
    dec chars_typed
    bra @read_loop

    ; Check for terminating keystroke
@check_term:
;    bit read_v5
;    bmi @check_term_characters

    ; For v1-4, terminating character is just a newline
    cmp #13
    bne @check_output
    sta term_char
    tay
    ldx #0
    lda current_window
    jsr win_putchr
    bra @entry_done

@check_term_characters:

@check_output:
    ; Is there room in the buffer?
    ldx chars_typed
    cpx max_chars
    bcs @read_loop

    ; Is the character valid for output?
    jsr z_isoutput
    bcc @read_loop

    ; If it's in the ZSCII high range, convert it to Unicode before printing (32-126 matches already)
    cmp #155
    bcc @print_char
    pha
    jsr convert_zsciihigh_to_unicode
    bcc @print_high ; not found
    jmp @read_loop
@print_high:
    lda current_window
    sec ; Advance the cursor
    jsr win_putchr
    pla
    bra @store_lower

@print_char:
    ; Print the character, add it as lowercase to the buffer, and loop
    tay
    ldx #0
    lda current_window
    sec ; Advance the cursor
    jsr win_putchr
    tya

@store_lower:
    jsr z_tolower
    jsr mem_store_and_advance
    inc chars_typed
    jmp @read_loop

@entry_done:
    ; Done entering, are we v5+?
    bit read_v5
    bmi @store_length

    ; v1-4 stores a NUL at the end
    lda #0
    jsr mem_store_and_advance
    bra @check_parse

@store_length:
    ; v5+ stores the length typed at byte 1 of the array
    ldx operand_0
    ldy operand_0+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA
    lda #1
    jsr mem_advance
    lda chars_typed
    sta (zpu_mem)

@check_parse:
    ; In v5+, if parse buffer is 0, skip parsing
    bit read_v5
    bpl @do_parse
    lda operand_1
    ora operand_1+1
    beq @done

@do_parse:
    ; Parse the entered text
    lda dict_base
    sta operand_2
    lda dict_base+1
    sta operand_2+1
    stz operand_3
    stz operand_3+1
    jsr parse_text

@done:
    ; If it's v5+, need to return the terminating character
    bit read_v5
    bpl @noresult
    lda zpu_pc+2
    sta VIA1::PRA
    jsr pc_fetch_and_advance
    ldx #0
    ldy term_char
    clc ; Push to stack if necessary
    jsr store_varvalue

@noresult:
    jmp fetch_and_dispatch
.endproc

; parse_text - Helper for op_sread to parse entered text
; In:   operand_0       - Pointer to text buffer
;       operand_1       - Pointer to parse buffer
;       operand_2       - Pointer to dictionary to use
;       operand_3       - If non-zero, don't put unrecognized words in the parse buffer
;       chars_typed     - Number of characters entered in the text buffer
;       read_v5         - Positive if v1-4, negative if v5+ (text buffer is formatted differently)
; Out:  operand_1       - Contents of parse buffer updated with parsed words (see Inform Standard v1.1, section 15)
.proc parse_text
    ; Start at the beginning of the text in the text buffer
    stz text_idx
    ldx operand_0
    ldy operand_0+1
    jsr decode_baddr
    sty zpu_mem_2
    stx zpu_mem_2+1
    sta zpu_mem_2+2
    jsr mem2_fetch_and_advance
    bit read_v5
    bpl @nolengthbyte
    jsr mem2_fetch_and_advance
@nolengthbyte:

    ; Get the number of words we can put in the parse buffer
    ldx operand_1
    ldy operand_1+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA
    jsr mem_fetch_and_advance
    sta max_words
    jsr mem_fetch_and_advance
    stz words_typed

@parse_loop:
    ; Can we still parse words?
    lda words_typed
    cmp max_words
    bcs @done_parsing

    ; Parse a word from the text buffer
    jsr parse_word
    bcc @done_parsing

    ; Copy the word information into the parse buffer
    lda zpu_mem+2
    sta VIA1::PRA
    ldx #0
@1: lda word_dict,x
    jsr mem_store_and_advance
    inx
    cpx #4
    bne @1

    ; Increment the word count and loop
    inc words_typed
    bra @parse_loop

@done_parsing:
    ; Store the number of words typed in the parse buffer
    ldx operand_1
    ldy operand_1+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA
    jsr mem_fetch_and_advance
    lda words_typed
    jmp mem_store_and_advance
.endproc

; parse_word - Helper for parse_text to parse a single word from the text buffer
; In:   zpu_mem_2       - Pointer to next character in text buffer
;       chars_typed     - Length of text in buffer
;       text_idx        - Current position into text buffer
; Out:  word_dict       - Matching dictionary entry for parsed word (0 if not in dictionary)
;       word_pos        - Position of start of parsed word in text buffer
;       word_len        - Length of parsed word in text buffer
;       carry           - Set if word was successfully parsed
.proc parse_word
    lda zpu_mem_2+2
    sta VIA1::PRA

@trim_loop:
    ; Check if we still have characters
    lda text_idx
    cmp chars_typed
    bcc @haveacharacter

    ; No more words
    clc
    rts

@haveacharacter:
    ; Trim spaces
    jsr mem2_fetch_and_advance
    inc text_idx
    sta parse_char
    cmp #32
    beq @trim_loop

@notaspace:
    ; Save the start of this word
    lda text_idx
    dec
    sta word_pos
    ldx #0
    lda parse_char
    sta word_buf,x
    inx
    stx word_len

    ; Save zpu_mem since check_sep and the search use it
    lda zpu_mem
    sta memreg_save
    lda zpu_mem+1
    sta memreg_save+1
    lda zpu_mem+2
    sta memreg_save+2

    ; If the first character is a separator, it's a whole word
    jsr check_sep
    bcs @have_whole_word

@scan_word_loop:
    ; It's not a separator, so scan until we find a space or separator or run out of characters
    lda text_idx
    cmp chars_typed
    bcs @have_whole_word
    lda zpu_mem_2+2
    sta VIA1::PRA
    jsr mem2_fetch_and_advance
    sta parse_char
    inc text_idx
    ldx word_len
    sta word_buf,x
    cmp #32
    beq @have_whole_word
    jsr check_sep
    bcs @endwithseparator
    inc word_len
    bra @scan_word_loop

@endwithseparator:
    ; Make sure we don't skip the separator
    lda #1
    jsr mem2_retreat
    dec text_idx

@have_whole_word:
    ; Encode the word
    jsr encode_word

    ; Now we need to look for the word in the dictionary
    ldx operand_2
    ldy operand_2+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA

    ; Skip the separators
    jsr mem_fetch_and_advance
    tax
@1: cpx #0
    beq @getsizeandcount
    jsr mem_fetch_and_advance
    dex
    bra @1

@getsizeandcount:
    ; Save the entry size and count
    jsr mem_fetch_and_advance
    sta entry_size
    jsr mem_fetch_and_advance
    sta entry_count+1
    jsr mem_fetch_and_advance
    sta entry_count

    ; Find the encoded word in the dictionary (fills in word_dict)
    jsr find_encoded_word

    ; Restore zpu_mem
    lda memreg_save
    sta zpu_mem
    lda memreg_save+1
    sta zpu_mem+1
    lda memreg_save+2
    sta zpu_mem+2
    sta VIA1::PRA

    ; Return true that we parsed a word
    sec
    rts
.endproc

; check_sep - Return carry set if parse_char is in dictionary separator list
.proc check_sep
    ; Get the dictionary address into zpu_mem
    ldx operand_2
    ldy operand_2+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA

    ; Scan the word separators to see if this is one
    jsr mem_fetch_and_advance
    tax
@scan_seps_loop:
    cpx #0
    bne @1
    clc
    rts
@1: jsr mem_fetch_and_advance
    cmp parse_char
    beq @isasep
    dex
    bra @scan_seps_loop
@isasep:
    sec
    rts
.endproc

.proc op_tokenise
    ; Get the text buffer into zpu_mem
    ldx operand_0
    ldy operand_0+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA
    jsr mem_fetch_and_advance

    ; Are we v5+?
    stz read_v5
    bit #V5|V6|V7|V8
    bne @v5

    ; For v1-4, we need to count the number of characters in the text buffer by looking
    ; for the NUL at the end
    ldx #0
@strlen_loop:
    jsr mem_fetch_and_advance
    beq @set_param_defaults
    inx
    bra @strlen_loop

@v5:
    ; For v5+, the string length is in byte 1, so just read it
    lda (zpu_mem)
    tax

    ; And set the v5+ flag
    dec read_v5

@set_param_defaults:
    ; Set default values for our parameters if they're missing
    stx chars_typed
    lda num_operands
    cmp #4
    bcs @do_parse
    stz operand_3
    stz operand_3+1
    cmp #3
    bcs @do_parse
    lda dict_base
    sta operand_2
    lda dict_base+1
    sta operand_2+1

@do_parse:
    ; And parse the text
    lda #<msg_op_tokenise
    sta gREG::r6L
    lda #>msg_op_tokenise
    sta gREG::r6H
    jsr printf
    jsr parse_text
    jmp fetch_and_dispatch
.endproc

; Encode the word in word_buf that is word_len bytes long into encoded_buf
.proc encode_word
    ; How many characters we map depends on the version. We encode 6 Z-characters in v1-3, and 9 Z-characters
    ; in later versions
    chkver V1|V2|V3,@need9
    ldx #6
    .byte $2c
@need9:
    ldx #9
    stx max_zchars
    stz current_zchar
    ldy #0

@convert_loop:
    ; First convert ZSCII to Z-characters
    lda word_buf,y
    cmp #33
    bcc @shouldnt ; shouldn't get less than 33
    cmp #127
    bcc @in_low ; shouldn't get more than 126
    cmp #155
    bcc @shouldnt

    ; See if it's a valid upper ZSCII
    phx
    phy
    jsr convert_zsciihigh_to_unicode
    ply
    plx
    bcc @need_straight

@shouldnt:
    sta operand_0
    lda #ERR_INVALID_PARSE_CHAR
    jsr print_error_and_exit

@in_low:
    ; Map the ZSCII character to the matching Z-character
    sec
    sbc #33
    tax
    lda zscii_encode_map,x

    ; Do we have to encode it as ZSCII?
    bit #$40
    bne @need_straight

    ; Is it in A2?
    bit #$80
    bne @need_shift

    ; It's in A0, so just store it
    bra @store_and_next

@need_shift:
    ; Do we have at least 2 entries left?
    tax
    lda max_zchars
    sec
    sbc current_zchar
    cmp #2
    bcc @pad_out

    ; Store the shift
    phx
    lda #5
    ldx current_zchar
    sta encoded_buf,x
    inc current_zchar
    pla

@store_and_next:
    ; Store the Z-character
    and #$1f
    ldx current_zchar
    sta encoded_buf,x
    inx

    ; See if we've converted as many Z-characters as we are allowed
    cpx max_zchars
    beq @convert_done
    stx current_zchar

    ; See if we have anything else in the buffer
    iny
    cpy word_len
    bcc @convert_loop

@pad_out:
    ; Pad A2 shifts until we fill the Z-characters
    lda #5
    ldx current_zchar
@1: sta encoded_buf,x
    inx
    cpx max_zchars
    bcc @1
    bra @convert_done

@need_straight:
    ; Store an A2 shift
    lda #5
    ldx current_zchar
    sta encoded_buf,x
    inc current_zchar

    ; Still have space?
    inx
    cpx max_zchars
    beq @convert_done

    ; Store an A2 $06 (2-byte ZSCII flag)
    lda #6
    sta encoded_buf,x
    inc current_zchar

    ; Still have space?
    inx
    cpx max_zchars
    beq @convert_done

    ; Store high 3 bits of our ZSCII character
    lda word_buf,y
    lsr
    lsr
    lsr
    lsr
    lsr
    sta encoded_buf,x
    inc current_zchar

    ; Still have space?
    inx
    cpx max_zchars
    beq @convert_done

    ; Store low 5 bits of our ZSCII character
    lda word_buf,y
    bra @store_and_next

@convert_done:
    ; We now have all the characters we need in encoded_buf. Now compress them down.
    ldx #0
    ldy #0

@compress_loop:
    ; Get first Z-character
    lda encoded_buf,x

    ; Shift in first two bits of bottom 5 bits of second Z-character
    inx
    asl encoded_buf,x
    asl encoded_buf,x
    asl encoded_buf,x
    asl encoded_buf,x
    rol
    asl encoded_buf,x
    rol

    ; And store back in encoded buffer
    sta encoded_buf,y

    ; Now we have bottom 3 bits of second Z-character in the top three bits, so read it in, and
    ; then combine it with the third Z-character
    lda encoded_buf,x
    inx
    ora encoded_buf,x
    iny
    sta encoded_buf,y

    ; Step to next chunk of Z-characters
    inx
    iny

    ; And see if we reached the end
    cpx max_zchars
    bcc @compress_loop

    ; Now we compressed all the characters, so save the encoded size and step y back 2 so we can
    ; set the terminating high bit
    sty encoded_size
    dey
    dey
    lda encoded_buf,y
    ora #$80
    sta encoded_buf,y
    rts
.endproc

; Find the encoded word in encoded_buf in the dictionary at zpu_mem with entry_count entries of size entry_size
; (Note: If entry_count is negative, dictionary is unsorted and we have to do a linear search; otherwise we can
; do a binary search)
.proc find_encoded_word
    ; Save zpu_mem as a byte address (big-endian)
    lda zpu_mem
    sta dict_0+1
    lda zpu_mem+2
    ldx zpu_mem+1
    jsr encode_baddr
    stx dict_0

    bit entry_count+1
    bpl @do_binary_search

    ; Negate the entry count and do a linear search
    ldx entry_count+1
    ldy entry_count
    jsr negate_xy
    stx entry_count+1
    sty entry_count

    ; Start at index 0
    stz curr_idx
    stz curr_idx+1

@linear_loop:
    ; Compare this entry
    jsr compare_encoded_to_entry
    beq @found

    ; No match so step to next
    inc curr_idx+1
    bne @1
    inc curr_idx
@1: lda curr_idx
    cmp entry_count
    bne @linear_loop
    lda curr_idx+1
    cmp entry_count+1
    bne @linear_loop

@not_found:
    ; Not in the dictionary, so store 0 in word_dict
    ldx #0
    ldy #0

@store_and_return:
    stx word_dict
    sty word_dict+1
    rts

@found:
    ; Found, so store byte address of entry in word_dict
    ldx curr_idx
    ldy curr_idx+1
    jsr calc_dict_address
    bra @store_and_return

@do_binary_search:
    ; Set range (0 .. entry_count-1)
    lda entry_count
    sec
    sbc #1
    sta range_end+1
    lda entry_count+1
    sbc #0
    sta range_end
    ldx #0
    ldy #0
@save_range_begin:
    stx range_begin
    sty range_begin+1

@binary_loop:
    ; Check if end < begin
    ldy range_end+1
    ldx range_end
    cpx range_begin
    bne @2
    cpy range_begin+1
@2: bcc @not_found ; beginning passed end, so it's not in there

    ; Calculate midpoint index (begin+end)/2
    lda range_begin+1
    clc
    adc range_end+1
    sta curr_idx+1
    lda range_begin
    adc range_end
    sta curr_idx
    lsr curr_idx
    ror curr_idx+1

    ; Compare encoded_buf to entry
    jsr compare_encoded_to_entry

    ; If it's equal, we found it
    beq @found

    ; If it's greater, then look above
    bcs @look_above

    ; It's less, so set range_end to curr_idx-1
    lda curr_idx+1
    sec
    sbc #1
    sta range_end+1
    lda curr_idx
    sbc #0
    sta range_end
    bra @binary_loop

@look_above:
    ; Set range_begin to curr_idx+1
    ldx curr_idx
    ldy curr_idx+1
    iny
    bne @save_range_begin
    inx
    bra @save_range_begin
.endproc

; Compare encoded_buf to entry at curr_idx and return with flags set:
;   N set = encoded buffer less than entry at index
;   Z set = encoded buffer same as entry at index
;   both clear = encoded buffer greater than entry at index
.proc compare_encoded_to_entry
    ; Get the address of the dictionary entry we want to compare to
    ldx curr_idx
    ldy curr_idx+1
    jsr calc_dict_address

    ; Convert to bank/addr and store in zpu_mem
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA

    ; Now compare max_zchars bytes at encoded_buf to those at zpu_mem and return flags
    ldx #0
@compare_loop:
    lda encoded_buf,x
    cmp (zpu_mem)
    beq @check_next
@compare_done:  ; We're done if we find something that doesn't match
    rts

@check_next:
    ; If we compared everything, they're equal
    inx
    cpx encoded_size
    beq @compare_done

    ; Step ahead in the dictionary as well
    jsr mem_fetch_and_advance
    bra @compare_loop
.endproc

; Calculate the address of a dictionary entry
; In:   x/y         - dictionary index (0-based, x=hi, y=lo)
;       dict_0      - byte address of dictionary entry 0
;       entry_size  - size of dictionary entries
; Out:  x/y         - byte address of desired dictionary entry (x=hi, y=lo)
.proc calc_dict_address
    ; Start with dict addr = index, and store in dict_idx_x2/dict_idx_x8, and zero dict_idx_x4
    stx dict_addr
    sty dict_addr+1
    stx dict_idx_x2
    sty dict_idx_x2+1
    stz dict_idx_x4
    stz dict_idx_x4+1

    ; What's the entry size?
    lda entry_size
    cmp #7
    beq @mulby7
    cmp #9
    bne @mulbysize

    ; Multiply by 9, which is idx*8 + idx
    asl dict_idx_x8+1
    rol dict_idx_x8
    asl dict_idx_x8+1
    rol dict_idx_x8
    bra @mulby2andadd

@mulby7:
    ; Multiply by 7, which is idx*4 + idx*2 + idx
    stx dict_idx_x4
    sty dict_idx_x4+1
    asl dict_idx_x4+1
    rol dict_idx_x4
    asl dict_idx_x4+1
    rol dict_idx_x4

@mulby2andadd:
    ; Multiply by 2
    asl dict_idx_x2+1
    rol dict_idx_x2

    ; Then add both into original
    lda dict_addr+1
    clc
    adc dict_idx_x2+1
    sta dict_addr+1
    lda dict_addr
    adc dict_idx_x2
    sta dict_addr
    lda dict_addr+1
    clc
    adc dict_idx_x4+1
    sta dict_addr+1
    lda dict_addr
    adc dict_idx_x4
    sta dict_addr

@addbase:
    ; Then add the base
    lda dict_addr+1
    clc
    adc dict_0+1
    tay
    lda dict_addr
    adc dict_0
    tax
    rts

@mulbysize:
    ; Generic multiply -- for now just die
    .byte $ff
.endproc

.rodata

x16key_to_zscii:
    .byte $00, $00, $00, $1b, $00, $00, $00, $00,  $00, $00, $00, $00, $00, $0d, $00, $00
    .byte $00, $82, $00, $00, $08, $00, $00, $00,  $00, $00, $00, $00, $00, $84, $00, $00
    .byte $20, $21, $22, $23, $24, $25, $26, $27,  $28, $29, $2a, $2b, $2c, $2d, $2e, $2f
    .byte $30, $31, $32, $33, $34, $35, $36, $37,  $38, $39, $3a, $3b, $3c, $3d, $3e, $3f
    .byte $40, $61, $62, $63, $64, $65, $66, $67,  $68, $69, $6a, $6b, $6c, $6d, $6e, $6f
    .byte $70, $71, $72, $73, $74, $75, $76, $77,  $78, $79, $7a, $5b, $db, $5d, $5e, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00,  $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00,  $00, $00, $00, $00, $db, $00, $00, $00
 
    .byte $00, $00, $00, $00, $00, $85, $87, $89,  $8b, $86, $88, $8a, $8c, $00, $00, $00
    .byte $00, $81, $00, $00, $00, $00, $00, $00,  $00, $00, $00, $00, $00, $83, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00,  $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00,  $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $41, $42, $43, $44, $45, $46, $47,  $48, $49, $4a, $4b, $4c, $4d, $4e, $4f
    .byte $50, $51, $52, $53, $54, $55, $56, $57,  $58, $59, $5a, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00,  $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00,  $00, $00, $00, $00, $00, $00, $00, $00

zscii_encode_map: ; (characters 33-126)
    ; $80 = set is A2, clear is A0 (A1 not supported/needed for tokenization)
    ; $40 = needs full ZSCII code (A2 char 6 + 2 5bit)
    .byte      $94, $99, $97, $40, $40, $40, $98,  $9e, $9f, $40, $40, $93, $9c, $92, $9a
    .byte $88, $89, $8a, $8b, $8c, $8d, $8e, $8f,  $90, $91, $9d, $40, $40, $40, $40, $95
    .byte $40, $06, $07, $08, $09, $0a, $0b, $0c,  $0d, $0e, $0f, $10, $11, $12, $13, $14
    .byte $15, $16, $17, $18, $19, $1a, $1b, $1c,  $1d, $1e, $1f, $40, $9b, $40, $40, $96
    .byte $40, $06, $07, $08, $09, $0a, $0b, $0c,  $0d, $0e, $0f, $10, $11, $12, $13, $14
    .byte $15, $16, $17, $18, $19, $1a, $1b, $1c,  $1d, $1e, $1f, $40, $40, $40, $40

msg_op_read_char: .byte "Reading @ char", CH::ENTER, 0
msg_op_read: .byte "Reading input", CH::ENTER, 0
msg_op_tokenise: .byte "Tokenize buffer @ into @ using dict @ flag=@", CH::ENTER, 0
