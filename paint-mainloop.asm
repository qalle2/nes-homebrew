main_loop:
    bit nmi_done
    bpl main_loop  ; branch if flag clear

    lda joypad_status
    sta prev_joypad_status
    jsr read_joypad

    ; run one of two subs
    bit in_palette_editor
    bmi +                  ; branch if flag set
    jsr main_loop_paint_mode
    jmp main_loop_end
+   jsr main_loop_palette_edit_mode

main_loop_end:
    lsr nmi_done  ; clear flag
    jmp main_loop

; --------------------------------------------------------------------------------------------------

read_joypad:
    ; Read joypad status, save to joypad_status.
    ; Bits: A, B, select, start, up, down, left, right.

    ldx #$01
    stx joypad_status  ; to detect end of loop
    stx joypad1
    dex
    stx joypad1

-   clc
    lda joypad1
    and #$03
    beq +
    sec
+   rol joypad_status
    bcc -

    rts

; --------------------------------------------------------------------------------------------------

main_loop_paint_mode:
    ; ignore B, select, start if any of them was pressed on previous frame
    lda prev_joypad_status
    and #(button_b | button_select | button_start)
    bne arrow_stuff

    ; check B, select, start
    lda joypad_status
    cmp #button_b
    beq change_color          ; ends with rts
    cmp #button_select
    beq enter_palette_editor  ; ends with rts
    cmp #button_start
    beq change_cursor_type    ; ends with rts

arrow_stuff:
    ; if no arrow pressed, clear cursor movement delay
    lda joypad_status
    and #$0f
    bne +
    sta delay_left
    jmp buttons_done
    ; else if delay > 0, decrement it
+   lda delay_left
    beq +
    dec delay_left
    jmp buttons_done
    ; else react to arrows and reinitialize delay
+   jsr check_horizontal_arrows
    jsr check_vertical_arrows
    lda #cursor_move_delay
    sta delay_left

buttons_done:
    ; make sprite data reflect changes to cursor
    jsr update_paint_mode_sprite_data

    ; if A pressed, tell NMI routine to paint
    lda joypad_status
    and #button_a
    beq +

    jsr get_paint_area_offset  ; cursor_x, cursor_y -> paint_area_offset (0-767)
    jsr update_nt_buffer       ; update nt_buffer according to paint_area_offset/etc.

    ; set flag
    sec
    ror do_paint

+   rts

; --------------------------------------------------------------------------------------------------

change_color:
    ; cycle between 4 colors
    ldx color
    inx
    txa
    and #%00000011
    sta color
    rts

; --------------------------------------------------------------------------------------------------

enter_palette_editor:
    ; init palette cursor position, hide paint cursor
    ldx #0
    stx palette_cursor
    dex
    stx sprite_data + 0 + 0

    ; show palette editor sprites
    ldx #((13 - 1) * 4)
-   lda initial_sprite_data + 9 * 4, x
    sta sprite_data + 9 * 4, x
    dex
    dex
    dex
    dex
    bpl -

    ; set flag
    sec
    ror in_palette_editor

    rts

; --------------------------------------------------------------------------------------------------

change_cursor_type:
    ; toggle between small and big cursor, update sprite tile
    lda cursor_type
    eor #%00000001
    sta cursor_type
    ora #2
    sta sprite_data + 0 + 1

    ; if big, make coordinates even
    beq +
    lsr cursor_x
    asl cursor_x
    lsr cursor_y
    asl cursor_y

+   rts

; --------------------------------------------------------------------------------------------------

check_horizontal_arrows:
    ; React to left/right arrow.
    ; Reads: joypad_status, cursor_x, cursor_type
    ; Changes: cursor_x

    lda joypad_status
    lsr
    bcs paint_right
    lsr
    bcs paint_left
    rts
paint_right:
    lda cursor_x
    sec
    adc cursor_type
    jmp store_horizontal
paint_left:
    lda cursor_x
    clc
    sbc cursor_type
store_horizontal:
    and #%00111111
    sta cursor_x
    rts

check_vertical_arrows:
    ; React to up/down arrow.
    ; Reads: joypad_status, cursor_x, cursor_type
    ; Changes: cursor_x

    lda joypad_status
    lsr
    lsr
    lsr
    bcs paint_cursor_down
    lsr
    bcs paint_cursor_up
    rts
paint_cursor_down:
    lda cursor_y
    sec
    adc cursor_type
    cmp #48
    bne store_vertical
    lda #0
    jmp store_vertical
paint_cursor_up:
    lda cursor_y
    clc
    sbc cursor_type
    bpl store_vertical
    lda #48
    clc
    sbc cursor_type
store_vertical:
    and #%00111111
    sta cursor_y
    rts

; --------------------------------------------------------------------------------------------------

update_paint_mode_sprite_data:
    ; Update sprite data regarding cursor position.

    ; cursor sprite X position
    lda cursor_x
    asl
    asl
    ldx cursor_type
    bne +
    clc
    adc #2               ; center small cursor on "pixel"
+   sta sprite_data + 0 + 3

    ; cursor sprite Y position
    lda cursor_y
    asl
    asl
    clc
    adc #(4 * 8 - 1)
    ldx cursor_type
    bne +
    clc
    adc #2               ; center small cursor on "pixel"
+   sta sprite_data + 0 + 0

    ; tiles of X position sprites
    lda cursor_x
    pha
    jsr to_decimal_tens_tile
    sta sprite_data + 4 + 1
    pla
    jsr to_decimal_ones_tile
    sta sprite_data + 2 * 4 + 1

    ; tiles of Y position sprites
    lda cursor_y
    pha
    jsr to_decimal_tens_tile
    sta sprite_data + 3 * 4 + 1
    pla
    jsr to_decimal_ones_tile
    sta sprite_data + 4 * 4 + 1

    rts

