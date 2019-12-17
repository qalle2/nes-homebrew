; KHS-NES-Brainfuck

    ; byte to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory

program_status    equ $00  ; 0 = editing, 1 = running, 2 = asking for input
joypad_status     equ $01
program_length    equ $02  ; 0-255
pointer           equ $03  ; 2 bytes
output_buffer     equ $05  ; 1 byte
output_buffer_len equ $06  ; 0-1
output_char_cnt   equ $07  ; number of characters printed by the Brainfuck program
char_x            equ $08  ; virtual keyboard - X position (0-15)
char_y            equ $09  ; virtual keyboard - Y position (0-5)
input_char        equ $0A  ; virtual keyboard - character (32-127)
temp              equ $0B

brainfuck_code1    equ $0200  ; code with spaces (255 bytes)
brainfuck_code2    equ $0300  ; code without spaces (255 bytes)
brainfuck_brackets equ $0400  ; target addresses of "[" and "]" (255 bytes)
brainfuck_ram      equ $0500  ; RAM (256 bytes)

sprite_data equ $0600  ; 256 bytes

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_addr   equ $2006
ppu_data   equ $2007
oam_dma    equ $4014
joypad1    equ $4016

; PPU memory

vram_name_table0 equ $2000
vram_palette     equ $3f00

; non-address constants

button_a      equ 1 << 7
button_b      equ 1 << 6
button_select equ 1 << 5
button_start  equ 1 << 4
button_up     equ 1 << 3
button_down   equ 1 << 2
button_left   equ 1 << 1
button_right  equ 1 << 0

terminator equ $00

sprite_count equ 2

black equ $0f
white equ $30

; --------------------------------------------------------------------------------------------------
; Macros

macro wait_for_start_of_vblank
    bit ppu_status
-   bit ppu_status
    bpl -
endm

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (CHR RAM)
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

    org $c000
reset:

    lda #$00
    sta ppu_ctrl
    sta ppu_mask
    sta joypad_status
    sta program_length

    ; clear Brainfuck code
    tax
-   sta brainfuck_code1, x
    inx
    bne -

    ; initialize used sprites, hide other sprites
-   lda initial_sprite_data, x
    sta sprite_data, x
    inx
    cpx #(sprite_count * 4)
    bne -
    lda #$ff
-   sta sprite_data, x
    inx
    bne -

    wait_for_start_of_vblank
-   bit ppu_status
    bpl -

    ; palette

    ; fill with black
    lda #>vram_palette
    ldx #<vram_palette
    jsr set_vram_address
    lda #black
    ldx #32
    jsr write_vram

    ; change first color of first background&sprite subpalette to white
    lda #>(vram_palette + 1)
    ldx #<(vram_palette + 1)
    jsr set_vram_address
    ldy #white
    sty ppu_data
    ldx #<(vram_palette + 4 * 4 + 1)
    jsr set_vram_address
    sty ppu_data

    ; copy CHR data to CHR RAM;
    ; the second (more significant) bitplane of every character is blank

    ; set up source pointer, set target to start of pattern table 0
    lda #>CHRdata
    sta pointer + 1
    ldy #$00
    sty pointer + 0
    sty ppu_addr
    sty ppu_addr
chr_data_copy_loop:
--  lda (pointer), y
    sta ppu_data
    iny
    ; if source offset is a multiple of eight, write a blank bitplane to complete the character
    tya
    and #%00000111
    bne +
    ldx #8
-   sta ppu_data
    dex
    bne -
+   ; if source page not finished, just continue loop
    cpy #0
    bne chr_data_copy_loop
    ; increment most significant byte of address; if not all data read, continue loop
    inc pointer + 1
    lda pointer + 1
    cmp #((>CHRdata) + 8)
    bne chr_data_copy_loop

    ; ??
    lda #>AjoTila
    sta pointer + 1

