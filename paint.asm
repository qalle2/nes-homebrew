    ; byte to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory space

mode               equ $00   ; 0 = paint mode, 1 = palette edit mode
joypad_status      equ $01
prev_joypad_status equ $02   ; previous joypad status
delay_left         equ $03   ; cursor move delay left
cursor_type        equ $04   ; 0 = arrow, 1 = square
cursor_x           equ $05   ; cursor X position (in paint mode; 0-63)
cursor_y           equ $06   ; cursor Y position (in paint mode; 0-47)
color              equ $07   ; selected color (0-3)
user_palette       equ $08   ; 4 bytes, each $00-$3f
palette_cursor     equ $0c   ; cursor position in palette edit mode (0-3)
vram_address       equ $0d   ; 2 bytes
pointer            equ $0f   ; 2 bytes

sprite_data equ $0200  ; 256 bytes

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_addr   equ $2006
ppu_data   equ $2007
oam_dma    equ $4014
joypad1    equ $4016

; PPU memory space
vram_name_table0 equ $2000
vram_palette     equ $3f00

; non-address constants

button_a      = 1 << 7
button_b      = 1 << 6
button_select = 1 << 5
button_start  = 1 << 4
button_up     = 1 << 3
button_down   = 1 << 2
button_left   = 1 << 1
button_right  = 1 << 0

black  equ $0f
white  equ $30
red    equ $16
yellow equ $28
olive  equ $18
green  equ $1a
blue   equ $02
purple equ $04

cursor_move_delay equ 10

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

    org $c000
reset:
    ; note: I could do the initialization better nowadays (see "init code" in NESDev Wiki), but
    ; I want to keep this binary identical to the old one

    ; disable NMI, hide background&sprites
    lda #$00
    sta ppu_ctrl
    sta ppu_mask

    ; clear zero page
    tax
-   sta $00, x
    inx
    bne -

    ; wait for start of VBlank, then wait for another VBlank
    bit ppu_status
-   bit ppu_status
    bpl -
-   bit ppu_status
    bpl -

    ; palette
    lda #>vram_palette
    ldx #<vram_palette
    jsr set_vram_address
-   lda initial_palette, x
    sta ppu_data
    inx
    cpx #32
    bne -

    ; First half of CHR RAM (background).
    ; Contains all combinations of 2*2 subpixels * 4 colors.
    ; Bits of tile index: AaBbCcDd
    ; Corresponding subpixel colors (capital letter = MSB, small letter = LSB):
    ; Aa Bb
    ; Cc Dd
    jsr reset_vram_address
    ldy #15
--  ldx #15
-   lda background_chr_data1, y
    jsr print_four_times
    lda background_chr_data1, x
    jsr print_four_times
    lda background_chr_data2, y
    jsr print_four_times
    lda background_chr_data2, x
    jsr print_four_times
    dex
    bpl -
    dey
    bpl --

    ; second half of CHR RAM (sprites)
    lda #>sprite_chr_data
    sta pointer + 1
    ldy #$00
    sty pointer + 0
-   lda (pointer), y
    sta ppu_data
    iny
    bne -
    ; change most significant byte of address
    inc pointer + 1
    lda pointer + 1
    cmp #((>sprite_chr_data) + 16)
    bne -

    ; name table
    lda #>vram_name_table0
    ldx #<vram_name_table0
    jsr set_vram_address
    ; top bar (4 rows)
    lda #%01010101  ; block of color 1
    ldx #32
    jsr print_repeatedly
    ldx #0
-   lda logo, x
    sta ppu_data
    inx
    cpx #(3 * 32)
    bne -
    ; paint area (24 rows)
    lda #$00
    ldx #(6 * 32)
-   jsr print_four_times
    dex
    bne -
    ; bottom bar (2 rows)
    lda #%01010101  ; block of color 1
    ldx #64
    jsr print_repeatedly

    ; attribute table
    ; top bar
    lda #%01010101
    ldx #8
    jsr print_repeatedly
    ; paint area
    lda #%00000000
    ldx #(6 * 8)
    jsr print_repeatedly
    ; bottom bar
    lda #%00000101
    sta ppu_data
    sta ppu_data
    ldx #%00000100
    stx ppu_data
    ldx #5
    jsr print_repeatedly

    ; user palette
    ldx #3
