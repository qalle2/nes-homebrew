    ; value to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

    ; CPU memory space

    frame_counter        equ $00
    square_x             equ $01  ; 0-15
    square_y             equ $02  ; 0-14
    moving_square1_x     equ $03
    moving_square1_y     equ $04
    moving_square2_x     equ $05
    moving_square2_y     equ $06
    square_old_nt_value1 equ $07
    square_old_nt_value2 equ $08
    square_old_at_value1 equ $09
    square_old_at_value2 equ $0a
    temp                 equ $0b
    temp2                equ $0c

    ppu_ctrl   equ $2000
    ppu_mask   equ $2001
    ppu_status equ $2002
    ppu_scroll equ $2005
    ppu_addr   equ $2006
    ppu_data   equ $2007

    ; PPU memory space

    ppu_name_table0      equ $2000
    ppu_attribute_table0 equ $23c0
    ppu_palette          equ $3f00

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 1  ; name table mirroring: vertical
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

    org $c000
reset:
    lda #$00
    sta ppu_ctrl  ; disable NMI
    sta ppu_mask  ; hide background&sprites

    ; wait for start of VBlank, then wait for next VBlank
    bit ppu_status
-   bit ppu_status
    bpl -
-   bit ppu_status
    bpl -

    ; background palette
    lda #>ppu_palette
    sta ppu_addr
    ldx #$00
    stx ppu_addr
-   lda background_palette, x
    sta ppu_data
    inx
    cpx #16
    bne -

    ; copy CHR data to CHR RAM
    jsr reset_vram_address
    ldx #0
-   lda chr_data, x
    sta ppu_data
    inx
    bne -

    ; name table
    lda #>ppu_name_table0
    sta ppu_addr
    lda #<ppu_name_table0
    sta ppu_addr

    ; write the name table;
    ; each byte in name_table_data specifies 4*1 squares (2*2 tiles each)
    ldx #0
--  ; Read data byte. Bits: X: 0abcdefg --> table index: 00abcdfg.
    ; I.e., each data byte is used on two rows.
    txa
    and #%11111000
    lsr
    sta temp
    txa
    and #%00000011
    ora temp
    tay
    lda name_table_data, y
    tay
    ; %00000000 if on even row, %00001000 if odd
    txa
    and #%00000100
    asl
    sta temp
    ; store loop counter
    stx temp2
    ; write 4 tile pairs specified by the data byte
    ; bits of tile number: 0000VCCH (V = bottom/top half, CC = color, H = left/right half)
    tya
    ldx #4
-   and #%00000011
    asl            ; color
    adc temp       ; top/bottom half
    sta ppu_data   ; left corner
    adc #1
    sta ppu_data   ; right corner
    tya
    lsr
    lsr
    tay
    dex
    bne -
    ; end of loop
    ldx temp2
    inx
    cpx #(56 * 2)
    bne --

    ; fill end of name table with $00
    lda #$00
    ldx #(2 * 32)
-   sta ppu_data
    dex
    bne -

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
-   sta ppu_data
    dex
    bne -

    jsr reset_vram_address

    ; scroll 8 pixels down to center the active area vertically
    lda #0
    sta ppu_scroll
    lda #(240 - 8)
    sta ppu_scroll

    ; wait for start of VBlank
    bit ppu_status
-   bit ppu_status
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
    inc frame_counter

    ; the location of the left or top square of the square pair to swap
    ldx frame_counter
    lda shuffle_data, x
    tay
    rept 4
        lsr
    endr
    sta moving_square1_x
    sta moving_square2_x
    tya
    and #%00001111
    sta moving_square1_y
    sta moving_square2_y

    ; the another square of the pair is to the right or below on alternating frames
    txa
    and #%00000001
    tax
    inc moving_square2_x, x  ; moving_square2_x or moving_square2_y

    ; read current color of first square
    lda moving_square1_x
    sta square_x
    lda moving_square1_y
    sta square_y
    jsr read_square_from_name_table
    sta square_old_nt_value1
    jsr read_square_from_attribute_table
    sta square_old_at_value1

    ; read current color of second square
    lda moving_square2_x
    sta square_x
    lda moving_square2_y
    sta square_y
    jsr read_square_from_name_table
    sta square_old_nt_value2
    jsr read_square_from_attribute_table
    sta square_old_at_value2

    ; write new second square
    ldy square_old_nt_value1
    jsr write_square_to_name_table
    ldy square_old_at_value1
    jsr write_square_to_attribute_table

    ; write new first square
    lda moving_square1_x
    sta square_x
    lda moving_square1_y
    sta square_y
    ldy square_old_nt_value2
    jsr write_square_to_name_table
    ldy square_old_at_value2
    jsr write_square_to_attribute_table

    jsr reset_vram_address

    ; scroll 8 pixels down to center the active area vertically
    lda #0
    sta ppu_scroll
    lda #(240 - 8)
    sta ppu_scroll
    rti