edit_mode:
    lda #$00
    sta ppu_ctrl
    sta ppu_mask
    sta program_status
    sta char_x
    sta char_y

    ; set up name table 0 and attribute table 0

    lda #>vram_name_table0
    ldx #<vram_name_table0
    jsr set_vram_address
    ; print top part of editor
    ldx #(rle_data_editor_top - rle_data)
    jsr print_rle_data
    ; print Brainfuck code
    ldx #0
-   lda brainfuck_code1, x
    sta ppu_data
    inx
    bne -
    ; print bottom part of editor
    ldx #(rle_data_editor_bottom - rle_data)
    jsr print_rle_data
    ; clear attribute table
    lda #%00000000
    ldx #(8 * 8)
    jsr write_vram
    ; write cursor to name table
    lda #>(vram_name_table0 + 16 * 32)
    ldx program_length
    jsr set_vram_address
    lda #"_"
    sta ppu_data

    jsr reset_vram_address
    wait_for_start_of_vblank

wait_for_execution_start:
    lda #%10000000
    sta ppu_ctrl
    lda #%00001010
    sta ppu_mask

    ; wait until we exit the editor in the NMI routine
-   lda program_status
    beq -

    ; start execution

    ; disable rendering
    lda #%00000000
    sta ppu_ctrl

    ; TODO: translate & clean up from here on

; Kopioidaan Brainfuck-koodin alkupuoli nayttomuistista brainfuck_code1:een
    wait_for_start_of_vblank
    lda #$22
    ldx #$00
    jsr set_vram_address
    lda ppu_data
    KoodiKopSilm1:
        lda ppu_data
        sta brainfuck_code1, x
        inx
        bpl KoodiKopSilm1
    jsr reset_vram_address

; Kopioidaan Brainfuck-koodin loppupuoli nayttomuistista brainfuck_code1:een
    wait_for_start_of_vblank
    lda #$22
    ldx #$80
    jsr set_vram_address
    lda ppu_data
    KoodiKopSilm2:
        lda ppu_data
        sta brainfuck_code1, x
        inx
        bne KoodiKopSilm2
    jsr reset_vram_address

; Tyhjennetaan brainfuck_code2
    lda #$00
    tax
    TyhjSilm:
        sta brainfuck_code2, x
        inx
        bne TyhjSilm

; Kopioidaan brainfuck_code1:n sisalto brainfuck_code2:een ilman valilyonteja
    tay
    KoodiKopSilm3:
        lda brainfuck_code1, x
        cmp #$20  ; space
        beq EiOteta
            sta brainfuck_code2, y
            iny
            EiOteta:
        inx
        bne KoodiKopSilm3

