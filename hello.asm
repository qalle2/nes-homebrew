; An NES/Famicom program that prints "Hello, World!" in dark blue on light pink
; background.
; Tested with Nestopia, FCEUX and Mednafen.
; Assembles with ASM6.
;
; Note: The following ASM6-specific directives are used; if you're using
; another 6502 assembler, look up their equivalents in the manual:
;     - db X, Y, ...: output bytes X, Y, ...
;     - dw X, Y, ...: output 2-byte values X, Y, ...; low byte first
;     - X equ Y: assign value Y to constant X
;     - base X: set the address of the assembler's internal program counter
;       to X (do not output any bytes)
;     - pad X, Y: output byte Y until the assembler's internal program counter
;       reaches address X

; --- Constants ---------------------------------------------------------------

; NES memory-mapped registers
ppu_ctrl        equ $2000
ppu_mask        equ $2001
ppu_status      equ $2002
ppu_scroll      equ $2005
ppu_addr        equ $2006
ppu_data        equ $2007
dmc_freq        equ $4010
snd_chn         equ $4015
joypad2         equ $4017

; --- iNES header -------------------------------------------------------------

                ; see https://wiki.nesdev.org/w/index.php/INES
                ;
                base $0000
                db $4e, $45, $53, $1a    ; file id ("NES\x1a")
                db 1, 1                  ; 16 KiB PRG ROM, 8 KiB CHR ROM
                db %00000000, %00000000  ; NROM mapper, horizontal mirroring
                pad $0010, $00           ; unused

; --- Main program ------------------------------------------------------------

                base $c000             ; last 16 KiB of CPU memory space

reset           ; initialize the NES;
                ; see https://wiki.nesdev.org/w/index.php/Init_code
                ;
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
                jsr wait_vbl_start      ; wait for start of next VBlank

                ; set palette (do this while still in VBlank to avoid glitches)
                ;
                ldx #$3f
                lda #$00
                jsr set_ppu_addr        ; X * 256 + A -> PPU address
                ;
                lda #$34                ; background color (light pink)
                sta ppu_data
                lda #$02                ; text color (dark blue)
                sta ppu_data

                ; clear 1st Name Table and Attribute Table (4*256 bytes)
                ;
                ldx #$20
                lda #$00
                jsr set_ppu_addr        ; X * 256 + A -> PPU address
                ldy #4
                tax
                ;
clr_loop        sta ppu_data
                inx
                bne clr_loop
                dey
                bne clr_loop

                ; copy text to 1st Name Table (3rd row, 2nd column)
                ;
                ldx #$20
                lda #$41
                jsr set_ppu_addr        ; X * 256 + A -> PPU address
                ldx #0                  ; source index
                ;
copy_loop       lda text,x
                bmi exit_copy_loop      ; $80-$ff = terminator
                sta ppu_data
                inx
                jmp copy_loop

exit_copy_loop  jsr wait_vbl_start

                ; reset PPU scroll
                lda #$00
                sta ppu_scroll
                sta ppu_scroll

                ; disable NMI on VBlank; use 1st Pattern & Name Table for
                ; background
                lda #%00000000
                sta ppu_ctrl

                ; show background
                lda #%00001010
                sta ppu_mask

infinite_loop   jmp infinite_loop       ; an infinite loop

; --- Subroutines and arrays --------------------------------------------------

wait_vbl_start  ; wait until start of next VBlank
                ;
                ; clear VBlank flag (also resets the ppu_scroll/ppu_addr latch)
                bit ppu_status
                ; wait until in VBlank
vbl_wait_loop   bit ppu_status
                bpl vbl_wait_loop
                rts

set_ppu_addr    ; X * 256 + A -> PPU address
                stx ppu_addr
                sta ppu_addr
                rts

text            ; the text to print (tile indexes)
                db $01, $04, $05, $05, $06, $08, $00  ; "Hello, "
                db $02, $06, $07, $05, $03, $09       ; "World!"
                db $80                                ; terminator ($80-$ff)

; --- Interrupt vectors -------------------------------------------------------

                pad $fffa, $ff          ; end of CPU memory space
                dw $ffff, reset, $ffff  ; NMI (unused), reset, IRQ (unused)

; --- CHR ROM -----------------------------------------------------------------

                base $0000

                ; 1 byte encodes 8*1 pixels of one bitplane.
                ;
                ; tile $00 (" ")
                db $00, $00, $00, $00, $00, $00, $00, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $01 ("H")
                db $c6, $c6, $c6, $fe, $c6, $c6, $c6, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $02 ("W")
                db $c6, $c6, $c6, $d6, $d6, $d6, $6c, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $03 ("d")
                db $06, $06, $06, $7e, $c6, $ce, $76, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $04 ("e")
                db $00, $00, $7c, $c6, $fc, $c0, $7e, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $05 ("l")
                db $30, $30, $30, $30, $30, $30, $18, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $06 ("o")
                db $00, $00, $7c, $c6, $c6, $c6, $7c, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $07 ("r")
                db $00, $00, $de, $e0, $c0, $c0, $c0, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $08 (",")
                db $00, $00, $00, $00, $00, $18, $18, $30  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane
                ;
                ; tile $09 ("!")
                db $18, $18, $18, $18, $18, $00, $18, $00  ; low bitplane
                db $00, $00, $00, $00, $00, $00, $00, $00  ; high bitplane

                pad $2000, $ff
