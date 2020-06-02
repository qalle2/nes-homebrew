; Initialization

reset:
    initialize_nes

    lda #$00
    sta snd_chn  ; disable sound channels
    sta frame_counter
    sta nmi_done

    wait_vblank

    ; background palette
    load_ax ppu_palette
    jsr set_ppu_address
-   lda background_palette, x
    sta ppu_data
    inx
    cpx #16
    bne -

    jsr generate_chr_ram_data
    jsr write_name_table

    ; attribute table - copy from table
    ldx #0
-   lda attribute_table_data, x
    sta ppu_data
    inx
    cpx #(7 * 8)
    bne -

    ; fill end of attribute table with $00
    lda #$00
    ldx #8
    jsr fill_vram

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

background_palette:
    hex 0f 12 14 16  ; black, blue, purple, red
    hex 0f 18 1a 1c  ; black, yellow, green, teal
    hex 0f 22 24 26  ; like 1st subpalette but lighter foreground colors
    hex 0f 28 2a 2c  ; like 2nd subpalette but lighter foreground colors

; --------------------------------------------------------------------------------------------------

generate_chr_ram_data:
    ; Generate CHR RAM data from RLE data.

    lda #$00
    tax
    jsr set_ppu_address

    ; X is also RLE pointer
rle_loop:
    ; get CHR byte from RLE byte via LUT, push it
    lda chr_rle_data, x
    and #$03
    tay
    lda chr_bytes, y
    pha
    ; get RLE count
    lda chr_rle_data, x
    lsr
    lsr
    tay
    ; write CHR byte Y times
    pla
-   sta ppu_data
    dey
    bne -
    ; end loop
    inx
    cpx #(chr_rle_data_end - chr_rle_data)
    bne rle_loop

rle_exit:
    rts

chr_rle_data:
    ; RLE-compressed CHR RAM data (16 tiles, 256 bytes).
    ; Bits: CCCCCCII (C=count, I=index to chr_bytes).

    ; uncompressed data:
    ; 00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00
    ; 00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00
    ; 00 7f 7f 7f 7f 7f 7f 7f   00 00 00 00 00 00 00 00
    ; 00 ff ff ff ff ff ff ff   00 00 00 00 00 00 00 00
    ; 00 00 00 00 00 00 00 00   00 7f 7f 7f 7f 7f 7f 7f
    ; 00 00 00 00 00 00 00 00   00 ff ff ff ff ff ff ff
    ; 00 7f 7f 7f 7f 7f 7f 7f   00 7f 7f 7f 7f 7f 7f 7f
    ; 00 ff ff ff ff ff ff ff   00 ff ff ff ff ff ff ff
    ; 00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00
    ; 00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00
    ; 7f 7f 7f 7f 7f 7f 7f 7f   00 00 00 00 00 00 00 00
    ; ff ff ff ff ff ff ff ff   00 00 00 00 00 00 00 00
    ; 00 00 00 00 00 00 00 00   7f 7f 7f 7f 7f 7f 7f 7f
    ; 00 00 00 00 00 00 00 00   ff ff ff ff ff ff ff ff
    ; 7f 7f 7f 7f 7f 7f 7f 7f   7f 7f 7f 7f 7f 7f 7f 7f
    ; ff ff ff ff ff ff ff ff   ff ff ff ff ff ff ff ff

    ; tiles $00-$04
    db (33 << 2) | 0
    db ( 7 << 2) | 1
    db ( 9 << 2) | 0
    db ( 7 << 2) | 2
    db (17 << 2) | 0
    db ( 7 << 2) | 1

    ; tile $05
    db ( 9 << 2) | 0
    db ( 7 << 2) | 2

    ; tiles $06-$07
    db ( 1 << 2) | 0
    db ( 7 << 2) | 1
    db ( 1 << 2) | 0
    db ( 7 << 2) | 1
    db ( 1 << 2) | 0
    db ( 7 << 2) | 2
    db ( 1 << 2) | 0
    db ( 7 << 2) | 2

    ; tiles $08-$09
    db (32 << 2) | 0

    ; tile $0a
    db ( 8 << 2) | 1
    db ( 8 << 2) | 0

    ; tiles $0b-$0c
    db ( 8 << 2) | 2
    db (16 << 2) | 0
    db ( 8 << 2) | 1

    ; tile $0d
    db ( 8 << 2) | 0
    db ( 8 << 2) | 2

    ; tile $0e
    db (16 << 2) | 1

    ; tile $0f
    db (16 << 2) | 2
chr_rle_data_end:

chr_bytes:
    hex 00 7f ff

; --------------------------------------------------------------------------------------------------

write_name_table:
    ; Write Name Table 0.
    ; 16*14 squares, square = 2*2 tiles.
    ; Each byte in name_table_data specifies 4*1 squares.

    load_ax ppu_name_table0
    jsr set_ppu_address

    ldx #0  ; loop counter
name_table_loop:
    ; Write 8*1 tiles per round.

    ; Data byte -> Y. Bits: X=0ABCDEFG, table index=00ABCDFG. (Each byte is used on two tile rows.)
    txa
    and #%01111000
    lsr
    sta temp
    txa
    and #%00000011
    ora temp
    tay
    lda name_table_data, y
    tay
    ; temp: %00000000 if even row, %00001000 if odd
    txa
    and #%00000100
    asl
    sta temp
    ; store loop counter
    stx temp2
    ; write tiles
    jsr write_8_tiles
    ; end loop
    ldx temp2
    inx
    cpx #(28 * 4)
    bne name_table_loop

    ; fill end of name table with $00
    lda #$00
    ldx #(2 * 32)
    jsr fill_vram

    rts

write_8_tiles:
    ; Write 8*1 tiles to Name Table.
    ; Y:    data byte from name_table_data
    ; temp: row number (%00000000=even, %00001000=odd)
    ; Scrambles A, X, Y.

    ldx #4
    tya
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
    tya
    lsr
    lsr
    tay
    ; end loop
    dex
    bne write_tiles_loop

    rts

fill_vram:
    ; write A X times
-   sta ppu_data
    dex
    bne -
    rts

name_table_data:
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

attribute_table_data:
    ; 7 * 8 = 56 bytes
    hex bc 5b 18 91 b1 f3 17 79
    hex e9 0d 6e 73 2b 8d fb 64
    hex 88 36 97 47 38 78 4b bc
    hex c8 35 09 be 3a 21 93 ad
    hex 99 c7 37 d6 14 9b 18 88
    hex 14 1b 99 fb a7 5c f4 2a
    hex 78 17 b6 43 0f 6e 29 f8