get_paint_area_offset:
    ; Compute offset within name table data of paint area from cursor_x and cursor_y.
    ; Bits of cursor_y (0-47 or %000000-%101111): ABCDEF
    ; Bits of cursor_x (0-63 or %000000-%111111): abcdef
    ; Bits of paint_area_offset (0-767):          000000AB CDEabcde

    ; high byte
    lda cursor_y  ; 00ABCDEF
    lsr
    lsr
    lsr
    lsr           ; 000000AB
    sta paint_area_offset + 1

    ; low byte
    lda cursor_y    ; 00ABCDEF
    and #$0e        ; 0000CDE0
    asl
    asl
    asl
    asl
    sta temp        ; CDE00000
    lda cursor_x    ; 00abcdef
    lsr             ; 000abcde
    ora temp        ; CDEabcde
    sta paint_area_offset + 0

    rts

; --------------------------------------------------------------------------------------------------

update_nt_buffer:
    ; Update a byte in nt_buffer.
    ; In: cursor_type, cursor_x, cursor_y, color, paint_area_offset, nt_buffer
    ; Writes: nt_buffer

    ; compute address within nt_buffer (nt_buffer + paint_area_offset -> pointer)
    clc
    lda paint_area_offset + 0
    sta pointer + 0
    lda paint_area_offset + 1
    adc #>nt_buffer
    sta pointer + 1

    ; get old byte
    lda cursor_type
    beq small_cursor

    ; big cursor
    ldx color
    lda solid_color_tiles, x
    jmp update_nt_buffer_byte

small_cursor:
    ; push old byte
    ldy #0
    lda (pointer), y
    pha
    ; position within tile (0-3) -> X
    lda cursor_x
    ror
    lda cursor_y
    rol
    and #%00000011
    tax
    ; position_within_tile * 4 + color -> Y
    asl
    asl
    ora color
    tay
    ; pull old byte, clear some bits, replace with new bits
    pla
    and and_masks, x
    ora or_masks, y

update_nt_buffer_byte:
    ldy #0
    sta (pointer), y
    rts

solid_color_tiles:
    ; tiles of solid color 0/1/2/3
    db %00000000, %01010101, %10101010, %11111111

and_masks:
    db %00111111, %11001111, %11110011, %11111100

or_masks:
    db %00000000, %01000000, %10000000, %11000000
    db %00000000, %00010000, %00100000, %00110000
    db %00000000, %00000100, %00001000, %00001100
    db %00000000, %00000001, %00000010, %00000011

; --------------------------------------------------------------------------------------------------

to_decimal_tens_tile:
    ; In: A = unsigned integer
    ; Out: A = tile number for decimal tens

    ldx #$ff
    sec
-   inx
    sbc #10
    bcs -

    txa
    adc #$0a  ; tile number for "0"
    rts

to_decimal_ones_tile:
    ; In: A = unsigned integer
    ; Out: A = tile number for decimal ones

    sec
-   sbc #10
    bcs -
    adc #10

    clc
    adc #$0a  ; tile number for "0"
    rts

; --------------------------------------------------------------------------------------------------

main_loop_palette_edit_mode:
    ; get color at cursor
    ldx palette_cursor
    ldy user_palette, x

    ; react to buttons if nothing was pressed on previous frame
    lda prev_joypad_status
    bne palette_edit_button_read_done
    lda joypad_status
    cmp #button_up
    beq palette_cursor_up
    cmp #button_down
    beq palette_cursor_down
    cmp #button_left
    beq small_color_decrement
    cmp #button_right
    beq small_color_increment
    cmp #button_b
    beq large_color_decrement
    cmp #button_a
    beq large_color_increment
    cmp #button_select
    beq exit_palette_edit_mode
    jmp palette_edit_button_read_done
palette_cursor_up:
    dex
    dex
palette_cursor_down:
    inx
    txa
    and #%00000011
    sta palette_cursor
    tax
    jmp palette_edit_button_read_done
small_color_decrement:
    dey
    dey
small_color_increment:
    iny
    tya
    and #$0f
    sta temp
    lda user_palette, x
    and #$f0
    ora temp
    sta user_palette, x
    jmp palette_edit_button_read_done
large_color_decrement:
    tya
    sec
    sbc #$10
    jmp +
large_color_increment:
    tya
    clc
    adc #$10
+   and #%00111111
    sta user_palette, x
    jmp palette_edit_button_read_done

exit_palette_edit_mode:
    ; hide palette editor sprites
    lda #$ff
    ldx #((13 - 1) * 4)
-   sta sprite_data + 9 * 4, x
    dex
    dex
    dex
    dex
    bpl -

    lsr in_palette_editor  ; clear flag
    rts

palette_edit_button_read_done:
    ldx palette_cursor

    ; cursor sprite Y position
    txa
    asl
    asl
    asl
    clc
    adc #(22 * 8 - 1)
    sta sprite_data + 9 * 4 + 0

    ; 16s of color number (sprite tile)
    lda user_palette, x
    lsr
    lsr
    lsr
    lsr
    clc
    adc #10
    sta sprite_data + (9 + 5) * 4 + 1

    ; ones of color number (sprite tile)
    lda user_palette, x
    and #$0f
    clc
    adc #$0a
    sta sprite_data + (9 + 6) * 4 + 1

    rts

