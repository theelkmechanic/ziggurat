.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"
.include "zscii_type.inc"

.code

readln_buffer   = $600
readln_maxlen   = $700
readln_curlen   = $701
readln_idx      = $702
readln_orig_x   = $703
readln_orig_y   = $704

; win_readln - Read in a line of text entered via the keyboard
; In:   a           - Window ID (0-MAX_WINDOWS-1)
;       x           - Max length to read
; Out:  a           - Length read
;       x/y         - Read buffer address (x=hi, y=lo)
.proc win_readln
    ; Get the window table entry pointer
    jsr win_getptr

    ; Flush anything in the buffer
    jsr curwin_flushbuffer

    ; Read valid input keys
@1: jsr GETIN
    tax
    lda x16key_to_zscii,x
    beq @1
    jsr z_isinput
    bcc @1

    ; Check for terminating character
    cmp #13
    beq @finished

    ; If the character is valid for output, print it
    jsr z_isoutput
    bcc @1
    ldx #0
    tay
    sec
    jsr curwin_putchr_nobuffer
    bra @1
   
@finished:
    rts
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
