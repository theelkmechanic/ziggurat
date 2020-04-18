.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.bss

utf_xlat_addr: .res 3

utf16 = $7d0
map_base = gREG::r9
map_entry = gREG::r10

.code

; utf_find_charinfo - Find the character info table entry for the specified UTF-16 character
; In:   a           - character font
;       x/y         - UTF-16 character (x=hi, y=lo)
; Out:  a           - character flags
;       x           - normal character glyph
;       y           - extras character glyph
;       carry       - set if character info was found
.proc utf_find_charinfo
    ; Save the character
    sty utf16
    stx utf16+1

    ; Check if we're using the special Z-machine font
    cmp #3
    bne @check_basic

    ; Start with the Font 3 map
    lda #<utf_zm_font3
    sta map_base
    lda #>utf_zm_font3
    sta map_base+1
    bra @scan_maps

@check_basic:
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
    lda (map_entry),y
    tax
    iny
    lda (map_entry),y
    tay
    lda (map_entry)

    ; And we're done
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
    beq @not_found
    jmp @scan_maps
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

; Our UTF and Z-machine Font 3 fontmaps start with three words:
;   * Starting UTF-16 character in the map
;   * Number of entries in the table
;   * Address of the next map (0 if last map)
;
; These are followed by entries of 3 bytes each:
;   * Flags byte:
;       * $80 = layer 1 transparency (if 1, draw layer 1 with transparent background so layer 0 shows)
;       * $40 = layer 1 reversed (if 1, draw layer 1 colors reversed)
;       * $20 = layer 0 reversed (if 1, draw layer 0 colors reversed)
;   * Glyph index from normal (layer 1) font
;   * Glyph index from extras (layer 0) font

utf_basic_latin:
    .word 32, 95, utf_latin_1_supplement
    .byte $00, $20, $00
    .byte $00, $21, $00
    .byte $00, $22, $00
    .byte $00, $23, $00
    .byte $00, $24, $00
    .byte $00, $25, $00
    .byte $00, $26, $00
    .byte $00, $27, $00
    .byte $00, $28, $00
    .byte $00, $29, $00
    .byte $00, $2a, $00
    .byte $00, $2b, $00
    .byte $00, $2c, $00
    .byte $00, $2d, $00
    .byte $00, $2e, $00
    .byte $00, $2f, $00
    .byte $00, $30, $00
    .byte $00, $31, $00
    .byte $00, $32, $00
    .byte $00, $33, $00
    .byte $00, $34, $00
    .byte $00, $35, $00
    .byte $00, $36, $00
    .byte $00, $37, $00
    .byte $00, $38, $00
    .byte $00, $39, $00
    .byte $00, $3a, $00
    .byte $00, $3b, $00
    .byte $00, $3c, $00
    .byte $00, $3d, $00
    .byte $00, $3e, $00
    .byte $00, $3f, $00
    .byte $00, $00, $00
    .byte $00, $41, $00
    .byte $00, $42, $00
    .byte $00, $43, $00
    .byte $00, $44, $00
    .byte $00, $45, $00
    .byte $00, $46, $00
    .byte $00, $47, $00
    .byte $00, $48, $00
    .byte $00, $49, $00
    .byte $00, $4a, $00
    .byte $00, $4b, $00
    .byte $00, $4c, $00
    .byte $00, $4d, $00
    .byte $00, $4e, $00
    .byte $00, $4f, $00
    .byte $00, $50, $00
    .byte $00, $51, $00
    .byte $00, $52, $00
    .byte $00, $53, $00
    .byte $00, $54, $00
    .byte $00, $55, $00
    .byte $00, $56, $00
    .byte $00, $57, $00
    .byte $00, $58, $00
    .byte $00, $59, $00
    .byte $00, $5a, $00
    .byte $00, $1b, $00
    .byte $00, $5c, $00
    .byte $00, $1d, $00
    .byte $00, $5e, $00
    .byte $00, $5f, $00
    .byte $80, $20, $c0
    .byte $00, $01, $00
    .byte $00, $02, $00
    .byte $00, $03, $00
    .byte $00, $04, $00
    .byte $00, $05, $00
    .byte $00, $06, $00
    .byte $00, $07, $00
    .byte $00, $08, $00
    .byte $80, $09, $e6
    .byte $80, $0a, $e3
    .byte $00, $0b, $00
    .byte $00, $0c, $00
    .byte $00, $0d, $00
    .byte $00, $0e, $00
    .byte $00, $0f, $00
    .byte $00, $10, $00
    .byte $00, $11, $00
    .byte $00, $12, $00
    .byte $00, $13, $00
    .byte $00, $14, $00
    .byte $00, $15, $00
    .byte $00, $16, $00
    .byte $00, $17, $00
    .byte $00, $18, $00
    .byte $00, $19, $00
    .byte $00, $1a, $00
    .byte $00, $7b, $00
    .byte $00, $7c, $00
    .byte $00, $7d, $00
    .byte $80, $20, $7e

