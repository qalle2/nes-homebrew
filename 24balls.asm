; 24 Balls for the NES by Kalle
; Assembles with ASM6F.
; (History: I wrote this program in early 2010s in NESASM but lost the source, so I disassembled the
; binary in 2019 with DISASM6.)
;
; Zero page layout:
;   $00-$bf: visible sprites:
;       192 bytes = 24 balls * 2 sprites/ball * 4 bytes/sprite
;   $c0-$ff: hidden sprites:
;       Y positions ($c0, $c4, $c8, $cc, ...) are always $ff
;       other bytes are used for directions of balls:
;           horizontal: $c1, $c2, $c3; $c5, $c6, $c7; ...; $dd, $de, $df
;           vertical:   $e1, $e2, $e3; $e5, $e6, $e7; ...; $fd, $fe, $ff

    fillvalue $ff

; --------------------------------------------------------------------------------------------------
; Constants

; CPU memory space

sprite_page equ $0000
timer       equ $0200

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_addr   equ $2006
ppu_data   equ $2007
oam_dma    equ $4014

; PPU memory space

vram_name_table0 equ $2000
vram_palette     equ $3f00

; non-address constants

ball_count equ 24

; --------------------------------------------------------------------------------------------------
; Macros

macro move_ball_x ball
    ; move ball (0-23) horizontally

    ; $c1, $c2, $c3; $c5, $c6, $c7; ...; $dd, $de, $df
    direction_addr = $c1 + ball + ball / 3

    bit direction_addr
    bpl +
    ; left
    dec sprite_page + ball * 2 * 4     + 3
    dec sprite_page + ball * 2 * 4 + 4 + 3
    lda sprite_page + ball * 2 * 4     + 3
    cmp #8
    bne ++
    inc direction_addr
    jmp ++
+   ; right
    inc sprite_page + ball * 2 * 4     + 3
    inc sprite_page + ball * 2 * 4 + 4 + 3
    lda sprite_page + ball * 2 * 4     + 3
    cmp #(240 - 8)
    bne ++
    dec direction_addr
++
endm

macro move_ball_y ball
    ; move ball (0-23) vertically

    ; $e1, $e2, $e3; $e5, $e6, $e7; ...; $fd, $fe, $ff
    direction_addr = $e1 + ball + ball / 3

    bit direction_addr
    bpl +
    ; up
    ldx sprite_page + ball * 2 * 4
    dex
    stx sprite_page + ball * 2 * 4
    stx sprite_page + ball * 2 * 4 + 4
    cpx #(16 - 1)
    bne ++
    inc direction_addr
    jmp ++
+   ; down
    ldx sprite_page + ball * 2 * 4
    inx
    stx sprite_page + ball * 2 * 4
    stx sprite_page + ball * 2 * 4 + 4
    cpx #(240 - 16 - 16 - 1)
    bne ++
    dec direction_addr
++
endm

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1
    ineschr 0
    inesmir 0
    inesmap 0

; --------------------------------------------------------------------------------------------------
; Main program

    org $c000

reset:
    ; disable rendering
    lda #$00
    sta ppu_ctrl
    sta ppu_mask

    ; wait for start of VBlank, then for another VBlank
    bit ppu_status
-   bit ppu_status
    bpl -
-   bit ppu_status
    bpl -

    ; set palette
    lda #>vram_palette
    sta ppu_addr
    ldx #<vram_palette
    stx ppu_addr
-   lda palette_background, x
    sta ppu_data
    inx
    cpx #32
    bne -

    ; copy CHR data to CHR RAM (16 tiles)
    jsr reset_vram_address
    ldx #0
