.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.data

utf16: .res 2
utf_xlat_addr: .res 3

map_base = gREG::r9
map_entry = gREG::r10

.code

; utf_find_charinfo - Find the character info table entry for the specified UTF-16 character
; In:   x/y         - UTF-16 character (x=hi, y=lo)
; Out:  a           - character flags
;       x           - base character glyph
;       y           - overlay character glyph
;       carry       - set if character info was found
.proc utf_find_charinfo
    ; Save the character
    sty utf16
    stx utf16+1

    ; Start with the Basic Latin map
    lda #<utf_basic_latin
    sta map_base
    lda #>utf_basic_latin
    sta map_base+1

@scan_maps:
    ; Check that starting char <= our char
    ldy #1
    lda (map_base),y
    tay
    lda (map_base)
    cpy utf16+1
    bne @1
    cmp utf16

    ; If we hit a block that's greater than our character, we're done, because our maps are in
    ; ascending order
@1: bcc @in_range_low
    beq @in_range_low

@not_found:
    clc
    rts

@in_range_low:
    ; Check that starting char + size > our char
    ldy #2
    lda (map_base)
    clc
    adc (map_base),y
    tax
    dey
    lda (map_base),y
    ldy #3
    adc (map_base),y
    tay
    cpy utf16+1
    bne @2
    cpx utf16

    ; If we're past the end, skip to the next map
@2: bcc @next_map
    beq @next_map

    ; We found the right map. The font entry address is at:
    ;   map_base + (our char - starting char) * 3 + 6
    ; which is the same as:
    ;   map_base + (our char - starting char + 2) * 2 + (our char - starting char + 2).

    ; Subtract our char - starting char
    ldy #0
    lda utf16
    sec
    sbc (map_base),y
    sta map_entry
    iny
    lda utf16+1
    sbc (map_base),y
    sta map_entry+1

    ; Add 2 and save twice
    lda map_entry
    clc
    adc #2
    sta map_entry
    sta utf16
    lda map_entry+1
    adc #0
    sta map_entry+1
    sta utf16+1

    ; Multiply one of them by 2
    asl map_entry
    rol map_entry+1

    ; And add them
    lda map_entry
    clc
    adc utf16
    sta map_entry
    lda map_entry+1
    adc utf16+1
    sta map_entry+1

    ; And finally add the fontmap base
    lda map_entry
    clc
    adc map_base
    sta map_entry
    lda map_entry+1
    adc map_base+1
    sta map_entry+1

    ; Read the character info
    ldy #1
    lda (map_entry)
    pha
    lda (map_entry),y
    pha
    iny
    lda (map_entry),y
    ply
    plx

    ; And we're done--is it a valid glyph?
    bit #$40
    bne @not_found_2
    sec
    rts

    ; Jump to the next map
@next_map:
    ldy #5
    lda (map_base),y
    tax
    dey
    lda (map_base),y
    sta map_base
    stx map_base+1
    ora map_base+1
    beq @not_found_2
    jmp @scan_maps
@not_found_2:
    clc
    rts
.endproc

.rodata

utf_xlat_default:
    .byte 69    ; Number of Unicode characters in the table (2 bytes each, big-endian)
    .dbyt $00e4
    .dbyt $00f6
    .dbyt $00fc
    .dbyt $00c4
    .dbyt $00d6
    .dbyt $00dc
    .dbyt $00df
    .dbyt $00bb
    .dbyt $00ab
    .dbyt $00eb
    .dbyt $00ef
    .dbyt $00ff
    .dbyt $00cb
    .dbyt $00cf
    .dbyt $00e1
    .dbyt $00e9
    .dbyt $00ed
    .dbyt $00f3
    .dbyt $00fa
    .dbyt $00fd
    .dbyt $00c1
    .dbyt $00c9
    .dbyt $00cd
    .dbyt $00d3
    .dbyt $00da
    .dbyt $00dd
    .dbyt $00e0
    .dbyt $00e8
    .dbyt $00ec
    .dbyt $00f2
    .dbyt $00f9
    .dbyt $00c0
    .dbyt $00c8
    .dbyt $00cc
    .dbyt $00d2
    .dbyt $00d9
    .dbyt $00e2
    .dbyt $00ea
    .dbyt $00ee
    .dbyt $00f4
    .dbyt $00fb
    .dbyt $00c2
    .dbyt $00ca
    .dbyt $00ce
    .dbyt $00d4
    .dbyt $00db
    .dbyt $00e5
    .dbyt $00c5
    .dbyt $00f8
    .dbyt $00d8
    .dbyt $00e3
    .dbyt $00f1
    .dbyt $00f5
    .dbyt $00c3
    .dbyt $00d1
    .dbyt $00d5
    .dbyt $00e6
    .dbyt $00c6
    .dbyt $00e7
    .dbyt $00c7
    .dbyt $00fe
    .dbyt $00f0
    .dbyt $00de
    .dbyt $00d0
    .dbyt $00a3
    .dbyt $0153
    .dbyt $0152
    .dbyt $00a1
    .dbyt $00bf

