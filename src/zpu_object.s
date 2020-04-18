.include "ziggurat.inc"
.include "zpu.inc"

.code

set_or_clear = $400

.proc op_set_attr
    ; Want to set the attribute
    lda #$ff
    .byte $2c

    ; FALL THRU INTENTIONAL
.endproc

.proc op_clear_attr
    ; Want to clear the attribute
    lda #0
    sta set_or_clear

    bit set_or_clear
    bmi @were_setting
    ldy #<msg_off
    ldx #>msg_off
    bra @show_msg
@were_setting:
    ldy #<msg_on
    ldx #>msg_on
@show_msg:
    sty operand_2
    stx operand_2+1
    lda #<msg_op_setclear_attr
    sta gREG::r6L
    lda #>msg_op_setclear_attr
    sta gREG::r6H
    jsr printf

    ; Find the base address of our object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Now find the attribute in that object
    jsr find_attribute

    ; Are we setting or clearing the bit?
    bit set_or_clear
    bmi @set_value

    ; Clear the bit
    eor #$ff
    and (zpu_mem)
    sta (zpu_mem)
    bra @done

@set_value:
    ; Set the bit
    ora (zpu_mem)
    sta (zpu_mem)

@done:
    ; And go on with the world
    popb
    jmp fetch_and_dispatch
.endproc

.proc op_test_attr
    lda #<msg_op_test_attr
    sta gREG::r6L
    lda #>msg_op_test_attr
    sta gREG::r6H
    jsr printf

    ; Find the base address of our object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Now find the attribute in that object
    jsr find_attribute

    ; Test to see if the bit is set
    and (zpu_mem)
    beq @time_to_branch
    lda #$80

    ; Follow branch with condition that the attribute is set
@time_to_branch:
    tax
    popb
    txa
    jmp follow_branch
.endproc

.proc op_get_parent
    lda #<msg_op_get_parent
    sta gREG::r6L
    lda #>msg_op_get_parent
    sta gREG::r6H
    jsr printf

    ; Find the base address of the destination object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Get the object's parent and store it
    jsr get_parent
    popb
    jsr pc_fetch_and_advance
    clc ; Push to stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch
.endproc

.proc op_get_sibling
    lda #<msg_op_get_sibling
    sta gREG::r6L
    lda #>msg_op_get_sibling
    sta gREG::r6H
    jsr printf

    ; Find the base address of the destination object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Get the object's sibling and store it
    jsr get_sibling
.endproc

.proc store_and_branch_if_exists
    popb
    jsr pc_fetch_and_advance
    clc ; Push to stack if necessary
    jsr store_varvalue

    ; Branch if exists (easiest is to invert and branch if 0)
    txa
    eor #$ff
    sta operand_0
    tya
    eor #$ff
    sta operand_0+1
    jmp do_jz
.endproc

.proc op_get_child
    lda #<msg_op_get_child
    sta gREG::r6L
    lda #>msg_op_get_child
    sta gREG::r6H
    jsr printf

    ; Find the base address of the destination object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Get the object's child and store it
    jsr get_child
    bra store_and_branch_if_exists
.endproc

.proc op_jin
    lda #<msg_op_jin
    sta gREG::r6L
    lda #>msg_op_jin
    sta gREG::r6H
    jsr printf

    ; Find the base address of the destination object
    ldx operand_1
    ldy operand_1+1
    jsr find_object
    pushb zpu_mem+2

    ; Get the destination's current child (so it can be our new child's sibling)
    jsr get_child
    stx operand_2
    sty operand_2+1

    ; And set our object as the new child of the destination
    ldx operand_0
    ldy operand_0+1
    jsr set_child

    ; Get the test object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    lda zpu_mem+2
    sta VIA1::PRA

    ; Get its parent
    jsr get_parent
    popb

    ; And jump if parent equals test object
    stx operand_0
    sty operand_0+1
    jmp op_je
.endproc

