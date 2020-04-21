.include "ziggurat.inc"

.import load_zif

.segment "EXEHDR"
    ; Stub launcher
    .byte $0b, $08, $b0, $1f, $9e, $32, $30, $36, $31, $00, $00, $00

.segment "LOWCODE"
    ; Load the specified file into high memory
    lda $0804
    asl
    clc
    adc $0804
    tax
    lda filenames,x
    sta gREG::r0L
    lda filenames+1,x
    sta gREG::r0H
    lda filenames+2,x
    jsr printfn
    ldx #8
    jsr load_zif

    ; Start the ZPU
    jmp zpu_start

printfn:
    sta gREG::r1L
    ldy #0
@1:
    lda (gREG::r0),y
    jsr CHROUT
    iny
    cpy gREG::r1L
    bne @1
    lda #CH::ENTER
    jsr CHROUT
    lda gREG::r1L
    rts

.rodata

fn_test:        .byte   "test.dat",0
fn_amfv:        .byte   "amfv.dat", 0
fn_arthur:      .byte   "arthur.zip", 0
fn_ballyhoo:    .byte   "ballyhoo.dat", 0
fn_beyondzork:  .byte   "beyondzo.dat", 0
fn_borderzone:  .byte   "borderzo.dat", 0
fn_bureaucracy: .byte   "bureaucr.dat", 0
fn_cutthroat:   .byte   "cutthroa.dat", 0
fn_deadline:    .byte   "deadline.dat", 0
fn_enchanter:   .byte   "enchante.dat", 0
fn_hollywood:   .byte   "hollywoo.dat", 0
fn_infidel:     .byte   "infidel.dat", 0
fn_journey:     .byte   "journey.zip", 0
fn_leather:     .byte   "leather.dat", 0
fn_lurking:     .byte   "lurking.dat", 0
fn_moonmist:    .byte   "moonmist.dat", 0
fn_nordandbert: .byte   "nordandb.dat", 0
fn_planetfall:  .byte   "planetfa.dat", 0
fn_plundered:   .byte   "plundere.dat", 0
fn_seastalker:  .byte   "seastalk.dat", 0
fn_sherlock:    .byte   "sherlock.dat", 0
fn_sorceror:    .byte   "sorcerer.dat", 0
fn_spellbreaker: .byte  "spellbre.dat", 0
fn_starcross:   .byte   "starcros.dat", 0
fn_stationfall: .byte   "stationf.dat", 0
fn_suspect:     .byte   "suspect.dat", 0
fn_suspended:   .byte   "suspend.dat", 0
fn_trinity:     .byte   "trinity.dat", 0
fn_wishbringer: .byte   "wishbrin.dat", 0
fn_witness:     .byte   "witness.dat", 0
fn_zork0:       .byte   "zork0.zip", 0
fn_zork1:       .byte   "zork1.dat", 0
fn_zork2:       .byte   "zork2.dat", 0
fn_zork3:       .byte   "zork3.dat", 0

filenames:      .word   fn_test
                .byte   fn_amfv-fn_test-1
                .word   fn_amfv
                .byte   fn_arthur-fn_amfv-1
                .word   fn_arthur
                .byte   fn_ballyhoo-fn_arthur-1
                .word   fn_ballyhoo
                .byte   fn_beyondzork-fn_ballyhoo-1
                .word   fn_beyondzork
                .byte   fn_borderzone-fn_beyondzork-1
                .word   fn_borderzone
                .byte   fn_bureaucracy-fn_borderzone-1
                .word   fn_bureaucracy
                .byte   fn_cutthroat-fn_bureaucracy-1
                .word   fn_cutthroat
                .byte   fn_deadline-fn_cutthroat-1
                .word   fn_deadline
                .byte   fn_enchanter-fn_deadline-1
                .word   fn_enchanter
                .byte   fn_hollywood-fn_enchanter-1
                .word   fn_hollywood
                .byte   fn_infidel-fn_hollywood-1
                .word   fn_infidel
                .byte   fn_journey-fn_infidel-1
                .word   fn_journey
                .byte   fn_leather-fn_journey-1
                .word   fn_leather
                .byte   fn_lurking-fn_leather-1
                .word   fn_lurking
                .byte   fn_moonmist-fn_lurking-1
                .word   fn_moonmist
                .byte   fn_nordandbert-fn_moonmist-1
                .word   fn_nordandbert
                .byte   fn_planetfall-fn_nordandbert-1
                .word   fn_planetfall
                .byte   fn_plundered-fn_planetfall-1
                .word   fn_plundered
                .byte   fn_seastalker-fn_plundered-1
                .word   fn_seastalker
                .byte   fn_sherlock-fn_seastalker-1
                .word   fn_sherlock
                .byte   fn_sorceror-fn_sherlock-1
                .word   fn_sorceror
                .byte   fn_spellbreaker-fn_sorceror-1
                .word   fn_spellbreaker
                .byte   fn_starcross-fn_spellbreaker-1
                .word   fn_starcross
                .byte   fn_stationfall-fn_starcross-1
                .word   fn_stationfall
                .byte   fn_suspect-fn_stationfall-1
                .word   fn_suspect
                .byte   fn_suspended-fn_suspect-1
                .word   fn_suspended
                .byte   fn_trinity-fn_suspended-1
                .word   fn_trinity
                .byte   fn_wishbringer-fn_trinity-1
                .word   fn_wishbringer
                .byte   fn_witness-fn_wishbringer-1
                .word   fn_witness
                .byte   fn_zork0-fn_witness-1
                .word   fn_zork0
                .byte   fn_zork1-fn_zork0-1
                .word   fn_zork1
                .byte   fn_zork2-fn_zork1-1
                .word   fn_zork2
                .byte   fn_zork3-fn_zork2-1
                .word   fn_zork3
                .byte   filenames-fn_zork3-1
