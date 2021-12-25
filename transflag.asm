; Transgender flag (NES, ASM6; tested on Mednafen & FCEUX)
; Note: this program is heavily optimized for size; it doesn't represent good programming practice.

; --- Constants -----------------------------------------------------------------------------------

; memory-mapped registers
ppuctrl     equ $2000
ppumask     equ $2001
ppustatus   equ $2002
ppuaddr     equ $2006
ppudata     equ $2007

; --- iNES header ---------------------------------------------------------------------------------

            ; see https://wiki.nesdev.org/w/index.php/INES
            base $0000
            db "NES", $1a            ; file id
            db 1, 0                  ; 16 KiB PRG ROM, 0 KiB CHR ROM (uses CHR RAM)
            db %00000001, %00000000  ; NROM mapper, vertical name table mirroring
            pad $0010, $00           ; unused


; --- Main program --------------------------------------------------------------------------------

            base $c000          ; end of CPU memory space
            pad $10000-97, $ff  ; note: set start address manually to as large as possible

reset       ; notes: A, X and Y aren't always zero after soft reset (at least in FCEUX);
            ; we use X as the "zero register" as much as possible

            ldx #%00000011
            stx ppuctrl     ; disable NMI (and show name table 3, which doesn't matter)

-           bit ppustatus  ; wait for start of VBlank three times; also clear X
            bpl -
            dex
            bne -

            stx ppuaddr  ; set up CHR RAM (VRAM $0000-$002f)
            stx ppuaddr  ; tile 0: color #0 only (16 * 0x00)
            txa          ; tile 1: color #2 only (8 * 0x00, 8 * 0xff)
            ldy #2       ; tile 2: color #3 only (16 * 0xff)
--          ldx #24      ; that is, write 24 * 0x00 and 24 * 0xff
-           sta ppudata
            dex
            bne -
            lda #$ff
            dey
            bne --

            lda #$3f       ; set up palette (VRAM $3f00-$3f03)
            sta ppuaddr
            stx ppuaddr
            ldy #3
-           lda palette,y
            sta ppudata
            dey
            bpl -

            lda #$20     ; set up name & attribute table 0
            sta ppuaddr  ; each stripe in name table is 6*32 = 192 bytes
            stx ppuaddr  ; the "6th stripe" actually clears attribute table 0 (and writes garbage
            ldy #5       ; to the start of name table 1, which is why we use vertical mirroring)
--          lda tiles,y
            ldx #(6*32)
-           sta ppudata
            dex
            bne -
            dey
            bpl --

            lda #%00001010  ; enable background rendering
            sta ppumask

irq         ; an infinite loop (see next byte)

tiles       hex 00  ; for clearing attribute table 0 / BRK opcode
            hex 01  ; blue
            hex 02  ; pink
            hex 00  ; white
            hex 02  ; pink
            hex 01  ; blue

            ; interrupt vectors and palette
            pad $10000-8, $ff  ; end of CPU memory space
palette     hex 25     ; pink
            hex 21     ; light blue
            hex 00     ; unused color / low  byte of unused NMI vector
            hex 30     ; white        / high byte of unused NMI vector
            dw reset   ; reset vector
            dw irq     ; IRQ vector
