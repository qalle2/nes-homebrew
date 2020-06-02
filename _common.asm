; Stuff used by many programs.

    ; value to fill unused areas with
    fillvalue $ff

; --- Constants ------------------------------------------------------------------------------------

; CPU memory space

ppu_ctrl   equ $2000
ppu_mask   equ $2001
ppu_status equ $2002
oam_addr   equ $2003
oam_data   equ $2004
ppu_scroll equ $2005
ppu_addr   equ $2006
ppu_data   equ $2007

dmc_freq equ $4010
oam_dma  equ $4014
snd_chn  equ $4015
joypad1  equ $4016
joypad2  equ $4017

; PPU memory space

ppu_name_table0      equ $2000
ppu_attribute_table0 equ $23c0
ppu_name_table1      equ $2400
ppu_attribute_table1 equ $27c0
ppu_name_table2      equ $2800
ppu_attribute_table2 equ $2bc0
ppu_name_table3      equ $2c00
ppu_attribute_table3 equ $2fc0

ppu_palette equ $3f00

; Colors

color_black equ $0f
color_white equ $30

; --- Macros ---------------------------------------------------------------------------------------

macro initialize_nes
    ; Initialize the NES.
    ; Do this at the start of the program.
    ; Afterwards, do a wait_vblank before doing any PPU operations. In between, you have about
    ; 30,000 cycles to do non-PPU-related stuff.
    ; See http://wiki.nesdev.com/w/index.php/Init_code

    sei              ; ignore IRQs
    cld              ; disable decimal mode
    ldx #$40
    stx joypad2      ; disable APU frame IRQ
    ldx #$ff
    txs              ; initialize stack pointer
    inx              ; now X = 0
    stx ppu_ctrl     ; disable NMI
    stx ppu_mask     ; disable rendering
    stx dmc_freq     ; disable DMC IRQs

    ; wait until we're at the start of VBlank
    bit ppu_status
-   bit ppu_status
    bpl -
endm

macro wait_vblank
    ; Wait until we're in VBlank.

-   bit ppu_status
    bpl -
endm

macro wait_vblank_start
    ; Wait until we're at the start of VBlank.

    bit ppu_status
-   bit ppu_status
    bpl -
endm

macro load_ax word
    ; Copy high byte of word into A and low byte into X.

    lda #>word
    if <word = >word
        tax
    else
        ldx #<word
    endif
endm

macro push_all
    ; Push A, X and Y.

    pha
    txa
    pha
    tya
    pha
endm

macro pull_all
    ; Pull (pop) Y, X and A.

    pla
    tay
    pla
    tax
    pla
endm
