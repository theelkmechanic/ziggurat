; zzmain.s - Ziggurat launcher with UniLib initialization
;
; Initializes UniLib, draws the title screen, presents a file picker,
; loads the selected game file, and starts the ZPU.
; Uses UniLib directly for all windowing (ulwin_*), file picker
; (ulwin_picklist), and loading messages (ulwin_flash).

.include "ziggurat.inc"
.include "zpu.inc"
.include "unilib.inc"

.import load_file_to_hiram

.segment "EXEHDR"
    ; Stub launcher
    .byte $0b, $08, $b0, $07, $9e, $32, $30, $36, $31, $00, $00, $00
    jmp maincode

.code

maincode:
    ; Clear BSS (not done automatically in assembly mode)
    ; __BSS_RUN__ and __BSS_SIZE__ defined by linker config
    .import __BSS_RUN__, __BSS_SIZE__
    lda #<__BSS_RUN__
    sta gREG::r0L
    lda #>__BSS_RUN__
    sta gREG::r0H
    lda #0
    ldy #0
    ldx #>__BSS_SIZE__      ; number of full pages
    beq @bss_partial
@bss_page:
    sta (gREG::r0),y
    iny
    bne @bss_page
    inc gREG::r0H
    dex
    bne @bss_page
@bss_partial:
    ldx #<__BSS_SIZE__      ; remaining bytes
    beq @bss_done
@bss_tail:
    sta (gREG::r0),y
    iny
    dex
    bne @bss_tail
@bss_done:

    ; Limit UniLib's RAM usage so it doesn't use banks >= ZIF_BASE_BANK.
    ; With -ram 2048, MEMTOP returns 0 (256 wraps). Tell it we only have
    ; ZIF_BASE_BANK banks so UniLib's heap+pools stay below the game data.
    ; CLC = SET mode for MEMTOP (SEC = GET mode).
    lda #ZIF_BASE_BANK      ; $80 = 128 banks available for UniLib
    ldx #0
    ldy #$A0                ; address $A000 (start of banked window)
    clc
    jsr MEMTOP

    ; Initialize UniLib (loads font, sets up VERA, creates window 0)
    ; UniLib will use banks 1 to ~ZIF_BASE_BANK-6 for heap+pools.
    ; NOTE: SEI to prevent KERNAL IRQ from clobbering VERA during setup
    sei
    stz gREG::r0L
    stz gREG::r0H
    stz gREG::r1L       ; r1L=0: use ROM built-in font (no file load)
    lda #8              ; device 8 (unused when r1L=0, but set anyway)
    sta gREG::r1H
    lda #ULCOLOR::LGREY
    sta gREG::r2L
    lda #ULCOLOR::BLACK
    sta gREG::r2H
    jsr ul_init
    cli

    ; Leave window 0 open — it's the screen window, and UniLib's
    ; window map/occlusion system depends on it.

.ifdef QUICK_LOAD
    ; Quick-load: skip title/picklist, load hardcoded game file directly
    ldx #0
@ql_copy:
    lda quick_filename,x
    beq @ql_loaded
    sta filename,x
    inx
    bra @ql_copy
@ql_loaded:
    stx fnlen
    lda #>filename
    sta gREG::r0H
    lda #<filename
    sta gREG::r0L
    lda fnlen
    ldx #8
    jsr load_file_to_hiram
    jmp zpu_start
.endif

    ; Show title screen — open a full-screen window directly via UniLib
    stz gREG::r0L               ; left = 0
    stz gREG::r0H               ; top = 0
    lda #80
    sta gREG::r1L               ; width = 80
    lda #30
    sta gREG::r1H               ; height = 30
    lda #ULCOLOR::DGREY
    sta gREG::r2L               ; foreground
    lda #ULCOLOR::WHITE
    sta gREG::r2H               ; background
    stz gREG::r4L
    stz gREG::r4H               ; no border
    jsr ulwin_open
    sta titlewin
    jsr ulwin_clear
    jsr show_title

    ; Show "Loading directory" flash message
    ldx #>directory
    ldy #<directory
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

    ; Clear window and repaint title (removes flash message artifact)
    lda titlewin
    jsr ulwin_clear
    jsr show_title

    ; Build a stringtable from the parsed filenames
    jsr build_stringtable

    ; Create title string for picker window
    ldx #<choose
    ldy #>choose
    jsr ulstr_fromUtf8
    bcc @got_title
    stz gREG::r3L
    stz gREG::r3H
    bra @open_picker
