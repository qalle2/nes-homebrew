; TODO: move stuff to main loop

nmi:
    ; push A, X, Y
    pha
    txa
    pha
    tya
    pha

    ; copy sprite data from RAM to PPU
    lda #>sprite_data
    sta oam_dma

    ; run one of two subs
    bit in_palette_editor
    bmi +                  ; branch if flag set
    jsr nmi_paint_mode
    jmp nmi_end
+   jsr nmi_palette_edit_mode

nmi_end:
    ; clear VRAM address & scroll
    lda #$00
    tax
    jsr set_vram_address
    sta ppu_scroll
    sta ppu_scroll

    sec
    ror nmi_done  ; set flag

    ; pull Y, X, A
    pla
    tay
    pla
    tax
    pla

    rti

; --- Paint mode -----------------------------------------------------------------------------------

nmi_paint_mode:
    ; update selected color to bottom bar (row 28, column 8)
    bit ppu_status  ; reset ppu_addr latch
    lda #$23
    sta ppu_addr
    lda #$88
    sta ppu_addr
    ldx color
    lda solid_color_tiles, x
    sta ppu_data

    ; paint if instructed by main loop
    bit do_paint
    bpl +
    jsr paint
    lsr do_paint  ; clear flag

+   rts

; --- Paint mode - subs/tables ---------------------------------------------------------------------

paint:
    ; Paint a "pixel" (a quarter tile) or 2*2 "pixels" (a tile) by changing one VRAM byte between
    ; $2080-$237f.
    ; In: vram_address, cursor_type, color.
    ; Writes VRAM.

    lda cursor_type
    beq +

    ; big (square) cursor
    ldx color
    lda solid_color_tiles, x
    jmp write_new_byte

    ; small (arrow) cursor
    ; position within tile (0-3) -> X
+   lda cursor_x
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
    bit ppu_status  ; reset ppu_addr latch
    lda vram_address + 0
    sta ppu_addr
    lda vram_address + 1
    sta ppu_addr
    lda ppu_data  ; garbage read
    lda ppu_data
    ; clear bits of this "pixel"
    and and_masks, x
    ; add new bits
    ora or_masks, y

write_new_byte:
    bit ppu_status  ; reset ppu_addr latch
    ldx vram_address + 0
    stx ppu_addr
    ldx vram_address + 1
    stx ppu_addr
    sta ppu_data

    rts

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

; --- Palette edit mode ----------------------------------------------------------------------------

nmi_palette_edit_mode:
    ldx palette_cursor  ; cursor position
    ldy #$3f            ; high byte of ppu_addr
    bit ppu_status      ; reset ppu_addr latch

    ; copy selected color to first background subpalette
    sty ppu_addr
    stx ppu_addr
    lda user_palette, x
    sta ppu_data

    ; copy selected color to third/fourth sprite subpalette
    sty ppu_addr
    lda selected_color_offsets, x
    sta ppu_addr
    lda user_palette, x
    sta ppu_data

    rts

selected_color_offsets:
    db (4 + 2) * 4 + 2
    db (4 + 2) * 4 + 3
    db (4 + 3) * 4 + 2
    db (4 + 3) * 4 + 3

