.include "ziggurat.inc"
.include "zpu.inc"

.import load_file_to_hiram

.segment "EXEHDR"
    ; Stub launcher
    .byte $0b, $08, $b0, $07, $9e, $32, $30, $36, $31, $00, $00, $00

titlewin = $803
filewin = $804
loadwinwidth = $400
fnlen = $401
fnaddr = $402
filename = $404
fncount = $400
fnlist = $414
fntoplineidx = $404
curline = $405

.segment "LOWCODE"
    ; Initialize our windowing library
    lda #1
    sta VIA1::PRA
    jsr win_init

    ; Show title screen
    ; Open a full-screen window
    jsr win_open
    sta titlewin
    ldx #0
    ldy #0
    jsr win_setpos
    jsr win_setcursor
    jsr win_setwrap
    ldx #80
    ldy #30
    jsr win_setsize
    ldx #(COLOR::WHITE << 4) + COLOR::GRAY1
    jsr win_setcolor
    jsr show_title

    ; Show "Loading directory" message
    ldx #>directory
    ldy #<directory
    lda #9
    jsr show_loading

    ; Load the directory into high memory
    lda #>dollar
    sta gREG::r0H
    lda #<dollar
    sta gREG::r0L
    lda #1
    ldx #8
    jsr load_file_to_hiram

    ; Save the addresses/lengths of all our filenames
    jsr parse_filenames

    ; Close the loading message and repaint the title
    lda filewin
    jsr win_close
    jsr show_title

    ; Open the file picker window
    jsr win_open
    sta filewin
    ldx #30
    ldy #10
    jsr win_setpos
    ldx #0
    ldy #0
    jsr win_setcursor
    jsr win_setwrap
    ldx #20
    ldy #18
    jsr win_setsize
    ldx #(COLOR::GRAY1 << 4) + COLOR::WHITE
    jsr win_setcolor
    jsr win_clear
    jsr boxfilewin
    lda filewin
    ldx #2
    ldy #0
    jsr win_setcursor
    ldx #>choose
    ldy #<choose
    jsr printxy
    lda filewin
    jsr win_getpos
    inx
    iny
    jsr win_setpos
    jsr win_getsize
    dex
    dex
    dey
    dey
    jsr win_setsize

    ; Choose the file to load
    jsr choose_file

    ; Close the file picker window, repaint the title screen
    lda filewin
    jsr win_close
    jsr show_title

    ; Show "Loading filename" message
    lda fnlen
    ldx #>filename
    ldy #<filename
    jsr show_loading

    ; Load the ZIF file
    lda #>filename
    sta gREG::r0H
    lda #<filename
    sta gREG::r0L
    lda fnlen
    ldx #8
    jsr load_file_to_hiram

    ; Close our windows
    lda filewin
    jsr win_close
    lda titlewin
    jsr win_close

    ; Start the ZPU
    jmp zpu_start

.proc show_title
    lda titlewin
    jsr win_clear
    ldx #1
    ldy #1
    jsr win_setcursor
    ldx #>zigtitle
    ldy #<zigtitle
    jsr printxy
    rts
.endproc

.proc update_yline
    ; Check if fntoplineidx + y < count
    stz fnlen
    phy
    tya
    clc
    adc fntoplineidx
    cmp fncount
    bcs @printloop

    ; Okay, line should be a valid filename, so find it and print it
    sta gREG::r0L
    stz gREG::r0H
    asl gREG::r0L
    rol gREG::r0H
    asl gREG::r0L
    rol gREG::r0H
    lda #<fnlist
    clc
    adc gREG::r0L
    sta gREG::r0L
    lda #>fnlist
    adc gREG::r0H
    sta gREG::r0H

    ; Is this the current line
    lda filewin
    ldx #3
    jsr win_setfont
    ldx #0
    jsr win_setcursor
    cpy curline
    beq @iscurrent
    ldy #' '
    .byte $2c
