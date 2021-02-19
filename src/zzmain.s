.include "ziggurat.inc"
.include "zpu.inc"

.import load_file_to_hiram

.segment "EXEHDR"
    ; Stub launcher
    .byte $0b, $08, $b0, $07, $9e, $32, $30, $36, $31, $00, $00, $00
    jmp maincode

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
chunklen = $800

.data

maincode:
    ; Initialize our windowing library
    lda #1
    sta BANK_RAM
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
    ldx #(W_WHITE << 4) + W_DGREY
    jsr win_setcolor
    jsr win_clear
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
    ldx #56
    ldy #10
    jsr win_setpos
    ldx #0
    ldy #0
    jsr win_setcursor
    jsr win_setwrap
    ldx #20
    ldy #18
    jsr win_setsize
    ldx #(W_DGREY << 4) + W_WHITE
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
    ; Use zpu_mem because it's easier to scan with
    lda #<zigtitle
    sta zpu_mem
    lda #>zigtitle
    sta zpu_mem+1
    lda #1
    sta zpu_mem+2

@draw_chunk:
    ; Read start x/y and move cursor
    jsr mem_fetch_and_advance
    cmp #$ff
    bne @goodchunk

    ; Draw title texts
    lda titlewin
    ldx #23
    ldy #16
    jsr win_setcursor
    ldx #>azmachine
    ldy #<azmachine
    jsr printxy
    ldx #23
    ldy #17
    jsr win_setcursor
    ldx #>forthex16
    ldy #<forthex16
    jsr printxy
    ldx #1
    ldy #28
    jsr win_setcursor
    ldx #>versionstr
    ldy #<versionstr
    jmp printxy

@goodchunk:
    ; Draw a chunk of graphics
    tax
    jsr mem_fetch_and_advance
    tay
    lda titlewin
    jsr win_setcursor

    ; Read length
    jsr mem_fetch_and_advance
    sta chunklen

    ; Draw block characters
@draw_next:
    jsr mem_fetch_and_advance
    tax
    lda zigbits,x
    tay
    bpl @notblock
    ldx #$25
    .byte $2c
@notblock:
    ldx #0
    lda titlewin
    sec
    jsr win_putchr
    dec chunklen
    bne @draw_next
    bra @draw_chunk
.endproc

.proc find_fname_addr
    phy
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
    sta BANK_RAM
    iny
    lda (gREG::r0),y
    sta fnlen
    ply
    rts
.endproc

.proc update_yline
    ; Check if fntoplineidx + y < count
    phy
    tya
    clc
    adc fntoplineidx
    cmp fncount
    bcs @done

    ; Okay, line should be a valid filename, so find it and print it
    jsr find_fname_addr

    ; Is this the current line
    lda filewin
    ldx #0
    jsr win_setcursor
    cpy curline
    beq @iscurrent
    ldy #' '
    .byte $2c
@iscurrent:
    ldy #34
    ldx #$e0
    sec
    jsr win_putchr

    ; Print the filename followed by enough spaces to clear the remainder of the line
    stz gREG::r0
    ldx #0
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
    stz fntoplineidx
    stz curline
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
    jsr find_fname_addr
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
    ldx #$e0
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
    ldx #0
    ldy #13
    sec
    jsr win_putchr
@3: dec gREG::r7L
    bmi @4
    ldx #$e0
    ldy #41
    sec
    jsr win_putchr
    jsr win_getcursor
    ldx gREG::r7H
    jsr win_setcursor
    ldx #$e0
    ldy #40
    sec
    jsr win_putchr
    ldx #0
    ldy #13
    sec
    jsr win_putchr
    bra @3
