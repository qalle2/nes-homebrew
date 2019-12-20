; The clock has been centered by scrolling the screen both horizontally and vertically to make it
; fit on one name table page.

    ; byte to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory space

numbers            equ $00  ; ajan numerot (7 tavua)
hour_tens          equ $00  ; tunnin/minuutin/sekunnin kymmenet/ykköset
hour_ones          equ $01
minute_tens        equ $02
minute_ones        equ $03
second_tens        equ $04
second_ones        equ $05
frame              equ $06
mode               equ $07  ; ohjelman tila (0 = ajan asetus, 1 = kello käynnissä)
KursSij            equ $08  ; kursorin sijainti ajanasetustilassa
joypad_status      equ $09  ; peliohjaimen tila
prev_joypad_status equ $0a  ; edellinen peliohjaimen tila
SamSegNak          equ $0b  ; näytetäänkö sammuksissa olevat segmentit (0 = ei, 1 = kyllä)
pal_timing         equ $0c  ; 0 = NTSC-kone, 1 = PAL-kone
temp               equ $0d

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_scroll equ $2005
ppu_addr   equ $2006
ppu_data   equ $2007
joypad1    equ $4016

; PPU memory space

vram_name_table0 equ $2000
vram_palette     equ $3f00

; non-address constants

black  equ $0f
yellow equ $28

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

    org $C000
reset:

    lda #%00000000
    sta ppu_ctrl
    sta ppu_mask

    bit ppu_status
-   lda ppu_status
    bpl -
-   lda ppu_status
    bpl -

    ; palette
    lda #>vram_palette
    sta ppu_addr
    lda #<vram_palette
    sta ppu_addr
    lda #black
    sta ppu_data
    sta ppu_data
    lda #yellow
    sta ppu_data

    ; copy CHR data to CHR RAM (3 * 256 bytes)
    ldx #$00
    stx ppu_addr
    stx ppu_addr
-   lda chr_data, x
    sta ppu_data
    inx
    bne -
-   lda chr_data + $100, x
    sta ppu_data
    inx
    bne -
-   lda chr_data + $200, x
    sta ppu_data
    inx
    bne -

    ; name table and attribute table (clear 4 * 256 bytes)
    lda #>vram_name_table0
    sta ppu_addr
    lda #$00
    sta ppu_addr
    tax
-   sta ppu_data
    sta ppu_data
    sta ppu_data
    sta ppu_data
    inx
    bne -

    ; colons (tiles $01 $02, $01 $02, $03 $04, $03 $04)
    ldx #0
-   lda #>(vram_name_table0 + 8 * 32)
    sta ppu_addr
    lda colon_addresses_low, x
    sta ppu_addr
    txa
    and #%00000010
    ora #%00000001
    tay
    sty ppu_data
    iny
    sty ppu_data
    inx
    cpx #4
    bne -

    ; clear zero page
    lda #$00
    tax
-   sta $00, x
    inx
    bne -

    ; enable square 1
    lda #%00000001
    sta $4015

    ldx #0
    jsr NaytaNuoli
    jsr TulostaNTSCPAL
    jsr PaivitaNumerot

    bit ppu_status
-   lda ppu_status
    bpl -

    ; enable NMI
    lda #%10000000
    sta ppu_ctrl

    ; show background
    lda #%00001010
    sta ppu_mask

-   jmp -

; --------------------------------------------------------------------------------------------------
; Non-maskable interrupt routine