; Our UTF fontmaps start with three words:
;   * Starting UTF-16 character in the map
;   * Number of entries in the map
;   * Address of the next map (0 if last map)
;
; These are followed by entries of 3 bytes each:
;   * Glyph index from base (layer 0) font
;   * Glyph index from overlay (layer 1) font
;   * Flags byte:
;       - $80 = reverse character colors
;       - $40 = no glyph (do not print)
;       - $08 = flip overlay vertical
;       - $04 = flip overlay horizontal
;       - $03 = overlay index bits 9:8

utf_basic_latin:
    .word 32, 95, utf_latin_1_supplement
    .byte $20, $00, $00
    .byte $21, $00, $00
    .byte $22, $00, $00
    .byte $23, $00, $00
    .byte $24, $00, $00
    .byte $25, $00, $00
    .byte $26, $00, $00
    .byte $27, $00, $00
    .byte $20, $8e, $01
    .byte $20, $8e, $05
    .byte $2a, $00, $00
    .byte $2b, $00, $00
    .byte $20, $86, $0d
    .byte $2d, $00, $00
    .byte $2e, $00, $00
    .byte $2f, $00, $00
    .byte $4f, $ef, $00
    .byte $31, $00, $00
    .byte $32, $00, $00
    .byte $33, $00, $00
    .byte $34, $00, $00
    .byte $35, $00, $00
    .byte $36, $00, $00
    .byte $37, $00, $00
    .byte $38, $00, $00
    .byte $39, $00, $00
    .byte $3a, $00, $00
    .byte $3a, $86, $0d
    .byte $20, $92, $01
    .byte $3d, $00, $00
    .byte $20, $92, $05
    .byte $3f, $00, $00
    .byte $00, $00, $00
    .byte $41, $00, $00
    .byte $42, $00, $00
    .byte $43, $00, $00
    .byte $44, $00, $00
    .byte $45, $00, $00
    .byte $46, $00, $00
    .byte $47, $00, $00
    .byte $48, $00, $00
    .byte $49, $00, $00
    .byte $4a, $00, $00
    .byte $4b, $00, $00
    .byte $4c, $00, $00
    .byte $4d, $00, $00
    .byte $4e, $00, $00
    .byte $4f, $00, $00
    .byte $50, $00, $00
    .byte $51, $00, $00
    .byte $52, $00, $00
    .byte $53, $00, $00
    .byte $54, $00, $00
    .byte $55, $00, $00
    .byte $56, $00, $00
    .byte $57, $00, $00
    .byte $58, $00, $00
    .byte $59, $00, $00
    .byte $5a, $00, $00
    .byte $20, $8f, $01
    .byte $5c, $00, $00
    .byte $20, $8f, $05
    .byte $5e, $00, $00
    .byte $5f, $00, $00
    .byte $20, $d3, $00
    .byte $01, $00, $00
    .byte $02, $00, $00
    .byte $03, $00, $00
    .byte $04, $00, $00
    .byte $05, $00, $00
    .byte $06, $00, $00
    .byte $07, $00, $00
    .byte $08, $00, $00
    .byte $09, $e6, $00
    .byte $0a, $f3, $00
    .byte $0b, $00, $00
    .byte $0c, $00, $00
    .byte $0d, $00, $00
    .byte $0e, $00, $00
    .byte $0f, $00, $00
    .byte $10, $00, $00
    .byte $11, $00, $00
    .byte $12, $00, $00
    .byte $13, $00, $00
    .byte $14, $00, $00
    .byte $15, $00, $00
    .byte $16, $00, $00
    .byte $17, $00, $00
    .byte $18, $00, $00
    .byte $19, $00, $00
    .byte $1a, $00, $00
    .byte $20, $91, $01
    .byte $7c, $00, $00
    .byte $20, $91, $05
    .byte $20, $e3, $00

