    ; byte to fill unused areas with
    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory space

mode               equ $00  ; 0 = paint mode, 1 = palette edit mode
joypad_status      equ $01
prev_joypad_status equ $02  ; previous joypad status
delay_left         equ $03  ; cursor move delay left
cursor_type        equ $04  ; 0 = small (arrow), 1 = big (square)
cursor_x           equ $05  ; cursor X position (in paint mode; 0-63)
cursor_y           equ $06  ; cursor Y position (in paint mode; 0-47)
color              equ $07  ; selected color (0-3)
user_palette       equ $08  ; 4 bytes, each $00-$3f
palette_cursor     equ $0c  ; cursor position in palette edit mode (0-3)
vram_address       equ $0d  ; 2 bytes
pointer            equ $0f  ; 2 bytes

sprite_data equ $0200  ; 256 bytes

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_addr   equ $2006
ppu_data   equ $2007
oam_dma    equ $4014
joypad1    equ $4016

; PPU memory space

vram_name_table0 equ $2000
vram_palette     equ $3f00

; non-address constants

button_a      = 1 << 7
button_b      = 1 << 6
button_select = 1 << 5
button_start  = 1 << 4
button_up     = 1 << 3
button_down   = 1 << 2
button_left   = 1 << 1
button_right  = 1 << 0

black  equ $0f
white  equ $30
red    equ $16
yellow equ $28
olive  equ $18
green  equ $1a
blue   equ $02
purple equ $04

cursor_move_delay           equ 10
paint_mode_sprite_count     equ 9
palette_editor_sprite_count equ 13

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------
; Main program

    org $c000
reset:
    ; note: I could do the initialization better nowadays (see "init code" in NESDev Wiki), but
    ; I want to keep this binary identical to the old one

    ; disable NMI, hide background&sprites
    lda #$00
    sta ppu_ctrl
    sta ppu_mask

    ; clear zero page
    tax
-   sta $00, x
    inx
    bne -

    ; wait for start of VBlank, then wait for another VBlank
    bit ppu_status
-   bit ppu_status
    bpl -
-   bit ppu_status
    bpl -

    ; palette
    lda #>vram_palette
    ldx #<vram_palette
    jsr set_vram_address
-   lda initial_palette, x
    sta ppu_data
    inx
    cpx #32
    bne -

    ; First half of CHR RAM (background).
    ; Contains all combinations of 2*2 subpixels * 4 colors.
    ; Bits of tile index: AaBbCcDd
    ; Corresponding subpixel colors (capital letter = MSB, small letter = LSB):
    ; Aa Bb
    ; Cc Dd
    jsr reset_vram_address
    ldy #15
--  ldx #15
-   lda background_chr_data1, y
    jsr print_four_times
    lda background_chr_data1, x
    jsr print_four_times
    lda background_chr_data2, y
    jsr print_four_times
    lda background_chr_data2, x
    jsr print_four_times
    dex
    bpl -
    dey
    bpl --

    ; second half of CHR RAM (sprites)
    lda #>sprite_chr_data
    sta pointer + 1
    ldy #$00
    sty pointer + 0
-   lda (pointer), y
    sta ppu_data
    iny
    bne -
    ; change most significant byte of address
    inc pointer + 1
    lda pointer + 1
    cmp #((>sprite_chr_data) + 16)
    bne -

    ; name table
    lda #>vram_name_table0
    ldx #<vram_name_table0
    jsr set_vram_address
    ; top bar (4 rows)
    lda #%01010101  ; block of color 1
    ldx #32
    jsr print_repeatedly
    ldx #0
-   lda logo, x
    sta ppu_data
    inx
    cpx #(3 * 32)
    bne -
    ; paint area (24 rows)
    lda #$00
    ldx #(6 * 32)
-   jsr print_four_times
    dex
    bne -
    ; bottom bar (2 rows)
    lda #%01010101  ; block of color 1
    ldx #64
    jsr print_repeatedly

    ; attribute table
    ; top bar
    lda #%01010101
    ldx #8
    jsr print_repeatedly
    ; paint area
    lda #%00000000
    ldx #(6 * 8)
    jsr print_repeatedly
    ; bottom bar
    lda #%00000101
    sta ppu_data
    sta ppu_data
    ldx #%00000100
    stx ppu_data
    ldx #5
    jsr print_repeatedly

    ; user palette
    ldx #3
