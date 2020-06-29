reset:
    initialize_nes

    lda #$00
    sta snd_chn  ; disable all sound channels

    ; clear zero page
    lda #$00
    tax
-   sta $00, x
    inx
    bne -

    ; init user palette
    ldx #3
-   lda initial_palette, x
    sta user_palette, x
    dex
    bpl -

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

    inc color  ; default color: 1

    sec
    ror nmi_done  ; set flag

    wait_for_vblank

    ; set palette
    lda #$3f
    ldx #$00
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

    ; second half of CHR RAM (sprites, 2 * 256 = 512 bytes)
    ldx #0
-   lda sprite_chr_data, x
    sta ppu_data
    inx
    bne -
-   lda sprite_chr_data + 256, x
    sta ppu_data
    inx
    bne -

    ; name table
    lda #$20
    ldx #$00
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

    ; clear VRAM address & scroll
    lda #$00
    tax
    jsr set_vram_address
    sta ppu_scroll
    sta ppu_scroll

    wait_vblank_start

    ; enable NMI, use pattern table 1 for sprites
    lda #%10001000
    sta ppu_ctrl

    ; show background&sprites
    lda #%00011110
    sta ppu_mask

    jmp main_loop

; --------------------------------------------------------------------------------------------------

print_four_times:
    sta ppu_data
    sta ppu_data
    sta ppu_data
    sta ppu_data
    rts

print_repeatedly:
    ; print A X times
-   sta ppu_data
    dex
    bne -
    rts

; --------------------------------------------------------------------------------------------------

    ; for generating background CHR data (read backwards)
background_chr_data1:
    hex ff f0 ff f0  0f 00 0f 00  ff f0 ff f0  0f 00 0f 00
background_chr_data2:
    hex ff ff f0 f0  ff ff f0 f0  0f 0f 00 00  0f 0f 00 00

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

    ; CHR data (second half, sprites)
sprite_chr_data:
    incbin "paint-sprites.chr"  ; 32 tiles (512 bytes)