@got_title:
    stx gREG::r3L
    sty gREG::r3H
    stx pick_title
    sty pick_title+1

@open_picker:
    ; Open bordered picker window directly via UniLib
    ; Border is drawn outside the content area, so offset by 1
    ; to keep border within the cleared title area (cols 56-75, rows 10-24)
    lda #57
    sta gREG::r0L               ; left (border at col 56)
    lda #12
    sta gREG::r0H               ; top (border at row 11)
    lda #19
    sta gREG::r1L               ; width (border adds 2 → 21 total)
    lda #14
    sta gREG::r1H               ; height (border adds 2 → 16 total)
    lda #ULCOLOR::WHITE
    sta gREG::r2L
    lda #ULCOLOR::DGREY
    sta gREG::r2H
    stz gREG::r4L
    lda #ULWIN_FLAGS::BORDER
    sta gREG::r4H
    jsr ulwin_open
    sta filewin_handle

    ; Let user pick a file
@pick_again:
    lda filewin_handle
    ldx strtbl_brp
    ldy strtbl_brp+1
    jsr ulwin_picklist
    ; A = 1-based selection index (0 = cancelled)
    cmp #0
    beq @pick_again
    sta pick_result

    ; Close the picker window
    lda filewin_handle
    jsr ulwin_close
    jsr ulwin_refresh

    ; Free the stringtable
    ldx strtbl_brp
    ldy strtbl_brp+1
    jsr ulstb_delete

    ; Release title string if it was created
    lda pick_title
    ora pick_title+1
    beq @no_rel_title
    ldx pick_title
    ldy pick_title+1
    jsr ulstr_release
@no_rel_title:

    ; Copy selected filename to buffer
    lda pick_result
    dec                         ; convert 1-based to 0-based
    jsr find_fname_addr
    ldy #0
@cpfn:
    jsr mem_fetch_and_advance
    sta filename,y
    iny
    cpy fnlen
    bcc @cpfn
    ; Trim trailing $A0 (PETSCII shifted space padding)
@cpfn_trim:
    dey
    bmi @cpfn_trimmed
    lda filename,y
    cmp #$a0
    beq @cpfn_trim
    iny
@cpfn_trimmed:
    lda #0
    sta filename,y

    ; Repaint title and show "Loading <filename>" flash
    jsr show_title
    ldx #>filename
    ldy #<filename
    jsr show_loading

    ; Reset KERNAL file state (directory load may leave channels dirty)
    jsr CLRCHN
    lda #1
    jsr CLOSE

    ; Load the selected ZIF file
    lda #>filename
    sta gREG::r0H
    lda #<filename
    sta gREG::r0L
    lda fnlen
    ldx #8
    jsr load_file_to_hiram

    ; Close title window before ZPU init creates its own
    lda titlewin
    jsr ulwin_close

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
    jsr ulwin_putcursor
    ldx #>azmachine
    ldy #<azmachine
    jsr printxy
    lda titlewin
    ldx #23
    ldy #17
    jsr ulwin_putcursor
    ldx #>forthex16
    ldy #<forthex16
    jsr printxy
    lda titlewin
    ldx #1
    ldy #28
    jsr ulwin_putcursor
    ldx #>versionstr
    ldy #<versionstr
    jsr printxy
    jmp ulwin_refresh

@goodchunk:
    ; Draw a chunk of graphics
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
    tax
    lda zigbits,x
    tay
    bpl @notblock
    ldx #$25
    .byte $2c
@notblock:
    ldx #0
    lda titlewin
    jsr zmwin_putchr
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
    jsr zmwin_putchr
    ply
    iny
    bne @1
@2: ldx gREG::r0H
    ldy gREG::r0L
    lda gREG::r1
    rts
.endproc

; show_loading - Display a "Loading <name>..." flash message via ulwin_flash
; In: X = name string addr high, Y = name string addr low (NUL-terminated)
.proc show_loading
    stx fnaddr+1
    sty fnaddr

    ; Build "Loading <name>..." in msg_buf
    ldx #0
@prefix:
    lda loading,x
    beq @name
    sta msg_buf,x
    inx
    bra @prefix

@name:
    lda fnaddr
    sta gREG::r5L
    lda fnaddr+1
    sta gREG::r5H
    ldy #0
@name_loop:
    lda (gREG::r5),y
    beq @suffix
    sta msg_buf,x
    inx
    iny
    bra @name_loop

