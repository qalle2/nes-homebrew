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

sprite_page           equ $0000
timer                 equ $0200
nmi_done              equ $0201
loop_counter          equ $0202
sprite_palette_to_use equ $0203  ; 16 bytes

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
ppu_scroll equ $2005
ppu_addr   equ $2006
ppu_data   equ $2007
oam_dma    equ $4014

; PPU memory space

ppu_name_table0 equ $2000
ppu_palette     equ $3f00

; non-address constants

ball_count equ 24

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1
    ineschr 0
    inesmir 0
    inesmap 0

; --------------------------------------------------------------------------------------------------
; Initialization

    org $c000
reset:
    ; from NESDev wiki - Init code
    sei             ; ignore IRQs
    cld             ; disable decimal mode
    ldx #%01000000
    stx $4017       ; disable APU frame IRQ
    ldx #$ff
    txs             ; initialize stack pointer

    inx           ; X = 0
    stx ppu_ctrl  ; disable NMI
    stx ppu_mask  ; hide background&sprites
    stx $4010     ; disable DMC IRQs

    ; see NESDev wiki - PPU power up state - Best practice
    jsr wait_for_start_of_vblank

    stx timer     ; X is still 0
    stx nmi_done
    jsr copy_sprite_palette_from_rom_to_ram

    jsr wait_for_vblank

    ; set background palette
    lda #>ppu_palette
    ldx #$00
    jsr set_ppu_address
    ldx #(4 - 1)
-   lda background_palette, x
    sta ppu_data
    dex
    bpl -

    jsr copy_sprite_palette_from_ram_to_vram

    ; copy CHR data to CHR RAM (12 tiles)
    lda #$00
    tax
    jsr set_ppu_address
-   lda chr_data, x
    sta ppu_data
    inx
    cpx #(12 * 16)
    bne -

    ; prepare to write name table 0
    lda #>ppu_name_table0
    ldx #<ppu_name_table0
    jsr set_ppu_address

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

    ; reset VRAM address and scroll registers
    lda #$00
    tax
    jsr set_ppu_address
    jsr set_ppu_scroll

    jsr wait_for_start_of_vblank

    ; enable NMI, use 8*16-px sprites
    lda #%10100000
    sta ppu_ctrl

    ; show sprites and background
    lda #%00011110
    sta ppu_mask

; --------------------------------------------------------------------------------------------------
; Main loop

main_loop:
    ; wait until NMI routine has done its job
-   lda nmi_done
    beq -

    ; set up loop counter for moving balls horizontally
    ; (all balls on even frames, all except last 8 on odd frames)
    ldx #(ball_count - 1)
    lda timer
    and #%00000001
    beq +
    ldx #(ball_count - 8 - 1)
+   stx loop_counter

    ; move balls horizontally
horizontal_move_loop:
    ldx loop_counter
    ; direction address -> Y
    ldy horizontal_direction_addresses, x
    ; offset in sprite data -> X
    txa
    rept 3
        asl
    endr
    tax
    ; get current direction
    lda $00, y
    bpl move_right
    ; move left
    dec sprite_page + 3, x      ; move left half
    dec sprite_page + 4 + 3, x  ; move right half
    lda sprite_page + 3, x      ; check for collision
    cmp #8
    bne +
    lda #$00
    sta $00, y                  ; change direction
    jmp +
move_right:
    inc sprite_page + 3, x      ; move left half
    inc sprite_page + 4 + 3, x  ; move right half
    lda sprite_page + 3, x      ; check for collision
    cmp #(256 - 16 - 8)
    bne +
    lda #$ff
    sta $00, y                  ; change direction
    ; end of loop
+   dec loop_counter
    bpl horizontal_move_loop

    ; set up loop counter for moving balls vertically
    lda #(ball_count - 1)
    sta loop_counter

    ; move balls vertically (very similar to previous loop)
