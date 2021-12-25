    ; the byte to fill unused parts with
    fillvalue $ff

    ; some PPU registers
    ppu_control equ $2000
    ppu_mask    equ $2001
    ppu_status  equ $2002
    ppu_scroll  equ $2005
    ppu_address equ $2006
    ppu_data    equ $2007

    ; colors
    bgcolor equ $34  ; pink
    fgcolor equ $02  ; blue

macro set_vram_address address
    ; Set the VRAM address.
    ; Clobbers A.
    lda #>(address)
    sta ppu_address
    if >(address) <> <(address)
        lda #<(address)
    endif
    sta ppu_address
endm

macro set_scroll_position horizontal, vertical
    ; Set the scroll position.
    ; Clobbers A.
    lda #(horizontal)
    sta ppu_scroll
    if (horizontal) <> (vertical)
        lda #(vertical)
    endif
    sta ppu_scroll
endm

; --------------------------------------------------------------------------------------------------
; Directives regarding the iNES header

    inesprg 1  ; PRG ROM size: 1 * 16 KiB
    ineschr 1  ; CHR ROM size: 1 * 8 KiB
    inesmir 0  ; name table mirroring: horizontal
    inesmap 0  ; mapper: 0 (NROM)

; --------------------------------------------------------------------------------------------------
; The main program

    org $c000  ; the last 16 KiB of CPU memory space

reset:
    ; initialize the NES
    sei              ; ignore IRQs
    cld              ; disable decimal mode
    ldx #%01000000
    stx $4017        ; disable APU frame IRQ
    ldx #$ff
    txs              ; initialize stack pointer
    inx              ; now X = 0
    stx ppu_control  ; disable NMI
    stx ppu_mask     ; disable rendering
    stx $4010        ; disable DMC IRQs

    ; wait for start of VBlank
    bit ppu_status  ; read to clear VBlank flag
-   bit ppu_status
    bpl -

    ; wait for start of VBlank again
-   bit ppu_status
    bpl -

    ; clear the first Name Table and Attribute Table (1024 = 4*256 bytes)
    set_vram_address $2000
    ldy #4
    tax
-   sta ppu_data
    inx
    bne -
    dey
    bne -

    ; copy the text from ROM to VRAM
    set_vram_address $2000 + 2 * $20 + 1  ; first Name Table, row 2, column 1
    ldx #0
-   lda text,x
    bmi +            ; exit if terminator ($80-$ff)
    sta ppu_data
    inx
    jmp -
+

    ; wait for start of VBlank, for the third time
    bit ppu_status
-   bit ppu_status
    bpl -

    ; set the palette
    set_vram_address $3f00
    lda #bgcolor     ; background color
    sta ppu_data
    lda #fgcolor     ; the first foreground color of the first subpalette
    sta ppu_data

    ; read ppu_status to reset the ppu_address/ppu_scroll latch
    bit ppu_status
    ; reset the VRAM address
    set_vram_address $0000
    set_scroll_position 0, 0

    ; enable background rendering
    lda #%00001010
    sta ppu_mask

    ; an infinite loop
-   jmp -

; --------------------------------------------------------------------------------------------------
; Data tables

text:
    ; tiles $00-$09 = " HWdelor,!"
    db $01, $04, $05, $05, $06, $08, $00  ; "Hello, "
    db $02, $06, $07, $05, $03, $09       ; "World!"
    ; value $80-$ff = terminator
    db $80

; --------------------------------------------------------------------------------------------------
; Interrupt vectors

    pad $10000 - 6  ; the last 6 bytes of the PRG ROM

    dw $ffff  ; NMI (unused)
    dw reset  ; reset
    dw $ffff  ; IRQ (unused)

; --------------------------------------------------------------------------------------------------
; CHR ROM

    base $0000

    hex   00 00 00 00 00 00 00 00   00 00 00 00 00 00 00 00   ; $00: " "
    hex   c6 c6 c6 fe c6 c6 c6 00   00 00 00 00 00 00 00 00   ; $01: "H"
    hex   c6 c6 c6 d6 d6 d6 6c 00   00 00 00 00 00 00 00 00   ; $02: "W"
    hex   06 06 06 7e c6 ce 76 00   00 00 00 00 00 00 00 00   ; $03: "d"
    hex   00 00 7c c6 fc c0 7e 00   00 00 00 00 00 00 00 00   ; $04: "e"
    hex   30 30 30 30 30 30 18 00   00 00 00 00 00 00 00 00   ; $05: "l"
    hex   00 00 7c c6 c6 c6 7c 00   00 00 00 00 00 00 00 00   ; $06: "o"
    hex   00 00 de e0 c0 c0 c0 00   00 00 00 00 00 00 00 00   ; $07: "r"
    hex   00 00 00 00 00 18 18 30   00 00 00 00 00 00 00 00   ; $08: ","
    hex   18 18 18 18 18 00 18 00   00 00 00 00 00 00 00 00   ; $09: "!"

    pad $2000
