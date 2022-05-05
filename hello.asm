; Prints "Hello, World!" (NES, ASM6)

; --- Constants -----------------------------------------------------------------------------------

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_scroll      equ $2005
ppu_addr        equ $2006
ppu_data        equ $2007
dmc_freq        equ $4010
snd_chn         equ $4015
joypad2         equ $4017

; colors
bg_color        equ $34  ; background (pink)
fg_color        equ $02  ; foreground (blue)

; --- iNES header ---------------------------------------------------------------------------------

                base $0000               ; see https://wiki.nesdev.org/w/index.php/INES
                db "NES", $1a            ; file id
                db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
                db %00000000, %00000000  ; NROM mapper, horizontal name table mirroring
                pad $0010, $00           ; unused

; --- Main program --------------------------------------------------------------------------------

                base $c000              ; last 16 KiB of CPU memory space

reset           ; initialize the NES; see https://wiki.nesdev.org/w/index.php/Init_code
                sei                     ; ignore IRQs
                cld                     ; disable decimal mode
                ldx #%01000000
                stx joypad2             ; disable APU frame IRQ
                ldx #$ff
                txs                     ; initialize stack pointer
                inx
                stx ppu_ctrl            ; disable NMI
                stx ppu_mask            ; disable rendering
                stx dmc_freq            ; disable DMC IRQs
                stx snd_chn             ; disable sound channels

                jsr wait_vbl_start      ; wait for start of next VBlank
                jsr wait_vbl            ; wait for start of another VBlank

                ldx #$3f                ; set palette (do this while still in VBlank to avoid
                lda #$00                ; glitches)
                jsr set_ppu_addr
                lda #bg_color
                sta ppu_data
                lda #fg_color
                sta ppu_data

                ldx #$20                ; clear 1st Name Table and Attribute Table (4*256 bytes)
                lda #$00
                jsr set_ppu_addr
                ldy #4
                tax
-               sta ppu_data
                inx
                bne -
                dey
                bne -

                ldx #$20                ; copy text to 1st Name Table (3rd row, 2nd column)
                lda #$41                ; (X = source index, byte $80...$ff = terminator)
                jsr set_ppu_addr
                ldx #0
-               lda text,x
                bmi +
                sta ppu_data
                inx
                jmp -

+               jsr wait_vbl_start      ; to avoid glitches when enabling rendering

                lda #$00                ; reset PPU scroll
                sta ppu_scroll
                sta ppu_scroll
                sta ppu_ctrl            ; no NMI; use 1st Pattern & Name Table for background
                lda #%00001010          ; show background
                sta ppu_mask

-               jmp -                   ; infinite loop

; --- Subroutines and arrays ----------------------------------------------------------------------

                ; wait_vbl waits until we're in VBlank (which possibly ends very soon);
                ; wait_vbl_start waits until start of next VBlank instead;
                ; both subs also reset ppu_scroll/ppu_addr latch
wait_vbl_start  bit ppu_status          ; clear VBlank flag
wait_vbl        bit ppu_status          ; wait until PPU indicates we're in VBlank
                bpl wait_vbl
                rts

set_ppu_addr    stx ppu_addr            ; set PPU address from X and A
                sta ppu_addr
                rts

text            hex 01 04 05 05 06 08 00 02 06 07 05 03 09  ; "Hello, World!"
                hex 80                                      ; terminator ($80-$ff)

; --- Interrupt vectors ---------------------------------------------------------------------------

                pad $fffa, $ff          ; end of CPU memory space
                dw $ffff, reset, $ffff  ; NMI (unused), reset, IRQ (unused)

; --- CHR ROM -------------------------------------------------------------------------------------

                base $0000

                ; 16 bytes/tile (first 8 bytes for low bitplane, then high; byte = 8*1 pixels)
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