-   lda chr_data, x
    sta ppu_data
    inx
    bne -

    ; prepare to write name table 0
    lda #>vram_name_table0
    sta ppu_addr
    lda #<vram_name_table0
    sta ppu_addr

    ; line: (32 * tile $01)
    lda #$01
    ldx #32
    jsr fill_vram
    ; line: (tile $02, 30 * tile $03, tile $04)
    lda #$02
    sta ppu_data
    lda #$03
    ldx #30
    jsr fill_vram
    lda #$04
    sta ppu_data
    ; 26 lines: (tile $08, 30 * tile $00, tile $09)
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
    ; line: (tile $05, 30 * tile $06, tile $07)
    lda #$05
    sta ppu_data
    lda #$06
    ldx #30
    jsr fill_vram
    lda #$07
    sta ppu_data
    ; line: (32 * tile $01)
    lda #$01
    ldx #32
    jsr fill_vram

    ; clear attribute table 0
    lda #$00
    ldx #64
    jsr fill_vram

    ; fill sprite page with $ff
    ; (it will serve as invisible sprites' Y positions and as negative directions)
    lda #$ff
    ldx #0
-   sta sprite_page, x
    inx
    bne -

    ; tile numbers: $0a for all sprites
    ldy #$0a
    lda #(ball_count * 2 * 4)
    sec
-   tax
    sty 256 - 3, x
    sbc #4
    bne -

    ; initial Y positions: 18 + ball_index * 8
    lda #18
    clc
-   tax
    sta 256 - 18, x
    sta 256 - 14, x
    adc #8
    cmp #(18 + ball_count * 2 * 4)
    bne -

    ; initialize sprite X positions
    ldy #(ball_count - 1)
    ldx #(ball_count * 2 * 4)
    clc
-   ; subtract 8 from X
    txa
    sbc #7
    tax
    lda initial_x, y
    sta sprite_page + 3, x
    adc #7                      ; add 8 to A for right half of ball
    sta sprite_page + 4 + 3, x
    dey
    bpl -

    ; initialize sprite attributes
    ;     horizontal flip:
    ;         0 for even-numbered sprites (left  half of ball)
    ;         1 for  odd-numbered sprites (right half of ball)
    ;     subpalette = ball_index modulo 4
    ldy #0
    ldx #2
    clc
-   lda initial_attributes, y
    sta sprite_page +  0 * 4, x
    sta sprite_page +  8 * 4, x
    sta sprite_page + 16 * 4, x
    sta sprite_page + 24 * 4, x
    sta sprite_page + 32 * 4, x
    sta sprite_page + 40 * 4, x
    ; add 4 to X
    txa
    adc #4
    tax
    iny
    cpy #8
    bne -

    ; clear some addresses of ball directions (to make them start in different directions)
    lda #$00
    ldy #(24 - 1)
-   ldx directions_to_clear, y
    sta sprite_page, x
    dey
    bpl -

    ; do sprite DMA
    lda #>sprite_page
    sta oam_dma

    jsr reset_vram_address

    ; wait for start of VBlank
    bit ppu_status
-   bit ppu_status
    bpl -

    ; enable NMI, use 8*16-px sprites
    lda #%10100000
    sta ppu_ctrl

    ; show sprites and background
    lda #%00011110
    sta ppu_mask

-   jmp -

; --------------------------------------------------------------------------------------------------
; NMI

nmi:
    inc timer

    ; horizontal movement
    ; speed:
    ;     1 px every 2nd frame for balls 1, 4, 7, 10, 14, 17, 20, 23
    ;     1 px every     frame for other balls
    lda timer
    and #%00000001
    beq +
    ; odd frame
    move_ball_x  1
    move_ball_x  4
    move_ball_x  7
    move_ball_x 10
    jmp ++
+   ; even frame
    move_ball_x 14
    move_ball_x 17
    move_ball_x 20
    move_ball_x 23
++  move_ball_x  0
    move_ball_x  2
    move_ball_x  3
    move_ball_x  5
    move_ball_x  6
    move_ball_x  8
    move_ball_x  9
    move_ball_x 11
    move_ball_x 12
    move_ball_x 13
    move_ball_x 15
    move_ball_x 16
    move_ball_x 18
    move_ball_x 19
    move_ball_x 21
    move_ball_x 22

    ; vertical movement
    ; speed: 1 px/frame for all balls
    move_ball_y  0
    move_ball_y  1
    move_ball_y  2
    move_ball_y  3
    move_ball_y  4
    move_ball_y  5
    move_ball_y  6
    move_ball_y  7
    move_ball_y  8
    move_ball_y  9
    move_ball_y 10
    move_ball_y 11
    move_ball_y 12
    move_ball_y 13
    move_ball_y 14
    move_ball_y 15
    move_ball_y 16
    move_ball_y 17
    move_ball_y 18
    move_ball_y 19
    move_ball_y 20
    move_ball_y 21
    move_ball_y 22
    move_ball_y 23

    ; do sprite DMA
    lda #>sprite_page
    sta oam_dma

    ; set up sprite palette update
    lda #>(vram_palette + 4 * 4)
    sta ppu_addr
    lda #<(vram_palette + 4 * 4)
    sta ppu_addr

    ; copy one of two palettes depending on timer
    lda timer
    and #%00001000
    asl
    tax
    ldy #16
-   lda palette_sprites, x
    sta ppu_data
    inx
    dey
    bne -

    jsr reset_vram_address
    rti

; --------------------------------------------------------------------------------------------------
; Subroutines

reset_vram_address:
    lda #$00
    sta ppu_addr
    sta ppu_addr
    rts

fill_vram:
    sta ppu_data
    dex
    bne fill_vram
    rts

; --------------------------------------------------------------------------------------------------
; Tables

palette_background:
    hex 0f 00 10 30  ; black, dark gray, gray, light gray
    hex 0f 0f 0f 0f  ; unused (all black)
    hex 0f 0f 0f 0f  ; unused (all black)
    hex 0f 0f 0f 0f  ; unused (all black)

palette_sprites:
    ; shades of blue, red, yellow and green
    hex 0f 11 21 31
    hex 0f 14 24 34
    hex 0f 17 27 37
    hex 0f 1a 2a 3a
    ; slightly different shades of blue, red, yellow and green
    hex 0f 12 22 32
    hex 0f 15 25 35
    hex 0f 18 28 38
    hex 0f 1b 2b 3b

initial_x:
    ; is there a pattern in this?
    hex 9d 77 4f 1e
    hex e4 4a a1 e5
    hex 30 66 e3 3b
    hex a2 c5 4f 83
    hex dd 59 a1 1a
    hex 62 e4 2d 9f

initial_attributes:
    db %00000000, %01000000  ; subpalette 0, left/right half of ball
    db %00000001, %01000001  ; subpalette 1, left/right half of ball
    db %00000010, %01000010  ; subpalette 2, left/right half of ball
    db %00000011, %01000011  ; subpalette 3, left/right half of ball

directions_to_clear:
    hex c5 c9 cd d1 d7 db c1 c7 ce d5 d9 df
    hex e5 e9 ed f1 f7 fb e3 ea ef f3 f6 fd

; --------------------------------------------------------------------------------------------------
; CHR data (will be copied to CHR RAM)

chr_data:
    hex   00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00   ; $00: color 0 only
    hex   ff ff ff ff ff ff ff ff   ff ff ff ff ff ff ff ff   ; $01: color 3 only
    hex   ff ff ff ff f0 f0 f3 f3   ff ff ff ff ff ff fc fc   ; $02: BG top left corner
    hex   ff ff ff ff 00 00 ff ff   ff ff ff ff ff ff 00 00   ; $03: BG top edge
    hex   ff ff ff ff 0f 0f cf cf   ff ff ff ff ff ff 3f 3f   ; $04: BG top right corner
    hex   f3 f3 f0 f0 ff ff ff ff   fc fc ff ff ff ff ff ff   ; $05: BG bottom left corner
    hex   ff ff 00 00 ff ff ff ff   00 00 ff ff ff ff ff ff   ; $06: BG bottom edge
    hex   cf cf 0f 0f ff ff ff ff   3f 3f ff ff ff ff ff ff   ; $07: BG bottom right corner
    hex   f3 f3 f3 f3 f3 f3 f3 f3   fc fc fc fc fc fc fc fc   ; $08: BG left edge
    hex   cf cf cf cf cf cf cf cf   3f 3f 3f 3f 3f 3f 3f 3f   ; $09: BG right edge
    hex   07 1f 38 70 63 c7 cf cf   00 00 07 0f 1f 3f 3f 3f   ; $0a: ball top left quarter
    hex   cf cf c7 63 70 38 1f 07   3f 3f 3f 1f 0f 07 00 00   ; $0b: ball bottom left quarter
    hex   00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00   ; $0c: unused
    hex   00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00   ; $0d: unused
    hex   00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00   ; $0e: unused
    hex   00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00   ; $0f: unused

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    .dw nmi, reset, $0000