-   lda initial_palette, x
    sta user_palette, x
    dex
    bpl -

    ; default color: 1
    inc color

    ; paint mode sprites
    ldx #(paint_mode_sprite_count * 4 - 1)
-   lda paint_mode_sprites, x
    sta sprite_data, x
    dex
    bpl -
    ; hide other sprites
    lda #$ff
    ldx #(paint_mode_sprite_count * 4)
-   sta sprite_data, x
    inx
    bne -

    lda #button_select
    sta prev_joypad_status

    jsr reset_vram_address

    ; wait for start of VBlank
    bit ppu_status
-   bit ppu_status
    bpl -

    ; enable NMI, use pattern table 1 for sprites
    lda #%10001000
    sta ppu_ctrl

    ; show background&sprites
    lda #%00011110
    sta ppu_mask

-   jmp -

; --------------------------------------------------------------------------------------------------

nmi:
    jsr read_joypad
    sta joypad_status

    lda mode
    bne nmi_palette_edit_mode
    jmp nmi_paint_mode

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
    and #%00111111
    sta user_palette, x
    jmp palette_edit_button_read_done
large_color_decrement:
    tya
    sbc #$10
    jmp +
large_color_increment:
    tya
    adc #$0F
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
    inx
    stx mode
    jmp nmi_exit

palette_edit_button_read_done:
    ; X is still the palette cursor position

    ; cursor sprite Y position
    txa
    rept 3
        asl
    endr
    adc #(22 * 8 - 1)
    sta sprite_data + paint_mode_sprite_count * 4

    ; 16s of color number (sprite tile)
    lda user_palette, x
    rept 4
        lsr
    endr
    clc
    adc #$10  ; digits start at tile $10
    sta sprite_data + (paint_mode_sprite_count + 5) * 4 + 1

    ; ones of color number (sprite tile)
    lda user_palette, x
    and #%00001111
    clc
    adc #$10  ; digits start at tile $10
    sta sprite_data + (paint_mode_sprite_count + 6) * 4 + 1

    ; copy selected color to first background subpalette
    lda #>vram_palette
    jsr set_vram_address
    ldy user_palette, x
    sty ppu_data

    ; copy selected color to sprite palette
    sta ppu_addr
    lda palette_editor_selected_color_offsets, x
    sta ppu_addr
    sty ppu_data

    jsr reset_vram_address
    jmp nmi_exit

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
    ; switch mode
    lda #1
    sta mode
    ; initialize palette cursor position
    lda #0
    sta palette_cursor
    jmp nmi_exit
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
    adc cursor_type
+   and #%00111111
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
    bpl +            ; could've just branched to vertical_arrow_read_done
    lda #48
    sbc cursor_type
+   jmp vertical_arrow_read_done
paint_cursor_down:
    adc cursor_type
    cmp #48
    bne vertical_arrow_read_done
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
+

    ; if A pressed, paint a "pixel" (change one VRAM byte between $2080-$237f)
    lda joypad_status
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
    lda #>(vram_name_table0 + 28 * 32 + 8)
    ldx #<(vram_name_table0 + 28 * 32 + 8)
    jsr set_vram_address
    ldx color
    lda solid_color_tiles, x
    sta ppu_data

    jsr reset_vram_address

    ; cursor sprite tile
    lda #2
    clc
    adc cursor_type
    sta sprite_data + 1

    ; cursor sprite X position
    lda cursor_x
    asl
    asl
    ldx cursor_type
    bne +
    adc #2               ; center small cursor on "pixel"
+   sta sprite_data + 3

    ; cursor sprite Y position
    lda cursor_y
    asl
    asl
    adc #(4 * 8 - 1)  ; carry is clear
    ldx cursor_type
    bne +
    adc #2               ; center small cursor on "pixel"
