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
    pha
    ; Use LFN 2 to avoid conflicts with UniLib font loading (which may use LFN 1)
    lda #2
    jsr CLOSE
    pla
    pha
    lda #2
    ldx #8
    ldy #2 ; headerless load
    jsr SETLFS
    pla
    ldx gREG::r0L
    ldy gREG::r0H
    jsr SETNAM
    pushb #ZIF_BASE_BANK ; start at base bank (above UniLib)
    lda #0 ; specify address $A000
    ldx #0
    ldy #$A0
    jsr LOAD
    popb ; restore bank
    rts
.endproc