@suffix:
    ldy #0
@suffix_loop:
    lda threedots,y
    sta msg_buf,x
    beq @flash
    inx
    iny
    bra @suffix_loop

@flash:
    ; Create UniLib string from the message
    ldx #<msg_buf
    ldy #>msg_buf
    jsr ulstr_fromUtf8
    bcs @done
    stx gREG::r0L
    sty gREG::r0H
    stz gREG::r1L
    stz gREG::r1H
    ldx #ULCOLOR::WHITE
    ldy #ULCOLOR::DGREY
    jsr ulwin_flash
    ; r0 preserved by ulwin_flash - release the string
    ldx gREG::r0L
    ldy gREG::r0H
    jsr ulstr_release

@done:
    rts
.endproc

; build_stringtable - Create a stringtable from parsed filenames
; Out: carry clear on success (strtbl_brp set), carry set on error
.proc build_stringtable
    lda fncount
    jsr ulstb_create
    bcs @error
    stx strtbl_brp
    sty strtbl_brp+1

    stz pick_idx

@loop:
    lda pick_idx
    cmp fncount
    bcs @done

    ; Get filename address in banked RAM
    jsr find_fname_addr

    ; Copy filename to buffer and NUL-terminate
    ldy #0
@copy:
    jsr mem_fetch_and_advance
    sta filename,y
    iny
    cpy fnlen
    bcc @copy
    ; Trim trailing $A0 (PETSCII shifted space padding)
@trim:
    dey
    bmi @trimmed
    lda filename,y
    cmp #$a0
    beq @trim
    iny                         ; keep the last non-$A0 char
@trimmed:
    lda #0
    sta filename,y

    ; Create UniLib string from filename (PETSCII $20-$5A = ASCII)
    ldx #<filename
    ldy #>filename
    jsr ulstr_fromUtf8
    bcs @skip

    ; Store in stringtable (1-based index)
    stx str_tmp
    sty str_tmp+1
    lda strtbl_brp
    sta gREG::r0L
    lda strtbl_brp+1
    sta gREG::r0H
    lda pick_idx
    inc                         ; convert to 1-based
    ldx str_tmp
    ldy str_tmp+1
    jsr ulstb_put

    ; Release our reference (stringtable has its own)
    ldx str_tmp
    ldy str_tmp+1
    jsr ulstr_release

@skip:
    inc pick_idx
    bra @loop

@done:
    clc
    rts

@error:
    sec
    rts
.endproc

.proc parse_filenames
    stz zpu_mem
    lda #$a0
    sta zpu_mem+1
    lda #ZIF_BASE_BANK
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

.rodata

fontname:       .byte "ZIGGURAT.FNT"
fontname_len = * - fontname

versionstr: .byte $56, $65, $72, $73, $69, $6f, $6e, $20
version:    .byte "0.0.8"
            .byte 0

azmachine:  .byte $41, $20, $5a, "-", $6d, $61, $63, $68, $69, $6e, $65, 0
forthex16:  .byte $66, $6f, $72, $20, $74, $68, $65, $20, $58, "-16!", 0
loading:    .byte $4c, $6f, $61, $64, $69, $6e, $67, $20, 0
directory:  .byte $64, $69, $72, $65, $63, $74, $6f, $72, $79, 0
threedots:  .byte "...", 0
dollar:     .byte "$"
choose:     .byte $43, $68, $6f, $6f, $73, $65, $20, $67, $61, $6d, $65, $3a, 0
.ifdef QUICK_LOAD
quick_filename: .byte "ZORK1.DAT", 0
.endif
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

; =========================================================================
; BSS - Launcher temp variables
; =========================================================================
.bss

titlewin:       .res 1
filewin_handle: .res 1       ; Direct UniLib window handle
fnlen:          .res 1
fnaddr:         .res 2
filename:       .res 33      ; 32 chars + NUL (hostfs names can exceed 16)
fncount:        .res 1
fnlist:         .res 250 * 4 ; 4 bytes per filename entry
strtbl_brp:     .res 2       ; Stringtable BRP for picklist
pick_result:    .res 1       ; Picklist selection (1-based)
pick_title:     .res 2       ; Title string handle
pick_idx:       .res 1       ; Build loop counter
str_tmp:        .res 2       ; Temp string handle
msg_buf:        .res 32      ; Buffer for loading message
chunklen:       .res 1