@4: ldx #$e0
    ldy #46
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
    lda #76
    sec
    sbc loadwinwidth
    tax
    lda filewin
    ldy #25
    jsr win_setpos
    ldx #0
    ldy #0
    jsr win_setcursor
    jsr win_setwrap
    ldx loadwinwidth
    ldy #3
    jsr win_setsize
    ldx #(W_DGREY << 4) + W_WHITE
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
    sta BANK_RAM
    lda #>fnlist
    sta zpu_mem_2+1
    lda #<fnlist
    sta zpu_mem_2
    stz fncount

    ; Skip program address
    lda #2
    jsr mem_advance

@check_count:
    ; Bail at 250 files since we don't have room for more
    lda fncount
    cmp #250
    bcc @check_line
@done:
    ; Finished parsing directory
    rts

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
    bra @check_count
.endproc

versionstr: .byte $56, $65, $72, $73, $69, $6f, $6e, $20
version:    .byte "0.0.7"
            .byte 0

azmachine:  .byte $41, $20, $5a, "-", $6d, $61, $63, $68, $69, $6e, $65, 0
forthex16:  .byte $66, $6f, $72, $20, $74, $68, $65, $20, $58, "-16!", 0
loading:    .byte $4c, $6f, $61, $64, $69, $6e, $67, $20, 0
directory:  .byte $64, $69, $72, $65, $63, $74, $6f, $72, $79, 0
threedots:  .byte "...", 0
dollar:     .byte "$"
choose:     .byte $43, $68, $6f, $6f, $73, $65, $20, $67, $61, $6d, $65, $3a, 0

zigbits:    .byte $20, $97, $96, $84, $9d, $90, $9e, $9f, $98, $9a, $8c, $99, $80, $9c, $9b, $88