; --------------------------------------------------------------------------------------------------
; Subroutines

reset_vram_address:
    lda #$00
    sta ppu_addr
    sta ppu_addr
    rts

set_name_table_address:
    ; Set VRAM address to top left tile of (square_x, square_y) in name table.
    ; High byte of address returned in X, low byte in A.
    ; Bits: square_y: 0000ABCD, square_x: 0000EFGH, VRAM address: 001000AB CD0EFGH0

    ; high byte
    lda square_y
    lsr
    lsr
    ora #%00100000
    sta ppu_addr
    tax

    ; low byte
    lda square_y  ; 0000ABCD
    lsr           ; 00000ABC, carry=D
    ror           ; D00000AB, carry=C
    ror           ; CD00000A, carry=B
    lsr           ; 0CD00000, carry=A
    ora square_x  ; 0CD0EFGH, carry=A
    asl           ; CD0EFGH0
    sta ppu_addr
    rts

read_square_from_name_table:
    ; Return value of (square_x, square_y) in A.

    jsr set_name_table_address
    lda ppu_data
    lda ppu_data
    rts

write_square_to_name_table:
    ; Write Y to name table at (square_x, square_y).

    ; top row
    jsr set_name_table_address
    sty ppu_data
    iny
    sty ppu_data

    ; bottom row
    stx ppu_addr
    ora #%00100000
    sta ppu_addr
    dey
    tya
    ora #%00001000
    sta ppu_data
    tay
    iny
    sty ppu_data
    rts

set_attribute_table_address:
    ; Set VRAM address to (square_x, square_y) in attribute table.
    ; Bits: square_y: 0000ABCD, square_x: 0000EFGH, VRAM address: 00100011 11ABCEFG

    ; high byte
    lda #>ppu_attribute_table0
    sta ppu_addr

    ; low byte
    lda square_y    ; 0000ABCD
    and #%00001110  ; 0000ABC0
    rept 3
        asl         ; 0ABC0000
    endr
    ora #%10000000  ; 1ABC0000
    ora square_x    ; 1ABCEFGH
    sec
    ror             ; 11ABCEFG
    sta ppu_addr

    ; optimization: replace ora&ora&sec&ror above with:
    ;     ora square_x    ; 0ABCEFGH
    ;     lsr             ; 00ABCEFG
    ;     ora #%11000000  ; 11ABCEFG

    rts

get_attribute_byte_bit_position:
    ; Return position of (square_x, square_y) within attribute byte in X (0-3).
    ; Bits: square_y: 0000ABCD, square_x: 0000EFGH, position: 000000DH

    lda square_x
    lsr
    lda square_y
    rol
    and #%00000011
    tax
    rts

read_square_from_attribute_table:
    ; Return value of (square_x, square_y) in attribute table in A (0-3).

    jsr set_attribute_table_address
    jsr get_attribute_byte_bit_position
    lda ppu_data
    lda ppu_data

    ; shift important bits to least significant positions
    cpx #0
    beq +
-   lsr
    lsr
    dex
    bne -
+   and #%00000011
    rts

write_square_to_attribute_table:
    ; Write Y (0-3) to attribute table at (square_x, square_y).

    ; read old byte, get bit position to change
    jsr set_attribute_table_address
    jsr get_attribute_byte_bit_position
    lda ppu_data
    lda ppu_data

    ; clear bits to change
    and and_masks, x
    sta temp

    ; shift new bits to correct position, combine with old byte
    tya
    cpx #0
    beq +
-   asl
    asl
    dex
    bne -
+   ora temp
    tax

    jsr set_attribute_table_address
    stx ppu_data
    rts

; --------------------------------------------------------------------------------------------------
; Tables

and_masks:
    ; AND bitmasks for attribute table data
    db %11111100, %11110011, %11001111, %00111111

background_palette:
    hex 0f 12 14 16  ; black, blue, purple, red
    hex 0f 18 1a 1c  ; black, yellow, green, teal
    hex 0f 22 24 26  ; like 1st subpalette but lighter foreground colors
    hex 0f 28 2a 2c  ; like 2nd subpalette but lighter foreground colors