.proc op_insert_obj
    lda #<msg_op_insert_obj
    sta gREG::r6L
    lda #>msg_op_insert_obj
    sta gREG::r6H
    jsr printf

    ; Make sure they're passing a real object
    lda operand_0
    tax
    ora operand_0+1
    bne @removeit
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@removeit:
    ; First, remove the object from its current parent
    ldy operand_0+1
    jsr remove_object_from_parent

    ; Make sure the destination object exists
    ldx operand_1
    ldy operand_1+1
    txa
    ora operand_1+1
    beq @no_new_parent

    ; Find the base address of the destination object
    ldx operand_1
    ldy operand_1+1
    jsr find_object
    sta VIA1::PRA

    ; Get the destination's current child (so it can be our new child's sibling)
    jsr get_child
    stx operand_2
    sty operand_2+1

    ; And set our object as the new child of the destination
    ldx operand_0
    ldy operand_0+1
    jsr set_child

@no_new_parent:
    ; Now get our new child object
    jsr find_object
    lda zpu_mem+2
    sta VIA1::PRA

    ; Set the destination as its parent
    ldx operand_1
    ldy operand_1+1
    jsr set_parent

    ; And set the old child as its sibling
    ldx operand_2
    ldy operand_2+1
    jsr set_sibling

    ; And back we go
    jmp fetch_and_dispatch
.endproc

.proc op_remove_obj
    lda #<msg_op_remove_obj
    sta gREG::r6L
    lda #>msg_op_remove_obj
    sta gREG::r6H
    jsr printf

    ; Make sure they're passing a real object
    lda operand_0
    tax
    ora operand_0+1
    bne @removeit
    lda #ERR_INVALID_PARAM
    jmp print_error_and_exit

@removeit:
    ; Remove the object from its current parent
    ldy operand_0+1
    jsr remove_object_from_parent

    ; And back we go
    jmp fetch_and_dispatch
.endproc

.proc remove_object_from_parent
    ; Find the object (objnum in x/y)
    jsr find_object
    sta VIA1::PRA

    ; Get the object's current parent
    jsr get_parent
    stx operand_2
    sty operand_2+1

    ; Get the object's current sibling
    jsr get_sibling
    stx operand_3
    sty operand_3+1

    ; Set the object's parent and sibling to none
    ldx #0
    ldy #0
    jsr set_parent
    jsr set_sibling

    ; Get the old parent object
    lda operand_2
    tax
    ora operand_2+1
    bne @findparent
    rts
@findparent:
    ldy operand_2+1
    jsr find_object
    sta VIA1::PRA

    ; Start with previous child as null
    stz operand_4
    stz operand_4+1

    ; Get its current first child
    jsr get_child

    ; If none, just set the child to the old sibling
    txa
    bne @find_child_in_list
    tya
    bne @find_child_in_list
@set_sibling_as_child_of_parent:
    ldx operand_3
    ldy operand_3+1
    jmp set_child

@find_child_in_list:
    ; See if the child we're on matches the one we want
    cpx operand_0
    bne @no_match
    cpy operand_0+1
    beq @found_child

@no_match:
    ; Step to the next child
    stx operand_4
    sty operand_4+1
    jsr find_object
    sta VIA1::PRA
    jsr get_sibling

    ; If this is the old sibling, we're done
    cpx operand_3
    bne @check_end
    cpy operand_3+1
    bne @check_end
    rts

@check_end:
    ; If we get to the end of the list without finding our child or the old sibling, make sure the
    ; old sibling is at least on the list
    txa
    bne @find_child_in_list
    tya
    bne @find_child_in_list
    ldx operand_3
    ldy operand_3+1
    jmp set_sibling

@found_child:
    ; Okay, we found our child. We need to set the previous sibling's sibling to our old sibling to take
    ; ourselves out of the list. If the previous sibling is null, we should still be on our old parent and
    ; can just set his child.
    lda operand_4
    ora operand_4+1
    beq @set_sibling_as_child_of_parent
    jsr find_object
    ldx operand_3
    ldy operand_3+1
    jmp set_sibling
.endproc

.proc op_print_obj
    lda current_window ; print to current window
    ldx #0 ; print whole string
    jsr do_print_obj
    jmp fetch_and_dispatch
.endproc

.proc do_print_obj
    ; Find the base address of our object
    sta $400 ; Save window to print to
    stx $401 ; Save max length to print
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Now find the property table address in that object and print the encoded string one byte into it
    jsr find_proptable_addr
    jsr mem_fetch_and_advance
    lda $400 ; Get window to print to
    ldx $401 ; Get max length to print
    jsr print_encoded
    popb
    rts