zigtitle:   .byte 72, 0, 5, 1, 3, 3, 3, 3
            .byte 48, 1, 6, 1, 3, 3, 3, 3, 2
            .byte 59, 1, 2, 5, 11
            .byte 64, 1, 15, 1, 15, 12, 12, 12, 12, 12, 12, 12, 15, 14, 0, 15, 3, 2
            .byte 13, 2, 6, 3, 3, 3, 3, 3, 3
            .byte 27, 2, 2, 3, 3
            .byte 34, 2, 45, 3, 3, 3, 3, 2, 0, 1, 3, 3, 7, 15, 14, 12, 15, 15, 8, 0, 0, 4, 12, 15, 3, 0, 0, 1, 15, 13, 15, 2, 0, 5, 15, 0, 3, 0, 1, 3, 7, 15, 15, 10, 1, 15, 15, 10
            .byte 2, 3, 76, 3, 3, 3, 3, 7, 15, 15, 12, 12, 12, 12, 12, 12, 12, 12, 13, 15, 15, 14, 12, 15, 2, 0, 7, 14, 12, 12, 15, 11, 2, 0, 7, 14, 0, 0, 4, 13, 3, 7, 10, 0, 15, 15, 10, 0, 15, 15, 8, 0, 3, 0, 0, 5, 15, 2, 0, 7, 8, 0, 13, 15, 2, 0, 12, 15, 15, 0, 5, 15, 15, 15, 15, 11, 5, 15, 15
            .byte 1, 4, 77, 5, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 15, 15, 10, 0, 15, 15, 15, 14, 0, 0, 0, 0, 13, 15, 7, 14, 0, 0, 0, 0, 1, 15, 15, 10, 0, 15, 15, 10, 0, 15, 15, 0, 5, 15, 15, 0, 0, 15, 15, 7, 14, 5, 11, 4, 15, 15, 0, 0, 12, 15, 0, 5, 15, 15, 0, 1, 15, 13, 15, 15
            .byte 1, 5, 78, 5, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 15, 15, 15, 10, 0, 15, 15, 15, 0, 0, 1, 2, 1, 15, 15, 15, 8, 0, 1, 15, 3, 15, 15, 15, 10, 0, 15, 15, 10, 0, 15, 15, 0, 4, 12, 8, 0, 7, 15, 15, 15, 8, 12, 12, 8, 4, 15, 11, 0, 0, 15, 0, 5, 15, 15, 0, 5, 11, 1, 15, 15, 10
            .byte 1, 6, 77, 5, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 15, 15, 13, 10, 0, 15, 15, 10, 0, 1, 15, 15, 15, 15, 15, 15, 0, 0, 15, 15, 12, 12, 15, 15, 10, 0, 4, 12, 0, 0, 15, 15, 0, 0, 0, 0, 4, 15, 15, 15, 10, 1, 3, 15, 3, 0, 13, 15, 11, 0, 13, 3, 7, 15, 15, 0, 0, 12, 15, 14, 12
            .byte 1, 7, 71, 5, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 15, 15, 14, 5, 10, 0, 15, 15, 10, 0, 4, 15, 11, 0, 0, 15, 15, 0, 0, 4, 12, 8, 0, 15, 15, 11, 0, 0, 0, 0, 5, 15, 15, 0, 5, 15, 15, 0, 5, 15, 15, 3, 7, 15, 15, 15, 15, 15, 15, 15, 8, 0, 4, 12, 12, 8
            .byte 1, 8, 64, 5, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 15, 15, 0, 5, 10, 0, 15, 15, 10, 0, 0, 4, 12, 0, 1, 15, 15, 2, 0, 0, 0, 0, 5, 15, 15, 15, 3, 0, 0, 3, 15, 15, 15, 3, 7, 15, 15, 13, 15, 15, 15, 15, 14, 12, 12, 0, 0, 12, 8
            .byte 1, 9, 56, 5, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 15, 15, 10, 0, 5, 10, 0, 15, 15, 15, 0, 0, 0, 0, 0, 7, 15, 15, 15, 2, 0, 0, 3, 15, 15, 14, 0, 13, 15, 15, 15, 15, 12, 0, 5, 14, 12, 12, 0, 12, 12, 8
            .byte 1, 10, 45, 4, 15, 3, 3, 3, 15, 15, 15, 10, 0, 0, 0, 0, 15, 15, 15, 0, 0, 5, 10, 0, 15, 15, 15, 11, 2, 0, 1, 7, 15, 15, 8, 4, 13, 15, 15, 15, 15, 12, 0, 0, 0, 0, 12, 12
            .byte 3, 11, 35, 13, 15, 14, 12, 13, 15, 8, 0, 0, 0, 1, 15, 15, 10, 0, 0, 5, 11, 3, 15, 15, 10, 4, 13, 15, 15, 15, 12, 8, 0, 0, 0, 4, 12, 8
            .byte 7, 12, 18, 7, 10, 0, 0, 0, 0, 15, 15, 15, 0, 0, 0, 0, 0, 15, 14, 12, 8
            .byte 6, 13, 13, 5, 14, 0, 0, 0, 0, 7, 15, 15, 11, 3, 3, 2
            .byte 5, 14, 15, 1, 15, 8, 0, 0, 0, 0, 15, 15, 12, 12, 8, 5, 11, 3
            .byte 5, 15, 15, 7, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 15, 15
            .byte 4, 16, 16, 1, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 15, 15
            .byte 4, 17, 16, 15, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 15, 15
            .byte 3, 18, 17, 5, 14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 15, 15
            .byte 3, 19, 17, 15, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 15, 15
            .byte 2, 20, 18, 7, 14, 0, 0, 0, 0, 0, 0, 0, 0, 3, 3, 7, 15, 15, 15, 15, 15
            .byte 1, 21, 17, 1, 15, 0, 0, 0, 3, 3, 3, 7, 15, 15, 15, 15, 15, 14, 12, 12
            .byte 1, 22, 12, 5, 15, 3, 15, 15, 15, 15, 15, 15, 12, 12, 12
            .byte 3, 23, 4, 15, 12, 12, 8
            .byte 56, 10, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 11, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 12, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 13, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 14, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 15, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 16, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 17, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 18, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 19, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 20, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 21, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 22, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 23, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 56, 24, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 45, 25, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 45, 26, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte 45, 27, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            .byte $ff