utf_zm_font3:
    .word 32, 95, utf_latin_1_supplement
    .byte $00, $20, $00
    .byte $00, $1f, $00
    .byte $80, $20, $1f
    .byte $80, $20, $7f
    .byte $00, $7f, $00
    .byte $00, $20, $00
    .byte $00, $40, $00
    .byte $00, $40, $00
    .byte $00, $5d, $00
    .byte $00, $5d, $00
    .byte $80, $40, $20
    .byte $80, $40, $21
    .byte $80, $5d, $20
    .byte $80, $5d, $22
    .byte $80, $20, $20
    .byte $80, $20, $21
    .byte $80, $20, $22
    .byte $80, $20, $23
    .byte $80, $9c, $20
    .byte $80, $9d, $21
    .byte $80, $9e, $22
    .byte $80, $9f, $23
    .byte $40, $20, $20
    .byte $80, $20, $24
    .byte $80, $20, $25
    .byte $80, $20, $26
    .byte $80, $20, $27
    .byte $80, $5d, $25
    .byte $80, $5d, $24
    .byte $80, $40, $26
    .byte $80, $40, $27
    .byte $80, $20, $28
    .byte $80, $20, $29
    .byte $80, $20, $2a
    .byte $80, $20, $2b
    .byte $80, $9c, $28
    .byte $80, $9d, $29
    .byte $80, $9e, $2a
    .byte $80, $9f, $2b
    .byte $80, $20, $9c
    .byte $80, $20, $9d
    .byte $80, $20, $9e
    .byte $80, $20, $9f
    .byte $00, $fb, $00
    .byte $80, $20, $fb
    .byte $00, $fd, $00
    .byte $80, $20, $fd
    .byte $80, $20, $91
    .byte $80, $20, $92
    .byte $80, $20, $93
    .byte $80, $20, $94
    .byte $80, $20, $95
    .byte $80, $20, $96
    .byte $80, $20, $97
    .byte $80, $20, $98
    .byte $80, $20, $99
    .byte $80, $20, $9a
    .byte $80, $20, $9b
    .byte $80, $7f, $7f
    .byte $00, $5b, $00
    .byte $00, $1e, $00
    .byte $80, $20, $1e
    .byte $80, $1e, $1e
    .byte $80, $fc, $fc
    .byte $00, $3f, $00
    .byte $00, $81, $00
    .byte $00, $82, $00
    .byte $00, $83, $00
    .byte $00, $84, $00
    .byte $00, $85, $00
    .byte $00, $86, $00
    .byte $00, $87, $00
    .byte $00, $88, $00
    .byte $00, $89, $00
    .byte $00, $8a, $00
    .byte $00, $8b, $00
    .byte $00, $8c, $00
    .byte $00, $8d, $00
    .byte $00, $8e, $00
    .byte $00, $8f, $00
    .byte $00, $90, $00
    .byte $00, $91, $00
    .byte $00, $92, $00
    .byte $00, $93, $00
    .byte $00, $94, $00
    .byte $00, $95, $00
    .byte $00, $96, $00
    .byte $00, $97, $00
    .byte $00, $98, $00
    .byte $00, $99, $00
    .byte $00, $9a, $00
    .byte $40, $1e, $00
    .byte $a0, $20, $1e
    .byte $40, $9b, $00
    .byte $40, $3f, $00

