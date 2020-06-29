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

; --- Paint mode -----------------------------------------------------------------------------------

main_loop_paint_mode:
    ; only react to select, start and B (bits 6-4) if none of them was pressed on previous frame
    lda prev_joypad_status
    and #$70
    bne paint_button_read_done
    lda joypad_status
    and #$70
    cmp #button_select
    beq enter_palette_editor
    cmp #button_start
    beq change_cursor_type
    cmp #button_b
    beq change_color
    jmp paint_button_read_done

enter_palette_editor:
    sec
    ror in_palette_editor  ; set flag

    ldx #0
    stx palette_cursor  ; init cursor position
    dex
    stx sprite_data + 0 + 0  ; hide paint cursor

    ; show palette editor sprites
    ldx #((13 - 1) * 4)
-   lda initial_sprite_data + 9 * 4, x
    sta sprite_data + 9 * 4, x
    dex
    dex
    dex
    dex
    bpl -

    rts

change_cursor_type:
    lda cursor_type
    eor #%00000001
    sta cursor_type
    ; if switched to big (square) cursor, make cursor X and Y position even
    beq +
    lda cursor_x
    and #$3e
    sta cursor_x
    lda cursor_y
    and #$3e
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

    ; if A pressed, tell NMI routine to paint
+   lda joypad_status
    and #button_a
    beq +
    jsr get_vram_address  ; cursor_x, cursor_y -> vram_address (for NMI routine)
    sec
    ror do_paint  ; set flag
+

    ; update sprite_data in RAM

    ; cursor sprite tile
    lda #2
    clc
    adc cursor_type
    sta sprite_data + 0 + 1

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

; --- Paint mode - subs/data -----------------------------------------------------------------------

get_vram_address:
    ; Compute vram_address from cursor_x and cursor_y.
    ; Bits of cursor_y (0-47 or %000000-%101111): ABCDEF
    ; Bits of cursor_x (0-63 or %000000-%111111): abcdef
    ; Bits of vram_address ($2080-$237f):         $2080 + 000000AB CDEabcde

    ; high byte
    lda cursor_y             ; 00ABCDEF
    lsr
    lsr
    lsr
    tax                      ; 00000ABC (0-5)
    lda vram_addresses_h, x
    sta vram_address + 0

    ; low byte
    lda cursor_y             ; 00ABCDEF
    and #%00001110           ; 0000CDE0
    lsr                      ; 00000CDE (0-7)
    tax
    lda cursor_x             ; 00abcdef
    lsr                      ; 000abcde
    ora vram_addresses_l, x
    sta vram_address + 1

    rts

vram_addresses_h:
    hex 20 21 21 22 22 23

vram_addresses_l:
    hex 80 a0 c0 e0 00 20 40 60

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