; Otetaan muistiin kustakin sulusta eli [:sta tai ]:sta, missa sita vastaava ] tai [ sijaitsee.
; Y: silmukkalaskuri. Pino: aukinaisten sulkujen osoitteet.
    ldy #0
    dex
    txs
    SulkuKeruuSilm:
        lda brainfuck_code2, y

        cmp #'['
        bne EiAlkusulku
            ; Nykyisen kaskyn osoite pinoon
            tya
            pha
            jmp MerkkiTulkittu
            EiAlkusulku:

        cmp #']'
        bne MerkkiTulkittu
            ; Nykyisen kaskyn vastakaskyksi edellinen avattu sulku, ja painvastoin
            pla
            tsx
            beq PinonAlivuoto
            sta brainfuck_brackets, y
            tax
            tya
            sta brainfuck_brackets, x
            MerkkiTulkittu:

        iny
        bne SulkuKeruuSilm
        dey   ; kertoo, etta alivuotoa ei tapahtunut
        PinonAlivuoto:

; Onko alku- ja loppusulkuja sama maara
    tsx
    inx
    beq SulutKunnossa
        ; Naytetaan virheilmoitus ja odotetaan napinpainallusta
        wait_for_start_of_vblank
        lda #$23
        ldx #$20
        jsr set_vram_address
        ldx #(string_opening_bracket - strings)
        iny
        beq EiAlivuotoa
            ldx #(string_closing_bracket - strings)
            EiAlivuotoa:
        jsr TulostaTekstidataa
        jsr reset_vram_address
        OdotaB1:
            jsr LueOhjain
            sta joypad_status
            and #button_b
            beq OdotaB1

        ; Palataan editointitilaan
        dec program_status
        wait_for_start_of_vblank
        lda #$23
        ldx #$20
        jsr set_vram_address
        lda #$20  ; space
        ldx #32
        jsr write_vram
        jsr reset_vram_address
        jmp wait_for_execution_start

        SulutKunnossa:

    lda #%00000000
    sta ppu_mask

; Vaihdetaan kunkin brainfuck_code2:n kaskyn tilalle osoite, jossa kaskyn suorittava ohjelmanpatka on.
; Kursori eli "_" on kasky, joka lopettaa ohjelman.
    ldx #0
    TulkintaSilm1:
        lda brainfuck_code2, x
        ldy #0
        TulkintaSilm2:
            cmp instructions, y
            beq KaskyTulkittu
            iny
            cpy #10
            bne TulkintaSilm2
            KaskyTulkittu:
        lda instruction_offsets, y
        sta brainfuck_code2, x
        inx
        bne TulkintaSilm1

; Tyhjennetaan Brainfuck-RAM
    txa
    BFRAMtyhj:
        sta brainfuck_ram, x
        inx
        bne BFRAMtyhj

; Kirjoitetaan Name Table uudelleen
    lda #$20
    jsr set_vram_address
    ldx #(rle_data_code_execution_top - rle_data)
    jsr print_rle_data
    ldx #(string_running - strings)
    jsr TulostaTekstidataa
    lda #$20  ; space
    ldx #28
    jsr write_vram

    ; Virtuaalinappaimisto
    ldx #32   ; ASCII-koodi
    VirtuSilm:
        txa
        and #%00001111
        bne EiRivinvaihtoa
            lda #$20  ; space
            ldy #16
            VirtuValiSilm:
                sta ppu_data
                dey
                bne VirtuValiSilm
            EiRivinvaihtoa:
        stx ppu_data
        inx
        bpl VirtuSilm

    lda #$20  ; space
    ldx #136
    jsr write_vram

; Attribute Tablessa virtuaalinappaimisto piiloon
    lda #%01010101
    jsr AsetaVirtuNappTila

    jsr reset_vram_address
    wait_for_start_of_vblank

    lda #%10000000
    sta ppu_ctrl
    lda #%00001010
    sta ppu_mask

; Varsinainen Brainfuck-koodin suoritus
    jmp AjoTila
    org $C300
AjoTila:

    ldx #$00
    stx output_buffer_len
    stx output_char_cnt

; Y: osoite Brainfuck-koodissa. X: osoite Brainfuck-RAM:issa.
    ldy #$FF
SuoritusSilm:
    iny
    lda brainfuck_code2, y
    sta pointer + 0
    jmp (pointer)

    KaksiPlus:
        inc brainfuck_ram, x
    Plus:
        inc brainfuck_ram, x
        jmp SuoritusSilm

    KaksiMiinus:
        dec brainfuck_ram, x
    Miinus:
        dec brainfuck_ram, x
        jmp SuoritusSilm

    Vasen:
        dex
        jmp SuoritusSilm

    Oikea:
        inx
        jmp SuoritusSilm

    Alkusulku:
        lda brainfuck_ram, x
        bne SuoritusSilm
            lda brainfuck_brackets, y
            tay
        jmp SuoritusSilm

    Loppusulku:
        lda brainfuck_ram, x
        beq SuoritusSilm
            lda brainfuck_brackets, y
            tay
        jmp SuoritusSilm

    Piste:
        ; Laitetaan merkki puskuriin ja odotetaan, etta se tyhjennetaan NMI:ssa
        lda brainfuck_ram, x
        sta output_buffer
        inc output_buffer_len
        OdotaPuskTyhj:
            lda output_buffer_len
            bne OdotaPuskTyhj
        lda output_char_cnt
        beq PoistuOhjelmasta   ; jos tulostettu 256 merkkia
        jmp SuoritusSilm

    Pilkku:
        stx temp

        ; Teksti "Character?"
        wait_for_start_of_vblank
        lda #$22
        ldx #$40
        jsr set_vram_address
        ldx #(string_input - strings)
        jsr TulostaTekstidataa

        ; Virtuaalinappaimisto nakyviin
        lda #%00000000
        jsr AsetaVirtuNappTila
        jsr reset_vram_address

        ; sprite_data nakyviin
        lda #%00011110
        sta ppu_mask

        ; Kayttajalta kysytaan syote NMI:ssa
        inc program_status
        OdotaNMIta:
            ldx program_status
            dex
            bne OdotaNMIta

        ; Teksti "Running..."
        lda #$22
        ldx #$40
        jsr set_vram_address
        ldx #(string_running - strings)
        jsr TulostaTekstidataa

        ; Virtuaalinappaimisto piiloon
        lda #%01010101
        jsr AsetaVirtuNappTila
        jsr reset_vram_address

        ; sprite_data piiloon
        lda #%00001010
        sta ppu_mask

        ldx temp
        lda input_char
        sta brainfuck_ram, x
        jmp SuoritusSilm

    PoistuOhjelmasta:

; Brainfuck-ohjelma on ajettu
    lda #%00000000
    sta ppu_ctrl
    wait_for_start_of_vblank

    ; Teksti "Finished."
    lda #$22
    ldx #$40
    jsr set_vram_address
    ldx #(string_finished - strings)
    jsr TulostaTekstidataa
    jsr reset_vram_address

    ; Odota, etta painetaan B
    OdotaB2:
        jsr LueOhjain
        sta joypad_status
        and #button_b
        beq OdotaB2

    jmp edit_mode

; --------------------------------------------------------------------------------------------------
; Non-maskable interrupt routine

nmi:
    php
    pha
    txa
    pha
    tya
    pha

    ldx program_status
    beq NMI_editointitila
    dex
    beq NMI_ajotila
    jmp NMI_syotetila

    NMI_editointitila:
        jsr LueOhjain

        ; Ei jatketa, jos nappien tila on sama kuin edellisella kerralla
        cpx joypad_status
        bne Jatka1
        jmp PoistuNMIsta
        Jatka1:
        stx joypad_status

        ; Jos kirjoitettuja merkkeja on alle 255 ja on painettu nappia, jolla lisataan merkki,
        ; lisataan kyseinen merkki ja poistutaan NMI:sta.
        ldx program_length
        inx
        beq NapitLuettu1
            ldy #10
            TutkiNappiSilm:
                lda instruction_buttons, y
                cmp joypad_status
                bne EiOllutTamaNappi
                    lda #$22
                    ldx program_length
                    jsr set_vram_address
                    lda instructions, y
                    sta ppu_data
                    lda #'_'
                    sta ppu_data
                    inc program_length
                    jmp NollaaJaPoistuNMIsta
                    EiOllutTamaNappi:
                dey
                bpl TutkiNappiSilm
            NapitLuettu1:

        ; Jos on painettu start-vasen ja kirjoitettu ainakin yksi merkki, poistetaan viimeinen
        ; ja poistutaan NMI:sta.
        lda program_length
        beq EiBackSpacea
        lda joypad_status
        cmp #(button_start | button_left)
        bne EiBackSpacea
            dec program_length
            lda #$22
            ldx program_length
            jsr set_vram_address
            lda #"_"
            sta ppu_data
            lda #$20  ; space
            sta ppu_data
            jmp NollaaJaPoistuNMIsta
            EiBackSpacea:

        ; Jos on painettu select-start, ajetaan ohjelma
        lda joypad_status
        cmp #(button_select | button_start)
        bne EiAjeta
            inc program_status
            EiAjeta:

        jmp PoistuNMIsta

    NMI_ajotila:
        jsr LueOhjain
        sta joypad_status

        ; Jos on painettu B, keskeytetaan
        and #button_b
        beq EiKeskeyteta
            jmp edit_mode
            EiKeskeyteta:

        ; Jos puskurissa on merkki, tulostetaan se
        lda output_buffer_len
        bne Jatka2
        jmp PoistuNMIsta
        Jatka2:
            lda output_buffer
            cmp #$0A
            beq Rivinvaihto
                lda #$21
                ldx output_char_cnt
                jsr set_vram_address
                lda output_buffer
                sta ppu_data
                inc output_char_cnt
                dec output_buffer_len
                jmp NollaaJaPoistuNMIsta
            Rivinvaihto:
                lda output_char_cnt
                and #%11100000
                adc #31
                sta output_char_cnt
                dec output_buffer_len
                jmp PoistuNMIsta

    NMI_syotetila:
        jsr LueOhjain

        ; Ei reagoida nappeihin, jos niiden tila on sama kuin edellisella kerralla
        cmp joypad_status
        beq NapitLuettu
        sta joypad_status

        lsr
        bcs Oikea2
        lsr
        bcs Vasen2
        lsr
        bcs Ala
        lsr
        bcs Yla
        lsr
        lsr
        lsr
        bcs Pois
        lsr
        bcs Valitse

        jmp NapitLuettu

        Vasen2:
            ldx char_x
            dex
            txa
            and #%00001111
            sta char_x
            jmp NapitLuettu

        Oikea2:
            ldx char_x
            inx
            txa
            and #%00001111
            sta char_x
            jmp NapitLuettu

        Yla:
            ldx char_y
            dex
            bpl EiTaysille
                ldx #5
                EiTaysille:
            stx char_y
            jmp NapitLuettu

        Ala:
            ldx char_y
            inx
            cpx #6
            bne EiNollaan
                ldx #0
                EiNollaan:
            stx char_y
            jmp NapitLuettu

        Valitse:
            dec program_status
            jmp NapitLuettu

        Pois:
            jmp edit_mode

        NapitLuettu:

        ; Spritejen Y
        lda char_y
        asl
        asl
        asl
        tax
        adc #$9F
        sta sprite_data + 0
        sta sprite_data + 4

        ; Spriten 0 kuva ja input_char
        txa
        asl
        adc #$20
        adc char_x
        sta sprite_data + 1
        cmp #127
        bne EiVirtuNappEnter
            lda #$0A
            EiVirtuNappEnter:
        sta input_char

        ; Spritejen X
        lda char_x
        asl
        asl
        asl
        adc #$40
        sta sprite_data + 3
        sta sprite_data + 7

        lda #>sprite_data
        sta oam_dma

    NollaaJaPoistuNMIsta:
        jsr reset_vram_address
    PoistuNMIsta:
        pla
        tay
        pla
        tax
        pla
        plp
        rti

; --------------------------------------------------------------------------------------------------
; Subroutines

reset_vram_address:
    lda #$00
    sta ppu_addr
    sta ppu_addr
    rts

set_vram_address:
    sta ppu_addr
    stx ppu_addr
    rts

write_vram:
    ; write A to VRAM X times
-   sta ppu_data
    dex
    bne -
    rts

TulostaTekstidataa:
    ; Tulostaa taulukosta strings tavut X:sta seuraavaan loppumerkkiin ($00).
    TekstiSilm:
        lda strings, x
        beq LoppumerkkiHavaittu1
        sta ppu_data
        inx
        bne TekstiSilm
    LoppumerkkiHavaittu1:
    rts

print_rle_data:
    ; Tulostaa taulukosta rle_data tavut X:sta seuraavaan loppumerkkiin.
    ; RLE-data on jaettu lohkoihin. Lohkon 1. tavu kertoo lohkon tyypin:
    ;     $00       = loppumerkki
    ;     $01 - $7F = pakattu,     pituus 2 - 128 tavua
    ;     $80 - $FF = pakkaamaton, pituus 1 - 128 tavua
    ; Lohkon muut tavut ovat varsinainen data (pakatussa lohkossa aina yksi tavu).
    RLEsilm1:
        ldy rle_data, x   ; lohkon tyyppi
        beq LoppumerkkiHavaittu2
        bpl Pakattu
            ; Pakkaamaton lohko
            RLEsilm2:
                inx
                lda rle_data, x
                sta ppu_data
                dey
                bmi RLEsilm2
            jmp LohkoKopioitu
        Pakattu:
            inx
            lda rle_data, x
            RLEsilm3:
                sta ppu_data
                dey
                bpl RLEsilm3
        LohkoKopioitu:
        inx
        bne RLEsilm1
    LoppumerkkiHavaittu2:
    rts

LueOhjain:
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

AsetaVirtuNappTila:
    ; Kirjoittaa Attribute Tableen virtuaalinappaimiston kohdalle A:n arvoa
    ldx #$23
    stx ppu_addr
    ldx #$EA
    stx ppu_addr
    ldx #12
    VirtuNappSilm:
        sta ppu_data
        dex
        bne VirtuNappSilm
    rts

; --------------------------------------------------------------------------------------------------
; Tables

; Brainfuck-kaskyt; milla napilla ne kirjoitetaan; kaskyt suorittavien koodinpatkien osoitteet
instructions:
    db "+"
    db "-"
    db "<"
    db ">"
    db "["
    db "]"
    db "."
    db ","
    db $8a  ; double plus
    db $8b  ; double minus
    db " "  ; ??
instruction_buttons:
    db button_up
    db button_down
    db button_left
    db button_right
    db button_b
    db button_a
    db button_select | button_a
    db button_select | button_b
    db button_start | button_up
    db button_start | button_down
    db button_start | button_right
instruction_offsets:
    db Plus - AjoTila
    db Miinus - AjoTila
    db Vasen - AjoTila
    db Oikea - AjoTila
    db Alkusulku - AjoTila
    db Loppusulku - AjoTila
    db Piste - AjoTila
    db Pilkku - AjoTila
    db KaksiPlus - AjoTila
    db KaksiMiinus - AjoTila
    db PoistuOhjelmasta - AjoTila   ; means "_" instead of space

; run length encoded name table data
; compressed block:
;   - length minus one
;   - byte to repeat
; uncompressed block:
;   - $80 | (length - 1)
;   - as many bytes as length is
rle_data:

    ; edit screen before the Brainfuck code
rle_data_editor_top:
    db 102 - 1, " "
    db $80 | (1 - 1), $82
    db 17 - 1, $80
    db $80 | (1 - 1), $83
    db 13 - 1, " "
    db $80 | (19 - 1), $81, "KHS-NES-Brainfuck", $81
    db 13 - 1, " "
    db $80 | (1 - 1), $84
    db 17 - 1, $80
    db $80 | (1 - 1), $85
    db 40 - 1, " "
    db $80 | (8 - 1), $86, "=+  ", $87, "=-"
    db 3 - 1, " "
    db $80 | (8 - 1), $88, "=<  ", $89, "=>"
    db 3 - 1, " "
    db $80 | (8 - 1), "B=[  A=]"
    db 35 - 1, " "
    db $80 | (9 - 1), "start-", $86, "=", $8a
    db 3 - 1,  " "
    db $80 | (13 - 1), "start-", $89, "=space"
    db 7 - 1, " "
    db $80 | (9 - 1), "start-", $87, "=", $8b
    db 3 - 1,  " "
    db $80 | (41 - 1), "start-", $88, "=backspace  select-B=,  select-A=."
    db 42 - 1, " "
    db $80 | (16 - 1), "select-start=run"
    db 47 - 1, " "
    db 32 - 1, $80
    db terminator

    ; edit screen after the Brainfuck code
rle_data_editor_bottom:
    db 32 - 1, $80
    db 128 - 1, " "
    db 32 - 1, " "
    db terminator

    ; run screen before the text "Running"
rle_data_code_execution_top:
    db 128 - 1, " "
    db 32 - 1, " "
    db $80 | (7 - 1), "Output:"
    db 57 - 1, " "
    db 32 - 1, $80
    db 128 - 1, " "
    db 128 - 1, " "
    db 32 - 1, $80
    db 32 - 1, " "
    db terminator

strings:
string_opening_bracket:
    db "Error: '[' without ']'. Press B."
    db terminator
string_closing_bracket:
    db "Error: ']' without '['. Press B."
    db terminator
string_running:
    db "Running... (B=end)          "
    db terminator
string_input:
    db "Character? (", $86, $87, $88, $89, " A=OK B=end)"
    db terminator
string_finished:
    db "Finished. Press B."
    db terminator

initial_sprite_data:
    db $ff, $00, %00000001, $ff   ; valittu merkki mustana
    db $ff, $8c, %00000000, $ff   ; a white block

; --------------------------------------------------------------------------------------------------
; CHR data
;   - 256 characters
;   - one bitplane (1 byte = 8 * 1 pixels, 8 bytes = character)
;   - printable ASCII at correct positions
;   - some extra characters

    pad $c800
CHRdata:
    dsb 32 * 8, $00  ; characters $00-$1f: blank

    ; characters $20-$3f: space and !"#$%&'()*+,-./0123456789:;<=>?
    hex 00 00 00 00 00 00 00 00
    hex 10 10 10 10 10 00 10 00
    hex 28 28 00 00 00 00 00 00
    hex 28 28 7c 28 7c 28 28 00
    hex 10 3c 50 38 14 78 10 00
    hex 00 44 08 10 20 44 00 00
    hex 38 44 28 10 2a 44 3a 00
    hex 10 10 00 00 00 00 00 00
    hex 08 10 20 20 20 10 08 00
    hex 20 10 08 08 08 10 20 00
    hex 00 44 28 fe 28 44 00 00
    hex 10 10 10 fe 10 10 10 00
    hex 00 00 00 00 08 10 20 00
    hex 00 00 00 fc 00 00 00 00
    hex 00 00 00 00 00 18 18 00
    hex 02 04 08 10 20 40 80 00
    hex 7c 82 82 92 82 82 7c 00
    hex 10 30 10 10 10 10 38 00
    hex 7c 82 02 7c 80 80 fe 00
    hex fc 02 02 fc 02 02 fc 00
    hex 08 18 28 48 fe 08 08 00
    hex fe 80 80 fc 02 02 fc 00
    hex 7e 80 80 fc 82 82 7c 00
    hex fe 04 08 10 20 40 80 00
    hex 7c 82 82 7c 82 82 7c 00
    hex 7c 82 82 7e 02 02 fc 00
    hex 00 10 00 00 00 10 00 00
    hex 00 10 00 00 10 20 40 00
    hex 08 10 20 40 20 10 08 00
    hex 00 00 fe 00 00 fe 00 00
    hex 40 20 10 08 10 20 40 00
    hex 7c 82 02 0c 10 10 00 10

    ; characters $40-$5f: @ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_
    hex 7c 82 ba ba b4 80 7e 00
    hex 7c 82 82 fe 82 82 82 00
    hex fc 42 42 7c 42 42 fc 00
    hex 7e 80 80 80 80 80 7e 00
    hex f8 84 82 82 82 84 f8 00
    hex fe 80 80 fe 80 80 fe 00
    hex fe 80 80 fe 80 80 80 00
    hex 7e 80 80 9e 82 82 7e 00
    hex 82 82 82 fe 82 82 82 00
    hex 38 10 10 10 10 10 38 00
    hex 04 04 04 04 04 44 38 00
    hex 44 48 50 60 50 48 44 00
    hex 80 80 80 80 80 80 fe 00
    hex 82 c6 aa 92 82 82 82 00
    hex 82 c2 a2 92 8a 86 82 00
    hex 7c 82 82 82 82 82 7c 00
    hex fc 82 82 fc 80 80 80 00
    hex 7c 82 82 92 8a 86 7e 00
    hex fc 82 82 fc 88 84 82 00
    hex 7e 80 80 7c 02 02 fc 00
    hex fe 10 10 10 10 10 10 00
    hex 82 82 82 82 82 82 7c 00
    hex 82 82 82 82 44 28 10 00
    hex 82 82 82 92 aa c6 82 00
    hex 82 44 28 10 28 44 82 00
    hex 82 44 28 10 10 10 10 00
    hex fe 04 08 10 20 40 fe 00
    hex 38 20 20 20 20 20 38 00
    hex 80 40 20 10 08 04 02 00
    hex 38 08 08 08 08 08 38 00
    hex 10 28 44 00 00 00 00 00
    hex 00 00 00 00 00 00 fe 00

    ; characters $60-$7f: `abcdefghijklmnopqrstuvwxyz{|}~
    hex 10 08 04 00 00 00 00 00
    hex 00 00 78 04 3c 4c 34 00
    hex 40 40 78 44 44 44 78 00
    hex 00 00 3c 40 40 40 3c 00
    hex 04 04 3c 44 44 44 3c 00
    hex 00 00 38 44 78 40 3c 00
    hex 18 24 20 78 20 20 20 00
    hex 00 00 34 4c 44 3c 04 78
    hex 40 40 58 64 44 44 44 00
    hex 00 10 00 10 10 10 10 00
    hex 00 08 00 08 08 08 48 30
    hex 40 40 48 50 60 50 48 00
    hex 30 10 10 10 10 10 10 00
    hex 00 00 b6 da 92 92 92 00
    hex 00 00 58 64 44 44 44 00
    hex 00 00 38 44 44 44 38 00
    hex 00 00 58 64 44 78 40 40
    hex 00 00 34 4c 44 3c 04 04
    hex 00 00 5c 60 40 40 40 00
    hex 00 00 3c 40 38 04 78 00
    hex 00 20 78 20 20 28 10 00
    hex 00 00 44 44 44 4c 34 00
    hex 00 00 44 44 28 28 10 00
    hex 00 00 54 54 54 54 28 00
    hex 00 00 44 28 10 28 44 00
    hex 00 00 44 44 44 3c 04 78
    hex 00 00 7c 08 10 20 7c 00
    hex 0c 10 10 60 10 10 0c 00
    hex 10 10 10 00 10 10 10 00
    hex 60 10 10 0c 10 10 60 00
    hex 64 98 00 00 00 00 00 00
    hex 04 04 24 44 fc 40 20 00

    ; characters $80-$8c
    hex 00 00 ff ff ff 00 00 00  ; $80: horizontal thick line
    hex 38 38 38 38 38 38 38 38  ; $81: vertical thick line
    hex 00 00 0f 1f 3f 3c 38 38  ; $82: curved thick line from bottom to right
    hex 00 00 e0 f0 f8 78 38 38  ; $83: curved thick line from bottom to left
    hex 38 3c 3f 1f 0f 00 00 00  ; $84: curved thick line from top to right
    hex 38 78 f8 f0 e0 00 00 00  ; $85: curved thick line from top to left
    hex 10 38 54 10 10 10 10 00  ; $86: up arrow
    hex 10 10 10 10 54 38 10 00  ; $87: down arrow
    hex 00 20 40 fe 40 20 00 00  ; $88: left arrow
    hex 00 08 04 fe 04 08 00 00  ; $89: right arrow
    hex 00 40 44 e4 4e 44 04 00  ; $8a: double plus
    hex 00 00 f0 00 1e 00 00 00  ; $8b: double minus
    hex ff ff ff ff ff ff ff ff  ; $8c: solid block

    pad $d000, $00  ; the rest of the 256 characters are blank

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    dw nmi, reset, 0
