reset:
    initialize_nes

    ; disable all sound channels
    lda #$00
    sta snd_chn

    ; clear zero page and nt_buffer
    lda #$00
    tax
-   sta $00, x
    sta nt_buffer, x
    sta nt_buffer + $100, x
    sta nt_buffer + $200, x
    inx
    bne -

    ; init user palette
    ldx #3
-   lda initial_palette, x
    sta user_palette, x
    dex
    bpl -

    jsr set_sprite_data

    inc paint_color  ; default color: 1

    wait_for_vblank

    ; reset ppu_addr/ppu_scroll latch
    bit ppu_status

    jsr set_palette
    jsr set_pattern_tables
    jsr set_name_table

    ; clear VRAM address & scroll
    lda #$00
    tax
    jsr set_vram_address
    sta ppu_scroll
    sta ppu_scroll

    wait_vblank_start

    ; show background & sprites
    lda #%00011110
    sta ppu_mask

    ; enable NMI, use pattern table 1 for sprites
    lda #%10001000
    sta ppu_ctrl

    jmp main_loop

; --------------------------------------------------------------------------------------------------

set_sprite_data:
    ; copy initial sprite data (paint mode, palette edit mode)
    ldx #((9 + 13) * 4 - 1)
-   lda initial_sprite_data, x
    sta sprite_data, x
    dex
    bpl -

    ; hide palette editor sprites and unused sprites
    lda #$ff
    ldx #(9 * 4)
-   sta sprite_data, x
    inx
    inx
    inx
    inx
    bne -

    rts

initial_sprite_data:
    ; paint mode (9 sprites)
    db  0 * 8 - 1, $02, %00000000, 0 * 8   ; cursor
    db 28 * 8 - 1, $00, %00000000, 1 * 8   ; tens of X position
    db 28 * 8 - 1, $00, %00000000, 2 * 8   ; ones of X position
    db 28 * 8 - 1, $00, %00000000, 5 * 8   ; tens of Y position
    db 28 * 8 - 1, $00, %00000000, 6 * 8   ; ones of Y position
    db 28 * 8 - 1, $04, %00000000, 3 * 8   ; comma
    db 28 * 8 - 1, $01, %00000000, 9 * 8   ; cover 1
    db 29 * 8 - 1, $01, %00000000, 8 * 8   ; cover 2
    db 29 * 8 - 1, $01, %00000000, 9 * 8   ; cover 3

    ; palette editor mode (13 sprites)
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

set_palette:
    ; set palette
    lda #$3f
    ldx #$00
    jsr set_vram_address
-   lda initial_palette, x
    sta ppu_data
    inx
    cpx #32
    bne -
    rts

initial_palette:
    ; background
    db white, red,    green, blue    ; paint area; same as two last sprite subpalettes
    db white, yellow, blue,  white   ; top and bottom bar
    db white, white,  white, white   ; unused
    db white, white,  white, white   ; unused
    ; sprites
    db white, yellow, black, gray    ; status bar cover sprite, status bar text, paint cursor
    db white, black,  white, yellow  ; palette editor - text and cursor
    db white, black,  white, red     ; palette editor - selected colors 0&1
    db white, black,  green, blue    ; palette editor - selected colors 2&3

; --------------------------------------------------------------------------------------------------

set_pattern_tables:
    ; first half of CHR RAM (background)

    ; all combinations of 2*2 subpixels * 4 colors
    ; bits of tile index: AaBbCcDd
    ; corresponding subpixel colors (capital letter = MSB, small letter = LSB):
    ; Aa Bb
    ; Cc Dd

    lda #$00
    tax
    jsr set_vram_address
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

    ; second half of CHR RAM (sprites; 32 tiles, 512 bytes)
    ldx #0
-   lda sprite_chr_data, x
    sta ppu_data
    inx
    bne -
-   lda sprite_chr_data + 256, x
    sta ppu_data
    inx
    bne -

    rts

background_chr_data1:
    ; read backwards
    hex ff f0 ff f0  0f 00 0f 00  ff f0 ff f0  0f 00 0f 00

background_chr_data2:
    ; read backwards
    hex ff ff f0 f0  ff ff f0 f0  0f 0f 00 00  0f 0f 00 00

sprite_chr_data:
    ; 32 tiles (512 bytes)
    incbin "paint-sprites.chr"

; --------------------------------------------------------------------------------------------------

set_name_table:
    ; Set name table 0 and attribute table 0.

    lda #$20
    ldx #$00
    jsr set_vram_address

    ; name table

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

    rts

print_repeatedly:
    ; print A X times
-   sta ppu_data
    dex
    bne -
    rts

logo:
    ; colors: 1 = background, 2 = foreground; 1 byte = 2*2 subpixels
    ; bits of tile index: AaBbCcDd
    ; corresponding subpixel colors (capital letter = MSB, small letter = LSB):
    ; Aa Bb
    ; Cc Dd

    hex 66 55 69 55 a5 96 55 a6 55 55 a6 55 56 a5 96  55 55  a9 a5 59 65 a5 59 55 95 55 a9 a5 59 5a 9a 59
    hex 66 a5 59 56 a5 a6 55 66 55 55 66 55 66 a5 a5  55 55  a9 a5 55 69 a5 99 65 99 55 99 55 99 55 99 55
    hex 65 55 65 65 a5 a5 65 a5 a5 65 a5 a5 55 a5 95  55 55  95 55 55 a5 a5 95 a5 a5 95 95 55 95 55 65 95

; --------------------------------------------------------------------------------------------------

set_vram_address:
    ; A = high byte, X = low byte
    sta ppu_addr
    stx ppu_addr
    rts

print_four_times:
    sta ppu_data
    sta ppu_data
    sta ppu_data
    sta ppu_data
    rts

