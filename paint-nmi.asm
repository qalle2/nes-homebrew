; TODO: move stuff to main loop

nmi:
    push_all

    bit mode
    bmi +
    jsr nmi_paint_mode
    jmp nmi_end
+   jsr nmi_palette_edit_mode

nmi_end:
    ; update sprite data
    lda #>sprite_data
    sta oam_dma

    ; clear VRAM address & scroll
    load_ax $0000
    jsr set_vram_address
    sta ppu_scroll
    sta ppu_scroll

    sec
    ror nmi_done  ; set flag

    pull_all
    rti

; --------------------------------------------------------------------------------------------------

nmi_paint_mode:
    ; only react to select, start and B if none of them was pressed on previous frame
    lda prev_joypad_status
    and #(button_b | button_select | button_start)
    bne paint_button_read_done
    lda joypad_status
    and #(button_b | button_select | button_start)
    cmp #button_select
    beq enter_palette_editor
    cmp #button_start
    beq change_cursor_type
    cmp #button_b
    beq change_color
    jmp paint_button_read_done
enter_palette_editor:
    ; show palette editor sprites
    ldx #(palette_editor_sprite_count * 4 - 1)
-   lda palette_editor_sprites, x
    sta sprite_data + paint_mode_sprite_count * 4, x
    dex
    bpl -
    ; hide paint cursor
    lda #$ff
    sta sprite_data
    ; switch mode (set MSB)
    sec
    ror mode
    ; initialize palette cursor position
    lda #0
    sta palette_cursor
    rts
change_cursor_type:
    lda cursor_type
    eor #%00000001
    sta cursor_type
    ; if switched to big (square) cursor, make cursor X and Y position even
    beq +
    lda cursor_x
    and #%00111110
    sta cursor_x
    lda cursor_y
    and #%00111110
    sta cursor_y
+   jmp paint_button_read_done
change_color:
    ; cycle between 4 colors
    ldx color
    inx
    txa
    and #%00000011
    sta color

paint_button_read_done:
    ; react to arrows only if cursor movement delay has passed
    dec delay_left
    bpl paint_cursor_move_done

    ; left/right arrow
    lda joypad_status
    and #(button_left | button_right)
    tax
    lda cursor_x
    cpx #button_left
    beq paint_cursor_left
    cpx #button_right
    beq paint_cursor_right
    jmp +
paint_cursor_left:
    clc
    sbc cursor_type
    jmp +
paint_cursor_right:
    sec
    adc cursor_type
+   and #%00111111  ; handle X pos over/underflow
    sta cursor_x

    ; up/down arrow
    lda joypad_status
    and #(button_up | button_down)
    tax
    lda cursor_y
    cpx #button_up
    beq paint_cursor_up
    cpx #button_down
    beq paint_cursor_down
    jmp vertical_arrow_read_done
paint_cursor_up:
    clc
    sbc cursor_type
    bpl vertical_arrow_read_done
    ; Y pos underflow
    lda #48
    clc
    sbc cursor_type
    jmp vertical_arrow_read_done
paint_cursor_down:
    sec
    adc cursor_type
    cmp #48
    bne vertical_arrow_read_done
    ; Y pos overflow
    lda #0
vertical_arrow_read_done:
    and #%00111111
    sta cursor_y

    ; reinitialize cursor movement delay
    lda #cursor_move_delay
    sta delay_left

paint_cursor_move_done:
    ; if no arrow pressed, clear cursor movement delay
    lda joypad_status
    and #(button_up | button_down | button_left | button_right)
    bne +
    sta delay_left

    ; if A pressed, paint a "pixel" (change one VRAM byte between $2080-$237f)
+   lda joypad_status
    and #button_a
    beq paint_done

    ; bits of cursor Y position (0-47): ABCDEF
    ; bits of cursor X position (0-63): abcdef
    ; name table address: $2080 + AB CDEabcde

    ; most significant byte of address
    lda cursor_y
    rept 3
        lsr
    endr
    tax  ; bits: 00000ABC (ABC = 0-5)
    lda paint_nt_addresses_h, x  ; hex 20 21 21 22 22 23
    sta vram_address + 1

    ; least significant byte of address
    lda cursor_y
    and #%00001110  ; bits: 0000CDE0
    lsr             ; bits: 00000CDE (CDE = 0-7)
    tax
    lda cursor_x
    lsr                          ; bits: 000abcde
    ora paint_nt_addresses_l, x  ; hex 80 a0 c0 e0 00 20 40 60
    sta vram_address + 0

    ; byte to write
    lda cursor_type
    beq +
    ; big (square) cursor
    ldx color
    lda solid_color_tiles, x
    jmp new_byte_created
+   ; small (arrow) cursor
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
    ; read old byte
    lda vram_address + 1
    sta ppu_addr
    lda vram_address + 0
    sta ppu_addr
    lda ppu_data
    lda ppu_data
    ; clear bits of this "pixel"
    and and_masks, x  ; %00111111, %11001111, %11110011, %11111100
    ; add new bits
    ora or_masks, y   ; %00/%01/%10/%11 in bits 7-6, then in bits 5-4, etc.

