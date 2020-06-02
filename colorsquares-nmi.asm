nmi:
    push_all

    ; read current color of first square
    lda moving_square1_x
    sta square_x
    lda moving_square1_y
    sta square_y
    jsr set_name_table_address  ; in: square_x, square_y; out: X, A
    lda ppu_data  ; garbage read
    lda ppu_data
    pha
    jsr read_square_from_attribute_table  ; in: square_x, square_y; out: A
    pha

    ; read current color of second square
    lda moving_square2_x
    sta square_x
    lda moving_square2_y
    sta square_y
    jsr set_name_table_address  ; in: square_x, square_y; out: X, A
    lda ppu_data  ; garbage read
    lda ppu_data
    sta square_old_nt_value2
    jsr read_square_from_attribute_table  ; in: square_x, square_y; out: A
    sta square_old_at_value2

    ; write new second square
    pla
    tay
    jsr write_square_to_attribute_table  ; in: Y, square_X, square_Y
    pla
    tay
    jsr write_square_to_name_table

    ; write new first square
    lda moving_square1_x
    sta square_x
    lda moving_square1_y
    sta square_y
    ldy square_old_nt_value2
    jsr write_square_to_name_table
    ldy square_old_at_value2
    jsr write_square_to_attribute_table  ; in: Y, square_X, square_Y

    jsr reset_ppu_address

    lda #1
    sta nmi_done

    pull_all
    rti

set_name_table_address:
    ; Set VRAM address to top left tile of (square_x, square_y) in name table.
    ; Also return: A=low byte, X=high byte.
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

write_square_to_name_table:
    ; Write Y to name table at (square_x, square_y).

    ; top row
    jsr set_name_table_address  ; in: square_x, square_y; out: X, A
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
    ; Bits: square_y: 0000ABCD, square_x: 0000abcd, VRAM address: 00100011 11ABCabc

    ; high byte
    lda #>ppu_attribute_table0
    sta ppu_addr

    ; low byte
    lda square_y                ; 0000ABCD
    and #%00001110              ; 0000ABC0
    rept 3
        asl                     ; 0ABC0000
    endr
    ora square_x                ; 0ABCabcd
    lsr                         ; 00ABCabc
    ora #<ppu_attribute_table0  ; 11ABCabc
    sta ppu_addr

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

and_masks:
    ; AND bitmasks for attribute table data
    db %11111100, %11110011, %11001111, %00111111