+   sta sprite_data + 0

    ; tiles of X position sprites
    lda cursor_x
    lsr
    tax
    lda tiles_decimal_ones, x    ; "0"/"2"/"4"/"6"/"8"
    adc #0                       ; add carry
    sta sprite_data + 2 * 4 + 1
    lda tiles_decimal_tens, x    ; "0"-"6"
    sta sprite_data + 4 + 1

    ; tiles of Y position sprites
    lda cursor_y
    lsr
    tax
    lda tiles_decimal_ones, x    ; "0"/"2"/"4"/"6"/"8"
    adc #0                       ; add carry
    sta sprite_data + 4 * 4 + 1
    lda tiles_decimal_tens, x    ; "0"-"6"
    sta sprite_data + 3 * 4 + 1

nmi_exit:
    ; update sprite data
    lda #>sprite_data
    sta oam_dma
    ; save current joypad status
    lda joypad_status
    sta prev_joypad_status
    rti

; --------------------------------------------------------------------------------------------------

read_joypad:
    ; return joypad 1 status in A and X (bits: A, B, select, start, up, down, left, right)
    ldx #1
    stx joypad1
    dex
    stx joypad1
    ldy #8
-   lda joypad1
    ror
    txa
    rol
    tax
    dey
    bne -
    rts

reset_vram_address:
    lda #$00
    sta ppu_addr
    sta ppu_addr
    rts

set_vram_address:
    sta ppu_addr
    stx ppu_addr
    rts

print_four_times:
    rept 4
        sta ppu_data
    endr
    rts

print_repeatedly:
    ; print A X times
-   sta ppu_data
    dex
    bne -
    rts

; --------------------------------------------------------------------------------------------------
; Tables

    ; for generating background CHR data (read backwards)
background_chr_data1:
    hex ff f0 ff f0  0f 00 0f 00  ff f0 ff f0  0f 00 0f 00
background_chr_data2:
    hex ff ff f0 f0  ff ff f0 f0  0f 0f 00 00  0f 0f 00 00

paint_nt_addresses_h:
    hex 20 21 21 22 22 23
paint_nt_addresses_l:
    hex 80 a0 c0 e0 00 20 40 60

tiles_decimal_tens:
    ; a right-shifted number -> tile of tens ("0"-"6")
    hex 10 10 10 10 10
    hex 11 11 11 11 11
    hex 12 12 12 12 12
    hex 13 13 13 13 13
    hex 14 14 14 14 14
    hex 15 15 15 15 15
    hex 16 16
tiles_decimal_ones:
    ; a right-shifted number -> tile of ones ("0"/"2"/"4"/"6"/"8")
    hex 10 12 14 16 18
    hex 10 12 14 16 18
    hex 10 12 14 16 18
    hex 10 12 14 16 18
    hex 10 12 14 16 18
    hex 10 12 14 16 18
    hex 10 12

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

    ; name table data for the logo in the top bar (colors 2&3 on color 1; 1 byte = 2*2 subpixels)
    ; bits of tile index: AaBbCcDd
    ; subpixel colors:
    ; Aa Bb
    ; Cc Dd
logo:
    hex 555555 66 66 66 66 66 a5 55 55 66 a6 66 a5 66 a5 55 55 66 a6 66 a6 66 66 a6 65 a9 55555555
    hex 555555 66 96 66 a6 65 a6 75 f5 66 66 66 a5 65 a6 75 f5 66 a5 66 a6 66 66 66 55 99 55555555
    hex 555555 65 65 65 65 65 a5 55 55 65 65 65 a5 65 a5 55 55 65 55 65 65 65 65 65 55 95 55555555

initial_palette:
    ; background
    db white, red,    green, blue    ; paint area; same as two last sprite subpalettes
    db white, yellow, green, purple  ; top and bottom bar
    db white, white,  white, white   ; unused
    db white, white,  white, white   ; unused
    ; sprites
    db white, yellow, black, olive   ; status bar cover sprite, status bar text, paint cursor
    db white, black,  white, yellow  ; palette editor - text and cursor
    db white, black,  white, red     ; palette editor - selected colors 0&1
    db white, black,  green, blue    ; palette editor - selected colors 2&3

