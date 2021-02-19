.include "ziggurat.inc"
.include "zpu.inc"
.include "zscii_type.inc"

ZTYPE_INPUT     = $80
ZTYPE_OUTPUT    = $40

.code

; z_isinput - Check if a ZSCII character is valid for input
; In:   a           - ZSCII character
; Out:  carry       - Carry flag set if character is valid for input
.proc z_isinput
    phx
    pha
    tax
    lda zscii_ctype_map,x
    bra return_bit7
.endproc

; z_isoutput - Check if a ZSCII character is valid for output
; In:   a           - ZSCII character
; Out:  carry       - Carry flag set if character is valid for output
.proc z_isoutput
    phx
    pha
    tax
    lda zscii_ctype_map,x
    bra return_bit6
.endproc

; z_iswhitespace - Check if a ZSCII character is whitespace
; In:   a           - ZSCII character
; Out:  carry       - Carry flag set if character is whitespace
.proc z_iswhitespace
    phx
    pha
    tax
    lda zscii_ctype_map,x
    bra return_bit6
.endproc

; z_canbreakafter - Check if we can break a line following a ZSCII character
; In:   a           - ZSCII character
; Out:  carry       - Carry flag set if valid to break a line following character
.proc z_canbreakafter
    phx
    pha
    tax
    lda zscii_ctype_map,x
    asl
.endproc

return_bit5: asl
return_bit6: asl
return_bit7: asl
    pla
    plx
    rts

; z_tolower - Convert a ZSCII character to lowercase
; In:   a           - ZSCII character
; Out:  a           - Lowercase equivalent
.proc z_tolower
    phx
    tax
    lda zscii_lower_map,x
    plx
    rts
.endproc

.rodata

zscii_ctype_map:
    .byte   $40, $00, $00, $00, $00, $00, $00, $00,  $80, $40, $00, $40, $00, $c0, $00, $00
    .byte   $00, $00, $00, $00, $00, $00, $00, $00,  $00, $00, $80, $00, $00, $00, $00, $00
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $00

    .byte   $00, $80, $80, $80, $80, $80, $80, $80,  $80, $80, $80, $80, $80, $80, $80, $80
    .byte   $80, $80, $80, $80, $80, $80, $80, $80,  $80, $80, $80, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0
    .byte   $c0, $c0, $c0, $c0, $c0, $c0, $c0, $c0,  $c0, $c0, $c0, $c0, $80, $80, $80, $00

zscii_lower_map:
    .byte   $00, $01, $02, $03, $04, $05, $06, $07,  $08, $09, $0a, $0b, $0c, $0d, $0e, $0f
    .byte   $10, $11, $12, $13, $14, $15, $16, $17,  $18, $19, $1a, $1b, $1c, $1d, $1e, $1f
    .byte   $20, $21, $22, $23, $24, $25, $26, $27,  $28, $29, $2a, $2b, $2c, $2d, $2e, $2f
    .byte   $30, $31, $32, $33, $34, $35, $36, $37,  $38, $39, $3a, $3b, $3c, $3d, $3e, $3f
    .byte   $40, $61, $62, $63, $64, $65, $66, $67,  $68, $69, $6a, $6b, $6c, $6d, $6e, $6f
    .byte   $70, $71, $72, $73, $74, $75, $76, $77,  $78, $79, $7a, $5b, $5c, $5d, $5e, $5f
    .byte   $60, $61, $62, $63, $64, $65, $66, $67,  $68, $69, $6a, $6b, $6c, $6d, $6e, $6f
    .byte   $70, $71, $72, $73, $74, $75, $76, $77,  $78, $79, $7a, $7b, $7c, $7d, $7e, $7f

    .byte   $80, $81, $82, $83, $84, $85, $86, $87,  $88, $89, $8a, $8b, $8c, $8d, $8e, $8f
    .byte   $90, $91, $92, $93, $94, $95, $96, $97,  $98, $99, $9a, $9b, $9c, $9d, $9b, $9c
    .byte   $9d, $a1, $a2, $a3, $a4, $a5, $a6, $a4,  $a5, $a9, $aa, $ab, $ac, $ad, $ae, $a9
    .byte   $aa, $ab, $ac, $ad, $ae, $b5, $b6, $b7,  $b8, $b9, $b5, $b6, $b7, $b8, $b9, $bf
    .byte   $c0, $c1, $c2, $c3, $bf, $c0, $c1, $c2,  $c3, $c9, $c9, $cb, $cb, $cd, $ce, $cf
    .byte   $cd, $ce, $cf, $d3, $d3, $d5, $d5, $d7,  $d8, $d7, $d8, $db, $dc, $dc, $de, $df
    .byte   $e0, $e1, $e2, $e3, $e4, $e5, $e6, $e7,  $e8, $e9, $ea, $eb, $ec, $ed, $ee, $ef
    .byte   $f0, $f1, $f2, $f3, $f4, $f5, $f6, $f7,  $f8, $f9, $fa, $fb, $fc, $fd, $fe, $ff
