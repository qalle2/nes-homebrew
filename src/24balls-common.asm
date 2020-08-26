; 24 Balls - subs and tables used by many files

reset_ppu_address_and_scroll:
    ; Reset ppu_addr/ppu_scroll address latch; reset PPU address and scroll.
    ; Args: none

    bit ppu_status
    lda #$00
    sta ppu_addr
    sta ppu_addr
    sta ppu_scroll
    sta ppu_scroll
    rts

set_ppu_address:
    ; Reset ppu_addr/ppu_scroll address latch and set PPU address.
    ; Args: A = high byte, X = low byte

    bit ppu_status
    sta ppu_addr
    stx ppu_addr
    rts

; -------------------------------------------------------------------------------------------------

sprite_palette_rom_to_ram:
    ; Depending on timer, copy one of two sprite palettes from ROM to RAM backwards.
    ; Args: none

    lda timer
    and #%00001000
    asl
    tax

    ldy #15
-   lda sprite_palettes, x
    sta sprite_palette_ram, y
    inx
    dey
    bpl -

    rts

sprite_palettes:
    ; shades of blue, red, yellow and green
    hex 0f 11 21 31
    hex 0f 14 24 34
    hex 0f 17 27 37
    hex 0f 1a 2a 3a
    ; slightly different shades of blue, red, yellow and green
    hex 0f 12 22 32
    hex 0f 15 25 35
    hex 0f 18 28 38
    hex 0f 1b 2b 3b

sprite_palette_ram_to_vram:
    ; Copy sprite palette backwards from RAM to VRAM.
    ; Args: none

    lda #$3f
    ldx #$10
    jsr set_ppu_address

    ldx #15
-   lda sprite_palette_ram, x
    sta ppu_data
    dex
    bpl -

    rts

