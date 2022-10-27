; Transgender flag for the NES. Assembles with ASM6.
; Shows horizontal blue, pink, white, pink and blue stripes.
; Note: this program is heavily optimized for size; it doesn't represent good
; programming practice.
; Python 3 program to dump last X bytes of PRG ROM:
; f=open("transflag.nes","rb");f.seek(-X,2);f.read().hex();f.close()

; --- Constants ---------------------------------------------------------------

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_addr        equ $2006
ppu_data        equ $2007

; --- iNES header -------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 0                  ; 16 KiB PRG ROM, 8 KiB CHR RAM
                db %00000001, %00000000  ; NROM mapper, vertical NT mirroring
                pad $0010, $00           ; unused

; --- Start of PRG ROM --------------------------------------------------------

                base $c000

                ; end of CPU memory space; note: if the assembler prints an
                ; error message, adjust the address manually (see the end of
                ; the program)
                pad $10000-95, $ff

reset           ; notes:
                ; - A, X and Y aren't always zero after soft reset (at least
                ;   in FCEUX)
                ; - we use X as the "zero register" as much as possible

                ; disable NMI (and show name table 3, which doesn't matter)
                ldx #%00000011
                stx ppu_ctrl

                ; wait for start of VBlank three times; also clear X
-               bit ppu_status
                bpl -
                dex
                bne -

                ; set up CHR RAM (PPU $0000-$002f):
                ; - tile 0: color #0 only
                ; - tile 1: color #2 only
                ; - tile 2: color #3 only
                ; - that is, write 24 * $00 and 24 * $ff
                ;
                txa
                jsr set_ppu_addr        ; A*$100 + X -> PPU address
                ldy #2
--              ldx #24
-               sta ppu_data
                dex
                bne -
                lda #$ff
                dey
                bne --

                ; set up palette (PPU $3f00-$3f03)
                lda #$3f
                jsr set_ppu_addr        ; A*$100 + X -> PPU address
                ldy #3
-               lda palette,y
                sta ppu_data
                dey
                bpl -

                ; set up NT0 & AT0:
                ; - each stripe in NT is 6*32 = 192 bytes
                ; - the "6th stripe" actually clears AT0 (and writes garbage to
                ;   the start of NT1, which is why we use vertical NT
                ;   mirroring)
                ;
                lda #$20
                jsr set_ppu_addr        ; A*$100 + X -> PPU address
                ldy #5
--              lda stripes,y
                ldx #(6*32)
-               sta ppu_data
                dex
                bne -
                dey
                bpl --

                ; enable background rendering
                lda #%00001010
                sta ppu_mask

irq             ; an infinite loop (the next byte is also BRK)

stripes         ; NT & AT bytes (stored backwards)
                db 0                    ; AT; also BRK opcode
                db 1, 2, 0, 2, 1        ; NT

set_ppu_addr    ; A*$100 + X -> PPU address
                sta ppu_addr
                stx ppu_addr
                rts

; --- Palette and interrupt vectors -------------------------------------------

                ; note: for code golf reasons, we want the program to be
                ; contiguous and don't use "pad" here
                if $ < $10000-8
                    error "please increase 'pad' address at start of PRG ROM"
                elseif $ > $10000-8
                    error "please decrease 'pad' address at start of PRG ROM"
                endif

palette         ; palette (stored backwards) and NMI vector (unused)
                hex 25 21               ; pink, light blue
                hex 00                  ; unused color / low byte of NMI vector
                hex 30                  ; white / high byte of NMI vector

                dw reset, irq           ; reset/IRQ vector