@iscurrent:
    ldy #34
    sec
    jsr win_putchr

    ; Print the filename followed by enough spaces to clear the remainder of the line
    ldy #1
    lda (gREG::r0)
    sta zpu_mem
    lda (gREG::r0),y
    sta zpu_mem+1
    iny
    lda (gREG::r0),y
    sta zpu_mem+2
    sta VIA1::PRA
    iny
    lda (gREG::r0),y
    sta fnlen
    stz gREG::r0
    ldx #0
    lda filewin
    jsr win_setfont
@printloop:
    lda gREG::r0
    cmp #16
    bcs @done
    cmp fnlen
    bcs @usespace
    jsr mem_fetch_and_advance
    .byte $2c
@usespace:
    lda #' '
    tay
    lda filewin
    sec
    jsr win_putchr
    inc gREG::r0
    bra @printloop

@done:
    ply
    rts
.endproc

.proc choose_file
    ; Show first (up to) 16 filenames
    lda filewin
    jsr win_clear
    ldx #0
    ldy #0
    jsr win_setcursor
    ldy #10
    sty fntoplineidx
    sty curline
    ldy #15
@1: jsr update_yline
    dey
    bpl @1

@keys:
    jsr GETIN
    cmp #17
    beq @cursordown
    cmp #145
    beq @cursorup
    cmp #13
    beq @selected
    bra @keys

@cursorup:
    ; Check if we're at the top
    lda curline
    beq @atthetop
    dec curline
    tay
    jsr update_yline
    dey
    jsr update_yline
    bra @keys

@atthetop:
    ; Can we scroll more names into view?
    lda fntoplineidx
    beq @keys
    lda filewin
    jsr win_scrolldown
    dec fntoplineidx
    ldy #0
    jsr update_yline
    iny
    jsr update_yline
    bra @keys

@cursordown:
    ; Check if we're at the end of the file list
    lda fntoplineidx
    clc
    adc curline
    inc
    cmp fncount
    bcs @keys

    ; We can move down, are we at the last line
    lda curline
    cmp #15
    bcs @atthebottom
    inc curline
    tay
    jsr update_yline
    iny
    jsr update_yline
    bra @keys

@atthebottom:
    ; Scroll another name into view
    lda filewin
    jsr win_scroll
    inc fntoplineidx
    ldy curline
    jsr update_yline
    dey
    jsr update_yline
    bra @keys

@selected:
    lda fntoplineidx
    clc
    adc curline
    sta gREG::r0L
    stz gREG::r0H
    asl gREG::r0L
    rol gREG::r0H
    asl gREG::r0L
    rol gREG::r0H
    lda #<fnlist
    clc
    adc gREG::r0L
    sta gREG::r0L
    lda #>fnlist
    adc gREG::r0H
    sta gREG::r0H
    ldy #1
    lda (gREG::r0)
    sta zpu_mem
    lda (gREG::r0),y
    sta zpu_mem+1
    iny
    lda (gREG::r0),y
    sta zpu_mem+2
    sta VIA1::PRA
    iny
    lda (gREG::r0),y
    sta fnlen
    lda #>filename
    sta gREG::r0H
    lda #<filename
    sta gREG::r0L
    ldy #0
@2: jsr mem_fetch_and_advance
    sta (gREG::r0),y
    iny
    cpy fnlen
    bcc @2
    lda #0
    sta (gREG::r0),y
    rts
.endproc

.proc boxfilewin
    lda filewin
    jsr win_getsize
    txa
    dec
    sta gREG::r7H
    dec
    sta gREG::r6L
    sta gREG::r6H
    tya
    dec
    dec
    sta gREG::r7L
    lda filewin
    ldx #0
    ldy #0
    jsr win_setcursor
    ldx #3
    jsr win_setfont
    ldx #0
    ldy #47
    sec
    jsr win_putchr
    ldy #39
@1: dec gREG::r6L
    bmi @2
    sec
    jsr win_putchr
    bra @1
@2: ldy #48
    sec
    jsr win_putchr
    ldy #13
    sec
    jsr win_putchr
@3: dec gREG::r7L
    bmi @4
    ldy #41
    sec
    jsr win_putchr
    jsr win_getcursor
    ldx gREG::r7H
    jsr win_setcursor
    ldx #0
    ldy #40
    sec
    jsr win_putchr
    ldy #13
    sec
    jsr win_putchr
    bra @3