utf_latin_1_supplement:
    .word 160, 96, utf_latin_extended_a
    .byte $20, $00, $00
    .byte $20, $80, $01
    .byte $20, $00, $02
    .byte $1c, $00, $00
    .byte $20, $02, $02
    .byte $20, $03, $02
    .byte $20, $39, $00
    .byte $20, $e1, $01
    .byte $20, $c4, $00
    .byte $20, $00, $03
    .byte $2d, $ce, $02
    .byte $20, $94, $01
    .byte $20, $b3, $01
    .byte $20, $00, $00
    .byte $20, $01, $03
    .byte $20, $c9, $00

    .byte $20, $e5, $00
    .byte $20, $40, $02
    .byte $20, $c2, $02
    .byte $20, $c3, $02
    .byte $20, $c0, $04
    .byte $6d, $00, $00
    .byte $20, $a2, $01
    .byte $20, $44, $02
    .byte $20, $c7, $00
    .byte $20, $c1, $02
    .byte $2d, $d0, $02
    .byte $20, $94, $05
    .byte $20, $b5, $01
    .byte $20, $b6, $01
    .byte $20, $b7, $01
    .byte $20, $81, $01

    .byte $41, $c0, $00
    .byte $41, $c0, $04
    .byte $41, $c2, $00
    .byte $41, $c3, $00
    .byte $41, $c4, $00
    .byte $41, $c5, $00
    .byte $c6, $00, $00
    .byte $43, $c7, $00
    .byte $45, $c0, $00
    .byte $45, $c0, $04
    .byte $45, $c2, $00
    .byte $45, $c4, $00
    .byte $49, $c0, $00
    .byte $49, $c0, $04
    .byte $49, $c2, $00
    .byte $49, $c4, $00
    .byte $44, $d2, $00
    .byte $4e, $c3, $00
    .byte $4f, $c0, $00
    .byte $4f, $c0, $04
    .byte $4f, $c2, $00
    .byte $4f, $c3, $00
    .byte $4f, $c4, $00
    .byte $20, $41, $02
    .byte $4f, $d8, $00
    .byte $55, $c0, $00
    .byte $55, $c0, $04
    .byte $55, $c2, $00
    .byte $55, $c4, $00
    .byte $59, $c0, $04
    .byte $de, $00, $00
    .byte $df, $00, $00
    .byte $01, $e0, $00
    .byte $01, $e0, $04
    .byte $01, $e2, $00
    .byte $01, $e3, $00
    .byte $01, $e4, $00
    .byte $01, $e5, $00
    .byte $e6, $00, $00
    .byte $03, $c7, $00
    .byte $05, $e0, $00
    .byte $05, $e0, $04
    .byte $05, $e2, $00
    .byte $05, $e4, $00
    .byte $09, $e0, $00
    .byte $09, $e0, $04
    .byte $09, $e2, $00
    .byte $09, $e4, $00
    .byte $d0, $00, $00
    .byte $0e, $e3, $00
    .byte $0f, $e0, $00
    .byte $0f, $e0, $04
    .byte $0f, $e2, $00
    .byte $0f, $e3, $00
    .byte $0f, $e4, $00
    .byte $20, $42, $02
    .byte $0f, $f8, $00
    .byte $15, $e0, $00
    .byte $15, $e0, $04
    .byte $15, $e2, $00
    .byte $15, $e4, $00
    .byte $19, $e0, $04
    .byte $fe, $00, $00
    .byte $19, $e4, $00