.endproc

.proc op_get_prop
    lda #<msg_op_get_prop
    sta gREG::r6L
    lda #>msg_op_get_prop
    sta gREG::r6H
    jsr printf

    ; Find the base address of our object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Now find the property in that object
    jsr find_property
    bcs @get_prop_value

    ; This object doesn't have that property, so read the default instead
    ldx obj_base
    ldy obj_base+1
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    sta VIA1::PRA
    lda operand_1+1
    asl
    jsr mem_advance
    jsr mem_fetch_and_advance
    tax
    lda (zpu_mem)
    tay
    bra get_prop_store_result

@get_prop_value:
    ; Check the property length to see how many bytes we should get
    ldx #0
    cmp #1
    bcs @check_one_byte
    lda #ERR_INVALID_PROPERTY
    jmp print_error_and_exit
@check_one_byte:
    beq @get_one_byte

    ; The property is at least 2 bytes long, so get the high byte in first
    jsr mem_fetch_and_advance
    tax

@get_one_byte:
    ; Get the low byte into the property
    lda (zpu_mem)
    tay
    bra get_prop_store_result
.endproc

.proc op_get_next_prop
    lda #<msg_op_get_next_prop
    sta gREG::r6L
    lda #>msg_op_get_next_prop
    sta gREG::r6H
    jsr printf

    ; Find the base address of our object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Now find the property list for that object
    jsr find_property_list

    ; If they're looking for prop #0, that means just get the first property
    lda operand_1+1
    beq reverse_zpu_mem

@scan_properties:
    ; Step through the list until we find a matching property
    jsr get_property_number
    cmp operand_1+1
    bcc prop_not_found
    beq @found
    jsr find_next_property
    bra @scan_properties

@found:
    ; Step to the next property
    jsr find_next_property

    ; FALL THRU INTENTIONAL
.endproc

reverse_zpu_mem:
    ; Reverse the current contents of zpu_mem into a byte address in x/y
    ldy zpu_mem
    ldx zpu_mem+1
    lda zpu_mem+2
    jsr encode_baddr

    ; FALL THRU INTENTIONAL

get_prop_store_result:
    ; Store the result and keep on truckin'
    popb
    jsr pc_fetch_and_advance

    sta operand_0
    stx operand_1
    sty operand_1+1
    lda #<msg_op_storing_result
    sta gREG::r6L
    lda #>msg_op_storing_result
    sta gREG::r6H
    jsr printf
    lda operand_0
    clc ; Push to stack if necessary
    jsr store_varvalue
    jmp fetch_and_dispatch

prop_not_found:
    lda #ERR_INVALID_PROPERTY
    jmp print_error_and_exit

.proc op_get_prop_len
    lda #<msg_op_get_prop_len
    sta gREG::r6L
    lda #>msg_op_get_prop_len
    sta gREG::r6H
    jsr printf

    ; Find the base address of our object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Now find the property in that object
    jsr find_property
    bcs @return_length
    lda #ERR_INVALID_PROPERTY
    jmp print_error_and_exit

@return_length:
    tay
    ldx #0
    bra get_prop_store_result
.endproc

.proc op_get_prop_addr
    lda #<msg_op_get_prop_addr
    sta gREG::r6L
    lda #>msg_op_get_prop_addr
    sta gREG::r6H
    jsr printf

    ; Find the base address of our object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Get the property list address
    jsr find_property_list

