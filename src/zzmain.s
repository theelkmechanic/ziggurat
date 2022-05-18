.include "ziggurat.inc"
.include "zpu.inc"

.import load_file_to_hiram, __BSS_RUN__, __BSS_SIZE__

.zeropage

zpu_mem:    .res    3
zpu_mem_2:  .res    3

.segment "EXEHDR"
    ; Stub launcher
    .byte $0b, $08, $b0, $07, $9e, $32, $30, $36, $31, $00, $00, $00
    jmp maincode

.segment "DISPOSE"

need2mb:                jsr PRIMM
                        .asciiz "need 2mb machine"
                        jmp ENTER_BASIC

maincode:
                        ; Zero the BSS
                        lda #<__BSS_RUN__
                        sta gREG::r0L
                        lda #>__BSS_RUN__
                        sta gREG::r0H
                        lda #<__BSS_SIZE__
                        sta gREG::r1L
                        lda #>__BSS_SIZE__
                        sta gREG::r1H
                        lda #0
                        jsr MEMORY_FILL

                        ; Reserve the top 512KB of banked RAM (bail if not 2MB)
                        sec
                        jsr MEMTOP
                        and #$ff
                        bne need2mb
                        sec
                        sbc #64
                        clc
                        jsr MEMTOP

                        ; Print "Loading font..." message
                        ldx #0
:                       lda loadingmsg,x
                        beq :+
                        jsr CHROUT
                        inx
                        bra :-

                        ; Set font name in r0 and length/device in r1
:                       lda #zigfont_end-zigfont
                        sta gREG::r1L
                        lda #8
                        sta gREG::r1H
                        lda #<zigfont
                        sta gREG::r0L
                        lda #>zigfont
                        sta gREG::r0H

                        ; Use white on dark grey by default
                        ldx #ULCOLOR::WHITE
                        stx gREG::r2L
                        ldy #ULCOLOR::DGREY
                        sty gREG::r2H
                        jsr ulwin_errorcfg

                        ; Initialize the Unilib library
                        jsr ul_init

                        ; Show title screen
                        ; Open a full-screen window
                        stz gREG::r0L
                        stz gREG::r0H
                        stz gREG::r3L
                        stz gREG::r3H
                        stz gREG::r4H
                        lda #80
                        sta gREG::r1L
                        lda #30
                        sta gREG::r1H
                        lda #ULCOLOR::DGREY
                        sta gREG::r2L
                        lda #ULCOLOR::WHITE
                        sta gREG::r2H
                        jsr ulwin_open
                        sta titlewin

                        ; Paint the title screen into it
                        jsr show_title

                        ; Show "Loading directory" message
                        ldx #<directory
                        ldy #>directory
                        jsr show_loading
                        jsr ulwin_refresh

                        ; Load the directory into high memory
                        lda #<dollar
                        sta gREG::r0L
                        lda #>dollar
                        sta gREG::r0H
                        lda #1
                        ldx #8
                        jsr load_file_to_hiram

                        ; Save the addresses/lengths of all our filenames
                        jsr parse_filenames

                        ; Close the loading message and repaint the title
                        lda filewin
                        jsr ulwin_close

                        ; Open the file picker window
                        lda #57
                        sta gREG::r0L
                        lda #11
                        sta gREG::r0H
                        lda #18
                        sta gREG::r1L
                        lda #16
                        sta gREG::r1H
                        lda #ULCOLOR::WHITE
                        sta gREG::r2L
                        lda #ULCOLOR::DGREY
                        sta gREG::r2H
                        ldx #<choose
                        ldy #>choose
                        jsr ulstr_fromUtf8
                        stx gREG::r3L
                        sty gREG::r3H
                        lda #ULWIN_FLAGS::BORDER
                        sta gREG::r4H
                        jsr ulwin_open
                        sta filewin
                        jsr ulwin_refresh

                        ; Choose the file to load
                        jsr choose_file

                        ; Close the file picker window, repaint the title screen
                        lda filewin
                        jsr ulwin_close

                        ; Show "Loading filename" message
                        lda fnlen
                        ldx #<filename
                        ldy #>filename
                        jsr show_loading

                        ; Load the ZIF file
                        lda #<filename
                        sta gREG::r0L
                        lda #>filename
                        sta gREG::r0H
                        lda fnlen
                        ldx #8
                        jsr load_file_to_hiram

                        ; Close our windows
                        lda filewin
                        jsr ulwin_close
                        lda titlewin
                        jsr ulwin_close

@loop: bra @loop

                        ; Start the ZPU
