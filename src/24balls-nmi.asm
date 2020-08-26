; 24 Balls - NMI routine

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

    jsr sprite_palette_ram_to_vram
    jsr reset_ppu_address_and_scroll

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

