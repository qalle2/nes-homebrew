    ; value to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; memory-mapped registers
ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_addr   equ $2006
ppu_data   equ $2007
oam_dma    equ $4014

; RAM
FrameLaskuriVarit  equ $0200
FrameLaskuriTeksti equ $0201
direction          equ $0202
temp               equ $0203

; colors
bgcol equ $0f
col1  equ $12
col2  equ $14
col3  equ $16
col4  equ $17
col5  equ $18
col6  equ $19
col7  equ $1a
col8  equ $1c

; Sprite data is on zero page.

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1
    ineschr 0
    inesmir 1
    inesmap 0

; --------------------------------------------------------------------------------------------------

    org $c000
reset:

    lda #$00
    sta ppu_ctrl
    sta ppu_mask

    bit ppu_status
-   bit ppu_status
    bpl -
-   bit ppu_status
    bpl -

    ; CHR RAM
    ldx #0
    stx ppu_addr
    stx ppu_addr
-   lda CHRdata, x
    sta ppu_data
    inx
    bne -
-   lda CHRdata+$100, x
    sta ppu_data
    inx
    cpx #48
    bne -

    ; 1st name table
    lda #$20
    sta ppu_addr
    lda #$00
    sta ppu_addr

    lda #30
    sta temp
--  ldy #4
-   ldx #0
    stx ppu_data
    inx
    stx ppu_data
    inx
    stx ppu_data
    inx
    stx ppu_data
    dey
    bne -
    ldy #4
-   ldx #3
    stx ppu_data
    dex
    stx ppu_data
    dex
    stx ppu_data
    dex
    stx ppu_data
    dey
    bne -
    ldy temp
    dey
    sty temp
    bne --

    ; 1st attribute table
    ldy #8
--  ldx #0
-   lda attr_table_data, x
    sta ppu_data
    inx
    cpx #8
    bne -
    dey
    bne --

    ; 2nd name table
    ldy #0
--  tya
    and #%00000011
    ldx #32
-   sta ppu_data
    dex
    bne -
    iny
    cpy #16
    bne --
    ldy #15
--  tya
    and #%00000011
    ldx #32
-   sta ppu_data
    dex
    bne -
    dey
    cpy #1
    bne --

    ; 2nd attribute table
    ldy #0
--  lda attr_table_data, y
    ldx #8
-   sta ppu_data
    dex
    bne -
    iny
    cpy #8
    bne --

    ; sprite data

    ; tiles
    ldx #0
    ldy #0
-   lda sprite_tiles, y
    sta $01, x
    inx
    inx
    inx
    inx
    iny
    cpy #17
    bne -

    ; attributes
    lda #%00000000
    ldx #0
-   sta $02, x
    inx
    inx
    inx
    inx
    cpx #4*17
    bne -

    ; unused data
    lda #$ff
    ldx #(4 * 17)
-   sta $00, x
    inx
    bne -

    ; sprite palette
    lda #>$3f11
    sta ppu_addr
    lda #<$3f11
    sta ppu_addr
    lda #$0f      ; black
    sta ppu_data

    lda #0
    sta direction
    sta ppu_addr
    sta ppu_addr

    bit ppu_status
-   bit ppu_status
    bpl -

    lda #%10000001
    sta ppu_ctrl
    lda #%00011110
    sta ppu_mask

-   jmp -

; --------------------------------------------------------------------------------------------------

nmi:
    ; FrameLaskuriVarit laskee edestakaisin 0:n ja 255:n v�lill�
    lda direction
    beq Nolla
        ; Yksi
        inc FrameLaskuriVarit
        jmp Muutettu
    Nolla:
        dec FrameLaskuriVarit
    Muutettu:
    bne EiNolla
        lda direction
        eor #%00000001
        sta direction
        EiNolla:

    ; Taustagrafiikkapalettien vaihto
    lda #$3f
    sta ppu_addr
    lda #$00
    sta ppu_addr
    lda FrameLaskuriVarit
    and #%00001110
    asl a
    asl a
    asl a
    tax
    ldy #16
    PalVaihtoSilm:
        lda palettes, x
        sta ppu_data
        inx
        dey
        bne PalVaihtoSilm

    lda #$00
    sta ppu_addr
    sta ppu_addr

    ; Name Tablen valinta
    lda FrameLaskuriVarit
    and #%10000000
    asl a
    rol a
    eor direction
    ora #%10000000
    sta ppu_ctrl

    ; Py�riv� teksti (17 sprite�)
    inc FrameLaskuriTeksti
    ldy FrameLaskuriTeksti   ; spritejen kulmat eli paikat ympyr�n keh�ll�
    ldx #0                   ; silmukkalaskuri
    SprSilm:
        stx temp   ; X talteen

        ; Asetetaan spriten Y-koordinaatti
        txa
        asl a
        asl a
        tax
        lda sine_table, y
        sta $00, x

        ; Lis�t��n kulmaa nelj�nneskierros
        tya
        clc
        adc #$40
        tay

        ; Asetetaan spriten X-koordinaatti
        lda sine_table, y
        clc
        adc #9
        sta $03, x

        ldx temp   ; X takaisin

        ; V�hennet��n kulmaa sen mukaisesti, monennessako spritess� ollaan
        tya
        sec
        sbc angle_changes, x
        tay

        inx
        cpx #17
        bne SprSilm

    lda #$00
    sta oam_dma
    rti

; --------------------------------------------------------------------------------------------------
; Tables