;                        jmp zpu_start

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
                        bpl @goodchunk

                        ; Draw title texts
                        lda titlewin
                        ldx #23
                        ldy #16
                        jsr ulwin_putcursor
                        ldx #<azmachine
                        ldy #>azmachine
                        jsr printit
                        ldx #23
                        ldy #17
                        jsr ulwin_putcursor
                        ldx #<forthex16
                        ldy #>forthex16
                        jsr printit
                        ldx #1
                        ldy #28
                        jsr ulwin_putcursor
                        ldx #<versionstr
                        ldy #>versionstr
                        jmp printit

@goodchunk:
                        ; Set the cursor position for this chunk
                        tax
                        jsr mem_fetch_and_advance
                        tay
                        lda titlewin
                        jsr ulwin_putcursor

                        ; Read length
                        jsr mem_fetch_and_advance
                        sta chunklen

                        ; Draw block characters
@draw_next:
                        jsr mem_fetch_and_advance
                        tay
                        lda zigbits,y
                        tax
                        bpl @notblock
                        ldy #$25
                        .byte $2c
@notblock:
                        ldy #0
                        stx gREG::r0L
                        sty gREG::r0H
                        stz gREG::r1L
                        lda titlewin
                        jsr ulwin_putchar
                        dec chunklen
                        bne @draw_next
                        bra @draw_chunk
.endproc

.proc find_fname_brp
                        tya
                        clc
                        adc fntoplineidx
                        asl
                        tax
                        lda #0
                        rol
                        tay
                        txa
                        clc
                        adc #<fnlist
                        sta gREG::r0L
                        tya
                        adc #>fnlist
                        sta gREG::r0H
                        ldy #1
                        lda (gREG::r0)
                        tax
                        lda (gREG::r0),y
                        sta gREG::r0H
                        stx gREG::r0L
                        rts
.endproc

.proc update_yline
                        ; Pick colors based on current selection
                        phy
                        cpy curline
                        bne :+
                        ldx #ULCOLOR::BLACK
                        ldy #ULCOLOR::WHITE
                        bra :++
:                       ldx #ULCOLOR::WHITE
                        ldy #ULCOLOR::DGREY
:                       clc
                        lda filewin
                        jsr ulwin_putcolor

                        ; Erase the line and draw the string one space over
                        ldx #0
                        ply
                        phy
                        jsr ulwin_putcursor
                        jsr ulwin_eraseeol
                        inx
                        jsr ulwin_putcursor

                        ; Get the correct filename from the list and draw it
                        jsr find_fname_brp
                        lda filewin
                        jsr ulwin_putstr
                        ply
                        rts
.endproc

.proc choose_file
                        ; Show first (up to) 16 filenames
                        stz fntoplineidx
                        stz curline
                        ldy fncount
                        dey
                        cpy #15
                        bcc @1
                        ldy #15
@1:                     jsr update_yline
                        dey
                        bpl @1
@refresh:               jsr ulwin_refresh

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
                        bra @refresh

@atthetop:
                        ; Can we scroll more names into view?
                        lda fntoplineidx
                        beq @keys
                        lda filewin
                        ldx #0
                        ldy #1
                        jsr ulwin_scroll
                        dec fntoplineidx
                        ldy #0
                        jsr update_yline
                        iny
                        jsr update_yline
                        bra @refresh

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
                        bra @refresh

@atthebottom:
                        ; Scroll another name into view
                        lda filewin
                        ldx #0
                        ldy #$ff
                        jsr ulwin_scroll
                        inc fntoplineidx
                        ldy curline
                        jsr update_yline
                        dey
                        jsr update_yline
                        bra @refresh

@selected:
                        lda fntoplineidx
                        clc
                        adc curline
                        jsr find_fname_brp
                        lda #>filename
                        sta gREG::r0H
                        lda #<filename
                        sta gREG::r0L
                        ldy #0
@2:                     jsr mem_fetch_and_advance
                        sta (gREG::r0),y
                        iny
                        cpy fnlen
                        bcc @2
                        lda #0
                        sta (gREG::r0),y
                        rts
.endproc

.proc printit
                        stz gREG::r1L
                        stz gREG::r0H
                        stx zpu_mem
                        sty zpu_mem+1
                        sta zpu_mem_2
:                       jsr mem_fetch_and_advance
                        beq :+
                        sta gREG::r0L
                        lda zpu_mem_2
                        sec
                        jsr ulwin_putchar
                        bra :-
:                       lda zpu_mem_2
                        rts
.endproc

