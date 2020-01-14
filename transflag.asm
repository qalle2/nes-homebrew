    ; http://wiki.nesdev.com/w/index.php/CPU_power_up_state

    ; the byte to fill unused parts with
    fillvalue $ff

    ; some PPU registers
    ppu_control equ $2000
    ppu_mask    equ $2001
    ppu_status  equ $2002
    ppu_address equ $2006
    ppu_data    equ $2007

; --------------------------------------------------------------------------------------------------
; iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 0  ; CHR ROM size: 0 * 8 KiB (uses CHR RAM)
    inesmir 1  ; name table mirroring: vertical
    inesmap 0  ; mapper: 0 (NROM)

; --------------------------------------------------------------------------------------------------
; The main program

    org $c000
    pad $10000 - 92

reset:
    ; note: A, X and Y are 0 at power-up;
    ; we use X as the "zero register" as much as possible

    stx ppu_control  ; disable NMI

    ; wait for start of VBlank twice
-   bit ppu_status
    bpl -
-   bit ppu_status
    bpl -

    ; set up CHR RAM (VRAM $0000-$002f)
    ; tile 0: color 0 only
    ; tile 1: color 2 only
    ; tile 2: color 3 only
    ; it doesn't seem necessary to set the VRAM address
    ldy #2
write_bitplanes:
    ldx #24
-   sta ppu_data
    dex
    bne -
    lda #$ff
    dey
    bne write_bitplanes

    ; set up palette (VRAM $3f00-$3f02)
    lda #$3f
    sta ppu_address
    stx ppu_address
    ldy #3
-   lda palette, y
    sta ppu_data
    dey
    bpl -

    ; set up name table 0 and attribute table 0;
    ; each stripe in name table 0 is 32 * 6 = 192 bytes;
    ; the "6th stripe" clears attribute table 0 (and writes garbage at the start of name table 1,
    ; which is why we need to use vertical mirroring)
    lda #$20
    sta ppu_address
    stx ppu_address
    ldy #5
write_stripe:
    lda stripe_bytes, y
    ldx #192
-   sta ppu_data
    dex
    bne -
    dey
    bpl write_stripe

    ; enable background rendering
    lda #$0a
    sta ppu_mask

    ; an infinite loop
-   bne -

; --------------------------------------------------------------------------------------------------
; Data

stripe_bytes:
    ; read backwards
    db $00  ; for clearing attribute table 0
    db $01  ; blue
    db $02  ; pink
    db $00  ; white
    db $02  ; pink
    db $01  ; blue

; --------------------------------------------------------------------------------------------------
; Interrupt vectors & palette

    pad $fff8  ; the last 8 bytes of the PRG ROM
palette:       ; read backwards
    db $25     ; pink
    db $21     ; light blue
    db $00     ; unused (also LSB of unused NMI vector)
    db $30     ; white (also MSB of unused NMI vector)
    dw reset   ; reset vector
    dw $ffff   ; IRQ vector (unused)