-   lda initial_palette, x
    sta user_palette, x
    dex
    bpl -

    ; default color: 1
    inc color

    ; paint mode sprites
    ldx #(paint_mode_sprites_end - paint_mode_sprites - 1)
-   lda paint_mode_sprites, x
    sta sprite_data, x
    dex
    bpl -
    ; hide other sprites
    lda #$ff
    ldx #(paint_mode_sprites_end - paint_mode_sprites)
-   sta sprite_data, x
    inx
    bne -

    lda #button_select
    sta prev_joypad_status

    jsr reset_vram_address

    ; wait for start of VBlank
    bit ppu_status
-   bit ppu_status
    bpl -

    ; enable NMI, use pattern table 1 for sprites
    lda #%10001000
    sta ppu_ctrl

    ; show background&sprites
    lda #%00011110
    sta ppu_mask

-   jmp -

; --------------------------------------------------------------------------------------------------

nmi:
    jsr read_joypad
    sta joypad_status

    ; TODO: tidy up & translate from here on

    lda mode
    bne NMI_paletinvalintatila
    jmp NMI_piirtotila

    NMI_paletinvalintatila:
        ldx palette_cursor
        ldy user_palette, x

        ; Luetaan napit vain, jos edellisella framella ei ole painettu mitaan
        lda prev_joypad_status
        bne EiLuetaNappeja1
            lda joypad_status
            cmp #button_up
            beq KursoriYlos
            cmp #button_down
            beq KursoriAlas
            cmp #button_left
            beq PienennaVariaVahan
            cmp #button_right
            beq SuurennaVariaVahan
            cmp #button_b
            beq PienennaVariaPaljon
            cmp #button_a
            beq SuurennaVariaPaljon
            cmp #button_select
            beq TakaisinPiirtotilaan
            jmp EiLuetaNappeja1

            KursoriYlos:
                dex
                dex
            KursoriAlas:
                inx
                txa
                and #%00000011
                sta palette_cursor
                tax
                jmp EiLuetaNappeja1

            PienennaVariaVahan:
                dey
                dey
            SuurennaVariaVahan:
                iny
                tya
                and #%00111111
                sta user_palette, x
                jmp EiLuetaNappeja1

            PienennaVariaPaljon:
                tya
                sbc #$10
                jmp Pienennetty
            SuurennaVariaPaljon:
                tya
                adc #$0F
                Pienennetty:
                and #%00111111
                sta user_palette, x
                jmp EiLuetaNappeja1

            TakaisinPiirtotilaan:
                ; Paletinvalintaruutu piiloon
                lda #$FF
                ldx #PALVALSPRTAVUJA - 1
                PalValPiilSilm:
                    sta sprite_data + TAVSPRTAVUJA, x
                    dex
                    bpl PalValPiilSilm
                inx
                stx mode
                jmp PoistuNMIsta

            EiLuetaNappeja1:

        ; Kursorin Y-koordinaatti
        txa
        rept 3
            asl
        endr
        adc #$AF
        sta sprite_data + TAVSPRTAVUJA

        ; Vasen varinumero
        lda user_palette, x
        rept 4
            lsr
        endr
        clc
        adc #$10
        sta sprite_data + TAVSPRTAVUJA + 5 * 4 + 1

        ; Oikea varinumero
        lda user_palette, x
        and #%00001111
        clc
        adc #$10
        sta sprite_data + TAVSPRTAVUJA + 6 * 4 + 1

        ; Paivitetaan valittuna oleva vari paletteihin
        lda #$3F
        jsr set_vram_address
        ldy user_palette, x
        sty ppu_data
        sta ppu_addr
        lda SprPalTaul, x
        sta ppu_addr
        sty ppu_data
        jsr reset_vram_address
        jmp PoistuNMIsta

    NMI_piirtotila:
        ; Select, start ja B luetaan vain, jos edellisella framella ei ole painettu mitaan niista
        lda prev_joypad_status
        and #button_b|button_select|button_start
        bne EiLuetaNappeja2
            lda joypad_status
            and #button_b|button_select|button_start
            cmp #button_select
            beq Paletinvalintatilaan
            cmp #button_start
            beq KursorityypinVaihto
            cmp #button_b
            beq PiirtovarinVaihto
            jmp EiLuetaNappeja2

            Paletinvalintatilaan:
                ldx #PALVALSPRTAVUJA - 1
                PalValEsiinSilm:
                    lda PalValSpritet, x
                    sta sprite_data + TAVSPRTAVUJA, x
                    dex
                    bpl PalValEsiinSilm
                lda #$FF
                sta sprite_data   ; piirtokursori piiloon
                lda #1
                sta mode
                lda #0
                sta palette_cursor
                jmp PoistuNMIsta

            KursorityypinVaihto:
                lda cursor_type
                eor #%00000001
                sta cursor_type
                beq EiKoordinaattejaParillisiksi
                    lda cursor_x
                    and #%00111110
                    sta cursor_x
                    lda cursor_y
                    and #%00111110
                    sta cursor_y
                    EiKoordinaattejaParillisiksi:
                jmp EiLuetaNappeja2

            PiirtovarinVaihto:
                ldx color
                inx
                txa
                and #%00000011
                sta color

            EiLuetaNappeja2:

        ; Saako kayttaja siirtaa kursoria
        dec delay_left
        bpl KursoriaEiSaaSiirtaa

        ; Vasen ja oikea nuoli
        lda joypad_status
        and #button_left|button_right
        tax
        lda cursor_x
        cpx #button_left
        beq Vasen
        cpx #button_right
        beq Oikea
        jmp EiVasenOikea
        Vasen:
            clc
            sbc cursor_type
            jmp EiVasenOikea
        Oikea:
            adc cursor_type
            EiVasenOikea:
        and #%00111111
        sta cursor_x

        ; Yla- ja alanuoli
        lda joypad_status
        and #button_up|button_down
        tax
        lda cursor_y
        cpx #button_up
        beq Yla
        cpx #button_down
        beq Ala
        jmp EiYlaAla
        Yla:
            clc
            sbc cursor_type
            bpl EiTaysille
                lda #48
                sbc cursor_type
                EiTaysille:
            jmp EiYlaAla
        Ala:
            adc cursor_type
            cmp #48
            bne EiNollaan
                lda #0
                EiNollaan:
            EiYlaAla:
        and #%00111111
        sta cursor_y

        ; Asetetaan viive uudelleen
        lda #cursor_move_delay
        sta delay_left

        KursoriaEiSaaSiirtaa:

        ; Jos ei paineta nuolta, nollataan kursorinsiirtoviive
        lda joypad_status
        and #button_up|button_down|button_left|button_right
        bne PainettuNuolta
            sta delay_left
            PainettuNuolta:

        ; Piirto: jos painettu A:ta, muutetaan yksi nayttomuistin tavu.
        ; Alue: $2080 - $237F (768 tavua).

        lda joypad_status
        and #button_a
        beq EiPainettuA

        ; Osoitteen enemman merkitseva tavu
        lda cursor_y
        rept 3
            lsr
        endr
        tax
        lda NayMuiOsMuunnosH, x
        sta vram_address + 1

        ; Osoitteen vahemman merkitseva tavu
        lda cursor_y
        and #%00001110
        lsr
        tax
        lda cursor_x
        lsr
        ora NayMuiOsMuunnosL, x
        sta vram_address + 0

        ; Muodostetaan tavulle uusi arvo
        lda cursor_type
        beq PieniKursori
            ; Iso kursori
            ldx color
            lda PiirtovariIlmaisimet, x
            jmp UusiArvoLuotu
        PieniKursori:
            ; X = sijainti 8 * 8 pikselin palan sisalla (0 - 3)
            lda cursor_x
            ror
            lda cursor_y
            rol
            and #%00000011
            tax
            ; Y = sijainti * 4 + piirtovari
            asl
            asl
            ora color
            tay
            ; Luetaan vanha arvo ja tehdaan muutokset siihen
            lda vram_address + 1
            sta ppu_addr
            lda vram_address + 0
            sta ppu_addr
            lda ppu_data
            lda ppu_data
            and PalaAndArvot, x
            ora PalaOrArvot, y
        UusiArvoLuotu:

        ; Kirjoitetaan uusi arvo
        ldx vram_address + 1
        stx ppu_addr
        ldx vram_address + 0
        stx ppu_addr
        sta ppu_data

        EiPainettuA:

        ; Piirtovari alapalkin taustagrafiikkapalaan
        lda #$23
        ldx #$88
        jsr set_vram_address
        ldx color
        lda PiirtovariIlmaisimet, x
        sta ppu_data

        jsr reset_vram_address

        ; Spritet

        ; Kursorin kuva
        lda #2
        clc
        adc cursor_type
        sta sprite_data + 1

        ; Kursorin X-koordinaatti
        lda cursor_x
        asl
        asl
        ldx cursor_type
        bne IsoKursori1
            adc #2
            IsoKursori1:
        sta sprite_data + 3

        ; Kursorin Y-koordinaatti
        lda cursor_y
        asl
        asl
        adc #31
        ldx cursor_type
        bne IsoKursori2
            adc #2
            IsoKursori2:
        sta sprite_data

        ; X-koordinaattinumerot
        lda cursor_x
        lsr
        tax
        lda HaeYkkosetTaul, x
        adc #0
        sta sprite_data + 2 * 4 + 1
        lda HaeKymmenetTaul, x
        sta sprite_data + 4 + 1

        ; Y-koordinaattinumerot
        lda cursor_y
        lsr
        tax
        lda HaeYkkosetTaul, x
        adc #0
        sta sprite_data + 4 * 4 + 1
        lda HaeKymmenetTaul, x
        sta sprite_data + 3 * 4 + 1

    PoistuNMIsta:
        lda #$02
        sta oam_dma   ; spritedatan siirto
        lda joypad_status
        sta prev_joypad_status
        rti