.proc show_loading
                        jsr ulstr_fromUtf8
                        stx fnaddr
                        sty fnaddr+1
                        jsr ulstr_getprintlen
                        sta fnlen
                        clc
                        adc #13
                        sta gREG::r1L
                        lda #76
                        sec
                        sbc gREG::r1L
                        sta gREG::r0L
                        lda #27
                        sta gREG::r0H
                        lda #1
                        sta gREG::r1H
                        lda #ULCOLOR::WHITE
                        sta gREG::r2L
                        lda #ULCOLOR::DGREY
                        sta gREG::r2H
                        stz gREG::r3L
                        stz gREG::r3H
                        lda #ULWIN_FLAGS::BORDER
                        sta gREG::r4H
                        jsr ulwin_open
                        sta filewin
                        ldx #1
                        ldy #0
                        jsr ulwin_putcursor
                        ldx #<loading
                        ldy #>loading
                        jsr printit
                        lda fnaddr
                        sta gREG::r0L
                        lda fnaddr+1
                        sta gREG::r0H
                        lda filewin
                        clc
                        jsr ulwin_putstr
                        ldx #<threedots
                        ldy #>threedots
                        lda filewin
                        jmp printit
.endproc

.proc parse_filenames
                        stz zpu_mem
                        lda #$a0
                        sta zpu_mem+1
                        lda #192
                        sta zpu_mem+2
                        sta BANKSEL::RAM
                        lda #<fnlist
                        sta zpu_mem_2
                        lda #>fnlist
                        sta zpu_mem_2+1
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

                        ; Copy the filename to low memory
                        ldx #0
@find_name_end:
                        ; Find the second doublequote
                        jsr mem_fetch_and_advance
                        cmp #$22
                        beq @found_end
                        sta $400,x
                        inx
                        bra @find_name_end

                        ; NUL-terminate, turn into a string, and save to our list
@found_end:
                        stz $400,x
                        ldx #0
                        ldy #4
                        jsr ulstr_fromUtf8
                        txa
                        jsr mem2_store_and_advance
                        tya
                        jsr mem2_store_and_advance
                        inc fncount

@skip_line:
                        ; Find the end of the line
                        lda zpu_mem+2
                        sta BANKSEL::RAM
                        jsr mem_fetch_and_advance
                        bne @skip_line
                        bra @check_count
.endproc

.proc mem_fetch_and_advance
    lda (zpu_mem)
    pha
    inc zpu_mem
    beq mem_advance_finish
    pla
    rts
.endproc

.proc mem_advance
    pha
    clc
    adc zpu_mem
    sta zpu_mem
    bcc mem_advance_skip

    ; FALL THRU INTENTIONAL
.endproc

mem_advance_finish:
    inc zpu_mem+1
    lda zpu_mem+1
    cmp #$c0
    bcc mem_advance_skip
    lda #$a0
    sta zpu_mem+1
    inc zpu_mem+2
    lda zpu_mem+2
    sta BANKSEL::RAM
mem_advance_skip:
    pla
    rts

.proc mem2_store_and_advance
    sta (zpu_mem_2)
    pha
    inc zpu_mem_2
    beq mem2_advance_finish
    pla
    rts
.endproc

.proc mem2_advance
    pha
    clc
    adc zpu_mem_2
    sta zpu_mem_2
    bcc mem2_advance_skip

    ; FALL THRU INTENTIONAL
.endproc

mem2_advance_finish:
    inc zpu_mem_2+1
    lda zpu_mem_2+1
    cmp #$c0
    bcc mem2_advance_skip
    lda #$a0
    sta zpu_mem_2+1
    inc zpu_mem_2+2
    lda zpu_mem_2+2
    sta BANKSEL::RAM
mem2_advance_skip:
    pla
    rts

loadingmsg:     .byte "LOADING "
zigfont:        .byte "ZIGGURAT.FNT"
zigfont_end:    .byte "...", 0
cantloadfont:   .byte "ERROR LOADING FONT!", CH::ENTER, 0

versionstr: .asciiz "Version 0.1.0"

azmachine:  .asciiz "A Z-Machine"
forthex16:  .asciiz "for the X-16!"
loading:    .asciiz "Loading "
directory:  .asciiz "directory"
threedots:  .asciiz "..."
dollar:     .byte "$"
choose:     .asciiz "Choose game:"

titlewin:       .res    1
filewin:        .res    1
loadwinwidth:   .res    1
fnlen:          .res    1
fnaddr:         .res    2
filename:       .res    2
fncount:        .res    1
fntoplineidx:   .res    1
curline:        .res    1
chunklen:       .res    1
fnlist:

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
