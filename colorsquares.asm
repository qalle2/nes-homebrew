    ; idea: keep copy of NT&AT data in RAM, edit it, copy changed bytes to VRAM

    include "_common.asm"

; --- Constants ------------------------------------------------------------------------------------

    frame_counter        equ $00
    square_x             equ $01  ; 0-15
    square_y             equ $02  ; 0-14
    moving_square1_x     equ $03
    moving_square1_y     equ $04
    moving_square2_x     equ $05
    moving_square2_y     equ $06
    square_old_nt_value1 equ $07
    square_old_nt_value2 equ $08
    square_old_at_value1 equ $09
    square_old_at_value2 equ $0a
    temp                 equ $0b
    temp2                equ $0c
    nmi_done             equ $0d

; --- iNES header ----------------------------------------------------------------------------------

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 1  ; name table mirroring: vertical
    inesmap 0  ; mapper: NROM

; --------------------------------------------------------------------------------------------------

    org $c000
    include "colorsquares-init.asm"
    include "colorsquares-mainloop.asm"
    include "colorsquares-nmi.asm"

; --- General-purpose subroutines ------------------------------------------------------------------

set_ppu_address:
    ; A = high byte, X = low byte
    bit ppu_status  ; clear ppu_addr/ppu_scroll address latch
    sta ppu_addr
    stx ppu_addr
    rts

reset_ppu_address:
    ; reset PPU address
    lda #$00
    tax
    jsr set_ppu_address
    ; horizontal scroll: center
    sta ppu_scroll
    ; vertical scroll: center active area
    lda #(240 - 8)
    sta ppu_scroll
    rts

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $fffa
    dw nmi, reset, 0
