; Initialization

reset:
    initialize_nes

    lda #$00
    sta snd_chn  ; disable sound channels
    sta frame_counter
    sta nmi_done

    jsr copy_name_table_data

    wait_vblank

    jsr write_palette
    jsr write_pattern_table
    jsr write_name_table
    jsr write_attribute_table

    jsr reset_ppu_address

    wait_vblank_start

    ; enable NMI
    lda #%10000000
    sta ppu_ctrl

    ; show background
    lda #%00001010
    sta ppu_mask

    jmp main_loop

; --------------------------------------------------------------------------------------------------

copy_name_table_data:
    ; Copy name table data from ROM to CPU RAM.

    ldx #(14 * 4 - 1)
-   lda initial_name_table_data, x
    sta name_table_data, x
    dex
    bpl -
    rts

initial_name_table_data:
    ; Each byte specifies the color of 4*1 squares.
    ; The value of each 2-bit group is 1-3 (never 0), so each nybble is one of: 1235679abdef
    ; 14 * 4 = 56 bytes
    hex 66 77 7b af
    hex ed 99 da e6
    hex 56 99 65 ae
    hex 6a e6 76 db
    hex a7 bd 9f d5
    hex fd df 6b a7
    hex eb 65 99 b6
    hex 59 f6 ff d9
    hex 7b e5 65 75
    hex 6e e7 a6 ef
    hex fb 5f 69 9e
    hex 55 65 bb 79
    hex 6b 9f 66 ea
    hex a6 6f bb 9e

; --------------------------------------------------------------------------------------------------

write_palette:
    ; Copy palette to PPU.

    ; set PPU address
    load_ax ppu_palette
    jsr set_ppu_address

    ldx #0
-   lda background_palette, x
    sta ppu_data
    inx
    cpx #16
    bne -

    rts

background_palette:
    hex 0f 12 14 16  ; black, blue, purple, red
    hex 0f 18 1a 1c  ; black, yellow, green, teal
    hex 0f 22 24 26  ; like 1st subpalette but lighter foreground colors
    hex 0f 28 2a 2c  ; like 2nd subpalette but lighter foreground colors

; --------------------------------------------------------------------------------------------------

write_pattern_table:
    ; Uncompress CHR data to Pattern Table 0.

    load_ax ppu_pattern_table0
    jsr set_ppu_address

    ; X = source index, Y = write loop counter
    ldx #0
chr_ram_loop:
    ; read byte, write once
    lda chr_data, x
    inx
    sta ppu_data
    ; read byte, write seven times
    lda chr_data, x
    inx
    ldy #7
-   sta ppu_data
    dey
    bne -
    ; end loop
    cpx #(16 * 4)
    bne chr_ram_loop

    rts

chr_data:
    ; Each 4 bytes represent a tile (16 bytes uncompressed).
    ; Index within compressed tile -> index within uncompressed tile:
    ; 0 -> 0, 1 -> 1-7, 2 -> 8, 3 -> 9-15

    hex 00 00 00 00  ; tile 0
    hex 00 00 00 00  ; tile 1
    hex 00 7f 00 00  ; tile 2
    hex 00 ff 00 00  ; tile 3
    hex 00 00 00 7f  ; tile 4
    hex 00 00 00 ff  ; tile 5
    hex 00 7f 00 7f  ; tile 6
    hex 00 ff 00 ff  ; tile 7
    hex 00 00 00 00  ; tile 8
    hex 00 00 00 00  ; tile 9
    hex 7f 7f 00 00  ; tile 10
    hex ff ff 00 00  ; tile 11
    hex 00 00 7f 7f  ; tile 12
    hex 00 00 ff ff  ; tile 13
    hex 7f 7f 7f 7f  ; tile 14
    hex ff ff ff ff  ; tile 15

; --------------------------------------------------------------------------------------------------

write_name_table:
    ; Write Name Table 0.
    ; 16*14 squares, square = 2*2 tiles.
    ; Each byte in name_table_data specifies the color of 4*1 squares.

    load_ax ppu_name_table0
    jsr set_ppu_address

    ldy #0  ; loop counter
name_table_loop:
    ; Write 8*1 tiles per round.

    ; Data byte -> X. Bits: X=0ABCDEFG, table index=00ABCDFG. (Each byte is used on two tile rows.)
    tya
    and #%01111000
    lsr
    sta temp
    tya
    and #%00000011
    ora temp
    tax
    lda name_table_data, x
    tax
    ; store loop counter
    tya
    pha
    ; write tiles
    jsr write_8_tiles
    ; restore loop counter
    pla
    tay
    ; end loop
    iny
    cpy #(28 * 4)
    bne name_table_loop

    ; pad with 0x00
    lda #$00
    ldx #(2 * 32)
-   sta ppu_data
    dex
    bne -

    rts

write_8_tiles:
    ; Write 8*1 tiles to Name Table.
    ; Y: loop counter (set of 8*1 tiles)
    ; X: data byte from name_table_data
    ; Scrambles A, X, Y.

    ; temp: OR mask (%00000000 if even row, %00001000 if odd)
    tya
    and #%00000100
    asl
    sta temp

    ldy #4
    txa
write_tiles_loop:
    ; Write two tiles per round.
    ; Bits of tile number: 0000VCCH (V = bottom/top half, CC = color, H = left/right half)
    and #%00000011
    asl
    ora temp
    sta ppu_data
    ora #$01
    sta ppu_data
    ; restore data byte, discard two LSBs, store again
    txa
    lsr
    lsr
    tax
    ; end loop
    dey
    bne write_tiles_loop

    rts

; --------------------------------------------------------------------------------------------------

write_attribute_table:
    ; Write Attribute Table 0.

    ; set PPU address
    load_ax ppu_attribute_table0
    jsr set_ppu_address

    ; copy data from table
    ldx #0
-   lda attribute_table_data, x
    sta ppu_data
    inx
    cpx #(7 * 8)
    bne -

    ; pad with 0x00
    lda #$00
    ldx #8
-   sta ppu_data
    dex
    bne -

    rts

attribute_table_data:
    ; 7 * 8 = 56 bytes
    hex bc 5b 18 91 b1 f3 17 79
    hex e9 0d 6e 73 2b 8d fb 64
    hex 88 36 97 47 38 78 4b bc
    hex c8 35 09 be 3a 21 93 ad
    hex 99 c7 37 d6 14 9b 18 88
    hex 14 1b 99 fb a7 5c f4 2a
    hex 78 17 b6 43 0f 6e 29 f8