; --------------------------------------------------------------------------------------------------

read_joypad:
    ; Luetaan peliohjaimen tila A:han ja X:aan.
    ; Bitit: A, B, select, start, yla, ala, vasen, oikea.
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
    rts

reset_vram_address:
    lda #$00
    sta ppu_addr
    sta ppu_addr
    rts

set_vram_address:
    sta ppu_addr
    stx ppu_addr
    rts

print_four_times:
    rept 4
        sta ppu_data
    endr
    rts

print_repeatedly:
    ; print A X times
-   sta ppu_data
    dex
    bne -
    rts

; --------------------------------------------------------------------------------------------------

    ; tables for generating background CHR data (read backwards)
background_chr_data1:
    hex ff f0 ff f0  0f 00 0f 00  ff f0 ff f0  0f 00 0f 00
background_chr_data2:
    hex ff ff f0 f0  ff ff f0 f0  0f 0f 00 00  0f 0f 00 00

NayMuiOsMuunnosH: db $20, $21, $21, $22, $22, $23
NayMuiOsMuunnosL: db $80, $A0, $C0, $E0, $00, $20, $40, $60

HaeKymmenetTaul:
    ; Kerran oikealle shiftattu luku --> kymmenkantaisten kymmenten (0 - 6) grafiikkamerkki
    db $10,$10,$10,$10,$10, $11,$11,$11,$11,$11, $12,$12,$12,$12,$12
    db $13,$13,$13,$13,$13, $14,$14,$14,$14,$14, $15,$15,$15,$15,$15
    db $16,$16