vertical_move_loop:
    ldx loop_counter
    ; direction address -> Y
    ldy vertical_direction_addresses, x
    ; offset in sprite data -> X
    txa
    rept 3
        asl
    endr
    tax
    ; get current direction
    lda $00, y
    bpl move_down
    ; move up
    dec sprite_page + 0, x      ; move left half
    dec sprite_page + 4 + 0, x  ; move right half
    lda sprite_page + 0, x      ; check for collision
    cmp #(16 - 1)
    bne +
    lda #$00
    sta $00, y                  ; change direction
    jmp +
move_down:
    inc sprite_page + 0, x      ; move left half
    inc sprite_page + 4 + 0, x  ; move right half
    lda sprite_page + 0, x      ; check for collision
    cmp #(240 - 16 - 16 - 1)
    bne +
    lda #$ff
    sta $00, y                  ; change direction
    ; end of loop
+   dec loop_counter
    bpl vertical_move_loop

    jsr copy_sprite_palette_from_rom_to_ram

    inc timer

    lda #0
    sta nmi_done

    jmp main_loop

; --------------------------------------------------------------------------------------------------
; Non-maskable interrupt routine

nmi:
    ; push A, X, Y
    pha
    txa
    pha
    tya
    pha

    ; do sprite DMA
    lda #>sprite_page
    sta oam_dma

    jsr copy_sprite_palette_from_ram_to_vram

    ; reset VRAM address and scroll registers
    lda #$00
    tax
    jsr set_ppu_address
    jsr set_ppu_scroll

    lda #1
    sta nmi_done

    ; pull Y, X, A
    pla
    tay
    pla
    tax
    pla
    rti

; --------------------------------------------------------------------------------------------------
; Subroutines

wait_for_start_of_vblank:
    ; clear VBlank flag
    bit ppu_status
wait_for_vblank:
    ; wait until VBlank flag is set
-   bit ppu_status
    bpl -
    rts

set_ppu_address:
    ; clear ppu_addr/ppu_scroll address latch; A/X = high/low byte
    bit ppu_status
    sta ppu_addr
    stx ppu_addr
    rts

set_ppu_scroll:
    ; A/X = horizontal/vertical scroll
    sta ppu_scroll
    stx ppu_scroll
    rts

fill_vram:
    ; print A X times (clobbers X)
-   sta ppu_data
    dex
    bne -
    rts

copy_sprite_palette_from_rom_to_ram:
    ; depending on timer, copy one of two sprite palettes backwards to RAM
    lda timer
    and #%00001000
    asl
    tax
    ldy #15
-   lda sprite_palettes, x
    sta sprite_palette_to_use, y
    inx
    dey
    bpl -
    rts

copy_sprite_palette_from_ram_to_vram:
    ; copy sprite palette backwards from RAM to VRAM
    lda #>(ppu_palette + 4 * 4)
    ldx #<(ppu_palette + 4 * 4)
    jsr set_ppu_address
    ldx #15
-   lda sprite_palette_to_use, x
    sta ppu_data
    dex
    bpl -
    rts

; --------------------------------------------------------------------------------------------------
; Tables

background_palette:
    ; black, dark gray, gray, light gray (backwards!)
    hex 30 10 00 0f

sprite_palettes:
    ; shades of blue, red, yellow and green (NOT backwards!)
    hex 0f 11 21 31
    hex 0f 14 24 34
    hex 0f 17 27 37
    hex 0f 1a 2a 3a
    ; slightly different shades of blue, red, yellow and green (NOT backwards!)
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

horizontal_direction_addresses:
    hex c1 c2 c3  c5 c6 c7  c9 ca cb  cd ce cf
    hex d1 d2 d3  d5 d6 d7  d9 da db  dd de df
vertical_direction_addresses:
    hex e1 e2 e3  e5 e6 e7  e9 ea eb  ed ee ef
    hex f1 f2 f3  f5 f6 f7  f9 fa fb  fd fe ff

; CHR data
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

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    .dw nmi, reset, $ffff