@scanprop:
    ; Get the property number and see if it matches (Note: Properties are required to be listed in descending order, so
    ; once we hit a property that is less than the one we're looking for, we can bottom out the search)
    jsr get_property_number
    cmp operand_1+1
    beq reverse_zpu_mem
    bcc @not_found
    jsr find_next_property
    bra @scanprop

    ; Return 0 if property not found
@not_found:
    ldx #0
    ldy #0
    jmp get_prop_store_result
.endproc

.proc op_put_prop
    lda #<msg_op_put_prop
    sta gREG::r6L
    lda #>msg_op_put_prop
    sta gREG::r6H
    jsr printf

    ; Find the base address of our object
    ldx operand_0
    ldy operand_0+1
    jsr find_object
    pushb zpu_mem+2

    ; Now find the property in that object
    jsr find_property
    bcs @set_prop_value
@invalid_property:
    lda #ERR_INVALID_PROPERTY
    jmp print_error_and_exit

@set_prop_value:
    ; Check the property length to see how many bytes we should set
    cmp #1
    bcc @invalid_property
    beq @set_one_byte

    ; The property is at least 2 bytes long, so set the high byte in first
    lda operand_2
    jsr mem_store_and_advance

@set_one_byte:
    ; Set the low byte into the property
    lda operand_2+1
    sta (zpu_mem)

    ; Switch back to the original bank and go on running stuff
    popb
    jmp fetch_and_dispatch
.endproc

; find_object - Load the physical address of the requested object into zpu_mem
; In:   x/y         - object number (non-zero)
; Out:  zpu_mem     - physical address of object in memory
.proc find_object
    ; Decrement the object number by 1
    cpy #0
    bne @just_low
    dex
@just_low:
    dey

    ; In versions 1-3, the object table entries are 9 bytes in size, so we multiply the object number by 9.
    ; Fast way to do this is to multiply by 8 (shift left 3) and add original
    chkver V1|V2|V3,@multiply_by_14
    stx gREG::r11
    sty gREG::r11+1
    asl gREG::r11+1
    rol gREG::r11
    asl gREG::r11+1
    rol gREG::r11
    asl gREG::r11+1
    rol gREG::r11
    clc
    tya
    adc gREG::r11+1
    sta gREG::r11+1
    txa
    adc gREG::r11
    sta gREG::r11
    bra @decodeit

@multiply_by_14:
    ; In versions 4+, the object table entries are 14 bytes in size, so we multiply the object number by 14
    ; Fast way to do this is (n*16)-(n*2)
    tya
    asl
    sta gREG::r11+1
    sta gREG::r12+1
    txa
    rol
    sta gREG::r11
    sta gREG::r12
    asl gREG::r11+1
    rol gREG::r11
    asl gREG::r11+1
    rol gREG::r11
    asl gREG::r11+1
    rol gREG::r11
    lda gREG::r11+1
    sec
    sbc gREG::r12+1
    sta gREG::r11+1
    lda gREG::r11
    sbc gREG::r12
    sta gREG::r11

@decodeit:
    ; Use the offset into the object table
    clc
    lda gREG::r11+1
    adc objtbl_base+1
    tay
    lda gREG::r11
    adc objtbl_base
    tax

    ; Decode the address into zpu_mem
    jsr decode_baddr
    sty zpu_mem
    stx zpu_mem+1
    sta zpu_mem+2
    rts
.endproc

; find_attribute - Load physical address of the requested attribute into zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
;       operand_1       - attribute to locate
; Out:  zpu_mem         - physical address of byte containing requested attribute (bank already set)
;       a               - mask with correct attribute bit set
.proc find_attribute
    ; Attribute is in a bitmap starting at the beginning of our object. Attributes are zero-based, and run from high to low
    ; bits in the bitmap. So attribute 0 is bit 7 of byte 0 of the bitmap, attribute 12 is bit 3 of byte 1 of the bitmap, etc.
    phx
    lda operand_1+1
    tax
    lsr
    lsr
    lsr
    jsr mem_advance
    txa
    and #07
    tax
    lda numtobit,x
    plx
    rts
.endproc

; 

; get_parent - Get the parent of the object in zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
; Out:  x/y             - parent object number (x=hi,y=lo)
.proc get_parent
    chkver V1|V2|V3,@get_v4

    ; Read 1 byte at offset 4
    lda #4
    jmp read_array_byte

@get_v4:
    ; Read 2 bytes at offset 6
    lda #3
    jmp read_array_word
.endproc

; get_sibling - Get the sibling of the object in zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
; Out:  x/y             - sibling object number (x=hi,y=lo)
.proc get_sibling
    chkver V1|V2|V3,@get_v4

    ; Read 1 byte at offset 5
    lda #5
    jmp read_array_byte

@get_v4:
    ; Read 2 bytes at offset 8
    lda #4
    jmp read_array_word
.endproc

; get_child - Get the child of the object in zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
; Out:  x/y             - child object number (x=hi,y=lo)
.proc get_child
    chkver V1|V2|V3,@get_v4

    ; Read 1 byte at offset 6
    lda #6
    jmp read_array_byte

@get_v4:
    ; Read 2 bytes at offset 10
    lda #5
    jmp read_array_word
.endproc

; set_parent - Set the parent of the object in zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
;       x/y             - parent object number (x=hi,y=lo)
.proc set_parent
    chkver V1|V2|V3,@set_v4

    ; Write 1 byte at offset 4
    lda #4
    jmp write_array_byte

@set_v4:
    ; Write 2 bytes at offset 6
    lda #3
    jmp write_array_word
.endproc

; set_sibling - Set the sibling of the object in zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
;       x/y             - sibling object number (x=hi,y=lo)
.proc set_sibling
    chkver V1|V2|V3,@set_v4

    ; Write 1 byte at offset 5
    lda #5
    jmp write_array_byte

@set_v4:
    ; Write 2 bytes at offset 8
    lda #4
    jmp write_array_word
.endproc

; set_child - Set the child of the object in zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
;       x/y             - child object number (x=hi,y=lo)
.proc set_child
    chkver V1|V2|V3,@set_v4

    ; Write 1 byte at offset 6
    lda #6
    jmp write_array_byte

@set_v4:
    ; Write 2 bytes at offset 10
    lda #5
    jmp write_array_word
.endproc

; find_proptable_addr - Load the physical address of an object's property table into zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
; Out:  zpu_mem         - physical address of property table in memory (bank already set)
.proc find_proptable_addr
    ; Get the property table address
    lda objentry_offset_propaddr
    jsr mem_advance
    jsr mem_fetch_and_advance
    tax
    lda (zpu_mem)
    tay
    jsr decode_baddr
    sta VIA1::PRA
    sta zpu_mem+2
    stx zpu_mem+1
    sty zpu_mem
.endproc

nearby_rts:
    rts

; find_property_list - Load the physical address of the first property into zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
; Out:  zpu_mem         - physical address of property list in memory (bank already set)
.proc find_property_list
    ; Get the property table address
    jsr find_proptable_addr

    ; Skip the property header
    jsr mem_fetch_and_advance
    beq nearby_rts ; No name to skip
    tax
    bit #$80
    beq @onebyteoffset
    jsr mem_advance_block
@onebyteoffset:
    txa
    asl
    jmp mem_advance
.endproc

; get_property_number - Parse the current property number
; In:   zpu_mem         - physical address of property table entry in memory (bank already set)
; Out:  a               - property number
.proc get_property_number
    ; Figure out which version property list we have
    chkver V1|V2|V3,@parseprop_v4

    ; For v1-3, property number is in the low 5 bits (put in y), length is in the high 3 bits plus 1 (put in a)
    lda (zpu_mem)
    and #$1f
    rts

@parseprop_v4:
    ; Property number is in the low 6 bits
    lda (zpu_mem)
    and #$3f
    rts
.endproc

; get_property_length - Parse the current property length
; In:   zpu_mem         - physical address of property table entry in memory (bank already set)
; Out:  a               - property length
.proc get_property_length
    ; Figure out which version property list we have
    chkver V1|V2|V3,@parseprop_v4

    ; For v1-3, length is in the high 3 bits plus 1
    lda (zpu_mem)
    lsr
    lsr
    lsr
    lsr
    lsr
    inc
    rts

@parseprop_v4:
    ; If high bit is clear, size is bit 6 plus 1. If high bit is set, size is
    ; low 6 bits of second byte. If low 6 bits of second byte are 0, size is 64.
    jsr mem_fetch_and_advance
    sta gREG::r6L
    bit gREG::r6L
    bmi @handle_twobyte

    ; Length is 1 if bit 6 clear, 2 if bit 6 set
    ldy #1
    bvc @backupafter
    iny
@backupafter:
    lda #1
    jsr mem_retreat
    tya
    rts

@handle_twobyte:
    ; Read the next byte to get the length
    lda (zpu_mem)
    and #$3f
    tay
    bne @backupafter
    ldy #64
    bra @backupafter
.endproc

; get_property_value - Parse the property value
; In:   zpu_mem         - physical address of property table entry in memory (bank already set)
; Out:  x/y             - property value (x=hi, y=lo)
.proc get_property_value
proplenlen = gREG::r7L

    ; Get the property length and the length length
    jsr get_property_length
    tax
    jsr get_prop_len_len
    sta proplenlen

    ; Advance by property length length
    jsr mem_advance

    ; Check if it's more than one byte long
    txa
    and #$fe
    bne @handle_twobyte

    ; Read one byte into y and back up
    lda (zpu_mem)
    tay
    ldx #0
    lda proplenlen
    jmp mem_retreat

@handle_twobyte:
    ; Read two bytes into x/y
    jsr mem_fetch_and_advance
    tax
    lda (zpu_mem)
    tay

    ; Back up length length + 1
    lda proplenlen
    inc
    jmp mem_retreat
.endproc

; get_prop_len_len - Get the length of the current property's length
; In:   zpu_mem         - physical address of property table entry in memory (bank already set)
; Out:  a               - length of current property length field
.proc get_prop_len_len
    ; Which version property table do we have?
    chkver V1|V2|V3,@check_v4
    lda #1
    rts

@check_v4:
    ; If high bit is clear, length is 1 byte; if set, it is 2 bytes. We can move that high bit into the low
    ; bit and then add 1 to get the length we need.
    lda (zpu_mem)
    and #$80
    asl
    rol
    inc
    rts
.endproc

; find_next_property - Load the physical address of the next property into zpu_mem
; In:   zpu_mem         - physical address of property table entry in memory (bank already set)
; Out:  zpu_mem         - physical address of next property table entry (bank already set)
.proc find_next_property
    ; Get the current property length
    jsr get_property_length
    sta gREG::r6

    ; And get the current property length length
    jsr get_prop_len_len

    ; Add them and advance by that much
    clc
    adc gREG::r6
    jmp mem_advance
.endproc

; find_property - Load the physical address of the requested property into zpu_mem
; In:   zpu_mem         - physical address of object in memory (bank already set)
;       operand_1       - property number (non-zero)
; Out:  zpu_mem         - physical address of property value in memory (bank already set)
;       a               - property length
;       carry           - set if property found
.proc find_property
    ; Get the property list address
    jsr find_property_list

@scanprop:
    ; Get the property number and see if it matches (Note: Properties are required to be listed in descending order, so
    ; once we hit a property that is less than the one we're looking for, we can bottom out the search)
    jsr get_property_number
    cmp operand_1+1
    beq @found
    bcc @not_found
    jsr find_next_property
    bra @scanprop

@not_found:
    ; Didn't find the property
    clc
    rts

@found:
    ; Found it, so get length, advance address by length length, and set carry to say we found it
    jsr get_property_length
    tax
    jsr get_prop_len_len
    jsr mem_advance
    txa
    sec
    rts
.endproc

.rodata

msg_op_test_attr: .byte "Testing object @ attr @", CH::ENTER, 0
msg_op_setclear_attr: .byte "Setting object @ attr @ to $", CH::ENTER, 0
msg_off: .byte "off", 0
msg_on: .byte "on", 0
msg_op_jin: .byte "Jumping if object @ in object @", CH::ENTER, 0
msg_op_insert_obj: .byte "Insert object @ into object @", CH::ENTER, 0
msg_op_remove_obj: .byte "Remove object @ from parent", CH::ENTER, 0
msg_op_get_prop: .byte "Get object @ prop @", CH::ENTER, 0
msg_op_get_next_prop: .byte "Get next prop for object @ prop @", CH::ENTER, 0
msg_op_get_prop_len: .byte "Get length of object @ prop @", CH::ENTER, 0
msg_op_get_prop_addr: .byte "Get address of object @ prop @", CH::ENTER, 0
msg_op_put_prop: .byte "Put object @ prop @ value=@", CH::ENTER, 0
msg_op_get_parent: .byte "Getting object @'s parent", CH::ENTER, 0
msg_op_get_sibling: .byte "Getting object @'s sibling", CH::ENTER, 0
msg_op_get_child: .byte "Getting object @'s child", CH::ENTER, 0
msg_op_storing_result: .byte "Storing result in var # value=@", CH::ENTER, 0