nmi:
    ; TODO: clean up & translate the rest of the program

    lda mode
    beq AjanSaato
    jmp KelloKaynnissa

    AjanSaato:
        ; Luetaan peliohjaimen tila A:han ja X:ään.
        ; Bitit: A, B, select, start, ylä, ala, vasen, oikea.
        ldx #1
        stx joypad1
        dex
        stx joypad1
        ldy #8
        OhjainLukuSilm:
            lda joypad1
            ror
            txa
            rol
            tax
            dey
            bne OhjainLukuSilm
        sta joypad_status

        ; Reagoidaan nappeihin, jos edellisellä framella ei ole painettu mitään

        ldx prev_joypad_status
        beq Jatka1
        jmp Pois
        Jatka1:

        lsr
        bcs Oikea
        lsr
        bcs Vasen
        lsr
        bcs Ala
        lsr
        bcs Yla
        lsr
        bcs Start
        lsr
        lsr
        bcc EiBnappi
            jmp Bnappi
            EiBnappi:
        lsr
        bcc EiAnappi
            jmp Anappi
            EiAnappi:
        jmp Pois

        Oikea:
            ldx KursSij
            jsr PiilotaNuoli
            inx
            cpx #6
            bne EiNollata1
                ldx #0
                EiNollata1:
            stx KursSij
            jsr NaytaNuoli
            jmp Pois
        Vasen:
            ldx KursSij
            jsr PiilotaNuoli
            dex
            bpl EiNollata2
                ldx #5
                EiNollata2:
            stx KursSij
            jsr NaytaNuoli
            jmp Pois
        Ala:
            ldx KursSij
            lda NumYlarajat, x
            sta temp
            ldy numbers, x
            dey
            bpl EiNollata3
                ldy temp
                dey
                EiNollata3:
            sty numbers, x
            jmp Pois
        Yla:
            ldx KursSij
            lda NumYlarajat, x
            sta temp
            ldy numbers, x
            iny
            cpy temp
            bne EiNollata4
                ldy #0
                EiNollata4:
            sty numbers, x
            jmp Pois
        Start:
            ; Käynnistetään kello, jos tunti on enintään 23
            lda hour_tens
            cmp #2
            bcc Jatka2
            lda hour_ones
            cmp #4
            bcc Jatka2
                ; Ääniefekti
                lda #%10011111
                sta $4000
                lda #%00001000
                sta $4001
                lda #%11111111
                sta $4002
                lda #%10111111
                sta $4003
                jmp Pois
            Jatka2:
                ; NTSC-/PAL-teksti pois
                lda #$21
                sta ppu_addr
                lda #$46
                sta ppu_addr
                lda #$00
                ldx #4
                TyhjSilm2:
                    sta ppu_data
                    dex
                    bne TyhjSilm2
                ldx KursSij
                jsr PiilotaNuoli
                inc mode
                jmp Pois
        Bnappi:
            ; Sammuksissa olevat segmentit piiloon/näkyviin
            lda SamSegNak
            eor #%00000001
            sta SamSegNak
            tax
            lda #$3F
            sta ppu_addr
            lda #$01
            sta ppu_addr
            lda SegVarit, x
            sta ppu_data
            jmp Pois
        Anappi:
            ; NTSC-/PAL-tila
            lda pal_timing
            eor #%00000001
            sta pal_timing
            jsr TulostaNTSCPAL
        Pois:
        lda joypad_status
        sta prev_joypad_status
        jsr PaivitaNumerot
        rti

    KelloKaynnissa:
        jsr PaivitaNumerot

        ; Määritetään sekunnin pituus frameina.
        ; Tarkat taajuudet NESDev Wikistä: NTSC 60,0988 Hz; PAL 50,007 Hz.
        ; Tässä ohjelmassa:
        ; NTSC: 60 framea, paitsi joka 10.  sekunti 61 framea (= 60,1 framea/s, virhe 1/50000)
        ; PAL:  50 framea, paitsi joka 120. sekunti 51 framea (= 50,0083 framea/s, virhe 1/38000)
        db $ad  ; LDA absolute (forgot to use zero page addressing mode here)
        dw pal_timing
        bne PAL
            ; NTSC
            lda #60
            sta temp
            lda second_ones
            bne SekPituusOK
                inc temp
                jmp SekPituusOK
        PAL:
            lda #50
            sta temp
            lda minute_ones
            and #%00000001
            ora second_tens
            ora second_ones
            bne SekPituusOK
                inc temp
        SekPituusOK:

        ; Suurennetaan ajan numeroita
        inc frame
        lda frame
        cmp temp
        bne EiNollata5
            lda #0
            sta frame
            ldx second_ones
            lda SeurNum10, x
            sta second_ones
            bne EiNollata5
                ldx second_tens
                lda SeurNum6, x
                sta second_tens
                bne EiNollata5
                    ldx minute_ones
                    lda SeurNum10, x
                    sta minute_ones
                    bne EiNollata5
                        ldx minute_tens
                        lda SeurNum6, x
                        sta minute_tens
                        bne EiNollata5
                            ldx hour_ones
                            lda hour_tens
                            cmp #2
                            beq Kaksi
                                lda SeurNum10, x
                                jmp Tehty
                            Kaksi:
                                lda SeurNum4, x
                                Tehty:
                            sta hour_ones
                            bne EiNollata5
                                ldx hour_tens
                                lda SeurNum3, x
                                sta hour_tens
                                EiNollata5:
    rti

; --------------------------------------------------------------------------------------------------
; Subroutines