HaeYkkosetTaul:
    ; Kerran oikealle shiftattu luku --> kymmenkantaisten ykkosten (0/2/4/6/8) grafiikkamerkki
    db $10,$12,$14,$16,$18, $10,$12,$14,$16,$18, $10,$12,$14,$16,$18
    db $10,$12,$14,$16,$18, $10,$12,$14,$16,$18, $10,$12,$14,$16,$18
    db $10,$12

PalaAndArvot:
    db %00111111, %11001111, %11110011, %11111100

PalaOrArvot:
    db %00000000, %01000000, %10000000, %11000000
    db %00000000, %00010000, %00100000, %00110000
    db %00000000, %00000100, %00001000, %00001100
    db %00000000, %00000001, %00000010, %00000011

PiirtovariIlmaisimet: db $00, $55, $AA, $FF
SprPalTaul: db $1A, $1B, $1E, $1F

    ; name table data for the logo in the top bar (colors 2&3 on color 1; 1 byte = 2*2 subpixels)
    ; bits of tile index: AaBbCcDd
    ; subpixel colors:
    ; Aa Bb
    ; Cc Dd
logo:
    hex 555555 66 66 66 66 66 a5 55 55 66 a6 66 a5 66 a5 55 55 66 a6 66 a6 66 66 a6 65 a9 55555555
    hex 555555 66 96 66 a6 65 a6 75 f5 66 66 66 a5 65 a6 75 f5 66 a5 66 a6 66 66 66 55 99 55555555
    hex 555555 65 65 65 65 65 a5 55 55 65 65 65 a5 65 a5 55 55 65 55 65 65 65 65 65 55 95 55555555

