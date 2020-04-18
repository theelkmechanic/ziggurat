; Ziggurat ZIF file manager functions

.include "ziggurat.inc"

.export load_zif

.import printhex
.import print_error_and_exit

.code

;
; loadzif - Load a ZIF file into high memory pages
;
; In: r0 Pointer to filename
; a Filename length
; x Device #
; Out: a Length of ZIF data loaded in 8K banks (0=failure)
;

.proc load_zif
    ; Setup file load channel
    pha
    lda #1
    ldy #1
    jsr SETLFS

    ; Set filename
    pla
    ldx gREG::r0L
    ldy gREG::r0H
    jsr SETNAM

    ; Open the file for input
    jsr OPEN
    ldx #1
    jsr CHKIN
    jsr READST
    cmp #0
    beq opened
    sta gREG::r12L
    lda #ERR_CANT_OPEN_FILE
    jmp print_error_and_exit

opened:
    ; Set up high memory copy locations. We start loading in bank 1.
baseaddr = gREG::r11
bank  = gREG::r12L
saved_bank = gREG::r12H
block_len = gREG::r13L
is_done  = gREG::r13H
block_chk = gREG::r14L
    ; r11 = base address in high memory bank slot
    ; r12L = RAM bank
    ; r12H = saved RAM bank
    ; r13L = block length (0 = 256 bytes)
    ; r13H = non-zero is done
    ; r14L = block checksum
    ldx #0
    ldy #$a0
    stx baseaddr
    sty baseaddr+1
    stx is_done
    inx
    stx bank

    ; Loop reading 256-byte blocks into temp_buffer
blkread:
    ldy #0
    sty block_chk
readloop:
    jsr CHRIN
    tax
    jsr READST
    cmp #0
    bne partial
    txa
    sta temp_buffer,y
    clc
    adc block_chk
    sta block_chk
    iny
    bne readloop

    ; Copy y bytes to next high memory block (0 = 256 bytes)

    ; Start by saving the length to copy
copytohigh:
    sty block_len

    ; Save and switch RAM bank
    lda VIA1::PRA
    sta saved_bank
    lda bank
    sta VIA1::PRA

    ; Copy the data (descending)
copyblock:
    dey
    lda temp_buffer,y
    sta (baseaddr),y
    cpy #0
    bne copyblock

    ; Stop after the last block
    cpy block_len
    bne done

    ; Step to next block, and once we hit $c000, skip back
    ; to $a000 and increment the bank
    ldx baseaddr+1
    inx
    cpx #$c0
    bne nextblock
    ldx #$a0
    inc bank
    lda #'.'
    jsr CHROUT
nextblock:
    stx baseaddr+1

    ; Switch the bank back
    lda saved_bank
    sta VIA1::PRA

    ; And read the next block
    jmp blkread

    ; Partial block, if it's 0 bytes, we're done,
    ; otherwise go back up and copy the partial
partial:
    lda #1
    sta block_len
    cpy #0
    bne copytohigh

    ; Close the file
done:
    jsr CLRCHN
    lda #1
    jsr CLOSE
    lda #CH::ENTER
    jsr CHROUT
    rts
.endproc