@4: ldy #46
    sec
    jsr win_putchr
    ldy #38
@5: dec gREG::r6H
    bmi @6
    sec
    jsr win_putchr
    bra @5
@6: ldy #49
    sec
    jsr win_putchr
    ldx #0
    jsr win_setfont
    rts
.endproc

.proc printxy
    sta gREG::r1
    stx gREG::r0H
    sty gREG::r0L
    ldy #0
@1: lda (gREG::r0),y
    beq @2
    phy
    tay
    ldx #0
    lda gREG::r1
    sec
    jsr win_putchr
    ply
    iny
    bne @1
@2: ldx gREG::r0H
    ldy gREG::r0L
    lda gREG::r1
    rts
.endproc

.proc show_loading
    sta fnlen
    stx fnaddr+1
    sty fnaddr
    jsr win_open
    sta filewin
    lda fnlen
    clc
    adc #15
    sta loadwinwidth
    lda #80
    sec
    sbc loadwinwidth
    lsr
    tax
    lda filewin
    ldy #24
    jsr win_setpos
    ldx #0
    ldy #0
    jsr win_setcursor
    jsr win_setwrap
    ldx loadwinwidth
    ldy #3
    jsr win_setsize
    ldx #(COLOR::GRAY1 << 4) + COLOR::WHITE
    jsr win_setcolor
    jsr win_clear
    jsr boxfilewin
    lda filewin
    ldx #2
    ldy #1
    jsr win_setcursor
    ldx #>loading
    ldy #<loading
    jsr printxy
    ldx fnaddr+1
    ldy fnaddr
    jsr printxy
    ldx #>threedots
    ldy #<threedots
    jmp printxy
.endproc

.proc parse_filenames
    stz zpu_mem
    lda #$a0
    sta zpu_mem+1
    lda #1
    sta zpu_mem+2
    sta VIA1::PRA
    lda #>fnlist
    sta zpu_mem_2+1
    lda #<fnlist
    sta zpu_mem_2
    stz fncount

    ; Skip program address
    lda #2
    jsr mem_advance

@check_line:
    ; Check if this is a line
    jsr mem_fetch_and_advance
    tax
    jsr mem_fetch_and_advance
    bne @check_size
    cpx #0
    beq @done

@check_size:
    ; Skip zero-block files
    jsr mem_fetch_and_advance
    tax
    jsr mem_fetch_and_advance
    bne @find_name
    cpx #0
    beq @skip_line

@find_name:
    ; Find the first doublequote (if we hit a NUL, we're at the end of the directory)
    jsr mem_fetch_and_advance
    beq @done
    cmp #$22
    bne @find_name

    ; Save the address of the filename
    ldy #1
    lda zpu_mem
    sta (zpu_mem_2)
    lda zpu_mem+1
    sta (zpu_mem_2),y
    iny
    lda zpu_mem+2
    sta (zpu_mem_2),y
    ldx #0

@find_name_end:
    ; Find the second doublequote
    jsr mem_fetch_and_advance
    cmp #$22
    beq @found_end
    inx
    bra @find_name_end
@found_end:
    txa
    ldy #3
    sta (zpu_mem_2),y

    ; Advance the fnlist pointer to the next entry
    inc fncount
    lda zpu_mem_2
    clc
    adc #4
    sta zpu_mem_2
    lda zpu_mem_2+1
    adc #0
    sta zpu_mem_2+1

@skip_line:
    ; Find the end of the line
    jsr mem_fetch_and_advance
    bne @skip_line
    bra @check_line

@done:
    ; Finished parsing directory
    rts
.endproc

.rodata

zigtitle:   .byte $5a, $69, $67, $67, $75, $72, $61, $74, 0
loading:    .byte $4c, $6f, $61, $64, $69, $6e, $67, $20, 0
directory:  .byte $64, $69, $72, $65, $63, $74, $6f, $72, $79, 0
threedots:  .byte "...", 0
dollar:     .byte "$"
choose:     .byte $43, $68, $6f, $6f, $73, $65, $20, $47, $61, $6d, $65, $3a, 0
zork1:      .byte "zork1.dat", 0