new_byte_created:
    ; write new byte
    ldx vram_address + 1
    stx ppu_addr
    ldx vram_address + 0
    stx ppu_addr
    sta ppu_data

paint_done:
    ; update current color to bottom bar
    load_ax $2000 + 28 * 32 + 8
    jsr set_vram_address
    ldx color
    lda solid_color_tiles, x
    sta ppu_data

    ; cursor sprite tile
    lda #2
    add cursor_type
    sta sprite_data + 1

    ; cursor sprite X position
    lda cursor_x
    asl
    asl
    ldx cursor_type
    bne +
    add #2               ; center small cursor on "pixel"
+   sta sprite_data + 3

    ; cursor sprite Y position
    lda cursor_y
    asl
    asl
    add #(4 * 8 - 1)
    ldx cursor_type
    bne +
    add #2               ; center small cursor on "pixel"
+   sta sprite_data + 0

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

; --------------------------------------------------------------------------------------------------

nmi_palette_edit_mode:
    ; get color at cursor
    ldx palette_cursor
    ldy user_palette, x

    ; react to buttons if nothing was pressed on the previous frame
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
    sub #$10
    jmp +
large_color_increment:
    tya
    add #$10
+   and #%00111111
    sta user_palette, x
    jmp palette_edit_button_read_done

exit_palette_edit_mode:
    ; hide palette editor
    lda #$ff
    ldx #(palette_editor_sprite_count * 4 - 1)
-   sta sprite_data + paint_mode_sprite_count * 4, x
    dex
    bpl -
    lsr mode  ; clear MSB
    rts

palette_edit_button_read_done:
    ; X is still the palette cursor position

    ; cursor sprite Y position
    txa
    asl
    asl
    asl
    add #(22 * 8 - 1)
    sta sprite_data + paint_mode_sprite_count * 4

    ; 16s of color number (sprite tile)
    lda user_palette, x
    lsr
    lsr
    lsr
    lsr
    add #10
    sta sprite_data + (paint_mode_sprite_count + 5) * 4 + 1

    ; ones of color number (sprite tile)
    lda user_palette, x
    and #$0f
    add #$0a
    sta sprite_data + (paint_mode_sprite_count + 6) * 4 + 1

    ; copy selected color to first background subpalette
    lda #$3f
    jsr set_vram_address  ; $3f00 + X
    ldy user_palette, x
    sty ppu_data

    ; copy selected color to sprite palette
    sta ppu_addr
    lda palette_editor_selected_color_offsets, x
    sta ppu_addr
    sty ppu_data

    rts

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
    add #$0a  ; tile number for "0"
    rts

to_decimal_ones_tile:
    ; In: A = unsigned integer
    ; Out: A = tile number for decimal ones

    sec
-   sbc #10
    bcs -
    add #10

    add #$0a  ; tile number for "0"
    rts

; --------------------------------------------------------------------------------------------------

and_masks:
    db %00111111, %11001111, %11110011, %11111100
or_masks:
    db %00000000, %01000000, %10000000, %11000000
    db %00000000, %00010000, %00100000, %00110000
    db %00000000, %00000100, %00001000, %00001100
    db %00000000, %00000001, %00000010, %00000011

solid_color_tiles:
    ; tiles of solid color 0/1/2/3
    db %00000000, %01010101, %10101010, %11111111

palette_editor_selected_color_offsets:
    ; VRAM offsets for selected colors in palette editor
    db 6 * 4 + 2
    db 6 * 4 + 3
    db 7 * 4 + 2
    db 7 * 4 + 3

palette_editor_sprites:
    db 22 * 8 - 1, $07, %00000001, 1 * 8   ; cursor
    db 22 * 8 - 1, $08, %00000010, 2 * 8   ; selected color 0
    db 23 * 8 - 1, $09, %00000010, 2 * 8   ; selected color 1
    db 24 * 8 - 1, $08, %00000011, 2 * 8   ; selected color 2
    db 25 * 8 - 1, $09, %00000011, 2 * 8   ; selected color 3
    db 26 * 8 - 1, $01, %00000001, 1 * 8   ; 16s  of color number
    db 26 * 8 - 1, $01, %00000001, 2 * 8   ; ones of color number
    db 21 * 8 - 1, $05, %00000001, 1 * 8   ; left half of "PAL"
    db 21 * 8 - 1, $06, %00000001, 2 * 8   ; right half of "PAL"
    db 22 * 8 - 1, $01, %00000001, 1 * 8   ; blank
    db 23 * 8 - 1, $01, %00000001, 1 * 8   ; blank
    db 24 * 8 - 1, $01, %00000001, 1 * 8   ; blank
    db 25 * 8 - 1, $01, %00000001, 1 * 8   ; blank
