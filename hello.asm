; Prints "Hello, World!" (NES, ASM6)

; --- Constants -----------------------------------------------------------------------------------

; memory-mapped registers
ppuctrl     equ $2000
ppumask     equ $2001
ppustatus   equ $2002
ppuscroll   equ $2005
ppuaddr     equ $2006
ppudata     equ $2007
dmcfreq     equ $4010
sndchn      equ $4015
joypad2     equ $4017

; colors
bgcolor     equ $34  ; background (pink)
fgcolor     equ $02  ; foreground (blue)

; --- iNES header ---------------------------------------------------------------------------------

            ; see https://wiki.nesdev.org/w/index.php/INES
            base $0000
            db "NES", $1a            ; file id
            db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
            db %00000000, %00000000  ; NROM mapper, horizontal name table mirroring
            pad $0010, $00           ; unused

; --- Main program --------------------------------------------------------------------------------

            base $c000  ; last 16 KiB of CPU memory space

reset       ; initialize the NES; see https://wiki.nesdev.org/w/index.php/Init_code
            sei             ; ignore IRQs
            cld             ; disable decimal mode
            ldx #%01000000
            stx joypad2     ; disable APU frame IRQ
            ldx #$ff
            txs             ; initialize stack pointer
            inx
            stx ppuctrl     ; disable NMI
            stx ppumask     ; disable rendering
            stx dmcfreq     ; disable DMC IRQs
            stx sndchn      ; disable sound channels

            bit ppustatus  ; wait until next VBlank starts
-           bit ppustatus
            bpl -
-           bit ppustatus  ; wait until next VBlank starts
            bpl -

            lda #$3f      ; set palette (VRAM $3f00-$3f01; do this while still in VBlank to avoid
            sta ppuaddr   ; glitches)
            lda #$00
            sta ppuaddr
            lda #bgcolor
            sta ppudata
            lda #fgcolor
            sta ppudata

            lda #$20     ; clear 1st Name Table and Attribute Table
            sta ppuaddr  ; (VRAM $2000-$23ff, 4*256 bytes)
            lda #$00
            sta ppuaddr
            ldy #4
            tax
-           sta ppudata
            inx
            bne -
            dey
            bne -

            lda #$20     ; copy text to 1st Name Table starting from 2nd column on 3rd row
            sta ppuaddr  ; (VRAM $2041)
            lda #$41
            sta ppuaddr
            ldx #0
-           lda text,x
            bmi +        ; exit if terminator ($80-$ff)
            sta ppudata
            inx
            jmp -

+           bit ppustatus  ; reset ppuaddr/ppuscroll latch
            lda #$00       ; reset VRAM address
            sta ppuaddr
            sta ppuaddr
            sta ppuscroll
            sta ppuscroll

            bit ppustatus  ; wait until next VBlank starts (to avoid glitches when enabling
-           bit ppustatus  ; background rendering)
            bpl -

            lda #%00001010  ; enable background rendering
            sta ppumask

-           jmp -  ; infinite loop

text        hex 01 04 05 05 06 08 00 02 06 07 05 03 09  ; "Hello, World!" (see CHR ROM)
            hex 80                                      ; terminator ($80-$ff)

; --- Interrupt vectors ---------------------------------------------------------------------------

            pad $10000-6, $ff       ; end of CPU memory space
            dw $ffff, reset, $ffff  ; NMI (unused), reset, IRQ (unused)

; --- CHR ROM -------------------------------------------------------------------------------------

            base $0000

            ; 16 bytes/tile; 8 bytes/bitplane (first low, then high); byte = 8*1 pixels
            hex  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  ; $00: " "
            hex  c6 c6 c6 fe c6 c6 c6 00  00 00 00 00 00 00 00 00  ; $01: "H"
            hex  c6 c6 c6 d6 d6 d6 6c 00  00 00 00 00 00 00 00 00  ; $02: "W"
            hex  06 06 06 7e c6 ce 76 00  00 00 00 00 00 00 00 00  ; $03: "d"
            hex  00 00 7c c6 fc c0 7e 00  00 00 00 00 00 00 00 00  ; $04: "e"
            hex  30 30 30 30 30 30 18 00  00 00 00 00 00 00 00 00  ; $05: "l"
            hex  00 00 7c c6 c6 c6 7c 00  00 00 00 00 00 00 00 00  ; $06: "o"
            hex  00 00 de e0 c0 c0 c0 00  00 00 00 00 00 00 00 00  ; $07: "r"
            hex  00 00 00 00 00 18 18 30  00 00 00 00 00 00 00 00  ; $08: ","
            hex  18 18 18 18 18 00 18 00  00 00 00 00 00 00 00 00  ; $09: "!"

            pad $2000, $ff