utf_latin_extended_a:
    .word 256, 128, utf_general_punctuation
    .byte $41, $c9, $00
    .byte $01, $e9, $00
    .byte $41, $c8, $00
    .byte $01, $e8, $00
    .byte $41, $ec, $00
    .byte $01, $ec, $00
    .byte $43, $c0, $04
    .byte $03, $e0, $04
    .byte $43, $c2, $00
    .byte $03, $e2, $00
    .byte $43, $c6, $00
    .byte $03, $e6, $00
    .byte $43, $c8, $00
    .byte $03, $e8, $00
    .byte $44, $c8, $00
    .byte $20, $03, $01
    .byte $44, $d2, $00
    .byte $04, $f2, $00
    .byte $45, $c9, $00
    .byte $05, $e9, $00
    .byte $45, $c8, $00
    .byte $05, $e8, $00
    .byte $45, $c6, $00
    .byte $05, $e6, $00
    .byte $45, $ec, $00
    .byte $05, $cc, $00
    .byte $45, $c8, $00
    .byte $05, $e8, $00
    .byte $47, $c2, $00
    .byte $07, $e2, $00
    .byte $47, $c8, $00
    .byte $07, $e8, $00
    .byte $47, $c6, $00
    .byte $07, $e6, $00
    .byte $47, $ca, $00
    .byte $07, $ea, $00
    .byte $48, $c2, $00
    .byte $08, $c2, $00
    .byte $48, $cb, $00
    .byte $08, $eb, $00
    .byte $49, $c3, $00
    .byte $09, $e3, $00
    .byte $49, $c9, $00
    .byte $09, $e9, $00
    .byte $49, $c8, $00
    .byte $09, $e8, $00
    .byte $49, $cc, $00
    .byte $09, $cc, $00
    .byte $49, $c6, $00
    .byte $09, $00, $00
    .byte $20, $00, $01
    .byte $20, $01, $01
    .byte $4a, $cd, $00
    .byte $0a, $ed, $00
    .byte $4b, $ca, $00
    .byte $0b, $ca, $00
    .byte $6b, $00, $00
    .byte $4c, $c0, $04
    .byte $0c, $c0, $04
    .byte $4c, $cc, $00
    .byte $0c, $cc, $00
    .byte $4c, $ce, $00
    .byte $20, $05, $01
    .byte $4c, $c1, $00
    .byte $0c, $e1, $00
    .byte $4c, $cf, $00
    .byte $0c, $ef, $00
    .byte $4e, $c0, $04
    .byte $0e, $e0, $04
    .byte $4e, $ca, $00
    .byte $0e, $ca, $00
    .byte $4e, $c8, $00
    .byte $0e, $e8, $00
    .byte $20, $04, $01
    .byte $ce, $00, $00
    .byte $ee, $00, $00
    .byte $4f, $c9, $00
    .byte $0f, $e9, $00
    .byte $4f, $c8, $00
    .byte $0f, $e8, $00
    .byte $4f, $d1, $04
    .byte $0f, $f1, $04
    .byte $c7, $00, $00
    .byte $e7, $00, $00
    .byte $52, $c0, $04
    .byte $12, $e0, $04
    .byte $52, $ca, $00
    .byte $12, $ca, $00
    .byte $52, $c8, $00
    .byte $12, $e8, $00
    .byte $53, $c0, $04
    .byte $13, $e0, $04
    .byte $53, $c2, $00
    .byte $13, $e2, $00
    .byte $53, $c7, $00
    .byte $13, $c7, $00
    .byte $53, $c8, $00
    .byte $13, $e8, $00
    .byte $54, $c7, $00
    .byte $14, $c7, $00
    .byte $54, $c8, $00
    .byte $20, $02, $01
    .byte $54, $d0, $00
    .byte $14, $f0, $00
    .byte $55, $c3, $00
    .byte $15, $e3, $00
    .byte $55, $c9, $00
    .byte $15, $e9, $00
    .byte $55, $c8, $00
    .byte $15, $e8, $00
    .byte $55, $c5, $00
    .byte $15, $e5, $00
    .byte $55, $d1, $04
    .byte $15, $f1, $04
    .byte $55, $cc, $00
    .byte $15, $ec, $00
    .byte $57, $c2, $00
    .byte $17, $e2, $00
    .byte $59, $c2, $00
    .byte $19, $e2, $00
    .byte $59, $c4, $00
    .byte $5a, $c0, $04
    .byte $1a, $e0, $04
    .byte $5a, $c6, $00
    .byte $1a, $e6, $00
    .byte $5a, $c8, $00
    .byte $1a, $e8, $00
    .byte $ff, $00, $00

