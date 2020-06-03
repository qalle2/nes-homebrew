nmi:
    ; TODO: modify name_table_data in CPU RAM and update the change to VRAM instead of reading
    ; VRAM.

    push_all

    ; access first square
    copy moving_square1_x, square_x
    copy moving_square1_y, square_y

    ; read & push tile number and attribute color (1-3)
    jsr set_name_table_address  ; square_x, square_y -> X, A
    lda ppu_data                ; garbage read
    lda ppu_data
    pha
    jsr get_square_attribute
    pha

    ; access second square
    copy moving_square2_x, square_x
    copy moving_square2_y, square_y

    ; read & push tile number and attribute color (1-3)
    jsr set_name_table_address  ; square_x, square_y -> X, A
    lda ppu_data                ; garbage read
    lda ppu_data
    pha
    jsr get_square_attribute
    pha

    ; access first square
    copy moving_square1_x, square_x
    copy moving_square1_y, square_y

    ; write new values
    pull_y
    jsr set_square_attribute        ; Y, square_x, square_y -> none
    pull_y
    jsr write_square_to_name_table  ; Y, square_x, square_y -> none

    ; access second square
    copy moving_square2_x, square_x
    copy moving_square2_y, square_y

    ; write new values
    pull_y
    jsr set_square_attribute        ; Y, square_x, square_y -> none
    pull_y
    jsr write_square_to_name_table  ; Y, square_x, square_y -> none

    jsr reset_ppu_address

    lda #1
    sta nmi_done

    pull_all
    rti

; --------------------------------------------------------------------------------------------------

set_name_table_address:
    ; Set VRAM address to top left tile of specified square in name table.
    ; called by: nmi, write_square_to_name_table
    ; in: square_x, square_y
    ; out: X=high byte, A=low byte
    ; scrambles: -

    ; bits: square_y=0000ABCD, square_x=0000EFGH -> X=001000AB, A=CD0EFGH0

    bit ppu_status

    ; high byte
    lda square_y
    lsr
    lsr
    ora #$20
    sta ppu_addr
    tax

    ; low byte
    lda square_y
    lsr
    ror
    ror
    lsr
    ora square_x
    asl
    sta ppu_addr

    rts

write_square_to_name_table:
    ; Write square to name table.
    ; called by: nmi
    ; in: Y (0/2/4/6), square_x, square_y
    ; scrambles: A, X, Y

    ; top row
    jsr set_name_table_address  ; square_x, square_y -> X, A
    sty ppu_data
    iny
    sty ppu_data

    ; bottom row
    stx ppu_addr
    ora #$20
    sta ppu_addr
    dey
    tya
    ora #$08
    sta ppu_data
    tay
    iny
    sty ppu_data
    rts

; --------------------------------------------------------------------------------------------------

get_square_attribute:
    ; Get attribute color of specified square.
    ; called by: nmi
    ; in: square_x, square_y
    ; out: A (1-3)
    ; scrambles: A, X

    ; get bit position of attribute block within byte
    lda square_x
    lsr
    lda square_y
    rol
    and #$03
    tax

    ; set PPU address
    ; bits: square_y: 0000ABCD, square_x: 0000abcd -> 00100011 11ABCabc
    ; high byte
    lda #$23
    sta ppu_addr
    ; low byte
    lda square_y
    and #$0e
    asl
    asl
    asl
    ora square_x
    lsr
    ora #$c0
    sta ppu_addr

    ; read byte
    lda ppu_data
    lda ppu_data

    ; shift important bits to LSBs
    cpx #0
    beq shift_done
-   lsr
    lsr
    dex
    bne -
shift_done:
    and #$03

    rts

set_square_attribute:
    ; Write attribute color to specified square.
    ; called by: nmi
    ; in: Y (0-3), square_x, square_y
    ; scrambles: A, X, Y

    ; get bit position of attribute block within byte
    lda square_x
    lsr
    lda square_y
    rol
    and #$03
    tax

    ; set PPU address, push for later use
    ; bits: square_y: 0000ABCD, square_x: 0000abcd -> 00100011 11ABCabc
    ; high byte
    lda #$23
    sta ppu_addr
    pha
    ; low byte
    lda square_y
    and #$0e
    asl
    asl
    asl
    ora square_x
    lsr
    ora #$c0
    sta ppu_addr
    pha

    ; read old byte
    lda ppu_data
    lda ppu_data

    ; clear bits to change
    and and_masks, x
    sta temp

    ; shift new bits to correct position, combine with old byte
    tya
    cpx #0
    beq shift_done2
-   asl
    asl
    dex
    bne -
shift_done2:

    ; combine old and new bits
    ora temp
    tax

    ; pull & set PPU address
    pull_y
    pla
    sta ppu_addr
    sty ppu_addr

    ; write new byte
    stx ppu_data

    rts

and_masks:
    ; AND bitmasks for attribute table data
    hex fc f3 cf 3f
