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
    bmi +
    jsr nmi_paint_mode
    jmp ++
+   jsr nmi_palette_edit_mode

    ; reset VRAM address & scroll
++  bit ppu_status
    lda #$00
    sta ppu_addr
    sta ppu_addr
    sta ppu_scroll
    sta ppu_scroll

    ; set flag
    sec
    ror nmi_done

    ; pull Y, X, A
    pla
    tay
    pla
    tax
    pla

    rti

; --- Paint mode -----------------------------------------------------------------------------------

nmi_paint_mode:
    ; update selected color to bottom bar (NT 0, row 28, column 8)
    bit ppu_status  ; reset ppu_addr latch
    lda #$23
    sta ppu_addr
    lda #$88
    sta ppu_addr
    ldx color
    lda solid_color_tiles, x
    sta ppu_data

    ; copy nt_buffer[nt_buffer_address] to [vram_address] if instructed by main loop
    bit do_paint
    bpl +
    jsr update_vram_byte
    lsr do_paint          ; clear flag

+   rts

update_vram_byte:
    ; Change one VRAM byte in the paint area.

    ; compute address within nt_buffer (nt_buffer + paint_area_offset -> pointer)
    clc
    lda paint_area_offset + 0
    sta pointer + 0
    lda paint_area_offset + 1
    adc #>nt_buffer
    sta pointer + 1

    ; compute PPU address ($2080 + paint_area_offset; low byte -> stack, high byte -> A)
    clc
    lda paint_area_offset + 0
    adc #$80
    pha
    lda paint_area_offset + 1
    adc #$20

    ; set PPU address
    bit ppu_status  ; reset latch
    sta ppu_addr
    pla
    sta ppu_addr

    ; write byte
    ldy #0
    lda (pointer), y
    sta ppu_data

    rts

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