paint_mode_sprites:
    db $00       , $02, %00000000, 0 * 8   ; cursor
    db 28 * 8 - 1, $00, %00000000, 1 * 8   ; tens of X position
    db 28 * 8 - 1, $00, %00000000, 2 * 8   ; ones of X position
    db 28 * 8 - 1, $00, %00000000, 5 * 8   ; tens of Y position
    db 28 * 8 - 1, $00, %00000000, 6 * 8   ; ones of Y position
    db 28 * 8 - 1, $04, %00000000, 3 * 8   ; comma
    db 28 * 8 - 1, $01, %00000000, 9 * 8   ; cover 1
    db 29 * 8 - 1, $01, %00000000, 8 * 8   ; cover 2
    db 29 * 8 - 1, $01, %00000000, 9 * 8   ; cover 3

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

; --------------------------------------------------------------------------------------------------
; CHR data (second half, sprites, 256 tiles)

    pad $d000
sprite_chr_data:
    hex 00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  ; $00: block of color 0
    hex ff ff ff ff ff ff ff ff  00 00 00 00 00 00 00 00  ; $01: block of color 1
    hex f0 c0 a0 90 08 04 02 01  f0 c0 a0 90 08 04 02 01  ; $02: arrow cursor (color 3)
    hex ff 81 81 81 81 81 81 ff  ff 81 81 81 81 81 81 ff  ; $03: square cursor (color 3)
    hex ff ff ff ff ff e7 e7 cf  00 00 00 00 00 18 18 30  ; $04: comma (color 2 on 1)
    hex ff 8e b5 b5 8c bd bd ff  00 71 4a 4a 73 42 42 00  ; $05: left half of "PAL" (color 2 on 1)
    hex ff 6f af af 2f af a1 ff  00 90 50 50 d0 50 5e 00  ; $06: right half of "PAL" (color 2 on 1)
    hex 00 0c 06 7f 06 0c 00 00  00 0c 06 7f 06 0c 00 00  ; $07: right arrow (color 3)
    hex 81 81 81 81 81 81 81 ff  7e 7e 7e 7e 7e 7e 7e 00  ; $08: block of color 2, border color 1
    hex ff ff ff ff ff ff ff ff  7e 7e 7e 7e 7e 7e 7e 00  ; $09: block of color 3, border color 1

    ; tiles $10-$1f: hexadecimal digits "0"-"F" (color 2 on 1)
    pad $d000 + $10 * 16, $00
    hex 83 39 39 39 39 39 83 ff  7c c6 c6 c6 c6 c6 7c 00
    hex e7 c7 e7 e7 e7 e7 c3 ff  18 38 18 18 18 18 3c 00
    hex 83 39 f9 e3 8f 3f 01 ff  7c c6 06 1c 70 c0 fe 00
    hex 83 39 f9 c3 f9 39 83 ff  7c c6 06 3c 06 c6 7c 00
    hex f3 e3 c3 93 01 f3 f3 ff  0c 1c 3c 6c fe 0c 0c 00
    hex 01 3f 3f 03 f9 f9 03 ff  fe c0 c0 fc 06 06 fc 00
    hex 81 3f 3f 03 39 39 83 ff  7e c0 c0 fc c6 c6 7c 00
    hex 01 f9 f3 e7 cf 9f 3f ff  fe 06 0c 18 30 60 c0 00
    hex 83 39 39 83 39 39 83 ff  7c c6 c6 7c c6 c6 7c 00
    hex 83 39 39 81 f9 f9 03 ff  7c c6 c6 7e 06 06 fc 00
    hex 83 39 39 01 39 39 39 ff  7c c6 c6 fe c6 c6 c6 00
    hex 03 99 99 83 99 99 03 ff  fc 66 66 7c 66 66 fc 00
    hex 83 39 3f 3f 3f 39 83 ff  7c c6 c0 c0 c0 c6 7c 00
    hex 03 99 99 99 99 99 03 ff  fc 66 66 66 66 66 fc 00
    hex 01 3f 3f 01 3f 3f 01 ff  fe c0 c0 fe c0 c0 fe 00
    hex 01 3f 3f 01 3f 3f 3f ff  fe c0 c0 fe c0 c0 c0 00

    ; the rest of the tiles are blank
    pad $e000, $00

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    dw nmi, reset, 0