utf_general_punctuation:
    .word $2000, 11, utf_general_punctuation_1
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00
    .byte $20, $00, $00

utf_general_punctuation_1:
    .word $2010, 24, utf_general_punctuation_2
    .byte $2d, $00, $00
    .byte $2d, $00, $00
    .byte $2d, $00, $00
    .byte $2d, $00, $00
    .byte $20, $b8, $01
    .byte $20, $b8, $01
    .byte $20, $b9, $01
    .byte $20, $ba, $01
    .byte $20, $86, $01
    .byte $20, $87, $01
    .byte $20, $86, $0d
    .byte $20, $87, $05
    .byte $20, $88, $01
    .byte $20, $89, $01
    .byte $20, $88, $0d
    .byte $20, $89, $05

    .byte $20, $b1, $01
    .byte $2d, $b1, $01
    .byte $20, $9c, $01
    .byte $20, $9d, $01
    .byte $2e, $00, $00
    .byte $20, $9e, $01
    .byte $20, $9f, $01
    .byte $20, $44, $02

utf_general_punctuation_2:
    .word $202f, 49, utf_superscripts_and_subscripts
    .byte $20, $00, $00
    .byte $20, $af, $01
    .byte $20, $b0, $01
    .byte $20, $8a, $01
    .byte $20, $8b, $01
    .byte $20, $8c, $01
    .byte $20, $8a, $05
    .byte $20, $8b, $05
    .byte $20, $8c, $05
    .byte $20, $98, $01
    .byte $20, $93, $01
    .byte $20, $93, $05
    .byte $20, $9a, $01
    .byte $20, $82, $01
    .byte $20, $85, $01
    .byte $20, $97, $01
    .byte $20, $95, $09

    .byte $20, $95, $01
    .byte $20, $99, $01
    .byte $20, $9b, $01
    .byte $2c, $d0, $00
    .byte $20, $b4, $01
    .byte $20, $90, $01
    .byte $20, $90, $05
    .byte $20, $b2, $01
    .byte $20, $84, $01
    .byte $20, $83, $01
    .byte $20, $bb, $01
    .byte $20, $a2, $01
    .byte $20, $a3, $01
    .byte $20, $a3, $05
    .byte $20, $a0, $01
    .byte $3a, $86, $09

    .byte $20, $a4, $01
    .byte $20, $a1, $01
    .byte $20, $a5, $01
    .byte $20, $a6, $01
    .byte $20, $96, $09
    .byte $20, $a7, $01
    .byte $20, $a8, $01
    .byte $20, $8d, $01
    .byte $20, $a9, $01
    .byte $20, $bc, $01
    .byte $20, $aa, $01
    .byte $20, $ab, $01
    .byte $20, $ac, $01
    .byte $20, $ad, $01
    .byte $20, $ae, $01
    .byte $20, $00, $00

utf_superscripts_and_subscripts:
    .word $2070, 45, utf_box_drawing
    .byte $20, $c0, $02
    .byte $20, $db, $02
    .byte $20, $00, $40
    .byte $20, $00, $40
    .byte $20, $c4, $02
    .byte $20, $c5, $02
    .byte $20, $c6, $02
    .byte $20, $c7, $02
    .byte $20, $c8, $02
    .byte $20, $c9, $02
    .byte $20, $ca, $02
    .byte $20, $cb, $02
    .byte $20, $cc, $02
    .byte $20, $cd, $02
    .byte $20, $cd, $06
    .byte $20, $d7, $02

    .byte $20, $c0, $0a
    .byte $20, $e1, $02
    .byte $20, $e2, $02
    .byte $20, $e3, $02
    .byte $20, $e4, $02
    .byte $20, $e5, $02
    .byte $20, $c9, $0e
    .byte $20, $e7, $02
    .byte $20, $c8, $0a
    .byte $20, $c6, $0e
    .byte $20, $ca, $0a
    .byte $20, $cb, $0a
    .byte $20, $cc, $0a
    .byte $20, $cd, $0a
    .byte $20, $cd, $0e
    .byte $20, $00, $40

    .byte $20, $ee, $02
    .byte $20, $d2, $0e
    .byte $20, $d0, $0a
    .byte $20, $d1, $0a
    .byte $20, $cf, $0e
    .byte $20, $f3, $02
    .byte $20, $f4, $02
    .byte $20, $f5, $02
    .byte $20, $f6, $02
    .byte $20, $f7, $02
    .byte $20, $f8, $02
    .byte $20, $d9, $0e
    .byte $20, $fa, $02