NaytaNuoli:
    lda #$22
    sta ppu_addr
    lda NuoliOs, x
    sta ppu_addr
    lda #$05
    sta ppu_data
    lda #$06
    sta ppu_data
    rts

PiilotaNuoli:
    lda #$22
    sta ppu_addr
    lda NuoliOs, x
    sta ppu_addr
    lda #$00
    sta ppu_data
    sta ppu_data
    rts

TulostaNTSCPAL:
    lda pal_timing
    asl
    asl
    tax
    lda #$21
    sta ppu_addr
    lda #$46
    sta ppu_addr
    ldy #4
    NTSCPALsilm:
        lda NTSCPALteksti, x
        sta ppu_data
        inx
        dey
        bne NTSCPALsilm
    rts

PaivitaNumerot:
    ; Päivitetään numerot merkkipari (24 kpl) kerrallaan, nollataan PPU-osoite ja asetetaan
    ; vieritysarvo

    ldy #23
    SegSilm:
        lda #$21
        sta ppu_addr
        lda SegOs, y
        sta ppu_addr

        ; Monennessako numerossa ollaan
        tya
        lsr
        lsr
        tax

        ; Numeron arvon sijainti SegTilat-taulukossa
        lda numbers, x
        rept 3
            asl
        endr
        sta temp

        ; Tarkka sijainti SegTilat-taulukossa
        tya
        and #%00000011
        asl
        adc temp
        tax

        lda SegTilat, x
        sta ppu_data
        lda SegTilat+1, x
        sta ppu_data

        dey
        bpl SegSilm

    lda #$00
    sta ppu_addr
    sta ppu_addr
    lda #256-4
    sta ppu_scroll
    lda #256-8
    sta ppu_scroll
    rts

; --------------------------------------------------------------------------------------------------
; Tables

colon_addresses_low:
    db 5 * 32 + 11
    db 5 * 32 + 18
    db 6 * 32 + 11
    db 6 * 32 + 18
NuoliOs:
    db $26, $29, $2d, $30, $34, $37
NTSCPALteksti:
    hex 07 08 09 0a  ; "NTSC"
    hex 0b 0c 0d 00  ; "PAL "

NumYlarajat:
    db 3, 10, 6, 10, 6, 10
SeurNum3:
    db 1, 2, 0
SeurNum4:
    db 1, 2, 3, 0
SeurNum6:
    db 1, 2, 3, 4, 5, 0
SeurNum10:
    db 1, 2, 3, 4, 5, 6, 7, 8, 9, 0

SegVarit:
    db $0f, $0c

SegOs:
    db $86,$a6,$c6,$e6   ; tuntien kymmenet
    db $89,$a9,$c9,$e9   ; tuntien ykköset
    db $8d,$ad,$cd,$ed   ; minuuttien kymmenet
    db $90,$b0,$d0,$f0   ; minuuttien ykköset
    db $94,$b4,$d4,$f4   ; sekuntien kymmenet
    db $97,$b7,$d7,$f7   ; sekuntien ykköset

SegTilat:
    hex 13 17 1a 1d 22 25 2b 2f   ; "0"
    hex 10 15 18 1d 20 25 28 2d   ; "1"
    hex 11 17 19 1f 23 26 2b 2e   ; "2"
    hex 11 17 19 1f 21 27 29 2f   ; "3"
    hex 12 15 1b 1f 21 27 28 2d   ; "4"
    hex 13 16 1b 1e 21 27 29 2f   ; "5"
    hex 13 16 1b 1e 23 27 2b 2f   ; "6"
    hex 13 17 1a 1d 20 25 28 2d   ; "7"
    hex 13 17 1b 1f 23 27 2b 2f   ; "8"
    hex 13 17 1b 1f 21 27 29 2f   ; "9"