chr_data:
    ; each tile represents a quarter of a 16*16-px square
    hex  00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00  ; $00: color 0, top    left
    hex  00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00  ; $01: color 0, top    right
    hex  00 7f 7f 7f 7f 7f 7f 7f   00 00 00 00 00 00 00 00  ; $02: color 1, top    left
    hex  00 ff ff ff ff ff ff ff   00 00 00 00 00 00 00 00  ; $03: color 1, top    right
    hex  00 00 00 00 00 00 00 00   00 7f 7f 7f 7f 7f 7f 7f  ; $04: color 2, top    left
    hex  00 00 00 00 00 00 00 00   00 ff ff ff ff ff ff ff  ; $05: color 2, top    right
    hex  00 7f 7f 7f 7f 7f 7f 7f   00 7f 7f 7f 7f 7f 7f 7f  ; $06: color 3, top    left
    hex  00 ff ff ff ff ff ff ff   00 ff ff ff ff ff ff ff  ; $07: color 3, top    right
    hex  00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00  ; $08: color 0, bottom left
    hex  00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00  ; $09: color 0, bottom right
    hex  7f 7f 7f 7f 7f 7f 7f 7f   00 00 00 00 00 00 00 00  ; $0a: color 1, bottom left
    hex  ff ff ff ff ff ff ff ff   00 00 00 00 00 00 00 00  ; $0b: color 1, bottom right
    hex  00 00 00 00 00 00 00 00   7f 7f 7f 7f 7f 7f 7f 7f  ; $0c: color 2, bottom left
    hex  00 00 00 00 00 00 00 00   ff ff ff ff ff ff ff ff  ; $0d: color 2, bottom right
    hex  7f 7f 7f 7f 7f 7f 7f 7f   7f 7f 7f 7f 7f 7f 7f 7f  ; $0e: color 3, bottom left
    hex  ff ff ff ff ff ff ff ff   ff ff ff ff ff ff ff ff  ; $0f: color 3, bottom right

name_table_data:
    ; 56 bytes
    hex 66 77 7b af ed 99 da e6
    hex 56 99 65 ae 6a e6 76 db
    hex a7 bd 9f d5 fd df 6b a7
    hex eb 65 99 b6 59 f6 ff d9
    hex 7b e5 65 75 6e e7 a6 ef
    hex fb 5f 69 9e 55 65 bb 79
    hex 6b 9f 66 ea a6 6f bb 9e

attribute_table_data:
    ; 56 bytes
    hex bc 5b 18 91 b1 f3 17 79
    hex e9 0d 6e 73 2b 8d fb 64
    hex 88 36 97 47 38 78 4b bc
    hex c8 35 09 be 3a 21 93 ad
    hex 99 c7 37 d6 14 9b 18 88
    hex 14 1b 99 fb a7 5c f4 2a
    hex 78 17 b6 43 0f 6e 29 f8

shuffle_data:
    ; 256 bytes
    hex 2b 35 c4 71 5c b0 46 15 c6 80 d2 18 dc 27 bb 84
    hex c6 7c 8d 59 e7 f9 8c 46 54 fc 64 ab 04 46 88 83
    hex 2b 89 06 98 33 2c 42 b1 6a 04 43 34 75 66 61 65
    hex 05 2c 17 16 98 cb 85 9a 78 15 03 8b bb 23 b8 b3
    hex 6a 3c 06 86 c2 88 0d e0 1c b7 d5 20 70 46 59 ec
    hex 30 11 ca 57 64 47 c9 77 93 e4 5b 60 35 e3 a3 22
    hex 88 51 b6 c1 e5 53 9a c0 96 c6 b4 78 a3 66 ac 54
    hex 48 b9 dd d6 29 34 9c 37 91 d9 a0 37 89 77 b5 36
    hex ad 4a a2 65 c4 a9 80 e3 49 d1 65 5b 7d 0c 00 56
    hex aa 96 12 f6 75 d4 a9 b6 28 ba c5 55 5d 51 d5 f6
    hex 7b 2c a9 ea 1a 04 ba 56 d2 e1 15 78 c8 d9 88 28
    hex 4c 08 8a 52 45 f1 35 32 28 f6 20 ba ab 6b 71 c8
    hex 38 61 4a 42 0d 80 d5 b0 bd b8 47 f8 d2 05 ca 7a
    hex 78 c0 07 6b 13 f9 19 b2 45 63 65 c7 36 18 5b a1
    hex 65 f4 55 20 5b c0 cc 06 9b 54 08 79 91 2b 10 83
    hex 44 1c 90 d1 c1 aa 7b 66 7d 5c 08 5c 08 48 d5 17

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    dw nmi, reset, 0
