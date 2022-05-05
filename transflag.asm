; Transgender flag (NES, ASM6; tested on Mednafen & FCEUX)
; Note: this program is heavily optimized for size; it doesn't represent good programming practice.
; Python 3 program to dump last X bytes of PRG ROM:
; f=open("transflag.nes","rb");f.seek(-X,2);f.read().hex();f.close()

; --- Constants -----------------------------------------------------------------------------------

; memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_addr        equ $2006
ppu_data        equ $2007

; --- iNES header ---------------------------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                base $0000
                db "NES", $1a            ; file id
                db 1, 0                  ; 16 KiB PRG ROM, 0 KiB CHR ROM (uses CHR RAM)
                db %00000001, %00000000  ; NROM mapper, vertical name table mirroring
                pad $0010, $00           ; unused

; --- Start of PRG ROM ----------------------------------------------------------------------------

                base $c000              ; end of CPU memory space; note: if necessary, set pad
                pad $10000-95, $ff      ; address manually according to assembler's error message

reset           ; notes: A, X and Y aren't always zero after soft reset (at least in FCEUX);
                ; we use X as the "zero register" as much as possible

                ldx #%00000011
                stx ppu_ctrl            ; disable NMI (and show name table 3, which doesn't matter)

-               bit ppu_status          ; wait for start of VBlank three times; also clear X
                bpl -
                dex
                bne -

                txa                     ; set up CHR RAM (VRAM $0000-$002f)
                jsr set_ppu_addr        ; tile 0: color #0 only (16 * $00)
                ldy #2                  ; tile 1: color #2 only (8 * $00, 8 * $ff)
--              ldx #24                 ; tile 2: color #3 only (16 * $ff)
-               sta ppu_data            ; that is, write 24 * $00 and 24 * $ff
                dex
                bne -
                lda #$ff
                dey
                bne --

                lda #$3f                ; set up palette (VRAM $3f00-$3f03)
                jsr set_ppu_addr
                ldy #3
-               lda palette,y
                sta ppu_data
                dey
                bpl -

                lda #$20                ; set up name & attribute table 0
                jsr set_ppu_addr        ; each stripe in name table is 6*32 = 192 bytes
                ldy #5                  ; "6th stripe" actually clears attribute table 0 (and
--              lda stripes,y           ; writes garbage to start of name table 1, which is why
                ldx #(6*32)             ; we use vertical mirroring)
-               sta ppu_data
                dex
                bne -
                dey
                bpl --

                lda #%00001010          ; enable background rendering
                sta ppu_mask

irq             ; an infinite loop (next byte is also BRK)

stripes         hex 00  ; for clearing attribute table 0; also BRK opcode
                hex 01  ; blue
                hex 02  ; pink
                hex 00  ; white
                hex 02  ; pink
                hex 01  ; blue

set_ppu_addr    sta ppu_addr
                stx ppu_addr
                rts

; --- Palette and interrupt vectors ---------------------------------------------------------------

                ; note: for code golf reasons, we want the program to be contiguous and don't use
                ; "pad" here
                if $ < $10000-8
                    error "please increase 'pad' address at start of PRG ROM"
                elseif $ > $10000-8
                    error "please decrease 'pad' address at start of PRG ROM"
                endif

palette         hex 25     ; pink
                hex 21     ; light blue
                hex 00     ; unused color / low  byte of unused NMI vector
                hex 30     ; white        / high byte of unused NMI vector
                dw reset   ; reset vector
                dw irq     ; IRQ vector
