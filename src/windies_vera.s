.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.bss

blt_src:    .res 3
blt_dst:    .res 3
blt_len:    .res 2

.code

; This initializes the VERA to display in one of two modes:
;   Text mode (default): 80x30 text, used for displaying text. Uses both layers so we can overlay characters.
;       - Map size = 128x32, tile size = 8x16
;       - Layer 0 (base) text mode, 1bpp, T256C=0, map is from $02000-03fff, line stride is 256, tile set is at $04000
;       - Layer 1 (overlay) text mode, 2bpp, map is from $00000-01fff, line stride is 256, tile set is at $05000
;   TODO: Graphics mode: 640x200x16 bitmap, used for displaying graphics in V6 games that need it.
;       - Bitmap mode, 4bpp, TILEW=1,TILEH=0
;       - Screen buffer is from $00000-$1f3ff
.proc vera_init
    ; Load our Z-machine font to $04000 in VRAM (4K layer 0 base glyphs, 32K layer 1 overlay glyphs)
    ldx #0
@1: lda loadingmsg,x
    beq @loadfont
    jsr CHROUT
    inx
    bra @1
@loadfont:
    lda #1
    ldx #8
    ldy #2
    jsr SETLFS
    lda #zigfont_end-zigfont
    ldx #<zigfont
    ldy #>zigfont
    jsr SETNAM
    lda #2
    ldx #0
    ldy #$40
    jsr LOAD
    bcc @doneload
@cantloadfont:
    ldx #0
@2: lda cantloadfont,x
    beq @exittobasic
    jsr CHROUT
    inx
    bra @2
@exittobasic:
    clc
    jmp RESTORE_BASIC

@doneload:
    ; Configure the display compositor
    lda VERA::CTRL
    and #$fd
    sta VERA::CTRL
    lda VERA_DC_VIDEO
    and #$8f
    ora #$30
    sta VERA_DC_VIDEO
    lda #$80
    sta VERA_DC_HSCALE
    sta VERA_DC_VSCALE
    stz VERA_DC_BORDER
    lda VERA::CTRL
    ora #$02
    sta VERA::CTRL
    stz VERA_DC_HSTART
    stz VERA_DC_VSTART
    lda #160
    sta VERA_DC_HSTOP
    lda #240
    sta VERA_DC_VSTOP

    ; Configure layer 0
    lda #$20
    sta VERA_L0_CONFIG
    stz VERA_L0_MAPBASE
    lda #$22
    sta VERA_L0_TILEBASE
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H

    ; Configure layer 1
    lda #$21
    sta VERA_L1_CONFIG
    lda #$10
    sta VERA_L1_MAPBASE
    lda #$2a
    sta VERA_L1_TILEBASE
    stz VERA_L1_HSCROLL_L
    stz VERA_L1_HSCROLL_H
    stz VERA_L1_VSCROLL_L
    stz VERA_L1_VSCROLL_H

    ; Set palette colors
    ldx #11
@3: jsr setpalette
    dex
    bne @3

    ; Clear layer 0 with 8K of yellow-on-black spaces and layer 1 with 8K of 0s
    lda VERA::CTRL
    and #$fe
    sta VERA::CTRL
    stz VERA::ADDR
    stz VERA::ADDR+1
    lda #$10
    sta VERA::ADDR+2
    lda VERA::CTRL
    ora #$01
    sta VERA::CTRL
    stz VERA::ADDR
    lda #$20
    sta VERA::ADDR+1
    lda #$10
    sta VERA::ADDR+2
    ldy #(W_BLACK << 4) | W_YELLOW
    lda #' '
@7: stz VERA::DATA1
    stz VERA::DATA1
    sta VERA::DATA0
    sty VERA::DATA0
    bit VERA::ADDR+1
    bvc @7
    rts
.endproc

.proc vera_blt
    ; Put destination address in ADDR1
    lda VERA::CTRL
    ora #1
    sta VERA::CTRL
    lda blt_dst
    sta VERA::ADDR
    lda blt_dst+1
    sta VERA::ADDR+1
    lda blt_dst+2
    sta VERA::ADDR+2

    ; Put source address in ADDR0
    lda VERA::CTRL
    and #$fe
    sta VERA::CTRL
    lda blt_src
    sta VERA::ADDR
    lda blt_src+1
    sta VERA::ADDR+1
    lda blt_src+2
    sta VERA::ADDR+2

    ; Blit the line
    ldx blt_len+1
    ldy blt_len
@blit_loop:
    lda VERA::DATA0
    sta VERA::DATA1
    lda blt_len
    bne @1
    dec blt_len+1
@1: dec blt_len
    lda blt_len
    ora blt_len+1
    bne @blit_loop
    rts
.endproc

.proc setpalette
    ; Read appropriate color
    txa
    dec
    asl
    tay
    lda zm_colors,y
    sta gREG::r0L
    iny
    lda zm_colors,y
    sta gREG::r0H

    ; We want to update palette entry x+1, and also palette entry (x+1)*16+3
    lda VERA::CTRL
    and #$fe
    sta VERA::CTRL
    lda #$11
    sta VERA::ADDR+2
    lda #$fa
    sta VERA::ADDR+1
    txa
    inc
    asl
    sta VERA::ADDR
    lda gREG::r0L
    sta VERA::DATA0
    lda gREG::r0H
    sta VERA::DATA0
    txa
    inc
    cmp #$08
    bcc @1
    ldy #$fb
    .byte $2c
@1: ldy #$fa
    sty VERA::ADDR+1
    asl
    asl
    asl
    asl
    asl
    clc
    adc #6
    sta VERA::ADDR
    lda gREG::r0L
    sta VERA::DATA0
    lda gREG::r0H
    sta VERA::DATA0
    rts
.endproc

.rodata

zm_colors:
    .word   $000    ; black
    .word   $e00    ; red
    .word   $0d0    ; green
    .word   $ee0    ; yellow
    .word   $06b    ; blue
    .word   $f0f    ; magenta
    .word   $0ee    ; cyan
    .word   $fff    ; white
    .word   $bbb    ; light grey
    .word   $888    ; medium grey
    .word   $555    ; dark grey

loadingmsg:     .byte CH::FONT_LOWER, "Loading "
zigfont:        .byte "ziggurat.fnt"
zigfont_end:    .byte "...", 0
cantloadfont:   .byte "Error loading font!", CH::ENTER, 0