chr_data:
    ; characters $00-$0d
    hex 00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  ; $00: blank
    hex 00 00 00 00 00 00 00 00  00 03 03 03 03 00 00 00  ; $01: part of colon
    hex 00 00 00 00 00 00 00 00  00 c0 c0 c0 c0 00 00 00  ; $02: part of colon
    hex 00 00 00 00 00 00 00 00  00 00 00 03 03 03 03 00  ; $03: part of colon
    hex 00 00 00 00 00 00 00 00  00 00 00 c0 c0 c0 c0 00  ; $04: part of colon
    hex 00 00 00 00 00 00 00 00  01 03 07 0d 01 01 01 01  ; $05: left  half of up arrow
    hex 00 00 00 00 00 00 00 00  80 c0 e0 b0 80 80 80 80  ; $06: right half of up arrow
    hex 00 00 00 00 00 00 00 00  c6 e6 f6 de ce c6 c6 00  ; $07: "N"
    hex 00 00 00 00 00 00 00 00  7e 18 18 18 18 18 18 00  ; $08: "T"
    hex 00 00 00 00 00 00 00 00  7c c6 c0 7c 06 c6 7c 00  ; $09: "S"
    hex 00 00 00 00 00 00 00 00  7c c6 c0 c0 c0 c6 7c 00  ; $0a: "C"
    hex 00 00 00 00 00 00 00 00  fc c6 c6 fc c0 c0 c0 00  ; $0b: "P"
    hex 00 00 00 00 00 00 00 00  7c c6 c6 fe c6 c6 c6 00  ; $0c: "A"
    hex 00 00 00 00 00 00 00 00  c0 c0 c0 c0 c0 c0 fe 00  ; $0d: "L"

    ; characters $10-$3f: segments
    pad chr_data + $10 * 16, $00
    hex 0f 1f 1f 6f f0 f0 f0 f0  00 00 00 00 00 00 00 00
    hex 00 00 00 60 f0 f0 f0 f0  0f 1f 1f 0f 00 00 00 00
    hex 0f 1f 1f 0f 00 00 00 00  00 00 00 60 f0 f0 f0 f0
    hex 00 00 00 00 00 00 00 00  0f 1f 1f 6f f0 f0 f0 f0
    hex f0 f8 f8 f6 0f 0f 0f 0f  00 00 00 00 00 00 00 00
    hex f0 f8 f8 f0 00 00 00 00  00 00 00 06 0f 0f 0f 0f
    hex 00 00 00 06 0f 0f 0f 0f  f0 f8 f8 f0 00 00 00 00
    hex 00 00 00 00 00 00 00 00  f0 f8 f8 f6 0f 0f 0f 0f
    hex f0 f0 f0 f0 f0 f0 6f 1f  00 00 00 00 00 00 00 00
    hex f0 f0 f0 f0 f0 f0 60 00  00 00 00 00 00 00 0f 1f
    hex 00 00 00 00 00 00 0f 1f  f0 f0 f0 f0 f0 f0 60 00
    hex 00 00 00 00 00 00 00 00  f0 f0 f0 f0 f0 f0 6f 1f
    hex 0f 0f 0f 0f 0f 0f f6 f8  00 00 00 00 00 00 00 00
    hex 00 00 00 00 00 00 f0 f8  0f 0f 0f 0f 0f 0f 06 00
    hex 0f 0f 0f 0f 0f 0f 06 00  00 00 00 00 00 00 f0 f8
    hex 00 00 00 00 00 00 00 00  0f 0f 0f 0f 0f 0f f6 f8
    hex 1f 6f f0 f0 f0 f0 f0 f0  00 00 00 00 00 00 00 00
    hex 00 60 f0 f0 f0 f0 f0 f0  1f 0f 00 00 00 00 00 00
    hex 1f 0f 00 00 00 00 00 00  00 60 f0 f0 f0 f0 f0 f0
    hex 00 00 00 00 00 00 00 00  1f 6f f0 f0 f0 f0 f0 f0
    hex f8 f6 0f 0f 0f 0f 0f 0f  00 00 00 00 00 00 00 00
    hex f8 f0 00 00 00 00 00 00  00 06 0f 0f 0f 0f 0f 0f
    hex 00 06 0f 0f 0f 0f 0f 0f  f8 f0 00 00 00 00 00 00
    hex 00 00 00 00 00 00 00 00  f8 f6 0f 0f 0f 0f 0f 0f
    hex f0 f0 f0 f0 6f 1f 1f 0f  00 00 00 00 00 00 00 00
    hex f0 f0 f0 f0 60 00 00 00  00 00 00 00 0f 1f 1f 0f
    hex 00 00 00 00 0f 1f 1f 0f  f0 f0 f0 f0 60 00 00 00
    hex 00 00 00 00 00 00 00 00  f0 f0 f0 f0 6f 1f 1f 0f
    hex 0f 0f 0f 0f f6 f8 f8 f0  00 00 00 00 00 00 00 00
    hex 00 00 00 00 f0 f8 f8 f0  0f 0f 0f 0f 06 00 00 00
    hex 0f 0f 0f 0f 06 00 00 00  00 00 00 00 f0 f8 f8 f0
    hex 00 00 00 00 00 00 00 00  0f 0f 0f 0f f6 f8 f8 f0

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    org $fffa
    dw nmi, reset, 0