palettes:
    db bgcol,col1,col2,col3, bgcol,col3,col4,col5, bgcol,col5,col6,col7, bgcol,col7,col8,col1
    db bgcol,col2,col3,col4, bgcol,col4,col5,col6, bgcol,col6,col7,col8, bgcol,col8,col1,col2
    db bgcol,col3,col4,col5, bgcol,col5,col6,col7, bgcol,col7,col8,col1, bgcol,col1,col2,col3
    db bgcol,col4,col5,col6, bgcol,col6,col7,col8, bgcol,col8,col1,col2, bgcol,col2,col3,col4
    db bgcol,col5,col6,col7, bgcol,col7,col8,col1, bgcol,col1,col2,col3, bgcol,col3,col4,col5
    db bgcol,col6,col7,col8, bgcol,col8,col1,col2, bgcol,col2,col3,col4, bgcol,col4,col5,col6
    db bgcol,col7,col8,col1, bgcol,col1,col2,col3, bgcol,col3,col4,col5, bgcol,col5,col6,col7
    db bgcol,col8,col1,col2, bgcol,col2,col3,col4, bgcol,col4,col5,col6, bgcol,col6,col7,col8

attr_table_data:
    db %00000000, %01010101, %10101010, %11111111, %11111111, %10101010, %01010101, %00000000

sprite_tiles:
    hex 04 05 06 07 08 09 0a 0b  ; "GRADIENT"
    hex 07 09 0c 0d              ; "DEMO"
    hex 0e 0f                    ; "BY"
    hex 10 11 12                 ; "KHS"

; change of angle after each letter
angle_changes:
    hex 44 44 44 44 44 44 44 48
    hex 44 44 44 48
    hex 44 48
    hex 44 44

sine_table:
    hex 73 75 77 7a 7c 7f 81 84 86 88 8b 8d 90 92 94 96
    hex 99 9b 9d 9f a2 a4 a6 a8 aa ac ae b0 b2 b4 b6 b7
    hex b9 bb bd be c0 c1 c3 c4 c6 c7 c8 ca cb cc cd ce
    hex cf d0 d1 d1 d2 d3 d4 d4 d5 d5 d5 d6 d6 d6 d6 d6
    hex d6 d6 d6 d6 d6 d6 d5 d5 d5 d4 d4 d3 d2 d1 d1 d0
    hex cf ce cd cc cb ca c8 c7 c6 c4 c3 c1 c0 be bd bb
    hex b9 b7 b6 b4 b2 b0 ae ac aa a8 a6 a4 a2 9f 9d 9b
    hex 99 96 94 92 90 8d 8b 88 86 84 81 7f 7c 7a 77 75
    hex 73 70 6e 6b 69 66 64 61 5f 5d 5a 58 55 53 51 4f
    hex 4c 4a 48 46 43 41 3f 3d 3b 39 37 35 33 31 2f 2e
    hex 2c 2a 28 27 25 24 22 21 1f 1e 1d 1b 1a 19 18 17
    hex 16 15 14 14 13 12 11 11 10 10 10 0f 0f 0f 0f 0f
    hex 0f 0f 0f 0f 0f 0f 10 10 10 11 11 12 13 14 14 15
    hex 16 17 18 19 1a 1b 1d 1e 1f 21 22 24 25 27 28 2a
    hex 2c 2e 2f 31 33 35 37 39 3b 3d 3f 41 43 46 48 4a
    hex 4c 4f 51 53 55 58 5a 5d 5f 61 64 66 69 6b 6e 70

; --------------------------------------------------------------------------------------------------
; CHR data

CHRdata:
    hex   ff ff ff ff ff ff ff ff   00 00 00 00 00 00 00 00   ; $00: color 1
    hex   55 aa 55 aa 55 aa 55 aa   aa 55 aa 55 aa 55 aa 55   ; $01: color 1&2 (dithered)
    hex   00 00 00 00 00 00 00 00   ff ff ff ff ff ff ff ff   ; $02: color 2
    hex   aa 55 aa 55 aa 55 aa 55   ff ff ff ff ff ff ff ff   ; $03: color 2&3 (dithered)
    hex   7c c6 c0 ce c6 c6 7e 00   00 00 00 00 00 00 00 00   ; $04: "G"
    hex   fc c6 c6 fc d8 cc c6 00   00 00 00 00 00 00 00 00   ; $05: "R"
    hex   7c c6 c6 fe c6 c6 c6 00   00 00 00 00 00 00 00 00   ; $06: "A"
    hex   fc 66 66 66 66 66 fc 00   00 00 00 00 00 00 00 00   ; $07: "D"
    hex   3c 18 18 18 18 18 3c 00   00 00 00 00 00 00 00 00   ; $08: "I"
    hex   fe 60 60 7e 60 60 fe 00   00 00 00 00 00 00 00 00   ; $09: "E"
    hex   c6 e6 f6 de ce c6 c6 00   00 00 00 00 00 00 00 00   ; $0a: "N"
    hex   7e 18 18 18 18 18 18 00   00 00 00 00 00 00 00 00   ; $0b: "T"
    hex   c6 ee fe d6 c6 c6 c6 00   00 00 00 00 00 00 00 00   ; $0c: "M"
    hex   7c c6 c6 c6 c6 c6 7c 00   00 00 00 00 00 00 00 00   ; $0d: "O"
    hex   fc 66 66 7c 66 66 fc 00   00 00 00 00 00 00 00 00   ; $0e: "B"
    hex   66 66 3c 18 18 18 18 00   00 00 00 00 00 00 00 00   ; $0f: "Y"
    hex   c6 cc d8 f0 d8 cc c6 00   00 00 00 00 00 00 00 00   ; $10: "K"
    hex   c6 c6 c6 fe c6 c6 c6 00   00 00 00 00 00 00 00 00   ; $11: "H"
    hex   7c c6 c0 7c 06 c6 7c 00   00 00 00 00 00 00 00 00   ; $12: "S"

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    dw nmi, reset, $0000