initial_palette:
    ; Taustagrafiikka
    db white, red, green, blue   ; piirtoalue; samat kuin kahdessa viimeisessa spritepaletissa
    db white, yellow, green, purple   ; yla- ja alapalkki
    db white, white, white, white   ; ei kaytossa
    db white, white, white, white   ; ei kaytossa
    ; Spritet
    db white, yellow, black, olive   ; statuspalkin peitesprite, statuspalkin teksti, kursori
    db white, black, white, yellow   ; paletinvalintaruutu - tekstit ja nuoli
    db white, black, white, red   ; paletinvalintaruutu - valitut varit 0 ja 1
    db white, black, green, blue   ; paletinvalintaruutu - valitut varit 2 ja 3

    ; Tavalliset spritet. Y, kuva, ominaisuudet, X.
paint_mode_sprites:
    db $00    ,    $02, %00000000, 0 * 8   ; kursori
    db 28 * 8 - 1, $00, %00000000, 1 * 8   ; X-kymmenet
    db 28 * 8 - 1, $00, %00000000, 2 * 8   ; X-ykkoset
    db 28 * 8 - 1, $00, %00000000, 5 * 8   ; Y-kymmenet
    db 28 * 8 - 1, $00, %00000000, 6 * 8   ; Y-ykkoset
    db 28 * 8 - 1, $04, %00000000, 3 * 8   ; pilkku
    db 28 * 8 - 1, $01, %00000000, 9 * 8   ; peite 1
    db 29 * 8 - 1, $01, %00000000, 8 * 8   ; peite 2
    db 29 * 8 - 1, $01, %00000000, 9 * 8   ; peite 3
    paint_mode_sprites_end:

    ; Paletinvalintaspritet
PalValSpritet:
    db 22 * 8 - 1, $07, %00000001, 1 * 8   ; kursori
    db 22 * 8 - 1, $08, %00000010, 2 * 8   ; valittu vari 0
    db 23 * 8 - 1, $09, %00000010, 2 * 8   ; valittu vari 1
    db 24 * 8 - 1, $08, %00000011, 2 * 8   ; valittu vari 2
    db 25 * 8 - 1, $09, %00000011, 2 * 8   ; valittu vari 3
    db 26 * 8 - 1, $01, %00000001, 1 * 8   ; varinumeron 1. numero
    db 26 * 8 - 1, $01, %00000001, 2 * 8   ; varinumeron 2. numero
    db 21 * 8 - 1, $05, %00000001, 1 * 8   ; "PAL", vasen puoli
    db 21 * 8 - 1, $06, %00000001, 2 * 8   ; "PAL", oikea puoli
    db 22 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
    db 23 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
    db 24 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
    db 25 * 8 - 1, $01, %00000001, 1 * 8   ; tyhja
    PalValSpritetLoppu:

TAVSPRTAVUJA    = paint_mode_sprites_end    - paint_mode_sprites
PALVALSPRTAVUJA = PalValSpritetLoppu - PalValSpritet

; --------------------------------------------------------------------------------------------------
; CHR data (second half, 256 tiles)

    pad $d000
sprite_chr_data:
    hex 00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  ; $00: block of color 0
    hex ff ff ff ff ff ff ff ff  00 00 00 00 00 00 00 00  ; $01: block of color 1
    hex f0 c0 a0 90 08 04 02 01  f0 c0 a0 90 08 04 02 01  ; $02: arrow cursor (color 3)
    hex ff 81 81 81 81 81 81 ff  ff 81 81 81 81 81 81 ff  ; $03: square cursor (color 3)
    hex ff ff ff ff ff e7 e7 cf  00 00 00 00 00 18 18 30  ; $04: comma (color 2 on 1)
    hex ff 8e b5 b5 8c bd bd ff  00 71 4a 4a 73 42 42 00  ; $05: left half of "PAL" (color 2 on 1)
    hex ff 6f af af 2f af a1 ff  00 90 50 50 d0 50 5e 00  ; $06: right half of "PAL" (color 2 on 1)
    hex 00 0c 06 7f 06 0c 00 00  00 0c 06 7f 06 0c 00 00  ; $07: right arrow (color 3)
    hex 81 81 81 81 81 81 81 ff  7e 7e 7e 7e 7e 7e 7e 00  ; $08: block of color 2, border color 1
    hex ff ff ff ff ff ff ff ff  7e 7e 7e 7e 7e 7e 7e 00  ; $09: block of color 3, border color 1

    ; tiles $10-$1f: hexadecimal digits "0"-"F" (color 2 on 1)
    pad $d000 + $10 * 16, $00
    hex 83 39 39 39 39 39 83 ff  7c c6 c6 c6 c6 c6 7c 00
    hex e7 c7 e7 e7 e7 e7 c3 ff  18 38 18 18 18 18 3c 00
    hex 83 39 f9 e3 8f 3f 01 ff  7c c6 06 1c 70 c0 fe 00
    hex 83 39 f9 c3 f9 39 83 ff  7c c6 06 3c 06 c6 7c 00
    hex f3 e3 c3 93 01 f3 f3 ff  0c 1c 3c 6c fe 0c 0c 00
    hex 01 3f 3f 03 f9 f9 03 ff  fe c0 c0 fc 06 06 fc 00
    hex 81 3f 3f 03 39 39 83 ff  7e c0 c0 fc c6 c6 7c 00
    hex 01 f9 f3 e7 cf 9f 3f ff  fe 06 0c 18 30 60 c0 00
    hex 83 39 39 83 39 39 83 ff  7c c6 c6 7c c6 c6 7c 00
    hex 83 39 39 81 f9 f9 03 ff  7c c6 c6 7e 06 06 fc 00
    hex 83 39 39 01 39 39 39 ff  7c c6 c6 fe c6 c6 c6 00
    hex 03 99 99 83 99 99 03 ff  fc 66 66 7c 66 66 fc 00
    hex 83 39 3f 3f 3f 39 83 ff  7c c6 c0 c0 c0 c6 7c 00
    hex 03 99 99 99 99 99 03 ff  fc 66 66 66 66 66 fc 00
    hex 01 3f 3f 01 3f 3f 01 ff  fe c0 c0 fe c0 c0 fe 00
    hex 01 3f 3f 01 3f 3f 3f ff  fe c0 c0 fe c0 c0 c0 00

    pad $e000, $00

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    dw nmi, reset, 0