utf_latin_1_supplement:
    .word 160, 96, utf_latin_extended_a
    .byte $00, $20, $00
    .byte $00, $a1, $00
    .byte $00, $a2, $00
    .byte $00, $1c, $00
    .byte $00, $a4, $00
    .byte $00, $a5, $00
    .byte $00, $a6, $00
    .byte $00, $a7, $00
    .byte $80, $20, $c4
    .byte $00, $a9, $00
    .byte $00, $aa, $00
    .byte $00, $ab, $00
    .byte $00, $ac, $00
    .byte $00, $2d, $00
    .byte $00, $ae, $00
    .byte $80, $20, $c9
    .byte $00, $b0, $00
    .byte $00, $b1, $00
    .byte $00, $b2, $00
    .byte $00, $b3, $00
    .byte $80, $20, $c1
    .byte $00, $6d, $00
    .byte $00, $b6, $00
    .byte $00, $b7, $00
    .byte $80, $20, $c7
    .byte $00, $b9, $00
    .byte $00, $ba, $00
    .byte $00, $bb, $00
    .byte $00, $bc, $00
    .byte $00, $bd, $00
    .byte $00, $be, $00
    .byte $00, $bf, $00
    .byte $80, $41, $c0
    .byte $80, $41, $c1
    .byte $80, $41, $c2
    .byte $80, $41, $c3
    .byte $80, $41, $c4
    .byte $80, $41, $c5
    .byte $00, $c6, $00
    .byte $80, $43, $c7
    .byte $80, $45, $c0
    .byte $80, $45, $c1
    .byte $80, $45, $c2
    .byte $80, $45, $c4
    .byte $80, $49, $c0
    .byte $80, $49, $c1
    .byte $80, $49, $c2
    .byte $80, $49, $c4
    .byte $80, $44, $d2
    .byte $80, $4e, $c3
    .byte $80, $4f, $c0
    .byte $80, $4f, $c1
    .byte $80, $4f, $c2
    .byte $80, $4f, $c3
    .byte $80, $4f, $c4
    .byte $00, $d7, $00
    .byte $80, $4f, $d8
    .byte $80, $55, $c0
    .byte $80, $55, $c1
    .byte $80, $55, $c2
    .byte $80, $55, $c4
    .byte $80, $59, $c2
    .byte $00, $de, $00
    .byte $00, $df, $00
    .byte $80, $01, $e0
    .byte $80, $01, $e1
    .byte $80, $01, $e2
    .byte $80, $01, $7e
    .byte $80, $01, $e4
    .byte $80, $01, $e5
    .byte $00, $e6, $00
    .byte $80, $03, $e7
    .byte $80, $05, $e0
    .byte $80, $05, $e1
    .byte $80, $05, $e2
    .byte $80, $05, $e4
    .byte $80, $09, $e0
    .byte $80, $09, $e1
    .byte $80, $09, $e2
    .byte $80, $09, $e4
    .byte $00, $d0, $00
    .byte $80, $0e, $7e
    .byte $80, $0f, $e0
    .byte $80, $0f, $e1
    .byte $80, $0f, $e2
    .byte $80, $0f, $7e
    .byte $80, $0f, $e4
    .byte $00, $f7, $00
    .byte $80, $0f, $f8
    .byte $80, $15, $e0
    .byte $80, $15, $e1
    .byte $80, $15, $e2
    .byte $80, $15, $e4
    .byte $80, $19, $e2
    .byte $00, $fe, $00
    .byte $80, $19, $e4

