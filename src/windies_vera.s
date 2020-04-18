.include "cx16.inc"
.include "cbm_kernal.inc"
.include "windies_impl.inc"

.bss

blt_src:    .res 3
blt_dst:    .res 3
blt_len:    .res 2

.code

; This initializes the VERA to display in one of two modes:
;   Text mode (default): 80x30x256 text, used for displaying text. Uses both layers so we can overlay characters.
;       - Text mode, 1bpp, T256C=1
;       - Map size = 128x32, tile size = 8x16
;       - Layer 0 (extras) map is from $02000-03fff, line stride is 256, tile set is at $05000
;       - Layer 1 (normal) map is from $00000-01fff, line stride is 256, tile set is at $04000
;   TODO: Graphics mode: 640x200x16 bitmap, used for displaying graphics in V6 games that need it.
;       - Bitmap mode, 4bpp, TILEW=1,TILEH=0
;       - Screen buffer is from $00000-$1f3ff
.proc vera_init
    ; Copy our default Z-machine font to $04000-$05fff
    lda VERA::CTRL
    and #$fe
    sta VERA::CTRL
    lda #$10
    sta VERA::ADDR+2
    lda #$40
    sta VERA::ADDR+1
    stz VERA::ADDR
    lda #<zmachine_default_font_8x16
    sta win_ptr
    lda #>zmachine_default_font_8x16
    sta win_ptr+1
    ldx #32
    ldy #0
@4: lda (win_ptr),y
    sta VERA::DATA0
    iny
    bne @4
    inc win_ptr+1
    dex
    bne @4

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
    lda #$10
    sta VERA_L0_MAPBASE
    lda #$2a
    sta VERA_L0_TILEBASE
    stz VERA_L0_HSCROLL_L
    stz VERA_L0_HSCROLL_H
    stz VERA_L0_VSCROLL_L
    stz VERA_L0_VSCROLL_H

    ; Configure layer 1
    lda #$20
    sta VERA_L1_CONFIG
    stz VERA_L1_MAPBASE
    lda #$22
    sta VERA_L1_TILEBASE
    stz VERA_L1_HSCROLL_L
    stz VERA_L1_HSCROLL_H
    stz VERA_L1_VSCROLL_L
    stz VERA_L1_VSCROLL_H

    ; Clear layer 0 with 8K of 0s and layer 1 with 8K of yellow-on-black spaces
    lda VERA::CTRL
    and #$fe
    sta VERA::CTRL
    stz VERA::ADDR
    lda #$20
    stz VERA::ADDR+1
    lda #$10
    sta VERA::ADDR+2
    lda VERA::CTRL
    ora #$01
    sta VERA::CTRL
    stz VERA::ADDR
    stz VERA::ADDR+1
    lda #$10
    sta VERA::ADDR+2
    ldy #COLOR::YELLOW
    lda #' '
@7: stz VERA::DATA0
    stz VERA::DATA0
    sta VERA::DATA1
    sty VERA::DATA1
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