utf_box_drawing:
    .word $2500, 128, utf_block_elements
    .byte $40, $00, $00
    .byte $40, $00, $00
    .byte $5b, $00, $00
    .byte $5b, $00, $00
    .byte $20, $3c, $00
    .byte $20, $3c, $00
    .byte $20, $3b, $00
    .byte $20, $3b, $00
    .byte $20, $3e, $00
    .byte $20, $3e, $00
    .byte $20, $3d, $00
    .byte $20, $3d, $00
    .byte $20, $32, $08
    .byte $20, $32, $08
    .byte $20, $32, $08
    .byte $20, $32, $08

    .byte $20, $32, $0c
    .byte $20, $32, $0c
    .byte $20, $32, $0c
    .byte $20, $32, $0c
    .byte $20, $32, $00
    .byte $20, $32, $00
    .byte $20, $32, $00
    .byte $20, $32, $00
    .byte $20, $32, $04
    .byte $20, $32, $04
    .byte $20, $32, $04
    .byte $20, $32, $04
    .byte $5b, $3f, $04
    .byte $5b, $3f, $04
    .byte $5b, $3f, $04
    .byte $5b, $3f, $04

    .byte $5b, $3f, $04
    .byte $5b, $3f, $04
    .byte $5b, $3f, $04
    .byte $5b, $3f, $04
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $40, $40, $08
    .byte $40, $40, $08
    .byte $40, $40, $08
    .byte $40, $40, $08

    .byte $40, $40, $08
    .byte $40, $40, $08
    .byte $40, $40, $08
    .byte $40, $40, $08
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00

    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $20, $3a, $00
    .byte $20, $3a, $00
    .byte $20, $39, $00
    .byte $20, $39, $00

    .byte $40, $00, $00
    .byte $5b, $00, $00
    .byte $20, $32, $08
    .byte $20, $32, $08
    .byte $20, $32, $08
    .byte $20, $32, $0c
    .byte $20, $32, $0c
    .byte $20, $32, $0c
    .byte $20, $32, $00
    .byte $20, $32, $00
    .byte $20, $32, $00
    .byte $20, $32, $04
    .byte $20, $32, $04
    .byte $20, $32, $04
    .byte $5b, $3f, $04
    .byte $5b, $3f, $04

    .byte $5b, $3f, $04
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $5b, $3f, $00
    .byte $40, $40, $08
    .byte $40, $40, $08
    .byte $40, $40, $08
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $40, $40, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $5b, $4c, $00
    .byte $20, $38, $08
    .byte $20, $38, $0c
    .byte $20, $38, $04

    .byte $20, $38, $00
    .byte $20, $7f, $00
    .byte $7f, $00, $00
    .byte $7f, $7f, $00
    .byte $20, $3f, $00
    .byte $20, $40, $00
    .byte $20, $3f, $04
    .byte $20, $40, $08
    .byte $20, $3f, $00
    .byte $20, $40, $00
    .byte $20, $3f, $04
    .byte $20, $40, $08
    .byte $40, $00, $00
    .byte $5b, $00, $00
    .byte $40, $00, $00
    .byte $5b, $00, $00