utf_latin_extended_a:
    .word 256, 128, 0
    .byte $80, $41, $c9
    .byte $80, $01, $e9
    .byte $80, $41, $c8
    .byte $80, $01, $e8
    .byte $80, $41, $ec
    .byte $80, $01, $ec
    .byte $80, $43, $c1
    .byte $80, $03, $e1
    .byte $80, $43, $c2
    .byte $80, $03, $e2
    .byte $80, $43, $c6
    .byte $80, $03, $e6
    .byte $80, $43, $c8
    .byte $80, $03, $e8
    .byte $80, $44, $c8
    .byte $80, $20, $7d
    .byte $80, $44, $d2
    .byte $80, $04, $7c
    .byte $80, $45, $c9
    .byte $80, $05, $e9
    .byte $80, $45, $c8
    .byte $80, $05, $e8
    .byte $80, $45, $c6
    .byte $80, $05, $e6
    .byte $80, $45, $ec
    .byte $80, $05, $cc
    .byte $80, $45, $c8
    .byte $80, $05, $e8
    .byte $80, $47, $c2
    .byte $80, $07, $e2
    .byte $80, $47, $c8
    .byte $80, $07, $e8
    .byte $80, $47, $c6
    .byte $80, $07, $e6
    .byte $80, $47, $ca
    .byte $80, $07, $ea
    .byte $80, $48, $c2
    .byte $80, $08, $c2
    .byte $80, $48, $cb
    .byte $80, $08, $eb
    .byte $80, $49, $c3
    .byte $80, $09, $7e
    .byte $80, $49, $c9
    .byte $80, $09, $e9
    .byte $80, $49, $c8
    .byte $80, $09, $e8
    .byte $80, $49, $cc
    .byte $80, $09, $cc
    .byte $80, $49, $c6
    .byte $00, $09, $00
    .byte $80, $20, $49
    .byte $80, $20, $09
    .byte $80, $4a, $cd
    .byte $80, $0a, $ed
    .byte $80, $4b, $ca
    .byte $80, $0b, $ca
    .byte $00, $6b, $00
    .byte $80, $4c, $c1
    .byte $80, $0c, $c1
    .byte $80, $4c, $cc
    .byte $80, $0c, $cc
    .byte $80, $4c, $ce
    .byte $80, $20, $ee
    .byte $80, $4c, $4c
    .byte $80, $0c, $0c
    .byte $80, $4c, $cf
    .byte $80, $0c, $ef
    .byte $80, $4e, $c1
    .byte $80, $0e, $e1
    .byte $80, $4e, $ca
    .byte $80, $0e, $ca
    .byte $80, $4e, $c8
    .byte $80, $0e, $e8
    .byte $00, $0e, $00
    .byte $00, $ce, $00
    .byte $00, $ee, $00
    .byte $80, $4f, $c9
    .byte $80, $0f, $e9
    .byte $80, $4f, $c8
    .byte $80, $0f, $e8
    .byte $80, $4f, $d3
    .byte $80, $0f, $f3
    .byte $00, $c7, $00
    .byte $00, $e7, $00
    .byte $80, $52, $c1
    .byte $80, $12, $e1
    .byte $80, $52, $ca
    .byte $80, $12, $ca
    .byte $80, $52, $c8
    .byte $80, $12, $e8
    .byte $80, $53, $c1
    .byte $80, $13, $e1
    .byte $80, $53, $c2
    .byte $80, $13, $e2
    .byte $80, $53, $c7
    .byte $80, $13, $c7
    .byte $80, $53, $c8
    .byte $80, $13, $e8
    .byte $80, $54, $c7
    .byte $80, $14, $c7
    .byte $80, $54, $c8
    .byte $80, $20, $7b
    .byte $80, $54, $d0
    .byte $80, $14, $f0
    .byte $80, $55, $c3
    .byte $80, $15, $7e
    .byte $80, $55, $c9
    .byte $80, $15, $e9
    .byte $80, $55, $c8
    .byte $80, $15, $e8
    .byte $80, $55, $c5
    .byte $80, $15, $e5
    .byte $80, $55, $d3
    .byte $80, $15, $f3
    .byte $80, $55, $cc
    .byte $80, $15, $ec
    .byte $80, $57, $c2
    .byte $80, $17, $e2
    .byte $80, $59, $c2
    .byte $80, $19, $e2
    .byte $80, $59, $c4
    .byte $80, $5a, $c1
    .byte $80, $1a, $e1
    .byte $80, $5a, $c6
    .byte $80, $1a, $e6
    .byte $80, $5a, $c8
    .byte $80, $1a, $e8
    .byte $00, $ff, $00
