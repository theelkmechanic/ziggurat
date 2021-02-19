; Ziggurat ZIF file manager functions

.include "ziggurat.inc"

.export load_file_to_hiram

.import print_error_and_exit

.code

;
; load_file_to_hiram - Load a file into high memory pages (starting with bank 1)
;
; In:   r0          Pointer to filename
;       a           Filename length
;       x           Device #
;

.proc load_file_to_hiram

    ; Set up write buffer ($A000 in bank 1)
@write = gREG::r11
@writeh = gREG::r11H
    ldy #$a0
    sty @writeh
    ldy #0
    sty @write
    iny
    sty BANK_RAM

    ; Set filename and load parameters
    ldx gREG::r0L
    ldy gREG::r0H
    jsr SETNAM
    lda #1
    ldx #8
    ldy #$60
    jsr SETLFS

    ; Open the file and set it for input
    jsr OPEN
    bcs :+
    ldx #1
    jsr CHKIN
    bcc @loadit
@loaddone:
    lda #1
    sta BANK_RAM
    jsr CLRCHN
:   lda #1
    jmp CLOSE

    ; Load the file into memory
@loadit:
    ldy #0
@loadloop:
    jsr CHRIN
    pha
    jsr READST
    tax
    pla
    cpx #0
    bne @loaddone
    sta (@write),y
    iny
    bne @loadloop

    ; Every block we finish, step to the next block, and if we reach the end of the high ram window,
    ; skip to the next bank and reset
    ldx @writeh
    inx
    cpx #$c0
    bcc :+
    ldx BANK_RAM
    inx
    stx BANK_RAM
    ldx #$a0
:   stx @writeh
    bra @loadloop
.endproc