utf_block_elements:
    .word $2580, 32, private_use_e020_font_3
    .byte $20, $2a, $80
    .byte $20, $27, $00
    .byte $20, $28, $00
    .byte $20, $29, $00
    .byte $20, $2a, $00
    .byte $20, $2b, $00
    .byte $20, $2c, $00
    .byte $20, $2d, $00
    .byte $20, $00, $80
    .byte $20, $26, $00
    .byte $20, $25, $00
    .byte $20, $24, $00
    .byte $20, $23, $00
    .byte $20, $22, $00
    .byte $20, $21, $00
    .byte $20, $20, $00

    .byte $20, $23, $80
    .byte $20, $30, $00
    .byte $20, $31, $00
    .byte $20, $30, $8c
    .byte $20, $27, $08
    .byte $20, $20, $04
    .byte $20, $2e, $0c
    .byte $20, $2e, $08
    .byte $20, $2e, $04
    .byte $20, $2e, $80
    .byte $20, $2f, $80
    .byte $20, $2e, $88
    .byte $20, $2e, $8c
    .byte $20, $2e, $00
    .byte $20, $2f, $00
    .byte $20, $2e, $84

private_use_e020_font_3:
    .word $e020, 95, 0
    .byte $20, $00, $00
    .byte $1f, $00, $00
    .byte $20, $1f, $00
    .byte $20, $7f, $00
    .byte $7f, $00, $00
    .byte $20, $00, $00
    .byte $40, $00, $00
    .byte $40, $00, $00
    .byte $5b, $00, $00
    .byte $5b, $00, $00
    .byte $40, $40, $00
    .byte $40, $40, $08
    .byte $5b, $3f, $04
    .byte $5b, $3f, $00
    .byte $20, $32, $00
    .byte $20, $32, $08
    .byte $20, $32, $0c
    .byte $20, $32, $04
    .byte $20, $36, $00
    .byte $20, $36, $08
    .byte $20, $36, $0c
    .byte $20, $36, $04
    .byte $20, $00, $80
    .byte $20, $33, $00
    .byte $20, $33, $08
    .byte $20, $23, $00
    .byte $20, $23, $04
    .byte $5b, $33, $08
    .byte $5b, $33, $00
    .byte $40, $23, $00
    .byte $40, $23, $04
    .byte $20, $34, $00
    .byte $20, $34, $08
    .byte $20, $34, $0c
    .byte $20, $34, $04
    .byte $20, $37, $00
    .byte $20, $37, $08
    .byte $20, $37, $0c
    .byte $20, $37, $04
    .byte $20, $35, $00
    .byte $20, $35, $08
    .byte $20, $35, $0c
    .byte $20, $35, $04
    .byte $20, $27, $08
    .byte $20, $27, $00
    .byte $20, $20, $00
    .byte $20, $20, $04
    .byte $20, $42, $00
    .byte $20, $43, $00
    .byte $20, $44, $00
    .byte $20, $45, $00
    .byte $20, $46, $00
    .byte $20, $47, $00
    .byte $20, $48, $00
    .byte $20, $49, $00
    .byte $20, $4a, $00
    .byte $20, $41, $00
    .byte $20, $4b, $00
    .byte $7f, $7f, $00
    .byte $5b, $4c, $00
    .byte $1e, $00, $00
    .byte $20, $1e, $00
    .byte $1e, $1e, $00
    .byte $9e, $9e, $00
    .byte $3f, $00, $00
    .byte $20, $81, $02
    .byte $20, $82, $02
    .byte $20, $83, $02
    .byte $20, $84, $02
    .byte $20, $85, $02
    .byte $20, $86, $02
    .byte $20, $87, $02
    .byte $20, $88, $02
    .byte $20, $89, $02
    .byte $20, $8a, $02
    .byte $20, $8b, $02
    .byte $20, $8c, $02
    .byte $20, $8d, $02
    .byte $20, $8e, $02
    .byte $20, $8f, $02
    .byte $20, $90, $02
    .byte $20, $91, $02
    .byte $20, $92, $02
    .byte $20, $93, $02
    .byte $20, $94, $02
    .byte $20, $95, $02
    .byte $20, $96, $02
    .byte $20, $97, $02
    .byte $20, $98, $02
    .byte $20, $99, $02
    .byte $20, $9a, $02
    .byte $1e, $00, $80
    .byte $20, $1e, $80
    .byte $1e, $1e, $80
    .byte $3f, $00, $80
