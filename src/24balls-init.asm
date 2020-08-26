; 24 Balls - initialization

reset:
    initialize_nes

    lda #0
    sta timer
    sta nmi_done
    jsr sprite_palette_rom_to_ram

    ; fill sprite page with $ff
    ; (it will serve as invisible sprites' Y positions and as negative directions)
    lda #$ff
    ldx #0
-   sta sprite_page, x
    inx
    bne -

    ; sprite tile numbers: all $0a
    ;
    lda #$0a
    ldx #0
    ;
-   sta sprite_page + 1, x
    inx
    inx
    inx
    inx
    cpx #(ball_count * 2 * 4)
    bne -

    ; sprite Y positions: 18 + ball_index * 8
    ;
    ldx #0  ; ball offset on sprite page
    ;
-   txa
    clc
    adc #18
    sta sprite_page, x
    sta sprite_page + 4, x
    ;
    txa
    clc
    adc #8
    tax
    ;
    cpx #(ball_count * 8)
    bne -

    ; sprite X positions: left sides from table, add 8 for right sides
    ; regs: Y = ball index, X = ball offset on sprite page
    ;
    ldy #(ball_count - 1)
    ;
-   tya
    asl
    asl
    asl
    tax
    ;
    lda initial_x, y
    ;
    sta sprite_page + 3, x
    clc
    adc #8
    sta sprite_page + 4 + 3, x
    ;
    dey
    bpl -

    ; sprite attributes
    ;     horizontal flip:
    ;         0 for even-numbered sprites (left  half of ball)
    ;         1 for  odd-numbered sprites (right half of ball)
    ;     subpalette = ball_index modulo 4
    ;
    ldy #0
    ldx #0
    ;
-   lda initial_attributes, y
    sta sprite_page +  0 * 4 + 2, x
    sta sprite_page +  8 * 4 + 2, x
    sta sprite_page + 16 * 4 + 2, x
    sta sprite_page + 24 * 4 + 2, x
    sta sprite_page + 32 * 4 + 2, x
    sta sprite_page + 40 * 4 + 2, x
    ;
    inx
    inx
    inx
    inx
    ;
    iny
    cpy #8
    bne -

    ; clear some addresses of ball directions (to make them start in different directions)
    ;
    lda #$00
    ldy #(ball_count - 1)
    ;
-   ldx directions_to_clear, y
    sta sprite_page, x
    dey
    bpl -

    wait_vblank_start
    jsr sprite_palette_ram_to_vram

    ; do sprite DMA
    lda #>sprite_page
    sta oam_dma

    ; set background palette
    ;
    lda #$3f
    ldx #$00
    jsr set_ppu_address
    ;
    ldx #(4 - 1)
-   lda background_palette, x
    sta ppu_data
    dex
    bpl -

    ; write name table 0
    ;
    lda #$20
    ldx #$00
    jsr set_ppu_address
    ;
    ; 1 line (tile $01)
    lda #$01
    ldx #32
    jsr fill_vram
    ;
    ; 1 line (tiles $02, $03, $04)
    lda #$02
    sta ppu_data
    lda #$03
    ldx #30
    jsr fill_vram
    lda #$04
    sta ppu_data
    ;
    ; 26 lines (tiles $00, $08, $09)
    ldy #26
--  lda #$08
    sta ppu_data
    lda #$00
    ldx #30
-   sta ppu_data
    dex
    bne -
    lda #$09
    sta ppu_data
    dey
    bne --
    ;
    ; 1 line (tiles $05, $06, $07)
    lda #$05
    sta ppu_data
    lda #$06
    ldx #30
    jsr fill_vram
    lda #$07
    sta ppu_data
    ;
    ; 1 line (tile $01)
    lda #$01
    ldx #32
    jsr fill_vram

    ; clear attribute table 0
    lda #$00
    ldx #64
    jsr fill_vram

    jsr reset_ppu_address_and_scroll

    wait_vblank_start

    ; enable NMI, use 8*16-pixel sprites
    lda #%10100000
    sta ppu_ctrl

    ; show sprites and background
    lda #%00011110
    sta ppu_mask

    jmp main_loop

; -------------------------------------------------------------------------------------------------

fill_vram:
    ; Print A X times.

-   sta ppu_data
    dex
    bne -
    rts

; -------------------------------------------------------------------------------------------------

initial_x:
    ; initial X positions for balls
    ; minimum: 8 + 1 = 9
    ; maximum: 256 - 16 - 8 - 1 = 231
    ; Python 3: " ".join(format(n, "02x") for n in random.sample(range(9, 231 + 1), 24))
    hex 48 59 32 96 93 c6 26 70
    hex 31 d5 73 e6 3a 34 8c 52
    hex 1c 3d 61 c5 9e 88 b9 e7

initial_attributes:
    db %00000000, %01000000  ; subpalette 0, left/right half of ball
    db %00000001, %01000001  ; subpalette 1, left/right half of ball
    db %00000010, %01000010  ; subpalette 2, left/right half of ball
    db %00000011, %01000011  ; subpalette 3, left/right half of ball

directions_to_clear:
    hex c5 c9 cd d1 d7 db c1 c7 ce d5 d9 df
    hex e5 e9 ed f1 f7 fb e3 ea ef f3 f6 fd

background_palette:
    ; black, dark gray, gray, white (backwards!)
    hex 30 10 00 0f

